// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AVFoundation
import CryptoKit
import Foundation
import os

/// The remote engines' secrets: the Studio's token and the API key, in an
/// owner-only file of the app's container, like the meeting exporters' (no
/// Keychain prompt after each update). Never in the preferences, the
/// settings backup or a log.
enum ForkTranscribeSecrets {
    static let studioAccount = "studio.token"
    static let openAIAccount = "openai.key"

    private static let store = ForkMeetingKeychain(
        service: (Bundle.main.bundleIdentifier ?? "swishsaint") + ".transcribe",
        file: PrivateFileStore.containerURL?.appendingPathComponent("TranscribeSecrets.json"))

    static func read(_ account: String) -> String? {
        guard case let .found(data) = store.read(account) else { return nil }
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    static func exists(_ account: String) -> Bool { store.exists(account) }

    @discardableResult
    static func save(_ secret: String, account: String) -> Bool {
        let text = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && store.save(Data(text.utf8), account: account)
    }

    static func delete(_ account: String) { _ = store.delete(account) }

    /// The token the `transcrire` tool keeps in the login Keychain (service
    /// "opah-transcripteur"), read by `security`, which made that item and
    /// so reads it without a prompt. Nil when there is none.
    static func transcrireToken() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "opah-transcripteur", "-a", "studio-m2", "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }
}

/// One HTTP exchange on the work queue: blocking, cancelled at the job's
/// stop within a quarter of a second, the bytes sent reported on the way.
enum ForkTranscribeHTTP {
    struct Response {
        var status: Int
        var data: Data
        /// Seconds the server asked to wait (`Retry-After`).
        var retryAfter: TimeInterval?
    }

    private final class Box: @unchecked Sendable {
        var data: Data?
        var response: URLResponse?
        var error: Error?
    }

    /// Throws `CancellationError` at the stop, `ForkTranscribeFailure.network`
    /// when the server cannot be reached.
    static func send(_ request: URLRequest, file: URL? = nil, stop: ForkMeetingTranscriptStop,
                     timeout: TimeInterval = 120, sent: (Double) -> Void = { _ in }) throws -> Response {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = 6 * 3600
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        let handler: @Sendable (Data?, URLResponse?, Error?) -> Void = { data, response, error in
            box.data = data
            box.response = response
            box.error = error
            done.signal()
        }
        let task = file.map { session.uploadTask(with: request, fromFile: $0, completionHandler: handler) }
            ?? session.dataTask(with: request, completionHandler: handler)
        task.resume()
        var lastSent = -1.0
        while done.wait(timeout: .now() + 0.25) == .timedOut {
            if stop.isCancelled {
                task.cancel()
                done.wait()
                throw CancellationError()
            }
            if file != nil, task.countOfBytesExpectedToSend > 0 {
                let fraction = Double(task.countOfBytesSent) / Double(task.countOfBytesExpectedToSend)
                if fraction - lastSent >= 0.005 {
                    lastSent = fraction
                    sent(min(1, fraction))
                }
            }
        }
        if stop.isCancelled { throw CancellationError() }
        guard box.error == nil, let http = box.response as? HTTPURLResponse else {
            throw ForkTranscribeFailure.network
        }
        let retry = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
        return Response(status: http.statusCode, data: box.data ?? Data(), retryAfter: retry)
    }

    /// Waits `seconds` unless the job is stopped first.
    static func pause(_ seconds: TimeInterval, stop: ForkMeetingTranscriptStop) throws {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if stop.isCancelled { throw CancellationError() }
            Thread.sleep(forTimeInterval: min(0.25, end.timeIntervalSinceNow))
        }
        if stop.isCancelled { throw CancellationError() }
    }
}

/// The sound of a file made light to send: decoded as Parakeet reads it
/// (every track mixed, Ogg read whole), then AAC at 16 kHz mono and
/// 32 kbit/s, 14.4 MB an hour, in pieces when a server limits each request.
enum ForkTranscribeLighten {
    struct Piece {
        var url: URL
        var start: TimeInterval
        var length: TimeInterval
    }

