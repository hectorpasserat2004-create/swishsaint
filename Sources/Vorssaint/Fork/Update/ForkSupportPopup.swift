// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The fork never shows the official "Support Vorssaint / Buy Me a Coffee"
/// window, neither after an update nor when the update tour is replayed.
/// The support page in Settings stays reachable for anyone who looks for it.
enum ForkSupportPopup {
    /// Called by the seam `no-support-popup` at the start of
    /// `AppDelegate.showSupportUpdateIntro(isReview:)`. Returns true: the
    /// window is skipped. After an update (not a replay), it does what
    /// closing the window would have done: `markSeen` records this
    /// release's invitation as seen, so it is never offered again, and
    /// `next` lets the remaining update intros follow.
    static func skip(isReview: Bool, markSeen: () -> Void,
                     next: @escaping () -> Void) -> Bool {
        guard !isReview else { return true }
        markSeen()
        DispatchQueue.main.async(execute: next)
        return true
    }
}
