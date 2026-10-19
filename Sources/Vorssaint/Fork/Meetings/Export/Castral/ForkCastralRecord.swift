// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Why a meeting did not go to the CRM, beside the exports' own failures.
/// Its `code` is what `meeting.json` keeps (`exports[].reason`, after
/// `castral.`): stable names, new ones only added.
enum ForkCastralFailure: Equatable {
    /// No appointment around the meeting.
    case noBooking
    /// On its own: several could match, or none surely.
    case uncertain
    /// On its own: the appointment has no company in the CRM.
    case orphan
    /// On its own: the appointment already has a report.
    case alreadyReported
    /// On its own: a deposit of the appointment is already on its way.
    case alreadyDeposited
    /// The profile is not in the Keychain, or no longer reads.
    case profile
    /// The author set is not one the profile names.
    case author
    /// The CRM refused the token (401).
    case tokenRefused
    /// The CRM refused the deposit (4xx): its sentence is in the record.
    case rejected
    /// The longest meeting the server takes, in minutes.
    case tooLong(maximumMinutes: Int)
    /// The CRM gave an upload address outside its profile.
    case uploadHost
    /// The sound did not reach the storage.
    case storage
    /// The CRM says the sound never arrived (409 at the start).
    case notArrived
    /// The sound could not be written as FLAC.
    case encoding

    var code: String {
        switch self {
        case .noBooking: return "noBooking"
        case .uncertain: return "uncertain"
        case .orphan: return "orphan"
        case .alreadyReported: return "alreadyReported"
        case .alreadyDeposited: return "alreadyDeposited"
        case .profile: return "profile"
        case .author: return "author"
        case .tokenRefused: return "tokenRefused"
        case .rejected: return "rejected"
        case let .tooLong(minutes): return "tooLong.\(minutes)"
        case .uploadHost: return "uploadHost"
        case .storage: return "storage"
        case .notArrived: return "notArrived"
        case .encoding: return "encoding"
        }
    }

    /// Read back; a code this version does not know is `nil`.
    init?(code: String) {
        switch code {
        case "noBooking": self = .noBooking
        case "uncertain": self = .uncertain
        case "orphan": self = .orphan
        case "alreadyReported": self = .alreadyReported
        case "alreadyDeposited": self = .alreadyDeposited
        case "profile": self = .profile
        case "author": self = .author
        case "tokenRefused": self = .tokenRefused
        case "rejected": self = .rejected
        case "uploadHost": self = .uploadHost
        case "storage": self = .storage
        case "notArrived": self = .notArrived
        case "encoding": self = .encoding
        default:
            guard code.hasPrefix("tooLong."), let minutes = Int(code.dropFirst("tooLong.".count)),
                  (5...10_000).contains(minutes) else { return nil }
            self = .tooLong(maximumMinutes: minutes)
        }
    }

    /// Fixed by choosing the appointment by hand (Export To, Retry).
    var needsChoice: Bool { [.noBooking, .uncertain, .orphan, .alreadyReported, .alreadyDeposited].contains(self) }
}

/// Where a meeting is in the CRM, kept in its `meeting.json` (`castral`),
/// one deposit per meeting. The local steps are written as they happen, so
/// a quit at any moment resumes where it stopped (B3, B5):
///
/// ```
/// (none) ──POST──► uploading ──PUT 200──► uploaded ──start──► started ──status──► ready | failed
///                    │ quit: PUT again on the same address (< 2 h),             │
///                    │ else DELETE that deposit and open a new one              └─ failed: retry
///                    └ (never `retry`: the sound is not there, S1)
/// ```
/// The upload address itself, which lets anyone write the sound, stays in
/// the Keychain; here, only when it was given.
struct ForkCastralRecord: Equatable {
    enum Step: String, CaseIterable {
        case uploading
        case uploaded
        case started
    }

    /// The exporter it went with.
    var target: String
    var step: Step
    /// The deposit's id on the server.
    var deposit: String
    var booking: String?
    var company: String?
    var companyName: String?
    var bookingStart: Date?
    var rule: ForkCastralMatch.Rule?
    var format: ForkCastralAudioPlan.Format?
    var bytes: Int64?
    var seconds: Double?
    /// When the upload address was given: it is valid two hours.
    var openedAt: Date?
    var startedAt: Date?
    var engine: String?
    var stage: ForkCastralContract.Stage?
    var progress: Int?
    /// The server's sentences, written for a person, in its language.
    var error: String?
    var warning: String?
    var hasSummary = false
    var checkedAt: Date?
    var preserved: [String: ForkMeetingJSON] = [:]

