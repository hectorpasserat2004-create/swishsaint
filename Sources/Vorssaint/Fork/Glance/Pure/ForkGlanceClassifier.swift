// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

/// From an estimated point to a zone, with margins (plan §7.2).
///
/// A zone's score is the signed distance from the point to its edge (positive
/// inside), in σ of the axis that edge crosses. Entering a zone other than the
/// current one takes a score of at least `1 + s` (the sensitivity, plus the
/// anti ping-pong extra); the current zone stays while its score is at least
/// `-stay`. The gap between the two bars is the hysteresis: a point wobbling
/// on a border switches nothing.
///
/// Two refinements of the plan's rule, both prudent:
/// - An edge that faces no other display (the top of the LG, the menu bar
///   side, the outer sides) does not count: past it there is nothing to
///   confuse the zone with, and a point far past it is `away` anyway. Without
///   this, the menu bar and the Dock could never be entered.
/// - Zones are read in the order given (front to back in Windows mode) and
///   the first one past its bar wins, so a window in front beats the one
///   behind; in Screens and Zones modes the zones are disjoint and the order
///   does not matter.
///
/// `away` (never act, the keyboard stays where it is) when the point is
/// farther than 1.5 σ from every display, below the lowest display's bottom
/// edge (looking at the keyboard), or the head turned past the calibrated yaw
/// or pitch by 15°. `noFace` without an estimate.
///
/// `crowded`: the sample does not carry the other faces' size
/// (`ForkGlanceObservation.otherFaceRatio`); `Pure/ForkGlanceFeatures` folds
/// a comparable second face into the confidence. So a face present with a
/// confidence under `crowdedConfidence` reads as crowded, which is the same
/// bar as the `lowConfidence` guard.
struct ForkGlanceClassifier {
    /// The current zone stays down to this score.
    static let stay = 0.6
    /// The entry bar before the sensitivity.
    static let enterBase = 1.0
    /// Away past this many σ from every display.
    static let awayMargin = 1.5
    /// Away past the calibrated yaw or pitch by this much, radians (15°).
    static let angleMargin = 15 * Double.pi / 180
    static let crowdedConfidence = 0.5
    /// Anti ping-pong: A → B → A with the return within this time…
    static let pingPongWindow: TimeInterval = 1.5
    /// … raises the entry bar by this…
    static let pingPongExtra = 0.5
    /// … for this long.
    static let pingPongDuration: TimeInterval = 30
    /// The score of a zone with no edge to cross (a lone display): finite, so
    /// a gaze still encodes as JSON.
    static let unbounded = 100.0

    private struct Switch: Equatable {
        var zone: String
        var time: TimeInterval
    }

    /// The last two switches, oldest first.
    private var switches: [Switch] = []
    private var penaltyUntil: TimeInterval = -.infinity
    /// The latest time seen (an estimate's or a switch's).
    private var now: TimeInterval = -.infinity

    init() {}

    /// The extra entry margin in force (diagnostic): 0.5 for 30 s after a
    /// ping-pong, 0 otherwise.
    var extraEntry: Double { now < penaltyUntil ? Self.pingPongExtra : 0 }

    mutating func classify(_ estimate: ForkGlanceEstimate?, sample: ForkGlanceSample?, zones: [ForkGlanceZone],
                           layout: ForkGlanceDisplayLayout, calibration: ForkGlanceCalibration?, current: String?,
                           sensitivity: Double, headSpeed: Double) -> ForkGlanceGaze {
        let confidence = sample?.confidence ?? estimate?.confidence ?? 0
        let crowded = sample.map { $0.facePresent && $0.confidence < Self.crowdedConfidence } ?? false
        func gaze(_ target: ForkGlanceGazeTarget, margin: Double = 0) -> ForkGlanceGaze {
            ForkGlanceGaze(estimate: estimate, target: target, margin: margin, headSpeed: headSpeed,
                           confidence: confidence, crowded: crowded)
        }
        guard let estimate, sample?.facePresent ?? true,
              estimate.point.x.isFinite, estimate.point.y.isFinite else { return gaze(.noFace) }
        if estimate.time.isFinite { now = max(now, estimate.time) }

        let sigmaX = Self.positive(Double(estimate.sigma.width))
        let sigmaY = Self.positive(Double(estimate.sigma.height))
        let point = estimate.point
        if Self.isAway(point, sigmaX: sigmaX, sigmaY: sigmaY, sample: sample, layout: layout,
                       calibration: calibration) {
            return gaze(.away)
        }

        let enter = Self.enterBase + max(sensitivity, 0) + extraEntry
        for zone in zones {
            let score = Self.score(point, in: zone, sigmaX: sigmaX, sigmaY: sigmaY, layout: layout)
            let bar = zone.id == current ? -Self.stay : enter
            if score >= bar { return gaze(.zone(zone.id), margin: score) }
        }
        return gaze(.between)
    }

