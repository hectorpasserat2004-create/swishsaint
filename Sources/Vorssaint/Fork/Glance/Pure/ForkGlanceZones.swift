// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

/// Glance Focus: the display layout cut into the zones the gaze picks from
/// (plan §5.1–§5.3), and the geometry around it. Pure: everything is in global
/// points with the origin at the top left of the main display, like
/// `CGDisplayBounds` and Accessibility; `cocoaToGlobal` is the one way in from
/// AppKit's bottom-left space.
enum ForkGlanceZones {
    /// A width over height from which a display is cut in two by default: an
    /// ultra-wide (21:9 is 2.33, the LG 34" 2.39) has two places to look at,
    /// a 16:10 or 16:9 one has one.
    static let wideRatio: CGFloat = 2.1

    /// Windows mode: a visible part thinner than this on either side is no
    /// zone. A sliver left between two windows is too narrow to look at on
    /// purpose, and would only make the classifier hesitate.
    static let minimumWindowSide: CGFloat = 48

    // MARK: - Splits

    static func defaultSplit(for display: ForkGlanceDisplay) -> ForkGlanceSplit {
        let size = display.frame.size
        guard size.width > 0, size.height > 0 else { return .whole }
        return size.width / size.height >= wideRatio ? .columns2 : .whole
    }

    /// Display uuid → its default split, for a new profile.
    static func defaultSplits(_ layout: ForkGlanceDisplayLayout) -> [String: ForkGlanceSplit] {
        var splits: [String: ForkGlanceSplit] = [:]
        for display in layout.displays { splits[display.uuid] = defaultSplit(for: display) }
        return splits
    }

    /// The positions of a split's zones, in zone index order: left to right,
    /// then top to bottom.
    static func positions(for split: ForkGlanceSplit) -> [ForkGlancePosition] {
        switch split {
        case .whole: return [.whole]
        case .columns2: return [.left, .right]
        case .columns3: return [.left, .center, .right]
        case .rows2: return [.top, .bottom]
        case .grid2x2: return [.topLeft, .topRight, .bottomLeft, .bottomRight]
        }
    }

    /// Columns and rows of a split.
    private static func grid(_ split: ForkGlanceSplit) -> (columns: Int, rows: Int) {
        switch split {
        case .whole: return (1, 1)
        case .columns2: return (2, 1)
        case .columns3: return (3, 1)
        case .rows2: return (1, 2)
        case .grid2x2: return (2, 2)
        }
    }

    // MARK: - Zones

    /// Screens: one zone per display. Zones: each display cut by its split
    /// (its default one when `splits` has none). Windows: the visible part of
    /// each window, `windows` front to back and already filtered to layer 0;
    /// a covered window keeps only what is left of it, a hidden one neither
    /// counts nor covers.
    static func zones(layout: ForkGlanceDisplayLayout, mode: ForkGlanceMode, splits: [String: ForkGlanceSplit],
                      windows: [ForkGlanceWindow]) -> [ForkGlanceZone] {
        switch mode {
        case .screens:
            return layout.displays.map { display in
                ForkGlanceZone(id: zoneID(display, 0), displayUUID: display.uuid, rect: display.frame,
                               position: .whole)
            }
        case .zones:
            return layout.displays.flatMap { display in
                splitZones(display, split: splits[display.uuid] ?? defaultSplit(for: display))
            }
        case .windows:
            return windowZones(layout: layout, windows: windows)
        }
    }

    /// The Screens mode needs two displays at least: with one, the machine
    /// pauses with `singleScreen`.
    static func screensModePossible(_ layout: ForkGlanceDisplayLayout) -> Bool {
        layout.displays.count >= 2
    }

    private static func zoneID(_ display: ForkGlanceDisplay, _ index: Int) -> String { "\(display.uuid)#\(index)" }

    /// Edges are computed from the display's own, so the zones of a split
    /// tile it exactly, with neither gap nor overlap.
    private static func splitZones(_ display: ForkGlanceDisplay, split: ForkGlanceSplit) -> [ForkGlanceZone] {
        let frame = display.frame
        let (columns, rows) = grid(split)
        let positions = positions(for: split)
        func edge(_ start: CGFloat, _ length: CGFloat, _ index: Int, _ count: Int) -> CGFloat {
            index == count ? start + length : start + length * CGFloat(index) / CGFloat(count)
        }
        var zones: [ForkGlanceZone] = []
        for row in 0..<rows {
            for column in 0..<columns {
                let index = row * columns + column
                let minX = edge(frame.minX, frame.width, column, columns)
                let maxX = edge(frame.minX, frame.width, column + 1, columns)
                let minY = edge(frame.minY, frame.height, row, rows)
                let maxY = edge(frame.minY, frame.height, row + 1, rows)
                zones.append(ForkGlanceZone(id: zoneID(display, index), displayUUID: display.uuid,
                                            rect: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
                                            position: positions[index]))
            }
        }
        return zones
    }

    // MARK: - Windows mode

