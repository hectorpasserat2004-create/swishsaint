// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import SwiftUI

extension ForkMeetingIslandSection {
    /// At launch (`ForkBootstrap.start`): the island's own code and its
    /// tests build without the fork, so they reach the Meetings section
    /// through these hooks, never by its name (seam `notch-meetings`): its
    /// name, its line in the Content tab, and whether it can show, which is
    /// the feature's own switch, as an official section follows its feature.
    static func start() {
        NotchModule.meetingsHooks = (title: { ForkExtrasStrings.strings($0).meetingsTitle },
                                     summary: { ForkMeetingIslandStrings.current.sectionSummary },
                                     isAvailable: { $0.bool(forKey: ForkDefaultsKey.meetingsEnabled) })
    }
}

/// The section's options in the Dynamic Island's Content tab (seam
/// `notch-meetings7`): what the page shows, the recording in the closed
/// island (`fork.meetings.indicator`, the same setting as the Activity
/// tab's and the Meetings page's), and the way to the rest of the
/// feature's settings.
struct ForkMeetingIslandSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(ForkDefaultsKey.meetingsIndicator) private var stored = ForkMeetingIndicator.fallback.rawValue

    var body: some View {
        let text = ForkMeetingStrings.strings(l10n.language)
        SettingsRow(symbol: "record.circle", title: text.islandActivity, caption: text.islandActivityCaption) {
            Toggle(text.islandActivity, isOn: ForkMeetingIslandSettings.stripBinding($stored))
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .onChange(of: stored) { _, _ in ForkMeetingIslandStrip.refreshIsland() }
        Divider()
        HStack(spacing: 8) {
            Button(text.actionOpenMeetings) { ForkSettingsPages.open(.meetings) }
            Button(text.openLibrary) { ForkMeetingLibraryWindow.shared.show() }
        }
        .controlSize(.small)
    }

    /// "Show the recording in the closed island": on brings back the
    /// automatic pill, off leaves the pill alone, as the Meetings page does.
    static func stripBinding(_ stored: Binding<String>) -> Binding<Bool> {
        Binding(get: { ForkMeetingIndicator(stored: stored.wrappedValue).showsStrip },
                set: { stored.wrappedValue = ($0 ? ForkMeetingIndicator.auto : .pill).rawValue })
    }

    /// While the feature is off, the section's header leads to the
    /// Meetings page, whose switch turns it on (seam `notch-meetings7`), as
    /// the Meeting tile's reason does: the official Features page does not
    /// list the fork's features.
    static func openFeature() {
        ForkSettingsPages.open(.meetings)
    }
}

/// The meeting in the closed island, among the island's other activities in
/// its Activity tab (seam `notch-meetings8`): the same switch as the
/// Meetings page's, whether the floating indicator stays beside it, and
/// which of the island's indicators its messages follow. Shown once the
/// feature is on, as the official Agents resting choice is.
struct ForkMeetingIslandActivityCard: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(ForkDefaultsKey.meetingsEnabled) private var enabled = false
    @AppStorage(ForkDefaultsKey.meetingsIndicator) private var stored = ForkMeetingIndicator.fallback.rawValue

    private var indicator: ForkMeetingIndicator { ForkMeetingIndicator(stored: stored) }

    var body: some View {
        let text = ForkMeetingStrings.strings(l10n.language)
        let page = ForkMeetingIslandStrings.strings(l10n.language)
        if enabled {
            card(text: text, page: page)
                .onChange(of: stored) { _, _ in ForkMeetingIslandStrip.refreshIsland() }
        }
    }

    private func card(text: ForkMeetingStrings, page: ForkMeetingIslandStrings) -> some View {
        SettingsCard(title: ForkExtrasStrings.strings(l10n.language).meetingsTitle) {
            SettingsRow(symbol: "record.circle", title: text.islandActivity, caption: text.islandActivityCaption) {
                Toggle(text.islandActivity, isOn: ForkMeetingIslandSettings.stripBinding($stored))
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            if indicator.showsStrip {
                VStack(alignment: .leading, spacing: 6) {
                    SettingsChoiceRow(symbol: "pip", title: text.indicatorPill, selection: pillBinding) {
                        Text(text.indicatorAuto).tag(ForkMeetingIndicator.auto)
                        Text(text.indicatorBoth).tag(ForkMeetingIndicator.both)
                    }
                    Text(indicator == .both ? text.indicatorBothCaption : text.indicatorAutoCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, settingsRowTextInset)
                }
            }
            Text(page.noticesCaption(FeatureStrings.notch(l10n.language).captures))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(text.actionOpenMeetings) { ForkSettingsPages.open(.meetings) }
                .controlSize(.small)
        }
    }

    private var pillBinding: Binding<ForkMeetingIndicator> {
        Binding(get: { indicator == .both ? .both : .auto }, set: { stored = $0.rawValue })
    }
}

/// The way from the Meetings page to the island's own settings for them:
/// its Content tab, on the Meetings section.
struct ForkMeetingIslandSettingsLink: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        Button(ForkMeetingIslandStrings.strings(l10n.language).islandSettingsLink) {
            SettingsRouter.shared.notchModule = .meetings
            SettingsRouter.shared.request(FeatureSettingsDestination(.notch))
        }
        .controlSize(.small)
    }
}
