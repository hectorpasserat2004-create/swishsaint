// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

/// Suite `fork-glance-classifier` — A3: point to zone with margins and hysteresis.
enum ForkGlanceClassifierTests {
    static func run(_ suite: TestSuite) {
        entry(suite)
        stay(suite)
        sensitivity(suite)
        edges(suite)
        away(suite)
        faces(suite)
        pingPong(suite)
        windows(suite)
    }

    private typealias Fixtures = ForkGlanceModelFixtures

    /// σ of the Annex A tests: 60 pt across, 80 pt up and down.
    private static let sigma = CGSize(width: 60, height: 80)
    /// The default sensitivity step: an entry bar of 1.4 σ.
    private static let s = ForkGlanceTuning.sensitivity.defaultValue

    private static func estimate(_ x: Double, _ y: Double, time: TimeInterval = 0) -> ForkGlanceEstimate {
        ForkGlanceEstimate(point: CGPoint(x: x, y: y), sigma: sigma, time: time, confidence: 0.9)
    }

    private static func sample(yaw: Double = 0, pitch: Double = 0, confidence: Double = 0.9,
                               face: Bool = true, others: Double = 0) -> ForkGlanceSample {
        var vector = Array(repeating: 0.0, count: ForkGlanceVectorLayout.count)
        vector[ForkGlanceVectorLayout.yaw] = yaw
        vector[ForkGlanceVectorLayout.pitch] = pitch
        return ForkGlanceSample(time: 0, vector: vector, confidence: confidence, eyesUsable: true, facePresent: face,
                                otherFaceRatio: others)
    }

    /// Only the yaw and pitch spans matter to the classifier.
    private static let calibration = ForkGlanceCalibration(
        version: 1, date: Fixtures.date, cameraID: "c", layoutSignature: "s", usesEyes: true, coefficientsX: [],
        coefficientsY: [], normalization: [], sigma: sigma, bias: .zero, yawRange: -0.6...0.6,
        pitchRange: -0.3...0.2, zoneAccuracy: [:])

    private static func target(_ x: Double, _ y: Double, current: String?, sensitivity: Double = s,
                               classifier: inout ForkGlanceClassifier, time: TimeInterval = 0,
                               sample given: ForkGlanceSample? = nil) -> ForkGlanceGazeTarget {
        classifier.classify(estimate(x, y, time: time), sample: given ?? sample(), zones: Fixtures.annexZones,
                            layout: Fixtures.annex, calibration: calibration, current: current,
                            sensitivity: sensitivity, headSpeed: 0).target
    }

    private static func target(_ x: Double, _ y: Double, current: String?,
                               sensitivity: Double = s) -> ForkGlanceGazeTarget {
        var classifier = ForkGlanceClassifier()
        return target(x, y, current: current, sensitivity: sensitivity, classifier: &classifier)
    }

    private static let left = Fixtures.lgLeft.id, right = Fixtures.lgRight.id, macBook = Fixtures.macBookZone.id

    private static func entry(_ suite: TestSuite) {
        suite.expect(target(2600, 700, current: left) == .zone(right), "a glance deep in the LG's right half enters it")
        suite.expect(target(1720 + 1.5 * 60, 700, current: left) == .zone(right), "1.5 σ past the border enters")
        suite.expect(target(1720 + 1.2 * 60, 700, current: left) == .between,
                     "1.2 σ past the border is not enough to enter, nor close enough to stay: between")
        suite.expect(target(2600, 700, current: nil) == .zone(right), "with no current zone, a clear glance enters")
        suite.expect(target(1800, 2000, current: right) == .zone(macBook), "looking down at the MacBook enters it")
        suite.expect(target(1800, 1440 + 1.2 * 80, current: right) == .between,
                     "the LG | MacBook border is measured in the vertical σ")
        var classifier = ForkGlanceClassifier()
        let gaze = classifier.classify(estimate(2600, 700), sample: sample(), zones: Fixtures.annexZones,
                                       layout: Fixtures.annex, calibration: calibration, current: left,
                                       sensitivity: s, headSpeed: 12)
        suite.expectClose(gaze.margin, (1440 - 700) / 80.0,
                          "the margin is the distance to the nearest counted border, in that border's σ")
        suite.expect(gaze.headSpeed == 12 && gaze.estimate == estimate(2600, 700) && gaze.confidence == 0.9,
                     "the gaze carries the head speed, the estimate and the confidence")
    }

