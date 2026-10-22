// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Suite `fork-macbackup-settings`: owned by WP Settings, which tests its
/// `MacBackup/Settings/Pure/` files here (only pure files are compiled by fork/test.sh).
enum ForkMacBackupSettingsTests {
    static func run(_ suite: TestSuite) {
        suite.expect(true, "WP Settings has no test yet")
    }
}
