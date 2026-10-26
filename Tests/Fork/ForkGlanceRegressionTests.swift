// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

/// Suite `fork-glance-regression` — A3: polynomial ridge regression and cross-validation.
enum ForkGlanceRegressionTests {
    static func run(_ suite: TestSuite) {
        expansion(suite)
        knownFunction(suite)
        lambdaChoice(suite)
        groupedFolds(suite)
        weights(suite)
        degenerate(suite)
    }

    private typealias Fixtures = ForkGlanceModelFixtures

    private static func f(_ a: Double, _ b: Double) -> Double { 3 + 2 * a - b + 0.5 * a * b + 0.25 * a * a }

    private static func expansion(_ suite: TestSuite) {
        suite.expect(ForkGlanceRegression.expand([2, 3]) == [1, 2, 3, 4, 6, 9],
                     "the degree-2 terms are 1, each component, then each product with i ≤ j")
        suite.expect(ForkGlanceRegression.expand(Array(repeating: 1, count: 6)).count == 28
                        && ForkGlanceRegression.expand(Array(repeating: 1, count: 11)).count == 78,
                     "head only gives 28 terms, head and eyes 78")
        let model = ForkGlanceRidgeModel(coefficients: [1, 2, 3, 0, 0, 0], lambda: 0)
        suite.expect(model.predict([1, 1]) == 6 && model.predict([1, 1, 1]).isNaN,
                     "a model predicts from its own length of vector only")
    }

    private static func knownFunction(_ suite: TestSuite) {
        var random = Fixtures.Random(seed: 1)
        var inputs: [[Double]] = [], clean: [Double] = [], noisy: [Double] = []
        for _ in 0..<80 {
            let a = random.uniform(-2, 2), b = random.uniform(-2, 2)
            inputs.append([a, b])
            clean.append(f(a, b))
            noisy.append(f(a, b) + 0.1 * random.gaussian())
        }
        guard let exact = try? ForkGlanceRegression.fit(inputs: inputs, targets: clean, lambda: 1e-6),
              let fitted = try? ForkGlanceRegression.crossValidated(inputs: inputs, targets: noisy) else {
            suite.expect(false, "a well-spread quadratic fits")
            return
        }
        let probes: [[Double]] = [[0, 0], [1.5, -1], [-1.2, 1.7], [0.4, 0.9]]
        let exactError = probes.map { abs(exact.predict($0) - f($0[0], $0[1])) }.max() ?? .infinity
        suite.expect(exactError < 0.01, "a noiseless quadratic is found again (worst error \(exactError))")
        let noisyError = probes.map { abs(fitted.model.predict($0) - f($0[0], $0[1])) }.max() ?? .infinity
        suite.expect(noisyError < 0.15, "with a noise of 0.1 the function is still found (worst error \(noisyError))")
        suite.expect(fitted.residualSD > 0.07 && fitted.residualSD < 0.16,
                     "the cross-validated residual spread measures the noise (\(fitted.residualSD) for 0.1)")
    }

    private static func lambdaChoice(_ suite: TestSuite) {
        var random = Fixtures.Random(seed: 2)
        var cleanInputs: [[Double]] = [], cleanTargets: [Double] = []
        for _ in 0..<80 {
            let a = random.uniform(-2, 2), b = random.uniform(-2, 2)
            cleanInputs.append([a, b])
            cleanTargets.append(f(a, b))
        }
        // Six components, few rows, targets with no relation to them: the
        // best guess is the mean, so the strongest shrinkage should win.
        var noiseInputs: [[Double]] = [], noiseTargets: [Double] = []
        for _ in 0..<14 {
            noiseInputs.append((0..<6).map { _ in random.gaussian() })
            noiseTargets.append(random.gaussian())
        }
        let clean = try? ForkGlanceRegression.crossValidated(inputs: cleanInputs, targets: cleanTargets)
        let noise = try? ForkGlanceRegression.crossValidated(inputs: noiseInputs, targets: noiseTargets)
        suite.expect(clean?.model.lambda == ForkGlanceRegression.defaultLambdas.first,
                     "a clean signal keeps the lightest shrinkage (λ = \(clean?.model.lambda ?? -1))")
        suite.expect((noise?.model.lambda ?? 0) >= 0.3,
                     "targets without signal pick a strong shrinkage (λ = \(noise?.model.lambda ?? -1))")
        let only = try? ForkGlanceRegression.crossValidated(inputs: cleanInputs, targets: cleanTargets, lambdas: [0.1])
        suite.expect(only?.model.lambda == 0.1, "the λ ladder given is the one searched")
    }

