// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// What the CRM export promises (W2 H): a profile is all it knows of a
/// server, checked field by field; a meeting goes to its own appointment,
/// on its own only when sure; its sound fits the server or is refused
/// before anything opens; each step is kept so a quit never sends twice,
/// and the server's retry only follows a sound that arrived. Every value
/// here is made up (`example.test`): no server is named.
enum ForkMeetingCastralTests {
    static func run(_ suite: TestSuite) {
        profile(suite)
        profileRefusals(suite)
        addresses(suite)
        targets(suite)
        deposit(suite)
        matching(suite)
        automatic(suite)
        audio(suite)
        steps(suite)
        record(suite)
        failures(suite)
        configs(suite)
        texts(suite)
    }

    // MARK: - Fixtures

    static let profileObject: [String: Any] = [
        "kind": "castral-recorder/1",
        "baseURL": "https://crm.example.test/",
        "uploadHost": "storage-1234.example.test",
        "tokenHeader": "x-example-recorder-token",
        "authors": ["Alice", "Bob"],
        "filenamePrefix": "Call_",
        "dashboardPath": "/records/company/{company}",
        "name": "Example CRM",
    ]

    static func json(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }

    static func profile(_ changes: [String: Any?] = [:]) -> Result<ForkCastralProfile, ForkCastralProfile.Refusal> {
        var object = profileObject
        for (key, value) in changes { object[key] = value }
        return ForkCastralProfile.parse(json(object))
    }

    static let good: ForkCastralProfile = try! profile().get()

    static let iso = ISO8601DateFormatter()
    static func at(_ text: String) -> Date { iso.date(from: text)! }

    static func booking(_ id: Int, start: String, end: String? = nil, url: String? = nil, status: String = "scheduled",
                        active: Bool? = true, company: Bool = true, deposits: [[String: Any]] = []) -> [String: Any] {
        var row: [String: Any] = [
            "booking_id": String(format: "00000000-0000-4000-8000-%012d", id), "start_at": start, "status": status,
            "attendee_name": "Guest \(id)", "transcriptions": deposits, "timezone": "Europe/Paris",
        ]
        if let end { row["end_at"] = end }
        if let url { row["meeting_url"] = url }
        if let active { row["is_active"] = active }
        if company {
            row["company"] = ["id": String(format: "11111111-0000-4000-8000-%012d", id), "nom": "Company \(id)",
                              "domain": "company\(id).example.test"]
        }
        return row
    }

    static func bookings(_ rows: [[String: Any]]) -> [ForkCastralContract.Booking] {
        ForkCastralContract.bookings(json(["bookings": rows]))!
    }

    // MARK: - Profile

    private static func profile(_ suite: TestSuite) {
        suite.expect(good.baseURL.absoluteString == "https://crm.example.test" && good.uploadHost == "storage-1234.example.test"
                        && good.tokenHeader == "x-example-recorder-token" && good.authors == ["Alice", "Bob"]
                        && good.filenamePrefix == "Call_" && good.displayName == "Example CRM"
                        && good.maximumUploadBytes == ForkCastralProfile.defaultMaximumUploadBytes,
                     "a profile reads whole: its address without a final slash, the storage's exact host, the header, the authors")
        suite.expect(ForkCastralProfile.defaultMaximumUploadBytes == 50_000_000,
                     "without its own cap, a profile takes the lower of the two caps measured on the server: 50 000 000 bytes")
        suite.expect(ForkCastralProfile.parse(good.encoded()) == .success(good),
                     "what the Keychain keeps reads back as the same profile")
        suite.expect((try? profile(["name": nil]).get())?.displayName == "crm.example.test",
                     "a profile without a name is called after its host")
        suite.expect((try? profile(["maxUploadBytes": 200_000_000]).get())?.maximumUploadBytes == 200_000_000,
                     "a profile may raise the cap, once the server takes more")
        suite.expect((try? profile(["uploadHost": "Storage.Example.Test:8443"]).get())?.uploadHost == "storage.example.test:8443",
                     "the upload host is compared in lower case, with its port")
    }

