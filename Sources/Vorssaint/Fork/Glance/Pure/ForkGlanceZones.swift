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

    /// The fixed split a display falls back to when nothing else is known:
    /// no split in the map, or a window split no window was read for (the
    /// island's preview, a test).
    static func defaultSplit(for display: ForkGlanceDisplay) -> ForkGlanceSplit {
        let size = display.frame.size
        guard size.width > 0, size.height > 0 else { return .whole }
        return size.width / size.height >= wideRatio ? .columns2 : .whole
    }

    /// Display uuid → its split in a new profile: each display follows its
    /// windows (« Selon mes fenêtres »). A profile stored before keeps its own.
    static func defaultSplits(_ layout: ForkGlanceDisplayLayout) -> [String: ForkGlanceSplit] {
        var splits: [String: ForkGlanceSplit] = [:]
        for display in layout.displays { splits[display.uuid] = .windows }
        return splits
    }

    /// The positions of a split's zones, in zone index order: left to right,
    /// then top to bottom. A window split has the positions of the split it
    /// resolves to; unresolved, it is drawn whole here.
    static func positions(for split: ForkGlanceSplit) -> [ForkGlancePosition] {
        switch split {
        case .whole, .windows: return [.whole]
        case .columns2: return [.left, .right]
        case .columns3: return [.left, .center, .right]
        case .rows2: return [.top, .bottom]
        case .grid2x2: return [.topLeft, .topRight, .bottomLeft, .bottomRight]
        }
    }

    /// Columns and rows of a split.
    private static func grid(_ split: ForkGlanceSplit) -> (columns: Int, rows: Int) {
        switch split {
        case .whole, .windows: return (1, 1)
        case .columns2: return (2, 1)
        case .columns3: return (3, 1)
        case .rows2: return (1, 2)
        case .grid2x2: return (2, 2)
        }
    }

    // MARK: - Zones

    /// Screens: one zone per display. Zones: each display cut by its split
    /// (its default one when `splits` has none; a window split is resolved
    /// beforehand with `resolving(_:with:)`, else it falls back to the
    /// default one too). Windows: the visible part of
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
    private static func splitZones(_ display: ForkGlanceDisplay, split chosen: ForkGlanceSplit) -> [ForkGlanceZone] {
        let split = chosen == .windows ? defaultSplit(for: display) : chosen
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

    // MARK: - Window split (« Selon mes fenêtres »)

    /// The splits a window split resolves to, the coarsest first: a finer
    /// one wins only when it explains clearly more of the display.
    static let fixedSplits: [ForkGlanceSplit] = [.whole, .columns2, .rows2, .columns3, .grid2x2]

    /// A window takes a split's cell when their intersection over union
    /// reaches this. A half and a two-thirds overlap at 0.75 at best, a third
    /// and a half at 0.67, so no window fits both; Swish's gaps (10 pt on
    /// each side of a 1 512 pt half: 0.97) and a half spilling past the
    /// middle for its minimum width (`Gestures/ForkLayoutComplement`, up to
    /// about 8 % of the display) still fit.
    static let windowFit: CGFloat = 0.78
    /// A window showing less than this share of the usable area says nothing
    /// about the split: a sliver left between two others, a small panel.
    static let windowEvidenceShare: CGFloat = 0.04
    /// A finer split must explain this share of the usable area more than
    /// the coarser one in force: two side by side halves stay 2 columns,
    /// never a 2×2 grid that explains them as well.
    static let windowSplitMargin: CGFloat = 0.03
    /// Only a display's front windows count, which also bounds the cost.
    static let windowEvidenceLimit = 12

    /// One window seen on a display, in global points.
    struct WindowEvidence: Sendable, Equatable {
        /// The window's frame within the usable area.
        var frame: CGRect
        /// Its largest visible rectangle: a maximized window behind a left
        /// half shows as the right half.
        var visible: CGRect
        /// Its visible area, the weight of its vote.
        var area: CGFloat
    }

    /// Display uuid → the fixed split its windows draw. `windows` front to
    /// back (layer 0, the app's own left out by the caller), on every
    /// display: a window belongs to the display showing most of it, and
    /// hides what is under it wherever it is. `usable` is each display's
    /// visible frame (no menu bar, no Dock), its frame when missing.
    static func deducedSplits(layout: ForkGlanceDisplayLayout, windows: [ForkGlanceWindow],
                              usable: [String: CGRect] = [:]) -> [String: ForkGlanceSplit] {
        let shown = windows.filter { !$0.isOnHiddenSpace && !$0.frame.isNull && !$0.frame.isEmpty }
        let owners = shown.map { displayShowingMost(of: $0.frame, in: layout)?.uuid }
        var splits: [String: ForkGlanceSplit] = [:]
        for display in layout.displays {
            let area = usableArea(display, usable[display.uuid])
            var evidence: [WindowEvidence] = []
            var above: [CGRect] = []
            for (index, window) in shown.enumerated() {
                defer { above.append(window.frame) }
                guard owners[index] == display.uuid, evidence.count < windowEvidenceLimit,
                      let part = visiblePart(of: window.frame, within: area, under: above) else { continue }
                evidence.append(WindowEvidence(frame: window.frame.intersection(area), visible: part.largest,
                                               area: part.area))
            }
            splits[display.uuid] = split(for: evidence, usable: area)
        }
        return splits
    }

    /// The fixed split that explains the most visible window area, each
    /// window counting when its frame or its visible part fits one of the
    /// split's cells (`cells(of:)`, `windowFit`); a finer split must beat the
    /// coarser one by `windowSplitMargin`. Nothing recognizable: whole.
    static func split(for evidence: [WindowEvidence], usable: CGRect) -> ForkGlanceSplit {
        let total = usable.width * usable.height
        guard total > 0 else { return .whole }
        let counted = evidence.filter { item in
            item.area >= windowEvidenceShare * total
                && item.visible.width >= minimumWindowSide && item.visible.height >= minimumWindowSide
        }
        var best = ForkGlanceSplit.whole
        var bestScore = score(.whole, counted, usable: usable)
        for split in fixedSplits.dropFirst() {
            let score = score(split, counted, usable: usable)
            if score > bestScore + windowSplitMargin * total {
                best = split
                bestScore = score
            }
        }
        return best
    }

    /// The shapes a window may take under a split, as fractions of the
    /// usable area (y down): its zones, and the unions of zones the window
    /// tools place (two thirds; a half beside two quarters in a 2×2 grid).
    static func cells(of split: ForkGlanceSplit) -> [CGRect] {
        let third: CGFloat = 1.0 / 3
        func cell(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect {
            CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        }
        let halves = [cell(0, 0, 0.5, 1), cell(0.5, 0, 1, 1)]
        let rows = [cell(0, 0, 1, 0.5), cell(0, 0.5, 1, 1)]
        switch split {
        case .whole:
            return [cell(0, 0, 1, 1)]
        case .columns2:
            return halves
        case .rows2:
            return rows
        case .columns3:
            return [cell(0, 0, third, 1), cell(third, 0, 2 * third, 1), cell(2 * third, 0, 1, 1),
                    cell(0, 0, 2 * third, 1), cell(third, 0, 1, 1)]
        case .grid2x2:
            return [cell(0, 0, 0.5, 0.5), cell(0.5, 0, 1, 0.5), cell(0, 0.5, 0.5, 1), cell(0.5, 0.5, 1, 1)]
                + halves + rows
        case .windows:
            return []
        }
    }

    /// `splits` with each window split replaced by the split its windows
    /// draw (`deduced`, from `deducedSplits`); one not deduced stays as it is.
    static func resolving(_ splits: [String: ForkGlanceSplit],
                          with deduced: [String: ForkGlanceSplit]) -> [String: ForkGlanceSplit] {
        var resolved = splits
        for (uuid, split) in splits where split == .windows {
            if let fixed = deduced[uuid], fixed != .windows { resolved[uuid] = fixed }
        }
        return resolved
    }

    /// The zone that takes over `zone` once its display's split changed: the
    /// one on the same display it overlaps most. Nil when none is left there.
    static func successor(of zone: ForkGlanceZone, in zones: [ForkGlanceZone]) -> ForkGlanceZone? {
        var best: (zone: ForkGlanceZone, area: CGFloat)?
        for candidate in zones where candidate.displayUUID == zone.displayUUID {
            let overlap = candidate.rect.intersection(zone.rect)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > (best?.area ?? -1) { best = (candidate, area) }
        }
        return best?.zone
    }

    private static func usableArea(_ display: ForkGlanceDisplay, _ usable: CGRect?) -> CGRect {
        guard let usable else { return display.frame }
        let inside = usable.intersection(display.frame)
        return inside.isNull || inside.width <= 0 || inside.height <= 0 ? display.frame : inside
    }

    /// The visible area of the windows that fit one of `split`'s cells.
    private static func score(_ split: ForkGlanceSplit, _ evidence: [WindowEvidence], usable: CGRect) -> CGFloat {
        let cells = cells(of: split).map { cell in
            CGRect(x: usable.minX + cell.minX * usable.width, y: usable.minY + cell.minY * usable.height,
                   width: cell.width * usable.width, height: cell.height * usable.height)
        }
        var score: CGFloat = 0
        for item in evidence where cells.contains(where: { fits(item.frame, $0) || fits(item.visible, $0) }) {
            score += item.area
        }
        return score
    }

    private static func fits(_ rect: CGRect, _ cell: CGRect) -> Bool {
        let overlap = rect.intersection(cell)
        guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { return false }
        let shared = overlap.width * overlap.height
        let union = rect.width * rect.height + cell.width * cell.height - shared
        return union > 0 && shared / union >= windowFit
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

/// Window split: the split in force for each display, held back until the
/// windows have drawn the same one for `settle` seconds with no mouse button
/// down, so a window being dragged or a Swish gesture under way never cuts
/// the display anew. The service reads it at each look at the window server.
struct ForkGlanceWindowSplitWatch: Sendable, Equatable {
    static let settle: TimeInterval = 1

    /// Display uuid → the deduced split in force; nil before the first reading.
    private(set) var applied: [String: ForkGlanceSplit]?
    private var pending: [String: ForkGlanceSplit]?
    private var since: TimeInterval = 0

    /// One reading of the windows; true when `applied` changed. The first
    /// reading is taken at once: there is nothing to hold back yet.
    mutating func observe(_ deduced: [String: ForkGlanceSplit], buttonsDown: Bool, now: TimeInterval) -> Bool {
        guard let current = applied else {
            applied = deduced
            return true
        }
        guard deduced != current else {
            pending = nil
            return false
        }
        if deduced != pending || buttonsDown {
            pending = deduced
            since = now
            return false
        }
        guard now - since >= Self.settle else { return false }
        applied = deduced
        pending = nil
        return true
    }

    /// Taken at once, when nothing follows the windows (a one-off reading).
    mutating func take(_ deduced: [String: ForkGlanceSplit]) -> Bool {
        pending = nil
        guard applied != deduced else { return false }
        applied = deduced
        return true
    }

    /// Following stops: the next reading is taken at once.
    mutating func reset() {
        applied = nil
        pending = nil
    }
}
