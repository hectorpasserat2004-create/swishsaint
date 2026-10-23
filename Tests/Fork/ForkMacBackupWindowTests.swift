// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Suite `fork-macbackup-window`: the pure files of `MacBackup/Window/Pure/`
/// (status against the Mac, versions, restore names and checks, the slots
/// calendar, the timeline, « is this file backed up? », the window's words).
enum ForkMacBackupWindowTests {
    static func run(_ suite: TestSuite) {
        localStatus(suite)
        browseEntries(suite)
        folderPaths(suite)
        nameQuery(suite)
        versions(suite)
        restoreNames(suite)
        restoreChecks(suite)
        slotsGrid(suite)
        slotsGridAcrossClockChanges(suite)
        timeline(suite)
        timelineAcrossClockChanges(suite)
        ignoreRules(suite)
        verdicts(suite)
        capacity(suite)
        dates(suite)
        strings(suite)
    }

    // MARK: Helpers

    private static let now = Date(timeIntervalSince1970: 1_792_663_440) // 22/10/2026, a fixed instant

    private static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        calendar.locale = Locale(identifier: "fr_FR")
        return calendar
    }

    private static func date(_ text: String, _ zone: String = "Europe/Paris") -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: zone)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text) ?? .distantPast
    }

    private static func manifest(_ json: String) -> ForkMacBackupKopia.DirectoryManifest? {
        ForkMacBackupKopia.decode(ForkMacBackupKopia.DirectoryManifest.self, from: Data(json.utf8))
    }

    // MARK: Status against the Mac

    private static func localStatus(_ suite: TestSuite) {
        let saved = now.addingTimeInterval(-3_600)
        typealias Facts = ForkMacBackupLocalStatus.LocalFacts
        func compare(_ isDirectory: Bool, _ size: Int64?, _ modified: Date?, _ local: Facts?) -> ForkMacBackupLocalStatus {
            ForkMacBackupLocalStatus.compare(isDirectory: isDirectory, size: size, modified: modified, local: local)
        }
        suite.expect(compare(false, 100, saved, Facts(isDirectory: false, size: 100, modified: saved)) == .identical,
                     "same size and date: identical")
        suite.expect(compare(false, 100, saved, Facts(isDirectory: false, size: 100, modified: saved.addingTimeInterval(1.5)))
                        == .identical, "a date rounded by a copy (≤ 2 s) is still the same")
        suite.expect(compare(false, 100, saved, Facts(isDirectory: false, size: 100, modified: saved.addingTimeInterval(60)))
                        == .modifiedSince, "a later date: modified since")
        suite.expect(compare(false, 100, saved, Facts(isDirectory: false, size: 101, modified: saved)) == .modifiedSince,
                     "another size, same date: modified since")
        suite.expect(compare(false, 100, saved, nil) == .deletedSince, "gone from the Mac: deleted since")
        suite.expect(compare(true, 4_000, saved, Facts(isDirectory: true, size: 96, modified: now)) == .present,
                     "a folder still there is compared file by file, not as a whole")
        suite.expect(compare(true, nil, saved, nil) == .deletedSince, "a folder gone: deleted since")
        suite.expect(compare(false, 100, saved, Facts(isDirectory: true, size: 0, modified: saved)) == .modifiedSince,
                     "a file that became a folder changed")
        suite.expect(compare(false, nil, nil, Facts(isDirectory: false, size: 1, modified: nil)) == .unknown,
                     "nothing to compare: unknown, never a guess")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fork-macbackup-window-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("a.txt")
        try? Data("hello".utf8).write(to: file)
        let facts = ForkMacBackupLocalStatus.facts(atPath: file.path)
        suite.expect(facts?.size == 5 && facts?.isDirectory == false && facts?.modified != nil,
                     "the Mac's facts: logical size, kind, date")
        suite.expect(ForkMacBackupLocalStatus.facts(atPath: folder.path)?.isDirectory == true
                        && ForkMacBackupLocalStatus.facts(atPath: folder.appendingPathComponent("nope").path) == nil,
                     "a folder reads as one, a missing path as nil")
    }

    private static func browseEntries(_ suite: TestSuite) {
        let json = """
        {"stream":"kopia:directory","entries":[
          {"name":"small","type":"d","mtime":"2026-10-22T14:22:08.665164893Z","obj":"k034c","summ":{"size":67715,"files":3000,"numFailed":0}},
          {"name":"unreadable","type":"d","obj":"k583e","summ":{"size":0,"files":0,"numFailed":1}},
          {"name":"link","type":"s","size":17,"obj":"b054"},
          {"name":"random 10.bin","type":"f","size":209715200,"mtime":"2026-10-22T14:22:09.678414147Z","obj":"Ix76"},
          {"name":"random 2.bin","type":"f","size":12,"obj":"Ix77"},
          {"name":"","type":"f","obj":"Ix78"},
          {"name":"no-object","type":"f"}
        ]}
        """
        guard let manifest = manifest(json) else {
            suite.expect(false, "the directory manifest decodes")
            return
        }
        let entries = ForkMacBackupBrowseEntry.entries(of: manifest, folder: "data")
        suite.expect(entries.count == 5, "unnamed entries and entries without an object are dropped")
        let small = entries.first { $0.name == "small" }
        suite.expect(small?.isDirectory == true && small?.size == 67_715 && small?.fileCount == 3_000
                        && small?.relativePath == "data/small" && small?.modified != nil,
                     "a folder takes its summary's size and count, its path under the folder")
        suite.expect(entries.first { $0.name == "unreadable" }?.failedCount == 1, "a folder's unread files are counted")
        suite.expect(entries.first { $0.name == "link" }?.isSymlink == true, "a symlink stays a symlink")
        let sorted = entries.sorted(by: ForkMacBackupBrowseEntry.finderOrder).map(\.name)
        suite.expect(sorted.firstIndex(of: "random 2.bin")! < sorted.firstIndex(of: "random 10.bin")!,
                     "Finder's order: 2 before 10")
        let size = ForkMacBackupSelectionSize.of(entries.filter { $0.name.hasPrefix("random") || $0.name == "small" })
        suite.expect(size.bytes == 209_715_200 + 12 + 67_715 && size.files == 3_002 && !size.isEstimate,
                     "a selection weighs its files and its folders' content")
        var unsized = entries[0]
        unsized.size = nil
        suite.expect(ForkMacBackupSelectionSize.of([unsized]).isEstimate, "an entry without a size makes it an estimate")
    }

    private static func folderPaths(_ suite: TestSuite) {
        suite.expect(ForkMacBackupFolderPath.components("/Documents//Castral/") == ["Documents", "Castral"]
                        && ForkMacBackupFolderPath.join("", "a") == "a" && ForkMacBackupFolderPath.join("a", "b") == "a/b",
                     "relative paths split and join without empty parts")
        suite.expect(ForkMacBackupFolderPath.parent(of: "a/b/c") == "a/b" && ForkMacBackupFolderPath.parent(of: "a") == ""
                        && ForkMacBackupFolderPath.parent(of: "") == nil, "the parent of a path; none above the root")
        suite.expect(ForkMacBackupFolderPath.absolute("Documents/a.pdf", in: "/Users/m") == "/Users/m/Documents/a.pdf"
                        && ForkMacBackupFolderPath.absolute("", in: "/Users/m") == "/Users/m", "back to the Mac's path")
        suite.expect(ForkMacBackupFolderPath.relative("/Users/m/Documents/a", to: "/Users/m") == "Documents/a"
                        && ForkMacBackupFolderPath.relative("/Users/m", to: "/Users/m/") == ""
                        && ForkMacBackupFolderPath.relative("/Users/martial/a", to: "/Users/m") == nil
                        && ForkMacBackupFolderPath.relative("/etc/hosts", to: "/") == "etc/hosts",
                     "inside a source only on a folder boundary")
    }

    private static func nameQuery(_ suite: TestSuite) {
        let query = ForkMacBackupNameQuery("  Devis  PRONIC ")
        suite.expect(query.matches("devis-pronic.pdf") && query.matches("Pronic — DEVIS signé") && !query.matches("devis.pdf"),
                     "every word somewhere in the name, case ignored")
        suite.expect(ForkMacBackupNameQuery("ecran").matches("Capture d’écran.png")
                        && ForkMacBackupNameQuery("Ｄｅｖｉｓ").matches("devis"), "accents and widths ignored")
        suite.expect(ForkMacBackupNameQuery("   ").isEmpty && !ForkMacBackupNameQuery("").matches("x"), "no query matches nothing")
    }

    // MARK: Versions

    private static func versions(_ suite: TestSuite) {
        func version(_ manifest: String, _ hoursAgo: Double, _ object: String, _ size: Int64 = 10) -> ForkMacBackupFileVersion {
            ForkMacBackupFileVersion(manifestID: manifest, snapshotTime: now.addingTimeInterval(-hoursAgo * 3_600),
                                     objectID: object, size: size, modified: nil)
        }
        let list = [version("m1", 1, "C"), version("m2", 7, "C"), version("m3", 13, "B"), version("m4", 19, "A"),
                    version("m5", 25, "B"), version("m6", 31, "A")]
        let distinct = ForkMacBackupDistinctVersion.distinct(list)
        suite.expect(distinct.count == 3, "six snapshots, three different contents")
        suite.expect(distinct.map(\.id) == ["C", "B", "A"], "newest content first")
        let b = distinct.first { $0.id == "B" }
        suite.expect(b?.newest.manifestID == "m3" && b?.snapshotCount == 2
                        && b?.firstSeen == now.addingTimeInterval(-25 * 3_600) && b?.lastSeen == now.addingTimeInterval(-13 * 3_600),
                     "a content that came back is one version, restored from its newest snapshot")
        let unnamed = ForkMacBackupDistinctVersion.distinct([version("x", 1, ""), version("y", 2, "")])
        suite.expect(unnamed.count == 2, "versions without an object ID never merge")
        suite.expect(ForkMacBackupDistinctVersion.distinct([]).isEmpty, "no version, no line")
        let shuffled = ForkMacBackupDistinctVersion.distinct(list.reversed())
        suite.expect(shuffled.map(\.id) == ["C", "B", "A"], "the order of the engine's list does not matter")
    }

    // MARK: Restore

    private static func restoreNames(_ suite: TestSuite) {
        var taken: Set<String> = ["rapport.pdf", "rapport (restauré).pdf", "notes", ".zshrc", "Dossier",
                                  "archive.tar.gz", "Restauré — x", "Restauré — x 2"]
        let exists: (String) -> Bool = { taken.contains($0) }
        suite.expect(ForkMacBackupRestoreNaming.keepBothName("neuf.pdf", isDirectory: false, word: "restauré", exists: exists)
                        == "neuf.pdf", "a free name is kept")
        suite.expect(ForkMacBackupRestoreNaming.keepBothName("rapport.pdf", isDirectory: false, word: "restauré", exists: exists)
                        == "rapport (restauré 2).pdf", "the suffix goes before the extension, numbered when taken")
        taken.remove("rapport (restauré).pdf")
        suite.expect(ForkMacBackupRestoreNaming.keepBothName("rapport.pdf", isDirectory: false, word: "restauré", exists: exists)
                        == "rapport (restauré).pdf", "the first copy has no number")
        suite.expect(ForkMacBackupRestoreNaming.keepBothName("notes", isDirectory: false, word: "restored", exists: exists)
                        == "notes (restored)", "no extension: at the end")
        suite.expect(ForkMacBackupRestoreNaming.keepBothName(".zshrc", isDirectory: false, word: "restored", exists: exists)
                        == ".zshrc (restored)", "a dot file keeps its whole name")
        suite.expect(ForkMacBackupRestoreNaming.keepBothName("Dossier", isDirectory: true, word: "restauré", exists: exists)
                        == "Dossier (restauré)", "a folder too")
        suite.expect(ForkMacBackupRestoreNaming.keepBothName("archive.tar.gz", isDirectory: false, word: "restored",
                                                             exists: exists) == "archive.tar (restored).gz",
                     "only the last extension stays after the suffix, as the Finder does")
        suite.expect(ForkMacBackupRestoreNaming.split("v1.0 final", isDirectory: false) == ("v1.0 final", ""),
                     "« .0 final » is not an extension")
        suite.expect(ForkMacBackupRestoreNaming.uniqueFolder("Restauré — x", exists: exists) == "Restauré — x 3"
                        && ForkMacBackupRestoreNaming.uniqueFolder("Libre", exists: exists) == "Libre",
                     "the folder apart is never one that exists")

        var components = Locale.Components(identifier: "fr_FR")
        components.hourCycle = .zeroToTwentyThree
        let paris = TimeZone(identifier: "Europe/Paris") ?? .gmt
        let name = ForkMacBackupRestoreNaming.folderName(prefix: "Restauré", date: date("2026-10-22 10:04"),
                                                         locale: Locale(components: components), timeZone: paris)
        suite.expect(name.hasPrefix("Restauré — 22 oct. 2026") && name.contains("10.04") && !name.contains(":")
                        && !name.contains("/"), "« Restauré — 22 oct. 2026 à 10.04 », a Finder name: \(name)")
        var us = Locale.Components(identifier: "en_US")
        us.hourCycle = .oneToTwelve
        let english = ForkMacBackupRestoreNaming.folderName(prefix: "Restored", date: date("2026-10-22 22:04"),
                                                            locale: Locale(components: us), timeZone: paris)
        suite.expect(english.contains("10.04") && english.contains("PM") && !english.contains(":")
                        && !english.contains("\u{202F}"), "a 12-hour clock stays a 12-hour clock: \(english)")
        suite.expect(ForkMacBackupRestoreNaming.finderSafe("..a/b:c") == "a-b.c" && ForkMacBackupRestoreNaming.finderSafe(" ") == "-",
                     "no leading dot, no slash, no colon, never empty")
    }

    private static func restoreChecks(_ suite: TestSuite) {
        suite.expect(ForkMacBackupRestoreCheck.required(for: 1_000) == 1_100
                        && ForkMacBackupRestoreCheck.required(for: 1_001) == 1_102
                        && ForkMacBackupRestoreCheck.required(for: 0) == 0
                        && ForkMacBackupRestoreCheck.required(for: Int64.max) == Int64.max,
                     "size plus 10 %, rounded up, never overflowing")
        suite.expect(ForkMacBackupRestoreCheck.room(needed: 1_000, available: 1_100) == .enough
                        && ForkMacBackupRestoreCheck.room(needed: 1_000, available: 1_099) == .short(missing: 1)
                        && ForkMacBackupRestoreCheck.room(needed: 1_000, available: nil) == .unknown
                        && ForkMacBackupRestoreCheck.room(needed: 1_000, available: -1) == .unknown,
                     "enough room is the size plus the margin; an unknown volume says so")
        let sources = ["/Users/m", "/Volumes/Data/Projets/"]
        suite.expect(ForkMacBackupRestoreCheck.isInsideSource("/Users/m/Downloads/Restauré", sources: sources)
                        && ForkMacBackupRestoreCheck.isInsideSource("/Volumes/Data/Projets", sources: sources)
                        && !ForkMacBackupRestoreCheck.isInsideSource("/Users/martial/x", sources: sources)
                        && !ForkMacBackupRestoreCheck.isInsideSource("/tmp/x", sources: sources),
                     "restoring into a backed-up folder is flagged, on folder boundaries only")
    }

    // MARK: Slots

    private static func slotsGrid(_ suite: TestSuite) {
        let paris = calendar("Europe/Paris")
        let now = date("2026-10-22 10:30")
        var slots: [ForkMacBackupSlotRecord] = []
        for day in 20...22 {
            for hour in stride(from: 0, to: 24, by: 4) {
                let due = date(String(format: "2026-10-%02d %02d:00", day, hour))
                guard due <= now else { continue }
                let outcome: ForkMacBackupSlotRecord.Outcome = hour == 0 ? .missed(.asleep)
                    : (day == 21 && hour == 8 ? .failed : .done)
                slots.append(ForkMacBackupSlotRecord(due: due, outcome: outcome,
                                                     startedAt: hour == 0 ? nil : due.addingTimeInterval(30)))
            }
        }
        // A missed slot caught up later: asleep at 00:00 on the 20th, the 04:00 run catches it up.
        let grid = ForkMacBackupSlotsGrid.build(slots: slots, now: now, days: 3, calendar: paris)
        suite.expect(grid.hoursPerColumn == 4 && grid.columnCount == 6 && grid.columnHours == [0, 4, 8, 12, 16, 20],
                     "a slot every four hours: six columns")
        suite.expect(grid.rows.count == 3 && grid.rows.map { paris.component(.day, from: $0.day) } == [20, 21, 22],
                     "oldest day first, today last")
        let today = grid.rows[2]
        suite.expect(today.cells[0].mark == .asleep && today.cells[1].mark == .done && today.cells[2].mark == .done
                        && today.cells[3].mark == .upcoming && today.cells[5].mark == .upcoming,
                     "today: asleep, done, done (08:00 slot), then upcoming")
        suite.expect(grid.rows[1].cells[2].mark == .failed, "a failed run shows ✕")
        suite.expect(grid.rows[0].cells[0].caughtUpAt == date("2026-10-20 04:00").addingTimeInterval(30),
                     "a missed slot says when it was caught up")
        suite.expect(grid.rows[0].cells[3].mark == .done && grid.rows[0].cells[3].caughtUpAt == nil,
                     "a slot done on time has no catch-up")

        let marks = ForkMacBackupMissedReason.allCases.map(ForkMacBackupSlotsGrid.Mark.of)
        suite.expect(ForkMacBackupSlotsGrid.Mark.of(.battery) == .battery && ForkMacBackupSlotsGrid.Mark.of(.lowPower) == .battery
                        && ForkMacBackupSlotsGrid.Mark.of(.peerOffline) == .network
                        && ForkMacBackupSlotsGrid.Mark.of(.meeting) == .paused
                        && ForkMacBackupSlotsGrid.Mark.of(.notApproved) == .missed && !marks.contains { $0.ran },
                     "each missed reason has its ring: ○z ○b ○r ○p")

        // Two slots in one cell: the run wins over the reason, a failure over a success.
        let crowded = [ForkMacBackupSlotRecord(due: date("2026-10-22 08:00"), outcome: .missed(.battery)),
                       ForkMacBackupSlotRecord(due: date("2026-10-22 09:00"), outcome: .done,
                                               startedAt: date("2026-10-22 09:40"))]
        let forced = ForkMacBackupSlotsGrid.build(slots: crowded, now: now, days: 1, calendar: paris, hoursPerColumn: 4)
        let cell = forced.rows[0].cells[2]
        suite.expect(cell.slots.count == 2 && cell.mark == .done && cell.caughtUpAt == date("2026-10-22 09:40"),
                     "a cell holds both, shows the run, and its late start as the catch-up")
        let failing = ForkMacBackupSlotsGrid.build(
            slots: [ForkMacBackupSlotRecord(due: date("2026-10-22 08:00"), outcome: .done),
                    ForkMacBackupSlotRecord(due: date("2026-10-22 09:00"), outcome: .failed)],
            now: now, days: 1, calendar: paris, hoursPerColumn: 4)
        suite.expect(failing.rows[0].cells[2].mark == .failed, "a failure is never hidden by a success beside it")

        suite.expect(ForkMacBackupSlotsGrid.hoursPerColumn(for: []) == 4
                        && ForkMacBackupSlotsGrid.hoursPerColumn(for: (0..<12).map {
                            ForkMacBackupSlotRecord(due: now.addingTimeInterval(Double($0) * 7_200), outcome: .done)
                        }) == 2
                        && ForkMacBackupSlotsGrid.hoursPerColumn(for: (0..<6).map {
                            ForkMacBackupSlotRecord(due: now.addingTimeInterval(Double($0) * 5_400), outcome: .done)
                        }) == 2
                        && ForkMacBackupSlotsGrid.hoursPerColumn(for: (0..<6).map {
                            ForkMacBackupSlotRecord(due: now.addingTimeInterval(Double($0) * 86_400), outcome: .done)
                        }) == 24,
                     "the column follows the rhythm: 2 h, 1 h 30 → 2 h, daily → one column")
        let empty = ForkMacBackupSlotsGrid.build(slots: [], now: now, calendar: paris)
        suite.expect(empty.rows.count == 30 && empty.rows.allSatisfy { $0.cells.count == 6 },
                     "thirty days by default, even without a slot")
    }

    /// The clock goes back on 25/10/2026 in Paris (a 25-hour day) and
    /// forward on 29/03/2026 (23 hours): a day stays one row, an hour the
    /// clock's hour.
    private static func slotsGridAcrossClockChanges(_ suite: TestSuite) {
        let paris = calendar("Europe/Paris")
        let fallBack = date("2026-10-25 00:00")
        var slots: [ForkMacBackupSlotRecord] = []
        // Every hour of real time across the long day: 25 slots.
        for hour in 0..<25 {
            slots.append(ForkMacBackupSlotRecord(due: fallBack.addingTimeInterval(Double(hour) * 3_600), outcome: .done))
        }
        let now = date("2026-10-26 12:00")
        let grid = ForkMacBackupSlotsGrid.build(slots: slots, now: now, days: 2, calendar: paris)
        suite.expect(grid.hoursPerColumn == 1 && grid.rows.count == 2, "hourly slots: hourly columns, two days")
        let long = grid.rows[0]
        suite.expect(paris.component(.day, from: long.day) == 25 && long.cells.count == 24
                        && long.cells.allSatisfy { $0.mark == .done },
                     "the 25-hour day is one row of 24 clock hours")
        suite.expect(long.cells[2].slots.count == 2 && long.cells.map(\.slots.count).reduce(0, +) == 25,
                     "02:00 happened twice: both slots in the 02 column, none lost")

        let springForward = date("2026-03-29 00:00")
        let spring = (0..<23).map {
            ForkMacBackupSlotRecord(due: springForward.addingTimeInterval(Double($0) * 3_600), outcome: .done)
        }
        let short = ForkMacBackupSlotsGrid.build(slots: spring, now: date("2026-03-29 23:30"), days: 1, calendar: paris)
        suite.expect(short.rows.count == 1 && short.rows[0].cells[2].mark == .empty
                        && short.rows[0].cells.filter { $0.mark == .done }.count == 23,
                     "the 23-hour day has no 02:00: that cell stays empty, the 23 others are filled")

        // Another zone gives another calendar day to the same instant.
        let instant = date("2026-10-22 23:30", "UTC")
        let one = [ForkMacBackupSlotRecord(due: instant, outcome: .done)]
        let tokyo = ForkMacBackupSlotsGrid.build(slots: one, now: instant.addingTimeInterval(86_400), days: 2,
                                                 calendar: calendar("Asia/Tokyo"), hoursPerColumn: 4)
        suite.expect(tokyo.rows[0].cells[2].mark == .done, "in Tokyo it is the 23rd at 08:30")
    }

    // MARK: Timeline

    private static func timeline(_ suite: TestSuite) {
        let paris = calendar("Europe/Paris")
        let end = date("2026-10-22 12:00")
        var snapshots: [ForkMacBackupTimeline.Snapshot] = []
        for index in 0..<40 {
            let when = end.addingTimeInterval(-Double(index) * 4 * 3_600)
            let level: ForkMacBackupProofLevel = index == 3 ? .present : .complete
            snapshots.append(ForkMacBackupTimeline.Snapshot(manifestID: "m\(index)", date: when, level: level,
                                                            isPartial: index == 3))
        }
        let day = ForkMacBackupTimeline.build(snapshots, zoom: .day, end: end, calendar: paris)
        suite.expect(day.points.count == 7 && day.points.allSatisfy { $0.count == 1 },
                     "a day at one per four hours: seven dots, one each (both ends included)")
        suite.expect(day.points.first?.fraction == 0 && day.points.last?.fraction == 1
                        && day.points.map { (point: ForkMacBackupTimeline.Point) in point.fraction }
                        == day.points.map { (point: ForkMacBackupTimeline.Point) in point.fraction }.sorted(),
                     "dots placed along the span, oldest left")
        suite.expect(day.ticks.count == 9 && day.ticks.allSatisfy { paris.component(.hour, from: $0.date) % 3 == 0 },
                     "the day's axis marks every three clock hours")

        let week = ForkMacBackupTimeline.build(snapshots, zoom: .week, end: end, calendar: paris)
        let weekCounts: [Int] = week.points.map { (point: ForkMacBackupTimeline.Point) in point.count }
        suite.expect(weekCounts.allSatisfy { $0 <= 2 } && weekCounts.reduce(0, +) == 40,
                     "a week: six-hour buckets, every snapshot of the span in one of them")
        let partial = week.points.first { $0.snapshots.contains { $0.manifestID == "m3" } }
        suite.expect(partial?.newest.date ?? .distantPast >= partial?.snapshots.last?.date ?? .distantFuture,
                     "a bucket keeps its newest snapshot first")
        suite.expect(week.ticks.count == 7 && week.ticks.allSatisfy { paris.component(.hour, from: $0.date) == 0 },
                     "the week's axis marks each midnight")

        let month = ForkMacBackupTimeline.build(snapshots, zoom: .month, end: end, calendar: paris)
        let monthCounts: [Int] = month.points.map { (point: ForkMacBackupTimeline.Point) in point.count }
        suite.expect(month.points.count == 7 && monthCounts.reduce(0, +) == 40,
                     "a month: one dot per day, all forty snapshots")
        suite.expect(month.ticks.allSatisfy { paris.component(.weekday, from: $0.date) == paris.firstWeekday },
                     "the month's axis marks each week's first day")

        let shifted = ForkMacBackupTimeline.shifted(end: end, zoom: .week, direction: -1, now: end, calendar: paris)
        suite.expect(shifted == date("2026-10-15 12:00")
                        && ForkMacBackupTimeline.shifted(end: shifted, zoom: .month, direction: 1, now: end, calendar: paris) == end,
                     "earlier and later move by one span, never past now")
        suite.expect(ForkMacBackupTimeline.endShowing(end.addingTimeInterval(-3_600), currentEnd: end, zoom: .day, now: end,
                                                      calendar: paris) == end
                        && ForkMacBackupTimeline.endShowing(end.addingTimeInterval(-3 * 86_400), currentEnd: end, zoom: .day,
                                                            now: end, calendar: paris)
                        == end.addingTimeInterval(-3 * 86_400 + 12 * 3_600),
                     "a date in view keeps the view; one outside comes to the middle")
        suite.expect(ForkMacBackupTimeline.neighbor(of: "m5", step: -1, in: snapshots)?.manifestID == "m6"
                        && ForkMacBackupTimeline.neighbor(of: "m5", step: 1, in: snapshots)?.manifestID == "m4"
                        && ForkMacBackupTimeline.neighbor(of: "m0", step: 1, in: snapshots) == nil
                        && ForkMacBackupTimeline.neighbor(of: nil, step: -1, in: snapshots)?.manifestID == "m0",
                     "← is older, → is newer, nothing after the last; no selection goes to the latest")
        suite.expect(ForkMacBackupTimelineZoom.day.wider == .week && ForkMacBackupTimelineZoom.month.wider == nil
                        && ForkMacBackupTimelineZoom.day.narrower == nil, "the zoom steps")
    }

    private static func timelineAcrossClockChanges(_ suite: TestSuite) {
        let paris = calendar("Europe/Paris")
        let start = date("2026-10-25 00:00")
        let snapshots = (0..<25).map { hour in
            ForkMacBackupTimeline.Snapshot(manifestID: "h\(hour)", date: start.addingTimeInterval(Double(hour) * 3_600),
                                           level: .complete, isPartial: false)
        }
        let end = date("2026-10-26 00:00")
        let day = ForkMacBackupTimeline.build(snapshots, zoom: .day, end: end, calendar: paris)
        suite.expect(abs(day.end.timeIntervalSince(day.start) - 25 * 3_600) < 1, "the 25-hour day spans 25 hours")
        suite.expect(day.points.map(\.count).reduce(0, +) == 25 && day.points.contains { $0.count == 2 },
                     "02:00 twice: one dot holds both, nothing lost")
        let hours = day.ticks.map { paris.component(.hour, from: $0.date) }
        suite.expect(hours == [0, 3, 6, 9, 12, 15, 18, 21, 0], "the clock's own hours mark the axis: \(hours)")
    }

    // MARK: « Is this file backed up? »

    private static func ignoreRules(_ suite: TestSuite) {
        let rules = ["/.Trash/", "/Library/Caches/", "node_modules/", "*.log", "Virtual Machines.localized/",
                     "/Library/Containers/com.utmapp.UTM/", "!keep.log", "# a comment", "build/"]
        func rule(_ path: String, _ isDirectory: Bool = false) -> String? {
            ForkMacBackupIgnoreMatcher(rules: rules).excludingRule(for: path, isDirectory: isDirectory)
        }
        suite.expect(rule(".Trash/a.txt") == "/.Trash/" && rule("Documents/.Trash/a.txt") == nil,
                     "a leading slash anchors at the source's root")
        suite.expect(rule("Projets/app/node_modules/x/index.js") == "node_modules/" && rule("node_modules", true) == "node_modules/"
                        && rule("Documents/node_modules") == nil,
                     "a folder rule matches at any depth, folders only")
        suite.expect(rule("Library/Logs/x.log") == "*.log" && rule("Library/Logs/keep.log") == nil,
                     "a glob matches names; « ! » takes a file back")
        suite.expect(rule("Library/Containers/com.utmapp.UTM/Data/disk.img") == "/Library/Containers/com.utmapp.UTM/"
                        && rule("Library/Containers/com.apple.Notes/x") == nil, "a deep anchored rule")
        suite.expect(rule("Documents/Virtual Machines.localized/Win.vm/disk") == "Virtual Machines.localized/",
                     "names with spaces and dots")
        suite.expect(ForkMacBackupIgnoreMatcher(rules: ["build/", "!build/keep.log"]).excludingRule(for: "build/keep.log",
                                                                                                   isDirectory: false) == "build/",
                     "a file is never taken back out of a folder left out")
        suite.expect(rule("") == nil && rule("Documents/a.pdf") == nil, "the root and ordinary files are kept")
    }

    private static func verdicts(_ suite: TestSuite) {
        let home = "/Users/m"
        let sources = [ForkMacBackupSource(path: home, presets: [], customRules: ["node_modules/"]),
                       ForkMacBackupSource(path: home + "/Projets/app", presets: [], customRules: ["dist/"])]
        let saved = now.addingTimeInterval(-7_200)
        let facts = ForkMacBackupLocalStatus.LocalFacts(isDirectory: false, size: 10, modified: saved.addingTimeInterval(-60))
        func decide(_ path: String, local: ForkMacBackupLocalStatus.LocalFacts? = facts, cloud: Bool = false,
                    iCloud: ForkMacBackupICloudMode = .local, found: ForkMacBackupFileVerdict.Found? = nil,
                    lookedUp: Bool = true) -> ForkMacBackupFileVerdict {
            ForkMacBackupFileVerdict.decide(path: path, isDirectory: false, local: local, isCloudOnly: cloud, iCloud: iCloud,
                                            sources: sources, found: found, lookedUp: lookedUp, nextBackup: now)
        }
        let same = ForkMacBackupFileVerdict.Found(snapshotDate: saved, isDirectory: false, size: 10,
                                                  modified: saved.addingTimeInterval(-60))
        suite.expect(ForkMacBackupFileVerdict.source(of: home + "/Projets/app/x", in: sources)?.path == home + "/Projets/app",
                     "the deepest source holds the file")
        suite.expect(decide(home + "/Documents/a.pdf", found: same) == .backedUp(at: saved), "same file: backed up")
        var changed = same
        changed.size = 9
        suite.expect(decide(home + "/Documents/a.pdf", found: changed) == .modifiedSince(backedUpAt: saved, modified: facts.modified),
                     "changed since: says when it was saved")
        suite.expect(decide(home + "/Documents/new.pdf") == .notYet(nextBackup: now), "a new file: not yet, with the next backup")
        suite.expect(decide(home + "/Documents/new.pdf", lookedUp: false) == .unknown, "no snapshot read: unknown")
        suite.expect(decide(home + "/x/node_modules/a.js") == .excluded(rule: "node_modules/"), "left out by its rule")
        suite.expect(decide(home + "/Projets/app/dist/a.js") == .excluded(rule: "dist/"), "the inner source's own rule")
        suite.expect(decide("/tmp/a.txt") == .outsideSources, "outside every source")
        suite.expect(decide(home + "/Library/Mobile Documents/a.pages", cloud: true) == .cloudOnly
                        && decide(home + "/Library/Mobile Documents/a.pages", cloud: true, iCloud: .materialize)
                        == .notYet(nextBackup: now),
                     "in iCloud only: never backed up unless the mode downloads it")
        suite.expect(decide(home + "/Library/Mobile Documents/a.pages", cloud: true, found: same) == .backedUp(at: saved),
                     "a cloud file already in a snapshot is backed up")
    }

    private static func capacity(_ suite: TestSuite) {
        suite.expect(ForkMacBackupCapacitySupport.latest([
            ForkMacBackupCapacitySample(kind: .real, bytes: 333_000_000_000, date: now.addingTimeInterval(-7_200), source: "snapshot"),
            ForkMacBackupCapacitySample(kind: .real, bytes: 0, date: now.addingTimeInterval(-60), source: "snapshot"),
        ], kind: .real)?.bytes == 333_000_000_000,
                     "a real size of 0 (build 2331, a source not matched) is never shown as « Zéro ko »")
        func sample(_ kind: ForkMacBackupCapacitySample.Kind, _ daysAgo: Double, _ bytes: Int64) -> ForkMacBackupCapacitySample {
            ForkMacBackupCapacitySample(kind: kind, bytes: bytes, date: now.addingTimeInterval(-daysAgo * 86_400), source: "x")
        }
        let samples = [sample(.physical, 100, 1), sample(.physical, 60, 600), sample(.physical, 30, 900),
                       sample(.physical, 0, 1_200), sample(.real, 1, 50), sample(.nasFree, 2, 9_000), sample(.nasFree, 1, 8_000)]
        let series = ForkMacBackupCapacitySupport.series(samples, kind: .physical, now: now)
        suite.expect(series.map(\.bytes) == [600, 900, 1_200], "90 days of one kind, oldest first")
        suite.expect(ForkMacBackupCapacitySupport.latest(samples, kind: .nasFree)?.bytes == 8_000
                        && ForkMacBackupCapacitySupport.latest(samples, kind: .sent) == nil,
                     "the newest measure, or none (« inconnu »)")
        let months = ForkMacBackupCapacitySupport.monthsUntilFull(physical: series, free: 3_000)
        suite.expect(months.map { abs($0 - 3_000 / 10 / 30.44) < 0.01 } == true, "10 bytes a day, 3 000 free: ≈ 9,9 months")
        suite.expect(ForkMacBackupCapacitySupport.monthsUntilFull(physical: series, free: nil) == nil
                        && ForkMacBackupCapacitySupport.monthsUntilFull(physical: Array(series.prefix(2)), free: 3_000) == nil
                        && ForkMacBackupCapacitySupport.monthsUntilFull(
                            physical: [sample(.physical, 30, 1_200), sample(.physical, 15, 900), sample(.physical, 0, 600)],
                            free: 3_000) == nil,
                     "no forecast without a free space, enough measures, or growth")
    }

    private static func dates(_ suite: TestSuite) {
        let paris = calendar("Europe/Paris")
        var components = Locale.Components(identifier: "fr_FR")
        components.hourCycle = .zeroToTwentyThree
        let fr = Locale(components: components)
        let thisYear = ForkMacBackupWindowDates.short(date("2026-10-22 10:04"), now: date("2026-10-22 12:00"), locale: fr,
                                                      calendar: paris)
        let lastYear = ForkMacBackupWindowDates.short(date("2025-10-22 10:04"), now: date("2026-10-22 12:00"), locale: fr,
                                                      calendar: paris)
        suite.expect(!thisYear.contains("2026") && thisYear.contains("10:04") && lastYear.contains("2025"),
                     "the year only when it is not this one: \(thisYear) / \(lastYear)")
        var us = Locale.Components(identifier: "en_US")
        us.hourCycle = .oneToTwelve
        let english = ForkMacBackupWindowDates.short(date("2026-10-22 22:04"), now: date("2026-10-22 23:00"),
                                                     locale: Locale(components: us), calendar: paris)
        suite.expect(english.contains("10:04") && english.contains("PM"), "a 12-hour clock stays one: \(english)")
        let instant = ForkMacBackupWindowDates.relative(now, now: now, locale: Locale(identifier: "fr_FR"))
        suite.expect(!instant.contains("0") && !instant.isEmpty, "the same instant reads « maintenant », never « dans 0 s »: \(instant)")
        suite.expect(ForkMacBackupWindowDates.relative(now.addingTimeInterval(-7_200), now: now, locale: Locale(identifier: "fr_FR"))
                        .contains("2"), "two hours ago")
    }

    // MARK: Words

    private static let sameEverywhere: Set<String> = ["latency", "triggerCommandBar"]
    /// Words that really are the same as in English (Apple's own Finder and
    /// Time Machine terms in these languages).
    private static let sameInLanguage: Set<String> = [
        "pt-BR.windowTitle", "pt-BR.itemsOne", "pt-BR.kindBackup", "pt-BR.savesOne", "pt-BR.savesFew", "pt-BR.savesMany",
        "it.kindBackup", "it.savesOne", "de.windowTitle", "de.columnName", "de.levelManifest",
        "fr.versionsCount", "fr.versions", "fr.source", "fr.kindMaintenance", "fr.triggerAgent", "fr.columnDate",
        "fr.columnConditions",
    ]
    /// Russian and Ukrainian carry `%d` in their « one » form (21, 31…).
    private static let oneForms: Set<String> = ["itemsOne", "unreadOne", "searchResultsOne", "cloudOne", "selectedOne",
                                                "savesOne", "distinctOne", "restoredOne", "errorsOne", "fullOne"]

    private static func fields(_ strings: ForkMacBackupWindowStrings) -> [(String, String)] {
        Mirror(reflecting: strings).children.compactMap { child in
            guard let label = child.label, let value = child.value as? String else { return nil }
            return (label, value)
        }
    }

    private static func placeholders(_ text: String) -> [String] {
        var found: [String] = []
        var rest = Substring(text)
        while let range = rest.range(of: "%") {
            let next = rest[range.upperBound...].prefix(1)
            if next == "@" || next == "d" { found.append("%" + next) }
            rest = rest[range.upperBound...]
        }
        return found
    }

    private static func strings(_ suite: TestSuite) {
        let english = Dictionary(uniqueKeysWithValues: fields(.enUS))
        suite.expect(AppLanguage.allCases.count == 15 && english.count > 200, "fifteen languages, every window word")
        var empty: [String] = []
        var untranslated: [String] = []
        var wrongPlaceholders: [String] = []
        var straightApostrophes: [String] = []
        for language in AppLanguage.allCases {
            let values = fields(.strings(language))
            if values.count != english.count { empty.append("\(language.rawValue): \(values.count) fields") }
            for (label, value) in values {
                let tag = "\(language.rawValue).\(label)"
                if value.trimmingCharacters(in: .whitespaces).isEmpty { empty.append(tag) }
                if language != .enUS, value == english[label], !sameEverywhere.contains(label), !sameInLanguage.contains(tag) {
                    untranslated.append(tag)
                }
                let expected = placeholders(english[label] ?? "")
                let actual = placeholders(value)
                let oneWithCount = oneForms.contains(label) && (language == .ru || language == .uk) && actual == ["%d"]
                if actual != expected, !oneWithCount { wrongPlaceholders.append(tag) }
                if value.contains("'") { straightApostrophes.append(tag) }
            }
        }
        suite.expect(empty.isEmpty, "every window word exists in every language: \(empty)")
        suite.expect(untranslated.isEmpty, "every window word is really translated: \(untranslated)")
        suite.expect(wrongPlaceholders.isEmpty, "every translation keeps its placeholders: \(wrongPlaceholders)")
        suite.expect(straightApostrophes.isEmpty, "typographic apostrophes only: \(straightApostrophes)")

        var typography: [String] = []
        for (label, value) in fields(.fr) {
            let scalars = Array(value.unicodeScalars)
            for (index, scalar) in scalars.enumerated() where ":;!?".unicodeScalars.contains(scalar) {
                if index == 0 || scalars[index - 1] != "\u{00A0}" { typography.append(label) }
            }
            if value.contains("« ") || value.contains(" »") { typography.append(label) }
        }
        suite.expect(typography.isEmpty, "French: no-break space before : ; ! ? and inside « »: \(typography)")

        let fr = ForkMacBackupWindowStrings.strings(.fr)
        suite.expect(fr.items(1, .fr) == "1 élément" && fr.items(3, .fr) == "3 éléments" && fr.saves(0, .fr) == "0 sauvegardes",
                     "French agrees one and many")
        let ru = ForkMacBackupWindowStrings.strings(.ru)
        suite.expect(ru.restored(21, .ru).contains("21") && ru.restored(21, .ru) != ru.restored(25, .ru).replacingOccurrences(of: "25", with: "21")
                        && ru.restored(22, .ru).replacingOccurrences(of: "22", with: "") != ru.restored(25, .ru).replacingOccurrences(of: "25", with: ""),
                     "Russian agrees 21, 22 and 25 each its own way")
        let sk = ForkMacBackupWindowStrings.strings(.sk)
        suite.expect(sk.items(3, .sk).replacingOccurrences(of: "3", with: "") != sk.items(5, .sk).replacingOccurrences(of: "5", with: ""),
                     "Slovak has a form for two to four")
        suite.expect(fr.title(.verifications) == fr.tabVerifications && fr.title(.keepBoth).contains("restauré")
                        && fr.title(ForkMacBackupLocalStatus.unknown) == "—" && fr.capacitySource("blobStats") == fr.sourceBlobStats
                        && fr.capacitySource("qnap") == "qnap",
                     "enumerations have their words; an unknown source keeps its own name")
        let shared = ForkMacBackupStrings.strings(.fr)
        suite.expect(ForkMacBackupMissedReason.allCases.allSatisfy { !fr.title($0, shared: shared).isEmpty }
                        && ForkMacBackupSlotsGrid.Mark.allCases.filter { $0 != .empty }.allSatisfy { !fr.title($0).isEmpty }
                        && ForkMacBackupTrigger.allCases.allSatisfy { !fr.title($0).isEmpty }
                        && ForkMacBackupStopReason.allCases.allSatisfy { !fr.title($0).isEmpty },
                     "every reason, mark, trigger and stop has its word")
        let locale = Locale(identifier: "fr_FR")
        suite.expect(fr.title(.contentSample(percent: 1), locale: locale).contains("1")
                        && fr.title(.restoreTest(files: 50), locale: locale) == fr.levelRestoreTest,
                     "a verification level reads with its percentage")
    }
}
