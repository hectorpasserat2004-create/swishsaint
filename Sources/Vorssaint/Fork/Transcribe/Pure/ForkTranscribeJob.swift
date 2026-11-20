// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Who turns the file's sound into text. Written in the history: names never
/// change, new ones are only ever added.
enum ForkTranscribeEngine: String, Codable, CaseIterable {
    /// Parakeet on this Mac: nothing leaves it.
    case local
    /// The Studio's transcriber (Whisper, and who speaks), on the tailnet.
    case studio
    /// Any service with OpenAI's `audio/transcriptions` (OpenAI, Groq, a
    /// Whisper server of one's own).
    case openAI

    static let fallback: ForkTranscribeEngine = .local

    init(stored: String?) {
        self = ForkTranscribeEngine(rawValue: stored ?? "") ?? .fallback
    }
}

/// The language asked for. `auto` lets the engine find it, which keeps the
/// English of a mixed French meeting (forcing "fr" took Parakeet from 6 to
/// 23 % of errors on English, spike S6).
enum ForkTranscribeLanguage: String, Codable, CaseIterable {
    case auto
    case fr
    case en

    init(stored: String?) {
        self = ForkTranscribeLanguage(rawValue: stored ?? "") ?? .auto
    }

    /// What the engine is given: nil lets it decide.
    var code: String? { self == .auto ? nil : rawValue }
}

/// Why a file was not transcribed. Written in the history: names never
/// change, new ones are only ever added; one this version does not know is
/// read as `engine`.
enum ForkTranscribeFailure: String, Codable, Equatable, CaseIterable, Error {
    /// Moved, renamed or deleted since it was dropped, or its disk is gone.
    case fileMissing
    /// In iCloud and not on this Mac yet: its download was asked for.
    case notDownloaded
    /// A format this Mac cannot decode (webm, mkv…).
    case unreadable
    /// A video without sound.
    case noAudio
    /// Parakeet is not installed (or was removed during the job).
    case modelMissing
    /// The engine failed on its own.
    case engine
    /// Not a word was heard.
    case nothingHeard
    /// The text could not be written, beside the file nor in the fallback.
    case writeFailed
    /// The app ended in the middle of the job.
    case interrupted
    /// The remote engine has no address or no key yet.
    case notConfigured
    /// The server refused the token or the key.
    case unauthorized
    /// The server could not be reached, or the connection broke.
    case network
    /// The server stayed full, asleep or stopping for too long.
    case serverBusy
    /// Over what the server takes (400 MiB for the Studio).
    case tooLarge
    /// Over what the server takes (2 h of sound for the Studio).
    case tooLong
    /// The server failed on its side.
    case remoteFailed

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ForkTranscribeFailure(rawValue: raw) ?? .engine
    }

    /// Whether trying again as it is can work: a file gone stays gone.
    var isRetryable: Bool {
        switch self {
        case .fileMissing, .unreadable, .noAudio, .tooLarge, .tooLong: return false
        case .notDownloaded, .modelMissing, .engine, .nothingHeard, .writeFailed, .interrupted,
             .notConfigured, .unauthorized, .network, .serverBusy, .remoteFailed: return true
        }
    }
}

/// Where a job stands. Progress is kept apart (`ForkTranscribeQueue.progress`):
/// it changes many times a second and is never written.
enum ForkTranscribeStage: Equatable, Codable {
    case queued
    /// Parakeet must be installed first: the job goes on its own once it is.
    case waitingForModel
    /// Another transcription holds the engine (a meeting's).
    case waitingForEngine
    case loading
    /// Remote: the sound is taken out of the file, light enough to send.
    case preparing
    /// Remote: the Studio wakes up (30 to 60 s after 10 min without work).
    case waking
    case uploading
    /// Remote: the server is full; it is asked again after the time it said.
    case waitingForServer
    /// Remote: sent, waiting its turn on the server.
    case remoteQueued
    case transcribing
    case writing
    case done
    case failed(ForkTranscribeFailure)
    case cancelled

    var isActive: Bool {
        switch self {
        case .queued, .waitingForModel, .waitingForEngine, .loading, .preparing, .waking, .uploading,
             .waitingForServer, .remoteQueued, .transcribing, .writing: return true
        case .done, .failed, .cancelled: return false
        }
    }

    /// Whether the job holds the engine: it is the one at work.
    var isRunning: Bool {
        switch self {
        case .loading, .preparing, .waking, .uploading, .waitingForServer, .remoteQueued, .transcribing, .writing:
            return true
        default: return false
        }
    }
}

