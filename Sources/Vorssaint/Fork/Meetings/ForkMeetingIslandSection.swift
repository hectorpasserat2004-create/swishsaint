// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import SwiftUI

/// The island's Meetings section (seams `notch-meetings*`), a page like
/// Clipboard: on top the meeting being recorded, with a still of what is
/// filmed, its time, its levels and its controls; else the call detected,
/// one click from being recorded; else the button that records. Below, the
/// recent meetings by day, each saying where it is (transcribed, summarized,
/// exported, or what went wrong); a click opens one in place with its files,
/// the first words of its transcript and its actions, and ↗ shows it in the
/// Meetings window.
///
/// The list is the window's model (`ForkMeetingLibraryModel`), one kept
/// for the island across its openings (`.island`), started while the page
/// shows and stopped when it goes, never in the Settings preview: the disk
/// is read off the main thread, and a change in the folder reads it again.
struct ForkMeetingIslandSection: View {
    @ObservedObject var service: NotchService
    let size: CGSize
    @ObservedObject private var library: ForkMeetingLibraryModel
    /// Given rows (the render harness): no scan, no watch.
    private let givenLibrary: Bool
    @ObservedObject private var model = ForkMeetingIslandModel.shared
    @ObservedObject private var meetings = ForkMeetingService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(ForkDefaultsKey.meetingsShortcut) private var shortcutStorage = ""
    @Environment(\.notchSettingsPreview) private var preview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opened: String?
    @State private var searchOpen = false
    @FocusState private var searching: Bool
    /// The first words of the transcripts read so far, by folder and file.
    @State private var excerpts: [String: String] = [:]

    /// `library` and `open`: given rows and the meeting open among them,
    /// for the render harness; the island gives neither.
    init(service: NotchService, size: CGSize, library: ForkMeetingLibraryModel? = nil, open: String? = nil) {
        self.service = service
        self.size = size
        givenLibrary = library != nil
        _library = ObservedObject(wrappedValue: library ?? .island)
        _opened = State(initialValue: open)
    }

    private var text: ForkMeetingStrings { ForkMeetingStrings.strings(l10n.language) }
    private var page: ForkMeetingIslandStrings { ForkMeetingIslandStrings.strings(l10n.language) }

    private var top: ForkMeetingIslandPage.Top {
        ForkMeetingIslandPage.top(recording: model.state != .hidden, starting: meetings.isStarting,
                                  detected: meetings.detectedMeeting != nil, canStart: meetings.canStart)
    }

    private var groups: [ForkMeetingLibrary.Group] {
        let showsLive = top == .live
        return library.groups.compactMap { group in
            let rows = ForkMeetingIslandPage.rows(group.entries, showsLive: showsLive)
            return rows.isEmpty ? nil : ForkMeetingLibrary.Group(day: group.day, entries: rows)
        }
    }

