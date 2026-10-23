// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import SwiftUI

/// The validation step (plan §8.4, step 6; also « Tester » on its own): each
/// zone lights twice in a random order over the displays, then the score per
/// zone and overall with its grade (`ForkGlanceGrade`), hints aimed at what
/// scored low, and « Refaire les points faibles » for the zones under 85 %.
struct ForkGlanceValidationView: View {
    @ObservedObject var session: ForkGlanceCalibrationSession

    var body: some View {
        Form {
            if let accuracy = session.accuracy {
                results(accuracy)
            } else {
                intro
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Before

    @ViewBuilder
    private var intro: some View {
        let text = session.text
        let zones = session.zones
        Section {
            HStack(alignment: .top, spacing: 14) {
                ForkGlanceIconTile(symbol: "checkmark.seal", size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(text.validationTitle)
                        .font(.title3.weight(.semibold))
                    Text(text.validationBody)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(text.zoneCount(zones.count))
                        .font(.callout.monospacedDigit())
                        .padding(.top, 2)
                }
            }
            .padding(.vertical, 4)
        }
        Section {
            ForkGlanceLayoutMap(layout: session.layout, zones: zones, splits: session.splits)
                .frame(height: 130)
        }
        if session.isRunning || session.fitting || session.problem != nil {
            Section {
                if let problem = session.problem {
                    ForkGlanceCaption(session.problemText(problem), color: .orange)
                } else if session.fitting {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(text.fitting)
                    }
                } else if let run = session.run {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.runLine ?? "")
                            .font(.callout.monospacedDigit())
                        ProgressView(value: Double(run.done), total: Double(max(1, run.targets.count)))
                            .tint(.indigo)
                    }
                }
            }
        }
    }

    // MARK: After

    @ViewBuilder
    private func results(_ accuracy: [String: Double]) -> some View {
        let text = session.text
        let core = session.core
        let overall = ForkGlanceValidation.overall(accuracy)
        let grade = ForkGlanceGrade(score: overall)
        let zones = session.zones.filter { accuracy[$0.id] != nil }
        let hints = ForkGlanceValidation.advice(accuracy, zones: session.zones, layout: session.layout, mode: session.mode)
        let weak = ForkGlanceValidation.weakZones(accuracy, zones: session.zones)
        Section {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(ForkGlanceGradeBadge.color(grade).opacity(0.2), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: overall)
                        .stroke(ForkGlanceGradeBadge.color(grade), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(ForkGlanceStrings.percent(overall, locale: session.locale))
                        .font(.system(size: 15, weight: .bold).monospacedDigit())
                }
                .frame(width: 62, height: 62)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(text.overall)
                        .font(.headline)
                    ForkGlanceGradeBadge(grade: grade, core: core)
                }
                Spacer()
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
        } header: {
            Text(text.resultTitle)
        }
        Section {
            ForEach(zones, id: \.id) { zone in
                zoneRow(zone, score: accuracy[zone.id] ?? 0)
            }
        } footer: {
            if !weak.isEmpty {
                ForkGlanceCaption(text.weakLine(locale: session.locale))
            }
        }
        if !hints.isEmpty {
            Section {
                ForEach(hints, id: \.self) { hint in
                    Label {
                        Text(text.advice(hint, displayName: session.displayName))
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: hint == .excellent ? "sparkles" : "lightbulb")
                            .foregroundStyle(hint == .excellent ? .green : .yellow)
                    }
                }
            }
        }
    }

    private func zoneRow(_ zone: ForkGlanceZone, score: Double) -> some View {
        let grade = ForkGlanceGrade(score: score)
        return HStack(spacing: 10) {
            Text(session.zoneName(zone))
                .lineLimit(1)
            Spacer(minLength: 8)
            ProgressView(value: min(1, max(0, score)))
                .tint(ForkGlanceGradeBadge.color(grade))
                .frame(width: 110)
            Text(ForkGlanceStrings.percent(score, locale: session.locale))
                .font(.callout.monospacedDigit())
                .frame(width: 48, alignment: .trailing)
            ForkGlanceGradeBadge(grade: grade, core: session.core)
                .frame(width: 96, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
