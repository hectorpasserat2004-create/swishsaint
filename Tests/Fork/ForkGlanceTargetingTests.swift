// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

/// Suite `fork-glance-targeting` — A6: zone to window, most recently used,
/// the pointer's landing point and the panes' rules (plan §5, §6, §17.1).
enum ForkGlanceTargetingTests {
    static func run(_ suite: TestSuite) {
        mostRecentPerZone(suite)
        shares(suite)
        occlusion(suite)
        exclusions(suite)
        screensMode(suite)
        windowsMode(suite)
        zoneOfWindow(suite)
        pointer(suite)
        panes(suite)
        geometry(suite)
    }

    // MARK: Martial's layout (plan, annex A)

    private static let lg = ForkGlanceDisplay(uuid: "LG", name: "LG HDR WQHD", frame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
                                              millimeters: CGSize(width: 816, height: 338))
    private static let builtIn = ForkGlanceDisplay(uuid: "BI", name: "Built-in", frame: CGRect(x: 938, y: 1440, width: 1728, height: 1117),
                                                   millimeters: CGSize(width: 344, height: 222), isBuiltIn: true, hasNotch: true)
    private static let lgLeft = ForkGlanceZone(id: "LG#0", displayUUID: "LG", rect: CGRect(x: 0, y: 0, width: 1720, height: 1440),
                                               position: .left)
    private static let lgRight = ForkGlanceZone(id: "LG#1", displayUUID: "LG", rect: CGRect(x: 1720, y: 0, width: 1720, height: 1440),
                                                position: .right)
    private static let macBook = ForkGlanceZone(id: "BI#0", displayUUID: "BI", rect: builtIn.frame, position: .whole)
    private static let lgScreen = ForkGlanceZone(id: "LG#0", displayUUID: "LG", rect: lg.frame, position: .whole)

    private static func window(_ id: UInt32, _ frame: CGRect, pid: Int32 = 100, bundle: String? = "com.example.app",
                               hidden: Bool = false) -> ForkGlanceWindow {
        ForkGlanceWindow(id: id, pid: pid, bundleID: bundle, appName: bundle ?? "App", frame: frame, isOnHiddenSpace: hidden)
    }

    private static func pick(_ zone: ForkGlanceZone, _ windows: [ForkGlanceWindow], recent: [UInt32],
                              mode: ForkGlanceMode = .zones, never: [String] = [], front: Int32? = nil) -> UInt32? {
        ForkGlanceTargeting.target(for: zone, mode: mode, windows: windows, recent: recent, neverFocus: never,
                                   frontmostPID: front)?.window.id
    }

    // MARK: Most recently used per zone

    private static func mostRecentPerZone(_ suite: TestSuite) {
        // Two windows side by side fill the LG (Martial's photo), a third on the MacBook.
        let left = window(1, CGRect(x: 0, y: 25, width: 1720, height: 1415))
        let right = window(2, CGRect(x: 1720, y: 25, width: 1720, height: 1415))
        let mac = window(3, CGRect(x: 938, y: 1480, width: 1728, height: 1077))
        let windows = [right, left, mac]
        suite.expect(pick(lgLeft, windows, recent: [2, 1, 3]) == 1, "the left half of the LG goes to the window filling it")
        suite.expect(pick(lgRight, windows, recent: [1, 2, 3]) == 2, "the right half goes to its own window, even used earlier")
        suite.expect(pick(macBook, windows, recent: [1, 2, 3]) == 3, "the MacBook goes to the window on it")

        // Two windows in the same zone: the most recently used wins, whatever the z-order.
        let small = window(4, CGRect(x: 100, y: 100, width: 800, height: 600))
        let other = window(5, CGRect(x: 950, y: 100, width: 700, height: 600))
        suite.expect(pick(lgLeft, [small, other], recent: [5, 4]) == 5, "the most recent window of a zone wins")
        suite.expect(pick(lgLeft, [small, other], recent: [4, 5]) == 4, "the order of use decides, not the z-order")
        suite.expect(pick(lgLeft, [small, other], recent: []) == 4, "without a history, the front window wins")
        suite.expect(pick(lgLeft, [small, other], recent: [99, 5]) == 5,
                     "a window the history knows comes before one it does not")

        suite.expect(pick(lgRight, [small, other], recent: [4, 5]) == nil, "an empty zone hands the keyboard to nobody")
        suite.expect(pick(lgRight, [], recent: [1]) == nil, "no window at all, no target")
        let flat = ForkGlanceZone(id: "z", displayUUID: "LG", rect: .zero, position: .whole)
        suite.expect(pick(flat, [small], recent: [4]) == nil, "a zone without area has no target")
    }

