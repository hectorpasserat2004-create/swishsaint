// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AVFoundation
import CoreMedia
import os

/// Any sound a capture hands us, as mono Float32, without ever crashing.
///
/// `AVAudioFormat(cmAudioFormatDescription:)` is imported as never failing,
/// yet returns nil for a PCM stream of three channels or more that carries
/// no channel layout, and `AVAudioConverter(from:to:)` then dereferences
/// that nil: build-2237 died there on a MacBook whose built-in microphone
/// array sent three channels. So nothing here calls it, nor any other
/// initializer imported as non-failable:
/// - every stream description is checked first (`Layout.make`); one that
///   cannot be read is refused, and its buffer dropped;
/// - one or two channels keep the path they always had: an `AVAudioFormat`
///   from the failable `init?(streamDescription:channelLayout:)`, and the
///   converter does the rest (resampling, and mixing down when asked);
/// - three channels or more are read here and made mono at their own rate
///   (averaged for a meeting, the loudest kept for dictation: `Mix`), and
///   only that mono goes to a converter, built from formats known to exist.
///   A sample that is not a number (NaN, infinite) is read as silence.
enum ForkAudioInput {
    static let maximumChannels = 64
    /// A rate outside this range is not a microphone or a call: refused.
    static let sampleRates: ClosedRange<Double> = 1_000...1_000_000
    /// About 87 s at 48 kHz in one buffer: anything bigger is a broken buffer.
    static let maximumFrames = 1 << 22

    /// How a stream of three channels or more becomes one.
    enum Mix: Equatable {
        /// Their average: everyone the array hears, as a meeting records it.
        case average
        /// The loudest over the buffer (RMS), as is: a microphone array whose
        /// other channels hear the room, or nothing, would otherwise thin out
        /// the one voice dictation transcribes.
        case loudest
    }

    enum Refusal: String, Error, Equatable {
        case notAudio
        case notPCM
        case noChannels
        case tooManyChannels
        case badSampleRate
        case unsupportedSamples
        case badSize
    }

    /// How a PCM stream lays its samples out, checked.
    struct Layout: Equatable {
        enum Kind: Equatable {
            case float
            case signedInteger
            case unsignedInteger
        }

        let kind: Kind
        /// Significant bits of one sample.
        let bits: Int
        /// Bytes holding one sample (3 for packed 24-bit, 4 for 24 in 32).
        let bytes: Int
        let channels: Int
        let interleaved: Bool
        let bigEndian: Bool
        /// In a container wider than its bits, the sample sits in the high bits.
        let alignedHigh: Bool
        let sampleRate: Double

        /// Bytes from one frame to the next, within one buffer.
        var stride: Int { interleaved ? bytes * channels : bytes }
        /// Buffers of a buffer list in this layout.
        var bufferCount: Int { interleaved ? 1 : channels }