    private var isSearching: Bool { !library.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        let groups = groups
        VStack(spacing: NotchLayout.rowSpacing) {
            if searchOpen { searchField }
            if !searchOpen || !isSearching { topCard }
            if groups.isEmpty, top == .idle, !isSearching, library.loaded {
                // Nothing recorded yet and nothing going on: the page says it
                // once, with the button that records under it.
                NotchEmptyView(symbol: NotchModule.meetings.symbol, message: page.historyEmpty) {
                    NotchPillButton(title: page.recordMeeting, prominent: true) {
                        service.perform { ForkMeetingService.shared.recordFromIsland() }
                    }
                    .disabled(!meetings.canStart)
                }
                .frame(maxHeight: .infinity)
            } else if groups.isEmpty, isSearching {
                NotchEmptyView(symbol: "magnifyingglass", message: FeatureStrings.clipboard(l10n.language).noResults)
                    .frame(maxHeight: .infinity)
            } else {
                list(groups)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .notchBand(leading: {
            if !searchOpen {
                NotchIconButton(symbol: "magnifyingglass", title: text.searchPlaceholder, action: openSearch)
            }
        }, trailing: {
            NotchIconButton(symbol: "arrow.up.forward.app", title: text.openLibrary) {
                service.perform { ForkMeetingLibraryWindow.shared.show() }
            }
        })
        .animation(reduceMotion ? nil : .smooth(duration: 0.26), value: top)
        .onAppear(perform: appeared)
        .onDisappear(perform: disappeared)
        .onChange(of: model.state == .hidden) { _, hidden in
            // A recording that ended takes its still with it.
            if hidden { ForkMeetingLivePreview.shared.reset() }
        }
        .onChange(of: searchOpen) { _, open in
            guard !preview else { return }
            // Escape closes the search before it closes the island.
            service.setPageLayer(.meetings, close: open ? { closeSearch() } : nil)
        }
        .onChange(of: searching) { _, focused in
            if !focused, !isSearching { searchOpen = false }
        }
        // The folders being written are not watched: a recording that
        // starts, stops or is finished reads them again.
        .onChange(of: [meetings.isRecording, meetings.isBusy]) { _, _ in
            if scans { library.refresh() }
        }
    }

    /// The page in the island, not in the Settings preview nor the harness:
    /// only it reads the disk.
    private var scans: Bool { !givenLibrary && !preview }

    private func appeared() {
        if scans { library.start() }
        if let opened, let entry = library.entries.first(where: { $0.folderName == opened }) { readExcerpt(entry) }
    }

    private func disappeared() {
        if scans { library.stop() }
        if !preview { service.setPageLayer(.meetings, close: nil) }
    }

    // MARK: - The top

    @ViewBuilder private var topCard: some View {
        switch top {
        case .live:
            ForkMeetingLiveCardView(showsPreview: true)
                .transition(.opacity)
        case .starting:
            ForkMeetingIslandStatusCard(symbol: nil, title: text.stateStarting, caption: nil) {
                ForkMeetingIslandCardButton(symbol: "xmark", title: text.cancel, label: text.cancel) {
                    meetings.cancelStart()
                }
            }
            .transition(.opacity)
        case .detected:
            if let candidate = meetings.detectedMeeting {
                let name = ForkMeetingIslandPage.detectedName(candidate)
                ForkMeetingIslandStatusCard(symbol: "video.fill", tint: .green, title: name.title,
                                            caption: [name.service, page.detectedCaption].compactMap { $0 }
                                                .joined(separator: " · ")) {
                    recordButton(title: text.offerRecord)
                }
                .accessibilityHint(page.detectedTitle)
                .transition(.opacity)
            }
        case .idle:
            if !groups.isEmpty || isSearching || !library.loaded {
                ForkMeetingIslandStatusCard(symbol: "record.circle", tint: .white.opacity(0.45), title: page.idleTitle,
                                            caption: idleCaption) {
                    recordButton(title: text.offerRecord)
                }
                .transition(.opacity)
            } else {
                // An empty page says it all once, with the button under it.
                EmptyView()
            }
        }
    }

    /// The shortcut that records, when there is one; else how a meeting
    /// is offered.
    private var idleCaption: String {
        guard let shortcut = ForkMeetingShortcut.decode(shortcutStorage) else { return page.idleCaption }
        return page.idleShortcut(shortcut.displayString)
    }

    private func recordButton(title: String) -> some View {
        ForkMeetingIslandCardButton(symbol: "record.circle", title: title, label: page.recordMeeting, prominent: true) {
            // The island closes first, so the recording films the window
            // the person was in, not the island.
            service.perform { ForkMeetingService.shared.recordFromIsland() }
        }
        .disabled(!meetings.canStart)
    }

    // MARK: - The list

    private func list(_ groups: [ForkMeetingLibrary.Group]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: NotchLayout.clipboardCardSpacing) {
                    if groups.isEmpty, top == .idle || !library.loaded {
                        // Before the first scan, or nothing yet: the card above says it.
                    } else if groups.isEmpty {
                        Text(page.historyEmpty)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    ForEach(groups, id: \.day) { group in
                        Text(ForkMeetingLibrary.heading(group.day, strings: text, language: l10n.language,
                                                        calendar: library.calendar))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.leading, 4)
                            .padding(.top, 2)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(group.entries, id: \.folderName) { entry in
                            ForkMeetingIslandRow(library: library, entry: entry, open: opened == entry.folderName,
                                                 excerpt: excerpt(entry), toggle: { toggle(entry) },
                                                 window: { showInWindow(entry) })
                                .id(entry.folderName)
                        }
                    }
                }
                .padding(.bottom, 2)
            }
            .scrollIndicators(.automatic)
            .onChange(of: opened) { _, folder in
                guard let folder else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { proxy.scrollTo(folder) }
            }
        }
    }

    private func toggle(_ entry: ForkMeetingLibraryEntry) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.24)) {
            opened = opened == entry.folderName ? nil : entry.folderName
        }
        if opened == entry.folderName { readExcerpt(entry) }
    }

    private func showInWindow(_ entry: ForkMeetingLibraryEntry) {
        let folder = library.folderURL(entry)
        service.perform { ForkMeetingLibraryWindow.shared.show(folder: folder) }
    }

    private func excerptKey(_ entry: ForkMeetingLibraryEntry) -> String? {
        entry.transcript.map { entry.folderName + "/" + $0 }
    }

    private func excerpt(_ entry: ForkMeetingLibraryEntry) -> String? {
        excerptKey(entry).flatMap { excerpts[$0] }
    }

    /// The transcript's first words, read off the main thread the first
    /// time the meeting opens, and kept while the page shows. Never in the
    /// Settings preview.
    private func readExcerpt(_ entry: ForkMeetingLibraryEntry) {
        guard !preview, let key = excerptKey(entry), excerpts[key] == nil, let url = library.transcriptURL(entry) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let words = Self.firstWords(of: url)
            DispatchQueue.main.async { excerpts[key] = words }
        }
    }

    /// The start of the file is enough for three paragraphs: an hour's
    /// transcript is never read whole for them.
    private static func firstWords(of url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 8192)) ?? Data()
        // A cut in the middle of a character leaves it out.
        let text = String(decoding: data, as: UTF8.self)
        return ForkMeetingIslandPage.excerpt(text)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(text.searchPlaceholder, text: $library.query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searching)
                .onSubmit { if !isSearching { closeSearch() } }
                .accessibilityLabel(text.searchPlaceholder)
            if isSearching {
                Button { library.query = ""; searching = true } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(l10n.s.actionClear)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: NotchLayout.clipboardSearchHeight)
        .modifier(NotchControlSurface(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(searching ? 0.34 : 0), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .transition(.opacity)
    }

    private func openSearch() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { searchOpen = true }
        DispatchQueue.main.async { searching = true }
    }

    private func closeSearch() {
        library.query = ""
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { searchOpen = false }
    }
}

