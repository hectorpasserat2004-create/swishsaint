// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

/// Glance Focus: what Vision saw (`ForkGlanceObservation`) as the raw vector
/// of `ForkGlanceVectorLayout` (plan §8.1), before the One Euro filter
/// (`ForkGlanceFilter`) and before the calibration reduces it.
///
/// ```
///   [yaw, pitch, roll]   radians, as Vision gives them
///   [cx, cy]             face center, image-normalized (origin bottom left)
///   [s]                  distance between the eyes, image-normalized
///   [exL, eyL, exR, eyR] each pupil inside its eye outline, 0…1, in the eye's
///                        own frame (turned by the roll), so tilting the head
///                        does not read as looking up or down
///   [open]               eye opening, outline height over width, both eyes
/// ```
///
/// The eyes are usable only with both outlines, both pupils inside them, and
/// an opening above `blinkRatio` of the rolling median: a blink, a squint
/// against the light or a lost pupil freezes the eye components at their last
/// usable value and says so (`eyesUsable`), the head components keep going.
/// No image, no identity: only geometry crosses this type.
struct ForkGlanceFeatures {
    /// Below this share of the rolling median opening, the eyes are closing.
    static let blinkRatio = 0.35
    /// Openings kept for the median (3 to 15 s at the adaptive rates).
    static let opennessWindow = 45
    /// The blink test waits for this many openings.
    static let opennessWarmup = 5
    /// A pupil this far outside its outline (share of the outline) is doubtful.
    static let pupilSlack = 0.25
    /// Eye distance over face box width before both eyes were ever seen.
    static let defaultEyeSpanRatio = 0.4
    /// Below this face box width (image share) the face is too far or partial.
    static let smallFaceWidth = 0.08

    private var last: [Double]?
    private var openings: [Double] = []
    private var eyeSpanRatio = defaultEyeSpanRatio

    init() {}

    /// One sample per processed image; `nil`: Vision found no face.
    mutating func sample(from observation: ForkGlanceObservation?, time: TimeInterval) -> ForkGlanceSample {
        typealias L = ForkGlanceVectorLayout
        guard let observation, observation.faceBox.width > 0, observation.faceBox.height > 0 else {
            return ForkGlanceSample(time: time, vector: last ?? Self.neutral, confidence: 0,
                                    eyesUsable: false, facePresent: false)
        }
        var vector = last ?? Self.neutral
        let box = observation.faceBox

        vector[L.yaw] = observation.yaw ?? vector[L.yaw]
        vector[L.pitch] = observation.pitch ?? vector[L.pitch]
        vector[L.roll] = observation.roll ?? vector[L.roll]
        vector[L.centerX] = Double(box.midX)
        vector[L.centerY] = Double(box.midY)

        let eyes = Self.eyes(observation)
        if let span = eyes.span {
            vector[L.size] = span
            // Keeps the face box fallback on the same scale when the eyes drop out.
            let ratio = span / Double(box.width)
            if ratio.isFinite, ratio > 0 { eyeSpanRatio += 0.1 * (ratio - eyeSpanRatio) }
        } else {
            vector[L.size] = Double(box.width) * eyeSpanRatio
        }

        var eyesUsable = false
        if let left = eyes.left, let right = eyes.right {
            let opening = (left.openness + right.openness) / 2
            let blinking = openings.count >= Self.opennessWarmup
                && opening < Self.blinkRatio * Self.median(openings)
            openings.append(opening)
            if openings.count > Self.opennessWindow { openings.removeFirst(openings.count - Self.opennessWindow) }
            if !blinking {
                eyesUsable = true
                vector[L.leftEyeX] = left.x
                vector[L.leftEyeY] = left.y
                vector[L.rightEyeX] = right.x
                vector[L.rightEyeY] = right.y
                vector[L.openness] = opening
            }
        }

        last = vector
        return ForkGlanceSample(time: time, vector: vector, confidence: Self.confidence(observation),
                                eyesUsable: eyesUsable, facePresent: true)
    }

