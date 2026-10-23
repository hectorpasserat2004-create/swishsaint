// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import os

/// What the person's hands are doing, read at each camera image for the
/// guards (plan §7.4), plus the real left clicks the learning pairs with the
/// gaze (plan §7.6).
///
/// - **Ages, never keys.** The last key and pointer events' ages come from
///   the session's event state (`CGEventSource.secondsSinceLastEventType`),
///   as `MiddleClickService` reads the last key down: no tap, no permission,
///   about 20 ns a read. No key code is ever seen.
/// - **Glance's own pointer.** After the Focuser moves the pointer, the
///   service sets `ignorePointerUntil` (or calls `ignorePointer(for:)`): a
///   pointer event from then until that end is Glance's, and `sincePointer`
///   keeps counting from the last real one.
/// - **Menus and overviews** cost a window-server list (0.3 to 0.5 ms with
///   15 windows on screen, measured; more with more windows), too much for
///   every image: it is read off the main thread, at most twice a second
///   and only while someone asks (`menuWindowInterval`). A menu opened by a
///   click or a key is covered meanwhile by the pointer and typing guards,
///   which last at least 0.5 s. This app's own menus come from
///   `NSMenu.didBeginTracking`, the official screenshot selection from
///   `ScreenshotSelectionController.isSessionOnScreen`.
/// - **Clicks**: a global left-mouse-down monitor, which needs no permission
///   for mouse events and never sees a click on this app's own windows. Only
///   the position and time are kept; a click posted by a program (this app's
///   pane fallback included) is dropped (`isRealClick`).
/// - **Idle pause**: `onNextActivity` polls the same ages at 2 Hz while the
///   camera is off, and calls back at the first key or pointer event.
///
/// Main thread only, apart from the window list's read. `stop()` removes
/// every monitor, observer and timer.
final class ForkGlanceInputWatch: ForkGlanceInputSource {
    static let shared = ForkGlanceInputWatch()

    /// How long a warp of the pointer by Glance is not the person's.
    static let warpIgnore: TimeInterval = 0.3
    /// A warp may land just before `ignorePointerUntil` is set.
    static let warpLead: TimeInterval = 0.05
    /// At most one window-server list this often (the `menuOrOverview` guard).
    static let menuWindowInterval: TimeInterval = 0.5
    /// The idle pause's poll (plan §7.5).
    static let activityPollInterval: TimeInterval = 0.5

    /// Moving, dragging, scrolling or pressing a button: the `pointer` guard.
    static let pointerEventTypes: [CGEventType] = [
        .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel,
        .leftMouseDown, .rightMouseDown, .otherMouseDown,
    ]
    /// What ends an idle pause: the same events the idle age is made of, so
    /// a pause never ends on something that did not reset the idle count.
    static let activityEventTypes: [CGEventType] = [.keyDown] + pointerEventTypes

    private static let ownPID = getpid()
    private static let modifierMask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

    /// Set by the service right after the Focuser moved the pointer (or
    /// posted a pane click): pointer events until then are Glance's own.
    /// `systemUptime` seconds.
    var ignorePointerUntil: TimeInterval = 0 {
        didSet { ignorePointerFrom = ProcessInfo.processInfo.systemUptime - Self.warpLead }
    }
    /// A real left click: its position (global points, origin at the top
    /// left) and its time (`systemUptime` seconds). Main thread.
    var onClick: ((CGPoint, TimeInterval) -> Void)?
    /// The island is open with the keyboard. Set by the island's part.
    var islandKeyProvider: () -> Bool = { false }
    /// A window of this app is key: Settings, the Command Bar, the assistant.
    var ownPanelKeyProvider: () -> Bool = { NSApp?.keyWindow != nil }

    private let log = Logger(subsystem: "fork.glance", category: "input")
    private let windows = ForkGlanceMenuWindowProbe()

    // Main thread state.
    private(set) var isRunning = false
    private var ignorePointerFrom: TimeInterval = 0
    /// The last pointer event that was the person's, `systemUptime`.
    private var realPointerAt: TimeInterval?
    private var ownMenuOpen = false
    private var clickMonitor: Any?
    private var menuObservers: [NSObjectProtocol] = []
    private var activityTimer: Timer?
    private var lastMenuOrOverview = false

    private init() {}

    // MARK: - Lifecycle

