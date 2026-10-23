// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

/// Zone to window (plan §5, §6.1, §6.3): which window a zone hands the
/// keyboard to, which zone a window lies in, and where the pointer may land.
/// Pure: the window list comes from `Focus/ForkGlanceWindowIndex`, so the
/// tests feed it by hand.
enum ForkGlanceTargeting {
    /// A window belongs to a zone when the part of it the person can see there
    /// covers this share of the whole window…
    static let windowShare: CGFloat = 0.4
    /// …or this share of the zone, which keeps a window maximized over two
    /// zones the target of both.
    static let zoneShare: CGFloat = 0.5

    /// The most recently used window whose largest visible part falls in
    /// `zone`, the windows in front of it taken off (plan §5.2). Never a
    /// window parked on a hidden Space, never an app of « Ne jamais activer »
    /// (`neverFocus`, bundle ids, a trailing "." is a prefix): the next one
    /// wins instead. In Screens mode, when no window qualifies, the frontmost
    /// app's window that shows there. In Windows mode, the zone's own window or
    /// nothing. Nil leaves the keyboard where it is; the desktop is never a
    /// target, since the window server lists it on no layer-0 window.
    ///
    /// `windows`: layer 0, front to back. `recent`: most recently used first;
    /// a window it does not know follows every known one, in z-order.
    static func target(for zone: ForkGlanceZone, mode: ForkGlanceMode, windows: [ForkGlanceWindow],
                       recent: [UInt32], neverFocus: [String], frontmostPID: Int32?) -> ForkGlanceTarget? {
        guard !zone.rect.isNull, !zone.rect.isEmpty else { return nil }
        func eligible(_ window: ForkGlanceWindow) -> Bool {
            !window.isOnHiddenSpace && !window.frame.isNull && !window.frame.isEmpty
                && !ForkGlanceSettings.list(neverFocus, contains: window.bundleID)
        }

        // Windows mode: the zone is a window. Another window under an excluded
        // one would be a window the person does not see, so nothing.
        if mode == .windows, let windowID = zone.windowID {
            guard let window = windows.first(where: { $0.id == windowID }), eligible(window) else { return nil }
            return ForkGlanceTarget(zoneID: zone.id, window: window)
        }

        let zoneArea = area(zone.rect)
        for index in usageOrder(windows, recent: recent) where eligible(windows[index]) {
            let window = windows[index]
            let shown = visibleArea(of: index, in: zone.rect, windows: windows)
            guard shown > 0 else { continue }
            if shown >= windowShare * area(window.frame) || shown >= zoneShare * zoneArea {
                return ForkGlanceTarget(zoneID: zone.id, window: window)
            }
        }

        // Screens mode (plan §5.1): the frontmost app, if it shows a window here.
        guard mode == .screens, let frontmostPID else { return nil }
        for (index, window) in windows.enumerated()
        where window.pid == frontmostPID && eligible(window) && visibleArea(of: index, in: zone.rect, windows: windows) > 0 {
            return ForkGlanceTarget(zoneID: zone.id, window: window)
        }
        return nil
    }

    /// The zone a window lies in, for `.focusChanged`: its own zone in Windows
    /// mode, else the zone holding the largest part of its frame (a tie goes
    /// to the zone holding its center). Nil when it touches none.
    static func zone(of window: ForkGlanceWindow, in zones: [ForkGlanceZone]) -> ForkGlanceZone? {
        if let own = zones.first(where: { $0.windowID == window.id }) { return own }
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        var best: (zone: ForkGlanceZone, area: CGFloat, holdsCenter: Bool)?
        for zone in zones where zone.windowID == nil {
            let shared = area(zone.rect.intersection(window.frame))
            guard shared > 0 else { continue }
            let holdsCenter = zone.rect.contains(center)
            if let current = best,
               shared < current.area || (shared == current.area && (current.holdsCenter || !holdsCenter)) {
                continue
            }
            best = (zone, shared, holdsCenter)
        }
        return best?.zone
    }

    // MARK: - Pointer (plan §6.3)

    /// The band at the top of a display with a notch: the pointer there opens
    /// the island.
    static let notchBand: CGFloat = 40
    /// Kept from every edge: hot corners answer within a few points of a
    /// corner, and a hidden Dock rises from its edge.
    static let edgeInset: CGFloat = 8

    /// Where the pointer may land on a display.
    static func pointerArea(on display: ForkGlanceDisplay) -> CGRect {
        var area = display.frame.insetBy(dx: edgeInset, dy: edgeInset)
        if display.hasNotch {
            let top = display.frame.minY + notchBand
            if top > area.minY {
                area = CGRect(x: area.minX, y: top, width: area.width, height: max(0, area.maxY - top))
            }
        }
        return area.isNull || area.width <= 0 || area.height <= 0 ? .null : area
    }

    /// Where to put the pointer after a switch to `target` on `display`, nil:
    /// leave it. `behavior` is the resolved setting (`.auto` is read as
    /// `.stay`); `remembered` is the pointer's last place on this display.
    /// With « le focus suit la souris » on, the point is always inside the
    /// target window, so the two features agree; the caller then skips the
    /// move when the pointer already lies in that window.
    static func pointerDestination(behavior: ForkGlancePointerBehavior, target: ForkGlanceTarget,
                                   display: ForkGlanceDisplay, remembered: CGPoint?,
                                   focusFollowsMouse: Bool) -> CGPoint? {
        let allowed = pointerArea(on: display)
        guard !allowed.isNull else { return nil }
        let windowPart = target.window.frame.intersection(allowed)
        let windowCenter = windowPart.isNull || windowPart.isEmpty
            ? nil : CGPoint(x: windowPart.midX, y: windowPart.midY)

        switch behavior {
        case .stay, .auto:
            return focusFollowsMouse ? windowCenter : nil
        case .windowCenter:
            return windowCenter
        case .followScreen:
            if let remembered, allowed.contains(remembered),
               !focusFollowsMouse || windowPart.contains(remembered) {
                return remembered
            }
            if let windowCenter { return windowCenter }
            return focusFollowsMouse ? nil : CGPoint(x: allowed.midX, y: allowed.midY)
        }
    }

