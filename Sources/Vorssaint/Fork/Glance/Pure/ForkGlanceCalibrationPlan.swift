// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

// Glance Focus: the assistant's pure rules (plan §8.4, §8.5). Where the
// calibration points go and in which order, how long each one lasts and when
// it is done again, how the validation lights the zones and scores them, and
// what the framing gauges read. Pure: the tests compile it (fork/test.sh);
// `Calibration/` draws it and feeds it the camera's samples.

// MARK: - Steps

/// The assistant's seven steps (plan §8.4); each way in shows some of them.
enum ForkGlanceAssistantStep: Int, Sendable, CaseIterable, Identifiable {
    case welcome
    case permissions
    case framing
    case layout
    case points
    case validation
    case done

    var id: Int { rawValue }
}

// MARK: - Points

/// What a calibration point is there for.
enum ForkGlanceCalibrationTargetKind: String, Sendable, Codable, Hashable {
    /// The 3×3 grid of a display (5×3 on an ultra-wide).
    case grid
    /// On a line between two zones of a display (Zones mode).
    case zoneBorder
    /// Along the edge two displays share, just inside the upper or left one.
    case displayBorder
}

/// One point the assistant lights, in plan order.
struct ForkGlanceCalibrationTarget: Sendable, Equatable, Hashable, Identifiable {
    /// The point's place in the plan, from 0.
    var id: Int
    /// Global points, origin at the top left of the main display.
    var point: CGPoint
    /// The display the point is drawn on.
    var displayUUID: String
    var kind: ForkGlanceCalibrationTargetKind
    /// Validation and quick recenter: the zone lit around the point.
    var zoneID: String?

    init(id: Int, point: CGPoint, displayUUID: String, kind: ForkGlanceCalibrationTargetKind, zoneID: String? = nil) {
        self.id = id
        self.point = point
        self.displayUUID = displayUUID
        self.kind = kind
        self.zoneID = zoneID
    }
}

enum ForkGlanceCalibrationPlan {
    // MARK: Timing (plan §8.4, step 5)

    /// The dot springs to the next point.
    static let travel: TimeInterval = 0.35
    /// The eyes land: samples are ignored while the ring tightens.
    static let settle: TimeInterval = 0.45
    /// Samples are kept while the arc fills.
    static let collect: TimeInterval = 0.9
    /// The ✓ and its fade, before the next point travels.
    static let confirm: TimeInterval = 0.25
    /// A point done again: the ring shakes, « Encore une fois ».
    static let shake: TimeInterval = 0.4
    /// A point needs this many samples with a face…
    static let minimumSamples = 8
    /// … and a yaw this steady (standard deviation, degrees), or it is done once more.
    static let maximumYawDeviation = 2.5
    /// How many times a bad point is done again before it is kept as it is.
    static let redoLimit = 1

    /// One point, from its travel to its ✓.
    static var pointDuration: TimeInterval { travel + settle + collect + confirm }

    /// How long a plan of `count` points takes without a redo.
    static func duration(points count: Int) -> TimeInterval { Double(max(0, count)) * pointDuration }

    // MARK: Geometry

    /// The grid's rows and columns, as a share of the display (10 / 50 / 90 %).
    static let gridFractions: [CGFloat] = [0.1, 0.5, 0.9]
    /// The columns of an ultra-wide's grid (ratio ≥ `ForkGlanceZones.wideRatio`).
    static let wideGridFractions: [CGFloat] = [0.1, 0.3, 0.5, 0.7, 0.9]
    /// Three points along each border.
    static let borderFractions: [CGFloat] = [0.25, 0.5, 0.75]
    /// A display border point sits this far inside the upper or left display:
    /// on the edge itself, half the dot would be off the display, or under
    /// the lower display's notch.
    static let displayBorderInset: CGFloat = 30
    /// A border point closer than this to a point already planned is dropped:
    /// the grid's middle column already lies on a two-column split's border.
    static let minimumSpacing: CGFloat = 60
    /// Two edges this close are shared (frames are rounded to whole points).
    static let edgeTolerance: CGFloat = 1

