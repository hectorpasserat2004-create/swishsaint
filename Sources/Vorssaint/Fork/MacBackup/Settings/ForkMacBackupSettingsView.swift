// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import SwiftUI

/// What the page opens over itself.
enum ForkMacBackupSheet: Identifiable, Equatable {
    case content
    case rhythm
    case kit
    case options(ForkMacBackupOptionsTab)
    case wizard(ForkMacBackupWizardStart)

    var id: String {
        switch self {
        case .content: return "content"
        case .rhythm: return "rhythm"
        case .kit: return "kit"
        case .options(let tab): return "options.\(tab.rawValue)"
        case .wizard(let start): return "wizard.\(start.id)"
        }
    }
}

/// The « Sauvegarde du Mac » page, below its switch (plan §11.1): simple,
/// efficient, beautiful. At first glance only the state, the chain drawn
/// from the profile and four rows; everything else waits in a sheet. Until
/// the Mac is set up, the five steps of « Mise en route » come first.
struct ForkMacBackupSettingsView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var context: ForkMacBackupSettingsContext
    @ObservedObject private var status: ForkMacBackupStatusModel
    @ObservedObject private var engineStore: ForkMacBackupEngineStore
    @ObservedObject private var agentLink: ForkMacBackupAgentLink
    @AppStorage(ForkDefaultsKey.macBackupEnabled) private var enabled = false
    @AppStorage(ForkDefaultsKey.macBackupScheduleMode) private var scheduleMode = ForkMacBackupScheduleMode.fallback.rawValue
    @AppStorage(ForkDefaultsKey.macBackupIntervalHours) private var intervalHours = 4
    @AppStorage(ForkDefaultsKey.macBackupTimes) private var times = "13:00,21:00"
    @AppStorage(ForkDefaultsKey.macBackupPresets) private var presetsStorage = ""
    @AppStorage(ForkDefaultsKey.macBackupRules) private var rulesStorage = ""
    @AppStorage(ForkDefaultsKey.macBackupRetentionPreset) private var retentionPreset = "balanced"
    @State private var sheet: ForkMacBackupSheet?

    init() {
        self.init(context: .shared)
    }

    init(context: ForkMacBackupSettingsContext, sheet: ForkMacBackupSheet? = nil) {
        _context = ObservedObject(wrappedValue: context)
        _status = ObservedObject(wrappedValue: context.status)
        _engineStore = ObservedObject(wrappedValue: context.engineStore)
        _agentLink = ObservedObject(wrappedValue: context.agentLink)
        _sheet = State(initialValue: sheet)
    }

    var body: some View {
        let language = l10n.language
        let text = ForkMacBackupSettingsStrings.strings(language)
        let shared = ForkMacBackupStrings.strings(language)
        let setup = context.setup

        if let error = status.presentation.lastError, context.repository != nil, enabled {
            ForkMacBackupFailureBanner(error: error, text: text, shared: shared, context: context) { sheet = $0 }
        }

        if !setup.isReady {
            Section {
                ForkMacBackupSetupCard(text: text, setup: setup, context: context, enabled: enabled) { sheet = $0 }
            }
        }

        if context.repository != nil {
            Section {
                ForkMacBackupStatusCard(text: text, shared: shared, language: language, context: context,
                                        presentation: status.presentation)
            }
            .disabled(!enabled)

            Section {
                ForkMacBackupChainCard(text: text, shared: shared, language: language, context: context,
                                       presentation: status.presentation) { sheet = $0 }
            }
            .disabled(!enabled)
        }

        Section {
            ForkMacBackupNavigationRow(symbol: "folder.fill", color: .blue, title: text.contentTitle,
                                       summary: contentSummary(text, shared, language)) { sheet = .content }
            ForkMacBackupNavigationRow(symbol: "clock.fill", color: .indigo, title: text.rhythmTitle,
                                       summary: rhythmSummary(shared, language)) { sheet = .rhythm }
            kitRow(text, language)
            ForkMacBackupNavigationRow(symbol: "slider.horizontal.3", color: .gray, title: text.optionsTitle,
                                       summary: optionsSummary(text)) { sheet = .options(.retention) }
        }
        .disabled(!enabled && context.repository != nil)
        .sheet(item: $sheet) { sheet in
            sheetView(sheet)
                .environment(\.locale, language.formattingLocale())
        }
    }

    // MARK: Rows

    private func contentSummary(_ text: ForkMacBackupSettingsStrings, _ shared: ForkMacBackupStrings,
                                _ language: AppLanguage) -> String {
        _ = presetsStorage
        _ = rulesStorage
        let sources = context.effectiveSources
        let what = sources.count == 1 && sources[0].path == context.home
            ? text.homeFolder
            : (sources.count == 1 ? sources[0].displayName : text.folderCount(sources.count, language: language))
        var parts = [what]
        let size = context.preview?.includedBytes ?? status.presentation.capacity.protectedBytes
        if let size { parts.append(ForkMacBackupFormat.bytes(size, locale: language.formattingLocale())) }
        parts.append(text.exclusionCount(context.presets.count + context.customRules.count, language: language))
        return parts.joined(separator: " · ")
    }

    private func rhythmSummary(_ shared: ForkMacBackupStrings, _ language: AppLanguage) -> String {
        var presentation = status.presentation
        presentation.rhythm = ForkMacBackupRhythmSettings.rhythm(mode: scheduleMode, hours: intervalHours, times: times,
                                                                 measured: status.presentation.rhythm)
        return presentation.rhythmLine(shared, locale: language.formattingLocale())
    }

    @ViewBuilder
    private func kitRow(_ text: ForkMacBackupSettingsStrings, _ language: AppLanguage) -> some View {
        let locale = language.formattingLocale()
        switch context.kitStatus {
        case .missing:
            ForkMacBackupNavigationRow(symbol: "lifepreserver.fill", color: .orange, title: text.kitTitle,
                                       summary: context.repository == nil ? text.kitNeedsConnection : text.kitMissing,
                                       summaryColor: context.repository == nil ? .secondary : .orange) { sheet = .kit }
        case .upToDate(let date):
            ForkMacBackupNavigationRow(symbol: "lifepreserver.fill", color: .orange, title: text.kitTitle,
                                       summary: String(format: text.kitUpToDate, ForkMacBackupDay.text(date, locale: locale, now: context.services.now())))
            { sheet = .kit }
        case .repositoryChanged:
            ForkMacBackupNavigationRow(symbol: "lifepreserver.fill", color: .orange, title: text.kitTitle,
                                       summary: text.kitStaleChanged, summaryColor: .orange) { sheet = .kit }
        case .reminderDue(let date):
            ForkMacBackupNavigationRow(symbol: "lifepreserver.fill", color: .orange, title: text.kitTitle,
                                       summary: String(format: text.kitStaleOld, ForkMacBackupDay.text(date, locale: locale, now: context.services.now())),
                                       summaryColor: .orange) { sheet = .kit }
        }
    }

    private func optionsSummary(_ text: ForkMacBackupSettingsStrings) -> String {
        let preset = ForkMacBackupRetention.Preset(rawValue: retentionPreset) ?? .fallback
        return text.retentionPresetName(preset) + " · " + text.optionsSummary
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetView(_ sheet: ForkMacBackupSheet) -> some View {
        switch sheet {
        case .content:
            ForkMacBackupContentSheet(context: context)
        case .rhythm:
            ForkMacBackupRhythmSheet(context: context)
        case .kit:
            ForkMacBackupKitSheet(context: context) { self.sheet = $0 }
        case .options(let tab):
            ForkMacBackupOptionsSheet(context: context, tab: tab) { self.sheet = $0 }
        case .wizard(let start):
            ForkMacBackupWizard(context: context, start: start) { next in self.sheet = next }
        }
    }
}