    // MARK: 40 % of the window, 50 % of the zone

    private static func shares(_ suite: TestSuite) {
        // 45 % of a 1000-wide window in the right half: it belongs there too.
        let straddling = window(1, CGRect(x: 1170, y: 100, width: 1000, height: 600))
        suite.expect(pick(lgRight, [straddling], recent: [1]) == 1, "45 % of the window in a zone is enough")
        suite.expect(pick(lgLeft, [straddling], recent: [1]) == 1, "and its other 55 % holds the left zone as well")

        // 30 % in the right half: not there.
        let mostlyLeft = window(2, CGRect(x: 1020, y: 100, width: 1000, height: 600))
        suite.expect(pick(lgRight, [mostlyLeft], recent: [2]) == nil, "30 % of a small window in a zone is not enough")

        // A window maximized over the whole LG: half of it in each half.
        let maximized = window(3, CGRect(x: 0, y: 25, width: 3440, height: 1415))
        suite.expect(pick(lgLeft, [maximized], recent: [3]) == 3 && pick(lgRight, [maximized], recent: [3]) == 3,
                     "a window maximized on the LG is the target of both halves")

        // A big window hanging off the LG: 24 % of it in the right zone, but 58 % of that zone.
        let big = window(4, CGRect(x: 1720, y: 600, width: 3000, height: 2000))
        let inZone = 1720.0 * 840.0
        suite.expect(inZone / (3000.0 * 2000.0) < 0.4 && inZone / (1720.0 * 1440.0) >= 0.5,
                     "the fixture sits between the two rules")
        suite.expect(pick(lgRight, [big], recent: [4]) == 4, "covering half the zone is enough even under 40 % of the window")

        // Exactly 40 %: kept.
        let edge = window(5, CGRect(x: 1320, y: 0, width: 1000, height: 100))
        suite.expect(pick(lgLeft, [edge], recent: [5]) == 5, "exactly 40 % of the window counts")
        let below = window(6, CGRect(x: 1330, y: 0, width: 1000, height: 100))
        suite.expect(pick(lgLeft, [below], recent: [6]) == nil, "39 % of a window does not")
    }

    // MARK: What the person sees

    private static func occlusion(_ suite: TestSuite) {
        // The most recent window hides behind a window maximized on the left half.
        let cover = window(1, CGRect(x: 0, y: 0, width: 1720, height: 1440))
        let hidden = window(2, CGRect(x: 200, y: 200, width: 800, height: 600))
        suite.expect(pick(lgLeft, [cover, hidden], recent: [2, 1]) == 1,
                     "a window entirely covered is not what the zone shows: the one in front wins")
        // Half covered (60 % visible): still the target.
        let partial = window(3, CGRect(x: 200, y: 200, width: 1000, height: 600))
        let front = window(4, CGRect(x: 800, y: 0, width: 400, height: 900))
        suite.expect(pick(lgLeft, [front, partial], recent: [3, 4]) == 3,
                     "a window with 60 % of it in sight keeps its zone")
        // A window on a hidden Space covers nothing.
        let ghost = window(5, CGRect(x: 0, y: 0, width: 1720, height: 1440), hidden: true)
        suite.expect(pick(lgLeft, [ghost, hidden], recent: [2]) == 2, "a window parked on a hidden Space hides nothing")
    }

    // MARK: Excluded apps, hidden Spaces

    private static func exclusions(_ suite: TestSuite) {
        let game = window(1, CGRect(x: 0, y: 0, width: 1720, height: 1440), pid: 1, bundle: "com.example.game")
        let notes = window(2, CGRect(x: 100, y: 100, width: 1400, height: 1200), pid: 2, bundle: "com.apple.Notes")
        suite.expect(pick(lgLeft, [notes, game], recent: [1, 2], never: ["com.example.game"]) == 2,
                     "an app of « Ne jamais activer » is skipped for the next window of the zone")
        let jetbrains = window(3, CGRect(x: 0, y: 0, width: 1720, height: 1440), pid: 3, bundle: "com.jetbrains.intellij")
        suite.expect(pick(lgLeft, [notes, jetbrains], recent: [3, 2], never: ["com.jetbrains."]) == 2,
                     "an entry ending with a dot excludes every app under that prefix")
        suite.expect(pick(lgLeft, [game], recent: [1], never: ["com.example.game"]) == nil,
                     "a zone holding only excluded apps has no target")

        let parked = window(4, CGRect(x: 0, y: 0, width: 1720, height: 1440), hidden: true)
        suite.expect(pick(lgLeft, [parked, notes], recent: [4, 2]) == 2, "a window on a hidden Space is never a target")
        suite.expect(pick(lgLeft, [parked], recent: [4]) == nil, "nor is the zone handed to it when it is alone")
        let noBundle = window(5, CGRect(x: 0, y: 0, width: 1720, height: 1440), bundle: nil)
        suite.expect(pick(lgLeft, [noBundle], recent: [5], never: ["com.example.game"]) == 5,
                     "a window without a bundle id is never taken for an excluded one")
    }

