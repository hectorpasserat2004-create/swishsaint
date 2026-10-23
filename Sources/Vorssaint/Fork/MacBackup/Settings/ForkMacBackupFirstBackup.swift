// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Combine
import SwiftUI

extension ForkMacBackupSettingsContext {
    /// « Commencer maintenant ».
    func startFirstBackupNow() {
        powerWait = nil
        send(.backUpNow)
    }

    /// « Commencer sur secteur »: now when plugged in, else the moment the
    /// charger comes. Returns what happened, for the wizard to say.
    @discardableResult
    func startFirstBackupOnPower() -> ForkMacBackupFirstBackup.Choice {
        let island = NotchService.shared
        if isPreview || ForkMacBackupFirstBackup.startsAtOnce(externalConnected: island.power.externalConnected,
                                                              hasBattery: island.power.hasBattery) {
            send(.backUpNow)
            return .started
        }
        powerWait = island.$power
            .map(\.externalConnected)
            .removeDuplicates()
            .filter { $0 }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.powerWait = nil
                guard ForkMacBackupApp.isEnabled else { return }
                self.send(.backUpNow)
            }
        return .waitingForPower
    }
}

/// The wizard's first-backup block: the real size to send, then the three
/// choices.
struct ForkMacBackupFirstBackupSection: View {
    @ObservedObject var context: ForkMacBackupSettingsContext
    @ObservedObject var status: ForkMacBackupStatusModel
    @Binding var choice: ForkMacBackupFirstBackup.Choice?
    let chooseContent: () -> Void
    @ObservedObject private var l10n = L10n.shared

    private var text: ForkMacBackupSettingsStrings { .strings(l10n.language) }

    var body: some View {
        let size = ForkMacBackupFirstBackup.sizeToSend(preview: context.preview,
                                                       protectedBytes: status.presentation.capacity.protectedBytes)
        // Only before a first backup exists: an edit of an old connection has none to offer.
        if status.presentation.lastBackup == nil || choice != nil {
            Section {
                HStack(alignment: .top, spacing: 10) {
                    ForkMacBackupIconTile(symbol: "externaldrive.badge.icloud", color: ForkMacBackupStyle.accent, size: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(text.firstBackupTitle).fontWeight(.medium)
                        ForkMacBackupCaption(size.map {
                            String(format: text.firstBackupCaption,
                                   ForkMacBackupFormat.bytes($0, locale: l10n.language.formattingLocale()))
                        } ?? text.firstBackupCaptionUnknown)
                    }
                    Spacer()
                    if size == nil, context.scanProgress != nil { ProgressView().controlSize(.small) }
                }
                if let choice {
                    Label(choice == .started ? text.firstBackupStarted : text.firstBackupWaitsPower,
                          systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                } else {
                    HStack(spacing: 8) {
                        Button(text.firstBackupChoose, action: chooseContent)
                        Spacer()
                        Button(text.firstBackupOnPower) { choice = context.startFirstBackupOnPower() }
                        Button(text.firstBackupNow) {
                            context.startFirstBackupNow()
                            choice = .started
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ForkMacBackupStyle.accent)
                    }
                }
            }
            .onAppear {
                if context.preview == nil, size == nil { context.scanContent() }
            }
        }
    }
}
