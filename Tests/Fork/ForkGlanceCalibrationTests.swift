// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

/// Suite `fork-glance-calibration` — A3: the calibration model, sigma, recenter bias.
enum ForkGlanceCalibrationTests {
    static func run(_ suite: TestSuite) {
        stacking(suite)
        annexFit(suite)
        sigma(suite)
        eyesChoice(suite)
        degenerate(suite)
        estimate(suite)
        headMoves(suite)
        upgrade(suite)
        recenter(suite)
    }

    private typealias Fixtures = ForkGlanceModelFixtures

    /// Root mean square distance on fresh samples at `targets`.
    private static func heldOutError(_ calibration: ForkGlanceCalibration, person: Fixtures.Person,
                                     targets: [CGPoint], random: inout Fixtures.Random) -> Double {
        let points = person.points(targets, samples: 20, random: &random)
        return ForkGlanceCalibrationModel.error(of: calibration, on: points) ?? .infinity
    }

    private static func stacking(_ suite: TestSuite) {
        suite.expect(ForkGlanceCalibrationModel.stacked(Fixtures.annex), "the MacBook under the LG is a stacked layout")
        suite.expect(!ForkGlanceCalibrationModel.stacked(Fixtures.sideBySide), "two displays side by side are not stacked")
        suite.expect(!ForkGlanceCalibrationModel.stacked(ForkGlanceDisplayLayout(displays: [Fixtures.lg])),
                     "a single display is not stacked")
        let corner = ForkGlanceDisplayLayout(displays: [
            Fixtures.lg,
            ForkGlanceDisplay(uuid: "C", name: "C", frame: CGRect(x: 3340, y: 1440, width: 1728, height: 1117)),
        ])
        suite.expect(!ForkGlanceCalibrationModel.stacked(corner),
                     "a display that only touches another's corner from below is not stacked")
    }

    private static func annexFit(_ suite: TestSuite) {
        var random = Fixtures.Random(seed: 10)
        let person = Fixtures.Person()
        let points = person.points(Fixtures.annexTargets(), random: &random)
        suite.expect(points.count == 30, "the Annex A layout calibrates on 30 points")
        guard let calibration = Fixtures.fit(points) else {
            suite.expect(false, "the Annex A calibration fits")
            return
        }
        suite.expect(calibration.usesEyes, "a stacked layout uses the eyes")
        suite.expect(calibration.normalization.count == ForkGlanceVectorLayout.count
                        && calibration.coefficientsX.count == 15 && calibration.coefficientsY.count == 15,
                     "head and eyes read every component, 15 terms per axis")
        suite.expect(calibration.normalization.allSatisfy { $0.scale > 0 }, "no range has a zero scale")
        suite.expect(ForkGlanceCalibrationModel.minimumScales.count == ForkGlanceVectorLayout.count
                        && zip(calibration.normalization, ForkGlanceCalibrationModel.minimumScales)
                            .allSatisfy { $0.scale >= $1 },
                     "every component's scale keeps its floor, the face's size first (it barely moves here)")
        suite.expect(calibration.version == ForkGlanceCalibration.currentVersion && calibration.bias == .zero
                        && calibration.cameraID == "camera" && calibration.layoutSignature == "signature"
                        && calibration.date == Fixtures.date && calibration.zoneAccuracy.isEmpty,
                     "a new calibration carries its camera, layout and date, no bias and no validation yet")
        let yaws = points.flatMap(\.samples).map { $0.vector[ForkGlanceVectorLayout.yaw] }
        suite.expect(calibration.yawRange == yaws.min()!...yaws.max()!, "the yaw range is the one the calibration saw")

        let error = heldOutError(calibration, person: person, targets: Fixtures.annexTargets(), random: &random)
        suite.expect(error < 60, "fresh glances at the targets land close to them (\(Int(error)) pt)")
        let probes = [CGPoint(x: 860, y: 720), CGPoint(x: 2580, y: 720), CGPoint(x: 1802, y: 2000)]
        let probeError = heldOutError(calibration, person: person, targets: probes, random: &random)
        suite.expect(probeError < 80, "points between the targets too (\(Int(probeError)) pt)")

        let data = try? JSONEncoder().encode(calibration)
        let back = data.flatMap { try? JSONDecoder().decode(ForkGlanceCalibration.self, from: $0) }
        suite.expect(back == calibration, "a fitted calibration survives JSON (every value finite)")
    }