        static func make(_ stream: AudioStreamBasicDescription) -> Result<Layout, Refusal> {
            guard stream.mFormatID == kAudioFormatLinearPCM else { return .failure(.notPCM) }
            guard stream.mSampleRate.isFinite, ForkAudioInput.sampleRates.contains(stream.mSampleRate) else {
                return .failure(.badSampleRate)
            }
            guard stream.mChannelsPerFrame > 0 else { return .failure(.noChannels) }
            guard stream.mChannelsPerFrame <= UInt32(ForkAudioInput.maximumChannels) else {
                return .failure(.tooManyChannels)
            }
            let flags = stream.mFormatFlags
            let channels = Int(stream.mChannelsPerFrame)
            let interleaved = flags & kAudioFormatFlagIsNonInterleaved == 0
            let frameBytes = Int(stream.mBytesPerFrame)
            guard stream.mFramesPerPacket == 1, stream.mBytesPerPacket == stream.mBytesPerFrame, frameBytes > 0
            else { return .failure(.badSize) }
            let bytes = interleaved ? frameBytes / channels : frameBytes
            guard !interleaved || bytes * channels == frameBytes, (1...8).contains(bytes) else {
                return .failure(.badSize)
            }
            let bits = Int(stream.mBitsPerChannel)
            guard bits > 0, bits <= bytes * 8, flags & kLinearPCMFormatFlagsSampleFractionMask == 0 else {
                return .failure(.unsupportedSamples)
            }
            let kind: Kind
            if flags & kAudioFormatFlagIsFloat != 0 {
                guard (bits == 32 && bytes == 4) || (bits == 64 && bytes == 8) else {
                    return .failure(.unsupportedSamples)
                }
                kind = .float
            } else if flags & kAudioFormatFlagIsSignedInteger != 0 {
                guard bytes <= 4 else { return .failure(.unsupportedSamples) }
                kind = .signedInteger
            } else {
                guard bits == 8, bytes == 1 else { return .failure(.unsupportedSamples) }
                kind = .unsignedInteger
            }
            return .success(Layout(kind: kind, bits: bits, bytes: bytes, channels: channels, interleaved: interleaved,
                                   bigEndian: flags & kAudioFormatFlagIsBigEndian != 0,
                                   alignedHigh: flags & kAudioFormatFlagIsAlignedHigh != 0,
                                   sampleRate: stream.mSampleRate))
        }

        /// One sample at `pointer`, as a float in -1…1.
        func value(at pointer: UnsafeRawPointer) -> Float {
            switch kind {
            case .float:
                if bytes == 4 {
                    let raw = pointer.loadUnaligned(as: UInt32.self)
                    return Float(bitPattern: bigEndian ? raw.byteSwapped : raw)
                }
                let raw = pointer.loadUnaligned(as: UInt64.self)
                return Float(Double(bitPattern: bigEndian ? raw.byteSwapped : raw))
            case .unsignedInteger:
                return (Float(pointer.load(as: UInt8.self)) - 128) / 128
            case .signedInteger:
                // The container, most significant byte first.
                var raw: UInt32 = 0
                for index in 0..<bytes {
                    let byte = pointer.load(fromByteOffset: bigEndian ? index : bytes - 1 - index, as: UInt8.self)
                    raw = raw << 8 | UInt32(byte)
                }
                // The sample's bits moved to the top, then shifted back down
                // with their sign.
                let containerBits = bytes * 8
                let top = alignedHigh || bits == containerBits ? raw << (32 - containerBits) : raw << (32 - bits)
                let value = Int32(bitPattern: top) >> (32 - bits)
                return Float(value) / Float(1 << (bits - 1))
            }
        }
    }

    /// The frames of `list`, in `layout`, made one channel by `mix`; a
    /// sample that is not a number counts as silence. Nil when the list does
    /// not hold them all.
    static func mono(_ list: UnsafeMutableAudioBufferListPointer, frames: Int, layout: Layout,
                     mix: Mix = .average) -> [Float]? {
        guard frames > 0, frames <= maximumFrames, list.count == layout.bufferCount else { return nil }
        let (needed, overflow) = frames.multipliedReportingOverflow(by: layout.stride)
        guard !overflow else { return nil }
        var bases: [UnsafeRawPointer] = []
        for buffer in list {
            guard let data = buffer.mData, Int(buffer.mDataByteSize) >= needed else { return nil }
            bases.append(UnsafeRawPointer(data))
        }
        var mixed = [Float](repeating: 0, count: frames)
        let stride = layout.stride
        func base(_ channel: Int) -> UnsafeRawPointer {
            layout.interleaved ? bases[0] + channel * layout.bytes : bases[channel]
        }
        /// A sample that is not a number reads as silence.
        func sample(_ base: UnsafeRawPointer, _ frame: Int) -> Float {
            let value = layout.value(at: base + frame * stride)
            return value.isFinite ? value : 0
        }
        if mix == .loudest, layout.channels > 1 {
            var loudest = 0
            var loudestEnergy = -1.0
            for channel in 0..<layout.channels {
                let channelBase = base(channel)
                var energy = 0.0
                for frame in 0..<frames {
                    let value = Double(sample(channelBase, frame))
                    energy += value * value
                }
                // The first of equally loud channels wins.
                if energy > loudestEnergy {
                    loudest = channel
                    loudestEnergy = energy
                }
            }
            let loudestBase = base(loudest)
            mixed.withUnsafeMutableBufferPointer { mixed in
                for frame in 0..<frames { mixed[frame] = sample(loudestBase, frame) }
            }
            return mixed
        }
        mixed.withUnsafeMutableBufferPointer { mixed in
            for channel in 0..<layout.channels {
                let channelBase = base(channel)
                for frame in 0..<frames {
                    mixed[frame] += sample(channelBase, frame)
                }
            }
            if layout.channels > 1 {
                let scale = 1 / Float(layout.channels)
                for frame in 0..<frames { mixed[frame] *= scale }
            }
        }
        return mixed
    }

