// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import ApplicationServices
import AVFoundation
import Combine
import CoreGraphics
import Foundation
import IOKit
import IOKit.ps
import notify
import os

/// The Mac's state the pauses answer (plan §7.5), all from notifications,
/// none polled:
///
/// - **Lock, sleep, wake, displays**: `ForkMeetingSystemEvents` (its own
///   instance), which already gathers them, the lock read from the session
///   at start, the display changes grouped per 0.5 s burst.
/// - **Displays asleep**: `NSWorkspace.screensDidSleep` / `…DidWake`.
/// - **Session switched away**: `SessionActivity.shared`.
/// - **Power source**: `IOPSGetProvidingPowerSourceType`, re-read on
///   `kIOPSNotifyPowerSource`. **Low Power Mode** and **thermal state**:
///   `ProcessInfo`, re-read on their notifications.
/// - **Lid**: `BrightnessService.lidClosed()` (`AppleClamshellState`),
///   re-read on the root domain's general interest (clamshell changes
///   included, like `BrightnessService`'s own observer), on display changes
///   and on wake.
/// - **Accessibility**: `AXIsProcessTrusted()` at each snapshot, a change
///   said when `Permissions` publishes one.
///
/// The camera's fields are the service's, which knows the chosen camera:
/// `snapshot()` gives them at their safe values (`cameraPresent` false, the
/// others false) except `cameraPermission`, a free status read. The service
/// derives `lidClosedOnBuiltInCamera` from `lidClosed`.
///
/// Main thread only. `onChange` comes once per burst, and only when the
/// snapshot really changed. `stop()` removes every observer.
final class ForkGlancePowerWatch: ForkGlanceSystemSource {
    static let shared = ForkGlancePowerWatch()

    /// Main thread, grouped: one call per burst of changes.
    var onChange: (() -> Void)?

    /// The built-in display's lid is closed (`AppleClamshellState`); false
    /// on a Mac without one.
    var lidClosed: Bool {
        precondition(Thread.isMainThread)
        return isRunning ? lid : Self.readLidClosed()
    }

    private let log = Logger(subsystem: "fork.glance", category: "power")
    private lazy var events = ForkMeetingSystemEvents { [weak self] event in self?.received(event) }

    // Main thread state.
    private(set) var isRunning = false
    private var locked = false
    private var asleep = false
    private var screensAsleep = false
    private var onBattery = false
    private var lowPower = false
    private var thermal = ForkGlanceThermal.nominal
    private var displayCount = 1
    private var lid = false

    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var powerToken: Int32?
    private var rootPort: IONotificationPortRef?
    private var rootNotification: io_object_t = 0
    private var accessibility: AnyCancellable?
    /// `SessionActivity` keeps its handlers for good: hooked once, gated by
    /// `isRunning`.
    private var sessionHooked = false
    private var flushPending = false
    private var delivered: ForkGlanceSystemSnapshot?

    private init() {}

    // MARK: - Lifecycle

    /// Main thread. Reads everything once, then follows the changes. Idempotent.
    func start() {
        precondition(Thread.isMainThread)
        guard !isRunning else { return }
        isRunning = true
        delivered = nil
        readAll()
        events.start()

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification, queue: .main) { $0.set(\.screensAsleep, true) }
        observe(workspace, NSWorkspace.screensDidWakeNotification, queue: .main) { $0.set(\.screensAsleep, false) }
        // Posted on any thread.
        observe(.default, Notification.Name.NSProcessInfoPowerStateDidChange, queue: nil) {
            $0.set(\.lowPower, ProcessInfo.processInfo.isLowPowerModeEnabled)
        }
        observe(.default, ProcessInfo.thermalStateDidChangeNotification, queue: nil) {
            $0.set(\.thermal, Self.thermal(ProcessInfo.processInfo.thermalState))
        }

        var token: Int32 = 0
        if notify_register_dispatch(kIOPSNotifyPowerSource, &token, .main, { [weak self] _ in
            self?.set(\.onBattery, Self.readOnBattery())
        }) == UInt32(NOTIFY_STATUS_OK) {
            powerToken = token
        }
        watchRootDomain()

