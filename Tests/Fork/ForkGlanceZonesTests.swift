// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

/// Suite `fork-glance-zones` — A4: layout to zones in the three modes.
enum ForkGlanceZonesTests {
    static func run(_ suite: TestSuite) {
        defaultSplits(suite)
        zonesMode(suite)
        everySplit(suite)
        screensMode(suite)
        displays(suite)
        coordinates(suite)
        windowsMode(suite)
    }

    // MARK: Fixtures

    /// Plan, appendix A: the LG on top, the MacBook under it, centered-ish.
    static let lg = ForkGlanceDisplay(uuid: "LG-UUID", name: "LG HDR WQHD", frame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
                                      millimeters: CGSize(width: 816, height: 338))
    static let macBook = ForkGlanceDisplay(uuid: "BUILTIN-UUID", name: "Built-in Retina Display",
                                           frame: CGRect(x: 938, y: 1440, width: 1728, height: 1117),
                                           millimeters: CGSize(width: 344, height: 222), isBuiltIn: true, hasNotch: true)
    static let desk = ForkGlanceDisplayLayout(displays: [lg, macBook])

    private static func window(_ id: UInt32, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat,
                               hidden: Bool = false) -> ForkGlanceWindow {
        ForkGlanceWindow(id: id, pid: 100 + Int32(id), bundleID: "app.\(id)", appName: "App \(id)",
                         frame: CGRect(x: x, y: y, width: width, height: height), isOnHiddenSpace: hidden)
    }

    private static func windowZones(_ windows: [ForkGlanceWindow],
                                    layout: ForkGlanceDisplayLayout = desk) -> [ForkGlanceZone] {
        ForkGlanceZones.zones(layout: layout, mode: .windows, splits: [:], windows: windows)
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }

