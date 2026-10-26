// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

/// Suite `fork-glance-features` — A2: Vision observation to normalized vector.
enum ForkGlanceFeaturesTests {
    private typealias L = ForkGlanceVectorLayout

    static func run(_ suite: TestSuite) {
        head(suite)
        pupils(suite)
        roll(suite)
        blink(suite)
        missingPupils(suite)
        headOnly(suite)
        crowd(suite)
        noFace(suite)
    }

    // MARK: - A synthetic face

    /// An eye outline: an ellipse of `width` × `height` around `center`, turned by `angle`.
    private static func outline(_ center: CGPoint, width: Double, height: Double, angle: Double = 0) -> [CGPoint] {
        (0..<8).map { step in
            let t = Double(step) / 8 * 2 * .pi
            let x = cos(t) * width / 2
            let y = sin(t) * height / 2
            return CGPoint(x: Double(center.x) + x * cos(angle) - y * sin(angle),
                           y: Double(center.y) + x * sin(angle) + y * cos(angle))
        }
    }

    /// A point given in an eye's own frame (0…1 along and across), placed in the image.
    private static func inEye(_ center: CGPoint, width: Double, height: Double, x: Double, y: Double,
                              angle: Double = 0) -> CGPoint {
        let dx = (x - 0.5) * width
        let dy = (y - 0.5) * height
        return CGPoint(x: Double(center.x) + dx * cos(angle) - dy * sin(angle),
                       y: Double(center.y) + dx * sin(angle) + dy * cos(angle))
    }

    /// A face centered at (0.5, 0.55) with eyes `span` apart, pupils at (`x`, `y`)
    /// in each eye, eye height `height` (0.03 open, 0.004 closing).
    private static func face(time: TimeInterval = 0, yaw: Double? = 0.1, pitch: Double? = -0.05, roll: Double? = 0,
                             x: Double = 0.5, y: Double = 0.5, height: Double = 0.03, angle: Double = 0,
                             pupils: Bool = true, eyes: Bool = true, span: Double = 0.1, faceCount: Int = 1,
                             otherFaceRatio: Double = 0, quality: Double? = nil) -> ForkGlanceObservation {
        let mid = CGPoint(x: 0.5, y: 0.6)
        let half = span / 2
        let left = CGPoint(x: Double(mid.x) - half * cos(angle), y: Double(mid.y) - half * sin(angle))
        let right = CGPoint(x: Double(mid.x) + half * cos(angle), y: Double(mid.y) + half * sin(angle))
        let width = 0.04
        return ForkGlanceObservation(
            time: time, faceBox: CGRect(x: 0.375, y: 0.425, width: 0.25, height: 0.25),
            yaw: yaw, pitch: pitch, roll: roll,
            leftPupil: pupils && eyes ? inEye(left, width: width, height: height, x: x, y: y, angle: angle) : nil,
            rightPupil: pupils && eyes ? inEye(right, width: width, height: height, x: x, y: y, angle: angle) : nil,
            leftEye: eyes ? outline(left, width: width, height: height, angle: angle) : [],
            rightEye: eyes ? outline(right, width: width, height: height, angle: angle) : [],
            faceCount: faceCount, otherFaceRatio: otherFaceRatio, captureQuality: quality)
    }

    // MARK: - Cases