    private static func profileRefusals(_ suite: TestSuite) {
        let refused: [(String, [String: Any?], String)] = [
            ("kind", ["kind": "castral-recorder/2"], "a profile of another version"),
            ("baseURL", ["baseURL": "http://crm.example.test"], "a CRM in plain HTTP"),
            ("baseURL", ["baseURL": "https://user:pass@crm.example.test"], "an address with a user in it"),
            ("baseURL", ["baseURL": "https://crm.example.test/#x"], "an address with a fragment"),
            ("baseURL", ["baseURL": "https://crm.example.test/?a=1"], "an address with a query"),
            ("baseURL", ["baseURL": "https://сrm.example.test"], "a host with a lookalike letter"),
            ("uploadHost", ["uploadHost": "https://storage.example.test"], "an upload host written as an address"),
            ("uploadHost", ["uploadHost": "storage.example.test/x"], "an upload host with a path"),
            ("uploadHost", ["uploadHost": nil], "no upload host"),
            ("tokenHeader", ["tokenHeader": "Authorization"], "a header the system sets"),
            ("tokenHeader", ["tokenHeader": "cookie"], "the cookie header"),
            ("tokenHeader", ["tokenHeader": "x-token\r\nx-other: 1"], "a header with a line break"),
            ("tokenHeader", ["tokenHeader": "x token"], "a header with a space"),
            ("authors", ["authors": []], "no author"),
            ("authors", ["authors": ["Alice", "Alice"]], "the same author twice"),
            ("authors", ["authors": ["Al\nice"]], "an author with a line break"),
            ("authors", ["authors": [String(repeating: "a", count: 41)]], "an author too long"),
            ("filenamePrefix", ["filenamePrefix": "../x"], "a file name prefix with a path in it"),
            ("filenamePrefix", ["filenamePrefix": 3], "a file name prefix that is not text"),
            ("dashboardPath", ["dashboardPath": "sales/{company}"], "a link path without its first slash"),
            ("dashboardPath", ["dashboardPath": "/sales/../admin"], "a link path climbing up"),
            ("dashboardPath", ["dashboardPath": "/s?id={company}"], "a link path with a query"),
            ("dashboardPath", ["dashboardPath": "/s/{other}"], "a link path with another placeholder"),
            ("name", ["name": "A name far too long here"], "a name longer than 16 characters"),
            ("maxUploadBytes", ["maxUploadBytes": 900_000_000], "a cap beyond 500 MB"),
            ("maxUploadBytes", ["maxUploadBytes": true], "a cap that is a boolean"),
        ]
        for (field, changes, what) in refused {
            suite.expect(profile(changes) == .failure(field == "kind" ? .kind : .field(field)),
                         "refused, naming \(field): \(what)")
        }
        suite.expect(ForkCastralProfile.parse(Data("[]".utf8)) == .failure(.unreadable)
                        && ForkCastralProfile.parse(Data(count: ForkCastralProfile.maximumFileBytes + 1)) == .failure(.unreadable),
                     "a file that is not a JSON object, or too large, is no profile")
    }

    private static func addresses(_ suite: TestSuite) {
        suite.expect(good.endpoint(ForkCastralContract.targetsPath)?.absoluteString == "https://crm.example.test/api/transcriptions/targets",
                     "the contract's paths follow the CRM's address")
        let company = "11111111-0000-4000-8000-000000000001"
        suite.expect(good.dashboardURL(companyID: company)?.absoluteString == "https://crm.example.test/records/company/\(company)"
                        && (try? profile(["dashboardPath": "/leads/"]).get())?.dashboardURL(companyID: company)?.absoluteString
                            == "https://crm.example.test/leads/\(company)",
                     "the company's record: its id in the placeholder, or after the path")
        suite.expect(good.dashboardURL(companyID: "../../admin") == nil && good.dashboardURL(companyID: "x") == nil,
                     "an id that is not one makes no link")
        let upload = { (text: String) in good.allowsUpload(to: URL(string: text)!) }
        suite.expect(upload("https://storage-1234.example.test/storage/v1/object/upload/sign/x?token=abc")
                        && upload("https://crm.example.test/upload"),
                     "the sound may go to the profile's upload host or to the CRM itself")
        suite.expect(!upload("https://storage-9999.example.test/storage/v1/object/upload")
                        && !upload("https://example.test/upload") && !upload("http://storage-1234.example.test/x")
                        && !upload("https://storage-1234.example.test:8443/x") && !upload("https://storage-1234.example.test.evil.test/x")
                        && !upload("https://user@storage-1234.example.test/x"),
                     "never another project of the same storage domain, plain HTTP, another port, a lookalike or a user")
        let day = at("2026-10-19T08:00:00Z")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        suite.expect(good.fileName(day: day, who: "Société Générale / R&D", extension: "flac", calendar: calendar)
                        == "Call_2026-10-19_Societe-Generale-R-D.flac"
                        && good.fileName(day: day, who: nil, extension: "flac", calendar: calendar) == "Call_2026-10-19_meeting.flac"
                        && good.fileName(day: day, who: "company1.example.test", extension: "flac", calendar: calendar)
                            == "Call_2026-10-19_company1.example.test.flac",
                     "the file's name: the prefix, the day, then who, in the characters a storage path keeps")
    }

    // MARK: - Contract

