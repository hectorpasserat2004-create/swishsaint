// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import CoreGraphics
import os

/// Glance Focus: the displays as they are now (`ForkGlanceDisplayLayout`),
/// and a call when they change. Main thread: `NSScreen` belongs to it. Reading
/// a layout costs a few window server calls and one IORegistry property, no
/// disk.
enum ForkGlanceDisplays {
    /// Plugging a display, waking or closing the lid posts several changes
    /// in a row; one call follows the burst (like `ForkMeetingSystemEvents`).
    static let settle: TimeInterval = 0.5

    private static let log = Logger(subsystem: "fork.glance", category: "displays")

    /// Every display AppKit shows, the main one first. A display without a
    /// uuid (a virtual one being torn down) is left out: no profile could
    /// ever be bound to it.
    static func current() -> ForkGlanceDisplayLayout {
        precondition(Thread.isMainThread)
        let displays = NSScreen.screens.compactMap(display(for:))
        return ForkGlanceDisplayLayout(displays: displays, lidClosed: BrightnessService.lidClosed() ?? false)
    }

    private static func display(for screen: NSScreen) -> ForkGlanceDisplay? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let id = CGDirectDisplayID(number.uint32Value)
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
              let text = CFUUIDCreateString(nil, uuid) as String? else {
            log.debug("a display without a uuid is left out")
            return nil
        }
        let size = CGDisplayScreenSize(id)
        return ForkGlanceDisplay(
            uuid: text,
            name: screen.localizedName,
            // The window server's space (top left), not the screen's Cocoa frame.
            frame: CGDisplayBounds(id),
            millimeters: size.width > 0 && size.height > 0 ? size : nil,
            isBuiltIn: CGDisplayIsBuiltin(id) != 0,
            hasNotch: screen.safeAreaInsets.top > 0,
            rotation: CGDisplayRotation(id))
    }

    /// Calls `handler` on the main thread with the new layout, once per burst
    /// of `didChangeScreenParametersNotification`. Keep the token: dropping
    /// it, like `stopObserving`, ends the observation.
    static func observe(_ handler: @escaping (ForkGlanceDisplayLayout) -> Void) -> NSObjectProtocol {
        precondition(Thread.isMainThread)
        return Observation(handler)
    }

    static func stopObserving(_ token: NSObjectProtocol) {
        precondition(Thread.isMainThread)
        (token as? Observation)?.stop()
    }

    /// One observation: the notification's token and the burst's pending call.
    private final class Observation: NSObject {
        private var token: NSObjectProtocol?
        private var pending: DispatchWorkItem?
        private let handler: (ForkGlanceDisplayLayout) -> Void

        init(_ handler: @escaping (ForkGlanceDisplayLayout) -> Void) {
            self.handler = handler
            super.init()
            token = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.changed() }
        }

        deinit {
            pending?.cancel()
            if let token { NotificationCenter.default.removeObserver(token) }
        }

        private func changed() {
            guard token != nil else { return }
            pending?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.token != nil else { return }
                self.pending = nil
                self.handler(ForkGlanceDisplays.current())
            }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + ForkGlanceDisplays.settle, execute: work)
        }

        func stop() {
            pending?.cancel()
            pending = nil
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
        }
    }
}
