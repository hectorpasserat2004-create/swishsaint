// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// File Transcription: what is taken from a drop, the queue's order and its
/// list across launches, the words into passages and files, the files'
/// names, the settings and the texts.
enum ForkTranscribeTests {
    static func run(_ suite: TestSuite) {
        drops(suite)
        queue(suite)
        sentences(suite)
        files(suite)
        output(suite)
        settings(suite)
        strings(suite)
    }

    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    private static func job(_ name: String, _ stage: ForkTranscribeStage, finished: TimeInterval? = nil) -> ForkTranscribeJob {
        var job = ForkTranscribeJob(id: UUID(), source: URL(fileURLWithPath: "/tmp/\(name)"), engine: .local,
                                    language: .auto, added: start, stage: stage)
        job.finished = finished.map { start.addingTimeInterval($0) }
        return job
    }

    private static func drops(_ suite: TestSuite) {
        suite.expect(["a.mp3", "b.M4A", "c.wav", "d.mov", "e.mp4", "f.flac", "g.ogg", "h.opus", "i.webm"]
                        .allSatisfy { ForkTranscribeRules.accepts(URL(fileURLWithPath: "/x/\($0)")) },
                     "every audio and video format is taken, whatever its case")
        suite.expect(!["notes.txt", "photo.jpg", "doc.pdf", "noext"].contains { ForkTranscribeRules.accepts(URL(fileURLWithPath: "/x/\($0)")) },
                     "text, pictures and documents are not")

        let folder = URL(fileURLWithPath: "/rec", isDirectory: true)
        let inside = ["b 10.mp3", "b 2.mp3", ".hidden.mp3", "notes.txt", "a.m4a"].map { folder.appendingPathComponent($0) }
        let single = URL(fileURLWithPath: "/other/z.wav")
        let found = ForkTranscribeRules.files(of: [folder, single, single, folder.appendingPathComponent("a.m4a")]) {
            $0 == folder ? inside : nil
        }
        suite.expect(found.map(\.lastPathComponent) == ["a.m4a", "b 2.mp3", "b 10.mp3", "z.wav"],
                     "a folder gives its sound files in Finder order, hidden and other files left out, no file twice")
        suite.expect(ForkTranscribeRules.files(of: [URL(fileURLWithPath: "/x/notes.txt")]) { _ in nil }.isEmpty,
                     "a drop with nothing to hear gives nothing")
    }

