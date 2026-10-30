// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import ApplicationServices
import CoreGraphics
import os

/// Hands the keyboard to a zone's window (plan §6.2) and moves the pointer
/// (§6.3), by the official paths of « le focus suit la souris »:
/// `WindowActivator.activate` to bring the window forward (SkyLight, then the
/// cooperative activation of macOS 14), `SpaceWindowBridge.focusWithoutRaise`
/// to focus it where it is. Checks again 150 ms later, tries once more, then
/// reports a failure; three failures in a row set an app aside for 5 minutes.
/// Main thread only.
final class ForkGlanceFocuser: ForkGlanceFocusPerforming {
    static let shared = ForkGlanceFocuser()

    /// When the result of an attempt is read.
    static let verifyDelay: TimeInterval = 0.15
    static let failuresBeforeSetAside = 3
    static let setAsideDuration: TimeInterval = 5 * 60

    /// Each switch's outcome, on the main thread; an attempt overtaken by a
    /// newer one reports nothing.
    var onResult: ((ForkGlanceTarget, Bool) -> Void)?

    /// App name → the end of its time aside (diagnostics).
    var setAside: [String: Date] {
        pruneSetAside()
        return asideUntil
    }

    /// `systemUptime` of the last pointer move Glance made: the pointer guard
    /// leaves it out for 300 ms.
    private(set) var lastPointerWarp: TimeInterval?

    private var generation: UInt64 = 0
    private var failures: [String: Int] = [:]
    private var asideUntil: [String: Date] = [:]
    private let log = Logger(subsystem: "fork.glance", category: "focus")

    private init() {}

    // MARK: - Focus

    /// False when it could not even try: no Accessibility, a button or a
    /// modifier held, the app set aside or gone, the window gone or on a
    /// hidden Space. Already focused, nothing moves and it succeeds.
    func focus(_ target: ForkGlanceTarget, raise: Bool) -> Bool {
        precondition(Thread.isMainThread)
        generation &+= 1
        let attempt = generation
        guard canAct(on: target.window) else { return false }
        if Self.isFocused(target.window) {
            DispatchQueue.main.async { [weak self] in self?.finish(target, succeeded: true, attempt: attempt) }
            return true
        }
        perform(target, raise: raise, attempt: attempt)
        verify(target, raise: raise, attempt: attempt, retried: false)
        return true
    }

    /// Drops the attempt in flight (Glance stopped), and forgets the failures.
    func reset() {
        precondition(Thread.isMainThread)
        generation &+= 1
        failures.removeAll()
        asideUntil.removeAll()
    }

    private func canAct(on window: ForkGlanceWindow) -> Bool {
        guard AXIsProcessTrusted(), Self.nothingIsHeldDown, !isSetAside(window.appName),
              window.pid != ProcessInfo.processInfo.processIdentifier,
              let app = NSRunningApplication(processIdentifier: window.pid),
              !app.isTerminated, app.activationPolicy == .regular,
              Self.isOnScreen(window)
        else { return false }
        // A window still parked on a hidden Space is a desktop switch in
        // flight: activating it would replay the slide.
        return !SpaceWindowBridge.isParkedOnHiddenSpace(window.id)
    }

    private func perform(_ target: ForkGlanceTarget, raise: Bool, attempt: UInt64) {
        let window = target.window
        guard !raise else {
            WindowActivator.activate(pid: window.pid, windowID: window.id, appName: window.appName, retry: false)
            return
        }
        let appIsFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == window.pid
        let activation = WindowActivator.supersedePendingActivations(for: window.pid)
        SpaceWindowBridge.focusWithoutRaise(
            window.id, ownerPID: window.pid,
            replacing: appIsFrontmost ? WindowActivator.focusedWindowID(for: window.pid) : nil,
            while: { [weak self] in
                self?.generation == attempt && Self.nothingIsHeldDown && WindowActivator.isCurrentActivation(activation)
            },
            completion: { _ in })
    }

    private func verify(_ target: ForkGlanceTarget, raise: Bool, attempt: UInt64, retried: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.verifyDelay) { [weak self] in
            guard let self, self.generation == attempt else { return }
            if Self.isFocused(target.window) {
                self.finish(target, succeeded: true, attempt: attempt)
            } else if !retried, self.canAct(on: target.window) {
                self.perform(target, raise: raise, attempt: attempt)
                self.verify(target, raise: raise, attempt: attempt, retried: true)
            } else {
                self.finish(target, succeeded: false, attempt: attempt)
            }
        }
    }

    private func finish(_ target: ForkGlanceTarget, succeeded: Bool, attempt: UInt64) {
        guard generation == attempt else { return }
        let app = target.window.appName
        if succeeded {
            failures[app] = nil
        } else {
            let count = (failures[app] ?? 0) + 1
            if count >= Self.failuresBeforeSetAside {
                failures[app] = nil
                asideUntil[app] = Date().addingTimeInterval(Self.setAsideDuration)
                log.notice("an app refused focus \(count, privacy: .public) times in a row, set aside for 5 min")
            } else {
                failures[app] = count
            }
        }
        onResult?(target, succeeded)
    }

    private func isSetAside(_ app: String) -> Bool {
        pruneSetAside()
        return asideUntil[app] != nil
    }

    private func pruneSetAside() {
        let now = Date()
        asideUntil = asideUntil.filter { $0.value > now }
    }

    /// The window has the keyboard: its app is in front and focuses it.
    private static func isFocused(_ window: ForkGlanceWindow) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == window.pid
            && WindowActivator.focusedWindowID(for: window.pid) == window.id
    }

    /// Still on screen and still owned by the same process, straight from the
    /// window server.
    private static func isOnScreen(_ window: ForkGlanceWindow) -> Bool {
        let infos = CGWindowListCopyWindowInfo(.optionIncludingWindow, window.id) as? [[String: Any]] ?? []
        return infos.contains { info in
            (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value == window.id
                && (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == window.pid
                && (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true
        }
    }

    /// No mouse button pressed and no modifier, as `FocusFollowsMouseService`
    /// asks before each action: a drag or a shortcut may be under way.
    static var nothingIsHeldDown: Bool {
        NSEvent.pressedMouseButtons == 0
            && NSEvent.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
    }

    // MARK: - Pointer

    /// Warps the pointer (no permission needed) and ties it back to the mouse,
    /// without which the next physical move snaps it back
    /// (`PointerDisplayService`). Stamped for the pointer guard.
    func movePointer(to point: CGPoint) {
        precondition(Thread.isMainThread)
        lastPointerWarp = ProcessInfo.processInfo.systemUptime
        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}
