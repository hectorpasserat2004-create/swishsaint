// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

// MARK: Finish D

/// Whether a meeting app's sound is people talking, read from two numbers
/// per 50 ms frame: its energy and its zero crossings, for the last 10 s,
/// and nothing else. No sample is kept, only these 400 numbers, overwritten
/// in place.
///
/// Speech alternates voiced sounds (few crossings) and hissed ones (many),
/// and loud syllables with short drops: within a second of talk, the
/// crossings vary a lot from frame to frame and so does the level. Music,
/// even rhythmic, holds both far steadier. A second counts as speech when
/// it has sound (`activeFrames`), crossings that vary (`crossingSpread`)
/// and a level that moves (`levelSpread`); the speech of the last 10 s is
/// the frames with sound in such seconds. "Others talk" once it reaches
/// 3 s. Measured on 31 instrumental and sung tracks against French and
/// English voices (`<scratchpad>/finish-d/gate`): speech heard 4-6 s after
/// it begins, 1 track in 31 heard once.
struct ForkMeetingVoiceGate: Equatable {
    static let frameSeconds: Double = 0.05
    static let framesPerBlock = 20
    static let blocks = 10
    static let windowFrames = framesPerBlock * blocks
    /// -50 dBFS, as a mean square: below it a frame is silence (a call's
    /// comfort noise sits under -60).
    static let activeEnergy: Float = 1e-5
    /// A second with fewer frames of sound than this (0.25 s) is a cough, a
    /// click, a notification: never speech.
    static let activeFrames = 5
    /// The crossings' standard deviation over their mean, among the frames
    /// with sound (speech: 0.95-1.6; music: 0.15-0.6, a few up to 0.95).
    static let crossingSpread: Float = 0.9
    /// The level's standard deviation among the frames with sound, in dB
    /// (speech: 5-12; music: 1-4).
    static let levelSpread: Float = 5
    static let speechNeeded: TimeInterval = 3

    /// The last `windowFrames` frames, oldest overwritten first.
    private var energies = [Float](repeating: 0, count: ForkMeetingVoiceGate.windowFrames)
    private var crossings = [Float](repeating: 0, count: ForkMeetingVoiceGate.windowFrames)
    /// Frames taken since the start; the next one goes at `count % windowFrames`.
    private(set) var count = 0

    /// One frame: its mean square energy and its zero crossings.
    mutating func add(_ frame: ForkMeetingFrameMeter.Frame) {
        let slot = count % Self.windowFrames
        energies[slot] = frame.energy.isFinite ? max(0, frame.energy) : 0
        crossings[slot] = Float(max(0, frame.crossings))
        count += 1
    }

    /// Seconds of speech in the last 10 s, in whole seconds of frames
    /// already complete.
    var speechSeconds: TimeInterval {
        let complete = min(count, Self.windowFrames) / Self.framesPerBlock
        guard complete > 0 else { return 0 }
        var frames = 0
        // The last `complete` whole seconds.
        let end = count - count % Self.framesPerBlock
        for block in 0..<complete {
            let first = end - (complete - block) * Self.framesPerBlock
            let slots = (first..<(first + Self.framesPerBlock)).map { $0 % Self.windowFrames }
            frames += Self.speechFrames(energies: slots.map { energies[$0] }, crossings: slots.map { crossings[$0] })
        }
        return Double(frames) * Self.frameSeconds
    }

    /// Others are talking: 3 s of speech in the last 10.
    var hearsSpeech: Bool { speechSeconds >= Self.speechNeeded }

    /// The frames of sound of one second, when that second is speech; 0
    /// otherwise.
    static func speechFrames(energies: [Float], crossings: [Float]) -> Int {
        let active = energies.indices.filter { energies[$0] >= activeEnergy }
        guard active.count >= activeFrames else { return 0 }
        let crossed = active.map { crossings[$0] }
        let levels = active.map { 10 * log10(energies[$0]) }
        let meanCrossings = mean(crossed)
        guard meanCrossings > 0 else { return 0 }
        let speech = deviation(crossed) / meanCrossings >= crossingSpread && deviation(levels) >= levelSpread
        return speech ? active.count : 0
    }

    private static func mean(_ values: [Float]) -> Float {
        values.isEmpty ? 0 : values.reduce(0, +) / Float(values.count)
    }

    private static func deviation(_ values: [Float]) -> Float {
        let average = mean(values)
        return mean(values.map { ($0 - average) * ($0 - average) }).squareRoot()
    }

    /// Forgets every frame: a new meeting starts from silence.
    mutating func reset() {
        self = ForkMeetingVoiceGate()
    }
}