        if !sessionHooked {
            sessionHooked = true
            SessionActivity.shared.onChange { [weak self] _ in self?.changed() }
        }
        accessibility = Permissions.shared.$accessibility.dropFirst().removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.changed() }
        log.debug("power watch started")
    }

    /// Main thread. Removes every observer, notification and port.
    func stop() {
        precondition(Thread.isMainThread)
        guard isRunning else { return }
        isRunning = false
        events.stop()
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        if let powerToken { notify_cancel(powerToken) }
        powerToken = nil
        if rootNotification != 0 { IOObjectRelease(rootNotification) }
        rootNotification = 0
        if let rootPort { IONotificationPortDestroy(rootPort) }
        rootPort = nil
        accessibility = nil
        delivered = nil
        log.debug("power watch stopped")
    }

    // MARK: - Snapshot

    /// Main thread. Live reads when the watch is not running.
    func snapshot() -> ForkGlanceSystemSnapshot {
        precondition(Thread.isMainThread)
        if !isRunning { readAll() }
        return ForkGlanceSystemSnapshot(
            locked: locked,
            asleep: asleep,
            screensAsleep: screensAsleep,
            sessionInactive: !SessionActivity.shared.isActive,
            onBattery: onBattery,
            lowPower: lowPower,
            thermal: thermal,
            officialPreviewOpen: false,
            cameraInUseElsewhere: false,
            lidClosedOnBuiltInCamera: false,
            displayCount: displayCount,
            cameraPermission: Self.cameraPermission(),
            accessibility: AXIsProcessTrusted(),
            cameraPresent: false)
    }

    // MARK: - Reading

    private func readAll() {
        locked = ForkMeetingSystemEvents.screenIsLockedNow()
        screensAsleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
        onBattery = Self.readOnBattery()
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        thermal = Self.thermal(ProcessInfo.processInfo.thermalState)
        displayCount = max(1, NSScreen.screens.count)
        lid = Self.readLidClosed()
    }

    static func readOnBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return false }
        return type == kIOPSBatteryPowerValue
    }

    static func readLidClosed() -> Bool {
        BrightnessService.lidClosed() ?? false
    }

    static func thermal(_ state: ProcessInfo.ThermalState) -> ForkGlanceThermal {
        switch state {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .critical
        }
    }

    /// A status read: never a request.
    static func cameraPermission() -> ForkGlanceCameraPermission {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    // MARK: - Changes

    private func received(_ event: ForkMeetingSystemEvents.Event) {
        switch event {
        case .willSleep:
            set(\.asleep, true)
        case .didWake:
            // Anything may have moved while asleep: the lid, the power, the displays.
            readAll()
            asleep = false
            changed()
        case .locked:
            set(\.locked, true)
        case .unlocked:
            set(\.locked, false)
        case .displaysChanged:
            displayCount = max(1, NSScreen.screens.count)
            lid = Self.readLidClosed()
            changed()
        case .diskLow, .diskEnough, .diskCritical, .willTerminate:
            break
        }
    }

    /// Any thread: lands on the main thread.
    private func set<Value: Equatable>(_ field: ReferenceWritableKeyPath<ForkGlancePowerWatch, Value>, _ value: Value) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.set(field, value) }
            return
        }
        guard isRunning, self[keyPath: field] != value else { return }
        self[keyPath: field] = value
        changed()
    }

    /// One `onChange` per burst, after the burst's notifications ran, and
    /// only for a snapshot that differs from the last one said.
    private func changed() {
        precondition(Thread.isMainThread)
        guard isRunning, !flushPending else { return }
        flushPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.flushPending = false
            guard self.isRunning else { return }
            let snapshot = self.snapshot()
            guard snapshot != self.delivered else { return }
            self.delivered = snapshot
            self.onChange?()
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, queue: OperationQueue?,
                         _ handler: @escaping (ForkGlancePowerWatch) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: queue) { [weak self] _ in
            guard let self else { return }
            handler(self)
        }
        observers.append((center, token))
    }

    /// The root power domain's general interest includes the clamshell's
    /// changes (as `BrightnessService` observes them). The callback carries
    /// the singleton, never released.
    private func watchRootDomain() {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return }
        defer { IOObjectRelease(root) }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        IONotificationPortSetDispatchQueue(port, .main)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = IOServiceAddInterestNotification(port, root, kIOGeneralInterest, { context, _, _, _ in
            guard let context else { return }
            let watch = Unmanaged<ForkGlancePowerWatch>.fromOpaque(context).takeUnretainedValue()
            // Read the property outside the callback.
            DispatchQueue.main.async { watch.set(\.lid, ForkGlancePowerWatch.readLidClosed()) }
        }, context, &rootNotification)
        guard result == KERN_SUCCESS else {
            IONotificationPortDestroy(port)
            log.error("lid observer not installed: \(result, privacy: .public)")
            return
        }
        rootPort = port
    }
}
