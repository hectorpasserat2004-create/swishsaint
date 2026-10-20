// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import SwiftUI

extension View {
    /// An appointment of the island's agenda (seam `notch-calendar-crm2`):
    /// the official card, or this one when the appointment has a video link
    /// or comes from the CRM.
    func forkAppointmentRow(_ event: NotchCalendarEvent, day: Date, now: Date, isNext: Bool,
                            countdown: Bool?) -> some View {
        modifier(ForkCalendarRowChoice(event: event, day: day, now: now, isNext: isNext, countdown: countdown))
    }
}

private struct ForkCalendarRowChoice: ViewModifier {
    let event: NotchCalendarEvent
    let day: Date
    let now: Date
    let isNext: Bool
    let countdown: Bool?
    @ObservedObject private var model = ForkCalendarAppointments.shared
    @Environment(\.notchSettingsPreview) private var preview

    @ViewBuilder func body(content: Content) -> some View {
        if preview, model.calling, model.appointments[event.id] != nil {
            // The Settings window may be shared during a call: its preview
            // shows no CRM name, only the calendar as it has it.
            if let original = model.originals[event.id] {
                ForkCalendarAppointmentRow(event: original, day: day, now: now, isNext: isNext, countdown: countdown,
                                           hidesCRM: true)
            }
        } else if model.decorates(event) {
            ForkCalendarAppointmentRow(event: event, day: day, now: now, isNext: isNext, countdown: countdown)
        } else {
            content
        }
    }
}

/// The official appointment card (`NotchCalendarEventRow`, drawn the same
/// way), with the call's line under it: the service, then Join and Copy
/// Link, which the card's menu and VoiceOver's actions offer too. An
/// appointment of the CRM opens its page in the CRM (Calendar stays in its
/// menu when the calendar has it too); any other opens Calendar, as the
/// official card does.
///
/// Mirrors `NotchCalendarEventRow` in `UI/Notch/NotchCalendarView.swift`:
/// look at both after an official change to the card.
struct ForkCalendarAppointmentRow: View {
    let event: NotchCalendarEvent
    let day: Date
    let now: Date
    let isNext: Bool
    /// Whether the event counts down on its own; nil when it cannot.
    let countdown: Bool?
    /// Drawn as the calendar has it, without its appointment.
    var hidesCRM = false
    @ObservedObject private var model = ForkCalendarAppointments.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var text: NotchCalendarStrings { FeatureStrings.notchCalendar(l10n.language) }
    private var strings: ForkCalendarAppointmentsStrings { .strings(l10n.language) }
    private var link: ForkCalendarVideoLink? { hidesCRM ? model.links[event.id] : model.link(for: event) }
    /// Known only to the CRM: no Calendar event to open.
    private var crmOnly: Bool { event.id.hasPrefix(ForkCalendarAppointmentsSupport.eventPrefix) }
    /// "Open in <CRM>", for an appointment of the CRM.
    private var openInCRM: String? {
        hidesCRM || model.crmURL(for: event) == nil ? nil : model.crmName(ForkMeetingStrings.strings(l10n.language))
    }
    private var openTitle: String { openInCRM ?? text.openCalendar }
    private var ongoing: Bool { !event.allDay && event.start <= now && event.end > now }
    private var ended: Bool { event.end <= now }
    private var copied: Bool { model.copied == event.id }

    var body: some View {
        Button(action: open) { card }
            .buttonStyle(NotchButtonStyle(cornerRadius: 11, lifts: false))
            .help(openTitle)
            .accessibilityHint(openTitle)
            .accessibilityActions { menuItems }
            .overlay(alignment: .bottomTrailing) {
                if let link {
                    actions(link)
                        .padding([.trailing, .bottom], 10)
                }
            }
            .contextMenu { menuItems }
    }

