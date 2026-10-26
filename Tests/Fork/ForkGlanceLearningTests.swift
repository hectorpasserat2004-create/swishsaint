// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

/// Suite `fork-glance-learning` — A3: learning from clicks, drift.
enum ForkGlanceLearningTests {
    static func run(_ suite: TestSuite) {
        buffer(suite)
        ageWeights(suite)
        calibrationFloor(suite)
        refitAcceptance(suite)
        drift(suite)
        persistence(suite)
    }

    private typealias Fixtures = ForkGlanceModelFixtures

    private static func sample(confidence: Double = 0.9, face: Bool = true) -> ForkGlanceSample {
        ForkGlanceSample(time: 0, vector: Array(repeating: 0.1, count: ForkGlanceVectorLayout.count),
                         confidence: confidence, eyesUsable: true, facePresent: face)
    }

    private static func buffer(_ suite: TestSuite) {
        var learning = ForkGlanceLearning()
        learning.add(sample(confidence: 0.69), click: CGPoint(x: 1, y: 1), at: Fixtures.date)
        learning.add(sample(face: false), click: CGPoint(x: 1, y: 1), at: Fixtures.date)
        suite.expect(learning.pairs.isEmpty && learning.pendingSinceRefit == 0,
                     "a click with a doubtful sample (under 0.7) or no face teaches nothing")
        learning.add(sample(confidence: 0.7), click: CGPoint(x: 1, y: 1), at: Fixtures.date)
        suite.expect(learning.pairs.count == 1, "a confident sample of 0.7 is kept")

        learning = ForkGlanceLearning()
        for index in 0..<(ForkGlanceLearning.capacity + 30) {
            learning.add(sample(), click: CGPoint(x: Double(index), y: 0), at: Fixtures.date)
        }
        suite.expect(learning.pairs.count == 400 && learning.pairs.first?.click.x == 30
                        && learning.pairs.last?.click.x == 429,
                     "past 400 pairs the oldest go first")
        learning.markRefit()
        for index in 0..<24 { learning.add(sample(), click: CGPoint(x: Double(index), y: 0), at: Fixtures.date) }
        suite.expect(learning.pendingSinceRefit == 24 && !learning.refitDue, "24 new pairs do not call for a refit")
        learning.add(sample(), click: .zero, at: Fixtures.date)
        suite.expect(learning.refitDue, "the 25th does")
        learning.markRefit()
        suite.expect(learning.pendingSinceRefit == 0 && !learning.refitDue && learning.pairs.count == 400,
                     "a refit resets the count, not the pairs")
        suite.expect(learning.points.count == 400 && learning.points.allSatisfy { $0.samples.count == 1 },
                     "each pair reads as a one-sample calibration point")
    }

    private static func ageWeights(_ suite: TestSuite) {
        var learning = ForkGlanceLearning()
        let now = Fixtures.date
        learning.add(sample(), click: CGPoint(x: 1, y: 0), at: now)
        learning.add(sample(), click: CGPoint(x: 2, y: 0), at: now.addingTimeInterval(-3 * 86_400))
        learning.add(sample(), click: CGPoint(x: 3, y: 0), at: now.addingTimeInterval(-6 * 86_400))
        learning.add(sample(), click: CGPoint(x: 4, y: 0), at: now.addingTimeInterval(3600))
        let weights = learning.weighted(now: now).map { $0.1 }
        suite.expectClose(weights[0], 1, "a fresh click weighs 1")
        suite.expectClose(weights[1], 0.5, "three days later, half")
        suite.expectClose(weights[2], 0.25, "six days later, a quarter")
        suite.expectClose(weights[3], 1, "a click dated in the future weighs 1, no more")
        suite.expect(learning.weighted(now: now).map { $0.0.target.x } == [1, 2, 3, 4],
                     "each weight goes with its click's point")
    }

    private static func calibrationFloor(_ suite: TestSuite) {
        let few = ForkGlanceLearning.balanced(calibrationWeight: 300, learned: [1, 1, 0.5])
        suite.expect(few == [1, 1, 0.5], "a few clicks keep their weight")
        let many = ForkGlanceLearning.balanced(calibrationWeight: 300, learned: Array(repeating: 1, count: 400))
        suite.expectClose(many.reduce(0, +), 300, "many clicks never outweigh the calibration points together")
        suite.expect(Set(many).count == 1, "the scaling keeps the clicks' relative weights")

        // 400 consistent clicks that all say « 300 pt more to the right » can
        // pull the model at most half-way: the calibration keeps its floor.
        var random = Fixtures.Random(seed: 20)
        let person = Fixtures.Person()
        let points = person.points(Fixtures.annexTargets(), random: &random)
        var learning = ForkGlanceLearning()
        for index in 0..<400 {
            let target = Fixtures.annexTargets()[index % 30]
            learning.add(person.sample(looking: target, random: &random),
                         click: CGPoint(x: target.x + 300, y: target.y), at: Fixtures.date)
        }
        guard let plain = Fixtures.fit(points),
              let pulled = Fixtures.fit(points, learned: learning.weighted(now: Fixtures.date)) else {
            suite.expect(false, "both fits succeed")
            return
        }
        let probe = person.sample(looking: CGPoint(x: 1000, y: 700), random: &random)
        let shift = Double((ForkGlanceCalibrationModel.estimate(probe, with: pulled)?.point.x ?? 0)
                           - (ForkGlanceCalibrationModel.estimate(probe, with: plain)?.point.x ?? 0))
        suite.expect(shift > 60 && shift < 200,
                     "the clicks move the model, the calibration holds it to about half-way (\(Int(shift)) of 300 pt)")
    }

