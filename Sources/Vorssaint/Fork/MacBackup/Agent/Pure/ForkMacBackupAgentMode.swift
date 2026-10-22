// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The headless mode of the same binary (`--fork-backup-agent`), launched by
/// launchd. The seam `macbackup-agent` in `main.swift` calls
/// `if ForkMacBackupAgent.isRequested(CommandLine.arguments) { ForkMacBackupAgent.runAndExit() }`
/// after the `--uninstall` block; `runAndExit` is in `Agent/ForkMacBackupAgent.swift`.
enum ForkMacBackupAgent {
    static let argument = "--fork-backup-agent"

    /// Anywhere in the arguments, `argv[0]` included: launchd hands
    /// `ProgramArguments` on as they are, so the flag must be found even if
    /// a hand-written plist forgot the program's own name in front of it.
    /// An exact match only: `--fork-backup-agent=x` is not the flag.
    static func isRequested(_ arguments: [String]) -> Bool {
        arguments.contains(argument)
    }
}