    private func open() {
        if openInCRM != nil { model.openCRM(event) } else { model.openCalendar(event) }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 4) {
            if ongoing || isNext {
                Text(ongoing ? text.ongoing : text.next)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ongoing ? .mint : .white.opacity(0.7))
                    .lineLimit(1)
            }
            Text(event.title.isEmpty ? text.untitled : event.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(ended ? 0.65 : 1))
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Group {
                    if event.allDay {
                        Text(text.allDay)
                    } else if Calendar.current.isDate(event.start, inSameDayAs: day)
                                && Calendar.current.isDate(event.end.addingTimeInterval(-1), inSameDayAs: day) {
                        Text(event.start, format: .dateTime.hour().minute())
                            + Text(" · ") + Text(event.end, format: .dateTime.hour().minute())
                    } else {
                        Text(event.start, format: .dateTime.day().month(.abbreviated).hour().minute())
                            + Text(" → ") + Text(event.end, format: .dateTime.day().month(.abbreviated).hour().minute())
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                // The mark of an event chosen to count down on its own.
                if countdown == true {
                    Image(systemName: "timer")
                        .accessibilityLabel(text.countdown)
                }
            }
            .font(.system(size: 11)).monospacedDigit()
            .foregroundStyle(.white.opacity(0.75))
            Text(event.calendar)
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            if !event.location.isEmpty {
                Label(event.location, systemImage: "mappin")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            if let link { callLine(link) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(event.color.color)
                .frame(width: 3)
                .accessibilityHidden(true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(event.color.color.opacity(ongoing ? 0.2 : 0.1),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(.white.opacity(contrast == .increased ? 0.5 : ongoing ? 0.16 : 0.05), lineWidth: 0.75)
        }
        .clipped()
    }

    /// The service, or "Link Copied" for a moment; the buttons' room is
    /// kept at its end, where they float above the card.
    private func callLine(_ link: ForkCalendarVideoLink) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark.circle.fill" : "video.fill")
                    .accessibilityHidden(true)
                Text(copied ? strings.linkCopied : link.provider.name ?? strings.videoCall)
                    .lineLimit(1)
            }
            .font(.system(size: 10, weight: copied ? .medium : .regular))
            .foregroundStyle(copied ? AnyShapeStyle(.mint) : AnyShapeStyle(.white.opacity(0.6)))
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: copied)
            Spacer(minLength: 0)
            actions(link).hidden().accessibilityHidden(true)
        }
    }

    private func actions(_ link: ForkCalendarVideoLink) -> some View {
        HStack(spacing: 4) {
            if !ended {
                NotchPillButton(title: strings.join, prominent: true) { model.join(event) }
                    .help(link.provider.name ?? strings.videoCall)
                    .accessibilityHint(link.provider.name ?? strings.videoCall)
            }
            NotchIconButton(symbol: copied ? "checkmark" : "link",
                            title: copied ? strings.linkCopied : strings.copyLink) { model.copy(event) }
        }
    }

    /// Join and Copy Link, the countdown of this event, and where it opens.
    @ViewBuilder private var menuItems: some View {
        if link != nil {
            if !ended { Button(strings.join) { model.join(event) } }
            Button(strings.copyLink) { model.copy(event) }
            Divider()
        }
        if let countdown {
            Button(countdown ? text.removeCountdown : text.addCountdown) {
                NotchCalendarService.shared.setCountdown(!countdown, for: event)
            }
            Divider()
        }
        if let openInCRM { Button(openInCRM) { model.openCRM(event) } }
        if !crmOnly { Button(text.openCalendar) { model.openCalendar(event) } }
    }
}

// MARK: - The setting

/// "Show CRM appointments in the island's calendar": in the island's
/// Content tab, under the calendar's options (seam `notch-calendar-crm3`),
/// and in the CRM's block of the Meetings page; the same setting
/// (`fork.meetings.islandAppointments`) in both. Only with the Meetings
/// feature on and a CRM imported: for anyone else, nothing.
struct ForkCalendarAppointmentsSetting: View {
    enum Place {
        /// The island's settings: a row with its icon.
        case island
        /// The Meetings page's form.
        case meetings
    }

    var place: Place = .island
    @ObservedObject private var l10n = L10n.shared
    /// The app's registry; the render harness alone gives its own.
    @ObservedObject var exports = ForkMeetingExports.shared
    @AppStorage(ForkDefaultsKey.meetingsEnabled) private var meetings = false
    @AppStorage(ForkDefaultsKey.meetingsIslandAppointments) private var wanted = true

    var body: some View {
        // Once the CRM can be read: its profile and its token saved.
        if meetings, let config = exports.castralConfig,
           exports.savedSecrets.contains(ForkMeetingExporterConfig.tokenAccount(config.id)) {
            let strings = ForkCalendarAppointmentsStrings.strings(l10n.language)
            let caption = strings.settingCaption(exports.title(config, ForkMeetingStrings.strings(l10n.language)))
            switch place {
            case .island:
                SettingsRow(symbol: "person.crop.rectangle.stack", title: strings.settingTitle, caption: caption) {
                    Toggle(strings.settingTitle, isOn: $wanted).labelsHidden().toggleStyle(.switch)
                }
                Text(strings.callCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, settingsRowTextInset)
            case .meetings:
                Toggle(isOn: $wanted) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(strings.settingTitle)
                        Text(caption + " " + strings.callCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        // Not asked yet this launch: what the Keychain holds, asked off the
        // main thread as the Meetings page does at its display, for a moment.
        if meetings, let config = exports.castralConfig,
           !exports.savedSecrets.contains(ForkMeetingExporterConfig.profileAccount(config.id)) {
            Color.clear.frame(width: 0, height: 0)
                .accessibilityHidden(true)
                .onAppear { if exports.isIdle { exports.refresh() } }
        }
    }
}
