// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import Combine
import CoreGraphics
import CoreVideo
import Darwin
import Foundation
import os
import UniformTypeIdentifiers

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
///
/// ```
///  captureQueue: ForkGlanceCamera.frameHandler → Vision → Features → One Euro filter
///        │ (main.async, generation-checked)
///  main: calibration model → classifier → machine (.inputs, then .gaze) → effects
///        effects: camera on/off and rate, focus (targeting → Focuser), halo, notices
/// ```
///
/// - **Life cycle**: `sync()` brings everything up while the switch is on
///   (the power and input watches, the displays, the camera's sharing, the
///   permissions, the shortcuts, the machine) and takes everything down when
///   it is off: the camera stops for real, the timer, every observer and
///   monitor, the hotkeys, the halo, the Focuser's attempt. The camera runs
///   only while the machine watches (permissions granted, a calibrated
///   profile, no pause) or while the assistant collects points.
/// - **Threads** (plan §3.2): Vision, the features and the filter run on the
///   camera's capture queue; every image comes back to the main thread tagged
///   with the pipeline's generation, and an image of an older one (the camera
///   stopped or changed meanwhile) is dropped. The calibration fit and the
///   clicks' refits run on background queues, the disk on the stores' queues.
/// - **One timer**, armed at the machine's `nextDeadline` (the dwell, the
///   cooldown, a guard's end, a timed pause, the idle cut). A pause for
///   inactivity polls the input ages at 2 Hz (`ForkGlanceInputWatch.onNextActivity`).
/// - **Profiles** (plan §8.6): matched at each change of the displays or
///   the camera. Identical: loaded silently; moved: loaded with a hint to
///   recenter (`layoutMoved`); unknown: a new profile (stored at its first
///   split or calibration), `needsCalibration`, the notice once per layout
///   (`fork.glance.lastLayoutSignature`), the camera off.
/// - **Learning** (plan §7.6): real clicks pair with a fresh confident
///   sample; every 25 pairs a refit runs off the main thread, kept only when
///   it does not make the calibration points worse by more than 15 %. The
///   calibration points live next to the profiles (`calibration-points.json`),
///   since a profile keeps only the fitted model.
final class ForkGlanceService: ObservableObject {
    static let shared = ForkGlanceService()

    // MARK: State, for every surface

    @Published private(set) var phase: ForkGlancePhase = .off
    @Published private(set) var status: ForkGlanceStatusLine = .off
    @Published private(set) var settings: ForkGlanceSettings = .read()
    @Published private(set) var layout = ForkGlanceDisplayLayout(displays: [])
    /// The profile for this layout and camera, nil before the profiles are
    /// read. It may be a new one, not stored yet and not calibrated
    /// (`calibration == nil`): the splits can still be chosen on it.
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
    /// The camera filmed with: the one chosen, else the built-in one (never
    /// a Continuity camera on its own). Nil when there is none at all.
    @Published private(set) var cameraID: String?
    @Published private(set) var cameraPermission: ForkGlanceCameraPermission = .notDetermined
    @Published private(set) var live: ForkGlanceLive?

    /// The zone's display name (« Zone gauche du LG »), in the person's language.
    func zoneName(_ zoneID: String) -> String? {
        guard let zone = zones.first(where: { $0.id == zoneID }) else { return nil }
        let text = ForkGlanceStrings.strings(L10n.shared.language)
        if zone.position == .window, let id = zone.windowID, let app = windowApps[id], !app.isEmpty {
            return text.windowZoneName(app: app)
        }
        guard let display = layout.displays.first(where: { $0.uuid == zone.displayUUID }) else { return nil }
        return text.zoneName(zone.position, display: text.displayShortName(display, among: layout.displays))
    }

    // MARK: Private state

    private static let log = Logger(subsystem: "fork.glance", category: "service")
    /// The assistant collects at this rate: ≥ 8 samples in 0.9 s (plan §8.4).
    private static let calibrationRate: Double = 15
    /// « Recentrer » averages this long (plan §8.3).
    private static let recenterSpan: TimeInterval = 0.6
    /// Windows mode: the windows are read again this often while watching.
    private static let windowZonesInterval: TimeInterval = 0.5
    /// The key window is compared with the use history this often.
    private static let focusCheckInterval: TimeInterval = 0.5
    /// The learned clicks are written at most this often.
    private static let learningSaveDelay: TimeInterval = 30

    private let clock = ForkGlanceSystemClock()
    private let pipeline = ForkGlancePipeline()
    private let pointsStore = ForkGlancePointsStore()

    private var started = false
    /// The switch is on and everything it needs is installed.
    private var isUp = false
    private var machine: ForkGlanceMachine?
    private var classifier = ForkGlanceClassifier()

    // Profiles.
    private var profilesLoaded = false
    private var loadingProfiles = false
    private var profileIsNew = false
    private var need: ForkGlanceCalibrationNeed?
    /// A profile the person deleted: its layout says « supprimé », not « première fois ».
    private var removedSignature: String?
    /// Bumped by every new calibration, deletion or profile change: a refit
    /// or a recenter started before lands on nothing.
    private var profileGeneration = 0
    /// The « Nouvelle disposition » notice may show for this match.
    private var newLayoutNoticeAllowed = true
    private var learningSave: DispatchWorkItem?
    private var refitting = false

    // Camera.
    private var machineWantsCamera = false
    private var machineRate: Double?
    private var cameraRunning = false
    private var failure: ForkGlanceUnavailable?
    private var previewOpen = false
    private var calibrationActive = false
    private var calibrationGeneration = 0

    // Observers (all removed by `tearDown`).
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var cancellables: [AnyCancellable] = []
    private var displaysToken: NSObjectProtocol?
    private var defaultsPending = false
    private var shortcutFingerprint: [String] = []
    /// `fork.glance.cameraID` as last read.
    private var storedCameraChoice = ""
    /// A shortcut recorder listens: the hotkeys are off meanwhile.
    private var recordingShortcut = false

    // The one timer.
    private var deadlineTimer: Timer?
    private var armedDeadline: TimeInterval?

    // Images.
    private var lastObservation: ForkGlanceObservation?
    private var lastSample: ForkGlanceSample?
    private var lastEstimate: ForkGlanceEstimate?
    private var lastGaze: ForkGlanceGaze?
    private var lastInputs = ForkGlanceInputSnapshot.idle
    private var facelessSince: TimeInterval?
    private var lastWindowZones: TimeInterval = -.infinity
    private var lastFocusCheck: TimeInterval = -.infinity
    private var lastHistoryHead: UInt32?
    /// Windows mode: the app of each window zone, for its name.
    private var windowApps: [UInt32: String] = [:]

    // Switching.
    private struct PendingSwitch {
        var zone: ForkGlanceZone
        var target: ForkGlanceTarget
        /// The target had the keyboard already: no visible effect (plan §6.2).
        var alreadyFocused: Bool
    }
    private var pendingSwitch: PendingSwitch?
    /// The switch the halo is for.
    private var feedback: (zone: String, target: ForkGlanceTarget, silent: Bool)?
    /// Our last switch's window: its own focus change is not the person's.
    private var lastSwitched: (window: UInt32, zone: String)?
    private var pointerByDisplay: [String: CGPoint] = [:]
    private var focusFailures: [String: Int] = [:]

    // Pause.
    private var noticeOrigin: ForkGlanceServiceRules.NoticeOrigin?
    /// The user pause's end as given to the machine (`systemUptime`).
    private var userPauseUptime: TimeInterval?

    // Recenter, trace, cost, leases.
    private struct RecenterCollect {
        var target: CGPoint
        var samples: [ForkGlanceSample]
        var generation: Int
    }
    private var recenterCollect: RecenterCollect?
    private struct Recording {
        var start: TimeInterval
        var trace: ForkGlanceTrace
        var completion: (URL?) -> Void
        var generation: Int
    }
    private var recording: Recording?
    private var recordingGeneration = 0
    private var cost = ForkGlanceCostMeter()
    private var leases = 0
    private var lastDriftNotice: Date?

    private init() {}

    // MARK: - Life cycle (ForkGlance.start/sync/suspend call these)

