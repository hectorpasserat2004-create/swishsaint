// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import os

/// A camera Glance Focus may film with (`ForkGlanceCamera.devices()`).
struct ForkGlanceCameraDevice: Sendable, Equatable, Hashable, Identifiable {
    /// `AVCaptureDevice.uniqueID`, what a profile pins.
    let id: String
    /// `localizedName`: may carry a person's name (« Caméra de l'iPhone de … »),
    /// so it is shown, never logged.
    let name: String
    let isBuiltIn: Bool
    /// An iPhone through Continuity: listed, never chosen on its own (plan §8.6).
    let isContinuity: Bool
}

/// What the capture is doing, on the main thread.
enum ForkGlanceCameraState: Sendable, Equatable {
    case stopped
    /// The session is being built and started: the camera light comes on.
    case starting
    case running(deviceID: String)
    /// A runtime error or an interruption: the session is rebuilt in `retryIn`
    /// seconds (1, 3, 10, then 30), then given up as `.failed(.cameraFailed)`.
    case interrupted(retryIn: TimeInterval)
    /// `.cameraPermission` (never asked from here), `.noCamera`,
    /// `.cameraDisconnected` (back on its own when the camera is plugged in
    /// again) or `.cameraFailed`.
    case failed(ForkGlanceUnavailable)
}

/// Glance Focus's camera: its own `AVCaptureSession` with a video data output
/// (the official preview has none [V] `CameraPreviewService`), small 420v
/// images, a rate from 2 to 15 images per second, the cameras coming and
/// going, interruptions retried, and a stop that really frees the camera
/// (plan §10.1).
///
/// - **Threads** (plan §3.2): the public API is main-thread only. The session
///   is built, started, reconfigured and stopped on `sessionQueue` (all of it
///   blocks); images arrive on `captureQueue` (serial, `.userInitiated`),
///   where `frameHandler` runs Vision synchronously, so a late image is simply
///   dropped (`alwaysDiscardsLateVideoFrames`). Every start bumps a generation:
///   images, notifications and session results of an older one are dropped.
/// - **Format**: the smallest `activeFormat` of at least 640×480, the full
///   field preferred (`formatChoice`); otherwise `sessionPreset = .vga640x480`.
///   Pixels are asked as 420v (`kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange`),
///   two points of CPU less than BGRA [V] `ForkMeetingCaptureStream`.
/// - **Rate** (the plan §10.1 « À vérifier », settled): the device's frame
///   durations are hardware properties shared by every session on that
///   camera — the SDK says « On macOS, frame rate adjustments are supported
///   both at the AVCaptureDevice and at AVCaptureConnection, enabling
///   connections to output different frame rates » and « Holding the device
///   lock unnecessarily may degrade capture quality in other applications
///   sharing the device » (`AVCaptureSession.h`, `AVCaptureDevice.h`). So the
///   device is touched only while no other app uses it
///   (`!isInUseByAnotherApplication`): its format and rate are set at the
///   start, and given back to the format's default the moment another app
///   arrives, and at the stop, if they still are ours. Otherwise the rate is
///   kept by dropping images here (`Decimator`), which never changes what the
///   other app gets. Changes go up at once and down after 2 s (`setRate`).
/// - **Never Continuity on its own**: `start(deviceID: nil)` films with the
///   built-in camera (plan §8.6), and `AVCaptureDevice.userPreferredCamera`
///   is never written: that is the person's choice for every app [V]
///   (the official preview only writes it on an explicit pick).
final class ForkGlanceCamera: NSObject, @unchecked Sendable {
    static let shared = ForkGlanceCamera()

    /// Images per second `setRate` accepts. The plan's governor goes down to
    /// 2 in the Saver profile while typing (§10.2).
    static let rateRange: ClosedRange<Double> = 2...15
    /// The smallest image asked for, in pixels.
    static let minimumSize = CGSize(width: 640, height: 480)
    /// A rate goes down at most this often (it goes up at once).
    static let rateHysteresis: TimeInterval = 2
    /// The waits before each rebuild after an error or an interruption.
    static let retryDelays: [TimeInterval] = [1, 3, 10, 30]
    /// Running this long without trouble starts the retries over from 1 s.
    static let stableAfter: TimeInterval = 60
    /// A session that runs but gives no image for this long has failed (a
    /// suspended camera, a closed privacy shutter).
    static let firstFrameDeadline: TimeInterval = 3

