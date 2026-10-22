// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The browser's list, as the Finder's list view: icon and name, the
/// status against this Mac, the size, the date. AppKit, for the Finder's
/// own feel (type-select, double-click, contextual menu) and for dragging
/// files out as file promises (`NSFilePromiseProvider`, restored on drop).
struct ForkMacBackupFileTable: NSViewRepresentable {
    @ObservedObject var model: ForkMacBackupWindowModel
    let entries: [ForkMacBackupBrowseEntry]
    /// Search results: the folder shows after the name.
    let showsFolder: Bool

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.style = .fullWidth
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = true
        table.allowsColumnResizing = true
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.rowSizeStyle = .default
        table.intercellSpacing = NSSize(width: 6, height: 2)
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.autosaveName = "fork.macbackup.window.files"
        for column in Coordinator.Column.allCases {
            let item = NSTableColumn(identifier: column.identifier)
            item.minWidth = column.minWidth
            item.width = column.width
            item.resizingMask = column == .name ? [.autoresizingMask, .userResizingMask] : .userResizingMask
            item.sortDescriptorPrototype = NSSortDescriptor(key: column.rawValue, ascending: true)
            if column == .size { item.headerCell.alignment = .right }
            table.addTableColumn(item)
        }
        table.autosaveTableColumns = true
        table.sortDescriptors = [NSSortDescriptor(key: Coordinator.Column.name.rawValue, ascending: true)]
        let menu = NSMenu()
        menu.delegate = context.coordinator
        table.menu = menu
        context.coordinator.table = table

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.model = model
        coordinator.update(entries: entries, showsFolder: showsFolder, text: model.text, locale: model.locale,
                           selection: model.selection)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate,
        NSFilePromiseProviderDelegate {
        enum Column: String, CaseIterable {
            case name
            case status
            case size
            case modified

            var identifier: NSUserInterfaceItemIdentifier { NSUserInterfaceItemIdentifier("fork.macbackup.\(rawValue)") }

            var width: CGFloat {
                switch self {
                case .name: return 360
                case .status: return 130
                case .size: return 90
                case .modified: return 170
                }
            }

            var minWidth: CGFloat {
                switch self {
                case .name: return 180
                case .status: return 40
                case .size: return 60
                case .modified: return 90
                }
            }
        }

        weak var table: NSTableView?
        var model: ForkMacBackupWindowModel
        private var rows: [ForkMacBackupBrowseEntry] = []
        private var unsorted: [ForkMacBackupBrowseEntry] = []
        private var showsFolder = false
        private var text: ForkMacBackupWindowStrings = .enUS
        private var locale = Locale.current
        private var applyingSelection = false
        private let promiseQueue: OperationQueue = {
            let queue = OperationQueue()
            queue.qualityOfService = .userInitiated
            queue.maxConcurrentOperationCount = 2
            return queue
        }()
        private static var iconCache: [String: NSImage] = [:]

        init(model: ForkMacBackupWindowModel) {
            self.model = model
        }

        func update(entries: [ForkMacBackupBrowseEntry], showsFolder: Bool, text: ForkMacBackupWindowStrings,
                    locale: Locale, selection: Set<String>) {
            guard let table else { return }
            let wordsChanged = self.text.columnName != text.columnName || self.locale != locale
            self.text = text
            self.locale = locale
            if wordsChanged || table.tableColumns.first?.title.isEmpty == true { applyTitles(table) }
            if entries != unsorted || showsFolder != self.showsFolder || wordsChanged {
                let sameLines = entries.map(\.id) == unsorted.map(\.id)
                unsorted = entries
                self.showsFolder = showsFolder
                rows = sorted(entries, by: table.sortDescriptors)
                if sameLines {
                    table.reloadData(forRowIndexes: IndexSet(integersIn: 0..<rows.count),
                                     columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns))
                } else {
                    table.reloadData()
                }
            }
            let wanted = IndexSet(rows.indices.filter { selection.contains(rows[$0].id) })
            if table.selectedRowIndexes != wanted {
                applyingSelection = true
                table.selectRowIndexes(wanted, byExtendingSelection: false)
                if let first = wanted.first { table.scrollRowToVisible(first) }
                applyingSelection = false
            }
        }

