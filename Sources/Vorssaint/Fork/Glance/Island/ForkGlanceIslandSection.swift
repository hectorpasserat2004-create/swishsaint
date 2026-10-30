// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import SwiftUI

/// The island's « Regard » section (⌥⌘L, seams `notch-glance*`, plan
/// §11.1): the map of the displays at the scale of their millimeters with
/// the zone the keyboard is in filled, the zone being entered filling, and
/// the live gaze dot when the person asked for it; under it the state in
/// words and the calibration's score. Beside the camera the three modes on
/// the left; Recenter, Pause ▾ (or Resume) and the feature's page on the
/// right. Spacious, the last switches and Calibrate, Test beside the map.
/// A pause, a drift or a new layout lays its band over the map, with the
/// one button it asks for. Off, a permission or the camera missing: the
/// island's empty state with its next step.
///
/// Reads only `ForkGlanceService`'s published state; in the Settings
/// preview a fixed made-up layout, and nothing starts.
struct ForkGlanceIslandSection: View {
    @ObservedObject var service: NotchService
    let size: CGSize
    @ObservedObject private var glance: ForkGlanceService
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(ForkDefaultsKey.glanceIslandLiveDot) private var liveDot = false
    @AppStorage(ForkDefaultsKey.glanceIslandHistory) private var history = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.notchSettingsPreview) private var preview
    /// A fixed state (the render harness); nil: the service's.
    private let snapshot: ForkGlanceIslandSnapshot?
    /// A fixed clock (the render harness); nil: now.
    private let fixedNow: Date?

    init(service: NotchService, size: CGSize, glance: ForkGlanceService = .shared,
         snapshot: ForkGlanceIslandSnapshot? = nil, now: Date? = nil) {
        self.service = service
        self.size = size
        _glance = ObservedObject(wrappedValue: glance)
        self.snapshot = snapshot
        fixedNow = now
    }

    private var core: ForkGlanceStrings { ForkGlanceStrings.strings(l10n.language) }
    private var text: ForkGlanceIslandStrings { ForkGlanceIslandStrings.strings(l10n.language) }
    private var locale: Locale { l10n.language.formattingLocale() }
    private var spacious: Bool { ForkGlanceIslandRules.isSpacious(height: Double(size.height)) }
    /// Nothing acts and nothing is asked of the service: the Settings
    /// preview, or a fixed state.
    private var inert: Bool { preview || snapshot != nil }

    private var state: ForkGlanceIslandSnapshot {
        if let snapshot { return snapshot }
        if preview { return .preview(language: l10n.language, now: fixedNow ?? Date()) }
        return ForkGlanceIslandSnapshot(service: glance)
    }

    var body: some View {
        let state = state
        let top = ForkGlanceIslandRules.top(state.phase)
        Group {
            switch top {
            case .off:
                NotchEmptyView(symbol: "eyes", message: core.featureOff) {
                    NotchPillButton(title: core.enable, prominent: true) {
                        act { service.perform { ForkGlanceIsland.openFeatureSettings() } }
                    }
                }
            case .unavailable(let reason):
                unavailable(reason)
            default:
                // A timed pause's minutes and the calibration's age move by themselves.
                TimelineView(.periodic(from: Date(), by: 30)) { context in
                    page(state, top: top, now: fixedNow ?? context.date)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .notchBand(leading: { leadingBand(state, top: top) }, trailing: { trailingBand(state, top: top) })
        .modifier(ForkGlanceLiveLeaseHolder(
            active: ForkGlanceIslandRules.holdsLiveLease(liveDot: liveDot, preview: inert, top: top)))
        .animation(reduceMotion ? nil : .smooth(duration: 0.26), value: top)
    }

    // MARK: - Empty states

    @ViewBuilder private func unavailable(_ reason: ForkGlanceUnavailable) -> some View {
        switch reason {
        case .cameraPermission:
            NotchEmptyView(symbol: "video.slash", message: core.unavailable(reason)) {
                NotchPillButton(title: core.allowCamera, prominent: true) {
                    act { service.perform { ForkGlanceService.shared.requestCameraPermission() } }
                }
            }
        case .accessibilityPermission:
            NotchEmptyView(symbol: "accessibility", message: core.unavailable(reason)) {
                NotchPillButton(title: core.allowAccessibility, prominent: true) {
                    act { service.perform { Permissions.shared.requestAccessibility() } }
                }
            }
        case .noCamera, .cameraDisconnected, .cameraFailed:
            NotchEmptyView(symbol: "video.slash", message: core.unavailable(reason)) {
                HStack(spacing: 8) {
                    if reason != .noCamera {
                        NotchPillButton(title: core.retry, prominent: true) {
                            act { ForkGlanceService.shared.selectCamera(ForkGlanceService.shared.cameraID) }
                        }
                    }
                    NotchPillButton(title: core.chooseCamera, prominent: reason == .noCamera) {
                        act { service.perform { ForkGlanceService.shared.openSettings() } }
                    }
                }
            }
        }
    }

    // MARK: - The page

    private func page(_ state: ForkGlanceIslandSnapshot, top: ForkGlanceIslandRules.Top, now: Date) -> some View {
        let banner = ForkGlanceIslandRules.banner(top, pausedUntil: state.pausedUntil,
                                                  driftSuggested: state.driftSuggested, layoutMoved: state.layoutMoved)
        return VStack(alignment: .leading, spacing: NotchLayout.rowSpacing) {
            if let banner {
                bannerRow(banner, now: now)
                    .transition(reduceMotion ? .identity : .notchFadeThrough)
            }
            if spacious {
                HStack(alignment: .top, spacing: 12) {
                    map(state, top: top, now: now)
                    side(state, now: now)
                        .frame(width: 216)
                }
            } else {
                map(state, top: top, now: now)
            }
            statusRow(state, top: top, banner: banner, now: now)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(reduceMotion ? nil : .smooth(duration: 0.26), value: banner)
    }

    // MARK: Band

    @ViewBuilder private func leadingBand(_ state: ForkGlanceIslandSnapshot, top: ForkGlanceIslandRules.Top) -> some View {
        if ForkGlanceIslandRules.band(top).modes {
            HStack(spacing: 2) {
                ForEach(ForkGlanceMode.allCases, id: \.self) { mode in
                    NotchIconButton(symbol: ForkGlanceIslandRules.symbol(for: mode), title: core.modeName(mode),
                                    selected: state.mode == mode) {
                        act { ForkGlanceService.shared.setMode(mode) }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(text.modes)
        }
    }

    @ViewBuilder private func trailingBand(_ state: ForkGlanceIslandSnapshot, top: ForkGlanceIslandRules.Top) -> some View {
        let band = ForkGlanceIslandRules.band(top)
        if band.recenter {
            NotchIconButton(symbol: "scope", title: core.recenter) {
                act { ForkGlanceService.shared.recenter(from: .island) }
            }
        }
        switch band.pause {
        case .menu: pauseMenu
        case .none: EmptyView()
        }
        if band.settings {
            NotchIconButton(symbol: "arrow.up.forward.app", title: core.openSettings) {
                act { service.perform { ForkGlanceService.shared.openSettings() } }
            }
        }
    }

    /// « Pause ▾ »: 15 minutes, an hour, until tomorrow, until resumed. Never `Menu`.
    private var pauseMenu: some View {
        let items = ForkGlanceIslandRules.pauseChoices.map { duration in
            NotchMenuItem(title: core.pauseDurationName(duration),
                          symbol: duration == .untilResumed ? "pause.circle" : "clock") {
                act { ForkGlanceIsland.pause(duration) }
            }
        }
        return NotchMenuButton(title: core.pause, items: items, cornerRadius: 9) {
            Image(systemName: "eye.slash")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 28, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .help(core.pause)
    }

    // MARK: Banner

    private func bannerRow(_ banner: ForkGlanceIslandRules.Banner, now: Date) -> some View {
        let content = bannerContent(banner, now: now)
        return HStack(spacing: 10) {
            Image(systemName: content.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(content.warning ? Color.orange : .white.opacity(0.85))
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(content.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 6)
            NotchPillButton(title: content.button, prominent: true) { act(content.action) }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .modifier(NotchControlSurface(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }

    private struct BannerContent {
        let symbol: String
        let title: String
        let button: String
        let warning: Bool
        let action: () -> Void
    }

    private func bannerContent(_ banner: ForkGlanceIslandRules.Banner, now: Date) -> BannerContent {
        let glance = ForkGlanceService.shared
        let calibrate: (ForkGlanceCalibrationEntry) -> () -> Void = { entry in
            { service.perform { glance.openCalibration(entry) } }
        }
        switch banner {
        case .paused(let until):
            return BannerContent(symbol: "eye.slash", title: core.pauseBanner(until: until, locale: locale, now: now),
                                 button: core.resume, warning: false) { glance.resume(from: .island) }
        case .resumeAnyway(let reason):
            return BannerContent(symbol: "eye.slash", title: core.status(.paused(reason, until: nil), locale: locale, now: now),
                                 button: core.resumeAnyway, warning: false) { glance.resumeAnyway() }
        case .drift:
            return BannerContent(symbol: "viewfinder", title: core.noticeDrift, button: core.recalibrate, warning: true,
                                 action: calibrate(.recalibrate))
        case .layoutMoved:
            // The same displays moved a little: a quick recenter is enough (plan §8.6, the page's banner).
            return BannerContent(symbol: "display.2", title: text.layoutMovedTitle, button: core.quickRecenter, warning: true,
                                 action: calibrate(.quickRecenter))
        case .calibrate(let need):
            return BannerContent(symbol: "viewfinder", title: core.calibrationNeed(need), button: core.calibrate,
                                 warning: true, action: calibrate(.full))
        }
    }

    // MARK: Map

    private func map(_ state: ForkGlanceIslandSnapshot, top: ForkGlanceIslandRules.Top, now: Date) -> some View {
        let active = ForkGlanceIslandRules.mapActiveZone(state.phase, current: state.currentZone)
        let watching = top == .watching
        let dot = watching && liveDot && !preview ? state.gazePoint : nil
        return ForkGlanceLayoutMap(layout: state.layout, zones: state.zones, activeZone: active,
                                   candidate: watching ? state.candidate : nil, gazePoint: dot, style: .island)
            .opacity(ForkGlanceIslandRules.mapDimmed(top) ? 0.55 : 1)
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: active)
            .animation(reduceMotion ? nil : .spring(response: 0.18), value: dot)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text.mapLabel)
            .accessibilityValue(core.status(state.status, locale: locale, now: now))
    }

    // MARK: Lines

    private func statusRow(_ state: ForkGlanceIslandSnapshot, top: ForkGlanceIslandRules.Top,
                           banner: ForkGlanceIslandRules.Banner?, now: Date) -> some View {
        let score = scoreLine(state, now: now)
        return HStack(spacing: 8) {
            if ForkGlanceIslandRules.showsStatus(banner: banner) {
                Text(core.status(state.status, locale: locale, now: now))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(statusColor(state.status))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentTransition(.opacity)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 8)
            if let score {
                Text(score)
                    .font(.system(size: 11)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
        }
        .frame(height: 16)
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: state.status)
    }

    private func statusColor(_ line: ForkGlanceStatusLine) -> Color {
        switch line {
        case .active: return .white.opacity(0.9)
        case .unavailable: return Color(nsColor: .systemRed)
        case .needsCalibration: return .orange
        default: return .white.opacity(0.6)
        }
    }

    /// « Calibrage 97 % · il y a 3 j ».
    private func scoreLine(_ state: ForkGlanceIslandSnapshot, now: Date) -> String? {
        // While a calibration runs, the old score beside « Calibrage en cours » would read as its own.
        guard ForkGlanceIslandRules.top(state.phase) != .calibrating,
              let calibration = state.calibration, let score = ForkGlanceIslandRules.score(calibration) else { return nil }
        return core.calibrationScoreLine(score, date: calibration.date, now: now, locale: locale)
    }

    // MARK: Spacious

    private func side(_ state: ForkGlanceIslandSnapshot, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if history {
                VStack(alignment: .leading, spacing: 3) {
                    Text(core.recentSwitches)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .accessibilityAddTraits(.isHeader)
                    let records = ForkGlanceIslandRules.history(state.recentSwitches, date: \.date)
                    if records.isEmpty {
                        Text(text.historyEmpty)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    ForEach(records) { record in
                        switchRow(record)
                    }
                }
            }
            Spacer(minLength: 0)
            // The assistant is already open while it calibrates.
            if ForkGlanceIslandRules.top(state.phase) != .calibrating {
                calibrateButtons(state)
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    /// Calibrate (prominent until there is a calibration) and Test.
    private func calibrateButtons(_ state: ForkGlanceIslandSnapshot) -> some View {
        HStack(spacing: 6) {
            let calibrated = state.calibration != nil
            NotchPillButton(title: core.calibrate, prominent: !calibrated) {
                act { service.perform { ForkGlanceService.shared.openCalibration(calibrated ? .recalibrate : .full) } }
            }
            if calibrated {
                NotchPillButton(title: core.test) {
                    act { service.perform { ForkGlanceService.shared.openCalibration(.test) } }
                }
            }
        }
    }

    private func switchRow(_ record: ForkGlanceSwitchRecord) -> some View {
        HStack(spacing: 6) {
            Text(record.appName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Text(record.zoneName)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(-1)
            Spacer(minLength: 4)
            Text(ForkGlanceStrings.time(record.date, locale: locale))
                .font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
        }
        .frame(height: 14)
        .accessibilityElement(children: .combine)
    }

    // MARK: Parts

    /// Runs an action, except in the Settings preview and a fixed state.
    private func act(_ action: () -> Void) {
        guard !inert else { return }
        action()
    }
}

/// What the section draws, read from the service at once (or made up for
/// the Settings preview and the render harness).
struct ForkGlanceIslandSnapshot {
    var phase: ForkGlancePhase
    var status: ForkGlanceStatusLine
    var mode: ForkGlanceMode
    var layout: ForkGlanceDisplayLayout
    var zones: [ForkGlanceZone]
    var currentZone: String?
    var candidate: ForkGlanceCandidate?
    var pausedUntil: Date?
    var calibration: ForkGlanceCalibration?
    var recentSwitches: [ForkGlanceSwitchRecord] = []
    var driftSuggested = false
    var layoutMoved = false
    var gazePoint: CGPoint?

    init(phase: ForkGlancePhase, status: ForkGlanceStatusLine, mode: ForkGlanceMode, layout: ForkGlanceDisplayLayout,
         zones: [ForkGlanceZone], currentZone: String? = nil, candidate: ForkGlanceCandidate? = nil,
         pausedUntil: Date? = nil, calibration: ForkGlanceCalibration? = nil,
         recentSwitches: [ForkGlanceSwitchRecord] = [], driftSuggested: Bool = false, layoutMoved: Bool = false,
         gazePoint: CGPoint? = nil) {
        self.phase = phase
        self.status = status
        self.mode = mode
        self.layout = layout
        self.zones = zones
        self.currentZone = currentZone
        self.candidate = candidate
        self.pausedUntil = pausedUntil
        self.calibration = calibration
        self.recentSwitches = recentSwitches
        self.driftSuggested = driftSuggested
        self.layoutMoved = layoutMoved
        self.gazePoint = gazePoint
    }

    init(service: ForkGlanceService) {
        self.init(phase: service.phase, status: service.status, mode: service.settings.mode, layout: service.layout,
                  zones: service.zones, currentZone: service.currentZone, candidate: service.candidate,
                  pausedUntil: service.pausedUntil, calibration: service.profile?.calibration,
                  recentSwitches: service.recentSwitches, driftSuggested: service.driftSuggested,
                  layoutMoved: service.layoutMoved, gazePoint: service.live?.estimate?.point)
    }

    /// The island's Content tab: an ultra-wide over a MacBook, its left half
    /// active, calibrated three days ago (plan §11.1). Nothing is read.
    static func preview(language: AppLanguage, now: Date) -> ForkGlanceIslandSnapshot {
        let text = ForkGlanceStrings.strings(language)
        let layout = ForkGlanceIslandRules.previewLayout
        let zones = ForkGlanceIslandRules.previewZones
        let active = ForkGlanceIslandRules.previewActiveZone
        let wide = layout.displays[0]
        let name = text.zoneName(.left, display: text.displayShortName(wide, among: layout.displays))
        return ForkGlanceIslandSnapshot(
            phase: .settled(zone: active), status: .active(zoneName: name), mode: .zones, layout: layout, zones: zones,
            currentZone: active, calibration: sampleCalibration(zones: zones, date: now.addingTimeInterval(-3 * 86_400)))
    }

    /// A calibration with only what the section reads: its date and score.
    static func sampleCalibration(zones: [ForkGlanceZone], date: Date, score: Double = 0.97) -> ForkGlanceCalibration {
        ForkGlanceCalibration(
            version: ForkGlanceCalibration.currentVersion, date: date, cameraID: "", layoutSignature: "", usesEyes: false,
            coefficientsX: [], coefficientsY: [], normalization: [], sigma: .zero, bias: .zero,
            yawRange: 0...0, pitchRange: 0...0,
            zoneAccuracy: Dictionary(uniqueKeysWithValues: zones.map { ($0.id, score) }))
    }
}

/// Holds a live-readings lease while the section shows the gaze dot: the
/// service computes the dot for nobody else (plan §11.1).
private struct ForkGlanceLiveLeaseHolder: ViewModifier {
    let active: Bool
    @State private var lease: ForkGlanceLease?

    func body(content: Content) -> some View {
        content
            .onAppear { update(active) }
            .onChange(of: active) { _, now in update(now) }
            .onDisappear {
                lease?.release()
                lease = nil
            }
    }

    private func update(_ holds: Bool) {
        if holds, lease == nil {
            lease = ForkGlanceService.shared.liveLease()
        } else if !holds, let held = lease {
            held.release()
            lease = nil
        }
    }
}