    /// Each kept image and its capture time (`ProcessInfo.systemUptime`'s
    /// clock, the host clock [V]), on the capture queue. An image already
    /// being handled when `stop` is called may finish; none starts after it.
    var frameHandler: ((CVPixelBuffer, TimeInterval) -> Void)? {
        didSet {
            let handler = frameHandler
            shared.lock.withLock { shared.handler = handler }
        }
    }

    /// Main thread, on each change of `state`.
    var onState: ((ForkGlanceCameraState) -> Void)?
    /// Main thread: a camera was plugged in or unplugged (reload `devices()`).
    var onDevicesChanged: (() -> Void)?
    /// Main thread: another app started or stopped filming with the watched
    /// camera (`isInUseByAnotherApplication`, key-value observed).
    var onInUseElsewhereChanged: ((Bool) -> Void)?

    /// Main thread.
    private(set) var state: ForkGlanceCameraState = .stopped
    /// Main thread: another app films with the watched camera.
    private(set) var isInUseElsewhere = false

    /// Kept images per second over the last two seconds (diagnostics).
    var measuredRate: Double {
        let now = ProcessInfo.processInfo.systemUptime
        return shared.lock.withLock { shared.decimator.measuredRate(now: now) }
    }

    private static let logger = Logger(subsystem: "fork.glance", category: "camera")

    /// Serial: build, start, reconfigure and stop the session (all block).
    private let sessionQueue = DispatchQueue(label: "fork.glance.camera.session", qos: .userInitiated)
    /// Serial: the images, and Vision on them.
    private let captureQueue = DispatchQueue(label: "fork.glance.camera.capture", qos: .userInitiated)

    /// What the capture queue and the main thread share.
    fileprivate final class Shared: @unchecked Sendable {
        let lock = NSLock()
        /// The start allowed to deliver images; -1 when stopped.
        var generation = -1
        var handler: ((CVPixelBuffer, TimeInterval) -> Void)?
        var decimator = Decimator()
        /// Images received this generation, kept or not (the watchdog).
        var received = 0
    }

    private let shared = Shared()

    // Main thread state.
    private var generation = 0
    /// Between `start` and `stop`: the person wants the camera on.
    private var wanted = false
    /// What `start` was given: nil is the built-in camera.
    private var requestedID: String?
    /// The camera last opened, kept while a retry waits.
    private var openedID: String?
    private var box: SessionBox?
    private var sessionObservers: [NSObjectProtocol] = []
    private var retryWork: DispatchWorkItem?
    private var watchdog: DispatchWorkItem?
    private var retryAttempt = 0
    private var runningSince: TimeInterval?
    private var targetRate: Double = 12
    private var lastRateChange: TimeInterval = -.infinity
    private var pendingRate: DispatchWorkItem?
    /// The camera whose sharing is observed, by id: kept after `stop`, so a
    /// pause during a call knows when the other app lets go.
    private var watchedID: String?
    private var watchedDevice: AVCaptureDevice?
    private var sharingObservation: NSKeyValueObservation?
    private var deviceObservers: [NSObjectProtocol] = []

    private override init() {
        super.init()
    }

    // MARK: - Devices and permission