    // MARK: Screens mode

    private static func screensMode(_ suite: TestSuite) {
        // A window two thirds on the MacBook, a third on the LG, from the front app.
        let straddling = window(1, CGRect(x: 1000, y: 1000, width: 1000, height: 1320), pid: 7)
        let lgShare = 1000.0 * 440.0 / (1000.0 * 1320.0)
        suite.expect(lgShare < 0.4, "the fixture shows a third of the window on the LG")
        suite.expect(pick(lgScreen, [straddling], recent: [1], mode: .screens, front: 7) == 1,
                     "in Screens mode the front app's window there is the fallback")
        suite.expect(pick(lgScreen, [straddling], recent: [1], mode: .screens, front: 8) == nil,
                     "another app's sliver is no fallback")
        suite.expect(pick(lgScreen, [straddling], recent: [1], mode: .zones, front: 7) == nil,
                     "the fallback is Screens mode's alone")
        suite.expect(pick(lgScreen, [straddling], recent: [1], mode: .screens, front: nil) == nil,
                     "without a front app, no fallback")

        let onLG = window(2, CGRect(x: 100, y: 100, width: 800, height: 600), pid: 9)
        suite.expect(pick(lgScreen, [straddling, onLG], recent: [1, 2], mode: .screens, front: 7) == 2,
                     "a window that belongs to the screen comes before the front app's sliver")
        let excludedFront = window(3, CGRect(x: 1000, y: 1000, width: 1000, height: 1320), pid: 7, bundle: "com.example.game")
        suite.expect(pick(lgScreen, [excludedFront], recent: [3], mode: .screens, never: ["com.example.game"], front: 7) == nil,
                     "the fallback skips excluded apps too")
    }

    // MARK: Windows mode

    private static func windowsMode(_ suite: TestSuite) {
        let a = window(1, CGRect(x: 0, y: 0, width: 800, height: 800))
        let b = window(2, CGRect(x: 100, y: 100, width: 1500, height: 1200), bundle: "com.example.game")
        let zoneA = ForkGlanceZone(id: "win:1", displayUUID: "LG", rect: a.frame, position: .window, windowID: 1)
        let zoneB = ForkGlanceZone(id: "win:2", displayUUID: "LG", rect: CGRect(x: 800, y: 100, width: 800, height: 1200),
                                   position: .window, windowID: 2)
        suite.expect(pick(zoneA, [a, b], recent: [2, 1], mode: .windows) == 1, "a window's zone hands the keyboard to it")
        suite.expect(pick(zoneB, [a, b], recent: [1, 2], mode: .windows, never: ["com.example.game"]) == nil,
                     "an excluded window's zone hands it to nobody, not to a window under it")
        let gone = ForkGlanceZone(id: "win:9", displayUUID: "LG", rect: a.frame, position: .window, windowID: 9)
        suite.expect(pick(gone, [a, b], recent: [1], mode: .windows) == nil, "a window that closed is no target")
        let target = ForkGlanceTargeting.target(for: zoneA, mode: .windows, windows: [a], recent: [], neverFocus: [],
                                                frontmostPID: nil)
        suite.expect(target?.zoneID == "win:1", "the target names its zone")
    }

    // MARK: The zone of a window

