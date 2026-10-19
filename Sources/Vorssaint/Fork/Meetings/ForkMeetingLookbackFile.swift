// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AVFoundation
import CoreMedia
import os

// MARK: Finish D

/// The minutes kept before the click of one recording, from the click to
/// their own file beside the master (`ForkMeetingFolder.lookbackName`).
///
/// ```
/// click ─► begin (seconds kept, the rings go on) ─► the master's first sound per track ─► cut
///       ─► both cut, or 3 s, or the stop ─► write (its own queue) ─► meeting.json: lookbackJoins
/// ```
/// The listener that filled the rings goes on until then, so the seconds
/// between the click and the recording's own first sound are kept too; it
/// stops, and the rings are emptied and closed, once they are written. Never
/// on the writer's queue: the master's live samples never wait for it.
final class ForkMeetingLookbackHandOver: @unchecked Sendable {
    let lookback: ForkMeetingLookback
    private let listener: ForkMeetingCallListener?
    private let queue = DispatchQueue(label: "fork.meetings.lookback", qos: .utility)
    private let lock = NSLock()
    private static let log = Logger(subsystem: "fork.meetings", category: "lookback")

    // Under `lock`.
    private var zero: Double?
    private var folder: URL?
    private var seconds: TimeInterval = 0
    private var cuts: [Double?] = [nil, nil]
    private var settled = false

    /// Main thread: the file is whole, with each track's join; `nil` when
    /// nothing was written.
    var onWritten: ((URL, [Double]?) -> Void)?

    /// For a buffer of the listener still on its way when a track is cut.
    static let settle: TimeInterval = 0.5

    init(lookback: ForkMeetingLookback, listener: ForkMeetingCallListener?) {
        self.lookback = lookback
        self.listener = listener
    }

    /// At the click (`zero`, host seconds): how many seconds kept before it
    /// open the recording; 0 when too little was kept, and everything goes.
    /// The rings go on until each track is cut.
    func begin(zero: Double, folder: URL) -> TimeInterval {
        guard let plan = ForkMeetingLookbackPlan.plan(spans: lookback.rings.map(\.span), zero: zero) else {
            discard()
            return 0
        }
        lock.withLock {
            self.zero = zero
            self.folder = folder
            seconds = plan.seconds
        }
        queue.asyncAfter(deadline: .now() + ForkMeetingLookbackPlan.cutLimit + 0.1) { [self] in finish() }
        return plan.seconds
    }

    /// Writer queue: the master's own sound for `track` begins `seconds`
    /// after the click. Once both are cut, the file is written.
    func cut(track: Int, masterSeconds: Double) {
        let both = lock.withLock { () -> Bool in
            guard let zero, !settled, track < cuts.count, cuts[track] == nil else { return false }
            let host = zero + min(ForkMeetingLookbackPlan.cutLimit, max(0, masterSeconds))
            cuts[track] = host
            lookback.rings[track].cut(atHost: host)
            return cuts.allSatisfy { $0 != nil }
        }
        if both { queue.async { [self] in finish() } }
    }

    /// The recording stopped, or the cut limit passed: what is not cut yet
    /// is cut now, and the file written. Once.
    func finish() {
        let taken = lock.withLock { () -> (zero: Double, folder: URL, seconds: TimeInterval, cuts: [Double])? in
            guard let zero, let folder, !settled else { return nil }
            settled = true
            let now = ForkMeetingWriter.hostSeconds()
            let filled = cuts.map { $0 ?? min(now, zero + ForkMeetingLookbackPlan.cutLimit) }
            return (zero, folder, seconds, filled)
        }
        guard let taken else { return }
        for (index, host) in taken.cuts.enumerated() { lookback.rings[index].cut(atHost: host) }
        queue.asyncAfter(deadline: .now() + Self.settle) { [self] in
            listener?.stop()
            let url = taken.folder.appendingPathComponent(ForkMeetingFolder.lookbackName)
            let plan = ForkMeetingLookbackPlan.plan(spans: lookback.rings.map(\.span), zero: taken.zero,
                                                    cuts: taken.cuts, limit: taken.seconds)
            var joins: [Double]?
            if let plan, ForkMeetingLookbackFile.write(plan, rings: lookback.rings, to: url) {
                joins = plan.joins
                Self.log.notice("kept sound written: \(Int(plan.seconds)) s, joins \(plan.joins, privacy: .public)")
            } else {
                try? FileManager.default.removeItem(at: url)
                Self.log.error("kept sound not written")
            }
            lookback.clear()
            let done = onWritten
            DispatchQueue.main.async { done?(taken.folder, joins) }
        }
    }