    /// The calibration points of a layout (plan §8.4, step 5): each display's
    /// grid, the borders between the zones of a display in Zones mode, and
    /// the borders between displays. In a serpent order: each display is swept
    /// line by line toward the next display, every line starting at the end
    /// closest to the last point, and one display hands over to the next
    /// through the border they share. Annex A's desk: 15 + 9 + 2 + 3 = 29 points.
    static func targets(layout: ForkGlanceDisplayLayout, mode: ForkGlanceMode,
                        splits: [String: ForkGlanceSplit]) -> [ForkGlanceCalibrationTarget] {
        let displays = layout.displays.filter { $0.frame.width > 0 && $0.frame.height > 0 }
        guard !displays.isEmpty else { return [] }

        var own: [String: [(CGPoint, ForkGlanceCalibrationTargetKind)]] = [:]
        for display in displays {
            var points = grid(display).map { ($0, ForkGlanceCalibrationTargetKind.grid) }
            if mode == .zones {
                let split = splits[display.uuid] ?? ForkGlanceZones.defaultSplit(for: display)
                for point in zoneBorderPoints(display, split: split) where isFree(point, among: points.map(\.0)) {
                    points.append((point, .zoneBorder))
                }
            }
            own[display.uuid] = points
        }

        var borders = displayBorders(displays)
        for index in borders.indices {
            let planned = own[borders[index].owner]?.map(\.0) ?? []
            borders[index].points = borders[index].points.filter { isFree($0, among: planned) }
        }

        let walk = displayWalk(displays, borders: borders)
        var ordered: [(CGPoint, String, ForkGlanceCalibrationTargetKind)] = []
        var used = Set<Int>()
        for (step, display) in walk.enumerated() {
            let next = step + 1 < walk.count ? walk[step + 1] : nil
            let previous = step > 0 ? walk[step - 1] : nil
            let direction = sweepDirection(display, previous: previous, next: next)
            let start = ordered.last?.0
            for point in serpent(own[display.uuid]?.map(\.0) ?? [], rows: direction.rows,
                                 forward: direction.forward, from: start) {
                let kind = own[display.uuid]?.first(where: { $0.0 == point })?.1 ?? .grid
                ordered.append((point, display.uuid, kind))
            }
            // The borders the walk does not cross, after their owner's points.
            for (index, border) in borders.enumerated() where !used.contains(index) && border.owner == display.uuid {
                let crossed = next.map { border.joins(display.uuid, $0.uuid) } ?? false
                guard !crossed, !walkCrosses(border, walk) else { continue }
                used.insert(index)
                ordered += line(border.points, from: ordered.last?.0).map { ($0, border.owner, .displayBorder) }
            }
            if let next, let index = borders.indices.first(where: { !used.contains($0) && borders[$0].joins(display.uuid, next.uuid) }) {
                used.insert(index)
                ordered += line(borders[index].points, from: ordered.last?.0).map { ($0, borders[index].owner, .displayBorder) }
            }
        }
        return ordered.enumerated().map { index, entry in
            ForkGlanceCalibrationTarget(id: index, point: entry.0, displayUUID: entry.1, kind: entry.2)
        }
    }

    /// « Recalage rapide » (plan §8.4): one point in the middle of each zone,
    /// nearest first from the top left.
    static func quickTargets(zones: [ForkGlanceZone]) -> [ForkGlanceCalibrationTarget] {
        var left = zones.filter { !$0.rect.isNull && !$0.rect.isEmpty }
        var ordered: [ForkGlanceZone] = []
        var last: CGPoint?
        while !left.isEmpty {
            let index: Int
            if let last {
                index = left.indices.min { distance(center(left[$0].rect), last)
                    < distance(center(left[$1].rect), last) } ?? 0
            } else {
                index = left.indices.min { (left[$0].rect.minY, left[$0].rect.minX) < (left[$1].rect.minY, left[$1].rect.minX) } ?? 0
            }
            let zone = left.remove(at: index)
            ordered.append(zone)
            last = center(zone.rect)
        }
        return ordered.enumerated().map { index, zone in
            ForkGlanceCalibrationTarget(id: index, point: center(zone.rect), displayUUID: zone.displayUUID,
                                        kind: .grid, zoneID: zone.id)
        }
    }

    /// « Refaire les points faibles »: the points that lie in a weak zone, or
    /// within `minimumSpacing` of it (its border points), in plan order.
    static func targets(_ targets: [ForkGlanceCalibrationTarget],
                        near weak: [ForkGlanceZone]) -> [ForkGlanceCalibrationTarget] {
        targets.filter { target in
            weak.contains { $0.rect.insetBy(dx: -minimumSpacing, dy: -minimumSpacing).contains(target.point) }
        }
    }

    // MARK: Quality (plan §8.4: « refait une fois »)

