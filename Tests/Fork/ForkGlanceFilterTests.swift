// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Suite `fork-glance-filter` — A2: the One Euro filter and the outlier rejection.
enum ForkGlanceFilterTests {
    private typealias L = ForkGlanceVectorLayout
    /// 12 images per second, the balanced rate with the head moving.
    private static let step = 1.0 / 12
    private static let degree = Double.pi / 180

    static func run(_ suite: TestSuite) {
        stepResponse(suite)
        ramp(suite)
        noise(suite)
        isolatedOutlier(suite)
        persistentOutlier(suite)
        headSpeed(suite)
        eyes(suite)
        gaps(suite)
    }

    /// A present face: `yaw` in radians, the other components still.
    private static func sample(_ frame: Int, yaw: Double = 0, centerX: Double = 0.5, eye: Double = 0.5,
                               eyesUsable: Bool = true, facePresent: Bool = true,
                               time: TimeInterval? = nil) -> ForkGlanceSample {
        var vector = [Double](repeating: 0.5, count: L.count)
        vector[L.yaw] = yaw
        vector[L.pitch] = 0
        vector[L.roll] = 0
        vector[L.centerX] = centerX
        vector[L.size] = 0.1
        vector[L.leftEyeX] = eye
        return ForkGlanceSample(time: time ?? Double(frame) * step, vector: vector, confidence: 1,
                                eyesUsable: eyesUsable, facePresent: facePresent)
    }

    /// A filter that saw `frames` still images at yaw 0.
    private static func settled(_ frames: Int = 24) -> ForkGlanceFilter {
        var filter = ForkGlanceFilter()
        for frame in 0..<frames { _ = filter.filter(sample(frame)) }
        return filter
    }

    private static func stepResponse(_ suite: TestSuite) {
        var filter = settled()
        let target = 5 * degree
        var outputs: [Double] = []
        for frame in 24..<48 { outputs.append(filter.filter(sample(frame, yaw: target)).vector[L.yaw]) }
        suite.expect(outputs[0] > 0 && outputs[0] < target / 2, "a step is smoothed: the first image moves less than half")
        suite.expect(zip(outputs, outputs.dropFirst()).allSatisfy { $0 <= $1 + 1e-12 },
                     "the response to a step only climbs")
        suite.expect(outputs.allSatisfy { $0 <= target + 1e-12 }, "the response to a step never overshoots")
        suite.expectClose(outputs[11], target, "within 1 s the output reaches the step", tol: target * 0.03)
    }

    private static func ramp(_ suite: TestSuite) {
        var filter = settled()
        let speed = 30 * degree
        var last = 0.0
        var climbing = true
        var output = 0.0
        var raw = 0.0
        for frame in 24..<60 {
            raw = Double(frame - 24) * step * speed
            output = filter.filter(sample(frame, yaw: raw)).vector[L.yaw]
            climbing = climbing && output >= last
            last = output
        }
        suite.expect(climbing, "a ramp is followed without going back")
        suite.expect(raw - output >= 0 && raw - output < 3 * degree,
                     "a 30°/s turn is followed within 3° (the filter opens with speed)")
        suite.expectClose(filter.headSpeed, 30, "the head speed of a 30°/s turn", tol: 3)
    }

    private static func noise(_ suite: TestSuite) {
        var random = Random(seed: 7)
        var filter = ForkGlanceFilter()
        var raws: [Double] = []
        var outputs: [Double] = []
        for frame in 0..<480 {
            let raw = random.gaussian() * 0.5 * degree
            let output = filter.filter(sample(frame, yaw: raw)).vector[L.yaw]
            if frame >= 24 {
                raws.append(raw)
                outputs.append(output)
            }
        }
        let ratio = deviation(outputs) / deviation(raws)
        suite.expect(ratio < 0.6, "jitter of a still head is cut by at least 40 % (got \(ratio))")
        suite.expect(abs(mean(outputs)) < 0.1 * degree, "smoothing keeps a still head where it is")
    }

    private static func isolatedOutlier(_ suite: TestSuite) {
        var filter = settled()
        let before = filter.filter(sample(24, yaw: 0, centerX: 0.5)).vector
        let odd = filter.filter(sample(25, yaw: 1.0, centerX: 0.51)).vector
        suite.expect(odd[L.yaw] == before[L.yaw], "a single 57° jump is dropped: the yaw keeps its value")
        suite.expect(odd[L.centerX] > before[L.centerX], "the other components still follow on that image")
        let after = filter.filter(sample(26, yaw: 0, centerX: 0.51)).vector
        suite.expect(abs(after[L.yaw]) < 0.1 * degree, "after a dropped outlier the yaw goes on as before")
    }