    private static func targets(_ suite: TestSuite) {
        let rows: [[String: Any]] = [
            booking(1, start: "2026-10-19T08:00:00+00:00", end: "2026-10-19T08:30:00.123456+00:00",
                    url: "https://meet.google.com/abc-defg-hij?authuser=0"),
            ["booking_id": "not-an-id", "start_at": "2026-10-19T08:00:00Z"],
            booking(2, start: "2026-10-19T09:00:00.000Z", status: "rescheduled"),
            booking(3, start: "2026-10-19T10:00:00Z", status: "no_show", active: nil),
            booking(4, start: "2026-10-19T11:00:00Z", active: false),
            booking(5, start: "2026-10-19T12:00:00Z", status: "cancelled", active: nil),
        ]
        var unnamed = booking(6, start: "2026-10-19T13:00:00Z")
        unnamed["company"] = ["id": "11111111-0000-4000-8000-000000000006", "nom": NSNull(), "domain": NSNull()]
        let read = bookings(rows + [unnamed])
        suite.expect(read.count == 6 && !read.contains { $0.id == "not-an-id" },
                     "one appointment that does not read is skipped, never the whole list")
        suite.expect(read.last?.company?.id != nil && read.last?.company?.name == nil,
                     "a company without a name keeps its appointment (B10)")
        suite.expect(read[0].endAt == at("2026-10-19T08:30:00Z") && read[1].startAt == at("2026-10-19T09:00:00Z"),
                     "dates read with an offset, with milliseconds or with Postgres's microseconds")
        suite.expect(read[0].meetCode == "abc-defg-hij", "an appointment's Google Meet code comes from its link")
        suite.expect(!read[0].isBlocked && !read[1].isBlocked, "a rescheduled appointment is alive, at its new time (B1)")
        suite.expect(read[2].isBlocked && read[3].isBlocked && read[4].isBlocked,
                     "only a missed or cancelled appointment, or one the server says is not active, takes nothing (B1)")
        let deposits = bookings([
            booking(7, start: "2026-10-19T08:00:00Z", deposits: [["id": "a", "stage": "failed", "has_summary": false],
                                                                ["id": "b", "stage": "upload"]]),
            booking(8, start: "2026-10-19T08:00:00Z", deposits: [["id": "c", "stage": "ready", "has_summary": false]]),
            booking(9, start: "2026-10-19T08:00:00Z", deposits: [["id": "d", "stage": "summarizing", "has_summary": true]]),
        ])
        suite.expect(!deposits[0].hasReport && deposits[1].hasReport && deposits[2].hasReport,
                     "only a deposit ready, or with its summary, counts as a report; a failed or abandoned one does not (B4)")
        suite.expect(ForkCastralContract.bookings(Data("{\"error\":\"x\"}".utf8)) == nil,
                     "an answer of another shape is not an empty list")
    }

    private static func deposit(_ suite: TestSuite) {
        let opening = ForkCastralContract.Opening(bookingID: "00000000-0000-4000-8000-000000000001", fileName: "a.flac",
                                                  mimeType: "audio/flac", bytes: 42_000_000, durationMilliseconds: 2_520_000,
                                                  speakers: 9, author: "Alice", complement: "  ")
        let body = try? JSONSerialization.jsonObject(with: opening.body()) as? [String: Any]
        suite.expect(body?["source_type"] as? String == "booking" && body?["max_speakers"] as? Int == 6
                        && body?["created_by"] as? String == "Alice" && body?["size_bytes"] as? Int == 42_000_000
                        && body?["mime_type"] as? String == "audio/flac" && body?["summary_complement"] == nil,
                     "the deposit says its appointment, its FLAC, its size, its speakers within 2 to 6, its author")
        let long = String(repeating: "a", count: 19_999) + "😀😀"
        let cut = ForkCastralContract.complement(long)
        suite.expect(cut == String(repeating: "a", count: 19_999)
                        && ForkCastralContract.complement(String(repeating: "a", count: 19_998) + "😀😀")
                            == String(repeating: "a", count: 19_998) + "😀",
                     "what was not recorded is cut at 20 000 units as the server counts them, never inside a character (B8)")
        suite.expect(ForkCastralContract.complement("  la suite  ") == "la suite" && ForkCastralContract.complement("") == nil,
                     "trimmed, and nothing for nothing")
        let opened = ForkCastralContract.opened(json(["id": "EBB59DA0-0F44-414C-BAA3-3D8A337B417A", "engine": "speech_fast",
                                                      "upload": ["url": "https://storage-1234.example.test/u?token=t"]]))
        suite.expect(opened?.id == "ebb59da0-0f44-414c-baa3-3d8a337b417a" && opened?.engine == "speech_fast",
                     "a deposit opened: its id, lower case, and where its sound goes")
        suite.expect(ForkCastralContract.opened(json(["id": "../x", "upload": ["url": "https://x"]])) == nil,
                     "an id that is not one is not followed into a path")
        let status = ForkCastralContract.status(json(["stage": "transcribing", "progress": 55, "error": NSNull(),
                                                      "warning": NSNull(), "engine": "speech_batch", "summary": NSNull(),
                                                      "company": ["id": "11111111-0000-4000-8000-000000000001", "nom": "ACME"]]))
        suite.expect(status?.stage == .transcribing && status?.progress == 55 && status?.engine == "speech_batch"
                        && status?.hasSummary == false && status?.companyName == "ACME",
                     "a status: its stage, its share, its engine, its company")
        suite.expect(ForkCastralContract.Stage.allCases.map(\.progress) == [10, 25, 55, 85, 100, 100],
                     "the stages' shares: upload 10, queued 25, transcribing 55, summarizing 85, then 100")
        suite.expect(ForkCastralContract.errorMessage(json(["error": "Fichier trop lourd."])) == "Fichier trop lourd.",
                     "the server's own sentence is kept to be shown")
    }

