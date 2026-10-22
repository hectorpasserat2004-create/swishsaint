// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// « Ma chaîne » (plan §11.1): the active profile drawn, one node per step,
/// each with its live state. A broken node turns red and the link before it
/// dashed; a click opens the node's detail. The profile menu sits on top.
struct ForkMacBackupChainCard: View {
    let text: ForkMacBackupSettingsStrings
    let shared: ForkMacBackupStrings
    let language: AppLanguage
    @ObservedObject var context: ForkMacBackupSettingsContext
    let presentation: ForkMacBackupPresentation
    let open: (ForkMacBackupSheet) -> Void

    @State private var selected: String?
    @State private var problem: String?

    var body: some View {
        let nodes = ForkMacBackupChainDisplay.nodes(context.chain, statuses: presentation.chain)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(text.chainTitle)
                    .font(.headline)
                Spacer()
                ForkMacBackupProfileMenu(text: text, context: context, open: open, problem: $problem)
            }
            ForkMacBackupChainDiagram(nodes: nodes, shared: shared, text: text, language: language,
                                      presentation: presentation, selected: $selected, context: context)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "text.quote")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text(explanation(nodes))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let problem {
                ForkMacBackupCaption(problem, color: .orange)
            }
        }
        .padding(.vertical, 4)
    }

    /// The profile's own sentence, else one made from the nodes.
    private func explanation(_ nodes: [ForkMacBackupChainDisplayNode]) -> String {
        if let sentence = context.profile?.explanation, !sentence.isEmpty,
           context.profile?.repository.key == context.repository?.key {
            return sentence
        }
        let kinds = nodes.map(\.node.kind)
        let server = nodes.first { $0.node.kind == .s3 || $0.node.kind == .cloud }?.node.displayTitle(shared)
            ?? shared.nodeS3
        let storage = nodes.last { $0.node.kind == .nas || $0.node.kind == .cloud }?.node.displayTitle(shared)
        if kinds.contains(.tailscale) {
            if let storage, storage != server {
                return String(format: text.explainTailscaleStorage, server, storage)
            }
            return String(format: text.explainTailscale, server)
        }
        return String(format: text.explainDirect, server)
    }
}

/// The nodes and the links between them.
struct ForkMacBackupChainDiagram: View {
    let nodes: [ForkMacBackupChainDisplayNode]
    let shared: ForkMacBackupStrings
    let text: ForkMacBackupSettingsStrings
    let language: AppLanguage
    let presentation: ForkMacBackupPresentation
    @Binding var selected: String?
    let context: ForkMacBackupSettingsContext

    static let tileSize: CGFloat = 40

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                if index > 0 {
                    ForkMacBackupChainLink(state: linkState(node))
                        .frame(minWidth: 10, maxWidth: 180)
                        .frame(height: Self.tileSize)
                }
                nodeButton(node)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func linkState(_ node: ForkMacBackupChainDisplayNode) -> ForkMacBackupChainLink.State {
        if node.linkBeforeBroken { return .broken }
        if node.isBeyondBreak { return .unknown }
        return node.state == .unknown ? .unknown : .ok
    }

    private func nodeButton(_ node: ForkMacBackupChainDisplayNode) -> some View {
        Button {
            selected = node.id
        } label: {
            ForkMacBackupChainNodeView(node: node, subtitle: subtitle(node), title: node.node.displayTitle(shared))
        }
        .buttonStyle(.plain)
        .popover(isPresented: Binding(get: { selected == node.id }, set: { if !$0 { selected = nil } }),
                 arrowEdge: .bottom) {
            ForkMacBackupChainNodeDetail(node: node, text: text, shared: shared, language: language,
                                         presentation: presentation, context: context)
        }
        .help(node.node.displayTitle(shared))
        .accessibilityLabel("\(node.node.displayTitle(shared)), \(ForkMacBackupStyle.title(node.state, shared))")
        .accessibilityHint(text.nodeDetailHint)
    }

    /// Under a node: what is most telling, in a few characters.
    private func subtitle(_ node: ForkMacBackupChainDisplayNode) -> String {
        let locale = language.formattingLocale()
        switch node.state {
        case .broken: return shared.nodeBroken
        case .unknown: return node.isBeyondBreak ? "–" : shared.nodeUnknown
        case .slow, .ok:
            if node.node.kind == .nas, let free = presentation.capacity.nasFreeBytes {
                return String(format: shared.freeSpace, ForkMacBackupFormat.bytes(free, locale: locale))
            }
            if let latency = node.latencyMs { return String(format: text.latencyMs, latency) }
            if !node.node.detail.isEmpty, node.node.kind == .proxmox { return node.node.detail }
            return ForkMacBackupStyle.title(node.state, shared)
        }
    }
}