/// One file dropped to be transcribed, as the page and the history show it.
struct ForkTranscribeJob: Codable, Equatable, Identifiable {
    let id: UUID
    var source: URL
    var engine: ForkTranscribeEngine
    var language: ForkTranscribeLanguage
    let added: Date
    var stage: ForkTranscribeStage
    /// The sound's length, once read.
    var duration: TimeInterval?
    /// The files written, in the order of the formats.
    var outputs: [URL] = []
    /// Written in `~/Documents/Transcriptions` because the file's folder
    /// refused (read-only volume, no permission).
    var usedFallbackFolder = false
    var words: Int?
    /// The language heard ("fr", "en"), when known.
    var heardLanguage: String?
    var started: Date?
    var finished: Date?
    /// Seconds of work, for the diagnostic and the "1 h in 42 s" line.
    var processingSeconds: Double?
    /// The Studio's id for the job once sent: a relaunch follows it again
    /// instead of sending the file twice.
    var remoteID: String?
    /// Who speaks, as asked when it was dropped (`ForkTranscribeSpeakers`).
    var speakers: String?

    var name: String { source.lastPathComponent }
}

/// The rules of the queue, kept free of AppKit and of the engine so they can
/// be tested.
enum ForkTranscribeRules {
    /// What the drop zone shows, in this order.
    static let shownFormats = ["MP3", "WAV", "M4A", "FLAC", "OPUS", "OGG", "MP4", "MOV"]

    /// Every extension taken from a drop or a folder: AVFoundation decodes
    /// the first ones on this Mac (probe of 2026-11-20); the others are taken
    /// too, and say "unreadable" if they are.
    static let acceptedExtensions: Set<String> = [
        "mp3", "wav", "wave", "m4a", "m4b", "aac", "flac", "opus", "ogg", "oga", "caf", "aif", "aiff", "aifc",
        "mp4", "m4v", "mov", "3gp", "3g2", "amr", "wma", "webm", "mkv",
    ]

    /// The most finished jobs kept in the list: the oldest are forgotten
    /// (their files stay on the disk).
    static let historyLimit = 200

    static func accepts(_ url: URL) -> Bool {
        acceptedExtensions.contains(url.pathExtension.lowercased())
    }

    /// The files of a drop, in order: a folder gives its own files (not its
    /// sub-folders'), sorted by name; hidden files and anything already in
    /// the drop are left out.
    static func files(of dropped: [URL], contents: (URL) -> [URL]?) -> [URL] {
        var seen = Set<String>()
        var found: [URL] = []
        func take(_ url: URL) {
            let path = url.standardizedFileURL.path
            guard accepts(url), !url.lastPathComponent.hasPrefix("."), seen.insert(path).inserted else { return }
            found.append(url.standardizedFileURL)
        }
        for url in dropped {
            if let children = contents(url) {
                children.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                    .forEach(take)
            } else {
                take(url)
            }
        }
        return found
    }

    /// The next job to start: the first queued (or waiting) one, in the
    /// order they were dropped. Without Parakeet, a file for this Mac waits
    /// and the remote ones behind it go.
    static func next(in jobs: [ForkTranscribeJob], modelReady: Bool = true) -> UUID? {
        jobs.first {
            [.queued, .waitingForModel, .waitingForEngine].contains($0.stage) && ($0.engine != .local || modelReady)
        }?.id
    }

    /// What a list read at launch becomes: a job the app left in the middle
    /// failed as `interrupted`, a queued one waits again, and only the
    /// newest finished ones are kept.
    static func restored(_ jobs: [ForkTranscribeJob]) -> [ForkTranscribeJob] {
        let fixed = jobs.map { job -> ForkTranscribeJob in
            var job = job
            switch job.stage {
            // A remote job goes again on its own: the server kept it (its id
            // is followed again) or it is sent again.
            case _ where job.engine != .local && job.stage.isActive: job.stage = .queued
            case .loading, .transcribing, .writing: job.stage = .failed(.interrupted)
            case .waitingForModel, .waitingForEngine: job.stage = .queued
            default: break
            }
            return job
        }
        return trimmed(fixed)
    }

    /// Keeps every active job and the newest finished ones.
    static func trimmed(_ jobs: [ForkTranscribeJob]) -> [ForkTranscribeJob] {
        let finished = jobs.filter { !$0.stage.isActive }
        guard finished.count > historyLimit else { return jobs }
        let dropped = Set(finished.sorted { ($0.finished ?? $0.added) > ($1.finished ?? $1.added) }
            .dropFirst(historyLimit).map(\.id))
        return jobs.filter { !dropped.contains($0.id) }
    }

    /// Seconds left, once enough is done for the guess to mean something.
    static func remaining(fraction: Double, elapsed: TimeInterval) -> TimeInterval? {
        guard fraction >= 0.05, fraction < 1, elapsed > 0 else { return nil }
        return elapsed / fraction * (1 - fraction)
    }

    /// "4:05", "1:12:04".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        let hours = total / 3600, minutes = total % 3600 / 60, rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }
}
