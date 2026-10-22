// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import SwiftUI

/// The state at a glance (plan §11.1): the big word, the proof ladder, the
/// last and next backups, and two buttons. While a backup runs, its progress.
struct ForkMacBackupStatusCard: View {
    let text: ForkMacBackupSettingsStrings
    let shared: ForkMacBackupStrings
    let language: AppLanguage
    @ObservedObject var context: ForkMacBackupSettingsContext
    let presentation: ForkMacBackupPresentation

    var body: some View {
        let locale = language.formattingLocale()
        let now = context.services.now()
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                ForkMacBackupStateBadge(presentation: presentation)
                VStack(alignment: .leading, spacing: 6) {
                    Text(presentation.headline(shared, language: language, locale: locale, now: now))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(headlineColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if presentation.phase.showsInClosedIsland {
                        running(locale)
                    } else {
                        ForkMacBackupProofLadder(level: presentation.lastBackup?.level, shared: shared)
                            .frame(width: 252)
                            .padding(.leading, -8)
                        details(locale, now: now)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 8) {
                primaryButton
                Button {
                    ForkMacBackupWindow.open(.browse)
                } label: {
                    Label(shared.restore, systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                }
                Spacer()
                if let pending = presentation.pendingChanges, pending > 0, !presentation.phase.isBackingUp {
                    Label(shared.pending(pending, language: language), systemImage: "doc.badge.clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }
            .controlSize(.regular)
        }
        .padding(.vertical, 4)
        .onAppear { if presentation.phase.showsInClosedIsland { context.status.beginLiveViewing() } }
        .onDisappear { if presentation.phase.showsInClosedIsland { context.status.endLiveViewing() } }
    }

    private var headlineColor: Color {
        switch presentation.tone {
        case .red: return .red
        case .orange: return .orange
        default: return .primary
        }
    }

    @ViewBuilder
    private func details(_ locale: Locale, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let last = presentation.lastBackup {
                line("clock", String(format: shared.lastBackup, Self.when(last.date, now: now, locale: locale)))
                if let complete = presentation.lastComplete, complete.manifestID != last.manifestID {
                    line("checkmark.seal", String(format: shared.lastComplete, Self.when(complete.date, now: now, locale: locale)))
                }
            } else {
                line("clock", String(format: shared.lastBackup, shared.never))
            }
            if let next = presentation.nextRun ?? nextFromPhase {
                line("calendar", String(format: text.nextAround, ForkMacBackupFormat.time(next, locale: locale)))
            }
        }
    }

    private var nextFromPhase: Date? {
        if case .ready(let next) = presentation.phase { return next }
        return nil
    }

    @ViewBuilder
    private func running(_ locale: Locale) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let fraction = presentation.fraction {
                ProgressView(value: fraction)
                    .tint(ForkMacBackupStyle.accent)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(ForkMacBackupStyle.accent)
            }
            if let line = presentation.progressLine(shared, locale: locale) {
                Text(line)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let path = presentation.progress?.currentPath {
                Text(ForkMacBackupFormat.middleTruncated(path, limit: 56, home: context.home))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: 360, alignment: .leading)
    }

    private func line(_ symbol: String, _ value: String) -> some View {
        Label {
            Text(value)
        } icon: {
            Image(systemName: symbol)
                .frame(width: 14)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch presentation.phase {
        case .checkingChain, .preparing, .scanning, .uploading, .slowed:
            Menu {
                Button(shared.pauseOneHour) { context.send(.pause(until: context.services.now().addingTimeInterval(3_600))) }
                Button(shared.pauseUntilTomorrow) { context.send(.pause(until: Self.tomorrowMorning(context.services.now()))) }
                Button(shared.pauseUntilResumed) { context.send(.pause(until: nil)) }
            } label: {
                Label(shared.pause, systemImage: "pause.fill")
            }
            .menuStyle(.button)
            .fixedSize()
        case .paused:
            Button {
                context.send(.resume)
            } label: {
                Label(shared.resume, systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(ForkMacBackupStyle.accent)
        case .waiting:
            Button {
                context.send(.backUpNow)
            } label: {
                Label(shared.backUpAnyway, systemImage: "arrow.up.circle")
            }
        default:
            Button {
                context.send(.backUpNow)
            } label: {
                Label(shared.backUpNow, systemImage: "arrow.up.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(ForkMacBackupStyle.accent)
        }
    }

    /// « aujourd'hui 10:04 », « hier 22:10 », else the day and the time.
    static func when(_ date: Date, now: Date, locale: Locale) -> String {
        var calendar = Calendar.current
        calendar.locale = locale
        if calendar.isDate(date, inSameDayAs: now) || calendar.isDate(date, inSameDayAs: now.addingTimeInterval(-86_400)) {
            let day = calendar.isDate(date, inSameDayAs: now)
                ? Self.dayName(offset: 0, locale: locale) : Self.dayName(offset: -1, locale: locale)
            return day + " " + ForkMacBackupFormat.time(date, locale: locale)
        }
        return ForkMacBackupDay.text(date, locale: locale, now: now) + " " + ForkMacBackupFormat.time(date, locale: locale)
    }

    /// « aujourd'hui », « hier » in the locale's words.
    private static func dayName(offset: Int, locale: Locale) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.dateTimeStyle = .named
        formatter.formattingContext = .middleOfSentence
        return formatter.localizedString(from: DateComponents(day: offset))
    }

    static func tomorrowMorning(_ now: Date) -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}