    // MARK: - Matching

    private static func matching(_ suite: TestSuite) {
        let start = at("2026-10-19T10:02:00Z"), end = at("2026-10-19T10:40:00Z")
        let rows = bookings([
            booking(1, start: "2026-10-19T10:00:00Z", end: "2026-10-19T10:30:00Z"),
            booking(2, start: "2026-10-19T10:05:00Z", end: "2026-10-19T10:35:00Z", url: "https://meet.google.com/abc-defg-hij"),
        ])
        let byCode = ForkCastralMatch.choose(rows, meetCode: "abc-defg-hij", startedAt: start, endedAt: end)
        suite.expect(byCode?.booking.id == rows[1].id && byCode?.rule == .meetCode && byCode?.unique == true,
                     "the meeting's own Google Meet code wins over a closer start")
        let byTime = ForkCastralMatch.choose(rows, meetCode: nil, startedAt: start, endedAt: end)
        suite.expect(byTime?.booking.id == rows[0].id && byTime?.rule == .overlap,
                     "a meeting without a code never matches by code: its time finds the appointment (B2)")
        let otherCode = ForkCastralMatch.choose(rows, meetCode: "zzz-zzzz-zzz", startedAt: start, endedAt: end)
        suite.expect(otherCode?.rule == .overlap && otherCode?.booking.id == rows[0].id,
                     "another code matches nothing by code, and never the appointment of another code by its time")
        let conflict = bookings([booking(20, start: "2026-10-19T10:00:00Z", end: "2026-10-19T10:30:00Z",
                                         url: "https://meet.google.com/abc-defg-hij")])
        let conflicting = ForkCastralMatch.choose(conflict, meetCode: "zzz-zzzz-zzz", startedAt: start, endedAt: end)
        suite.expect(conflicting == nil && ForkCastralMatch.automatic(conflicting) == .needsChoice(.noBooking)
                        && ForkCastralMatch.candidates(conflict, startedAt: start).map(\.id) == [conflict[0].id],
                     "a call zzz-zzzz-zzz and the only appointment on abc-defg-hij at that time: nothing on its own (another prospect), still in the choice")
        let late = bookings([booking(21, start: "2026-10-19T14:00:00Z", end: "2026-10-19T14:30:00Z",
                                     url: "https://meet.google.com/abc-defg-hij")])
        let lateChoice = ForkCastralMatch.choose(late, meetCode: "abc-defg-hij", startedAt: start, endedAt: end)
        suite.expect(lateChoice?.rule == .meetCode && lateChoice?.unique == false
                        && ForkCastralMatch.automatic(lateChoice) == .needsChoice(.uncertain),
                     "the only appointment of the call's code, but at another time: proposed, never sent on its own")
        let personal = bookings([
            booking(3, start: "2026-10-19T08:00:00Z", end: "2026-10-19T08:30:00Z", url: "https://meet.google.com/abc-defg-hij"),
            booking(4, start: "2026-10-19T10:00:00Z", end: "2026-10-19T10:30:00Z", url: "https://meet.google.com/abc-defg-hij"),
        ])
        let shared = ForkCastralMatch.choose(personal, meetCode: "abc-defg-hij", startedAt: start, endedAt: end)
        suite.expect(shared?.booking.id == personal[1].id && shared?.unique == true,
                     "a personal Meet link used by several appointments: the time tells them apart")
        let margin = bookings([booking(5, start: "2026-10-19T10:50:00Z", end: "2026-10-19T11:20:00Z")])
        suite.expect(ForkCastralMatch.choose(margin, meetCode: nil, startedAt: start, endedAt: end)?.rule == .overlap,
                     "an appointment starting 10 minutes after the recording ends still overlaps it (± 15 min, B6)")
        let near = bookings([booking(6, start: "2026-10-19T11:45:00Z", end: "2026-10-19T12:15:00Z")])
        suite.expect(ForkCastralMatch.choose(near, meetCode: nil, startedAt: start, endedAt: end)?.rule == .closest,
                     "within two hours without overlap: only the closest, a guess")
        let far = bookings([booking(7, start: "2026-10-19T13:00:00Z", end: "2026-10-19T13:30:00Z")])
        suite.expect(ForkCastralMatch.choose(far, meetCode: nil, startedAt: start, endedAt: end) == nil,
                     "beyond two hours, nothing")
        let cancelled = bookings([booking(8, start: "2026-10-19T10:00:00Z", url: "https://meet.google.com/abc-defg-hij",
                                          status: "cancelled", active: false)])
        suite.expect(ForkCastralMatch.choose(cancelled, meetCode: "abc-defg-hij", startedAt: start, endedAt: end) == nil,
                     "a cancelled appointment is never one, even with the meeting's code")
        let rescheduled = bookings([booking(9, start: "2026-10-19T10:00:00Z", end: "2026-10-19T10:30:00Z",
                                            url: "https://meet.google.com/abc-defg-hij", status: "rescheduled")])
        suite.expect(ForkCastralMatch.choose(rescheduled, meetCode: "abc-defg-hij", startedAt: start, endedAt: end)?.rule == .meetCode,
                     "a rescheduled one is, at its new time (B1)")
        let candidates = ForkCastralMatch.candidates(rows + cancelled, startedAt: start)
        suite.expect(candidates.map(\.id) == [rows[0].id, rows[1].id], "the choice lists the closest first, never a cancelled one")
        suite.expect(ForkCastralMatch.byCode(rows, meetCode: "ABC-DEFG-HIJ", now: start)?.id == rows[1].id
                        && ForkCastralMatch.byCode(rows, meetCode: nil, now: start) == nil,
                     "the offer names the appointment of the call's code, and only then (B7)")
        let window = ForkCastralMatch.window(startedAt: start, endedAt: end)
        suite.expect(window.from == start.addingTimeInterval(-12 * 3600) && window.to == end.addingTimeInterval(12 * 3600),
                     "the appointments are asked twelve hours around the meeting: never the whole calendar")
        suite.expect(ForkCastralMatch.suggestsComplement(recordedSeconds: 600, booking: rows[0])
                        && !ForkCastralMatch.suggestsComplement(recordedSeconds: 1500, booking: rows[0]),
                     "a recording much shorter than its appointment offers to say what was not recorded")
    }

