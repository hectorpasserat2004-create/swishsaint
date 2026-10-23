// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Combine
import Foundation

// Wave 2 stand-in, written by the orchestrator: the service's surface is
// frozen here so the assistant (B2), the settings (B3) and the island (B4)
// build against it while B1 writes the bodies. B1 owns this file and keeps
// every signature below; a change goes through the orchestrator.

/// Where an action came from: a notice « Regard en pause / repris » only
/// follows a shortcut or the Command Bar, never a click in the island (plan §11.4).
enum ForkGlanceActionSource: Sendable, Equatable {
    case shortcut
    case commandBar
    case island
    case settings
}

/// What the assistant opens on (plan §8.4: Calibrer, Recalibrer, Tester,
/// Recalage rapide, Vérifier le cadrage).
enum ForkGlanceCalibrationEntry: Sendable, Equatable {
    /// Steps 1 to 7.
    case full
    /// Steps 3 to 6.
    case recalibrate
    /// Step 6 alone.
    case test
    /// One point in the middle of each zone: bias and a small refit.
    case quickRecenter
    /// Step 3 alone (Settings › Caméra › « Vérifier le cadrage… »).
    case framing
}

/// A switch the island lists (« Dernières bascules », plan §11.1).
struct ForkGlanceSwitchRecord: Sendable, Equatable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    var zoneID: String
    var zoneName: String
    var appName: String
}

/// The zone being entered and how far its dwell has gone (0…1), for the
/// section's filling zone (plan §9).
struct ForkGlanceCandidate: Sendable, Equatable {
    var zoneID: String
    var progress: Double
}

/// The live readings, published only while someone holds a lease (the
/// section's gaze dot, the diagnostics): nothing is computed for nobody.
struct ForkGlanceLive: Sendable, Equatable {
    var time: TimeInterval
    var observation: ForkGlanceObservation?
    var sample: ForkGlanceSample?
    var estimate: ForkGlanceEstimate?
    var gaze: ForkGlanceGaze?
    /// Images kept per second, and Vision's time per image (seconds).
    var frameRate: Double
    var visionMean: TimeInterval
    var visionP95: TimeInterval
    var guards: [ForkGlanceGuard]
    var extraEntry: Double
    /// App name → set aside until.
    var setAside: [String: Date]
    var focusFailures: [String: Int]
    /// Share of the last 60 clicks whose zone was the predicted one.
    var clickAgreement: Double?
    /// Process CPU in cores (0.02 = 2 % of a core) and watts, over 5 min,
    /// nil until measured (plan §10.4).
    var cpuCores: Double?
    var watts: Double?
    var revisions: String
}

/// Held while a surface shows live readings; released when it goes away.
final class ForkGlanceLease {
    private let onRelease: () -> Void
    private var released = false

    init(onRelease: @escaping () -> Void) { self.onRelease = onRelease }

    func release() {
        guard !released else { return }
        released = true
        onRelease()
    }

    deinit { release() }
}

/// Glance Focus's orchestrator (plan §3.1): the flow from the camera to the
/// focus, its life cycle, the permissions and the one timer. Main thread.
final class ForkGlanceService: ObservableObject {
    static let shared = ForkGlanceService()

    // MARK: State, for every surface

    @Published private(set) var phase: ForkGlancePhase = .off
    @Published private(set) var status: ForkGlanceStatusLine = .off
    @Published private(set) var settings: ForkGlanceSettings = .read()
    @Published private(set) var layout = ForkGlanceDisplayLayout(displays: [])
    /// The profile for this layout and camera, nil before one exists.
    @Published private(set) var profile: ForkGlanceProfile?
    @Published private(set) var profiles: [ForkGlanceProfile] = []
    @Published private(set) var zones: [ForkGlanceZone] = []
    @Published private(set) var currentZone: String?
    @Published private(set) var candidate: ForkGlanceCandidate?
    @Published private(set) var recentSwitches: [ForkGlanceSwitchRecord] = []
    /// The end of a timed user pause, as a date; nil otherwise.
    @Published private(set) var pausedUntil: Date?
    /// While the assistant collects points.
    @Published private(set) var calibrationProgress: (done: Int, total: Int)?
    /// « Le regard se trompe souvent » (plan §7.6).
    @Published private(set) var driftSuggested = false
    /// The layout moved since the profile was calibrated (plan §8.6 case 2).
    @Published private(set) var layoutMoved = false
    @Published private(set) var cameraDevices: [ForkGlanceCameraDevice] = []
    @Published private(set) var cameraID: String?
    @Published private(set) var cameraPermission: ForkGlanceCameraPermission = .notDetermined
    @Published private(set) var live: ForkGlanceLive?

    /// The zone's display name (« Zone gauche du LG »), in the person's language.
    func zoneName(_ zoneID: String) -> String? { nil }

    // MARK: Life cycle (ForkGlance.start/sync/suspend call these)

    func start() {}
    func sync() {}
    func suspend() {}

    // MARK: Actions

    func pause(_ duration: ForkGlancePauseDuration, from source: ForkGlanceActionSource) {}
    func resume(from source: ForkGlanceActionSource) {}
    /// Lifts a battery, Low Power or thermal pause until it changes.
    func resumeAnyway() {}
    /// « Recentrer » (plan §8.3): the gaze is on the pointer.
    func recenter(from source: ForkGlanceActionSource) {}
    func setMode(_ mode: ForkGlanceMode) {}
    func setSplit(_ split: ForkGlanceSplit, display uuid: String) {}
    func deleteProfile(_ id: String) {}
    func selectCamera(_ id: String?) {}
    func requestCameraPermission() {}
    /// Opens the assistant (`Calibration/ForkGlanceCalibrationWindow`).
    func openCalibration(_ entry: ForkGlanceCalibrationEntry) {}
    /// Opens Settings on the feature's page.
    func openSettings() {}

    /// Live readings while the lease lives (plan §11.1, §12.11).
    func liveLease() -> ForkGlanceLease { ForkGlanceLease {} }

    /// Records a 60 s trace and offers to save it (plan §12.11); nil on cancel or failure.
    func recordTrace(seconds: TimeInterval, completion: @escaping (URL?) -> Void) { completion(nil) }
    /// « Copier le rapport »: version, Mac, layout, score, settings.
    func reportText() -> String { "" }

    // MARK: The assistant's feed (B2)

    /// The assistant starts: the machine pauses switching (`calibrating`),
    /// the camera runs for the assistant. False when it cannot (permission, no camera).
    func beginCalibration() -> Bool { false }
    /// Every processed image while the assistant runs, on the main thread.
    var calibrationFeed: ((ForkGlanceSample, ForkGlanceObservation?) -> Void)?
    /// Progress for the island's activity (« 12/30 »).
    func calibrationProgressed(done: Int, total: Int) {}
    /// Points collected: fit off the main thread, store in the profile,
    /// completion on main with the calibration or the error.
    func finishCalibration(points: [ForkGlanceCalibrationPoint], splits: [String: ForkGlanceSplit],
                           mode: ForkGlanceMode,
                           completion: @escaping (Result<ForkGlanceCalibration, Error>) -> Void) {}
    /// The validation's per-zone scores, then the notice and the mascot.
    func finishValidation(zoneAccuracy: [String: Double]) {}
    /// The quick recenter's points: bias and a small refit.
    func finishQuickRecenter(points: [ForkGlanceCalibrationPoint]) {}
    func cancelCalibration() {}
    /// The model's estimate for a sample, with the current profile (validation step).
    func estimate(_ sample: ForkGlanceSample) -> ForkGlanceEstimate? { nil }
}
