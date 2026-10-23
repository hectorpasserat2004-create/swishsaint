// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Glance Focus: the One Euro filter (Casiez, Roussel, Vogel 2012) on each
/// component of a raw sample (plan §8.1), with a guard against Vision's odd
/// image.
///
/// One Euro is a low-pass whose cutoff opens with speed: still, it smooths a
/// lot (jitter at `minCutoff`); moving, it follows (`minCutoff + beta·speed`).
/// The speed is read in degrees per second for the angles and in percent of
/// the image (or of the eye) per second elsewhere, so one `beta` suits every
/// component.
///
/// An outlier is a jump from one image to the next above `outlierSigmas`
/// times the component's rolling spread of such jumps (with a floor, so a
/// still head does not make every movement an outlier). It is dropped once:
/// that component keeps its last filtered value. If the next image is still
/// that far from the last accepted value, the jump is real and goes through.
///
/// Images without a face change nothing and repeat the last filtered vector;
/// after `gapReset` without a face the filter starts over from the next face.
/// Images whose eyes are unusable (blink, lost pupils) leave the eye
/// components at their last filtered value.
struct ForkGlanceFilter {
    /// A jump above this many rolling σ is an outlier.
    static let outlierSigmas = 6.0
    /// Without a face this long, the next face starts the filter over.
    static let gapReset: TimeInterval = 1.0
    /// Weight of each new jump in the rolling spread.
    static let spreadWeight = 0.05

    /// The speed unit of each component: radians → degrees, image or eye shares → percent.
    static let speedScale: [Double] = {
        var scale = [Double](repeating: 100, count: ForkGlanceVectorLayout.count)
        for index in [ForkGlanceVectorLayout.yaw, ForkGlanceVectorLayout.pitch, ForkGlanceVectorLayout.roll] {
            scale[index] = 180 / .pi
        }
        return scale
    }()

    /// The smallest σ of a frame-to-frame jump, in the component's own unit:
    /// 2° for the angles, 1 % of the image for the face, 3 % of the eye.
    static let spreadFloor: [Double] = {
        typealias L = ForkGlanceVectorLayout
        var floor = [Double](repeating: 0.03, count: L.count)
        for index in [L.yaw, L.pitch, L.roll] { floor[index] = 2 * .pi / 180 }
        for index in [L.centerX, L.centerY] { floor[index] = 0.01 }
        floor[L.size] = 0.005
        floor[L.openness] = 0.03
        return floor
    }()

    let minCutoff: Double
    let beta: Double
    let dCutoff: Double

    private struct Channel {
        /// Last filtered value and its filtered derivative (the component's unit per second).
        var value: Double
        var derivative: Double
        /// Last raw value let through.
        var accepted: Double
        /// Rolling variance of the accepted frame-to-frame jumps.
        var spread: Double
        var rejected = false
        var time: TimeInterval
    }

    private var channels: [Channel] = []
    private var lastOutput: [Double]?
    private var lastFace: TimeInterval?
    private var speed = 0.0

    init(minCutoff: Double = 1.0, beta: Double = 0.02, dCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    /// Filtered yaw and pitch speed, degrees per second (the governor's « moving »).
    /// Zero without a face.
    var headSpeed: Double { speed }

    mutating func reset() {
        channels = []
        lastOutput = nil
        lastFace = nil
        speed = 0
    }

    mutating func filter(_ sample: ForkGlanceSample) -> ForkGlanceSample {
        var output = sample
        guard sample.facePresent else {
            speed = 0
            if let lastOutput { output.vector = lastOutput }
            return output
        }
        if let lastFace, sample.time - lastFace > Self.gapReset { channels = [] }
        if channels.count != sample.vector.count { channels = [] }
        lastFace = sample.time

        guard !channels.isEmpty else {
            channels = sample.vector.enumerated().map { index, value in
                let floor = Self.floor(index)
                return Channel(value: value, derivative: 0, accepted: value, spread: floor * floor, time: sample.time)
            }
            speed = 0
            lastOutput = sample.vector
            return output
        }

        let eyes = ForkGlanceVectorLayout.headCount..<ForkGlanceVectorLayout.count
        for index in channels.indices {
            if !sample.eyesUsable, eyes.contains(index) { continue }
            var channel = channels[index]
            update(&channel, index: index, raw: sample.vector[index], time: sample.time)
            channels[index] = channel
        }
        let vector = channels.map(\.value)
        output.vector = vector
        lastOutput = vector

        let yaw = ForkGlanceVectorLayout.yaw
        let pitch = ForkGlanceVectorLayout.pitch
        if channels.count > max(yaw, pitch) {
            let degrees = 180 / Double.pi
            let yawSpeed = channels[yaw].derivative * degrees
            let pitchSpeed = channels[pitch].derivative * degrees
            speed = (yawSpeed * yawSpeed + pitchSpeed * pitchSpeed).squareRoot()
        }
        return output
    }

    // MARK: - One component

    private func update(_ channel: inout Channel, index: Int, raw: Double, time: TimeInterval) {
        let elapsed = time - channel.time
        guard elapsed > 1e-4, raw.isFinite else { return }

        let jump = raw - channel.accepted
        let threshold = Self.outlierSigmas * channel.spread.squareRoot()
        if abs(jump) > threshold {
            if !channel.rejected {
                // Once: maybe Vision's odd image. The time is kept so the next
                // step spans both images.
                channel.rejected = true
                return
            }
        } else {
            let floor = Self.floor(index)
            channel.spread = max((1 - Self.spreadWeight) * channel.spread + Self.spreadWeight * jump * jump,
                                 floor * floor)
        }
        channel.rejected = false
        // Raw to raw, like the authors' reference code: the head's real speed,
        // not the filter's lag.
        let derivative = (raw - channel.accepted) / elapsed
        channel.accepted = raw

        channel.derivative += Self.alpha(cutoff: dCutoff, elapsed: elapsed) * (derivative - channel.derivative)
        let scale = index < Self.speedScale.count ? Self.speedScale[index] : 1
        let cutoff = minCutoff + beta * abs(channel.derivative) * scale
        channel.value += Self.alpha(cutoff: cutoff, elapsed: elapsed) * (raw - channel.value)
        channel.time = time
    }

    private static func alpha(cutoff: Double, elapsed: TimeInterval) -> Double {
        let tau = 1 / (2 * .pi * max(cutoff, 1e-6))
        return 1 / (1 + tau / elapsed)
    }

    private static func floor(_ index: Int) -> Double {
        index < spreadFloor.count ? spreadFloor[index] : 0.01
    }
}
