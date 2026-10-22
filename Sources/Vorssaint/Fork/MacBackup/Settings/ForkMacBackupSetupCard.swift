// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import SwiftUI

/// « Mise en route » (plan §11.1): five steps with their check marks, the
/// next one's button standing out, prominent like the Parakeet card. Shown
/// until the four steps a backup needs are done; the kit can wait.
struct ForkMacBackupSetupCard: View {
    let text: ForkMacBackupSettingsStrings
    let setup: ForkMacBackupSetupState
    @ObservedObject var context: ForkMacBackupSettingsContext
    let enabled: Bool
    let open: (ForkMacBackupSheet) -> Void

    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ForkMacBackupIconTile(symbol: "clock.arrow.circlepath", size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.setupTitle)
                        .font(.title3.weight(.semibold))
                    Text(String(format: text.setupProgress, setup.count, ForkMacBackupSetupStep.allCases.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Gauge(value: Double(setup.count), in: 0...Double(ForkMacBackupSetupStep.allCases.count)) {
                    EmptyView()
                } currentValueLabel: {
                    Text("\(setup.count)")
                        .font(.caption.weight(.semibold))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(ForkMacBackupStyle.accent)
                .scaleEffect(0.75)
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(ForkMacBackupSetupStep.allCases.enumerated()), id: \.element) { index, step in
                    if index > 0 { Divider().padding(.leading, 34) }
                    stepRow(step, number: index + 1)
                        .padding(.vertical, 8)
                }
            }
            if !enabled {
                ForkMacBackupCaption(text.setupSwitchHint)
            }
        }
        .padding(.vertical, 6)
    }

    private func stepRow(_ step: ForkMacBackupSetupStep, number: Int) -> some View {
        let done = setup.done.contains(step)
        let current = setup.current == step
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(done ? Color.green : (current ? ForkMacBackupStyle.accent : Color.secondary.opacity(0.18)))
                    .frame(width: 22, height: 22)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(current ? .white : .secondary)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(text.stepTitle(step))
                    .fontWeight(current ? .semibold : .regular)
                    .foregroundStyle(done ? .secondary : .primary)
                if !done {
                    ForkMacBackupCaption(caption(step))
                    detail(step)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(text.stepTitle(step)), \(done ? text.stepDone : text.stepToDo)")
            Spacer(minLength: 8)
            if done {
                Text(text.stepDone)
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                control(step, prominent: current)
            }
        }
    }

    private func caption(_ step: ForkMacBackupSetupStep) -> String {
        switch step {
        case .engine: return text.stepEngineCaption
        case .diskAccess: return String(format: text.stepDiskAccessCaption, ForkMacBackupAppName.current)
        case .background:
            switch context.agentLink.registration {
            case .failed: return text.stepBackgroundFailed
            case .notRegistered: return enabled ? text.stepBackgroundCaption : text.stepBackgroundAfterSwitch
            default: return text.stepBackgroundCaption
            }
        case .repository: return text.stepRepositoryCaption
        case .kit: return text.stepKitCaption
        }
    }

    @ViewBuilder
    private func detail(_ step: ForkMacBackupSetupStep) -> some View {
        if step == .engine {
            switch context.engineStore.state {
            case .downloading(let progress):
                VStack(alignment: .leading, spacing: 3) {
                    ProgressView(value: progress)
                        .tint(ForkMacBackupStyle.accent)
                    ForkMacBackupCaption(String(format: text.engineDownloading,
                                                ForkMacBackupFormat.percent(progress, locale: l10n.language.formattingLocale())))
                }
                .frame(maxWidth: 260)
            case .verifying:
                ForkMacBackupCaption(text.engineVerifying)
            case .failed(let message):
                Label(message.isEmpty ? text.engineFailed : message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func control(_ step: ForkMacBackupSetupStep, prominent: Bool) -> some View {
        switch step {
        case .engine:
            switch context.engineStore.state {
            case .downloading:
                Button(text.cancel) { context.engineStore.cancel() }
                    .controlSize(.small)
            case .verifying:
                ProgressView().controlSize(.small)
            case .failed:
                action(text.tryAgain, prominent: prominent) { context.engineStore.install() }
            default:
                action(text.engineInstall, prominent: prominent) { context.engineStore.install() }
            }
        case .diskAccess:
            VStack(alignment: .trailing, spacing: 4) {
                action(text.allow, prominent: prominent) { Permissions.shared.requestFullDiskAccess() }
                Button(text.relaunch) { appDelegate()?.relaunchApp() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        case .background:
            switch context.agentLink.registration {
            case .requiresApproval:
                action(text.allow, prominent: prominent) { context.agentLink.openApprovalSettings() }
            case .failed:
                action(text.tryAgain, prominent: prominent) { context.agentLink.sync() }
            default:
                EmptyView()
            }
        case .repository:
            action(text.connect, prominent: prominent) { open(.wizard(.choose)) }
        case .kit:
            action(text.kitCreate, prominent: prominent) { open(.kit) }
                .disabled(context.repository == nil)
        }
    }

    private func action(_ title: String, prominent: Bool, _ perform: @escaping () -> Void) -> some View {
        Group {
            if prominent {
                Button(title, action: perform)
                    .buttonStyle(.borderedProminent)
                    .tint(ForkMacBackupStyle.accent)
                    .controlSize(.regular)
            } else {
                Button(title, action: perform)
                    .controlSize(.small)
            }
        }
        .fixedSize()
    }
}

/// The app's real name (« Swishsaint », « Vorssaint (Developer) »): the
/// official Full Disk Access hint says « Vorssaint », ours says the truth.
enum ForkMacBackupAppName {
    static var current: String {
        let info = Bundle.main.infoDictionary
        return info?["CFBundleDisplayName"] as? String ?? info?["CFBundleName"] as? String ?? "Swishsaint"
    }
}
