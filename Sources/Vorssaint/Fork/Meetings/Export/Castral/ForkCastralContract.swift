// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The recorder contract's messages, as the server writes them, read
/// **leniently**: a field missing or of another shape is `nil`, one
/// appointment that does not read is skipped, never the whole list (an
/// unnamed company, B10, used to empty it).
///
/// ```
/// GET  api/transcriptions/targets?from&to   the appointments around then
/// POST api/transcriptions                   {id, engine, upload{url}}
/// PUT  <upload.url>                         the sound, straight to the storage
/// POST api/transcriptions/<id>/start        idempotent
/// GET  api/transcriptions/<id>/status       upload 10 → queued 25 → transcribing 55
///                                           → summarizing 85 → ready | failed
/// POST api/transcriptions/<id>/retry        only once the sound is there (S1)
/// DELETE api/transcriptions/<id>            only a deposit still uploading or failed
/// ```
/// Every error is `{"error": "<a sentence>"}`.
enum ForkCastralContract {
    static let targetsPath = "api/transcriptions/targets"
    static let createPath = "api/transcriptions"
    static func startPath(_ id: String) -> String { "api/transcriptions/\(id)/start" }
    static func statusPath(_ id: String) -> String { "api/transcriptions/\(id)/status" }
    static func retryPath(_ id: String) -> String { "api/transcriptions/\(id)/retry" }
    static func depositPath(_ id: String) -> String { "api/transcriptions/\(id)" }

    static let maximumSpeakers = 6
    static let minimumSpeakers = 2
    static let defaultSpeakers = 3
    /// What the server takes of `summary_complement`, in JavaScript's
    /// length: UTF-16 code units.
    static let maximumComplementUnits = 20_000
    /// How long an upload address stays valid.
    static let uploadLifetime: TimeInterval = 2 * 3600

    /// An id the routes take: a UUID, in any case.
    static func isID(_ text: String) -> Bool {
        text.count == 36 && UUID(uuidString: text) != nil
    }

