// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The island's Meetings section (wave 2, lot G): its place among the
/// island's sections, what its top shows, the meetings it lists and what
/// each row says, the first words of a transcript, the preview's size, and
/// its texts in every language.
enum ForkMeetingIslandPageTests {
    static func run(_ suite: TestSuite) {
        section(suite)
        top(suite)
        rows(suite)
        badges(suite)
        files(suite)
        excerpt(suite)
        detected(suite)
        preview(suite)
        texts(suite)
    }

    private static let folder = "2026-10-18 10h02 — Point hebdo"

    private static func entry(state: ForkMeetingSidecar.State = .complete, live: Bool = false, audioOnly: Bool = false,
                              transcript: Bool = false, summary: Bool = false,
                              name: String = folder) -> ForkMeetingLibraryEntry? {
        var meeting = ForkMeetingSidecar.started(id: UUID(), startedAt: Date(timeIntervalSinceReferenceDate: 0),
                                                 origin: .manual, title: "Point hebdo", titleSource: .window,
                                                 capture: ForkMeetingSidecar.Capture())
        meeting.state = state
        meeting.recordedSeconds = 3120
        if audioOnly { meeting.capture?.target = .audioOnly }
        if summary { meeting.summary = ForkMeetingSummaryRecord(state: .done, files: ["\(name) summary.md"]).json }
        var names = [ForkMeetingFolder.sidecarName, audioOnly ? "\(name).m4a" : "\(name).mp4"]
        if !audioOnly { names.append("\(name).m4a") }
        var ours: [String] = []
        if transcript {
            ours = ["\(name).txt", "\(name).srt"]
            names += ours
        }
        return ForkMeetingLibraryEntry(folderName: name, sidecar: .success(meeting),
                                       contents: ForkMeetingFolder.contents(of: names, folderName: name,
                                                                            transcriptFiles: ours),
                                       live: live)
    }

    // MARK: - Its place in the island

    private static func section(_ suite: TestSuite) {
        let others = NotchModule.allCases.filter { $0 != .meetings }
        suite.expect(NotchModule.meetings.shortcutKey == "e"
                        && !others.map(\.shortcutKey).contains("e")
                        && NotchSupport.moduleShortcut("E", modules: NotchModule.allCases) == .meetings,
                     "the Meetings section opens with ⌥⌘E, a key no other section uses")
        suite.expect(NotchModule.meetings.symbol == NotchControlItem.meeting.symbol
                        && NotchModule.meetings.pageTop == .row,
                     "the section shows the Meeting button's mark, and its page starts below the island's row")
        suite.expect(NotchCompactActivity.meeting.module == .meetings,
                     "the recording in the closed island opens the Meetings section, as Timer's opens Timer")
        suite.expect(NotchQuickAction(id: NotchQuickAction.module(.meetings).id) == .module(.meetings)
                        && NotchQuickAction.optionalActions.contains(.module(.meetings)),
                     "a Meetings button can be placed around the island, as every other section's")

        let saved = NotchModule.meetingsHooks
        defer { NotchModule.meetingsHooks = saved }
        let defaults = UserDefaults(suiteName: "fork.meetings.island.page.\(UUID().uuidString)")!
        suite.expect(!NotchModule.meetings.isAvailable(in: defaults) && !NotchSupport.modules(in: defaults).contains(.meetings),
                     "without the fork's hooks (the official tests), the section never shows")
        NotchModule.meetingsHooks = (title: { _ in "Meetings" }, summary: { "" },
                                     isAvailable: { $0.bool(forKey: ForkDefaultsKey.meetingsEnabled) })
        suite.expect(!NotchSupport.modules(in: defaults).contains(.meetings),
                     "with Meetings off, the island shows no Meetings section")
        defaults.set(true, forKey: ForkDefaultsKey.meetingsEnabled)
        suite.expect(NotchSupport.modules(in: defaults).last == .meetings,
                     "with Meetings on, the section comes after the others until the person moves it")
        defaults.set("meetings,controls", forKey: DefaultsKey.notchModuleOrder)
        suite.expect(NotchSupport.modules(in: defaults).first == .meetings,
                     "it takes the place the person gives it in the Content tab")
        defaults.set("meetings", forKey: DefaultsKey.notchHiddenModules)
        suite.expect(!NotchSupport.modules(in: defaults).contains(.meetings)
                        && !NotchQuickAction.module(.meetings).isAvailable(in: defaults),
                     "unticked in the Content tab, the section and its button around the island go")
    }

