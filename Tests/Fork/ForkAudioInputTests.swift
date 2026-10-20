// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AVFoundation
import CoreMedia
import Foundation

/// `ForkAudioInput`: any microphone or call sound as mono, never a crash
/// (build-2237 died on a built-in microphone sending three channels).
/// Synthetic buffers only: a known sine per channel, in every PCM layout.
enum ForkAudioInputTests {
    static func run(_ suite: TestSuite) {
        matrix(suite)
        resampled(suite)
        sameAsBefore(suite)
        refused(suite)
        switching(suite)
        brokenLists(suite)
    }

    // MARK: - Synthetic buffers

    enum Encoding: String, CaseIterable {
        case float32, int16, int16BigEndian, int24, int24InHigh32, int32, uint8

        var bytes: Int {
            switch self {
            case .uint8: 1
            case .int16, .int16BigEndian: 2
            case .int24: 3
            case .float32, .int24InHigh32, .int32: 4
            }
        }

        var bits: Int {
            switch self {
            case .uint8: 8
            case .int16, .int16BigEndian: 16
            case .int24, .int24InHigh32: 24
            case .float32, .int32: 32
            }
        }

        var flags: AudioFormatFlags {
            switch self {
            case .float32: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
            case .uint8: kAudioFormatFlagIsPacked
            case .int16BigEndian: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked | kAudioFormatFlagIsBigEndian
            case .int24InHigh32: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsAlignedHigh
            case .int16, .int24, .int32: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
            }
        }

        private func quantized(_ value: Double) -> Int64 {
            let scale = Double(Int64(1) << (bits - 1))
            return Int64((value * (scale - 1)).rounded())
        }

        /// What a perfect reader gets back from `value` written in this encoding.
        func decoded(_ value: Double) -> Float {
            switch self {
            case .float32: Float(value)
            case .uint8: Float(quantized(value)) / 128
            default: Float(quantized(value)) / Float(Int64(1) << (bits - 1))
            }
        }

        func write(_ value: Double, to pointer: UnsafeMutableRawPointer) {
            switch self {
            case .float32:
                pointer.storeBytes(of: Float(value).bitPattern.littleEndian, as: UInt32.self)
            case .uint8:
                pointer.storeBytes(of: UInt8(quantized(value) + 128), as: UInt8.self)
            case .int16:
                pointer.storeBytes(of: Int16(quantized(value)).littleEndian, as: Int16.self)
            case .int16BigEndian:
                pointer.storeBytes(of: Int16(quantized(value)).bigEndian, as: Int16.self)
            case .int24:
                let raw = UInt32(bitPattern: Int32(quantized(value)))
                for index in 0..<3 { pointer.storeBytes(of: UInt8(truncatingIfNeeded: raw >> (8 * index)),
                                                        toByteOffset: index, as: UInt8.self) }
            case .int24InHigh32:
                pointer.storeBytes(of: (Int32(quantized(value)) << 8).littleEndian, as: Int32.self)
            case .int32:
                pointer.storeBytes(of: Int32(quantized(value)).littleEndian, as: Int32.self)
            }
        }
    }

    /// Channel `channel` of a test stream: its own sine, its own loudness.
    static func signal(channel: Int, frame: Int, rate: Double) -> Double {
        let frequency = 220.0 * Double(channel + 1)
        return 0.9 / Double(channel + 1) * sin(2 * .pi * frequency * Double(frame) / rate)
    }

    static func stream(channels: Int, rate: Double, encoding: Encoding,
                       interleaved: Bool) -> AudioStreamBasicDescription {
        let frameBytes = UInt32(interleaved ? encoding.bytes * channels : encoding.bytes)
        return AudioStreamBasicDescription(
            mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: encoding.flags | (interleaved ? 0 : kAudioFormatFlagIsNonInterleaved),
            mBytesPerPacket: frameBytes, mFramesPerPacket: 1, mBytesPerFrame: frameBytes,
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: UInt32(encoding.bits), mReserved: 0)
    }

