// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AVFoundation
import AppKit
import Combine
import Foundation
import os

// MARK: - What the assistant needs from the service

/// The service seen from the assistant (plan §8.4): `ForkGlanceService` in the
/// app, a stand-in in the renders, which never start a camera. Main thread.
protocol ForkGlanceCalibrationBackend: AnyObject {
    var layout: ForkGlanceDisplayLayout { get }
    var profile: ForkGlanceProfile? { get }
    var mode: ForkGlanceMode { get }
    var cameraDevices: [ForkGlanceCameraDevice] { get }
    var cameraID: String? { get }
    var cameraPermission: ForkGlanceCameraPermission { get }
    /// Called on the main thread when any of the above may have changed.
    var onChange: (() -> Void)? { get set }
    /// Every processed image while the assistant runs, on the main thread.
    var calibrationFeed: ((ForkGlanceSample, ForkGlanceObservation?) -> Void)? { get set }
    func requestCameraPermission()
    func selectCamera(_ id: String?)
    func beginCalibration() -> Bool
    func calibrationProgressed(done: Int, total: Int)
    func finishCalibration(points: [ForkGlanceCalibrationPoint], splits: [String: ForkGlanceSplit], mode: ForkGlanceMode,
                           completion: @escaping (Result<ForkGlanceCalibration, Error>) -> Void)
    func finishValidation(zoneAccuracy: [String: Double])
    func finishQuickRecenter(points: [ForkGlanceCalibrationPoint])
    func cancelCalibration()
    func estimate(_ sample: ForkGlanceSample) -> ForkGlanceEstimate?
    /// A preview of the running camera; nil when it is not running.
    func makePreviewLayer() -> AVCaptureVideoPreviewLayer?
}

/// The real one: `ForkGlanceService.shared` and its camera.
final class ForkGlanceServiceCalibrationBackend: ForkGlanceCalibrationBackend {
    private let service = ForkGlanceService.shared
    private var observer: AnyCancellable?

    var layout: ForkGlanceDisplayLayout { service.layout }
    var profile: ForkGlanceProfile? { service.profile }
    var mode: ForkGlanceMode { service.settings.mode }
    var cameraDevices: [ForkGlanceCameraDevice] { service.cameraDevices }
    var cameraID: String? { service.cameraID }
    var cameraPermission: ForkGlanceCameraPermission { service.cameraPermission }

    var onChange: (() -> Void)? {
        didSet {
            guard onChange != nil else {
                observer = nil
                return
            }
            // `objectWillChange` fires before the value changes: read it on the next turn.
            observer = service.objectWillChange.sink { [weak self] _ in
                DispatchQueue.main.async { self?.onChange?() }
            }
        }
    }

    var calibrationFeed: ((ForkGlanceSample, ForkGlanceObservation?) -> Void)? {
        get { service.calibrationFeed }
        set { service.calibrationFeed = newValue }
    }

    func requestCameraPermission() { service.requestCameraPermission() }
    func selectCamera(_ id: String?) { service.selectCamera(id) }
    func beginCalibration() -> Bool { service.beginCalibration() }
    func calibrationProgressed(done: Int, total: Int) { service.calibrationProgressed(done: done, total: total) }

    func finishCalibration(points: [ForkGlanceCalibrationPoint], splits: [String: ForkGlanceSplit], mode: ForkGlanceMode,
                           completion: @escaping (Result<ForkGlanceCalibration, Error>) -> Void) {
        service.finishCalibration(points: points, splits: splits, mode: mode, completion: completion)
    }

    func finishValidation(zoneAccuracy: [String: Double]) { service.finishValidation(zoneAccuracy: zoneAccuracy) }
    func finishQuickRecenter(points: [ForkGlanceCalibrationPoint]) { service.finishQuickRecenter(points: points) }
    func cancelCalibration() { service.cancelCalibration() }
    func estimate(_ sample: ForkGlanceSample) -> ForkGlanceEstimate? { service.estimate(sample) }
    func makePreviewLayer() -> AVCaptureVideoPreviewLayer? { ForkGlanceCamera.shared.makePreviewLayer() }
}

