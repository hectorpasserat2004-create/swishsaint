// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import SwiftUI

// MARK: - The page

/// "Import a Profile…" in the page's Add menu: the only trace of a CRM
/// for someone who has none.
enum ForkCastralProfileImport {
    /// The panel, then the import; `done` with what the page says, `nil`
    /// when the panel was cancelled.
    static func choose(_ text: ForkMeetingStrings, done: @escaping (String?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = text.castralProfilePanelMessage
        guard panel.runModal() == .OK, let url = panel.url else { return done(nil) }
        let data: Data
        do {
            let size = (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
            guard size <= ForkCastralProfile.maximumFileBytes else { return done(text.castralProfileRefused("JSON")) }
            data = try Data(contentsOf: url)
        } catch {
            return done(text.castralProfileRefused("JSON"))
        }
        ForkMeetingExports.shared.importCastralProfile(data) { outcome in
            switch outcome {
            case let .imported(_, serverChanged): done(serverChanged ? text.castralServerChanged : nil)
            case let .refused(refusal): done(text.castralProfileRefused(refusal.field))
            case .keychainRefused: done(text.exportFailKeychain)
            case .listUnconfirmed: done(text.exportFailListUnconfirmed)
            }
        }
    }
}

/// The CRM's block on the Meetings page, once its profile is imported: its
/// token (typed once, written at Save), the link's state, who signs, how
/// many speak, when it sends, Test, Remove.
struct ForkCastralRow: View {
    let config: ForkMeetingExporterConfig
    let text: ForkMeetingStrings
    let language: AppLanguage
    let remove: () -> Void

    @ObservedObject private var exports = ForkMeetingExports.shared
    /// Typed once, written to the Keychain at Save, then emptied.
    @State private var newToken = ""
    @State private var problem: String?

    private var profile: ForkCastralProfile? { exports.castralProfiles[config.id] }
    private var name: String { exports.title(config, text) }
    private var hasToken: Bool { exports.savedSecrets.contains(ForkMeetingExporterConfig.tokenAccount(config.id)) }

    var body: some View {
        Label(name, systemImage: "person.crop.rectangle.stack")
            .font(.headline)
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
        Text(text.castralCaption(name))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        if profile == nil, exports.savedSecrets.contains(ForkMeetingExporterConfig.profileAccount(config.id)) == false {
            Text(text.castralFailProfile)
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        LabeledContent(text.castralToken) {
            SecureField(text.castralTokenNew, text: $newToken, prompt: Text(text.castralTokenNew))
                .labelsHidden()
                .multilineTextAlignment(.leading)
                .textFieldStyle(.roundedBorder)
                .onSubmit(saveToken)
                .accessibilityLabel(text.castralTokenNew)
        }
        HStack(alignment: .firstTextBaseline) {
            Text(hasToken ? text.castralTokenSaved : text.castralTokenMissing)
                .font(.caption)
                .foregroundStyle(hasToken ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(text.webhookSave, action: saveToken)
                .disabled(newToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        if let problem {
            Text(problem)
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        LabeledContent(text.castralLinkTitle) {
            HStack(spacing: 8) {
                if exports.castralChecking.contains(config.id) { ProgressView().controlSize(.small) }
                link
                Button(text.castralTest) { exports.testCastral(config.id) }
                    .disabled(!hasToken || exports.castralChecking.contains(config.id))
            }
        }
        if let profile {
            Picker(selection: Binding(get: { config.author ?? "" }, set: { author in
                var next = config
                next.author = author
                exports.update(next)
            })) {
                ForEach(profile.authors, id: \.self) { Text(verbatim: $0).tag($0) }
            } label: {
                Text(text.castralAuthor)
            }
        }
        Stepper(value: Binding(get: { config.speakers ?? ForkCastralContract.defaultSpeakers }, set: { count in
            var next = config
            next.speakers = ForkCastralContract.speakers(count)
            exports.update(next)
        }), in: ForkCastralContract.minimumSpeakers...ForkCastralContract.maximumSpeakers) {
            VStack(alignment: .leading, spacing: 2) {
                Text(text.castralSpeakers(config.speakers ?? ForkCastralContract.defaultSpeakers))
                Text(text.castralSpeakersCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        Picker(selection: Binding(get: { config.mode }, set: { mode in
            var next = config
            next.mode = mode
            exports.update(next)
        })) {
            Text(text.exportModeManual).tag(ForkMeetingExportMode.manual)
            Text(text.exportModeAutomatic).tag(ForkMeetingExportMode.automatic)
        } label: {
            Text(text.exportMode)
        }
        Text(text.castralAutomaticCaption)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        Text(text.castralAudioCaption(minutes: ForkCastralAudioPlan.maximumMinutes(
            limit: profile?.maximumUploadBytes ?? ForkCastralProfile.defaultMaximumUploadBytes)))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        HStack {
            Spacer()
            Button(text.exportRemove, role: .destructive, action: remove)
        }
        .onAppear { exports.testCastral(config.id, unlessCheckedWithin: 60) }
    }

    @ViewBuilder private var link: some View {
        switch exports.castralLinks[config.id] {
        case let .connected(upcoming, at)?:
            Label(text.castralLinkConnected(upcoming), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help(text.castralLinkChecked(ForkMeetingLibraryText.time(at, language: language)))
        case let .tokenRefused(at)?:
            Label(text.castralLinkRefused, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .help(text.castralLinkChecked(ForkMeetingLibraryText.time(at, language: language)))
        case let .offline(at)?:
            Label(text.castralLinkOffline, systemImage: "wifi.slash")
                .foregroundStyle(.orange)
                .help(text.castralLinkChecked(ForkMeetingLibraryText.time(at, language: language)))
        case let .failed(status, at)?:
            Label(text.castralLinkFailed(status), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help(text.castralLinkChecked(ForkMeetingLibraryText.time(at, language: language)))
        case nil:
            Text(text.castralLinkUnchecked).foregroundStyle(.secondary)
        }
    }

    private func saveToken() {
        exports.saveCastralToken(config.id, token: newToken) { change in
            switch change {
            case .saved:
                problem = nil
                newToken = ""
            case .invalid:
                problem = text.castralTokenInvalid
            case .keychainRefused:
                problem = text.webhookSecretRefused
                newToken = ""
            }
        }
    }
}

// MARK: - The library

/// Under the CRM's line in a meeting's detail: where the meeting is there
/// (the stage and its bar), the appointment, the sound sent, the server's
/// own words, "Open in <CRM>".
struct ForkCastralDetail: View {
    let folder: URL
    let config: ForkMeetingExporterConfig
    let text: ForkMeetingStrings
    let language: AppLanguage

    @ObservedObject private var exports = ForkMeetingExports.shared

    var body: some View {
        let key = ForkMeetingExports.key(folder, config.id)
        let record = exports.castralRecords[folder.standardizedFileURL.path].flatMap { $0.target == config.id ? $0 : nil }
        VStack(alignment: .leading, spacing: 3) {
            if let status = exports.castralStatus(folder), status.failure == nil || exports.pending.contains(key) {
                HStack(spacing: 6) {
                    Text(phase(status.phase))
                        .foregroundStyle(status.phase == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    if let share = status.progress, status.phase.isWorking {
                        ProgressView(value: share)
                            .frame(maxWidth: 120)
                            .accessibilityLabel(phase(status.phase))
                    }
                }
            }
            if let record {
                if let line = booking(record) { Text(line).foregroundStyle(.secondary) }
                if let format = record.format, let bytes = record.bytes {
                    Text(text.castralSound(kilohertz: format.kilohertz,
                                           size: ForkMeetingLiveText.size(bytes, language: language)))
                        .foregroundStyle(.secondary)
                }
                if let warning = record.warning { Text(warning).foregroundStyle(.orange) }
                if record.stage == .failed, let error = record.error { Text(error).foregroundStyle(.red) }
                // The sound is there: only the server's own retry (S1).
                if ForkCastralSteps.allowsRetry(record) {
                    Button(text.exportRetry) { exports.export(folder, to: config.id) }
                        .controlSize(.small)
                        .disabled(exports.pending.contains(key) || exports.listChanged)
                }
            }
            if let said = exports.castralSaid[key] { Text(said).foregroundStyle(.secondary) }
            if let url = exports.castralDashboard(folder) {
                Link(text.castralOpen(exports.title(config, text)), destination: url)
            }
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
        .task(id: folder.standardizedFileURL.path) {
            // Asked again at each look, when the follow had stopped.
            guard let record, record.step == .started, !record.isSettled else { return }
            exports.castralTracker.follow(folder, target: config.id)
        }
    }

    private func phase(_ phase: ForkCastralPhase) -> String {
        switch phase {
        case let .sending(share):
            return share.map { text.castralPhaseSendingShare(Int(($0 * 100).rounded())) } ?? text.castralPhaseSending
        case .waitingForSound: return text.castralPhaseWaiting
        case .queued: return text.castralPhaseQueued
        case .transcribing: return text.castralPhaseTranscribing
        case .summarizing: return text.castralPhaseSummarizing
        case .ready: return text.castralPhaseReady
        case .readyWithoutReport: return text.castralPhaseReadyWithoutReport
        case .failed: return text.castralPhaseFailed
        case .stillWorking: return text.castralPhaseStillWorking
        }
    }

    private func booking(_ record: ForkCastralRecord) -> String? {
        guard record.booking != nil else { return nil }
        let who = record.companyName ?? text.castralNoCompany
        let when = record.bookingStart.map { ForkMeetingLibraryText.time($0, language: language) } ?? ""
        let line = when.isEmpty ? text.castralBooking(who) : text.castralBooking("\(who) · \(when)")
        switch record.rule {
        case .meetCode?: return "\(line) · \(text.castralRuleMeetCode)"
        case .overlap?: return "\(line) · \(text.castralRuleOverlap)"
        case .closest?, .chosen?, nil: return line
        }
    }
}

/// The phase in a few words, for the island's Meetings page (lot G): 28
/// characters at most.
extension ForkCastralStatus {
    func short(_ text: ForkMeetingStrings) -> String {
        switch phase {
        case let .sending(share):
            return share.map { text.castralPhaseSendingShare(Int(($0 * 100).rounded())) } ?? text.castralPhaseSending
        case .waitingForSound: return text.castralPhaseWaiting
        case .queued: return text.castralPhaseQueued
        case .transcribing: return text.castralPhaseTranscribing
        case .summarizing: return text.castralPhaseSummarizing
        case .ready: return text.castralPhaseReady
        case .readyWithoutReport: return text.castralPhaseReadyWithoutReport
        case .failed: return failure == nil ? text.castralPhaseFailed : text.exportFailedShort
        case .stillWorking: return text.castralPhaseStillWorking
        }
    }

    var symbol: String {
        switch phase {
        case .ready: return "checkmark.circle.fill"
        case .readyWithoutReport: return "exclamationmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        default: return "arrow.up.circle"
        }
    }
}

// MARK: - The choice

/// Which appointment the meeting was: those around it in the CRM, the
/// likeliest chosen; a badge for one with a report already (the new one
/// replaces it) or without a company; and, when the recording is much
/// shorter than the appointment, what was not recorded.
struct ForkCastralChoiceSheet: View {
    let choice: ForkCastralChoice
    let text: ForkMeetingStrings
    let language: AppLanguage

    @ObservedObject private var exports = ForkMeetingExports.shared
    @State private var selected: String?
    @State private var complement = ""

    private var current: ForkCastralChoice { exports.castralChoice?.id == choice.id ? exports.castralChoice ?? choice : choice }

    var body: some View {
        let shown = current
        VStack(alignment: .leading, spacing: 12) {
            Text(text.castralChooseTitle(shown.name))
                .font(.headline)
            Text(text.castralChooseCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if shown.loading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(text.castralChooseLoading).foregroundStyle(.secondary)
                }
            } else if let failure = shown.failure {
                Text(failure.message(text))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if shown.bookings.isEmpty {
                Text(text.castralChooseEmpty).foregroundStyle(.secondary)
            } else {
                List(shown.bookings, selection: $selected) { booking in
                    row(booking).tag(booking.id)
                }
                .frame(minHeight: 140, maxHeight: 260)
                if let booking = shown.bookings.first(where: { $0.id == selected }),
                   ForkCastralMatch.suggestsComplement(recordedSeconds: shown.recordedSeconds, booking: booking) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(text.castralComplement)
                        TextEditor(text: $complement)
                            .font(.callout)
                            .frame(minHeight: 60, maxHeight: 120)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                            .accessibilityLabel(text.castralComplement)
                        Text(text.castralComplementCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack {
                Spacer()
                Button(text.cancel, role: .cancel) { exports.castralChoice = nil }
                    .keyboardShortcut(.cancelAction)
                Button(text.castralSend) {
                    if let selected { exports.confirmCastralChoice(shown, booking: selected, complement: complement) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected == nil || shown.loading)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onChange(of: shown.proposed) { _, proposed in if selected == nil { selected = proposed } }
        .onAppear { if selected == nil { selected = shown.proposed } }
    }

    private func row(_ booking: ForkCastralContract.Booking) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: booking.company?.name ?? booking.attendeeName ?? text.castralNoCompany)
            HStack(spacing: 6) {
                if let start = booking.startAt {
                    Text(when(start, timeZone: booking.timeZone)).foregroundStyle(.secondary)
                }
                if booking.hasReport {
                    Text(text.castralBadgeReported).foregroundStyle(.orange)
                }
                if booking.company?.id == nil {
                    Text(text.castralNoCompany).foregroundStyle(.orange)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
    }

    /// "10:00", and the prospect's own time when they booked in another
    /// zone (B8): "10:00 · 16:00 their time".
    private func when(_ date: Date, timeZone: String?) -> String {
        var calendar = Calendar.current
        let here = ForkMeetingLibraryText.longDate(date, language: language, calendar: calendar)
        guard let name = timeZone, let zone = TimeZone(identifier: name),
              zone.secondsFromGMT(for: date) != calendar.timeZone.secondsFromGMT(for: date) else { return here }
        calendar.timeZone = zone
        return "\(here) · \(text.castralTheirTime(ForkMeetingLibraryText.time(date, language: language, calendar: calendar)))"
    }
}
