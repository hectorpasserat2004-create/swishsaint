// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// A transcription as the app keeps it: timed passages, each with who said
/// it when the engine knows (the Studio's voices), and how the files are
/// written from it. Kept in the app's container (one JSON per job), so the
/// reader works even when the written files were moved, and a voice renamed
/// later rewrites them.
struct ForkTranscribeDocument: Codable, Equatable {
    struct Segment: Codable, Equatable {
        var start: TimeInterval
        var end: TimeInterval
        /// The engine's name for the voice ("0", "SPEAKER_01"); nil when one
        /// engine hears no voices.
        var speaker: String?
        var text: String
    }

    var segments: [Segment]
    var duration: TimeInterval
    /// "fr", "en"…, when known.
    var language: String?
    /// The names given to the voices, by the engine's name.
    var speakerNames: [String: String] = [:]

    var wordCount: Int {
        segments.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
    }

    var plainText: String { segments.map(\.text).joined(separator: " ") }

    /// The voices in the order they first speak.
    var speakers: [String] {
        var seen = Set<String>()
        return segments.compactMap(\.speaker).filter { seen.insert($0).inserted }
    }

    /// "Voix 1", or the name the person gave it.
    func name(of speaker: String?, voice: (Int) -> String) -> String? {
        guard let speaker else { return nil }
        if let given = speakerNames[speaker]?.trimmingCharacters(in: .whitespacesAndNewlines), !given.isEmpty {
            return given
        }
        return voice((speakers.firstIndex(of: speaker) ?? 0) + 1)
    }
}

/// Timed words into passages, and passages into files.
enum ForkTranscribeFormat {
    /// One word with its time, from any engine.
    struct Word: Equatable {
        var text: String
        var start: TimeInterval
        var end: TimeInterval
    }

    /// A silence this long closes a sentence even without its full stop.
    static let sentenceGap: TimeInterval = 1.2
    /// A sentence never runs longer than this: the reader keeps its bearings.
    static let longestSentence: TimeInterval = 30
    /// A full stop closes a sentence once it is at least this long.
    static let shortestSentence: TimeInterval = 4
    /// The text's paragraphs: sentences joined until this long, or a pause
    /// (a turn of speech is often one).
    static let longestParagraph: TimeInterval = 45
    static let paragraphGap: TimeInterval = 1.5

