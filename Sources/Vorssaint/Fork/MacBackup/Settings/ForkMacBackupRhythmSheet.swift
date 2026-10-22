// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import SwiftUI

/// « Rythme » (plan §3.9, §3.9.1): Automatic by default, paced by what a
/// backup really costs; or every N hours, at fixed times, or both. Then the
/// conditions: power, Low Power Mode, a limited network, meetings, keeping
/// the Mac awake, a slower window, the priority.
struct ForkMacBackupRhythmSheet: View {
    @ObservedObject var context: ForkMacBackupSettingsContext
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var status: ForkMacBackupStatusModel

    @AppStorage(ForkDefaultsKey.macBackupScheduleMode) private var mode = ForkMacBackupScheduleMode.fallback.rawValue
    @AppStorage(ForkDefaultsKey.macBackupIntervalHours) private var intervalHours = 4
    @AppStorage(ForkDefaultsKey.macBackupTimes) private var times = "13:00,21:00"
    @AppStorage(ForkDefaultsKey.macBackupCatchUpDelayMinutes) private var catchUpMinutes = 3
    @AppStorage(ForkDefaultsKey.macBackupPowerMode) private var powerMode = "threshold"
    @AppStorage(ForkDefaultsKey.macBackupPowerMinPercent) private var minPercent = 30
    @AppStorage(ForkDefaultsKey.macBackupPowerForceAfterHours) private var forceAfterHours = 24
    @AppStorage(ForkDefaultsKey.macBackupLowPowerWaits) private var lowPowerWaits = true
    @AppStorage(ForkDefaultsKey.macBackupLimitedNetwork) private var limitedNetwork = "wait"
    @AppStorage(ForkDefaultsKey.macBackupMeetingMode) private var meetingMode = "slow"
    @AppStorage(ForkDefaultsKey.macBackupSlowMBps) private var slowMBps = 2
    @AppStorage(ForkDefaultsKey.macBackupThrottleWindow) private var throttleWindow = ""
    @AppStorage(ForkDefaultsKey.macBackupKeepAwake) private var keepAwake = "ac"
    @AppStorage(ForkDefaultsKey.macBackupEarlyEnabled) private var earlyEnabled = false
    @AppStorage(ForkDefaultsKey.macBackupEarlyThreshold) private var earlyThreshold = 200
    @AppStorage(ForkDefaultsKey.macBackupPriority) private var priority = "low"

    init(context: ForkMacBackupSettingsContext) {
        self.context = context
        _status = ObservedObject(wrappedValue: context.status)
    }

    private var text: ForkMacBackupSettingsStrings { .strings(l10n.language) }
    private var shared: ForkMacBackupStrings { .strings(l10n.language) }
    private var locale: Locale { l10n.language.formattingLocale() }
    private var scheduleMode: ForkMacBackupScheduleMode { ForkMacBackupScheduleMode(rawValue: mode) ?? .fallback }

    var body: some View {
        ForkMacBackupSheetScaffold(symbol: "clock.fill", title: text.rhythmTitle, subtitle: text.rhythmSubtitle,
                                   done: text.done) {
            rhythmSection
            powerSection
            networkSection
            speedSection
        }
    }

    // MARK: Rhythm