    /// The cameras, built-in first, then the external ones, then Continuity.
    static func devices() -> [ForkGlanceCameraDevice] {
        captureDevices().map(describe).sorted { lhs, rhs in
            let left = rank(lhs), right = rank(rhs)
            if left != right { return left < right }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// The camera to film with when none is chosen: the built-in one while
    /// the lid is open, else the first external camera that is not an iPhone.
    /// Never a Continuity camera (plan §8.6).
    static func defaultDeviceID(lidClosed: Bool) -> String? {
        let all = devices()
        if !lidClosed, let builtIn = all.first(where: \.isBuiltIn) { return builtIn.id }
        return all.first { !$0.isBuiltIn && !$0.isContinuity }?.id
    }

    static var permission: ForkGlanceCameraPermission {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    /// Shows the system prompt. Only from an explicit action of the person
    /// (the service and the assistant); `start` never asks.
    static func requestPermission(_ done: @escaping (Bool) -> Void) {
        precondition(Thread.isMainThread)
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                Permissions.shared.refresh()
                done(granted)
            }
        }
    }

    private static func captureDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                         mediaType: .video, position: .unspecified).devices
    }

    private static func describe(_ device: AVCaptureDevice) -> ForkGlanceCameraDevice {
        // The Info.plist opts in to `.continuityCamera`; `isContinuityCamera`
        // still catches an iPhone reported as a wide-angle camera.
        let continuity = device.deviceType == .continuityCamera || device.isContinuityCamera
        return ForkGlanceCameraDevice(id: device.uniqueID, name: device.localizedName,
                                      isBuiltIn: device.deviceType == .builtInWideAngleCamera && !continuity,
                                      isContinuity: continuity)
    }

    private static func rank(_ device: ForkGlanceCameraDevice) -> Int {
        device.isBuiltIn ? 0 : (device.isContinuity ? 2 : 1)
    }

    /// `id` when that camera is here; otherwise (nil, or gone) the default
    /// with the lid open.
    private static func resolve(_ id: String?) -> AVCaptureDevice? {
        let all = captureDevices()
        if let id, let chosen = all.first(where: { $0.uniqueID == id }) { return chosen }
        guard let fallback = defaultDeviceID(lidClosed: false) else { return nil }
        return all.first { $0.uniqueID == fallback }
    }

    // MARK: - Start and stop

    /// Films with `deviceID`; nil or unknown: the built-in camera (never a
    /// Continuity one). Restarts when already running. Never asks for the
    /// permission: without it the state is `.failed(.cameraPermission)`.
    func start(deviceID: String?) {
        precondition(Thread.isMainThread)
        wanted = true
        requestedID = deviceID
        retryAttempt = 0
        runningSince = nil
        guard Self.permission == .granted else {
            closeSession()
            setState(.failed(.cameraPermission))
            return
        }
        open()
    }

    /// Turns the camera off: the session stops and lets go of the device on
    /// its queue, then `completion` runs on the main thread, once the camera
    /// is free (its light goes off). The sharing of the camera stays
    /// observed (`stopWatching` ends that).
    func stop(completion: (() -> Void)? = nil) {
        precondition(Thread.isMainThread)
        wanted = false
        retryAttempt = 0
        runningSince = nil
        pendingRate?.cancel()
        pendingRate = nil
        let closing = detachSession()
        setState(.stopped)
        let asked = ProcessInfo.processInfo.systemUptime
        // Through the serial queue even without a session: a session closed
        // just before (a failure, a disconnect) is free once this runs.
        sessionQueue.async {
            closing?.close()
            DispatchQueue.main.async {
                if closing != nil {
                    let elapsed = ProcessInfo.processInfo.systemUptime - asked
                    Self.logger.info("camera off in \(elapsed, format: .fixed(precision: 3)) s")
                }
                completion?()
            }
        }
    }

    /// Observes whether another app films with `deviceID` (nil: the default
    /// camera) without filming: a pause for a call needs to know when the
    /// call lets go of the camera. `start` watches the camera it films with.
    func watch(deviceID: String?) {
        precondition(Thread.isMainThread)
        watchedID = deviceID ?? Self.defaultDeviceID(lidClosed: false)
        installDeviceObservers()
        rewatch()
    }

    /// Stops observing the camera's sharing and the cameras coming and going:
    /// for when the feature turns off, after `stop`.
    func stopWatching() {
        precondition(Thread.isMainThread)
        watchedID = nil
        rewatch()
        deviceObservers.forEach(NotificationCenter.default.removeObserver)
        deviceObservers = []
    }

    /// Images per second wanted, clamped to `rateRange`. Up at once; down at
    /// most every `rateHysteresis` seconds, the latest wish applied when that
    /// time comes.
    func setRate(_ fps: Double) {
        precondition(Thread.isMainThread)
        guard fps.isFinite else { return }
        let rate = min(max(fps, Self.rateRange.lowerBound), Self.rateRange.upperBound)
        pendingRate?.cancel()
        pendingRate = nil
        guard rate != targetRate else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let wait = lastRateChange + Self.rateHysteresis - now
        guard rate < targetRate, wait > 0 else {
            applyRate(rate)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            self?.pendingRate = nil
            self?.applyRate(rate)
        }
        pendingRate = work
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
    }

    /// A preview of the running session (framing, diagnostics); nil when
    /// stopped. It shows nothing once the session is rebuilt: make a new one
    /// on each `.running`.
    func makePreviewLayer() -> AVCaptureVideoPreviewLayer? {
        precondition(Thread.isMainThread)
        guard let session = box?.session else { return nil }
        return AVCaptureVideoPreviewLayer(session: session)
    }

    // MARK: - Session

    private func open() {
        closeSession()
        cancelRetry()
        guard let device = Self.resolve(requestedID) else {
            setState(.failed(.noCamera))
            return
        }
        generation &+= 1
        let generation = generation
        let rate = targetRate
        let box = SessionBox(device: device, sink: FrameSink(shared: shared, generation: generation))
        self.box = box
        openedID = device.uniqueID
        shared.lock.withLock {
            shared.generation = generation
            shared.received = 0
            shared.decimator = Decimator()
            shared.decimator.rate = rate
        }
        watchedID = device.uniqueID
        installDeviceObservers()
        rewatch()
        observe(box.session, generation: generation)
        setState(.starting)
        Self.logger.info("camera starting (\(Self.describe(device).isBuiltIn ? "built-in" : "external", privacy: .public))")
        let captureQueue = captureQueue
        sessionQueue.async { [weak self] in
            let running = box.start(rate: rate, captureQueue: captureQueue)
            DispatchQueue.main.async {
                self?.started(running, generation: generation)
            }
        }
    }

    private func started(_ running: Bool, generation: Int) {
        guard generation == self.generation, wanted, let box else { return }
        guard running else {
            failed(generation: generation, reason: "did not start")
            return
        }
        runningSince = ProcessInfo.processInfo.systemUptime
        setState(.running(deviceID: box.device.uniqueID))
        let watchdog = DispatchWorkItem { [weak self] in
            guard let self, self.generation == generation, self.wanted else { return }
            if self.shared.lock.withLock({ self.shared.received }) == 0 {
                self.failed(generation: generation, reason: "no image")
            }
        }
        self.watchdog = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.firstFrameDeadline, execute: watchdog)
    }

    /// An error, an interruption, a start that failed or no image: rebuild
    /// after the next delay, or give up.
    private func failed(generation: Int, reason: String) {
        guard generation == self.generation, wanted else { return }
        Self.logger.error("camera trouble: \(reason, privacy: .public)")
        closeSession()
        let now = ProcessInfo.processInfo.systemUptime
        if let since = runningSince, now - since >= Self.stableAfter { retryAttempt = 0 }
        runningSince = nil
        guard retryAttempt < Self.retryDelays.count else {
            setState(.failed(.cameraFailed))
            return
        }
        let delay = Self.retryDelays[retryAttempt]
        retryAttempt += 1
        setState(.interrupted(retryIn: delay))
        // `closeSession` moved the generation on: a start, stop or unplug
        // from here moves it again and drops this retry.
        let waiting = self.generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.wanted, self.generation == waiting else { return }
            self.retryWork = nil
            self.open()
        }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func observe(_ session: AVCaptureSession, generation: Int) {
        let center = NotificationCenter.default
        sessionObservers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
                                                   object: session, queue: .main) { [weak self] _ in
            self?.failed(generation: generation, reason: "runtime error")
        })
        sessionObservers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification,
                                                   object: session, queue: .main) { [weak self] _ in
            self?.failed(generation: generation, reason: "interrupted")
        })
    }

    /// Detaches the session and closes it on the session queue.
    private func closeSession() {
        guard let box = detachSession() else { return }
        sessionQueue.async { box.close() }
    }

    /// Detaches the session: no image, notification or result of it counts
    /// any more. The caller closes what it gets back.
    private func detachSession() -> SessionBox? {
        generation &+= 1
        cancelRetry()
        watchdog?.cancel()
        watchdog = nil
        sessionObservers.forEach(NotificationCenter.default.removeObserver)
        sessionObservers = []
        shared.lock.withLock {
            shared.generation = -1
            shared.decimator = Decimator()
        }
        guard let box else { return nil }
        self.box = nil
        return box
    }

    private func cancelRetry() {
        retryWork?.cancel()
        retryWork = nil
    }

    private func applyRate(_ rate: Double) {
        targetRate = rate
        lastRateChange = ProcessInfo.processInfo.systemUptime
        shared.lock.withLock { shared.decimator.rate = rate }
        guard let box else { return }
        sessionQueue.async { box.applyHardwareRate(rate) }
    }

    private func setState(_ new: ForkGlanceCameraState) {
        guard new != state else { return }
        state = new
        onState?(new)
    }

    // MARK: - Devices coming and going, sharing

    private func installDeviceObservers() {
        guard deviceObservers.isEmpty else { return }
        let center = NotificationCenter.default
        deviceObservers.append(center.addObserver(forName: .AVCaptureDeviceWasConnected, object: nil,
                                                  queue: .main) { [weak self] _ in
            self?.devicesChanged(disconnected: nil)
        })
        deviceObservers.append(center.addObserver(forName: .AVCaptureDeviceWasDisconnected, object: nil,
                                                  queue: .main) { [weak self] note in
            self?.devicesChanged(disconnected: (note.object as? AVCaptureDevice)?.uniqueID)
        })
    }

    private func devicesChanged(disconnected: String?) {
        if wanted {
            if let disconnected, disconnected == openedID, isFilmingOrRetrying {
                Self.logger.info("camera disconnected")
                closeSession()
                setState(.failed(.cameraDisconnected))
            } else if disconnected == nil, retryWork == nil, shouldReopenAfterPlug() {
                retryAttempt = 0
                open()
            }
        }
        rewatch()
        onDevicesChanged?()
    }

    private var isFilmingOrRetrying: Bool {
        switch state {
        case .starting, .running, .interrupted: return true
        case .stopped, .failed: return false
        }
    }

    /// A camera arrived: film again if the camera was missing, or move to the
    /// chosen camera when a stand-in films for it.
    private func shouldReopenAfterPlug() -> Bool {
        switch state {
        case .failed(.cameraDisconnected), .failed(.noCamera):
            return Self.resolve(requestedID) != nil
        case .running, .starting:
            guard let requestedID, requestedID != box?.device.uniqueID else { return false }
            return Self.captureDevices().contains { $0.uniqueID == requestedID }
        default:
            return false
        }
    }

    /// Follows the watched camera: a new device object after a replug.
    private func rewatch() {
        let device = watchedID.flatMap { id in Self.captureDevices().first { $0.uniqueID == id } }
        if device !== watchedDevice {
            sharingObservation?.invalidate()
            sharingObservation = nil
            watchedDevice = device
            sharingObservation = device?.observe(\.isInUseByAnotherApplication, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.sharingChanged() }
            }
        }
        sharingChanged()
    }

    private func sharingChanged() {
        let inUse = watchedDevice?.isInUseByAnotherApplication ?? false
        guard inUse != isInUseElsewhere else { return }
        isInUseElsewhere = inUse
        Self.logger.info("camera in use elsewhere: \(inUse, privacy: .public)")
        if let box, box.device === watchedDevice {
            let rate = targetRate
            sessionQueue.async { box.sharingChanged(inUse: inUse, rate: rate) }
        }
        onInUseElsewhereChanged?(inUse)
    }
}