    private static func groupedFolds(_ suite: TestSuite) {
        // Ten points, twelve near-identical samples each, each point's target
        // off the trend by its own error: only folds that keep a point's
        // samples together see that error.
        var random = Fixtures.Random(seed: 3)
        var inputs: [[Double]] = [], targets: [Double] = [], groups: [Int] = []
        for point in 0..<10 {
            let a = random.uniform(-2, 2), b = random.uniform(-2, 2)
            let offset = 0.5 * random.gaussian()
            for _ in 0..<12 {
                inputs.append([a + 0.001 * random.gaussian(), b + 0.001 * random.gaussian()])
                targets.append(f(a, b) + offset)
                groups.append(point)
            }
        }
        let leaky = try? ForkGlanceRegression.crossValidated(inputs: inputs, targets: targets)
        let honest = try? ForkGlanceRegression.crossValidated(inputs: inputs, targets: targets, groups: groups)
        suite.expect((honest?.residualSD ?? 0) > 1.5 * (leaky?.residualSD ?? .infinity),
                     "a point's samples stay in one fold, so σ is not flattered "
                        + "(\(honest?.residualSD ?? -1) grouped, \(leaky?.residualSD ?? -1) mixed)")
        var fewGroups = groups
        for index in fewGroups.indices { fewGroups[index] = fewGroups[index] % 5 }
        suite.expect((try? ForkGlanceRegression.crossValidated(inputs: inputs, targets: targets, groups: fewGroups)) == nil,
                     "fewer than six groups is too few points, whatever the number of samples")
    }

    private static func weights(_ suite: TestSuite) {
        var random = Fixtures.Random(seed: 4)
        var inputs: [[Double]] = [], targets: [Double] = [], weights: [Double] = []
        for _ in 0..<40 {
            let a = random.uniform(-1, 1), b = random.uniform(-1, 1)
            inputs.append([a, b]); targets.append(0); weights.append(1)
            inputs.append([a, b]); targets.append(10); weights.append(9)
        }
        let model = try? ForkGlanceRegression.fit(inputs: inputs, targets: targets, weights: weights, lambda: 1e-3)
        suite.expectClose(model?.predict([0, 0]) ?? 0, 9, "rows weigh by their weight", tol: 0.05)
        let zero = (try? ForkGlanceRegression.fit(inputs: inputs, targets: targets,
                                                  weights: Array(repeating: 0, count: inputs.count), lambda: 0.1))
        suite.expect(zero == nil, "rows without weight teach nothing")
    }

