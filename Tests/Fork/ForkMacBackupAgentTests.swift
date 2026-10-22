// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Suite `fork-macbackup-agent`: owned by WP Agent, which tests its
/// `MacBackup/Agent/Pure/` files here (only pure files are compiled by fork/test.sh).
enum ForkMacBackupAgentTests {
    static func run(_ suite: TestSuite) {
        suite.expect(true, "WP Agent has no test yet")
    }
}