// MARK: - Session queue

/// One session on one camera. Built on the main thread, then touched only on
/// the session queue (its `var`s too).
private final class SessionBox: @unchecked Sendable {
    let session = AVCaptureSession()
    let device: AVCaptureDevice
    let sink: FrameSink
    private let output = AVCaptureVideoDataOutput()
    /// The device's rate may be set: no other app filmed with it.
    private var mayTouchDevice = false
    /// The frame duration this session set on the device, to give it back.
    private var ourDuration: CMTime?

    init(device: AVCaptureDevice, sink: FrameSink) {
        self.device = device
        self.sink = sink
    }

    /// Builds and starts the session; true when it runs.
    func start(rate: Double, captureQueue: DispatchQueue) -> Bool {
        guard let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            return false
        }
        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        let yuv = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        if output.availableVideoPixelFormatTypes.contains(yuv) {
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: yuv]
        }
        output.setSampleBufferDelegate(sink, queue: captureQueue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return false
        }
        session.addOutput(output)
        sink.clock = session.synchronizationClock

        // Another app already films: its format and rate are left alone, the
        // preset asks for the least, and the rate is kept by dropping images.
        mayTouchDevice = !device.isInUseByAnotherApplication
        var locked = false
        if mayTouchDevice, let format = ForkGlanceCamera.formatChoice(device.formats),
           (try? device.lockForConfiguration()) != nil {
            locked = true
            device.activeFormat = format
            setDuration(for: rate)
        } else if session.canSetSessionPreset(.vga640x480) {
            session.sessionPreset = .vga640x480
        }
        session.commitConfiguration()
        // Locked through the start, so the session keeps the format it was given.
        session.startRunning()
        if locked { device.unlockForConfiguration() }
        return session.isRunning
    }

    /// Gives the device back and stops: once this returns the camera is free.
    func close() {
        restoreDevice()
        if session.isRunning { session.stopRunning() }
        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        session.commitConfiguration()
        output.setSampleBufferDelegate(nil, queue: nil)
    }

    func applyHardwareRate(_ rate: Double) {
        guard mayTouchDevice, !device.isInUseByAnotherApplication,
              (try? device.lockForConfiguration()) != nil else { return }
        setDuration(for: rate)
        device.unlockForConfiguration()
    }

    /// Another app arrived: give it the device's default rate if it still is
    /// ours. It left: the rate is ours to set again (the format stays).
    func sharingChanged(inUse: Bool, rate: Double) {
        if inUse {
            restoreDevice()
            mayTouchDevice = false
        } else {
            mayTouchDevice = true
            applyHardwareRate(rate)
        }
    }

    /// The device is locked. Min and max durations equal: a steady rate, the
    /// smallest the format offers at or above `rate`. Set in the order that
    /// keeps min ≤ max, since a value out of range throws.
    private func setDuration(for rate: Double) {
        if #available(macOS 15.0, *), device.isAutoVideoFrameRateEnabled { return }
        guard let duration = ForkGlanceCamera.frameDuration(atLeast: rate,
                                                            in: device.activeFormat.videoSupportedFrameRateRanges)
        else { return }
        if CMTimeCompare(duration, device.activeVideoMaxFrameDuration) > 0 {
            device.activeVideoMaxFrameDuration = duration
            device.activeVideoMinFrameDuration = duration
        } else {
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
        }
        ourDuration = duration
    }

    /// The format's default rate back, unless someone else changed it since.
    private func restoreDevice() {
        guard let ours = ourDuration else { return }
        ourDuration = nil
        guard device.activeVideoMinFrameDuration == ours, device.activeVideoMaxFrameDuration == ours,
              (try? device.lockForConfiguration()) != nil else { return }
        device.activeVideoMinFrameDuration = .invalid
        device.activeVideoMaxFrameDuration = .invalid
        device.unlockForConfiguration()
    }
}