    /// One zone per window that shows enough of itself. Its display is the
    /// one where most of it is visible, and its rectangle the largest one
    /// fully visible there: an L-shaped part left by a window over a corner
    /// gives its larger arm, so no two zones ever overlap and a point in a
    /// window's visible part never lands in a window behind it.
    private static func windowZones(layout: ForkGlanceDisplayLayout,
                                    windows: [ForkGlanceWindow]) -> [ForkGlanceZone] {
        let shown = windows.filter { !$0.isOnHiddenSpace && !$0.frame.isNull && !$0.frame.isEmpty }
        var zones: [ForkGlanceZone] = []
        for (index, window) in shown.enumerated() {
            let above = shown[..<index].map(\.frame)
            var best: (display: ForkGlanceDisplay, area: CGFloat, rect: CGRect)?
            for display in layout.displays {
                guard let part = visiblePart(of: window.frame, within: display.frame, under: above),
                      part.area > (best?.area ?? 0) else { continue }
                best = (display, part.area, part.largest)
            }
            guard let best, best.rect.width >= minimumWindowSide, best.rect.height >= minimumWindowSide else {
                continue
            }
            zones.append(ForkGlanceZone(id: "win:\(window.id)", displayUUID: best.display.uuid, rect: best.rect,
                                        position: .window, windowID: window.id))
        }
        return zones
    }

    /// What `frame` shows inside `bounds` once `above` is drawn over it: its
    /// visible area and the largest visible rectangle. Nil when nothing shows.
    ///
    /// The plane is cut along every edge into a grid of cells, each either
    /// fully covered or fully visible; the largest rectangle is then the
    /// classic largest rectangle of visible cells, row by row over column
    /// heights. A few dozen windows make a grid of a few thousand cells.
    static func visiblePart(of frame: CGRect, within bounds: CGRect,
                            under above: [CGRect]) -> (area: CGFloat, largest: CGRect)? {
        let clip = frame.intersection(bounds)
        guard !clip.isNull, clip.width > 0, clip.height > 0 else { return nil }
        let covers = above.map { $0.intersection(clip) }.filter { !$0.isNull && $0.width > 0 && $0.height > 0 }
        if covers.isEmpty { return (clip.width * clip.height, clip) }

        let xs = Array(Set([clip.minX, clip.maxX] + covers.flatMap { [$0.minX, $0.maxX] })).sorted()
        let ys = Array(Set([clip.minY, clip.maxY] + covers.flatMap { [$0.minY, $0.maxY] })).sorted()
        let columns = xs.count - 1
        var heights = [CGFloat](repeating: 0, count: columns)
        var area: CGFloat = 0
        var largest = CGRect.null
        var largestArea: CGFloat = 0
        for row in 0..<(ys.count - 1) {
            let top = ys[row], bottom = ys[row + 1]
            let middleY = (top + bottom) / 2
            for column in 0..<columns {
                let middle = CGPoint(x: (xs[column] + xs[column + 1]) / 2, y: middleY)
                if covers.contains(where: { $0.contains(middle) }) {
                    heights[column] = 0
                } else {
                    heights[column] += bottom - top
                    area += (xs[column + 1] - xs[column]) * (bottom - top)
                }
            }
            // The rectangles whose bottom edge is this row's.
            for first in 0..<columns where heights[first] > 0 {
                var height = CGFloat.greatestFiniteMagnitude
                for last in first..<columns {
                    height = min(height, heights[last])
                    guard height > 0 else { break }
                    let width = xs[last + 1] - xs[first]
                    if width * height > largestArea {
                        largestArea = width * height
                        largest = CGRect(x: xs[first], y: bottom - height, width: width, height: height)
                    }
                }
            }
        }
        return area > 0 ? (area, largest) : nil
    }

    // MARK: - Displays

    /// The display under a point. Frames are half-open, so a point on the
    /// edge two displays share belongs to the one below or to the right.
    static func display(containing point: CGPoint, in layout: ForkGlanceDisplayLayout) -> ForkGlanceDisplay? {
        layout.displays.first { $0.frame.contains(point) }
    }

    /// The display holding the larger part of a rectangle (a window
    /// straddling two displays belongs to it), like the switcher's
    /// `SwitcherSupport.displayIndex(showingMostOf:)`. Nil when it touches none.
    static func displayShowingMost(of rect: CGRect, in layout: ForkGlanceDisplayLayout) -> ForkGlanceDisplay? {
        guard !rect.isNull, !rect.isEmpty else { return nil }
        var best: (display: ForkGlanceDisplay, area: CGFloat)?
        for display in layout.displays {
            let overlap = display.frame.intersection(rect)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            guard area > 0, area > (best?.area ?? 0) else { continue }
            best = (display, area)
        }
        return best?.display
    }

    // MARK: - Coordinates

    /// AppKit's space (origin at the bottom left of the main display, y up)
    /// to the global one (top left, y down). `mainHeight` is the main
    /// display's height, the line both spaces share.
    static func cocoaToGlobal(_ rect: CGRect, mainHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The same flip, back: it is its own inverse.
    static func globalToCocoa(_ rect: CGRect, mainHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
