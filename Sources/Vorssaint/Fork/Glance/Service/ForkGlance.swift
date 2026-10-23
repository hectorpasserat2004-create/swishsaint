// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Glance Focus in the app: started once at launch by `ForkBootstrap.start()`,
/// then synced by every switch of the feature (`ForkFeature.glanceFocus.sync()`),
/// like `ForkGestures`. Off, everything it started stops: camera, timers,
/// observers, shortcuts.
enum ForkGlance {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: ForkDefaultsKey.glanceEnabled) }

    /// At launch, whatever the switch says.
    static func start() {}

    /// The switch moved (its page, the Extras page, a settings import).
    static func sync() {}

    /// Before Accessibility is revoked or the app quits: stop acting on windows.
    static func suspend() {}
}
