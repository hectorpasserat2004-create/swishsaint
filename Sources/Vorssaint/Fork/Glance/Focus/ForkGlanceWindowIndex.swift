// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The windows of each zone, most recently used first (plan §6.1).
enum ForkGlanceWindowIndex {
    /// At launch: tells the official MRU tracker when Glance needs it (seam `glance-mru`).
    static func start() {}
}
