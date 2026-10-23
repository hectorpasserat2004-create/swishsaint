// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

// Glance Focus: from calibration points to a calibration, and from a sample
// to the point it looks at (plan §8.3). Each sample of a calibration point is
// one row (its vector, the point's target); the vector is reduced by the
// calibration's ranges, then one ridge regression per screen axis maps it to
// global points. σ is the cross-validated error, per axis.

enum ForkGlanceCalibrationModel {
    /// « Tête + yeux » is kept when its cross-validated error is at least this
    /// much lower than « tête seule » (plan §8.3).
    static let eyesGain = 0.10
    /// The recenter offset never goes past this share of the display's diagonal.
    static let maximumBiasShare = 0.15
    /// σ never goes below this, in points: a perfect fit would otherwise make
    /// every margin infinite.
    static let minimumSigma = 2.0
    /// A component that barely moves keeps a unit scale instead of blowing its
    /// noise up (`ForkGlanceRange.scale` is never 0).
    static let minimumScale = 1e-6
    /// Two displays are stacked when one lies below the other over at least
    /// this share of the narrower one's width.
    static let stackedOverlap = 0.25

    /// Fits both axes. `learned` pairs come weighted (`ForkGlanceLearning`),
    /// rebalanced so the calibration keeps its floor. `usesEyes` nil picks
    /// « tête + yeux » when the layout is stacked, or when it beats « tête
    /// seule » by `eyesGain` in cross-validation. The ranges, yaw and pitch
    /// spans come from the calibration points only: they describe the session
    /// the person sat through. Throws `tooFewPoints` under 6 usable points,
    /// `degenerate` when the targets lie on a line or the head never moved.
    static func fit(points: [ForkGlanceCalibrationPoint], learned: [(ForkGlanceCalibrationPoint, Double)] = [],
                    usesEyes: Bool?, layout: ForkGlanceDisplayLayout, cameraID: String, layoutSignature: String,
                    date: Date) throws -> ForkGlanceCalibration {
        let kept = points.filter { point in
            point.samples.contains { usable($0, width: ForkGlanceVectorLayout.headCount) }
        }
        guard kept.count >= ForkGlanceRegression.minimumPoints else { throw ForkGlanceRegressionError.tooFewPoints }
        guard ForkGlanceRegression.spansPlane(kept.map { [Double($0.target.x), Double($0.target.y)] }) else {
            throw ForkGlanceRegressionError.degenerate
        }

        let choice: Bool
        if let usesEyes {
            choice = usesEyes
        } else if stacked(layout) {
            choice = true
        } else {
            let head = try fitted(points: kept, learned: learned, usesEyes: false)
            if let eyes = try? fitted(points: kept, learned: learned, usesEyes: true),
               eyes.error <= head.error * (1 - eyesGain) {
                choice = true
            } else {
                return calibration(head, usesEyes: false, points: kept, cameraID: cameraID,
                                   layoutSignature: layoutSignature, date: date)
            }
        }
        let result = try fitted(points: kept, learned: learned, usesEyes: choice)
        return calibration(result, usesEyes: choice, points: kept, cameraID: cameraID,
                           layoutSignature: layoutSignature, date: date)
    }

    /// The point a sample looks at, the recenter bias included; nil without a
    /// face, or when the sample does not carry the components the calibration
    /// reads. The eye components of a blink already repeat their last value
    /// (`ForkGlanceSample.eyesUsable`), so a blink still gives an estimate.
    static func estimate(_ sample: ForkGlanceSample, with calibration: ForkGlanceCalibration) -> ForkGlanceEstimate? {
        guard sample.facePresent, let point = unbiasedPoint(sample, with: calibration) else { return nil }
        let sigma = CGSize(width: max(Double(calibration.sigma.width), minimumSigma),
                           height: max(Double(calibration.sigma.height), minimumSigma))
        return ForkGlanceEstimate(point: CGPoint(x: point.x + calibration.bias.dx, y: point.y + calibration.bias.dy),
                                  sigma: sigma, time: sample.time, confidence: sample.confidence)
    }

    /// « Recentrer »: the person looks at `target` (the pointer) while
    /// `samples` arrive (0.6 s). The mean offset between `target` and the
    /// unbiased estimates becomes the bias, its length bounded by
    /// `maximumBiasShare` of the diagonal of the display under `target`.
    /// Without a usable sample or a display, the calibration comes back as is.
    static func recentered(_ calibration: ForkGlanceCalibration, samples: [ForkGlanceSample], target: CGPoint,
                           layout: ForkGlanceDisplayLayout) -> ForkGlanceCalibration {
        recentered(calibration, points: [ForkGlanceCalibrationPoint(target: target, samples: samples)], layout: layout)
    }

