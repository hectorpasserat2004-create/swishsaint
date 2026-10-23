// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import CoreGraphics

/// The windows on screen and their order of use, for the zones (plan §6.1).
/// Reads the window server only (`WindowServerSupport.onScreenWindowInfo`,
/// no round trip to any app) and the official use history
/// (`WindowUseTracker`), which runs while Glance is on through the seam
/// `glance-mru`. Read when a switch is a candidate, never at every image,
/// and kept 250 ms. Main thread only.
final class ForkGlanceWindowIndex: ForkGlanceWindowSource {
    static let shared = ForkGlanceWindowIndex()

    /// How long one reading of the window server serves.
    static let cacheLifetime: TimeInterval = 0.25
    /// Narrower or shorter than this, a layer-0 window is a sliver (a drag
    /// image, a hidden helper), never a target.
    static let minimumSide: CGFloat = 40

    private var cached: (time: TimeInterval, windows: [ForkGlanceWindow])?

    private init() {}

    /// At launch (`ForkBootstrap.start()`): the official tracker asks Glance
    /// whether it is needed at each of its syncs (seam `glance-mru`).
    static func start() {
        WindowUseTracker.forkDemand = { ForkGlance.isEnabled }
    }

    /// Glance's switch moved: the tracker starts, or stops unless the
    /// switcher or Window Layout still needs it. Called by `ForkGlance.sync()`.
    static func syncTracker() {
        precondition(Thread.isMainThread)
        WindowUseTracker.shared.syncWithFeatures()
        shared.invalidate()
    }

    // MARK: - ForkGlanceWindowSource

    /// Layer-0 windows on screen, front to back.
    func windows() -> [ForkGlanceWindow] {
        precondition(Thread.isMainThread)
        let now = ProcessInfo.processInfo.systemUptime
        if let cached, now - cached.time < Self.cacheLifetime { return cached.windows }
        let fresh = Self.readWindowServer()
        cached = (now, fresh)
        return fresh
    }

    /// Most recently used first. Empty while the tracker has not seeded yet.
    func recentWindowIDs() -> [UInt32] {
        WindowUseTracker.shared.windows
    }

    /// The front app's focused window (one Accessibility round trip, 0.35 s at most).
    func focusedWindowID() -> UInt32? {
        precondition(Thread.isMainThread)
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        return WindowActivator.focusedWindowID(for: front.processIdentifier)
    }

    /// The next read asks the window server again (a switch just happened).
    func invalidate() {
        cached = nil
    }

    // MARK: - Window server

    private static func readWindowServer() -> [ForkGlanceWindow] {
        let infos = WindowServerSupport.onScreenWindowInfo()
        // One Space query for the whole list; nil when SkyLight does not answer,
        // and then no window counts as parked (the official fallback).
        let visibleSpaces = SpaceWindowBridge.topology()?.visibleSpaces
        var apps: [pid_t: NSRunningApplication?] = [:]
        var windows: [ForkGlanceWindow] = []
        for info in infos {
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid > 0,
                  (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let frame = WindowServerSupport.bounds(from: info),
                  frame.width >= minimumSide, frame.height >= minimumSide
            else { continue }
            if apps[pid] == nil { apps[pid] = NSRunningApplication(processIdentifier: pid) }
            let app = apps[pid] ?? nil
            let name = info[kCGWindowOwnerName as String] as? String ?? app?.localizedName ?? ""
            let parked = visibleSpaces.map { SpaceWindowBridge.isParkedOnHiddenSpace(id, visibleSpaces: $0) } ?? false
            windows.append(ForkGlanceWindow(id: id, pid: pid, bundleID: app?.bundleIdentifier, appName: name,
                                            frame: frame, isOnHiddenSpace: parked))
        }
        return windows
    }
}
