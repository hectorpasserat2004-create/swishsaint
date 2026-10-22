// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// « Contenu » (plan §4): the folders backed up, the named exclusions with
/// their real size, the sparse disk images, iCloud Drive, free rules with
/// the paths they touch, and the preview of what is kept and left out.
struct ForkMacBackupContentSheet: View {
    @ObservedObject var context: ForkMacBackupSettingsContext
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(ForkDefaultsKey.macBackupPresets) private var presetsStorage =
        ForkMacBackupPreset.storageValue(ForkMacBackupPreset.defaultApplied)
    @AppStorage(ForkDefaultsKey.macBackupRules) private var rulesStorage = ""
    @AppStorage(ForkDefaultsKey.macBackupICloudMode) private var iCloudMode = ForkMacBackupICloudMode.fallback.rawValue
    @State private var newRule = ""
    @State private var rulesExpanded = false
    @State private var dropTargeted = false

    private var text: ForkMacBackupSettingsStrings { .strings(l10n.language) }
    private var shared: ForkMacBackupStrings { .strings(l10n.language) }
    private var locale: Locale { l10n.language.formattingLocale() }

    /// The order the switches are listed in: the big ones first.
    static let listed: [ForkMacBackupPreset] = [.trash, .caches, .docker, .appleContainer, .virtualMachines,
                                                .devFolders, .genericBuildNames, .cloudStorage, .cacheDirTag,
                                                .logs, .secrets]

    var body: some View {
        ForkMacBackupSheetScaffold(symbol: "folder.fill", color: .blue, title: text.contentTitle, subtitle: text.contentSubtitle,
                                   done: text.done) {
            sourcesSection
            previewSection
            presetsSection
            sparseSection
            iCloudSection
            rulesSection
        }
    }

    // MARK: Sources

