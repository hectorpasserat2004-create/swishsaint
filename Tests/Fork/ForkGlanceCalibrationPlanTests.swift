// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

/// Suite `fork-glance-calibration-plan` — B2: the calibration points and the assistant's pure rules.
enum ForkGlanceCalibrationPlanTests {
    static func run(_ suite: TestSuite) {
        deskPoints(suite)
        otherLayouts(suite)
        quickAndWeak(suite)
        quality(suite)
        runThrough(suite)
        runRedo(suite)
        runPauseAndBack(suite)
        dot(suite)
        validationOrder(suite)
        validationScore(suite)
        validationAdvice(suite)
        framing(suite)
        strings(suite)
    }

    // MARK: Fixtures

    /// Plan, appendix A: the LG on top, the MacBook under it.
    private static let lg = ForkGlanceZonesTests.lg
    private static let macBook = ForkGlanceZonesTests.macBook
    private static let desk = ForkGlanceZonesTests.desk
    private static let deskSplits: [String: ForkGlanceSplit] = ["LG-UUID": .columns2, "BUILTIN-UUID": .whole]

    private static func sample(yaw: Double = 0, face: Bool = true, time: TimeInterval = 0) -> ForkGlanceSample {
        var vector = [Double](repeating: 0, count: ForkGlanceVectorLayout.count)
        vector[ForkGlanceVectorLayout.yaw] = yaw
        return ForkGlanceSample(time: time, vector: vector, confidence: 0.9, eyesUsable: true, facePresent: face)
    }

