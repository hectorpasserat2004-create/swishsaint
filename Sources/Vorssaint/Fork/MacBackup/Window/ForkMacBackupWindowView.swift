// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The sidebar (this Mac's sources, the other Macs, the follow-up tabs)
/// beside the tab shown.
struct ForkMacBackupWindowView: View {
    @ObservedObject var model: ForkMacBackupWindowModel
    @ObservedObject var status: ForkMacBackupStatusModel
    @State private var columns: NavigationSplitViewVisibility = .all

    init(model: ForkMacBackupWindowModel) {
        self.model = model
        status = model.status
    }

    private var text: ForkMacBackupWindowStrings { model.text }
    private var shared: ForkMacBackupStrings { model.shared }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: ForkMacBackupWindowController.minimumSize.width,
               minHeight: ForkMacBackupWindowController.minimumSize.height)
        .sheet(item: $model.restoreFlow) { flow in
            ForkMacBackupRestoreSheet(flow: flow) { model.restoreFlow = nil }
        }
        .sheet(item: $model.versionsSheet) { sheet in
            ForkMacBackupVersionsSheet(model: model, sheet: sheet)
        }
        .sheet(item: $model.verdict) { verdict in
            ForkMacBackupVerdictSheet(model: model, verdict: verdict)
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $model.sidebarSelection) {
            Section(shared.nodeMac) {
                if model.localSources.isEmpty {
                    Text(placeholderLine)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                }
                ForEach(model.localSources) { key in
                    sourceRow(key, subtitle: nil)
                        .tag(ForkMacBackupSidebarItem.source(key.id))
                }
            }
            if !model.otherMachines.isEmpty {
                Section(text.sidebarOtherMacs) {
                    ForEach(model.otherMachines, id: \.machine) { machine in
                        ForEach(machine.sources) { key in
                            sourceRow(key, subtitle: key.host)
                                .tag(ForkMacBackupSidebarItem.source(key.id))
                        }
                    }
                }
            }
            Section(text.sidebarActivity) {
                Label(text.tabHistory, systemImage: "clock.arrow.circlepath")
                    .tag(ForkMacBackupSidebarItem.history)
                Label {
                    HStack {
                        Text(text.tabHealth)
                        Spacer()
                        Circle()
                            .fill(ForkMacBackupWindowStyle.color(status.presentation.tone))
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                    }
                } icon: {
                    Image(systemName: "stethoscope")
                }
                .tag(ForkMacBackupSidebarItem.health)
                Label(text.tabVerifications, systemImage: "checkmark.shield")
                    .tag(ForkMacBackupSidebarItem.verifications)
            }
        }
        .listStyle(.sidebar)
    }

    private var placeholderLine: String {
        switch model.engineState {
        case .loading: return text.loading
        case .unavailable: return text.unavailableTitle
        case .ready: return text.noSnapshotTitle
        }
    }

    private func sourceRow(_ key: ForkMacBackupSourceKey, subtitle: String?) -> some View {
        let last = model.snapshots[key]?.last
        return Label {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(key.displayName)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if let last {
                    ForkMacBackupProofDots(level: last.proof.level, isPartial: last.proof.isPartial, dot: 5, gap: 2)
                }
            }
        } icon: {
            Image(systemName: ForkMacBackupWindowStyle.symbol(forSource: key.path))
        }
        .help(key.path)
        .accessibilityElement(children: .combine)
        .accessibilityValue(last.map { $0.proof.level.title(shared) } ?? "")
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        switch model.sidebarSelection {
        case .history:
            ForkMacBackupHistoryView(model: model)
                .navigationTitle(text.tabHistory)
        case .health:
            ForkMacBackupHealthView(model: model, status: status)
                .navigationTitle(text.tabHealth)
        case .verifications:
            ForkMacBackupVerificationsView(model: model)
                .navigationTitle(text.tabVerifications)
        case .source, nil:
            ForkMacBackupBrowseView(model: model)
        }
    }
}