    private var sourcesSection: some View {
        Section {
            ForEach(context.effectiveSources) { source in
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: source.path))
                        .resizable()
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(source.displayName(.strings(l10n.language), home: context.home))
                        Text(ForkMacBackupFormat.middleTruncated(source.path, limit: 60, home: context.home))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        context.removeSource(source.path)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(context.effectiveSources.count < 2)
                    .help(text.sourceRemove)
                    .accessibilityLabel(text.sourceRemove)
                }
            }
            .onMove { context.moveSources(from: $0, to: $1) }
            HStack {
                Button {
                    chooseFolder()
                } label: {
                    Label(text.sourceAdd, systemImage: "plus")
                }
                Spacer()
                ForkMacBackupCaption(text.sourceDropHint)
            }
        } header: {
            Text(text.sourcesTitle)
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return }
                    DispatchQueue.main.async { context.addSource(url.path) }
                }
            }
            return true
        }
        .listRowBackground(dropTargeted ? ForkMacBackupStyle.accent.opacity(0.12) : nil)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: context.home)
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls { context.addSource(url.path) }
        }
    }

    // MARK: Preview

    private var previewSection: some View {
        Section {
            if let progress = context.scanProgress {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(format: text.previewScanning, progress.files.formatted(.number.locale(locale))))
                            .font(.callout)
                        Text(ForkMacBackupFormat.middleTruncated(progress.path, limit: 60, home: context.home))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button(text.cancel) { context.cancelScan() }
                        .controlSize(.small)
                }
            } else if let preview = context.preview {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        legend(ForkMacBackupStyle.accent, String(format: text.previewKept,
                                                                 ForkMacBackupFormat.bytes(preview.includedBytes, locale: locale)))
                        Spacer()
                        legend(.secondary.opacity(0.4), String(format: text.previewLeftOut,
                                                               ForkMacBackupFormat.bytes(preview.excludedBytes, locale: locale)))
                    }
                    ForkMacBackupSplitBar(kept: preview.includedBytes, left: preview.excludedBytes)
                    ForkMacBackupCaption(String(format: text.previewMeasured,
                                                ForkMacBackupFormat.relative(preview.measuredAt, now: context.services.now(), locale: locale),
                                                preview.includedFiles.formatted(.number.locale(locale))))
                }
                .accessibilityElement(children: .combine)
                let folders = preview.topFolders.filter { $0.path.filter { $0 == "/" }.count <= 1 }.prefix(6)
                if !folders.isEmpty {
                    let biggest = max(1, folders.first?.bytes ?? 1)
                    ForEach(Array(folders)) { folder in
                        HStack(spacing: 8) {
                            Text(folder.path)
                                .font(.caption)
                                .lineLimit(1)
                                .frame(width: 170, alignment: .leading)
                            GeometryReader { geometry in
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(ForkMacBackupStyle.accent.opacity(0.55))
                                    .frame(width: max(2, geometry.size.width * Double(folder.bytes) / Double(biggest)))
                            }
                            .frame(height: 6)
                            Text(ForkMacBackupFormat.bytes(folder.bytes, locale: locale))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 64, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                HStack {
                    Spacer()
                    Button(text.previewRefresh) { context.scanContent() }
                        .controlSize(.small)
                }
            } else {
                HStack(spacing: 10) {
                    ForkMacBackupCaption(text.previewNever)
                    Spacer()
                    Button(text.previewRun) { context.scanContent() }
                        .buttonStyle(.borderedProminent)
                        .tint(ForkMacBackupStyle.accent)
                }
            }
        } header: {
            Text(text.previewTitle)
        } footer: {
            ForkMacBackupCaption(text.previewFooter)
        }
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label)
                .font(.callout.weight(.medium))
        }
    }

    // MARK: Presets

    private var presets: [ForkMacBackupPreset] { ForkMacBackupPreset.parse(presetsStorage) }

    private func binding(_ preset: ForkMacBackupPreset) -> Binding<Bool> {
        Binding(get: { presets.contains(preset) }, set: { on in
            var list = presets
            if on { list.append(preset) } else { list.removeAll { $0 == preset } }
            context.setPresets(list)
            presetsStorage = ForkMacBackupPreset.storageValue(list)
        })
    }

    private var presetsSection: some View {
        Section {
            ForEach(Self.listed, id: \.self) { preset in
                presetRow(preset)
            }
        } header: {
            Text(text.presetsTitle)
        } footer: {
            ForkMacBackupCaption(text.presetsFooter)
        }
    }

    private func presetRow(_ preset: ForkMacBackupPreset) -> some View {
        let group = context.preview?.group(preset)
        return VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: binding(preset)) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(text.presetTitle(preset))
                        ForkMacBackupCaption(text.presetCaption(preset))
                    }
                    Spacer(minLength: 8)
                    Text(size(group))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(group == nil ? .tertiary : .secondary)
                }
            }
            if preset == .genericBuildNames, let group, group.matches > 0 {
                examples(group)
            }
            if preset == .secrets, !presets.contains(.secrets) {
                Label(text.secretsIncluded, systemImage: "key.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if preset == .virtualMachines, !presets.contains(.virtualMachines) {
                ForkMacBackupCaption(text.vmWarning)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func size(_ group: ForkMacBackupContentPreview.Group?) -> String {
        guard let group else { return "–" }
        return ForkMacBackupFormat.bytes(group.bytes, locale: locale)
    }

    private func examples(_ group: ForkMacBackupContentPreview.Group) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text.matchCount(group.matches, language: l10n.language))
                .font(.caption.weight(.medium))
            ForEach(group.examples, id: \.self) { path in
                Text(path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.leading, 20)
    }

    // MARK: Sparse disk images

    private var sparseSection: some View {
        Section {
            Toggle(isOn: binding(.sparseDiskImages)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.presetTitle(.sparseDiskImages))
                    ForkMacBackupCaption(sparseSentence)
                }
            }
            if let sparse = context.preview?.sparse, !sparse.isEmpty {
                ForEach(sparse.prefix(5)) { file in
                    HStack(spacing: 8) {
                        Image(systemName: "externaldrive")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text((file.path as NSString).lastPathComponent)
                            .font(.callout)
                            .lineLimit(1)
                            .help(file.path)
                        Spacer()
                        Text(String(format: text.sparseSizes,
                                    ForkMacBackupFormat.bytes(file.logicalBytes, locale: locale),
                                    ForkMacBackupFormat.bytes(file.allocatedBytes, locale: locale)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } header: {
            Text(text.sparseTitle)
        }
    }

    /// One friendly sentence, with both sizes of the biggest one when known.
    private var sparseSentence: String {
        guard let file = context.preview?.sparse.first else { return text.sparseExplain }
        return String(format: text.sparseExplainMeasured, (file.path as NSString).lastPathComponent,
                      ForkMacBackupFormat.bytes(file.logicalBytes, locale: locale),
                      ForkMacBackupFormat.bytes(file.allocatedBytes, locale: locale))
    }

    // MARK: iCloud

    private var iCloudSection: some View {
        Section {
            Picker(text.iCloudTitle, selection: Binding(get: { iCloudMode }, set: { value in
                iCloudMode = value
                context.objectWillChange.send()
            })) {
                ForEach(ForkMacBackupICloudMode.allCases, id: \.self) { mode in
                    Text(text.iCloudMode(mode)).tag(mode.rawValue)
                }
            }
            .pickerStyle(.radioGroup)
            ForkMacBackupCaption(text.iCloudCaption(ForkMacBackupICloudMode(rawValue: iCloudMode) ?? .fallback))
            if let preview = context.preview, preview.cloudOnlyFiles > 0 {
                Label(String(format: text.iCloudCloudOnly, preview.cloudOnlyFiles.formatted(.number.locale(locale)),
                             ForkMacBackupFormat.bytes(preview.cloudOnlyBytes, locale: locale)),
                      systemImage: "icloud")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(text.iCloudHeader)
        }
    }

    // MARK: Custom rules

    private var rules: [String] {
        guard !rulesStorage.isEmpty, let list = try? JSONDecoder().decode([String].self, from: Data(rulesStorage.utf8)) else {
            return []
        }
        return list
    }

    private func setRules(_ list: [String]) {
        context.setCustomRules(list)
        rulesStorage = context.defaults.string(forKey: ForkDefaultsKey.macBackupRules) ?? ""
    }

    private var rulesSection: some View {
        Section {
            DisclosureGroup(isExpanded: $rulesExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rules, id: \.self) { rule in
                        ruleRow(rule)
                    }
                    HStack {
                        TextField(text.ruleField, text: $newRule, prompt: Text(text.rulePlaceholder))
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                            .onSubmit(addRule)
                        Button(text.ruleAdd, action: addRule)
                            .disabled(ForkMacBackupIgnoreRule(newRule) == nil)
                    }
                    if let rule = ForkMacBackupIgnoreRule(newRule) {
                        ForkMacBackupCaption(text.ruleExplain(rule))
                    }
                    ForkMacBackupCaption(text.rulesSyntax)
                }
                .padding(.top, 6)
            } label: {
                HStack {
                    Text(text.rulesTitle)
                    Spacer()
                    Text(text.ruleCount(rules.count, language: l10n.language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func ruleRow(_ rule: String) -> some View {
        let group = context.preview?.group(rule: rule)
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule)
                    .font(.body.monospaced())
                if let group {
                    Text(group.matches == 0 ? text.ruleNoMatch
                         : text.matchCount(group.matches, language: l10n.language) + " · "
                            + ForkMacBackupFormat.bytes(group.bytes, locale: locale))
                        .font(.caption)
                        .foregroundStyle(group.matches == 0 ? .orange : .secondary)
                    ForEach(group.examples.prefix(3), id: \.self) { path in
                        Text(path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } else if let parsed = ForkMacBackupIgnoreRule(rule) {
                    ForkMacBackupCaption(text.ruleExplain(parsed))
                }
            }
            Spacer()
            Button {
                setRules(rules.filter { $0 != rule })
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(text.ruleRemove)
            .accessibilityLabel(text.ruleRemove)
        }
    }

    private func addRule() {
        let rule = newRule.trimmingCharacters(in: .whitespaces)
        guard ForkMacBackupIgnoreRule(rule) != nil, !rules.contains(rule) else { return }
        setRules(rules + [rule])
        newRule = ""
    }
}
