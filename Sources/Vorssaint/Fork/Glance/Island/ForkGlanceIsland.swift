// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Glance Focus in the Dynamic Island: notices, the mascot, opening the
/// section. `start()` sets the island's injected hooks at launch (they answer
/// « unavailable » while the feature is off), like `ForkMacBackupIsland`.
enum ForkGlanceIsland {
    static func start() {}
}
