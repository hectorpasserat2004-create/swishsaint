// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// File Transcription's page, under its switch: the drop zone, the engine,
/// the choices, then the files at work and those done. A click on a done
/// file opens its text in the reader.
struct ForkTranscribeSettingsView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var queue = ForkTranscribeQueue.shared
    @AppStorage(ForkDefaultsKey.transcribeEnabled) private var enabled = true
    @AppStorage(ForkDefaultsKey.transcribeLanguage) private var language = ForkTranscribeLanguage.auto.rawValue
    @AppStorage(ForkDefaultsKey.transcribeFormats) private var formats = "md,txt,srt"
    @AppStorage(ForkDefaultsKey.transcribeUsesFolder) private var usesFolder = false
    @AppStorage(ForkDefaultsKey.transcribeFolder) private var folder = ""
    @AppStorage(ForkDefaultsKey.transcribeReplacements) private var replacements = true
    @AppStorage(ForkDefaultsKey.transcribeNotifies) private var notifies = true
    @AppStorage(ForkDefaultsKey.transcribeEngine) private var engine = ForkTranscribeEngine.local.rawValue
    @AppStorage(ForkDefaultsKey.transcribeSpeakers) private var speakers = ForkTranscribeSpeakers.auto

    private var text: ForkTranscribeStrings { ForkTranscribeStrings.strings(l10n.language) }
    private var remote: ForkTranscribeRemoteStrings { ForkTranscribeRemoteStrings.strings(l10n.language) }
    private var chosen: ForkTranscribeEngine { ForkTranscribeEngine(stored: engine) }
    private var active: [ForkTranscribeJob] { queue.jobs.filter(\.stage.isActive) }
    private var finished: [ForkTranscribeJob] {
        queue.jobs.filter { !$0.stage.isActive }.sorted { ($0.finished ?? $0.added) > ($1.finished ?? $1.added) }
    }

    var body: some View {
        Group {
            Section {
                ForkTranscribeDropZone(text: text, enabled: enabled)
                Text(text.pageIntro)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(text.engineTitle) {
                Picker(text.engineTitle, selection: $engine) {
                    Label(text.engineLocal, systemImage: "laptopcomputer").tag(ForkTranscribeEngine.local.rawValue)
                    Label(remote.engineStudio, systemImage: "person.2.wave.2").tag(ForkTranscribeEngine.studio.rawValue)
                    Label(remote.engineOpenAI, systemImage: "network").tag(ForkTranscribeEngine.openAI.rawValue)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Text(detail(chosen))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                switch chosen {
                case .local:
                    ForkTranscribeModelRow(text: text)
                case .studio:
                    ForkTranscribeStudioSettings(remote: remote)
                    Picker(remote.speakersTitle, selection: $speakers) {
                        ForEach(ForkTranscribeSpeakers.choices, id: \.self) { choice in
                            Text(remote.speakers(choice)).tag(choice)
                        }
                    }
                case .openAI:
                    ForkTranscribeOpenAISettings(remote: remote)
                }
                Picker(text.languageTitle, selection: $language) {
                    ForEach(ForkTranscribeLanguage.allCases, id: \.rawValue) { choice in
                        Text(text.language(choice)).tag(choice.rawValue)
                    }
                }
            }

            Section {
                Picker(text.outputTitle, selection: $usesFolder) {
                    Text(text.outputBeside).tag(false)
                    Text(text.outputFolder).tag(true)
                }
                if usesFolder {
                    HStack {
                        Text(folder.isEmpty ? "—" : (folder as NSString).abbreviatingWithTildeInPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(text.chooseFolder) { chooseFolder() }
                    }
                }
                HStack {
                    Text(text.formatsTitle)
                    Spacer()
                    ForEach(ForkTranscribeOutput.Kind.allCases, id: \.self) { kind in
                        Toggle(".\(kind.rawValue)", isOn: binding(for: kind))
                            .toggleStyle(.checkbox)
                    }
                }
                Toggle(text.replacementsTitle, isOn: $replacements)
                Toggle(text.notifyTitle, isOn: $notifies)
            }

            if !active.isEmpty {
                Section {
                    ForEach(active) { job in ForkTranscribeJobRow(job: job, text: text) }
                } header: {
                    HStack {
                        Text(text.inProgress)
                        Spacer()
                        Button(text.cancelAll) { queue.cancelAll() }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
            }

            Section {
                if finished.isEmpty {
                    Text(text.empty)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(finished) { job in ForkTranscribeJobRow(job: job, text: text) }
                }
            } header: {
                HStack {
                    Text(text.finished)
                    Spacer()
                    if !finished.isEmpty {
                        Button(text.clearList) { queue.clearFinished() }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
            }
        }
        .sheet(item: readingBinding) { reading in
            ForkTranscribeReader(id: reading.id, text: text)
        }
        .onAppear { ForkTranscribePageTracker.isShown = true }
        .onDisappear { ForkTranscribePageTracker.isShown = false }
        .onChange(of: enabled) { _, _ in queue.sync() }
    }

    private func detail(_ engine: ForkTranscribeEngine) -> String {
        switch engine {
        case .local: return text.engineLocalDetail
        case .studio: return remote.engineStudioDetail
        case .openAI: return remote.engineOpenAIDetail
        }
    }

    private struct Reading: Identifiable { let id: UUID }

    private var readingBinding: Binding<Reading?> {
        Binding(get: { queue.reading.map(Reading.init) }, set: { queue.reading = $0?.id })
    }

    private func binding(for kind: ForkTranscribeOutput.Kind) -> Binding<Bool> {
        Binding(get: { ForkTranscribeOutput.kinds(formats).contains(kind) }, set: { on in
            var kinds = ForkTranscribeOutput.kinds(formats)
            if on { kinds.append(kind) } else { kinds.removeAll { $0 == kind } }
            // At least one file: the last box cannot be unticked.
            guard !kinds.isEmpty else { return }
            formats = ForkTranscribeOutput.stored(kinds)
        })
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { folder = url.path }
    }
}

/// The dashed zone files are dropped on, as in Spokenly: it lights up under
/// a drag, and says so when nothing in the drop can be heard.
struct ForkTranscribeDropZone: View {
    let text: ForkTranscribeStrings
    let enabled: Bool
    @State private var targeted = false
    @State private var refused = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: refused ? "xmark.circle" : "arrow.down.doc")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(refused ? Color.red : Color.accentColor)
                .symbolEffect(.bounce, value: targeted && !reduceMotion)
            Text(refused ? text.dropRefused : text.dropTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(refused ? Color.red : Color.accentColor)
            HStack(spacing: 6) {
                ForEach(ForkTranscribeRules.shownFormats, id: \.self) { format in
                    Text(format)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.85)))
                        .foregroundStyle(.white)
                }
            }
            Button(text.chooseFiles) { choose() }
                .disabled(!enabled)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(targeted ? 0.12 : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(refused ? Color.red : Color.accentColor,
                              style: StrokeStyle(lineWidth: targeted ? 2 : 1.5, dash: targeted ? [] : [7, 5]))
        )
        .scaleEffect(targeted && !reduceMotion ? 1.01 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: targeted)
        .animation(.easeInOut(duration: 0.2), value: refused)
        .opacity(enabled ? 1 : 0.5)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            guard enabled else { return false }
            load(providers)
            return true
        }
    }

    private func choose() {
        guard let urls = ForkTranscribePanel.choose(), !urls.isEmpty else { return }
        added(ForkTranscribeQueue.shared.add(urls))
    }

    private func load(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.withLock { urls.append(url) } }
                group.leave()
            }
        }
        group.notify(queue: .main) { added(ForkTranscribeQueue.shared.add(urls)) }
    }

    private func added(_ count: Int) {
        guard count == 0 else { return }
        refused = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { refused = false }
    }
}