    private static let known: Set<String> = [
        "target", "step", "deposit", "booking", "company", "companyName", "bookingStart", "rule", "format", "bytes",
        "seconds", "openedAt", "startedAt", "engine", "stage", "progress", "error", "warning", "hasSummary", "checkedAt",
    ]

    init(target: String, step: Step, deposit: String) {
        self.target = target
        self.step = step
        self.deposit = deposit
    }

    /// `nil` for none, or one this version cannot read.
    init?(json: ForkMeetingJSON?) {
        guard case let .object(object)? = json, case let .string(target)? = object["target"],
              case let .string(rawStep)? = object["step"], let step = Step(rawValue: rawStep),
              case let .string(deposit)? = object["deposit"], ForkCastralContract.isID(deposit) else { return nil }
        self.target = target
        self.step = step
        self.deposit = deposit
        func string(_ key: String) -> String? {
            if case let .string(value)? = object[key], !value.isEmpty { return value }
            return nil
        }
        func number(_ key: String) -> Double? {
            if case let .number(value)? = object[key], value.isFinite, value >= 0 { return value }
            return nil
        }
        func date(_ key: String) -> Date? { string(key).flatMap(ForkCastralContract.date) }
        booking = string("booking")
        company = string("company")
        companyName = string("companyName")
        bookingStart = date("bookingStart")
        rule = string("rule").flatMap(ForkCastralMatch.Rule.init(rawValue:))
        format = string("format").flatMap(ForkCastralAudioPlan.Format.init(rawValue:))
        bytes = number("bytes").map { Int64(min($0, 1e15)) }
        seconds = number("seconds")
        openedAt = date("openedAt")
        startedAt = date("startedAt")
        engine = string("engine")
        stage = string("stage").flatMap(ForkCastralContract.Stage.init(rawValue:))
        progress = number("progress").map { min(100, Int($0)) }
        error = string("error")
        warning = string("warning")
        if case let .bool(value)? = object["hasSummary"] { hasSummary = value }
        checkedAt = date("checkedAt")
        preserved = object.filter { !Self.known.contains($0.key) }
    }

    var json: ForkMeetingJSON {
        var object = preserved
        func text(_ key: String, _ value: String?) { object[key] = value.map(ForkMeetingJSON.string) }
        func instant(_ key: String, _ value: Date?) { text(key, value.map { ISO8601DateFormatter().string(from: $0) }) }
        func figure(_ key: String, _ value: Double?) { object[key] = value.map(ForkMeetingJSON.number) }
        text("target", target)
        text("step", step.rawValue)
        text("deposit", deposit)
        text("booking", booking)
        text("company", company)
        text("companyName", companyName)
        instant("bookingStart", bookingStart)
        text("rule", rule?.rawValue)
        text("format", format?.rawValue)
        figure("bytes", bytes.map(Double.init))
        figure("seconds", seconds)
        instant("openedAt", openedAt)
        instant("startedAt", startedAt)
        text("engine", engine)
        text("stage", stage?.rawValue)
        figure("progress", progress.map(Double.init))
        text("error", error)
        text("warning", warning)
        object["hasSummary"] = hasSummary ? .bool(true) : nil
        instant("checkedAt", checkedAt)
        return .object(object)
    }

    /// The server said what became of it; nothing more to ask.
    var isSettled: Bool { step == .started && stage?.isTerminal == true }

    /// A status read: the stage and what comes with it.
    mutating func apply(_ status: ForkCastralContract.Status, at date: Date) {
        if let stage = status.stage { self.stage = stage }
        progress = status.progress ?? status.stage?.progress ?? progress
        error = status.error
        warning = status.warning
        if let engine = status.engine { self.engine = engine }
        if let id = status.companyID { company = id }
        if let name = status.companyName { companyName = name }
        hasSummary = status.hasSummary
        checkedAt = date
    }
}

// MARK: - What comes next

/// What a send does with what the last attempt left, so that nothing is
/// opened twice, sent twice or paid twice.
enum ForkCastralSteps {
    enum Action: Equatable {
        /// Nothing of this exporter yet: choose the appointment, write the
        /// sound, open a deposit.
        case open
        /// The sound did not finish leaving: send it again to the same
        /// address, still valid (B3).
        case upload
        /// The address is over or gone: that deposit goes, a new one opens.
        case reopen(abandoned: String)
        /// The sound is there: only `start`, which the server takes twice
        /// without harm (B5).
        case start
        /// The server failed it, the sound being there: `retry` (S1).
        case retry
        /// Sent: nothing to send again, only its status to ask.
        case follow
    }

