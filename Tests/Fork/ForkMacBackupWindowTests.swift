// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Suite `fork-macbackup-window`: owned by WP Window, which tests its
/// `MacBackup/Window/Pure/` files here (only pure files are compiled by fork/test.sh).
enum ForkMacBackupWindowTests {
    static func run(_ suite: TestSuite) {
        suite.expect(true, "WP Window has no test yet")
    }
}