// MARK: - Cards

/// The top of the page when nothing records: a mark, two lines and the
/// card's buttons, on the island's card surface (`panelCard`).
struct ForkMeetingIslandStatusCard<Actions: View>: View {
    /// Nil: the spinner of a start under way.
    let symbol: String?
    var tint: Color = .white
    let title: String
    let caption: String?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(tint)
                } else {
                    ForkMeetingIslandGauge(progress: nil, side: 18)
                }
            }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            actions()
        }
        .panelCard()
        .accessibilityElement(children: .contain)
    }
}

/// The live card's buttons, for the cards around it: a filled red one for
/// the step the card leads to, white on the island's grey for the others.
struct ForkMeetingIslandCardButton: View {
    let symbol: String
    let title: String
    let label: String
    var prominent = false
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                Text(title)
                    .lineLimit(1)
                    .fixedSize()
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(enabled ? 1 : 0.45))
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background(prominent && enabled ? AnyShapeStyle(Color(nsColor: .systemRed)) : AnyShapeStyle(Color.white.opacity(0.1)),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 8))
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - A row

/// One meeting of the list: its status mark, title, time and length, and
/// what became of it; open, its files, the first words of its transcript
/// and its actions. It reads the transcriptions, summaries and exports on
/// its own, so their progress redraws the row, never the page.
struct ForkMeetingIslandRow: View {
    @ObservedObject var library: ForkMeetingLibraryModel
    let entry: ForkMeetingLibraryEntry
    let open: Bool
    let excerpt: String?
    let toggle: () -> Void
    let window: () -> Void
    @ObservedObject private var transcriber = ForkMeetingTranscriber.shared
    @ObservedObject private var summarizer = ForkMeetingSummarizer.shared
    @ObservedObject private var exports = ForkMeetingExports.shared
    @ObservedObject private var parakeet = ForkParakeetModelStore.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var hovering = false
    @Environment(\.notchSettingsPreview) private var preview