        private func applyTitles(_ table: NSTableView) {
            for column in table.tableColumns {
                switch Column.allCases.first(where: { $0.identifier == column.identifier }) {
                case .name: column.title = text.columnName
                case .status: column.title = text.columnStatus
                case .size: column.title = text.columnSize
                case .modified: column.title = text.columnModified
                case nil: break
                }
            }
        }

        private func sorted(_ entries: [ForkMacBackupBrowseEntry], by descriptors: [NSSortDescriptor])
            -> [ForkMacBackupBrowseEntry] {
            guard let descriptor = descriptors.first, let key = descriptor.key.flatMap(Column.init(rawValue:)) else {
                return entries.sorted(by: ForkMacBackupBrowseEntry.finderOrder)
            }
            let ascending = descriptor.ascending
            return entries.sorted { lhs, rhs in
                let ordered: Bool?
                switch key {
                case .name: ordered = nil
                case .status:
                    ordered = lhs.localStatus == rhs.localStatus ? nil
                        : rank(lhs.localStatus) < rank(rhs.localStatus)
                case .size:
                    ordered = lhs.size == rhs.size ? nil : (lhs.size ?? -1) < (rhs.size ?? -1)
                case .modified:
                    ordered = lhs.modified == rhs.modified ? nil
                        : (lhs.modified ?? .distantPast) < (rhs.modified ?? .distantPast)
                }
                let result = ordered ?? ForkMacBackupBrowseEntry.finderOrder(lhs, rhs)
                return ascending ? result : !result
            }
        }

        private func rank(_ status: ForkMacBackupLocalStatus) -> Int {
            ForkMacBackupLocalStatus.allCases.firstIndex(of: status) ?? 0
        }