extension ForkGlanceCamera {
    /// The smallest format of at least 640×480, among those with the full
    /// field (the largest format's aspect: a 4:3 cut of a 16:9 sensor loses
    /// the sides, and the field of view is not readable on macOS) when one
    /// is big enough; 420v first at equal size. Nil: none is big enough.
    fileprivate static func formatChoice(_ formats: [AVCaptureDevice.Format]) -> AVCaptureDevice.Format? {
        let sized = formats.compactMap { format -> (format: AVCaptureDevice.Format, width: Int, height: Int)? in
            guard CMFormatDescriptionGetMediaType(format.formatDescription) == kCMMediaType_Video else { return nil }
            let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return (format, Int(size.width), Int(size.height))
        }
        guard let largest = sized.max(by: { $0.width * $0.height < $1.width * $1.height }), largest.height > 0
        else { return nil }
        let fullAspect = Double(largest.width) / Double(largest.height)
        let big = sized.filter {
            $0.width >= Int(minimumSize.width) && $0.height >= Int(minimumSize.height) && !$0.format.videoSupportedFrameRateRanges.isEmpty
        }
        let full = big.filter { abs(Double($0.width) / Double($0.height) - fullAspect) < 0.02 }
        let yuv = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        return (full.isEmpty ? big : full).min { lhs, rhs in
            let left = lhs.width * lhs.height, right = rhs.width * rhs.height
            if left != right { return left < right }
            return CMFormatDescriptionGetMediaSubType(lhs.format.formatDescription) == yuv
                && CMFormatDescriptionGetMediaSubType(rhs.format.formatDescription) != yuv
        }?.format
    }

