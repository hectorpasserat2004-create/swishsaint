// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import SwiftUI

/// The closed island while Glance has something to say (plan §11.2), an
/// official live activity like Keep Awake's (`NotchKeepAwakeStrip`): left
/// of the camera its mark, `eye.slash` for a pause, `viewfinder` for a
/// calibration, `eyes` when it shows always; right of it the minutes a
/// timed pause has left (∞ for one until resumed), the calibration's
/// points, or the zone glyph, a small drawing of the zones of the display
/// looked at with the active one filled. A click (or a hover) opens the
/// « Regard » section. The capsule (a display without a notch) and the
/// copies on the other displays draw the same.
struct ForkGlanceIslandStrip: View {
    @ObservedObject var service: NotchService
    /// The capsule's size, when the island floats; nil for the wings.
    private let size: CGSize?
    /// Another display's geometry, when the island shows on every display.
    private let displayGeometry: NotchGeometry?
    @ObservedObject private var model = ForkGlanceIslandModel.shared
    @ObservedObject private var glance = ForkGlanceService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Shown whatever the island lists (the render harness).
    private let forced: ForkGlanceIslandRules.Activity?
    private let forcedZones: (layout: ForkGlanceDisplayLayout, zones: [ForkGlanceZone])?

    /// The hanging strip, around the camera.
    init(service: NotchService, displayGeometry: NotchGeometry?, forced: ForkGlanceIslandRules.Activity? = nil,
         forcedZones: (layout: ForkGlanceDisplayLayout, zones: [ForkGlanceZone])? = nil) {
        self.service = service
        size = nil
        self.displayGeometry = displayGeometry
        self.forced = forced
        self.forcedZones = forcedZones
    }

    /// The floating capsule.
    init(service: NotchService, size: CGSize, displayGeometry: NotchGeometry? = nil,
         forced: ForkGlanceIslandRules.Activity? = nil,
         forcedZones: (layout: ForkGlanceDisplayLayout, zones: [ForkGlanceZone])? = nil) {
        self.service = service
        self.size = size
        self.displayGeometry = displayGeometry
        self.forced = forced
        self.forcedZones = forcedZones
    }

    private var locale: Locale { Locale(identifier: l10n.language.rawValue) }

    var body: some View {
        // An activity that ends clears itself before the strip has left.
        NotchStripHold(forced ?? model.activity, shows: forced != nil || model.activity != nil) { activity in
            if let activity { content(activity) }
        }
    }

    @ViewBuilder private func content(_ activity: ForkGlanceIslandRules.Activity) -> some View {
        if case .paused(let until?) = activity {
            // The reading changes once a minute, so the clock wakes only then.
            TimelineView(.periodic(from: NotchKeepAwakeSupport.tickStart(until: until, now: Date()), by: 60)) { context in
                strip(activity, now: context.date)
            }
        } else {
            strip(activity, now: Date())
        }
    }