    /// Once, at launch: the callbacks of the parts the service drives, then a
    /// first sync once the launch is done.
    func start() {
        precondition(Thread.isMainThread)
        guard !started else { return }
        started = true

        let pipeline = self.pipeline
        let camera = ForkGlanceCamera.shared
        camera.frameHandler = { buffer, time in
            let frame = pipeline.process(buffer, time: time)
            DispatchQueue.main.async { ForkGlanceService.shared.received(frame) }
        }
        camera.onState = { [weak self] state in self?.cameraStateChanged(state) }
        camera.onDevicesChanged = { [weak self] in self?.devicesChanged() }
        camera.onInUseElsewhereChanged = { [weak self] _ in self?.sendSystem() }
        ForkGlancePowerWatch.shared.onChange = { [weak self] in self?.systemChanged() }
        ForkGlanceInputWatch.shared.onClick = { [weak self] point, time in self?.clicked(at: point, time: time) }
        ForkGlanceFocuser.shared.onResult = { [weak self] target, succeeded in
            self?.focusFinished(target, succeeded: succeeded)
        }
        ForkGlanceHotKeys.shared.onPress = { [weak self] role in self?.hotKeyPressed(role) }
        // For the app's life: nothing runs until it quits.
        _ = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                                   queue: .main) { [weak self] _ in self?.suspend() }
        DispatchQueue.main.async { ForkGlance.sync() }
    }

    /// The switch, the settings or the permissions may have changed. Light
    /// and idempotent: the settings page calls it after every change and when
    /// the app comes back in front. It reads the settings, the camera's
    /// permission, the cameras and the displays again, and only what changed
    /// moves: the camera is never restarted by it.
    func sync() {
        precondition(Thread.isMainThread)
        guard started else {
            start()
            return
        }
        let read = ForkGlanceSettings.read()
        let permission = ForkGlanceCamera.permission
        if cameraPermission != permission { cameraPermission = permission }
        let cameraBefore = cameraID
        refreshDevices()
        let current = ForkGlanceDisplays.current()
        if read.enabled {
            if isUp {
                settingsChanged(read)
                if current != layout {
                    layoutChanged(current)
                } else if cameraBefore != cameraID {
                    devicesChanged()
                }
                syncShortcuts()
                sendSystem()
            } else {
                if settings != read { settings = read }
                if layout != current { layout = current }
                bringUp()
            }
        } else {
            tearDown()
            if settings != read { settings = read }
            let moved = layout != current || cameraBefore != cameraID
            if layout != current { layout = current }
            if profilesLoaded, moved || profile == nil { applyProfile() }
        }
        if !profilesLoaded { loadProfiles() }
    }

    /// Before Accessibility is revoked or the app quits: everything stops,
    /// as if switched off; the next `sync()` starts it again.
    func suspend() {
        precondition(Thread.isMainThread)
        tearDown()
        if calibrationActive { endCalibration() }
        flushLearning()
    }

    private func bringUp() {
        isUp = true
        Self.log.info("glance focus up")
        ForkGlancePowerWatch.shared.start()
        ForkGlanceCamera.shared.watch(deviceID: cameraID)

        cancellables.append(ForkGlanceCameraBusy.observe { [weak self] open in
            guard let self, self.previewOpen != open else { return }
            self.previewOpen = open
            self.sendSystem()
        })
        cancellables.append(Permissions.shared.$camera.removeDuplicates().dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.cameraPermission = ForkGlanceCamera.permission
                self.refreshDevices()
                self.sendSystem()
            })
        displaysToken = ForkGlanceDisplays.observe { [weak self] layout in self?.layoutChanged(layout) }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didActivateApplicationNotification) { service in
            service.appActivated()
        }
        observe(.default, UserDefaults.didChangeNotification) { service in service.defaultsChanged() }
        shortcutFingerprint = Self.shortcutFingerprint()
        ForkGlanceHotKeys.shared.sync(enabled: !recordingShortcut)

        machine = ForkGlanceMachine(settings: settings)
        classifier = ForkGlanceClassifier()
        failure = nil
        machineWantsCamera = false
        machineRate = nil
        cost.cameraOff(Self.costReading(at: clock.now))
        // First, before any pass of the machine could clear the stored pause.
        restorePause()
        sendSystem()
        if profilesLoaded { applyProfile() }
    }

    private func tearDown() {
        guard isUp else {
            publishState()
            return
        }
        isUp = false
        Self.log.info("glance focus down")
        if calibrationActive {
            // The switch went off under the assistant: it closes as « Annuler ».
            ForkGlanceCalibrationWindow.close()
            endCalibration()
        }
        machine = nil
        machineWantsCamera = false
        applyCamera()
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        armedDeadline = nil
        ForkGlanceCamera.shared.stopWatching()
        ForkGlancePowerWatch.shared.stop()
        ForkGlanceInputWatch.shared.stop()
        if let displaysToken { ForkGlanceDisplays.stopObserving(displaysToken) }
        displaysToken = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        cancellables.removeAll()
        ForkGlanceHotKeys.shared.sync(enabled: false)
        ForkGlanceFocuser.shared.reset()
        ForkGlanceHalo.shared.hideAll()
        pendingSwitch = nil
        feedback = nil
        lastSwitched = nil
        recenterCollect = nil
        finishRecording(cancelled: true)
        failure = nil
        noticeOrigin = nil
        flushLearning()
        publishState()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ handler: @escaping (ForkGlanceService) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            handler(self)
        }
        observers.append((center, token))
    }

    // MARK: - The machine

    private func send(_ event: ForkGlanceEvent) {
        guard machine != nil else { return }
        let effects = machine?.handle(event, now: clock.now) ?? []
        afterMachine(effects)
    }

    private func afterMachine(_ effects: [ForkGlanceEffect]) {
        for effect in effects { run(effect) }
        syncPersistedPause()
        syncActivityWatch()
        rearmTimer()
        publishState()
    }

    private func run(_ effect: ForkGlanceEffect) {
        switch effect {
        case .startCamera:
            machineWantsCamera = true
            applyCamera()
        case .stopCamera:
            machineWantsCamera = false
            applyCamera()
        case let .setRate(rate):
            machineRate = rate
            if !calibrationActive { ForkGlanceCamera.shared.setRate(rate) }
        case let .focus(zone):
            performFocus(zone)
        case let .showFeedback(zone):
            showFeedback(zone)
        case let .notice(notice):
            present(notice)
        case .suggestRecalibration:
            suggestDrift()
        }
    }

    private func rearmTimer() {
        let deadline = isUp ? machine?.nextDeadline : nil
        guard deadline != armedDeadline || (deadline != nil && deadlineTimer == nil) else { return }
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        armedDeadline = deadline
        guard let deadline else { return }
        // A hair after the deadline, so the machine sees it passed.
        let delay = max(0, deadline - clock.now) + 0.002
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.deadlineTimer = nil
            self.armedDeadline = nil
            self.send(.tick)
        }
        timer.tolerance = min(0.02, delay * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        deadlineTimer = timer
    }

    /// A pause for inactivity ends at the first key or pointer move.
    private func syncActivityWatch() {
        let idle = isUp && (machine?.pauses.contains(.idle) ?? false)
        let input = ForkGlanceInputWatch.shared
        if idle, !input.isWatchingForActivity {
            input.onNextActivity { [weak self] in
                guard let self, self.isUp else { return }
                let snapshot = ForkGlanceInputWatch.shared.snapshot()
                self.lastInputs = snapshot
                self.send(.inputs(snapshot))
            }
        } else if !idle, input.isWatchingForActivity {
            input.cancelActivityWatch()
        }
    }

    private func publishState() {
        let now = clock.now
        let newPhase = machine?.phase ?? (calibrationActive ? .calibrating : .off)
        if phase != newPhase { phase = newPhase }
        switch newPhase {
        case .searching, .away:
            if facelessSince == nil { facelessSince = now }
        default:
            facelessSince = nil
        }
        let zone = machine?.currentZone
        if currentZone != zone { currentZone = zone }
        var newCandidate: ForkGlanceCandidate?
        if case let .candidate(zone, _, since) = newPhase {
            newCandidate = ForkGlanceCandidate(
                zoneID: zone, progress: ForkGlanceServiceRules.progress(since: since, dwell: settings.dwell, now: now))
        }
        if candidate != newCandidate { candidate = newCandidate }
        let line = ForkGlancePresentation.status(newPhase, zoneName: { [weak self] in self?.zoneName($0) },
                                                 calibration: calibrationProgress,
                                                 facelessFor: facelessSince.map { now - $0 } ?? 0,
                                                 pausedUntil: pausedUntil)
        if status != line { status = line }
    }

    // MARK: - System

    /// The camera's fields, which only the service knows, over the power watch's.
    private func systemSnapshot() -> ForkGlanceSystemSnapshot {
        var snapshot = ForkGlancePowerWatch.shared.snapshot()
        let device = cameraDevices.first { $0.id == cameraID }
        snapshot.officialPreviewOpen = previewOpen
        snapshot.cameraInUseElsewhere = ForkGlanceCamera.shared.isInUseElsewhere
        snapshot.lidClosedOnBuiltInCamera = (device?.isBuiltIn ?? false) && ForkGlancePowerWatch.shared.lidClosed
        snapshot.cameraPresent = device != nil
        snapshot.cameraPermission = ForkGlanceCamera.permission
        if !layout.displays.isEmpty { snapshot.displayCount = layout.displays.count }
        return snapshot
    }

    private func sendSystem() {
        guard isUp else { return }
        send(.system(systemSnapshot()))
    }

    private func systemChanged() {
        guard isUp else { return }
        resyncUserPause()
        sendSystem()
    }

    private func cameraStateChanged(_ state: ForkGlanceCameraState) {
        guard isUp else { return }
        switch state {
        case let .failed(reason):
            // A missing permission is the snapshot's, not a failure.
            guard reason != .cameraPermission, failure != reason else { return }
            failure = reason
            send(.cameraFailure(reason))
        case .running:
            guard failure != nil else { return }
            failure = nil
            send(.cameraFailure(nil))
        case .stopped, .starting, .interrupted:
            break
        }
    }

    private func refreshDevices() {
        let devices = ForkGlanceCamera.devices()
        if cameraDevices != devices { cameraDevices = devices }
        let stored = UserDefaults.standard.string(forKey: ForkDefaultsKey.glanceCameraID) ?? ""
        storedCameraChoice = stored
        // Never a Continuity camera on its own (plan §8.6), as `ForkGlanceCamera.defaultDeviceID`.
        let chosen = stored.isEmpty
            ? devices.first(where: \.isBuiltIn)?.id ?? devices.first(where: { !$0.isBuiltIn && !$0.isContinuity })?.id
            : stored
        if cameraID != chosen { cameraID = chosen }
    }

    private func devicesChanged() {
        let before = cameraID
        refreshDevices()
        guard isUp else { return }
        // Back from an unplug: the machine may start the camera again.
        if failure == .cameraDisconnected || failure == .noCamera, cameraDevices.contains(where: { $0.id == cameraID }) {
            failure = nil
            send(.cameraFailure(nil))
        }
        if before != cameraID {
            ForkGlanceCamera.shared.watch(deviceID: cameraID)
            restartCamera()
            applyProfile()
        }
        sendSystem()
    }

    private func layoutChanged(_ newLayout: ForkGlanceDisplayLayout) {
        guard newLayout != layout else { return }
        layout = newLayout
        pointerByDisplay = pointerByDisplay.filter { uuid, _ in newLayout.displays.contains { $0.uuid == uuid } }
        applyProfile()
        sendSystem()
    }

    private func appActivated() {
        lastWindowZones = -.infinity
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.isUp else { return }
            if self.settings.mode == .windows { self.recomputeZones() }
            self.refreshFocusZone(force: true)
        }
    }

    // MARK: - Settings

    private func defaultsChanged() {
        guard !defaultsPending else { return }
        defaultsPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.defaultsPending = false
            guard self.isUp else { return }
            let read = ForkGlanceSettings.read()
            if !read.enabled {
                // A settings import turned the switch off.
                ForkGlance.sync()
                return
            }
            self.settingsChanged(read)
            self.syncShortcuts()
            // A camera chosen elsewhere (a settings import never carries it: machine state).
            if UserDefaults.standard.string(forKey: ForkDefaultsKey.glanceCameraID) ?? "" != self.storedCameraChoice {
                self.devicesChanged()
            }
        }
    }

    private func settingsChanged(_ read: ForkGlanceSettings = .read()) {
        guard read != settings else { return }
        let modeChanged = read.mode != settings.mode
        settings = read
        send(.settings(read))
        if modeChanged { recomputeZones() }
        if !read.gazeDot { ForkGlanceHalo.shared.moveGazeDot(to: nil) }
    }

    /// Re-installs the shortcuts when what they depend on changed.
    private func syncShortcuts() {
        let fingerprint = Self.shortcutFingerprint()
        guard fingerprint != shortcutFingerprint else { return }
        shortcutFingerprint = fingerprint
        ForkGlanceHotKeys.shared.sync(enabled: isUp && !recordingShortcut)
    }

    /// A shortcut recorder is listening (the page's): the global shortcuts
    /// step aside, so the combination pressed is recorded, not run (like
    /// `ForkMeetingService.setShortcutRecording`).
    func setShortcutRecording(_ recording: Bool) {
        precondition(Thread.isMainThread)
        guard recordingShortcut != recording else { return }
        recordingShortcut = recording
        shortcutFingerprint = Self.shortcutFingerprint()
        ForkGlanceHotKeys.shared.sync(enabled: isUp && !recording)
    }

    /// What the shortcuts depend on: a change re-installs them.
    private static func shortcutFingerprint() -> [String] {
        let defaults = UserDefaults.standard
        var keys = ForkGlanceShortcutRole.allCases.map(\.key)
        keys += [ForkDefaultsKey.dictationShortcuts, ForkDefaultsKey.meetingsShortcut,
                 ForkDefaultsKey.meetingsPauseShortcut, ForkDefaultsKey.meetingsMarkerShortcut]
        return keys.map { defaults.string(forKey: $0) ?? "" }
            + [ForkDefaultsKey.dictationEnabled, ForkDefaultsKey.meetingsEnabled].map { defaults.bool(forKey: $0) ? "1" : "0" }
    }

    // MARK: - Profiles

    private func loadProfiles() {
        guard !loadingProfiles else { return }
        loadingProfiles = true
        ForkGlanceStore.shared.load { [weak self] list in
            guard let self else { return }
            self.loadingProfiles = false
            self.profilesLoaded = true
            if self.profiles != list { self.profiles = list }
            self.applyProfile()
        }
    }

    /// Matches the layout and the camera against the profiles (plan §8.6).
    private func applyProfile() {
        guard profilesLoaded else { return }
        let cameraKey = cameraID ?? ""
        let match = ForkGlanceProfiles.match(layout: layout, cameraID: cameraKey, in: profiles)
        var choice = ForkGlanceServiceRules.choose(match, layout: layout, cameraID: cameraKey, profiles: profiles,
                                                   now: Date())
        if choice.need != nil, choice.profile.id == removedSignature { choice.need = .removed }
        // A profile already in force keeps its in-memory state (clicks not written yet).
        if !choice.isNew, let current = profile, current.id == choice.profile.id { choice.profile = current }

        if profile?.id != choice.profile.id {
            profileGeneration += 1
            if !choice.isNew {
                choice.profile.lastUsed = Date()
                store(choice.profile)
            }
        }
        if profile != choice.profile { profile = choice.profile }
        profileIsNew = choice.isNew
        if layoutMoved != choice.moved { layoutMoved = choice.moved }
        let drift = choice.profile.learning.driftSuggested(mode: settings.mode)
        if driftSuggested != drift { driftSuggested = drift }
        need = choice.need
        if !calibrationActive { pipeline.vision.usesEyes = choice.profile.calibration?.usesEyes ?? false }

        // The new layout's notice once per layout, not again at each launch.
        let signature = ForkGlanceProfiles.signature(layout: layout, cameraID: cameraKey)
        let defaults = UserDefaults.standard
        newLayoutNoticeAllowed = defaults.string(forKey: ForkDefaultsKey.glanceLastLayoutSignature) != signature
        defaults.set(signature, forKey: ForkDefaultsKey.glanceLastLayoutSignature)

        recomputeZones()
        send(.calibrationNeed(need))
        newLayoutNoticeAllowed = false
    }

    /// Keeps `updated` in memory and on disk, in place of `old` when rekeyed.
    private func store(_ updated: ForkGlanceProfile, replacing old: String? = nil) {
        let list = ForkGlanceServiceRules.replacing(old ?? updated.id, with: updated, in: profiles)
        profiles = list
        ForkGlanceStore.shared.save(list)
        if let id = profile?.id, id == updated.id || id == old {
            profile = updated
            profileIsNew = false
        }
    }

    private func recomputeZones() {
        var windows: [ForkGlanceWindow] = []
        if settings.mode == .windows, isUp {
            windows = ForkGlanceWindowIndex.shared.windows()
            windowApps = Dictionary(windows.map { ($0.id, $0.appName) }, uniquingKeysWith: { first, _ in first })
        } else {
            windowApps = [:]
        }
        let splits = profile?.splits ?? ForkGlanceZones.defaultSplits(layout)
        let fresh = ForkGlanceZones.zones(layout: layout, mode: settings.mode, splits: splits, windows: windows)
        lastWindowZones = clock.now
        guard fresh != zones else { return }
        zones = fresh
        mark(.zonesChanged(time: 0, zones: fresh))
        send(.zonesChanged(fresh))
    }

    // MARK: - Camera

    private func applyCamera() {
        let wanted = calibrationActive || (isUp && machineWantsCamera)
        let camera = ForkGlanceCamera.shared
        if wanted, !cameraRunning {
            cameraRunning = true
            resetPipeline()
            camera.start(deviceID: cameraID)
            camera.setRate(calibrationActive ? Self.calibrationRate : machineRate ?? 12)
            if isUp {
                ForkGlanceInputWatch.shared.start()
                cost.cameraOn(Self.costReading(at: clock.now))
            }
            lastHistoryHead = nil
            refreshFocusZone(force: true)
        } else if !wanted, cameraRunning {
            cameraRunning = false
            resetPipeline()
            camera.stop()
            ForkGlanceInputWatch.shared.stop()
            ForkGlanceHalo.shared.moveGazeDot(to: nil)
            cost.cameraOff(Self.costReading(at: clock.now))
            lastObservation = nil
            lastSample = nil
            lastEstimate = nil
            lastGaze = nil
            recenterCollect = nil
            publishLive()
        }
    }

    /// The camera changed while running: closed, then opened on the new one.
    private func restartCamera() {
        guard cameraRunning else { return }
        resetPipeline()
        ForkGlanceCamera.shared.start(deviceID: cameraID)
    }

    /// Images of before are dropped, the face searched anew, the filter started over.
    private func resetPipeline() {
        pipeline.reset()
        pipeline.vision.usesEyes = calibrationActive || (profile?.calibration?.usesEyes ?? false)
        pipeline.vision.wantsQuality = calibrationActive
    }

    // MARK: - Images

    fileprivate func received(_ frame: ForkGlanceFrame) {
        guard cameraRunning, frame.generation == pipeline.generation else { return }
        let now = clock.now
        let sample = frame.sample
        lastObservation = frame.observation
        lastSample = sample
        if calibrationActive { calibrationFeed?(sample, frame.observation) }

        var estimate: ForkGlanceEstimate?
        var gaze: ForkGlanceGaze?
        let calibration = profile?.calibration
        if isUp, machine != nil, !calibrationActive {
            if settings.mode == .windows, now - lastWindowZones >= Self.windowZonesInterval { recomputeZones() }
            let inputs = ForkGlanceInputWatch.shared.snapshot()
            lastInputs = inputs
            send(.inputs(inputs))
            estimate = calibration.flatMap { ForkGlanceCalibrationModel.estimate(sample, with: $0) }
            gaze = classifier.classify(estimate, sample: sample, zones: zones, layout: layout, calibration: calibration,
                                       current: machine?.currentZone, sensitivity: settings.sensitivity,
                                       headSpeed: frame.headSpeed)
            lastGaze = gaze
            send(.gaze(gaze))
            if now - lastFocusCheck >= Self.focusCheckInterval { refreshFocusZone(force: false) }
            if var recording, recording.generation == recordingGeneration {
                recording.trace.frames.append(ForkGlanceTrace.Frame(
                    time: frame.time - recording.start, sample: sample.facePresent ? sample : nil, gaze: gaze,
                    input: ForkGlanceTrace.Input(inputs, neverLeaveApps: settings.neverLeaveApps),
                    guards: machine?.guards ?? []))
                self.recording = recording
            }
        } else if let calibration {
            // The assistant's validation draws the estimate.
            estimate = ForkGlanceCalibrationModel.estimate(sample, with: calibration)
        }
        lastEstimate = estimate

        if var collect = recenterCollect, collect.generation == profileGeneration, sample.facePresent {
            collect.samples.append(sample)
            recenterCollect = collect
        }
        if isUp, settings.gazeDot, !calibrationActive {
            ForkGlanceHalo.shared.moveGazeDot(to: estimate?.point)
        }
        if isUp, cost.due(at: now) { cost.add(Self.costReading(at: now)) }
        if leases > 0 { publishLive(gaze: gaze) }
    }

    // MARK: - Focus

    private func performFocus(_ zoneID: String) {
        guard let zone = zones.first(where: { $0.id == zoneID }) else {
            failLater(zoneID)
            return
        }
        let index = ForkGlanceWindowIndex.shared
        let recent = index.recentWindowIDs()
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let target = ForkGlanceTargeting.target(for: zone, mode: settings.mode, windows: index.windows(),
                                                      recent: recent, neverFocus: Array(settings.neverFocusApps),
                                                      frontmostPID: front) else {
            // An empty zone switches nothing (plan §5.2).
            failLater(zoneID)
            return
        }
        let alreadyFocused = front == target.window.pid && recent.first == target.window.id
        if !alreadyFocused { rememberPointer() }
        pendingSwitch = PendingSwitch(zone: zone, target: target, alreadyFocused: alreadyFocused)
        if !ForkGlanceFocuser.shared.focus(target, raise: settings.raise) {
            pendingSwitch = nil
            failLater(zoneID)
            // Accessibility withdrawn behind our back: the machine stops watching.
            if !AXIsProcessTrusted() { DispatchQueue.main.async { [weak self] in self?.sendSystem() } }
        }
    }

    /// The machine hears of a failure after its own pass, never inside it.
    private func failLater(_ zone: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isUp else { return }
            self.mark(.switched(time: 0, zone: zone, succeeded: false))
            self.send(.focusResult(zone: zone, succeeded: false))
        }
    }

    private func focusFinished(_ target: ForkGlanceTarget, succeeded: Bool) {
        guard isUp, let pending = pendingSwitch, pending.target.window.id == target.window.id,
              pending.zone.id == target.zoneID else { return }
        pendingSwitch = nil
        let now = clock.now
        mark(.switched(time: 0, zone: target.zoneID, succeeded: succeeded))
        if succeeded {
            classifier.noteSwitch(to: target.zoneID, at: now)
            lastSwitched = (target.window.id, target.zoneID)
            lastHistoryHead = target.window.id
            ForkGlanceWindowIndex.shared.invalidate()
            if !pending.alreadyFocused {
                recentSwitches = ForkGlanceServiceRules.appending(
                    ForkGlanceSwitchRecord(date: Date(), zoneID: target.zoneID,
                                           zoneName: zoneName(target.zoneID) ?? target.window.appName,
                                           appName: target.window.appName),
                    to: recentSwitches)
                movePointer(for: target, zone: pending.zone)
                focusPane(target)
            }
        } else {
            focusFailures[target.window.appName, default: 0] += 1
        }
        feedback = (target.zoneID, target, pending.alreadyFocused)
        send(.focusResult(zone: target.zoneID, succeeded: succeeded))
    }

    private func showFeedback(_ zoneID: String) {
        guard let feedback, feedback.zone == zoneID, !feedback.silent else { return }
        self.feedback = nil
        switch settings.feedback {
        case .none:
            break
        case .halo:
            ForkGlanceHalo.shared.flash(feedback.target.window.frame, style: .halo)
        case .zoneFlash:
            if let zone = zones.first(where: { $0.id == zoneID }) {
                ForkGlanceHalo.shared.flash(zone.rect, style: .zoneFlash)
            }
        }
    }

    /// The person changed window themselves: the zone of the key window.
    /// Cheap at each check (the use history's head); one Accessibility round
    /// trip only when an app was just activated.
    private func refreshFocusZone(force: Bool) {
        guard isUp, let machine else { return }
        lastFocusCheck = clock.now
        let index = ForkGlanceWindowIndex.shared
        let head = index.recentWindowIDs().first
        guard force || head != lastHistoryHead else { return }
        lastHistoryHead = head
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let windows = index.windows()
        var windowID = head.flatMap { id in windows.first { $0.id == id && $0.pid == front.processIdentifier }?.id }
        if windowID == nil, force { windowID = index.focusedWindowID() }
        guard let windowID, let window = windows.first(where: { $0.id == windowID }) else {
            if force, machine.currentZone != nil { send(.focusChanged(zone: nil)) }
            return
        }
        // Our own switch landing is not the person's choice.
        if let lastSwitched, lastSwitched.window == window.id, lastSwitched.zone == machine.currentZone { return }
        let zone = ForkGlanceTargeting.zone(of: window, in: zones)?.id
        guard zone != machine.currentZone else { return }
        mark(.focusChanged(time: 0, zone: zone))
        send(.focusChanged(zone: zone))
    }

    // MARK: - Pointer and panes (plan §5.4, §6.3)

    private static func pointerLocation() -> CGPoint? {
        CGEvent(source: nil)?.location
    }

    /// Where the pointer was on the display it leaves, for « Suivre l'écran ».
    private func rememberPointer() {
        guard let point = Self.pointerLocation(),
              let display = ForkGlanceZones.display(containing: point, in: layout) else { return }
        pointerByDisplay[display.uuid] = point
    }

    private func movePointer(for target: ForkGlanceTarget, zone: ForkGlanceZone) {
        guard let display = layout.displays.first(where: { $0.uuid == zone.displayUUID }) else { return }
        let followsMouse = AppFeature.focusFollowsMouse.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.focusFollowsMouseEnabled)
        guard let destination = ForkGlanceTargeting.pointerDestination(
            behavior: settings.pointer, target: target, display: display,
            remembered: pointerByDisplay[display.uuid], focusFollowsMouse: followsMouse) else { return }
        if let current = Self.pointerLocation() {
            // Already where it should be: inside the window, or on that display for « Suivre l'écran ».
            if target.window.frame.contains(current) { return }
            if settings.pointer == .followScreen, !followsMouse, display.frame.contains(current) { return }
        }
        ForkGlanceFocuser.shared.movePointer(to: destination)
        ForkGlanceInputWatch.shared.ignorePointer()
    }

    private func focusPane(_ target: ForkGlanceTarget) {
        guard settings.mode == .windows, settings.panes,
              ForkGlanceSettings.list(settings.panesApps, contains: target.window.bundleID),
              let point = lastEstimate?.point else { return }
        let typing = lastInputs.sinceKey < settings.typingPause
        _ = ForkGlancePanes.focusPane(at: point, in: target, clickFallback: settings.panesClickFallback, typing: typing)
        if settings.panesClickFallback { ForkGlanceInputWatch.shared.ignorePointer() }
    }

    // MARK: - Notices and the mascot (plan §11.4, §11.7)

    private func present(_ notice: ForkGlanceNotice) {
        switch notice {
        case .paused, .resumed:
            guard ForkGlanceServiceRules.showsPauseNotice(notice, origin: noticeOrigin ?? .deadline) else { return }
        case .newLayout:
            guard newLayoutNoticeAllowed else { return }
        case .calibrated:
            NotchService.shared.reactMascot(.celebrate)
        case .cameraUnavailable, .recentered, .drift:
            break
        }
        ForkGlanceIsland.show(notice)
    }

    private func withOrigin(_ origin: ForkGlanceServiceRules.NoticeOrigin, _ work: () -> Void) {
        let previous = noticeOrigin
        noticeOrigin = origin
        work()
        noticeOrigin = previous
    }

    private static func origin(_ source: ForkGlanceActionSource) -> ForkGlanceServiceRules.NoticeOrigin {
        switch source {
        case .shortcut: return .shortcut
        case .commandBar: return .commandBar
        case .island, .settings: return .surface
        }
    }

    private func suggestDrift() {
        if !driftSuggested { driftSuggested = true }
        let now = Date()
        guard ForkGlanceServiceRules.driftNoticeDue(last: lastDriftNotice, now: now) else { return }
        lastDriftNotice = now
        NotchService.shared.reactMascot(.confused)
        present(.drift)
    }

    // MARK: - Pause (plan §7.5)

    private func restorePause() {
        let stored = ForkGlancePause.stored()
        switch stored {
        case .none:
            ForkGlancePause.store(.none)
            pausedUntil = nil
            userPauseUptime = nil
        case .untilResumed:
            pausedUntil = nil
            userPauseUptime = nil
            withOrigin(.restore) { send(.pause(.user, until: nil)) }
        case let .until(date):
            pausedUntil = date
            let until = ForkGlancePauseRules.uptime(of: date, now: Date(), uptime: clock.now)
            userPauseUptime = until
            withOrigin(.restore) { send(.pause(.user, until: until)) }
        }
    }

    /// `systemUptime` stood still while the Mac slept: the timed pause's
    /// end is converted again from the wall clock.
    private func resyncUserPause() {
        guard case let .until(date) = ForkGlancePauseRules.decode(
            UserDefaults.standard.string(forKey: ForkDefaultsKey.glancePausedUntil)) else { return }
        let now = Date()
        if date <= now {
            withOrigin(.deadline) { send(.resume(.user)) }
            return
        }
        let until = ForkGlancePauseRules.uptime(of: date, now: now, uptime: clock.now)
        guard abs(until - (userPauseUptime ?? until)) > 1 else { return }
        userPauseUptime = until
        withOrigin(.restore) { send(.pause(.user, until: until)) }
    }

    /// The machine ended the person's pause (its deadline, a resume): the key goes.
    private func syncPersistedPause() {
        guard let machine, !machine.pauses.contains(.user), userPauseUptime != nil || pausedUntil != nil
                || ForkGlancePause.stored() != .none else { return }
        ForkGlancePause.store(.none)
        userPauseUptime = nil
        if pausedUntil != nil { pausedUntil = nil }
    }

    // MARK: - Actions

    func pause(_ duration: ForkGlancePauseDuration, from source: ForkGlanceActionSource) {
        precondition(Thread.isMainThread)
        guard isUp else { return }
        let now = Date()
        let stored = ForkGlancePause.stored(for: duration, now: now)
        ForkGlancePause.store(stored)
        let end = duration.end(from: now)
        pausedUntil = end
        let until = end.map { ForkGlancePauseRules.uptime(of: $0, now: now, uptime: clock.now) }
        userPauseUptime = until
        withOrigin(Self.origin(source)) { send(.pause(.user, until: until)) }
        NotchService.shared.reactMascot(.hush)
    }

    func resume(from source: ForkGlanceActionSource) {
        precondition(Thread.isMainThread)
        guard isUp else { return }
        ForkGlancePause.store(.none)
        pausedUntil = nil
        userPauseUptime = nil
        withOrigin(Self.origin(source)) { send(.resume(.user)) }
    }

    /// Lifts a battery, Low Power or thermal pause until it changes.
    func resumeAnyway() {
        precondition(Thread.isMainThread)
        send(.resumeAnyway)
    }

    /// « Recentrer » (plan §8.3): the gaze is on the pointer. The samples of
    /// the next 0.6 s give the offset.
    func recenter(from source: ForkGlanceActionSource) {
        precondition(Thread.isMainThread)
        guard isUp, cameraRunning, !calibrationActive, profile?.calibration != nil,
              let target = Self.pointerLocation() else { return }
        let generation = profileGeneration
        recenterCollect = RecenterCollect(target: target, samples: [], generation: generation)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.recenterSpan) { [weak self] in
            self?.finishRecenter(generation: generation)
        }
    }

    private func finishRecenter(generation: Int) {
        guard let collect = recenterCollect, collect.generation == generation, generation == profileGeneration else {
            return
        }
        recenterCollect = nil
        guard !collect.samples.isEmpty, var current = profile, let calibration = current.calibration else { return }
        current.calibration = ForkGlanceCalibrationModel.recentered(calibration, samples: collect.samples,
                                                                    target: collect.target, layout: layout)
        store(current)
        present(.recentered)
    }

    func setMode(_ mode: ForkGlanceMode) {
        precondition(Thread.isMainThread)
        UserDefaults.standard.set(mode.rawValue, forKey: ForkDefaultsKey.glanceMode)
        settingsChanged()
    }

    func setSplit(_ split: ForkGlanceSplit, display uuid: String) {
        precondition(Thread.isMainThread)
        guard var current = profile, current.splits[uuid] != split else { return }
        current.splits[uuid] = split
        store(current)
        recomputeZones()
    }

    func deleteProfile(_ id: String) {
        precondition(Thread.isMainThread)
        let list = profiles.filter { $0.id != id }
        if list != profiles {
            profiles = list
            ForkGlanceStore.shared.save(list)
        }
        pointsStore.remove(id)
        guard profile?.id == id else { return }
        removedSignature = id
        profile = nil
        applyProfile()
    }

    /// Nil: the built-in camera. Choosing the camera in use again retries it
    /// after a failure (« Réessayer »).
    func selectCamera(_ id: String?) {
        precondition(Thread.isMainThread)
        UserDefaults.standard.set(id ?? "", forKey: ForkDefaultsKey.glanceCameraID)
        refreshDevices()
        // A running session is rebuilt on the camera now chosen, the same one included.
        restartCamera()
        guard isUp else {
            if profilesLoaded { applyProfile() }
            return
        }
        ForkGlanceCamera.shared.watch(deviceID: cameraID)
        // After a failure the camera is off: the machine asks for it again,
        // and `applyCamera` opens a new session.
        if failure != nil {
            failure = nil
            send(.cameraFailure(nil))
        }
        applyProfile()
        sendSystem()
    }

    func requestCameraPermission() {
        precondition(Thread.isMainThread)
        ForkGlanceCamera.requestPermission { [weak self] _ in
            guard let self else { return }
            self.cameraPermission = ForkGlanceCamera.permission
            self.refreshDevices()
            self.sendSystem()
        }
    }

    /// Opens the assistant (`Calibration/ForkGlanceCalibrationWindow`).
    func openCalibration(_ entry: ForkGlanceCalibrationEntry) {
        precondition(Thread.isMainThread)
        refreshWhileDown()
        ForkGlanceCalibrationWindow.show(entry)
    }

    /// Switched off, nothing follows the displays: the assistant reads them now.
    private func refreshWhileDown() {
        guard !isUp else { return }
        let current = ForkGlanceDisplays.current()
        guard current != layout else { return }
        layout = current
        applyProfile()
    }

    /// Opens Settings on the feature's page.
    func openSettings() {
        precondition(Thread.isMainThread)
        ForkSettingsPages.open(.glanceFocus)
    }

    private func hotKeyPressed(_ role: ForkGlanceShortcutRole) {
        guard isUp else { return }
        switch role {
        case .pause:
            if machine?.pauses.contains(.user) == true {
                resume(from: .shortcut)
            } else {
                pause(.untilResumed, from: .shortcut)
            }
        case .recenter:
            recenter(from: .shortcut)
        case .mode:
            setMode(ForkGlanceServiceRules.nextMode(after: settings.mode))
        }
    }

    // MARK: - Live readings

    /// Live readings while the lease lives (plan §11.1, §12.11).
    func liveLease() -> ForkGlanceLease {
        precondition(Thread.isMainThread)
        leases += 1
        publishLive(gaze: lastGaze)
        return ForkGlanceLease { [weak self] in
            if Thread.isMainThread {
                self?.leaseReleased()
            } else {
                DispatchQueue.main.async { self?.leaseReleased() }
            }
        }
    }

    private func leaseReleased() {
        leases = max(0, leases - 1)
        if leases == 0, live != nil { live = nil }
    }

    private func publishLive(gaze: ForkGlanceGaze? = nil) {
        guard leases > 0 else {
            if live != nil { live = nil }
            return
        }
        let timing = pipeline.vision.timing
        let rate = cost.cost
        let value = ForkGlanceLive(
            time: clock.now, observation: lastObservation, sample: lastSample, estimate: lastEstimate,
            gaze: gaze ?? lastGaze, frameRate: cameraRunning ? ForkGlanceCamera.shared.measuredRate : 0,
            visionMean: timing.mean, visionP95: timing.p95, guards: machine?.guards ?? [],
            extraEntry: classifier.extraEntry, setAside: ForkGlanceFocuser.shared.setAside,
            focusFailures: focusFailures, clickAgreement: profile?.learning.agreement,
            cpuCores: rate?.cores, watts: rate?.watts, revisions: revisionsText)
        if live != value { live = value }
    }

    private var revisionsText: String {
        let used = pipeline.vision.revisions
        return "rectangles rev \(used.rectangles), landmarks rev \(used.landmarks)"
    }

    /// The process's CPU time and energy. `ri_energy_nj` only exists from
    /// `rusage_info_v6` on (`sys/resource.h`; v4, the plan's, stops at
    /// `ri_runnable_time`), which every macOS from 12 answers; v4 stays the
    /// fallback, without the energy.
    private static func costReading(at time: TimeInterval) -> ForkGlanceCostMeter.Reading {
        var base = mach_timebase_info_data_t()
        mach_timebase_info(&base)
        // CPU times are in Mach absolute units (`ForkMacBackupCostMeter`).
        func seconds(_ ticks: UInt64) -> Double {
            let value = Double(ticks)
            return (base.denom == 0 ? value : value * Double(base.numer) / Double(base.denom)) / 1_000_000_000
        }
        var current = rusage_info_v6()
        if read(&current, flavor: RUSAGE_INFO_V6) {
            let energy = current.ri_energy_nj > 0 ? Double(current.ri_energy_nj) / 1_000_000_000 : nil
            return ForkGlanceCostMeter.Reading(time: time, cpuSeconds: seconds(current.ri_user_time + current.ri_system_time),
                                               energyJoules: energy)
        }
        var older = rusage_info_v4()
        guard read(&older, flavor: RUSAGE_INFO_V4) else {
            return ForkGlanceCostMeter.Reading(time: time, cpuSeconds: 0, energyJoules: nil)
        }
        return ForkGlanceCostMeter.Reading(time: time, cpuSeconds: seconds(older.ri_user_time + older.ri_system_time),
                                           energyJoules: nil)
    }

    private static func read<Info>(_ info: inout Info, flavor: Int32) -> Bool {
        withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), flavor, $0) == 0
            }
        }
    }

    // MARK: - Trace and report (plan §12.11)

    /// Records a 60 s trace and offers to save it (plan §12.11); nil on cancel or failure.
    func recordTrace(seconds: TimeInterval, completion: @escaping (URL?) -> Void) {
        precondition(Thread.isMainThread)
        guard isUp, recording == nil else {
            completion(nil)
            return
        }
        recordingGeneration += 1
        let generation = recordingGeneration
        let trace = ForkGlanceTrace(
            recorded: Date(), appVersion: Self.appVersion, settings: settings, layout: layout,
            layoutSignature: profile?.id ?? "", usesEyes: profile?.calibration?.usesEyes ?? false, zones: zones,
            initialZone: machine?.currentZone)
        recording = Recording(start: clock.now, trace: trace, completion: completion, generation: generation)
        let span = min(max(seconds, 1), ForkGlanceTrace.maxDuration)
        DispatchQueue.main.asyncAfter(deadline: .now() + span) { [weak self] in
            guard let self, self.recording?.generation == generation else { return }
            self.finishRecording(cancelled: false)
        }
    }

    /// Something happened between images, for the trace being recorded.
    private func mark(_ mark: ForkGlanceTrace.Mark) {
        guard var recording, recording.generation == recordingGeneration else { return }
        let time = clock.now - recording.start
        switch mark {
        case let .click(_, point, zone): recording.trace.marks.append(.click(time: time, point: point, zone: zone))
        case let .focusChanged(_, zone): recording.trace.marks.append(.focusChanged(time: time, zone: zone))
        case let .switched(_, zone, succeeded):
            recording.trace.marks.append(.switched(time: time, zone: zone, succeeded: succeeded))
        case let .zonesChanged(_, zones): recording.trace.marks.append(.zonesChanged(time: time, zones: zones))
        }
        self.recording = recording
    }

    private func finishRecording(cancelled: Bool) {
        guard let recording else { return }
        self.recording = nil
        recordingGeneration += 1
        let completion = recording.completion
        guard !cancelled, !recording.trace.frames.isEmpty else {
            completion(nil)
            return
        }
        let trace = recording.trace
        DispatchQueue.global(qos: .utility).async {
            let data = try? ForkGlanceTrace.encode(trace)
            DispatchQueue.main.async { [weak self] in
                guard let self, let data else {
                    completion(nil)
                    return
                }
                self.offerToSave(data, recorded: trace.recorded, completion: completion)
            }
        }
    }

    private func offerToSave(_ data: Data, recorded: Date, completion: @escaping (URL?) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        panel.nameFieldStringValue = "glance-trace-\(formatter.string(from: recorded)).json"
        NSApp.activate()
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                completion(nil)
                return
            }
            DispatchQueue.global(qos: .utility).async {
                let written = (try? data.write(to: url, options: .atomic)) != nil
                DispatchQueue.main.async { completion(written ? url : nil) }
            }
        }
    }

    /// « Copier le rapport »: version, Mac, layout, score, settings.
    func reportText() -> String {
        precondition(Thread.isMainThread)
        let device = cameraDevices.first { $0.id == cameraID }
        let camera = device.map { $0.isBuiltIn ? "built-in" : ($0.isContinuity ? "Continuity" : "external") } ?? "none"
        let timing = pipeline.vision.timing
        return ForkGlanceServiceRules.report(ForkGlanceServiceRules.ReportInput(
            appVersion: Self.appVersion, macModel: Self.macModel,
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString, layout: layout, camera: camera,
            settings: settings, profile: profile, phase: phase, cost: cost.cost,
            frameRate: cameraRunning ? ForkGlanceCamera.shared.measuredRate : 0,
            visionMean: timing.mean, visionP95: timing.p95, revisions: revisionsText, now: Date()))
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "Developer"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private static var macModel: String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "Mac" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "Mac" }
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    // MARK: - Learning from clicks (plan §7.6)

    private func clicked(at point: CGPoint, time: TimeInterval) {
        guard isUp, !calibrationActive, var current = profile, current.calibration != nil else { return }
        let clickedZone = ForkGlanceServiceRules.zone(at: point, in: zones)
        mark(.click(time: 0, point: point, zone: clickedZone?.id))
        var changed = false
        if let clickedZone, let predicted = ForkGlanceServiceRules.prediction(lastGaze, clickTime: time) {
            current.learning.recordAgreement(predicted: predicted, clicked: clickedZone.id)
            changed = true
        }
        if settings.learnFromClicks, let sample = lastSample,
           ForkGlanceServiceRules.teaches(sample: sample, clickTime: time) {
            current.learning.add(sample, click: point, at: Date())
            changed = true
        }
        guard changed else { return }
        profile = current
        if current.learning.driftSuggested(mode: settings.mode) { suggestDrift() }
        if current.learning.refitDue { refit() } else { scheduleLearningSave() }
    }

    /// The clicks are written a little later, in one go.
    private func scheduleLearningSave() {
        guard learningSave == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.learningSave = nil
            self?.flushLearning()
        }
        learningSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.learningSaveDelay, execute: work)
    }

    private func flushLearning() {
        learningSave?.cancel()
        learningSave = nil
        guard let current = profile, !profileIsNew,
              let stored = profiles.first(where: { $0.id == current.id }), stored != current else { return }
        store(current)
    }

    /// Calibration points + weighted clicks, off the main thread; kept only
    /// when it does not make the calibration points worse.
    private func refit() {
        guard !refitting, var current = profile, let old = current.calibration, !profileIsNew else { return }
        refitting = true
        current.learning.markRefit()
        store(current)
        let learned = current.learning.weighted(now: Date())
        let id = current.id, generation = profileGeneration, layout = self.layout
        pointsStore.withPoints(for: id) { calibrationPoints in
            var accepted: ForkGlanceCalibration?
            if let calibrationPoints, !calibrationPoints.isEmpty,
               var fitted = try? ForkGlanceCalibrationModel.fit(
                   points: calibrationPoints, learned: learned, usesEyes: old.usesEyes, layout: layout,
                   cameraID: old.cameraID, layoutSignature: old.layoutSignature, date: old.date) {
                fitted.bias = old.bias
                fitted.zoneAccuracy = old.zoneAccuracy
                if ForkGlanceLearning.accepts(old: old, new: fitted, calibrationPoints: calibrationPoints) {
                    accepted = fitted
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.refitting = false
                guard let accepted, generation == self.profileGeneration, var latest = self.profile,
                      latest.id == id else {
                    Self.log.info("refit from clicks not kept")
                    return
                }
                latest.calibration = accepted
                self.store(latest)
                Self.log.info("refit from clicks kept")
            }
        }
    }

    // MARK: - The assistant's feed (B2)

    /// Every processed image while the assistant runs, on the main thread.
    var calibrationFeed: ((ForkGlanceSample, ForkGlanceObservation?) -> Void)?

    /// The assistant starts: the machine pauses switching (`calibrating`),
    /// the camera runs for the assistant. False when it cannot (permission, no camera).
    func beginCalibration() -> Bool {
        precondition(Thread.isMainThread)
        cameraPermission = ForkGlanceCamera.permission
        refreshDevices()
        guard cameraPermission == .granted, let id = cameraID, cameraDevices.contains(where: { $0.id == id }) else {
            return false
        }
        refreshWhileDown()
        calibrationGeneration += 1
        recenterCollect = nil
        if !calibrationActive {
            calibrationActive = true
            calibrationProgress = nil
            resetPipeline()
            send(.calibrationStarted)
        }
        applyCamera()
        ForkGlanceCamera.shared.setRate(Self.calibrationRate)
        publishState()
        return true
    }

    /// Progress for the island's activity (« 12/30 »).
    func calibrationProgressed(done: Int, total: Int) {
        precondition(Thread.isMainThread)
        calibrationProgress = (done, total)
        publishState()
    }

    /// Points collected: fit off the main thread, store in the profile,
    /// completion on main with the calibration or the error.
    func finishCalibration(points: [ForkGlanceCalibrationPoint], splits: [String: ForkGlanceSplit],
                           mode: ForkGlanceMode,
                           completion: @escaping (Result<ForkGlanceCalibration, Error>) -> Void) {
        precondition(Thread.isMainThread)
        calibrationGeneration += 1
        let generation = calibrationGeneration
        let layout = self.layout
        let cameraKey = cameraID ?? ""
        let signature = ForkGlanceProfiles.signature(layout: layout, cameraID: cameraKey)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result<ForkGlanceCalibration, Error> {
                try ForkGlanceCalibrationModel.fit(points: points, usesEyes: nil, layout: layout, cameraID: cameraKey,
                                                   layoutSignature: signature, date: Date())
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if case let .success(calibration) = result, generation == self.calibrationGeneration {
                    self.keep(calibration, points: points, splits: splits, mode: mode, layout: layout,
                              cameraKey: cameraKey)
                }
                completion(result)
            }
        }
    }

    private func keep(_ calibration: ForkGlanceCalibration, points calibrationPoints: [ForkGlanceCalibrationPoint],
                      splits: [String: ForkGlanceSplit], mode: ForkGlanceMode, layout: ForkGlanceDisplayLayout,
                      cameraKey: String) {
        let base = profile ?? ForkGlanceProfiles.newProfile(layout: layout, cameraID: cameraKey, now: Date())
        var updated = ForkGlanceServiceRules.rekeyed(base, layout: layout, cameraID: cameraKey)
        updated.splits = splits
        updated.calibration = calibration
        updated.learning = ForkGlanceLearning()
        updated.lastUsed = Date()
        store(updated, replacing: base.id)
        pointsStore.save(calibrationPoints, for: updated.id, replacing: base.id)
        profile = updated
        profileIsNew = false
        profileGeneration += 1
        removedSignature = nil
        need = nil
        if layoutMoved { layoutMoved = false }
        if driftSuggested { driftSuggested = false }
        UserDefaults.standard.set(updated.id, forKey: ForkDefaultsKey.glanceLastLayoutSignature)
        if mode != settings.mode {
            UserDefaults.standard.set(mode.rawValue, forKey: ForkDefaultsKey.glanceMode)
            if isUp { settingsChanged() } else { settings = .read() }
        }
        recomputeZones()
        publishState()
    }

    /// The validation's per-zone scores, then the notice and the mascot.
    func finishValidation(zoneAccuracy: [String: Double]) {
        precondition(Thread.isMainThread)
        if var current = profile, current.calibration != nil {
            current.calibration?.zoneAccuracy = zoneAccuracy
            store(current)
        }
        let score = ForkGlanceServiceRules.score(zoneAccuracy)
        // The machine first: it asks for the camera the assistant already
        // runs, so the light never blinks between the two.
        if machine != nil {
            send(.calibrationFinished(score: score))
        } else {
            present(.calibrated(score: score))
        }
        endCalibration()
    }

    /// The quick recenter's points: bias and a small refit.
    func finishQuickRecenter(points recenterPoints: [ForkGlanceCalibrationPoint]) {
        precondition(Thread.isMainThread)
        if var current = profile, let calibration = current.calibration {
            let oldID = current.id
            if layoutMoved {
                // The layout as it is now becomes the profile's (plan §8.6 case 2).
                current = ForkGlanceServiceRules.rekeyed(current, layout: layout, cameraID: cameraID ?? "")
                pointsStore.rename(oldID, to: current.id)
                layoutMoved = false
                profileGeneration += 1
            }
            current.calibration = ForkGlanceCalibrationModel.recentered(calibration, points: recenterPoints,
                                                                        layout: layout)
            store(current, replacing: oldID)
            profile = current
            present(.recentered)
        }
        send(.calibrationNeed(need))
        send(.calibrationCancelled)
        endCalibration()
    }

    func cancelCalibration() {
        precondition(Thread.isMainThread)
        calibrationGeneration += 1
        guard calibrationActive else { return }
        send(.calibrationNeed(need))
        send(.calibrationCancelled)
        endCalibration()
    }

    /// The model's estimate for a sample, with the current profile (validation step).
    func estimate(_ sample: ForkGlanceSample) -> ForkGlanceEstimate? {
        guard let calibration = profile?.calibration else { return nil }
        return ForkGlanceCalibrationModel.estimate(sample, with: calibration)
    }

    /// The assistant is done: back to the machine's camera and rate.
    private func endCalibration() {
        guard calibrationActive else { return }
        calibrationActive = false
        calibrationProgress = nil
        pipeline.vision.usesEyes = profile?.calibration?.usesEyes ?? false
        pipeline.vision.wantsQuality = false
        applyCamera()
        if cameraRunning, let machineRate { ForkGlanceCamera.shared.setRate(machineRate) }
        publishState()
    }
}