        // MARK: Data

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            rows = sorted(unsorted, by: tableView.sortDescriptors)
            tableView.reloadData()
            let wanted = IndexSet(rows.indices.filter { model.selection.contains(rows[$0].id) })
            applyingSelection = true
            tableView.selectRowIndexes(wanted, byExtendingSelection: false)
            applyingSelection = false
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row), let tableColumn,
                  let column = Column.allCases.first(where: { $0.identifier == tableColumn.identifier }) else { return nil }
            let entry = rows[row]
            let cell = (tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? FileCell)
                ?? FileCell(identifier: tableColumn.identifier, column: column)
            cell.show(entry, column: column, showsFolder: showsFolder, text: text, language: model.language, locale: locale,
                      icon: Self.icon(for: entry))
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !applyingSelection, let table else { return }
            let ids = Set(table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].id : nil })
            if model.selection != ids { model.selection = ids }
        }

        func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
            guard tableColumn?.identifier == Column.name.identifier, rows.indices.contains(row) else { return nil }
            return rows[row].name
        }

        @objc func doubleClicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard rows.indices.contains(row) else { return }
            let entry = rows[row]
            if entry.isDirectory {
                model.openFolder(entry)
            } else {
                model.selection = [entry.id]
                model.previewFile(entry)
            }
        }

        // MARK: Menu

        private var menuEntries: [ForkMacBackupBrowseEntry] {
            guard let table else { return [] }
            let clicked = table.clickedRow
            if rows.indices.contains(clicked), !table.selectedRowIndexes.contains(clicked) {
                return [rows[clicked]]
            }
            return table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0] : nil }
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            let chosen = menuEntries
            guard !chosen.isEmpty else { return }
            func add(_ title: String, _ symbol: String, _ action: Selector) {
                let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
                item.target = self
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                item.representedObject = chosen
                menu.addItem(item)
            }
            if chosen.count == 1, let entry = chosen.first {
                if entry.isDirectory {
                    add(text.open, "folder", #selector(openItem(_:)))
                } else {
                    add(text.quickLook, "eye", #selector(quickLookItem(_:)))
                }
            }
            add(ForkMacBackupStrings.strings(model.language).restore, "clock.arrow.circlepath", #selector(restoreItems(_:)))
            if !model.isOtherMac {
                add(text.restoreHere, "arrow.uturn.backward", #selector(restoreItemsHere(_:)))
            }
            if chosen.count == 1, let entry = chosen.first, !entry.isDirectory {
                menu.addItem(.separator())
                add(text.versions, "square.stack.3d.up", #selector(versionsOfItem(_:)))
            }
            menu.addItem(.separator())
            add(text.copyPath, "doc.on.doc", #selector(copyPaths(_:)))
            if !model.isOtherMac, chosen.count == 1, chosen[0].localStatus != .deletedSince {
                add(text.showOnMac, "magnifyingglass", #selector(showOnMac(_:)))
            }
        }

        private func items(_ sender: NSMenuItem) -> [ForkMacBackupBrowseEntry] {
            sender.representedObject as? [ForkMacBackupBrowseEntry] ?? []
        }

        @objc private func openItem(_ sender: NSMenuItem) {
            if let entry = items(sender).first { model.openFolder(entry) }
        }

        @objc private func quickLookItem(_ sender: NSMenuItem) {
            if let entry = items(sender).first {
                model.selection = [entry.id]
                model.previewFile(entry)
            }
        }

        @objc private func restoreItems(_ sender: NSMenuItem) { model.beginRestore(items(sender)) }

        @objc private func restoreItemsHere(_ sender: NSMenuItem) { model.beginRestore(items(sender), original: true) }

        @objc private func versionsOfItem(_ sender: NSMenuItem) {
            if let entry = items(sender).first { model.showVersions(entry) }
        }

        @objc private func copyPaths(_ sender: NSMenuItem) {
            guard let key = model.selectedKey else { return }
            let paths = items(sender).map { ForkMacBackupFolderPath.absolute($0.relativePath, in: key.path) }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
            model.show(text.copied)
        }

        @objc private func showOnMac(_ sender: NSMenuItem) {
            guard let key = model.selectedKey, let entry = items(sender).first else { return }
            let url = URL(fileURLWithPath: ForkMacBackupFolderPath.absolute(entry.relativePath, in: key.path))
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }

        // MARK: Dragging out

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard rows.indices.contains(row) else { return nil }
            let entry = rows[row]
            let type = entry.isDirectory ? UTType.folder
                : (UTType(filenameExtension: (entry.name as NSString).pathExtension) ?? .data)
            let provider = NSFilePromiseProvider(fileType: type.identifier, delegate: self)
            provider.userInfo = entry.id
            return provider
        }

        private func entry(for provider: NSFilePromiseProvider) -> ForkMacBackupBrowseEntry? {
            guard let id = provider.userInfo as? String else { return nil }
            return unsorted.first { $0.id == id }
        }

        func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
            entry(for: filePromiseProvider)?.name ?? "Restored"
        }

        func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL,
                                 completionHandler: @escaping (Error?) -> Void) {
            guard let entry = entry(for: filePromiseProvider) else {
                completionHandler(ForkMacBackupEngineError.other("unknown item"))
                return
            }
            // Called on `promiseQueue`: the restore runs on the main queue and
            // this one waits for it, as the Finder expects.
            let done = DispatchSemaphore(value: 0)
            var failure: Error?
            DispatchQueue.main.async { [model] in
                model.fulfillPromise(entry, to: url) { error in
                    failure = error
                    done.signal()
                }
            }
            done.wait()
            completionHandler(failure)
        }

        func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue { promiseQueue }

        // MARK: Icons

        static func icon(for entry: ForkMacBackupBrowseEntry) -> NSImage {
            let key = entry.isDirectory ? "/folder" : (entry.isSymlink ? "/link" : (entry.name as NSString).pathExtension.lowercased())
            if let cached = iconCache[key] { return cached }
            let image: NSImage
            if entry.isDirectory {
                image = NSWorkspace.shared.icon(for: .folder)
            } else if entry.isSymlink {
                image = NSWorkspace.shared.icon(for: .symbolicLink)
            } else {
                image = NSWorkspace.shared.icon(for: UTType(filenameExtension: key) ?? .data)
            }
            iconCache[key] = image
            return image
        }
    }

    /// One cell: an icon and a text, with a badge for unread files.
    final class FileCell: NSTableCellView {
        private let icon = NSImageView()
        private let label = NSTextField(labelWithString: "")
        private let badge = NSImageView()
        private var labelAfterIcon: NSLayoutConstraint!
        private var labelAtStart: NSLayoutConstraint!

        init(identifier: NSUserInterfaceItemIdentifier, column: Coordinator.Column) {
            super.init(frame: .zero)
            self.identifier = identifier
            label.lineBreakMode = .byTruncatingMiddle
            label.translatesAutoresizingMaskIntoConstraints = false
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.imageScaling = .scaleProportionallyUpOrDown
            badge.translatesAutoresizingMaskIntoConstraints = false
            badge.isHidden = true
            addSubview(icon)
            addSubview(label)
            addSubview(badge)
            imageView = icon
            textField = label
            let iconSize: CGFloat = column == .name ? 16 : 13
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                icon.centerYAnchor.constraint(equalTo: centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: iconSize),
                icon.heightAnchor.constraint(equalToConstant: iconSize),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
                badge.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 4),
                badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
                badge.centerYAnchor.constraint(equalTo: centerYAnchor),
                badge.widthAnchor.constraint(equalToConstant: 13),
                badge.heightAnchor.constraint(equalToConstant: 13),
            ])
            labelAfterIcon = label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5)
            labelAtStart = label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2)
            labelAfterIcon.isActive = true
            let trailing = label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4)
            trailing.priority = .defaultHigh
            trailing.isActive = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        func show(_ entry: ForkMacBackupBrowseEntry, column: Coordinator.Column, showsFolder: Bool,
                  text: ForkMacBackupWindowStrings, language: AppLanguage, locale: Locale, icon image: NSImage) {
            defer { placeLabel() }
            badge.isHidden = true
            label.alignment = .left
            label.textColor = .labelColor
            label.font = .systemFont(ofSize: NSFont.systemFontSize)
            icon.isHidden = false
            icon.contentTintColor = nil
            toolTip = nil
            setAccessibilityLabel(nil)
            switch column {
            case .name:
                icon.image = image
                if showsFolder, let parent = ForkMacBackupFolderPath.parent(of: entry.relativePath), !parent.isEmpty {
                    let value = NSMutableAttributedString(string: entry.name)
                    value.append(NSAttributedString(string: "  " + parent, attributes: [
                        .foregroundColor: NSColor.secondaryLabelColor,
                        .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                    ]))
                    label.attributedStringValue = value
                } else {
                    label.stringValue = entry.name
                }
                if entry.failedCount > 0 {
                    badge.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                          accessibilityDescription: nil)
                    badge.contentTintColor = .systemOrange
                    badge.isHidden = false
                    badge.toolTip = text.unread(Int(entry.failedCount), language)
                    badge.setAccessibilityLabel(badge.toolTip)
                }
            case .status:
                label.stringValue = entry.localStatus == .unknown || entry.localStatus == .present
                    ? "" : text.title(entry.localStatus)
                label.textColor = entry.localStatus == .identical ? .secondaryLabelColor : .labelColor
                if let symbol = ForkMacBackupWindowStyle.symbol(entry.localStatus) {
                    icon.image = NSImage(systemSymbolName: symbol.name, accessibilityDescription: text.title(entry.localStatus))
                    icon.contentTintColor = symbol.color
                } else {
                    icon.image = nil
                    icon.isHidden = true
                }
                setAccessibilityLabel(text.columnStatus + ": " + text.title(entry.localStatus))
            case .size:
                icon.image = nil
                icon.isHidden = true
                label.alignment = .right
                label.textColor = .secondaryLabelColor
                label.stringValue = entry.size.map { ForkMacBackupFormat.bytes($0, locale: locale) } ?? "—"
            case .modified:
                icon.image = nil
                icon.isHidden = true
                label.textColor = .secondaryLabelColor
                label.stringValue = entry.modified.map { ForkMacBackupFormat.dayAndTime($0, locale: locale) } ?? "—"
            }
        }

        /// The text starts where the icon would be when there is none.
        private func placeLabel() {
            labelAfterIcon.isActive = !icon.isHidden
            labelAtStart.isActive = icon.isHidden
        }
    }
}
