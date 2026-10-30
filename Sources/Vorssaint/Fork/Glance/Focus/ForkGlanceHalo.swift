// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit

/// What tells the person a switch happened (plan §6.4), and the gaze dot of
/// the diagnostics. Both are drawn in their own borderless panels the mouse
/// goes through, above the windows on every Space (the pattern of
/// `ForkTrackpadGesturePreview`): never key, never in the window cycle.
///
/// - **Halo**: a 3 pt ring in the system accent, corners of 10 pt, around the
///   window that got the keyboard. In 120 ms, held 220 ms, out 380 ms;
///   with Reduce Motion, shown 300 ms with no fade.
/// - **Zone flash**: the whole zone lightened at 6 % for 250 ms.
/// - **Gaze dot**: a 14 pt disc at 35 % opacity following the estimate,
///   smoothed so it glides instead of jittering.
///
/// Main thread only. Geometry comes in global points (top left), as
/// everywhere in the feature.
final class ForkGlanceHalo {
    static let shared = ForkGlanceHalo()

    static let ringWidth: CGFloat = 3
    static let cornerRadius: CGFloat = 10
    static let fadeIn: TimeInterval = 0.12
    static let hold: TimeInterval = 0.22
    static let fadeOut: TimeInterval = 0.38
    static let reducedHold: TimeInterval = 0.3
    static let zoneFlashOpacity: CGFloat = 0.06
    static let zoneFlashDuration: TimeInterval = 0.25
    static let dotDiameter: CGFloat = 14
    static let dotOpacity: CGFloat = 0.35
    /// Share of the way to the new estimate the dot goes at each image.
    static let dotSmoothing: CGFloat = 0.45

    private var flashPanel: NSPanel?
    private var flashView: ForkGlanceHaloView?
    private var flashGeneration = 0
    private var dotPanel: NSPanel?
    private var dotPosition: CGPoint?

    private init() {}

    /// Rings a window's frame (`.halo`) or lights a zone (`.zoneFlash`);
    /// `.none` does nothing. A new flash replaces the one on screen.
    func flash(_ rect: CGRect, style: ForkGlanceFeedback) {
        precondition(Thread.isMainThread)
        guard style != .none, !rect.isNull, rect.width > 1, rect.height > 1,
              let mainHeight = Self.mainHeight else { return }
        flashGeneration &+= 1
        let generation = flashGeneration
        let outset = style == .halo ? Self.ringWidth : 0
        let frame = ForkGlanceZones.globalToCocoa(rect.insetBy(dx: -outset, dy: -outset), mainHeight: mainHeight)

        let panel = flashPanel ?? makePanel()
        flashPanel = panel
        let view = flashView ?? ForkGlanceHaloView()
        flashView = view
        view.style = style
        panel.contentView = view
        panel.setFrame(frame, display: false)
        view.needsDisplay = true

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion || style == .zoneFlash {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            let hold = style == .zoneFlash ? Self.zoneFlashDuration : Self.reducedHold
            DispatchQueue.main.asyncAfter(deadline: .now() + hold) { [weak self] in
                guard let self, self.flashGeneration == generation else { return }
                panel.orderOut(nil)
            }
            return
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fadeIn
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }, completionHandler: {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.hold) { [weak self] in
                guard let self, self.flashGeneration == generation else { return }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = Self.fadeOut
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    panel.animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    guard let self, self.flashGeneration == generation else { return }
                    panel.orderOut(nil)
                })
            }
        })
    }

    /// Moves the gaze dot toward `point`; nil hides it.
    func moveGazeDot(to point: CGPoint?) {
        precondition(Thread.isMainThread)
        guard let point, point.x.isFinite, point.y.isFinite, let mainHeight = Self.mainHeight else {
            dotPanel?.orderOut(nil)
            dotPosition = nil
            return
        }
        let smoothed: CGPoint
        if let previous = dotPosition {
            smoothed = CGPoint(x: previous.x + (point.x - previous.x) * Self.dotSmoothing,
                               y: previous.y + (point.y - previous.y) * Self.dotSmoothing)
        } else {
            smoothed = point
        }
        dotPosition = smoothed
        let side = Self.dotDiameter
        let rect = CGRect(x: smoothed.x - side / 2, y: smoothed.y - side / 2, width: side, height: side)
        let panel = dotPanel ?? makeDotPanel()
        dotPanel = panel
        panel.setFrame(ForkGlanceZones.globalToCocoa(rect, mainHeight: mainHeight), display: false)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    /// Everything off screen (the feature stopped).
    func hideAll() {
        precondition(Thread.isMainThread)
        flashGeneration &+= 1
        flashPanel?.orderOut(nil)
        moveGazeDot(to: nil)
    }

    // MARK: - Panels

    /// The height of the display at the origin, the line AppKit's and the
    /// global spaces share.
    private static var mainHeight: CGFloat? {
        NSScreen.screens.first?.frame.height
    }

    private func makePanel() -> NSPanel {
        let panel = OverlayPanel(contentRect: CGRect(x: 0, y: 0, width: 10, height: 10),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.animationBehavior = .none
        return panel
    }

    private func makeDotPanel() -> NSPanel {
        let panel = makePanel()
        let view = ForkGlanceHaloView()
        view.style = nil
        panel.contentView = view
        return panel
    }
}

/// The ring, the zone's light, or (style nil) the gaze dot.
private final class ForkGlanceHaloView: NSView {
    var style: ForkGlanceFeedback? = .halo {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    convenience init() {
        self.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        switch style {
        case .halo?:
            let width = ForkGlanceHalo.ringWidth
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: width / 2, dy: width / 2),
                                    xRadius: ForkGlanceHalo.cornerRadius, yRadius: ForkGlanceHalo.cornerRadius)
            ring.lineWidth = width
            // A soft glow under the ring, in the same accent.
            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = accent.withAlphaComponent(0.8)
            glow.shadowBlurRadius = 6
            glow.shadowOffset = .zero
            glow.set()
            accent.setStroke()
            ring.stroke()
            NSGraphicsContext.restoreGraphicsState()
        case .zoneFlash?:
            NSColor.white.withAlphaComponent(ForkGlanceHalo.zoneFlashOpacity).setFill()
            bounds.fill()
        case .none?:
            break
        case nil:
            accent.withAlphaComponent(ForkGlanceHalo.dotOpacity).setFill()
            NSBezierPath(ovalIn: bounds).fill()
        }
    }
}