    private static func stay(_ suite: TestSuite) {
        suite.expect(target(1720 + 0.5 * 60, 700, current: left) == .zone(left),
                     "the current zone holds 0.5 σ past its border")
        suite.expect(target(1720 + 0.7 * 60, 700, current: left) == .between,
                     "0.7 σ past it, the current zone lets go (between, nothing switches)")
        suite.expect(target(1720 - 0.5 * 60, 700, current: right) == .zone(right),
                     "the hysteresis works both ways")
        suite.expect(target(1720 + 0.3 * 60, 700, current: nil) == .between,
                     "without a current zone, a point on the border is between")
    }

    private static func sensitivity(_ suite: TestSuite) {
        let lively = ForkGlanceTuning.sensitivity.steps.last!
        let prudent = ForkGlanceTuning.sensitivity.steps.first!
        suite.expect(target(1720 + 1.2 * 60, 700, current: left, sensitivity: lively) == .zone(right),
                     "the liveliest step enters at 1.2 σ")
        suite.expect(target(1720 + 1.8 * 60, 700, current: left, sensitivity: prudent) == .between,
                     "the most prudent step does not enter at 1.8 σ")
        suite.expect(target(1720 + 2 * 60, 700, current: left, sensitivity: prudent) == .zone(right),
                     "but does at 2 σ")
    }

    private static func edges(_ suite: TestSuite) {
        suite.expect(target(2600, 10, current: left) == .zone(right),
                     "the menu bar of the right half enters it: the LG's top faces no display")
        suite.expect(target(-60, 700, current: right) == .zone(left),
                     "just left of the LG still reads as its left half: its outer edge does not count")
        let open = ForkGlanceClassifier.openEdges(of: Fixtures.lgLeft, layout: Fixtures.annex)
        suite.expect(open.left && open.top && !open.right && !open.bottom,
                     "the LG's left half is open on the left and top, closed toward the right half and the MacBook")
        let book = ForkGlanceClassifier.openEdges(of: Fixtures.macBookZone, layout: Fixtures.annex)
        suite.expect(book.left && book.right && book.bottom && !book.top, "the MacBook is closed only toward the LG")
        let lone = ForkGlanceZone(id: "X#0", displayUUID: "X", rect: CGRect(x: 0, y: 0, width: 100, height: 100),
                                  position: .whole)
        suite.expectClose(ForkGlanceClassifier.score(CGPoint(x: 50, y: 50), in: lone, sigmaX: 60, sigmaY: 80,
                                                     layout: Fixtures.annex), 50 / 80.0,
                          "a zone off every display keeps all its edges")
    }

    private static func away(_ suite: TestSuite) {
        suite.expect(target(1800, 2600, current: macBook) == .away, "below the MacBook (the keyboard) is away")
        suite.expect(target(1800, 2565, current: right) == .away, "even just below the lowest display's edge")
        suite.expect(target(-200, 700, current: left) == .away, "3 σ left of every display is away")
        suite.expect(target(1720, -200, current: left) == .away, "2.5 σ above the LG is away")
        suite.expect(target(3000, 1500, current: right) == .between,
                     "beside the MacBook, under the LG, within 1.5 σ: between, not away")
        var classifier = ForkGlanceClassifier()
        let turned = sample(yaw: 0.6 + 16 * .pi / 180)
        suite.expect(target(2600, 700, current: left, classifier: &classifier, sample: turned) == .away,
                     "a head turned 16° past the calibrated yaw is away, wherever the point lands")
        let almost = sample(yaw: 0.6 + 14 * .pi / 180)
        suite.expect(target(2600, 700, current: left, classifier: &classifier, sample: almost) == .zone(right),
                     "14° past it is not")
        let down = sample(pitch: -0.3 - 16 * .pi / 180)
        suite.expect(target(1800, 2000, current: right, classifier: &classifier, sample: down) == .away,
                     "a head bowed past the calibrated pitch is away")
        let uncalibrated = classifier.classify(estimate(2600, 700), sample: turned, zones: Fixtures.annexZones,
                                               layout: Fixtures.annex, calibration: nil, current: left,
                                               sensitivity: s, headSpeed: 0)
        suite.expect(uncalibrated.target == .zone(right), "without a calibration, only the point counts")
    }