// MARK: - The capture side

/// One image, back on the main thread.
private struct ForkGlanceFrame: Sendable {
    var generation: Int
    var time: TimeInterval
    var observation: ForkGlanceObservation?
    var sample: ForkGlanceSample
    var headSpeed: Double
}

/// Vision, the features and the filter, on the camera's capture queue only
/// (`process`); `reset` and `generation` from the main thread, under the lock.
private final class ForkGlancePipeline: @unchecked Sendable {
    let vision = ForkGlanceVision()
    private let lock = NSLock()
    private var currentGeneration = 0
    private var resetPending = true
    // Capture queue only.
    private var features = ForkGlanceFeatures()
    private var filter = ForkGlanceFilter()

    var generation: Int { lock.withLock { currentGeneration } }

    /// Images already on their way are dropped; the next one starts over.
    func reset() {
        lock.withLock {
            currentGeneration += 1
            resetPending = true
        }
        vision.reset()
    }

    func process(_ buffer: CVPixelBuffer, time: TimeInterval) -> ForkGlanceFrame {
        let (generation, restart) = lock.withLock { () -> (Int, Bool) in
            let restart = resetPending
            resetPending = false
            return (currentGeneration, restart)
        }
        if restart {
            features = ForkGlanceFeatures()
            filter.reset()
        }
        let observation = vision.process(buffer, time: time)
        let sample = filter.filter(features.sample(from: observation, time: time))
        return ForkGlanceFrame(generation: generation, time: time, observation: observation, sample: sample,
                               headSpeed: filter.headSpeed)
    }
}

