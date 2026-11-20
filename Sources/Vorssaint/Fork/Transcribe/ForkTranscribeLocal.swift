// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AVFoundation
import Foundation

/// A dropped file's sound, every playing track mixed into one, decoded and
/// resampled to 16 kHz mono Float32 by AVAssetReader on the way: no file in
/// between, a few seconds in memory at a time. A meeting's own video (its
/// "Meeting" and "Microphone" tracks) is heard whole this way.
final class ForkTranscribeAudioSource: ForkParakeetSampleSource {
    enum Failure: Error, Equatable {
        case unreadable
        case noAudio
    }

    let duration: TimeInterval
    private let reader: AVAssetReader
    private let output: AVAssetReaderAudioMixOutput
    private var pending: [Float] = []
    private var pendingOffset = 0

    private struct Loaded {
        let asset: AVURLAsset
        /// The tracks that play; all of them when none says so.
        let tracks: [AVAssetTrack]
        let duration: TimeInterval
    }

    private final class Box: @unchecked Sendable {
        var loaded: Loaded?
    }

    /// Blocks until the file's tracks are loaded: never on the main thread.
    /// Nil when AVFoundation cannot open the file at all.
    private static func load(_ url: URL) -> Loaded? {
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            if let tracks = try? await asset.loadTracks(withMediaType: .audio),
               let duration = try? await asset.load(.duration) {
                var playing: [AVAssetTrack] = []
                for track in tracks where (try? await track.load(.isEnabled)) ?? true { playing.append(track) }
                box.loaded = Loaded(asset: asset, tracks: playing.isEmpty ? tracks : playing,
                                    duration: duration.seconds.isFinite ? duration.seconds : 0)
            }
            done.signal()
        }
        done.wait()
        return box.loaded
    }

    /// Blocks while the file's tracks load: never on the main thread.
    init(url: URL) throws {
        guard let audio = Self.load(url) else { throw Failure.unreadable }
        guard !audio.tracks.isEmpty else { throw Failure.noAudio }
        let tracks = audio.tracks
        duration = audio.duration
        do {
            reader = try AVAssetReader(asset: audio.asset)
        } catch {
            throw Failure.unreadable
        }
        output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: ForkParakeetShape.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw Failure.unreadable }
        reader.add(output)
        guard reader.startReading() else { throw Failure.unreadable }
    }

    deinit { reader.cancelReading() }

    func read(into buffer: UnsafeMutableBufferPointer<Float>) throws -> Int {
        var written = 0
        while written < buffer.count {
            if pendingOffset >= pending.count {
                guard refill() else { break }
            }
            let count = min(buffer.count - written, pending.count - pendingOffset)
            for index in 0..<count { buffer[written + index] = pending[pendingOffset + index] }
            written += count
            pendingOffset += count
        }
        if written == 0, reader.status == .failed { throw Failure.unreadable }
        return written
    }

    private func refill() -> Bool {
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let bytes = CMBlockBufferGetDataLength(block)
            guard bytes >= MemoryLayout<Float>.size else { continue }
            pending = [Float](repeating: 0, count: bytes / MemoryLayout<Float>.size)
            let status = pending.withUnsafeMutableBytes { raw -> OSStatus in
                guard let base = raw.baseAddress else { return -1 }
                return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: raw.count, destination: base)
            }
            guard status == kCMBlockBufferNoErr else { continue }
            pendingOffset = 0
            return true
        }
        return false
    }
}

/// Which reader opens a file.
///
/// - **AVAssetReader** for most: it mixes every playing track, so a meeting's
///   video with its "Meeting" and "Microphone" tracks is heard whole.
/// - **AVAudioFile** for Ogg and Opus: AVAssetReader stops a variable-rate
///   Ogg at the length it guesses from the bitrate, silently (probe of
///   2026-11-20: 27.1 s read of 34.4, 583 of 600), when AVAudioFile reads it
///   to its end. It is also the second try for anything AVAssetReader refuses.
enum ForkTranscribeAudio {
    static let audioFileExtensions: Set<String> = ["ogg", "oga", "opus"]

