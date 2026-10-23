// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit

// Wave 2 stand-in, written by the orchestrator: the service (B1), the
// settings (B3) and the island (B4) open the assistant through these
// signatures while B2 writes it. B2 owns this file and keeps them.

/// The calibration assistant's window (plan §8.4), like `ForkMacBackupWizard`.
enum ForkGlanceCalibrationWindow {
    /// Opens it on `entry`, or brings it forward. Main thread.
    static func show(_ entry: ForkGlanceCalibrationEntry) {}
    static var isOpen: Bool { false }
    /// Closes it as « Annuler » would (the feature switched off, the app quits).
    static func close() {}
}