    /// The frame duration for the lowest rate a format offers at or above
    /// `rate` (whole images per second), or its fastest when all are below.
    /// Always inside one of `ranges`: a duration outside them throws.
    fileprivate static func frameDuration(atLeast rate: Double, in ranges: [AVFrameRateRange]) -> CMTime? {
        let wanted = max(1, rate.rounded(.up))
        let exact = CMTime(value: 1, timescale: CMTimeScale(wanted))
        var best: (rate: Double, duration: CMTime)?
        for range in ranges {
            let candidate: (rate: Double, duration: CMTime)
            if CMTimeCompare(exact, range.minFrameDuration) >= 0, CMTimeCompare(exact, range.maxFrameDuration) <= 0 {
                candidate = (wanted, exact)
            } else if range.minFrameRate >= wanted {
                candidate = (range.minFrameRate, range.maxFrameDuration)
            } else {
                candidate = (range.maxFrameRate, range.minFrameDuration)
            }
            guard let current = best else {
                best = candidate
                continue
            }
            let candidateFits = candidate.rate >= wanted, currentFits = current.rate >= wanted
            if candidateFits != currentFits {
                if candidateFits { best = candidate }
            } else if candidateFits ? candidate.rate < current.rate : candidate.rate > current.rate {
                best = candidate
            }
        }
        return best?.duration
    }
}

