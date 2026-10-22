// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

extension ForkMacBackupAgent {
    /// Registers `ForkDefaults`, takes the lock, starts the planner and the
    /// Kopia server, then `dispatchMain()`. Stub: exits at once.
    static func runAndExit() -> Never {
        exit(0)
    }
}