    private static func faces(_ suite: TestSuite) {
        var classifier = ForkGlanceClassifier()
        let none = classifier.classify(nil, sample: nil, zones: Fixtures.annexZones, layout: Fixtures.annex,
                                       calibration: calibration, current: left, sensitivity: s, headSpeed: 0)
        suite.expect(none.target == .noFace && none.margin == 0 && none.confidence == 0, "no estimate is no face")
        let lost = classifier.classify(estimate(2600, 700), sample: sample(face: false), zones: Fixtures.annexZones,
                                       layout: Fixtures.annex, calibration: calibration, current: left,
                                       sensitivity: s, headSpeed: 0)
        suite.expect(lost.target == .noFace, "a sample without a face is no face")
        let crowded = classifier.classify(estimate(2600, 700), sample: sample(others: 0.8),
                                          zones: Fixtures.annexZones, layout: Fixtures.annex,
                                          calibration: calibration, current: left, sensitivity: s, headSpeed: 0)
        suite.expect(crowded.crowded && crowded.confidence == 0.9,
                     "another face over 70 % of the kept one's area reads as crowded")
        let clear = classifier.classify(estimate(2600, 700), sample: sample(confidence: 0.3, others: 0.5),
                                        zones: Fixtures.annexZones, layout: Fixtures.annex,
                                        calibration: calibration, current: left, sensitivity: s, headSpeed: 0)
        suite.expect(!clear.crowded, "a smaller face behind, or a low confidence alone, is not crowded")
        let data = try? JSONEncoder().encode(clear)
        suite.expect(data != nil, "a gaze encodes as JSON for the trace")
    }

    private static func pingPong(_ suite: TestSuite) {
        var classifier = ForkGlanceClassifier()
        classifier.noteSwitch(to: left, at: 0)
        classifier.noteSwitch(to: right, at: 10)
        classifier.noteSwitch(to: left, at: 11)
        suite.expectClose(classifier.extraEntry, 0.5, "A → B → A within 1.5 s raises the entry bar by 0.5")
        let point = 1720 + 1.6 * 60
        suite.expect(target(point, 700, current: left, classifier: &classifier, time: 20) == .between,
                     "while raised, 1.6 σ no longer enters")
        suite.expect(target(1720 + 0.5 * 60, 700, current: left, classifier: &classifier, time: 21) == .zone(left),
                     "the stay bar is unchanged")
        suite.expect(target(point, 700, current: left, classifier: &classifier, time: 41.5) == .zone(right)
                        && classifier.extraEntry == 0,
                     "30 s later the bar is back")

        var slow = ForkGlanceClassifier()
        slow.noteSwitch(to: left, at: 0)
        slow.noteSwitch(to: right, at: 10)
        slow.noteSwitch(to: left, at: 12)
        suite.expect(slow.extraEntry == 0, "a return after 2 s is a real change of mind, not a ping-pong")
        var tour = ForkGlanceClassifier()
        tour.noteSwitch(to: left, at: 0)
        tour.noteSwitch(to: right, at: 10)
        tour.noteSwitch(to: macBook, at: 10.5)
        suite.expect(tour.extraEntry == 0, "A → B → C is no ping-pong")
        tour.noteSwitch(to: right, at: 11)
        suite.expect(tour.extraEntry == 0.5, "B → C → B is one")
    }

    private static func windows(_ suite: TestSuite) {
        // Windows mode: a small window in front of a large one, listed front to back.
        let front = ForkGlanceZone(id: "win:2", displayUUID: "LG-UUID",
                                   rect: CGRect(x: 1000, y: 300, width: 800, height: 600), position: .window, windowID: 2)
        let back = ForkGlanceZone(id: "win:1", displayUUID: "LG-UUID",
                                  rect: CGRect(x: 0, y: 24, width: 3440, height: 1416), position: .window, windowID: 1)
        var classifier = ForkGlanceClassifier()
        func gaze(_ x: Double, _ y: Double, current: String?) -> ForkGlanceGazeTarget {
            classifier.classify(estimate(x, y), sample: sample(), zones: [front, back], layout: Fixtures.annex,
                                calibration: calibration, current: current, sensitivity: s, headSpeed: 0).target
        }
        suite.expect(gaze(1400, 600, current: "win:1") == .zone("win:2"),
                     "deep in a window in front, it wins over the one behind, current or not")
        suite.expect(gaze(2800, 600, current: "win:2") == .zone("win:1"), "outside it, the window behind")
    }
}