    /// An ISO 8601 instant as Postgres and JavaScript write it: `Z` or an
    /// offset, with or without fractions of a second (up to the
    /// microseconds Postgres keeps).
    static func date(_ value: Any?) -> Date? {
        guard var text = value as? String, !text.isEmpty else { return nil }
        if let dot = text.firstIndex(of: "."), let end = text[dot...].firstIndex(where: { !$0.isNumber && $0 != "." }) {
            text.removeSubrange(dot..<end)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    // MARK: - Targets

    struct Company: Equatable {
        var id: String?
        /// Optional: the column is nullable (B10).
        var name: String?
        var domain: String?
    }

    /// What was already deposited on an appointment.
    struct Deposit: Equatable {
        var id: String?
        var stage: String?
        var hasSummary = false
    }

    struct Booking: Equatable, Identifiable {
        var id: String
        var startAt: Date?
        var endAt: Date?
        /// The time zone the prospect booked in: not this Mac's.
        var timeZone: String?
        var status: String?
        var isActive: Bool?
        var meetingURL: String?
        var attendeeName: String?
        var detectedDomain: String?
        var company: Company?
        var deposits: [Deposit] = []

        /// Only a cancelled appointment, or one the prospect missed, takes
        /// nothing (B1): a rescheduled one is the same row at its new time,
        /// alive. The server's own reading (`is_active`) wins over a list
        /// copied here.
        var isBlocked: Bool {
            if isActive == false { return true }
            return ["cancelled", "no_show"].contains(status?.lowercased() ?? "")
        }

        /// Already has a report: only a deposit `ready`, or with its summary,
        /// counts (B4); the choice's badge. A failed one does not.
        var hasReport: Bool {
            deposits.contains { $0.stage == Stage.ready.rawValue || $0.hasSummary }
        }

        /// Has a deposit that did not fail, at any stage: a sound on its way
        /// (uploading, queued, transcribing, summarizing) or done. Nothing
        /// goes there on its own: it would be transcribed, and billed, twice.
        var hasDeposit: Bool {
            deposits.contains { $0.stage != Stage.failed.rawValue }
        }

        /// The Google Meet code of its link.
        var meetCode: String? { meetingURL.flatMap(ForkMeetingTitleRules.meetCode(inLink:)) }

        /// Who it is with: the company, else the person who booked.
        var who: String? {
            company?.name ?? attendeeName
        }
    }

    /// `targets`: its appointments, those that read; `nil` for an answer
    /// that is not that shape at all.
    static func bookings(_ data: Data) -> [Booking]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = object["bookings"] as? [Any] else { return nil }
        return list.compactMap { item in
            guard let row = item as? [String: Any], let id = row["booking_id"] as? String, isID(id) else { return nil }
            var booking = Booking(id: id.lowercased())
            booking.startAt = date(row["start_at"])
            booking.endAt = date(row["end_at"])
            booking.timeZone = text(row["timezone"])
            booking.status = text(row["status"])
            booking.isActive = row["is_active"] as? Bool
            booking.meetingURL = text(row["meeting_url"])
            booking.attendeeName = text(row["attendee_name"])
            booking.detectedDomain = text(row["detected_domain"])
            if let company = row["company"] as? [String: Any] {
                booking.company = Company(id: (company["id"] as? String).flatMap { isID($0) ? $0.lowercased() : nil },
                                          name: text(company["nom"]), domain: text(company["domain"]))
            }
            booking.deposits = (row["transcriptions"] as? [Any] ?? []).compactMap { item in
                guard let deposit = item as? [String: Any] else { return nil }
                return Deposit(id: deposit["id"] as? String, stage: text(deposit["stage"]),
                               hasSummary: deposit["has_summary"] as? Bool ?? false)
            }
            return booking
        }
    }

    /// A string worth showing: trimmed, not empty, bounded.
    static func text(_ value: Any?, maximum: Int = 300) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        let visible = String(String.UnicodeScalarView(text.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) || $0 == "\n"
        }))
        return visible.count > maximum ? String(visible.prefix(maximum)) + "…" : visible
    }

    // MARK: - A deposit

    /// The body of `POST api/transcriptions`.
    struct Opening: Equatable {
        var bookingID: String
        var fileName: String
        var mimeType: String
        var bytes: Int64
        var durationMilliseconds: Int64
        var speakers: Int
        var author: String
        var complement: String?

        func body() -> Data {
            var object: [String: Any] = [
                "source_type": "booking", "booking_id": bookingID, "filename": fileName, "mime_type": mimeType,
                "size_bytes": NSNumber(value: bytes), "audio_duration_ms": NSNumber(value: max(1, durationMilliseconds)),
                "max_speakers": NSNumber(value: ForkCastralContract.speakers(speakers)), "created_by": author,
            ]
            if let complement = ForkCastralContract.complement(complement) { object["summary_complement"] = complement }
            return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        }
    }

    static func speakers(_ count: Int) -> Int { min(maximumSpeakers, max(minimumSpeakers, count)) }

    /// What the meeting did not record, as the server takes it: trimmed,
    /// cut at its limit counted as JavaScript counts (UTF-16), never in the
    /// middle of a character (B8); `nil` when nothing is left.
    static func complement(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        guard trimmed.utf16.count > maximumComplementUnits else { return trimmed }
        var kept = ""
        var units = 0
        for character in trimmed {
            let size = String(character).utf16.count
            guard units + size <= maximumComplementUnits else { break }
            kept.append(character)
            units += size
        }
        return kept.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The answer of `POST api/transcriptions`.
    struct Opened: Equatable {
        var id: String
        var engine: String?
        var uploadURL: URL
    }

    static func opened(_ data: Data) -> Opened? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? String, isID(id),
              let upload = object["upload"] as? [String: Any], let text = upload["url"] as? String,
              let url = URL(string: text) else { return nil }
        return Opened(id: id.lowercased(), engine: object["engine"] as? String, uploadURL: url)
    }

    // MARK: - Status

    /// The server's single stage, the one to show.
    enum Stage: String, CaseIterable {
        case upload, queued, transcribing, summarizing, ready, failed

        var isTerminal: Bool { self == .ready || self == .failed }

        /// The server's own share, indicative.
        var progress: Int {
            switch self {
            case .upload: return 10
            case .queued: return 25
            case .transcribing: return 55
            case .summarizing: return 85
            case .ready, .failed: return 100
            }
        }
    }

    struct Status: Equatable {
        var stage: Stage?
        var progress: Int?
        var error: String?
        var warning: String?
        var engine: String?
        var companyID: String?
        var companyName: String?
        var hasSummary = false
    }

    static func status(_ data: Data) -> Status? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = object["stage"] as? String else { return nil }
        var status = Status(stage: Stage(rawValue: raw))
        if let number = object["progress"] as? NSNumber { status.progress = min(100, max(0, number.intValue)) }
        status.error = text(object["error"])
        status.warning = text(object["warning"])
        status.engine = text(object["engine"], maximum: 40)
        if let company = object["company"] as? [String: Any] {
            status.companyID = (company["id"] as? String).flatMap { isID($0) ? $0.lowercased() : nil }
            status.companyName = text(company["nom"], maximum: 120)
        }
        if let summary = object["summary"], !(summary is NSNull) { status.hasSummary = true }
        return status
    }

    /// `{"error": "…"}`: the server's sentence, written for a person.
    static func errorMessage(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return text(object["error"])
    }
}
