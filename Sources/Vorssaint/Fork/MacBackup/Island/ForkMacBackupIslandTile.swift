// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import SwiftUI

/// The island's Backup button among its controls (seams
/// `notch-macbackup-tile*`): it opens the Backup section, where « Back Up
/// Now », the pause and the rest live (decision 2 of 22/10). Being inside
/// the island, it may say the state: « 42 % » lit while something runs,
/// « il y a 2 h » at rest, red while the chain is broken.
struct ForkMacBackupIslandTile: View {
    let service: NotchService
    @ObservedObject private var status: ForkMacBackupStatusModel
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(ForkDefaultsKey.macBackupIslandReading) private var readingStored = ForkMacBackupReading.fallback.rawValue

    init(service: NotchService, status: ForkMacBackupStatusModel = .shared) {
        self.service = service
        _status = ObservedObject(wrappedValue: status)
    }

    var body: some View {
        // The age moves slowly: once a minute is enough.
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            tile(now: context.date)
        }
    }

    private func tile(now: Date) -> some View {
        let state = status.presentation
        let text = ForkMacBackupStrings.strings(l10n.language)
        let accent = ForkMacBackupIslandRules.tileAccent(state)
        let reading = ForkMacBackupIslandRules.tileReading(
            state, text: text, locale: l10n.language.formattingLocale(),
            reading: ForkMacBackupReading(rawValue: readingStored) ?? .fallback, now: now)
        return NotchActionTile(symbol: NotchControlItem.macBackup.symbol, title: Self.title(l10n.language),
                               reading: reading, active: accent.active, accent: accent.alert ? .alert : .selection) {
            ForkMacBackupIsland.openSection(from: service)
        }
        .accessibilityHint(ForkMacBackupIslandStrings.strings(l10n.language).activityHint)
    }

    /// « Sauvegarde », in the controls and in the island's picker.
    static func title(_ language: AppLanguage) -> String {
        ForkMacBackupStrings.strings(language).islandTitle
    }

    /// Why the Backup button is off while the feature is, as the official
    /// controls say it (seam `notch-macbackup-tile5`).
    static func controlReason(_ language: AppLanguage) -> String? {
        guard !ForkMacBackupApp.isEnabled else { return nil }
        return FeatureStrings.notchEditor(language).enableFeature(ForkExtrasStrings.strings(language).macBackupTitle)
    }

    /// Where that reason leads: the Mac Backup page, whose switch turns it on.
    static func controlSetupAction() -> (() -> Void)? {
        guard !ForkMacBackupApp.isEnabled else { return nil }
        return { ForkSettingsPages.open(.macBackup) }
    }
}
