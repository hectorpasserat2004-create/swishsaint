// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// « Options » (plan §11.1): what is rarely touched, by theme.
struct ForkMacBackupOptionsSheet: View {
    @ObservedObject var context: ForkMacBackupSettingsContext
    @State var tab: ForkMacBackupOptionsTab
    let open: (ForkMacBackupSheet) -> Void

    @ObservedObject private var l10n = L10n.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.forkMacBackupSheetHeight) private var heightOverride

    init(context: ForkMacBackupSettingsContext, tab: ForkMacBackupOptionsTab, open: @escaping (ForkMacBackupSheet) -> Void) {
        self.context = context
        _tab = State(initialValue: tab)
        self.open = open
    }

    private var text: ForkMacBackupSettingsStrings { .strings(l10n.language) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ForkMacBackupIconTile(symbol: "slider.horizontal.3", color: .gray, size: 30)
                Text(text.optionsTitle)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            Picker(text.optionsTitle, selection: $tab) {
                ForEach(ForkMacBackupOptionsTab.allCases) { tab in
                    Label(text.optionsTab(tab), systemImage: tab.symbol).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.top, 10)
            Form {
                switch tab {
                case .retention: ForkMacBackupRetentionPane(context: context)
                case .verifications: ForkMacBackupVerificationsPane(context: context)
                case .notifications: ForkMacBackupNotificationsPane(context: context)
                case .advanced: ForkMacBackupAdvancedPane(context: context, open: open)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button(text.done) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 640, height: heightOverride ?? 680)
        .onAppear { context.loadRecords() }
    }
}

// MARK: - Retention

struct ForkMacBackupRetentionPane: View {
    @ObservedObject var context: ForkMacBackupSettingsContext
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(ForkDefaultsKey.macBackupRetentionPreset) private var presetRaw = ForkMacBackupRetention.Preset.fallback.rawValue
    @AppStorage(ForkDefaultsKey.macBackupRetentionCustom) private var customRaw = ForkMacBackupRetention.balanced.storageValue
    @State private var draftPreset: ForkMacBackupRetention.Preset?
    @State private var draftCustom: ForkMacBackupRetention?
    /// This Mac's snapshots, one list per source (Kopia's retention is per source).
    @State private var snapshots: [[ForkMacBackupRetentionReplay.Snapshot]]?
    @State private var sizes: [String: Int64] = [:]
    @State private var loading = false
    @State private var loadFailed = false
    @State private var confirming = false

    private var text: ForkMacBackupSettingsStrings { .strings(l10n.language) }
    private var locale: Locale { l10n.language.formattingLocale() }

    private var savedPreset: ForkMacBackupRetention.Preset { ForkMacBackupRetention.Preset(rawValue: presetRaw) ?? .fallback }
    private var preset: ForkMacBackupRetention.Preset { draftPreset ?? savedPreset }
    private var saved: ForkMacBackupRetention { ForkMacBackupRetention.preset(savedPreset, custom: customRaw) }
    private var retention: ForkMacBackupRetention {
        preset == .custom ? (draftCustom ?? ForkMacBackupRetention.parse(customRaw) ?? .balanced)
            : ForkMacBackupRetention.preset(preset, custom: customRaw)
    }
    private var isDraft: Bool { retention != saved || preset != savedPreset }

    var body: some View {
        Section {
            Picker(text.retentionHeader, selection: Binding(get: { preset }, set: { draftPreset = $0 })) {
                ForEach(ForkMacBackupRetention.Preset.allCases, id: \.self) { preset in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(text.retentionPresetName(preset))
                        if preset != .custom {
                            Text(text.retentionShort(ForkMacBackupRetention.preset(preset, custom: ""), language: l10n.language, locale: locale))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(preset)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            if preset == .custom {
                customSteppers
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                ForkMacBackupCaption(text.retentionExplain(retention, language: l10n.language, locale: locale))
            }
        } header: {
            Text(text.retentionHeader)
        }

        Section {
            deletionPreview
        } header: {
            Text(text.retentionPreviewHeader)
        } footer: {
            if isDraft {
                HStack {
                    Spacer()
                    Button(text.cancel) {
                        draftPreset = nil
                        draftCustom = nil
                    }
                    Button(text.apply) { applyOrConfirm() }
                        .buttonStyle(.borderedProminent)
                        .tint(ForkMacBackupStyle.accent)
                }
            }
        }
        .onAppear { if snapshots == nil, !loading, context.repository != nil { load() } }
        .alert(text.retentionConfirmTitle, isPresented: $confirming) {
            Button(text.cancel, role: .cancel) {}
            Button(text.apply, role: .destructive) { apply() }
        } message: {
            Text(String(format: text.retentionConfirmMessage, deletions.count))
        }

        Section {
            maintenance
        } header: {
            Text(text.maintenanceHeader)
        } footer: {
            ForkMacBackupCaption(text.maintenanceFooter)
        }
    }

    private var customSteppers: some View {
        let value = retention
        return Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            stepper(text.keepLatest, value.latest) { draft(\.latest, $0) }
            stepper(text.keepHourly, value.hourly) { draft(\.hourly, $0) }
            stepper(text.keepDaily, value.daily) { draft(\.daily, $0) }
            stepper(text.keepWeekly, value.weekly) { draft(\.weekly, $0) }
            stepper(text.keepMonthly, value.monthly) { draft(\.monthly, $0) }
            stepper(text.keepAnnual, value.annual) { draft(\.annual, $0) }
        }
    }

    private func draft(_ key: WritableKeyPath<ForkMacBackupRetention, Int>, _ value: Int) {
        var next = retention
        next[keyPath: key] = max(0, value)
        draftCustom = next
        draftPreset = .custom
    }

    private func stepper(_ label: String, _ value: Int, set: @escaping (Int) -> Void) -> some View {
        GridRow {
            Text(label)
            HStack {
                Spacer()
                Text(value.formatted(.number.locale(locale)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Stepper(label, value: Binding(get: { value }, set: set), in: 0...999)
                    .labelsHidden()
            }
        }
    }

    private var deletions: [ForkMacBackupRetentionReplay.Snapshot] {
        guard let snapshots else { return [] }
        return snapshots.flatMap { ForkMacBackupRetentionReplay.deletions($0, retention: retention) }
            .sorted { $0.startTime > $1.startTime }
    }

    private var snapshotCount: Int { snapshots?.reduce(0) { $0 + $1.count } ?? 0 }

    @ViewBuilder
    private var deletionPreview: some View {
        if snapshots != nil {
            let gone = deletions
            if gone.isEmpty {
                Label(String(format: text.retentionKeepsAll, snapshotCount), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else {
                Label(String(format: text.retentionWouldDelete, gone.count, snapshotCount), systemImage: "trash")
                    .foregroundStyle(.orange)
                    .font(.callout)
                ForEach(gone.prefix(6), id: \.id) { snapshot in
                    HStack {
                        Text(ForkMacBackupFormat.dayAndTime(snapshot.startTime, locale: locale))
                            .font(.caption)
                        Spacer()
                        if let bytes = sizes[snapshot.id] {
                            Text(ForkMacBackupFormat.bytes(bytes, locale: locale))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if gone.count > 6 {
                    ForkMacBackupCaption(String(format: text.andMore, gone.count - 6))
                }
            }
        } else if loading {
            HStack {
                ProgressView().controlSize(.small)
                ForkMacBackupCaption(text.retentionLoading)
            }
        } else {
            HStack {
                ForkMacBackupCaption(loadFailed ? text.engineUnavailable : text.retentionPreviewCaption)
                Spacer()
                Button(text.retentionPreviewButton) { load() }
                    .disabled(context.repository == nil)
            }
        }
    }

    private func load() {
        guard let engine = context.services.makeEngine() else {
            loadFailed = true
            return
        }
        loading = true
        let identity = context.repository?.clientIdentity
        engine.listSnapshots(source: nil) { result in
            loading = false
            switch result {
            case .success(let manifests):
                let own = manifests.filter { manifest in
                    guard let identity else { return true }
                    return manifest.source?.userName == identity.userName && manifest.source?.host == identity.hostName
                }
                let bySource = Dictionary(grouping: own) { $0.source?.path ?? "" }
                snapshots = bySource.values.map { $0.compactMap(ForkMacBackupRetentionReplay.Snapshot.init(manifest:)) }
                sizes = Dictionary(own.compactMap { manifest in
                    (manifest.stats?.totalSize ?? manifest.rootEntry?.summ?.size).map { (manifest.id, $0) }
                }, uniquingKeysWith: { first, _ in first })
            case .failure:
                loadFailed = true
            }
        }
    }

    private func applyOrConfirm() {
        if deletions.count > 3 {
            confirming = true
        } else {
            apply()
        }
    }

    private func apply() {
        if preset == .custom { customRaw = retention.storageValue }
        presetRaw = preset.rawValue
        draftPreset = nil
        draftCustom = nil
        context.send(.reloadSettings)
    }

    @ViewBuilder
    private var maintenance: some View {
        if let last = context.records.maintenance.last {
            LabeledContent(text.maintenanceLast) {
                Text(ForkMacBackupFormat.dayAndTime(last.start, locale: locale) + " · " + text.outcome(last.outcome))
                    .foregroundStyle(last.outcome == .complete ? .secondary : Color.orange)
            }
            if let duration = last.duration {
                LabeledContent(text.duration, value: ForkMacBackupFormat.duration(duration, locale: locale))
            }
        } else {
            LabeledContent(text.maintenanceLast, value: ForkMacBackupStrings.strings(l10n.language).never)
        }
        if let bytes = context.status.presentation.capacity.repositoryBytes {
            LabeledContent(text.repositorySizeLabel, value: ForkMacBackupFormat.bytes(bytes, locale: locale))
        }
    }
}

// MARK: - Verifications

struct ForkMacBackupVerificationsPane: View {
    @ObservedObject var context: ForkMacBackupSettingsContext
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(ForkDefaultsKey.macBackupVerifyPlan) private var planRaw = "refs:7d,files1:1d,restore50:30d"

    private var text: ForkMacBackupSettingsStrings { .strings(l10n.language) }
    private var shared: ForkMacBackupStrings { .strings(l10n.language) }
    private var locale: Locale { l10n.language.formattingLocale() }
    private var plan: ForkMacBackupVerifyPlan { ForkMacBackupVerifyPlan.parse(planRaw) }

    static let periods: [Int?] = [nil, 24, 7 * 24, 30 * 24]

    var body: some View {
        Section {
            ForEach(ForkMacBackupVerifyPlan.Level.allCases, id: \.self) { level in
                levelRow(level)
            }
        } header: {
            Text(text.verifyPlanHeader)
        } footer: {
            ForkMacBackupCaption(text.verifyPlanFooter)
        }

        Section {
            Menu {
                Button(text.verifyLevelTitle(.references)) { context.send(.verify(.references)) }
                Button(text.verifyLevelTitle(.contentSample)) { context.send(.verify(.contentSample(percent: 1))) }
                Button(text.verifyLevelTitle(.restoreTest)) { context.send(.verify(.restoreTest(files: 50))) }
                Divider()
                Button(text.verifyFull) { context.send(.verify(.full)) }
            } label: {
                Label(text.verifyNow, systemImage: "checkmark.shield")
            }
            .menuStyle(.button)
            .fixedSize()
            ForkMacBackupCaption(text.verifyFullCaption)
            Button(text.openVerifications) { ForkMacBackupWindow.open(.verifications) }
                .buttonStyle(.link)
        } header: {
            Text(text.verifyNowHeader)
        }
    }

    private func levelRow(_ level: ForkMacBackupVerifyPlan.Level) -> some View {
        let entry = plan.entry(level)
        return VStack(alignment: .leading, spacing: 4) {
            Picker(selection: Binding(get: { entry?.everyHours }, set: { hours in
                var next = plan
                next.set(level, everyHours: hours)
                planRaw = next.storageValue
            })) {
                ForEach(Self.periods, id: \.self) { hours in
                    Text(text.period(hours, locale: locale)).tag(hours)
                }
                if let hours = entry?.everyHours, !Self.periods.contains(hours) {
                    Text(text.period(hours, locale: locale)).tag(Optional(hours))
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.verifyLevelTitle(level))
                    ForkMacBackupCaption(text.verifyLevelCaption(level))
                }
            }
            lastResult(level)
        }
    }

    @ViewBuilder
    private func lastResult(_ level: ForkMacBackupVerifyPlan.Level) -> some View {
        if let record = context.records.last(level) {
            let ok = record.outcome == .complete
            Label(String(format: ok ? text.verifyLastOK : text.verifyLastFailed,
                         ForkMacBackupFormat.relative(record.start, now: context.services.now(), locale: locale)),
                  systemImage: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .font(.caption)
                .foregroundStyle(ok ? Color.green : Color.red)
        } else {
            Label(text.verifyNever, systemImage: "circle.dashed")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Notifications

struct ForkMacBackupNotificationsPane: View {
    @ObservedObject var context: ForkMacBackupSettingsContext
    @ObservedObject private var l10n = L10n.shared
    /// Bumped on each change, so the rows redraw (their keys are many).
    @State private var revision = 0

    private var text: ForkMacBackupSettingsStrings { .strings(l10n.language) }
    /// The same switches as the island's Activity card: the same words.
    private var island: ForkMacBackupIslandStrings { .strings(l10n.language) }

    var body: some View {
        Section {
            ForEach(ForkMacBackupNoticeEvent.allCases, id: \.self) { event in
                Toggle(title(event), isOn: binding(event))
            }
            .id(revision)
        } header: {
            Text(text.notifyHeader)
        } footer: {
            ForkMacBackupCaption(island.noticesCaption)
        }
    }

    private func title(_ event: ForkMacBackupNoticeEvent) -> String {
        switch event {
        case .complete: return island.noticeComplete
        case .partial: return island.noticePartial
        case .failure: return island.noticeFailed
        case .restoreDone: return island.noticeRestore
        }
    }

    private func isOn(_ event: ForkMacBackupNoticeEvent) -> Bool {
        _ = revision
        return context.defaults.object(forKey: ForkDefaultsKey.macBackupNotice(event)) as? Bool ?? event.defaultOn
    }

    private func binding(_ event: ForkMacBackupNoticeEvent) -> Binding<Bool> {
        Binding(get: { isOn(event) },
                set: { context.defaults.set($0, forKey: ForkDefaultsKey.macBackupNotice(event)); revision += 1 })
    }
}

// MARK: - Advanced

struct ForkMacBackupAdvancedPane: View {
    @ObservedObject var context: ForkMacBackupSettingsContext
    let open: (ForkMacBackupSheet) -> Void
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(ForkDefaultsKey.macBackupWatchdogMinutes) private var watchdogMinutes = 10
    @AppStorage(ForkDefaultsKey.macBackupRepositoryTimeout) private var repositoryTimeout = 60
    @AppStorage(ForkDefaultsKey.macBackupProbeTimeout) private var probeTimeout = 5
    @State private var confirmingDisconnect = false
    @State private var message: String?

    private var text: ForkMacBackupSettingsStrings { .strings(l10n.language) }
    private var locale: Locale { l10n.language.formattingLocale() }

    var body: some View {
        Section {
            LabeledContent(text.engineVersion) {
                switch context.engineState {
                case .installed(let version): Text("Kopia \(version)")
                case .downloading(let progress): Text(ForkMacBackupFormat.percent(progress, locale: locale))
                case .verifying: Text(text.engineVerifying)
                case .notInstalled: Text(text.engineNotInstalled).foregroundStyle(.orange)
                case .failed: Text(text.engineFailed).foregroundStyle(.orange)
                }
            }
            HStack {
                Text(text.cacheSize)
                Spacer()
                Text(context.records.cacheBytes.map { ForkMacBackupFormat.bytes($0, locale: locale) } ?? "–")
                    .foregroundStyle(.secondary)
                Button(text.showInFinder) { reveal(context.repositoryFiles?.cache) }
                    .controlSize(.small)
                    .disabled(context.repositoryFiles == nil)
            }
            Button(text.reinstallEngine) { context.engineStore.install() }
        } header: {
            Text(text.engineHeader)
        }

        Section {
            ForkMacBackupStepperRow(title: text.watchdog, value: String(format: text.minutesValue, watchdogMinutes), number: $watchdogMinutes, range: 2...120)
            ForkMacBackupStepperRow(title: text.repositoryTimeout, value: String(format: text.secondsValue, repositoryTimeout), number: $repositoryTimeout, range: 10...600, step: 10)
            ForkMacBackupStepperRow(title: text.probeTimeout, value: String(format: text.secondsValue, probeTimeout), number: $probeTimeout, range: 1...60)
        } header: {
            Text(text.timeoutsHeader)
        }

        Section {
            Button(text.openLogs) { reveal(context.repositoryFiles?.logs) }
                .disabled(context.repositoryFiles == nil)
            Button(text.exportDiagnostic) { exportDiagnostic() }
            Button(text.openTerminal) { openTerminal() }
                .disabled(context.repositoryFiles == nil)
            ForkMacBackupCaption(text.openTerminalCaption)
        } header: {
            Text(text.toolsHeader)
        }

        Section {
            Button(text.importBran) { open(.wizard(.bran)) }
            ForkMacBackupCaption(text.importBranCaption)
            Button(text.disconnect, role: .destructive) { confirmingDisconnect = true }
                .foregroundStyle(.red)
                .disabled(context.repository == nil)
            ForkMacBackupCaption(text.disconnectCaption)
            if let message {
                ForkMacBackupCaption(message, color: .orange)
            }
        } header: {
            Text(text.connectionHeader)
        }
        .alert(text.disconnectConfirmTitle, isPresented: $confirmingDisconnect) {
            Button(text.cancel, role: .cancel) {}
            Button(text.disconnect, role: .destructive) { context.disconnect() }
        } message: {
            Text(text.disconnectCaption)
        }
    }

    private func reveal(_ url: URL?) {
        guard let url else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            message = text.folderMissing
        }
    }

    private func exportDiagnostic() {
        let status = context.status
        var settings: [String: String] = [:]
        for key in ForkMacBackupDefaults.registered.keys {
            if let value = context.defaults.object(forKey: key) { settings[key] = String(describing: value) }
        }
        var engineVersion: String?
        if case .installed(let version) = context.engineState { engineVersion = version }
        let input = ForkMacBackupDiagnostic.Input(
            appName: ForkMacBackupAppName.current,
            appBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?",
            agentBuild: status.agentBuild, agentAlive: status.agentAlive, engineVersion: engineVersion,
            registration: context.registration, fullDiskAccess: context.fullDiskAccess,
            presentation: status.presentation, repository: context.repository, profileName: context.profile?.name,
            sources: context.effectiveSources, settings: settings, now: context.services.now())
        let data = Data(ForkMacBackupDiagnostic.text(input).utf8)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "mac-backup-diagnostic.txt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                message = text.fileNotSaved
            }
        }
    }

    private func openTerminal() {
        guard let files = context.repositoryFiles, let paths = context.paths,
              case .installed(let version) = context.engineState else {
            message = text.engineNotInstalled
            return
        }
        let script = ForkMacBackupTerminalScript.text(
            engineBinary: paths.engineBinary(version: version).path, config: files.config.path,
            cache: files.cache.path, logs: files.logs.path, accessKeyID: context.repository?.accessKeyID,
            passwordPrompt: text.terminalPasswordPrompt, secretPrompt: text.terminalSecretPrompt,
            banner: text.terminalBanner)
        let url = paths.run.appendingPathComponent("terminal.command", isDirectory: false)
        guard PrivateFileStore.createDirectory(at: paths.run, container: PrivateFileStore.containerURL),
              PrivateFileStore.write(Data(script.utf8), to: url) else {
            message = text.fileNotSaved
            return
        }
        chmod(url.path, 0o700)
        NSWorkspace.shared.open(url)
    }
}
