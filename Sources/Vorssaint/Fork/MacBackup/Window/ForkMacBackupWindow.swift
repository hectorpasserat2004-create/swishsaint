// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import Carbon.HIToolbox
import Combine
import Quartz
import SwiftUI

/// The « Sauvegardes » window (browse, timeline, restore, history, health,
/// verifications). One window only: asked again, it comes back to the front
/// on the tab asked for. While it is open the app has a Dock icon and a
/// place in ⌘Tab, like the Meetings window. Main thread only.
enum ForkMacBackupWindow {
    /// Shows the window on `tab`, creating it if needed. Nothing while the
    /// feature is off.
    static func open(_ tab: ForkMacBackupWindowTab = .browse) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { open(tab) }
            return
        }
        guard ForkMacBackupApp.isEnabled else { return }
        ForkMacBackupWindowController.shared.show(tab)
    }

    #if VORSSAINT_DEVELOPMENT
    /// The window on the fake engine and records (Developer build only).
    static func openDemo(_ tab: ForkMacBackupWindowTab = .browse) {
        ForkMacBackupWindowController.shared.show(tab, model: ForkMacBackupWindowController.demoModel())
    }
    #endif
}

final class ForkMacBackupWindowController: NSWindowController, NSWindowDelegate {
    static let shared = ForkMacBackupWindowController()

    static let defaultSize = NSSize(width: 1_120, height: 720)
    static let minimumSize = NSSize(width: 860, height: 520)
    static let autosaveName = "fork.macbackup.window"

    private(set) var model: ForkMacBackupWindowModel?
    private var keyMonitor: Any?
    private var keepsAppRegular = false
    private var featureObserver: AnyCancellable?

    private init() {
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    static func makeModel() -> ForkMacBackupWindowModel {
        let status = ForkMacBackupStatusModel.shared
        let paths = status.paths ?? ForkMacBackupPaths(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("MacBackup", isDirectory: true))
        return ForkMacBackupWindowModel(status: status, ledgerReader: ForkMacBackupWindowDiskLedger(paths: paths),
                                        previewFolder: paths.preview) {
            ForkMacBackupEngineFactory.makeClient(paths: paths)
        }
    }

    #if VORSSAINT_DEVELOPMENT
    static func demoModel(now: Date = Date(), language: AppLanguage? = nil) -> ForkMacBackupWindowModel {
        let engine = ForkMacBackupDemoEngine(now: now, home: NSHomeDirectory())
        let calendar = Calendar.autoupdatingCurrent
        return ForkMacBackupWindowModel(status: ForkMacBackupStatusModel(preview: .protected, now: now),
                                        ledgerReader: ForkMacBackupDemoLedger(engine.ledger(calendar: calendar)),
                                        previewFolder: FileManager.default.temporaryDirectory
                                            .appendingPathComponent("fork-macbackup-demo-preview", isDirectory: true),
                                        language: language, now: { now }, calendar: calendar,
                                        localFacts: engine.localFacts, makeEngine: { engine })
    }
    #endif

    /// Opens or brings forward the window, on `tab`.
    func show(_ tab: ForkMacBackupWindowTab, model given: ForkMacBackupWindowModel? = nil) {
        if let given, given !== model {
            window?.close()
            window = nil
            model = given
        }
        let model = self.model ?? Self.makeModel()
        self.model = model
        let window = ensureWindow(model: model)
        window.title = model.text.windowTitle
        model.open(tab)
        installKeyMonitor()
        watchFeature()
        if !keepsAppRegular {
            keepsAppRegular = true
            WindowActivationPolicy.retain()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func ensureWindow(model: ForkMacBackupWindowModel) -> NSWindow {
        if let window { return window }
        let window = Self.makeWindow(model: model)
        window.setFrameAutosaveName(Self.autosaveName)
        if window.frame.origin == .zero { window.center() }
        window.delegate = self
        self.window = window
        return window
    }

    /// The window itself, also built by the offscreen renders.
    static func makeWindow(model: ForkMacBackupWindowModel, styleMask: NSWindow.StyleMask? = nil) -> NSWindow {
        let host = NSHostingController(rootView: ForkMacBackupWindowView(model: model))
        host.sizingOptions = []
        let window = NSWindow(contentViewController: host)
        window.styleMask = styleMask ?? [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.setContentSize(defaultSize)
        window.contentMinSize = minimumSize
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.hidesOnDeactivate = false
        window.tabbingMode = .disallowed
        window.toolbarStyle = .unified
        window.titleVisibility = .visible
        return window
    }

    /// Off: the window goes, with what it started.
    private func watchFeature() {
        guard featureObserver == nil else { return }
        featureObserver = ForkMacBackupStatusModel.shared.$presentation
            .map { $0.phase == .off }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] off in
                guard off, let self, self.model?.status === ForkMacBackupStatusModel.shared else { return }
                self.window?.close()
            }
    }

    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
        model?.close()
        removeKeyMonitor()
        featureObserver = nil
        if keepsAppRegular {
            keepsAppRegular = false
            WindowActivationPolicy.release()
        }
    }

    // MARK: Quick Look

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        model?.quickLook.begin(panel)
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        model?.quickLook.end(panel)
    }

