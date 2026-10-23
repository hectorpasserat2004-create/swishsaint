// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import SwiftUI

/// The « Regard » section's options in the island's Content tab (seam
/// `notch-glance7`, plan §11.6): the live gaze dot, the last switches, and
/// the way to the feature's page. The same `fork.glance.island.*` keys as
/// the feature's page, never a copy.
struct ForkGlanceIslandSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(ForkDefaultsKey.glanceIslandLiveDot) private var liveDot = false
    @AppStorage(ForkDefaultsKey.glanceIslandHistory) private var history = true

    var body: some View {
        let text = ForkGlanceIslandStrings.strings(l10n.language)
        SettingsRow(symbol: "smallcircle.filled.circle", title: text.showLiveDot, caption: text.liveDotCaption) {
            Toggle(text.showLiveDot, isOn: $liveDot).labelsHidden().toggleStyle(.switch)
        }
        SettingsRow(symbol: "clock", title: text.showHistory) {
            Toggle(text.showHistory, isOn: $history).labelsHidden().toggleStyle(.switch)
        }
        Divider()
        HStack(spacing: 8) {
            Button(text.allSettings) { ForkGlanceIsland.openFeatureSettings() }
        }
        .controlSize(.small)
    }

    /// While the feature is off, the section's header leads to the Glance
    /// Focus page, whose switch turns it on (seam `notch-glance7`): the
    /// official Features page does not list the fork's features.
    static func openFeature() {
        ForkSettingsPages.open(.glanceFocus)
    }
}

/// Glance in the closed island, among the island's other activities in its
/// Activity tab (seam `notch-glance8`, plan §11.6): what the closed island
/// shows (never, during a pause or a calibration, always), and which
/// notices it tells. Shown once the feature is on, as the official Agents
/// resting choice is.
struct ForkGlanceIslandActivityCard: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(ForkDefaultsKey.glanceEnabled) private var enabled = false
    @AppStorage(ForkDefaultsKey.glanceIslandClosed) private var closed = ForkGlanceIslandClosed.fallback.rawValue
    @AppStorage(ForkDefaultsKey.glanceNotice(.pause)) private var pause = ForkGlanceNoticeKind.pause.defaultOn
    @AppStorage(ForkDefaultsKey.glanceNotice(.newLayout)) private var newLayout = ForkGlanceNoticeKind.newLayout.defaultOn
    @AppStorage(ForkDefaultsKey.glanceNotice(.camera)) private var camera = ForkGlanceNoticeKind.camera.defaultOn
    @AppStorage(ForkDefaultsKey.glanceNotice(.recenter)) private var recenter = ForkGlanceNoticeKind.recenter.defaultOn
    @AppStorage(ForkDefaultsKey.glanceNotice(.calibrated)) private var calibrated = ForkGlanceNoticeKind.calibrated.defaultOn
    @AppStorage(ForkDefaultsKey.glanceNotice(.drift)) private var drift = ForkGlanceNoticeKind.drift.defaultOn
    /// Drawn whatever the switch says (the render harness).
    var forcesShown = false

    var body: some View {
        // The island's model follows `closed` itself (defaults observer).
        if enabled || forcesShown { card }
    }

    private var card: some View {
        let core = ForkGlanceStrings.strings(l10n.language)
        let text = ForkGlanceIslandStrings.strings(l10n.language)
        return SettingsCard(title: ForkExtrasStrings.strings(l10n.language).glanceTitle) {
            SettingsChoiceRow(symbol: "eyes", title: text.closedIsland, selection: $closed) {
                ForEach(ForkGlanceIslandClosed.allCases, id: \.self) { choice in
                    Text(core.islandClosedName(choice)).tag(choice.rawValue)
                }
            }
            Divider()
            Text(text.notices).font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            noticeRow(.pause, $pause)
            noticeRow(.newLayout, $newLayout)
            noticeRow(.camera, $camera)
            noticeRow(.recenter, $recenter)
            noticeRow(.calibrated, $calibrated)
            noticeRow(.drift, $drift)
            caption(text.noticesCaption)
            HStack(spacing: 8) {
                Button(text.allSettings) { ForkGlanceIsland.openFeatureSettings() }
            }
            .controlSize(.small)
        }
    }

    private func noticeRow(_ kind: ForkGlanceNoticeKind, _ isOn: Binding<Bool>) -> some View {
        let title = ForkGlanceStrings.strings(l10n.language).noticeKindName(kind)
        return SettingsRow(symbol: ForkGlanceIslandRules.symbol(for: kind), title: title) {
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, settingsRowTextInset)
    }
}

/// The way from the Glance Focus page to the island's own settings for it:
/// its Content tab, on the « Regard » section (plan §12.9). For the
/// Settings package to place on its page.
struct ForkGlanceIslandSettingsLink: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        Button(ForkGlanceIslandStrings.strings(l10n.language).islandSettings) {
            ForkGlanceIsland.openIslandSettings()
        }
        .controlSize(.small)
    }
}
