// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The sound a CRM receives: FLAC, mono, from the meeting's mix (D6).
///
/// The contract's speech engine takes FLAC up to five hours, while a long
/// AAC fails past about twenty minutes, and macOS writes FLAC itself (no MP3
/// encoder without a library in C). FLAC is lossless, so its size follows
/// the sound: measured on an hour of two-voice speech (`w2-h` recipe), 55 to
/// 65 MB at 16 kHz and 29 to 35 MB at 8 kHz, the higher with a room's noise
/// and echo. The server's storage takes 50 MB today:
///
/// - **16 kHz** when the file fits (about 45 minutes at most);
/// - else **8 kHz**, still what the engine reads speech at (about 1 h 25);
/// - else refused, saying how long a meeting the server takes, **before**
///   anything is opened on the server.
///
/// Each file is measured once written, never estimated only: the estimate
/// just spares encoding a size that cannot fit.
enum ForkCastralAudioPlan {
    enum Format: String, CaseIterable, Equatable {
        case flac16k
        case flac8k

        var sampleRate: Double { self == .flac16k ? 16_000 : 8_000 }
        var kilohertz: Int { self == .flac16k ? 16 : 8 }
        static let mimeType = "audio/flac"
        static let fileExtension = "flac"
    }

    /// An hour of speech with a room's noise, as measured.
    static func typicalBytesPerHour(_ format: Format) -> Double {
        format == .flac16k ? 65_500_000 : 35_100_000
    }

    /// The leanest hour measured (clean speech), less a margin: a meeting
    /// whose estimate at this rate does not fit cannot fit at all.
    static func leanestBytesPerHour(_ format: Format) -> Double {
        format == .flac16k ? 50_000_000 : 26_000_000
    }

    enum Step: Equatable {
        case encode(Format)
        case send
        /// No format fits: the longest meeting the server takes, in
        /// minutes, as a typical meeting at 8 kHz.
        case tooLong(maximumMinutes: Int)
    }

    /// The first format to write for a meeting of `seconds`.
    static func first(seconds: Double, limit: Int64) -> Step {
        for format in Format.allCases where estimate(seconds, format, leanest: true) <= Double(limit) {
            return .encode(format)
        }
        return .tooLong(maximumMinutes: maximumMinutes(limit: limit))
    }

    /// After writing `format`: send it, write the next, or refuse.
    static func next(after format: Format, bytes: Int64, seconds: Double, limit: Int64) -> Step {
        if bytes > 0, bytes <= limit { return .send }
        if format == .flac16k, estimate(seconds, .flac8k, leanest: true) <= Double(limit) { return .encode(.flac8k) }
        return .tooLong(maximumMinutes: maximumMinutes(limit: limit))
    }

    /// The longest typical meeting under `limit` in `format`, rounded down
    /// to five minutes: at 8 kHz "about 1 h 25" for 50 MB; at 16 kHz, the
    /// length past which 8 kHz goes ("about 45 min").
    static func maximumMinutes(limit: Int64, format: Format = .flac8k) -> Int {
        let minutes = Double(limit) / typicalBytesPerHour(format) * 60
        return max(5, Int(minutes / 5) * 5)
    }

    private static func estimate(_ seconds: Double, _ format: Format, leanest: Bool) -> Double {
        let perHour = leanest ? leanestBytesPerHour(format) : typicalBytesPerHour(format)
        return max(0, seconds) / 3600 * perHour
    }
}