// MARK: - Browse

/// « Parcourir »: the path, the files, the timeline, the inspector.
struct ForkMacBackupBrowseView: View {
    @ObservedObject var model: ForkMacBackupWindowModel
    @State private var dropTargeted = false

    private var text: ForkMacBackupWindowStrings { model.text }
    private var shared: ForkMacBackupStrings { model.shared }

    var body: some View {
        VStack(spacing: 0) {
            content
            ForkMacBackupTimelineBar(model: model)
        }
        .navigationTitle(model.selectedKey?.displayName ?? text.windowTitle)
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
        .inspector(isPresented: $model.inspectorShown) {
            ForkMacBackupInspector(model: model)
                .inspectorColumnWidth(min: 250, ideal: 290, max: 380)
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { model.check(url) }
            }
            return true
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(ForkMacBackupWindowStyle.teal, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                    .background(RoundedRectangle(cornerRadius: 12).fill(ForkMacBackupWindowStyle.teal.opacity(0.06)))
                    .overlay(Label(text.dropHint, systemImage: "questionmark.folder")
                        .font(.headline)
                        .padding(12)
                        .background(.regularMaterial, in: Capsule()))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
    }

    private var subtitle: String {
        guard let snapshot = model.selectedSnapshot else { return "" }
        var line = ForkMacBackupFormat.dayAndTime(snapshot.date, locale: model.locale)
        if model.isOtherMac, let key = model.selectedKey { line = key.machine + " · " + line }
        return line
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                model.stepSnapshot(-1)
            } label: {
                Label(text.previousSnapshot, systemImage: "chevron.backward")
            }
            .help(text.previousSnapshot + " (←)")
            .disabled(model.selectedSnapshot == nil || model.currentSnapshots.first?.id == model.selectedSnapshotID)
            Button {
                model.stepSnapshot(1)
            } label: {
                Label(text.nextSnapshot, systemImage: "chevron.forward")
            }
            .help(text.nextSnapshot + " (→)")
            .disabled(model.selectedSnapshot == nil || model.currentSnapshots.last?.id == model.selectedSnapshotID)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.beginRestore()
            } label: {
                Label(shared.restore, systemImage: "clock.arrow.circlepath")
                    .labelStyle(.titleAndIcon)
            }
            .help(shared.restore)
            .disabled(model.selectedEntries.isEmpty)
            ForkMacBackupSearchField(text: $model.searchText, placeholder: text.searchPlaceholder,
                                     focusToken: model.searchFocusToken)
                .frame(width: 230)
            Button {
                model.inspectorShown.toggle()
            } label: {
                Label(text.toggleInspector, systemImage: "sidebar.trailing")
            }
            .help(text.toggleInspector)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.engineState {
        case .loading:
            ProgressView(text.loading)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable:
            if model.status.presentation.phase == .notConfigured {
                ForkMacBackupEmptyState(symbol: "externaldrive.badge.questionmark", title: shared.notConfigured,
                                        detail: text.notConfiguredDetail)
            } else {
                ForkMacBackupEmptyState(symbol: "bolt.horizontal.circle", title: text.unavailableTitle,
                                        detail: text.unavailableDetail, action: (text.retry, { model.reload() }))
            }
        case .ready:
            if model.selectedSnapshot == nil {
                ForkMacBackupEmptyState(symbol: "clock.badge.questionmark", title: text.noSnapshotTitle,
                                        detail: text.noSnapshotDetail)
            } else {
                VStack(spacing: 0) {
                    ForkMacBackupPathBar(model: model)
                    Divider()
                    files
                    Divider()
                    ForkMacBackupStatusBar(model: model)
                }
            }
        }
    }

    @ViewBuilder private var files: some View {
        let searching = !model.search.query.isEmpty
        let list = searching ? model.search.results : model.entries
        ZStack {
            ForkMacBackupFileTable(model: model, entries: list, showsFolder: searching)
            if searching && list.isEmpty && !model.search.running {
                ForkMacBackupEmptyState(symbol: "magnifyingglass", title: text.searchNoResult)
                    .allowsHitTesting(false)
            } else if !searching {
                switch model.folderState {
                case .loading where model.entries.isEmpty:
                    ProgressView().controlSize(.small)
                case .failed(let message):
                    ForkMacBackupEmptyState(symbol: "exclamationmark.triangle", title: String(format: text.readFailed, message),
                                            action: (text.retry, { model.loadFolder(model.folder, keepSelection: true) }))
                        .background(Color(nsColor: .windowBackgroundColor))
                case .loaded where model.entries.isEmpty:
                    Text(text.folderEmpty)
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                default:
                    EmptyView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Where we are in the snapshot: the source, then each folder, clickable.
struct ForkMacBackupPathBar: View {
    @ObservedObject var model: ForkMacBackupWindowModel

    var body: some View {
        HStack(spacing: 6) {
            Button {
                model.goToParent()
            } label: {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.borderless)
            .help(model.text.parentFolder + " (⌘↑)")
            .accessibilityLabel(model.text.parentFolder)
            .disabled(model.folder.isEmpty)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    crumb(model.selectedKey?.displayName ?? "", symbol: ForkMacBackupWindowStyle.symbol(
                        forSource: model.selectedKey?.path ?? ""), depth: 0, last: model.folder.isEmpty)
                    ForEach(Array(model.folder.enumerated()), id: \.offset) { index, name in
                        Image(systemName: "chevron.compact.right")
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                        crumb(name, symbol: "folder.fill", depth: index + 1, last: index == model.folder.count - 1)
                    }
                }
            }
            Spacer(minLength: 0)
            if model.search.running {
                ProgressView().controlSize(.small)
                Text(String(format: model.text.searching, model.search.query))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button(model.text.searchStop) { model.stopSearch() }
                    .controlSize(.small)
            } else if !model.search.query.isEmpty {
                Text(model.text.searchResults(model.search.results.count, model.language))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func crumb(_ title: String, symbol: String, depth: Int, last: Bool) -> some View {
        Button {
            model.goTo(depth: depth)
        } label: {
            Label(title, systemImage: symbol)
                .font(.callout.weight(last ? .semibold : .regular))
                .foregroundStyle(last ? Color.primary : Color.secondary)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .disabled(last)
    }
}

/// The line under the files, as the Finder's status bar.
struct ForkMacBackupStatusBar: View {
    @ObservedObject var model: ForkMacBackupWindowModel
    @ObservedObject var quickLook: ForkMacBackupQuickLook

    init(model: ForkMacBackupWindowModel) {
        self.model = model
        quickLook = model.quickLook
    }

    var body: some View {
        HStack(spacing: 8) {
            if let notice = model.notice {
                Label(notice.text, systemImage: notice.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(notice.isError ? Color.orange : ForkMacBackupWindowStyle.teal)
                    .transition(.opacity)
            } else if let transfer = model.transfer {
                ProgressView().controlSize(.small)
                Text(String(format: model.text.restoringItem, transfer.name))
            } else if quickLook.preparing != nil {
                ProgressView().controlSize(.small)
                Text(model.text.preparingPreview)
            } else if let note = model.folderNote {
                Label(note, systemImage: "info.circle")
            } else {
                Text(summary)
            }
            Spacer()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .animation(.easeInOut(duration: 0.2), value: model.notice)
    }

    private var summary: String {
        let count = model.search.query.isEmpty ? model.entries.count : model.search.results.count
        var parts = [model.text.items(count, model.language)]
        if model.selection.count > 0 {
            parts = [model.text.selected(model.selection.count, model.language)]
            let size = ForkMacBackupSelectionSize.of(model.selectedEntries)
            parts.append(ForkMacBackupFormat.bytes(size.bytes, locale: model.locale))
        }
        if model.search.truncated { parts.append(model.text.searchTruncated) }
        return parts.joined(separator: " · ")
    }
}