    private static func degenerate(_ suite: TestSuite) {
        func error(_ body: () throws -> Void) -> ForkGlanceRegressionError? {
            do { try body(); return nil } catch { return error as? ForkGlanceRegressionError }
        }
        let five = (0..<5).map { [Double($0), Double($0 * $0)] }
        suite.expect(error { _ = try ForkGlanceRegression.fit(inputs: five, targets: [1, 2, 3, 4, 5], lambda: 0.1) }
                        == .tooFewPoints, "five points are too few")
        let aligned = (0..<12).map { [Double($0), 2 * Double($0) + 1] }
        let targets = (0..<12).map(Double.init)
        suite.expect(error { _ = try ForkGlanceRegression.fit(inputs: aligned, targets: targets, lambda: 0.1) }
                        == .degenerate, "inputs on a line are degenerate")
        suite.expect(error { _ = try ForkGlanceRegression.crossValidated(inputs: aligned, targets: targets) }
                        == .degenerate, "the cross-validation refuses them too")
        let same = Array(repeating: [0.3, 0.7], count: 12)
        suite.expect(error { _ = try ForkGlanceRegression.fit(inputs: same, targets: targets, lambda: 0.1) }
                        == .degenerate, "a head that never moved is degenerate")
        var ragged = (0..<12).map { [Double($0), Double($0 % 3)] }
        ragged[4] = [1]
        suite.expect(error { _ = try ForkGlanceRegression.fit(inputs: ragged, targets: targets, lambda: 0.1) }
                        == .degenerate, "rows of different lengths are degenerate")
        var infinite = (0..<12).map { [Double($0), Double($0 % 3)] }
        infinite[2][1] = .nan
        suite.expect(error { _ = try ForkGlanceRegression.fit(inputs: infinite, targets: targets, lambda: 0.1) }
                        == .degenerate, "a non-finite value is degenerate")
        suite.expect(error { _ = try ForkGlanceRegression.fit(inputs: [], targets: [], lambda: 0.1) } == .tooFewPoints,
                     "no rows at all are too few points")
    }
}

/// Shared by the A3 suites (regression, calibration, learning, classifier):
/// a seeded random source, the Annex A layout and a synthetic person.
enum ForkGlanceModelFixtures {
    /// SplitMix64: the same numbers on every run.
    struct Random {
        private var state: UInt64

        init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 1 }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        /// In [0, 1).
        mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

        mutating func uniform(_ low: Double, _ high: Double) -> Double { low + (high - low) * unit() }

        /// Standard normal (Box–Muller).
        mutating func gaussian() -> Double {
            let u = max(unit(), 1e-12), v = unit()
            return (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
        }
    }

    // MARK: Annex A

    static let lg = ForkGlanceDisplay(uuid: "LG-UUID", name: "LG HDR WQHD", frame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
                                      millimeters: CGSize(width: 816, height: 338))
    static let macBook = ForkGlanceDisplay(uuid: "MB-UUID", name: "Built-in",
                                           frame: CGRect(x: 938, y: 1440, width: 1728, height: 1117),
                                           millimeters: CGSize(width: 344, height: 222), isBuiltIn: true, hasNotch: true)
    static let annex = ForkGlanceDisplayLayout(displays: [lg, macBook])
    static let lgLeft = ForkGlanceZone(id: "LG-UUID#0", displayUUID: "LG-UUID",
                                       rect: CGRect(x: 0, y: 0, width: 1720, height: 1440), position: .left)
    static let lgRight = ForkGlanceZone(id: "LG-UUID#1", displayUUID: "LG-UUID",
                                        rect: CGRect(x: 1720, y: 0, width: 1720, height: 1440), position: .right)
    static let macBookZone = ForkGlanceZone(id: "MB-UUID#0", displayUUID: "MB-UUID",
                                            rect: CGRect(x: 938, y: 1440, width: 1728, height: 1117), position: .whole)
    static let annexZones = [lgLeft, lgRight, macBookZone]

    /// Two 1920 × 1080 displays side by side.
    static let sideBySide = ForkGlanceDisplayLayout(displays: [
        ForkGlanceDisplay(uuid: "A", name: "A", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
        ForkGlanceDisplay(uuid: "B", name: "B", frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080)),
    ])

    /// The Annex A calibration points: 5 × 3 on the LG, 3 × 3 on the
    /// MacBook, 3 on the LG's middle border and 3 on the LG | MacBook border.
    static func annexTargets() -> [CGPoint] {
        var targets: [CGPoint] = []
        for fy in [0.1, 0.5, 0.9] {
            for fx in [0.1, 0.3, 0.5, 0.7, 0.9] { targets.append(CGPoint(x: 3440 * fx, y: 1440 * fy)) }
        }
        for fy in [0.1, 0.5, 0.9] {
            for fx in [0.1, 0.5, 0.9] { targets.append(CGPoint(x: 938 + 1728 * fx, y: 1440 + 1117 * fy)) }
        }
        for fy in [0.1, 0.5, 0.9] { targets.append(CGPoint(x: 1720, y: 1440 * fy)) }
        for fx in [0.2, 0.5, 0.8] { targets.append(CGPoint(x: 938 + 1728 * fx, y: 1440)) }
        return targets
    }