/// Cuts a stream of mono samples into the gate's 50 ms frames: a running
/// sum of squares, a count of sign changes, and nothing more.
struct ForkMeetingFrameMeter: Equatable {
    struct Frame: Equatable {
        var energy: Float
        var crossings: Int
    }

    let frameLength: Int
    private var sum: Float = 0
    private var crossed = 0
    private var taken = 0
    private var positive = true

    init(sampleRate: Double) {
        frameLength = max(1, Int((sampleRate * ForkMeetingVoiceGate.frameSeconds).rounded()))
    }

    /// The frames the samples complete.
    mutating func take(_ samples: UnsafeBufferPointer<Float>) -> [Frame] {
        var done: [Frame] = []
        for sample in samples {
            sum += sample * sample
            let isPositive = sample >= 0
            if taken > 0, isPositive != positive { crossed += 1 }
            positive = isPositive
            taken += 1
            if taken == frameLength {
                done.append(Frame(energy: sum / Float(frameLength), crossings: crossed))
                sum = 0
                crossed = 0
                taken = 0
            }
        }
        return done
    }
}

/// When the offer comes back: "It's started · Record?".
///
/// Once per meeting when others start talking while its app's microphone is
/// open, then a last time after 2 minutes of conversation, never more.
/// Without the system audio permission, only the microphone can be heard:
/// once there has been a minute of talk on it (the person's own voice), and
/// a last time two minutes later.
struct ForkMeetingNudgePlan: Equatable {
    enum Source: Equatable {
        /// The meeting app's sound, through its tap.
        case app
        /// The microphone alone.
        case microphone
    }

    /// Talk heard on the microphone alone before the first nudge.
    static let microphoneSpeech: TimeInterval = 60
    /// Conversation after the first nudge before the last one.
    static let secondAfter: TimeInterval = 120
    static let most = 2

    private(set) var meeting: ForkMeetingIdentity?
    private(set) var nudges = 0
    /// Seconds of talk counted toward the next nudge.
    private(set) var talk: TimeInterval = 0

    /// Another nudge may come for `meeting`: the listener may still be
    /// needed for it.
    func wantsMore(for meeting: ForkMeetingIdentity) -> Bool {
        self.meeting != meeting || nudges < Self.most
    }

    /// Once a second while the offer waits: whether to nudge now, and if it
    /// is the last one. `speaking`: the gate hears speech now (3 s in the
    /// last 10); `microphoneOpen`: the meeting app records its microphone.
    /// After the first nudge, the call's time counts (its microphone open,
    /// or voices heard), and the last nudge comes 2 minutes on, while
    /// someone talks.
    mutating func second(meeting: ForkMeetingIdentity, source: Source, speaking: Bool,
                         microphoneOpen: Bool) -> (nudge: Bool, last: Bool) {
        if self.meeting != meeting {
            self.meeting = meeting
            nudges = 0
            talk = 0
        }
        guard nudges < Self.most else { return (false, false) }
        if nudges == 0 {
            guard speaking else { return (false, false) }
            switch source {
            case .app:
                // Others talking while the person is in the call (its app
                // records the microphone): the meeting has begun.
                guard microphoneOpen else { return (false, false) }
            case .microphone:
                talk += 1
                guard talk >= Self.microphoneSpeech else { return (false, false) }
            }
            nudges = 1
            talk = 0
            return (true, false)
        }
        if microphoneOpen || speaking { talk += 1 }
        guard talk >= Self.secondAfter, speaking else { return (false, false) }
        nudges = Self.most
        return (true, true)
    }

    /// The meeting is not offered any more: the next one starts anew.
    mutating func forget() {
        self = ForkMeetingNudgePlan()
    }
}

/// What listens while a meeting is offered and nothing records: the meeting
/// app's level for the nudge, and, with "the last 5 minutes" on, its sound
/// and the microphone kept in memory.
///
/// Nothing listens without an offer waiting for an answer (a "Not now", a
/// "Never", the call over, the feature off: no offer), on a locked screen,
/// in sleep, or while the app quits. The kept sound goes with any of them.
struct ForkMeetingListenPlan: Equatable {
    struct Facts: Equatable {
        var nudgeOn = true
        var lookbackOn = false
        /// The meeting offered and not answered; also the one a start from
        /// that offer is starting, whose sound the recording takes.
        var meeting: ForkMeetingIdentity?
        /// Another nudge may come for it.
        var nudgesLeft = true
        var locked = false
        var asleep = false
        var terminating = false
        /// A tap proved system audio recording allowed on this Mac: only
        /// then is an app tapped (otherwise macOS could ask, mid-call).
        var systemAudio = false
        /// The microphone may be read: never asked for here.
        var microphoneAllowed = false
    }