/// Parakeet's state on this Mac, with its install button.
private struct ForkTranscribeModelRow: View {
    let text: ForkTranscribeStrings
    @ObservedObject private var store = ForkParakeetModelStore.shared

    var body: some View {
        HStack {
            switch store.state {
            case .installed:
                Label(text.modelReady, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case let .downloading(progress, _, _):
                ProgressView(value: progress)
                    .frame(width: 120)
                Text(String(format: text.modelDownloading, Int(progress * 100)))
                    .foregroundStyle(.secondary)
            case .verifying:
                ProgressView().controlSize(.small)
                Text(String(format: text.modelDownloading, 100))
                    .foregroundStyle(.secondary)
            case .notInstalled, .failed:
                Label(text.modelMissing, systemImage: "arrow.down.circle")
                    .foregroundStyle(.orange)
                Spacer()
                Button(text.modelInstall) { store.install() }
            }
        }
        .font(.callout)
    }
}

/// One file: its name, length and engine, then where it stands, with what
/// can be done about it.
private struct ForkTranscribeJobRow: View {
    let job: ForkTranscribeJob
    let text: ForkTranscribeStrings
    @ObservedObject private var queue = ForkTranscribeQueue.shared

    private var isVideo: Bool {
        ["mp4", "m4v", "mov", "webm", "mkv", "3gp", "3g2"].contains(job.source.pathExtension.lowercased())
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: isVideo ? "film" : "waveform")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(job.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let duration = job.duration {
                        Text(ForkTranscribeRules.clock(duration))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                status
            }
            Spacer(minLength: 8)
            actions
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if job.stage == .done { queue.reading = job.id } }
        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
    }

