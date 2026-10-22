// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import SwiftUI

/// The timeline at the bottom (plan §6.2): one dot per backup, coloured by
/// its proof, ◐ when partial; earlier and later, the zoom, « Maintenant ».
struct ForkMacBackupTimelineBar: View {
    @ObservedObject var model: ForkMacBackupWindowModel
    @GestureState private var magnification: CGFloat = 1

    private var text: ForkMacBackupWindowStrings { model.text }

    var body: some View {
        let timeline = model.timeline
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                Button {
                    model.shiftTimeline(-1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .help(text.earlier)
                .accessibilityLabel(text.earlier)
                track(timeline)
                    .frame(maxWidth: .infinity)
                Button {
                    model.shiftTimeline(1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
                .help(text.later)
                .accessibilityLabel(text.later)
                .disabled(timeline.end >= model.now().addingTimeInterval(-60))
                Picker(text.zoomWeek, selection: Binding(get: { model.zoom }, set: { model.setZoom($0) })) {
                    ForEach(ForkMacBackupTimelineZoom.allCases, id: \.self) { zoom in
                        Text(text.title(zoom)).tag(zoom)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Button(text.now) { model.showNow() }
                    .disabled(model.currentSnapshots.last?.id == model.selectedSnapshotID
                              && timeline.end >= model.now().addingTimeInterval(-60))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
        .disabled(model.selectedSnapshot == nil)
    }

    private func track(_ timeline: ForkMacBackupTimeline) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: width, height: 2)
                    .offset(y: 13)
                ForEach(Array(timeline.ticks.enumerated()), id: \.offset) { _, tick in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 1, height: 6)
                        .offset(x: tick.fraction * width, y: 11)
                    Text(tickLabel(tick.date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .offset(x: min(max(0, tick.fraction * width - 14), max(0, width - 40)), y: 22)
                        .accessibilityHidden(true)
                }
                if timeline.points.isEmpty {
                    Text(text.noSnapshotInSpan)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: width)
                        .offset(y: -1)
                }
                ForEach(timeline.points) { point in
                    let selected = point.snapshots.contains { $0.manifestID == model.selectedSnapshotID }
                    Button {
                        model.selectSnapshot(selected ? (model.selectedSnapshotID ?? point.newest.manifestID)
                                                      : point.newest.manifestID)
                    } label: {
                        ForkMacBackupSnapshotDot(level: point.level, isPartial: point.snapshots.contains(where: \.isPartial),
                                                 selected: selected, size: point.count > 1 ? 11 : 10)
                            .overlay(alignment: .top) {
                                if point.count > 1 {
                                    Text("\(point.count)")
                                        .font(.system(size: 8, weight: .semibold).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .offset(y: -11)
                                        .fixedSize()
                                }
                            }
                            .contentShape(Rectangle().inset(by: -4))
                    }
                    .buttonStyle(.plain)
                    .help(help(point))
                    .accessibilityLabel(help(point))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .offset(x: point.fraction * width - (selected ? 8 : 5), y: selected ? 5 : 8)
                }
            }
        }
        .frame(height: 36)
        .gesture(MagnifyGesture().updating($magnification) { value, state, _ in
            state = value.magnification
        }.onEnded { value in
            if value.magnification > 1.3, let narrower = model.zoom.narrower { model.setZoom(narrower) }
            if value.magnification < 0.75, let wider = model.zoom.wider { model.setZoom(wider) }
        })
    }

    private func tickLabel(_ date: Date) -> String {
        switch model.zoom {
        case .day: return ForkMacBackupFormat.time(date, locale: model.locale)
        case .week: return date.formatted(.dateTime.weekday(.abbreviated).day().locale(model.locale))
        case .month: return date.formatted(.dateTime.day().month(.abbreviated).locale(model.locale))
        }
    }

    private func help(_ point: ForkMacBackupTimeline.Point) -> String {
        let date = ForkMacBackupFormat.dayAndTime(point.newest.date, locale: model.locale)
        var line = date + " · " + point.level.title(model.shared)
        if point.isPartial { line += " · " + text.partial }
        if point.count > 1 { line += " · " + text.saves(point.count, model.language) }
        return line
    }
}
