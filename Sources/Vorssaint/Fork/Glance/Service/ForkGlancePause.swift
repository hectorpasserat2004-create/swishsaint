// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// A person's pause on disk (`fork.glance.pausedUntil`, machine state: never
/// in the settings backup), so « En pause · 1 h » survives a relaunch and a
/// night's sleep. The machine itself counts in `systemUptime`, which stands
/// still while the Mac sleeps: the service converts the stored wall-clock end
/// at launch and at each wake (`ForkGlancePauseRules`). Main thread.
enum ForkGlancePause {
    /// What is stored, an end already passed read as none.
    static func stored(_ defaults: UserDefaults = .standard, now: Date = Date()) -> ForkGlancePauseRules.Stored {
        ForkGlancePauseRules.restored(
            ForkGlancePauseRules.decode(defaults.string(forKey: ForkDefaultsKey.glancePausedUntil)), now: now)
    }

    static func store(_ stored: ForkGlancePauseRules.Stored, _ defaults: UserDefaults = .standard) {
        let text = ForkGlancePauseRules.encode(stored)
        guard defaults.string(forKey: ForkDefaultsKey.glancePausedUntil) ?? "" != text else { return }
        defaults.set(text, forKey: ForkDefaultsKey.glancePausedUntil)
    }

    /// The stored pause for a duration picked now.
    static func stored(for duration: ForkGlancePauseDuration, now: Date = Date()) -> ForkGlancePauseRules.Stored {
        duration.end(from: now).map(ForkGlancePauseRules.Stored.until) ?? .untilResumed
    }
}