    @ViewBuilder
    private var status: some View {
        switch job.stage {
        case .queued:
            caption(text.stageQueued)
        case .waitingForModel:
            caption(text.stageWaitingForModel, color: .orange)
        case .waitingForEngine:
            caption(text.stageWaitingForEngine)
        case .loading:
            busy(text.stageLoading)
        case .waking:
            busy(remote.stageWaking)
        case .waitingForServer:
            busy(remote.stageWaitingForServer, color: .orange)
        case .remoteQueued:
            busy(remote.stageRemoteQueued)
        case .preparing:
            measured(remote.stagePreparing, timed: false)
        case .uploading:
            measured(remote.stageUploading, timed: false)
        case .transcribing:
            measured(text.stageTranscribing, timed: job.engine == .local)
        case .writing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                caption(text.stageWriting)
            }
        case .done:
            VStack(alignment: .leading, spacing: 1) {
                caption(doneLine)
                if job.usedFallbackFolder { caption(text.fallbackNote, color: .orange) }
            }
        case let .failed(failure):
            caption(remote.failure(failure) ?? text.failure(failure), color: .red)
        case .cancelled:
            caption(text.stageCancelled)
        }
    }

    private var remote: ForkTranscribeRemoteStrings { ForkTranscribeRemoteStrings.strings(L10n.shared.language) }

    private func busy(_ label: String, color: Color = .secondary) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            caption(label, color: color)
        }
    }

    /// A step with its bar when the share done is known (a spinner when it is
    /// not: a server that gives none), and the time left for this Mac's work.
    @ViewBuilder
    private func measured(_ label: String, timed: Bool) -> some View {
        if queue.progress < 0 {
            busy(label)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 8) {
                    ProgressView(value: queue.progress)
                        .frame(maxWidth: 180)
                        .animation(.linear(duration: 0.3), value: queue.progress)
                    caption("\(label) \(percent)" + (timed ? remaining(now: context.date) : ""))
                }
            }
        }
    }

    /// "58 %" in French, "58%" in English: the person's own way.
    private var percent: String {
        queue.progress.formatted(.percent.precision(.fractionLength(0)).locale(Locale(identifier: l10nLocale)))
    }

    private var l10nLocale: String { L10n.shared.language.rawValue.replacingOccurrences(of: "-", with: "_") }

    private var doneLine: String {
        var parts: [String] = []
        if let words = job.words { parts.append(String(format: text.doneWords, words)) }
        if let seconds = job.processingSeconds { parts.append(String(format: text.doneIn, ForkTranscribeRules.clock(seconds))) }
        return parts.joined(separator: " · ")
    }

    private func remaining(now: Date) -> String {
        guard let started = job.started,
              let left = ForkTranscribeRules.remaining(fraction: queue.progress, elapsed: now.timeIntervalSince(started))
        else { return "" }
        return " · " + String(format: text.stageRemaining, ForkTranscribeRules.clock(left))
    }

    private func caption(_ string: String, color: Color = .secondary) -> some View {
        Text(string)
            .font(.caption)
            .foregroundStyle(color)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var actions: some View {
        if job.stage.isActive {
            Button { queue.cancel(job.id) } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(text.cancel)
        } else {
            HStack(spacing: 6) {
                if job.stage == .done {
                    Button(text.open) { queue.reading = job.id }
                } else if job.stage == .failed(.unreadable), job.engine == .local,
                          ForkTranscribeSecrets.exists(ForkTranscribeSecrets.studioAccount) {
                    Button(remote.tryOnStudio) { queue.retry(job.id, engine: .studio) }
                } else if case let .failed(failure) = job.stage, failure.isRetryable {
                    Button(text.retry) { queue.retry(job.id) }
                } else if job.stage == .cancelled {
                    Button(text.retry) { queue.retry(job.id) }
                }
                Menu {
                    if let first = job.outputs.first, job.stage == .done {
                        Button(text.showInFinder) { NSWorkspace.shared.activateFileViewerSelecting([first]) }
                    } else {
                        Button(text.showInFinder) { NSWorkspace.shared.activateFileViewerSelecting([job.source]) }
                    }
                    Button(text.copyDiagnostic) { ForkTranscribeClipboard.copy(queue.diagnostic(job.id)) }
                    Divider()
                    Button(text.remove, role: .destructive) { queue.remove(job.id) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
    }
}

enum ForkTranscribeClipboard {
    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

/// A transcription's text: searched, copied whole or for an AI assistant,
/// or shown in the Finder.
struct ForkTranscribeReader: View {
    let id: UUID
    let text: ForkTranscribeStrings
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var queue = ForkTranscribeQueue.shared
    @State private var query = ""
    @State private var copied: String?
    @State private var document: ForkTranscribeDocument?

    private var job: ForkTranscribeJob? { queue.job(id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(16)
            Divider()
            if let document {
                passages(document)
            } else {
                Text(text.textMissing)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
                .padding(12)
        }
        .frame(minWidth: 620, idealWidth: 720, minHeight: 460, idealHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { document = queue.document(id) }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(job?.name ?? "")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(meta)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextField(text.search, text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
        }
    }

    private var meta: String {
        guard let job else { return "" }
        var parts: [String] = []
        if let duration = job.duration { parts.append(ForkTranscribeRules.clock(duration)) }
        if let words = job.words { parts.append(String(format: text.doneWords, words)) }
        if let language = job.heardLanguage { parts.append(language.uppercased()) }
        let remote = ForkTranscribeRemoteStrings.strings(L10n.shared.language)
        switch job.engine {
        case .local: parts.append(text.engineLocal)
        case .studio: parts.append(remote.engineStudio)
        case .openAI: parts.append(remote.engineOpenAI)
        }
        return parts.joined(separator: " · ")
    }

    private func passages(_ document: ForkTranscribeDocument) -> some View {
        let blocks = ForkTranscribeFormat.paragraphs(document.segments)
        let needle = query.trimmingCharacters(in: .whitespaces)
        let shown = needle.isEmpty ? blocks : blocks.filter { $0.text.localizedCaseInsensitiveContains(needle) }
        let labels = labels(document)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if !document.speakers.isEmpty {
                    voices(document, labels: labels)
                    Divider()
                }
                ForEach(Array(shown.enumerated()), id: \.offset) { _, block in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(ForkTranscribeFormat.timestamp(block.start))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            if let who = document.name(of: block.speaker, voice: labels.voice) {
                                Text(who).font(.caption.weight(.semibold))
                            }
                            Text(highlighted(block.text, needle))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func labels(_ document: ForkTranscribeDocument) -> ForkTranscribeFormat.Labels {
        guard let job else {
            return .init(title: { $0 }, summary: "", voice: { String(format: text.voice, $0) }, separator: text.separator)
        }
        return ForkTranscribeQueue.labels(for: document, job: job, language: L10n.shared.language,
                                          model: UserDefaults.standard.string(forKey: ForkDefaultsKey.transcribeOpenAIModel) ?? "",
                                          at: job.finished ?? Date())
    }

    /// The voices the Studio told apart, each with a field to name it.
    private func voices(_ document: ForkTranscribeDocument, labels: ForkTranscribeFormat.Labels) -> some View {
        let remote = ForkTranscribeRemoteStrings.strings(L10n.shared.language)
        return VStack(alignment: .leading, spacing: 6) {
            Text(remote.voicesTitle).font(.subheadline.weight(.semibold))
            Text(remote.voicesHint).font(.caption).foregroundStyle(.secondary)
            ForEach(Array(document.speakers.enumerated()), id: \.element) { index, speaker in
                ForkTranscribeVoiceField(placeholder: String(format: text.voice, index + 1),
                                         initial: document.speakerNames[speaker] ?? "") { name in
                    queue.rename(id, speaker: speaker, to: name)
                    self.document = queue.document(id)
                }
            }
        }
    }

    private func highlighted(_ string: String, _ needle: String) -> AttributedString {
        var attributed = AttributedString(string)
        guard !needle.isEmpty else { return attributed }
        var searchRange = attributed.startIndex..<attributed.endIndex
        while let found = attributed[searchRange].range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) {
            attributed[found].backgroundColor = .yellow.opacity(0.45)
            searchRange = found.upperBound..<attributed.endIndex
        }
        return attributed
    }

    private var footer: some View {
        HStack {
            if let document, let job {
                let labels = labels(document)
                Button(text.copyAll) {
                    ForkTranscribeClipboard.copy(ForkTranscribeFormat.text(document, labels: labels))
                    flash(text.copyAll)
                }
                Button(text.copyForAssistant) {
                    ForkTranscribeClipboard.copy(ForkTranscribeFormat.forAssistant(document, fileName: job.name, labels: labels))
                    flash(text.copyForAssistant)
                }
                if let first = job.outputs.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                    Button(text.showInFinder) { NSWorkspace.shared.activateFileViewerSelecting([first]) }
                }
            }
            if copied != nil {
                Label(text.copied, systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
            Spacer()
            Button(text.close) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    private func flash(_ what: String) {
        withAnimation { copied = what }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { copied = nil } }
    }
}

/// One voice's name in the reader: saved when Return is pressed or the field
/// is left.
private struct ForkTranscribeVoiceField: View {
    let placeholder: String
    let initial: String
    let commit: (String) -> Void
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(placeholder).font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
            TextField(placeholder, text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
                .focused($focused)
                .onSubmit { commit(name) }
                .onChange(of: focused) { _, now in if !now { commit(name) } }
        }
        .onAppear { name = initial }
    }
}

/// A secret's row: "Saved" with Forget once kept, a field and Save before.
/// The secret is never shown again once saved.
private struct ForkTranscribeSecretRow: View {
    let title: String
    let account: String
    let remote: ForkTranscribeRemoteStrings
    var importer: (() -> String?)?
    @State private var saved = false
    @State private var input = ""
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                if saved {
                    Label(remote.secretSaved, systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                    Button(remote.forget) {
                        ForkTranscribeSecrets.delete(account)
                        saved = false
                    }
                } else {
                    SecureField(remote.secretPlaceholder, text: $input)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                        .onSubmit(save)
                    Button(remote.save, action: save)
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if !saved, let importer {
                HStack {
                    Spacer()
                    Button(remote.importToken) {
                        if let token = importer(), ForkTranscribeSecrets.save(token, account: account) {
                            saved = true
                            note = nil
                        } else {
                            note = remote.importFailed
                        }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            if let note {
                Text(note).font(.caption).foregroundStyle(.orange)
            }
        }
        .onAppear { saved = ForkTranscribeSecrets.exists(account) }
    }

    private func save() {
        guard ForkTranscribeSecrets.save(input, account: account) else { return }
        input = ""
        saved = true
        note = nil
    }
}

/// "Test": the server answers with this address and secret, or why not.
private struct ForkTranscribeTestRow: View {
    let remote: ForkTranscribeRemoteStrings
    let check: () throws -> String
    @State private var result: (ok: Bool, text: String)?
    @State private var testing = false

    var body: some View {
        HStack {
            Button(remote.test) {
                testing = true
                result = nil
                DispatchQueue.global(qos: .userInitiated).async {
                    let outcome: (Bool, String)
                    do {
                        outcome = (true, try check())
                    } catch let failure as ForkTranscribeFailure {
                        outcome = (false, remote.failure(failure)
                            ?? ForkTranscribeStrings.strings(L10n.shared.language).failure(failure))
                    } catch {
                        outcome = (false, remote.failureNetwork)
                    }
                    DispatchQueue.main.async {
                        result = outcome
                        testing = false
                    }
                }
            }
            .disabled(testing)
            if testing { ProgressView().controlSize(.small) }
            if let result {
                Label(result.text, systemImage: result.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.ok ? .green : .red)
                    .font(.callout)
            }
            Spacer()
        }
    }
}

/// The Studio: its address, this Mac's token (or the transcrire tool's),
/// and a test.
private struct ForkTranscribeStudioSettings: View {
    let remote: ForkTranscribeRemoteStrings
    @AppStorage(ForkDefaultsKey.transcribeStudioURL) private var address = ForkTranscribeStudioAPI.defaultURL

    var body: some View {
        TextField(remote.addressTitle, text: $address)
        ForkTranscribeSecretRow(title: remote.tokenTitle, account: ForkTranscribeSecrets.studioAccount, remote: remote,
                                importer: ForkTranscribeSecrets.transcrireToken)
        ForkTranscribeTestRow(remote: remote) {
            guard let base = URL(string: address.trimmingCharacters(in: .whitespaces)), base.host != nil,
                  let token = ForkTranscribeSecrets.read(ForkTranscribeSecrets.studioAccount)
            else { throw ForkTranscribeFailure.notConfigured }
            let state = try ForkTranscribeStudioEngine(base: base, token: token).health(stop: ForkMeetingTranscriptStop())
            return state == .waking ? remote.testWaking : remote.testOK
        }
    }
}

/// An OpenAI-compatible service: its address, model and key, and a test.
private struct ForkTranscribeOpenAISettings: View {
    let remote: ForkTranscribeRemoteStrings
    @AppStorage(ForkDefaultsKey.transcribeOpenAIURL) private var address = ForkTranscribeOpenAIAPI.defaultURL
    @AppStorage(ForkDefaultsKey.transcribeOpenAIModel) private var model = ForkTranscribeOpenAIAPI.defaultModel

    var body: some View {
        TextField(remote.addressTitle, text: $address)
        TextField(remote.modelTitle, text: $model)
        ForkTranscribeSecretRow(title: remote.keyTitle, account: ForkTranscribeSecrets.openAIAccount, remote: remote)
        ForkTranscribeTestRow(remote: remote) {
            try ForkTranscribeOpenAIEngine(base: address, model: model,
                                           key: ForkTranscribeSecrets.read(ForkTranscribeSecrets.openAIAccount))
                .check(stop: ForkMeetingTranscriptStop())
            return remote.testOK
        }
    }
}
