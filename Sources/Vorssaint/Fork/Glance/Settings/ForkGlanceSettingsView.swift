// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import SwiftUI

/// The Glance Focus page (Extras › Focus au regard, plan §12), inside the
/// `Form` that `ForkFeatureSettingsPage` lays out under the feature's switch
/// and, when it is missing, the Accessibility row (never doubled here).
///
/// This view only reads the service; `ForkGlanceSettingsContent` draws from
/// a snapshot of it and acts through closures, so the off-screen renders
/// feed it fake states and nothing starts.
struct ForkGlanceSettingsView: View {
    @ObservedObject private var service = ForkGlanceService.shared

    var body: some View {
        ForkGlanceSettingsContent(state: ForkGlanceSettingsState(service), actions: .live)
    }

    /// The « Dynamic Island » row (plan §11.6, §12.9): the island's settings.
    /// The orchestrator adds `SettingsRouter.shared.notchModule = .glance`
    /// here once the island's module exists (B4).
    static func openIslandSettings() {
        SettingsRouter.shared.request(FeatureSettingsDestination(.notch))
    }
}

/// What the page shows of the service, at one moment.
struct ForkGlanceSettingsState {
    var phase: ForkGlancePhase
    var status: ForkGlanceStatusLine
    var layout: ForkGlanceDisplayLayout
    var profile: ForkGlanceProfile?
    var profiles: [ForkGlanceProfile]
    var zones: [ForkGlanceZone]
    var currentZone: String?
    var candidate: ForkGlanceCandidate?
    var recentSwitches: [ForkGlanceSwitchRecord]
    var driftSuggested: Bool
    var layoutMoved: Bool
    var cameraDevices: [ForkGlanceCameraDevice]
    var cameraID: String?
    var cameraPermission: ForkGlanceCameraPermission
    var live: ForkGlanceLive?
    var zoneName: (String) -> String? = { _ in nil }

    init(phase: ForkGlancePhase, status: ForkGlanceStatusLine, layout: ForkGlanceDisplayLayout,
         profile: ForkGlanceProfile? = nil, profiles: [ForkGlanceProfile] = [], zones: [ForkGlanceZone] = [],
         currentZone: String? = nil, candidate: ForkGlanceCandidate? = nil,
         recentSwitches: [ForkGlanceSwitchRecord] = [], driftSuggested: Bool = false, layoutMoved: Bool = false,
         cameraDevices: [ForkGlanceCameraDevice] = [], cameraID: String? = nil,
         cameraPermission: ForkGlanceCameraPermission = .granted, live: ForkGlanceLive? = nil,
         zoneName: @escaping (String) -> String? = { _ in nil }) {
        self.phase = phase
        self.status = status
        self.layout = layout
        self.profile = profile
        self.profiles = profiles
        self.zones = zones
        self.currentZone = currentZone
        self.candidate = candidate
        self.recentSwitches = recentSwitches
        self.driftSuggested = driftSuggested
        self.layoutMoved = layoutMoved
        self.cameraDevices = cameraDevices
        self.cameraID = cameraID
        self.cameraPermission = cameraPermission
        self.live = live
        self.zoneName = zoneName
    }

    init(_ service: ForkGlanceService) {
        self.init(phase: service.phase, status: service.status, layout: service.layout, profile: service.profile,
                  profiles: service.profiles, zones: service.zones, currentZone: service.currentZone,
                  candidate: service.candidate, recentSwitches: service.recentSwitches,
                  driftSuggested: service.driftSuggested, layoutMoved: service.layoutMoved,
                  cameraDevices: service.cameraDevices, cameraID: service.cameraID,
                  cameraPermission: service.cameraPermission, live: service.live,
                  zoneName: { service.zoneName($0) })
    }
}

/// What the page asks of the service.
struct ForkGlanceSettingsActions {
    var pause: (ForkGlancePauseDuration) -> Void
    var resume: () -> Void
    var resumeAnyway: () -> Void
    var recenter: () -> Void
    var setMode: (ForkGlanceMode) -> Void
    var setSplit: (ForkGlanceSplit, String) -> Void
    var deleteProfile: (String) -> Void
    var selectCamera: (String?) -> Void
    var requestCameraPermission: () -> Void
    /// The app came back to the front: the camera permission may have changed.
    var refreshPermission: () -> Void
    var retryCamera: () -> Void
    var openCalibration: (ForkGlanceCalibrationEntry) -> Void
    /// A setting changed on the page (its key is already written).
    var settingsChanged: () -> Void
    var openIslandSettings: () -> Void
    var diagnostics: ForkGlanceDiagnosticsActions