    private static func sigma(_ suite: TestSuite) {
        var random = Fixtures.Random(seed: 11)
        let quiet = Fixtures.Person(angleNoise: 0.005, eyeNoise: 0.005)
        let shaky = Fixtures.Person(angleNoise: 0.03, eyeNoise: 0.03)
        let targets = Fixtures.annexTargets()
        guard let calm = Fixtures.fit(quiet.points(targets, random: &random)),
              let rough = Fixtures.fit(shaky.points(targets, random: &random)) else {
            suite.expect(false, "both calibrations fit")
            return
        }
        suite.expect(rough.sigma.width > 2 * calm.sigma.width && rough.sigma.height > 2 * calm.sigma.height,
                     "a shakier signal gives a larger σ on both axes (\(calm.sigma) → \(rough.sigma))")
        let error = heldOutError(rough, person: shaky, targets: targets, random: &random)
        let sigma = hypot(Double(rough.sigma.width), Double(rough.sigma.height))
        suite.expect(sigma > 0.6 * error && sigma < 1.8 * error,
                     "σ tells the real error on fresh glances (σ \(Int(sigma)) pt, error \(Int(error)) pt)")
        suite.expect(calm.sigma.width >= ForkGlanceCalibrationModel.minimumSigma
                        && calm.sigma.height >= ForkGlanceCalibrationModel.minimumSigma, "σ is never below its floor")
    }

    private static func eyesChoice(_ suite: TestSuite) {
        var random = Fixtures.Random(seed: 12)
        let targets = Fixtures.sideBySideTargets()
        let blankEyes = Fixtures.Person(camera: CGPoint(x: 1920, y: 1080), eyeSignal: 0)
        let eyesOnly = Fixtures.Person(camera: CGPoint(x: 1920, y: 1080), headPitch: 0, eyeSignal: 1)
        let head = Fixtures.fit(blankEyes.points(targets, random: &random), layout: Fixtures.sideBySide)
        let eyes = Fixtures.fit(eyesOnly.points(targets, random: &random), layout: Fixtures.sideBySide)
        suite.expect(head?.usesEyes == false && head?.normalization.count == ForkGlanceVectorLayout.headCount
                        && head?.coefficientsX.count == 10,
                     "side by side, eyes that say nothing leave the head-only model")
        suite.expect(eyes?.usesEyes == true, "eyes that carry the vertical gaze win by more than 10 %")
        let forced = Fixtures.fit(eyesOnly.points(targets, random: &random), layout: Fixtures.sideBySide,
                                  usesEyes: false)
        suite.expect(forced?.usesEyes == false, "an explicit choice is kept")
    }

