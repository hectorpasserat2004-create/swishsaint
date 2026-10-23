// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

extension ForkMacBackupAgent {
    /// The runner of this process, kept for its whole life.
    private static var runner: ForkMacBackupRunner?

    /// Launched by launchd: registers `ForkDefaults`, takes the single
    /// instance lock, starts the runner (planner, conditions, Kopia server),
    /// then `dispatchMain()`. No NSApplication is ever created.
    ///
    /// Exit codes follow the plist's `KeepAlive.SuccessfulExit = false`:
    /// 0 when there is nothing to do for good (switched off, another agent
    /// runs), non-zero to be launched again (75: a new build is installed,
    /// or the app's runner did not hand the lock over in time).
    static func runAndExit() -> Never {
        ForkDefaults.register()
        guard UserDefaults.standard.bool(forKey: ForkDefaultsKey.macBackupEnabled),
              let bundleID = Bundle.main.bundleIdentifier,
              let paths = ForkMacBackupPaths(container: PrivateFileStore.containerURL) else { exit(0) }
        let runner = ForkMacBackupRunner(host: .agent, paths: paths, bundleID: bundleID)
        runner.onExitRequest = { code in exit(code) }
        Self.runner = runner
        start(runner, deadline: Date().addingTimeInterval(60))
        dispatchMain()
    }

    /// The app's runner holds the lock while the agent was not allowed: it
    /// hands over when asked. Another agent: this one leaves.
    private static func start(_ runner: ForkMacBackupRunner, deadline: Date) {
        switch runner.start() {
        case .started:
            return
        case .held(role: .app?, _):
            guard Date() < deadline else { exit(75) }
            runner.postHandover()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { start(runner, deadline: deadline) }
        case .held:
            exit(0)
        case .failed:
            exit(0)
        }
    }
}
