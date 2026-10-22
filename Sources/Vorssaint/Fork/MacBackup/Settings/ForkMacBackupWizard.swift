// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The connection wizard (plan §11.2): where to start from, the server, the
/// repository (tested, then locked by its unique ID), this Mac's identity,
/// then the kit.
struct ForkMacBackupWizard: View {
    @StateObject private var model: ForkMacBackupWizardModel
    let open: (ForkMacBackupSheet?) -> Void

    @ObservedObject private var l10n = L10n.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.forkMacBackupSheetHeight) private var heightOverride
    @State private var confirmingStop = false
    @State private var startProblem: String?

    init(context: ForkMacBackupSettingsContext, start: ForkMacBackupWizardStart,
         open: @escaping (ForkMacBackupSheet?) -> Void) {
        _model = StateObject(wrappedValue: ForkMacBackupWizardModel(context: context, start: start))
        self.open = open
    }

    /// For renders: a model already in a given state.
    init(model: ForkMacBackupWizardModel) {
        _model = StateObject(wrappedValue: model)
        open = { _ in }
    }

    private var text: ForkMacBackupSettingsStrings { .strings(l10n.language) }
    private var shared: ForkMacBackupStrings { .strings(l10n.language) }
    private var locale: Locale { l10n.language.formattingLocale() }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Form {
                switch model.step {
                case .start: startStep
                case .server: serverStep
                case .repository: repositoryStep
                case .identity: identityStep
                case .kit: kitStep
                }
            }
            .formStyle(.grouped)
            Divider()
            footer
        }
        .frame(width: 640, height: heightOverride ?? 660)
        .alert(text.stopBranTitle, isPresented: $confirmingStop) {
            Button(text.cancel, role: .cancel) {}
            Button(text.stopBran, role: .destructive) { model.stopBran() }
        } message: {
            Text(text.stopBranMessage)
        }
    }

    // MARK: Header and footer

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ForkMacBackupIconTile(symbol: "externaldrive.connected.to.line.below.fill", size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(text.wizardTitle)
                        .font(.headline)
                    Text(text.wizardStepCaption(model.step))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 6) {
                ForEach(ForkMacBackupWizardStep.allCases) { step in
                    stepChip(step)
                    if step != .kit {
                        Rectangle()
                            .fill(step.rawValue < model.step.rawValue ? ForkMacBackupStyle.accent : Color.secondary.opacity(0.25))
                            .frame(height: 1.5)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func stepChip(_ step: ForkMacBackupWizardStep) -> some View {
        let done = step.rawValue < model.step.rawValue
        let current = step == model.step
        return HStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(done || current ? ForkMacBackupStyle.accent : Color.secondary.opacity(0.18))
                    .frame(width: 18, height: 18)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(step.rawValue + 1)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(current ? .white : .secondary)
                }
            }
            Text(text.wizardStepName(step))
                .font(.caption.weight(current ? .semibold : .regular))
                .foregroundStyle(current ? .primary : .secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(step.rawValue + 1). \(text.wizardStepName(step))")
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    private var footer: some View {
        HStack {
            if model.step != .kit {
                Button(text.cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            if let finishError = model.finishError {
                ForkMacBackupCaption(finishError, color: .orange)
            }
            Spacer()
            if model.step != .start && model.step != .kit && !(model.step == .server && isEditing) {
                Button(text.back) { model.back() }
            }
            switch model.step {
            case .start:
                EmptyView()
            case .kit:
                Button(text.later) { dismiss() }
                if model.origin != .otherMac || !model.browseOnly {
                    Button(text.kitCreate) { open(.kit) }
                        .buttonStyle(.borderedProminent)
                        .tint(ForkMacBackupStyle.accent)
                        .keyboardShortcut(.defaultAction)
                }
            default:
                Button(model.step == .identity ? text.finish : text.continueAction) { model.next() }
                    .buttonStyle(.borderedProminent)
                    .tint(ForkMacBackupStyle.accent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canContinue)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var isEditing: Bool { model.existing != nil }

    // MARK: 1. Start

    @ViewBuilder
    private var startStep: some View {
        Section {
            choice("doc.badge.arrow.up.fill", .blue, text.startProfile, text.startProfileCaption) { importProfile() }
            choice("arrow.triangle.branch", .purple, text.startBran, text.startBranCaption) { model.importBran() }
            branResult
            choice("keyboard.fill", .gray, text.startManual, text.startManualCaption) { model.manual(.existing) }
        } header: {
            Text(text.startExisting)
        }
        Section {
            choice("plus.rectangle.on.folder.fill", ForkMacBackupStyle.accent, text.startNew, text.startNewCaption) {
                model.manual(.newRepository)
            }
            choice("laptopcomputer.and.arrow.down", .orange, text.startOtherMac, text.startOtherMacCaption) { openKit() }
        } header: {
            Text(text.startOther)
        }
        if let startProblem {
            Section {
                ForkMacBackupCaption(startProblem, color: .orange)
            }
        }
    }

    private func choice(_ symbol: String, _ color: Color, _ title: String, _ caption: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ForkMacBackupIconTile(symbol: symbol, color: color, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    ForkMacBackupCaption(caption)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var branResult: some View {
        switch model.branState {
        case .idle:
            EmptyView()
        case .reading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                ForkMacBackupCaption(text.branReading)
            }
        case .missing:
            ForkMacBackupCaption(text.branMissing, color: .orange)
        case .failed:
            ForkMacBackupCaption(text.branFailed, color: .orange)
        case .found:
            if let bran = model.bran {
                ForkMacBackupBranSummary(text: text, bran: bran, secretsRead: model.branSecretsRead)
                HStack {
                    Spacer()
                    Button(text.continueAction) { model.step = .server }
                        .buttonStyle(.borderedProminent)
                        .tint(ForkMacBackupStyle.accent)
                }
            }
        }
    }

    private func importProfile() {
        startProblem = nil
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: ForkMacBackupProfile.fileExtension) ?? .json, .json]
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let data = try? Data(contentsOf: url), let profile = ForkMacBackupProfile.decode(data) else {
                startProblem = text.profileUnreadable
                return
            }
            model.useProfile(profile)
        }
    }

    private func openKit() {
        startProblem = nil
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: ForkMacBackupKitFile.fileExtension) ?? .json, .json]
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            guard let data = try? Data(contentsOf: url), let kit = ForkMacBackupKitFile.decode(data) else {
                startProblem = text.kitUnreadable
                return
            }
            // Its secrets, if sealed, are typed in the repository step.
            model.useKit(kit, secrets: nil)
        }
    }

    // MARK: 2. Server

    @ViewBuilder
    private var serverStep: some View {
        Section {
            Picker(text.serverType, selection: $model.form.flavor) {
                Text("MinIO").tag(ForkMacBackupRepository.ServerFlavor.minio)
                Text(text.serverGenericS3).tag(ForkMacBackupRepository.ServerFlavor.genericS3)
            }
            .pickerStyle(.segmented)
            field(text.serverAddress, issue: .address) {
                TextField(text.serverAddress, text: $model.form.address, prompt: Text(text.serverAddressPrompt))
                    .onSubmit { model.form.absorbAddress() }
            }
            peerSuggestions
            field(text.serverPort, issue: .port) {
                TextField(text.serverPort, text: $model.form.port,
                          prompt: Text(String(ForkMacBackupServerForm.defaultPort(flavor: model.form.flavor, tls: model.form.tls))))
            }
            Toggle(isOn: $model.form.tls) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.serverTLS)
                    ForkMacBackupCaption(model.form.peer != nil ? text.serverTLSTailscale : text.serverTLSCaption)
                }
            }
        } header: {
            Text(text.serverHeader)
        }
        .onAppear { model.loadPeers() }

        Section {
            field(text.serverBucket, issue: .bucket) {
                TextField(text.serverBucket, text: $model.form.bucket, prompt: Text("mac-backup"))
            }
            field(text.serverRegion, issue: .region) {
                TextField(text.serverRegion, text: $model.form.region, prompt: Text("us-east-1"))
            }
            TextField(text.serverPrefix, text: $model.form.prefix, prompt: Text(text.optional))
        } header: {
            Text(text.storageHeader)
        }

        Section {
            field(text.serverAccessKey, issue: .accessKey) {
                TextField(text.serverAccessKey, text: $model.form.accessKeyID)
                    .font(.body.monospaced())
            }
            field(text.serverSecretKey, issue: .secretKey) {
                SecureField(text.serverSecretKey, text: $model.form.secretKey,
                            prompt: Text(model.form.hasSavedSecret ? text.savedOnThisMac : ""))
            }
        } header: {
            Text(text.keysHeader)
        } footer: {
            ForkMacBackupCaption(text.keysFooter)
        }
    }

    private func field<Content: View>(_ label: String, issue: ForkMacBackupServerForm.Issue,
                                      @ViewBuilder content: () -> Content) -> some View {
        let wrong = model.showIssues && model.form.issues.contains(issue)
        return VStack(alignment: .leading, spacing: 3) {
            content()
            if wrong {
                Label(text.issue(issue), systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var peerSuggestions: some View {
        let online = model.peers.filter(\.online)
        if !online.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(text.tailscaleSuggestions)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(online.prefix(8)) { peer in
                            let chosen = model.form.peer?.stableID == peer.stableID
                            Button {
                                model.form.choose(peer)
                            } label: {
                                HStack(spacing: 5) {
                                    Circle().fill(Color.green).frame(width: 6, height: 6)
                                    Text(peer.shortName)
                                        .font(.caption.weight(.medium))
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(chosen ? ForkMacBackupStyle.accent.opacity(0.25)
                                                           : Color.secondary.opacity(0.12)))
                                .overlay(Capsule().strokeBorder(chosen ? ForkMacBackupStyle.accent : .clear))
                            }
                            .buttonStyle(.plain)
                            .help(peer.dnsName)
                            .accessibilityLabel(String(format: text.tailscalePeerLabel, peer.shortName))
                        }
                    }
                }
            }
        }
    }

    // MARK: 3. Repository

    @ViewBuilder
    private var repositoryStep: some View {
        Section {
            SecureField(text.repositoryPassword, text: $model.password,
                        prompt: Text(model.hasSavedPassword ? text.savedOnThisMac : ""))
            if model.origin == .newRepository {
                SecureField(text.passphraseConfirm, text: $model.passwordConfirm)
                if !model.passwordConfirm.isEmpty, model.password != model.passwordConfirm {
                    ForkMacBackupCaption(text.passphraseMismatch, color: .orange)
                }
            }
            ForkMacBackupCaption(model.origin == .newRepository ? text.repositoryPasswordNew : text.repositoryPasswordCaption)
        } header: {
            Text(text.repositoryHeader)
        }

        Section {
            HStack {
                Button {
                    model.test()
                } label: {
                    Label(text.testConnection, systemImage: "bolt.horizontal.circle")
                }
                .disabled(!model.canTest)
                if model.testing {
                    ProgressView().controlSize(.small)
                }
                Spacer()
            }
            ForEach(model.results) { result in
                resultRow(result)
            }
            if let error = model.testError {
                Label(error, systemImage: "xmark.octagon.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(text.testHeader)
        }

        if let uniqueID = model.uniqueID {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(text.uniqueIDLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(uniqueID)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                if !model.machines.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(text.machinesFound)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(model.machines) { machine in
                            Label(machineLine(machine), systemImage: "laptopcomputer")
                                .font(.callout)
                        }
                    }
                } else {
                    ForkMacBackupCaption(text.machinesNone)
                }
                if model.lockedID != nil {
                    Label(model.expectedUniqueID != nil ? text.lockedExpected : text.locked, systemImage: "lock.fill")
                        .foregroundStyle(ForkMacBackupStyle.accent)
                        .font(.callout.weight(.medium))
                } else {
                    HStack {
                        ForkMacBackupCaption(text.lockCaption)
                        Spacer()
                        Button(text.lockButton) { model.lock() }
                            .buttonStyle(.borderedProminent)
                            .tint(ForkMacBackupStyle.accent)
                    }
                }
            } header: {
                Text(text.thisRepository)
            }
        }
    }

    private func machineLine(_ machine: ForkMacBackupMachine) -> String {
        var line = machine.identity.description + " · " + text.snapshotCount(machine.snapshots, language: l10n.language)
        if let latest = machine.latest {
            line += " · " + ForkMacBackupFormat.relative(latest, now: model.context.services.now(), locale: locale)
        }
        return line
    }

    private func resultRow(_ result: ForkMacBackupWizardModel.NodeResult) -> some View {
        HStack(spacing: 10) {
            ForkMacBackupIconTile(symbol: result.node.symbol, color: color(result.state), size: 22)
            Text(result.node.displayTitle(shared))
            Spacer()
            switch result.state {
            case .pending:
                Text("–").foregroundStyle(.tertiary)
            case .running:
                ProgressView().controlSize(.mini)
            case .ok(let detail):
                Label(detail, systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .lineLimit(1)
            case .failed(let detail):
                Label(detail, systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            case .skipped:
                Text(text.testSkipped)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func color(_ state: ForkMacBackupWizardModel.NodeState) -> Color {
        switch state {
        case .ok: return ForkMacBackupStyle.accent
        case .failed: return .red
        case .running: return .blue
        case .pending, .skipped: return .gray
        }
    }

    // MARK: 4. Identity

    @ViewBuilder
    private var identityStep: some View {
        if model.origin == .otherMac {
            Section {
                Picker(text.otherMacHeader, selection: $model.browseOnly) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(text.otherMacBrowse)
                        Text(text.otherMacBrowseCaption).font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(text.otherMacTakeOver)
                        Text(text.otherMacTakeOverCaption).font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(false)
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text(text.otherMacHeader)
            }
        }
        if model.origin != .otherMac || !model.browseOnly {
            Section {
                Picker(text.identityHeader, selection: $model.identityChoice) {
                    ForEach(model.machines) { machine in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(String(format: text.identityContinue, machine.identity.description))
                            Text(machineLine(machine)).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(ForkMacBackupWizardModel.IdentityChoice.continuing(machine.identity))
                    }
                    if case .continuing(let identity) = model.identityChoice,
                       !model.machines.contains(where: { $0.identity == identity }) {
                        Text(String(format: text.identityContinue, identity.description))
                            .tag(ForkMacBackupWizardModel.IdentityChoice.continuing(identity))
                    }
                    Text(text.identityNew).tag(ForkMacBackupWizardModel.IdentityChoice.new)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                if model.identityChoice == .new {
                    TextField(text.identityUser, text: $model.newUser)
                    TextField(text.identityHost, text: $model.newHost)
                }
                if let warning = identityWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(text.identityHeader)
            } footer: {
                ForkMacBackupCaption(text.identityFooter)
            }
        }
    }

    /// Continuing an identity another Mac still uses mixes two histories.
    private var identityWarning: String? {
        guard case .continuing(let identity) = model.identityChoice,
              identity.hostName.lowercased() != model.context.localIdentity.hostName.lowercased(),
              let machine = model.machines.first(where: { $0.identity == identity }), let latest = machine.latest,
              model.context.services.now().timeIntervalSince(latest) < 3 * 86_400 else { return nil }
        return String(format: text.identityStillUsed, identity.description,
                      ForkMacBackupFormat.relative(latest, now: model.context.services.now(), locale: locale))
    }

    // MARK: 5. Kit

    @ViewBuilder
    private var kitStep: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.origin == .otherMac && model.browseOnly ? text.doneBrowseTitle : text.doneTitle)
                        .font(.headline)
                    ForkMacBackupCaption(model.origin == .otherMac && model.browseOnly ? text.doneBrowseCaption : text.doneCaption)
                }
            }
            .padding(.vertical, 4)
        }
        if model.origin != .otherMac || !model.browseOnly {
            Section {
                HStack(alignment: .top, spacing: 10) {
                    ForkMacBackupIconTile(symbol: "lifepreserver.fill", color: .orange, size: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(text.kitTitle).fontWeight(.medium)
                        ForkMacBackupCaption(text.kitWhy)
                    }
                }
            }
        }
        if model.bran != nil {
            Section {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(text.branStillRuns).fontWeight(.medium)
                        ForkMacBackupCaption(text.branStillRunsCaption)
                    }
                    Spacer()
                    switch model.stopState {
                    case .idle:
                        Button(text.stopBran) { confirmingStop = true }
                    case .stopping:
                        ProgressView().controlSize(.small)
                    case .stopped:
                        Label(text.branStopped, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    case .failed:
                        Button(text.tryAgain) { confirmingStop = true }
                    }
                }
                if model.stopState == .failed {
                    ForkMacBackupCaption(text.branStopFailed, color: .orange)
                }
            } header: {
                Text("Bran")
            }
        }
    }
}

/// What « Importer depuis Bran » found, before anything is saved.
struct ForkMacBackupBranSummary: View {
    let text: ForkMacBackupSettingsStrings
    let bran: ForkMacBackupBranImport.Result
    let secretsRead: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(bran.repository.endpoint.hostAndPort, systemImage: "server.rack")
                .font(.callout.weight(.medium))
            if bran.usesMagicDNS, let ip = bran.repository.endpoint.observedIPs.first {
                ForkMacBackupCaption(String(format: text.branMagicDNS, ip))
            }
            ForkMacBackupCaption(String(format: text.branDetails, bran.repository.bucket,
                                        bran.repository.clientIdentity.description))
            ForkMacBackupCaption(String(format: text.branRules, bran.rulesAsPresets.count, bran.customRules.count))
            if let hours = bran.branIntervalHours {
                ForkMacBackupCaption(String(format: text.branRhythm, hours))
            }
            Label(secretsRead ? text.branSecretsRead : text.branSecretsMissing,
                  systemImage: secretsRead ? "key.fill" : "key")
                .font(.caption)
                .foregroundStyle(secretsRead ? Color.green : Color.orange)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.purple.opacity(0.08)))
    }
}
