// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AVFoundation
import CoreMedia

// MARK: Finish D

/// "The last 5 minutes" of one offered meeting: its app's sound and the
/// microphone, each in its own ring, in memory only. A recording of that
/// meeting takes them once (`take`); anything else empties them (`clear`).
final class ForkMeetingLookback: @unchecked Sendable {
    let meeting: ForkMeetingIdentity
    let app = ForkMeetingLookbackRing()
    let microphone = ForkMeetingLookbackRing()
    /// When it began to keep, for "+4 min 12 s already kept".
    let since: Date

    init(meeting: ForkMeetingIdentity, since: Date = Date()) {
        self.meeting = meeting
        self.since = since
    }

    /// The kept sound up to `zero` (host seconds), moved out for the
    /// writer, the meeting's track first; `nil` when there is too little.
    /// Whatever happens, these rings keep nothing afterwards.
    func take(zero: Double) -> ForkMeetingWriter.Lookback? {
        let rings = [app.handOver(), microphone.handOver()]
        guard let plan = ForkMeetingLookbackPlan.plan(spans: rings.map(\.span), zero: zero) else {
            rings.forEach { $0.clear() }
            return nil
        }
        return ForkMeetingWriter.Lookback(plan: plan, rings: rings)
    }

    /// What was kept is gone, zeros first.
    func clear() {
        app.clear()
        microphone.clear()
    }

    /// The memory held, for the recipe and the logs.
    var bytesHeld: Int { app.bytesHeld + microphone.bytesHeld }
}

/// Listens to an offered meeting while nothing records: the level of its
/// app's sound (through a tap of that app alone, the official
/// `RecorderSystemAudioTap`) and of the microphone, for the nudge; and,
/// when "the last 5 minutes" is on, the same sound at 16 kHz into the
/// meeting's rings.
///
/// What it keeps of the sound for the nudge is two numbers per 50 ms
/// (`ForkMeetingVoiceGate`): each buffer is read on this listener's queue
/// and let go. Nothing is written, ever. Once a second it says whether
/// people talk, on the main thread.
///
/// The tap is made only once a tap proved system audio recording allowed
/// on this Mac, the microphone only when it is allowed: nothing here asks
/// macOS for anything.
final class ForkMeetingCallListener: @unchecked Sendable {
    typealias Second = (_ appSpeaks: Bool, _ microphoneSpeaks: Bool) -> Void

    private let queue = DispatchQueue(label: "fork.meetings.listener", qos: .utility)
    private let plan: ForkMeetingListenPlan
    private let appPID: pid_t?
    private let microphoneChoice: ForkMeetingMicrophoneChoice
    private let meetingDevice: String?
    private let lookback: ForkMeetingLookback?
    private let onSecond: Second
    private let makeTap: ForkMeetingRecorder.TapMaker

    // Queue only.
    private var running = false
    private var tap: ForkMeetingAudioTap?
    private var microphone: ForkMeetingMicrophone?
    private var timer: DispatchSourceTimer?
    private var appGate = ForkMeetingVoiceGate()
    private var microphoneGate = ForkMeetingVoiceGate()
    private var appMeter = ForkMeetingFrameMeter(sampleRate: ForkMeetingLookbackRing.sampleRate)
    private var microphoneMeter = ForkMeetingFrameMeter(sampleRate: ForkMeetingLookbackRing.sampleRate)
    private let appConverter = ForkMeetingMonoConverter()
    private let microphoneConverter = ForkMeetingMonoConverter()

    /// `onSecond` runs on the main thread.
    init(plan: ForkMeetingListenPlan, appPID: pid_t?, microphoneChoice: ForkMeetingMicrophoneChoice,
         meetingDevice: String?, lookback: ForkMeetingLookback?,
         makeTap: @escaping ForkMeetingRecorder.TapMaker = { await RecorderSystemAudioTap.make(hearing: $0) },
         onSecond: @escaping Second) {
        self.plan = plan
        self.appPID = appPID
        self.microphoneChoice = microphoneChoice
        self.meetingDevice = meetingDevice
        self.lookback = plan.keeps ? lookback : nil
        self.makeTap = makeTap
        self.onSecond = onSecond
    }