    enum Verdict: Sendable, Equatable {
        case good
        /// Fewer than `minimumSamples` samples with a face.
        case tooFewSamples
        /// The yaw moved more than `maximumYawDeviation`: the head was still turning.
        case unsteady
    }

    static func verdict(_ samples: [ForkGlanceSample]) -> Verdict {
        let yaws = usableYaws(samples)
        guard yaws.count >= minimumSamples else { return .tooFewSamples }
        let mean = yaws.reduce(0, +) / Double(yaws.count)
        let variance = yaws.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(yaws.count)
        return variance.squareRoot() * 180 / .pi > maximumYawDeviation ? .unsteady : .good
    }

    /// The samples a point keeps once it is done: those with a face.
    static func usable(_ samples: [ForkGlanceSample]) -> [ForkGlanceSample] {
        samples.filter { $0.facePresent && $0.vector.count > ForkGlanceVectorLayout.yaw
            && $0.vector[ForkGlanceVectorLayout.yaw].isFinite }
    }

    private static func usableYaws(_ samples: [ForkGlanceSample]) -> [Double] {
        usable(samples).map { $0.vector[ForkGlanceVectorLayout.yaw] }
    }

    // MARK: Helpers

    private static func grid(_ display: ForkGlanceDisplay) -> [CGPoint] {
        let frame = display.frame
        let wide = frame.width / frame.height >= ForkGlanceZones.wideRatio
        let columns = wide ? wideGridFractions : gridFractions
        return gridFractions.flatMap { row in
            columns.map { column in CGPoint(x: frame.minX + frame.width * column, y: frame.minY + frame.height * row) }
        }
    }

    /// Three points along each line that cuts a display into its zones.
    private static func zoneBorderPoints(_ display: ForkGlanceDisplay, split: ForkGlanceSplit) -> [CGPoint] {
        let frame = display.frame
        let verticals: [CGFloat], horizontals: [CGFloat]
        switch split {
        case .whole: verticals = []; horizontals = []
        case .columns2: verticals = [0.5]; horizontals = []
        case .columns3: verticals = [1.0 / 3, 2.0 / 3]; horizontals = []
        case .rows2: verticals = []; horizontals = [0.5]
        case .grid2x2: verticals = [0.5]; horizontals = [0.5]
        }
        var points: [CGPoint] = []
        for x in verticals {
            for along in borderFractions {
                points.append(CGPoint(x: frame.minX + frame.width * x, y: frame.minY + frame.height * along))
            }
        }
        for y in horizontals {
            for along in borderFractions {
                points.append(CGPoint(x: frame.minX + frame.width * along, y: frame.minY + frame.height * y))
            }
        }
        var kept: [CGPoint] = []
        for point in points where isFree(point, among: kept) { kept.append(point) }
        return kept
    }

    private static func isFree(_ point: CGPoint, among planned: [CGPoint]) -> Bool {
        planned.allSatisfy { distance($0, point) >= minimumSpacing }
    }

    private struct DisplayBorder {
        var first: String
        var second: String
        /// The upper or left display, where the points are drawn.
        var owner: String
        var points: [CGPoint]

        func joins(_ a: String, _ b: String) -> Bool { (first == a && second == b) || (first == b && second == a) }
    }

    /// Every edge two displays share, with its three points just inside the
    /// upper (or left) display.
    private static func displayBorders(_ displays: [ForkGlanceDisplay]) -> [DisplayBorder] {
        var borders: [DisplayBorder] = []
        for (index, a) in displays.enumerated() {
            for b in displays[(index + 1)...] {
                for (upper, lower) in [(a, b), (b, a)] {
                    if abs(upper.frame.maxY - lower.frame.minY) <= edgeTolerance {
                        let from = max(upper.frame.minX, lower.frame.minX), to = min(upper.frame.maxX, lower.frame.maxX)
                        guard to - from > 0 else { continue }
                        let y = upper.frame.maxY - displayBorderInset
                        borders.append(DisplayBorder(first: a.uuid, second: b.uuid, owner: upper.uuid,
                                                     points: borderFractions.map { CGPoint(x: from + (to - from) * $0, y: y) }))
                    }
                    if abs(upper.frame.maxX - lower.frame.minX) <= edgeTolerance {
                        let from = max(upper.frame.minY, lower.frame.minY), to = min(upper.frame.maxY, lower.frame.maxY)
                        guard to - from > 0 else { continue }
                        let x = upper.frame.maxX - displayBorderInset
                        borders.append(DisplayBorder(first: a.uuid, second: b.uuid, owner: upper.uuid,
                                                     points: borderFractions.map { CGPoint(x: x, y: from + (to - from) * $0) }))
                    }
                }
            }
        }
        return borders
    }