    private static func automatic(_ suite: TestSuite) {
        let rows = bookings([
            booking(1, start: "2026-10-19T10:00:00Z", end: "2026-10-19T10:30:00Z", url: "https://meet.google.com/abc-defg-hij"),
            booking(2, start: "2026-10-19T10:00:00Z", end: "2026-10-19T10:30:00Z", company: false),
            booking(3, start: "2026-10-19T10:00:00Z", end: "2026-10-19T10:30:00Z",
                    deposits: [["id": "x", "stage": "ready", "has_summary": true]]),
        ])
        func verdict(_ rule: ForkCastralMatch.Rule, _ index: Int, unique: Bool = true) -> ForkCastralMatch.Verdict {
            ForkCastralMatch.automatic(ForkCastralMatch.Choice(booking: rows[index], rule: rule, unique: unique))
        }
        suite.expect(verdict(.meetCode, 0) == .send(ForkCastralMatch.Choice(booking: rows[0], rule: .meetCode, unique: true))
                        && verdict(.overlap, 0) != .needsChoice(.uncertain),
                     "on its own, only to a sure appointment: by its code, or the only one at that time")
        suite.expect(verdict(.closest, 0) == .needsChoice(.uncertain) && verdict(.overlap, 0, unique: false) == .needsChoice(.uncertain)
                        && ForkCastralMatch.automatic(nil) == .needsChoice(.noBooking),
                     "a guess, two at that time, or none: the person chooses")
        suite.expect(verdict(.meetCode, 1) == .needsChoice(.orphan) && verdict(.meetCode, 2) == .needsChoice(.alreadyReported),
                     "never on its own to an appointment without a company, or one that has a report already")
        for stage in ["upload", "queued", "transcribing", "summarizing"] {
            let row = bookings([booking(30, start: "2026-10-19T10:00:00Z", deposits: [["id": "y", "stage": stage]])])[0]
            suite.expect(ForkCastralMatch.automatic(.init(booking: row, rule: .meetCode, unique: true)) == .needsChoice(.alreadyDeposited)
                            && !row.hasReport,
                         "a deposit \(stage) on the appointment: never a second one on its own, which would be billed twice")
        }
        let failedOnly = bookings([booking(31, start: "2026-10-19T10:00:00Z", deposits: [["id": "z", "stage": "failed"]])])[0]
        suite.expect(ForkCastralMatch.automatic(.init(booking: failedOnly, rule: .meetCode, unique: true))
                        == .send(.init(booking: failedOnly, rule: .meetCode, unique: true)),
                     "only a failed deposit leaves the appointment free for one on its own")
        let start = at("2026-10-19T10:02:00Z")
        let two = bookings([booking(4, start: "2026-10-19T10:00:00Z", end: "2026-10-19T10:30:00Z"),
                            booking(5, start: "2026-10-19T10:15:00Z", end: "2026-10-19T10:45:00Z")])
        suite.expect(ForkCastralMatch.automatic(ForkCastralMatch.choose(two, meetCode: nil, startedAt: start,
                                                                        endedAt: start.addingTimeInterval(1800)))
                        == .needsChoice(.uncertain),
                     "two appointments at that time, no code: asked, never guessed")
    }

    // MARK: - Audio