    private static func degenerate(_ suite: TestSuite) {
        var random = Fixtures.Random(seed: 13)
        let person = Fixtures.Person()
        func error(_ points: [ForkGlanceCalibrationPoint]) -> ForkGlanceRegressionError? {
            do {
                _ = try ForkGlanceCalibrationModel.fit(points: points, usesEyes: nil, layout: Fixtures.annex,
                                                       cameraID: "c", layoutSignature: "s", date: Fixtures.date)
                return nil
            } catch {
                return error as? ForkGlanceRegressionError
            }
        }
        let five = person.points(Array(Fixtures.annexTargets().prefix(5)), random: &random)
        suite.expect(error(five) == .tooFewPoints, "five points are too few to calibrate")
        let line = person.points((1...8).map { CGPoint(x: 400 * Double($0), y: 720) }, random: &random)
        suite.expect(error(line) == .degenerate, "points on one line cannot calibrate two axes")
        var faceless = person.points(Fixtures.annexTargets(), random: &random)
        for index in faceless.indices.dropFirst(5) {
            faceless[index].samples = faceless[index].samples.map { var s = $0; s.facePresent = false; return s }
        }
        suite.expect(error(faceless) == .tooFewPoints, "points without a face do not count")
        let frozen = person.sample(looking: CGPoint(x: 1720, y: 720), random: &random)
        let still = Fixtures.annexTargets().map { target in
            ForkGlanceCalibrationPoint(target: target, samples: Array(repeating: frozen, count: 4))
        }
        suite.expect(error(still) == .degenerate, "a head that never moved is degenerate")
    }

    private static func estimate(_ suite: TestSuite) {
        var random = Fixtures.Random(seed: 14)
        let person = Fixtures.Person()
        guard let calibration = Fixtures.fit(person.points(Fixtures.annexTargets(), random: &random)) else {
            suite.expect(false, "the calibration fits")
            return
        }
        var sample = person.sample(looking: CGPoint(x: 2580, y: 720), time: 42, confidence: 0.8, random: &random)
        let estimate = ForkGlanceCalibrationModel.estimate(sample, with: calibration)
        suite.expect(estimate?.time == 42 && estimate?.confidence == 0.8 && estimate?.sigma == calibration.sigma,
                     "an estimate carries the sample's time and confidence and the calibration's σ")
        var biased = calibration
        biased.bias = CGVector(dx: 30, dy: -20)
        let moved = ForkGlanceCalibrationModel.estimate(sample, with: biased)
        suite.expectClose(Double((moved?.point.x ?? 0) - (estimate?.point.x ?? 0)), 30, "the bias moves x")
        suite.expectClose(Double((moved?.point.y ?? 0) - (estimate?.point.y ?? 0)), -20, "the bias moves y")
        sample.facePresent = false
        suite.expect(ForkGlanceCalibrationModel.estimate(sample, with: calibration) == nil, "no face, no estimate")
        sample.facePresent = true
        sample.vector = Array(sample.vector.prefix(6))
        suite.expect(ForkGlanceCalibrationModel.estimate(sample, with: calibration) == nil,
                     "a head-only vector cannot feed a head and eyes calibration")
    }