/// One node: a tile tinted by its state, its name, one short line.
struct ForkMacBackupChainNodeView: View {
    let node: ForkMacBackupChainDisplayNode
    let subtitle: String
    let title: String

    var body: some View {
        let color = node.state == .unknown ? Color.gray : ForkMacBackupStyle.color(node.state)
        VStack(spacing: 5) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(color.gradient.opacity(node.state == .unknown ? 0.45 : 1))
                    .frame(width: ForkMacBackupChainDiagram.tileSize, height: ForkMacBackupChainDiagram.tileSize)
                    .overlay(
                        Image(systemName: node.node.symbol)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                    )
                    .shadow(color: color.opacity(node.state == .unknown ? 0 : 0.35), radius: 4, y: 2)
                if node.state != .unknown {
                    Image(systemName: ForkMacBackupStyle.symbol(node.state))
                        .font(.system(size: 12, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, ForkMacBackupStyle.color(node.state))
                        .background(Circle().fill(Color(nsColor: .windowBackgroundColor)).padding(-1.5))
                        .offset(x: 5, y: 5)
                }
            }
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(node.isBeyondBreak ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(node.state == .broken ? Color.red : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(width: 78)
        .contentShape(Rectangle())
    }
}

/// A link: a line with an arrow head, dashed red before a break, dotted
/// grey after it.
struct ForkMacBackupChainLink: View {
    enum State {
        case ok
        case broken
        case unknown
    }

    let state: State

    var body: some View {
        Canvas { context, size in
            let y = size.height / 2
            let inset: CGFloat = 2
            var line = Path()
            line.move(to: CGPoint(x: inset, y: y))
            line.addLine(to: CGPoint(x: size.width - inset - 4, y: y))
            let stroke: StrokeStyle
            let color: Color
            switch state {
            case .ok:
                stroke = StrokeStyle(lineWidth: 2, lineCap: .round)
                color = ForkMacBackupStyle.accent.opacity(0.7)
            case .broken:
                stroke = StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 3])
                color = .red
            case .unknown:
                stroke = StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [1, 3])
                color = .secondary.opacity(0.6)
            }
            context.stroke(line, with: .color(color), style: stroke)
            var head = Path()
            head.move(to: CGPoint(x: size.width - inset - 6, y: y - 3.5))
            head.addLine(to: CGPoint(x: size.width - inset, y: y))
            head.addLine(to: CGPoint(x: size.width - inset - 6, y: y + 3.5))
            context.stroke(head, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .padding(.horizontal, 2)
        .accessibilityHidden(true)
    }
}

/// A node's detail (popover): what it is, where it is, its last measure,
/// and what to do when it is red.
struct ForkMacBackupChainNodeDetail: View {
    let node: ForkMacBackupChainDisplayNode
    let text: ForkMacBackupSettingsStrings
    let shared: ForkMacBackupStrings
    let language: AppLanguage
    let presentation: ForkMacBackupPresentation
    let context: ForkMacBackupSettingsContext

    var body: some View {
        let locale = language.formattingLocale()
        let color = ForkMacBackupStyle.color(node.state)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ForkMacBackupIconTile(symbol: node.node.symbol, color: node.state == .unknown ? .gray : color, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(node.node.displayTitle(shared))
                        .font(.headline)
                    Label(ForkMacBackupStyle.title(node.state, shared), systemImage: ForkMacBackupStyle.symbol(node.state))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(node.state == .unknown ? .secondary : color)
                }
            }
            Text(text.about(node.node.kind))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
                if let address = address {
                    row(text.detailAddress, address, monospaced: true)
                }
                if let ips = observedIPs {
                    row(text.detailObservedIPs, ips, monospaced: true)
                }
                if let checked = node.checkedAt {
                    let when = ForkMacBackupFormat.relative(checked, now: context.services.now(), locale: locale)
                    let latency = node.latencyMs.map { " · " + String(format: text.latencyMs, $0) } ?? ""
                    row(text.detailLastCheck, when + latency)
                } else {
                    row(text.detailLastCheck, shared.never)
                }
                if node.node.kind == .nas, let free = presentation.capacity.nasFreeBytes {
                    row(text.detailFree, ForkMacBackupFormat.bytes(free, locale: locale))
                }
                if node.node.kind == .repository, let id = context.repository?.expectedUniqueID {
                    row(text.detailUniqueID, ForkMacBackupRepository.shortID(id), monospaced: true)
                }
                if node.node.probe == nil {
                    row(text.detailProbe, text.detailNotProbed)
                }
            }
            .font(.caption)
            if node.state == .broken || node.state == .slow {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .foregroundStyle(color)
                    Text(text.remedy(node.node.kind))
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color.opacity(0.1)))
            } else if node.isBeyondBreak {
                ForkMacBackupCaption(text.beyondBreak)
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private var address: String? {
        let repository = context.repository
        switch node.node.kind {
        case .s3: return repository?.endpoint.hostAndPort ?? nilIfEmpty(node.node.detail)
        case .repository:
            guard let repository else { return nilIfEmpty(node.node.detail) }
            return repository.prefix.isEmpty ? repository.bucket : "\(repository.bucket)/\(repository.prefix)"
        case .tailscale:
            return repository?.peer?.dnsName ?? nilIfEmpty(node.node.detail)
        default:
            return nilIfEmpty(node.node.detail)
        }
    }

    private var observedIPs: String? {
        guard node.node.kind == .s3 || node.node.kind == .tailscale,
              let ips = context.repository?.endpoint.observedIPs, !ips.isEmpty else { return nil }
        return ips.joined(separator: ", ")
    }

    private func nilIfEmpty(_ value: String) -> String? { value.isEmpty ? nil : value }

    private func row(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .font(monospaced ? .caption.monospaced() : .caption)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }
}

