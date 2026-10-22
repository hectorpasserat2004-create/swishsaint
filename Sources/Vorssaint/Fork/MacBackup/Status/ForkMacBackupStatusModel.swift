// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Combine
import Foundation
import notify

/// The app's view of the backup: what every view observes. The agent owns
/// the truth and writes `state.json`; this model reads it when the agent
/// posts `ForkMacBackupNotify.state`, and sends the person's orders as
/// command files. Main thread only; the disk is read and written on a
/// utility queue, never in a view.
///
/// Also the one place that tells the agent the settings changed: any
/// `fork.macbackup.*` change posts `ForkMacBackupNotify.settings`, so no
/// page has to remember to.
final class ForkMacBackupStatusModel: ObservableObject {
    static let shared = ForkMacBackupStatusModel(paths: ForkMacBackupPaths(container: PrivateFileStore.containerURL),
                                                 notify: .current)

    @Published private(set) var presentation: ForkMacBackupPresentation
    /// The last state file came from an agent still running.
    @Published private(set) var agentAlive = false
    @Published private(set) var stateWrittenAt: Date?
    /// The agent's build, as it wrote it.
    @Published private(set) var agentBuild: String?

    let paths: ForkMacBackupPaths?
    let notify: ForkMacBackupNotify
    private let defaults: UserDefaults
    private let isPreview: Bool
    private let queue = DispatchQueue(label: "fork.macbackup.status", qos: .utility)
    private var stateToken: Int32?
    private var defaultsObserver: NSObjectProtocol?
    private var settingsFingerprint: [String: String] = [:]
    private var settingsPost: DispatchWorkItem?
    private var liveViewers = 0
    private var leaseTimer: Timer?
    private var started = false

    /// How often the live-progress lease is renewed while a view shows it.
    static let leaseInterval: TimeInterval = 5

    init(paths: ForkMacBackupPaths?, notify: ForkMacBackupNotify, defaults: UserDefaults = .standard) {
        self.paths = paths
        self.notify = notify
        self.defaults = defaults
        isPreview = false
        presentation = .unknown
    }

    /// A model that shows `scenario` and never touches the disk (previews,
    /// the island's settings preview, offscreen renders).
    init(preview scenario: ForkMacBackupPresentation.Scenario, now: Date = Date()) {
        paths = nil
        notify = ForkMacBackupNotify(bundleID: "preview")
        defaults = .standard
        isPreview = true
        presentation = .preview(scenario, now: now)
        agentAlive = true
        stateWrittenAt = now
    }

    var isEnabled: Bool { defaults.bool(forKey: ForkDefaultsKey.macBackupEnabled) }

    // MARK: Switch

    /// Follows the feature's switch: on, listens to the agent; off, stops
    /// listening and shows `.off`.
    func sync() {
        guard !isPreview else { return }
        if isEnabled {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard !started else {
            reload()
            return
        }
        started = true
        var token: Int32 = 0
        let status = notify_register_dispatch(notify.state, &token, DispatchQueue.main) { [weak self] _ in
            self?.reload()
        }
        if status == UInt32(NOTIFY_STATUS_OK) { stateToken = token }
        settingsFingerprint = currentSettingsFingerprint()
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                                  object: nil, queue: .main) { [weak self] _ in
            self?.defaultsDidChange()
        }
        reload()
    }

    private func stop() {
        let wasStarted = started
        if let stateToken { notify_cancel(stateToken) }
        stateToken = nil
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
        defaultsObserver = nil
        settingsPost?.cancel()
        settingsPost = nil
        leaseTimer?.invalidate()
        leaseTimer = nil
        liveViewers = 0
        started = false
        agentAlive = false
        if presentation.phase != .off { presentation = ForkMacBackupPresentation(phase: .off, updatedAt: Date()) }
        // The switch itself is a setting the agent follows.
        if wasStarted { notify_post(notify.settings) }
    }

    // MARK: State

    /// Reads `state.json` off the main thread and publishes it.
    func reload() {
        guard !isPreview, started, let url = paths?.state else { return }
        queue.async { [weak self] in
            let file = (try? Data(contentsOf: url)).flatMap(ForkMacBackupStateFile.decode)
            let alive = file?.agentPID.map { $0 > 0 && kill($0, 0) == 0 } ?? false
            DispatchQueue.main.async {
                guard let self, self.started else { return }
                if let file {
                    if self.presentation != file.presentation { self.presentation = file.presentation }
                    self.stateWrittenAt = file.writtenAt
                    self.agentBuild = file.agentBuild
                }
                if self.agentAlive != alive { self.agentAlive = alive }
            }
        }
    }

    // MARK: Commands

    /// Writes `command` for the agent and wakes it. `completion` (main
    /// thread) says whether the file was written; the agent's answer is the
    /// next state.
    func send(_ command: ForkMacBackupCommand, origin: ForkMacBackupTrigger,
              completion: ((Bool) -> Void)? = nil) {
        guard !isPreview, isEnabled, let paths else {
            completion?(false)
            return
        }
        let file = ForkMacBackupCommandFile(command: command, origin: origin)
        let name = notify.command
        queue.async {
            let container = PrivateFileStore.containerURL
            let written = PrivateFileStore.createDirectory(at: paths.commands, container: container)
                && file.encoded().map { PrivateFileStore.write($0, to: paths.commandFile(file)) } == true
            if written { notify_post(name) }
            DispatchQueue.main.async { completion?(written) }
        }
    }

    // MARK: Live progress

    /// A view that shows the live progress calls this on appear, and
    /// `endLiveViewing` on disappear: while one does, the agent publishes
    /// every second instead of every ten.
    func beginLiveViewing() {
        guard !isPreview, started else { return }
        liveViewers += 1
        guard liveViewers == 1 else { return }
        touchLease()
        let timer = Timer(timeInterval: Self.leaseInterval, repeats: true) { [weak self] _ in self?.touchLease() }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        leaseTimer = timer
    }

    func endLiveViewing() {
        guard !isPreview, liveViewers > 0 else { return }
        liveViewers -= 1
        guard liveViewers == 0 else { return }
        leaseTimer?.invalidate()
        leaseTimer = nil
        if let url = paths?.viewerLease {
            queue.async { try? FileManager.default.removeItem(at: url) }
        }
    }

    private func touchLease() {
        guard let paths else { return }
        queue.async {
            guard PrivateFileStore.createDirectory(at: paths.run, container: PrivateFileStore.containerURL) else { return }
            PrivateFileStore.write(Data(), to: paths.viewerLease)
        }
    }

    // MARK: Settings → agent

    private func defaultsDidChange() {
        let current = currentSettingsFingerprint()
        guard current != settingsFingerprint else { return }
        settingsFingerprint = current
        settingsPost?.cancel()
        let name = notify.settings
        let post = DispatchWorkItem { notify_post(name) }
        settingsPost = post
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: post)
    }

    /// Every `fork.macbackup.*` value the agent reads, as text.
    private func currentSettingsFingerprint() -> [String: String] {
        var values: [String: String] = [:]
        for key in Array(ForkMacBackupDefaults.registered.keys) + ForkMacBackupDefaults.machineKeys {
            if let value = defaults.object(forKey: key) { values[key] = String(describing: value) }
        }
        return values
    }
}