    private var rhythmSection: some View {
        Section {
            Picker(text.rhythmTitle, selection: $mode) {
                ForEach(ForkMacBackupScheduleMode.allCases, id: \.self) { mode in
                    Text(text.scheduleMode(mode)).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch scheduleMode {
            case .auto:
                automatic
            case .interval:
                intervalStepper
            case .times:
                timesEditor
            case .both:
                intervalStepper
                timesEditor
            }

            Stepper(value: $catchUpMinutes, in: 0...60) {
                LabeledContent(text.catchUp, value: String(format: text.minutesValue, catchUpMinutes))
            }
            ForkMacBackupCaption(text.catchUpCaption)
        } header: {
            Text(text.rhythmTitle)
        }
    }

    private var automatic: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.title3)
                    .foregroundStyle(ForkMacBackupStyle.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentRhythm)
                        .fontWeight(.semibold)
                    ForkMacBackupCaption(text.autoExplain)
                }
            }
            if let cost = status.presentation.costLine(shared, locale: locale) {
                Label(cost, systemImage: "gauge.with.dots.needle.33percent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let samples = status.presentation.cost?.samples {
                    ForkMacBackupCaption(text.measuredOver(samples, language: l10n.language))
                }
            } else {
                Label(text.autoNotMeasured, systemImage: "gauge.with.dots.needle.0percent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var currentRhythm: String {
        status.presentation.rhythmLine(shared, locale: locale)
    }

    private var intervalStepper: some View {
        Stepper(value: $intervalHours, in: 1...48) {
            LabeledContent(text.every, value: ForkMacBackupFormat.age(TimeInterval(intervalHours) * 3_600, locale: locale))
        }
    }

    private var timesEditor: some View {
        let list = ForkMacBackupTimes.parse(times)
        return VStack(alignment: .leading, spacing: 6) {
            Text(text.atTimes)
            ForEach(Array(list.enumerated()), id: \.offset) { index, minutes in
                HStack {
                    DatePicker(text.atTimes, selection: timeBinding(index: index, list: list),
                               displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .environment(\.locale, locale)
                    Spacer()
                    Button {
                        var next = list
                        next.remove(at: index)
                        times = ForkMacBackupTimes.storageValue(next)
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(list.count < 2)
                    .accessibilityLabel(text.timeRemove)
                }
            }
            Button {
                let last = list.last ?? 12 * 60
                times = ForkMacBackupTimes.storageValue(list + [(last + 4 * 60) % (24 * 60)])
            } label: {
                Label(text.timeAdd, systemImage: "plus")
            }
            .controlSize(.small)
        }
    }

    private func timeBinding(index: Int, list: [Int]) -> Binding<Date> {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_792_627_200))
        return Binding(get: {
            base.addingTimeInterval(TimeInterval(list[min(index, list.count - 1)]) * 60)
        }, set: { date in
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            var next = list
            next[index] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            times = ForkMacBackupTimes.storageValue(next)
        })
    }

    // MARK: Power

    private var powerSection: some View {
        Section {
            Picker(text.powerTitle, selection: $powerMode) {
                Text(text.powerAlways).tag("always")
                Text(text.powerAC).tag("ac")
                Text(text.powerThreshold).tag("threshold")
            }
            if powerMode == "threshold" {
                Stepper(value: $minPercent, in: 5...95, step: 5) {
                    LabeledContent(text.powerMinimum, value: ForkMacBackupFormat.percent(Double(minPercent) / 100, locale: locale))
                }
            }
            if powerMode != "always" {
                Stepper(value: $forceAfterHours, in: 1...168) {
                    LabeledContent(text.forceAfter, value: ForkMacBackupFormat.age(TimeInterval(forceAfterHours) * 3_600, locale: locale))
                }
            }
            Toggle(text.lowPowerWaits, isOn: $lowPowerWaits)
            Picker(text.keepAwake, selection: $keepAwake) {
                Text(text.keepAwakeNever).tag("never")
                Text(text.keepAwakeAC).tag("ac")
                Text(text.keepAwakeAlways).tag("always")
            }
            ForkMacBackupCaption(text.keepAwakeCaption)
        } header: {
            Text(text.powerHeader)
        }
    }

    // MARK: Network and meetings

    private var networkSection: some View {
        Section {
            Picker(text.limitedNetwork, selection: $limitedNetwork) {
                Text(text.conditionWait).tag("wait")
                Text(text.conditionSlow).tag("slow")
                Text(text.conditionIgnore).tag("ignore")
            }
            ForkMacBackupCaption(text.limitedNetworkCaption)
            Picker(text.meetingTitle, selection: $meetingMode) {
                Text(text.meetingPause).tag("pause")
                Text(text.conditionSlow).tag("slow")
                Text(text.meetingNothing).tag("none")
            }
            Toggle(isOn: $earlyEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.earlyTitle)
                    ForkMacBackupCaption(String(format: text.earlyCaption, earlyThreshold))
                }
            }
            if earlyEnabled {
                Stepper(value: $earlyThreshold, in: 20...5_000, step: 20) {
                    LabeledContent(text.earlyThreshold, value: earlyThreshold.formatted(.number.locale(locale)))
                }
            }
        } header: {
            Text(text.conditionsHeader)
        }
    }

    // MARK: Speed

    private var window: ForkMacBackupThrottleWindow? { ForkMacBackupThrottleWindow.parse(throttleWindow) }

    private var speedSection: some View {
        Section {
            Stepper(value: $slowMBps, in: 1...100) {
                LabeledContent(text.slowLimit, value: String(format: text.megabytesPerSecond, slowMBps))
            }
            ForkMacBackupCaption(text.slowLimitCaption)
            Toggle(text.windowTitle, isOn: Binding(get: { window != nil }, set: { on in
                throttleWindow = on ? ForkMacBackupThrottleWindow.suggested.storageValue : ""
            }))
            if let window {
                HStack {
                    DatePicker(text.windowFrom, selection: windowBinding(\.start, window), displayedComponents: .hourAndMinute)
                        .datePickerStyle(.field)
                        .environment(\.locale, locale)
                    DatePicker(text.windowTo, selection: windowBinding(\.end, window), displayedComponents: .hourAndMinute)
                        .datePickerStyle(.field)
                        .environment(\.locale, locale)
                }
                Stepper(value: Binding(get: { window.megabytesPerSecond }, set: { value in
                    var next = window
                    next.megabytesPerSecond = value
                    throttleWindow = next.storageValue
                }), in: 1...100) {
                    LabeledContent(text.windowLimit, value: String(format: text.megabytesPerSecond, window.megabytesPerSecond))
                }
            }
            Picker(text.priorityTitle, selection: $priority) {
                Text(text.priorityLow).tag("low")
                Text(text.priorityNormal).tag("normal")
            }
            ForkMacBackupCaption(text.priorityCaption)
        } header: {
            Text(text.speedHeader)
        }
    }

    private func windowBinding(_ key: WritableKeyPath<ForkMacBackupThrottleWindow, Int>,
                               _ window: ForkMacBackupThrottleWindow) -> Binding<Date> {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_792_627_200))
        return Binding(get: {
            base.addingTimeInterval(TimeInterval(window[keyPath: key]) * 60)
        }, set: { date in
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            var next = window
            next[keyPath: key] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            if next.start != next.end { throttleWindow = next.storageValue }
        })
    }
}