    private static func zoneOfWindow(_ suite: TestSuite) {
        let zones = [lgLeft, lgRight, macBook]
        let left = window(1, CGRect(x: 0, y: 25, width: 1720, height: 1415))
        suite.expect(ForkGlanceTargeting.zone(of: left, in: zones)?.id == "LG#0", "a window lies in the zone it fills")
        let mostlyRight = window(2, CGRect(x: 1500, y: 100, width: 1000, height: 600))
        suite.expect(ForkGlanceTargeting.zone(of: mostlyRight, in: zones)?.id == "LG#1",
                     "a window across a border lies in the zone holding most of it")
        let mac = window(3, CGRect(x: 1000, y: 1300, width: 800, height: 900))
        suite.expect(ForkGlanceTargeting.zone(of: mac, in: zones)?.id == "BI#0", "a window mostly on the MacBook lies there")
        let maximized = window(4, CGRect(x: 0, y: 0, width: 3440, height: 1440))
        suite.expect(ForkGlanceTargeting.zone(of: maximized, in: zones)?.id == "LG#1",
                     "a tie goes to the zone holding the window's center")
        let offscreen = window(5, CGRect(x: 5000, y: 0, width: 400, height: 400))
        suite.expect(ForkGlanceTargeting.zone(of: offscreen, in: zones) == nil, "a window off every zone lies in none")
        let own = ForkGlanceZone(id: "win:5", displayUUID: "LG", rect: CGRect(x: 0, y: 0, width: 10, height: 10),
                                 position: .window, windowID: 5)
        suite.expect(ForkGlanceTargeting.zone(of: offscreen, in: zones + [own])?.id == "win:5",
                     "in Windows mode a window lies in its own zone")
    }

    // MARK: Pointer

    private static func pointer(_ suite: TestSuite) {
        let macWindow = ForkGlanceTarget(zoneID: "BI#0", window: window(1, CGRect(x: 938, y: 1440, width: 1728, height: 1117)))
        func destination(_ behavior: ForkGlancePointerBehavior, _ target: ForkGlanceTarget = macWindow,
                         on display: ForkGlanceDisplay = builtIn, remembered: CGPoint? = nil,
                         ffm: Bool = false) -> CGPoint? {
            ForkGlanceTargeting.pointerDestination(behavior: behavior, target: target, display: display,
                                                   remembered: remembered, focusFollowsMouse: ffm)
        }

        suite.expect(destination(.stay) == nil, "« stay » leaves the pointer alone")
        suite.expect(destination(.auto) == nil, "an unresolved « auto » is read as « stay »")

        let remembered = CGPoint(x: 1200, y: 2000)
        suite.expect(destination(.followScreen, remembered: remembered) == remembered,
                     "following the screen brings the pointer back where it last was on it")
        let inNotchBand = CGPoint(x: 1800, y: 1460)
        let fromBand = destination(.followScreen, remembered: inNotchBand)
        suite.expect(fromBand != nil && fromBand != inNotchBand, "a remembered point in the notch band is not reused")
        if let fromBand {
            suite.expect(fromBand.y >= 1440 + ForkGlanceTargeting.notchBand,
                         "the pointer never lands in the 40 pt under the top of a display with a notch")
        }
        let onOtherDisplay = CGPoint(x: 100, y: 100)
        suite.expect(destination(.followScreen, remembered: onOtherDisplay) != onOtherDisplay,
                     "a point remembered on another display is not reused")

        // The window fills the MacBook: its center, kept off the band and the edges.
        if let center = destination(.windowCenter) {
            let area = ForkGlanceTargeting.pointerArea(on: builtIn)
            suite.expect(area.contains(center), "the window's center lands inside the allowed area")
            suite.expectClose(Double(center.x), 938 + 1728 / 2, "the window's center, horizontally", tol: 0.5)
            suite.expect(center.y > 1440 + 40, "the window's center is pushed below the notch band")
        } else {
            suite.expect(false, "a window on the display has a center to go to")
        }

        // Corners and edges: a remembered point in a hot corner is not reused.
        let corner = CGPoint(x: 939, y: 2556)
        suite.expect(destination(.followScreen, remembered: corner) != corner, "the pointer never lands in a hot corner")
        let lgEdge = CGPoint(x: 3, y: 700)
        let lgTarget = ForkGlanceTarget(zoneID: "LG#0", window: window(2, CGRect(x: 0, y: 25, width: 1720, height: 1415)))
        let fromEdge = destination(.followScreen, lgTarget, on: lg, remembered: lgEdge)
        suite.expect(fromEdge != lgEdge, "nor on the edge a hidden Dock rises from")
        let lgTop = CGPoint(x: 900, y: 20)
        suite.expect(destination(.followScreen, lgTarget, on: lg, remembered: lgTop) == lgTop,
                     "a display without a notch keeps its top band for the pointer")

        // Focus follows the mouse: always inside the target window.
        let smallWindow = ForkGlanceTarget(zoneID: "BI#0", window: window(3, CGRect(x: 1000, y: 1600, width: 600, height: 400)))
        let ffmStay = destination(.stay, smallWindow, ffm: true)
        suite.expect(ffmStay.map(smallWindow.window.frame.contains) == true,
                     "with focus following the mouse, even « stay » puts the pointer in the target window")
        let outside = CGPoint(x: 2400, y: 2300)
        let ffmFollow = destination(.followScreen, smallWindow, remembered: outside, ffm: true)
        suite.expect(ffmFollow.map(smallWindow.window.frame.contains) == true,
                     "a remembered point outside the target window is not reused when focus follows the mouse")
        let inside = CGPoint(x: 1100, y: 1700)
        suite.expect(destination(.followScreen, smallWindow, remembered: inside, ffm: true) == inside,
                     "a remembered point inside the target window is")

        // A window entirely in the notch band (a thin strip) has nowhere allowed.
        let strip = ForkGlanceTarget(zoneID: "BI#0", window: window(4, CGRect(x: 1000, y: 1442, width: 600, height: 30)))
        suite.expect(destination(.windowCenter, strip) == nil, "no allowed point in the window, no move")
        suite.expect(destination(.followScreen, strip) != nil, "following the screen still finds the display's center")
        suite.expect(destination(.followScreen, strip, ffm: true) == nil,
                     "but not when the point must lie inside the window")
    }

