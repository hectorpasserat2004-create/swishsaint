// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

/// Learning from clicks (plan §7.6). A real click while a confident sample is
/// fresh pairs the vector with the clicked point: where the person clicks is
/// where they look. The pairs age out (half-life of 3 days), feed a refit
/// every 25 new ones, and the last 60 clicks tell whether the model drifted.
///
/// The service picks the clicks: real ones (not synthetic, not on a Swishsaint
/// panel), with a sample at most `maximumSampleAge` old, and only when
/// « Apprendre de mes clics » is on. This value only keeps and weighs them.
struct ForkGlanceLearning: Codable, Equatable {
    static let capacity = 400
    static let halfLife: TimeInterval = 3 * 86_400
    static let refitEvery = 25
    /// Below this, a sample says too little to teach the model.
    static let minimumConfidence = 0.7
    /// A click pairs with a sample at most this old (the service checks it).
    static let maximumSampleAge: TimeInterval = 0.25
    /// The calibration points' floor: they keep at least this share of the
    /// total weight of a refit, however many clicks pile up.
    static let calibrationShare = 0.5
    /// A refit may make the calibration points' error this much worse, no more.
    static let maximumDegradation = 0.15
    /// The drift window: the last clicks compared.
    static let agreementWindow = 60

    struct Pair: Codable, Equatable {
        var sample: ForkGlanceSample
        /// Global points.
        var click: CGPoint
        var date: Date
    }

    /// Oldest first.
    private(set) var pairs: [Pair] = []
    private(set) var pendingSinceRefit = 0
    /// Oldest first: whether the predicted zone was the clicked one.
    private(set) var agreements: [Bool] = []

    init() {}

    private enum CodingKeys: String, CodingKey { case pairs, pendingSinceRefit, agreements }

    /// Tolerant: a missing field reads as empty, and the bounds hold even for
    /// a file written by hand.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pairs = Array((try container.decodeIfPresent([Pair].self, forKey: .pairs) ?? []).suffix(Self.capacity))
        pendingSinceRefit = max(try container.decodeIfPresent(Int.self, forKey: .pendingSinceRefit) ?? 0, 0)
        agreements = Array((try container.decodeIfPresent([Bool].self, forKey: .agreements) ?? [])
            .suffix(Self.agreementWindow))
    }

    /// Keeps the pair when the sample is confident (≥ 0.7) and has a face;
    /// past `capacity`, the oldest pair goes.
    mutating func add(_ sample: ForkGlanceSample, click: CGPoint, at date: Date) {
        guard sample.facePresent, sample.confidence >= Self.minimumConfidence,
              sample.vector.allSatisfy(\.isFinite), click.x.isFinite, click.y.isFinite else { return }
        pairs.append(Pair(sample: sample, click: click, date: date))
        if pairs.count > Self.capacity { pairs.removeFirst(pairs.count - Self.capacity) }
        pendingSinceRefit += 1
    }

    /// Each pair as a one-sample calibration point, weighted ½ per half-life
    /// of age (a pair dated in the future weighs 1).
    func weighted(now: Date) -> [(ForkGlanceCalibrationPoint, Double)] {
        pairs.map { pair in
            let age = max(now.timeIntervalSince(pair.date), 0)
            return (ForkGlanceCalibrationPoint(target: pair.click, samples: [pair.sample]),
                    pow(0.5, age / Self.halfLife))
        }
    }

    /// The pairs as calibration points, for the profile (`ForkGlanceProfile.learned`).
    var points: [ForkGlanceCalibrationPoint] {
        pairs.map { ForkGlanceCalibrationPoint(target: $0.click, samples: [$0.sample]) }
    }

    /// Enough new pairs for a refit.
    var refitDue: Bool { pendingSinceRefit >= Self.refitEvery }

    mutating func markRefit() { pendingSinceRefit = 0 }

    /// Forgets every pair (a new calibration, a deleted profile).
    mutating func removeAll() {
        pairs.removeAll()
        pendingSinceRefit = 0
        agreements.removeAll()
    }

    /// A refit is kept only when its error on the calibration points is at
    /// most 15 % above the old one's: clicks may refine the model, never undo
    /// the calibration. A new calibration that cannot be measured is refused;
    /// an old one that cannot be is replaced.
    static func accepts(old: ForkGlanceCalibration, new: ForkGlanceCalibration,
                        calibrationPoints: [ForkGlanceCalibrationPoint]) -> Bool {
        guard let newError = ForkGlanceCalibrationModel.error(of: new, on: calibrationPoints) else { return false }
        guard let oldError = ForkGlanceCalibrationModel.error(of: old, on: calibrationPoints) else { return true }
        return newError <= oldError * (1 + maximumDegradation) + 1e-9
    }

    /// The learned weights, scaled down when needed so the calibration rows
    /// (`calibrationWeight` in total) keep `calibrationShare` of the total.
    static func balanced(calibrationWeight: Double, learned: [Double]) -> [Double] {
        let total = learned.reduce(0, +)
        let allowed = calibrationWeight * (1 - calibrationShare) / calibrationShare
        guard total > allowed, total > 0 else { return learned }
        let factor = allowed / total
        return learned.map { $0 * factor }
    }

    /// One click: the zone the gaze predicted (nil: none, a miss) and the zone
    /// clicked. The last `agreementWindow` are kept.
    mutating func recordAgreement(predicted: String?, clicked: String) {
        agreements.append(predicted == clicked)
        if agreements.count > Self.agreementWindow { agreements.removeFirst(agreements.count - Self.agreementWindow) }
    }

    /// Forgets the agreement history (after a new calibration).
    mutating func resetAgreement() { agreements.removeAll() }

    /// Share of the recorded clicks where the prediction was right; nil before any.
    var agreement: Double? {
        guard !agreements.isEmpty else { return nil }
        return Double(agreements.filter { $0 }.count) / Double(agreements.count)
    }

    /// The model drifted: over a full window of clicks, the agreement fell
    /// under 80 % (70 % in Windows mode, where zones are smaller and overlap).
    func driftSuggested(mode: ForkGlanceMode) -> Bool {
        guard agreements.count >= Self.agreementWindow, let agreement else { return false }
        return agreement < (mode == .windows ? 0.7 : 0.8)
    }
}
