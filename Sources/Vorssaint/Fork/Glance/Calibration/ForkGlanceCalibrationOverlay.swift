// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The calibration's panels (plan §8.4, step 5): one per display, like
/// `CleaningModeManager.showOverlays` (`OverlayPanel`, the shielding level,
/// every Space), black at 85 % so the desktop still shows through. One of
/// them is key while a run goes, like `ScreenshotOverlayPanel`, for Space,
/// Esc and ⌫; it takes no other app's keyboard. Main thread.
final class ForkGlanceCalibrationOverlay {
    private var panels: [NSPanel] = []
    private var keyMonitor: Any?
    private var globalMonitor: Any?

    var isShown: Bool { !panels.isEmpty }

    func show(session: ForkGlanceCalibrationSession) {
        precondition(Thread.isMainThread)
        hide()
        // The global space has its origin at the top left of the main
        // display, AppKit's at its bottom left: the main display's height
        // is the line both share.
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        for display in session.layout.displays where !display.frame.isEmpty {
            let frame = ForkGlanceZones.globalToCocoa(display.frame, mainHeight: mainHeight)
            let panel = ForkGlanceOverlayPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                               backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.animationBehavior = .none
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let host = NSHostingView(rootView: ForkGlanceOverlayRoot(session: session, display: display))
            host.frame = NSRect(origin: .zero, size: frame.size)
            host.autoresizingMask = [.width, .height]
            panel.contentView = host
            panel.setFrame(frame, display: false)
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        let mouse = NSEvent.mouseLocation
        (panels.first { $0.frame.contains(mouse) } ?? panels.first)?.makeKey()
        installKeys(session: session)
    }

    func hide() {
        precondition(Thread.isMainThread)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        keyMonitor = nil
        globalMonitor = nil
        panels.forEach { $0.orderOut(nil) }
        panels = []
    }

    /// Space pauses, Esc cancels (asked first), ⌫ does the previous point
    /// again, Return answers the confirmation. Esc is also heard while
    /// another app is key (with Accessibility), like the screenshot tool.
    private func installKeys(session: ForkGlanceCalibrationSession) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak session] event in
            guard let self, let session, self.panels.contains(where: { $0 === event.window }) else { return event }
            switch Int(event.keyCode) {
            case kVK_Space:
                session.togglePause()
            case kVK_Escape:
                session.escape()
            case kVK_Delete:
                session.redoPrevious()
            case kVK_Return, kVK_ANSI_KeypadEnter:
                guard session.askingCancel else { return event }
                session.keepGoing()
            default:
                return event
            }
            return nil
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak session] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return }
            session?.escape()
        }
    }
}

/// Key without activating the app, and never listed by window managers.
private final class ForkGlanceOverlayPanel: OverlayPanel {
    override var canBecomeKey: Bool { true }
}

/// One display's panel, following the session.
struct ForkGlanceOverlayRoot: View {
    @ObservedObject var session: ForkGlanceCalibrationSession
    let display: ForkGlanceDisplay

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !session.isRunning)) { _ in
            ForkGlanceOverlayContent(display: display, frame: session.overlayFrame(now: session.clock.now),
                                     text: session.text, pausedTitle: session.core.statusPaused,
                                     keepGoing: { session.keepGoing() },
                                     cancel: { session.cancel() })
        }
    }
}

/// What one display shows: the dim, the lit zone, the dot with its caption,
/// the progress and the keys, the pause and the confirmation.
struct ForkGlanceOverlayContent: View {
    let display: ForkGlanceDisplay
    let frame: ForkGlanceOverlayFrame?
    let text: ForkGlanceCalibrationStrings
    /// « En pause » (the core strings).
    let pausedTitle: String
    var keepGoing: () -> Void = {}
    var cancel: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let captionWidth: CGFloat = 360

    /// The dot is on this display.
    private var holdsDot: Bool { frame?.target.displayUUID == display.uuid }

    /// The pause and the confirmation show on the dot's display.
    private var holdsDialog: Bool { holdsDot }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.85)
                if let frame, let zone = frame.zoneRect, zone.intersects(display.frame) {
                    let local = zone.intersection(display.frame).offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.28), lineWidth: 2))
                        .frame(width: max(0, local.width - 24), height: max(0, local.height - 24))
                        .position(x: local.midX, y: local.midY)
                }
                if let frame, holdsDot {
                    dot(frame, size: geometry.size)
                }
                topBar
                    .frame(width: geometry.size.width)
                    .padding(.top, display.hasNotch ? 40 : 18)
                if let frame, holdsDialog, frame.isPaused {
                    dialog(frame)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2
                            + (frame.target.point.y - display.frame.minY < geometry.size.height / 2 ? 160 : -160))
                }
            }
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }

    // MARK: Parts

    private func dot(_ frame: ForkGlanceOverlayFrame, size: CGSize) -> some View {
        let local = CGPoint(x: frame.target.point.x - display.frame.minX, y: frame.target.point.y - display.frame.minY)
        let look = ForkGlanceDotLook.at(frame.stage, progress: frame.progress, reduceMotion: reduceMotion)
        // The caption goes below the dot, above it in the lower half, and
        // slides sideways to stay on the display near its left or right edge.
        let below = local.y < size.height * 0.6
        let half = Self.captionWidth / 2 + 16
        let slide = max(0, half - local.x) + min(0, size.width - half - local.x)
        return ZStack {
            ForkGlanceTargetDot(look: look)
                .accessibilityLabel(text.dotLabel)
            Text(caption(frame))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(frame.isRetry ? 1 : 0.85))
                .multilineTextAlignment(.center)
                .frame(width: Self.captionWidth)
                .fixedSize(horizontal: false, vertical: true)
                .offset(x: slide, y: below ? 56 : -56)
                .opacity(frame.isPaused ? 0 : 1)
        }
        .position(clamped(local, in: size))
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: frame.target.id)
    }

    /// The caption stays on the display when the dot is near an edge.
    private func clamped(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), size.width), y: min(max(point.y, 0), size.height))
    }

    private func caption(_ frame: ForkGlanceOverlayFrame) -> String {
        if frame.isRetry { return text.again }
        if frame.kind == .validation { return text.lookAtZone }
        return frame.number <= 1 ? text.instruction : text.holdEyes
    }

    @ViewBuilder
    private var topBar: some View {
        if let frame {
            HStack(spacing: 18) {
                Text(frame.kind == .validation ? text.validationLine(frame.number, of: frame.total)
                                               : text.progressLine(frame.number, of: frame.total))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                Text(text.keySpace)
                Text(text.keyEscape)
                Text(text.keyDelete)
            }
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .frame(maxWidth: .infinity)
        }
    }

    private func dialog(_ frame: ForkGlanceOverlayFrame) -> some View {
        VStack(spacing: 10) {
            Image(systemName: frame.askingCancel ? "xmark.circle" : "pause.circle")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.white.opacity(0.85))
            Text(frame.askingCancel ? text.cancelTitle : pausedTitle)
                .font(.title3.weight(.semibold))
            Text(frame.askingCancel ? text.cancelMessage : text.pausedHint)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            if frame.askingCancel {
                HStack(spacing: 10) {
                    Button(text.keepGoing, action: keepGoing)
                        .keyboardShortcut(.defaultAction)
                    Button(text.cancelConfirm, role: .destructive, action: cancel)
                }
                .controlSize(.large)
                .padding(.top, 4)
            }
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(width: 380)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.1)))
    }
}