    /// `count` samples whose yaw wobbles by `degrees` around zero.
    private static func samples(_ count: Int, wobble degrees: Double = 0.2, face: Bool = true) -> [ForkGlanceSample] {
        (0..<count).map { sample(yaw: (($0 % 2 == 0) ? 1 : -1) * degrees * .pi / 180, face: face) }
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    // MARK: Points

    private static func deskPoints(_ suite: TestSuite) {
        let targets = ForkGlanceCalibrationPlan.targets(layout: desk, mode: .zones, splits: deskSplits)
        let kinds = Dictionary(grouping: targets, by: \.kind).mapValues(\.count)
        suite.expect(targets.count == 29, "Annex A's desk takes 29 points: \(targets.count)")
        suite.expect(kinds[.grid] == 24 && kinds[.zoneBorder] == 2 && kinds[.displayBorder] == 3,
                     "15 + 9 grid points, 2 on the LG's middle line, 3 along the LG over the MacBook: \(kinds)")
        suite.expect(targets.map(\.id) == Array(0..<targets.count), "the points are numbered in plan order")
        suite.expect(targets.filter { $0.displayUUID == "LG-UUID" && $0.kind == .grid }.count == 15
                        && targets.filter { $0.displayUUID == "BUILTIN-UUID" }.count == 9,
                     "the ultra-wide LG gets a 5×3 grid, the MacBook a 3×3 one")
        let inside = targets.allSatisfy { target in
            [lg, macBook].first { $0.uuid == target.displayUUID }?.frame.contains(target.point) == true
        }
        suite.expect(inside, "every point is drawn inside its own display")
        var crowded = false
        for (index, a) in targets.enumerated() {
            for b in targets[(index + 1)...] where distance(a.point, b.point) < ForkGlanceCalibrationPlan.minimumSpacing {
                crowded = true
            }
        }
        suite.expect(!crowded, "no two points sit on top of each other (the grid's middle column is not done twice)")
        let borders = targets.filter { $0.kind == .displayBorder }
        suite.expect(borders.allSatisfy { $0.displayUUID == "LG-UUID" && $0.point.y == 1440 - ForkGlanceCalibrationPlan.displayBorderInset }
                        && borders.allSatisfy { $0.point.x > macBook.frame.minX && $0.point.x < macBook.frame.maxX },
                     "the display border points run just inside the LG's bottom edge, over the MacBook")
        let firstMacBook = targets.firstIndex { $0.displayUUID == "BUILTIN-UUID" } ?? 0
        let lastLG = targets.lastIndex { $0.displayUUID == "LG-UUID" && $0.kind != .displayBorder } ?? 0
        let borderIndices = targets.indices.filter { targets[$0].kind == .displayBorder }
        suite.expect(lastLG < (borderIndices.first ?? -1) && (borderIndices.last ?? .max) < firstMacBook,
                     "the LG is done first, then its border with the MacBook, then the MacBook: one display hands over through their border")
        let lgRows = targets.filter { $0.displayUUID == "LG-UUID" && $0.kind == .grid }.map(\.point.y)
        suite.expect(lgRows == lgRows.sorted(), "the LG is swept row by row toward the MacBook below it")
        let steps = zip(targets, targets.dropFirst()).map { distance($0.point, $1.point) }
        suite.expect((steps.max() ?? 0) <= lg.frame.width * 0.45,
                     "no step crosses more than half the LG: the order is a serpent, not a zigzag (\(Int(steps.max() ?? 0)) pt)")
        let firstRow = targets.prefix(5).map(\.point.x)
        let secondGridRow = targets.filter { $0.kind == .grid && $0.point.y == 720 }.map(\.point.x)
        suite.expect(firstRow == firstRow.sorted() && secondGridRow.count == 5,
                     "the first row runs from one end to the other, and every row keeps its five points")
    }

    private static func otherLayouts(_ suite: TestSuite) {
        let screens = ForkGlanceCalibrationPlan.targets(layout: desk, mode: .screens, splits: deskSplits)
        suite.expect(screens.count == 27 && !screens.contains { $0.kind == .zoneBorder },
                     "Screens mode has no zone borders: 15 + 9 + 3 points")
        let windows = ForkGlanceCalibrationPlan.targets(layout: desk, mode: .windows, splits: deskSplits)
        suite.expect(windows.count == 27, "Windows mode calibrates the grids and the display border only")

        let alone = ForkGlanceDisplayLayout(displays: [macBook])
        let single = ForkGlanceCalibrationPlan.targets(layout: alone, mode: .zones, splits: [:])
        suite.expect(single.count == 9 && single.allSatisfy { $0.kind == .grid }, "a lone 16:10 display takes its 3×3 grid")
        let grid = ForkGlanceCalibrationPlan.targets(layout: alone, mode: .zones, splits: ["BUILTIN-UUID": .grid2x2])
        suite.expect(grid.count == 13, "a 2×2 split adds four border points around the center the grid already has: \(grid.count)")

        let left = ForkGlanceDisplay(uuid: "L", name: "Left", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let right = ForkGlanceDisplay(uuid: "R", name: "Right", frame: CGRect(x: 1920, y: 100, width: 1920, height: 1080))
        let sideBySide = ForkGlanceCalibrationPlan.targets(layout: ForkGlanceDisplayLayout(displays: [right, left]),
                                                           mode: .screens, splits: [:])
        let borders = sideBySide.filter { $0.kind == .displayBorder }
        suite.expect(sideBySide.count == 21 && borders.count == 3
                        && borders.allSatisfy { $0.displayUUID == "L" && $0.point.x == 1920 - ForkGlanceCalibrationPlan.displayBorderInset },
                     "side by side, the border points run just inside the left display's right edge")
        let firstBorder = sideBySide.firstIndex { $0.kind == .displayBorder } ?? 0
        suite.expect(sideBySide.first?.displayUUID == "L" && firstBorder > 0
                        && sideBySide[firstBorder - 1].point.x == 1920 * 0.9,
                     "the left display is swept column by column toward the right one, ending on its right column")
        suite.expect(ForkGlanceCalibrationPlan.targets(layout: ForkGlanceDisplayLayout(displays: []), mode: .zones, splits: [:]).isEmpty,
                     "no display, no point")

        suite.expectClose(ForkGlanceCalibrationPlan.pointDuration, 1.95, "one point: 0.35 s travel, 0.45 s settle, 0.9 s collect, 0.25 s ✓")
        suite.expectClose(ForkGlanceCalibrationPlan.duration(points: 29), 56.55, "the desk's 29 points take under a minute")
    }

    private static func quickAndWeak(_ suite: TestSuite) {
        let zones = ForkGlanceZones.zones(layout: desk, mode: .zones, splits: deskSplits, windows: [])
        let quick = ForkGlanceCalibrationPlan.quickTargets(zones: zones)
        suite.expect(quick.count == 3 && Set(quick.compactMap(\.zoneID)) == Set(zones.map(\.id)),
                     "the quick recenter lights one point per zone")
        suite.expect(quick.allSatisfy { target in
            zones.first { $0.id == target.zoneID }.map { $0.rect.midX == target.point.x && $0.rect.midY == target.point.y } == true
        }, "each quick point sits in the middle of its zone")
        suite.expect(quick.first?.zoneID == "LG-UUID#0", "the quick points start at the top left")

        let targets = ForkGlanceCalibrationPlan.targets(layout: desk, mode: .zones, splits: deskSplits)
        let weak = zones.filter { $0.id == "BUILTIN-UUID#0" }
        let redo = ForkGlanceCalibrationPlan.targets(targets, near: weak)
        suite.expect(redo.count == 12 && redo.filter { $0.kind == .displayBorder }.count == 3,
                     "the weak MacBook takes its nine points again, and the border points just above it: \(redo.count)")
        suite.expect(redo.map(\.id) == redo.map(\.id).sorted(), "the weak points keep the plan's order")
    }

    // MARK: Quality

    private static func quality(_ suite: TestSuite) {
        suite.expect(ForkGlanceCalibrationPlan.verdict(samples(7)) == .tooFewSamples, "seven samples are too few")
        suite.expect(ForkGlanceCalibrationPlan.verdict(samples(8)) == .good, "eight steady samples make a point")
        suite.expect(ForkGlanceCalibrationPlan.verdict(samples(12, wobble: 3)) == .unsteady,
                     "a yaw wandering 3° is a head still turning")
        suite.expect(ForkGlanceCalibrationPlan.verdict(samples(12, wobble: 2.4)) == .good, "2.4° is steady enough")
        suite.expect(ForkGlanceCalibrationPlan.verdict(samples(6) + samples(6, face: false)) == .tooFewSamples,
                     "samples without a face do not count")
    }

    // MARK: Run

    /// Feeds `count` samples during the collect of the current point and advances past it.
    private static func collect(_ run: inout ForkGlanceCalibrationRun, _ batch: [ForkGlanceSample],
                                clock: inout TimeInterval) -> [ForkGlanceCalibrationRun.Event] {
        var events: [ForkGlanceCalibrationRun.Event] = []
        // To the collect stage.
        while run.stage != .collect, let deadline = run.nextDeadline {
            clock = deadline
            events += run.advance(now: clock)
            if run.isFinished { return events }
        }
        for (index, sample) in batch.enumerated() {
            run.add(sample, now: clock + 0.05 * Double(index))
        }
        clock = run.nextDeadline ?? clock
        events += run.advance(now: clock)
        return events
    }

    private static func runThrough(_ suite: TestSuite) {
        let targets = Array(ForkGlanceCalibrationPlan.targets(layout: desk, mode: .zones, splits: deskSplits).prefix(3))
        var clock: TimeInterval = 100
        var run = ForkGlanceCalibrationRun(targets: targets, now: clock)
        suite.expect(run.stage == .travel && run.current == targets[0], "a run starts by travelling to its first point")
        run.add(sample(), now: clock + 0.1)
        clock += ForkGlanceCalibrationPlan.travel
        _ = run.advance(now: clock)
        run.add(sample(), now: clock + 0.1)
        suite.expect(run.stage == .settle, "the dot settles after its travel")
        var events: [ForkGlanceCalibrationRun.Event] = []
        for _ in targets { events += collect(&run, samples(10), clock: &clock) }
        clock = run.nextDeadline ?? clock
        events += run.advance(now: clock)
        suite.expect(events == [.pointDone(index: 0, done: 1), .pointDone(index: 1, done: 2), .pointDone(index: 2, done: 3), .finished],
                     "each point says it is done, then the run finishes: \(events)")
        suite.expect(run.isFinished && run.nextDeadline == nil && run.current == nil, "a finished run waits for nothing")
        suite.expect(run.points.count == 3 && run.points.allSatisfy { $0.samples.count == 10 },
                     "each point keeps only its collect's samples, none from its travel or settle")

        var late = ForkGlanceCalibrationRun(targets: targets, now: 0)
        let all = late.advance(now: 60)
        let retries = all.filter { if case .retry = $0 { return true } else { return false } }.count
        suite.expect(all.count == 7 && retries == 3 && all.last == .finished && late.isFinished && late.points.isEmpty,
                     "a run left without samples redoes each point once, drops it, and still finishes: \(all)")
    }

    private static func runRedo(_ suite: TestSuite) {
        let targets = Array(ForkGlanceCalibrationPlan.targets(layout: desk, mode: .zones, splits: deskSplits).prefix(2))
        var clock: TimeInterval = 0
        var run = ForkGlanceCalibrationRun(targets: targets, now: clock)
        let first = collect(&run, samples(10, wobble: 4), clock: &clock)
        suite.expect(first == [.retry(index: 0, verdict: .unsteady)] && run.stage == .shake && run.isRetry,
                     "an unsteady point shakes and is done once more")
        let second = collect(&run, samples(10), clock: &clock)
        suite.expect(second == [.pointDone(index: 0, done: 1)] && run.points.first?.samples.count == 10,
                     "the second attempt keeps its own samples")

        let third = collect(&run, samples(5), clock: &clock)
        let fourth = collect(&run, samples(5), clock: &clock)
        suite.expect(third == [.retry(index: 1, verdict: .tooFewSamples)] && fourth == [.pointDone(index: 1, done: 2)],
                     "a point that fails twice is kept with what it has")
        suite.expect(run.points.count == 2 && run.points.last?.samples.count == 5, "the twice-failed point keeps its five samples")

        var faceless = ForkGlanceCalibrationRun(targets: [targets[0]], now: 0)
        var time: TimeInterval = 0
        _ = collect(&faceless, samples(10, face: false), clock: &time)
        let dropped = collect(&faceless, samples(10, face: false), clock: &time)
        suite.expect(dropped == [.pointDone(index: 0, done: 1)] && faceless.stage == .confirm(kept: false) && faceless.points.isEmpty,
                     "a point without a single face is dropped, and still counts as done for the progress")

        var validation = ForkGlanceCalibrationRun(targets: targets, checksQuality: false, now: 0)
        var t: TimeInterval = 0
        let lenient = collect(&validation, samples(3, wobble: 5), clock: &t)
        suite.expect(lenient == [.pointDone(index: 0, done: 1)] && validation.points.first?.samples.count == 3,
                     "the validation never redoes a zone: it keeps whatever it measured")
    }

    private static func runPauseAndBack(_ suite: TestSuite) {
        let targets = Array(ForkGlanceCalibrationPlan.targets(layout: desk, mode: .zones, splits: deskSplits).prefix(3))
        var clock: TimeInterval = 0
        var run = ForkGlanceCalibrationRun(targets: targets, now: clock)
        _ = collect(&run, samples(10), clock: &clock)
        // Into the second point's collect.
        while run.stage != .collect, let deadline = run.nextDeadline {
            clock = deadline
            _ = run.advance(now: clock)
        }
        run.add(sample(), now: clock)
        run.pause(now: clock + 0.1)
        suite.expect(run.isPaused && run.nextDeadline == nil, "paused, the run waits for nothing")
        run.add(sample(), now: clock + 0.2)
        suite.expect(run.advance(now: clock + 30).isEmpty, "time passing during a pause does nothing")
        run.resume(now: clock + 31)
        suite.expect(!run.isPaused && run.stage == .settle && run.index == 1,
                     "on resume the point settles again: the eyes may have left it")
        clock += 31
        let events = collect(&run, samples(9), clock: &clock)
        suite.expect(events == [.pointDone(index: 1, done: 2)] && run.points.last?.samples.count == 9,
                     "the samples from before the pause are dropped")

        // ⌫ during the third point: the second one again.
        clock = run.nextDeadline ?? clock
        _ = run.advance(now: clock)
        run.back(now: clock)
        suite.expect(run.index == 1 && run.stage == .travel && run.done == 1,
                     "⌫ goes back to the previous point and forgets its samples")
        _ = collect(&run, samples(8), clock: &clock)
        clock = run.nextDeadline ?? clock
        _ = run.advance(now: clock)
        suite.expect(run.index == 2 && run.stage == .travel, "once redone, the run goes on where it was")

        var start = ForkGlanceCalibrationRun(targets: targets, now: 0)
        start.back(now: 0.1)
        suite.expect(start.index == 0 && start.stage == .travel, "⌫ on the first point starts it again")
        var empty = ForkGlanceCalibrationRun(targets: [], now: 0)
        suite.expect(empty.isFinished && empty.advance(now: 10).isEmpty, "a run without points is finished from the start")
    }

    // MARK: Dot

    private static func dot(_ suite: TestSuite) {
        let open = ForkGlanceDotLook.at(.settle, progress: 0, reduceMotion: false)
        let closed = ForkGlanceDotLook.at(.settle, progress: 1, reduceMotion: false)
        let half = ForkGlanceDotLook.at(.settle, progress: 0.5, reduceMotion: false)
        suite.expect(open.ring == 44 && closed.ring == 18 && half.ring < 31,
                     "the ring tightens from 44 to 18 pt, ease-out (past half way at mid-time)")
        suite.expect(ForkGlanceDotLook.at(.settle, progress: 0, reduceMotion: true).ring == 18,
                     "with Reduce Motion the ring jumps")
        suite.expectClose(ForkGlanceDotLook.at(.collect, progress: 0.4, reduceMotion: false).arc, 0.4, "the arc fills linearly")
        suite.expectClose(ForkGlanceDotLook.at(.collect, progress: 0.4, reduceMotion: true).arc, 0.4, "with Reduce Motion the arc stays")
        let done = ForkGlanceDotLook.at(.confirm(kept: true), progress: 0.5, reduceMotion: false)
        suite.expect(done.check && done.opacity < 1 && ForkGlanceDotLook.at(.confirm(kept: true), progress: 0.5, reduceMotion: true).opacity == 1,
                     "a kept point shows its ✓ and fades, without the fade under Reduce Motion")
        suite.expect(!ForkGlanceDotLook.at(.confirm(kept: false), progress: 0, reduceMotion: false).check, "a dropped point shows no ✓")
        let shaking = (1..<12).map { ForkGlanceDotLook.at(.shake, progress: Double($0) / 12, reduceMotion: false).shake }
        suite.expect(shaking.contains { $0 > 3 } && shaking.contains { $0 < -3 } && shaking.allSatisfy { abs($0) <= 4 },
                     "a redone point shakes by 4 pt each way")
        suite.expect(ForkGlanceDotLook.at(.shake, progress: 0.3, reduceMotion: true).shake == 0, "with Reduce Motion it does not shake")
        suite.expect(ForkGlanceDotLook.at(.collect, progress: .nan, reduceMotion: false).arc == 0, "a nonsense progress draws an empty arc")
    }

    // MARK: Validation

    private static let threeZones = ForkGlanceZones.zones(layout: desk, mode: .zones, splits: deskSplits, windows: [])

    private static func validationOrder(_ suite: TestSuite) {
        let trials = ForkGlanceValidation.trials(zones: threeZones, seed: 42)
        let counts = Dictionary(grouping: trials.compactMap(\.zoneID), by: { $0 }).mapValues(\.count)
        suite.expect(trials.count == 6 && counts.values.allSatisfy { $0 == 2 }, "each zone is lit twice")
        suite.expect(ForkGlanceValidation.trials(zones: threeZones, seed: 42) == trials, "the same seed gives the same order")
        var repeats = 0, orders = Set<[String]>()
        for seed in 0..<300 {
            for zones in [threeZones, Array(threeZones.prefix(2))] {
                let order = ForkGlanceValidation.trials(zones: zones, seed: UInt64(seed)).compactMap(\.zoneID)
                repeats += zip(order, order.dropFirst()).filter { $0 == $1 }.count
                if zones.count == 3 { orders.insert(order) }
            }
        }
        suite.expect(repeats == 0, "never the same zone twice in a row: \(repeats)")
        suite.expect(orders.count > 5, "the order changes with the seed: \(orders.count) orders")
        suite.expect(trials.allSatisfy { trial in
            threeZones.first { $0.id == trial.zoneID }.map { $0.rect.midX == trial.point.x && $0.rect.midY == trial.point.y } == true
        }, "each zone is lit at its center")
        let lone = ForkGlanceValidation.trials(zones: [threeZones[2]], seed: 1)
        suite.expect(lone.count == 2, "a single zone is still lit twice")
    }

    private static func validationScore(_ suite: TestSuite) {
        let trials = ForkGlanceValidation.trials(zones: threeZones, seed: 7)
        let estimates: [[CGPoint]] = trials.map { trial in
            switch trial.zoneID {
            case "LG-UUID#0": return Array(repeating: CGPoint(x: 800, y: 700), count: 10)
            case "LG-UUID#1": return Array(repeating: CGPoint(x: 2500, y: 700), count: 9) + [CGPoint(x: 1000, y: 700)]
            default: return []
            }
        }
        let accuracy = ForkGlanceValidation.zoneAccuracy(trials: trials, estimates: estimates, zones: threeZones)
        suite.expectClose(accuracy["LG-UUID#0"] ?? -1, 1, "every estimate in the left zone")
        suite.expectClose(accuracy["LG-UUID#1"] ?? -1, 0.9, "18 of 20 estimates in the right zone, both rounds pooled")
        suite.expectClose(accuracy["BUILTIN-UUID#0"] ?? -1, 0, "a zone with no estimate at all scores nothing")
        suite.expectClose(ForkGlanceValidation.overall(accuracy), 1.9 / 3, "the overall score weighs every zone the same")
        suite.expect(ForkGlanceValidation.weakZones(accuracy, zones: threeZones).map(\.id) == ["BUILTIN-UUID#0"],
                     "the weak zones are those under 85 %")
        suite.expect(ForkGlanceGrade(score: accuracy["LG-UUID#1"] ?? 0) == .good, "90 % is « Bonne »")
        suite.expect(ForkGlanceValidation.overall([:]) == 0, "no zone, no score")
    }

    private static func validationAdvice(_ suite: TestSuite) {
        let macBookWeak = ["LG-UUID#0": 0.98, "LG-UUID#1": 0.97, "BUILTIN-UUID#0": 0.6]
        suite.expect(ForkGlanceValidation.advice(macBookWeak, zones: threeZones, layout: desk, mode: .zones)
                        == [.stackedDisplay(displayUUID: "BUILTIN-UUID")],
                     "a weak MacBook under the LG says the switch to it is fragile")
        let lgBlur = ["LG-UUID#0": 0.7, "LG-UUID#1": 0.72, "BUILTIN-UUID#0": 0.99]
        suite.expect(ForkGlanceValidation.advice(lgBlur, zones: threeZones, layout: desk, mode: .zones)
                        == [.splitTooFine(displayUUID: "LG-UUID")],
                     "two weak halves of the LG side by side say its split is too fine, not that the MacBook is in the way")
        let perfect = ["LG-UUID#0": 1.0, "LG-UUID#1": 0.96, "BUILTIN-UUID#0": 0.95]
        suite.expect(ForkGlanceValidation.advice(perfect, zones: threeZones, layout: desk, mode: .zones) == [.excellent],
                     "everything « Excellente » says so")
        let poor = ["LG-UUID#0": 0.5, "LG-UUID#1": 0.5, "BUILTIN-UUID#0": 0.5]
        let hints = ForkGlanceValidation.advice(poor, zones: threeZones, layout: desk, mode: .windows)
        suite.expect(hints.contains(.windowsMode) && hints.last == .lowOverall,
                     "a poor Windows-mode result points to Zones mode, then to the light and distance")
        let good = ["LG-UUID#0": 0.9, "LG-UUID#1": 0.9, "BUILTIN-UUID#0": 0.9]
        suite.expect(ForkGlanceValidation.advice(good, zones: threeZones, layout: desk, mode: .zones).isEmpty,
                     "« Bonne » everywhere needs no hint")
    }

    // MARK: Framing

    private static func face(width: CGFloat = 0.28, x: CGFloat = 0.5, yaw: Double = 0, pitch: Double = 0.1,
                             quality: Double? = 0.6, others: Double = 0) -> ForkGlanceObservation {
        ForkGlanceObservation(time: 0, faceBox: CGRect(x: x - width / 2, y: 0.5 - width / 2, width: width, height: width),
                              yaw: yaw, pitch: pitch, roll: 0, faceCount: others > 0 ? 2 : 1, otherFaceRatio: others,
                              captureQuality: quality)
    }

    private static func framing(_ suite: TestSuite) {
        let nothing = ForkGlanceFraming.check(nil, sample: nil)
        suite.expect(!nothing.allGood && nothing.advice == .noFace, "no face: place your face in the picture")
        let good = ForkGlanceFraming.check(face(), sample: sample())
        suite.expect(good.allGood && good.advice == .ready, "a face of a good size, lit and facing: all four gauges green")
        suite.expect(ForkGlanceFraming.check(face(others: 0.9), sample: nil).advice == .severalFaces,
                     "another face of a comparable size asks for one person")
        suite.expect(ForkGlanceFraming.check(face(others: 0.3), sample: nil).allGood, "a small face far behind does not matter")
        suite.expect(ForkGlanceFraming.check(face(quality: 0.1), sample: nil).advice == .moreLight, "a dark face asks for light")
        let unlit = ForkGlanceFraming.check(face(quality: nil), sample: ForkGlanceSample(time: 0, vector: [], confidence: 0.3,
                                                                                         eyesUsable: false, facePresent: true))
        suite.expect(unlit.light == .low, "without a quality, a low confidence reads as poor light")
        suite.expect(ForkGlanceFraming.check(face(width: 0.08), sample: nil).advice == .closer, "a tiny face asks to come closer")
        suite.expect(ForkGlanceFraming.check(face(width: 0.6), sample: nil).advice == .farther, "a huge face asks to move back")
        suite.expect(ForkGlanceFraming.check(face(yaw: 40 * .pi / 180), sample: nil).advice == .faceScreens,
                     "a head turned 40° asks to face the displays")
        suite.expect(ForkGlanceFraming.check(face(pitch: 25 * .pi / 180), sample: nil).facing == .good,
                     "looking up at a display above the camera is still « de face »")
        suite.expect(ForkGlanceFraming.check(face(x: 0.12), sample: nil).facing == .low, "a face at the image's edge is off center")

        var hold = ForkGlanceFraming.Hold()
        hold.update(true, now: 10)
        hold.update(true, now: 10.9)
        suite.expect(!hold.isReady(now: 10.9), "green for 0.9 s is not enough")
        suite.expect(hold.isReady(now: 11), "green for a second turns « Suivant » on")
        hold.update(false, now: 11.1)
        hold.update(true, now: 11.2)
        suite.expect(!hold.isReady(now: 12), "one red reading starts the second over")
    }

    // MARK: Strings

    private static func strings(_ suite: TestSuite) {
        ForkGlanceStringsTests.mirrorChecks(suite, "ForkGlanceCalibrationStrings", ForkGlanceCalibrationStrings.strings,
                                            sameInFrench: ["gaugeDistance", "modeLabel", "zoneCountOne", "zoneCountMany"],
                                            untranslated: [])
        let fr = ForkGlanceCalibrationStrings.fr, en = ForkGlanceCalibrationStrings.enUS
        let frenchLocale = Locale(identifier: "fr_FR")
        suite.expect(fr.instruction == "Tournez la tête naturellement vers chaque point."
                        && fr.holdEyes == "Gardez les yeux sur le point jusqu’à ce qu’il se remplisse."
                        && fr.again == "Encore une fois.",
                     "the assistant says the plan's sentences")
        suite.expect(fr.stepLine(3, of: 6) == "Étape 3 sur 6" && fr.progressLine(12, of: 29) == "Point 12 sur 29"
                        && fr.validationLine(7, of: 6) == "Zone 6 sur 6",
                     "the counters fill both numbers and stay within the plan")
        suite.expect(fr.pointsLine(29, locale: frenchLocale) == "29 points · environ 1\u{00A0}min",
                     "the points step says how many and how long")
        suite.expect(fr.duration(57, locale: frenchLocale) == "Environ 1\u{00A0}min, assis comme d’habitude.",
                     "the welcome says how long, rounded up to the minute")
        suite.expect(fr.costLine(locale: frenchLocale).hasPrefix("Coût visé\u{00A0}: environ 3\u{00A0}% d’un cœur.")
                        && fr.weakLine(locale: frenchLocale) == "Points faibles\u{00A0}: les zones sous 85\u{00A0}%.",
                     "the cost and the weak bar are percentages in the locale's own way")
        suite.expect(fr.zoneCount(1) == "1 zone" && fr.zoneCount(3) == "3 zones" && en.zoneCount(2) == "2 zones",
                     "a zone count agrees with its number")
        suite.expect(fr.advice(.stackedDisplay(displayUUID: "B"), displayName: { $0 == "B" ? "MacBook" : "?" })
                        == "La bascule vers «\u{00A0}MacBook\u{00A0}» est fragile\u{00A0}: allongez le délai avant de basculer, ou placez la caméra entre les deux écrans.",
                     "a hint names the display it is about")
        let steps = ForkGlanceAssistantStep.allCases.map(fr.stepName)
        let gauges = ForkGlanceFraming.Gauge.allCases.map(fr.gaugeName)
        let advices: [ForkGlanceFraming.Advice] = [.noFace, .severalFaces, .moreLight, .closer, .farther, .faceScreens, .ready]
        suite.expect(Set(steps).count == 7 && Set(gauges).count == 4 && Set(advices.map(fr.framingAdvice)).count == 7,
                     "every step, gauge and framing hint has words of its own")
        let validationHints: [ForkGlanceValidationAdvice] = [.stackedDisplay(displayUUID: "A"), .splitTooFine(displayUUID: "A"),
                                                             .windowsMode, .lowOverall, .excellent]
        suite.expect(Set(validationHints.map { en.advice($0, displayName: { _ in "LG" }) }).count == 5,
                     "every validation hint has words of its own")
    }
}