// MARK: - Calibration points on disk

/// The points each profile was calibrated on, next to `profiles.json`
/// (`Glance/calibration-points.json`, owner-only through `PrivateFileStore`):
/// the clicks' refits need them, and so does the check that a refit does
/// not undo the calibration. A profile itself keeps only the fitted model.
/// Everything runs on `queue`, in the order asked.
private final class ForkGlancePointsStore: @unchecked Sendable {
    private let queue = DispatchQueue(label: "fork.glance.points", qos: .utility)
    private let file = PrivateFileStore.containerURL?
        .appendingPathComponent("Glance", isDirectory: true)
        .appendingPathComponent("calibration-points.json", isDirectory: false)
    private let log = Logger(subsystem: "fork.glance", category: "store")
    /// Queue only.
    private var cache: [String: [ForkGlanceCalibrationPoint]]?

    func save(_ points: [ForkGlanceCalibrationPoint], for id: String, replacing old: String?) {
        queue.async {
            var all = self.read()
            if let old, old != id { all[old] = nil }
            all[id] = points
            self.write(all)
        }
    }

    func rename(_ old: String, to new: String) {
        guard old != new else { return }
        queue.async {
            var all = self.read()
            guard let moved = all.removeValue(forKey: old) else { return }
            all[new] = moved
            self.write(all)
        }
    }

