// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

/// Glance Focus: the input watch's rules (plan §7.4, §7.6), pure so the
/// tests read them; `Engine/ForkGlanceInputWatch` reads the event state and
/// the window list, and asks these.
enum ForkGlanceInputRules {
    /// `CGEventField.eventSourceUserData` of the panes' fallback click,
    /// "Swis" + G (`Focus/ForkGlancePanes`): a click carrying it is never the
    /// person's.
    static let syntheticClickMarker: Int64 = 0x5377_6973_0047_0001

    /// A pointer event at `time` lies in the window Glance moved the pointer
    /// in (`from` a hair before the warp, `until` its end). Nothing is
    /// Glance's before any warp (`until` not past `from`).
    static func isGlancePointer(at time: TimeInterval, from start: TimeInterval, until end: TimeInterval) -> Bool {
        end > start && time >= start && time <= end
    }

    /// A click the person made, not one a program posted. The window server
    /// stamps a posted event with its poster's process id (`OwnKeyEvent`),
    /// and every synthetic event of this app carries a user-data marker
    /// (the panes' fallback click among them): a hardware click has neither.
    static func isRealClick(sourcePID: Int64, userData: Int64, ownPID: Int64) -> Bool {
        sourcePID != ownPID && userData == 0
    }
}

/// Which on-screen windows mean a menu, Mission Control or App Exposé, or
/// a screenshot selection (plan §7.4). Pure over the window list's
/// dictionaries (`CGWindowListCopyWindowInfo`).
enum ForkGlanceMenuWindows {
    enum Hit: Equatable {
        /// A menu of another app: menu bar, context or pop-up menus all sit
        /// at `kCGPopUpMenuWindowLevel` (`CGWindowLevel.h`: 101).
        case menu
        /// Mission Control or App Exposé, read like
        /// `NotchFrameProbe.overviewIsVisible(on:)` (private to
        /// `NotchWindowHost.swift`, hence restated): Dock's overview window at
        /// layer 18 before macOS 27, WindowManager's display-wide one at layer
        /// 19 since (Show Desktop's layer 18 and Stage Manager's strip stay out).
        case overview
        /// The system's screenshot selection (⌘⇧4, ⌘⇧5): screencaptureui
        /// covering a display.
        case screenshot
    }

    static let menuLayer = Int(kCGPopUpMenuWindowLevel)
    static let screenshotBundleID = "com.apple.screencaptureui"

    /// The first window that holds the guard, nil when none. This app's own
    /// windows never count (its menus come from `NSMenu` notifications; its
    /// tooltips and drag ghosts sit at the menu layer too). `bundleID` is
    /// asked only for a window covering a display above layer 0.
    static func hit(in windows: [[String: Any]], ownPID: pid_t, displaySizes: [CGSize],
                    bundleID: (pid_t) -> String) -> Hit? {
        for window in windows {
            guard let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != ownPID else {
                continue
            }
            if let alpha = window[kCGWindowAlpha as String] as? Double, alpha <= 0 { continue }
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            let owner = window[kCGWindowOwnerName as String] as? String
            let size = bounds(of: window).size
            guard size.width >= 2, size.height >= 2 else { continue }
            if layer == menuLayer { return .menu }
            // Unlike the official probe, Dock's window must cover a display
            // too: here it decides on its own, there it only starts a probe.
            let coversDisplay = displaySizes.contains {
                size.width >= $0.width - 1 && size.height >= $0.height - 1
            }
            guard coversDisplay else { continue }
            if owner == "Dock", layer == 18 { return .overview }
            if owner == "WindowManager", layer == 19 { return .overview }
            if layer > 0, bundleID(pid) == screenshotBundleID { return .screenshot }
        }
        return nil
    }

    static func bounds(of window: [String: Any]) -> CGRect {
        guard let dictionary = window[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: dictionary) else { return .zero }
        return rect
    }
}