    /// The order the displays are visited in: from the top-left end of a
    /// chain, to a neighbor whenever there is one, else to the nearest.
    private static func displayWalk(_ displays: [ForkGlanceDisplay], borders: [DisplayBorder]) -> [ForkGlanceDisplay] {
        func neighbors(_ uuid: String) -> Set<String> {
            Set(borders.compactMap { $0.first == uuid ? $0.second : ($0.second == uuid ? $0.first : nil) })
        }
        func topLeft(_ a: ForkGlanceDisplay, _ b: ForkGlanceDisplay) -> Bool {
            (a.frame.minY, a.frame.minX) < (b.frame.minY, b.frame.minX)
        }
        let fewest = displays.map { neighbors($0.uuid).count }.min() ?? 0
        guard var current = displays.filter({ neighbors($0.uuid).count == fewest }).min(by: topLeft) else { return [] }
        var walk = [current]
        var left = displays.filter { $0.uuid != current.uuid }
        while !left.isEmpty {
            let adjacent = neighbors(current.uuid)
            let next = left.filter { adjacent.contains($0.uuid) }.min(by: topLeft)
                ?? left.min { distance(center($0.frame), center(current.frame)) < distance(center($1.frame), center(current.frame)) }!
            walk.append(next)
            left.removeAll { $0.uuid == next.uuid }
            current = next
        }
        return walk
    }

    private static func walkCrosses(_ border: DisplayBorder, _ walk: [ForkGlanceDisplay]) -> Bool {
        zip(walk, walk.dropFirst()).contains { border.joins($0.uuid, $1.uuid) }
    }

    /// Rows (top to bottom or back) when the next display is above or below,
    /// columns when it is beside; toward the next display, else away from
    /// the previous one.
    private static func sweepDirection(_ display: ForkGlanceDisplay, previous: ForkGlanceDisplay?,
                                       next: ForkGlanceDisplay?) -> (rows: Bool, forward: Bool) {
        let here = center(display.frame)
        let vector: CGVector
        if let next {
            let there = center(next.frame)
            vector = CGVector(dx: there.x - here.x, dy: there.y - here.y)
        } else if let previous {
            let there = center(previous.frame)
            vector = CGVector(dx: here.x - there.x, dy: here.y - there.y)
        } else {
            vector = CGVector(dx: 0, dy: 1)
        }
        if abs(vector.dy) >= abs(vector.dx) { return (true, vector.dy >= 0) }
        return (false, vector.dx >= 0)
    }

    /// The points line by line (rows or columns) in the sweep's direction,
    /// each line starting at the end closest to the point before it.
    private static func serpent(_ points: [CGPoint], rows: Bool, forward: Bool, from start: CGPoint?) -> [CGPoint] {
        func across(_ point: CGPoint) -> CGFloat { rows ? point.y : point.x }
        func along(_ point: CGPoint) -> CGFloat { rows ? point.x : point.y }
        var lines: [[CGPoint]] = []
        for point in points.sorted(by: { across($0) < across($1) }) {
            if let last = lines.last?.first, abs(across(last) - across(point)) <= edgeTolerance {
                lines[lines.count - 1].append(point)
            } else {
                lines.append([point])
            }
        }
        if !forward { lines.reverse() }
        var ordered: [CGPoint] = []
        var last = start
        for line in lines {
            let sorted = line.sorted { along($0) < along($1) }
            ordered += Self.line(sorted, from: last)
            last = ordered.last
        }
        return ordered
    }

    /// A line of points from the end closest to `start` (its own order without one).
    private static func line(_ points: [CGPoint], from start: CGPoint?) -> [CGPoint] {
        guard let start, let first = points.first, let last = points.last else { return points }
        return distance(last, start) < distance(first, start) ? points.reversed() : points
    }

    static func center(_ rect: CGRect) -> CGPoint { CGPoint(x: rect.midX, y: rect.midY) }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}

// MARK: - The run of points

