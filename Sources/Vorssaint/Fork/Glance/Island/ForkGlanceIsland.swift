// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

// Wave 2 stand-in, written by the orchestrator: the service (B1) shows the
// notices and opens the section through these signatures while B4 writes
// them. B4 owns this file and keeps them.

/// Glance Focus in the Dynamic Island: notices, the mascot, opening the
/// section. `start()` sets the island's injected hooks at launch (they answer
/// « unavailable » while the feature is off), like `ForkMacBackupIsland`.
enum ForkGlanceIsland {
    static func start() {}
    /// The switch moved: the section, the tile and the activity follow.
    static func sync() {}
    /// Shows `notice` if its switch (`fork.glance.notice.<kind>`) is on.
    static func show(_ notice: ForkGlanceNotice) {}
    /// Opens the island on the « Regard » section.
    static func openSection() {}
}