    private static func persistentOutlier(_ suite: TestSuite) {
        var filter = settled()
        let first = filter.filter(sample(24, yaw: 1.0)).vector[L.yaw]
        suite.expect(abs(first) < 1e-9, "the first image of a big jump is held back")
        let second = filter.filter(sample(25, yaw: 1.0)).vector[L.yaw]
        suite.expect(second > 0.3, "a jump that persists is accepted on the next image")
        var output = second
        for frame in 26..<48 { output = filter.filter(sample(frame, yaw: 1.0)).vector[L.yaw] }
        suite.expectClose(output, 1.0, "a persistent jump is reached", tol: 0.01)
    }

    private static func headSpeed(_ suite: TestSuite) {
        var filter = settled()
        suite.expect(filter.headSpeed < 1, "a still head has no speed")
        let speed = 40 * degree
        for frame in 24..<48 { _ = filter.filter(sample(frame, yaw: Double(frame - 24) * step * speed)) }
        suite.expect(filter.headSpeed > 20, "a 40°/s turn reads as moving (above 20°/s)")
        let stop = Double(23) * step * speed
        for frame in 48..<54 { _ = filter.filter(sample(frame, yaw: stop)) }
        suite.expect(filter.headSpeed < 20, "half a second after the head stops, it no longer reads as moving")
    }

    private static func eyes(_ suite: TestSuite) {
        var filter = settled()
        let open = filter.filter(sample(24, eye: 0.5)).vector[L.leftEyeX]
        var held = true
        var yaw = 0.0
        for frame in 25..<31 {
            let output = filter.filter(sample(frame, yaw: Double(frame - 24) * degree, eye: 0.9, eyesUsable: false))
            held = held && output.vector[L.leftEyeX] == open
            yaw = output.vector[L.yaw]
        }
        suite.expect(held, "unusable eyes keep the eye components at their last filtered value")
        suite.expect(yaw > 1 * degree, "the head goes on while the eyes are unusable")
        let back = filter.filter(sample(31, eye: 0.6)).vector[L.leftEyeX]
        suite.expect(back > open, "usable eyes move the eye components again")
    }

    private static func gaps(_ suite: TestSuite) {
        var filter = settled()
        let last = filter.filter(sample(24)).vector
        let lost = filter.filter(sample(25, yaw: 0.3, facePresent: false))
        suite.expect(!lost.facePresent && lost.vector == last, "no face repeats the last filtered vector")
        suite.expect(filter.headSpeed == 0, "no face: no head speed")

        let shortGap = filter.filter(sample(30, yaw: 3 * degree)).vector[L.yaw]
        suite.expect(shortGap < 3 * degree, "after a short loss the filter goes on smoothing")

        _ = filter.filter(sample(31, facePresent: false))
        let reborn = filter.filter(sample(0, yaw: 0.4, time: 31 * step + 1.5)).vector[L.yaw]
        suite.expectClose(reborn, 0.4, "after more than 1 s without a face the filter starts over")

        let duplicate = filter.filter(sample(0, yaw: 0.0, time: 31 * step + 1.5)).vector[L.yaw]
        suite.expectClose(duplicate, 0.4, "an image at the same time changes nothing")

        filter.reset()
        let fresh = filter.filter(sample(0, yaw: -0.2, time: 100)).vector[L.yaw]
        suite.expectClose(fresh, -0.2, "after a reset the first image passes as it is")
    }

    // MARK: - Helpers

    private static func mean(_ values: [Double]) -> Double { values.reduce(0, +) / Double(values.count) }

    private static func deviation(_ values: [Double]) -> Double {
        let center = mean(values)
        return (values.map { ($0 - center) * ($0 - center) }.reduce(0, +) / Double(values.count)).squareRoot()
    }

    /// Deterministic noise: a linear congruential generator and Box–Muller.
    private struct Random {
        var state: UInt64
        init(seed: UInt64) { state = seed }

        mutating func uniform() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return (Double(state >> 11) + 0.5) / Double(1 << 53)
        }

        mutating func gaussian() -> Double {
            (-2 * log(uniform())).squareRoot() * cos(2 * .pi * uniform())
        }
    }
}