    /// Work queue only. Throws `ForkTranscribeFailure`.
    static func open(_ url: URL) throws -> (ForkParakeetSampleSource, TimeInterval) {
        if audioFileExtensions.contains(url.pathExtension.lowercased()) {
            guard let file = try? ForkTranscribeAudioFileSource(url: url) else { throw ForkTranscribeFailure.unreadable }
            return (file, file.duration)
        }
        do {
            let source = try ForkTranscribeAudioSource(url: url)
            return (source, source.duration)
        } catch ForkTranscribeAudioSource.Failure.noAudio {
            throw ForkTranscribeFailure.noAudio
        } catch {
            guard let file = try? ForkTranscribeAudioFileSource(url: url) else { throw ForkTranscribeFailure.unreadable }
            return (file, file.duration)
        }
    }
}

/// A file read by AVAudioFile and converted to 16 kHz mono Float32 by
/// AVAudioConverter, a second of it at a time.
final class ForkTranscribeAudioFileSource: ForkParakeetSampleSource {
    let duration: TimeInterval
    private let file: AVAudioFile
    private let converter: AVAudioConverter
    private let target: AVAudioFormat
    private var pending: [Float] = []
    private var pendingOffset = 0
    private var ended = false

    init(url: URL) throws {
        file = try AVAudioFile(forReading: url)
        guard file.length > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(ForkParakeetShape.sampleRate),
                                         channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: file.processingFormat, to: target)
        else { throw ForkTranscribeAudioSource.Failure.unreadable }
        self.target = target
        self.converter = converter
        duration = Double(file.length) / file.fileFormat.sampleRate
    }

    func read(into buffer: UnsafeMutableBufferPointer<Float>) throws -> Int {
        var written = 0
        while written < buffer.count {
            if pendingOffset >= pending.count {
                guard try refill() else { break }
            }
            let count = min(buffer.count - written, pending.count - pendingOffset)
            for index in 0..<count { buffer[written + index] = pending[pendingOffset + index] }
            written += count
            pendingOffset += count
        }
        return written
    }

    private func refill() throws -> Bool {
        guard !ended,
              let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(ForkParakeetShape.sampleRate))
        else { return false }
        var failure: NSError?
        let file = self.file
        let status = converter.convert(to: out, error: &failure) { count, state in
            guard let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count),
                  (try? file.read(into: input, frameCount: count)) != nil, input.frameLength > 0
            else {
                state.pointee = .endOfStream
                return nil
            }
            state.pointee = .haveData
            return input
        }
        if status == .error { throw ForkTranscribeAudioSource.Failure.unreadable }
        if status == .endOfStream { ended = true }
        guard out.frameLength > 0, let channel = out.floatChannelData?[0] else { return false }
        pending = Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
        pendingOffset = 0
        return true
    }
}

/// Parakeet on a dropped file. One engine of its own at `.utility`, like a
/// meeting's transcript: the dictation's stays ready and never waits behind
/// an hour of sound. Kept loaded while files wait, freed when the queue is
/// empty.
final class ForkTranscribeLocalEngine: @unchecked Sendable {
    struct Heard {
        var words: [ForkTranscribeFormat.Word]
        var duration: TimeInterval
        var processing: TimeInterval
    }

    private var engine: ForkParakeetEngine?
    private var loadedFrom: URL?

    /// Work queue only. Throws `ForkTranscribeFailure`.
    func transcribe(_ url: URL, modelDirectory: URL, language: String?,
                    progress: @escaping (Double) -> Bool) throws -> Heard {
        let (source, duration) = try ForkTranscribeAudio.open(url)
        let engine = try loaded(modelDirectory)
        do {
            let heard = try engine.transcribeLong(source, languageCode: language) { seconds in
                progress(duration > 0 ? min(1, seconds / duration) : 0)
            }
            return Heard(words: heard.words.map { .init(text: $0.text, start: $0.start, end: $0.end) },
                         duration: max(duration, heard.audioDuration), processing: heard.processingTime)
        } catch ForkParakeetError.cancelled {
            throw CancellationError()
        } catch is ForkTranscribeAudioSource.Failure {
            throw ForkTranscribeFailure.unreadable
        } catch {
            throw ForkTranscribeFailure.engine
        }
    }

    private func loaded(_ directory: URL) throws -> ForkParakeetEngine {
        if let engine, loadedFrom == directory, engine.isLoaded { return engine }
        let engine = ForkParakeetEngine(qos: .utility)
        do {
            try engine.load(from: directory)
        } catch {
            if case .missingModel = error as? ForkParakeetError { throw ForkTranscribeFailure.modelMissing }
            throw ForkTranscribeFailure.engine
        }
        self.engine = engine
        loadedFrom = directory
        return engine
    }

    /// Work queue only.
    func unload() {
        engine?.unload()
        engine = nil
        loadedFrom = nil
    }
}
