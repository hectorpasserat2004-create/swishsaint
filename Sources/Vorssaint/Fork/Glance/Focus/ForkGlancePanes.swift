// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import ApplicationServices
import CoreGraphics

/// Panes inside a terminal or an editor (plan §5.4), experimental and off by
/// default; the rules are in `Pure/ForkGlanceTargeting` (`ForkGlancePaneRules`).
/// Called once the window has the keyboard, with the gaze point.
///
/// 1. Accessibility: the element under the point, asked of the target app
///    alone (never a system-wide query), then up to the first pane whose focus
///    is settable, then `kAXFocusedAttribute`.
/// 2. If that fails and the click fallback is on: one synthetic click at the
///    center of the pane found, only inside the target window, never on a
///    control, never while typing, marked so the learning ignores it.
///
/// Chromium apps are never asked (`ForkGlancePaneRules.chromiumBundleIDs`).
/// Main thread only; every Accessibility call carries a short timeout.
enum ForkGlancePanes {
    /// `CGEventField.eventSourceUserData` of the fallback's click: the click
    /// monitor of the learning drops events carrying it.
    static let syntheticMarker = ForkGlanceInputRules.syntheticClickMarker

    /// One Accessibility round trip, per element: a hung app costs little.
    private static let timeout: Float = 0.15
    /// How long the pointer stays at the click before going back.
    private static let pointerReturnDelay: TimeInterval = 0.05

    /// True when the pane under `point` has the keyboard afterwards (or had it).
    static func focusPane(at point: CGPoint, in target: ForkGlanceTarget, clickFallback: Bool, typing: Bool) -> Bool {
        precondition(Thread.isMainThread)
        let window = target.window
        guard AXIsProcessTrusted(), window.frame.contains(point),
              window.pid != ProcessInfo.processInfo.processIdentifier,
              ForkGlancePaneRules.allowsAccessibility(bundleID: window.bundleID),
              let found = pane(at: point, in: window)
        else { return false }

        if let focusable = found.focusable {
            if bool(focusable, kAXFocusedAttribute) == true { return true }
            // The return code is unreliable across apps; the read-back decides.
            _ = AXUIElementSetAttributeValue(focusable, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            if bool(focusable, kAXFocusedAttribute) == true { return true }
        }

        guard clickFallback, !typing, ForkGlanceFocuser.nothingIsHeldDown,
              let clickable = found.clickable, let paneFrame = frame(of: clickable),
              let center = ForkGlancePaneRules.clickPoint(pane: paneFrame, window: window.frame)
        else { return false }
        return click(at: center, on: clickable, in: window)
    }

    // MARK: - Accessibility

    private struct Found {
        /// The first pane up the path whose focus is settable.
        var focusable: AXUIElement?
        /// The first pane up the path the fallback may click.
        var clickable: AXUIElement?
    }

    /// Walks up from the element under `point` to the window, which must be
    /// the target one.
    private static func pane(at point: CGPoint, in window: ForkGlanceWindow) -> Found? {
        guard var current = hit(at: point, pid: window.pid) else { return nil }
        var found = Found()
        for _ in 0..<ForkGlancePaneRules.maxDepth {
            let role = string(current, kAXRoleAttribute)
            if role == kAXWindowRole as String {
                return AXWindowResolver.windowID(for: current) == window.id ? found : nil
            }
            if let role {
                if found.focusable == nil, ForkGlancePaneRules.focusRoles.contains(role),
                   isSettable(current, kAXFocusedAttribute) {
                    found.focusable = current
                }
                if found.clickable == nil, ForkGlancePaneRules.clickRoles.contains(role) {
                    found.clickable = current
                }
            }
            guard let parent = element(current, kAXParentAttribute) else { return nil }
            current = parent
        }
        return nil
    }

    /// The target app's element under `point`, only if that app owns it.
    private static func hit(at point: CGPoint, pid: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, timeout)
        var raw: AXUIElement?
        guard AXUIElementCopyElementAtPosition(application, Float(point.x), Float(point.y), &raw) == .success,
              let raw
        else { return nil }
        AXUIElementSetMessagingTimeout(raw, timeout)
        var owner: pid_t = 0
        guard AXUIElementGetPid(raw, &owner) == .success, owner == pid else { return nil }
        return raw
    }

    // MARK: - Click fallback

    /// Clicks `point` if the window server would hand the click to the target
    /// window and nothing between the element there and the pane is a control.
    private static func click(at point: CGPoint, on pane: AXUIElement, in window: ForkGlanceWindow) -> Bool {
        guard WindowServerSupport.receivingWindow(at: point) == window.id,
              var current = hit(at: point, pid: window.pid)
        else { return false }
        var roles: [String?] = []
        var reachedPane = false
        for _ in 0..<ForkGlancePaneRules.maxDepth {
            if CFEqual(current, pane) {
                reachedPane = true
                break
            }
            roles.append(string(current, kAXRoleAttribute))
            guard let parent = element(current, kAXParentAttribute) else { break }
            current = parent
        }
        guard reachedPane, ForkGlancePaneRules.isSafeToClick(roles: roles),
              let original = CGEvent(source: nil)?.location
        else { return false }

        // The pointer goes to the click and back: a click delivered elsewhere
        // than under the pointer is not one every app believes. Both moves
        // are stamped, so the pointer guard does not count them.
        let focuser = ForkGlanceFocuser.shared
        focuser.movePointer(to: point)
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                      mouseCursorPosition: point, mouseButton: .left) else { continue }
            event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
            event.post(tap: .cghidEventTap)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + pointerReturnDelay) {
            focuser.movePointer(to: original)
        }
        return true
    }

    // MARK: - Attributes

    private static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        let found = value as! AXUIElement
        // A timeout belongs to one element reference, not to the app.
        AXUIElementSetMessagingTimeout(found, timeout)
        return found
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func bool(_ element: AXUIElement, _ name: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? Bool
    }

    private static func isSettable(_ element: AXUIElement, _ name: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success && settable.boolValue
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }
}