    /// Work queue only. `pieceSeconds` nil gives one file.
    static func pieces(of url: URL, into folder: URL, pieceSeconds: TimeInterval?, stop: ForkMeetingTranscriptStop,
                       progress: (Double) -> Void) throws -> (pieces: [Piece], duration: TimeInterval) {
        let (source, duration) = try ForkTranscribeAudio.open(url)
        let rate = Double(ForkParakeetShape.sampleRate)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)
        else { throw ForkTranscribeFailure.engine }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate,
                                       AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: ForkTranscribeUpload.bitRate]
        let pieceSamples = pieceSeconds.map { Int($0 * rate) } ?? Int.max
        var pieces: [Piece] = []
        var writer: AVAudioFile?
        var inPiece = 0
        var total = 0
        let chunk = Int(rate)
        var samples = [Float](repeating: 0, count: chunk)
        func open() throws {
            let destination = folder.appendingPathComponent("piece-\(pieces.count + 1).m4a")
            writer = try AVAudioFile(forWriting: destination, settings: settings, commonFormat: .pcmFormatFloat32,
                                     interleaved: false)
            pieces.append(Piece(url: destination, start: Double(total) / rate, length: 0))
            inPiece = 0
        }
        do {
            try open()
            while true {
                if stop.isCancelled { throw CancellationError() }
                let wanted = min(chunk, pieceSamples - inPiece)
                let count = try samples.withUnsafeMutableBufferPointer { buffer in
                    try source.read(into: UnsafeMutableBufferPointer(rebasing: buffer[0..<wanted]))
                }
                guard count > 0 else { break }
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
                      let channel = buffer.floatChannelData?[0] else { throw ForkTranscribeFailure.engine }
                samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: count) }
                buffer.frameLength = AVAudioFrameCount(count)
                try writer?.write(from: buffer)
                inPiece += count
                total += count
                pieces[pieces.count - 1].length = Double(inPiece) / rate
                if duration > 0 { progress(min(1, Double(total) / rate / duration)) }
                if inPiece >= pieceSamples {
                    writer = nil
                    try open()
                }
            }
        } catch let failure as ForkTranscribeFailure {
            throw failure
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ForkTranscribeFailure.unreadable
        }
        writer = nil
        // The last piece opened after the sound ended holds nothing.
        if let last = pieces.last, last.length == 0, pieces.count > 1 {
            try? FileManager.default.removeItem(at: last.url)
            pieces.removeLast()
        }
        guard total > 0 else { throw ForkTranscribeFailure.noAudio }
        return (pieces, max(duration, Double(total) / rate))
    }

    /// The sound's length without decoding it, or nil.
    static func duration(of url: URL) -> TimeInterval? {
        (try? ForkTranscribeAudio.open(url))?.1
    }
}

/// What a remote engine reports on the way, for the job's line.
typealias ForkTranscribeReport = (ForkTranscribeStage, Double?) -> Void

/// The Studio's transcriber: wake it, send the file (lightened when it is a
/// video, lossless or big), follow the job, take back the passages and the
/// voices. Its id is kept as soon as the Studio gives it, so a relaunch
/// follows the same job instead of sending the file twice.
struct ForkTranscribeStudioEngine {
    var base: URL
    var token: String
    private let log = Logger(subsystem: "fork.transcribe", category: "studio")

    init(base: URL, token: String) {
        self.base = base
        self.token = token
    }

    private func request(_ path: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: URL(string: path, relativeTo: base)?.absoluteURL ?? base)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// The transcriber is ready, waking, or why not.
    func health(stop: ForkMeetingTranscriptStop) throws -> ForkTranscribeStudioAPI.State {
        let answer = try ForkTranscribeHTTP.send(request("/v1/sante"), stop: stop, timeout: 20)
        guard answer.status == 200 else {
            throw ForkTranscribeStudioAPI.failure(status: answer.status,
                                                  code: ForkTranscribeStudioAPI.answer(answer.data)?.code)
        }
        return ForkTranscribeStudioAPI.state(answer.data)
    }