    /// Main thread. Watches the clicks and this app's menus. Idempotent.
    func start() {
        precondition(Thread.isMainThread)
        guard !isRunning else { return }
        isRunning = true
        realPointerAt = nil
        ownMenuOpen = false
        windows.reset()

        // Mouse events need no permission for a global monitor, and a click
        // on one of this app's windows never reaches it (plan §7.6).
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.received(click: event)
        }
        let center = NotificationCenter.default
        menuObservers = [
            center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) {
                [weak self] _ in self?.ownMenuOpen = true
            },
            center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) {
                [weak self] _ in self?.ownMenuOpen = false
            },
        ]
        log.debug("input watch started")
    }

    /// Main thread. Removes every monitor and observer, and ends the idle
    /// poll (`onNextActivity`): arm that one after `stop()` when pausing.
    func stop() {
        precondition(Thread.isMainThread)
        cancelActivityWatch()
        guard isRunning else { return }
        isRunning = false
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        menuObservers.forEach { NotificationCenter.default.removeObserver($0) }
        menuObservers.removeAll()
        ownMenuOpen = false
        lastMenuOrOverview = false
        windows.reset()
        log.debug("input watch stopped")
    }

    /// Main thread. Pointer events from now for `duration` are Glance's.
    func ignorePointer(for duration: TimeInterval = ForkGlanceInputWatch.warpIgnore) {
        precondition(Thread.isMainThread)
        ignorePointerUntil = ProcessInfo.processInfo.systemUptime + duration
    }

    // MARK: - Snapshot

    /// Main thread, at each image. A few nanosecond reads of the session's
    /// event state, and the window list's last result (refreshed off the
    /// main thread when due).
    func snapshot() -> ForkGlanceInputSnapshot {
        precondition(Thread.isMainThread)
        let now = ProcessInfo.processInfo.systemUptime
        let sinceKey = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        let pressed = CGEventSource.flagsState(.combinedSessionState).intersection(Self.modifierMask)

        var menuOrOverview = ownMenuOpen || ScreenshotSelectionController.isSessionOnScreen
        if windows.isDue(now: now) {
            windows.refresh(displaySizes: NSScreen.screens.map(\.frame.size), ownPID: Self.ownPID)
        }
        menuOrOverview = menuOrOverview || windows.value
        if menuOrOverview != lastMenuOrOverview {
            lastMenuOrOverview = menuOrOverview
            log.debug("menu or overview: \(menuOrOverview, privacy: .public)")
        }

        return ForkGlanceInputSnapshot(
            sinceKey: sinceKey,
            sincePointer: sincePointer(now: now),
            buttonsDown: NSEvent.pressedMouseButtons != 0,
            modifiersDown: !pressed.isEmpty,
            secureInput: IsSecureEventInputEnabled(),
            dictationActive: ForkDictationService.shared.isDictating,
            menuOrOverview: menuOrOverview,
            islandKey: islandKeyProvider(),
            ownPanelKey: ownPanelKeyProvider(),
            frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    /// The latest pointer event's age, Glance's own warps left out.
    private func sincePointer(now: TimeInterval) -> TimeInterval {
        let age = Self.age(of: Self.pointerEventTypes)
        guard age.isFinite else { return realPointerAt.map { now - $0 } ?? age }
        let latest = now - age
        if !Self.isGlancePointer(at: latest, from: ignorePointerFrom, until: ignorePointerUntil) {
            realPointerAt = max(realPointerAt ?? latest, latest)
        }
        // Before any real event is known, the age as the session tells it.
        return realPointerAt.map { max(0, now - $0) } ?? age
    }

    /// A pointer event at `time` lies in the window Glance moved the pointer in.
    static func isGlancePointer(at time: TimeInterval, from start: TimeInterval, until end: TimeInterval) -> Bool {
        end > start && time >= start && time <= end
    }

    /// The youngest age among `types`, seconds.
    static func age(of types: [CGEventType]) -> TimeInterval {
        types.reduce(TimeInterval.infinity) {
            min($0, CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $1))
        }
    }

    // MARK: - Clicks

    private func received(click event: NSEvent) {
        guard isRunning, let onClick, let cgEvent = event.cgEvent else { return }
        let real = Self.isRealClick(sourcePID: cgEvent.getIntegerValueField(.eventSourceUnixProcessID),
                                    userData: cgEvent.getIntegerValueField(.eventSourceUserData),
                                    ownPID: Int64(Self.ownPID))
        guard real else { return }
        onClick(cgEvent.location, event.timestamp)
    }

    /// A click the person made, not one a program posted. The window server
    /// stamps a posted event with its poster's process id (`OwnKeyEvent`),
    /// and every synthetic event of this app carries a user-data marker
    /// (the panes' fallback click among them): a hardware click has neither.
    static func isRealClick(sourcePID: Int64, userData: Int64, ownPID: Int64) -> Bool {
        sourcePID != ownPID && userData == 0
    }

    // MARK: - Idle pause

    /// Main thread. Calls `handler` once, on the main thread, at the first
    /// key or pointer event after this call, polling the event ages at 2 Hz
    /// (no tap, no permission). Replaces a previous watch. Works whether the
    /// watch runs or not; `stop()` and `cancelActivityWatch()` end it.
    func onNextActivity(_ handler: @escaping () -> Void) {
        precondition(Thread.isMainThread)
        cancelActivityWatch()
        let armedAt = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: Self.activityPollInterval, repeats: true) { [weak self] _ in
            let age = Self.age(of: Self.activityEventTypes)
            guard age.isFinite, ProcessInfo.processInfo.systemUptime - age > armedAt else { return }
            self?.cancelActivityWatch()
            handler()
        }
        timer.tolerance = Self.activityPollInterval * 0.4
        RunLoop.main.add(timer, forMode: .common)
        activityTimer = timer
    }

    /// Main thread.
    func cancelActivityWatch() {
        activityTimer?.invalidate()
        activityTimer = nil
    }

    var isWatchingForActivity: Bool { activityTimer != nil }
}