    /// Margin kept before an upload address expires: a send of an hour of
    /// sound does not begin at its last minute.
    static let uploadMargin: TimeInterval = 10 * 60

    /// - `hasAddress`: the Keychain still has the deposit's upload address.
    static func next(_ record: ForkCastralRecord?, target: String, hasAddress: Bool, now: Date) -> Action {
        guard let record, record.target == target else { return .open }
        switch record.step {
        case .uploading:
            let fresh = record.openedAt.map {
                now.timeIntervalSince($0) < ForkCastralContract.uploadLifetime - uploadMargin && now >= $0
            } ?? false
            return hasAddress && fresh ? .upload : .reopen(abandoned: record.deposit)
        case .uploaded:
            return .start
        case .started:
            return record.stage == .failed ? .retry : .follow
        }
    }

    /// `retry` only once the sound reached the storage (S1): a deposit still
    /// uploading would be queued without its sound, and billed again.
    static func allowsRetry(_ record: ForkCastralRecord?) -> Bool {
        guard let record else { return false }
        return record.step == .started && record.stage == .failed
    }

    /// What a `PUT` answer means.
    enum Upload: Equatable {
        case done
        /// The address is no longer valid: a new deposit is needed.
        case expired
        case failed
    }

    /// - A `2xx` is the sound stored.
    /// - The storage takes one object per address, never twice: "already
    ///   exists" is an earlier send that arrived without its answer; the
    ///   start checks it is really there.
    /// - An expired or unknown signature asks for a new address.
    static func upload(status: Int, body: String?) -> Upload {
        if (200..<300).contains(status) { return .done }
        let said = (body ?? "").lowercased()
        if status == 409 || said.contains("already exists") || said.contains("duplicate") { return .done }
        if [400, 401, 403].contains(status), said.contains("expired") || said.contains("jwt") || said.contains("signature") {
            return .expired
        }
        return .failed
    }

    // MARK: - Following

    /// How long to wait before asking the status again: every 4 s at first,
    /// as the contract advises (never under 2 s), then every 10 s, then 30 s.
    static func pollDelay(sinceStart elapsed: TimeInterval) -> TimeInterval {
        if elapsed < 120 { return 4 }
        if elapsed < 600 { return 10 }
        return 30
    }

    /// How long the status is asked before leaving it for a later look: a
    /// batch engine (the contract's, past 70 minutes of sound) may stay on
    /// "transcribing" a long while.
    static func followBudget(engine: String?) -> TimeInterval {
        engine?.lowercased().hasSuffix("batch") == true ? 2 * 3600 : 30 * 60
    }

    /// Network failures in a row before the follow waits for a later look.
    static let toleratedFailures = 5
}

// MARK: - Said

/// The state of a meeting in the CRM, as the detail, the island's Meetings
/// page and the notices say it.
enum ForkCastralPhase: Equatable {
    /// The sound leaves: its share sent, when known.
    case sending(Double?)
    case waitingForSound
    case queued
    case transcribing
    case summarizing
    case ready
    /// Transcribed, but no report: the server's warning says why.
    case readyWithoutReport
    case failed
    /// Asked long enough for now: asked again at the next look.
    case stillWorking

    init(record: ForkCastralRecord, followed: Bool = true) {
        switch record.step {
        case .uploading: self = .sending(nil)
        case .uploaded: self = .waitingForSound
        case .started:
            switch record.stage {
            case .upload?: self = .waitingForSound
            case .queued?, nil: self = followed ? .queued : .stillWorking
            case .transcribing?: self = followed ? .transcribing : .stillWorking
            case .summarizing?: self = followed ? .summarizing : .stillWorking
            case .ready?: self = record.hasSummary || record.warning == nil ? .ready : .readyWithoutReport
            case .failed?: self = .failed
            }
        }
    }

    /// The server's share for the bar, `nil` when there is none.
    func progress(_ record: ForkCastralRecord?) -> Double? {
        switch self {
        // The share of the sound sent, not the server's scale.
        case let .sending(share): return share
        case .ready, .readyWithoutReport, .failed: return nil
        default: return record?.progress.map { Double($0) / 100 }
        }
    }

    var isWorking: Bool {
        switch self {
        case .ready, .readyWithoutReport, .failed, .stillWorking: return false
        default: return true
        }
    }
}