    /// The same over several targets, the quick recalibration (one point per
    /// zone, plan §8.4): every sample counts once, the bound is the smallest
    /// diagonal among the targets' displays.
    static func recentered(_ calibration: ForkGlanceCalibration, points: [ForkGlanceCalibrationPoint],
                           layout: ForkGlanceDisplayLayout) -> ForkGlanceCalibration {
        var sumX = 0.0, sumY = 0.0, count = 0.0
        var diagonal = Double.infinity
        for point in points {
            let estimates = point.samples.filter(\.facePresent).compactMap { unbiasedPoint($0, with: calibration) }
            guard !estimates.isEmpty, let display = display(near: point.target, in: layout) else { continue }
            diagonal = min(diagonal, hypot(Double(display.frame.width), Double(display.frame.height)))
            for estimate in estimates {
                sumX += Double(point.target.x) - estimate.x
                sumY += Double(point.target.y) - estimate.y
                count += 1
            }
        }
        guard count > 0, diagonal.isFinite else { return calibration }
        var dx = sumX / count, dy = sumY / count
        let length = hypot(dx, dy), bound = maximumBiasShare * diagonal
        if length > bound {
            dx *= bound / length
            dy *= bound / length
        }
        var result = calibration
        result.bias = CGVector(dx: dx, dy: dy)
        return result
    }

    /// Displays one above the other (the Annex A setup: the MacBook under the
    /// LG): the head barely tilts between them, so the eyes help most there.
    static func stacked(_ layout: ForkGlanceDisplayLayout) -> Bool {
        let frames = layout.displays.map(\.frame).filter { !$0.isEmpty }
        for (index, upper) in frames.enumerated() {
            for lower in frames[(index + 1)...] {
                let overlap = min(upper.maxX, lower.maxX) - max(upper.minX, lower.minX)
                let narrower = min(upper.width, lower.width)
                let disjointVertically = upper.maxY <= lower.minY + 1 || lower.maxY <= upper.minY + 1
                if disjointVertically, narrower > 0, overlap >= stackedOverlap * narrower { return true }
            }
        }
        return false
    }

    /// Root mean square distance, in points, between the calibration's
    /// estimates and the targets, over every usable sample; nil when none is.
    static func error(of calibration: ForkGlanceCalibration, on points: [ForkGlanceCalibrationPoint]) -> Double? {
        var sum = 0.0, count = 0.0
        for point in points {
            for sample in point.samples {
                guard let estimate = estimate(sample, with: calibration) else { continue }
                let dx = Double(estimate.point.x - point.target.x), dy = Double(estimate.point.y - point.target.y)
                sum += dx * dx + dy * dy
                count += 1
            }
        }
        return count > 0 ? (sum / count).squareRoot() : nil
    }

    // MARK: Helpers

    private struct Fitted {
        var x: ForkGlanceRidgeModel
        var y: ForkGlanceRidgeModel
        var sigma: CGSize
        var normalization: [ForkGlanceRange]
        /// Combined cross-validated error, √(σx² + σy²).
        var error: Double { hypot(Double(sigma.width), Double(sigma.height)) }
    }

    private static func usable(_ sample: ForkGlanceSample, width: Int) -> Bool {
        sample.facePresent && sample.vector.count >= width && sample.vector.prefix(width).allSatisfy(\.isFinite)
    }

    private static func fitted(points: [ForkGlanceCalibrationPoint], learned: [(ForkGlanceCalibrationPoint, Double)],
                               usesEyes: Bool) throws -> Fitted {
        let components = ForkGlanceVectorLayout.components(usesEyes: usesEyes)
        let width = components.upperBound

        var inputs: [[Double]] = [], xs: [Double] = [], ys: [Double] = [], groups: [Int] = []
        var weights: [Double] = []
        for (index, point) in points.enumerated() {
            for sample in point.samples where usable(sample, width: width) {
                inputs.append(Array(sample.vector[components]))
                xs.append(Double(point.target.x))
                ys.append(Double(point.target.y))
                groups.append(index)
                weights.append(1)
            }
        }
        let calibrationRows = inputs.count
        guard calibrationRows >= ForkGlanceRegression.minimumPoints else { throw ForkGlanceRegressionError.tooFewPoints }
        let normalization = ranges(of: inputs)

        var learnedRows: [[Double]] = [], learnedXs: [Double] = [], learnedYs: [Double] = []
        var learnedWeights: [Double] = []
        for (point, weight) in learned where weight > 0 && weight.isFinite {
            for sample in point.samples where usable(sample, width: width) {
                learnedRows.append(Array(sample.vector[components]))
                learnedXs.append(Double(point.target.x))
                learnedYs.append(Double(point.target.y))
                learnedWeights.append(weight)
            }
        }
        let balanced = ForkGlanceLearning.balanced(calibrationWeight: Double(calibrationRows), learned: learnedWeights)
        // Each learned click is its own group, after the calibration points.
        for row in learnedRows.indices {
            inputs.append(learnedRows[row])
            xs.append(learnedXs[row])
            ys.append(learnedYs[row])
            groups.append(points.count + row)
            weights.append(balanced[row])
        }

        let reduced = inputs.map { row in row.indices.map { normalization[$0].reduce(row[$0]) } }
        let result = try ForkGlanceRegression.crossValidated(inputs: reduced, targets: [xs, ys], weights: weights,
                                                             groups: groups)
        let sigma = CGSize(width: max(result.residualSDs[0], minimumSigma),
                           height: max(result.residualSDs[1], minimumSigma))
        return Fitted(x: result.models[0], y: result.models[1], sigma: sigma, normalization: normalization)
    }

