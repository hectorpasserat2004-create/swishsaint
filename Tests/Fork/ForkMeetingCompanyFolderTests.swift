// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// A meeting filed in its company's folder (`ForkMeetingCompanyFolder`):
/// the folder's name from a domain, the library's names, the scan one level
/// down into company folders only, the move itself, and what the CRM keeps
/// of the domain.
enum ForkMeetingCompanyFolderTests {
    static func run(_ suite: TestSuite) {
        names(suite)
        disk(suite)
        library(suite)
        crm(suite)
        wiring(suite)
    }

    private static let meeting = "2026-10-22 10h08 — Diagnostic"
    private static let other = "2026-10-21 14h02 — Point"

    private static func names(_ suite: TestSuite) {
        typealias Company = ForkMeetingCompanyFolder
        suite.expect(Company.name(domain: " Pronic.com ") == "pronic.com" && Company.name(domain: "www.acme.co.uk") == "acme.co.uk"
                        && Company.name(domain: "r2d-automation.com") == "r2d-automation.com",
                     "a company's folder is its domain, in lower case, without www.")
        let refused: [String?] = [nil, "", "acme", ".acme.com", "acme.com.", "acme..com", "https://acme.com", "acme.com/x",
                                  "../acme.com", "a b.com", "-acme.com", "acmé.com", String(repeating: "a", count: 98) + ".com"]
        suite.expect(refused.allSatisfy { Company.name(domain: $0) == nil },
                     "anything but a plain domain is no folder: no path, no scheme, no dots alone, never too long")
        suite.expect(Company.relative(meeting, company: "acme.com") == "acme.com/" + meeting
                        && Company.relative(meeting, company: nil) == meeting
                        && Company.leaf(of: "acme.com/" + meeting) == meeting && Company.leaf(of: meeting) == meeting
                        && Company.company(of: "acme.com/" + meeting) == "acme.com" && Company.company(of: meeting) == nil,
                     "the library names a filed meeting with its company's folder, and its own name stays the folder's")
        suite.expect(Company.covers(["acme.com"], "acme.com/" + meeting) && Company.covers([meeting], meeting)
                        && !Company.covers(["acme.com"], meeting) && !Company.covers([meeting], "acme.com/" + meeting),
                     "a change in a company's folder rescans the meetings filed in it, and only them")
    }

    private static func makeMeeting(_ folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? Data("{}".utf8).write(to: folder.appendingPathComponent(ForkMeetingFolder.sidecarName))
    }