    var app = false
    var microphone = false
    /// The sound heard is kept in memory, for a recording to begin with.
    var keeps = false

    var listens: Bool { app || microphone }

    static func plan(_ facts: Facts) -> ForkMeetingListenPlan {
        guard facts.meeting != nil, !facts.locked, !facts.asleep, !facts.terminating else {
            return ForkMeetingListenPlan()
        }
        let keeps = facts.lookbackOn && (facts.systemAudio || facts.microphoneAllowed)
        let nudges = facts.nudgeOn && facts.nudgesLeft
        var plan = ForkMeetingListenPlan()
        plan.app = facts.systemAudio && (keeps || nudges)
        // The microphone hears the person: kept for the recording, or the
        // only way to tell the meeting began without the app's sound.
        plan.microphone = facts.microphoneAllowed && (keeps || (nudges && !facts.systemAudio))
        plan.keeps = keeps
        return plan
    }

    /// Whether the sound kept so far must go: nothing keeps it any more, or
    /// it was another meeting's.
    static func clears(from old: Facts, to new: Facts) -> Bool {
        let before = plan(old), after = plan(new)
        return before.keeps && (!after.keeps || old.meeting != new.meeting)
    }
}

/// A few minutes of one sound, in memory only: 16 kHz mono, 16-bit, a
/// circle the newest sample overwrites the oldest of. Its samples follow
/// the host clock: a buffer late or early leaves silence, or overlaps
/// what came before, so the end of the circle is always "now".
///
/// It is never written anywhere by itself: a recording that starts reads it
/// once (`freeze`, then `read`), and `clear` fills it with zeros and lets
/// its memory go. Thread safe.
final class ForkMeetingLookbackRing: @unchecked Sendable {
    static let sampleRate: Double = 16_000
    static let seconds: TimeInterval = 300
    /// 10 ms: closer than this, a buffer follows the previous one as is.
    static let tolerance = 160

    let capacity: Int
    private let lock = NSLock()
    // Under `lock`.
    private var storage: [Int16] = []
    /// Samples written since the start (or the last `clear`).
    private var written = 0
    /// The host time just after the last sample.
    private var endHost: Double?
    private var frozen = false

    init(seconds: TimeInterval = ForkMeetingLookbackRing.seconds) {
        capacity = max(1, Int(seconds * Self.sampleRate))
    }

    /// Samples at 16 kHz that begin at `startHost` (host seconds).
    func append(_ samples: UnsafeBufferPointer<Float>, startHost: Double) {
        guard !samples.isEmpty, startHost.isFinite else { return }
        lock.withLock {
            guard !frozen else { return }
            // Allocated only once something is kept.
            if storage.isEmpty { storage = [Int16](repeating: 0, count: capacity) }
            var skip = 0
            if let endHost {
                let offset = Int(((startHost - endHost) * Self.sampleRate).rounded())
                if offset > Self.tolerance {
                    writeSilence(offset)
                } else if offset < -Self.tolerance {
                    skip = min(samples.count, -offset)
                }
            }
            for sample in samples.dropFirst(skip) {
                storage[written % capacity] = Int16(max(-1, min(1, sample)) * Float(Int16.max))
                written += 1
            }
            endHost = startHost + Double(samples.count) / Self.sampleRate
        }
    }

    /// Under `lock`.
    private func writeSilence(_ count: Int) {
        let count = min(count, capacity)
        for _ in 0..<count {
            storage[written % capacity] = 0
            written += 1
        }
    }

    /// What it holds: from `start` to `end`, host seconds; `nil` when empty.
    var span: (start: Double, end: Double)? {
        lock.withLock {
            guard let endHost, written > 0 else { return nil }
            return (endHost - Double(min(written, capacity)) / Self.sampleRate, endHost)
        }
    }

    var storedSeconds: TimeInterval {
        lock.withLock { Double(min(written, capacity)) / Self.sampleRate }
    }

    /// The memory it holds, 0 once cleared.
    var bytesHeld: Int {
        lock.withLock { storage.count * MemoryLayout<Int16>.stride }
    }

    /// Nothing more is taken: a recording reads what it holds now.
    func freeze() {
        lock.withLock { frozen = true }
    }

    var isFrozen: Bool { lock.withLock { frozen } }