    /// A 3 × 3 grid on each side-by-side display.
    static func sideBySideTargets() -> [CGPoint] {
        var targets: [CGPoint] = []
        for originX in [0.0, 1920.0] {
            for fy in [0.1, 0.5, 0.9] {
                for fx in [0.1, 0.5, 0.9] { targets.append(CGPoint(x: originX + 1920 * fx, y: 1080 * fy)) }
            }
        }
        return targets
    }

    /// A synthetic person: the head turns with x, tilts a little with y, the
    /// eyes follow y. `headPitch` 0 is a person who only moves their eyes
    /// vertically; `eyeSignal` 0 is eyes that say nothing.
    struct Person {
        var camera = CGPoint(x: 1802, y: 1440)
        var headPitch = 0.5
        var eyeSignal = 1.0
        var angleNoise = 0.01
        var eyeNoise = 0.01

        func sample(looking target: CGPoint, time: TimeInterval = 0, confidence: Double = 0.9,
                    random: inout Random) -> ForkGlanceSample {
            let x = Double(target.x - camera.x) / 2600, y = Double(target.y - camera.y) / 2600
            var vector = Array(repeating: 0.0, count: ForkGlanceVectorLayout.count)
            vector[ForkGlanceVectorLayout.yaw] = x + 0.05 * y * y + angleNoise * random.gaussian()
            vector[ForkGlanceVectorLayout.pitch] = headPitch * y + angleNoise * random.gaussian()
            vector[ForkGlanceVectorLayout.roll] = angleNoise * random.gaussian()
            vector[ForkGlanceVectorLayout.centerX] = 0.5 - 0.05 * x + 0.002 * random.gaussian()
            vector[ForkGlanceVectorLayout.centerY] = 0.5 + 0.03 * headPitch * y + 0.002 * random.gaussian()
            vector[ForkGlanceVectorLayout.size] = 0.12 + 0.001 * random.gaussian()
            let eyeY = 0.5 + eyeSignal * 0.35 * y
            let eyeX = 0.5 + eyeSignal * 0.1 * x
            vector[ForkGlanceVectorLayout.leftEyeX] = eyeX + eyeNoise * random.gaussian()
            vector[ForkGlanceVectorLayout.leftEyeY] = eyeY + eyeNoise * random.gaussian()
            vector[ForkGlanceVectorLayout.rightEyeX] = eyeX + eyeNoise * random.gaussian()
            vector[ForkGlanceVectorLayout.rightEyeY] = eyeY + eyeNoise * random.gaussian()
            vector[ForkGlanceVectorLayout.openness] = 0.3 + eyeSignal * 0.05 * y + 0.005 * random.gaussian()
            return ForkGlanceSample(time: time, vector: vector, confidence: confidence, eyesUsable: true,
                                    facePresent: true)
        }

        func points(_ targets: [CGPoint], samples: Int = 10, random: inout Random) -> [ForkGlanceCalibrationPoint] {
            targets.map { target in
                ForkGlanceCalibrationPoint(target: target,
                                           samples: (0..<samples).map { _ in sample(looking: target, random: &random) })
            }
        }
    }

    static let date = Date(timeIntervalSince1970: 1_792_750_000) // 23/10/2026, a fixed instant

    static func fit(_ points: [ForkGlanceCalibrationPoint], layout: ForkGlanceDisplayLayout = annex,
                    usesEyes: Bool? = nil,
                    learned: [(ForkGlanceCalibrationPoint, Double)] = []) -> ForkGlanceCalibration? {
        try? ForkGlanceCalibrationModel.fit(points: points, learned: learned, usesEyes: usesEyes, layout: layout,
                                            cameraID: "camera", layoutSignature: "signature", date: date)
    }
}