    private var text: ForkMeetingStrings { ForkMeetingStrings.strings(l10n.language) }
    private var page: ForkMeetingIslandStrings { ForkMeetingIslandStrings.strings(l10n.language) }
    private var folder: URL { library.folderURL(entry) }

    private var badges: [ForkMeetingIslandPage.Badge] {
        var transcribing: Double?, queued = false
        switch transcriber.phase(id: entry.id, folder: folder) {
        case let .running(fraction): transcribing = fraction
        case .waiting: queued = true
        case .idle: break
        }
        let summarizing: Bool
        switch summarizer.phase(id: entry.id, folder: folder) {
        case .running, .waiting: summarizing = true
        case .idle: summarizing = false
        }
        return ForkMeetingIslandPage.badges(entry, transcribing: transcribing, transcriptQueued: queued,
                                            summarizing: summarizing, sending: exports.isSending(folder),
                                            exportMark: ForkMeetingExportHistory.mark(entry.exports,
                                                                                      targets: exports.configs.map(\.id)))
    }

    var body: some View {
        let badges = badges
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggle) { summary(badges) }
                .buttonStyle(NotchButtonStyle(lifts: false))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(badges))
                .accessibilityHint(open ? page.hideDetails : page.showDetails)
                .accessibilityAddTraits(.isButton)
            if open { details }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(NotchControlSurface(cornerRadius: 14, selected: open))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(hovering && !open ? 0.18 : 0), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .onHover { hovering = $0 }
        .contextMenu { menuItems }
    }

    // MARK: Closed

    private func summary(_ badges: [ForkMeetingIslandPage.Badge]) -> some View {
        HStack(alignment: .center, spacing: 8) {
            ForkMeetingIslandRowMark(status: entry.status)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(entry.displayTitle(text))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    if let length = ForkMeetingLibraryText.duration(entry.seconds, language: l10n.language) {
                        Text(length)
                            .font(.system(size: 10.5)).monospacedDigit()
                            .foregroundStyle(.white.opacity(0.55))
                            .fixedSize()
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if let date = entry.date {
                        Text(ForkMeetingLibraryText.time(date, language: l10n.language, calendar: library.calendar))
                            .monospacedDigit()
                    }
                    if let service = ForkMeetingLibraryText.providerName(entry.provider) {
                        Text("·")
                        Text(service).lineLimit(1)
                    }
                    if entry.isAudioOnly {
                        Text("·")
                        Text(text.soundOnly).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    ForkMeetingIslandBadges(badges: badges, entry: entry)
                }
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
            }
            if hovering || open {
                NotchIconButton(symbol: "arrow.up.forward.app", title: page.openInWindow, action: window)
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
    }

    private func accessibilityLabel(_ badges: [ForkMeetingIslandPage.Badge]) -> String {
        let label = ForkMeetingLibraryText.accessibilityLabel(entry, strings: text, language: l10n.language,
                                                              calendar: library.calendar)
        let said = badges.compactMap { ForkMeetingIslandBadges.word($0, entry: entry, text: text, page: page,
                                                                     language: l10n.language) }
        return ([label] + said).reduce("") { ForkMeetingLiveText.sentences($0, $1) }
    }

    // MARK: Open

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            let files = ForkMeetingIslandPage.files(entry)
            if !files.isEmpty {
                ForkMeetingIslandFiles(files: files, folder: folder, page: page, text: text)
            }
            if let excerpt, !excerpt.isEmpty {
                Text(excerpt)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            if let flagged = ForkMeetingLibrary.statusText(entry.status, strings: text), entry.status.isFlagged {
                Label(flagged, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            actions
        }
        .padding(.leading, 22)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var transcribable: Bool {
        !entry.isReadOnly && !library.isLive(entry) && entry.playable != nil && parakeet.isInstalled
    }

    /// As an open clipboard entry's bottom row: when and how much on the
    /// leading side, the actions on the trailing one.
    private var actions: some View {
        HStack(spacing: 2) {
            HStack(spacing: 5) {
                if let date = entry.date {
                    Text(ForkMeetingLibraryText.longDate(date, language: l10n.language, calendar: library.calendar))
                        .lineLimit(1)
                }
                if let bytes = entry.bytes, bytes > 0 {
                    Text("·")
                    Text(ForkMeetingLiveText.size(bytes, language: l10n.language)).lineLimit(1).fixedSize()
                }
            }
            .font(.system(size: 9.5))
            .foregroundStyle(.white.opacity(0.4))
            Spacer(minLength: 6)
            NotchIconButton(symbol: "play.fill", title: page.actionOpen) {
                guard let url = library.playableURL(entry) else { return }
                NSWorkspace.shared.open(url)
            }
            .disabled(library.playableURL(entry) == nil)
            NotchIconButton(symbol: "folder", title: text.actionShow) { library.showInFinder(entry) }
            if entry.transcript != nil {
                NotchIconButton(symbol: "doc.text", title: text.actionOpenTranscript) { library.openTranscript(entry) }
            }
            if transcriber.phase(id: entry.id, folder: folder) == .idle, entry.transcript == nil, transcribable {
                NotchIconButton(symbol: "waveform.and.mic", title: text.actionTranscribe) { library.transcribe(entry) }
            }
            if !exports.configured.isEmpty {
                NotchMenuButton(title: text.actionExportTo, items: exportItems, cornerRadius: 9) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 28, height: 28)
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .help(text.actionExportTo)
            }
        }
        .frame(height: 28)
    }

    /// One item per exporter set up, as the window's ⋯ › Export To.
    private var exportItems: [NotchMenuItem] {
        let live = library.isLive(entry)
        var items = exports.configured.map { config in
            NotchMenuItem(title: config.title(text), symbol: "arrow.up.circle",
                          enabled: !live && !exports.listChanged
                            && !exports.pending.contains(ForkMeetingExports.key(folder, config.id))) {
                exports.export(folder, to: config.id)
            }
        }
        if exports.listChanged {
            items.append(.separator)
            items.append(NotchMenuItem(title: text.actionOpenMeetings, symbol: "gearshape") {
                ForkMeetingService.shared.perform(.openMeetingsPage)
            })
        }
        return items
    }

    @ViewBuilder private var menuItems: some View {
        Button(page.openInWindow, action: window)
        if let url = library.playableURL(entry) {
            Button(page.actionOpen) { NSWorkspace.shared.open(url) }
        }
        Button(text.actionShow) { library.showInFinder(entry) }
        if entry.transcript != nil {
            Button(text.actionOpenTranscript) { library.openTranscript(entry) }
        }
        Divider()
        Button(text.actionCopyPath) { library.copyPath(entry) }
    }
}

/// The row's leading mark: the red dot while it records, the gauge while it
/// finishes, ⚠ when something went wrong, a quiet film or waveform else.
private struct ForkMeetingIslandRowMark: View {
    let status: ForkMeetingLibraryEntry.Status
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch status {
            case .recording:
                ForkMeetingRecordingDot(pulses: !reduceMotion, diameter: 8)
            case .finalizing:
                ForkMeetingIslandGauge(progress: nil, side: 12)
            case .recovered, .interrupted, .unreadable:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            case .complete:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
    }
}

/// What became of a meeting, after its time: a few words for what runs
/// (the transcript's share, a send), a glyph for what is done.
private struct ForkMeetingIslandBadges: View {
    let badges: [ForkMeetingIslandPage.Badge]
    let entry: ForkMeetingLibraryEntry
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let text = ForkMeetingStrings.strings(l10n.language)
        let page = ForkMeetingIslandStrings.strings(l10n.language)
        HStack(spacing: 5) {
            // ⚠ already leads the row.
            ForEach(Array(badges.filter { $0 != .flagged }.enumerated()), id: \.offset) { _, badge in
                badgeView(badge, text: text, page: page)
                    .help(Self.word(badge, entry: entry, text: text, page: page, language: l10n.language) ?? "")
            }
        }
        .fixedSize()
    }

    @ViewBuilder private func badgeView(_ badge: ForkMeetingIslandPage.Badge, text: ForkMeetingStrings,
                                        page: ForkMeetingIslandStrings) -> some View {
        switch badge {
        case .recording:
            Text(text.stateRecording).foregroundStyle(.red)
        case .finishing:
            Text(text.pillFinalizing)
        case .flagged:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case let .transcribing(share):
            Text(page.statusTranscribing(ForkMeetingIslandRules.percent(share, language: l10n.language)))
                .monospacedDigit()
        case .transcriptQueued:
            Image(systemName: "text.badge.plus").foregroundStyle(.white.opacity(0.55))
        case .transcript:
            Image(systemName: "text.quote").foregroundStyle(.white.opacity(0.7))
        case .summarizing:
            Text(page.statusSummarizing)
        case .summary:
            Image(systemName: "list.bullet.rectangle").foregroundStyle(.white.opacity(0.7))
        case .sending:
            Text(text.exportSending)
        case .exported:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .exportFailed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    /// What VoiceOver and the tooltip say of a badge.
    static func word(_ badge: ForkMeetingIslandPage.Badge, entry: ForkMeetingLibraryEntry, text: ForkMeetingStrings,
                     page: ForkMeetingIslandStrings, language: AppLanguage) -> String? {
        switch badge {
        case .recording: return text.stateRecording
        case .finishing: return text.pillFinalizing
        case .flagged: return ForkMeetingLibrary.statusText(entry.status, strings: text)
        case let .transcribing(share): return page.statusTranscribing(ForkMeetingIslandRules.percent(share, language: language))
        case .transcriptQueued: return page.statusTranscriptQueued
        case .transcript: return page.statusTranscript
        case .summarizing: return page.statusSummarizing
        case .summary: return page.statusSummary
        case .sending: return text.exportSending
        case .exported: return text.exportDone
        case .exportFailed: return page.statusExportFailed
        }
    }
}

/// The open row's files, each a small chip that opens it.
private struct ForkMeetingIslandFiles: View {
    let files: [ForkMeetingIslandPage.File]
    let folder: URL
    let page: ForkMeetingIslandStrings
    let text: ForkMeetingStrings

    var body: some View {
        // Named where the island is wide enough in this language, else
        // their marks alone (named on hover and to VoiceOver all the same).
        ViewThatFits(in: .horizontal) {
            chips(titled: true)
            chips(titled: false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(page.filesTitle)
    }

    private func chips(titled: Bool) -> some View {
        HStack(spacing: 5) {
            ForEach(files, id: \.name) { file in
                Button {
                    NSWorkspace.shared.open(folder.appendingPathComponent(file.name))
                } label: {
                    Group {
                        if titled {
                            Label(title(file.kind), systemImage: symbol(file.kind)).labelStyle(.titleAndIcon)
                        } else {
                            Label(title(file.kind), systemImage: symbol(file.kind)).labelStyle(.iconOnly)
                        }
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, titled ? 8 : 7)
                    .frame(height: 22)
                    .background(.white.opacity(0.07), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(NotchButtonStyle(cornerRadius: 11))
                .help(title(file.kind) + " · " + file.name)
                .accessibilityLabel(title(file.kind) + ", " + file.name)
            }
        }
    }

    private func title(_ kind: ForkMeetingIslandPage.File.Kind) -> String {
        switch kind {
        case .video: return page.fileVideo
        case .audio: return page.fileAudio
        case .transcript: return text.transcriptTitle
        case .subtitles: return page.fileSubtitles
        case .summary: return text.summaryTitle
        }
    }

    private func symbol(_ kind: ForkMeetingIslandPage.File.Kind) -> String {
        switch kind {
        case .video: return "film"
        case .audio: return "waveform"
        case .transcript: return "doc.text"
        case .subtitles: return "captions.bubble"
        case .summary: return "list.bullet.rectangle"
        }
    }
}

// MARK: - The island's library

extension ForkMeetingLibraryModel {
    /// The island's Meetings page's own, kept while the app runs so the
    /// page opens on its rows at once and scans in the background.
    static let island = ForkMeetingLibraryModel(forIsland: true)
}

// MARK: - Recording from the island

extension ForkMeetingService {
    /// The page's Record: the call offered is accepted as the offer's own
    /// Record does; otherwise a meeting starts as from the shortcut.
    func recordFromIsland() {
        if case .offering = machine.phase {
            acceptOffer()
        } else {
            startManually()
        }
    }
}

