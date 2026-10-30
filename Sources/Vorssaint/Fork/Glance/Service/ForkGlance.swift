// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Glance Focus in the app: started once at launch by `ForkBootstrap.start()`,
/// then synced by every switch of the feature (`ForkFeature.glanceFocus.sync()`),
/// like `ForkGestures`. Off, everything it started stops: camera, timers,
/// observers, shortcuts.
enum ForkGlance {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: ForkDefaultsKey.glanceEnabled) }

    /// At launch, whatever the switch says: the service hooks its callbacks,
    /// then syncs once the launch is done.
    static func start() {
        ForkGlanceService.shared.start()
    }

    /// The switch moved (its page, the Extras page, a settings import): the
    /// window history the zones read (seam `glance-mru`), the service, and
    /// the island's section, tile and activity.
    static func sync() {
        precondition(Thread.isMainThread)
        ForkGlanceWindowIndex.syncTracker()
        ForkGlanceService.shared.sync()
        ForkGlanceIsland.sync()
    }

    /// Before Accessibility is revoked or the app quits: stop acting on windows.
    static func suspend() {
        ForkGlanceService.shared.suspend()
    }
}