    func remove(_ id: String) {
        queue.async {
            var all = self.read()
            guard all.removeValue(forKey: id) != nil else { return }
            self.write(all)
        }
    }

    /// Runs `work` on the store's queue (off the main thread) with the points of `id`.
    func withPoints(for id: String, _ work: @escaping ([ForkGlanceCalibrationPoint]?) -> Void) {
        queue.async { work(self.read()[id]) }
    }

    private func read() -> [String: [ForkGlanceCalibrationPoint]] {
        if let cache { return cache }
        var all: [String: [ForkGlanceCalibrationPoint]] = [:]
        if let file, let data = try? Data(contentsOf: file) {
            let decoder = JSONDecoder()
            decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf",
                                                                            negativeInfinity: "-inf", nan: "nan")
            if let decoded = try? decoder.decode([String: [ForkGlanceCalibrationPoint]].self, from: data) {
                all = decoded
            } else {
                log.error("calibration points unreadable, starting empty")
            }
        }
        cache = all
        return all
    }

    private func write(_ all: [String: [ForkGlanceCalibrationPoint]]) {
        cache = all
        guard let file else { return }
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf",
                                                                      negativeInfinity: "-inf", nan: "nan")
        guard let data = try? encoder.encode(all),
              PrivateFileStore.createDirectory(at: file.deletingLastPathComponent()),
              PrivateFileStore.write(data, to: file) else {
            log.error("calibration points not written")
            return
        }
    }
}
