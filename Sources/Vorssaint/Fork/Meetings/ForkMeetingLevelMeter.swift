// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import QuartzCore
import SwiftUI

/// The recording's two levels, read once for every meter on screen: the
/// pill's, the island strip's and the live card's share one timer, which
/// runs only while one of them can be seen.
///
/// Fifteen readings a second, twice with Reduce Motion: the meters still
/// follow the voices, which is information, not decoration. Each reading
/// sets a few layers' heights without animation. A Core Animation
/// animation retriggered at each reading, like a SwiftUI one, keeps the
/// window server compositing the display on every refresh, up to 120
/// times a second, for bars a few points tall.
///
/// Main thread only.
final class ForkMeetingLevelFeed {
    static let shared = ForkMeetingLevelFeed()

    static let interval: TimeInterval = 1.0 / 15
    static let reducedInterval: TimeInterval = 0.5

    /// The engine's latest levels, read under its lock, between 0 and 1.
    var source: () -> ForkMeetingLevels = { .silent }

    private let meters = NSHashTable<ForkMeetingLevelBarsView>.weakObjects()
    private var timer: Timer?
    private var motionObserver: NSObjectProtocol?
    private(set) var latest = ForkMeetingLevels.silent

    private init() {}

    /// The feature is off: nothing is read any more.
    func reset() {
        source = { .silent }
        latest = .silent
    }

    /// A meter came on screen: it shows the latest reading at once, and the
    /// timer runs.
    func attach(_ meter: ForkMeetingLevelBarsView) {
        if meters.allObjects.isEmpty { latest = source() }
        meters.add(meter)
        meter.show(latest)
        sync()
    }

    func detach(_ meter: ForkMeetingLevelBarsView) {
        meters.remove(meter)
        sync()
    }

    private func sync() {
        guard !meters.allObjects.isEmpty else {
            timer?.invalidate()
            timer = nil
            if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }
            motionObserver = nil
            return
        }
        if motionObserver == nil {
            motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: nil, queue: .main) { [weak self] _ in self?.sync() }
        }
        let interval = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? Self.reducedInterval : Self.interval
        if let timer, timer.timeInterval == interval { return }
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.read() }
        timer.tolerance = interval / 4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func read() {
        let meters = self.meters.allObjects
        // A meter released without leaving its window first: nothing reads.
        guard !meters.isEmpty else {
            sync()
            return
        }
        let reading = source()
        guard reading != latest else { return }
        latest = reading
        for meter in meters { meter.show(reading) }
    }
}

/// Which of the two levels a meter shows.
enum ForkMeetingLevelTrack {
    case microphone
    case meeting

    func level(_ levels: ForkMeetingLevels) -> Float {
        switch self {
        case .microphone: return levels.microphone
        case .meeting: return levels.meeting
        }
    }
}

/// A level meter of the pill, the island's strip or the live card: its
/// bars are Core Animation layers (`ForkMeetingMeterStyle`), set by the
/// shared feed while the meter is on screen.
///
/// `reads` false (paused, stopped, the pill stepped aside) rests the bars
/// and reads nothing; `heard` false draws them flat and dim. With a
/// `label`, the meter is an accessibility element whose value, the level
/// in percent, is worked out only when an assistive app asks for it.
struct ForkMeetingLevelBars: NSViewRepresentable {
    let style: ForkMeetingMeterStyle
    let track: ForkMeetingLevelTrack
    var heard = true
    var reads = true
    var tint: NSColor?
    var label: String?

    func makeNSView(context: Context) -> ForkMeetingLevelBarsView {
        ForkMeetingLevelBarsView(style: style)
    }

    func updateNSView(_ view: ForkMeetingLevelBarsView, context: Context) {
        view.configure(style: style, track: track, heard: heard, reads: reads, tint: tint, label: label)
    }

    static func dismantleNSView(_ view: ForkMeetingLevelBarsView, coordinator: ()) {
        view.stop()
    }
}

