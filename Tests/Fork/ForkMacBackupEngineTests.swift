// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Suite `fork-macbackup-engine`: owned by WP Engine, which tests its
/// `MacBackup/Engine/Pure/` files here (only pure files are compiled by fork/test.sh).
enum ForkMacBackupEngineTests {
    static func run(_ suite: TestSuite) {
        suite.expect(true, "WP Engine has no test yet")
    }
}
