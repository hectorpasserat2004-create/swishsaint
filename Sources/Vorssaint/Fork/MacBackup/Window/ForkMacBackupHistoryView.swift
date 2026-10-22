// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import SwiftUI

/// « Historique » (plan §5.4, §11.3): the slots of the last thirty days,
/// then every operation, newest first.
struct ForkMacBackupHistoryView: View {
    @ObservedObject var model: ForkMacBackupWindowModel

    private var text: ForkMacBackupWindowStrings { model.text }

    var body: some View {
        VStack(spacing: 0) {
            ForkMacBackupSlotsGridView(model: model)
                .padding(16)
            Divider()
            runs
        }
    }

    private var sortedRuns: [ForkMacBackupRunRecord] {
        model.ledger.runs.sorted { $0.start > $1.start }
    }

    @ViewBuilder private var runs: some View {
        if model.ledger.runs.isEmpty {
            ForkMacBackupEmptyState(symbol: "clock", title: text.runsEmpty)
        } else {
            Table(sortedRuns) {
                TableColumn(text.columnDate) { run in
                    Text(ForkMacBackupWindowDates.short(run.start, now: model.now(), locale: model.locale))
                        .monospacedDigit()
                }
                .width(min: 100, ideal: 120)
                TableColumn(text.columnOperation) { run in
                    Label(text.title(run.kind), systemImage: symbol(run.kind))
                }
                .width(min: 100, ideal: 120)
                TableColumn(text.columnTrigger) { run in
                    Text(text.title(run.trigger)).foregroundStyle(.secondary)
                }
                .width(min: 70, ideal: 95)
                TableColumn(text.duration) { run in
                    Text(run.duration.map { ForkMacBackupFormat.duration($0, locale: model.locale) } ?? "—")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 50, ideal: 65)
                TableColumn(text.sent) { run in
                    Text(run.kind == .backup ? ForkMacBackupFormat.bytes(run.bytesSent, locale: model.locale) : "—")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 55, ideal: 70)
                TableColumn(text.proof) { run in
                    if let proof = run.proofs.max(by: { $0.level < $1.level }) {
                        ForkMacBackupProofDots(level: proof.level, isPartial: proof.isPartial, dot: 6, gap: 3)
                            .help(proof.level.title(model.shared))
                            .accessibilityLabel(proof.level.title(model.shared))
                    } else {
                        Text("—").foregroundStyle(.tertiary)
                    }
                }
                .width(min: 50, ideal: 60)
                TableColumn(text.columnConditions) { run in
                    Text(conditions(run)).foregroundStyle(.secondary)
                }
                .width(min: 100, ideal: 170)
                TableColumn(text.columnResult) { run in
                    result(run)
                }
                .width(min: 100, ideal: 150)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private func symbol(_ kind: ForkMacBackupRunRecord.Kind) -> String {
        switch kind {
        case .backup: return "arrow.up.circle"
        case .verify: return "checkmark.shield"
        case .restore: return "arrow.down.circle"
        case .maintenance: return "wrench.and.screwdriver"
        }
    }

    private func conditions(_ run: ForkMacBackupRunRecord) -> String {
        var parts = [run.onBattery ? text.onBattery : text.onPower]
        if let drop = run.batteryDrop {
            parts.append(String(format: text.batteryUsed, ForkMacBackupFormat.batteryPoints(drop, locale: model.locale)))
        }
        return parts.joined(separator: " · ")
    }

    private func result(_ run: ForkMacBackupRunRecord) -> some View {
        let color: Color
        switch run.outcome {
        case .complete, .nothingToDo: color = ForkMacBackupWindowStyle.teal
        case .partial: color = .orange
        case .failed: color = .red
        case .canceled: color = .secondary
        }
        var line = text.title(run.outcome)
        if let failure = run.failure { line += " · " + failure.title(model.shared) }
        if let stop = run.stopReason { line += " · " + text.title(stop) }
        return HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(line).lineLimit(1)
        }
        .help(line)
    }
}

/// The slots, one column per day (oldest left), one row per stretch of
/// hours: the plan's calendar turned to fit the window's width.
struct ForkMacBackupSlotsGridView: View {
    @ObservedObject var model: ForkMacBackupWindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var text: ForkMacBackupWindowStrings { model.text }
    static let cell: CGFloat = 15
    static let spacing: CGFloat = 3

    var body: some View {
        let grid = ForkMacBackupSlotsGrid.build(slots: model.ledger.slots, now: model.now(), calendar: model.calendar)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(text.slotsTitle).font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                legend
            }
            if model.ledger.slots.isEmpty {
                Text(text.slotsEmpty).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 6) {
                        hourLabels(grid)
                        HStack(alignment: .top, spacing: Self.spacing) {
                            ForEach(Array(grid.rows.enumerated()), id: \.element.id) { index, row in
                                dayColumn(row, index: index, count: grid.rows.count, grid: grid)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            guard !appeared else { return }
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.35)) { appeared = true }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach([ForkMacBackupSlotsGrid.Mark.done, .partial, .failed, .asleep, .battery, .network, .paused, .upcoming],
                    id: \.self) { mark in
                HStack(spacing: 3) {
                    ForkMacBackupSlotMark(mark: mark, size: 11)
                    Text(text.title(mark)).font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func hourLabels(_ grid: ForkMacBackupSlotsGrid) -> some View {
        VStack(alignment: .trailing, spacing: Self.spacing) {
            Text(" ").font(.caption2).frame(height: 14)
            ForEach(grid.columnHours, id: \.self) { hour in
                Text(hourLabel(hour))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(height: Self.cell)
            }
        }
        .accessibilityHidden(true)
    }

    private func dayColumn(_ row: ForkMacBackupSlotsGrid.Row, index: Int, count: Int,
                           grid: ForkMacBackupSlotsGrid) -> some View {
        let isToday = index == count - 1
        return VStack(spacing: Self.spacing) {
            Text(row.day.formatted(.dateTime.day().locale(model.locale)))
                .font(.caption2.monospacedDigit().weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Color.primary : Color.secondary)
                .frame(width: Self.cell, height: 14)
            ForEach(row.cells) { cell in
                ForkMacBackupSlotMark(mark: cell.mark, size: Self.cell)
                    .help(tooltip(cell, day: row.day))
                    .accessibilityLabel(tooltip(cell, day: row.day))
            }
        }
        .padding(.horizontal, isToday ? 2 : 0)
        .background(RoundedRectangle(cornerRadius: 4).fill(isToday ? Color.accentColor.opacity(0.08) : Color.clear))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3).delay(Double(index) * 0.012), value: appeared)
    }

    private func hourLabel(_ hour: Int) -> String {
        var components = model.calendar.dateComponents([.year, .month, .day], from: model.now())
        components.hour = hour
        guard let date = model.calendar.date(from: components) else { return "\(hour)" }
        return date.formatted(.dateTime.hour(.defaultDigits(amPM: .narrow)).locale(model.locale))
    }

    private func tooltip(_ cell: ForkMacBackupSlotsGrid.Cell, day: Date) -> String {
        let locale = model.locale
        var lines = [day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))]
        if cell.slots.isEmpty {
            if cell.mark == .upcoming { lines.append(text.markUpcoming) }
            return lines.joined(separator: "\n")
        }
        for slot in cell.slots {
            var line = String(format: text.slotDue, ForkMacBackupFormat.time(slot.due, locale: locale)) + " · "
            switch slot.outcome {
            case .missed(let reason): line += text.title(reason, shared: model.shared)
            default: line += text.title(ForkMacBackupSlotsGrid.Mark.of(slot.outcome))
            }
            if let started = slot.startedAt, slot.startedLate {
                line += " · " + String(format: text.slotStarted, ForkMacBackupFormat.time(started, locale: locale))
            }
            lines.append(line)
        }
        if let caught = cell.caughtUpAt {
            lines.append(String(format: text.slotCaughtUp, ForkMacBackupFormat.dayAndTime(caught, locale: locale)))
        } else if !cell.mark.ran {
            lines.append(text.slotNotCaughtUp)
        }
        return lines.joined(separator: "\n")
    }
}

/// One mark of the slots: ● done, ◐ partial, ✕ failed, a ring with the
/// reason's symbol for a missed slot, · for later today.
struct ForkMacBackupSlotMark: View {
    let mark: ForkMacBackupSlotsGrid.Mark
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Color.secondary.opacity(mark == .empty ? 0.06 : 0.0))
            switch mark {
            case .done:
                Circle().fill(ForkMacBackupWindowStyle.teal).padding(size * 0.14)
            case .nothingToDo:
                Circle().fill(ForkMacBackupWindowStyle.teal.opacity(0.45)).padding(size * 0.14)
            case .partial:
                Image(systemName: "circle.lefthalf.filled")
                    .resizable()
                    .foregroundStyle(.orange)
                    .padding(size * 0.12)
            case .failed:
                Image(systemName: "xmark")
                    .resizable()
                    .fontWeight(.bold)
                    .foregroundStyle(.red)
                    .padding(size * 0.22)
            case .asleep, .battery, .network, .paused, .missed:
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1)
                    .padding(size * 0.08)
                if let symbol = symbol {
                    Image(systemName: symbol)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary)
                        .padding(size * 0.3)
                }
            case .upcoming:
                Circle().fill(Color.secondary.opacity(0.5)).frame(width: size * 0.2, height: size * 0.2)
            case .empty:
                EmptyView()
            }
        }
        .frame(width: size, height: size)
    }

    private var symbol: String? {
        switch mark {
        case .asleep: return "moon.fill"
        case .battery: return "battery.25"
        case .network: return "wifi.slash"
        case .paused: return "pause.fill"
        default: return nil
        }
    }
}