    // MARK: - The top

    private static func top(_ suite: TestSuite) {
        typealias P = ForkMeetingIslandPage
        suite.expect(P.top(recording: true, starting: true, detected: true, canStart: false) == .live,
                     "a recording comes first, whatever else is going on")
        suite.expect(P.top(recording: false, starting: true, detected: true, canStart: false) == .starting,
                     "a start under way shows, with the way to cancel it")
        suite.expect(P.top(recording: false, starting: false, detected: true, canStart: true) == .detected
                        && P.top(recording: false, starting: false, detected: true, canStart: false) == .idle,
                     "a call detected is offered only when a meeting can start now")
        suite.expect(P.top(recording: false, starting: false, detected: false, canStart: true) == .idle,
                     "nothing going on: the button that records a meeting")
    }

    // MARK: - The list

    private static func rows(_ suite: TestSuite) {
        guard let recording = entry(state: .recording, live: true, name: "2026-10-18 11h00 — Live"),
              let saved = entry() else { return suite.expect(false, "the fixture's meetings read") }
        guard let finishing = entry(state: .finalizing, live: true, name: "2026-10-18 10h30 — Done") else {
            return suite.expect(false, "the fixture's finishing meeting reads")
        }
        suite.expect(ForkMeetingIslandPage.rows([recording, finishing, saved], showsLive: true) == [saved]
                        && ForkMeetingIslandPage.rows([recording, saved], showsLive: false) == [recording, saved],
                     "the meeting the live card shows, recording or finishing, is not listed twice; the others keep the window's order")
        let root = URL(fileURLWithPath: "/Users/me/Meetings", isDirectory: true)
        let writing: Set<String> = ["/Users/me/Meetings/2026-10-18 11h00 — Live"]
        typealias R = ForkMeetingLibrary.Rescan
        suite.expect(ForkMeetingIslandPage.rescan(.folders(["2026-10-18 11h00 — Live"]), root: root, writing: writing) == nil
                        && ForkMeetingIslandPage.rescan(.folders(["2026-10-18 11h00 — Live", "Old"]), root: root,
                                                        writing: writing) == R.folders(["Old"])
                        && ForkMeetingIslandPage.rescan(.all, root: root, writing: writing) == R.all,
                     "a recording's own writes scan nothing on the island's page; other changes still do")
    }

    private static func badges(_ suite: TestSuite) {
        typealias P = ForkMeetingIslandPage
        func badges(_ entry: ForkMeetingLibraryEntry?, transcribing: Double? = nil, queued: Bool = false,
                    summarizing: Bool = false, sending: Bool = false,
                    mark: ForkMeetingExportHistory.Mark? = nil) -> [P.Badge] {
            guard let entry else { return [] }
            return P.badges(entry, transcribing: transcribing, transcriptQueued: queued, summarizing: summarizing,
                            sending: sending, exportMark: mark)
        }
        suite.expect(badges(entry()) == [] && badges(entry(transcript: true, summary: true), mark: .done)
                        == [.transcript, .summary, .exported],
                     "a saved meeting says it is transcribed, summarized and exported, in that order")
        suite.expect(badges(entry(transcript: true), transcribing: 0.42) == [.transcribing(0.42)]
                        && badges(entry(), transcribing: 7) == [.transcribing(1)]
                        && badges(entry(), transcribing: .nan) == [.transcribing(0)]
                        && badges(entry(), queued: true) == [.transcriptQueued],
                     "a transcript under way shows its share, kept between 0 and 100 %, or that it waits")
        suite.expect(badges(entry(summary: true), summarizing: true) == [.summarizing]
                        && badges(entry(), sending: true, mark: .failed) == [.sending]
                        && badges(entry(), mark: .failed) == [.exportFailed],
                     "a summary or a send under way says so; an export that failed is marked")
        suite.expect(badges(entry(state: .recording, live: true), transcribing: 0.5, mark: .done) == [.recording]
                        && badges(entry(state: .recording), mark: .done).first == .flagged,
                     "a meeting being written says only that; one left unfinished by a crash is flagged first")
    }