    /// The PCM of `sample` copied out and made one channel by `mix`.
    static func mono(of sample: CMSampleBuffer, frames: Int, layout: Layout, mix: Mix = .average) -> [Float]? {
        guard frames > 0, frames <= maximumFrames, let frameCount = Int32(exactly: frames) else { return nil }
        let (size, overflow) = frames.multipliedReportingOverflow(by: layout.stride)
        guard !overflow, let byteSize = UInt32(exactly: size) else { return nil }
        let list = AudioBufferList.allocate(maximumBuffers: layout.bufferCount)
        var memory: [UnsafeMutableRawPointer] = []
        defer {
            memory.forEach { $0.deallocate() }
            free(list.unsafeMutablePointer)
        }
        for index in 0..<layout.bufferCount {
            let data = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
            memory.append(data)
            list[index] = AudioBuffer(mNumberChannels: UInt32(layout.interleaved ? layout.channels : 1),
                                      mDataByteSize: byteSize, mData: data)
        }
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: frameCount,
                                                           into: list.unsafeMutablePointer) == noErr
        else { return nil }
        return mono(list, frames: frames, layout: layout, mix: mix)
    }

    /// The format of a one- or two-channel stream, through the failable
    /// initializer. A layout is kept only when it is a plain tag of the
    /// stream's channel count, nil otherwise (the default for one or two).
    static func format(_ stream: AudioStreamBasicDescription, description: CMAudioFormatDescription) -> AVAudioFormat? {
        guard stream.mChannelsPerFrame >= 1, stream.mChannelsPerFrame <= 2 else { return nil }
        var stream = stream
        var layout: AVAudioChannelLayout?
        if let pointer = CMAudioFormatDescriptionGetChannelLayout(description, sizeOut: nil) {
            let tag = pointer.pointee.mChannelLayoutTag
            if tag != kAudioChannelLayoutTag_UseChannelDescriptions, tag != kAudioChannelLayoutTag_UseChannelBitmap,
               tag & 0xFFFF == stream.mChannelsPerFrame {
                layout = AVAudioChannelLayout(layoutTag: tag)
            }
        }
        return AVAudioFormat(streamDescription: &stream, channelLayout: layout)
    }
}

/// One source's sound as mono Float32 at `target`'s rate. Keeps its
/// converter across buffers (the resampler's state carries over) and builds
/// a new one when the source changes format. Its caller's queue only.
final class ForkAudioInputConverter {
    let target: AVAudioFormat
    /// Two channels mixed down (a stereo call can put a voice on one side
    /// only) rather than the first one kept. Three or more are always mixed.
    private let downmix: Bool
    /// Three channels or more: averaged, or the loudest kept.
    private let manyChannels: ForkAudioInput.Mix
    private let log: Logger
    private var converter: AVAudioConverter?
    /// For the log, once per converter: a refused stream, a mixed-down one.
    private(set) var refusal: ForkAudioInput.Refusal?
    private(set) var averagedChannels: Int?