    private static func audio(_ suite: TestSuite) {
        let limit: Int64 = 50_000_000
        suite.expect(ForkCastralAudioPlan.first(seconds: 30 * 60, limit: limit) == .encode(.flac16k)
                        && ForkCastralAudioPlan.first(seconds: 75 * 60, limit: limit) == .encode(.flac8k)
                        && ForkCastralAudioPlan.first(seconds: 2 * 3600, limit: limit) == .tooLong(maximumMinutes: 85),
                     "16 kHz first, 8 kHz when 16 kHz cannot fit, refused before writing when nothing can")
        suite.expect(ForkCastralAudioPlan.next(after: .flac16k, bytes: 49_000_000, seconds: 2700, limit: limit) == .send
                        && ForkCastralAudioPlan.next(after: .flac16k, bytes: 52_000_000, seconds: 2900, limit: limit) == .encode(.flac8k)
                        && ForkCastralAudioPlan.next(after: .flac8k, bytes: 51_000_000, seconds: 5400, limit: limit)
                            == .tooLong(maximumMinutes: 85),
                     "the file written is measured: over the cap at 16 kHz, 8 kHz; over it at 8 kHz, refused")
        suite.expect(ForkCastralAudioPlan.next(after: .flac16k, bytes: 0, seconds: 10, limit: limit) != .send,
                     "an empty file is never sent")
        suite.expect(ForkCastralAudioPlan.maximumMinutes(limit: 50_000_000, format: .flac16k) == 45
                        && ForkCastralAudioPlan.maximumMinutes(limit: 200_000_000, format: .flac16k) == 180,
                     "the length past which 8 kHz goes follows the cap: about 45 min at 50 MB, 3 h at 200 MB")
        suite.expect(ForkCastralAudioPlan.maximumMinutes(limit: 50_000_000) == 85
                        && ForkCastralAudioPlan.maximumMinutes(limit: 200_000_000) == 340,
                     "the longest meeting said: about 1 h 25 at 50 MB, 5 h 40 at 200 MB")
        suite.expect(ForkCastralAudioPlan.Format.flac16k.sampleRate == 16_000 && ForkCastralAudioPlan.Format.flac8k.sampleRate == 8_000
                        && ForkCastralAudioPlan.Format.mimeType == "audio/flac",
                     "FLAC, 16 kHz or 8 kHz, sent as audio/flac")
    }

    // MARK: - Steps

    private static func steps(_ suite: TestSuite) {
        let now = at("2026-10-19T12:00:00Z")
        let deposit = "ebb59da0-0f44-414c-baa3-3d8a337b417a"
        func record(_ step: ForkCastralRecord.Step, opened minutes: Double? = 5, stage: ForkCastralContract.Stage? = nil,
                    target: String = "crm") -> ForkCastralRecord {
            var record = ForkCastralRecord(target: target, step: step, deposit: deposit)
            record.openedAt = minutes.map { now.addingTimeInterval(-$0 * 60) }
            record.stage = stage
            return record
        }
        typealias Steps = ForkCastralSteps
        suite.expect(Steps.next(nil, target: "crm", hasAddress: false, now: now) == .open
                        && Steps.next(record(.started, target: "other"), target: "crm", hasAddress: false, now: now) == .open,
                     "nothing yet for this exporter: a deposit is opened")
        suite.expect(Steps.next(record(.uploading), target: "crm", hasAddress: true, now: now) == .upload,
                     "a quit while the sound left: sent again to the same address, still valid (B3)")
        suite.expect(Steps.next(record(.uploading, opened: 115), target: "crm", hasAddress: true, now: now) == .reopen(abandoned: deposit)
                        && Steps.next(record(.uploading), target: "crm", hasAddress: false, now: now) == .reopen(abandoned: deposit)
                        && Steps.next(record(.uploading, opened: -5), target: "crm", hasAddress: true, now: now) == .reopen(abandoned: deposit)
                        && Steps.next(record(.uploading, opened: nil), target: "crm", hasAddress: true, now: now) == .reopen(abandoned: deposit),
                     "an address near its two hours, gone, or of a clock gone back: that deposit goes, a new one opens (B3)")
        suite.expect(Steps.next(record(.uploaded), target: "crm", hasAddress: false, now: now) == .start,
                     "the sound arrived but the start failed: only the start again, never the sound (B5)")
        suite.expect(Steps.next(record(.started, stage: .failed), target: "crm", hasAddress: false, now: now) == .retry
                        && Steps.next(record(.started, stage: .transcribing), target: "crm", hasAddress: false, now: now) == .follow
                        && Steps.next(record(.started, stage: .ready), target: "crm", hasAddress: false, now: now) == .follow,
                     "started: retried only once the server failed it, else only followed, never sent twice")
        suite.expect(!Steps.allowsRetry(record(.uploading, stage: .failed)) && !Steps.allowsRetry(record(.uploaded, stage: .failed))
                        && !Steps.allowsRetry(record(.started, stage: .upload)) && Steps.allowsRetry(record(.started, stage: .failed))
                        && !Steps.allowsRetry(nil),
                     "the server's retry only after the sound arrived and the server failed it (S1)")
        suite.expect(Steps.upload(status: 200, body: nil) == .done
                        && Steps.upload(status: 400, body: "{\"statusCode\":\"409\",\"error\":\"Duplicate\",\"message\":\"The resource already exists\"}") == .done
                        && Steps.upload(status: 400, body: "{\"error\":\"InvalidJWT\",\"message\":\"exp claim timestamp check failed: jwt expired\"}") == .expired
                        && Steps.upload(status: 413, body: "Payload too large") == .failed
                        && Steps.upload(status: 500, body: nil) == .failed,
                     "the storage's answers: stored, already there from a send whose answer was lost, an address over, a failure")
        suite.expect(Steps.pollDelay(sinceStart: 0) == 4 && Steps.pollDelay(sinceStart: 300) == 10 && Steps.pollDelay(sinceStart: 900) == 30
                        && Steps.followBudget(engine: "speech_fast") == 1800 && Steps.followBudget(engine: "speech_batch") == 7200,
                     "the status is asked every 4 s, then 10 s, then 30 s, for half an hour, two for the batch engine")
    }