    private static func disk(_ suite: TestSuite) {
        typealias Company = ForkMeetingCompanyFolder
        let manager = FileManager.default
        let root = manager.temporaryDirectory
            .appendingPathComponent("ForkMeetingCompanyFolderTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: root) }
        try? manager.createDirectory(at: root, withIntermediateDirectories: true)
        makeMeeting(root.appendingPathComponent(meeting))
        makeMeeting(root.appendingPathComponent("pronic.com/" + other))
        try? Data("<html>".utf8).write(to: root.appendingPathComponent("pronic.com/pre-rdv.html"))
        try? manager.createDirectory(at: root.appendingPathComponent("pronic.com/docs"), withIntermediateDirectories: true)
        makeMeeting(root.appendingPathComponent("Recordings/2026-01-01 09h00 — Elsewhere"))
        makeMeeting(root.appendingPathComponent(".hidden.com/2026-01-01 09h00 — Hidden"))
        try? Data("x".utf8).write(to: root.appendingPathComponent("notes.com"))

        suite.expect(Company.meetings(in: root) == [meeting, "pronic.com/" + other],
                     "the scan finds the root's meetings and those of company folders, nothing in other folders or files")
        suite.expect(Company.meetings(in: root, only: ["pronic.com"]) == ["pronic.com/" + other]
                        && Company.meetings(in: root, only: [meeting]) == [meeting]
                        && Company.meetings(in: root, only: ["pronic.com/" + other]) == ["pronic.com/" + other],
                     "a partial scan reads a company folder's meetings, or one of them, or a root meeting alone")
        suite.expect(Company.relativeName(of: root.appendingPathComponent("pronic.com/" + other), root: root) == "pronic.com/" + other
                        && Company.relativeName(of: root.appendingPathComponent(meeting), root: root) == meeting
                        && Company.relativeName(of: root.appendingPathComponent("Recordings/x"), root: root) == nil,
                     "a folder's name in the library: at the root, or in a company folder, else none")

        // Filed: the company folder made, the meeting moved whole.
        let first = root.appendingPathComponent(meeting, isDirectory: true)
        let filed = Company.file(first, root: root, company: "acme.com")
        let there = root.appendingPathComponent("acme.com/" + meeting, isDirectory: true)
        suite.expect(filed == .filed(there) && !manager.fileExists(atPath: first.path)
                        && manager.fileExists(atPath: there.appendingPathComponent(ForkMeetingFolder.sidecarName).path)
                        && Company.meetings(in: root).contains("acme.com/" + meeting),
                     "filing moves the meeting into its company's folder, made when missing, and the scan finds it there")
        suite.expect(Company.file(there, root: root, company: "acme.com") == .already,
                     "a meeting already in its company's folder stays")
        // Moved to another company's folder that exists, beside its files.
        let moved = Company.file(there, root: root, company: "pronic.com")
        suite.expect(moved == .filed(root.appendingPathComponent("pronic.com/" + meeting, isDirectory: true))
                        && manager.fileExists(atPath: root.appendingPathComponent("pronic.com/pre-rdv.html").path),
                     "another appointment's company: from one company folder to another, its other files kept")
        let blocked = root.appendingPathComponent("2026-10-23 09h00 — Blocked", isDirectory: true)
        makeMeeting(blocked)
        suite.expect(Company.file(blocked, root: root, company: "notes.com") == .blockedByFile
                        && manager.fileExists(atPath: blocked.path),
                     "a file with the company's name is left alone, and the meeting stays")
        makeMeeting(root.appendingPathComponent("pronic.com/2026-10-23 09h00 — Blocked"))
        suite.expect(Company.file(blocked, root: root, company: "pronic.com") == .taken && manager.fileExists(atPath: blocked.path),
                     "a folder of the same name in the company's folder: nothing moves, nothing is overwritten")
        suite.expect(Company.file(root.appendingPathComponent("Recordings/2026-01-01 09h00 — Elsewhere"), root: root,
                                  company: "acme.com") == .notInLibrary
                        && Company.file(blocked, root: root, company: "../x") != .filed(blocked),
                     "a folder the person filed elsewhere is never moved, nor anything to a name that is not a domain")
    }

    private static func library(_ suite: TestSuite) {
        let leaf = "2026-10-21 14h02 — Point hebdo"
        let filed = ForkMeetingLibraryEntry(folderName: "pronic.com/" + leaf, sidecar: .failure(.corrupt("x")),
                                            contents: ForkMeetingFolder.contents(of: [ForkMeetingFolder.sidecarName, leaf + ".mp4"],
                                                                                 folderName: leaf))
        suite.expect(filed?.leafName == leaf && filed?.companyFolder == "pronic.com" && filed?.title == "Point hebdo"
                        && filed?.dateSource == .folderName && filed?.video == leaf + ".mp4"
                        && filed.map(ForkMeetingAudioExport.suggestedName) == leaf + ".m4a",
                     "a filed meeting reads its date, title and media from its own folder's name")
        let rows = [filed, ForkMeetingLibraryEntry(folderName: leaf + " bis", sidecar: .failure(.corrupt("x")),
                                                   contents: ForkMeetingFolder.contents(of: [ForkMeetingFolder.sidecarName],
                                                                                        folderName: leaf + " bis"))]
            .compactMap { $0 }
        suite.expect(ForkMeetingLibrary.merged(rows, scanned: ["pronic.com"], with: []).map(\.folderName) == [leaf + " bis"],
                     "a rescan of a company folder replaces the rows filed in it, and only them")
        suite.expect(ForkMeetingLibrary.keptSelection(leaf, before: [leaf, "b"], after: ["b", "pronic.com/" + leaf])
                        == "pronic.com/" + leaf
                        && ForkMeetingLibrary.keptSelection("pronic.com/" + leaf, before: ["pronic.com/" + leaf],
                                                            after: ["acme.com/" + leaf]) == "acme.com/" + leaf,
                     "the meeting shown stays selected when it is filed in its company's folder, or moved to another")
        suite.expect(ForkMeetingRename.folderLags(folderName: leaf, startedAt: nil, title: "x") == false,
                     "the rename rules judge the folder's own name")
    }

    private static func crm(_ suite: TestSuite) {
        let status = ForkCastralContract.status(Data(#"{"stage":"ready","company":{"id":"11111111-0000-4000-8000-000000000001","nom":"PRONIC","domain":"pronic.com"}}"#.utf8))
        suite.expect(status?.companyDomain == "pronic.com" && status?.companyName == "PRONIC",
                     "the status says the company's domain")
        var record = ForkCastralRecord(target: "crm", step: .started, deposit: "ebb59da0-0f44-414c-baa3-3d8a337b417a")
        record.booking = "00000000-0000-4000-8000-000000000001"
        record.company = "11111111-0000-4000-8000-000000000001"
        suite.expect(record.companyFolder == nil, "no domain, no company folder")
        if let status { record.apply(status, at: Date(timeIntervalSinceReferenceDate: 0)) }
        suite.expect(record.companyDomain == "pronic.com" && record.companyFolder == "pronic.com"
                        && ForkCastralRecord(json: record.json) == record,
                     "a status read gives the record its domain, kept in meeting.json")
        let rows = ForkCastralContract.bookings(Data(#"{"bookings":[{"booking_id":"00000000-0000-4000-8000-000000000002","start_at":"2026-10-22T08:00:00Z","detected_domain":"www.Saboulet.fr","company":null}]}"#.utf8)) ?? []
        var moved = record
        moved.moved(.init(bookingID: "00000000-0000-4000-8000-000000000002", companyID: nil, oldNotes: nil, regenerating: false),
                    booking: rows.first, at: Date(timeIntervalSinceReferenceDate: 0))
        suite.expect(rows.first?.domain == "www.Saboulet.fr" && moved.companyFolder == "saboulet.fr",
                     "an appointment without a company files under the domain its attendee's address gave")

        var config = ForkMeetingExporterConfig(id: "crm", kind: .castral)
        let plain = ForkMeetingExporterList.encode([config])
        config.filesByCompany = true
        let filing = ForkMeetingExporterList.encode([config])
        let decodedOff = ForkMeetingExporterList.decode(#"[{"kind":"castral","id":"crm","filesByCompany":false}]"#).first
        suite.expect(!plain.contains("filesByCompany") && ForkMeetingExporterList.decode(filing).first?.filesByCompany == true
                        && decodedOff?.filesByCompany == nil,
                     "the option is kept with the exporter, and a list written before it reads the same")
        for language in AppLanguage.allCases {
            let strings = ForkMeetingStrings.strings(language)
            suite.expect(!strings.castralFilesByCompany.isEmpty && strings.castralFilesByCompanyCaption.contains("acme.com"),
                         "\(language.rawValue): the option and its example")
        }
    }

    private static func wiring(_ suite: TestSuite) {
        let library = ForkMeetingFinalizeTests.source("Sources/Vorssaint/Fork/Meetings/ForkMeetingStore+Library.swift")
        let castral = ForkMeetingFinalizeTests.source("Sources/Vorssaint/Fork/Meetings/Export/Castral/ForkCastralStore.swift")
        let exports = ForkMeetingFinalizeTests.source("Sources/Vorssaint/Fork/Meetings/Export/ForkMeetingExports.swift")
        let locate = ForkMeetingFinalizeTests.source("Sources/Vorssaint/Fork/Meetings/ForkMeetingStore+Transcript.swift")
        let tracker = ForkMeetingFinalizeTests.source("Sources/Vorssaint/Fork/Meetings/Export/Castral/ForkCastralTracker.swift")
        let store = ForkMeetingFinalizeTests.source("Sources/Vorssaint/Fork/Meetings/ForkMeetingStore.swift")
        suite.expect(library.contains("ForkMeetingCompanyFolder.meetings(in: root, only: only)")
                        && castral.contains("ForkMeetingCompanyFolder.meetings(in: root)")
                        && exports.contains("ForkMeetingCompanyFolder.meetings(in: root)")
                        && locate.contains("ForkMeetingCompanyFolder.meetings(in: root)"),
                     "the library, the CRM's resume, the sends and the store's writes all see the filed meetings")
        suite.expect(library.contains("renameTable.record(from: old, to: new") && library.contains("func fileInCompany(")
                        && tracker.contains("exports.fileByCompany(folder)") && tracker.contains("exports.fileUnfiled()")
                        && tracker.contains("ForkMeetingExports.folder(of: id, near: follow.folder"),
                     "filing follows the writes like a rename, and the follow files a settled meeting and finds it moved")
        let recover = store.components(separatedBy: "private func recover(").dropFirst().first ?? ""
        suite.expect(recover.contains("contentsOfDirectory(atPath: root.path)") && !recover.contains("ForkMeetingCompanyFolder"),
                     "the recovery at launch reads the root alone: a meeting is recorded there, filed only once complete")
    }
}
