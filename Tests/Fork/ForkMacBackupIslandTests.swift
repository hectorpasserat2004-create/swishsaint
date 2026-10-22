// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Suite `fork-macbackup-island`: owned by WP Island, which tests its
/// `MacBackup/Island/Pure/` files here (only pure files are compiled by fork/test.sh).
enum ForkMacBackupIslandTests {
    static func run(_ suite: TestSuite) {
        suite.expect(true, "WP Island has no test yet")
    }
}