    private static func files(_ suite: TestSuite) {
        typealias F = ForkMeetingIslandPage.File
        suite.expect(entry(transcript: true, summary: true).map(ForkMeetingIslandPage.files)
                        == [F(kind: .video, name: "\(folder).mp4"), F(kind: .audio, name: "\(folder).m4a"),
                            F(kind: .transcript, name: "\(folder).txt"), F(kind: .subtitles, name: "\(folder).srt"),
                            F(kind: .summary, name: "\(folder) summary.md")],
                     "an open meeting lists its video, its sound, its transcript, subtitles and summary")
        suite.expect(entry(audioOnly: true).map(ForkMeetingIslandPage.files) == [F(kind: .audio, name: "\(folder).m4a")],
                     "a meeting recorded without picture lists its sound alone")
    }

    private static func excerpt(_ suite: TestSuite) {
        let transcript = "[00:00:03] Moi\u{00A0}: Bonjour à tous.\n\n★ [00:00:10]\n\n[00:00:12] Participants\u{00A0}: Salut.\n\n"
            + "[00:01:00] Moi\u{00A0}: On commence.\n\n[00:02:00] Participants\u{00A0}: D’accord.\n"
        suite.expect(ForkMeetingIslandPage.excerpt(transcript)
                        == "Moi\u{00A0}: Bonjour à tous.\nParticipants\u{00A0}: Salut.\nMoi\u{00A0}: On commence.",
                     "the first three paragraphs, without their times or the marked moments")
        let long = ForkMeetingIslandPage.excerpt("[00:00:01] Moi : " + String(repeating: "mot ", count: 200))
        suite.expect(long.count <= 241 && long.hasSuffix("…") && !long.contains("mo…"),
                     "a long excerpt is cut at a word, with an ellipsis")
        suite.expect(ForkMeetingIslandPage.excerpt("[note] kept\n") == "[note] kept" && ForkMeetingIslandPage.excerpt("") == "",
                     "only a time in brackets is taken off; an empty transcript says nothing")
    }

    private static func detected(_ suite: TestSuite) {
        func candidate(title: String?, calendar: String?) -> ForkMeetingCandidate {
            ForkMeetingCandidate(identity: ForkMeetingIdentity("meet:abc-defg-hij"), provider: "meet",
                                 providerName: "Google Meet", providerShortName: "Meet", titleName: title,
                                 meetCode: "abc-defg-hij", calendarTitle: calendar, appBundle: "com.google.Chrome",
                                 pid: 100, windowID: 1, windowBundle: "com.google.Chrome", defaultSound: .app,
                                 policy: .ask, silenced: false, bornAt: Date(timeIntervalSinceReferenceDate: 0))
        }
        let calendar = ForkMeetingIslandPage.detectedName(candidate(title: "Point", calendar: " Revue Q4 "))
        let window = ForkMeetingIslandPage.detectedName(candidate(title: "Point hebdo", calendar: nil))
        let bare = ForkMeetingIslandPage.detectedName(candidate(title: "  ", calendar: nil))
        suite.expect(calendar.title == "Revue Q4" && calendar.service == "Google Meet"
                        && window.title == "Point hebdo" && bare.title == "Google Meet" && bare.service == nil,
                     "a call detected is named by its event, else its own name, else its service")
    }

