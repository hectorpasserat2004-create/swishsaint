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
                        && calibration.coefficientsX.count == 78 && calibration.coefficientsY.count == 78,
                     "head and eyes read every component, 78 terms per axis")
        suite.expect(calibration.normalization.allSatisfy { $0.scale > 0 }, "no range has a zero scale")
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
                        && head?.coefficientsX.count == 28,
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
