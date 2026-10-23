// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import SwiftUI

/// The Backup section's options in the island's Content tab (seam
/// `notch-macbackups7`): what the page shows (the chain, the files waiting),
/// its size, and the way to the rest of the feature's settings. The same
/// `fork.macbackup.island.*` keys as the feature's page, never a copy.
struct ForkMacBackupIslandSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(ForkDefaultsKey.macBackupIslandShowChain) private var showChain = true
    @AppStorage(ForkDefaultsKey.macBackupIslandShowPending) private var showPending = true
    @AppStorage(ForkDefaultsKey.macBackupIslandSize) private var size = "compact"

    var body: some View {
        let text = ForkMacBackupIslandStrings.strings(l10n.language)
        SettingsRow(symbol: "point.3.connected.trianglepath.dotted", title: text.showChain) {
            Toggle(text.showChain, isOn: $showChain).labelsHidden().toggleStyle(.switch)
        }
        SettingsRow(symbol: "doc.badge.clock", title: text.showPending) {
            Toggle(text.showPending, isOn: $showPending).labelsHidden().toggleStyle(.switch)
        }
        SettingsChoiceRow(symbol: "rectangle.expand.vertical", title: text.sectionSize, selection: $size) {
            Text(text.sizeCompact).tag("compact")
            Text(text.sizeSpacious).tag("spacious")
        }
        .onChange(of: size) { _, _ in ForkMacBackupIsland.refreshIsland() }
        Divider()
        HStack(spacing: 8) {
            Button(text.allSettings) { ForkMacBackupIsland.openFeatureSettings() }
            Button(ForkMacBackupStrings.strings(l10n.language).openBackups) { ForkMacBackupWindow.open(.browse) }
        }
        .controlSize(.small)
    }

    /// While the feature is off, the section's header leads to the Mac
    /// Backup page, whose switch turns it on (seam `notch-macbackups7`): the
    /// official Features page does not list the fork's features.
    static func openFeature() {
        ForkSettingsPages.open(.macBackup)
    }
}

/// The backup in the closed island, among the island's other activities in
/// its Activity tab (seam `notch-macbackups8`): whether the closed island
/// shows a backup running, what its right wing reads, and which ends get a
/// notice. Shown once the feature is on, as the official Agents resting
/// choice is.
struct ForkMacBackupIslandActivityCard: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(ForkDefaultsKey.macBackupEnabled) private var enabled = false
    @AppStorage(ForkDefaultsKey.macBackupIslandCompact) private var compact = ForkMacBackupCompactSetting.fallback.rawValue
    @AppStorage(ForkDefaultsKey.macBackupIslandReading) private var reading = ForkMacBackupReading.fallback.rawValue
    @AppStorage(ForkDefaultsKey.macBackupNotice(.complete)) private var complete = ForkMacBackupNoticeEvent.complete.defaultOn
    @AppStorage(ForkDefaultsKey.macBackupNotice(.partial)) private var partial = ForkMacBackupNoticeEvent.partial.defaultOn
    @AppStorage(ForkDefaultsKey.macBackupNotice(.failure)) private var failure = ForkMacBackupNoticeEvent.failure.defaultOn
    @AppStorage(ForkDefaultsKey.macBackupNotice(.restoreDone)) private var restore = ForkMacBackupNoticeEvent.restoreDone.defaultOn
    /// Drawn whatever the switch says (the render harness).
    var forcesShown = false

    var body: some View {
        if enabled || forcesShown {
            card
                .onChange(of: compact) { _, _ in ForkMacBackupIsland.refreshIsland() }
                .onChange(of: reading) { _, _ in ForkMacBackupIsland.refreshIsland() }
        }
    }

    private var card: some View {
        let text = ForkMacBackupIslandStrings.strings(l10n.language)
        return SettingsCard(title: ForkExtrasStrings.strings(l10n.language).macBackupTitle) {
            VStack(alignment: .leading, spacing: 6) {
                SettingsChoiceRow(symbol: "clock.arrow.circlepath", title: text.closedIsland, selection: $compact) {
                    Text(text.compactRunning).tag(ForkMacBackupCompactSetting.running.rawValue)
                    Text(text.compactNever).tag(ForkMacBackupCompactSetting.never.rawValue)
                }
                caption(text.closedIslandCaption)
            }
            if compact == ForkMacBackupCompactSetting.running.rawValue {
                SettingsChoiceRow(symbol: "percent", title: text.rightWing, selection: $reading) {
                    Text(text.readingPercent).tag(ForkMacBackupReading.percent.rawValue)
                    Text(text.readingRemaining).tag(ForkMacBackupReading.remaining.rawValue)
                }
            }
            Divider()
            Text(text.endNotices).font(.subheadline.weight(.semibold))
            noticeRow("checkmark.circle", text.noticeComplete, $complete)
            noticeRow("exclamationmark.circle", text.noticePartial, $partial)
            noticeRow("xmark.octagon", text.noticeFailed, $failure)
            noticeRow("arrow.down.circle", text.noticeRestore, $restore)
            caption(text.noticesCaption)
            HStack(spacing: 8) {
                Button(text.allSettings) { ForkMacBackupIsland.openFeatureSettings() }
            }
            .controlSize(.small)
        }
    }

    private func noticeRow(_ symbol: String, _ title: String, _ isOn: Binding<Bool>) -> some View {
        SettingsRow(symbol: symbol, title: title) {
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

/// The way from the Mac Backup page to the island's own settings for it:
/// its Content tab, on the Backup section. For the Settings package to
/// place on its page.
struct ForkMacBackupIslandSettingsLink: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        Button(ForkMacBackupIslandStrings.strings(l10n.language).islandSettings) {
            ForkMacBackupIsland.openIslandSettings()
        }
        .controlSize(.small)
    }
}
