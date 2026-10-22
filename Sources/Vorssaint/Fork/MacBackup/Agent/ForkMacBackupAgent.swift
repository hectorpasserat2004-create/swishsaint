// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The headless mode of the same binary (`--fork-backup-agent`), launched by
/// launchd. WP Agent fills it and adds the `macbackup-agent` seam in
/// `main.swift` (after the `--uninstall` block):
/// `if ForkMacBackupAgent.isRequested(CommandLine.arguments) { ForkMacBackupAgent.runAndExit() }`.
enum ForkMacBackupAgent {
    static let argument = "--fork-backup-agent"

    static func isRequested(_ arguments: [String]) -> Bool {
        arguments.dropFirst().contains(argument)
    }

    /// Registers `ForkDefaults`, takes the lock, starts the planner and the
    /// Kopia server, then `dispatchMain()`. Stub: exits at once.
    static func runAndExit() -> Never {
        exit(0)
    }
}