// MARK: - Menus, overviews and screenshot selections

/// The window server's list, read on its own queue at most every
/// `ForkGlanceInputWatch.menuWindowInterval`, and only when a snapshot asks:
/// nothing runs while the camera is off. A late answer from before a
/// `reset()` is dropped (generation).
private final class ForkGlanceMenuWindowProbe: @unchecked Sendable {
    private let queue = DispatchQueue(label: "fork.glance.windows", qos: .utility)
    private let lock = NSLock()
    private var current = false
    private var readAt = -TimeInterval.infinity
    private var inFlight = false
    private var generation = 0
    /// pid → bundle id, for the few windows that cover a display. Queue only.
    private var bundleIDs: [pid_t: String] = [:]

    var value: Bool { lock.withLock { current } }

    func isDue(now: TimeInterval) -> Bool {
        lock.withLock { !inFlight && now - readAt >= ForkGlanceInputWatch.menuWindowInterval }
    }

    func refresh(displaySizes: [CGSize], ownPID: pid_t) {
        let ticket: Int? = lock.withLock {
            guard !inFlight else { return nil }
            inFlight = true
            return generation
        }
        guard let ticket else { return }
        queue.async { [self] in
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] ?? []
            let hit = ForkGlanceMenuWindows.hit(in: list, ownPID: ownPID, displaySizes: displaySizes) { pid in
                if let known = bundleIDs[pid] { return known }
                let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
                bundleIDs[pid] = id
                return id
            }
            if bundleIDs.count > 64 { bundleIDs.removeAll() }
            let done = ProcessInfo.processInfo.systemUptime
            lock.withLock {
                guard generation == ticket else { return }
                current = hit != nil
                readAt = done
                inFlight = false
            }
        }
    }

    func reset() {
        lock.withLock {
            generation += 1
            current = false
            readAt = -.infinity
            inFlight = false
        }
    }
}

/// Which on-screen windows mean a menu, Mission Control or App Exposé, or
/// a screenshot selection (plan §7.4). Pure over the window list's
/// dictionaries.
enum ForkGlanceMenuWindows {
    enum Hit: Equatable {
        /// A menu of another app: menu bar, context or pop-up menus all sit
        /// at `kCGPopUpMenuWindowLevel` (`CGWindowLevel.h`: 101).
        case menu
        /// Mission Control or App Exposé, read like
        /// `NotchFrameProbe.overviewIsVisible(on:)` (private to
        /// `NotchWindowHost.swift`, hence restated): Dock's overview window at
        /// layer 18 before macOS 27, WindowManager's display-wide one at layer
        /// 19 since (Show Desktop's layer 18 and Stage Manager's strip stay out).
        case overview
        /// The system's screenshot selection (⌘⇧4, ⌘⇧5): screencaptureui
        /// covering a display.
        case screenshot
    }

    static let menuLayer = Int(kCGPopUpMenuWindowLevel)
    static let screenshotBundleID = "com.apple.screencaptureui"

    /// The first window that holds the guard, nil when none. This app's own
    /// windows never count (its menus come from `NSMenu` notifications; its
    /// tooltips and drag ghosts sit at the menu layer too).
    static func hit(in windows: [[String: Any]], ownPID: pid_t, displaySizes: [CGSize],
                    bundleID: (pid_t) -> String) -> Hit? {
        for window in windows {
            guard let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != ownPID else {
                continue
            }
            if let alpha = window[kCGWindowAlpha as String] as? Double, alpha <= 0 { continue }
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            let owner = window[kCGWindowOwnerName as String] as? String
            let size = bounds(of: window).size
            guard size.width >= 2, size.height >= 2 else { continue }
            if layer == menuLayer { return .menu }
            // Unlike the official probe, Dock's window must cover a display
            // too: here it decides on its own, there it only starts a probe.
            let coversDisplay = displaySizes.contains {
                size.width >= $0.width - 1 && size.height >= $0.height - 1
            }
            guard coversDisplay else { continue }
            if owner == "Dock", layer == 18 { return .overview }
            if owner == "WindowManager", layer == 19 { return .overview }
            if layer > 0, bundleID(pid) == screenshotBundleID { return .screenshot }
        }
        return nil
    }

    static func bounds(of window: [String: Any]) -> CGRect {
        guard let dictionary = window[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: dictionary) else { return .zero }
        return rect
    }
}
