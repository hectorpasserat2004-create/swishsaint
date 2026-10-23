// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// What one frame of the closed island's backup draws, held by
/// `NotchStripHold` while the activity leaves.
struct ForkMacBackupIslandSnapshot: Equatable {
    let state: ForkMacBackupPresentation
    /// The run just ended: the ring fills.
    let finishing: Bool
    /// The filled ring has turned into the checkmark.
    let checked: Bool

    init(state: ForkMacBackupPresentation, finishing: Bool, checked: Bool? = nil) {
        self.state = state
        self.finishing = finishing
        self.checked = finishing && (checked ?? true)
    }

    var glyph: ForkMacBackupIslandRules.Glyph {
        ForkMacBackupIslandRules.glyph(phase: state.phase, finishing: checked)
    }

    var progress: Double? { ForkMacBackupIslandRules.ringProgress(state, finishing: finishing) }
}