    private static func refitAcceptance(_ suite: TestSuite) {
        var random = Fixtures.Random(seed: 21)
        let person = Fixtures.Person()
        let points = person.points(Fixtures.annexTargets(), random: &random)
        guard let old = Fixtures.fit(points),
              let error = ForkGlanceCalibrationModel.error(of: old, on: points) else {
            suite.expect(false, "the calibration fits")
            return
        }
        suite.expect(ForkGlanceLearning.accepts(old: old, new: old, calibrationPoints: points),
                     "a refit as good as the old one is kept")
        var slightly = old
        slightly.bias = CGVector(dx: 0.3 * error, dy: 0)
        suite.expect(ForkGlanceLearning.accepts(old: old, new: slightly, calibrationPoints: points),
                     "a refit a few percent worse on the calibration points is kept")
        var worse = old
        worse.bias = CGVector(dx: 0.8 * error, dy: 0)
        suite.expect(!ForkGlanceLearning.accepts(old: old, new: worse, calibrationPoints: points),
                     "a refit more than 15 % worse on the calibration points is refused")
        var broken = old
        broken.normalization = []
        suite.expect(!ForkGlanceLearning.accepts(old: old, new: broken, calibrationPoints: points),
                     "a refit that cannot be measured is refused")
        suite.expect(ForkGlanceLearning.accepts(old: broken, new: old, calibrationPoints: points),
                     "an old calibration that cannot be measured is replaced")
    }

    private static func drift(_ suite: TestSuite) {
        func record(agreeing: Int, of total: Int) -> ForkGlanceLearning {
            var learning = ForkGlanceLearning()
            for index in 0..<total {
                learning.recordAgreement(predicted: index < agreeing ? "A" : "B", clicked: "A")
            }
            return learning
        }
        suite.expect(ForkGlanceLearning().agreement == nil, "no click, no agreement")
        let good = record(agreeing: 50, of: 60)
        suite.expect(!good.driftSuggested(mode: .zones) && !good.driftSuggested(mode: .windows),
                     "83 % agreement is no drift")
        let fair = record(agreeing: 45, of: 60)
        suite.expect(fair.driftSuggested(mode: .zones) && fair.driftSuggested(mode: .screens)
                        && !fair.driftSuggested(mode: .windows),
                     "75 % is a drift in Screens and Zones, not yet in Windows")
        let poor = record(agreeing: 40, of: 60)
        suite.expect(poor.driftSuggested(mode: .windows), "67 % is a drift in Windows too")
        let early = record(agreeing: 10, of: 59)
        suite.expect(!early.driftSuggested(mode: .zones) && (early.agreement ?? 1) < 0.2,
                     "no drift before a full window of 60 clicks")

        var rolling = record(agreeing: 0, of: 60)
        for _ in 0..<60 { rolling.recordAgreement(predicted: "A", clicked: "A") }
        suite.expect(rolling.agreement == 1 && !rolling.driftSuggested(mode: .zones), "only the last 60 clicks count")
        rolling.recordAgreement(predicted: nil, clicked: "A")
        suite.expectClose(rolling.agreement ?? 0, 59.0 / 60, "a click with no predicted zone counts as a miss")
        rolling.resetAgreement()
        suite.expect(rolling.agreement == nil, "a new calibration starts the count again")
    }

    private static func persistence(_ suite: TestSuite) {
        var learning = ForkGlanceLearning()
        learning.add(sample(), click: CGPoint(x: 12, y: 34), at: Fixtures.date)
        learning.recordAgreement(predicted: "A", clicked: "B")
        let data = try? JSONEncoder().encode(learning)
        let back = data.flatMap { try? JSONDecoder().decode(ForkGlanceLearning.self, from: $0) }
        suite.expect(back == learning, "the clicks, the count and the agreement survive JSON")
        let empty = try? JSONDecoder().decode(ForkGlanceLearning.self, from: Data("{}".utf8))
        suite.expect(empty == ForkGlanceLearning(), "an empty file reads as no learning")
        learning.removeAll()
        suite.expect(learning == ForkGlanceLearning(), "forgetting removes the pairs, the count and the agreement")
    }
}