    init?(sampleRate: Double, downmix: Bool, manyChannels: ForkAudioInput.Mix = .average, category: String) {
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1,
                                         interleaved: false) else { return nil }
        self.target = target
        self.downmix = downmix
        self.manyChannels = manyChannels
        log = Logger(subsystem: "fork.audio", category: category)
    }

    /// The next buffer starts a new stream.
    func reset() {
        converter = nil
    }

    /// Nil for a buffer that cannot be read: it is dropped, never fatal.
    func convert(_ sample: CMSampleBuffer) -> [Float]? {
        guard let description = CMSampleBufferGetFormatDescription(sample),
              CMFormatDescriptionGetMediaType(description) == kCMMediaType_Audio,
              let stream = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee
        else { return refuse(.notAudio, nil) }
        let layout: ForkAudioInput.Layout
        switch ForkAudioInput.Layout.make(stream) {
        case .success(let made): layout = made
        case .failure(let refusal): return refuse(refusal, stream)
        }
        let frames = CMSampleBufferGetNumSamples(sample)
        guard frames > 0 else { return nil }
        guard frames <= ForkAudioInput.maximumFrames, let count = AVAudioFrameCount(exactly: frames) else {
            return refuse(.badSize, stream)
        }
        if layout.channels <= 2, let format = ForkAudioInput.format(stream, description: description) {
            guard let source = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else { return nil }
            source.frameLength = count
            guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames),
                                                               into: source.mutableAudioBufferList) == noErr
            else { return nil }
            if format == target, let channel = source.floatChannelData?[0] {
                return Array(UnsafeBufferPointer(start: channel, count: Int(source.frameLength)))
            }
            return run(source)
        }
        guard let mono = ForkAudioInput.mono(of: sample, frames: frames, layout: layout, mix: manyChannels)
        else { return nil }
        if averagedChannels == nil {
            averagedChannels = layout.channels
            let channels = layout.channels, rate = layout.sampleRate
            let how = manyChannels == .loudest ? "loudest kept" : "averaged"
            log.notice("Made mono (\(how, privacy: .public)): \(channels, privacy: .public) channels at \(rate, privacy: .public) Hz")
        }
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: layout.sampleRate, channels: 1,
                                         interleaved: false) else { return nil }
        if format == target { return mono }
        guard let source = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
              let channel = source.floatChannelData?[0] else { return nil }
        mono.withUnsafeBufferPointer { mono in
            guard let base = mono.baseAddress else { return }
            channel.update(from: base, count: mono.count)
        }
        source.frameLength = count
        return run(source)
    }

    /// `source` through the converter for its format, built if needed.
    private func run(_ source: AVAudioPCMBuffer) -> [Float]? {
        let format = source.format
        if converter?.inputFormat != format {
            converter = AVAudioConverter(from: format, to: target)
            converter?.downmix = downmix
        }
        guard let converter else { return nil }
        let wanted = Double(source.frameLength) * target.sampleRate / format.sampleRate
        // Bounded: a pathological buffer must not ask for gigabytes.
        guard wanted.isFinite, wanted >= 0, wanted < Double(4 * ForkAudioInput.maximumFrames),
              let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(wanted) + 64)
        else { return nil }
        let handedOver = Latch()
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            guard handedOver.close() else {
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
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }

    private func refuse(_ refusal: ForkAudioInput.Refusal, _ stream: AudioStreamBasicDescription?) -> [Float]? {
        if self.refusal == nil {
            self.refusal = refusal
            let channels = stream.map { Int($0.mChannelsPerFrame) } ?? 0
            let rate = stream?.mSampleRate ?? 0
            let reason = refusal.rawValue
            log.error("Refused (\(reason, privacy: .public)): \(channels, privacy: .public) ch at \(rate, privacy: .public) Hz")
        }
        return nil
    }

    /// Single use: the first `close` returns true, the next ones false.
    private final class Latch: @unchecked Sendable {
        private var isOpen = true
        func close() -> Bool {
            defer { isOpen = false }
            return isOpen
        }
    }
}