    /// The calibration is taken with a still head; in use the person leans,
    /// shifts and comes closer. Such a sample must still land on the desk.
    private static func headMoves(_ suite: TestSuite) {
        var random = Fixtures.Random(seed: 16)
        let person = Fixtures.Person()
        let points = person.points(Fixtures.annexTargets(), random: &random)
        guard let calibration = Fixtures.fit(points) else {
            suite.expect(false, "the calibration fits")
            return
        }
        let samples = points.flatMap(\.samples)
        func deviation(_ component: Int) -> Double {
            let values = samples.map { $0.vector[component] }
            let mean = values.reduce(0, +) / Double(values.count)
            return (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)).squareRoot()
        }
        let desk = Fixtures.annex.displays.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        let target = CGPoint(x: 2580, y: 720)
        let still = person.sample(looking: target, random: &random)
        guard let base = ForkGlanceCalibrationModel.estimate(still, with: calibration)?.point else {
            suite.expect(false, "a still glance gives an estimate")
            return
        }
        for (component, name) in [(ForkGlanceVectorLayout.size, "size"), (ForkGlanceVectorLayout.centerX, "center x")] {
            for sign in [-1.0, 1.0] {
                var moved = still
                moved.vector[component] += sign * 10 * deviation(component)
                guard let point = ForkGlanceCalibrationModel.estimate(moved, with: calibration)?.point else {
                    suite.expect(false, "a moved head still gives an estimate")
                    continue
                }
                let shift = hypot(Double(point.x - base.x), Double(point.y - base.y))
                suite.expect(desk.insetBy(dx: -300, dy: -300).contains(point) && shift < 600,
                             "the face's \(name) 10 σ off still lands near the displays (moved \(Int(shift)) pt)")
            }
        }
        // Far past the bound, further makes no difference.
        var near = still, nearer = still
        near.vector[ForkGlanceVectorLayout.size] += 0.1
        nearer.vector[ForkGlanceVectorLayout.size] += 10
        suite.expect(ForkGlanceCalibrationModel.estimate(near, with: calibration)?.point
                        == ForkGlanceCalibrationModel.estimate(nearer, with: calibration)?.point,
                     "past ±3 scales a component is held at the bound: the estimate stops moving")
    }

    /// A calibration from the version-1 model (degree 2 on every component)
    /// is fitted again on its points, with nothing asked of the person.
    private static func upgrade(_ suite: TestSuite) {
        var random = Fixtures.Random(seed: 17)
        let person = Fixtures.Person()
        let points = person.points(Fixtures.annexTargets(), random: &random)
        guard var old = Fixtures.fit(points) else {
            suite.expect(false, "the calibration fits")
            return
        }
        old.version = 1
        old.coefficientsX = (0..<78).map { Double($0) }
        old.coefficientsY = (0..<78).map { -Double($0) }
        old.bias = CGVector(dx: 40, dy: -25)
        old.zoneAccuracy = ["LG-UUID#0": 0.9]
        old.date = Date(timeIntervalSince1970: 1_790_000_000)
        let glance = person.sample(looking: CGPoint(x: 860, y: 720), random: &random)
        suite.expect(ForkGlanceCalibrationModel.estimate(glance, with: old) == nil,
                     "a version-1 calibration gives no estimate: its terms are not the model's")

        guard let upgraded = ForkGlanceCalibrationModel.upgraded(old, points: points, learned: [],
                                                                 layout: Fixtures.annex) else {
            suite.expect(false, "a version-1 calibration with its points is fitted again")
            return
        }
        suite.expect(upgraded.version == ForkGlanceCalibration.currentVersion && upgraded.coefficientsX.count == 15
                        && upgraded.usesEyes == old.usesEyes && upgraded.cameraID == old.cameraID
                        && upgraded.layoutSignature == old.layoutSignature && upgraded.date == old.date
                        && upgraded.zoneAccuracy == old.zoneAccuracy,
                     "the upgrade keeps the eyes choice, camera, layout, date and validation, in the current version")
        suite.expect(upgraded.bias == .zero, "the old bias, measured against the old model, goes")
        let landed = ForkGlanceCalibrationModel.estimate(glance, with: upgraded)?.point
        let miss = heldOutError(upgraded, person: person, targets: Fixtures.annexTargets(), random: &random)
        suite.expect(miss < 60, "the upgraded calibration tracks the gaze again (\(Int(miss)) pt)")

        var headOnly = old
        headOnly.usesEyes = false
        headOnly.normalization = Array(old.normalization.prefix(ForkGlanceVectorLayout.headCount))
        headOnly.coefficientsX = Array(repeating: 1, count: 28)
        headOnly.coefficientsY = Array(repeating: 1, count: 28)
        let head = ForkGlanceCalibrationModel.upgraded(headOnly, points: points, learned: [], layout: Fixtures.annex)
        suite.expect(head?.usesEyes == false && head?.coefficientsX.count == 10,
                     "a head-only calibration stays head-only, even on a stacked layout")

        // Clicks learned since the calibration, all pointing 300 pt right of where the person looked.
        let learned = (0..<30).map { index -> (ForkGlanceCalibrationPoint, Double) in
            let look = CGPoint(x: 400 + 90 * Double(index), y: 300 + 25 * Double(index % 20))
            let sample = person.sample(looking: look, random: &random)
            return (ForkGlanceCalibrationPoint(target: CGPoint(x: look.x + 300, y: look.y), samples: [sample]), 5)
        }
        let taught = ForkGlanceCalibrationModel.upgraded(old, points: points, learned: learned, layout: Fixtures.annex)
        let taughtX = taught.flatMap { ForkGlanceCalibrationModel.estimate(glance, with: $0) }.map { Double($0.point.x) }
        suite.expect((taughtX ?? 0) > Double(landed?.x ?? .infinity) + 20,
                     "the clicks learned since are learned again")
        suite.expect(ForkGlanceCalibrationModel.upgraded(old, points: [], learned: learned, layout: Fixtures.annex) == nil,
                     "without its points a calibration cannot be fitted again")
    }

    private static func recenter(_ suite: TestSuite) {
        var random = Fixtures.Random(seed: 15)
        let person = Fixtures.Person()
        guard let calibration = Fixtures.fit(person.points(Fixtures.annexTargets(), random: &random)) else {
            suite.expect(false, "the calibration fits")
            return
        }
        // The person moved: they look at the pointer, the model sees them 60 pt left.
        let pointer = CGPoint(x: 2000, y: 600)
        let seen = CGPoint(x: 1940, y: 600)
        let samples = (0..<12).map { _ in person.sample(looking: seen, random: &random) }
        let fixed = ForkGlanceCalibrationModel.recentered(calibration, samples: samples, target: pointer,
                                                          layout: Fixtures.annex)
        suite.expectClose(Double(fixed.bias.dx), 60, "recentering cancels the offset in x", tol: 25)
        suite.expectClose(Double(fixed.bias.dy), 0, "and keeps y", tol: 25)
        suite.expect(fixed.coefficientsX == calibration.coefficientsX && fixed.sigma == calibration.sigma,
                     "recentering only moves the bias")
        let after = samples.compactMap { ForkGlanceCalibrationModel.estimate($0, with: fixed)?.point }
        let meanX = after.map { Double($0.x) }.reduce(0, +) / Double(max(after.count, 1))
        suite.expectClose(meanX, 2000, "after recentering the gaze lands on the pointer", tol: 3)

        // Far off: bounded to 15 % of the LG's diagonal, same direction.
        let far = (0..<12).map { _ in person.sample(looking: CGPoint(x: 400, y: 600), random: &random) }
        let bounded = ForkGlanceCalibrationModel.recentered(calibration, samples: far, target: CGPoint(x: 3000, y: 600),
                                                            layout: Fixtures.annex)
        let limit = 0.15 * hypot(3440.0, 1440.0)
        suite.expectClose(hypot(Double(bounded.bias.dx), Double(bounded.bias.dy)), limit,
                          "the bias stops at 15 % of the display's diagonal", tol: 0.5)
        suite.expect(bounded.bias.dx > 0 && abs(Double(bounded.bias.dy)) < 0.1 * limit,
                     "a bounded bias keeps its direction")
        let onMacBook = ForkGlanceCalibrationModel.recentered(
            calibration, samples: far, target: CGPoint(x: 2600, y: 2000), layout: Fixtures.annex)
        suite.expectClose(hypot(Double(onMacBook.bias.dx), Double(onMacBook.bias.dy)), 0.15 * hypot(1728.0, 1117.0),
                          "the bound is the diagonal of the display under the target", tol: 0.5)
        suite.expect(ForkGlanceCalibrationModel.recentered(calibration, samples: [], target: pointer,
                                                           layout: Fixtures.annex) == calibration,
                     "without samples nothing changes")
        let faceless = samples.map { var s = $0; s.facePresent = false; return s }
        suite.expect(ForkGlanceCalibrationModel.recentered(calibration, samples: faceless, target: pointer,
                                                           layout: Fixtures.annex) == calibration,
                     "without a face nothing changes")
    }
}