/// One run of the assistant's points, timed by an injected clock: the
/// calibration, the weak points done again, the quick recenter, and the
/// validation's zones (which keep every attempt: `checksQuality` false).
///
/// A point travels, settles (samples ignored), collects, then confirms (✓)
/// and the next one travels. A point whose samples fail `Verdict` shakes
/// and settles again, once (`redoLimit`); failed again, it is kept with what
/// it has, or dropped when not one sample had a face. Space pauses (the
/// point starts its settle again on resume), ⌫ does the previous point again.
struct ForkGlanceCalibrationRun: Sendable, Equatable {
    enum Stage: Sendable, Equatable {
        case travel
        case settle
        case collect
        /// The point is done: `kept` false when it was dropped.
        case confirm(kept: Bool)
        /// The point failed its quality check: it is done again.
        case shake
    }

    /// What a step of the run tells the assistant.
    enum Event: Sendable, Equatable {
        /// `index` is done (kept or dropped); `done` points handled so far.
        case pointDone(index: Int, done: Int)
        /// `index` failed its check and is done once more (« Encore une fois »).
        case retry(index: Int, verdict: ForkGlanceCalibrationPlan.Verdict)
        case finished
    }

    let targets: [ForkGlanceCalibrationTarget]
    let checksQuality: Bool
    private(set) var index = 0
    private(set) var stage: Stage = .travel
    /// When `stage` began (the clock's seconds).
    private(set) var stageStart: TimeInterval
    private(set) var isPaused = false
    private(set) var isFinished = false
    /// The current point is a second attempt.
    private(set) var isRetry = false
    /// The samples kept for each target, nil until it is done (or dropped).
    private(set) var results: [[ForkGlanceSample]?]
    /// Each target's turn has passed, kept or dropped.
    private(set) var handled: [Bool]
    private var attempts = 0
    private var buffer: [ForkGlanceSample] = []

    init(targets: [ForkGlanceCalibrationTarget], checksQuality: Bool = true, now: TimeInterval) {
        self.targets = targets
        self.checksQuality = checksQuality
        stageStart = now
        results = Array(repeating: nil, count: targets.count)
        handled = Array(repeating: false, count: targets.count)
        isFinished = targets.isEmpty
    }

    var current: ForkGlanceCalibrationTarget? { isFinished ? nil : targets[index] }

    /// Points whose turn has passed (the island's « 12/30 »).
    var done: Int { handled.filter { $0 }.count }

    /// The kept points, with their targets, in plan order.
    var points: [(target: ForkGlanceCalibrationTarget, samples: [ForkGlanceSample])] {
        zip(targets, results).compactMap { target, samples in samples.map { (target, $0) } }
    }

    /// When `advance` next has something to do; nil while paused or finished.
    var nextDeadline: TimeInterval? {
        guard !isPaused, !isFinished else { return nil }
        return stageStart + duration(of: stage)
    }

    /// How far the current stage has gone, 0…1 (the dot's ring and arc).
    func progress(now: TimeInterval) -> Double {
        let length = duration(of: stage)
        guard length > 0, !isPaused else { return isPaused ? 0 : 1 }
        return min(1, max(0, (now - stageStart) / length))
    }

    /// A camera sample: kept only while collecting.
    mutating func add(_ sample: ForkGlanceSample, now: TimeInterval) {
        guard !isPaused, !isFinished, stage == .collect, now >= stageStart else { return }
        buffer.append(sample)
    }

    /// Moves through every stage whose time is up.
    mutating func advance(now: TimeInterval) -> [Event] {
        var events: [Event] = []
        while let deadline = nextDeadline, now >= deadline {
            events += step(at: deadline)
        }
        return events
    }

    mutating func pause(now: TimeInterval) {
        guard !isPaused, !isFinished else { return }
        isPaused = true
        stageStart = now
        buffer = []
    }

    /// The point settles again: the eyes may have left it.
    mutating func resume(now: TimeInterval) {
        guard isPaused else { return }
        isPaused = false
        if case .confirm = stage {
            // It was done: go on to the next one.
            stageStart = now
            return
        }
        stage = .settle
        stageStart = now
    }

    /// ⌫: the previous point again (the current one on the first point).
    mutating func back(now: TimeInterval) {
        guard !isFinished else { return }
        if case .confirm = stage {
            // The point just confirmed is the one to do again.
        } else if index > 0 {
            index -= 1
        }
        results[index] = nil
        handled[index] = false
        attempts = 0
        isRetry = false
        buffer = []
        stage = .travel
        stageStart = now
    }

