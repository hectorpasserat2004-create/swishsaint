// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// What the final pass decides, apart from the AVFoundation that carries it
/// out (`ForkMeetingFinalizer`).
///
/// The master the writer leaves (`.recording.mp4`) holds the picture and the
/// two sources, the meeting's sound then the microphone, in that order. The
/// final file keeps all of it untouched and adds one track every player
/// plays:
///
/// ```
/// master  video · meeting · microphone
/// final   video (copied) · Mix (AAC, enabled) · meeting · microphone (copied, disabled, named)
/// ```
///
/// - The sources are told apart **by their order**: an `.mp4` drops the
///   content identifier of a track (spike S1), and order is what the writer
///   controls.
/// - The copy is written beside the master and replaces nothing until it is
///   verified; the master goes only after.
enum ForkMeetingFinalPass {
    enum Route: Equatable {
        /// The copy with the mixed track, written to a draft.
        case copy
        /// No room for the copy: the master itself becomes the final file,
        /// with its separate tracks (`finalPass: skipped-disk`).
        case promoteMaster
    }

    /// An unknown free space is neither enough nor too little: the copy is
    /// tried, on a draft that cannot harm the master, and a copy that then
    /// fails for want of room still falls back to the master.
    static func route(freeBytes: Int64?, masterBytes: Int64) -> Route {
        guard let freeBytes else { return .copy }
        return ForkMeetingDisk.finalPassFits(freeBytes: freeBytes, masterBytes: masterBytes) ? .copy : .promoteMaster
    }

    /// What a source track is, from its place among the master's audio
    /// tracks.
    enum SourceRole: Equatable {
        case meeting
        case microphone
        /// Beyond the two the writer makes: kept, never mixed.
        case extra
    }

    static func role(at index: Int) -> SourceRole {
        switch index {
        case 0: return .meeting
        case 1: return .microphone
        default: return .extra
        }
    }

    struct Layout: Equatable {
        /// Places, among the master's audio tracks, of the ones summed into
        /// the mix. Empty: a silent master, and no mix.
        var mixed: [Int]
        /// Every audio track of the master, copied after the mix, disabled.
        var copied: [SourceRole]

        var hasMix: Bool { !mixed.isEmpty }
    }

    /// The final file's audio for a master with `audioTracks` sources. One
    /// source (no microphone) still gets its mix, so every final file reads
    /// the same way: picture, mix, then the sources.
    static func layout(audioTracks: Int) -> Layout {
        let count = max(0, audioTracks)
        return Layout(mixed: Array(0..<min(count, 2)), copied: (0..<count).map(role(at:)))
    }

    /// Each source's volume in the mix. Two voices summed at full volume
    /// clip as soon as both speak loud; at 0.7 (−3 dB) each, two voices
    /// peaking at −3 dBFS at the same instant still fit, and a single voice
    /// loses little. Spike S1 measured no clipping either way: a value to
    /// confirm on real meetings.
    static func mixVolume(sources: Int) -> Float {
        sources > 1 ? 0.7 : 1
    }

    /// Whether a copy (or a promoted master) holds the whole meeting: it
    /// opens, and plays at least `ForkMeetingRecoveryPlan.completeShare` of
    /// the master. Only then may the master go.
    static func isWhole(seconds: Double?, masterSeconds: Double?) -> Bool {
        guard let seconds, seconds.isFinite, seconds > 0 else { return false }
        guard let masterSeconds, masterSeconds.isFinite, masterSeconds > 0 else { return true }
        return seconds >= masterSeconds * ForkMeetingRecoveryPlan.completeShare
    }

    /// The share of the progress the copy takes when an M4A follows: the
    /// M4A is a copy of one audio track, about a tenth of a second per hour.
    static let copyShare = 0.95

    /// The progress of a whole job, 0…1, for the pill's gauge.
    static func progress(copy: Double, audio: Double = 0, extractsAudio: Bool) -> Double {
        let copied = min(max(copy, 0), 1)
        guard extractsAudio else { return copied }
        return copied * copyShare + min(max(audio, 0), 1) * (1 - copyShare)
    }