    private static func head(_ suite: TestSuite) {
        var features = ForkGlanceFeatures()
        let sample = features.sample(from: face(yaw: 0.2, pitch: -0.1, roll: 0.05), time: 3)
        suite.expect(sample.vector.count == L.count, "the vector has every component of the layout")
        suite.expect(sample.facePresent && sample.time == 3, "a face gives a present sample at the image's time")
        suite.expectClose(sample.vector[L.yaw], 0.2, "yaw passes in radians")
        suite.expectClose(sample.vector[L.pitch], -0.1, "pitch passes in radians")
        suite.expectClose(sample.vector[L.roll], 0.05, "roll passes in radians")
        suite.expectClose(sample.vector[L.centerX], 0.5, "the face center is the box's center (x)")
        suite.expectClose(sample.vector[L.centerY], 0.55, "the face center is the box's center (y)")
        suite.expectClose(sample.vector[L.size], 0.1, "the size is the distance between the eyes", tol: 1e-6)
        suite.expect(sample.confidence > 0.9, "one clear face with its angles is trusted")

        let partial = features.sample(from: face(yaw: nil, pitch: nil), time: 4)
        suite.expectClose(partial.vector[L.yaw], 0.2, "a missing yaw repeats the last one")
        suite.expect(partial.confidence <= 0.5, "a face without angles is half trusted at most")
    }

    private static func pupils(_ suite: TestSuite) {
        var features = ForkGlanceFeatures()
        let sample = features.sample(from: face(x: 0.75, y: 0.3), time: 0)
        suite.expect(sample.eyesUsable, "open eyes with both pupils are usable")
        suite.expectClose(sample.vector[L.leftEyeX], 0.75, "the left pupil sits at 75 % along its eye", tol: 1e-6)
        suite.expectClose(sample.vector[L.leftEyeY], 0.3, "the left pupil sits at 30 % up its eye", tol: 1e-6)
        suite.expectClose(sample.vector[L.rightEyeX], 0.75, "the right pupil sits at 75 % along its eye", tol: 1e-6)
        suite.expectClose(sample.vector[L.rightEyeY], 0.3, "the right pupil sits at 30 % up its eye", tol: 1e-6)
        suite.expectClose(sample.vector[L.openness], 0.03 / 0.04, "the opening is height over width", tol: 1e-6)
        let inside = [L.leftEyeX, L.leftEyeY, L.rightEyeX, L.rightEyeY].allSatisfy {
            (0...1).contains(sample.vector[$0])
        }
        suite.expect(inside, "pupil positions stay within 0…1")

        let past = features.sample(from: face(x: 1.1), time: 1)
        suite.expect(past.eyesUsable && past.vector[L.leftEyeX] == 1,
                     "a pupil slightly past the outline is clamped to its edge")
        let wild = features.sample(from: face(x: 2), time: 2)
        suite.expect(!wild.eyesUsable, "a pupil far outside its eye is doubtful")
    }

    private static func roll(_ suite: TestSuite) {
        var straight = ForkGlanceFeatures()
        var tilted = ForkGlanceFeatures()
        let a = straight.sample(from: face(x: 0.7, y: 0.6), time: 0)
        let b = tilted.sample(from: face(x: 0.7, y: 0.6, angle: 0.5), time: 0)
        let same = [L.leftEyeX, L.leftEyeY, L.rightEyeX, L.rightEyeY, L.openness, L.size].allSatisfy {
            abs(a.vector[$0] - b.vector[$0]) < 1e-6
        }
        suite.expect(same, "tilting the head changes neither the pupils' place in the eyes nor the eye distance")
    }

    private static func blink(_ suite: TestSuite) {
        var features = ForkGlanceFeatures()
        var open = features.sample(from: face(x: 0.6), time: 0)
        for frame in 1...10 { open = features.sample(from: face(x: 0.6), time: Double(frame) / 10) }
        let closing = features.sample(from: face(x: 0.9, y: 0.9, height: 0.004), time: 1.1)
        suite.expect(closing.facePresent && !closing.eyesUsable,
                     "an opening under 35 % of the median is a blink: the eyes are not usable")
        let frozen = (L.headCount..<L.count).allSatisfy { closing.vector[$0] == open.vector[$0] }
        suite.expect(frozen, "during a blink the eye components keep their last usable values")
        suite.expect(closing.confidence > 0.9, "a blink does not make the head less trustworthy")
        let back = features.sample(from: face(x: 0.6), time: 1.2)
        suite.expect(back.eyesUsable, "the eyes are usable again once they open")

        var squint = ForkGlanceFeatures()
        for frame in 0...10 { _ = squint.sample(from: face(height: 0.03), time: Double(frame) / 10) }
        let narrower = squint.sample(from: face(height: 0.015), time: 1.2)
        suite.expect(narrower.eyesUsable, "half-closed eyes (above 35 % of the median) stay usable")

        var fresh = ForkGlanceFeatures()
        let first = fresh.sample(from: face(height: 0.004), time: 0)
        suite.expect(first.eyesUsable, "without a median yet, no blink is declared")
    }

