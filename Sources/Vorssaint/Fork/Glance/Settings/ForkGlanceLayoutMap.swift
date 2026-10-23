// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import SwiftUI

/// The displays at the scale of their millimeters, laid out like macOS has
/// them, with their zones (plan §12.4); the zone editor when `onSplit` is set.
/// The island's section (B4) and the assistant (B2) draw it read-only.
///
/// Geometry is `ForkGlanceMapGeometry` (pure, tested). The active zone is
/// filled, the candidate fills up as its dwell goes (plan §9), the live gaze
/// dot follows on a spring; all of it still under Reduce Motion.
struct ForkGlanceLayoutMap: View {
    enum Style: Sendable, Equatable {
        /// White on the island's black (`NotchControlSurface` zones).
        case island
        /// The Settings window's colors.
        case settings
    }

    let layout: ForkGlanceDisplayLayout
    let zones: [ForkGlanceZone]
    var activeZone: String?
    var candidate: ForkGlanceCandidate?
    /// The live gaze point, global points; nil hides the dot.
    var gazePoint: CGPoint?
    var style: Style = .settings
    /// Set: a click on a display opens its split menu (Entier, 2 colonnes…).
    var splits: [String: ForkGlanceSplit] = [:]
    var onSplit: ((String, ForkGlanceSplit) -> Void)?
    /// The estimate's σ around `gazePoint`, global points: the diagnostics'
    /// ellipse. Nil draws the dot alone.
    var gazeSigma: CGSize? = nil

    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var splitMenu: String?

    /// The stand-in's memberwise signature, kept as is (B2, B4), with the
    /// diagnostics' σ last.
    init(layout: ForkGlanceDisplayLayout, zones: [ForkGlanceZone], activeZone: String? = nil,
         candidate: ForkGlanceCandidate? = nil, gazePoint: CGPoint? = nil, style: Style = .settings,
         splits: [String: ForkGlanceSplit] = [:], onSplit: ((String, ForkGlanceSplit) -> Void)? = nil,
         gazeSigma: CGSize? = nil) {
        self.layout = layout
        self.zones = zones
        self.activeZone = activeZone
        self.candidate = candidate
        self.gazePoint = gazePoint
        self.style = style
        self.splits = splits
        self.onSplit = onSplit
        self.gazeSigma = gazeSigma
    }