// MARK: - The assistant's model

/// What a run of points shows on the displays at one moment (the overlay).
struct ForkGlanceOverlayFrame: Equatable {
    enum Kind: Equatable {
        case points
        case validation
    }

    var kind: Kind
    var target: ForkGlanceCalibrationTarget
    var stage: ForkGlanceCalibrationRun.Stage
    var progress: Double
    /// The point under way, from 1, and the points of the run.
    var number: Int
    var total: Int
    /// Validation: the zone lit around the point, global points.
    var zoneRect: CGRect?
    var isPaused: Bool
    var isRetry: Bool
    var askingCancel: Bool
}

/// The calibration assistant (plan §8.4): its steps, the camera feed while it
/// runs, the framing gauges, the layout chosen, the runs of points, the fit,
/// the validation and its score. Main thread. A preview session (renders)
/// never starts the camera, the overlay or a timer.
final class ForkGlanceCalibrationSession: ObservableObject {
    enum RunKind: Equatable {
        case points
        case weakPoints
        case quick
        case validation
    }

    enum Problem: Equatable {
        case cameraUnavailable
        case fitTooFew
        case fitDegenerate
        case fitFailed
        case layoutChanged
    }

    /// No feed for this long: the preview layer is made again (the camera was rebuilt).
    static let previewRefresh: TimeInterval = 1.5

    let entry: ForkGlanceCalibrationEntry
    let steps: [ForkGlanceAssistantStep]
    let backend: ForkGlanceCalibrationBackend
    let isPreview: Bool
    let clock: ForkGlanceClock

    @Published private(set) var step: ForkGlanceAssistantStep
    @Published private(set) var language: AppLanguage

    // Framing
    @Published private(set) var framing = ForkGlanceFraming.Check.empty
    @Published private(set) var framingReady = false
    @Published private(set) var observation: ForkGlanceObservation?
    @Published private(set) var receiving = false
    @Published private(set) var previewLayer: AVCaptureVideoPreviewLayer?

    // Layout
    @Published private(set) var mode: ForkGlanceMode
    @Published private(set) var splits: [String: ForkGlanceSplit]

    // Runs
    @Published private(set) var run: ForkGlanceCalibrationRun?
    @Published private(set) var runKind: RunKind?
    @Published private(set) var fitting = false
    @Published private(set) var problem: Problem?
    @Published private(set) var askingCancel = false

    // Results
    @Published private(set) var calibration: ForkGlanceCalibration?
    @Published private(set) var accuracy: [String: Double]?

    /// Closes the window (set by `ForkGlanceCalibrationWindow`).
    var onClose: (() -> Void)?
    /// Opens the assistant again on another entry (« Recalibrer » after « Tester »).
    var onReopen: ((ForkGlanceCalibrationEntry) -> Void)?

    private static let logger = Logger(subsystem: "fork.glance", category: "calibration")

    /// The calibration's points by plan id, kept across « Refaire les points faibles ».
    private var collected: [Int: ForkGlanceCalibrationPoint] = [:]
    private(set) var planTargets: [ForkGlanceCalibrationTarget] = []
    private var hold = ForkGlanceFraming.Hold()
    private var lastFeed: TimeInterval = -.infinity
    private var began = false
    private var concluded = false
    private var closed = false
    private var timer: Timer?
    private var framingTimer: Timer?
    private var overlay: ForkGlanceCalibrationOverlay?
    private var languageObserver: AnyCancellable?
    /// The desk the runs were planned on, from the first run until the
    /// assistant ends (`ForkGlanceServiceRules.sameDesk`): the points, the fit
    /// and the score only hold for it.
    private var desk: ForkGlanceDisplayLayout?
    /// The layout last compared, so a change of anything else costs nothing.
    private var lastLayout: ForkGlanceDisplayLayout?
    private var seed = UInt64.random(in: 0...UInt64.max)