final class ForkMeetingLevelBarsView: NSView {
    private(set) var style: ForkMeetingMeterStyle
    private var track = ForkMeetingLevelTrack.microphone
    private var heard = true
    private var reads = true
    /// `nil`: the label colour of the view's appearance (the pill's glass).
    private var tint: NSColor?
    private var level: Float?
    private var color = NSColor.white.cgColor
    private var bars: [CALayer] = []
    private var attached = false
    private var visibilityObserver: NSObjectProtocol?

    init(style: ForkMeetingMeterStyle) {
        self.style = style
        super.init(frame: CGRect(origin: .zero, size: style.size))
        wantsLayer = true
        setAccessibilityElement(false)
        setAccessibilityRole(.levelIndicator)
        refreshColor()
        rebuildBars()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit {
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
    }

    override var intrinsicContentSize: NSSize { style.size }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(style: ForkMeetingMeterStyle, track: ForkMeetingLevelTrack, heard: Bool, reads: Bool,
                   tint: NSColor?, label: String?) {
        let restyled = style != self.style
        self.style = style
        self.track = track
        self.heard = heard
        self.reads = reads
        self.tint = tint
        setAccessibilityElement(label != nil)
        setAccessibilityLabel(label)
        refreshColor()
        if restyled {
            invalidateIntrinsicContentSize()
            rebuildBars()
        }
        if !reads { level = nil }
        sync()
        render()
    }

    /// A reading of the feed, or the latest one as the meter comes back.
    func show(_ levels: ForkMeetingLevels) {
        guard reads else { return }
        let next = track.level(levels)
        guard next != level else { return }
        level = next
        render()
    }

    /// The view leaves for good: the feed forgets it.
    func stop() {
        if attached { ForkMeetingLevelFeed.shared.detach(self) }
        attached = false
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
        visibilityObserver = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
        visibilityObserver = window.map { window in
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                   object: window, queue: .main) { [weak self] _ in
                self?.sync()
            }
        }
        sync()
    }

    override func viewDidHide() { super.viewDidHide(); sync() }
    override func viewDidUnhide() { super.viewDidUnhide(); sync() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColor()
        render()
    }

    override func layout() {
        super.layout()
        render()
    }

    override func accessibilityValue() -> Any? {
        let value = Double(min(1, max(0, level.map { $0.isFinite ? $0 : 0 } ?? 0)))
        return value.formatted(.percent.precision(.fractionLength(0)))
    }

    /// On the feed while the levels are read and the meter can be seen: in
    /// a window on screen and not covered.
    private func sync() {
        let wanted = reads && heard && !isHiddenOrHasHiddenAncestor && window?.isVisible == true
            && window?.occlusionState.contains(.visible) == true
        guard wanted != attached else { return }
        attached = wanted
        if wanted { ForkMeetingLevelFeed.shared.attach(self) } else { ForkMeetingLevelFeed.shared.detach(self) }
    }

    private func rebuildBars() {
        bars.forEach { $0.removeFromSuperlayer() }
        bars = (0..<style.bars).map { _ in
            let bar = CALayer()
            bar.cornerCurve = .continuous
            layer?.addSublayer(bar)
            return bar
        }
        needsLayout = true
    }

    /// Light or dark, and with Increase Contrast, as the pill's words.
    private func refreshColor() {
        if let tint {
            color = tint.cgColor
            return
        }
        effectiveAppearance.performAsCurrentDrawingAppearance { color = NSColor.labelColor.cgColor }
    }

    private func render() {
        let left = (bounds.width - style.contentWidth) / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            let look = style.bar(index, level: reads ? level : nil, heard: heard)
            let y = style.standsOnBottom ? 0 : (bounds.height - look.height) / 2
            bar.frame = CGRect(x: left + CGFloat(index) * (style.barWidth + style.spacing), y: y,
                               width: style.barWidth, height: look.height)
            bar.cornerRadius = style.barWidth / 2
            bar.backgroundColor = color
            bar.opacity = Float(look.opacity)
        }
        CATransaction.commit()
    }
}