    // MARK: Keys

    /// ⌘F finds, Esc leaves the search, ← → step between backups, ⌘↑ goes
    /// up a folder, ⌘↓ opens one, Space shows Quick Look. A text being
    /// typed keeps its keys.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window, window.attachedSheet == nil,
                  let model = self.model else { return event }
            return Self.handle(event, model: model, editing: window.firstResponder is NSText) ? nil : event
        }
    }

    /// Whether `event` was one of the window's keys (and was handled).
    static func handle(_ event: NSEvent, model: ForkMacBackupWindowModel, editing: Bool) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let browsing: Bool = {
            if case .source = model.sidebarSelection { return true }
            return false
        }()
        switch (Int(event.keyCode), modifiers) {
        case (kVK_ANSI_F, [.command]):
            if !browsing { model.select(.browse) }
            model.focusSearch()
            return true
        case (kVK_Escape, []):
            if model.quickLook.isVisible {
                model.quickLook.close()
                return true
            }
            guard !model.searchText.isEmpty else { return false }
            model.cancelSearch()
            return true
        case (kVK_UpArrow, [.command]) where browsing:
            model.goToParent()
            return true
        case (kVK_DownArrow, [.command]) where browsing && !editing:
            guard let entry = model.selectedEntries.first, entry.isDirectory else { return false }
            model.openFolder(entry)
            return true
        case (kVK_LeftArrow, []) where browsing && !editing:
            model.stepSnapshot(-1)
            return true
        case (kVK_RightArrow, []) where browsing && !editing:
            model.stepSnapshot(1)
            return true
        case (kVK_Space, []) where browsing && !editing:
            model.toggleQuickLook()
            return true
        case (kVK_ANSI_I, [.command, .option]) where browsing:
            model.inspectorShown.toggle()
            return true
        default:
            return false
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

/// Quick Look over a file restored apart (plan §6.2): the panel shows it,
/// the file goes when the panel or the window closes.
final class ForkMacBackupQuickLook: NSObject, ObservableObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    /// The name of the file being restored for the preview.
    @Published private(set) var preparing: String?
    private var url: URL?

    var isVisible: Bool { QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible }

    func prepare(title: String, text: ForkMacBackupWindowStrings) {
        preparing = title
    }

    func show(_ url: URL) {
        preparing = nil
        discard()
        self.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func close() {
        preparing = nil
        if isVisible { QLPreviewPanel.shared().orderOut(nil) }
        discard()
    }

    func begin(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
    }

    func end(_ panel: QLPreviewPanel) {
        panel.dataSource = nil
        panel.delegate = nil
        discard()
    }

    /// The restored copy goes with its folder.
    private func discard() {
        guard let url else { return }
        self.url = nil
        let folder = url.deletingLastPathComponent()
        DispatchQueue.global(qos: .utility).async { try? FileManager.default.removeItem(at: folder) }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        url.map { $0 as NSURL }
    }
}