    private func duration(of stage: Stage) -> TimeInterval {
        switch stage {
        case .travel: return ForkGlanceCalibrationPlan.travel
        case .settle: return ForkGlanceCalibrationPlan.settle
        case .collect: return ForkGlanceCalibrationPlan.collect
        case .confirm: return ForkGlanceCalibrationPlan.confirm
        case .shake: return ForkGlanceCalibrationPlan.shake
        }
    }

    private mutating func step(at time: TimeInterval) -> [Event] {
        stageStart = time
        switch stage {
        case .travel:
            stage = .settle
        case .shake:
            stage = .settle
        case .settle:
            buffer = []
            stage = .collect
        case .collect:
            let verdict = ForkGlanceCalibrationPlan.verdict(buffer)
            if checksQuality, verdict != .good, attempts < ForkGlanceCalibrationPlan.redoLimit {
                attempts += 1
                isRetry = true
                buffer = []
                stage = .shake
                return [.retry(index: index, verdict: verdict)]
            }
            let kept = checksQuality ? ForkGlanceCalibrationPlan.usable(buffer) : buffer
            results[index] = kept.isEmpty && checksQuality ? nil : kept
            handled[index] = true
            buffer = []
            stage = .confirm(kept: results[index] != nil)
            return [.pointDone(index: index, done: done)]
        case .confirm:
            // The next point not handled yet (⌫ may have left later ones handled).
            guard let next = handled.indices.first(where: { $0 > index && !handled[$0] }) else {
                isFinished = true
                return [.finished]
            }
            index = next
            attempts = 0
            isRetry = false
            stage = .travel
        }
        return []
    }
}

// MARK: - The dot (plan §8.5)

/// How the target dot looks at a moment of its stage: a pure function of the
/// stage and its progress, so the overlay and the renders draw the same.
struct ForkGlanceDotLook: Sendable, Equatable {
    /// The ring's diameter, points: 44 → 18 while settling.
    var ring: CGFloat
    /// The collect arc, 0…1.
    var arc: Double
    /// The shake's horizontal offset, points.
    var shake: CGFloat
    var check: Bool
    var opacity: Double

    static let dot: CGFloat = 14
    static let ringOpen: CGFloat = 44
    static let ringClosed: CGFloat = 18
    /// « 3 oscillations de 4 pt ».
    static let shakeAmplitude: CGFloat = 4
    static let shakeCount = 3.0

    /// `progress` is the stage's 0…1. Reduce Motion: the ring jumps, the arc
    /// stays, no shake, no fade.
    static func at(_ stage: ForkGlanceCalibrationRun.Stage, progress: Double, reduceMotion: Bool) -> ForkGlanceDotLook {
        let p = min(1, max(0, progress.isFinite ? progress : 0))
        switch stage {
        case .travel:
            return ForkGlanceDotLook(ring: ringOpen, arc: 0, shake: 0, check: false, opacity: 1)
        case .settle:
            let eased = 1 - pow(1 - p, 3)
            let ring = reduceMotion ? ringClosed : ringOpen - (ringOpen - ringClosed) * CGFloat(eased)
            return ForkGlanceDotLook(ring: ring, arc: 0, shake: 0, check: false, opacity: 1)
        case .collect:
            return ForkGlanceDotLook(ring: ringClosed, arc: p, shake: 0, check: false, opacity: 1)
        case .confirm(let kept):
            return ForkGlanceDotLook(ring: ringClosed, arc: kept ? 1 : 0, shake: 0, check: kept,
                                     opacity: reduceMotion ? 1 : 1 - p)
        case .shake:
            let offset = reduceMotion ? 0 : shakeAmplitude * CGFloat(sin(2 * .pi * shakeCount * p))
            return ForkGlanceDotLook(ring: ringOpen, arc: 0, shake: offset, check: false, opacity: 1)
        }
    }
}

// MARK: - Validation (plan §8.4, step 6)

/// A hint after the validation, aimed at what scored low.
enum ForkGlanceValidationAdvice: Sendable, Equatable, Hashable {
    /// A weak zone on a display above or below another: the head barely
    /// tilts between them (« La bascule vers le MacBook est fragile »).
    case stackedDisplay(displayUUID: String)
    /// Two weak zones side by side on one display: they blur together.
    case splitTooFine(displayUUID: String)
    /// Windows mode below « Bonne »: Zones will hold better.
    case windowsMode
    /// Below « Moyenne » overall: light, distance, then calibrate again.
    case lowOverall
    /// Everything « Excellente ».
    case excellent
}