    func start() {
        queue.async { [self] in
            guard !running else { return }
            running = true
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(200))
            timer.setEventHandler { [weak self] in self?.second() }
            timer.resume()
            self.timer = timer
            if plan.microphone { startMicrophone() }
        }
        guard plan.app, let appPID else { return }
        Task { [self] in
            guard let tap = await makeTap(appPID) else { return }
            tap.onSample = { [weak self] sample in self?.appSample(sample) }
            let kept = queue.sync { () -> Bool in
                guard running else { return false }
                self.tap = tap
                return true
            }
            guard kept else { return await tap.stop() }
            if await tap.start(synchronizingTo: CMClockGetHostTimeClock()) == false {
                queue.async { [self] in if self.tap === tap { self.tap = nil } }
                await tap.stop()
            }
        }
    }

    /// Everything stops; the gates forget. The rings are the service's.
    func stop() {
        queue.async { [self] in
            guard running else { return }
            running = false
            timer?.cancel()
            timer = nil
            appGate.reset()
            microphoneGate.reset()
            if let tap {
                self.tap = nil
                Task { await tap.stop() }
            }
            microphone?.stop {}
            microphone = nil
        }
    }

    private func startMicrophone() {
        let microphone = ForkMeetingMicrophone(
            choice: microphoneChoice, meetingDevice: meetingDevice,
            callbacks: ForkMeetingMicrophone.Callbacks(
                samples: { [weak self] sample in self?.microphoneSample(sample) },
                switched: { _, _ in }, silent: {}, soundBack: {}))
        self.microphone = microphone
        microphone.start { _ in }
    }

    // MARK: - Samples

    /// The tap's audio thread: handed to the queue, read there, let go.
    private func appSample(_ sample: CMSampleBuffer) {
        let box = SampleBox(sample)
        queue.async { [self] in
            guard running, let converted = appConverter.convert(box.sample) else { return }
            converted.samples.withUnsafeBufferPointer { buffer in
                for frame in appMeter.take(buffer) { appGate.add(frame) }
                lookback?.app.append(buffer, startHost: converted.host)
            }
        }
    }

    private func microphoneSample(_ sample: CMSampleBuffer) {
        let box = SampleBox(sample)
        queue.async { [self] in
            guard running, let converted = microphoneConverter.convert(box.sample) else { return }
            converted.samples.withUnsafeBufferPointer { buffer in
                for frame in microphoneMeter.take(buffer) { microphoneGate.add(frame) }
                lookback?.microphone.append(buffer, startHost: converted.host)
            }
        }
    }

    private func second() {
        guard running else { return }
        let app = appGate.hearsSpeech, microphone = microphoneGate.hearsSpeech
        let deliver = onSecond
        DispatchQueue.main.async { deliver(app, microphone) }
    }

    private struct SampleBox: @unchecked Sendable {
        let sample: CMSampleBuffer
        init(_ sample: CMSampleBuffer) { self.sample = sample }
    }
}

/// Any PCM buffer as 16 kHz mono floats, with its host time. One per
/// source: the resampler's state carries across buffers, and a source that
/// changes its format gets a new one. Its queue only.
final class ForkMeetingMonoConverter {
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: ForkMeetingLookbackRing.sampleRate,
                                       channels: 1, interleaved: false)
    private var converter: AVAudioConverter?

    func convert(_ sample: CMSampleBuffer) -> (samples: [Float], host: Double)? {
        guard let target, CMSampleBufferIsValid(sample),
              let description = CMSampleBufferGetFormatDescription(sample),
              let stream = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              stream.mFormatID == kAudioFormatLinearPCM, stream.mSampleRate > 0 else { return nil }
        let presentation = CMSampleBufferGetPresentationTimeStamp(sample)
        guard presentation.isNumeric else { return nil }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let frames = CMSampleBufferGetNumSamples(sample)
        guard frames > 0, let count = AVAudioFrameCount(exactly: frames),
              let source = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else { return nil }
        source.frameLength = count
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames),
                                                           into: source.mutableAudioBufferList) == noErr else { return nil }
        if converter?.inputFormat != format {
            converter = AVAudioConverter(from: format, to: target)
            converter?.downmix = true
        }
        guard let converter else { return nil }
        let capacity = AVAudioFrameCount(Double(count) * target.sampleRate / format.sampleRate) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        let handed = Handed()
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            guard handed.first() else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            inputStatus.pointee = .haveData
            return source
        }
        guard status != .error, error == nil, let channel = output.floatChannelData?[0] else {
            self.converter = nil
            return nil
        }
        return (Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength))), presentation.seconds)
    }

    /// True the first time only.
    private final class Handed: @unchecked Sendable {
        private var done = false
        func first() -> Bool {
            defer { done = true }
            return !done
        }
    }
}
