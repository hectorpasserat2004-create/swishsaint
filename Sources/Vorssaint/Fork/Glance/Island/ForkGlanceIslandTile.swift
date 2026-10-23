// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import SwiftUI

/// The island's « Regard » button among its controls (seams
/// `notch-glance-tile*`, plan §11.3): lit with `eyes` while the camera
/// watches, `eye.slash` in a pause, reading the minutes a timed pause has
/// left, « Pause », an automatic pause's reason or what is missing. A click
/// pauses until resumed, or resumes; while the feature is not ready (a
/// permission, a calibration) it opens the section, or the assistant when
/// only a calibration is missing.
struct ForkGlanceIslandTile: View {
    let service: NotchService
    @ObservedObject private var glance: ForkGlanceService
    @ObservedObject private var l10n = L10n.shared
    /// A fixed state (the render harness); nil: the service's. A fixed tile
    /// does nothing when clicked.
    private let fixed: (phase: ForkGlancePhase, status: ForkGlanceStatusLine)?

    init(service: NotchService, glance: ForkGlanceService = .shared,
         fixed: (phase: ForkGlancePhase, status: ForkGlanceStatusLine)? = nil) {
        self.service = service
        _glance = ObservedObject(wrappedValue: glance)
        self.fixed = fixed
    }

    var body: some View {
        // A timed pause's minutes move by the minute: the tile wakes only then.
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            tile(now: context.date)
        }
    }

    private func tile(now: Date) -> some View {
        let text = ForkGlanceStrings.strings(l10n.language)
        let phase = fixed?.phase ?? glance.phase
        let status = fixed?.status ?? glance.status
        return NotchActionTile(symbol: ForkGlancePresentation.symbol(phase), title: Self.title(l10n.language),
                               reading: text.tileReading(status, locale: l10n.language.formattingLocale(), now: now),
                               active: ForkGlancePresentation.tileIsActive(phase), accent: .selection) {
            guard fixed == nil else { return }
            Self.activate(from: service)
        }
        .accessibilityHint(ForkGlanceIslandStrings.strings(l10n.language).activityHint)
    }

    /// « Regard », in the controls and in the island's picker.
    static func title(_ language: AppLanguage) -> String {
        ForkGlanceStrings.strings(language).sectionTitle
    }

    /// The tile and its button around the island (seam `notch-glance-tile4`).
    static func activate(from service: NotchService = .shared) {
        precondition(Thread.isMainThread)
        guard ForkFeature.glanceFocus.isEnabled else { return }
        let glance = ForkGlanceService.shared
        switch ForkGlanceIslandRules.tileAction(glance.phase) {
        case .pause: ForkGlanceIsland.pause(.untilResumed)
        case .resume: glance.resume(from: .island)
        case .calibrate: service.perform { glance.openCalibration(.full) }
        case .openSection: ForkGlanceIsland.openSection(from: service)
        }
    }

    /// Why the « Regard » button is off while the feature is, as the official
    /// controls say it (seam `notch-glance-tile5`).
    static func controlReason(_ language: AppLanguage) -> String? {
        guard !ForkFeature.glanceFocus.isEnabled else { return nil }
        return FeatureStrings.notchEditor(language).enableFeature(ForkExtrasStrings.strings(language).glanceTitle)
    }

    /// Where that reason leads: the Glance Focus page, whose switch turns it on.
    static func controlSetupAction() -> (() -> Void)? {
        guard !ForkFeature.glanceFocus.isEnabled else { return nil }
        return { ForkSettingsPages.open(.glanceFocus) }
    }
}