    private func strip(_ activity: ForkGlanceIslandRules.Activity, now: Date) -> some View {
        let reading = ForkGlanceIslandRules.reading(activity, now: now, locale: locale)
        return Button { ForkGlanceIsland.openSection(from: service) } label: {
            if let size {
                capsule(activity, reading: reading, size: size)
            } else {
                wings(activity, reading: reading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ForkGlanceStrings.strings(l10n.language).sectionTitle)
        .accessibilityValue(spoken(activity, now: now))
        .accessibilityHint(ForkGlanceIslandStrings.strings(l10n.language).activityHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("notch.glance")
        // A reading that gains or loses a character, like 10m becoming 9m,
        // resizes the wings; the island measures the same reading.
        .onChange(of: ForkGlanceIslandRules.readingText(reading).map(NotchAgentSupport.readingShape) ?? "") { _, _ in
            DispatchQueue.main.async { service.refreshPresentation() }
        }
    }

    // MARK: Wings

    private func wings(_ activity: ForkGlanceIslandRules.Activity, reading: ForkGlanceIslandRules.Reading) -> some View {
        let geometry = displayGeometry ?? service.compactActivityGeometry
        let height = geometry.compactActivityContentHeight
        let wing = geometry.compactActivityWingWidth
        let iconSize = Self.markSize(height: height)
        let textSize = NotchTimerSupport.stripTextSize(height: height)
        return HStack(spacing: 0) {
            Group {
                if wing >= 28 { mark(activity, size: iconSize) }
            }
            .padding(.leading, geometry.compactActivityEdgeInset(boxHeight: iconSize, radius: iconSize / 2))
            .frame(width: wing, height: height, alignment: .leading)
            Color.clear.frame(width: geometry.compactActivityCameraGap)
            Group {
                if wing >= 42 { readingView(activity, reading: reading, font: .system(size: textSize, weight: .medium)) }
            }
            // Digits carry no descenders, so their ink is about the cap height.
            .padding(.trailing, geometry.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0))
            .frame(width: wing, height: height, alignment: .trailing)
        }
        .foregroundStyle(.white.opacity(0.9))
        .frame(height: height)
        .contentShape(Rectangle())
        .padding(.horizontal, geometry.compactActivityHorizontalPadding)
        .padding(.top, geometry.compactActivityTopPadding)
    }

    // MARK: Capsule

    private func capsule(_ activity: ForkGlanceIslandRules.Activity, reading: ForkGlanceIslandRules.Reading,
                         size: CGSize) -> some View {
        let geometry = displayGeometry ?? service.geometry
        let side = NotchCapsuleLayout.side(geometry)
        let layout = NotchCapsuleLayout.self
        return HStack(spacing: layout.spacing) {
            mark(activity, size: layout.symbolSize)
                .frame(width: layout.symbolWidth)
            readingView(activity, reading: reading, font: Font(layout.readingFont as CTFont))
        }
        .padding(.leading, side + layout.endPadding)
        .padding(.trailing, side + layout.endPadding)
        .frame(width: size.width, height: geometry.stripHeight)
        .foregroundStyle(.white.opacity(0.9))
        .contentShape(Rectangle())
    }

    // MARK: Parts

    private func mark(_ activity: ForkGlanceIslandRules.Activity, size: CGFloat) -> some View {
        let symbol = ForkGlanceIslandRules.symbol(activity)
        return Image(systemName: symbol)
            .font(.system(size: size, weight: .medium))
            .contentTransition(.symbolEffect(.replace))
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: symbol)
            .accessibilityHidden(true)
    }

    @ViewBuilder private func readingView(_ activity: ForkGlanceIslandRules.Activity,
                                          reading: ForkGlanceIslandRules.Reading, font: Font) -> some View {
        switch reading {
        case .text(let text):
            Text(text)
                .font(font).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.65)
                .fixedSize(horizontal: size != nil, vertical: false)
                .modifier(NotchRollingDigits(value: text, countsDown: true, everySecond: false))
        case .symbol(let name):
            Image(systemName: name).font(font)
        case .glyph:
            let zoneID: String? = {
                if case .watching(let zone) = activity { return zone }
                return nil
            }()
            ZStack {
                ForkGlanceZoneGlyph(cells: cells(active: zoneID))
                    .id(zoneID ?? "")
                    .transition(.blurReplace)
            }
            .frame(width: ForkGlanceIslandRules.glyphSize.width, height: ForkGlanceIslandRules.glyphSize.height)
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: zoneID)
        }
    }

    private func cells(active: String?) -> [ForkGlanceIslandRules.GlyphCell] {
        let source = forcedZones ?? (glance.layout, glance.zones)
        return ForkGlanceIslandRules.glyph(zones: source.zones, layout: source.layout, active: active)
    }

    /// What VoiceOver reads: the status line, or the zone's name.
    private func spoken(_ activity: ForkGlanceIslandRules.Activity, now: Date) -> String {
        let text = ForkGlanceStrings.strings(l10n.language)
        let locale = l10n.language.formattingLocale()
        switch activity {
        case .paused(let until):
            return text.status(.paused(.user, until: until), locale: locale, now: now)
        case .calibrating(let done, let total):
            return text.status(.calibrating(done: done, total: total), locale: locale, now: now)
        case .watching(let zone):
            return text.status(.active(zoneName: zone.flatMap(glance.zoneName)), locale: locale, now: now)
        }
    }

    // MARK: Measures

    /// The mark: Keep Awake's size less a little, never too small to read
    /// (plan §11.2: `min(18, max(12, icon − 2))`).
    static func markSize(height: CGFloat) -> CGFloat {
        min(18, max(12, NotchTimerSupport.stripIconSize(height: height) - 2))
    }

    /// The wider of the two sides, the mark or the reading, with the
    /// timer's clearance from the silhouette's curve and air beside the
    /// camera (seam `notch-glance-activity3`).
    static func wing(in geometry: NotchGeometry) -> CGFloat {
        guard let activity = ForkGlanceIslandModel.shared.activity else { return 0 }
        return wing(in: geometry, activity: activity, now: Date(), locale: Locale(identifier: L10n.shared.language.rawValue))
    }

    static func wing(in geometry: NotchGeometry, activity: ForkGlanceIslandRules.Activity, now: Date,
                     locale: Locale) -> CGFloat {
        let provisional = geometry.compactTimerGeometry(showsDownloads: false,
                                                        wing: NotchTimerSupport.stripWingRange.lowerBound)
        let height = provisional.compactActivityContentHeight
        let textSize = NotchTimerSupport.stripTextSize(height: height)
        let reading: CGFloat
        switch ForkGlanceIslandRules.reading(activity, now: now, locale: locale) {
        case .text(let text):
            reading = (NotchAgentSupport.readingShape(text) as NSString)
                .size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: textSize, weight: .medium)])
                .width.rounded(.up)
        case .symbol(let name):
            reading = NotchKeepAwakeSupport.symbolWidth(name, size: textSize)
        case .glyph:
            reading = ForkGlanceIslandRules.glyphSize.width
        }
        let markSize = markSize(height: height)
        let mark = NotchKeepAwakeSupport.symbolWidth(ForkGlanceIslandRules.symbol(activity), size: markSize)
            + provisional.compactActivityEdgeInset(boxHeight: markSize, radius: markSize / 2)
        return max(reading + provisional.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0), mark)
            + NotchTimerSupport.stripCameraGap
    }

    /// The floating capsule: the mark and the reading (seam `notch-glance-activity8`).
    static func capsuleSize(geometry: NotchGeometry) -> CGSize {
        guard let activity = ForkGlanceIslandModel.shared.activity else { return geometry.restingSize(showsContent: false) }
        return capsuleSize(geometry: geometry, activity: activity, now: Date(),
                           locale: Locale(identifier: L10n.shared.language.rawValue))
    }

    static func capsuleSize(geometry: NotchGeometry, activity: ForkGlanceIslandRules.Activity, now: Date,
                            locale: Locale) -> CGSize {
        let layout = NotchCapsuleLayout.self
        let right: CGFloat
        switch ForkGlanceIslandRules.reading(activity, now: now, locale: locale) {
        case .text(let text): right = layout.width(NotchAgentSupport.readingShape(text), font: layout.readingFont)
        case .symbol(let name): right = NotchKeepAwakeSupport.symbolWidth(name, size: layout.readingFont.pointSize) + layout.air
        case .glyph: right = ForkGlanceIslandRules.glyphSize.width + layout.air
        }
        return layout.surface(content: layout.symbolWidth + layout.spacing + right, maximum: layout.Maximum.activity,
                              geometry: geometry)
    }
}

/// The zones of one display at 16 × 10 pt: each a small rounded cell, the
/// active one filled white, the others outlined.
struct ForkGlanceZoneGlyph: View {
    let cells: [ForkGlanceIslandRules.GlyphCell]
    var size = ForkGlanceIslandRules.glyphSize

    var body: some View {
        Canvas { context, canvas in
            let gap: CGFloat = 1
            for cell in cells {
                let rect = CGRect(x: cell.rect.minX * canvas.width, y: cell.rect.minY * canvas.height,
                                  width: cell.rect.width * canvas.width, height: cell.rect.height * canvas.height)
                    .insetBy(dx: gap / 2, dy: gap / 2)
                guard rect.width > 0.5, rect.height > 0.5 else { continue }
                let shape = Path(roundedRect: rect, cornerRadius: 1.5)
                if cell.active {
                    context.fill(shape, with: .color(.white))
                } else {
                    context.stroke(shape, with: .color(.white.opacity(0.55)), lineWidth: 1)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}