// MARK: - Capture queue

/// Keeps one image every `1 / rate` seconds on average, whatever the camera
/// sends, and counts the kept ones (`measuredRate`). Under `Shared.lock`.
fileprivate struct Decimator {
    var rate: Double = 12
    private var nextDue: TimeInterval?
    private var kept: [TimeInterval] = []

    /// Whether the image taken at `time` is kept.
    mutating func keep(_ time: TimeInterval) -> Bool {
        let interval = 1 / max(rate, 0.1)
        // A fifth of an interval of slack: an image a hair early is not
        // dropped for its jitter, which would halve a matching camera rate.
        if let due = nextDue, time < due - interval * 0.2 { return false }
        if let due = nextDue, time - due < interval {
            nextDue = due + interval
        } else {
            nextDue = time + interval
        }
        kept.append(time)
        if let first = kept.first, time - first > 2 { kept.removeAll { time - $0 > 2 } }
        return true
    }

    /// Kept images per second over the last two seconds; 0 when none came
    /// for a second.
    func measuredRate(now: TimeInterval) -> Double {
        guard kept.count >= 2, let first = kept.first, let last = kept.last, last - first >= 0.5,
              now - last < 1 else { return 0 }
        return Double(kept.count - 1) / (last - first)
    }
}

/// The delegate of one session's output.
private final class FrameSink: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let shared: ForkGlanceCamera.Shared
    private let generation: Int
    /// The session's clock, set before it starts (session queue), read on the
    /// capture queue afterwards.
    var clock: CMClock?

    init(shared: ForkGlanceCamera.Shared, generation: Int) {
        self.shared = shared
        self.generation = generation
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = hostTime(of: sampleBuffer)
        let handler = shared.lock.withLock { () -> ((CVPixelBuffer, TimeInterval) -> Void)? in
            guard shared.generation == generation else { return nil }
            shared.received += 1
            guard shared.decimator.keep(time) else { return nil }
            return shared.handler
        }
        handler?(pixels, time)
    }

    /// Seconds on the host clock, `ProcessInfo.systemUptime`'s.
    private func hostTime(of sampleBuffer: CMSampleBuffer) -> TimeInterval {
        let stamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard stamp.isValid else { return ProcessInfo.processInfo.systemUptime }
        let host = clock.map { CMSyncConvertTime(stamp, from: $0, to: CMClockGetHostTimeClock()) } ?? stamp
        return host.isValid ? host.seconds : ProcessInfo.processInfo.systemUptime
    }
}