    private static func missingPupils(_ suite: TestSuite) {
        var features = ForkGlanceFeatures()
        let seen = features.sample(from: face(x: 0.2), time: 0)
        let lost = features.sample(from: face(yaw: 0.3, x: 0.8, pupils: false), time: 0.1)
        suite.expect(lost.facePresent && !lost.eyesUsable, "missing pupils make the eyes unusable, the face stays")
        suite.expect(lost.vector[L.leftEyeX] == seen.vector[L.leftEyeX],
                     "missing pupils freeze the eye components")
        suite.expectClose(lost.vector[L.yaw], 0.3, "the head keeps updating without pupils")
    }

    private static func headOnly(_ suite: TestSuite) {
        var features = ForkGlanceFeatures()
        let blind = features.sample(from: face(eyes: false), time: 0)
        suite.expect(!blind.eyesUsable && blind.facePresent, "without landmarks the eyes are not usable")
        suite.expect(blind.vector[L.size] > 0, "without landmarks the size comes from the face box")

        var learned = ForkGlanceFeatures()
        for frame in 0..<40 { _ = learned.sample(from: face(span: 0.12), time: Double(frame) / 10) }
        let dropped = learned.sample(from: face(eyes: false), time: 4)
        suite.expectClose(dropped.vector[L.size], 0.12, "once eyes were seen, the face box fallback keeps their scale",
                          tol: 0.003)
    }

    private static func crowd(_ suite: TestSuite) {
        var features = ForkGlanceFeatures()
        let alone = features.sample(from: face(), time: 0).confidence
        let behind = features.sample(from: face(faceCount: 2, otherFaceRatio: 0.1), time: 0.1).confidence
        let twin = features.sample(from: face(faceCount: 2, otherFaceRatio: 1), time: 0.2).confidence
        suite.expect(behind < alone && behind > 0.9, "a small face far behind barely lowers the confidence")
        suite.expect(twin <= 0.5 + 1e-9, "a second face as large as the kept one halves the confidence")
        suite.expect(features.sample(from: face(faceCount: 2, otherFaceRatio: 0.8), time: 0.25).otherFaceRatio == 0.8
                        && features.sample(from: face(), time: 0.26).otherFaceRatio == 0,
                     "the sample carries the other faces' size for the crowded guard")
        let poor = features.sample(from: face(quality: 0.1), time: 0.3).confidence
        let good = features.sample(from: face(quality: 0.9), time: 0.4).confidence
        suite.expect(poor < good, "a poor capture quality (assistant) lowers the confidence")
    }

    private static func noFace(_ suite: TestSuite) {
        var features = ForkGlanceFeatures()
        let none = features.sample(from: nil, time: 1)
        suite.expect(!none.facePresent && none.confidence == 0 && !none.eyesUsable,
                     "no face: absent, not trusted, eyes unusable")
        suite.expect(none.vector.count == L.count, "even without a face the vector has every component")
        let seen = features.sample(from: face(yaw: 0.4), time: 2)
        let gone = features.sample(from: nil, time: 3)
        suite.expect(!gone.facePresent && gone.vector == seen.vector && gone.time == 3,
                     "a lost face repeats the last vector at the new time")
        let empty = features.sample(from: ForkGlanceObservation(time: 4, faceBox: .zero), time: 4)
        suite.expect(!empty.facePresent, "an empty face box counts as no face")
    }
}