    /// Words into sentences: a full stop after a few seconds, a pause, or a
    /// sentence grown too long closes one.
    static func sentences(_ words: [Word], speaker: String? = nil) -> [ForkTranscribeDocument.Segment] {
        var segments: [ForkTranscribeDocument.Segment] = []
        var current: [Word] = []
        func close() {
            guard let first = current.first, let last = current.last else { return }
            let text = current.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                segments.append(.init(start: first.start, end: max(last.end, first.start), speaker: speaker, text: text))
            }
            current = []
        }
        for word in words where !word.text.trimmingCharacters(in: .whitespaces).isEmpty {
            if let last = current.last, word.start - last.end > sentenceGap { close() }
            // The word that would take it past the longest starts the next one.
            if let first = current.first, word.end - first.start > longestSentence { close() }
            current.append(word)
            guard let first = current.first else { continue }
            let length = word.end - first.start
            let endsSentence = word.text.last.map { ".?!…".contains($0) } ?? false
            if endsSentence && length >= shortestSentence { close() }
        }
        close()
        return segments
    }

    /// Sentences into paragraphs for the text and Markdown files: the same
    /// voice, no long pause, not too long.
    static func paragraphs(_ segments: [ForkTranscribeDocument.Segment]) -> [ForkTranscribeDocument.Segment] {
        var result: [ForkTranscribeDocument.Segment] = []
        for segment in segments {
            if var last = result.last, last.speaker == segment.speaker,
               segment.start - last.end <= paragraphGap, segment.end - last.start <= longestParagraph {
                last.text += " " + segment.text
                last.end = max(last.end, segment.end)
                result[result.count - 1] = last
            } else {
                result.append(segment)
            }
        }
        return result
    }

    /// "00:04:05", or "00:04:05,250" in a subtitle.
    static func timestamp(_ seconds: TimeInterval, subtitle: Bool = false) -> String {
        let clamped = max(0, seconds)
        let millis = Int((clamped * 1000).rounded())
        let hours = millis / 3_600_000, minutes = millis % 3_600_000 / 60000
        let secs = millis % 60000 / 1000, rest = millis % 1000
        return subtitle ? String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, rest)
            : String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }

    /// The words of a written file's header, in the person's language.
    struct Labels {
        var title: (String) -> String
        /// "1:12:04 · 3 voices · French · transcribed on 20/11/2026 at 14:03 on this Mac".
        var summary: String
        var voice: (Int) -> String
        /// What follows a voice's name: ": ", or " : " in French.
        var separator: String
    }

    /// `[00:00:03] Voice 1: text`, one paragraph by block.
    static func text(_ document: ForkTranscribeDocument, labels: Labels) -> String {
        paragraphs(document.segments).map { block in
            let who = document.name(of: block.speaker, voice: labels.voice).map { $0 + labels.separator } ?? ""
            return "[\(timestamp(block.start))] \(who)\(block.text)"
        }.joined(separator: "\n\n") + "\n"
    }

    static func markdown(_ document: ForkTranscribeDocument, fileName: String, labels: Labels) -> String {
        var lines = ["# \(labels.title(fileName))", "", "*\(labels.summary)*", ""]
        for block in paragraphs(document.segments) {
            let who = document.name(of: block.speaker, voice: labels.voice).map { "**\($0)** · " } ?? ""
            lines.append("\(who)`\(timestamp(block.start))`  ")
            lines.append(block.text)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Subtitles cut short enough to read: a sentence of more than this many
    /// characters is split by words, its time shared in proportion.
    static let subtitleCharacters = 90

    static func subtitles(_ document: ForkTranscribeDocument, labels: Labels) -> String {
        var cues: [(start: TimeInterval, end: TimeInterval, text: String)] = []
        for segment in document.segments {
            let who = document.name(of: segment.speaker, voice: labels.voice).map { $0 + labels.separator } ?? ""
            for (start, end, text) in split(segment) { cues.append((start, end, who + text)) }
        }
        return cues.enumerated().map { index, cue in
            "\(index + 1)\n\(timestamp(cue.start, subtitle: true)) --> \(timestamp(max(cue.end, cue.start + 0.5), subtitle: true))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    static func split(_ segment: ForkTranscribeDocument.Segment) -> [(TimeInterval, TimeInterval, String)] {
        guard segment.text.count > subtitleCharacters else { return [(segment.start, segment.end, segment.text)] }
        var pieces: [String] = []
        var current = ""
        for word in segment.text.split(separator: " ") {
            if !current.isEmpty, current.count + word.count + 1 > subtitleCharacters {
                pieces.append(current)
                current = ""
            }
            current += current.isEmpty ? String(word) : " " + word
        }
        if !current.isEmpty { pieces.append(current) }
        let total = Double(pieces.reduce(0) { $0 + $1.count })
        let length = segment.end - segment.start
        var start = segment.start
        return pieces.map { piece in
            let end = start + length * Double(piece.count) / max(1, total)
            defer { start = end }
            return (start, end, piece)
        }
    }

    /// What can be pasted into an AI assistant: the header, then the text.
    static func forAssistant(_ document: ForkTranscribeDocument, fileName: String, labels: Labels) -> String {
        markdown(document, fileName: fileName, labels: labels)
    }
}

/// The files a transcription writes and where they go.
enum ForkTranscribeOutput {
    enum Kind: String, CaseIterable, Codable {
        case md
        case txt
        case srt
    }

    /// "md,txt,srt" → the kinds, in their fixed order; none read gives all.
    static func kinds(_ stored: String?) -> [Kind] {
        let asked = Set((stored ?? "").split(separator: ",").compactMap { Kind(rawValue: $0.trimmingCharacters(in: .whitespaces)) })
        let kinds = Kind.allCases.filter(asked.contains)
        return kinds.isEmpty ? Kind.allCases : kinds
    }

    static func stored(_ kinds: [Kind]) -> String {
        Kind.allCases.filter(kinds.contains).map(\.rawValue).joined(separator: ",")
    }

    /// `reunion.transcription.md`, then `reunion (2).transcription.md` if any
    /// of the files already exists: the files of one job always share their
    /// name, and nothing is ever written over.
    static func urls(for source: URL, in folder: URL, kinds: [Kind], exists: (URL) -> Bool) -> [URL] {
        let base = source.deletingPathExtension().lastPathComponent
        for attempt in 1...999 {
            let stem = attempt == 1 ? base : "\(base) (\(attempt))"
            let urls = kinds.map { folder.appendingPathComponent("\(stem).transcription.\($0.rawValue)") }
            if !urls.contains(where: exists) { return urls }
        }
        return kinds.map { folder.appendingPathComponent("\(base) \(UUID().uuidString.prefix(8)).transcription.\($0.rawValue)") }
    }

    /// The source's own folder when it takes files, else the fallback.
    static func folder(for source: URL, chosen: URL?, fallback: URL, writable: (URL) -> Bool) -> (URL, usedFallback: Bool) {
        if let chosen { return writable(chosen) ? (chosen, false) : (fallback, true) }
        let beside = source.deletingLastPathComponent()
        return writable(beside) ? (beside, false) : (fallback, true)
    }
}
