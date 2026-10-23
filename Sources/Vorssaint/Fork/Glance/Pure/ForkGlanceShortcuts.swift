// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

// Wave 2 stand-in, written by the orchestrator: the settings (B3) record
// and check the shortcuts through these signatures while B1 writes them.
// B1 owns this file and keeps them.

/// Glance Focus's three global shortcuts (plan §12.8).
enum ForkGlanceShortcutRole: String, CaseIterable, Sendable {
    case pause
    case recenter
    case mode

    var key: String {
        switch self {
        case .pause: return ForkDefaultsKey.glanceHotKeyPause
        case .recenter: return ForkDefaultsKey.glanceHotKeyRecenter
        case .mode: return ForkDefaultsKey.glanceHotKeyMode
        }
    }
}

/// Load, save and check, in the format of `ForkMeetingShortcut` (pure).
enum ForkGlanceShortcuts {
    static func load(_ defaults: UserDefaults = .standard, role: ForkGlanceShortcutRole) -> GlobalShortcut? { nil }
    static func save(_ shortcut: GlobalShortcut?, _ defaults: UserDefaults = .standard, role: ForkGlanceShortcutRole) {}
    /// What keeps a combination from being `role`'s: macOS, the apps, an
    /// official feature, Dictation, Meetings, or another Glance shortcut.
    static func problem(of shortcut: GlobalShortcut, role: ForkGlanceShortcutRole,
                        defaults: UserDefaults = .standard) -> ForkMeetingShortcutProblem? { nil }
}