// MARK: - Profiles

/// « Profil « Maison — QNAP » ▾ »: the profiles known on this Mac, import,
/// export (never a secret), create through the wizard.
struct ForkMacBackupProfileMenu: View {
    let text: ForkMacBackupSettingsStrings
    @ObservedObject var context: ForkMacBackupSettingsContext
    let open: (ForkMacBackupSheet) -> Void
    @Binding var problem: String?

    var body: some View {
        Menu {
            if !context.knownProfiles.isEmpty {
                Section(text.profilesKnown) {
                    ForEach(context.knownProfiles, id: \.name) { profile in
                        Button {
                            choose(profile)
                        } label: {
                            if profile.name == context.profile?.name {
                                Label(profile.name, systemImage: "checkmark")
                            } else {
                                Text(profile.name)
                            }
                        }
                    }
                }
            }
            Button(text.profileImport) { importProfile() }
            Button(text.profileExport) { exportProfile() }
                .disabled(context.repository == nil && context.profile == nil)
            Button(text.profileCreate) { open(.wizard(.choose)) }
            if context.profile != nil {
                Divider()
                Button(text.profileNone) { context.setProfile(nil) }
            }
        } label: {
            Label(context.profile.map { String(format: text.profileNamed, $0.name) } ?? text.profileNoneLabel,
                  systemImage: "person.crop.rectangle.stack")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel(text.profilesMenu)
    }

    private func choose(_ profile: ForkMacBackupProfile) {
        problem = nil
        if let repository = context.repository, repository.key == profile.repository.key {
            context.setProfile(profile)
        } else {
            open(.wizard(.profile(profile)))
        }
    }

    private func importProfile() {
        problem = nil
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: ForkMacBackupProfile.fileExtension) ?? .json, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let data = try? Data(contentsOf: url), let profile = ForkMacBackupProfile.decode(data) else {
                problem = text.profileUnreadable
                return
            }
            choose(profile)
        }
    }

    private func exportProfile() {
        guard let profile = currentProfile, let data = ForkMacBackupProfileFile.encode(profile),
              !ForkMacBackupProfileFile.containsSecretField(data) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: ForkMacBackupProfile.fileExtension) ?? .json]
        panel.nameFieldStringValue = ForkMacBackupFileNames.safe(profile.name) + "." + ForkMacBackupProfile.fileExtension
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                problem = text.fileNotSaved
            }
        }
    }

    /// The active profile, else one made from the connection and the rules.
    private var currentProfile: ForkMacBackupProfile? {
        if let profile = context.profile { return profile }
        guard let repository = context.repository else { return nil }
        return ForkMacBackupProfile(name: String(format: text.profileDefaultName, repository.bucket),
                                    repository: repository, chain: context.chain, explanation: "",
                                    rules: .init(presets: context.presets, custom: context.customRules,
                                                 iCloud: context.iCloudMode))
    }
}

enum ForkMacBackupFileNames {
    /// A name a file can carry: no slash, no colon.
    static func safe(_ name: String) -> String {
        let cleaned = name.map { "/:\\".contains($0) ? "-" : $0 }
        let text = String(cleaned).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? "backup" : text
    }
}
