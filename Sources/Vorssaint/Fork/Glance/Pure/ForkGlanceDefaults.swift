// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Glance Focus's preference keys (plan §14, with Martial's decisions of
/// 23/10). Registered ones follow the person (settings backup): Bool, Int or
/// String only. Machine state is never registered, so it never leaves this
/// Mac; the splits and the calibration live in `profiles.json` (plan §8.6).
extension ForkDefaultsKey {
    static let glanceEnabled = "fork.glance.enabled"
    /// `ForkGlanceMode`.
    static let glanceMode = "fork.glance.mode"
    static let glanceSensitivityStep = "fork.glance.sensitivityStep"
    static let glanceDwellStep = "fork.glance.dwellStep"
    static let glanceDwellScreensStep = "fork.glance.dwellScreensStep"
    static let glanceTypingPauseStep = "fork.glance.typingPauseStep"
    static let glancePointerPauseStep = "fork.glance.pointerPauseStep"
    /// Bring the window to the front (on), or focus it where it is.
    static let glanceRaise = "fork.glance.raise"
    /// `ForkGlancePointerBehavior`.
    static let glancePointer = "fork.glance.pointer"
    /// `ForkGlanceFeedback`.
    static let glanceFeedback = "fork.glance.feedback"
    static let glanceLearnFromClicks = "fork.glance.learnFromClicks"
    /// Panes in terminals and editors (experimental, plan §5.4).
    static let glancePanes = "fork.glance.panes"
    static let glancePanesClickFallback = "fork.glance.panesClickFallback"
    /// JSON array of bundle ids.
    static let glancePanesApps = "fork.glance.panesApps"
    static let glanceNeverLeaveApps = "fork.glance.neverLeaveApps"
    static let glanceNeverFocusApps = "fork.glance.neverFocusApps"
    /// `ForkGlanceEnergy`.
    static let glanceEnergy = "fork.glance.energy"
    /// `ForkGlanceBatteryPolicy`.
    static let glanceOnBattery = "fork.glance.onBattery"
    static let glancePauseInLowPower = "fork.glance.pauseInLowPower"
    static let glanceIdleOffStep = "fork.glance.idleOffStep"
    /// `ForkGlanceCallPolicy`.
    static let glanceDuringCalls = "fork.glance.duringCalls"
    /// Global shortcuts, in the official recorder's format; empty: none.
    static let glanceHotKeyPause = "fork.glance.hotkey.pause"
    static let glanceHotKeyRecenter = "fork.glance.hotkey.recenter"
    static let glanceHotKeyMode = "fork.glance.hotkey.mode"
    /// `ForkGlanceIslandClosed`.
    static let glanceIslandClosed = "fork.glance.island.closed"
    static let glanceIslandLiveDot = "fork.glance.island.liveDot"
    static let glanceIslandHistory = "fork.glance.island.history"
    /// The gaze dot drawn over every screen (diagnostics).
    static let glanceGazeDot = "fork.glance.gazeDot"

    /// `fork.glance.notice.<kind>`: whether the island shows that notice, a Bool.
    static func glanceNotice(_ kind: ForkGlanceNoticeKind) -> String {
        "fork.glance.notice.\(kind.rawValue)"
    }

    // MARK: Machine state (never registered, never exported)

    /// `AVCaptureDevice.uniqueID` of the chosen camera; empty: the built-in one.
    static let glanceCameraID = "fork.glance.cameraID"
    /// The end of a timed user pause, ISO 8601; empty: none; « forever »: until resumed.
    static let glancePausedUntil = "fork.glance.pausedUntil"
    /// The layout signature last seen, to tell a new layout at launch.
    static let glanceLastLayoutSignature = "fork.glance.lastLayoutSignature"
}

