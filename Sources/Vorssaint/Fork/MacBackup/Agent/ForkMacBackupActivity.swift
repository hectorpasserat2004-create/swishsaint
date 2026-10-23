// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Combine
import Foundation

/// Whether a backup is running, for the fork's updater (plan §3.3, §3.11):
/// installing quits the app, so it waits for the backup to end, at most 30
/// minutes; past that, the backup is stopped cleanly (cancel = Kopia keeps a
/// checkpoint, the next run resumes) and the update goes ahead, even when
/// the state still says busy 3 min later. A restore (it runs in the app),
/// and a verification the app's own runner does, count as busy too. Main
/// thread.
///
/// The truth comes from the state the runner publishes
/// (`ForkMacBackupStatusModel`), whoever runs it (the agent or the app).
enum ForkMacBackupActivity {
    /// A backup is between its start and its conclusion.
    static var isBusy: Bool {
        let model = ForkMacBackupStatusModel.shared
        guard model.isEnabled else { return false }
        let phase = model.presentation.phase
        // A restore runs in this app: quitting would leave it half done.
        if phase == .restoring { return true }
        guard model.agentAlive else { return false }
        if phase.isBackingUp { return true }
        // A verification by the app's own runner stops with the app.
        return phase == .verifying && ForkMacBackupAgentLink.shared.mode == .appWhileOpen
    }

    /// The wait gave up (the stop was not confirmed in time): the install
    /// that follows goes ahead whatever the state says, instead of waiting
    /// another 30 minutes, again and again.
    private static var forcedAt: Date?
    private static let forcedValidity: TimeInterval = 10 * 60

    private static var waitStartedAt: Date?
    private static var stopSentAt: Date?
    private static var waiters: [() -> Void] = []
    private static var subscription: AnyCancellable?
    private static var timer: Timer?

    /// Asked by the updater before it replaces the app. true: go ahead (a
    /// hold is written, so no backup starts in the meantime). false: wait;
    /// `ready` runs on the main thread once the backup ended, or once it was
    /// stopped after `updateWaitLimit`.
    static func clearForUpdate(ready: @escaping () -> Void) -> Bool {
        writeHold()
        if let forcedAt, Date().timeIntervalSince(forcedAt) < forcedValidity {
            reset()
            return true
        }
        guard isBusy else {
            reset()
            return true
        }
        waiters.append(ready)
        if waitStartedAt == nil {
            waitStartedAt = Date()
            subscription = ForkMacBackupStatusModel.shared.$presentation
                .receive(on: DispatchQueue.main)
                .sink { _ in DispatchQueue.main.async { check() } }
            let timer = Timer(timeInterval: 15, repeats: true) { _ in check() }
            timer.tolerance = 5
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        return false
    }

    private static func check() {
        guard let started = waitStartedAt else { return }
        let now = Date()
        if !isBusy {
            finish()
            return
        }
        writeHold()
        if stopSentAt == nil, now.timeIntervalSince(started) >= ForkMacBackupAgentTuning.updateWaitLimit {
            // The runner reads the hold and records the stop as « app update ».
            stopSentAt = now
            ForkMacBackupStatusModel.shared.send(.cancel, origin: .settings)
        } else if let sent = stopSentAt, now.timeIntervalSince(sent) >= ForkMacBackupAgentTuning.cancelGrace {
            // Kopia did not confirm in time: the update goes ahead anyway.
            forcedAt = now
            finish()
        }
    }

    private static func finish() {
        let ready = waiters
        reset()
        ready.forEach { $0() }
    }

    private static func reset() {
        waiters = []
        waitStartedAt = nil
        stopSentAt = nil
        subscription = nil
        timer?.invalidate()
        timer = nil
    }

    /// The update did not happen (download failed…): backups may start again.
    static func updateAbandoned() {
        reset()
        forcedAt = nil
        guard let paths = ForkMacBackupStatusModel.shared.paths else { return }
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.removeItem(at: ForkMacBackupAgentIPCSupport.updateHoldURL(paths))
        }
    }

    /// `run/update.hold`: fresh for 20 min, removed at the next launch.
    private static func writeHold() {
        guard ForkMacBackupStatusModel.shared.isEnabled, let paths = ForkMacBackupStatusModel.shared.paths else { return }
        DispatchQueue.global(qos: .utility).async {
            guard PrivateFileStore.createDirectory(at: paths.run, container: PrivateFileStore.containerURL) else { return }
            PrivateFileStore.write(Data(), to: ForkMacBackupAgentIPCSupport.updateHoldURL(paths))
        }
    }
}