    /// A switch the machine made. A → B → A with the return within 1.5 s of
    /// leaving A raises the entry bar for 30 s (a new ping-pong restarts it).
    mutating func noteSwitch(to zone: String, at time: TimeInterval) {
        if switches.last?.zone == zone { return }
        if switches.count == 2, switches[0].zone == zone, time - switches[1].time < Self.pingPongWindow {
            penaltyUntil = time + Self.pingPongDuration
        }
        switches.append(Switch(zone: zone, time: time))
        if switches.count > 2 { switches.removeFirst(switches.count - 2) }
        now = max(now, time)
    }

    // MARK: Geometry

    /// The signed distance, in σ, from `point` to the edge of `zone` (see the
    /// type's comment for the edges that do not count).
    static func score(_ point: CGPoint, in zone: ForkGlanceZone, sigmaX: Double, sigmaY: Double,
                      layout: ForkGlanceDisplayLayout) -> Double {
        let rect = zone.rect
        let open = openEdges(of: zone, layout: layout)
        // Per edge: is it open, the distance inside in σ (negative outside), is it a vertical edge.
        let edges: [(open: Bool, inside: Double, crossesX: Bool)] = [
            (open.left, Double(point.x - rect.minX) / sigmaX, true),
            (open.right, Double(rect.maxX - point.x) / sigmaX, true),
            (open.top, Double(point.y - rect.minY) / sigmaY, false),
            (open.bottom, Double(rect.maxY - point.y) / sigmaY, false),
        ]
        var insides: [Double] = []
        var outsideX = 0.0, outsideY = 0.0
        for edge in edges where !edge.open {
            if edge.inside >= 0 {
                insides.append(edge.inside)
            } else if edge.crossesX {
                outsideX = max(outsideX, -edge.inside)
            } else {
                outsideY = max(outsideY, -edge.inside)
            }
        }
        if outsideX > 0 || outsideY > 0 { return -hypot(outsideX, outsideY) }
        return min(insides.min() ?? unbounded, unbounded)
    }

    /// The edges of `zone` that lie on its display's border with no other
    /// display beyond them (within 2 pt). A zone off every display keeps all
    /// its edges.
    static func openEdges(of zone: ForkGlanceZone,
                          layout: ForkGlanceDisplayLayout) -> (left: Bool, right: Bool, top: Bool, bottom: Bool) {
        guard let display = layout.displays.first(where: { $0.uuid == zone.displayUUID })?.frame else {
            return (false, false, false, false)
        }
        let rect = zone.rect, tolerance: CGFloat = 2
        let others = layout.displays.map(\.frame).filter { $0 != display && !$0.isEmpty }
        func overlapsX(_ other: CGRect) -> Bool { min(rect.maxX, other.maxX) - max(rect.minX, other.minX) > 0 }
        func overlapsY(_ other: CGRect) -> Bool { min(rect.maxY, other.maxY) - max(rect.minY, other.minY) > 0 }
        let left = abs(rect.minX - display.minX) <= tolerance
            && !others.contains { $0.maxX <= display.minX + tolerance && overlapsY($0) }
        let right = abs(rect.maxX - display.maxX) <= tolerance
            && !others.contains { $0.minX >= display.maxX - tolerance && overlapsY($0) }
        let top = abs(rect.minY - display.minY) <= tolerance
            && !others.contains { $0.maxY <= display.minY + tolerance && overlapsX($0) }
        let bottom = abs(rect.maxY - display.maxY) <= tolerance
            && !others.contains { $0.minY >= display.maxY - tolerance && overlapsX($0) }
        return (left, right, top, bottom)
    }

    private static func isAway(_ point: CGPoint, sigmaX: Double, sigmaY: Double, sample: ForkGlanceSample?,
                               layout: ForkGlanceDisplayLayout, calibration: ForkGlanceCalibration?) -> Bool {
        // The head turned past what the calibration saw.
        if let calibration, let vector = sample?.vector, vector.count > ForkGlanceVectorLayout.pitch {
            let yaw = vector[ForkGlanceVectorLayout.yaw], pitch = vector[ForkGlanceVectorLayout.pitch]
            if yaw.isFinite, yaw < calibration.yawRange.lowerBound - angleMargin
                || yaw > calibration.yawRange.upperBound + angleMargin { return true }
            if pitch.isFinite, pitch < calibration.pitchRange.lowerBound - angleMargin
                || pitch > calibration.pitchRange.upperBound + angleMargin { return true }
        }
        let frames = layout.displays.map(\.frame).filter { !$0.isEmpty }
        guard !frames.isEmpty else { return false }
        // Below the lowest display: the keyboard.
        if let lowest = frames.map(\.maxY).max(), point.y > lowest { return true }
        // Off every display by more than the margin.
        let near = frames.contains { frame in
            let dx = max(Double(frame.minX - point.x), 0, Double(point.x - frame.maxX)) / sigmaX
            let dy = max(Double(frame.minY - point.y), 0, Double(point.y - frame.maxY)) / sigmaY
            return hypot(dx, dy) <= awayMargin
        }
        return !near
    }

    private static func positive(_ sigma: Double) -> Double {
        sigma.isFinite && sigma > 0 ? max(sigma, 1e-3) : ForkGlanceCalibrationModel.minimumSigma
    }
}