    static func description(_ stream: AudioStreamBasicDescription, layout: Bool) -> CMAudioFormatDescription? {
        var stream = stream
        let channels = stream.mChannelsPerFrame
        var channelLayout = AudioChannelLayout()
        channelLayout.mChannelLayoutTag = switch channels {
        case 1: kAudioChannelLayoutTag_Mono
        case 2: kAudioChannelLayoutTag_Stereo
        default: kAudioChannelLayoutTag_DiscreteInOrder | channels
        }
        var description: CMAudioFormatDescription?
        let status = withUnsafePointer(to: &channelLayout) { pointer in
            CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &stream,
                                           layoutSize: layout ? MemoryLayout<AudioChannelLayout>.size : 0,
                                           layout: layout ? pointer : nil, magicCookieSize: 0, magicCookie: nil,
                                           extensions: nil, formatDescriptionOut: &description)
        }
        return status == noErr ? description : nil
    }

    /// `frames` frames from `first` on, and the mono a reader should make of them.
    static func buffer(channels: Int, rate: Double = 48_000, encoding: Encoding, interleaved: Bool,
                       layout: Bool, frames: Int, first: Int = 0) -> (sample: CMSampleBuffer, mono: [Float])? {
        let stream = stream(channels: channels, rate: rate, encoding: encoding, interleaved: interleaved)
        guard let description = description(stream, layout: layout) else { return nil }
        let buffers = interleaved ? 1 : channels
        let size = frames * Int(stream.mBytesPerFrame)
        let list = AudioBufferList.allocate(maximumBuffers: buffers)
        var memory: [UnsafeMutableRawPointer] = []
        defer {
            memory.forEach { $0.deallocate() }
            free(list.unsafeMutablePointer)
        }
        for index in 0..<buffers {
            let data = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
            memory.append(data)
            list[index] = AudioBuffer(mNumberChannels: UInt32(interleaved ? channels : 1),
                                      mDataByteSize: UInt32(size), mData: data)
        }
        var mono = [Float](repeating: 0, count: frames)
        for channel in 0..<channels {
            for frame in 0..<frames {
                let value = signal(channel: channel, frame: first + frame, rate: rate)
                let offset = interleaved ? (frame * channels + channel) * encoding.bytes : frame * encoding.bytes
                encoding.write(value, to: memory[interleaved ? 0 : channel] + offset)
                mono[frame] += encoding.decoded(value)
            }
        }
        if channels > 1 {
            let scale = 1 / Float(channels)
            for frame in 0..<frames { mono[frame] *= scale }
        }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(rate)),
                                        presentationTimeStamp: CMTime(value: CMTimeValue(first),
                                                                      timescale: CMTimeScale(rate)),
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
                                   makeDataReadyCallback: nil, refcon: nil, formatDescription: description,
                                   sampleCount: frames, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                   sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample) == noErr,
              let sample,
              CMSampleBufferSetDataBufferFromAudioBufferList(sample, blockBufferAllocator: kCFAllocatorDefault,
                                                             blockBufferMemoryAllocator: kCFAllocatorDefault,
                                                             flags: 0, bufferList: list.unsafeMutablePointer) == noErr
        else { return nil }
        return (sample, mono)
    }

    /// The code before the fix, for one or two channels only (where it was
    /// safe): the reference that the new path must match sample for sample.
    final class OldPath {
        let target: AVAudioFormat
        let downmix: Bool
        var converter: AVAudioConverter?

        init(sampleRate: Double, downmix: Bool) {
            target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1,
                                   interleaved: false)!
            self.downmix = downmix
        }

        func convert(_ sample: CMSampleBuffer) -> [Float]? {
            guard let description = CMSampleBufferGetFormatDescription(sample) else { return nil }
            let format = AVAudioFormat(cmAudioFormatDescription: description)
            let frames = CMSampleBufferGetNumSamples(sample)
            guard let count = AVAudioFrameCount(exactly: frames),
                  let source = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else { return nil }
            source.frameLength = count
            guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames),
                                                               into: source.mutableAudioBufferList) == noErr
            else { return nil }
            if format == target, let channel = source.floatChannelData?[0] {
                return Array(UnsafeBufferPointer(start: channel, count: Int(count)))
            }
            if converter?.inputFormat != format {
                converter = AVAudioConverter(from: format, to: target)
                converter?.downmix = downmix
            }
            guard let converter,
                  let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(
                      Double(count) * target.sampleRate / format.sampleRate) + 64) else { return nil }
            var handed = false
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, inputStatus in
                guard !handed else {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                handed = true
                inputStatus.pointee = .haveData
                return source
            }
            guard status != .error, error == nil, let channel = output.floatChannelData?[0] else { return nil }
            return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
        }
    }

    static func maximumDifference(_ left: [Float], _ right: [Float]) -> Float {
        guard left.count == right.count else { return .infinity }
        return zip(left, right).reduce(0) { max($0, abs($1.0 - $1.1)) }
    }

    // MARK: - Cases

    /// Every channel count, encoding, interleaving and layout, at the
    /// writer's own rate: three channels or more come out as the exact
    /// average of their channels, one or two exactly as before the fix.
    private static func matrix(_ suite: TestSuite) {
        var built = 0, averaged = 0, matched = 0
        var failures: [String] = []
        for channels in [1, 2, 3, 4, 8] {
            for encoding in Encoding.allCases {
                for interleaved in [true, false] {
                    for layout in [true, false] {
                        let name = "\(channels) ch \(encoding.rawValue) \(interleaved ? "interleaved" : "planar") "
                            + (layout ? "with layout" : "without layout")
                        guard let made = buffer(channels: channels, encoding: encoding, interleaved: interleaved,
                                                layout: layout, frames: 480) else {
                            failures.append("\(name): test buffer not built")
                            continue
                        }
                        built += 1
                        let input = ForkAudioInputConverter(sampleRate: 48_000, downmix: true, category: "tests")!
                        guard let output = input.convert(made.sample) else {
                            failures.append("\(name): nothing out")
                            continue
                        }
                        guard output.count == 480 else {
                            failures.append("\(name): \(output.count) frames out of 480")
                            continue
                        }
                        if channels >= 3 {
                            let difference = maximumDifference(output, made.mono)
                            if difference <= 1e-6 { averaged += 1 } else {
                                failures.append("\(name): off the average of its channels by \(difference)")
                            }
                            if input.averagedChannels != channels {
                                failures.append("\(name): the mix down is not reported")
                            }
                        } else {
                            guard let before = OldPath(sampleRate: 48_000, downmix: true).convert(made.sample) else {
                                failures.append("\(name): the old path gives nothing")
                                continue
                            }
                            if output == before { matched += 1 } else {
                                failures.append("\(name): differs from before the fix by "
                                    + "\(maximumDifference(output, before))")
                            }
                            if channels == 1, maximumDifference(output, made.mono) > 1e-6 {
                                failures.append("\(name): mono is not its own samples")
                            }
                        }
                    }
                }
            }
        }
        suite.expect(failures.isEmpty, "every PCM layout reads: \(failures.prefix(8).joined(separator: "; "))")
        suite.expect(built == 5 * Encoding.allCases.count * 4, "all \(built) synthetic buffers are built")
        suite.expect(averaged == 3 * Encoding.allCases.count * 4,
                     "three, four and eight channels, in every encoding, become the average of their channels "
                        + "(\(averaged))")
        suite.expect(matched == 2 * Encoding.allCases.count * 4,
                     "one and two channels come out sample for sample as before the fix (\(matched))")
    }

    /// The dictation's 16 kHz and the call listener's: the crash's exact
    /// stream (three Float32 channels at 48 kHz, no layout) resampled like
    /// a mono microphone, frame count included.
    private static func resampled(_ suite: TestSuite) {
        for channels in [3, 4, 8] {
            let input = ForkAudioInputConverter(sampleRate: 16_000, downmix: false, category: "tests")!
            let reference = OldPath(sampleRate: 16_000, downmix: false)
            var output: [Float] = [], expected: [Float] = []
            var first = 0
            for _ in 0..<100 {
                // The reference: the averaged signal, fed as a mono stream.
                guard let made = buffer(channels: channels, encoding: .float32, interleaved: true, layout: false,
                                        frames: 480, first: first),
                      let mono = monoBuffer(made.mono) else { break }
                output += input.convert(made.sample) ?? []
                expected += reference.convert(mono) ?? []
                first += 480
            }
            suite.expect(abs(output.count - 16_000) <= 64,
                         "\(channels) channels at 48 kHz give 16 kHz: \(output.count) frames for 1 s")
            suite.expect(output == expected,
                         "\(channels) channels resample exactly like their average as a mono microphone "
                            + "(off by \(maximumDifference(output, expected)))")
        }
    }

    /// One and two channels, at 16 kHz (dictation, first channel kept; the
    /// call listener, mixed down) and in Int16: as before the fix, over a
    /// whole second, so the resampler's state carried across buffers too.
    private static func sameAsBefore(_ suite: TestSuite) {
        for channels in [1, 2] {
            for downmix in [false, true] {
                for encoding in [Encoding.float32, .int16] {
                    let input = ForkAudioInputConverter(sampleRate: 16_000, downmix: downmix, category: "tests")!
                    let reference = OldPath(sampleRate: 16_000, downmix: downmix)
                    var output: [Float] = [], expected: [Float] = []
                    for index in 0..<100 {
                        guard let made = buffer(channels: channels, encoding: encoding, interleaved: channels == 1,
                                                layout: true, frames: 441, first: index * 441) else { break }
                        output += input.convert(made.sample) ?? []
                        expected += reference.convert(made.sample) ?? []
                    }
                    suite.expect(!output.isEmpty && output == expected,
                                 "\(channels) ch \(encoding.rawValue) at 16 kHz, downmix \(downmix): as before the fix "
                                    + "(\(output.count) frames, off by \(maximumDifference(output, expected)))")
                }
            }
        }
    }

    /// Streams that cannot be read: dropped, reported once, never a crash.
    private static func refused(_ suite: TestSuite) {
        let good = stream(channels: 3, rate: 48_000, encoding: .float32, interleaved: true)
        func with(_ change: (inout AudioStreamBasicDescription) -> Void) -> AudioStreamBasicDescription {
            var copy = good
            change(&copy)
            return copy
        }
        let cases: [(String, AudioStreamBasicDescription, ForkAudioInput.Refusal)] = [
            ("0 Hz", with { $0.mSampleRate = 0 }, .badSampleRate),
            ("NaN Hz", with { $0.mSampleRate = .nan }, .badSampleRate),
            ("infinite Hz", with { $0.mSampleRate = .infinity }, .badSampleRate),
            ("0 channels", with { $0.mChannelsPerFrame = 0 }, .noChannels),
            ("65 channels", with { $0.mChannelsPerFrame = 65; $0.mBytesPerFrame = 260; $0.mBytesPerPacket = 260 },
             .tooManyChannels),
            ("AAC", with { $0.mFormatID = kAudioFormatMPEG4AAC }, .notPCM),
            ("bytes per frame not a multiple of channels", with { $0.mBytesPerFrame = 10; $0.mBytesPerPacket = 10 },
             .badSize),
            ("0 bytes per frame", with { $0.mBytesPerFrame = 0; $0.mBytesPerPacket = 0 }, .badSize),
            ("absurd bytes per frame", with { $0.mBytesPerFrame = 3_000_000; $0.mBytesPerPacket = 3_000_000 },
             .badSize),
            ("16-bit float", with { $0.mBitsPerChannel = 16 }, .unsupportedSamples),
            ("more bits than bytes", with { $0.mBitsPerChannel = 40 }, .unsupportedSamples),
            ("fixed point", with { $0.mFormatFlags = kAudioFormatFlagIsSignedInteger | (24 << 7) }, .unsupportedSamples),
        ]
        var throughBuffers = 0
        for (name, stream, expected) in cases {
            suite.expect(ForkAudioInput.Layout.make(stream) == .failure(expected), "\(name) is refused as \(expected)")
            // Through a real buffer too, when Core Media builds one.
            guard let description = description(stream, layout: false) else { continue }
            var block: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: 4_096,
                                               blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
                                               offsetToData: 0, dataLength: 4_096,
                                               flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
            var sample: CMSampleBuffer?
            var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
            var size = 4
            CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: block, dataReady: true,
                                 makeDataReadyCallback: nil, refcon: nil, formatDescription: description,
                                 sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                 sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
            guard let sample else { continue }
            throughBuffers += 1
            let input = ForkAudioInputConverter(sampleRate: 16_000, downmix: false, category: "tests")!
            suite.expect(input.convert(sample) == nil && input.convert(sample) == nil && input.refusal == expected,
                         "a buffer of \(name) is dropped, twice, and reported as \(expected)")
        }

        print("    (\(throughBuffers) of \(cases.count) refused streams also fed as real sample buffers)")

        var video: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: kCMVideoCodecType_H264,
                                       width: 16, height: 16, extensions: nil, formatDescriptionOut: &video)
        var sample: CMSampleBuffer?
        if let video {
            CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: true,
                                 makeDataReadyCallback: nil, refcon: nil, formatDescription: video, sampleCount: 1,
                                 sampleTimingEntryCount: 0, sampleTimingArray: nil, sampleSizeEntryCount: 0,
                                 sampleSizeArray: nil, sampleBufferOut: &sample)
        }
        let input = ForkAudioInputConverter(sampleRate: 48_000, downmix: true, category: "tests")!
        suite.expect(sample != nil && input.convert(sample!) == nil && input.refusal == .notAudio,
                     "a picture handed as sound is dropped")
    }

    /// A device switch mid-stream: three channels, then one, then four.
    private static func switching(_ suite: TestSuite) {
        let input = ForkAudioInputConverter(sampleRate: 16_000, downmix: true, category: "tests")!
        var counts: [Int] = []
        for (index, channels) in [3, 3, 1, 1, 4, 4, 2, 3].enumerated() {
            guard let made = buffer(channels: channels, encoding: .int16, interleaved: index % 2 == 0,
                                    layout: index % 3 == 0, frames: 4_800, first: index * 4_800) else { continue }
            counts.append(input.convert(made.sample)?.count ?? -1)
        }
        // 1 600 frames each, less the resampler's lead-in when a new
        // converter starts (a new format, or the first buffer).
        suite.expect(counts.count == 8 && counts.allSatisfy { (1_300...1_664).contains($0) },
                     "a source switching between 1, 2, 3 and 4 channels keeps flowing: \(counts)")
    }

    /// A buffer list that does not hold what its layout says.
    private static func brokenLists(_ suite: TestSuite) {
        guard case .success(let layout) = ForkAudioInput.Layout.make(
            stream(channels: 3, rate: 48_000, encoding: .int24, interleaved: false)) else {
            return suite.expect(false, "3-channel planar Int24 is a layout")
        }
        let list = AudioBufferList.allocate(maximumBuffers: 3)
        let data = UnsafeMutableRawPointer.allocate(byteCount: 300, alignment: 16)
        defer {
            data.deallocate()
            free(list.unsafeMutablePointer)
        }
        for index in 0..<3 { list[index] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 300, mData: data) }
        suite.expect(ForkAudioInput.mono(list, frames: 100, layout: layout)?.count == 100, "a full list reads")
        suite.expect(ForkAudioInput.mono(list, frames: 101, layout: layout) == nil, "a short buffer is not read past")
        list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 300, mData: nil)
        suite.expect(ForkAudioInput.mono(list, frames: 100, layout: layout) == nil, "a missing buffer is not read")
        suite.expect(ForkAudioInput.mono(list, frames: 0, layout: layout) == nil
                        && ForkAudioInput.mono(list, frames: ForkAudioInput.maximumFrames + 1, layout: layout) == nil,
                     "no frames, or absurdly many, read nothing")
        guard case .success(let interleaved) = ForkAudioInput.Layout.make(
            stream(channels: 3, rate: 48_000, encoding: .int24, interleaved: true)) else { return }
        suite.expect(ForkAudioInput.mono(list, frames: 10, layout: interleaved) == nil,
                     "three buffers where one interleaved is expected are not read")
    }
    /// 48 kHz mono Float32 samples as a ready sample buffer.
    static func monoBuffer(_ samples: [Float]) -> CMSampleBuffer? {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1,
                                         interleaved: false),
              let count = AVAudioFrameCount(exactly: samples.count),
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
              let channel = pcm.floatChannelData?[0] else { return nil }
        pcm.frameLength = count
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress { channel.update(from: base, count: source.count) }
        }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000), presentationTimeStamp: .zero,
                                        decodeTimeStamp: .invalid)
        var buffer: CMSampleBuffer?
        guard CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
                                   makeDataReadyCallback: nil, refcon: nil, formatDescription: format.formatDescription,
                                   sampleCount: samples.count, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                   sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &buffer) == noErr,
              let buffer,
              CMSampleBufferSetDataBufferFromAudioBufferList(buffer, blockBufferAllocator: kCFAllocatorDefault,
                                                             blockBufferMemoryAllocator: kCFAllocatorDefault,
                                                             flags: 0, bufferList: pcm.audioBufferList) == noErr
        else { return nil }
        return buffer
    }
}