    /// The recording did not start: nothing is written, everything goes.
    func discard() {
        lock.withLock { settled = true }
        listener?.stop()
        lookback.clear()
    }
}

/// Writes the kept minutes: two sound tracks, the meeting's then the
/// microphone's, in the master's format (AAC, 48 kHz, mono), both as long as
/// the longest (`ForkMeetingLookbackPlan.lengths`), the shorter ending on
/// silence the final pass never takes: an `.m4a` whose tracks end apart
/// reads its later one cut short. Not in real time: a second of each track
/// in turn, so the file's interleaving never holds one back.
enum ForkMeetingLookbackFile {
    static let sampleRate = ForkMeetingWriter.sampleRate

    /// Blocking, off the main thread. `false` when the file is not whole.
    static func write(_ plan: ForkMeetingLookbackPlan, rings: [ForkMeetingLookbackRing], to url: URL) -> Bool {
        try? FileManager.default.removeItem(at: url)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1,
                                         interleaved: false),
              let writer = try? AVAssetWriter(outputURL: url, fileType: .m4a) else { return false }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: ForkMeetingQuality.Rates.sourceAudio,
        ]
        guard writer.canApply(outputSettings: settings, forMediaType: .audio) else { return false }
        let count = min(plan.tracks.count, rings.count)
        var inputs: [AVAssetWriterInput] = []
        for _ in 0..<count {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else { return false }
            writer.add(input)
            inputs.append(input)
        }
        guard !inputs.isEmpty, writer.startWriting() else { return false }
        writer.startSession(atSourceTime: .zero)
        let longest = Int64(((plan.lengths.max() ?? plan.seconds) * sampleRate).rounded())
        let totals = [Int64](repeating: longest, count: count)
        var positions = [Int64](repeating: 0, count: count)
        var finished = [Bool](repeating: false, count: count)
        let chunk = Int64(sampleRate)
        while finished.contains(false) {
            for index in 0..<count where !finished[index] {
                let from = positions[index]
                guard from < totals[index] else {
                    inputs[index].markAsFinished()
                    finished[index] = true
                    continue
                }
                let length = min(chunk, totals[index] - from)
                let samples = Self.samples(plan.tracks[index], ring: rings[index], from: from, count: Int(length))
                guard waitUntilReady(inputs[index]),
                      let buffer = ForkMeetingWriter.sampleBuffer(samples, start: from, format: format),
                      inputs[index].append(buffer) else {
                    writer.cancelWriting()
                    return false
                }
                positions[index] += length
            }
        }
        let closed = DispatchSemaphore(value: 0)
        writer.finishWriting { closed.signal() }
        guard closed.wait(timeout: .now() + 30) == .success, writer.status == .completed else { return false }
        return true
    }

    /// `count` samples at 48 kHz from file sample `from`: silence before the
    /// track's kept sound and after it, the 16 kHz ring brought to 48 kHz by
    /// linear steps, every sample where its host time says.
    static func samples(_ track: ForkMeetingLookbackPlan.Track, ring: ForkMeetingLookbackRing,
                        from: Int64, count: Int) -> [Float] {
        var out = [Float](repeating: 0, count: max(0, count))
        let rate = sampleRate, kept = ForkMeetingLookbackRing.sampleRate
        let start = Int64((track.silence * rate).rounded())
        let end = start + Int64((track.seconds * rate).rounded())
        let first = max(from, start), last = min(from + Int64(count), end)
        guard first < last else { return out }
        // The ring's samples covering [first, last), one more for the steps.
        let offset = Double(first - start) / rate
        let needed = Int((Double(last - first) / rate * kept).rounded(.up)) + 2
        let source = ring.read(from: track.from + offset, count: needed)
        let step = kept / rate
        for index in first..<last {
            let position = Double(index - first) * step
            let below = Int(position)
            guard below + 1 < source.count else { break }
            let fraction = Float(position - Double(below))
            out[Int(index - from)] = source[below] + (source[below + 1] - source[below]) * fraction
        }
        return out
    }

    private static func waitUntilReady(_ input: AVAssetWriterInput) -> Bool {
        var waited = 0
        while !input.isReadyForMoreMediaData {
            guard waited < 5_000 else { return false }
            usleep(1_000)
            waited += 1
        }
        return true
    }
}