    // MARK: - Pieces

    /// Before any face: centered, eyes looking ahead.
    private static let neutral: [Double] = {
        var vector = [Double](repeating: 0, count: ForkGlanceVectorLayout.count)
        vector[ForkGlanceVectorLayout.centerX] = 0.5
        vector[ForkGlanceVectorLayout.centerY] = 0.5
        for index in [ForkGlanceVectorLayout.leftEyeX, ForkGlanceVectorLayout.leftEyeY,
                      ForkGlanceVectorLayout.rightEyeX, ForkGlanceVectorLayout.rightEyeY] { vector[index] = 0.5 }
        return vector
    }()

    /// How much to trust this image: a face, its angles, alone, large enough,
    /// inside the frame, and the capture quality when the assistant asked for it.
    static func confidence(_ observation: ForkGlanceObservation) -> Double {
        var confidence = 1.0
        if observation.yaw == nil || observation.pitch == nil { confidence *= 0.5 }
        if observation.faceCount > 1 {
            // A second face as large as the kept one halves it; a small one far behind barely counts.
            confidence *= 1 - 0.5 * min(max(observation.otherFaceRatio, 0), 1)
        }
        let width = Double(observation.faceBox.width)
        if width < smallFaceWidth { confidence *= max(width, 0) / smallFaceWidth }
        let box = observation.faceBox
        if box.minX < 0 || box.minY < 0 || box.maxX > 1 || box.maxY > 1 { confidence *= 0.7 }
        if let quality = observation.captureQuality { confidence *= 0.6 + 0.4 * min(max(quality, 0), 1) }
        return min(max(confidence, 0), 1)
    }

    struct Eye: Equatable {
        /// Pupil inside the outline, 0…1, along and across the eye.
        var x: Double
        var y: Double
        /// Outline height over width.
        var openness: Double
    }

    /// Both eyes in their own frame, and the distance between them.
    private static func eyes(_ observation: ForkGlanceObservation) -> (left: Eye?, right: Eye?, span: Double?) {
        guard let leftCenter = centroid(observation.leftEye), let rightCenter = centroid(observation.rightEye) else {
            return (nil, nil, nil)
        }
        var dx = Double(rightCenter.x - leftCenter.x)
        var dy = Double(rightCenter.y - leftCenter.y)
        // The eye axis read left to right in the image, whichever eye Vision calls left.
        if dx < 0 { dx = -dx; dy = -dy }
        let span = (dx * dx + dy * dy).squareRoot()
        let angle = atan2(dy, dx)
        let left = observation.leftPupil.flatMap { eye(observation.leftEye, pupil: $0, angle: angle) }
        let right = observation.rightPupil.flatMap { eye(observation.rightEye, pupil: $0, angle: angle) }
        return (left, right, span > 0 ? span : nil)
    }

    /// The pupil inside the outline once the outline is turned upright by `angle`.
    static func eye(_ outline: [CGPoint], pupil: CGPoint, angle: Double) -> Eye? {
        guard outline.count >= 3, let center = centroid(outline) else { return nil }
        let cosine = cos(-angle)
        let sine = sin(-angle)
        func upright(_ point: CGPoint) -> (x: Double, y: Double) {
            let x = Double(point.x - center.x)
            let y = Double(point.y - center.y)
            return (x * cosine - y * sine, x * sine + y * cosine)
        }
        let points = outline.map(upright)
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return nil }
        let width = maxX - minX
        let height = maxY - minY
        guard width > 1e-6 else { return nil }
        let openness = height / width
        let turned = upright(pupil)
        let x = (turned.x - minX) / width
        // A closed eye has no height: the opening says it, the position stays centered.
        let y = height > 1e-6 ? (turned.y - minY) / height : 0.5
        let slack = pupilSlack
        guard x >= -slack, x <= 1 + slack, y >= -slack, y <= 1 + slack else { return nil }
        return Eye(x: min(max(x, 0), 1), y: min(max(y, 0), 1), openness: openness)
    }

    private static func centroid(_ points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }
}