    // MARK: Panes

    private static func panes(_ suite: TestSuite) {
        suite.expect(!ForkGlancePaneRules.allowsAccessibility(bundleID: "com.microsoft.VSCode"),
                     "VS Code's Accessibility is never asked: it would wake Chromium's for good")
        suite.expect(!ForkGlancePaneRules.allowsAccessibility(bundleID: "com.todesktop.230313mxl2d9e9y"),
                     "nor Cursor's")
        suite.expect(ForkGlancePaneRules.allowsAccessibility(bundleID: "com.googlecode.iterm2"), "iTerm2 is asked")
        suite.expect(ForkGlancePaneRules.allowsAccessibility(bundleID: nil), "an app without a bundle id is asked")
        suite.expect(ForkGlanceDefaults.defaultPanesApps.filter { !ForkGlancePaneRules.allowsAccessibility(bundleID: $0) }
                        .count == 3, "of the default pane apps, the three Electron editors are the ones left out")

        let windowFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let leftSplit = CGRect(x: 0, y: 30, width: 500, height: 770)
        suite.expect(ForkGlancePaneRules.clickPoint(pane: leftSplit, window: windowFrame) == CGPoint(x: 250, y: 415),
                     "the fallback clicks the center of the pane")
        suite.expect(ForkGlancePaneRules.clickPoint(pane: CGRect(x: 0, y: 20, width: 1000, height: 780), window: windowFrame) == nil,
                     "a pane that is the whole window is never clicked: the app draws its splits itself")
        suite.expect(ForkGlancePaneRules.clickPoint(pane: CGRect(x: 2000, y: 0, width: 100, height: 100), window: windowFrame) == nil,
                     "a pane outside the window is never clicked")
        suite.expect(ForkGlancePaneRules.clickPoint(pane: CGRect(x: 900, y: 0, width: 400, height: 400), window: windowFrame)
                        == CGPoint(x: 950, y: 200), "only the part of the pane inside the window counts")

        suite.expect(ForkGlancePaneRules.isSafeToClick(roles: ["AXStaticText", nil, "AXGroup"]), "text and groups are safe to click")
        suite.expect(!ForkGlancePaneRules.isSafeToClick(roles: ["AXImage", "AXButton"]), "never inside a button")
        suite.expect(!ForkGlancePaneRules.isSafeToClick(roles: ["AXLink"]), "never on a link")
        suite.expect(ForkGlancePaneRules.isSafeToClick(roles: []), "the pane itself is safe")
        suite.expect(!ForkGlancePaneRules.clickRoles.contains("AXGroup") && ForkGlancePaneRules.focusRoles.contains("AXGroup"),
                     "a group may take the focus but is never clicked")
    }

    // MARK: Geometry helpers

    private static func geometry(_ suite: TestSuite) {
        let a = CGRect(x: 0, y: 0, width: 10, height: 10)
        let b = CGRect(x: 5, y: 5, width: 10, height: 10)
        suite.expectClose(Double(ForkGlanceTargeting.unionArea([a, b])), 175, "two overlapping squares")
        suite.expectClose(Double(ForkGlanceTargeting.unionArea([a, a])), 100, "the same square twice")
        suite.expectClose(Double(ForkGlanceTargeting.unionArea([a, CGRect(x: 20, y: 0, width: 5, height: 5)])), 125,
                          "two apart")
        suite.expectClose(Double(ForkGlanceTargeting.unionArea([])), 0, "nothing")
        suite.expect(ForkGlanceTargeting.usageOrder([window(1, a), window(2, a), window(3, a)], recent: [3, 3, 1]) == [2, 0, 1],
                     "the use order keeps a repeated id's first place and files the unknown last")
    }
}