    private static func preview(_ suite: TestSuite) {
        let full = ForkMeetingIslandPage.previewSize(width: 1920, height: 1080)
        let small = ForkMeetingIslandPage.previewSize(width: 320, height: 200)
        let tall = ForkMeetingIslandPage.previewSize(width: 600, height: 1200)
        suite.expect(full.width == 480 && full.height == 270 && small.width == 320 && small.height == 200
                        && tall.width == 240 && tall.height == 480
                        && ForkMeetingIslandPage.previewSize(width: 0, height: 1080) == (0, 0),
                     "the still is at most 480 pixels on its longer side, never enlarged, nothing for no frame")
        suite.expect(ForkMeetingIslandPage.previewInterval == 1, "the still is read once a second")
    }

    // MARK: - Texts

    private static func fields(_ strings: ForkMeetingIslandStrings) -> [(String, String)] {
        Mirror(reflecting: strings).children.compactMap { child in
            guard let label = child.label, let value = child.value as? String else { return nil }
            return (label, value)
        }
    }

    private static func texts(_ suite: TestSuite) {
        let languages = AppLanguage.allCases
        let all = languages.map(ForkMeetingIslandStrings.strings)
        suite.expect(all.allSatisfy { fields($0).allSatisfy { !$0.1.isEmpty } }
                        && all.allSatisfy { Set(fields($0).map(\.0)) == Set(fields(.enUS).map(\.0)) },
                     "every text of the island's Meetings section exists in the fifteen languages")
        let english = Dictionary(uniqueKeysWithValues: fields(.enUS))
        // Words several languages share with English, as their Finder says them.
        let shared: Set<String> = ["fileVideo", "fileAudio", "filesTitle", "islandSettingsLink"]
        var untranslated: [String] = []
        for language in languages where language != .enUS {
            for (label, value) in fields(.strings(language)) where value == english[label] && !shared.contains(label) {
                untranslated.append("\(language.rawValue).\(label)")
            }
        }
        suite.expect(untranslated.isEmpty, "every text is translated: \(untranslated)")
        let short: [(String, (ForkMeetingIslandStrings) -> String)] = [
            ("idleTitle", \.idleTitle), ("recordMeeting", \.recordMeeting), ("detectedTitle", \.detectedTitle),
            ("detectedCaption", \.detectedCaption), ("recentTitle", \.recentTitle),
            ("statusTranscript", \.statusTranscript), ("statusTranscriptQueued", \.statusTranscriptQueued),
            ("statusSummary", \.statusSummary), ("statusSummarizing", \.statusSummarizing),
            ("statusExportFailed", \.statusExportFailed), ("actionOpen", \.actionOpen), ("fileVideo", \.fileVideo),
            ("fileAudio", \.fileAudio), ("fileSubtitles", \.fileSubtitles),
            ("statusTranscribing", { $0.statusTranscribing("100 %") }),
        ]
        var tooLong: [String] = []
        for (language, strings) in zip(languages, all) {
            for (label, read) in short where read(strings).count > 28 {
                tooLong.append("\(language.rawValue).\(label): \(read(strings))")
            }
        }
        suite.expect(tooLong.isEmpty, "the section's statuses and buttons fit the island, 28 characters at most: \(tooLong)")
        let formats = all.flatMap { [$0.idleShortcutFormat, $0.statusTranscribingFormat, $0.noticesCaptionFormat] }
        suite.expect(formats.allSatisfy { $0.components(separatedBy: "%@").count == 2 && !$0.contains("%d") },
                     "each format takes exactly the one value it is given")
        let french = fields(.fr).map(\.1)
        let loose = french.filter { text in
            text.contains("'") || text.contains("« ") || [":", ";", "!", "?", "»"].contains { text.contains(" " + $0) }
        }
        suite.expect(loose.isEmpty, "French texts use no-break spaces and typographic apostrophes: \(loose)")
        suite.expect(!all.flatMap { fields($0).map(\.1) }.contains { $0.contains("'") },
                     "no text of the section uses a straight apostrophe")
    }
}