    init(entry: ForkGlanceCalibrationEntry, backend: ForkGlanceCalibrationBackend,
         language: AppLanguage? = nil, preview: Bool = false, clock: ForkGlanceClock = ForkGlanceSystemClock()) {
        self.entry = entry
        self.backend = backend
        self.isPreview = preview
        self.clock = clock
        steps = Self.steps(for: entry)
        step = steps.first ?? .points
        self.language = language ?? L10n.shared.language
        mode = backend.mode
        let defaults = ForkGlanceZones.defaultSplits(backend.layout)
        splits = defaults.merging(backend.profile?.splits ?? [:]) { _, chosen in chosen }
        planTargets = ForkGlanceCalibrationPlan.targets(layout: backend.layout, mode: mode, splits: splits)
        if language == nil {
            languageObserver = L10n.shared.$language.dropFirst().receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.language = $0 }
        }
        guard !preview else { return }
        backend.onChange = { [weak self] in self?.backendChanged() }
        enter(step)
    }

    deinit {
        timer?.invalidate()
        framingTimer?.invalidate()
    }

    /// The steps each way in shows (plan §8.4): Calibrer 1 to 7, Recalibrer 3
    /// to 6, Tester 6, Recalage rapide its points, Vérifier le cadrage 3.
    static func steps(for entry: ForkGlanceCalibrationEntry) -> [ForkGlanceAssistantStep] {
        switch entry {
        case .full: return ForkGlanceAssistantStep.allCases
        case .recalibrate: return [.framing, .layout, .points, .validation]
        case .test: return [.validation]
        case .quickRecenter: return [.points]
        case .framing: return [.framing]
        }
    }

    var text: ForkGlanceCalibrationStrings { .strings(language) }
    var core: ForkGlanceStrings { .strings(language) }
    var official: Strings { .localized(language) }
    var locale: Locale { language.formattingLocale() }
    var layout: ForkGlanceDisplayLayout { backend.layout }

    /// The zones of the layout and mode chosen. Windows mode validates the
    /// Zones split: its windows come and go, the displays' parts stay.
    var zones: [ForkGlanceZone] {
        ForkGlanceZones.zones(layout: layout, mode: mode == .windows ? .zones : mode, splits: splits, windows: [])
    }

    var stepNumber: Int { (steps.firstIndex(of: step) ?? 0) + 1 }
    var isRunning: Bool { run != nil && run?.isFinished == false }

    // MARK: Navigation

    var canGoBack: Bool {
        guard let index = steps.firstIndex(of: step), index > 0, !isRunning, !fitting else { return false }
        switch step {
        case .validation: return accuracy == nil
        case .done: return false
        default: return true
        }
    }

    var canGoNext: Bool {
        switch step {
        case .welcome, .layout: return true
        case .permissions: return backend.cameraPermission == .granted
        case .framing: return framingReady
        case .points, .validation, .done: return false
        }
    }

    func next() {
        precondition(Thread.isMainThread)
        guard canGoNext, let index = steps.firstIndex(of: step), index + 1 < steps.count else { return }
        go(to: steps[index + 1])
    }

    func back() {
        precondition(Thread.isMainThread)
        guard canGoBack, let index = steps.firstIndex(of: step) else { return }
        go(to: steps[index - 1])
    }

    private func go(to target: ForkGlanceAssistantStep) {
        problem = nil
        step = target
        enter(target)
    }

    /// What a step needs once shown: the camera from the framing on, the plan
    /// for the points.
    private func enter(_ step: ForkGlanceAssistantStep) {
        guard !isPreview else { return }
        switch step {
        case .welcome, .permissions, .done:
            break
        case .framing:
            ensureCamera()
            startFramingTimer()
        case .layout:
            break
        case .points:
            planTargets = ForkGlanceCalibrationPlan.targets(layout: layout, mode: mode, splits: splits)
            ensureCamera()
        case .validation:
            ensureCamera()
        }
        if step != .framing { stopFramingTimer() }
    }

    // MARK: Permissions and camera

    func requestCamera() {
        guard !isPreview else { return }
        backend.requestCameraPermission()
    }

    func selectCamera(_ id: String) {
        guard !isPreview, id != backend.cameraID else { return }
        backend.selectCamera(id)
        previewLayer = nil
        lastFeed = -.infinity
        hold = ForkGlanceFraming.Hold()
        framingReady = false
    }

    private func ensureCamera() {
        guard !began else { return }
        guard backend.beginCalibration() else {
            problem = .cameraUnavailable
            return
        }
        began = true
        problem = nil
        backend.calibrationFeed = { [weak self] sample, observation in
            self?.receive(sample, observation)
        }
    }

    /// « Réessayer » after the camera would not start.
    func retryCamera() {
        guard !isPreview else { return }
        problem = nil
        ensureCamera()
    }

    private func receive(_ sample: ForkGlanceSample, _ observation: ForkGlanceObservation?) {
        precondition(Thread.isMainThread)
        guard !closed else { return }
        let now = clock.now
        if previewLayer == nil || now - lastFeed > Self.previewRefresh {
            previewLayer = backend.makePreviewLayer()
        }
        lastFeed = now
        if !receiving { receiving = true }
        if step == .framing {
            self.observation = observation
            updateFraming(observation, sample: sample, now: now)
        }
        guard var current = run, !current.isFinished else { return }
        current.add(sample, now: now)
        run = current
    }

    private func updateFraming(_ observation: ForkGlanceObservation?, sample: ForkGlanceSample?, now: TimeInterval) {
        let check = ForkGlanceFraming.check(observation, sample: sample)
        if check != framing { framing = check }
        hold.update(check.allGood, now: now)
        let ready = hold.isReady(now: now)
        if ready != framingReady { framingReady = ready }
    }

    /// The gauges go red when the feed stops, and « Suivant » waits out its second.
    private func startFramingTimer() {
        guard framingTimer == nil else { return }
        framingTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = self.clock.now
            if now - self.lastFeed > ForkGlanceFraming.stale {
                self.observation = nil
                if self.receiving { self.receiving = false }
                self.updateFraming(nil, sample: nil, now: now)
            } else {
                self.updateFraming(self.observation, sample: nil, now: now)
            }
        }
    }

    private func stopFramingTimer() {
        framingTimer?.invalidate()
        framingTimer = nil
    }

    // MARK: Layout

    func setMode(_ new: ForkGlanceMode) {
        guard new != mode else { return }
        mode = new
        planTargets = ForkGlanceCalibrationPlan.targets(layout: layout, mode: mode, splits: splits)
    }

    func setSplit(_ split: ForkGlanceSplit, display uuid: String) {
        guard splits[uuid] != split else { return }
        splits[uuid] = split
        planTargets = ForkGlanceCalibrationPlan.targets(layout: layout, mode: mode, splits: splits)
    }

    // MARK: Runs

    /// « Commencer » on the points step: the calibration, or the quick recenter.
    func startPoints() {
        start(entry == .quickRecenter ? .quick : .points)
    }

    func startValidation() {
        accuracy = nil
        seed = UInt64.random(in: 0...UInt64.max)
        start(.validation)
    }

    /// « Refaire les points faibles »: the points near the zones under 85 %,
    /// then the fit and the validation again. After « Tester » alone the
    /// first points are gone: the assistant opens on « Recalibrer » instead.
    func redoWeakPoints() {
        guard let accuracy else { return }
        guard !collected.isEmpty else {
            reopen(.recalibrate)
            return
        }
        guard !ForkGlanceValidation.weakZones(accuracy, zones: zones).isEmpty else { return }
        lastAccuracy = accuracy
        self.accuracy = nil
        start(.weakPoints)
    }

    private func targets(for kind: RunKind) -> [ForkGlanceCalibrationTarget] {
        switch kind {
        case .points:
            return planTargets
        case .weakPoints:
            let weak = ForkGlanceValidation.weakZones(lastAccuracy, zones: zones)
            return ForkGlanceCalibrationPlan.targets(planTargets, near: weak)
        case .quick:
            return ForkGlanceCalibrationPlan.quickTargets(zones: zones)
        case .validation:
            return ForkGlanceValidation.trials(zones: zones, seed: seed)
        }
    }

    /// The validation's last score, kept for « Refaire les points faibles ».
    private var lastAccuracy: [String: Double] = [:]

    private func start(_ kind: RunKind) {
        precondition(Thread.isMainThread)
        guard !isPreview, !isRunning, !fitting else { return }
        ensureCamera()
        guard began else { return }
        let targets = targets(for: kind)
        guard !targets.isEmpty else { return }
        problem = nil
        askingCancel = false
        runKind = kind
        run = ForkGlanceCalibrationRun(targets: targets, checksQuality: kind != .validation, now: clock.now)
        if kind != .validation { backend.calibrationProgressed(done: 0, total: targets.count) }
        if desk == nil { desk = layout }
        let overlay = self.overlay ?? ForkGlanceCalibrationOverlay()
        self.overlay = overlay
        overlay.show(session: self)
        schedule()
    }

    private func schedule() {
        timer?.invalidate()
        timer = nil
        guard let deadline = run?.nextDeadline else { return }
        let delay = max(0, deadline - clock.now)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard var current = run else { return }
        let events = current.advance(now: clock.now)
        run = current
        for event in events {
            switch event {
            case .pointDone(_, let done):
                if runKind != .validation { backend.calibrationProgressed(done: done, total: current.targets.count) }
            case .retry:
                break
            case .finished:
                finishRun(current)
                return
            }
        }
        schedule()
    }

    /// Space.
    func togglePause() {
        guard var current = run, !current.isFinished else { return }
        if askingCancel {
            askingCancel = false
            current.resume(now: clock.now)
        } else if current.isPaused {
            current.resume(now: clock.now)
        } else {
            current.pause(now: clock.now)
        }
        run = current
        schedule()
    }

    /// ⌫: the previous point again.
    func redoPrevious() {
        guard var current = run, !current.isFinished, !askingCancel else { return }
        current.back(now: clock.now)
        run = current
        schedule()
    }

    /// Esc: the run pauses and asks; a second Esc cancels.
    func escape() {
        guard var current = run, !current.isFinished else {
            cancel()
            return
        }
        if askingCancel {
            cancel()
            return
        }
        current.pause(now: clock.now)
        run = current
        askingCancel = true
        schedule()
    }

    /// « Continuer » in the confirmation.
    func keepGoing() {
        guard askingCancel else { return }
        togglePause()
    }

    private func finishRun(_ finished: ForkGlanceCalibrationRun) {
        timer?.invalidate()
        timer = nil
        overlay?.hide()
        let kind = runKind
        run = nil
        runKind = nil
        askingCancel = false
        switch kind {
        case .points?:
            collected = [:]
            for point in finished.points {
                collected[point.target.id] = ForkGlanceCalibrationPoint(target: point.target.point, samples: point.samples)
            }
            fit()
        case .weakPoints?:
            for target in finished.targets { collected[target.id] = nil }
            for point in finished.points {
                collected[point.target.id] = ForkGlanceCalibrationPoint(target: point.target.point, samples: point.samples)
            }
            fit()
        case .quick?:
            let points = finished.points.map { ForkGlanceCalibrationPoint(target: $0.target.point, samples: $0.samples) }
            backend.finishQuickRecenter(points: points)
            concluded = true
            close()
        case .validation?:
            let estimates = finished.targets.indices.map { index -> [CGPoint] in
                (finished.results[index] ?? []).compactMap { backend.estimate($0)?.point }
            }
            accuracy = ForkGlanceValidation.zoneAccuracy(trials: finished.targets, estimates: estimates, zones: zones)
        case nil:
            break
        }
    }

    private func fit() {
        let points = collected.keys.sorted().compactMap { collected[$0] }
        fitting = true
        backend.finishCalibration(points: points, splits: splits, mode: mode) { [weak self] result in
            guard let self, !self.closed else { return }
            self.fitting = false
            switch result {
            case .success(let calibration):
                self.calibration = calibration
                self.accuracy = nil
                if self.steps.contains(.validation) { self.go(to: .validation) }
            case .failure(let error):
                Self.logger.info("calibration fit failed: \(String(describing: error), privacy: .public)")
                if error as? ForkGlanceCalibrationError == .layoutChanged {
                    self.forgetDesk()
                    return
                }
                switch error as? ForkGlanceRegressionError {
                case .tooFewPoints?: self.problem = .fitTooFew
                case .degenerate?: self.problem = .fitDegenerate
                case nil: self.problem = .fitFailed
                }
            }
        }
    }

    /// « Recommencer » after a failed fit or a layout change: the points again.
    func startAgain() {
        problem = nil
        collected = [:]
        calibration = nil
        accuracy = nil
        if step != .points, steps.contains(.points) { go(to: .points) }
    }

    /// Something the assistant reads from the service changed. The service
    /// follows the displays (grouped per 0.5 s burst), the feature on or off.
    private func backendChanged() {
        objectWillChange.send()
        let now = layout
        guard now != lastLayout else { return }
        lastLayout = now
        guard let desk, !ForkGlanceServiceRules.sameDesk(desk, now) else { return }
        forgetDesk()
    }

    /// The displays the runs were planned on are gone (a display came, went
    /// or moved): a run under way stops, the points, the fit and the score of
    /// the old desk are forgotten, the splits follow the new displays, and
    /// « Recommencer » starts the points again. A fit under way comes back
    /// refused by the service (`ForkGlanceCalibrationError.layoutChanged`).
    private func forgetDesk() {
        Self.logger.info("calibration: the displays changed")
        desk = nil
        timer?.invalidate()
        timer = nil
        overlay?.hide()
        run = nil
        runKind = nil
        askingCancel = false
        collected = [:]
        calibration = nil
        accuracy = nil
        lastAccuracy = [:]
        let displays = Set(layout.displays.map(\.uuid))
        splits = ForkGlanceZones.defaultSplits(layout).merging(splits.filter { displays.contains($0.key) }) { _, kept in kept }
        planTargets = ForkGlanceCalibrationPlan.targets(layout: layout, mode: mode, splits: splits)
        problem = .layoutChanged
    }

    // MARK: The end

    /// « Terminer » under the validation's score.
    func finishValidation() {
        guard let accuracy else { return }
        backend.finishValidation(zoneAccuracy: accuracy)
        concluded = true
        if steps.contains(.done) {
            go(to: .done)
        } else {
            close()
        }
    }

    /// « Annuler », the window's close button, Esc twice, the feature off.
    func cancel() {
        close()
    }

    /// The window goes: whatever was started stops. Idempotent.
    func close() {
        precondition(Thread.isMainThread)
        guard !closed else { return }
        closed = true
        teardown()
        if began && !concluded { backend.cancelCalibration() }
        onClose?()
    }

    private func reopen(_ entry: ForkGlanceCalibrationEntry) {
        let reopen = onReopen
        close()
        reopen?(entry)
    }

    private func teardown() {
        timer?.invalidate()
        timer = nil
        stopFramingTimer()
        overlay?.hide()
        overlay = nil
        if began { backend.calibrationFeed = nil }
        backend.onChange = nil
        run = nil
        previewLayer = nil
    }

    // MARK: For the overlay

    /// What the overlay draws now; nil without a run.
    func overlayFrame(now: TimeInterval) -> ForkGlanceOverlayFrame? {
        guard let run, let target = run.current, let kind = runKind else { return nil }
        let zone = kind == .validation ? zones.first { $0.id == target.zoneID }?.rect : nil
        return ForkGlanceOverlayFrame(kind: kind == .validation ? .validation : .points, target: target, stage: run.stage,
                                      progress: run.progress(now: now), number: run.index + 1, total: run.targets.count,
                                      zoneRect: zone, isPaused: run.isPaused, isRetry: run.isRetry,
                                      askingCancel: askingCancel)
    }

    /// « Point 12 sur 29 » or « Zone 3 sur 6 » for the window while a run goes.
    var runLine: String? {
        guard let run, !run.isFinished else { return nil }
        return runKind == .validation ? text.validationLine(run.index + 1, of: run.targets.count)
            : text.progressLine(run.index + 1, of: run.targets.count)
    }

    /// A display's name in a hint (its short name, like the zones').
    func displayName(_ uuid: String) -> String {
        guard let display = layout.displays.first(where: { $0.uuid == uuid }) else { return uuid }
        return core.displayShortName(display, among: layout.displays)
    }

    func zoneName(_ zone: ForkGlanceZone) -> String {
        guard let display = layout.displays.first(where: { $0.uuid == zone.displayUUID }) else { return zone.id }
        return core.zoneName(zone.position, display: core.displayShortName(display, among: layout.displays))
    }

    func problemText(_ problem: Problem) -> String {
        switch problem {
        case .cameraUnavailable: return text.cameraFailed
        case .fitTooFew: return text.fitTooFew
        case .fitDegenerate: return text.fitDegenerate
        case .fitFailed: return text.fitFailed
        case .layoutChanged: return text.layoutChanged
        }
    }
}