    func transcribe(_ job: ForkTranscribeJob, language: ForkTranscribeLanguage, speakers: Int?, vocabulary: [String],
                    work: URL, stop: ForkMeetingTranscriptStop, report: ForkTranscribeReport,
                    remember: (String?) -> Void) throws -> ForkTranscribeDocument {
        try wake(stop: stop, report: report)
        let duration = ForkTranscribeLighten.duration(of: job.source) ?? 0
        if duration > ForkTranscribeStudioAPI.longest { throw ForkTranscribeFailure.tooLong }
        if let id = job.remoteID {
            do {
                return try follow(id, duration: duration, stop: stop, report: report)
            } catch StudioGone.gone {
                log.notice("the Studio no longer has the job: sent again")
                remember(nil)
            }
        }
        let file = try prepare(job.source, work: work, stop: stop, report: report)
        let key = try Self.key(file, language: language, speakers: speakers, vocabulary: vocabulary)
        let path = ForkTranscribeStudioAPI.submitPath(name: job.name, language: language, key: key, speakers: speakers,
                                                      vocabulary: vocabulary)
        let id = try submit(file, path: path, stop: stop, report: report)
        remember(id)
        do {
            return try follow(id, duration: duration, stop: stop, report: report)
        } catch StudioGone.gone {
            throw ForkTranscribeFailure.remoteFailed
        }
    }

    private enum StudioGone: Error { case gone }

    private func wake(stop: ForkMeetingTranscriptStop, report: ForkTranscribeReport) throws {
        let started = Date()
        while true {
            switch try health(stop: stop) {
            case .ready, .unknown: return
            case .stopping: throw ForkTranscribeFailure.serverBusy
            case .waking:
                report(.waking, nil)
                guard Date().timeIntervalSince(started) < ForkTranscribeStudioAPI.wakeLimit else {
                    throw ForkTranscribeFailure.serverBusy
                }
                try ForkTranscribeHTTP.pause(4, stop: stop)
            }
        }
    }

    /// The file as it is, or its sound made light.
    private func prepare(_ source: URL, work: URL, stop: ForkMeetingTranscriptStop,
                         report: ForkTranscribeReport) throws -> URL {
        let bytes = Int64((try? source.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        if ForkTranscribeUpload.sendsAsIs(extension: source.pathExtension, bytes: bytes,
                                          limit: ForkTranscribeStudioAPI.byteLimit,
                                          accepted: ForkTranscribeStudioAPI.accepted) {
            return source
        }
        report(.preparing, 0)
        do {
            let light = try ForkTranscribeLighten.pieces(of: source, into: work, pieceSeconds: nil, stop: stop) {
                report(.preparing, $0)
            }
            guard let piece = light.pieces.first else { throw ForkTranscribeFailure.noAudio }
            return piece.url
        } catch ForkTranscribeFailure.unreadable where bytes <= ForkTranscribeStudioAPI.byteLimit {
            // This Mac cannot read it (webm, mkv…): the Studio's ffmpeg may.
            return source
        }
    }

    private func submit(_ file: URL, path: String, stop: ForkMeetingTranscriptStop,
                        report: ForkTranscribeReport) throws -> String {
        var request = request(path, method: "POST")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let started = Date()
        var networkTries = 0
        while true {
            report(.uploading, 0)
            let answer: ForkTranscribeHTTP.Response
            do {
                answer = try ForkTranscribeHTTP.send(request, file: file, stop: stop, timeout: 600) { report(.uploading, $0) }
            } catch ForkTranscribeFailure.network where networkTries < 2 {
                networkTries += 1
                try ForkTranscribeHTTP.pause(5, stop: stop)
                continue
            }
            let body = ForkTranscribeStudioAPI.answer(answer.data)
            if answer.status == 202, let id = body?.travail { return id }
            let failure = ForkTranscribeStudioAPI.failure(status: answer.status, code: body?.code)
            guard failure == .serverBusy || body?.reessayable == true,
                  Date().timeIntervalSince(started) < ForkTranscribeStudioAPI.busyLimit
            else { throw failure }
            report(.waitingForServer, nil)
            try ForkTranscribeHTTP.pause(min(120, max(5, answer.retryAfter ?? 15)), stop: stop)
        }
    }

    private func follow(_ id: String, duration: TimeInterval, stop: ForkMeetingTranscriptStop,
                        report: ForkTranscribeReport) throws -> ForkTranscribeDocument {
        var misses = 0
        while true {
            let answer: ForkTranscribeHTTP.Response
            do {
                answer = try ForkTranscribeHTTP.send(request("/v1/travaux/\(id)"), stop: stop, timeout: 60)
            } catch is CancellationError {
                cancel(id)
                throw CancellationError()
            } catch ForkTranscribeFailure.network where misses < 20 {
                // A Wi-Fi that drops for a minute does not lose the job.
                misses += 1
                try pauseOrCancel(5, id: id, stop: stop)
                continue
            }
            misses = 0
            if answer.status != 200 {
                let code = ForkTranscribeStudioAPI.answer(answer.data)?.code
                if ForkTranscribeStudioAPI.isGone(code) || answer.status == 404 { throw StudioGone.gone }
                throw ForkTranscribeStudioAPI.failure(status: answer.status, code: code)
            }
            switch ForkTranscribeStudioAPI.job(answer.data, duration: duration) {
            case .queued?: report(.remoteQueued, nil)
            case let .running(progress)?: report(.transcribing, progress)
            case let .done(document)?: return document
            case let .failed(failure)?: throw failure
            case nil: throw ForkTranscribeFailure.remoteFailed
            }
            try pauseOrCancel(3, id: id, stop: stop)
        }
    }

    private func pauseOrCancel(_ seconds: TimeInterval, id: String, stop: ForkMeetingTranscriptStop) throws {
        do {
            try ForkTranscribeHTTP.pause(seconds, stop: stop)
        } catch {
            cancel(id)
            throw error
        }
    }

    /// Best effort: the Studio stops working for nothing.
    private func cancel(_ id: String) {
        _ = try? ForkTranscribeHTTP.send(request("/v1/travaux/\(id)", method: "DELETE"),
                                         stop: ForkMeetingTranscriptStop(), timeout: 10)
    }

    /// The file and the options, hashed as the `transcrire` tool does: the
    /// same drop sent twice is the same job for the Studio.
    static func key(_ file: URL, language: ForkTranscribeLanguage, speakers: Int?, vocabulary: [String]) throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: file) else { throw ForkTranscribeFailure.fileMissing }
        defer { try? handle.close() }
        var hash = SHA256()
        while let block = try? handle.read(upToCount: 1 << 20), !block.isEmpty { hash.update(data: block) }
        let options = "{\"langue\":\"\(language.rawValue)\",\"vocab\":\(vocabulary),\"voix\":\(speakers.map(String.init) ?? "null")}"
        hash.update(data: Data(options.utf8))
        return hash.finalize().map { String(format: "%02x", $0) }.joined().prefix(32).description
    }
}

