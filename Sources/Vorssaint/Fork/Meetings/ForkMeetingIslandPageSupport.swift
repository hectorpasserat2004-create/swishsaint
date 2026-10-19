// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The island's Meetings page decided from facts, apart from its views, so
/// each case is tested: what its top shows, which meetings it lists and
/// how each row says where its meeting is (recorded, transcribed,
/// summarized, exported, or what went wrong).
enum ForkMeetingIslandPage {
    /// What the top of the page shows.
    enum Top: Equatable {
        /// A recording, running, paused or being finished: its live card.
        case live
        /// A start asked for, before its first frame: it can be cancelled.
        case starting
        /// A call the detection sees and nothing records: one click records it.
        case detected
        /// Nothing at all: the button that records a meeting.
        case idle
    }

    /// The recording comes first, whatever else is true: it is what the
    /// person must see. A call seen while the feature cannot start (a
    /// meeting still starting, the app quitting) is not offered.
    static func top(recording: Bool, starting: Bool, detected: Bool, canStart: Bool) -> Top {
        if recording { return .live }
        if starting { return .starting }
        if detected && canStart { return .detected }
        return .idle
    }

    /// The meetings in the window's order, newest first, without the one
    /// the live card above already shows.
    static func rows(_ ordered: [ForkMeetingLibraryEntry], showsLive: Bool) -> [ForkMeetingLibraryEntry] {
        // A meeting finishing is the live card's too until it is saved.
        ordered.filter { !(showsLive && $0.status.isInProgress) }
    }

    /// A change the folder watch saw, for the island's page: the folders
    /// this app is still writing are left out (a recording writes every
    /// 2 s), and nothing is scanned when only they changed. A change of the
    /// whole folder is scanned. `writing` holds standardized paths.
    static func rescan(_ rescan: ForkMeetingLibrary.Rescan, root: URL,
                       writing: Set<String>) -> ForkMeetingLibrary.Rescan? {
        guard case let .folders(names) = rescan else { return rescan }
        let kept = names.filter { name in
            !writing.contains(root.appendingPathComponent(name, isDirectory: true).standardizedFileURL.path)
        }
        return kept.isEmpty ? nil : .folders(kept)
    }

    /// What a row says of its meeting, in this order, after its date and
    /// length.
    enum Badge: Equatable {
        /// Being recorded (the live card is not up, or is about another).
        case recording
        /// Its final pass runs.
        case finishing
        /// Recovered, interrupted or unreadable: the row says why in orange.
        case flagged
        /// Its transcript runs: the share done.
        case transcribing(Double)
        case transcriptQueued
        case transcript
        case summarizing
        case summary
        case sending
        case exported
        case exportFailed
    }

    /// The badges of one meeting. A meeting still written has nothing else
    /// to say: its transcript, summary and exports come once it is saved.
    static func badges(_ entry: ForkMeetingLibraryEntry, transcribing: Double?, transcriptQueued: Bool,
                       summarizing: Bool, sending: Bool,
                       exportMark: ForkMeetingExportHistory.Mark?) -> [Badge] {
        switch entry.status {
        case .recording: return [.recording]
        case .finalizing: return [.finishing]
        case .complete, .recovered, .interrupted, .unreadable: break
        }
        var badges: [Badge] = entry.status.isFlagged ? [.flagged] : []
        if let transcribing {
            badges.append(.transcribing(transcribing.isFinite ? min(1, max(0, transcribing)) : 0))
        } else if transcriptQueued {
            badges.append(.transcriptQueued)
        } else if entry.transcript != nil {
            badges.append(.transcript)
        }
        if summarizing {
            badges.append(.summarizing)
        } else if hasSummary(entry) {
            badges.append(.summary)
        }
        if sending {
            badges.append(.sending)
        } else {
            switch exportMark {
            case .done?: badges.append(.exported)
            case .failed?: badges.append(.exportFailed)
            case nil: break
            }
        }
        return badges
    }

    /// A summary this app wrote and still knows the file of.
    static func hasSummary(_ entry: ForkMeetingLibraryEntry) -> Bool {
        guard let record = entry.summaryRecord else { return false }
        return record.state == .done && !record.files.isEmpty
    }

    /// The summary's file, when there is one.
    static func summaryFile(_ entry: ForkMeetingLibraryEntry) -> String? {
        hasSummary(entry) ? entry.summaryRecord?.files.first : nil
    }

    /// One file of a meeting, as the open row lists it.
    struct File: Equatable {
        enum Kind: Equatable { case video, audio, transcript, subtitles, summary }
        let kind: Kind
        let name: String
    }

    /// What the meeting's folder holds that the person may open: its
    /// picture (or its sound alone), the sound beside the picture, the
    /// transcript and its subtitles, the summary.
    static func files(_ entry: ForkMeetingLibraryEntry) -> [File] {
        var files: [File] = []
        if let video = entry.video, !entry.isAudioOnly { files.append(File(kind: .video, name: video)) }
        if let audio = entry.audio { files.append(File(kind: .audio, name: audio)) }
        if entry.isAudioOnly, let playable = entry.playable { files.append(File(kind: .audio, name: playable)) }
        if let transcript = entry.transcript { files.append(File(kind: .transcript, name: transcript)) }
        if let subtitles = entry.subtitles { files.append(File(kind: .subtitles, name: subtitles)) }
        if let summary = summaryFile(entry) { files.append(File(kind: .summary, name: summary)) }
        return files
    }

    /// The first words of a transcript, as the open row shows them: its
    /// first paragraphs without their times ("Me: Hello everyone…"), the
    /// marked moments left out, cut at a word within `limit` characters.
    static func excerpt(_ transcript: String, paragraphs: Int = 3, limit: Int = 240) -> String {
        var kept: [String] = []
        for line in transcript.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("★") else { continue }
            kept.append(withoutTime(trimmed))
            if kept.count == paragraphs { break }
        }
        let joined = kept.joined(separator: "\n")
        guard joined.count > limit else { return joined }
        let cut = joined.prefix(limit)
        let end = cut.lastIndex(where: { $0 == " " || $0 == "\n" }) ?? cut.endIndex
        return String(cut[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    /// "[00:12:03] Me: …" reads "Me: …".
    private static func withoutTime(_ line: String) -> String {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return line }
        let stamp = line[line.index(after: line.startIndex)..<close]
        guard !stamp.isEmpty, stamp.allSatisfy({ $0.isNumber || $0 == ":" }) else { return line }
        return line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
    }

    /// A call detected, named as the person knows it: the calendar's event,
    /// else the meeting's own name, else its service; under it the service
    /// when the name is another.
    static func detectedName(_ candidate: ForkMeetingCandidate) -> (title: String, service: String?) {
        let names = [candidate.calendarTitle, candidate.titleName].compactMap { name -> String? in
            let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        guard let title = names.first, title != candidate.providerName else { return (candidate.providerName, nil) }
        return (title, candidate.providerName)
    }

    /// How long the island waits before it reads a new still of what is
    /// filmed: once a second, and only while the page shows it.
    static let previewInterval: TimeInterval = 1
    /// The still's longer side, in pixels: a quarter of a 1080p frame is
    /// sharp at the card's size on a Retina display, and light to keep.
    static let previewPixels = 480

    /// The still's size for a frame of `width` × `height`: the longer side
    /// at most `previewPixels`, never larger than the frame, never zero.
    static func previewSize(width: Int, height: Int, longest: Int = previewPixels) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else { return (0, 0) }
        let scale = min(1, Double(longest) / Double(max(width, height)))
        return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
    }
}
