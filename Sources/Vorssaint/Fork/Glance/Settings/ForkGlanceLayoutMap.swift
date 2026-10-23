// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import SwiftUI

// Wave 2 stand-in, written by the orchestrator: the island section (B4)
// and the assistant (B2) draw the map through this signature while B3
// writes it. B3 owns this file and keeps the initializer.

/// The displays at the scale of their millimeters, laid out like macOS has
/// them, with their zones (plan §12.4); the zone editor when `onSplit` is set.
struct ForkGlanceLayoutMap: View {
    enum Style: Sendable, Equatable {
        /// White on the island's black (`NotchControlSurface` zones).
        case island
        /// The Settings window's colors.
        case settings
    }

    let layout: ForkGlanceDisplayLayout
    let zones: [ForkGlanceZone]
    var activeZone: String?
    var candidate: ForkGlanceCandidate?
    /// The live gaze point, global points; nil hides the dot.
    var gazePoint: CGPoint?
    var style: Style = .settings
    /// Set: a click on a display opens its split menu (Entier, 2 colonnes…).
    var splits: [String: ForkGlanceSplit] = [:]
    var onSplit: ((String, ForkGlanceSplit) -> Void)?

    var body: some View { Color.clear }
}