    private static func record(_ suite: TestSuite) {
        var record = ForkCastralRecord(target: "crm", step: .started, deposit: "ebb59da0-0f44-414c-baa3-3d8a337b417a")
        record.booking = "00000000-0000-4000-8000-000000000001"
        record.companyName = "ACME"
        record.rule = .meetCode
        record.format = .flac8k
        record.bytes = 31_000_000
        record.seconds = 3100
        record.openedAt = at("2026-10-19T12:00:00Z")
        record.stage = .summarizing
        record.progress = 85
        record.hasSummary = false
        guard case var .object(object) = record.json else { return suite.expect(false, "a record is an object") }
        object["later"] = .string("kept")
        let read = ForkCastralRecord(json: .object(object))
        var expected = record
        expected.preserved = ["later": .string("kept")]
        suite.expect(read == expected, "a record reads back as written, and keeps what a later version adds")
        suite.expect(ForkCastralRecord(json: .object(["target": .string("crm"), "step": .string("uploading"),
                                                      "deposit": .string("../x")])) == nil
                        && ForkCastralRecord(json: .object(["target": .string("crm"), "step": .string("later"),
                                                            "deposit": .string("ebb59da0-0f44-414c-baa3-3d8a337b417a")])) == nil,
                     "a record with a deposit that is not an id, or a step this version does not know, is none")
        var sidecar = ForkMeetingSidecar.started(id: UUID(), startedAt: at("2026-10-19T10:00:00Z"), origin: .offered,
                                                 title: "Point", titleSource: .window, capture: .init())
        var patch = ForkMeetingSidecarPatch()
        patch.castral = record.json
        sidecar = patch.applied(to: sidecar)
        let written = try? sidecar.encoded()
        let back = written.flatMap { try? ForkMeetingSidecar.decode($0).get() }
        suite.expect(back.flatMap { ForkCastralRecord(json: $0.castral) } == record,
                     "the record lives in meeting.json (castral), written by a patch and read back")
        let shared = (try? ForkMeetingExportDocument.json(sidecar, includesMeetCode: true, includesNotes: true,
                                                          includesSummary: true)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        suite.expect(!shared.isEmpty && !shared.contains("castral") && !shared.contains("deposit"),
                     "what the drop folder and the webhook send never carries the CRM's record")
        var settled = record
        settled.stage = .ready
        suite.expect(!record.isSettled && settled.isSettled, "only a started deposit the server finished is settled")
        var status = ForkCastralContract.Status(stage: .ready, progress: 100, warning: "Transcrit — compte-rendu en échec")
        status.companyID = "11111111-0000-4000-8000-000000000001"
        var applied = record
        applied.apply(status, at: at("2026-10-19T12:10:00Z"))
        suite.expect(applied.stage == .ready && applied.progress == 100 && applied.company == status.companyID
                        && ForkCastralPhase(record: applied) == .readyWithoutReport,
                     "transcribed, its report failed: said as such, not as a failure")
        settled.hasSummary = true
        suite.expect(ForkCastralPhase(record: settled) == .ready
                        && ForkCastralPhase(record: ForkCastralRecord(target: "crm", step: .uploading, deposit: record.deposit)) == .sending(nil)
                        && ForkCastralPhase(record: record, followed: false) == .stillWorking,
                     "each phase as the library and the island say it")
    }

    // MARK: - Failures and settings

    private static func failures(_ suite: TestSuite) {
        let all: [ForkCastralFailure] = [.noBooking, .uncertain, .orphan, .alreadyReported, .alreadyDeposited, .profile, .author, .tokenRefused,
                                         .rejected, .tooLong(maximumMinutes: 85), .uploadHost, .storage, .notArrived, .encoding]
        suite.expect(all.allSatisfy { ForkMeetingExportFailure(code: ForkMeetingExportFailure.castral($0).code, httpStatus: nil)
                         == .castral($0) },
                     "every CRM failure is written in meeting.json and read back as itself")
        suite.expect(ForkMeetingExportFailure.castral(.tooLong(maximumMinutes: 85)).code == "castral.tooLong.85"
                        && ForkMeetingExportFailure(code: "castral.later", httpStatus: nil) == .network,
                     "the longest meeting is kept with its failure; a code of a later version reads as the vaguest")
        suite.expect(all.filter(\.needsChoice) == [.noBooking, .uncertain, .orphan, .alreadyReported, .alreadyDeposited],
                     "what the person settles by choosing the appointment")
        for language in AppLanguage.allCases {
            let strings = ForkMeetingStrings.strings(language)
            let messages = all.map { ForkMeetingExportFailure.castral($0).message(strings) }
            suite.expect(Set(messages).count == messages.count && messages.allSatisfy { $0.count > 8 },
                         "\(language.rawValue): every CRM failure says, in a sentence of its own, what happened")
        }
        let english = ForkMeetingStrings.strings(.enUS), french = ForkMeetingStrings.strings(.fr)
        suite.expect(english.castralFailTooLong(minutes: 85).contains("1 h 25")
                        && french.castralFailTooLong(minutes: 85).contains("1\u{00A0}h\u{00A0}25"),
                     "too long says how long a meeting the server takes: about 1 h 25")
    }

    private static func configs(_ suite: TestSuite) {
        let config = ForkMeetingExporterConfig(id: "crm", kind: .castral, mode: .automatic, author: "Alice", speakers: 4)
        let stored = ForkMeetingExporterList.encode([config])
        suite.expect(ForkMeetingExporterList.decode(stored) == [config] && !stored.contains("token") && !stored.contains("https"),
                     "a CRM in the list: its id, mode, author and speakers; never its address nor its token")
        let wild = "[{\"id\":\"crm\",\"kind\":\"castral\",\"speakers\":40}]"
        suite.expect(ForkMeetingExporterList.decode(wild).first?.speakers == 6, "speakers out of range are brought back to 2 to 6")
        suite.expect(config.secretAccounts == ["castral-profile#crm", "castral-token#crm"]
                        && ForkMeetingExporterConfig(id: "d", kind: .dropFolder).secretAccounts.isEmpty,
                     "a CRM's profile and token are both in the Keychain, under its own id")
        suite.expect(config.readiness { _ in false } == .castral(.profile)
                        && config.readiness { $0 == "castral-profile#crm" } == .noSecret
                        && ForkMeetingExporterConfig(id: "crm", kind: .castral).readiness { _ in true } == .castral(.author)
                        && config.readiness { _ in true } == nil,
                     "set up once its profile, its author and its token are there")
        suite.expect(ForkMeetingExportKind.addable == [.dropFolder, .webhook],
                     "the page's Add never offers a CRM: it comes from its profile")
    }

    private static func texts(_ suite: TestSuite) {
        let name = String(repeating: "N", count: 16)
        var tooLong: [String] = []
        for language in AppLanguage.allCases {
            let strings = ForkMeetingStrings.strings(language)
            let short = [strings.noticeCastralSent(name), strings.noticeCastralFailed(name), strings.castralLinkConnected(999),
                         strings.castralLinkRefused, strings.castralLinkOffline, strings.castralLinkFailed(503),
                         strings.castralPhaseSending, strings.castralLinkCheckFailed, strings.castralPhaseWaiting,
                         strings.castralPhaseQueued, strings.castralPhaseTranscribing, strings.castralPhaseSummarizing,
                         strings.castralPhaseReady, strings.castralPhaseReadyWithoutReport, strings.castralPhaseFailed,
                         strings.castralPhaseStillWorking, strings.castralNoCompany, strings.castralBadgeReported]
            tooLong += short.filter { $0.count > 28 }.map { "\(language.rawValue): \($0)" }
            let phases = [strings.castralPhaseSending, strings.castralPhaseWaiting, strings.castralPhaseQueued,
                          strings.castralPhaseTranscribing, strings.castralPhaseSummarizing, strings.castralPhaseReady,
                          strings.castralPhaseReadyWithoutReport, strings.castralPhaseFailed, strings.castralPhaseStillWorking]
            suite.expect(Set(phases).count == phases.count, "\(language.rawValue): each phase has its own words")
            suite.expect(strings.noticeCastralSent("Example CRM").contains("Example CRM")
                            && strings.castralLinkConnected(12).contains("12")
                            && strings.castralAudioCaption(lower: "45 min", longest: "1 h 25").contains("1 h 25")
                            && strings.castralHosts("crm.example.test", sound: "storage.example.test").contains("storage.example.test"),
                         "\(language.rawValue): the notices name the CRM, the counts, the lengths and the hosts are said")
        }
        suite.expect(tooLong.isEmpty, "the notices and the phases fit the island: 28 characters at most, with a 16-letter name: \(tooLong)")
    }
}