enum ForkGlanceValidation {
    /// Each zone is lit this many times.
    static let rounds = 2
    /// « Refaire les points faibles » takes the zones under this (« Bonne »).
    static let weakBelow = 0.85

    /// Each zone `rounds` times, shuffled by `seed`, never the same zone
    /// twice in a row when there are two zones or more.
    static func trials(zones: [ForkGlanceZone], seed: UInt64) -> [ForkGlanceCalibrationTarget] {
        let usable = zones.filter { !$0.rect.isNull && !$0.rect.isEmpty }
        var order = (0..<rounds).flatMap { _ in usable }
        var generator = ForkGlanceSeededRandom(seed: seed)
        if order.count > 1 {
            for index in stride(from: order.count - 1, to: 0, by: -1) {
                let other = Int(generator.next() % UInt64(index + 1))
                order.swapAt(index, other)
            }
        }
        if usable.count > 1 {
            for index in 1..<order.count where order[index].id == order[index - 1].id {
                if let other = ((index + 1)..<order.count).first(where: { order[$0].id != order[index - 1].id }) {
                    order.swapAt(index, other)
                }
            }
            // The tail may still repeat: its last zone moves where it touches neither neighbor.
            let last = order.count - 1
            if last >= 2, order[last].id == order[last - 1].id {
                let id = order[last].id
                if let place = (0..<(last - 1)).first(where: { order[$0].id != id && ($0 == 0 || order[$0 - 1].id != id) }) {
                    order.insert(order.remove(at: last), at: place)
                }
            }
        }
        return order.enumerated().map { index, zone in
            ForkGlanceCalibrationTarget(id: index, point: ForkGlanceCalibrationPlan.center(zone.rect),
                                        displayUUID: zone.displayUUID, kind: .grid, zoneID: zone.id)
        }
    }

    /// Zone id → share of its estimates that fell in it, both rounds pooled.
    /// A zone lit without a single estimate (no face) scores 0.
    static func zoneAccuracy(trials: [ForkGlanceCalibrationTarget], estimates: [[CGPoint]],
                             zones: [ForkGlanceZone]) -> [String: Double] {
        var hits: [String: Int] = [:], counts: [String: Int] = [:]
        for zone in zones { hits[zone.id] = 0; counts[zone.id] = 0 }
        for (trial, points) in zip(trials, estimates) {
            guard let id = trial.zoneID, let zone = zones.first(where: { $0.id == id }) else { continue }
            counts[id, default: 0] += points.count
            hits[id, default: 0] += points.filter { zone.rect.contains($0) }.count
        }
        var accuracy: [String: Double] = [:]
        for (id, count) in counts where trials.contains(where: { $0.zoneID == id }) {
            accuracy[id] = count > 0 ? Double(hits[id] ?? 0) / Double(count) : 0
        }
        return accuracy
    }

    /// Every zone weighs the same.
    static func overall(_ accuracy: [String: Double]) -> Double {
        guard !accuracy.isEmpty else { return 0 }
        return accuracy.values.reduce(0, +) / Double(accuracy.count)
    }

    /// The zones under « Bonne », in `zones` order.
    static func weakZones(_ accuracy: [String: Double], zones: [ForkGlanceZone]) -> [ForkGlanceZone] {
        zones.filter { (accuracy[$0.id] ?? 1) < weakBelow }
    }

    /// At most one hint per display and kind, the most useful first.
    static func advice(_ accuracy: [String: Double], zones: [ForkGlanceZone], layout: ForkGlanceDisplayLayout,
                       mode: ForkGlanceMode) -> [ForkGlanceValidationAdvice] {
        let score = overall(accuracy)
        guard !accuracy.isEmpty else { return [] }
        if accuracy.values.allSatisfy({ ForkGlanceGrade(score: $0) == .excellent }) { return [.excellent] }
        var hints: [ForkGlanceValidationAdvice] = []
        let weak = weakZones(accuracy, zones: zones)
        for display in layout.displays where weak.contains(where: { $0.displayUUID == display.uuid }) {
            // Two weak zones side by side blur into each other: that, not the
            // other display, is what to fix first.
            let mine = weak.filter { $0.displayUUID == display.uuid }
            let touching = mine.contains { a in
                mine.contains { b in a.id != b.id && a.rect.insetBy(dx: -1, dy: -1).intersects(b.rect) }
            }
            let stacked = layout.displays.contains { other in
                other.uuid != display.uuid
                    && ForkGlanceCalibrationModel.stacked(ForkGlanceDisplayLayout(displays: [display, other]))
            }
            if touching {
                hints.append(.splitTooFine(displayUUID: display.uuid))
            } else if stacked {
                hints.append(.stackedDisplay(displayUUID: display.uuid))
            }
        }
        if mode == .windows, score < weakBelow { hints.append(.windowsMode) }
        if ForkGlanceGrade(score: score) == .poor { hints.append(.lowOverall) }
        return hints
    }
}