/// Any OpenAI-compatible `audio/transcriptions`: the file (or its sound made
/// light, in pieces of 24 MB at most), one request each, the passages put
/// back on the file's own clock.
struct ForkTranscribeOpenAIEngine {
    var base: String
    var model: String
    var key: String?

    func transcribe(_ job: ForkTranscribeJob, language: ForkTranscribeLanguage, vocabulary: [String], work: URL,
                    stop: ForkMeetingTranscriptStop, report: ForkTranscribeReport) throws -> ForkTranscribeDocument {
        guard let endpoint = ForkTranscribeOpenAIAPI.endpoint(base), !model.isEmpty else {
            throw ForkTranscribeFailure.notConfigured
        }
        if key == nil, endpoint.host?.hasSuffix("openai.com") == true { throw ForkTranscribeFailure.notConfigured }
        let bytes = Int64((try? job.source.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        var pieces: [ForkTranscribeLighten.Piece]
        var duration = ForkTranscribeLighten.duration(of: job.source) ?? 0
        if ForkTranscribeUpload.sendsAsIs(extension: job.source.pathExtension, bytes: bytes,
                                          limit: ForkTranscribeOpenAIAPI.byteLimit, accepted: ForkTranscribeOpenAIAPI.accepted) {
            pieces = [.init(url: job.source, start: 0, length: duration)]
        } else {
            report(.preparing, 0)
            let plan = ForkTranscribeUpload.pieces(duration: duration, limit: ForkTranscribeOpenAIAPI.byteLimit)
            let light = try ForkTranscribeLighten.pieces(of: job.source, into: work,
                                                         pieceSeconds: plan.count > 1 ? plan[0].length : nil, stop: stop) {
                report(.preparing, $0)
            }
            pieces = light.pieces
            duration = light.duration
        }
        var segments: [ForkTranscribeDocument.Segment] = []
        var heard: String?
        for (index, piece) in pieces.enumerated() {
            let share = (Double(index), Double(pieces.count))
            let result = try send(piece, to: endpoint, language: language, vocabulary: vocabulary, work: work, stop: stop) {
                report(.uploading, ($0 + share.0) / share.1)
            } waiting: {
                report($0, nil)
            }
            segments += result.segments
            heard = heard ?? result.language
        }
        return ForkTranscribeDocument(segments: segments, duration: max(duration, segments.last?.end ?? 0), language: heard)
    }

    private func send(_ piece: ForkTranscribeLighten.Piece, to endpoint: URL, language: ForkTranscribeLanguage,
                      vocabulary: [String], work: URL, stop: ForkMeetingTranscriptStop, sent: (Double) -> Void,
                      waiting: (ForkTranscribeStage) -> Void)
        throws -> (segments: [ForkTranscribeDocument.Segment], language: String?) {
        var verbose = true
        let started = Date()
        var networkTries = 0
        while true {
            var fields: [(String, String)] = [("model", model)]
            if verbose {
                fields += [("response_format", "verbose_json"), ("timestamp_granularities[]", "segment")]
            } else {
                fields.append(("response_format", "json"))
            }
            if let code = language.code { fields.append(("language", code)) }
            if let prompt = ForkTranscribeOpenAIAPI.prompt(vocabulary) { fields.append(("prompt", prompt)) }
            let boundary = "swishsaint-\(UUID().uuidString)"
            let body = work.appendingPathComponent("request-\(UUID().uuidString).multipart")
            defer { try? FileManager.default.removeItem(at: body) }
            let parts = ForkTranscribeOpenAIAPI.multipart(boundary: boundary, fields: fields,
                                                          fileName: piece.url.lastPathComponent,
                                                          mime: ForkTranscribeOpenAIAPI.mime(piece.url.pathExtension))
            try Self.write(body, head: parts.head, file: piece.url, tail: parts.tail)
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
            let answer: ForkTranscribeHTTP.Response
            do {
                answer = try ForkTranscribeHTTP.send(request, file: body, stop: stop, timeout: 900) { fraction in
                    sent(fraction)
                    if fraction >= 1 { waiting(.transcribing) }
                }
            } catch ForkTranscribeFailure.network where networkTries < 2 {
                networkTries += 1
                try ForkTranscribeHTTP.pause(5, stop: stop)
                continue
            }
            if answer.status == 200 {
                guard let result = ForkTranscribeOpenAIAPI.segments(answer.data, offset: piece.start, length: piece.length)
                else { throw ForkTranscribeFailure.remoteFailed }
                return result
            }
            if verbose, ForkTranscribeOpenAIAPI.refusesVerbose(status: answer.status, body: answer.data) {
                verbose = false
                continue
            }
            let failure = ForkTranscribeOpenAIAPI.failure(status: answer.status)
            guard failure == .serverBusy, Date().timeIntervalSince(started) < ForkTranscribeStudioAPI.busyLimit else {
                throw failure
            }
            waiting(.waitingForServer)
            try ForkTranscribeHTTP.pause(min(120, max(5, answer.retryAfter ?? 20)), stop: stop)
        }
    }

    /// The multipart body as a file: the head, the file's bytes, the tail.
    private static func write(_ body: URL, head: Data, file: URL, tail: Data) throws {
        guard FileManager.default.createFile(atPath: body.path, contents: head),
              let output = try? FileHandle(forWritingTo: body),
              let input = try? FileHandle(forReadingFrom: file)
        else { throw ForkTranscribeFailure.fileMissing }
        defer {
            try? output.close()
            try? input.close()
        }
        try output.seekToEnd()
        while let block = try input.read(upToCount: 1 << 20), !block.isEmpty { try output.write(contentsOf: block) }
        try output.write(contentsOf: tail)
    }

    /// The key (if any) works: `GET …/models`.
    func check(stop: ForkMeetingTranscriptStop) throws {
        guard let url = ForkTranscribeOpenAIAPI.endpoint(base, path: "models") else { throw ForkTranscribeFailure.notConfigured }
        var request = URLRequest(url: url)
        if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        let answer = try ForkTranscribeHTTP.send(request, stop: stop, timeout: 20)
        guard answer.status == 200 else { throw ForkTranscribeOpenAIAPI.failure(status: answer.status) }
    }
}