    var body: some View {
        GeometryReader { proxy in
            let map = ForkGlanceMapGeometry(layout: layout, fitting: proxy.size, inset: 1)
            ZStack(alignment: .topLeading) {
                ForEach(map.screens) { screen in
                    screenView(screen, map: map)
                }
                gaze(map)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .aspectRatio(ForkGlanceMapGeometry.aspect(of: layout), contentMode: .fit)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: activeZone)
        .accessibilityElement(children: .contain)
    }

    // MARK: Displays

    @ViewBuilder
    private func screenView(_ screen: ForkGlanceMapGeometry.Screen, map: ForkGlanceMapGeometry) -> some View {
        let rect = screen.rect.insetBy(dx: 1.5, dy: 1.5)
        let radius = min(8, max(3, min(rect.width, rect.height) * 0.06))
        let own = zones.filter { $0.displayUUID == screen.display.uuid }
        let drawing = ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(style == .island ? Color.white.opacity(0.03) : Color.primary.opacity(0.045))
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(style == .island ? Color.white.opacity(0.22) : Color.primary.opacity(0.22),
                                      lineWidth: 1)
                }
                .frame(width: rect.width, height: rect.height)
            ForEach(own, id: \.id) { zone in
                if let zoneRect = map.rect(of: zone) {
                    zoneView(zone, rect: zoneRect.offsetBy(dx: -rect.minX, dy: -rect.minY).insetBy(dx: 2.5, dy: 2.5),
                             radius: max(2, radius - 2))
                }
            }
            if screen.display.hasNotch && style == .settings && rect.width > 60 {
                Capsule()
                    .fill(Color.primary.opacity(0.55))
                    .frame(width: rect.width * 0.12, height: max(3, rect.height * 0.045))
                    .offset(x: rect.width * 0.44, y: 2)
            }
            if style == .settings && rect.height > 34 {
                // In the bottom-left zone, never across a border between zones.
                Text(displayName(screen.display))
                    .font(.system(size: rect.height > 70 ? 10.5 : 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(.regularMaterial, in: Capsule())
                    .frame(maxWidth: labelRoom(own, map: map, screen: rect), alignment: .leading)
                    .padding(.bottom, 6)
                    .padding(.leading, 6)
                    .frame(width: rect.width, height: rect.height, alignment: .bottomLeading)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: rect.width, height: rect.height, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))

        if let onSplit {
            Button {
                splitMenu = screen.display.uuid
            } label: {
                drawing
            }
            .buttonStyle(.plain)
            .popover(isPresented: Binding(get: { splitMenu == screen.display.uuid },
                                          set: { if !$0 { splitMenu = nil } }),
                     arrowEdge: .bottom) {
                ForkGlanceSplitMenu(display: displayName(screen.display),
                                    current: splits[screen.display.uuid] ?? ForkGlanceZones.defaultSplit(for: screen.display),
                                    title: ForkGlanceSettingsStrings.strings(l10n.language).splitTitle,
                                    core: .strings(l10n.language)) { split in
                    splitMenu = nil
                    onSplit(screen.display.uuid, split)
                }
            }
            .help(displayName(screen.display))
            .accessibilityLabel(displayName(screen.display))
            .accessibilityValue(ForkGlanceStrings.strings(l10n.language).splitName(
                splits[screen.display.uuid] ?? ForkGlanceZones.defaultSplit(for: screen.display)))
            .accessibilityHint(ForkGlanceSettingsStrings.strings(l10n.language).splitTitle)
            .offset(x: rect.minX, y: rect.minY)
        } else {
            drawing
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(displayName(screen.display))
                .offset(x: rect.minX, y: rect.minY)
        }
    }

    /// The width the name may take: the zone in the display's bottom-left
    /// corner, less the zone's own inset, or the whole display.
    private func labelRoom(_ own: [ForkGlanceZone], map: ForkGlanceMapGeometry, screen rect: CGRect) -> CGFloat {
        let corner = CGPoint(x: rect.minX + 4, y: rect.maxY - 4)
        let zone = own.compactMap { map.rect(of: $0) }.first { $0.contains(corner) }
        return max(0, min(rect.width, zone?.width ?? rect.width) - 12)
    }

    private func displayName(_ display: ForkGlanceDisplay) -> String {
        display.isBuiltIn ? ForkGlanceStrings.strings(l10n.language).builtInDisplay : display.name
    }

    // MARK: Zones

    @ViewBuilder
    private func zoneView(_ zone: ForkGlanceZone, rect: CGRect, radius: CGFloat) -> some View {
        let active = zone.id == activeZone
        let progress = candidate?.zoneID == zone.id ? min(1, max(0, candidate?.progress ?? 0)) : nil
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack(alignment: .leading) {
            if style == .island {
                Color.clear
                    .modifier(NotchControlSurface(cornerRadius: radius, selected: false, interactive: false))
            } else {
                shape.fill(Color.primary.opacity(0.06))
                    .overlay { shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75) }
            }
            if let progress {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(fill.opacity(0.45))
                        .frame(width: proxy.size.width * progress)
                        .animation(reduceMotion ? nil : .linear(duration: 0.12), value: progress)
                }
                .clipShape(shape)
            }
            if active {
                shape.fill(fill)
                    .transition(.opacity)
            }
        }
        .frame(width: max(0, rect.width), height: max(0, rect.height))
        .offset(x: rect.minX, y: rect.minY)
    }

    private var fill: Color {
        style == .island ? .white : .accentColor
    }

    // MARK: Gaze

    @ViewBuilder
    private func gaze(_ map: ForkGlanceMapGeometry) -> some View {
        if let gazePoint, let point = map.point(gazePoint) {
            ZStack {
                if let gazeSigma, let size = map.size(gazeSigma, at: gazePoint), size.width > 0, size.height > 0 {
                    Ellipse()
                        .fill(dot.opacity(0.14))
                        .overlay { Ellipse().strokeBorder(dot.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2])) }
                        .frame(width: 2 * size.width, height: 2 * size.height)
                }
                Circle()
                    .fill(dot)
                    // On the island's white active zone, a dark ring keeps the white dot seen.
                    .overlay { Circle().strokeBorder(style == .island ? Color.black.opacity(0.75) : .white,
                                                     lineWidth: style == .island ? 2 : 1.5) }
                    .frame(width: 9, height: 9)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
            }
            .position(point)
            .animation(reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.86), value: point)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var dot: Color {
        style == .island ? .white : .orange
    }
}

/// A display's split menu: the five splits, each with its drawing (also
/// drawn alone by the render harness: a popover never shows off screen).
struct ForkGlanceSplitMenu: View {
    let display: String
    let current: ForkGlanceSplit
    let title: String
    let core: ForkGlanceStrings
    let pick: (ForkGlanceSplit) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(display)
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            ForEach(ForkGlanceSplit.allCases, id: \.self) { split in
                Button {
                    pick(split)
                } label: {
                    HStack(spacing: 10) {
                        ForkGlanceSplitGlyph(split: split, selected: split == current)
                            .frame(width: 30, height: 18)
                        Text(core.splitName(split))
                        Spacer(minLength: 12)
                        if split == current {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(minWidth: 220)
    }
}

/// A split drawn small: the display's outline and its zones.
struct ForkGlanceSplitGlyph: View {
    let split: ForkGlanceSplit
    var selected = false

    var body: some View {
        GeometryReader { proxy in
            let display = ForkGlanceDisplay(uuid: "glyph", name: "", frame: CGRect(origin: .zero, size: proxy.size))
            let zones = ForkGlanceZones.zones(layout: ForkGlanceDisplayLayout(displays: [display]), mode: .zones,
                                              splits: ["glyph": split], windows: [])
            ZStack(alignment: .topLeading) {
                ForEach(zones, id: \.id) { zone in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.22))
                        .frame(width: max(0, zone.rect.width - 2), height: max(0, zone.rect.height - 2))
                        .offset(x: zone.rect.minX + 1, y: zone.rect.minY + 1)
                }
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.4), lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
    }
}
