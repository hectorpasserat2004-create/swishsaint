// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AVFoundation
import Foundation

/// Writes a meeting's sound as FLAC, mono, at the plan's rate
/// (`ForkCastralAudioPlan`): the mix read through `AVAssetReader`, which
/// resamples and folds to mono, then written by macOS's own FLAC encoder.
/// Streamed a buffer at a time: an hour of sound is never held in memory.
/// An hour takes about 2.4 s at 16 kHz on an M1, 1.4 s at 8 kHz (`w2-h`).
enum ForkCastralAudio {
    struct Written: Equatable {
        let url: URL
        let bytes: Int64
        let seconds: Double
    }

    enum Failure: Error {
        case unreadable
        case unwritable
    }

    /// `source`: an audio file AVFoundation reads (the meeting's M4A).
    static func write(_ source: URL, as format: ForkCastralAudioPlan.Format, to destination: URL) async throws -> Written {
        let asset = AVURLAsset(url: source)
        guard let tracks = try? await asset.loadTracks(withMediaType: .audio), !tracks.isEmpty,
              let reader = try? AVAssetReader(asset: asset) else { throw Failure.unreadable }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: format.sampleRate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: settings)
        guard reader.canAdd(output) else { throw Failure.unreadable }
        reader.add(output)
        try? FileManager.default.removeItem(at: destination)
        let frames = try encode(reader, output, format: format, to: destination)
        guard frames > 0 else { throw Failure.unreadable }
        let bytes = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard bytes > 0 else { throw Failure.unwritable }
        return Written(url: destination, bytes: bytes, seconds: Double(frames) / format.sampleRate)
    }

    /// The frames written. The FLAC file is closed when this returns (its
    /// `AVAudioFile` released): its size is then the final one.
    private static func encode(_ reader: AVAssetReader, _ output: AVAssetReaderAudioMixOutput,
                               format: ForkCastralAudioPlan.Format, to destination: URL) throws -> Int64 {
        guard let pcm = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: format.sampleRate, channels: 1,
                                      interleaved: true) else { throw Failure.unwritable }
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forWriting: destination,
                                   settings: [AVFormatIDKey: kAudioFormatFLAC, AVSampleRateKey: format.sampleRate,
                                              AVNumberOfChannelsKey: 1],
                                   commonFormat: .pcmFormatInt16, interleaved: true)
        } catch {
            throw Failure.unwritable
        }
        guard reader.startReading() else { throw Failure.unreadable }
        var frames: Int64 = 0
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let count = CMSampleBufferGetNumSamples(sample)
            guard count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: AVAudioFrameCount(count)),
                  let channel = buffer.int16ChannelData?[0] else { continue }
            let length = min(CMBlockBufferGetDataLength(block), count * 2)
            guard CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: channel) == kCMBlockBufferNoErr else {
                reader.cancelReading()
                throw Failure.unreadable
            }
            buffer.frameLength = AVAudioFrameCount(length / 2)
            do { try file.write(from: buffer) } catch {
                reader.cancelReading()
                throw Failure.unwritable
            }
            frames += Int64(buffer.frameLength)
        }
        // A reader that stopped early would leave a cut sound: refused.
        guard reader.status == .completed else { throw Failure.unreadable }
        return frames
    }
}