enum ForkGlanceDefaults {
    /// The apps where panes are tried (plan §5.4).
    static let defaultPanesApps: [String] = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty", "com.github.wez.wezterm", "com.microsoft.VSCode", "com.todesktop.230313mxl2d9e9y",
        "com.exafunction.windsurf", "dev.zed.Zed", "com.apple.dt.Xcode", "com.jetbrains.",
    ]

    /// Every setting that follows the person, with its default. Merged into
    /// `ForkDefaults.registered`.
    static let registered: [String: Any] = {
        var values: [String: Any] = [
            ForkDefaultsKey.glanceEnabled: false,
            ForkDefaultsKey.glanceMode: ForkGlanceMode.fallback.rawValue,
            ForkDefaultsKey.glanceRaise: true,
            ForkDefaultsKey.glancePointer: ForkGlancePointerBehavior.fallback.rawValue,
            ForkDefaultsKey.glanceFeedback: ForkGlanceFeedback.fallback.rawValue,
            ForkDefaultsKey.glanceLearnFromClicks: true,
            ForkDefaultsKey.glancePanes: false,
            ForkDefaultsKey.glancePanesClickFallback: false,
            ForkDefaultsKey.glancePanesApps: encode(defaultPanesApps),
            ForkDefaultsKey.glanceNeverLeaveApps: "[]",
            ForkDefaultsKey.glanceNeverFocusApps: "[]",
            ForkDefaultsKey.glanceEnergy: ForkGlanceEnergy.fallback.rawValue,
            ForkDefaultsKey.glanceOnBattery: ForkGlanceBatteryPolicy.fallback.rawValue,
            ForkDefaultsKey.glancePauseInLowPower: true,
            ForkDefaultsKey.glanceDuringCalls: ForkGlanceCallPolicy.fallback.rawValue,
            ForkDefaultsKey.glanceHotKeyPause: "",
            ForkDefaultsKey.glanceHotKeyRecenter: "",
            ForkDefaultsKey.glanceHotKeyMode: "",
            ForkDefaultsKey.glanceIslandClosed: ForkGlanceIslandClosed.fallback.rawValue,
            ForkDefaultsKey.glanceIslandLiveDot: false,
            ForkDefaultsKey.glanceIslandHistory: true,
            ForkDefaultsKey.glanceGazeDot: false,
        ]
        for tuning in ForkGlanceTuning.allCases {
            values[tuning.key] = tuning.defaultStep
        }
        for kind in ForkGlanceNoticeKind.allCases {
            values[ForkDefaultsKey.glanceNotice(kind)] = kind.defaultOn
        }
        return values
    }()

    /// Machine state: never registered, never in the settings backup.
    static let machineKeys: [String] = [
        ForkDefaultsKey.glanceCameraID, ForkDefaultsKey.glancePausedUntil, ForkDefaultsKey.glanceLastLayoutSignature,
    ]

    /// A JSON array of strings, as the app lists are stored.
    static func encode(_ list: [String]) -> String {
        guard let data = try? JSONEncoder().encode(list), let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }

    /// A stored app list; anything unreadable is an empty list.
    static func decode(_ text: String?) -> [String] {
        guard let data = text?.data(using: .utf8),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return list
    }
}

extension ForkGlanceSettings {
    /// The person's settings, resolved: steps to values, the pointer and the
    /// dwell for the mode, unknown raw values to their fallback.
    static func read(_ defaults: UserDefaults = .standard) -> ForkGlanceSettings {
        let mode = defaults.string(forKey: ForkDefaultsKey.glanceMode).flatMap(ForkGlanceMode.init) ?? .fallback
        let pointer = defaults.string(forKey: ForkDefaultsKey.glancePointer)
            .flatMap(ForkGlancePointerBehavior.init) ?? .fallback
        let idle = ForkGlanceTuning.idleOff.value(in: defaults)
        return ForkGlanceSettings(
            enabled: defaults.bool(forKey: ForkDefaultsKey.glanceEnabled),
            mode: mode,
            sensitivity: ForkGlanceTuning.sensitivity.value(in: defaults),
            dwell: (mode == .screens ? ForkGlanceTuning.dwellScreens : .dwell).value(in: defaults),
            typingPause: ForkGlanceTuning.typingPause.value(in: defaults),
            pointerPause: ForkGlanceTuning.pointerPause.value(in: defaults),
            raise: defaults.object(forKey: ForkDefaultsKey.glanceRaise) as? Bool ?? true,
            pointer: pointer.resolved(for: mode),
            feedback: defaults.string(forKey: ForkDefaultsKey.glanceFeedback).flatMap(ForkGlanceFeedback.init) ?? .fallback,
            learnFromClicks: defaults.object(forKey: ForkDefaultsKey.glanceLearnFromClicks) as? Bool ?? true,
            panes: defaults.bool(forKey: ForkDefaultsKey.glancePanes),
            panesClickFallback: defaults.bool(forKey: ForkDefaultsKey.glancePanesClickFallback),
            panesApps: defaults.string(forKey: ForkDefaultsKey.glancePanesApps)
                .map(ForkGlanceDefaults.decode) ?? ForkGlanceDefaults.defaultPanesApps,
            neverLeaveApps: Set(ForkGlanceDefaults.decode(defaults.string(forKey: ForkDefaultsKey.glanceNeverLeaveApps))),
            neverFocusApps: Set(ForkGlanceDefaults.decode(defaults.string(forKey: ForkDefaultsKey.glanceNeverFocusApps))),
            energy: defaults.string(forKey: ForkDefaultsKey.glanceEnergy).flatMap(ForkGlanceEnergy.init) ?? .fallback,
            onBattery: defaults.string(forKey: ForkDefaultsKey.glanceOnBattery)
                .flatMap(ForkGlanceBatteryPolicy.init) ?? .fallback,
            pauseInLowPower: defaults.object(forKey: ForkDefaultsKey.glancePauseInLowPower) as? Bool ?? true,
            idleOff: idle.isFinite ? idle : nil,
            duringCalls: defaults.string(forKey: ForkDefaultsKey.glanceDuringCalls)
                .flatMap(ForkGlanceCallPolicy.init) ?? .fallback,
            islandClosed: defaults.string(forKey: ForkDefaultsKey.glanceIslandClosed)
                .flatMap(ForkGlanceIslandClosed.init) ?? .fallback,
            gazeDot: defaults.bool(forKey: ForkDefaultsKey.glanceGazeDot)
        )
    }

    /// Whether a bundle id is in a list where an entry ending with "." is a prefix.
    static func list(_ list: [String], contains bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return list.contains { $0.hasSuffix(".") ? bundleID.hasPrefix($0) : bundleID == $0 }
    }
}
