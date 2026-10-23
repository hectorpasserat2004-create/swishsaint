// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import CoreVideo
import Foundation
import Vision
import os

/// Glance Focus: Apple Vision on each kept camera image (plan §8.2, §10.3),
/// called synchronously on the camera's `captureQueue`, never on the main
/// thread. It returns geometry only (`ForkGlanceObservation`): no image is
/// kept, no face is recognized, nothing leaves the process.
///
/// Per image:
/// 1. `VNDetectFaceRectanglesRequest` revision 3 (continuous yaw, pitch and
///    roll) in a region of interest: the previous face box grown ×1.8. The
///    whole image every 2 s, after a loss, and right away when the region
///    came back empty.
/// 2. Several faces: the one that overlaps the previous box most, else the
///    largest. The others only count (`faceCount`, `otherFaceRatio`).
/// 3. `VNDetectFaceLandmarksRequest` revision 3 (pupils, eye outlines), only
///    when the profile uses the eyes, fed the kept face
///    (`inputFaceObservations`) so it does not detect again.
/// 4. `VNDetectFaceCaptureQualityRequest`, only while the assistant asks.
///
/// A revision this macOS lacks falls back to `supportedRevisions.max()`; the
/// revisions really used are in `revisions` for the diagnostics.
///
/// Orientation: the Mac's cameras deliver landscape images the right way up
/// and the video data output does not mirror them, so Vision reads them `.up`
/// and every coordinate here is the camera's view, not a mirror: turning the
/// head to one's left moves the face toward the image's right. The model
/// learns its signs at calibration, so this only matters to a view that draws
/// these points over a mirrored preview (it flips x).
final class ForkGlanceVision: @unchecked Sendable {
    /// The region of interest is the previous face box grown this much.
    static let regionGrowth: CGFloat = 1.8
    /// The whole image at least this often, to see a face come or leave.
    static let fullImageInterval: TimeInterval = 2
    /// Images kept for `timing`.
    static let timingWindow = 120

    static let wantedRectanglesRevision = VNDetectFaceRectanglesRequestRevision3
    static let wantedLandmarksRevision = VNDetectFaceLandmarksRequestRevision3

    private let log = Logger(subsystem: "fork.glance", category: "vision")
    private let lock = NSLock()

    // Guarded by `lock`: read from the capture queue, set from the main thread.
    private var eyes = false
    private var quality = false
    private var generation = 0
    private var previousBox: CGRect?
    private var lastFullImage: TimeInterval = -.infinity
    private var durations: [TimeInterval] = []
    private var failing = false

    // Only touched on the capture queue, inside `process`.
    private let rectangles = VNDetectFaceRectanglesRequest()
    private let landmarks = VNDetectFaceLandmarksRequest()
    private let captureQuality = VNDetectFaceCaptureQualityRequest()
    private let used: (rectangles: Int, landmarks: Int)

    init() {
        let rectanglesRevision = Self.revision(Self.wantedRectanglesRevision,
                                               supported: VNDetectFaceRectanglesRequest.supportedRevisions)
        let landmarksRevision = Self.revision(Self.wantedLandmarksRevision,
                                              supported: VNDetectFaceLandmarksRequest.supportedRevisions)
        rectangles.revision = rectanglesRevision
        landmarks.revision = landmarksRevision
        for request in [rectangles, landmarks, captureQuality] as [VNRequest] {
            request.preferBackgroundProcessing = true
        }
        used = (rectanglesRevision, landmarksRevision)
        if rectanglesRevision != Self.wantedRectanglesRevision || landmarksRevision != Self.wantedLandmarksRevision {
            log.notice("Vision revisions fall back: rectangles \(rectanglesRevision), landmarks \(landmarksRevision)")
        }
    }

    /// Eye landmarks, only when the profile uses them.
    var usesEyes: Bool {
        get { lock.withLock { eyes } }
        set { lock.withLock { eyes = newValue } }
    }

    /// The capture quality request, only during the assistant.
    var wantsQuality: Bool {
        get { lock.withLock { quality } }
        set { lock.withLock { quality = newValue } }
    }

    /// The revisions really used (the wanted 3, or the fallback).
    var revisions: (rectangles: Int, landmarks: Int) { used }

    /// Vision's time per image, in seconds, over the last `timingWindow` images.
    var timing: (mean: TimeInterval, p95: TimeInterval) {
        let values = lock.withLock { durations }
        guard !values.isEmpty else { return (0, 0) }
        let sorted = values.sorted()
        let rank = Int((Double(sorted.count - 1) * 0.95).rounded(.up))
        return (values.reduce(0, +) / Double(values.count), sorted[min(rank, sorted.count - 1)])
    }

    /// Forgets the face's place: the next image is searched whole. On a loss
    /// handled elsewhere, a camera change, a restart. The timing stays.
    func reset() {
        lock.withLock {
            generation += 1
            previousBox = nil
            lastFullImage = -.infinity
        }
    }

