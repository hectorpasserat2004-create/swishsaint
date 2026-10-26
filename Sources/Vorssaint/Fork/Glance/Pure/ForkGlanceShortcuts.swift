// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

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

/// Load, save and check, in the format of `ForkMeetingShortcut`
/// (`GlobalShortcut.storageValue`, `"control+option+command:5"`): the same
/// stored text, the same refusals (Escape, a typing key alone, a letter
/// without a modifier).
///
/// Who wins a combination two features want: macOS and the apps first, then
/// the official features, Dictation, Meetings, and Glance last. A combination
/// Dictation or Meetings holds is never Glance's, so the shortcut a person
/// already uses keeps working when Glance arrives with its default; and a
/// combination Glance holds is refused by their recorders
/// (`ForkDictationShortcuts.isTakenElsewhere` asks `usedByGlance`, and the
/// Meetings' check goes through Dictation's). Two features never refuse each
/// other's combination for good.
enum ForkGlanceShortcuts {
    /// ⌃⌥⌘G, the pause's default (decision D6): no official shortcut uses it
    /// (their defaults are tested) and macOS lists none on G. Stored as
    /// `"control+option+command:5"` (5 is `kVK_ANSI_G`).
    static let pauseDefault = GlobalShortcut(keyCode: 5, modifiers: [.control, .option, .command])

    static func load(_ defaults: UserDefaults = .standard, role: ForkGlanceShortcutRole) -> GlobalShortcut? {
        ForkMeetingShortcut.decode(defaults.string(forKey: role.key) ?? "")
    }

    static func save(_ shortcut: GlobalShortcut?, _ defaults: UserDefaults = .standard, role: ForkGlanceShortcutRole) {
        defaults.set(ForkMeetingShortcut.encode(shortcut), forKey: role.key)
    }

    /// What keeps a combination from being `role`'s: macOS, the apps, an
    /// official feature, Dictation, Meetings, or another Glance shortcut.
    static func problem(of shortcut: GlobalShortcut, role: ForkGlanceShortcutRole,
                        defaults: UserDefaults = .standard) -> ForkMeetingShortcutProblem? {
        problem(of: shortcut, role: role, defaults: defaults, isTakenBySystem: ForkGlanceShortcuts.isTakenBySystem)
    }

    /// The same, with macOS's and the official features' answer injected (tests).
    static func problem(of shortcut: GlobalShortcut, role: ForkGlanceShortcutRole, defaults: UserDefaults,
                        isTakenBySystem: (GlobalShortcut) -> Bool) -> ForkMeetingShortcutProblem? {
        ForkMeetingShortcut.problem(of: shortcut) { candidate in
            isTakenBySystem(candidate) || heldByDictationOrMeetings(candidate, defaults: defaults)
                || usedByGlance(candidate, besides: role, defaults: defaults, isTakenBySystem: isTakenBySystem)
        }
    }

    /// macOS, the apps' menus (⌘ and a typing key) or an official feature.
    static func isTakenBySystem(_ shortcut: GlobalShortcut) -> Bool {
        ForkDictationShortcuts.isAppMenuShortcut(shortcut)
            || shortcut.conflictsWithSystemShortcut(for: nil)
            || GlobalShortcutRole.conflict(for: shortcut, excluding: nil) != nil
    }

    /// One of Dictation's combinations (while it is on), or one of the
    /// Meetings' (while they are on).
    static func heldByDictationOrMeetings(_ shortcut: GlobalShortcut, defaults: UserDefaults = .standard) -> Bool {
        if ForkMeetingShortcut.usedByDictation(shortcut, enabled: defaults.bool(forKey: ForkDefaultsKey.dictationEnabled),
                                               shortcuts: ForkDictationShortcuts.load(defaults)) {
            return true
        }
        guard defaults.bool(forKey: ForkDefaultsKey.meetingsEnabled) else { return false }
        return ForkMeetingShortcutRole.allCases.contains { ForkMeetingShortcut.load(defaults, role: $0) == shortcut }
    }

    /// Glance holds this combination: the feature is on, and one of its
    /// shortcuts other than `role`'s is this one and nothing before Glance
    /// holds it (see the type's comment).
    static func usedByGlance(_ shortcut: GlobalShortcut, besides role: ForkGlanceShortcutRole? = nil,
                             defaults: UserDefaults = .standard,
                             isTakenBySystem: (GlobalShortcut) -> Bool = ForkGlanceShortcuts.isTakenBySystem) -> Bool {
        guard defaults.bool(forKey: ForkDefaultsKey.glanceEnabled),
              ForkGlanceShortcutRole.allCases.contains(where: { $0 != role && load(defaults, role: $0) == shortcut })
        else { return false }
        return !isTakenBySystem(shortcut) && !heldByDictationOrMeetings(shortcut, defaults: defaults)
    }

    /// The combination to install for `role`, nil when none is set or it
    /// has a problem: what is taken changes with macOS and the other
    /// features, so it is asked again at each install.
    static func usable(_ role: ForkGlanceShortcutRole, defaults: UserDefaults = .standard) -> GlobalShortcut? {
        guard let shortcut = load(defaults, role: role),
              problem(of: shortcut, role: role, defaults: defaults) == nil else { return nil }
        return shortcut
    }
}