    private static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        [a.minX - b.minX, a.minY - b.minY, a.maxX - b.maxX, a.maxY - b.maxY].allSatisfy { abs($0) < 1e-9 }
    }

    // MARK: Splits

    private static func defaultSplits(_ suite: TestSuite) {
        suite.expect(ForkGlanceZones.defaultSplit(for: lg) == .columns2, "the 2.39 LG is cut in two by default")
        suite.expect(ForkGlanceZones.defaultSplit(for: macBook) == .whole, "the 16:10 MacBook stays whole by default")
        let exact = ForkGlanceDisplay(uuid: "A", name: "A", frame: CGRect(x: 0, y: 0, width: 2100, height: 1000))
        let under = ForkGlanceDisplay(uuid: "B", name: "B", frame: CGRect(x: 0, y: 0, width: 2099, height: 1000))
        let portrait = ForkGlanceDisplay(uuid: "C", name: "C", frame: CGRect(x: 0, y: 0, width: 1440, height: 3440))
        let empty = ForkGlanceDisplay(uuid: "D", name: "D", frame: .zero)
        suite.expect(ForkGlanceZones.defaultSplit(for: exact) == .columns2, "a ratio of exactly 2.1 is wide")
        suite.expect(ForkGlanceZones.defaultSplit(for: under) == .whole, "a ratio just under 2.1 is not")
        suite.expect(ForkGlanceZones.defaultSplit(for: portrait) == .whole, "a display turned upright stays whole")
        suite.expect(ForkGlanceZones.defaultSplit(for: empty) == .whole, "a display without a size stays whole")
        suite.expect(ForkGlanceZones.defaultSplits(desk) == ["LG-UUID": .columns2, "BUILTIN-UUID": .whole],
                     "the default splits are keyed by display uuid")
        for split in ForkGlanceSplit.allCases {
            let positions = ForkGlanceZones.positions(for: split)
            suite.expect(Set(positions).count == positions.count && !positions.contains(.window),
                         "\(split) names each of its zones once, never as a window")
        }
    }

    private static func zonesMode(_ suite: TestSuite) {
        let zones = ForkGlanceZones.zones(layout: desk, mode: .zones, splits: ForkGlanceZones.defaultSplits(desk),
                                          windows: [])
        suite.expect(zones.map(\.id) == ["LG-UUID#0", "LG-UUID#1", "BUILTIN-UUID#0"],
                     "appendix A gives LG#0, LG#1 and BuiltIn#0, in display order")
        suite.expect(zones.map(\.rect) == [CGRect(x: 0, y: 0, width: 1720, height: 1440),
                                           CGRect(x: 1720, y: 0, width: 1720, height: 1440),
                                           CGRect(x: 938, y: 1440, width: 1728, height: 1117)],
                     "the LG halves meet at x = 1720 and the MacBook keeps its whole frame")
        suite.expect(zones.map(\.position) == [.left, .right, .whole], "the zones are named left, right and whole")
        suite.expect(zones.map(\.displayUUID) == ["LG-UUID", "LG-UUID", "BUILTIN-UUID"],
                     "each zone knows its display")
        suite.expect(zones.allSatisfy { $0.windowID == nil }, "a split zone holds no window id")

        let missing = ForkGlanceZones.zones(layout: desk, mode: .zones, splits: ["BUILTIN-UUID": .rows2], windows: [])
        suite.expect(missing.filter { $0.displayUUID == "LG-UUID" }.map(\.position) == [.left, .right],
                     "a display without a split uses its default one")
        suite.expect(missing.filter { $0.displayUUID == "BUILTIN-UUID" }.map(\.position) == [.top, .bottom],
                     "a display with a split uses it")
        let stray = ForkGlanceZones.zones(layout: desk, mode: .zones, splits: ["GONE": .grid2x2], windows: [])
        suite.expect(stray.count == 3, "a split for a display that is not there is ignored")
        let windowsIgnored = ForkGlanceZones.zones(layout: desk, mode: .zones, splits: [:],
                                                   windows: [window(1, 0, 0, 800, 600)])
        suite.expect(windowsIgnored == zones, "windows do not change the Zones mode")
    }

    /// A display away from the origin, with a size that does not divide evenly.
    private static func everySplit(_ suite: TestSuite) {
        let left = ForkGlanceDisplay(uuid: "SIDE", name: "Side", frame: CGRect(x: -1921, y: 217, width: 1921, height: 1081))
        let layout = ForkGlanceDisplayLayout(displays: [left])
        for split in ForkGlanceSplit.allCases {
            let zones = ForkGlanceZones.zones(layout: layout, mode: .zones, splits: ["SIDE": split], windows: [])
            let positions = ForkGlanceZones.positions(for: split)
            suite.expect(zones.count == positions.count && zones.map(\.position) == positions,
                         "\(split) gives one zone per position, in order")
            suite.expect(zones.map(\.id) == positions.indices.map { "SIDE#\($0)" }, "\(split) numbers its zones from 0")
            let total = zones.reduce(CGFloat(0)) { $0 + area($1.rect) }
            suite.expectClose(Double(total), Double(area(left.frame)), "\(split) covers the display's area", tol: 0.01)
            let bounds = zones.reduce(CGRect.null) { $0.union($1.rect) }
            suite.expect(same(bounds, left.frame), "\(split) reaches every edge of the display")
            var overlaps = false
            for (i, a) in zones.enumerated() {
                for b in zones[(i + 1)...] where area(a.rect.intersection(b.rect)) > 0.001 { overlaps = true }
            }
            suite.expect(!overlaps, "\(split) zones never overlap")
        }
        let grid = ForkGlanceZones.zones(layout: layout, mode: .zones, splits: ["SIDE": .grid2x2], windows: [])
        let topLeft = grid.first { $0.position == .topLeft }?.rect, bottomRight = grid.first { $0.position == .bottomRight }?.rect
        suite.expect(topLeft?.minX == -1921 && topLeft?.minY == 217, "the top left zone starts at the display's top left")
        suite.expect(bottomRight?.maxX == 0 && bottomRight?.maxY == 1298,
                     "the bottom right zone ends at the display's bottom right (global y grows down)")
        let rows = ForkGlanceZones.zones(layout: layout, mode: .zones, splits: ["SIDE": .rows2], windows: [])
        suite.expect((rows.first?.rect.minY ?? 0) < (rows.last?.rect.minY ?? 0), "the top row comes first and is above")
        let thirds = ForkGlanceZones.zones(layout: layout, mode: .zones, splits: ["SIDE": .columns3], windows: [])
        suite.expect(zip(thirds, thirds.dropFirst()).allSatisfy { abs($0.rect.maxX - $1.rect.minX) < 1e-9 },
                     "three columns touch without a gap")
    }

    private static func screensMode(_ suite: TestSuite) {
        let zones = ForkGlanceZones.zones(layout: desk, mode: .screens, splits: ["LG-UUID": .grid2x2], windows: [])
        suite.expect(zones.map(\.id) == ["LG-UUID#0", "BUILTIN-UUID#0"], "the Screens mode makes one zone per display")
        suite.expect(zones.map(\.rect) == [lg.frame, macBook.frame], "each screen zone is its display's frame")
        suite.expect(zones.allSatisfy { $0.position == .whole }, "a screen zone is whole, whatever the split")
        suite.expect(ForkGlanceZones.screensModePossible(desk), "two displays allow the Screens mode")
        suite.expect(!ForkGlanceZones.screensModePossible(ForkGlanceDisplayLayout(displays: [macBook])),
                     "one display does not")
        suite.expect(!ForkGlanceZones.screensModePossible(ForkGlanceDisplayLayout(displays: [])), "nor does none")
    }

    // MARK: Displays

    private static func displays(_ suite: TestSuite) {
        suite.expect(ForkGlanceZones.display(containing: CGPoint(x: 100, y: 100), in: desk) == lg, "a point up left is on the LG")
        suite.expect(ForkGlanceZones.display(containing: CGPoint(x: 1000, y: 1500), in: desk) == macBook,
                     "a point under the LG's middle is on the MacBook")
        suite.expect(ForkGlanceZones.display(containing: CGPoint(x: 100, y: 1500), in: desk) == nil,
                     "a point under the LG beside the MacBook is on no display")
        suite.expect(ForkGlanceZones.display(containing: CGPoint(x: 1000, y: 1440), in: desk) == macBook,
                     "the shared edge belongs to the display below")
        suite.expect(ForkGlanceZones.display(containing: CGPoint(x: 3440, y: 10), in: desk) == nil,
                     "the LG's right edge is past it")

        let straddling = CGRect(x: 1000, y: 1300, width: 800, height: 600) // 140 on the LG, 460 on the MacBook
        suite.expect(ForkGlanceZones.displayShowingMost(of: straddling, in: desk) == macBook,
                     "a window mostly on the MacBook belongs to it")
        let mostlyUp = CGRect(x: 1000, y: 900, width: 800, height: 600)
        suite.expect(ForkGlanceZones.displayShowingMost(of: mostlyUp, in: desk) == lg, "one mostly on the LG belongs to it")
        suite.expect(ForkGlanceZones.displayShowingMost(of: CGRect(x: 0, y: 2000, width: 300, height: 300), in: desk) == nil,
                     "a rectangle on no display belongs to none")
        suite.expect(ForkGlanceZones.displayShowingMost(of: .null, in: desk) == nil
                         && ForkGlanceZones.displayShowingMost(of: CGRect(x: 10, y: 10, width: 0, height: 50), in: desk) == nil,
                     "an empty rectangle belongs to none")
    }

    /// Plan, appendix A: the MacBook is at y = 1440 globally and y = −1117 in Cocoa.
    private static func coordinates(_ suite: TestSuite) {
        let cocoa = CGRect(x: 938, y: -1117, width: 1728, height: 1117)
        let global = CGRect(x: 938, y: 1440, width: 1728, height: 1117)
        suite.expect(ForkGlanceZones.cocoaToGlobal(cocoa, mainHeight: 1440) == global,
                     "the MacBook's Cocoa frame becomes its CG frame")
        suite.expect(ForkGlanceZones.globalToCocoa(global, mainHeight: 1440) == cocoa,
                     "its CG frame becomes its Cocoa frame")
        suite.expect(ForkGlanceZones.cocoaToGlobal(lg.frame, mainHeight: 1440) == lg.frame,
                     "the main display's frame is the same in both spaces")
        let window = CGRect(x: 200, y: 100, width: 800, height: 600) // Cocoa: 100 above the LG's bottom
        suite.expect(ForkGlanceZones.cocoaToGlobal(window, mainHeight: 1440) == CGRect(x: 200, y: 740, width: 800, height: 600),
                     "a window near the LG's bottom is near y = 1440 − 100 − 600 globally")
        let odd = CGRect(x: -512.5, y: 333.25, width: 77, height: 1.5)
        suite.expect(ForkGlanceZones.globalToCocoa(ForkGlanceZones.cocoaToGlobal(odd, mainHeight: 1117), mainHeight: 1117) == odd,
                     "the flip back and forth gives the rectangle back")
    }

    // MARK: Windows

    private static func windowsMode(_ suite: TestSuite) {
        let alone = windowZones([window(7, 100, 100, 1200, 900)])
        suite.expect(alone == [ForkGlanceZone(id: "win:7", displayUUID: "LG-UUID",
                                              rect: CGRect(x: 100, y: 100, width: 1200, height: 900),
                                              position: .window, windowID: 7)],
                     "a lone window is one zone, its frame, named after its id")

        // Two windows side by side fill the LG's halves (the plan's photo).
        let halves = windowZones([window(1, 0, 25, 1720, 1415), window(2, 1720, 25, 1720, 1415)])
        suite.expect(halves.map(\.rect) == [CGRect(x: 0, y: 25, width: 1720, height: 1415),
                                            CGRect(x: 1720, y: 25, width: 1720, height: 1415)],
                     "two windows side by side are each their own zone")

        // The front window covers the back one's right half.
        let half = windowZones([window(1, 600, 0, 1000, 1000), window(2, 0, 0, 1200, 1000)])
        suite.expect(half.first { $0.windowID == 2 }?.rect == CGRect(x: 0, y: 0, width: 600, height: 1000),
                     "a window half covered keeps only its uncovered half")

        // The front window covers the back one's bottom right corner.
        let corner = windowZones([window(1, 800, 700, 800, 600), window(2, 0, 0, 1200, 900)])
        let back = corner.first { $0.windowID == 2 }?.rect ?? .null
        let front = corner.first { $0.windowID == 1 }?.rect ?? .null
        suite.expect(back == CGRect(x: 0, y: 0, width: 1200, height: 700),
                     "a window with a corner covered keeps its largest visible rectangle")
        suite.expect(area(back.intersection(front)) == 0, "it never overlaps the window over it")

        let covered = windowZones([window(1, 0, 0, 2000, 1400), window(2, 100, 100, 500, 500)])
        suite.expect(covered.map(\.windowID) == [1], "a window fully covered is no zone")

        let hidden = windowZones([window(1, 0, 0, 2000, 1400, hidden: true), window(2, 100, 100, 500, 500)])
        suite.expect(hidden.map(\.windowID) == [2], "a window on a hidden Space is no zone and covers nothing")

        let sliver = windowZones([window(1, 40, 0, 1000, 800), window(2, 0, 0, 1000, 800)])
        suite.expect(sliver.map(\.windowID) == [1], "a sliver thinner than the minimum side is no zone")

        let offScreen = windowZones([window(1, -3000, -3000, 500, 500), window(2, 0, 1600, 600, 400)])
        suite.expect(offScreen.isEmpty, "a window on no display is no zone")

        // Straddling: 140 pt high on the LG, 460 pt on the MacBook.
        let straddling = windowZones([window(3, 1000, 1300, 800, 600)])
        suite.expect(straddling.first?.displayUUID == "BUILTIN-UUID"
                         && straddling.first?.rect == CGRect(x: 1000, y: 1440, width: 800, height: 460),
                     "a window across two displays is a zone on the one showing most of it, cut to it")

        // Visible most on the LG once the MacBook part is covered.
        let coveredBelow = windowZones([window(4, 938, 1440, 1728, 1117), window(3, 1000, 1300, 800, 600)])
        suite.expect(coveredBelow.first { $0.windowID == 3 }?.displayUUID == "LG-UUID",
                     "the display is chosen by what is visible, not by the frame")

        // A busy desk: no two zones overlap and each lies inside its window and display.
        let busy = [window(1, 300, 200, 900, 700), window(2, 1000, 100, 1500, 900), window(3, 0, 0, 1720, 1440),
                    window(4, 1500, 1000, 1500, 800), window(5, 950, 1500, 900, 900), window(6, 1720, 0, 1720, 1440)]
        let zones = windowZones(busy)
        var overlaps = false
        for (i, a) in zones.enumerated() {
            for b in zones[(i + 1)...] where area(a.rect.intersection(b.rect)) > 0 { overlaps = true }
        }
        suite.expect(!overlaps, "the zones of overlapping windows never overlap")
        let inside = zones.allSatisfy { zone in
            guard let frame = busy.first(where: { $0.id == zone.windowID })?.frame,
                  let display = desk.displays.first(where: { $0.uuid == zone.displayUUID }) else { return false }
            return frame.contains(zone.rect) && display.frame.contains(zone.rect)
        }
        suite.expect(inside, "each zone lies inside its window and its display")
        let fronter = zones.allSatisfy { zone in
            let index = busy.firstIndex { $0.id == zone.windowID } ?? 0
            return busy[..<index].allSatisfy { area($0.frame.intersection(zone.rect)) == 0 }
        }
        suite.expect(fronter, "no window in front covers any part of a zone")
        suite.expect(zones.map(\.windowID) == zones.map(\.windowID).sorted { a, b in
            (busy.firstIndex { $0.id == a } ?? 0) < (busy.firstIndex { $0.id == b } ?? 0)
        }, "the zones come front to back, like the windows")

        let part = ForkGlanceZones.visiblePart(of: CGRect(x: 0, y: 0, width: 100, height: 100),
                                               within: CGRect(x: 0, y: 0, width: 1000, height: 1000),
                                               under: [CGRect(x: 50, y: 50, width: 100, height: 100)])
        suite.expectClose(Double(part?.area ?? 0), 7500, "an L-shaped visible part's area")
    }
}