    static var live: ForkGlanceSettingsActions {
        let service = ForkGlanceService.shared
        return ForkGlanceSettingsActions(
            pause: { service.pause($0, from: .settings) },
            resume: { service.resume(from: .settings) },
            resumeAnyway: { service.resumeAnyway() },
            recenter: { service.recenter(from: .settings) },
            setMode: { service.setMode($0) },
            setSplit: { service.setSplit($0, display: $1) },
            deleteProfile: { service.deleteProfile($0) },
            selectCamera: { service.selectCamera($0) },
            requestCameraPermission: { service.requestCameraPermission() },
            refreshPermission: { service.sync() },
            // The same camera chosen again: the session is built anew.
            retryCamera: { service.selectCamera(service.cameraID) },
            openCalibration: { service.openCalibration($0) },
            settingsChanged: { service.sync() },
            openIslandSettings: { ForkGlanceSettingsView.openIslandSettings() },
            diagnostics: .live)
    }

    /// Does nothing: the off-screen renders.
    static let inert = ForkGlanceSettingsActions(
        pause: { _ in }, resume: {}, resumeAnyway: {}, recenter: {}, setMode: { _ in }, setSplit: { _, _ in },
        deleteProfile: { _ in }, selectCamera: { _ in }, requestCameraPermission: {}, refreshPermission: {},
        retryCamera: {}, openCalibration: { _ in }, settingsChanged: {}, openIslandSettings: {},
        diagnostics: .inert)
}

/// The page's sections (plan §12.1 to §12.11). Every setting is its
/// `fork.glance.*` key through `@AppStorage`, the steps through
/// `ForkGlanceTuning`. Off, the page stays adjustable and reads as set back
/// (0.62, like the gestures).
struct ForkGlanceSettingsContent: View {
    let state: ForkGlanceSettingsState
    let actions: ForkGlanceSettingsActions

    @ObservedObject private var l10n = L10n.shared
    @AppStorage(ForkDefaultsKey.glanceEnabled) private var enabled = false
    @AppStorage(ForkDefaultsKey.glanceMode) private var modeRaw = ForkGlanceMode.fallback.rawValue
    @AppStorage(ForkDefaultsKey.glanceSensitivityStep) private var sensitivityStep = ForkGlanceTuning.sensitivity.defaultStep
    @AppStorage(ForkDefaultsKey.glanceDwellStep) private var dwellStep = ForkGlanceTuning.dwell.defaultStep
    @AppStorage(ForkDefaultsKey.glanceDwellScreensStep) private var dwellScreensStep = ForkGlanceTuning.dwellScreens.defaultStep
    @AppStorage(ForkDefaultsKey.glanceTypingPauseStep) private var typingPauseStep = ForkGlanceTuning.typingPause.defaultStep
    @AppStorage(ForkDefaultsKey.glancePointerPauseStep) private var pointerPauseStep = ForkGlanceTuning.pointerPause.defaultStep
    @AppStorage(ForkDefaultsKey.glanceIdleOffStep) private var idleOffStep = ForkGlanceTuning.idleOff.defaultStep
    @AppStorage(ForkDefaultsKey.glanceRaise) private var raise = true
    @AppStorage(ForkDefaultsKey.glancePointer) private var pointerRaw = ForkGlancePointerBehavior.fallback.rawValue
    @AppStorage(ForkDefaultsKey.glanceFeedback) private var feedbackRaw = ForkGlanceFeedback.fallback.rawValue
    @AppStorage(ForkDefaultsKey.glanceLearnFromClicks) private var learnFromClicks = true
    @AppStorage(ForkDefaultsKey.glancePanes) private var panes = false
    @AppStorage(ForkDefaultsKey.glancePanesClickFallback) private var panesClickFallback = false
    @AppStorage(ForkDefaultsKey.glanceEnergy) private var energyRaw = ForkGlanceEnergy.fallback.rawValue
    @AppStorage(ForkDefaultsKey.glanceOnBattery) private var batteryRaw = ForkGlanceBatteryPolicy.fallback.rawValue
    @AppStorage(ForkDefaultsKey.glancePauseInLowPower) private var pauseInLowPower = true
    @AppStorage(ForkDefaultsKey.glanceDuringCalls) private var callsRaw = ForkGlanceCallPolicy.fallback.rawValue
    @AppStorage(DefaultsKey.focusFollowsMouseEnabled) private var focusFollowsMouse = false
    @State private var diagnosticsOpen: Bool
    @State private var pendingDelete: ForkGlanceProfile?