    /// A step worth publishing: a whole percent more, or the end. The gauge
    /// needs no more, and the main thread gets a hundred updates per job
    /// rather than one per frame.
    static func shouldPublish(_ value: Double, last: Double?) -> Bool {
        guard let last else { return true }
        return value >= 1 ? last < 1 : value - last >= 0.01
    }
}

// MARK: Finish D

/// The minutes kept before the click, in the final pass. They never go into
/// the master: a fragmented file written in real time, whose fragments a
/// crash must find in order, cannot take minutes of sound in one burst. The
/// recording writes them beside it (`ForkMeetingFolder.lookbackName`), and
/// the final pass, or the recovery's, puts them first:
///
/// ```
/// kept     ┃ meeting ─────────────┃┄ e0
///          ┃ microphone ──────────┃┄┄┄ e1
/// master                          ┃ (silence until e0) meeting ──────…
///                                 ┃ (silence until e1) microphone ───…
/// final    ┃ kept sound ───────────── then the master's, from e0 / e1 ─…
///          ┃ (no picture)         ┃ picture ─────────────────────────…
///          0                      seconds (the click)
/// ```
///
/// Each track goes on past the click in the kept file until the
/// master's own sound for it begins (`joins`), so the click leaves no hole.
/// The picture starts at the click: before it, no frame at all, which
/// QuickTime and AVPlayer show black. Times in `meeting.json` already count
/// the kept minutes; when their file did not survive, the meeting begins at
/// the click instead (`ForkMeetingSidecar.withoutLookback`).
enum ForkMeetingLookbackJoin {
    enum Decision: Equatable {
        /// Nothing was kept.
        case none
        /// The kept file opens the final one.
        case join(seconds: Double, joins: [Double])
        /// Kept, but its file is not whole (the app ended before it was
        /// written, or it does not open): the meeting goes on without it.
        case drop
    }

    /// `fileTracks`: the sound tracks the kept file opens with, `nil` when
    /// it is missing or does not open.
    static func decide(_ sidecar: ForkMeetingSidecar?, fileTracks: Int?) -> Decision {
        guard let sidecar, let seconds = sidecar.lookbackSeconds else { return .none }
        guard let joins = sidecar.lookbackJoins, !joins.isEmpty,
              joins.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= ForkMeetingLookbackPlan.cutLimit + 1 }),
              let fileTracks, fileTracks >= joins.count else { return .drop }
        return .join(seconds: seconds, joins: joins)
    }

    /// The master made the meeting's final file after a final pass that
    /// failed (`ForkMeetingStore.revealMaster`, where it cannot be a second
    /// name): it holds nothing from before the click, so the meeting begins
    /// there, its times moved back. `nil` when nothing was kept.
    static func shownMaster(_ sidecar: ForkMeetingSidecar?) -> ForkMeetingSidecarPatch? {
        guard let sidecar, sidecar.lookbackSeconds != nil || sidecar.lookbackJoins != nil else { return nil }
        return ForkMeetingSidecarPatch(dropsLookback: true)
    }

    /// A final pass failed: only its last try (`interrupted`, after the
    /// recovery's) gives the kept minutes up for good; a pass that may still
    /// be tried again keeps them to join. `nil`: kept.
    static func givenUp(_ sidecar: ForkMeetingSidecar?) -> ForkMeetingSidecarPatch? {
        guard sidecar?.state == .interrupted else { return nil }
        return shownMaster(sidecar)
    }

    /// Where a piece of a track goes in the final file, in seconds.
    struct Piece: Equatable {
        enum Source: Equatable { case kept, master }
        var source: Source
        /// The range of the source taken.
        var from: Double
        var to: Double
        /// Where it starts in the final file.
        var at: Double
    }

    /// Source track `index`: the kept sound up to the click and past it by
    /// its join, then the master's from there. `keptLength` and
    /// `masterLength`: the tracks' own lengths, nothing taken beyond them.
    static func pieces(seconds: Double, join: Double, keptLength: Double, masterLength: Double) -> [Piece] {
        var pieces: [Piece] = []
        let keptEnd = min(seconds + join, keptLength)
        if keptEnd > 0 { pieces.append(Piece(source: .kept, from: 0, to: keptEnd, at: 0)) }
        if masterLength > join {
            pieces.append(Piece(source: .master, from: join, to: masterLength, at: seconds + join))
        }
        return pieces
    }
}
