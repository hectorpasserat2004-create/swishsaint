// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import SwiftUI

/// The « Sauvegarde du Mac » page, below its switch (`ForkFeatureSettingsPage`
/// draws the switch). Placeholder owned by WP Settings: for now, the state
/// in one line.
struct ForkMacBackupSettingsView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var status = ForkMacBackupStatusModel.shared
    @AppStorage(ForkDefaultsKey.macBackupEnabled) private var enabled = false

    var body: some View {
        let language = l10n.language
        Section {
            LabeledContent(ForkMacBackupStrings.strings(language).featureTitle) {
                Text(status.presentation.headline(.strings(language), language: language,
                                                  locale: language.formattingLocale()))
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(!enabled)
    }
}