    init(state: ForkGlanceSettingsState, actions: ForkGlanceSettingsActions, diagnosticsOpen: Bool = false) {
        self.state = state
        self.actions = actions
        _diagnosticsOpen = State(initialValue: diagnosticsOpen)
    }

    private var mode: ForkGlanceMode { ForkGlanceMode(rawValue: modeRaw) ?? .fallback }

    var body: some View {
        let language = l10n.language
        let text = ForkGlanceSettingsStrings.strings(language)
        let core = ForkGlanceStrings.strings(language)
        let locale = language.formattingLocale()

        Section {
            header(text, core, locale)
        }

        Group {
            banners(text, core)
            Section(text.permissionsTitle) {
                ForkGlanceCameraRow(permission: state.cameraPermission, text: text,
                                    request: actions.requestCameraPermission, refresh: actions.refreshPermission)
            }
            calibrationSection(text, core, locale)
            layoutSection(text, core)
            behaviorSection(text, core, locale)
            Section(text.appsTitle) {
                ForkGlanceAppLists(text: text, changed: actions.settingsChanged)
            }
            cameraSection(text, core, locale)
            shortcutsSection(text, core)
            Section(text.islandTitle) {
                SettingsRow(symbol: "macbook", title: text.islandRow, caption: text.islandRowCaption) {
                    Button(text.islandOpen, action: actions.openIslandSettings)
                        .controlSize(.small)
                }
            }
            privacySection(text)
            diagnosticsSection(text, core, locale)
        }
        .opacity(enabled ? 1 : 0.62)
        .animation(.easeInOut(duration: 0.18), value: enabled)
        .alert(pendingDelete.map { ForkGlanceStrings.fill(text.deleteProfileTitle, $0.title) } ?? "",
               isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button(text.delete, role: .destructive) {
                if let profile = pendingDelete { actions.deleteProfile(profile.id) }
                pendingDelete = nil
            }
            Button(text.cancel, role: .cancel) { pendingDelete = nil }
        } message: {
            Text(text.deleteProfileMessage)
        }
    }

    // MARK: - Header (plan §12.1)

    private func header(_ text: ForkGlanceSettingsStrings, _ core: ForkGlanceStrings, _ locale: Locale) -> some View {
        HStack(alignment: .center, spacing: 18) {
            ForkGlanceHeroCard(isOn: enabled && state.phase.isWatching)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text(core.status(state.status, locale: locale, now: context.date))
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: ForkGlancePresentation.symbol(state.phase))
                            .foregroundStyle(Self.color(ForkGlancePresentation.tint(state.phase)))
                    }
                    if let detail = detail(core, locale, now: context.date) {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    headerButtons(core)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }

    /// The line under the status: the last switch while active, the remedy
    /// of a single screen in Screens mode.
    private func detail(_ core: ForkGlanceStrings, _ locale: Locale, now: Date) -> String? {
        switch state.status {
        case .active, .waiting:
            return state.recentSwitches.first.map { core.lastSwitchLine($0.date, now: now, locale: locale) }
        case .paused(.singleScreen, _):
            return core.singleScreenHint
        default:
            return nil
        }
    }

    @ViewBuilder
    private func headerButtons(_ core: ForkGlanceStrings) -> some View {
        switch state.phase {
        case .paused(.user, _):
            Button(core.resume, action: actions.resume)
                .buttonStyle(.borderedProminent)
        case .paused(.singleScreen, _):
            Button(core.switchToZones) { choose(.zones) }
        case .paused(let reason, _) where reason.canResumeAnyway:
            Button(core.resumeAnyway, action: actions.resumeAnyway)
        case .unavailable(.cameraPermission) where state.cameraPermission == .notDetermined:
            Button(core.allowCamera, action: actions.requestCameraPermission)
                .buttonStyle(.borderedProminent)
        case let phase where phase.isWatching:
            HStack(spacing: 8) {
                Menu {
                    ForEach(ForkGlancePauseDuration.allCases, id: \.self) { duration in
                        Button(core.pauseDurationName(duration)) { actions.pause(duration) }
                    }
                } label: {
                    Label(core.pause, systemImage: "eye.slash")
                }
                .fixedSize()
                Button(action: actions.recenter) {
                    Label(core.recenter, systemImage: "scope")
                }
            }
        default:
            EmptyView()
        }
    }