/// The rhythm the settings ask for, as the presentation words it.
enum ForkMacBackupRhythmSettings {
    static func rhythm(mode: String, hours: Int, times: String,
                       measured: ForkMacBackupPresentation.Rhythm) -> ForkMacBackupPresentation.Rhythm {
        let list = ForkMacBackupTimes.parse(times).map(ForkMacBackupTimes.clock)
        switch ForkMacBackupScheduleMode(rawValue: mode) ?? .fallback {
        case .auto:
            if case .automatic(let about) = measured { return .automatic(about: about) }
            return .automatic(about: nil)
        case .interval: return .interval(hours: max(1, hours))
        case .times: return .times(list)
        case .both: return .both(hours: max(1, hours), times: list)
        }
    }
}

// MARK: - Failure banner

/// The last failure, its cause and its remedy, with the button that fixes
/// it (modelled on `ForkMeetingFailureBanner`).
private struct ForkMacBackupFailureBanner: View {
    let error: ForkMacBackupPresentation.ErrorLine
    let text: ForkMacBackupSettingsStrings
    let shared: ForkMacBackupStrings
    let context: ForkMacBackupSettingsContext
    let open: (ForkMacBackupSheet) -> Void

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(error.cause == .chainBroken || error.cause == .wrongRepository ? .red : .orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .fontWeight(.semibold)
                    Text(error.cause.remedy(shared))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                Button(actionTitle) { act() }
                    .controlSize(.small)
            }
        }
    }

    private var title: String {
        let cause = error.cause.title(shared)
        guard error.cause == .chainBroken, let nodeID = error.nodeID,
              let node = context.chain.first(where: { $0.id == nodeID }) else { return cause }
        return String(format: text.bannerNodeDown, node.displayTitle(shared))
    }

    private var actionTitle: String {
        switch error.cause {
        case .wrongRepository: return text.editConnection
        case .authentication: return text.updatePassword
        case .engineMissing, .engineStopped: return text.reinstallEngine
        case .diskAccess: return text.openSystemSettings
        default: return text.tryAgain
        }
    }

    private func act() {
        switch error.cause {
        case .wrongRepository: open(.wizard(.edit(.server)))
        case .authentication: open(.wizard(.edit(.repository)))
        case .engineMissing, .engineStopped: context.engineStore.install()
        case .diskAccess: Permissions.shared.openFullDiskAccessSettings()
        default: context.send(.backUpNow)
        }
    }
}
