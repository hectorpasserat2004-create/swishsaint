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
    /// While the agent's state shows something running: read again after
    /// a while, so an agent that died mid-run is noticed without its
    /// notification.
    private var aliveCheck: DispatchWorkItem?
    private var started = false
    /// The agent's own state, as last read.
    private var agentPresentation: ForkMacBackupPresentation = .unknown
    /// A restore the window runs in this process (restores never go through
    /// the agent): its progress is laid over the agent's state while it
    /// runs, so the island shows « Restauration » like a backup.
    private var restore: (id: UUID, progress: ForkMacBackupRestoreProgress?)?

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
        if liveViewers > 0 { startLease() }
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
        aliveCheck?.cancel()
        aliveCheck = nil
        // The views showing the progress keep their count (they will end
        // it); only the lease stops.
        leaseTimer?.invalidate()
        leaseTimer = nil
        started = false
        agentAlive = false
        restore = nil
        agentPresentation = .unknown
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
                if self.agentAlive != alive { self.agentAlive = alive }
                if let file {
                    self.agentPresentation = file.presentation.settled(agentAlive: alive)
                    self.publishMerged()
                    self.stateWrittenAt = file.writtenAt
                    self.agentBuild = file.agentBuild
                }
                self.scheduleAliveCheck(running: file.map { $0.presentation.phase.showsInClosedIsland
                    || $0.presentation.phase == .maintaining } ?? false)
            }
        }
    }

    private func scheduleAliveCheck(running: Bool) {
        aliveCheck?.cancel()
        aliveCheck = nil
        guard running, started else { return }
        let check = DispatchWorkItem { [weak self] in self?.reload() }
        aliveCheck = check
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: check)
    }

    // MARK: Restores (in the app)

    /// The window started a restore; returns its token.
    @discardableResult
    func restoreStarted(_ progress: ForkMacBackupRestoreProgress? = nil) -> UUID {
        let id = UUID()
        guard !isPreview, started else { return id }
        restore = (id, progress)
        publishMerged()
        return id
    }

    func restoreProgressed(_ id: UUID, _ progress: ForkMacBackupRestoreProgress) {
        guard restore?.id == id else { return }
        restore?.progress = progress
        publishMerged()
    }

    /// The restore ended (the island's card is already up): the agent's
    /// state comes back, which ends the island's restore activity.
    func restoreEnded(_ id: UUID) {
        guard restore?.id == id else { return }
        restore = nil
        publishMerged()
    }

    /// The agent's state, with the app's restore over it unless the agent
    /// is busy itself (one activity in the closed island at a time).
    static func merged(_ agent: ForkMacBackupPresentation, restore: ForkMacBackupRestoreProgress??,
                       now: Date = Date()) -> ForkMacBackupPresentation {
        guard let restore, agent.phase != .off, !agent.phase.isBackingUp, agent.phase != .verifying else { return agent }
        var merged = agent
        merged.phase = .restoring
        merged.progress = restore.map {
            ForkMacBackupPresentation.Progress(bytesDone: $0.bytesDone, bytesTotal: $0.bytesTotal, files: $0.files,
                                               filesTotal: $0.filesTotal, errors: $0.errors)
        } ?? ForkMacBackupPresentation.Progress()
        merged.updatedAt = now
        return merged
    }

    private func publishMerged() {
        let value = Self.merged(agentPresentation, restore: restore.map { $0.progress })
        if presentation != value { presentation = value }
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
    /// Counted even while the model is stopped, so every view's end matches
    /// its own begin (a begin skipped then an end counted would stop another
    /// view's lease).
    func beginLiveViewing() {
        guard !isPreview else { return }
        liveViewers += 1
        if liveViewers == 1, started { startLease() }
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

    private func startLease() {
        guard leaseTimer == nil else { return }
        touchLease()
        let timer = Timer(timeInterval: Self.leaseInterval, repeats: true) { [weak self] _ in self?.touchLease() }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        leaseTimer = timer
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