    static func color(_ tint: ForkGlancePresentation.Tint) -> Color {
        switch tint {
        case .active: return .accentColor
        case .idle: return .secondary
        case .paused: return .orange
        case .warning: return .yellow
        case .error: return .red
        }
    }

    // MARK: - Banners (plan §9)

    @ViewBuilder
    private func banners(_ text: ForkGlanceSettingsStrings, _ core: ForkGlanceStrings) -> some View {
        switch state.phase {
        case .needsCalibration(let need):
            Section {
                ForkGlanceBanner(symbol: "viewfinder", color: .yellow, title: core.calibrationNeed(need),
                                 caption: text.calibrationCaption) {
                    Button(core.calibrateEllipsis) { actions.openCalibration(need == .firstTime ? .full : .recalibrate) }
                        .buttonStyle(.borderedProminent)
                }
            }
        case .unavailable(let reason) where reason == .noCamera || reason == .cameraDisconnected || reason == .cameraFailed:
            Section {
                ForkGlanceBanner(symbol: "video.slash.fill", color: .red, title: core.unavailable(reason),
                                 caption: text.cameraProblemCaption) {
                    HStack(spacing: 8) {
                        Button(core.retry, action: actions.retryCamera)
                        if !state.cameraDevices.isEmpty {
                            Menu(core.chooseCamera) {
                                ForEach(state.cameraDevices) { device in
                                    Button(device.name) { actions.selectCamera(device.id) }
                                }
                            }
                            .fixedSize()
                        }
                    }
                }
            }
        default:
            EmptyView()
        }
        if state.driftSuggested && state.phase != .off {
            Section {
                ForkGlanceBanner(symbol: "exclamationmark.bubble.fill", color: .yellow, title: core.noticeDrift,
                                 caption: text.driftCaption) {
                    Button(core.recalibrate) { actions.openCalibration(.recalibrate) }
                }
            }
        }
        if state.layoutMoved && state.phase != .off {
            Section {
                ForkGlanceBanner(symbol: "rectangle.2.swap", color: .blue, title: text.layoutMovedTitle,
                                 caption: text.layoutMovedCaption) {
                    Button(core.quickRecenter) { actions.openCalibration(.quickRecenter) }
                }
            }
        }
    }

    // MARK: - Calibration (plan §12.3)