#if VORSSAINT_DEVELOPMENT
// MARK: - Renders (Developer build only)

/// A backend that starts nothing: fixed displays, cameras and permission.
final class ForkGlancePreviewCalibrationBackend: ForkGlanceCalibrationBackend {
    var layout: ForkGlanceDisplayLayout
    var profile: ForkGlanceProfile?
    var mode: ForkGlanceMode = .zones
    var cameraDevices: [ForkGlanceCameraDevice]
    var cameraID: String?
    var cameraPermission: ForkGlanceCameraPermission
    var onChange: (() -> Void)?
    var calibrationFeed: ((ForkGlanceSample, ForkGlanceObservation?) -> Void)?

    init(layout: ForkGlanceDisplayLayout = ForkGlancePreviewCalibrationBackend.desk,
         permission: ForkGlanceCameraPermission = .granted) {
        self.layout = layout
        cameraPermission = permission
        cameraDevices = [ForkGlanceCameraDevice(id: "builtin", name: "FaceTime HD Camera", isBuiltIn: true, isContinuity: false)]
        cameraID = "builtin"
    }

    /// Annex A's desk: the LG 34" over the MacBook Pro 16".
    static let desk = ForkGlanceDisplayLayout(displays: [
        ForkGlanceDisplay(uuid: "LG", name: "LG HDR WQHD", frame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
                          millimeters: CGSize(width: 816, height: 338)),
        ForkGlanceDisplay(uuid: "BUILTIN", name: "Built-in Retina Display", frame: CGRect(x: 938, y: 1440, width: 1728, height: 1117),
                          millimeters: CGSize(width: 344, height: 222), isBuiltIn: true, hasNotch: true),
    ])