    /// Center = mean, scale = standard deviation (`minimumScale` floor: 1).
    private static func ranges(of rows: [[Double]]) -> [ForkGlanceRange] {
        guard let width = rows.first?.count else { return [] }
        let count = Double(rows.count)
        return (0..<width).map { column in
            let mean = rows.reduce(0) { $0 + $1[column] } / count
            let variance = rows.reduce(0) { $0 + ($1[column] - mean) * ($1[column] - mean) } / count
            let deviation = variance.squareRoot()
            return ForkGlanceRange(center: mean, scale: deviation >= minimumScale ? deviation : 1)
        }
    }

    private static func calibration(_ fitted: Fitted, usesEyes: Bool, points: [ForkGlanceCalibrationPoint],
                                     cameraID: String, layoutSignature: String, date: Date) -> ForkGlanceCalibration {
        let width = ForkGlanceVectorLayout.components(usesEyes: usesEyes).upperBound
        let samples = points.flatMap(\.samples).filter { usable($0, width: width) }
        let yaws = samples.map { $0.vector[ForkGlanceVectorLayout.yaw] }
        let pitches = samples.map { $0.vector[ForkGlanceVectorLayout.pitch] }
        return ForkGlanceCalibration(
            version: ForkGlanceCalibration.currentVersion, date: date, cameraID: cameraID,
            layoutSignature: layoutSignature, usesEyes: usesEyes,
            coefficientsX: fitted.x.coefficients, coefficientsY: fitted.y.coefficients,
            normalization: fitted.normalization, sigma: fitted.sigma, bias: .zero,
            yawRange: (yaws.min() ?? 0)...(yaws.max() ?? 0), pitchRange: (pitches.min() ?? 0)...(pitches.max() ?? 0),
            zoneAccuracy: [:])
    }

    /// The regression's point, without the bias; nil when the sample is short
    /// of components or the result is not finite.
    private static func unbiasedPoint(_ sample: ForkGlanceSample,
                                      with calibration: ForkGlanceCalibration) -> (x: Double, y: Double)? {
        let width = calibration.normalization.count
        guard width > 0, sample.vector.count >= width else { return nil }
        var reduced = [Double]()
        reduced.reserveCapacity(width)
        for index in 0..<width {
            let value = sample.vector[index]
            guard value.isFinite else { return nil }
            reduced.append(calibration.normalization[index].reduce(value))
        }
        let terms = ForkGlanceRegression.expand(reduced)
        guard terms.count == calibration.coefficientsX.count, terms.count == calibration.coefficientsY.count else {
            return nil
        }
        let x = ForkGlanceRegression.dot(terms, calibration.coefficientsX)
        let y = ForkGlanceRegression.dot(terms, calibration.coefficientsY)
        guard x.isFinite, y.isFinite else { return nil }
        return (x, y)
    }

    /// The display under `point`, else the closest one.
    private static func display(near point: CGPoint, in layout: ForkGlanceDisplayLayout) -> ForkGlanceDisplay? {
        if let under = layout.displays.first(where: { $0.frame.contains(point) }) { return under }
        return layout.displays.min { distance(point, $0.frame) < distance(point, $1.frame) }
    }

    private static func distance(_ point: CGPoint, _ rect: CGRect) -> Double {
        let dx = max(Double(rect.minX - point.x), 0, Double(point.x - rect.maxX))
        let dy = max(Double(rect.minY - point.y), 0, Double(point.y - rect.maxY))
        return hypot(dx, dy)
    }
}