    private func calibrationSection(_ text: ForkGlanceSettingsStrings, _ core: ForkGlanceStrings,
                                    _ locale: Locale) -> some View {
        let calibration = state.profile?.calibration
        let others = ForkGlanceSettingsRules.otherProfiles(state.profiles, current: state.profile?.id)
        return Section(text.calibrationTitle) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26, height: 26)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.profile?.title ?? ForkGlanceProfiles.title(for: state.layout))
                    Text(profileCaption(calibration, text, core, locale))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if let score = ForkGlanceSettingsRules.score(calibration) {
                    ForkGlanceGradeBadge(score: score, core: core, locale: locale)
                }
            }
            HStack(spacing: 8) {
                if calibration == nil {
                    Button(core.calibrateEllipsis) { actions.openCalibration(.full) }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(core.calibrateEllipsis) { actions.openCalibration(.recalibrate) }
                    Button(core.quickRecenter) { actions.openCalibration(.quickRecenter) }
                    Button(core.test) { actions.openCalibration(.test) }
                }
                Spacer(minLength: 8)
                if let profile = state.profile {
                    Button(text.deleteProfile, role: .destructive) { pendingDelete = profile }
                }
            }
            .controlSize(.small)
            .padding(.leading, settingsRowTextInset)
            Text(text.calibrationCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, settingsRowTextInset)
            if !others.isEmpty {
                DisclosureGroup {
                    ForEach(others) { profile in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(profile.title)
                                    .lineLimit(1)
                                Text(profileCaption(profile.calibration, text, core, locale))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            if let score = ForkGlanceSettingsRules.score(profile.calibration) {
                                ForkGlanceGradeBadge(score: score, core: core, locale: locale)
                            }
                            Button {
                                pendingDelete = profile
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(text.deleteProfile)
                            .accessibilityLabel(text.deleteProfile)
                        }
                    }
                } label: {
                    HStack {
                        Text(text.otherProfiles)
                        Spacer()
                        Text("\(others.count)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    /// « Calibré le 23 oct. 2026 · Tête et yeux », or « Pas encore calibré ».
    private func profileCaption(_ calibration: ForkGlanceCalibration?, _ text: ForkGlanceSettingsStrings,
                                _ core: ForkGlanceStrings, _ locale: Locale) -> String {
        guard let calibration else { return text.notCalibrated }
        let date = calibration.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale))
        return ForkGlanceStrings.fill(text.calibratedOn, date) + " · " + (calibration.usesEyes ? core.headAndEyes : core.headOnly)
    }

    // MARK: - Layout and mode (plan §12.4)

    private func layoutSection(_ text: ForkGlanceSettingsStrings, _ core: ForkGlanceStrings) -> some View {
        let splits = ForkGlanceSettingsRules.splits(profile: state.profile, layout: state.layout)
        let zones = ForkGlanceSettingsRules.mapZones(mode: mode, layout: state.layout, splits: splits,
                                                     liveZones: state.zones)
        let watching = enabled && state.phase.isWatching
        let fit = ForkGlanceSettingsRules.fit(mode, layout: state.layout, calibration: state.profile?.calibration)
        return Section(text.layoutTitle) {
            if state.layout.displays.isEmpty {
                Text(text.noDisplays)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForkGlanceLayoutMap(layout: state.layout, zones: zones,
                                        activeZone: watching ? state.currentZone : nil,
                                        candidate: watching ? state.candidate : nil, style: .settings,
                                        splits: splits,
                                        onSplit: mode == .zones ? { uuid, split in actions.setSplit(split, uuid) } : nil)
                        .frame(maxWidth: .infinity, maxHeight: 200)
                    if mode == .zones {
                        Text(text.mapCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            VStack(alignment: .leading, spacing: 6) {
                SettingsChoiceRow(symbol: Self.symbol(mode), title: text.modeTitle,
                                  selection: Binding(get: { mode }, set: { choose($0) })) {
                    ForEach(ForkGlanceMode.allCases, id: \.self) { mode in
                        Text(core.modeName(mode)).tag(mode)
                    }
                }
                Group {
                    Text(core.modeCaption(mode))
                        .foregroundStyle(.secondary)
                    fitLine(fit, text, core)
                }
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, settingsRowTextInset)
            }
            if mode == .windows {
                ForkGlanceSwitchRow(symbol: "rectangle.split.3x1", title: core.panes, caption: text.panesCaption,
                                    isOn: $panes)
                if panes {
                    ForkGlanceSwitchRow(symbol: "cursorarrow.click.2", title: text.panesClickFallback,
                                        caption: text.panesClickFallbackCaption, isOn: $panesClickFallback)
                    ForkGlanceAppList(key: ForkDefaultsKey.glancePanesApps, title: text.panesAppsTitle,
                                      caption: text.panesAppsCaption, text: text,
                                      fallback: ForkGlanceDefaults.defaultPanesApps, changed: actions.settingsChanged)
                }
            }
        }
        .onChange(of: panes) { _, _ in actions.settingsChanged() }
        .onChange(of: panesClickFallback) { _, _ in actions.settingsChanged() }
    }

    @ViewBuilder
    private func fitLine(_ fit: ForkGlanceModeFit, _ text: ForkGlanceSettingsStrings, _ core: ForkGlanceStrings) -> some View {
        switch fit {
        case .suited:
            Label(core.modeSuited, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .singleScreen:
            Label(core.singleScreenHint, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .lowPrecision:
            Label(core.modeDiscouraged, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .unknown:
            Label(text.modeUnknownFit, systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func choose(_ mode: ForkGlanceMode) {
        guard mode.rawValue != modeRaw else { return }
        modeRaw = mode.rawValue
        actions.setMode(mode)
    }

    static func symbol(_ mode: ForkGlanceMode) -> String {
        switch mode {
        case .screens: return "display.2"
        case .zones: return "rectangle.split.2x1"
        case .windows: return "macwindow.on.rectangle"
        }
    }

    // MARK: - Behavior (plan §12.5)

    private func behaviorSection(_ text: ForkGlanceSettingsStrings, _ core: ForkGlanceStrings,
                                 _ locale: Locale) -> some View {
        let dwell = ForkGlanceSettingsRules.dwellTuning(for: mode)
        let pointer = ForkGlancePointerBehavior(rawValue: pointerRaw) ?? .fallback
        return Section(text.behaviorTitle) {
            ForkGlanceStepRow(symbol: "dial.medium", title: text.sensitivityTitle, tuning: .sensitivity,
                              step: $sensitivityStep, low: core.sensitivityCautious, high: core.sensitivityLively,
                              locale: locale, never: core.never, changed: actions.settingsChanged)
            ForkGlanceStepRow(symbol: "timer", title: text.dwellTitle, tuning: dwell,
                              step: mode == .screens ? $dwellScreensStep : $dwellStep, locale: locale,
                              never: core.never, changed: actions.settingsChanged)
            ForkGlanceStepRow(symbol: "keyboard", title: text.typingPauseTitle, tuning: .typingPause,
                              step: $typingPauseStep, locale: locale, never: core.never,
                              changed: actions.settingsChanged)
            ForkGlanceStepRow(symbol: "computermouse", title: text.pointerPauseTitle, tuning: .pointerPause,
                              step: $pointerPauseStep, locale: locale, never: core.never,
                              changed: actions.settingsChanged)
            ForkGlanceSwitchRow(symbol: "macwindow", title: text.raiseTitle, caption: text.raiseCaption, isOn: $raise)
            VStack(alignment: .leading, spacing: 6) {
                SettingsMenuRow(symbol: "cursorarrow", title: text.pointerTitle, selection: $pointerRaw) {
                    ForEach(ForkGlancePointerBehavior.allCases, id: \.self) { behavior in
                        Text(core.pointerName(behavior)).tag(behavior.rawValue)
                    }
                }
                if pointer == .auto || focusFollowsMouse {
                    VStack(alignment: .leading, spacing: 4) {
                        if pointer == .auto {
                            Text(text.pointerAutoCaption)
                        }
                        if focusFollowsMouse {
                            Label(text.pointerFocusFollowsMouse, systemImage: "info.circle")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, settingsRowTextInset)
                }
            }
            SettingsChoiceRow(symbol: "sparkles", title: text.feedbackTitle, selection: $feedbackRaw) {
                ForEach(ForkGlanceFeedback.allCases, id: \.self) { feedback in
                    Text(core.feedbackName(feedback)).tag(feedback.rawValue)
                }
            }
            ForkGlanceSwitchRow(symbol: "cursorarrow.click", title: text.learnTitle, caption: text.learnCaption,
                                isOn: $learnFromClicks)
        }
        .onChange(of: raise) { _, _ in actions.settingsChanged() }
        .onChange(of: pointerRaw) { _, _ in actions.settingsChanged() }
        .onChange(of: feedbackRaw) { _, _ in actions.settingsChanged() }
        .onChange(of: learnFromClicks) { _, _ in actions.settingsChanged() }
    }

    // MARK: - Camera and energy (plan §12.7)

    private func cameraSection(_ text: ForkGlanceSettingsStrings, _ core: ForkGlanceStrings,
                               _ locale: Locale) -> some View {
        let devices = state.cameraDevices
        let camera = Binding<String>(
            get: { state.cameraID.flatMap { id in devices.contains { $0.id == id } ? id : nil } ?? "" },
            set: { actions.selectCamera($0.isEmpty ? nil : $0) })
        return Section(text.cameraEnergyTitle) {
            VStack(alignment: .leading, spacing: 6) {
                SettingsMenuRow(symbol: "camera", title: text.camera, selection: camera) {
                    Text(text.cameraAutomatic).tag("")
                    ForEach(devices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                HStack {
                    Spacer()
                    Button(text.checkFraming) { actions.openCalibration(.framing) }
                        .controlSize(.small)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                SettingsChoiceRow(symbol: "bolt", title: text.energyTitle, selection: $energyRaw) {
                    ForEach(ForkGlanceEnergy.allCases, id: \.self) { energy in
                        Text(core.energyName(energy)).tag(energy.rawValue)
                    }
                }
                caption(text.energyCaption)
            }
            SettingsChoiceRow(symbol: "battery.75", title: text.batteryTitle, selection: $batteryRaw) {
                ForEach(ForkGlanceBatteryPolicy.allCases, id: \.self) { policy in
                    Text(core.batteryPolicyName(policy)).tag(policy.rawValue)
                }
            }
            ForkGlanceSwitchRow(symbol: "leaf", title: text.lowPowerTitle, caption: nil, isOn: $pauseInLowPower)
            ForkGlanceStepRow(symbol: "moon.zzz", title: text.idleOffTitle, tuning: .idleOff, step: $idleOffStep,
                              caption: text.idleOffCaption, locale: locale, never: core.never,
                              changed: actions.settingsChanged)
            VStack(alignment: .leading, spacing: 6) {
                SettingsChoiceRow(symbol: "video", title: text.callsTitle, selection: $callsRaw) {
                    ForEach(ForkGlanceCallPolicy.allCases, id: \.self) { policy in
                        Text(core.callPolicyName(policy)).tag(policy.rawValue)
                    }
                }
                caption(text.callsCaption)
            }
            VStack(alignment: .leading, spacing: 4) {
                SettingsRow(symbol: "speedometer", title: text.costTitle, caption: costLine(text, locale)) {
                    EmptyView()
                }
                caption(text.costCameraNote)
            }
        }
        .onChange(of: energyRaw) { _, _ in actions.settingsChanged() }
        .onChange(of: batteryRaw) { _, _ in actions.settingsChanged() }
        .onChange(of: pauseInLowPower) { _, _ in actions.settingsChanged() }
        .onChange(of: callsRaw) { _, _ in actions.settingsChanged() }
    }

    /// Shown while the feature runs (plan §10.4).
    private func costLine(_ text: ForkGlanceSettingsStrings, _ locale: Locale) -> String {
        guard enabled, state.phase.isWatching else { return text.costNotRunning }
        guard let cost = ForkGlanceSettingsRules.cost(cpuCores: state.live?.cpuCores, watts: state.live?.watts,
                                                      locale: locale) else { return text.costMeasuring }
        return cost.watts.map { ForkGlanceStrings.fill(text.costLine, cost.cpu, $0) }
            ?? ForkGlanceStrings.fill(text.costCPUOnly, cost.cpu)
    }

    private func caption(_ string: String) -> some View {
        Text(string)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, settingsRowTextInset)
    }

    // MARK: - Shortcuts (plan §12.8)

    private func shortcutsSection(_ text: ForkGlanceSettingsStrings, _ core: ForkGlanceStrings) -> some View {
        Section(text.shortcutsTitle) {
            ForkGlanceShortcutRow(role: .pause, label: core.shortcutPauseResume, text: text,
                                  changed: actions.settingsChanged)
            ForkGlanceShortcutRow(role: .recenter, label: core.shortcutRecenter, text: text,
                                  changed: actions.settingsChanged)
            ForkGlanceShortcutRow(role: .mode, label: core.shortcutMode, text: text, changed: actions.settingsChanged)
            Text(text.recenterCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Privacy (plan §12.10)

    private func privacySection(_ text: ForkGlanceSettingsStrings) -> some View {
        Section(text.privacyTitle) {
            VStack(alignment: .leading, spacing: 8) {
                privacyLine("memorychip", text.privacyAnalyzed)
                privacyLine("number", text.privacyNothingSaved)
                privacyLine("lock.laptopcomputer", text.privacyStaysHere)
                privacyLine("person.crop.circle.badge.xmark", text.privacyNoRecognition)
                privacyLine("smallcircle.filled.circle", text.privacyLight, color: .green)
            }
            .padding(.vertical, 2)
        }
    }

    private func privacyLine(_ symbol: String, _ string: String, color: Color = .secondary) -> some View {
        Label {
            Text(string)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 18)
        }
        .font(.callout)
    }

    // MARK: - Diagnostics (plan §12.11)

    private func diagnosticsSection(_ text: ForkGlanceSettingsStrings, _ core: ForkGlanceStrings,
                                    _ locale: Locale) -> some View {
        Section {
            DisclosureGroup(isExpanded: $diagnosticsOpen) {
                // Built only while open: its lease is the whole cost.
                if diagnosticsOpen {
                    ForkGlanceDiagnosticsView(live: state.live, phase: state.phase, layout: state.layout,
                                              zones: state.zones, currentZone: state.currentZone,
                                              lastSwitch: state.recentSwitches.first?.date, text: text, core: core,
                                              locale: locale, actions: actions.diagnostics, zoneName: state.zoneName)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label(text.diagnosticsTitle, systemImage: "waveform.path.ecg")
                    Text(text.diagnosticsCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Rows

/// A banner above the page's sections (plan §9): a missing calibration in
/// yellow, a failing camera in red, a drift, a layout that moved.
private struct ForkGlanceBanner<Buttons: View>: View {
    let symbol: String
    let color: Color
    let title: String
    let caption: String
    @ViewBuilder let buttons: () -> Buttons

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .fontWeight(.semibold)
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                buttons()
                    .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .listRowBackground(color.opacity(0.09))
    }
}

/// « Excellente · 97 % » in the grade's color.
private struct ForkGlanceGradeBadge: View {
    let score: Double
    let core: ForkGlanceStrings
    let locale: Locale

    var body: some View {
        let grade = ForkGlanceGrade(score: score)
        Text(core.gradeName(grade) + " · " + ForkGlanceStrings.percent(score, locale: locale))
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(color(grade))
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(color(grade).opacity(0.14), in: Capsule())
            .fixedSize()
    }

    private func color(_ grade: ForkGlanceGrade) -> Color {
        switch grade {
        case .excellent: return .green
        case .good: return .teal
        case .fair: return .orange
        case .poor: return .red
        }
    }
}

/// A switch on the trailing edge, with its icon and caption.
private struct ForkGlanceSwitchRow: View {
    let symbol: String
    let title: String
    let caption: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(symbol: symbol, title: title, caption: caption) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

/// A ladder of steps (`ForkGlanceTuning`) as a slider, like the gestures':
/// its value beside the title, its ends under it.
private struct ForkGlanceStepRow: View {
    let symbol: String
    let title: String
    let tuning: ForkGlanceTuning
    @Binding var step: Int
    var low: String? = nil
    var high: String? = nil
    var caption: String? = nil
    let locale: Locale
    let never: String
    let changed: () -> Void

    var body: some View {
        let last = tuning.steps.count - 1
        VStack(alignment: .leading, spacing: 4) {
            SettingsRow(symbol: symbol, title: title, caption: caption) {
                if let value = ForkGlanceSettingsRules.stepValue(tuning, step: step, locale: locale, never: never) {
                    Text(value)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                Text(low ?? ForkGlanceSettingsRules.stepValue(tuning, step: 0, locale: locale, never: never) ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: Binding(get: { Double(tuning.clampedStep(step)) },
                                      set: { step = tuning.clampedStep(Int($0.rounded())) }),
                       in: 0...Double(last), step: 1) {
                    Text(title)
                }
                .labelsHidden()
                Text(high ?? ForkGlanceSettingsRules.stepValue(tuning, step: last, locale: locale, never: never) ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, settingsRowTextInset)
        }
        .onChange(of: step) { _, _ in changed() }
    }
}

/// One global shortcut: its field, its ✕ and what is wrong with it, like
/// the meetings' rows. A combination that cannot work is not saved.
private struct ForkGlanceShortcutRow: View {
    let role: ForkGlanceShortcutRole
    let label: String
    let text: ForkGlanceSettingsStrings
    let changed: () -> Void

    @AppStorage private var stored: String
    @AppStorage(ForkDefaultsKey.glanceEnabled) private var enabled = false
    /// The problem of the combination just typed, or of the stored one,
    /// read once per change: asking the window server on every redraw would
    /// make the page lag.
    @State private var problem: ForkMeetingShortcutProblem?

    init(role: ForkGlanceShortcutRole, label: String, text: ForkGlanceSettingsStrings, changed: @escaping () -> Void) {
        self.role = role
        self.label = label
        self.text = text
        self.changed = changed
        _stored = AppStorage(wrappedValue: "", role.key)
    }

    /// Shown in the field when there is none: `emptyTitle` hides it.
    private var placeholder: GlobalShortcut {
        switch role {
        case .pause: return GlobalShortcut(keyCode: 5, modifiers: [.control, .option, .command])
        case .recenter: return GlobalShortcut(keyCode: 15, modifiers: [.control, .option, .command])
        case .mode: return GlobalShortcut(keyCode: 46, modifiers: [.control, .option, .command])
        }
    }

    private var shortcut: GlobalShortcut? {
        _ = stored
        return ForkGlanceShortcuts.load(role: role)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(label)
                Spacer()
                ShortcutRecorderButton(
                    shortcut: shortcut ?? placeholder,
                    isEnabled: enabled,
                    waitingTitle: text.shortcutPrompt,
                    emptyTitle: shortcut == nil ? text.shortcutNone : nil,
                    clearAction: { save(nil) },
                    invalidAction: { problem = .needsModifier },
                    captureAction: { save($0) })
                    .frame(width: 140)
                    .accessibilityLabel(label)
                if shortcut != nil {
                    Button {
                        save(nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(text.shortcutRemove)
                    .accessibilityLabel(text.shortcutRemove)
                }
            }
            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { problem = shortcut.flatMap { ForkGlanceShortcuts.problem(of: $0, role: role) } }
    }

    private var warning: String? {
        switch problem {
        case .reservedKey: return text.shortcutReserved
        case .needsModifier: return text.shortcutNeedsModifier
        case .conflict: return text.shortcutConflict
        case nil: return nil
        }
    }

    private func save(_ captured: GlobalShortcut?) {
        if let captured, let refusal = ForkGlanceShortcuts.problem(of: captured, role: role) {
            problem = refusal
            return
        }
        problem = nil
        ForkGlanceShortcuts.save(captured, role: role)
        changed()
    }
}