    // MARK: - Geometry

    static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull || rect.isEmpty ? 0 : rect.width * rect.height
    }

    /// Indices into `windows`, most recently used first; the windows the
    /// history does not know follow, front to back.
    static func usageOrder(_ windows: [ForkGlanceWindow], recent: [UInt32]) -> [Int] {
        var rank: [UInt32: Int] = [:]
        for (position, id) in recent.enumerated() where rank[id] == nil { rank[id] = position }
        return windows.indices.sorted { lhs, rhs in
            let left = rank[windows[lhs].id] ?? Int.max
            let right = rank[windows[rhs].id] ?? Int.max
            return left != right ? left < right : lhs < rhs
        }
    }

    /// The area of `windows[index]` inside `rect` that no window in front of
    /// it covers. A window parked on a hidden Space covers nothing.
    static func visibleArea(of index: Int, in rect: CGRect, windows: [ForkGlanceWindow]) -> CGFloat {
        let part = windows[index].frame.intersection(rect)
        guard area(part) > 0 else { return 0 }
        let covers = windows[..<index].compactMap { front -> CGRect? in
            guard !front.isOnHiddenSpace else { return nil }
            let cover = front.frame.intersection(part)
            return area(cover) > 0 ? cover : nil
        }
        return max(0, area(part) - unionArea(covers))
    }

    /// The area of a union of rectangles, exact: the plane is cut along every
    /// edge and each cell counted once.
    static func unionArea(_ rects: [CGRect]) -> CGFloat {
        let rects = rects.filter { area($0) > 0 }
        guard !rects.isEmpty else { return 0 }
        if rects.count == 1 { return area(rects[0]) }
        let xs = Array(Set(rects.flatMap { [$0.minX, $0.maxX] })).sorted()
        let ys = Array(Set(rects.flatMap { [$0.minY, $0.maxY] })).sorted()
        var total: CGFloat = 0
        for i in 0..<(xs.count - 1) {
            let midX = (xs[i] + xs[i + 1]) / 2
            let columns = rects.filter { $0.minX <= midX && midX < $0.maxX }
            guard !columns.isEmpty else { continue }
            for j in 0..<(ys.count - 1) {
                let midY = (ys[j] + ys[j + 1]) / 2
                if columns.contains(where: { $0.minY <= midY && midY < $0.maxY }) {
                    total += (xs[i + 1] - xs[i]) * (ys[j + 1] - ys[j])
                }
            }
        }
        return total
    }
}

/// The rules of the experimental panes (plan §5.4), kept pure so the tests
/// read them; `Focus/ForkGlancePanes` asks Accessibility and acts.
enum ForkGlancePaneRules {
    /// Accessibility roles a pane can be focused through, the first one met
    /// walking up from the element under the gaze. A group counts only when
    /// its focus is settable.
    static let focusRoles: Set<String> = ["AXTextArea", "AXScrollArea", "AXWebArea", "AXGroup"]
    /// The roles the click fallback may aim at the center of. A group is too
    /// often a toolbar or a cluster of controls.
    static let clickRoles: Set<String> = ["AXTextArea", "AXScrollArea", "AXWebArea"]
    /// Never clicked, nor anything inside them: a click there acts.
    static let controlRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXLink",
        "AXDisclosureTriangle", "AXSlider", "AXIncrementor", "AXComboBox", "AXTextField",
        "AXMenu", "AXMenuItem", "AXMenuBar", "AXMenuBarItem", "AXColorWell", "AXToolbar",
        "AXSplitter", "AXScrollBar", "AXValueIndicator", "AXTabGroup", "AXDateField", "AXStepper",
    ]
    /// Chromium apps (Electron editors): asking their Accessibility switches
    /// every renderer into full accessibility mode for the life of the
    /// process, a few percent of a core for good (issue #953, the note in
    /// `AutoQuitService`), and their editor groups are web content with no
    /// focusable pane anyway. Their panes are never tried.
    static let chromiumBundleIDs: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium",
        "com.todesktop.230313mxl2d9e9y", "com.exafunction.windsurf",
    ]
    /// A « pane » this large is the window's single view: the app draws its
    /// splits itself (kitty, WezTerm…), and its center may lie in another
    /// split than the one looked at.
    static let maxPaneShare: CGFloat = 0.9
    /// How far up from the element under the gaze the walk goes.
    static let maxDepth = 12

    static func allowsAccessibility(bundleID: String?) -> Bool {
        guard let bundleID else { return true }
        return !chromiumBundleIDs.contains(bundleID)
    }

    /// Where the click fallback clicks: the center of the pane's visible part
    /// in the window. Nil when the pane is the whole window or lies outside it.
    static func clickPoint(pane: CGRect, window: CGRect) -> CGPoint? {
        let part = pane.intersection(window)
        let windowArea = ForkGlanceTargeting.area(window)
        guard windowArea > 0, ForkGlanceTargeting.area(part) > 0,
              ForkGlanceTargeting.area(part) < maxPaneShare * windowArea else { return nil }
        return CGPoint(x: part.midX, y: part.midY)
    }

    /// Whether the path from the element under a click up to its pane is safe
    /// to click: no control on the way. `roles` runs from the hit upward.
    static func isSafeToClick(roles: [String?]) -> Bool {
        !roles.contains { role in role.map(controlRoles.contains) ?? false }
    }
}