    /// The samples from host time `from`, `count` of them, as floats;
    /// zeros where it holds nothing (before its start, after its end).
    func read(from: Double, count: Int) -> [Float] {
        lock.withLock {
            var out = [Float](repeating: 0, count: max(0, count))
            guard let endHost, written > 0, count > 0 else { return out }
            let stored = min(written, capacity)
            // The absolute index of the sample at `from`.
            let first = written - Int(((endHost - from) * Self.sampleRate).rounded())
            let oldest = written - stored
            for index in 0..<count {
                let absolute = first + index
                guard absolute >= oldest, absolute < written else { continue }
                out[index] = Float(storage[absolute % capacity]) / Float(Int16.max)
            }
            return out
        }
    }

    /// Moves what it holds into a new ring, at once and without a copy, for
    /// a recording to read; this one is left empty and takes nothing more.
    /// Whatever empties this one afterwards never touches what the
    /// recording took.
    func handOver() -> ForkMeetingLookbackRing {
        let taken = ForkMeetingLookbackRing(capacity: capacity)
        lock.withLock {
            taken.adopt(storage: storage, written: written, endHost: endHost)
            storage = []
            written = 0
            endHost = nil
            frozen = true
        }
        return taken
    }

    private init(capacity: Int) {
        self.capacity = capacity
    }

    private func adopt(storage: [Int16], written: Int, endHost: Double?) {
        lock.withLock {
            self.storage = storage
            self.written = written
            self.endHost = endHost
            frozen = true
        }
    }

    /// Fills it with zeros and lets its memory go: what was kept is gone.
    func clear() {
        lock.withLock {
            for index in storage.indices { storage[index] = 0 }
            storage = []
            written = 0
            endHost = nil
            frozen = false
        }
    }
}

/// How the kept sound goes before a recording: both tracks start together
/// at the file's zero, `seconds` before the first frame of the picture; a
/// track that kept less begins with silence.
struct ForkMeetingLookbackPlan: Equatable {
    struct Track: Equatable {
        /// Silence first, in seconds.
        var silence: TimeInterval
        /// Then the kept sound from `from` (host seconds), this long.
        var from: Double
        var seconds: TimeInterval
    }

    /// How much sound comes before the picture.
    var seconds: TimeInterval
    var tracks: [Track]

    /// Less than this is not worth a "sound only" beginning.
    static let minimum: TimeInterval = 1

    /// `spans`: what each ring holds (host seconds), `nil` for an empty one;
    /// `zero`: the host time the picture starts at. `nil`: nothing to add.
    static func plan(spans: [(start: Double, end: Double)?], zero: Double,
                     limit: TimeInterval = ForkMeetingLookbackRing.seconds) -> ForkMeetingLookbackPlan? {
        let starts = spans.compactMap { $0?.start }.filter { $0 < zero }
        guard let earliest = starts.min() else { return nil }
        let seconds = min(limit, zero - earliest)
        guard seconds >= minimum else { return nil }
        let begin = zero - seconds
        let tracks = spans.map { span -> Track in
            guard let span, span.start < zero else { return Track(silence: seconds, from: zero, seconds: 0) }
            let from = max(begin, span.start)
            let to = min(zero, span.end)
            return Track(silence: from - begin, from: from, seconds: max(0, to - from))
        }
        return ForkMeetingLookbackPlan(seconds: seconds, tracks: tracks)
    }
}

/// The words of the nudge and of the kept sound.
enum ForkMeetingLookbackText {
    /// "+4 min 12 s already kept": the kept sound, at most 5 minutes.
    static func kept(since: Date, now: Date, strings s: ForkMeetingStrings) -> String {
        let seconds = Int(min(ForkMeetingLookbackRing.seconds, max(0, now.timeIntervalSince(since))))
        return String(format: s.lookbackKeptFormat, duration(seconds, strings: s))
    }

    /// "4 min 12 s", "45 s", "5 min".
    static func duration(_ seconds: Int, strings s: ForkMeetingStrings) -> String {
        let minutes = seconds / 60, rest = seconds % 60
        if minutes == 0 { return String(format: s.lookbackSecondsFormat, rest) }
        if rest == 0 { return String(format: s.lookbackMinutesFormat, minutes) }
        return String(format: s.lookbackMinutesFormat, minutes) + " " + String(format: s.lookbackSecondsFormat, rest)
    }

    /// "The first 4 minutes: sound only", in whole minutes, the nearest.
    static func soundOnly(seconds: TimeInterval, strings s: ForkMeetingStrings) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        return minutes == 1 ? s.lookbackSoundOnlyOne : String(format: s.lookbackSoundOnlyFormat, minutes)
    }
}
