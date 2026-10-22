// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import SwiftUI

/// The only cards Mac Backup opens the island on (decision 3 of 22/10):
/// the first heavy backup, a restore that landed, and Bran still running
/// after its import. Never a delay nor a broken chain: those live in the
/// section.
struct ForkMacBackupIslandCard {
    enum Kind: Equatable {
        /// `bytes`: what the first backup will send, when measured.
        case firstBackup(bytes: Int64?)
        case restored(files: Int64, path: String)
        case bran

        var isRestore: Bool {
            if case .restored = self { return true }
            return false
        }
    }

    enum Action: Equatable {
        case chooseContent
        case startOnPower
        case showInFinder(String)
        case open(String)
        case stopBran
        case later
    }

    let kind: Kind
    let perform: (Action) -> Void
}

struct ForkMacBackupIslandCardView: View {
    let card: ForkMacBackupIslandCard
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let language = l10n.language
        let text = ForkMacBackupIslandStrings.strings(language)
        let locale = language.formattingLocale()
        switch card.kind {
        case .firstBackup(let bytes):
            ForkMacBackupIslandMessage(
                symbol: "externaldrive.badge.icloud", tint: .teal, title: text.firstTitle,
                caption: bytes.map { String(format: text.firstCaption, ForkMacBackupFormat.bytes($0, locale: locale)) }
                    ?? text.firstCaptionUnknown) {
                ForkMacBackupIslandButton(title: text.chooseContent) { card.perform(.chooseContent) }
                ForkMacBackupIslandButton(title: text.startOnPower, prominent: true) { card.perform(.startOnPower) }
            }
        case .restored(let files, let path):
            ForkMacBackupIslandMessage(
                symbol: "arrow.down.circle.fill", tint: .teal, title: text.noticeRestore,
                caption: text.restored(Int(clamping: files), language: language) + " · "
                    + ForkMacBackupFormat.middleTruncated(path, limit: 40)) {
                ForkMacBackupIslandButton(title: text.showInFinder) { card.perform(.showInFinder(path)) }
                ForkMacBackupIslandButton(title: text.open, prominent: true) { card.perform(.open(path)) }
            }
        case .bran:
            ForkMacBackupIslandMessage(symbol: "exclamationmark.arrow.triangle.2.circlepath", tint: .orange,
                                       title: text.branTitle, caption: text.branCaption) {
                ForkMacBackupIslandButton(title: text.later) { card.perform(.later) }
                ForkMacBackupIslandButton(title: text.stopBran, prominent: true) { card.perform(.stopBran) }
            }
        }
    }
}

/// A card's body: its mark, its title and its sentence, then its buttons
/// on their own row, so a long sentence is never squeezed by them.
struct ForkMacBackupIslandMessage<Actions: View>: View {
    let symbol: String
    var tint: Color = .white
    let title: String
    let caption: String?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    if let caption, !caption.isEmpty {
                        Text(caption)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                actions()
            }
        }
        .panelCard()
        .accessibilityElement(children: .contain)
    }
}

/// A word on a pill, as the island's own pages draw their actions (the
/// agents' cards, the timer's Start): a quiet wash for the others, the
/// step the card leads to in sarcelle, its words in sarcelle too.
struct ForkMacBackupIslandButton: View {
    var symbol: String? = nil
    let title: String
    var prominent = false
    var label: String? = nil
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            ForkMacBackupIslandPill(symbol: symbol, title: title, prominent: prominent && enabled)
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 14))
        .help(label ?? title)
        .accessibilityLabel(label ?? title)
    }
}

/// The pill's face, shared with the pause menu's label.
struct ForkMacBackupIslandPill: View {
    var symbol: String? = nil
    let title: String
    var prominent = false
    var chevron = false

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .accessibilityHidden(true)
            }
            Text(title)
                .lineLimit(1)
                .fixedSize()
            if chevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .accessibilityHidden(true)
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(prominent ? Color.teal : Color.white.opacity(0.85))
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(prominent ? Color.teal.opacity(0.2) : Color.white.opacity(0.1), in: Capsule(style: .continuous))
        .contentShape(Capsule(style: .continuous))
    }
}