    /// One image, on the capture queue. Nil: no face (or Vision failed).
    func process(_ buffer: CVPixelBuffer, time: TimeInterval) -> ForkGlanceObservation? {
        let started = ProcessInfo.processInfo.systemUptime
        let (wantsEyes, wantsQuality, startGeneration, previous, lastFull) = lock.withLock {
            (eyes, quality, generation, previousBox, lastFullImage)
        }
        var fullImageAt = lastFull
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])

        var region = Self.unit
        if let previous, time - lastFull < Self.fullImageInterval {
            region = Self.grown(previous)
        } else {
            fullImageAt = time
        }
        var faces = detect(handler, in: region)
        if faces?.isEmpty == true, region != Self.unit {
            // Lost in the region: look at the whole image now rather than next time.
            fullImageAt = time
            faces = detect(handler, in: Self.unit)
        }

        var observation: ForkGlanceObservation?
        if let faces, let index = Self.pick(faces, previous: previous) {
            let kept = faces[index]
            let keptArea = Self.area(kept.box)
            let others = faces.indices.filter { $0 != index }.map { Self.area(faces[$0].box) }
            let otherRatio = others.max().map { keptArea > 0 ? $0 / keptArea : 0 } ?? 0
            var result = ForkGlanceObservation(time: time, faceBox: kept.box,
                                               yaw: kept.face.yaw?.doubleValue,
                                               pitch: kept.face.pitch?.doubleValue,
                                               roll: kept.face.roll?.doubleValue,
                                               faceCount: faces.count, otherFaceRatio: Double(otherRatio))
            if wantsEyes || wantsQuality {
                details(handler, kept: kept, eyes: wantsEyes, quality: wantsQuality, into: &result)
            }
            observation = result
        }

        let elapsed = ProcessInfo.processInfo.systemUptime - started
        lock.withLock {
            // A reset while Vision ran: this image's box belongs to the old camera or session.
            guard generation == startGeneration else { return }
            previousBox = observation?.faceBox
            lastFullImage = observation == nil ? -.infinity : fullImageAt
            durations.append(elapsed)
            if durations.count > Self.timingWindow { durations.removeFirst(durations.count - Self.timingWindow) }
        }
        return observation
    }

    // MARK: - Requests

    private struct Face {
        var face: VNFaceObservation
        /// Normalized in the whole image, origin bottom left.
        var box: CGRect
    }

    /// The faces in `region`, their boxes brought back to the whole image. Nil: Vision failed.
    private func detect(_ handler: VNImageRequestHandler, in region: CGRect) -> [Face]? {
        rectangles.regionOfInterest = region
        do {
            try handler.perform([rectangles])
        } catch {
            noteFailure(error)
            return nil
        }
        noteSuccess()
        // Detection results are normalized to the region of interest
        // (`VNImageRectForNormalizedRectUsingRegionOfInterest`).
        return (rectangles.results ?? []).map { face in
            Face(face: face, box: Self.inImage(face.boundingBox, region: region))
        }
    }

    /// Landmarks and capture quality of the kept face, without detecting it again.
    private func details(_ handler: VNImageRequestHandler, kept: Face, eyes: Bool, quality: Bool,
                         into observation: inout ForkGlanceObservation) {
        // The kept face in whole-image coordinates, so the follow-up requests run on the whole image.
        let input = VNFaceObservation(requestRevision: used.rectangles, boundingBox: kept.box,
                                      roll: kept.face.roll, yaw: kept.face.yaw, pitch: kept.face.pitch)
        var requests: [VNRequest] = []
        if eyes {
            landmarks.inputFaceObservations = [input]
            requests.append(landmarks)
        }
        if quality {
            captureQuality.inputFaceObservations = [input]
            requests.append(captureQuality)
        }
        do {
            try handler.perform(requests)
        } catch {
            noteFailure(error)
            return
        }
        if eyes, let face = landmarks.results?.first, let marks = face.landmarks {
            // Landmark points are normalized to their face's box.
            let box = face.boundingBox
            func points(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
                guard let region, region.pointCount > 0 else { return [] }
                return region.normalizedPoints.map {
                    CGPoint(x: box.minX + $0.x * box.width, y: box.minY + $0.y * box.height)
                }
            }
            observation.leftEye = points(marks.leftEye)
            observation.rightEye = points(marks.rightEye)
            observation.leftPupil = points(marks.leftPupil).first
            observation.rightPupil = points(marks.rightPupil).first
        }
        if quality, let value = captureQuality.results?.first?.faceCaptureQuality {
            observation.captureQuality = Double(value)
        }
    }

    private func noteFailure(_ error: Error) {
        let first = lock.withLock { () -> Bool in
            defer { failing = true }
            return !failing
        }
        if first { log.error("Vision request failed: \(error.localizedDescription, privacy: .public)") }
    }

    private func noteSuccess() {
        lock.withLock { failing = false }
    }

    // MARK: - Geometry

    private static let unit = CGRect(x: 0, y: 0, width: 1, height: 1)

    static func revision(_ wanted: Int, supported: IndexSet) -> Int {
        supported.contains(wanted) ? wanted : (supported.max() ?? wanted)
    }

    /// `box` grown `regionGrowth` around its center, kept inside the image.
    static func grown(_ box: CGRect) -> CGRect {
        let width = box.width * regionGrowth
        let height = box.height * regionGrowth
        let region = CGRect(x: box.midX - width / 2, y: box.midY - height / 2, width: width, height: height)
            .intersection(unit)
        return region.isNull || region.width <= 0 || region.height <= 0 ? unit : region
    }

    static func inImage(_ box: CGRect, region: CGRect) -> CGRect {
        CGRect(x: region.minX + box.minX * region.width, y: region.minY + box.minY * region.height,
               width: box.width * region.width, height: box.height * region.height)
    }

    private static func area(_ box: CGRect) -> CGFloat {
        box.isNull ? 0 : max(box.width, 0) * max(box.height, 0)
    }

    /// The face that overlaps `previous` most, else the largest. No identity:
    /// only where the face was.
    private static func pick(_ faces: [Face], previous: CGRect?) -> Int? {
        if let previous {
            let overlaps = faces.indices.map { ($0, area(faces[$0].box.intersection(previous))) }.filter { $0.1 > 0 }
            if let best = overlaps.max(by: { $0.1 < $1.1 }) { return best.0 }
        }
        return faces.indices.max(by: { area(faces[$0].box) < area(faces[$1].box) })
    }
}