    func requestCameraPermission() {}
    func selectCamera(_ id: String?) {}
    func beginCalibration() -> Bool { false }
    func calibrationProgressed(done: Int, total: Int) {}
    func finishCalibration(points: [ForkGlanceCalibrationPoint], splits: [String: ForkGlanceSplit], mode: ForkGlanceMode,
                           completion: @escaping (Result<ForkGlanceCalibration, Error>) -> Void) {}
    func finishValidation(zoneAccuracy: [String: Double]) {}
    func finishQuickRecenter(points: [ForkGlanceCalibrationPoint]) {}
    func cancelCalibration() {}
    func estimate(_ sample: ForkGlanceSample) -> ForkGlanceEstimate? { nil }
    func makePreviewLayer() -> AVCaptureVideoPreviewLayer? { nil }
}

extension ForkGlanceCalibrationSession {
    /// Puts a preview session in a state, for the offscreen renders.
    func preview(step: ForkGlanceAssistantStep? = nil, observation: ForkGlanceObservation? = nil, ready: Bool = false,
                 receiving: Bool = true, fitting: Bool = false, problem: Problem? = nil,
                 accuracy: [String: Double]? = nil, run: ForkGlanceCalibrationRun? = nil, runKind: RunKind? = nil) {
        precondition(isPreview)
        if let step { self.step = step }
        self.observation = observation
        framing = ForkGlanceFraming.check(observation, sample: nil)
        framingReady = ready
        self.receiving = receiving
        self.fitting = fitting
        self.problem = problem
        self.accuracy = accuracy
        self.run = run
        self.runKind = runKind
    }
}
#endif