    private static func queue(_ suite: TestSuite) {
        let a = job("a.mp3", .done, finished: 10), b = job("b.mp3", .waitingForModel), c = job("c.mp3", .queued)
        suite.expect(ForkTranscribeRules.next(in: [a, b, c]) == b.id, "the first waiting file in drop order goes next")
        suite.expect(ForkTranscribeRules.next(in: [a, job("x", .cancelled), job("y", .failed(.engine))]) == nil,
                     "nothing goes when nothing waits")

        let restored = ForkTranscribeRules.restored([job("1", .transcribing), job("2", .loading), job("3", .writing),
                                                     job("4", .waitingForEngine), job("5", .queued), job("6", .done)])
        suite.expect(restored.map(\.stage) == [.failed(.interrupted), .failed(.interrupted), .failed(.interrupted),
                                               .queued, .queued, .done],
                     "at launch, a job the app left in the middle reads as interrupted and the waiting ones wait again")
        suite.expect(ForkTranscribeFailure.interrupted.isRetryable && !ForkTranscribeFailure.fileMissing.isRetryable
                        && !ForkTranscribeFailure.unreadable.isRetryable,
                     "an interrupted job can be tried again, a file gone or unreadable cannot")

        let many = (0..<(ForkTranscribeRules.historyLimit + 5)).map { job("\($0).mp3", .done, finished: TimeInterval($0)) }
            + [job("active.mp3", .queued)]
        let trimmed = ForkTranscribeRules.trimmed(many)
        suite.expect(trimmed.count == ForkTranscribeRules.historyLimit + 1
                        && trimmed.contains { $0.name == "active.mp3" }
                        && !trimmed.contains { $0.name == "0.mp3" } && trimmed.contains { $0.name == "204.mp3" },
                     "the list keeps every active job and only the newest finished ones")

        let encoded = try? JSONEncoder().encode([job("f", .failed(.notDownloaded)), job("g", .transcribing)])
        let decoded = encoded.flatMap { try? JSONDecoder().decode([ForkTranscribeJob].self, from: $0) }
        suite.expect(decoded?.map(\.stage) == [.failed(.notDownloaded), .transcribing], "the list survives its JSON")
        let unknown = Data(#""fromTheFuture""#.utf8)
        suite.expect((try? JSONDecoder().decode(ForkTranscribeFailure.self, from: unknown)) == .engine,
                     "a failure a newer version wrote reads as an engine failure")

        suite.expect(ForkTranscribeRules.remaining(fraction: 0.02, elapsed: 3) == nil,
                     "no time left is guessed before 5 %")
        suite.expectClose(ForkTranscribeRules.remaining(fraction: 0.25, elapsed: 10) ?? -1, 30, "a quarter in 10 s leaves 30 s")
        suite.expect(ForkTranscribeRules.clock(42) == "0:42" && ForkTranscribeRules.clock(4325) == "1:12:05",
                     "lengths read as minutes, then hours")
    }

    private static func words(_ items: [(String, Double, Double)]) -> [ForkTranscribeFormat.Word] {
        items.map { .init(text: $0.0, start: $0.1, end: $0.2) }
    }

    private static func sentences(_ suite: TestSuite) {
        let gap = ForkTranscribeFormat.sentences(words([("Bonjour", 0, 0.5), ("à", 0.6, 0.7), ("tous", 0.8, 1),
                                                        ("Ensuite", 3, 3.4), ("on", 3.5, 3.6), ("commence", 3.7, 4)]))
        suite.expect(gap.map(\.text) == ["Bonjour à tous", "Ensuite on commence"] && gap[1].start == 3,
                     "a pause closes a sentence even without its full stop")

        let short = ForkTranscribeFormat.sentences(words([("Oui.", 0, 0.4), ("Non.", 0.5, 0.9), ("D’accord.", 1, 1.5)]))
        suite.expect(short.count == 1, "a full stop does not cut a sentence of a few seconds")

        let long = ForkTranscribeFormat.sentences(words([("Alors", 0, 1), ("voilà", 1.1, 4.2), ("le", 4.3, 4.4),
                                                         ("point.", 4.5, 5), ("Suite", 5.1, 5.5)]))
        suite.expect(long.map(\.text) == ["Alors voilà le point.", "Suite"], "a full stop after 4 s closes it")

        let stream = (0..<40).map { ("mot", Double($0), Double($0) + 0.9) }
        let capped = ForkTranscribeFormat.sentences(words(stream))
        suite.expect(capped.count == 2 && capped.allSatisfy { $0.end - $0.start <= ForkTranscribeFormat.longestSentence },
                     "a sentence never runs past 30 s")
        suite.expect(ForkTranscribeFormat.sentences(words([(" ", 0, 1)])).isEmpty, "blank words give nothing")

        let segments: [ForkTranscribeDocument.Segment] = [
            .init(start: 0, end: 5, speaker: "A", text: "Un."), .init(start: 5.5, end: 9, speaker: "A", text: "Deux."),
            .init(start: 9.2, end: 12, speaker: "B", text: "Trois."), .init(start: 20, end: 22, speaker: "B", text: "Quatre."),
        ]
        suite.expect(ForkTranscribeFormat.paragraphs(segments).map(\.text) == ["Un. Deux.", "Trois.", "Quatre."],
                     "paragraphs join one voice's sentences, and break at another voice or a long pause")
    }

    private static let labels = ForkTranscribeFormat.Labels(title: { "Transcription : \($0)" }, summary: "1:00 · ici",
                                                           voice: { "Voix \($0)" }, separator: " : ")

    private static func files(_ suite: TestSuite) {
        let mono = ForkTranscribeDocument(segments: [.init(start: 3, end: 6, speaker: nil, text: "Bonjour à tous."),
                                                     .init(start: 3725.25, end: 3730, speaker: nil, text: "Fin.")],
                                          duration: 3730, language: "fr")
        suite.expect(ForkTranscribeFormat.text(mono, labels: labels) == "[00:00:03] Bonjour à tous.\n\n[01:02:05] Fin.\n",
                     "the text file: one timed paragraph by block, hours past the first one")
        let srt = ForkTranscribeFormat.subtitles(mono, labels: labels)
        suite.expect(srt.hasPrefix("1\n00:00:03,000 --> 00:00:06,000\nBonjour à tous.\n")
                        && srt.contains("2\n01:02:05,250 --> 01:02:10,000\nFin.\n"),
                     "subtitles carry milliseconds")
        let md = ForkTranscribeFormat.markdown(mono, fileName: "reunion.m4a", labels: labels)
        suite.expect(md.hasPrefix("# Transcription : reunion.m4a\n\n*1:00 · ici*\n") && md.contains("`00:00:03`  \nBonjour à tous."),
                     "the Markdown file: a title, the summary, then the timed passages")

        var voices = ForkTranscribeDocument(segments: [.init(start: 0, end: 2, speaker: "S2", text: "Salut."),
                                                       .init(start: 9, end: 11, speaker: "S0", text: "Bonjour."),
                                                       .init(start: 20, end: 22, speaker: "S2", text: "Ça va ?")],
                                            duration: 22)
        suite.expect(voices.speakers == ["S2", "S0"] && voices.wordCount == 5, "voices in the order they first speak")
        suite.expect(ForkTranscribeFormat.text(voices, labels: labels).hasPrefix("[00:00:00] Voix 1 : Salut.\n\n[00:00:09] Voix 2 : Bonjour."),
                     "the first voice heard is Voice 1")
        voices.speakerNames = ["S0": "Hector", "S2": "  "]
        suite.expect(ForkTranscribeFormat.text(voices, labels: labels).contains("Voix 1 : Salut.")
                        && ForkTranscribeFormat.text(voices, labels: labels).contains("Hector : Bonjour."),
                     "a renamed voice takes its name; a blank name keeps the number")

        let long = String(repeating: "mot ", count: 60).trimmingCharacters(in: .whitespaces)
        let pieces = ForkTranscribeFormat.split(.init(start: 10, end: 40, speaker: nil, text: long))
        suite.expect(pieces.count > 1 && pieces.allSatisfy { $0.2.count <= ForkTranscribeFormat.subtitleCharacters }
                        && pieces.first?.0 == 10 && abs((pieces.last?.1 ?? 0) - 40) < 0.001,
                     "a long subtitle is cut by words, its time shared to the end")
    }

    private static func output(_ suite: TestSuite) {
        let source = URL(fileURLWithPath: "/rec/réunion 12.11.mp3")
        let folder = URL(fileURLWithPath: "/rec", isDirectory: true)
        let first = ForkTranscribeOutput.urls(for: source, in: folder, kinds: [.md, .txt], exists: { _ in false })
        suite.expect(first.map(\.lastPathComponent) == ["réunion 12.11.transcription.md", "réunion 12.11.transcription.txt"],
                     "the texts are named after the file")
        let taken: Set<String> = ["/rec/réunion 12.11.transcription.txt", "/rec/réunion 12.11 (2).transcription.md"]
        let next = ForkTranscribeOutput.urls(for: source, in: folder, kinds: [.md, .txt], exists: { taken.contains($0.path) })
        suite.expect(next.map(\.lastPathComponent) == ["réunion 12.11 (3).transcription.md", "réunion 12.11 (3).transcription.txt"],
                     "nothing is written over: the files of one job share a free name")

        let fallback = URL(fileURLWithPath: "/home/Documents/Transcriptions", isDirectory: true)
        suite.expect(ForkTranscribeOutput.folder(for: source, chosen: nil, fallback: fallback, writable: { _ in true }) == (folder, false),
                     "beside the file when its folder takes files")
        suite.expect(ForkTranscribeOutput.folder(for: source, chosen: nil, fallback: fallback, writable: { _ in false }) == (fallback, true),
                     "a read-only folder sends the text to the fallback")
        let chosen = URL(fileURLWithPath: "/notes", isDirectory: true)
        suite.expect(ForkTranscribeOutput.folder(for: source, chosen: chosen, fallback: fallback, writable: { _ in true }) == (chosen, false),
                     "a chosen folder wins")

        suite.expect(ForkTranscribeOutput.kinds("srt, md") == [.md, .srt] && ForkTranscribeOutput.kinds("") == [.md, .txt, .srt]
                        && ForkTranscribeOutput.kinds("pdf") == [.md, .txt, .srt],
                     "formats read in their fixed order; none known gives all")
        suite.expect(ForkTranscribeOutput.stored([.srt, .md]) == "md,srt", "formats are stored in their fixed order")
    }

    private static func settings(_ suite: TestSuite) {
        let keys = ForkDefaults.backupKeys
        suite.expect([ForkDefaultsKey.transcribeEnabled, ForkDefaultsKey.transcribeEngine, ForkDefaultsKey.transcribeLanguage,
                      ForkDefaultsKey.transcribeFormats, ForkDefaultsKey.transcribeUsesFolder,
                      ForkDefaultsKey.transcribeReplacements, ForkDefaultsKey.transcribeNotifies].allSatisfy(keys.contains),
                     "the choices follow the settings backup")
        suite.expect(!keys.contains(ForkDefaultsKey.transcribeFolder), "the chosen folder is this Mac's own")
        suite.expect(ForkDefaults.registered[ForkDefaultsKey.transcribeEnabled] as? Bool == true,
                     "on by default: it does nothing until a file is dropped")
        suite.expect(ForkTranscribeLanguage(stored: "xx") == .auto && ForkTranscribeLanguage.auto.code == nil
                        && ForkTranscribeLanguage.fr.code == "fr",
                     "an unknown language reads as automatic, which lets the engine decide")
        suite.expect(ForkTranscribeEngine(stored: nil) == .local, "the engine is this Mac's by default")
    }

    private static func strings(_ suite: TestSuite) {
        let reference = mirror(ForkTranscribeStrings.enUS)
        for language in AppLanguage.allCases {
            let text = mirror(ForkTranscribeStrings.strings(language))
            let empty = text.filter { $0.value.trimmingCharacters(in: .whitespaces).isEmpty && $0.label != "separator" }
            suite.expect(empty.isEmpty, "\(language): no empty text (\(empty.map(\.label)))")
            let wrong = zip(reference, text).filter { specifiers($0.0.value) != specifiers($0.1.value) }.map(\.0.label)
            suite.expect(wrong.isEmpty, "\(language): the same %@ and %d as in English (\(wrong))")
            let extras = ForkExtrasStrings.strings(language)
            suite.expect(!extras.transcribeTitle.isEmpty && !extras.transcribeSummary.isEmpty,
                         "\(language): the feature has its title and summary")
        }
    }

    private static func mirror(_ text: ForkTranscribeStrings) -> [(label: String, value: String)] {
        Mirror(reflecting: text).children.compactMap { child in
            (child.value as? String).map { (child.label ?? "", $0) }
        }
    }

    /// "%1$@ … %d %%" → ["@", "d"]: the arguments a format takes.
    private static func specifiers(_ format: String) -> [String] {
        let pattern = try? NSRegularExpression(pattern: "%(?:\\d\\$)?([@d])")
        let range = NSRange(format.startIndex..., in: format)
        return (pattern?.matches(in: format, range: range) ?? []).compactMap {
            Range($0.range(at: 1), in: format).map { String(format[$0]) }
        }.sorted()
    }
}
