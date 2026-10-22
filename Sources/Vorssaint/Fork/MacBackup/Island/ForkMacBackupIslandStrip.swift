// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import SwiftUI

/// The closed island while a backup, a restore or a verification runs, an
/// official live activity like Keep Awake's (`NotchKeepAwakeStrip`): left of
/// the camera a sarcelle ring around its arrow (up for a backup, down for a
/// restore, a shield for a verification), filling with the bytes, turning
/// while nothing honest can be said; right of it the percentage or the time
/// left, in orange while a meeting slows it. At the end the ring fills and
/// turns into a checkmark, then leaves for the notice. A click (or a hover)
/// opens the Backup section.
///
/// Never a delay, never a problem (decision 2 of 22/10): it is only listed
/// while `ForkMacBackupPhase.showsInClosedIsland`.
struct ForkMacBackupIslandStrip: View {
    @ObservedObject var service: NotchService
    /// The capsule's size, when the island floats; nil for the wings.
    private let size: CGSize?
    /// Another display's geometry, when the island shows on every display.
    private let displayGeometry: NotchGeometry?
    @ObservedObject private var status: ForkMacBackupStatusModel
    @ObservedObject private var model = ForkMacBackupIslandModel.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(ForkDefaultsKey.macBackupIslandReading) private var readingStored = ForkMacBackupReading.fallback.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.notchSettingsPreview) private var preview
    /// Shown whatever the island lists (the render harness).
    private let forced: ForkMacBackupIslandSnapshot?

    /// The hanging strip, around the camera.
    init(service: NotchService, displayGeometry: NotchGeometry?, status: ForkMacBackupStatusModel = .shared,
         forced: ForkMacBackupIslandSnapshot? = nil) {
        self.service = service
        size = nil
        self.displayGeometry = displayGeometry
        _status = ObservedObject(wrappedValue: status)
        self.forced = forced
    }

    /// The floating capsule.
    init(service: NotchService, size: CGSize, displayGeometry: NotchGeometry? = nil,
         status: ForkMacBackupStatusModel = .shared, forced: ForkMacBackupIslandSnapshot? = nil) {
        self.service = service
        self.size = size
        self.displayGeometry = displayGeometry
        _status = ObservedObject(wrappedValue: status)
        self.forced = forced
    }

    private var reading: ForkMacBackupReading { ForkMacBackupReading(rawValue: readingStored) ?? .fallback }
    private var text: ForkMacBackupStrings { ForkMacBackupStrings.strings(l10n.language) }

    var body: some View {
        let current = forced ?? ForkMacBackupIslandSnapshot(state: status.presentation, finishing: model.finishing,
                                                               checked: model.checked)
        NotchStripHold(current, shows: forced != nil || model.showsActivity) { snapshot in
            strip(snapshot)
        }
        .onAppear { if !preview, forced == nil { status.beginLiveViewing() } }
        .onDisappear { if !preview, forced == nil { status.endLiveViewing() } }
    }

    @ViewBuilder private func strip(_ snapshot: ForkMacBackupIslandSnapshot) -> some View {
        let value = ForkMacBackupIslandRules.reading(snapshot.state, text: text, locale: l10n.language.formattingLocale(),
                                                     reading: reading, finishing: snapshot.finishing)
        Button { ForkMacBackupIsland.openSection(from: service) } label: {
            if let size {
                capsule(snapshot, reading: value, size: size)
            } else {
                wings(snapshot, reading: value)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.islandTitle)
        .accessibilityValue(snapshot.finishing ? text.finished
            : snapshot.state.headline(text, language: l10n.language, locale: l10n.language.formattingLocale(),
                                      reading: reading))
        .accessibilityHint(ForkMacBackupIslandStrings.strings(l10n.language).activityHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("notch.macBackup")
        // A reading that gains a character widens the strip; the island
        // measures the same reading.
        .onChange(of: NotchAgentSupport.readingShape(value)) { _, _ in
            DispatchQueue.main.async { service.refreshPresentation() }
        }
    }

    // MARK: Wings

    private func wings(_ snapshot: ForkMacBackupIslandSnapshot, reading: String) -> some View {
        let geometry = displayGeometry ?? service.compactActivityGeometry
        let height = geometry.compactActivityContentHeight
        let wing = geometry.compactActivityWingWidth
        let side = Self.markSide(height: height)
        let textSize = NotchTimerSupport.stripTextSize(height: height)
        return HStack(spacing: 0) {
            Group {
                if wing >= 28 { mark(snapshot, side: side) }
            }
            .padding(.leading, geometry.compactActivityEdgeInset(boxHeight: side, radius: side / 2))
            .frame(width: wing, height: height, alignment: .leading)
            Color.clear.frame(width: geometry.compactActivityCameraGap)
            Group {
                if wing >= 42 {
                    readingText(snapshot, reading: reading, font: .system(size: textSize, weight: .medium))
                }
            }
            // Digits carry no descenders, so their ink is about the cap height.
            .padding(.trailing, geometry.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0))
            .frame(width: wing, height: height, alignment: .trailing)
        }
        .frame(height: height)
        .contentShape(Rectangle())
        .padding(.horizontal, geometry.compactActivityHorizontalPadding)
        .padding(.top, geometry.compactActivityTopPadding)
    }

    // MARK: Capsule

    private func capsule(_ snapshot: ForkMacBackupIslandSnapshot, reading: String, size: CGSize) -> some View {
        let geometry = displayGeometry ?? service.geometry
        let side = NotchCapsuleLayout.side(geometry)
        let layout = NotchCapsuleLayout.self
        return HStack(spacing: layout.spacing) {
            // With the meter beside it the mark need not fill too, as the
            // downloads' arrow does not: the ring only turns while no share is known.
            Group {
                if snapshot.progress != nil {
                    Image(systemName: snapshot.glyph.capsuleSymbol)
                        .font(.system(size: layout.symbolSize, weight: .medium))
                        .foregroundStyle(Color.teal)
                        .id(snapshot.glyph)
                        .transition(.blurReplace)
                } else {
                    mark(snapshot, side: layout.symbolWidth)
                }
            }
            .frame(width: layout.symbolWidth)
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: snapshot.glyph)
            .accessibilityHidden(true)
            if let fraction = snapshot.progress {
                NotchMeter(value: fraction, height: layout.meterHeight, tint: .teal)
                    .frame(width: layout.downloadMeterWidth)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: fraction)
                    .padding(.leading, layout.groupSpacing - layout.spacing)
            }
            readingText(snapshot, reading: reading, font: Font(layout.readingFont as CTFont))
        }
        .padding(.leading, side + layout.endPadding)
        .padding(.trailing, side + layout.endPadding)
        .frame(width: size.width, height: geometry.stripHeight)
        .foregroundStyle(.white)
        .contentShape(Rectangle())
    }

    // MARK: Parts

    /// The ring and its arrow, swapped through a blur for the checkmark at
    /// the end, or a step that changes the arrow; in place with Reduce Motion.
    private func mark(_ snapshot: ForkMacBackupIslandSnapshot, side: CGFloat) -> some View {
        ZStack {
            ForkMacBackupIslandMark(glyph: snapshot.glyph, progress: snapshot.progress, side: side)
                .id(snapshot.glyph)
                .transition(.blurReplace)
        }
        .frame(width: side, height: side)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: snapshot.glyph)
    }

    private func readingText(_ snapshot: ForkMacBackupIslandSnapshot, reading: String, font: Font) -> some View {
        let slowed = ForkMacBackupIslandRules.readingIsSlowed(snapshot.state)
        return Text(reading)
            .font(font).monospacedDigit()
            .foregroundStyle(slowed ? Color.orange : Color.white)
            .lineLimit(1).minimumScaleFactor(0.65)
            .fixedSize(horizontal: size != nil, vertical: false)
            .modifier(NotchRollingDigits(value: reading, countsDown: false, everySecond: false))
            .animation(reduceMotion ? nil : .smooth(duration: 0.26), value: slowed)
    }

    // MARK: Measures

    /// The ring's box: a little under the strip's icons, which carry their
    /// own circles, and never so small its arrow cannot be read.
    static func markSide(height: CGFloat) -> CGFloat {
        min(18, max(12, NotchTimerSupport.stripIconSize(height: height) - 2))
    }

    /// The wider of the two sides, the ring or the reading, with the
    /// timer's clearance from the silhouette's curve and air beside the
    /// camera (seam `notch-macbackup3`).
    static func wing(in geometry: NotchGeometry) -> CGFloat {
        wing(in: geometry, reading: currentReading)
    }

    static func wing(in geometry: NotchGeometry, reading value: String) -> CGFloat {
        let provisional = geometry.compactTimerGeometry(showsDownloads: false,
                                                        wing: NotchTimerSupport.stripWingRange.lowerBound)
        let height = provisional.compactActivityContentHeight
        let textSize = NotchTimerSupport.stripTextSize(height: height)
        let reading = (NotchAgentSupport.readingShape(value) as NSString)
            .size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: textSize, weight: .medium)])
            .width.rounded(.up)
        let side = markSide(height: height)
        let mark = side + provisional.compactActivityEdgeInset(boxHeight: side, radius: side / 2)
        return max(reading + provisional.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0), mark)
            + NotchTimerSupport.stripCameraGap
    }

    /// The floating capsule: the ring, the meter while bytes move, the
    /// reading (seam `notch-macbackup3`).
    static func capsuleSize(geometry: NotchGeometry) -> CGSize {
        let model = ForkMacBackupIslandModel.shared
        return capsuleSize(geometry: geometry, hasMeter: ForkMacBackupIslandRules.ringProgress(
            model.status.presentation, finishing: model.finishing) != nil, reading: currentReading)
    }

    static func capsuleSize(geometry: NotchGeometry, hasMeter: Bool, reading: String) -> CGSize {
        let layout = NotchCapsuleLayout.self
        let meter = hasMeter ? layout.downloadMeterWidth + layout.groupSpacing : 0
        let content = layout.symbolWidth + layout.spacing + meter
            + layout.width(NotchAgentSupport.readingShape(reading), font: layout.readingFont)
        return layout.surface(content: content, maximum: layout.Maximum.activity, geometry: geometry)
    }

    /// The reading as the strip draws it now.
    private static var currentReading: String {
        let model = ForkMacBackupIslandModel.shared
        let language = L10n.shared.language
        return ForkMacBackupIslandRules.reading(model.status.presentation, text: ForkMacBackupStrings.strings(language),
                                                locale: language.formattingLocale(), reading: model.readingSetting,
                                                finishing: model.finishing)
    }
}

/// A small sarcelle ring around its arrow (`ForkMeetingIslandGauge`, the
/// meetings' own ring): filled as far as the bytes went, a turning arc while
/// unknown (still with Reduce Motion); a checkmark once done.
struct ForkMacBackupIslandMark: View {
    let glyph: ForkMacBackupIslandRules.Glyph
    let progress: Double?
    let side: CGFloat

    var body: some View {
        Group {
            if glyph == .done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: side, weight: .semibold))
                    .foregroundStyle(Color.teal)
            } else {
                ZStack {
                    ForkMeetingIslandGauge(progress: progress, side: side, tint: .teal)
                    Image(systemName: glyph.symbol)
                        .font(.system(size: max(6, side * 0.42), weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}