/// SplitMix64: the same order for the same seed on every Mac and every
/// Swift (the standard library's shuffle promises neither).
struct ForkGlanceSeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Framing (plan §8.4, step 3)

/// The four gauges of the framing step, read from one Vision observation.
enum ForkGlanceFraming {
    enum Gauge: String, Sendable, CaseIterable {
        case face
        case light
        case distance
        case facing
    }

    enum Reading: Sendable, Equatable {
        case good
        /// No face, too dark, too far, turned away.
        case low
        /// Several faces, too close.
        case high
    }

    /// The one hint shown under the gauges, the first problem first.
    enum Advice: Sendable, Equatable {
        case noFace
        case severalFaces
        case moreLight
        case closer
        case farther
        /// Turned away, or the face near the image's edge.
        case faceScreens
        case ready
    }

    struct Check: Sendable, Equatable {
        var face: Reading
        var light: Reading
        var distance: Reading
        var facing: Reading

        func reading(_ gauge: Gauge) -> Reading {
            switch gauge {
            case .face: return face
            case .light: return light
            case .distance: return distance
            case .facing: return facing
            }
        }

        var allGood: Bool { Gauge.allCases.allSatisfy { reading($0) == .good } }

        var advice: Advice {
            if face == .low { return .noFace }
            if face == .high { return .severalFaces }
            if light == .low { return .moreLight }
            if distance == .low { return .closer }
            if distance == .high { return .farther }
            if facing != .good { return .faceScreens }
            return .ready
        }

        static let empty = Check(face: .low, light: .low, distance: .low, facing: .low)
    }

    /// `VNDetectFaceCaptureQualityRequest` under this: too dark (or blurred).
    static let minimumQuality = 0.3
    /// Without the quality, the sample's confidence under this.
    static let minimumConfidence = 0.6
    /// The face's width over the image's: under, too far; over, too close.
    static let faceWidth: ClosedRange<CGFloat> = 0.15...0.5
    /// Yaw and pitch away from the camera, degrees: generous, the camera may
    /// sit under the displays (Annex A).
    static let maximumYaw = 25.0
    static let maximumPitch = 30.0
    /// The face's center stays in this part of the image.
    static let centered: ClosedRange<CGFloat> = 0.2...0.8
    /// The four gauges green this long before « Suivant ».
    static let hold: TimeInterval = 1
    /// No observation for this long: the face is gone.
    static let stale: TimeInterval = 1

    static func check(_ observation: ForkGlanceObservation?, sample: ForkGlanceSample?) -> Check {
        guard let observation, observation.faceCount > 0, !observation.faceBox.isEmpty,
              sample?.facePresent ?? true else { return .empty }
        let face: Reading = observation.otherFaceRatio > ForkGlanceClassifier.crowdedRatio ? .high : .good
        let light: Reading
        if let quality = observation.captureQuality {
            light = quality >= minimumQuality ? .good : .low
        } else {
            light = (sample?.confidence ?? 1) >= minimumConfidence ? .good : .low
        }
        let width = observation.faceBox.width
        let distance: Reading = width < faceWidth.lowerBound ? .low : (width > faceWidth.upperBound ? .high : .good)
        let degrees = 180 / Double.pi
        let turned = (observation.yaw.map { abs($0 * degrees) > maximumYaw } ?? false)
            || (observation.pitch.map { abs($0 * degrees) > maximumPitch } ?? false)
        let box = observation.faceBox
        let offCenter = !centered.contains(box.midX) || !centered.contains(box.midY)
        return Check(face: face, light: light, distance: distance, facing: turned || offCenter ? .low : .good)
    }

    /// Whether the gauges stayed green for `hold`.
    struct Hold: Sendable, Equatable {
        private(set) var since: TimeInterval?

        init() {}

        mutating func update(_ allGood: Bool, now: TimeInterval) {
            if !allGood { since = nil } else if since == nil { since = now }
        }

        func isReady(now: TimeInterval) -> Bool {
            guard let since else { return false }
            return now - since >= ForkGlanceFraming.hold
        }
    }
}
