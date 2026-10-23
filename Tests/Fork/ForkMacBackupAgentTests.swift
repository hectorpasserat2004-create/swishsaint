// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Suite `fork-macbackup-agent`: the pure side of the agent
/// (`Fork/MacBackup/Agent/Pure`): settings, planner (Automatic rhythm, manual
/// rhythms across DST, catch-up, meetings), slot ledger, state machine
/// (watchdog, backoff, partial, exit 1 with JSON), presentation, IPC rules,
/// launchd plist, single instance, pending changes, neighbours, cost.
enum ForkMacBackupAgentTests {
    static func run(_ suite: TestSuite) {
        settings(suite)
        mode(suite)
        plannerAutomatic(suite)
        regression2331(suite)
        automaticSafetyNet(suite)
        plannerConditions(suite)
        plannerManualRhythms(suite)
        plannerCatchUp(suite)
        ledger(suite)
        slotBook(suite)
        machineHappyPath(suite)
        machineConclusions(suite)
        machineMultiSourceContinuity(suite)
        machineFailures(suite)
        machineStops(suite)
        machineLimitsAndVerify(suite)
        waits(suite)
        tracker(suite)
        presenter(suite)
        ipc(suite)
        commands(suite)
        plist(suite)
        lock(suite)
        pending(suite)
        tailscale(suite)
        otherEngine(suite)
        sparseImages(suite)
        cost(suite)
        proofStore(suite)
        journal(suite)
        priorities(suite)
        importedRules(suite)
        prescanPlan(suite)
        materialize(suite)
        strings(suite)
    }

    // MARK: Helpers

    private static let t0 = Date(timeIntervalSince1970: 1_792_663_440) // 22/10/2026
    private static let hour: TimeInterval = 3_600
    private static let home = "/Users/test"

    private static let repository = ForkMacBackupRepository(
        endpoint: .init(host: "minio.example.ts.net", port: 9000, tls: false, observedIPs: ["100.64.0.7"]),
        bucket: "mac-test", region: "us-east-1", prefix: "home/", accessKeyID: "kopia-test",
        clientIdentity: .init(userName: "test", hostName: "test-mac"),
        peer: .init(stableID: "nABC123CNTRL", dnsName: "minio.example.ts.net.", hostName: "minio"),
        serverFlavor: .minio)

    private static func settings(_ values: [String: Any] = [:], sources: [String] = ["/Users/test"],
                                 configured: Bool = true) -> ForkMacBackupAgentSettings {
        var all = values
        all[ForkDefaultsKey.macBackupEnabled] = all[ForkDefaultsKey.macBackupEnabled] ?? true
        if configured {
            all[ForkDefaultsKey.macBackupRepository] = try! ForkMacBackupJSON.encoder.encode(repository)
            all[ForkDefaultsKey.macBackupSources] = try! ForkMacBackupJSON.encoder.encode(
                sources.map { ForkMacBackupSource(path: $0) })
        }
        return ForkMacBackupAgentSettings { all[$0] }
    }

    private static func utc(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)!
    }

    private static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private static let paris = calendar("Europe/Paris")

    private static func input(_ settings: ForkMacBackupAgentSettings, now: Date,
                              conditions: ForkMacBackupConditions = ForkMacBackupConditions(network: .available(limited: false)),
                              lastBackup: Date? = nil, pending: ForkMacBackupPendingSummary? = nil)
        -> ForkMacBackupPlanner.Input {
        ForkMacBackupPlanner.Input(now: now, calendar: paris, settings: settings, conditions: conditions,
                                   lastBackup: lastBackup, pending: pending)
    }

    private static func changes(_ total: Int, important: Int = 0, weighted: Double? = nil) -> ForkMacBackupPendingSummary {
        ForkMacBackupPendingSummary(total: total, important: important,
                                    weighted: weighted ?? Double(important) * 5 + Double(total - important))
    }

    private static func fixture(_ name: String) -> Data? {
        try? Data(contentsOf: URL(fileURLWithPath: "Tests/Fork/Fixtures/MacBackup/\(name)"))
    }

    private static func manifest(id: String, path: String = "/Users/test", start: Date, end: Date,
                                 errors: [String] = [], incomplete: String? = nil,
                                 host: String = "test-mac", user: String = "test") -> ForkMacBackupKopia.SnapshotManifest {
        let iso = ISO8601DateFormatter()
        let errorJSON = errors.map { "{\"path\":\"\($0)\",\"error\":\"open: permission denied\"}" }.joined(separator: ",")
        let incompleteJSON = incomplete.map { ",\"incomplete\":\"\($0)\"" } ?? ""
        let text = """
        {"id":"\(id)","source":{"host":"\(host)","userName":"\(user)","path":"\(path)"},
         "startTime":"\(iso.string(from: start))","endTime":"\(iso.string(from: end))"\(incompleteJSON),
         "stats":{"totalSize":1000,"fileCount":10,"errorCount":\(errors.count),"ignoredErrorCount":0},
         "rootEntry":{"name":"x","type":"d","obj":"k1","summ":{"size":1000,"files":10,"dirs":1,
           "numFailed":\(errors.count),"errors":[\(errorJSON)]}}}
        """
        return ForkMacBackupKopia.decode(ForkMacBackupKopia.SnapshotManifest.self, from: Data(text.utf8))!
    }

    /// Whether `actions` ask how `source`'s snapshot ended.
    private static func concludes(_ actions: [ForkMacBackupMachine.Action], _ source: ForkMacBackupSource) -> Bool {
        actions.contains { action in
            if case .conclude(let concluded, _, _) = action { return concluded == source }
            return false
        }
    }

    private static func sources(path: String = "/Users/test", uploading: Bool, hashed: Int64 = 0,
                                estimate: Int64 = 0, uploaded: Int64 = 0, files: Int64 = 0,
                                last: (start: Date, end: Date)? = nil) -> ForkMacBackupKopia.SourcesResponse {
        let iso = ISO8601DateFormatter()
        let upload = uploading ? """
        ,"upload":{"hashedBytes":\(hashed),"cachedBytes":0,"uploadedBytes":\(uploaded),"estimatedBytes":\(estimate),
          "hashedFiles":\(files),"cachedFiles":0,"estimatedFiles":\(estimate > 0 ? 100 : 0),"errors":0,"ignoredErrors":0,
          "directory":"Documents"}
        """ : ""
        let lastJSON = last.map {
            ",\"lastSnapshot\":{\"id\":\"prev\",\"startTime\":\"\(iso.string(from: $0.start))\",\"endTime\":\"\(iso.string(from: $0.end))\"}"
        } ?? ""
        let text = """
        {"localUsername":"test","localHost":"test-mac","sources":[{"source":{"host":"test-mac","userName":"test","path":"\(path)"},
         "status":"\(uploading ? "UPLOADING" : "IDLE")"\(upload)\(lastJSON)}]}
        """
        return ForkMacBackupKopia.decode(ForkMacBackupKopia.SourcesResponse.self, from: Data(text.utf8))!
    }

    // MARK: Settings

    private static func settings(_ suite: TestSuite) {
        let defaults = ForkMacBackupAgentSettings { _ in nil }
        suite.expect(!defaults.enabled && defaults.scheduleMode == .auto && defaults.intervalHours == 4
                        && defaults.catchUpDelay == 180 && defaults.powerMode == .threshold
                        && defaults.minBatteryPercent == 30 && defaults.forceAfter == 24 * hour
                        && defaults.meetingMode == .slow && defaults.slowBytesPerSecond == 2_000_000
                        && defaults.keepAwake == .ac && defaults.limitedNetwork == .wait && !defaults.isConfigured,
                     "the agent's settings default to the registered values (Automatic, slow 2 MB/s in meetings…)")
        suite.expect(defaults.times.map(\.storage) == ["13:00", "21:00"], "the default fixed times read back")
        let odd = ForkMacBackupAgentSettings { key in
            [ForkDefaultsKey.macBackupIntervalHours: 400, ForkDefaultsKey.macBackupTimes: "21:00, 7:05,bad,25:00,07:05",
             ForkDefaultsKey.macBackupThrottleWindow: "22:00-06:00@5", ForkDefaultsKey.macBackupPowerMode: "nonsense"][key]
        }
        suite.expect(odd.intervalHours == 48 && odd.times.map(\.storage) == ["07:05", "21:00"] && odd.powerMode == .threshold,
                     "out-of-range and malformed values are clamped, sorted, deduplicated or replaced by the default")
        let window = odd.throttleWindow
        suite.expect(window?.contains(.init(hour: 23, minute: 0)) == true && window?.contains(.init(hour: 5, minute: 59)) == true
                        && window?.contains(.init(hour: 12, minute: 0)) == false,
                     "a throttle window across midnight contains the night only")
        suite.expect(ForkMacBackupAgentSettings.ThrottleWindow.parse("09:00-09:00@5") == nil
                        && ForkMacBackupAgentSettings.ThrottleWindow.parse("09:00-19:00@0") == nil,
                     "an empty window or a zero limit is no window")
        let configured = settings()
        suite.expect(configured.isConfigured && configured.repository == repository && configured.sources.count == 1
                        && configured.chain.map(\.kind) == [.mac, .network, .tailscale, .s3, .repository],
                     "the machine state (repository, sources) decodes, and the default chain follows")
        let fromString = ForkMacBackupAgentSettings { key in
            key == ForkDefaultsKey.macBackupRepository
                ? String(decoding: try! ForkMacBackupJSON.encoder.encode(repository), as: UTF8.self) : nil
        }
        suite.expect(fromString.repository == repository, "the repository may also be stored as a JSON string")
    }

    private static func mode(_ suite: TestSuite) {
        suite.expect(ForkMacBackupAgent.isRequested(["/Applications/Swishsaint.app/Contents/MacOS/Swishsaint", "--fork-backup-agent"]),
                     "the agent mode is requested by its flag")
        suite.expect(ForkMacBackupAgent.isRequested(["--fork-backup-agent"]),
                     "the flag is found even as argv[0] (a plist without the program's name)")
        suite.expect(!ForkMacBackupAgent.isRequested(["/x/Swishsaint"]) && !ForkMacBackupAgent.isRequested(["/x", "--selftest"])
                        && !ForkMacBackupAgent.isRequested(["/x", "--fork-backup-agent=1"]) && !ForkMacBackupAgent.isRequested([]),
                     "a normal launch, the selftest or a look-alike flag never start the agent")
    }

    // MARK: Planner

    private static func plannerAutomatic(_ suite: TestSuite) {
        let auto = settings()
        let last = t0
        func decide(_ minutes: Double, _ pending: ForkMacBackupPendingSummary?,
                    conditions: ForkMacBackupConditions = ForkMacBackupConditions(network: .available(limited: false)))
            -> ForkMacBackupPlanner.Decision {
            ForkMacBackupPlanner.decide(input(auto, now: last.addingTimeInterval(minutes * 60), conditions: conditions,
                                              lastBackup: last, pending: pending))
        }
        suite.expect(decide(30, changes(10, important: 2)) == .idle(next: last.addingTimeInterval(4 * hour)),
                     "Automatic on AC: important changes within the first hour wait (at least 1 h apart)")
        suite.expect(decide(70, changes(10, important: 2)) == .run(trigger: .scheduled, due: last.addingTimeInterval(70 * 60)),
                     "Automatic on AC: important changes after 1 h back up at once, in a slot of their own")
        suite.expect(decide(70, changes(3)) == .idle(next: last.addingTimeInterval(4 * hour)),
                     "Automatic on AC: a few ordinary changes wait for the 4 h bound")
        suite.expect(decide(241, changes(3)) == .run(trigger: .scheduled, due: last.addingTimeInterval(4 * hour)),
                     "Automatic on AC: at most 4 h between backups when anything changed")
        suite.expect(decide(241, ForkMacBackupPendingSummary.none) == .nothingToDo(due: last.addingTimeInterval(4 * hour),
                                                         next: last.addingTimeInterval(8 * hour)),
                     "Automatic: nothing changed, no backup, a « nothing to do » slot")
        suite.expect(decide(241, nil) == .run(trigger: .scheduled, due: last.addingTimeInterval(4 * hour)),
                     "Automatic: changes not counted (FSEvents unavailable) back up at the bound")

        let battery = ForkMacBackupConditions(onAC: false, batteryPercent: 80, network: .available(limited: false))
        suite.expect(decide(120, changes(10, important: 2), conditions: battery) == .idle(next: last.addingTimeInterval(8 * hour)),
                     "Automatic on battery: a small need waits, up to 8 h")
        suite.expect(decide(120, changes(60, important: 10), conditions: battery)
                        == .run(trigger: .scheduled, due: last.addingTimeInterval(120 * 60)),
                     "Automatic on battery: a big need backs up")
        suite.expect(decide(481, changes(1), conditions: battery) == .run(trigger: .scheduled, due: last.addingTimeInterval(8 * hour)),
                     "Automatic on battery: at most 8 h apart")
        var low = battery
        low.batteryPercent = 25
        let due = last.addingTimeInterval(8 * hour)
        suite.expect(decide(481, changes(1), conditions: low)
                        == .wait(reason: .lowBattery, due: due, recheck: nil, forcedAt: due.addingTimeInterval(24 * hour)),
                     "Automatic on battery: never under 30 %, and says when it will be forced")
        suite.expect(decide(480 + 24 * 60 + 1, changes(1), conditions: low) == .run(trigger: .scheduled, due: due),
                     "Automatic on battery: forced after 24 h late")
        suite.expect(decide(130, changes(60, important: 10), conditions: low)
                        == .wait(reason: .lowBattery, due: nil, recheck: nil, forcedAt: nil),
                     "a big need on a low battery waits too")
        suite.expect(ForkMacBackupPlanner.decide(input(auto, now: t0, pending: changes(5000))) == .run(trigger: .scheduled, due: t0),
                     "Automatic: the very first backup is due at once")
    }

    /// Build 2331 on a real Mac: a source imported from Bran as « /Users/me/ »
    /// (trailing slash), Kopia's snapshots recorded as « /Users/me »: no proof
    /// matched, the planner believed nothing was ever backed up and started
    /// three complete backups back to back (runs, proofs and the one slot of
    /// that Mac, anonymized, in `agent-2331-*`).
    private static func regression2331(_ suite: TestSuite) {
        let stored = """
        [{"customRules":["*.pyc",".DS_Store"],"path":"\\/Users\\/test\\/","presets":["trash","caches","docker",\
        "appleContainer","sparseDiskImages","devFolders","cloudStorage","cacheDirTag","logs"]}]
        """
        let settings = ForkMacBackupAgentSettings { key in
            switch key {
            case ForkDefaultsKey.macBackupEnabled: return true
            case ForkDefaultsKey.macBackupRepository: return try? ForkMacBackupJSON.encoder.encode(repository)
            case ForkDefaultsKey.macBackupSources: return stored
            default: return nil
            }
        }
        suite.expect(settings.sources.map(\.path) == ["/Users/test"],
                     "2331: a source stored « /Users/test/ » is read « /Users/test », Kopia's own form")
        suite.expect(ForkMacBackupSourcePath.normalized("/Users/test/") == "/Users/test"
                        && ForkMacBackupSourcePath.normalized("/Users//test/./Documents/../") == "/Users/test"
                        && ForkMacBackupSourcePath.normalized("/") == "/" && ForkMacBackupSourcePath.normalized("///") == "/",
                     "one canonical form: standardized, no trailing « / » but for the root")
        let migrated = ForkMacBackupDefaults.canonicalSources(stored)
        let reread = migrated.flatMap { try? ForkMacBackupJSON.decoder.decode([ForkMacBackupSource].self, from: Data($0.utf8)) }
        suite.expect(migrated?.contains("\\/Users\\/test\"") == true && reread?.first?.customRules == ["*.pyc", ".DS_Store"]
                        && migrated.flatMap(ForkMacBackupDefaults.canonicalSources) == nil,
                     "2331: the stored sources are rewritten once in canonical form, their rules kept")
        let twice = "[{\"path\":\"/Users/test/\",\"presets\":[],\"customRules\":[]},{\"path\":\"/Users/test\",\"presets\":[],\"customRules\":[]}]"
        suite.expect(ForkMacBackupDefaults.canonicalSources(twice).flatMap {
            try? ForkMacBackupJSON.decoder.decode([ForkMacBackupSource].self, from: Data($0.utf8)) }?.count == 1,
                     "two spellings of one folder become one source")

        guard let proofData = fixture("agent-2331-proofs.json"), let proofs = ForkMacBackupProofStore.decode(proofData),
              let runData = fixture("agent-2331-runs.jsonl"), let slotData = fixture("agent-2331-slots.jsonl") else {
            suite.expect(false, "the 2331 fixtures are in Tests/Fork/Fixtures/MacBackup")
            return
        }
        let runs = ForkMacBackupJSON.lines(ForkMacBackupRunRecord.self, from: runData)
        let slots = ForkMacBackupJSON.lines(ForkMacBackupSlotRecord.self, from: slotData)
        let lastEnd = Date(timeIntervalSince1970: 1_792_761_233.620888)
        let lastBackup = proofs.lastBackup(paths: settings.sources.map(\.path))
        suite.expect(lastBackup == lastEnd && proofs.lastBackup(paths: ["/Users/test/"]) == lastEnd,
                     "2331: Kopia's « /Users/test » snapshots are the source's, whichever way it is written")
        suite.expect(proofs.last(of: "/Users/test/")?.manifestID == "62b13e88c8e0bc385d7d52aad8325920"
                        && proofs.lastComplete(of: "/Users/test/") != nil,
                     "2331: the last snapshot and the last complete one are found")
        let runEnd = ForkMacBackupRunRecord.lastProtectingEnd(runs)
        suite.expect(runs.count == 3 && runEnd == Date(timeIntervalSince1970: 1_792_761_236.151311),
                     "2331: the journal knows the three runs")
        // Martial's Mac 5 min after the third run: changes keep coming (his
        // home folder), the rhythm is Automatic, on AC.
        let now = runs[2].end!.addingTimeInterval(5 * 60)
        let busy = changes(400, important: 12)
        let book = ForkMacBackupSlotBook(lastClosedDue: slots.map(\.due).max())
        let fixed = ForkMacBackupPlanner.decide(ForkMacBackupPlanner.Input(
            now: now, calendar: paris, settings: settings, conditions: ForkMacBackupConditions(network: .available(limited: false)),
            lastBackup: lastBackup, lastRunEnd: runEnd, lastClosedDue: book.lastClosedDue, pending: busy))
        suite.expect(fixed == .idle(next: runEnd!.addingTimeInterval(hour)),
                     "2331: 5 min after a backup, Automatic waits for the 1 h gap (it started a fourth one)")
        let journalOnly = ForkMacBackupPlanner.decide(ForkMacBackupPlanner.Input(
            now: now, calendar: paris, settings: settings, conditions: ForkMacBackupConditions(network: .available(limited: false)),
            lastBackup: nil, lastRunEnd: runEnd, lastClosedDue: book.lastClosedDue, pending: busy))
        suite.expect(journalOnly == .idle(next: runEnd!.addingTimeInterval(hour)),
                     "2331: even with no proof matched, the run journal alone holds the gap")
        suite.expect(ForkMacBackupPlanner.decide(ForkMacBackupPlanner.Input(
            now: now, calendar: paris, settings: settings, conditions: ForkMacBackupConditions(network: .available(limited: false)),
            lastBackup: lastBackup, lastRunEnd: runEnd, pending: ForkMacBackupPendingSummary.none)) == .idle(next: runEnd!.addingTimeInterval(hour)),
                     "2331: nothing changed (pending 0): no backup")

        var cache = ForkMacBackupPrescanCache()
        var usage = ForkMacBackupDiskUsage()
        usage.allocatedBytes = 405_000_000_000
        cache.entries["/Users/test/"] = ForkMacBackupPrescanCache.Entry(date: t0, fingerprint: "x", usage: usage)
        let decoded = cache.encoded().flatMap(ForkMacBackupPrescanCache.decode)
        suite.expect(decoded?.entries.keys.sorted() == ["/Users/test"] && decoded?.entry(for: "/Users/test/")?.realBytes == 405_000_000_000
                        && decoded?.entry(for: "/Users/test")?.realBytes == 405_000_000_000,
                     "2331: the pre-scan of « /Users/test/ » is found for the snapshot of « /Users/test » (real size, reuse)")
        let response = sources(path: "/Users/test", uploading: true)
        suite.expect(response.source(path: "/Users/test/") != nil, "2331: Kopia's live source matches a source written with « / »")
        let proof = ForkMacBackupSnapshotProof(manifestID: "m", sourcePath: "/Users/test/", endTime: t0, level: .complete,
                                               bytes: 1, files: 1)
        suite.expect(proof.sourcePath == "/Users/test", "a proof keeps the canonical path")
    }

    /// The Automatic rhythm's safety net (fix of 2331): never two backups
    /// less than an hour apart, never one with nothing changed before the
    /// 4 h bound, and every run writes its slot. Changes keep pouring in, as
    /// in a busy home folder: over 6 h, backups an hour (plus their length)
    /// apart, never back to back.
    private static func automaticSafetyNet(_ suite: TestSuite) {
        let auto = settings()
        let online = ForkMacBackupConditions(network: .available(limited: false))
        var book = ForkMacBackupSlotBook()
        var runEnds: [Date] = []
        var starts: [Date] = []
        var slots: [ForkMacBackupSlotRecord] = []
        var clock = t0
        let runLength: TimeInterval = 9 * 60
        while clock < t0.addingTimeInterval(6 * hour) {
            let decision = ForkMacBackupPlanner.decide(ForkMacBackupPlanner.Input(
                now: clock, calendar: paris, settings: auto, conditions: online, lastBackup: nil, lastRunEnd: runEnds.last,
                lastClosedDue: book.lastClosedDue, openSlotDue: book.open?.due, pending: changes(300, important: 20)))
            if case .run(_, let due) = decision {
                if let due { book.open(due) }
                let id = UUID()
                book.runStarted(at: clock, runID: id)
                starts.append(clock)
                clock = clock.addingTimeInterval(runLength)
                runEnds.append(clock)
                if let slot = book.runEnded(.complete, runID: id, canceledByPerson: false) { slots.append(slot) }
            } else {
                clock = clock.addingTimeInterval(60)
            }
        }
        let gaps = zip(starts.dropFirst(), runEnds).map { $0.timeIntervalSince($1) }
        suite.expect(starts.count == 6 && gaps.allSatisfy { $0 >= hour },
                     "Automatic with changes pouring in: one backup an hour at most (\(starts.count) in 6 h), never back to back")
        suite.expect(slots.count == starts.count && slots.allSatisfy { $0.outcome == .done },
                     "every Automatic run writes its slot")

        let end = t0.addingTimeInterval(runLength)
        func decide(_ minutes: Double, _ pending: ForkMacBackupPendingSummary?) -> ForkMacBackupPlanner.Decision {
            ForkMacBackupPlanner.decide(ForkMacBackupPlanner.Input(
                now: end.addingTimeInterval(minutes * 60), calendar: paris, settings: auto, conditions: online,
                lastBackup: nil, lastRunEnd: end, lastClosedDue: t0, pending: pending))
        }
        suite.expect(decide(1, changes(5000, important: 900)) == .idle(next: end.addingTimeInterval(hour)),
                     "a burst of changes right after a backup waits for the 1 h gap")
        suite.expect(decide(61, ForkMacBackupPendingSummary.none) == .idle(next: end.addingTimeInterval(4 * hour)),
                     "past the gap, nothing changed: nothing before the 4 h bound")
        suite.expect(decide(4 * 60 + 1, ForkMacBackupPendingSummary.none) == .nothingToDo(due: end.addingTimeInterval(4 * hour),
                                                                next: end.addingTimeInterval(8 * hour)),
                     "at the bound with nothing changed: a « nothing to do » slot, no backup")
        var manual = ForkMacBackupPlanner.Input(now: end.addingTimeInterval(60), calendar: paris, settings: auto,
                                                conditions: online, lastRunEnd: end, pending: ForkMacBackupPendingSummary.none)
        manual.manual = .island
        suite.expect(ForkMacBackupPlanner.decide(manual) == .run(trigger: .island, due: nil),
                     "« Sauvegarder maintenant » is never held by the gap")
        let interval = settings([ForkDefaultsKey.macBackupScheduleMode: "interval", ForkDefaultsKey.macBackupIntervalHours: 1])
        suite.expect(ForkMacBackupPlanner.decide(ForkMacBackupPlanner.Input(
            now: end.addingTimeInterval(61 * 60), calendar: paris, settings: interval, conditions: online,
            lastRunEnd: end, pending: changes(1))) == .run(trigger: .scheduled, due: end.addingTimeInterval(hour)),
                     "a manual rhythm keeps its own interval, counted from the journal too")
    }

    private static func plannerConditions(_ suite: TestSuite) {
        let base = settings()
        let now = t0.addingTimeInterval(5 * hour)
        func decide(_ conditions: ForkMacBackupConditions, settings: ForkMacBackupAgentSettings = base,
                    manual: ForkMacBackupTrigger? = nil, retryAt: Date? = nil) -> ForkMacBackupPlanner.Decision {
            var value = input(settings, now: now, conditions: conditions, lastBackup: t0, pending: changes(4))
            value.manual = manual
            value.retryAt = retryAt
            return ForkMacBackupPlanner.decide(value)
        }
        let due = t0.addingTimeInterval(4 * hour)
        let online = ForkMacBackupConditions(network: .available(limited: false))
        suite.expect(decide(online) == .run(trigger: .scheduled, due: due), "every condition met: it runs")
        suite.expect(decide(ForkMacBackupConditions(network: .none))
                        == .wait(reason: .noNetwork, due: due, recheck: nil, forcedAt: nil), "no network: it waits")
        suite.expect(decide(ForkMacBackupConditions(network: .available(limited: false), peerOnline: false))
                        == .wait(reason: .peerOffline, due: due, recheck: now.addingTimeInterval(5 * 60), forcedAt: nil),
                     "the Tailscale peer offline: it waits and looks again in 5 min")
        suite.expect(decide(ForkMacBackupConditions(network: .available(limited: true)))
                        == .wait(reason: .limitedNetwork, due: due, recheck: nil, forcedAt: nil),
                     "a limited or expensive network waits by default")
        let slowNetwork = settings([ForkDefaultsKey.macBackupLimitedNetwork: "slow"])
        suite.expect(decide(ForkMacBackupConditions(network: .available(limited: true)), settings: slowNetwork)
                        == .run(trigger: .scheduled, due: due)
                        && ForkMacBackupPlanner.uploadLimit(settings: slowNetwork,
                                                            conditions: ForkMacBackupConditions(network: .available(limited: true)),
                                                            slowDown: false, now: now, calendar: paris) == 2_000_000,
                     "a limited network in « slow » mode runs at the slow limit")
        let meeting = ForkMacBackupConditions(network: .available(limited: false), meetingBusy: true)
        suite.expect(decide(meeting) == .run(trigger: .scheduled, due: due)
                        && ForkMacBackupPlanner.uploadLimit(settings: base, conditions: meeting, slowDown: false, now: now,
                                                            calendar: paris) == 2_000_000,
                     "a meeting slows the backup to 2 MB/s by default (live throttle), it does not stop it")
        let pauseMeetings = settings([ForkDefaultsKey.macBackupMeetingMode: "pause", ForkDefaultsKey.macBackupSlowMBps: 3])
        suite.expect(decide(meeting, settings: pauseMeetings) == .wait(reason: .meeting, due: due, recheck: nil, forcedAt: nil)
                        && ForkMacBackupPlanner.meetingStopsRun(settings: pauseMeetings, conditions: meeting)
                        && !ForkMacBackupPlanner.meetingStopsRun(settings: base, conditions: meeting),
                     "in « pause » mode a meeting holds the backup")
        suite.expect(ForkMacBackupPlanner.uploadLimit(settings: pauseMeetings, conditions: online, slowDown: true, now: now,
                                                      calendar: paris) == 3_000_000
                        && ForkMacBackupPlanner.uploadLimit(settings: base, conditions: online, slowDown: false, now: now,
                                                            calendar: paris) == nil,
                     "« Ralentir » applies its own limit; nothing asked, no limit")
        let window = settings([ForkDefaultsKey.macBackupThrottleWindow: "09:00-19:00@5"])
        suite.expect(ForkMacBackupPlanner.uploadLimit(settings: window, conditions: online, slowDown: false,
                                                      now: utc("2026-10-22T10:00:00Z"), calendar: paris) == 5_000_000
                        && ForkMacBackupPlanner.uploadLimit(settings: window, conditions: online, slowDown: true,
                                                            now: utc("2026-10-22T10:00:00Z"), calendar: paris) == 2_000_000
                        && ForkMacBackupPlanner.uploadLimit(settings: window, conditions: online, slowDown: false,
                                                            now: utc("2026-10-22T20:00:00Z"), calendar: paris) == nil,
                     "the throttle window limits in its hours (Paris time); the lowest limit wins")
        let acOnly = settings([ForkDefaultsKey.macBackupPowerMode: "ac", ForkDefaultsKey.macBackupScheduleMode: "interval"])
        let onBattery = ForkMacBackupConditions(onAC: false, batteryPercent: 90, network: .available(limited: false))
        suite.expect(decide(onBattery, settings: acOnly)
                        == .wait(reason: .power, due: due, recheck: nil, forcedAt: due.addingTimeInterval(24 * hour)),
                     "« AC only » waits for power, forced after 24 h late")
        suite.expect(decide(ForkMacBackupConditions(lowPowerMode: true, network: .available(limited: false)))
                        == .wait(reason: .lowPowerMode, due: due, recheck: nil, forcedAt: due.addingTimeInterval(24 * hour)),
                     "Low Power Mode waits by default")
        suite.expect(decide(ForkMacBackupConditions(lowPowerMode: true, network: .available(limited: false)),
                            settings: settings([ForkDefaultsKey.macBackupLowPowerWaits: false]))
                        == .run(trigger: .scheduled, due: due), "unless told to ignore it")
        suite.expect(decide(ForkMacBackupConditions(onAC: false, batteryPercent: 5, network: .available(limited: false),
                                                    meetingBusy: true), settings: pauseMeetings, manual: .island)
                        == .run(trigger: .island, due: nil),
                     "« Sauvegarder maintenant » runs past the battery and a meeting")
        suite.expect(decide(ForkMacBackupConditions(network: .available(limited: false), engineAvailable: false), manual: .island)
                        == .wait(reason: .engineMissing, due: nil, recheck: nil, forcedAt: nil),
                     "but never without the engine")
        suite.expect(decide(ForkMacBackupConditions(network: .available(limited: false), wrongRepository: true),
                            retryAt: now.addingTimeInterval(60))
                        == .wait(reason: .wrongRepository, due: nil, recheck: nil, forcedAt: nil),
                     "an unexpected repository is said even while a retry is pending")
        suite.expect(decide(online, retryAt: now.addingTimeInterval(300)) == .idle(next: now.addingTimeInterval(300)),
                     "after a failure, the next attempt waits for its backoff")
        suite.expect(decide(ForkMacBackupConditions(network: .available(limited: false), updateHold: true), manual: .island)
                        == .idle(next: nil), "nothing starts while the updater replaces the app")
        suite.expect(decide(ForkMacBackupConditions(network: .available(limited: false), otherEngine: true))
                        == .wait(reason: .otherEngine, due: nil, recheck: now.addingTimeInterval(120), forcedAt: nil),
                     "another Kopia writing to the repository: wait and look again")
        suite.expect(ForkMacBackupPlanner.decide(input(settings([ForkDefaultsKey.macBackupEnabled: false]), now: now)) == .off
                        && ForkMacBackupPlanner.decide(input(settings(configured: false), now: now)) == .notConfigured,
                     "off and not configured decide nothing")
        var interrupted = input(base, now: now, lastBackup: t0, pending: changes(4))
        interrupted.interrupted = .settings
        suite.expect(ForkMacBackupPlanner.decide(interrupted) == .run(trigger: .settings, due: nil),
                     "a run stopped by a pause or a meeting resumes as soon as allowed")
        suite.expect(ForkMacBackupPlanner.keepsAwake(.ac, onAC: true) && !ForkMacBackupPlanner.keepsAwake(.ac, onAC: false)
                        && ForkMacBackupPlanner.keepsAwake(.always, onAC: false) && !ForkMacBackupPlanner.keepsAwake(.never, onAC: true),
                     "the keep-awake policy: never, on AC, always")
    }

    private static func plannerManualRhythms(_ suite: TestSuite) {
        let times = settings([ForkDefaultsKey.macBackupScheduleMode: "times", ForkDefaultsKey.macBackupTimes: "02:30,13:00"])
        let sixAM = ForkMacBackupAgentSettings.TimeOfDay(hour: 2, minute: 30)
        // 25/10/2026, Europe/Paris falls back from 03:00 CEST to 02:00 CET: 02:30 happens twice.
        let saturday = utc("2026-10-24T11:00:00Z") // 13:00 CEST
        suite.expect(ForkMacBackupPlanner.timesDue(after: saturday, times: times.times, calendar: paris)
                        == utc("2026-10-25T00:30:00Z"),
                     "a fixed time on the fall-back night happens once, the first time (02:30 CEST)")
        suite.expect(ForkMacBackupPlanner.timesDue(after: utc("2026-10-25T00:30:00Z"), times: times.times, calendar: paris)
                        == utc("2026-10-25T12:00:00Z"),
                     "and not again at 02:30 CET: the next one is 13:00 CET")
        // 29/03/2026: 02:00 CET jumps to 03:00 CEST, 02:30 does not exist.
        suite.expect(ForkMacBackupPlanner.timesDue(after: utc("2026-03-28T12:00:00Z"), times: [sixAM], calendar: paris)
                        == utc("2026-03-29T01:30:00Z"),
                     "a fixed time skipped by the spring-forward night happens just after the gap (03:30 CEST)")
        suite.expect(ForkMacBackupPlanner.intervalDue(after: utc("2026-10-25T00:00:00Z"), hours: 4) == utc("2026-10-25T04:00:00Z"),
                     "an interval counts elapsed hours, a DST change does not stretch it")
        let dues = ForkMacBackupPlanner.dues(after: utc("2026-10-24T11:00:00Z"), through: utc("2026-10-26T11:59:00Z"),
                                             settings: times, onAC: true, calendar: paris)
        suite.expect(dues == [utc("2026-10-25T00:30:00Z"), utc("2026-10-25T12:00:00Z"), utc("2026-10-26T01:30:00Z")],
                     "the fixed times over the DST weekend: three slots, none doubled")
        var at = input(times, now: utc("2026-10-25T12:01:00Z"), lastBackup: utc("2026-10-25T00:31:00Z"),
                       pending: changes(0))
        suite.expect(ForkMacBackupPlanner.decide(at) == .run(trigger: .scheduled, due: utc("2026-10-25T12:00:00Z")),
                     "a fixed time backs up even when nothing changed (the person chose a schedule)")
        at.now = utc("2026-10-25T08:00:00Z")
        suite.expect(ForkMacBackupPlanner.decide(at) == .idle(next: utc("2026-10-25T12:00:00Z")),
                     "between two fixed times it waits for the next one")
        let both = settings([ForkDefaultsKey.macBackupScheduleMode: "both", ForkDefaultsKey.macBackupTimes: "13:00",
                             ForkDefaultsKey.macBackupIntervalHours: 2])
        suite.expect(ForkMacBackupPlanner.currentDue(input(both, now: utc("2026-10-22T10:30:00Z"),
                                                           lastBackup: utc("2026-10-22T10:00:00Z")))
                        == utc("2026-10-22T11:00:00Z"),
                     "« both »: the earliest of the interval (12:00 CEST) and the time (13:00 CEST)")
        let early = settings([ForkDefaultsKey.macBackupScheduleMode: "interval", ForkDefaultsKey.macBackupIntervalHours: 12,
                              ForkDefaultsKey.macBackupEarlyEnabled: true, ForkDefaultsKey.macBackupEarlyThreshold: 50])
        suite.expect(ForkMacBackupPlanner.decide(input(early, now: t0.addingTimeInterval(2 * hour), lastBackup: t0,
                                                       pending: changes(80, important: 60))) == .run(trigger: .early, due: nil)
                        && ForkMacBackupPlanner.decide(input(early, now: t0.addingTimeInterval(2 * hour), lastBackup: t0,
                                                             pending: changes(80, important: 40)))
                        == .idle(next: t0.addingTimeInterval(12 * hour)),
                     "the early backup of the manual rhythms follows its threshold of important changes")
    }

    private static func plannerCatchUp(_ suite: TestSuite) {
        let interval = settings([ForkDefaultsKey.macBackupScheduleMode: "interval"])
        let slept = t0.addingTimeInterval(hour)
        let woke = t0.addingTimeInterval(30 * hour)
        var timeline = ForkMacBackupSlotTimeline()
        timeline.append(.agentStarted, at: t0.addingTimeInterval(-hour))
        timeline.append(.willSleep, at: slept)
        timeline.append(.didWake, at: woke)
        var book = ForkMacBackupSlotBook()
        let records = book.sweep(now: woke.addingTimeInterval(60), lastBackup: t0, settings: interval, onAC: true,
                                 calendar: paris, timeline: timeline)
        suite.expect(records.count == 6 && records.allSatisfy { $0.outcome == .missed(.asleep) }
                        && records.map(\.due) == (1...6).map { t0.addingTimeInterval(Double($0) * 4 * hour) }
                        && book.lastClosedDue == t0.addingTimeInterval(24 * hour),
                     "a 30 h sleep: the slots at +4…+24 h are missed « asleep », the last one is left to catch up")
        var value = input(interval, now: woke.addingTimeInterval(60), lastBackup: t0, pending: changes(10))
        value.lastClosedDue = book.lastClosedDue
        value.wokeAt = woke
        suite.expect(ForkMacBackupPlanner.decide(value) == .idle(next: woke.addingTimeInterval(180)),
                     "after the wake, the catch-up waits 3 min for the network")
        value.now = woke.addingTimeInterval(181)
        suite.expect(ForkMacBackupPlanner.decide(value) == .run(trigger: .catchUp, due: t0.addingTimeInterval(28 * hour)),
                     "then catches up the last slot missed")
        let again = book.sweep(now: woke.addingTimeInterval(181), lastBackup: t0, settings: interval, onAC: true,
                               calendar: paris, timeline: timeline)
        suite.expect(again.isEmpty, "a second sweep writes nothing twice")
    }

    // MARK: Ledger

    private static func ledger(_ suite: TestSuite) {
        let due = t0.addingTimeInterval(4 * hour)
        func attribute(_ events: [(TimeInterval, ForkMacBackupSlotTimeline.Event)]) -> ForkMacBackupSlotTimeline.Attribution {
            ForkMacBackupSlotTimeline(entries: events.map { .init(date: t0.addingTimeInterval($0.0 * hour), event: $0.1) })
                .attribute(due)
        }
        suite.expect(attribute([(0, .agentStarted), (3, .willSleep), (6, .didWake)]) == .missed(.asleep),
                     "asleep from willSleep to didWake")
        suite.expect(attribute([(0, .agentStarted), (3, .agentStopped), (5, .booted), (5.1, .agentStarted)]) == .missed(.off),
                     "off: the agent's last sign of life, then a boot after the due date")
        suite.expect(attribute([(0, .agentStarted), (2, .agentStopped), (3, .booted), (6, .agentStarted)]) == .missed(.off),
                     "off: booted before the due date but nobody logged in yet")
        suite.expect(attribute([(0, .agentStarted), (3, .agentStopped), (6, .agentStarted)]) == .missed(.notApproved),
                     "the Mac ran without the agent: it was not allowed to (the app was closed)")
        suite.expect(attribute([(0, .agentStarted), (3, .waiting(.battery)), (5, .clear)]) == .missed(.battery),
                     "a wait for the battery")
        suite.expect(attribute([(0, .agentStarted), (3, .paused), (5, .resumed)]) == .missed(.paused), "a pause")
        suite.expect(attribute([(0, .agentStarted), (3, .runStarted), (5, .runEnded)]) == .covered,
                     "a due date during a run is covered, not missed")
        suite.expect(attribute([(0, .agentStarted), (2, .waiting(.network)), (3, .clear)]) == .unknown,
                     "nothing known at the due date: no reason is invented")
        var timeline = ForkMacBackupSlotTimeline()
        timeline.append(.waiting(.network), at: t0)
        timeline.append(.waiting(.network), at: t0.addingTimeInterval(1))
        timeline.append(.agentStarted, at: t0.addingTimeInterval(-10))
        suite.expect(timeline.entries.count == 2 && timeline.entries.first?.event == .agentStarted,
                     "repeated waits are kept once, late entries are put in order")
    }

    private static func slotBook(_ suite: TestSuite) {
        let interval = settings([ForkDefaultsKey.macBackupScheduleMode: "interval"])
        let due = t0.addingTimeInterval(4 * hour)
        let runID = UUID()
        var book = ForkMacBackupSlotBook()
        book.open(due)
        book.runStarted(at: due.addingTimeInterval(600), runID: runID)
        suite.expect(book.runEnded(.failed(.chainBroken), runID: runID, canceledByPerson: false) == nil && book.open?.failed == true,
                     "a failed run keeps its slot open for the retry")
        let retryID = UUID()
        book.runStarted(at: due.addingTimeInterval(1_200), runID: retryID)
        let done = book.runEnded(.partial(files: 2), runID: retryID, canceledByPerson: false)
        suite.expect(done == ForkMacBackupSlotRecord(due: due, outcome: .partial, startedAt: due.addingTimeInterval(600),
                                                     runID: retryID)
                        && done?.startedLate == true && book.open == nil && book.lastClosedDue == due,
                     "the retry closes it once, partial, started late (its first start)")
        book.open(due.addingTimeInterval(4 * hour))
        book.runStarted(at: due.addingTimeInterval(4 * hour), runID: runID)
        _ = book.runEnded(.failed(.stalled), runID: runID, canceledByPerson: false)
        let timeline = ForkMacBackupSlotTimeline(entries: [.init(date: t0, event: .agentStarted)])
        let swept = book.sweep(now: due.addingTimeInterval(8 * hour + 60), lastBackup: t0, settings: interval, onAC: true,
                               calendar: paris, timeline: timeline)
        suite.expect(swept == [ForkMacBackupSlotRecord(due: due.addingTimeInterval(4 * hour), outcome: .failed,
                                                       startedAt: due.addingTimeInterval(4 * hour), runID: runID)],
                     "a slot still failed when the next one is due is written failed")
        var waiting = ForkMacBackupSlotBook()
        waiting.open(due)
        waiting.waited(.peerOffline)
        let missed = waiting.sweep(now: due.addingTimeInterval(4 * hour + 1), lastBackup: t0, settings: interval, onAC: true,
                                   calendar: paris, timeline: timeline)
        suite.expect(missed.first?.outcome == .missed(.peerOffline), "a slot held by a wait is missed for that reason")
        var nothing = ForkMacBackupSlotBook()
        suite.expect(nothing.nothingToDo(due).outcome == .nothingToDo && nothing.lastClosedDue == due,
                     "« nothing to do » is written at once")
        var canceled = ForkMacBackupSlotBook()
        canceled.open(due)
        canceled.runStarted(at: due, runID: runID)
        suite.expect(canceled.runEnded(nil, runID: runID, canceledByPerson: true)?.outcome == .missed(.paused),
                     "a run the person canceled leaves its slot missed (paused)")
    }

    // MARK: Machine

    private static func startedMachine(_ settings: ForkMacBackupAgentSettings = settings(),
                                       keepAwake: Bool = true) -> (ForkMacBackupMachine, [ForkMacBackupMachine.Action]) {
        var machine = ForkMacBackupMachine()
        _ = machine.handle(.configure(settings), now: t0)
        _ = machine.handle(.keepAwakeAllowed(keepAwake), now: t0)
        let actions = machine.handle(.decision(.run(trigger: .scheduled, due: t0)), now: t0)
        return (machine, actions)
    }

    private static func runEnded(_ actions: [ForkMacBackupMachine.Action]) -> ForkMacBackupMachine.Summary? {
        for action in actions { if case .runEnded(let summary) = action { return summary } }
        return nil
    }

    private static func machineHappyPath(_ suite: TestSuite) {
        let source = ForkMacBackupSource(path: "/Users/test")
        var (machine, actions) = startedMachine()
        suite.expect(actions.contains(.checkChain) && actions.contains(.keepAwake(true)) && machine.phase(now: t0) == .checkingChain,
                     "a run checks the chain first and holds the keep-awake assertion")
        actions = machine.handle(.chainChecked(nil, nodeID: nil), now: t0)
        suite.expect(actions.contains(.applyPolicy(source)) && machine.phase(now: t0) == .preparing,
                     "then writes the source's rules")
        actions = machine.handle(.policyApplied(source, .matched), now: t0)
        suite.expect(actions == [.setThrottle(nil), .triggerSnapshot(source)],
                     "rules read back equal: the throttle is set explicitly (Kopia persists it), then the snapshot starts")
        _ = machine.handle(.snapshotTriggered(source, nil), now: t0)
        _ = machine.handle(.progress(sources(uploading: true, hashed: 1_000, files: 1)), now: t0.addingTimeInterval(1))
        let scanning = ForkMacBackupPresentation(phase: machine.phase(now: t0), progress: machine.progress(now: t0))
        suite.expect(machine.phase(now: t0) == .scanning && scanning.fraction == nil && scanning.progress?.eta == nil,
                     "without Kopia's estimate: scanning, no percentage, no ETA")
        for second in 2...40 {
            _ = machine.handle(.progress(sources(uploading: true, hashed: Int64(second) * 10_000_000, estimate: 1_000_000_000,
                                                 uploaded: Int64(second) * 5_000_000, files: Int64(second))),
                               now: t0.addingTimeInterval(Double(second)))
        }
        let at = t0.addingTimeInterval(40)
        let live = ForkMacBackupPresentation(phase: machine.phase(now: at), progress: machine.progress(now: at))
        suite.expect(machine.phase(now: at) == .uploading && live.fraction.map { abs($0 - 0.4) < 0.001 } == true
                        && live.progress?.bytesPerSecond.map { abs($0 - 10_000_000) < 1 } == true
                        && live.progress?.eta.map { abs($0 - 60) < 0.5 } == true
                        && live.progress?.currentPath == "/Users/test/Documents"
                        && live.progress?.bytesUploaded == 200_000_000,
                     "uploading: real fraction, 10 s mean rate, ETA once the estimate held 30 s, the folder walked")
        actions = machine.handle(.progress(sources(uploading: false)), now: at.addingTimeInterval(1))
        suite.expect(concludes(actions, source) && machine.phase(now: at) == .concluding,
                     "the source idle again: the manifest is looked for")
        let complete = manifest(id: "m1", start: t0.addingTimeInterval(1), end: at)
        actions = machine.handle(.listed(source, .success([complete])), now: at.addingTimeInterval(2))
        let summary = runEnded(actions)
        suite.expect(summary?.result == .complete && summary?.outcome == .complete && summary?.proofs.first?.level == .complete
                        && summary?.bytesSent == 200_000_000 && summary?.due == t0 && actions.contains(.keepAwake(false))
                        && actions.contains(.replan),
                     "a manifest without error: complete, its proof recorded, the assertion released")
        suite.expect(machine.phase(now: at.addingTimeInterval(10)) == .finished(.complete)
                        && machine.phase(now: at.addingTimeInterval(10 * 60)) == .ready(next: nil),
                     "« finished » shows a while, then the state rests")
        suite.expect(machine.nextWake(now: at.addingTimeInterval(10)) == at.addingTimeInterval(2 + 5 * 60),
                     "the machine asks to be woken when the « finished » display ends")
    }

    /// Three sources, the second's estimate arrives late, the third is tiny:
    /// ONE continuous progress (never nil, never backwards, never « scanning »).
    private static func machineMultiSourceContinuity(_ suite: TestSuite) {
        let paths = ["/Users/test/A", "/Users/test/B", "/Users/test/C"]
        let list = paths.map { ForkMacBackupSource(path: $0) }
        var (machine, _) = startedMachine(settings(sources: paths))
        _ = machine.handle(.chainChecked(nil, nodeID: nil), now: t0)
        for source in list { _ = machine.handle(.policyApplied(source, .matched), now: t0) }
        var clock = 0.0
        var fractions: [Double?] = []
        var started = false
        var scanningAfterStart = false
        func observe() {
            let at = t0.addingTimeInterval(clock)
            let presentation = ForkMacBackupPresentation(phase: machine.phase(now: at), progress: machine.progress(now: at))
            if started {
                fractions.append(presentation.fraction)
                if presentation.phase == .scanning || presentation.phase == .preparing { scanningAfterStart = true }
            }
            if presentation.fraction != nil { started = true }
        }
        func feed(_ source: ForkMacBackupSource, hashed: Int64, estimate: Int64) {
            clock += 1
            _ = machine.handle(.progress(sources(path: source.path, uploading: true, hashed: hashed, estimate: estimate,
                                                 files: hashed / 10)), now: t0.addingTimeInterval(clock))
            observe()
        }
        func finish(_ source: ForkMacBackupSource) {
            clock += 1
            _ = machine.handle(.progress(sources(path: source.path, uploading: false)), now: t0.addingTimeInterval(clock))
            if source != list[2] { observe() }
            clock += 1
            _ = machine.handle(.listed(source, .success([manifest(id: source.path, path: source.path, start: t0,
                                                                  end: t0.addingTimeInterval(clock))])),
                               now: t0.addingTimeInterval(clock))
            if source != list[2] { observe() }
        }
        for step in 1...4 { feed(list[0], hashed: Int64(step) * 250, estimate: 1_000) }
        finish(list[0])
        // Source 2: no estimate for a while, then a large one.
        for step in 1...3 { feed(list[1], hashed: Int64(step) * 100, estimate: 0) }
        for step in 4...8 { feed(list[1], hashed: Int64(step) * 100, estimate: 4_000) }
        finish(list[1])
        feed(list[2], hashed: 5, estimate: 10)
        feed(list[2], hashed: 10, estimate: 10)
        finish(list[2])
        let known = fractions.compactMap { $0 }
        suite.expect(started && known.count == fractions.count, "multi-source: the fraction is never nil once uploading started")
        suite.expect(zip(known, known.dropFirst()).allSatisfy { $0 <= $1 }, "multi-source: the fraction never moves backwards")
        suite.expect(!scanningAfterStart, "multi-source: the phase never returns to scanning between sources")
    }

    private static func machineConclusions(_ suite: TestSuite) {
        let source = ForkMacBackupSource(path: "/Users/test")
        // Exit 1 WITH the JSON (CLI engine): the manifest decides.
        var (machine, _) = startedMachine()
        _ = machine.handle(.chainChecked(nil, nodeID: nil), now: t0)
        _ = machine.handle(.policyApplied(source, .matched), now: t0)
        var actions = machine.handle(.snapshotTriggered(source, .kopia(exitCode: 1, message: "Found 1 fatal error(s)")),
                                     now: t0.addingTimeInterval(30))
        suite.expect(concludes(actions, source), "Kopia's exit 1 is not a failure by itself")
        actions = machine.handle(.listed(source, .success([manifest(id: "p1", start: t0, end: t0.addingTimeInterval(30),
                                                                    errors: ["a.txt", "b.txt"])])),
                                 now: t0.addingTimeInterval(31))
        suite.expect(runEnded(actions)?.result == .partial(files: 2) && machine.lastError == nil
                        && machine.consecutiveFailures == 0,
                     "exit 1 with a manifest of 2 read errors: partial, named, not a failure")

        (machine, _) = startedMachine()
        _ = machine.handle(.chainChecked(nil, nodeID: nil), now: t0)
        _ = machine.handle(.policyApplied(source, .matched), now: t0)
        _ = machine.handle(.snapshotTriggered(source, .kopia(exitCode: 1, message: "boom")), now: t0)
        actions = machine.handle(.listed(source, .success([manifest(id: "old", start: t0.addingTimeInterval(-hour),
                                                                    end: t0.addingTimeInterval(-hour + 10))])),
                                 now: t0.addingTimeInterval(5))
        suite.expect(runEnded(actions)?.result == .failed(.noSnapshot),
                     "exit 1 and no manifest newer than the run: failed, no snapshot")

        (machine, _) = startedMachine()
        _ = machine.handle(.chainChecked(nil, nodeID: nil), now: t0)
        _ = machine.handle(.policyApplied(source, .matched), now: t0)
        _ = machine.handle(.snapshotTriggered(source, nil), now: t0)
        _ = machine.handle(.progress(sources(uploading: true, hashed: 10)), now: t0.addingTimeInterval(1))
        _ = machine.handle(.progress(sources(uploading: false)), now: t0.addingTimeInterval(2))
        actions = machine.handle(.listed(source, .success([manifest(id: "c1", start: t0, end: t0.addingTimeInterval(2),
                                                                    incomplete: "canceled")])),
                                 now: t0.addingTimeInterval(3))
        suite.expect(runEnded(actions)?.result == .failed(.noSnapshot),
                     "a manifest left incomplete (canceled) without resume is a failure")

        // An unchanged source finishes before any poll shows it uploading.
        (machine, _) = startedMachine()
        _ = machine.handle(.chainChecked(nil, nodeID: nil), now: t0)
        _ = machine.handle(.policyApplied(source, .matched), now: t0)
        _ = machine.handle(.snapshotTriggered(source, nil), now: t0)
        actions = machine.handle(.progress(sources(uploading: false, last: (t0.addingTimeInterval(0.1), t0.addingTimeInterval(0.4)))),
                                 now: t0.addingTimeInterval(1))
        suite.expect(concludes(actions, source),
                     "a third-of-a-second snapshot is seen by its new manifest, not by an upload")

        // Two sources, one after the other.
        let two = settings(sources: ["/Users/test/Documents", "/Users/test/Projects"])
        let documents = ForkMacBackupSource(path: "/Users/test/Documents")
        let projects = ForkMacBackupSource(path: "/Users/test/Projects")
        (machine, _) = startedMachine(two)
        _ = machine.handle(.chainChecked(nil, nodeID: nil), now: t0)
        actions = machine.handle(.policyApplied(documents, .matched), now: t0)
        suite.expect(actions == [.applyPolicy(projects)], "each source's rules are written before any snapshot")
        actions = machine.handle(.policyApplied(projects, .matched), now: t0)
        suite.expect(actions.contains(.triggerSnapshot(documents)), "then the first source starts")
        _ = machine.handle(.progress(sources(path: documents.path, uploading: true, hashed: 5, estimate: 10)), now: t0)
        _ = machine.handle(.progress(sources(path: documents.path, uploading: false)), now: t0.addingTimeInterval(1))
        actions = machine.handle(.listed(documents, .success([manifest(id: "d", path: documents.path, start: t0,
                                                                       end: t0.addingTimeInterval(1))])),
                                 now: t0.addingTimeInterval(2))
        suite.expect(actions.contains(.triggerSnapshot(projects)) && machine.sourceState(documents.path) == .done
                        && machine.sourceState(projects.path) == .running,
                     "the second source follows; the first shows done")
    }

    private static func machineFailures(_ suite: TestSuite) {
        suite.expect((1...8).map(ForkMacBackupMachine.backoff(after:)) == [60, 300, 900, 3_600, 7_200, 14_400, 21_600, 21_600],
                     "backoff: 1, 5, 15, 60 min, then doubling, capped at 6 h")
        var (machine, _) = startedMachine()
        var actions = machine.handle(.chainChecked(.unreachable("dial tcp: i/o timeout"), nodeID: "server"), now: t0)
        let summary = runEnded(actions)
        suite.expect(summary?.result == .failed(.chainBroken) && machine.retryAt == t0.addingTimeInterval(60)
                        && machine.lastError == ForkMacBackupPresentation.ErrorLine(cause: .chainBroken, nodeID: "server", at: t0,
                                                                                    message: "dial tcp: i/o timeout")
                        && machine.phase(now: t0) == .finished(.failed(.chainBroken)),
                     "the storage unreachable: failed, the broken node named, retried in 1 min")
        _ = machine.handle(.decision(.run(trigger: .scheduled, due: t0)), now: t0.addingTimeInterval(61))
        actions = machine.handle(.chainChecked(.timeout, nodeID: nil), now: t0.addingTimeInterval(62))
        suite.expect(machine.retryAt == t0.addingTimeInterval(62 + 300), "a second failure waits 5 min")
        let source = ForkMacBackupSource(path: "/Users/test")
        _ = machine.handle(.decision(.run(trigger: .scheduled, due: t0)), now: t0.addingTimeInterval(400))
        _ = machine.handle(.chainChecked(nil, nodeID: nil), now: t0.addingTimeInterval(400))
        _ = machine.handle(.policyApplied(source, .matched), now: t0.addingTimeInterval(400))
        _ = machine.handle(.snapshotTriggered(source, nil), now: t0.addingTimeInterval(400))
        _ = machine.handle(.progress(sources(uploading: true, hashed: 5)), now: t0.addingTimeInterval(401))
        actions = machine.handle(.tick, now: t0.addingTimeInterval(401 + 9 * 60))
        suite.expect(!actions.contains(.cancelSnapshot(source)), "9 min without progress: still patient")
        actions = machine.handle(.tick, now: t0.addingTimeInterval(401 + 10 * 60))
        suite.expect(actions.contains(.cancelSnapshot(source)),
                     "the watchdog: 10 min without progress cancels with a checkpoint")
        actions = machine.handle(.progress(sources(uploading: false)), now: t0.addingTimeInterval(402 + 10 * 60))
        suite.expect(runEnded(actions)?.result == .failed(.stalled) && machine.consecutiveFailures == 3
                        && machine.retryAt == t0.addingTimeInterval(402 + 10 * 60 + 900),
                     "then fails « stuck » and retries after the next backoff step")
        _ = machine.handle(.decision(.run(trigger: .scheduled, due: t0)), now: t0.addingTimeInterval(4 * hour))
        _ = machine.handle(.chainChecked(nil, nodeID: nil), now: t0.addingTimeInterval(4 * hour))
        _ = machine.handle(.policyApplied(source, .matched), now: t0.addingTimeInterval(4 * hour))
        _ = machine.handle(.snapshotTriggered(source, nil), now: t0.addingTimeInterval(4 * hour))
        _ = machine.handle(.progress(sources(uploading: true, hashed: 5)), now: t0.addingTimeInterval(4 * hour + 1))
        _ = machine.handle(.progress(sources(uploading: false)), now: t0.addingTimeInterval(4 * hour + 2))
        actions = machine.handle(.listed(source, .success([manifest(id: "ok", start: t0.addingTimeInterval(4 * hour),
                                                                    end: t0.addingTimeInterval(4 * hour + 2))])),
                                 now: t0.addingTimeInterval(4 * hour + 3))
        suite.expect(machine.consecutiveFailures == 0 && machine.retryAt == nil && machine.lastError == nil,
                     "a success clears the backoff and the banner")

        (machine, _) = startedMachine()
        _ = machine.handle(.chainChecked(nil, nodeID: nil), now: t0)
        actions = machine.handle(.policyApplied(source, .mismatched), now: t0)
        suite.expect(runEnded(actions) != nil && machine.phase(now: t0.addingTimeInterval(6 * 60)) == .waiting(reason: .rulesNotApplied, until: nil),
                     "rules that do not read back the same: no snapshot, « rules not applied »")
        _ = machine.handle(.decision(.run(trigger: .scheduled, due: nil)), now: t0.addingTimeInterval(7 * 60))
        suite.expect(!machine.isBackingUp, "and nothing starts until the settings change")
        var changed = settings()
        changed.sources = [ForkMacBackupSource(path: "/Users/test", presets: [.trash])]
        _ = machine.handle(.configure(changed), now: t0.addingTimeInterval(8 * 60))
        suite.expect(!machine.rulesProblem, "new rules try again")

        (machine, _) = startedMachine()
        _ = machine.handle(.chainChecked(nil, nodeID: nil), now: t0)
        _ = machine.handle(.policyApplied(source, .matched), now: t0)
        _ = machine.handle(.snapshotTriggered(source, nil), now: t0)
        actions = machine.handle(.progress(sources(uploading: false)), now: t0.addingTimeInterval(91))
        suite.expect(runEnded(actions)?.result == .failed(.noSnapshot),
                     "a trigger that never shows an upload nor a new snapshot fails after 90 s")
    }

    private static func machineStops(_ suite: TestSuite) {
        let source = ForkMacBackupSource(path: "/Users/test")
        func uploading() -> ForkMacBackupMachine {
            var (machine, _) = startedMachine()
            _ = machine.handle(.chainChecked(nil, nodeID: nil), now: t0)
            _ = machine.handle(.policyApplied(source, .matched), now: t0)
            _ = machine.handle(.snapshotTriggered(source, nil), now: t0)
            _ = machine.handle(.progress(sources(uploading: true, hashed: 50, estimate: 100)), now: t0.addingTimeInterval(1))
            return machine
        }
        var machine = uploading()
        let until = t0.addingTimeInterval(hour)
        var actions = machine.handle(.command(.pause(until: until), origin: .island), now: t0.addingTimeInterval(2))
        suite.expect(actions.contains(.cancelSnapshot(source)) && machine.interrupted == .scheduled,
                     "pause = cancel-snapshot (Kopia keeps a checkpoint), the run to resume remembered")
        actions = machine.handle(.progress(sources(uploading: false)), now: t0.addingTimeInterval(20))
        let paused = runEnded(actions)
        suite.expect(paused?.outcome == .canceled && paused?.stopReason == .paused && paused?.result == nil
                        && machine.phase(now: t0.addingTimeInterval(21)) == .paused(until: until) && machine.lastError == nil,
                     "the pause ends the run as canceled (paused), no failure, the state says until when")
        actions = machine.handle(.tick, now: until.addingTimeInterval(1))
        suite.expect(actions.contains(.replan) && !machine.isPaused, "the pause ends on its own at its time")
        _ = machine.handle(.command(.pause(until: nil), origin: .island), now: until.addingTimeInterval(2))
        actions = machine.handle(.command(.resume, origin: .island), now: until.addingTimeInterval(3))
        suite.expect(actions.contains(.replan) && machine.phase(now: until.addingTimeInterval(3)) == .ready(next: nil),
                     "« Reprendre » ends a pause without end")

        machine = uploading()
        actions = machine.handle(.meetingStarted, now: t0.addingTimeInterval(2))
        _ = machine.handle(.progress(sources(uploading: false)), now: t0.addingTimeInterval(3))
        suite.expect(actions.contains(.cancelSnapshot(source)) && machine.interrupted == .scheduled && !machine.isBackingUp,
                     "a meeting in « pause » mode stops the run, to resume after it")

        machine = uploading()
        actions = machine.handle(.command(.cancel, origin: .window), now: t0.addingTimeInterval(2))
        suite.expect(actions.contains(.cancelSnapshot(source)), "« Annuler » cancels the snapshot")
        actions = machine.handle(.tick, now: t0.addingTimeInterval(2 + 3 * 60))
        let canceled = runEnded(actions)
        suite.expect(canceled?.stopReason == .user && machine.interrupted == nil && !machine.isBackingUp,
                     "a cancel that Kopia never confirms ends after the grace delay, and is not resumed")

        machine = uploading()
        actions = machine.handle(.stop(.agentQuit), now: t0.addingTimeInterval(2))
        suite.expect(actions.contains(.cancelSnapshot(source)), "SIGTERM: the snapshot is canceled cleanly")

        var off = uploading()
        var disabled = settings()
        disabled.enabled = false
        actions = off.handle(.configure(disabled), now: t0.addingTimeInterval(2))
        _ = off.handle(.progress(sources(uploading: false)), now: t0.addingTimeInterval(3))
        suite.expect(actions.contains(.cancelSnapshot(source)) && off.phase(now: t0.addingTimeInterval(3)) == .off,
                     "switched off: the run stops and the state says off")

        machine = uploading()
        actions = machine.handle(.command(.backUpNow, origin: .island), now: t0.addingTimeInterval(2))
        suite.expect(actions.isEmpty, "« Sauvegarder maintenant » during a run does nothing more")
        var idle = ForkMacBackupMachine()
        _ = idle.handle(.configure(settings()), now: t0)
        _ = idle.handle(.command(.pause(until: nil), origin: .island), now: t0)
        actions = idle.handle(.command(.backUpNow, origin: .commandBar), now: t0)
        suite.expect(actions.contains(.requestRun(.commandBar)) && !idle.isPaused,
                     "« Sauvegarder maintenant » lifts a pause and asks for a run")
    }

    private static func machineLimitsAndVerify(_ suite: TestSuite) {
        let source = ForkMacBackupSource(path: "/Users/test")
        var (machine, _) = startedMachine(keepAwake: false)
        _ = machine.handle(.chainChecked(nil, nodeID: nil), now: t0)
        _ = machine.handle(.policyApplied(source, .matched), now: t0)
        _ = machine.handle(.progress(sources(uploading: true, hashed: 50, estimate: 100)), now: t0.addingTimeInterval(1))
        var actions = machine.handle(.limit(2_000_000), now: t0.addingTimeInterval(2))
        suite.expect(actions.contains(.setThrottle(2_000_000)) && machine.phase(now: t0) == .slowed,
                     "a limit during the upload: live throttle, the state says slowed")
        actions = machine.handle(.limit(2_000_000), now: t0.addingTimeInterval(3))
        suite.expect(actions.isEmpty, "the same limit is not sent twice")
        actions = machine.handle(.limit(nil), now: t0.addingTimeInterval(4))
        suite.expect(actions.contains(.setThrottle(nil)) && machine.phase(now: t0) == .uploading,
                     "lifted: full speed again")
        actions = machine.handle(.keepAwakeAllowed(true), now: t0.addingTimeInterval(5))
        suite.expect(actions == [.keepAwake(true)], "plugged in mid-run (policy « on AC »): the assertion is taken")
        actions = machine.handle(.command(.slowDown(true), origin: .island), now: t0.addingTimeInterval(6))
        suite.expect(machine.slowDown && actions.contains(.replan), "« Ralentir » is remembered and the limit recomputed")
        actions = machine.handle(.command(.verify(.contentSample(percent: 1)), origin: .window), now: t0.addingTimeInterval(7))
        suite.expect(actions.isEmpty, "a verification asked during a backup waits for its end")
        _ = machine.handle(.progress(sources(uploading: false)), now: t0.addingTimeInterval(8))
        actions = machine.handle(.listed(source, .success([manifest(id: "v", start: t0, end: t0.addingTimeInterval(8))])),
                                 now: t0.addingTimeInterval(9))
        suite.expect(actions.contains(.startVerify(.contentSample(percent: 1))) && machine.phase(now: t0) == .verifying,
                     "then runs")
        _ = machine.handle(.verifyProgress(.init(checked: 10, total: 40)), now: t0.addingTimeInterval(10))
        suite.expect(machine.progress(now: t0)?.files == 10 && machine.progress(now: t0)?.filesTotal == 40,
                     "the verification's progress is published")
        let report = ForkMacBackupVerifyReport(level: .contentSample(percent: 1), manifestIDs: ["v"], checked: 40, errors: [],
                                               start: t0, end: t0.addingTimeInterval(20))
        actions = machine.handle(.verifyFinished(.success(report)), now: t0.addingTimeInterval(20))
        suite.expect(actions.contains(.verifyEnded(level: .contentSample(percent: 1), trigger: .window,
                                                   start: t0.addingTimeInterval(9), result: .success(report)))
                        && !machine.isBusy,
                     "its report goes to the runner (proofs raised, history)")
    }

    private static func waits(_ suite: TestSuite) {
        var machine = ForkMacBackupMachine()
        _ = machine.handle(.configure(settings()), now: t0)
        _ = machine.handle(.decision(.wait(reason: .lowBattery, due: t0, recheck: nil, forcedAt: t0.addingTimeInterval(hour))), now: t0)
        suite.expect(machine.phase(now: t0) == .waiting(reason: .lowBattery, until: t0.addingTimeInterval(hour)),
                     "a wait says until when at the latest (forced)")
        _ = machine.handle(.decision(.wait(reason: .peerOffline, due: t0, recheck: t0.addingTimeInterval(300), forcedAt: nil)), now: t0)
        suite.expect(machine.phase(now: t0) == .waiting(reason: .peerOffline, until: nil),
                     "an agent's recheck is no promise: no « until »")
        _ = machine.handle(.decision(.idle(next: t0.addingTimeInterval(hour))), now: t0)
        suite.expect(machine.phase(now: t0) == .ready(next: t0.addingTimeInterval(hour)), "the condition gone: ready, with the next run")
        var notConfigured = ForkMacBackupMachine()
        _ = notConfigured.handle(.configure(settings(configured: false)), now: t0)
        suite.expect(notConfigured.phase(now: t0) == .notConfigured, "without a repository or a source: not configured")
    }

    private static func tracker(_ suite: TestSuite) {
        var tracker = ForkMacBackupProgressTracker()
        tracker.add(done: 0, estimate: 1_000, at: t0)
        tracker.add(done: 100, estimate: 1_005, at: t0.addingTimeInterval(5))
        tracker.add(done: 200, estimate: 1_004, at: t0.addingTimeInterval(10))
        suite.expect(tracker.estimateSince == t0, "an estimate moving by less than 1 % holds")
        suite.expect(tracker.eta(now: t0.addingTimeInterval(10), done: 200, total: 1_000) == nil,
                     "no ETA before 30 s of a stable estimate")
        tracker.add(done: 300, estimate: 2_000, at: t0.addingTimeInterval(15))
        suite.expect(tracker.estimateSince == t0.addingTimeInterval(15), "a moving estimate starts the 30 s again")
        tracker.add(done: 600, estimate: 2_000, at: t0.addingTimeInterval(45))
        suite.expect(tracker.samples.count == 1 && tracker.rate() == nil, "samples older than 10 s are dropped")
        tracker.add(done: 800, estimate: 2_000, at: t0.addingTimeInterval(49))
        suite.expect(tracker.rate() == 50 && tracker.eta(now: t0.addingTimeInterval(49), done: 800, total: 2_000) == 24,
                     "rate over the window, ETA from it")
    }

    // MARK: Presentation

    private static func presenter(_ suite: TestSuite) {
        let configured = settings()
        let chain = configured.chain
        let broken = ForkMacBackupChainProbe(macReady: true, network: true, peerOnline: true, repository: .unreachable,
                                             checkedAt: t0).statuses(chain)
        suite.expect(broken.map(\.state) == [.ok, .ok, .ok, .broken, .unknown] && broken[0].checkedAt == t0
                        && broken[4].checkedAt == nil,
                     "the storage silent: the server node is broken, what lies behind is unknown")
        let offline = ForkMacBackupChainProbe(macReady: true, network: true, peerOnline: false, repository: .unreachable)
            .statuses(chain)
        suite.expect(offline.map(\.state) == [.ok, .ok, .broken, .unknown, .unknown], "the Tailscale peer offline is the break")
        let ok = ForkMacBackupChainProbe(repository: .ok(latencyMs: 18), checkedAt: t0).statuses(chain)
        suite.expect(ok.allSatisfy { $0.state == .ok } && ok.first { $0.kind == .s3 }?.latencyMs == 18,
                     "a repository that answered proves the whole chain")
        let wrong = ForkMacBackupChainProbe(network: true, repository: .wrongRepository).statuses(chain)
        suite.expect(wrong.last?.state == .broken && wrong[3].state == .ok, "an unexpected repository: the last node is broken")
        suite.expect(ForkMacBackupChainProbe(repository: .ok(latencyMs: 4_000)).statuses(chain)[3].state == .slow,
                     "an answer over 3 s is slow")

        var proofs = ForkMacBackupProofStore()
        let partial = ForkMacBackupSnapshotProof(manifest: manifest(id: "p", start: t0, end: t0.addingTimeInterval(60),
                                                                    errors: ["x"]), iCloud: .local)
        let complete = ForkMacBackupSnapshotProof(manifest: manifest(id: "c", start: t0.addingTimeInterval(-86_400),
                                                                     end: t0.addingTimeInterval(-86_000)), iCloud: .local)
        proofs.record([partial, complete], now: t0)
        var machine = ForkMacBackupMachine()
        _ = machine.handle(.configure(configured), now: t0)
        _ = machine.handle(.decision(.idle(next: t0.addingTimeInterval(hour))), now: t0)
        let runs = (0..<4).map { index in
            ForkMacBackupRunRecord(kind: .backup, trigger: .scheduled, start: t0.addingTimeInterval(Double(index - 4) * 2 * hour),
                                   end: t0.addingTimeInterval(Double(index - 4) * 2 * hour + 180), bytesSent: 1_000_000,
                                   batteryDrop: index == 0 ? 0.8 : nil, outcome: .complete)
        }
        let presentation = ForkMacBackupPresenter.presentation(
            machine, context: .init(settings: configured, proofs: proofs, chain: ForkMacBackupChainProbe(repository: .ok(latencyMs: 9)),
                                    pendingChanges: 214, runs: runs, repositoryBytes: 5_000, repositoryMeasuredAt: t0),
            now: t0)
        suite.expect(presentation.phase == .ready(next: t0.addingTimeInterval(hour)) && presentation.nextRun == t0.addingTimeInterval(hour),
                     "at rest: ready, with the next run")
        suite.expect(presentation.sources.first?.state == .partial && presentation.sources.first?.last?.manifestID == "p"
                        && presentation.sources.first?.last?.failures == 1
                        && presentation.sources.first?.lastComplete?.manifestID == "c" && presentation.tone == .orange,
                     "a source shows its last snapshot (partial, 1 file) and its last complete one together")
        suite.expect(presentation.pendingChanges == 214 && presentation.capacity.protectedBytes == 1_000
                        && presentation.capacity.lastSentBytes == 1_000_000 && presentation.capacity.repositoryBytes == 5_000,
                     "pending changes and real sizes are filled")
        suite.expect(presentation.cost == ForkMacBackupPresentation.Cost(averageDuration: 180, averageBatteryDrop: 0.8,
                                                                         averageSent: 1_000_000, samples: 4)
                        && presentation.rhythm == .automatic(about: 2 * hour),
                     "the cost line and the interval Automatic keeps come from the history")
        var disabled = configured
        disabled.enabled = false
        var offMachine = ForkMacBackupMachine()
        _ = offMachine.handle(.configure(disabled), now: t0)
        let off = ForkMacBackupPresenter.presentation(offMachine, context: .init(settings: disabled, proofs: proofs), now: t0)
        suite.expect(off.phase == .off && off.sources.isEmpty && off.chain.isEmpty && off.lastError == nil,
                     "switched off: nothing else is shown")
    }

    // MARK: IPC

    private static func ipc(_ suite: TestSuite) {
        suite.expect(ForkMacBackupAgentIPCSupport.publishInterval(leaseModifiedAt: t0.addingTimeInterval(-4), now: t0) == 1
                        && ForkMacBackupAgentIPCSupport.publishInterval(leaseModifiedAt: t0.addingTimeInterval(-16), now: t0) == 10
                        && ForkMacBackupAgentIPCSupport.publishInterval(leaseModifiedAt: nil, now: t0) == 10,
                     "a fresh live-progress lease (< 15 s) publishes each second, otherwise every 10 s")
        let base = ForkMacBackupPresentation(phase: .uploading, progress: .init(bytesDone: 10), updatedAt: t0)
        var moved = base
        moved.progress?.bytesDone = 20
        moved.updatedAt = t0.addingTimeInterval(2)
        let fresh = t0
        suite.expect(ForkMacBackupAgentIPCSupport.shouldPublish(moved, last: base, lastWrittenAt: t0, leaseModifiedAt: fresh,
                                                                now: t0.addingTimeInterval(1))
                        && !ForkMacBackupAgentIPCSupport.shouldPublish(moved, last: base, lastWrittenAt: t0, leaseModifiedAt: nil,
                                                                       now: t0.addingTimeInterval(5))
                        && ForkMacBackupAgentIPCSupport.shouldPublish(moved, last: base, lastWrittenAt: t0, leaseModifiedAt: nil,
                                                                      now: t0.addingTimeInterval(10)),
                     "the live figures follow the lease's cadence")
        var phaseChange = base
        phaseChange.phase = .concluding
        suite.expect(ForkMacBackupAgentIPCSupport.shouldPublish(phaseChange, last: base, lastWrittenAt: t0, leaseModifiedAt: nil,
                                                                now: t0.addingTimeInterval(0.1)),
                     "a phase change is published at once")
        var same = base
        same.updatedAt = t0.addingTimeInterval(60)
        suite.expect(!ForkMacBackupAgentIPCSupport.shouldPublish(same, last: base, lastWrittenAt: t0, leaseModifiedAt: nil,
                                                                 now: t0.addingTimeInterval(60))
                        && ForkMacBackupAgentIPCSupport.shouldPublish(same, last: base, lastWrittenAt: t0, leaseModifiedAt: nil,
                                                                      now: t0.addingTimeInterval(301)),
                     "an unchanged state is rewritten only as a 5 min heartbeat")
        suite.expect(ForkMacBackupAgentIPCSupport.updateHoldIsFresh(modifiedAt: t0, now: t0.addingTimeInterval(19 * 60))
                        && !ForkMacBackupAgentIPCSupport.updateHoldIsFresh(modifiedAt: t0, now: t0.addingTimeInterval(21 * 60))
                        && !ForkMacBackupAgentIPCSupport.updateHoldIsFresh(modifiedAt: nil, now: t0),
                     "the updater's hold lasts 20 min at most")
        let names = ForkMacBackupAgentIPCSupport.Names(bundleID: "io.example.app")
        suite.expect(names.meeting == "io.example.app.macbackup.meeting" && names.handover == "io.example.app.macbackup.handover",
                     "the agent's notify names derive from the bundle id")
    }

    private static func commands(_ suite: TestSuite) {
        let all: [ForkMacBackupCommand] = [.backUpNow, .pause(until: t0), .pause(until: nil), .resume, .slowDown(true),
                                           .verify(.contentSample(percent: 10)), .verify(.restoreTest(files: 50)), .cancel,
                                           .reloadSettings]
        let files = all.enumerated().map { index, command in
            ForkMacBackupCommandFile(command: command, origin: .island, issuedAt: t0.addingTimeInterval(Double(index)))
        }
        var disk: [(name: String, data: Data?)] = files.reversed().map { ($0.fileName, $0.encoded()) }
        let stale = ForkMacBackupCommandFile(command: .backUpNow, origin: .settings, issuedAt: t0.addingTimeInterval(-11 * 60))
        disk.append((stale.fileName, stale.encoded()))
        disk.append(("broken.json", Data("{".utf8)))
        disk.append(("note.txt", Data()))
        disk.append((files[0].fileName + ".json", files[0].encoded()))
        let inbox = ForkMacBackupAgentIPCSupport.inbox(disk, now: t0.addingTimeInterval(20))
        suite.expect(inbox.run.map(\.command) == all,
                     "every command decodes, oldest first, a duplicate once (backUpNow, pause, resume, slowDown, verify, cancel, reloadSettings)")
        suite.expect(inbox.delete.count == disk.count - 1 && !inbox.delete.contains("note.txt"),
                     "every command file read is deleted, the stale and broken ones too")
        let appWritten = Data(#"{"command":{"pause":{"until":1792667040}},"formatVersion":1,"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","issuedAt":1792663440,"origin":"island"}"#.utf8)
        suite.expect(ForkMacBackupCommandFile.decode(appWritten)?.command == .pause(until: t0.addingTimeInterval(hour)),
                     "a pause written by the app's status model decodes")
    }

    // MARK: Plist

    private static func plist(_ suite: TestSuite) {
        let bundle = "io.github.example.swishsaint"
        let release = ForkMacBackupAgentPlist.release(bundleID: bundle, executable: "Swishsaint")
        let keepAlive = release["KeepAlive"] as? [String: Any]
        suite.expect(release["Label"] as? String == "io.github.example.swishsaint.backup-agent"
                        && release["BundleProgram"] as? String == "Contents/MacOS/Swishsaint"
                        && release["ProgramArguments"] as? [String] == ["Contents/MacOS/Swishsaint", "--fork-backup-agent"]
                        && keepAlive?["SuccessfulExit"] as? Bool == false && release["RunAtLoad"] as? Bool == true
                        && release["ProcessType"] as? String == "Standard"
                        && release["LowPriorityBackgroundIO"] == nil && release["Program"] == nil
                        && release["AssociatedBundleIdentifiers"] as? [String] == [bundle]
                        && release["ExitTimeOut"] as? Int == 60,
                     "the release plist: BundleProgram, the flag, KeepAlive on failure only, a standard process (no Background, no low-priority I/O), 60 s to stop")
        let legacy = ForkMacBackupAgentPlist.legacy(bundleID: bundle, executablePath: "/tmp/App.app/Contents/MacOS/App")
        suite.expect(legacy["ProcessType"] as? String == "Standard" && legacy["LowPriorityBackgroundIO"] == nil,
                     "the Developer plist is a standard process too: priority is the engine's job, per run")
        suite.expect(legacy["Program"] as? String == "/tmp/App.app/Contents/MacOS/App" && legacy["BundleProgram"] == nil
                        && legacy["ProgramArguments"] as? [String] == ["/tmp/App.app/Contents/MacOS/App", "--fork-backup-agent"]
                        && legacy["LimitLoadToSessionType"] as? String == "Aqua",
                     "the Developer plist names the program by its absolute path")
        suite.expect(ForkMacBackupAgentPlist.data(release).flatMap {
            try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
        }.map { ForkMacBackupAgentPlist.same($0, release) } == true, "it writes as XML and reads back the same")
        suite.expect(ForkMacBackupAgentPlist.legacyURL(home: URL(fileURLWithPath: "/Users/test"), bundleID: bundle).path
                        == "/Users/test/Library/LaunchAgents/io.github.example.swishsaint.backup-agent.plist"
                        && ForkMacBackupAgentPlist.bundledURL(appURL: URL(fileURLWithPath: "/Applications/S.app"), bundleID: bundle).path
                        == "/Applications/S.app/Contents/Library/LaunchAgents/io.github.example.swishsaint.backup-agent.plist",
                     "the plists' places")
        let template = (try? String(contentsOfFile: "fork/macbackup-agent.plist", encoding: .utf8)) ?? ""
        let filled = ForkMacBackupAgentPlist.filledTemplate(template, bundleID: bundle, executable: "Swishsaint")
        let parsed = (try? PropertyListSerialization.propertyList(from: Data(filled.utf8), format: nil)) as? [String: Any]
        suite.expect(parsed.map { ForkMacBackupAgentPlist.same($0, release) } == true,
                     "fork/macbackup-agent.plist, filled as build-release.sh fills it, is exactly the release plist")
    }

    private static func lock(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fork-macbackup-agent-lock-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("agent.lock")
        let first = ForkMacBackupAgentLock(url: url)
        let second = ForkMacBackupAgentLock(url: url)
        suite.expect(first.acquire(role: .app, pid: 4242) == .acquired, "the first instance takes the lock")
        suite.expect(second.acquire(role: .agent) == .held(role: .app, pid: 4242),
                     "a second one is refused, and told who holds it (the app's runner hands over, an agent leaves)")
        first.release()
        suite.expect(second.acquire(role: .agent, pid: 7) == .acquired && second.isHeld, "released, the lock can be taken")
        suite.expect(first.acquire(role: .agent) == .held(role: .agent, pid: 7), "a second agent sees an agent")
        second.release()
        let parsed = ForkMacBackupAgentLock.parse("app 99")
        suite.expect(parsed.role == .app && parsed.pid == 99 && ForkMacBackupAgentLock.parse("").role == nil,
                     "the holder line « role pid » parses, an empty one says nothing")
    }

    // MARK: Pending changes

    private static func pending(_ suite: TestSuite) {
        let source = ForkMacBackupSource(path: home, presets: [.trash, .caches, .devFolders, .logs], customRules: ["*.tmp", "/Movies/Exports/"])
        let filter = ForkMacBackupPendingChanges.Filter(source: source, extraRules: ["/VMs/big.img"], home: home,
                                                        ignoredPrefixes: [home + "/Library/Application Support/app/MacBackup"])
        suite.expect(filter.weight(of: home + "/Documents/devis.pdf") == .important
                        && filter.weight(of: home + "/Desktop/a.png") == .important
                        && filter.weight(of: home + "/Projects/x.swift") == .ordinary
                        && filter.weight(of: home + "/Library/Preferences/a.plist") == .library,
                     "Documents and Desktop weigh more, Library less")
        suite.expect(filter.weight(of: home + "/.Trash/old.txt") == nil
                        && filter.weight(of: home + "/Library/Caches/com.app/x") == nil
                        && filter.weight(of: home + "/Projects/web/node_modules/react/index.js") == nil
                        && filter.weight(of: home + "/Documents/log/app.log") == nil
                        && filter.weight(of: home + "/Documents/draft.tmp") == nil
                        && filter.weight(of: home + "/Movies/Exports/film.mov") == nil
                        && filter.weight(of: home + "/VMs/big.img") == nil
                        && filter.weight(of: home + "/Library/Application Support/app/MacBackup/state.json") == nil
                        && filter.weight(of: home + "/Documents/.DS_Store") == nil
                        && filter.weight(of: "/Volumes/Other/file") == nil,
                     "excluded by the rules (anchored, folder, glob), our own files and .DS_Store are not counted")
        suite.expect(filter.weight(of: home + "/Projects/Caches/keep.txt") == .ordinary
                        && filter.weight(of: home + "/Projects/.Trash/keep.txt") == .ordinary,
                     "an anchored rule only acts at the source's root")
        var tally = ForkMacBackupPendingChanges.Tally()
        tally.add(home + "/Documents/a", weight: .important, eventID: 10)
        tally.add(home + "/Documents/a", weight: .important, eventID: 12)
        tally.add(home + "/Projects/b", weight: .ordinary, eventID: 11)
        tally.add(home + "/Library/c", weight: .library, eventID: 30)
        suite.expect(tally.summary == ForkMacBackupPendingSummary(total: 3, important: 1, weighted: 6.1),
                     "distinct paths counted once, weighted")
        tally.reset(upTo: 20)
        suite.expect(tally.summary.total == 1, "a complete snapshot clears what happened before its start only")
        suite.expect(ForkMacBackupPendingChanges.replayStart(saved: 100, current: 500) == 100
                        && ForkMacBackupPendingChanges.replayStart(saved: 900, current: 500) == nil
                        && ForkMacBackupPendingChanges.replayStart(saved: nil, current: 500) == nil,
                     "FSEvents replays from the saved event, unless the history was reset")
        let file = ForkMacBackupPendingChanges.File(sinceEventID: 77, since: t0, total: 3, important: 1, updatedAt: t0)
        suite.expect(ForkMacBackupPendingChanges.File.decode(try! ForkMacBackupJSON.encoder.encode(file)) == file,
                     "pending.json round-trips")
    }

    // MARK: Neighbours

    private static func tailscale(_ suite: TestSuite) {
        suite.expect(ForkMacBackupTailscale.command(isExecutable: { $0 == "/Applications/Tailscale.app/Contents/MacOS/Tailscale" })
                        == .init(path: "/Applications/Tailscale.app/Contents/MacOS/Tailscale", arguments: ["status", "--json"],
                                 environment: ["TAILSCALE_BE_CLI": "1"])
                        && ForkMacBackupTailscale.command(isExecutable: { _ in true })?.path == "/usr/local/bin/tailscale"
                        && ForkMacBackupTailscale.command(isExecutable: { _ in false }) == nil,
                     "the standalone CLI first, else the app's binary as a CLI (TAILSCALE_BE_CLI=1), else none")
        let status = fixture("agent-tailscale-status.json").flatMap(ForkMacBackupTailscale.decode)
        suite.expect(status?.backendState == "Running" && status?.peers.count == 2, "tailscale status --json decodes")
        let peer = repository.peer!
        suite.expect(ForkMacBackupTailscale.peerOnline(peer, status: status) == true, "the peer, found by its stable ID, is online")
        var renamed = peer
        renamed.stableID = "nGONE"
        renamed.dnsName = "MINIO.example.ts.net"
        suite.expect(ForkMacBackupTailscale.peer(renamed, in: status!)?.id == "nABC123CNTRL",
                     "an unknown ID falls back on the DNS name, any case, final dot or not")
        suite.expect(ForkMacBackupTailscale.peerOnline(.init(stableID: "nOFF456CNTRL", dnsName: "", hostName: "nas"), status: status) == false
                        && ForkMacBackupTailscale.peerOnline(.init(stableID: "x", dnsName: "y", hostName: "z"), status: status) == false
                        && ForkMacBackupTailscale.peerOnline(peer, status: nil) == nil,
                     "an offline or missing peer is offline; without Tailscale nothing is said")
        var stopped = status!
        stopped.backendState = "Stopped"
        suite.expect(ForkMacBackupTailscale.peerOnline(peer, status: stopped) == false, "Tailscale stopped: the peer is out of reach")
    }

    private static func otherEngine(_ suite: TestSuite) {
        suite.expect(ForkMacBackupOtherEngine.isWriter(executable: "/usr/local/bin/kopia", arguments: ["kopia", "snapshot", "create", "/x"])
                        && ForkMacBackupOtherEngine.isWriter(executable: "/A/KopiaUI.app/Contents/Resources/server/kopia",
                                                             arguments: ["kopia", "--config-file=/c", "server", "start", "--ui"])
                        && ForkMacBackupOtherEngine.isWriter(executable: "/x/kopia", arguments: ["kopia", "maintenance", "run", "--full"])
                        && !ForkMacBackupOtherEngine.isWriter(executable: "/x/kopia", arguments: ["kopia", "snapshot", "list"])
                        && !ForkMacBackupOtherEngine.isWriter(executable: "/x/kopia", arguments: ["kopia", "repository", "status"])
                        && !ForkMacBackupOtherEngine.isWriter(executable: "/x/KopiaUI", arguments: ["KopiaUI"]),
                     "a Kopia that snapshots, serves or maintains writes; listing or KopiaUI's shell does not")
        suite.expect(ForkMacBackupOtherEngine.configPath(arguments: ["kopia", "--config-file", "/a.config", "server"], environment: [:], home: home) == "/a.config"
                        && ForkMacBackupOtherEngine.configPath(arguments: ["kopia", "--config-file=/b.config"], environment: [:], home: home) == "/b.config"
                        && ForkMacBackupOtherEngine.configPath(arguments: ["kopia"], environment: ["KOPIA_CONFIG_PATH": "/e"], home: home) == "/e"
                        && ForkMacBackupOtherEngine.configPath(arguments: ["kopia"], environment: [:], home: home)
                        == home + "/Library/Application Support/kopia/repository.config",
                     "its config: the flag, the environment, else Kopia's default")
        let same = Data(#"{"storage":{"type":"s3","config":{"bucket":"mac-test","prefix":"home/","endpoint":"minio.example.ts.net:9000","doNotUseTLS":true}},"caching":{}}"#.utf8)
        let byIP = Data(#"{"storage":{"type":"s3","config":{"bucket":"mac-test","prefix":"/home","endpoint":"100.64.0.7:9000"}}}"#.utf8)
        let other = Data(#"{"storage":{"type":"s3","config":{"bucket":"mac-test","prefix":"other/","endpoint":"minio.example.ts.net:9000"}}}"#.utf8)
        suite.expect(ForkMacBackupOtherEngine.sameRepository(configData: same, as: repository)
                        && ForkMacBackupOtherEngine.sameRepository(configData: byIP, as: repository)
                        && !ForkMacBackupOtherEngine.sameRepository(configData: other, as: repository)
                        && !ForkMacBackupOtherEngine.sameRepository(configData: Data("nope".utf8), as: repository),
                     "the same bucket and prefix on the same host (or one of its addresses) is our repository")
    }

    private static func sparseImages(_ suite: TestSuite) {
        var usage = ForkMacBackupDiskUsage()
        usage.sparseImages = [.init(relativePath: "VMs/kali [x].ext4", logicalBytes: 1_000_000_000_000, allocatedBytes: 4_000_000_000)]
        usage.dataless = ["Library/Mobile Documents/com~apple~CloudDocs/film.mov", "Library/Mobile Documents/x/"]
        let source = ForkMacBackupSource(path: home)
        suite.expect(ForkMacBackupRunRules.extra(for: source, usage: usage, iCloud: .local, home: home)
                        == ["/VMs/kali \\[x].ext4", "/Library/Mobile Documents/com~apple~CloudDocs/film.mov",
                            "/Library/Mobile Documents/x/"],
                     "the run's rules: the sparse images and, in local mode, the cloud-only files (escaped, anchored)")
        suite.expect(ForkMacBackupRunRules.extra(for: ForkMacBackupSource(path: home, presets: []), usage: usage,
                                                 iCloud: .materialize, home: home).isEmpty,
                     "the sparse images stay when their preset is off; nothing cloud-only when iCloud downloads")
        suite.expect(ForkMacBackupRunRules.extra(for: source, usage: ForkMacBackupDiskUsage(), iCloud: .exclude, home: home)
                        == ["/Library/Mobile Documents/"]
                        && ForkMacBackupRunRules.iCloudDriveRule(source: home + "/Library", home: home) == "/Mobile Documents/"
                        && ForkMacBackupRunRules.iCloudDriveRule(source: home + "/Documents", home: home) == nil,
                     "iCloud left out: iCloud Drive's folder, wherever the source starts")
        suite.expect(ForkMacBackupRunRules.matcher(for: source).excludes("Library/Caches", isDirectory: true),
                     "the pre-scan never enters what the source's rules leave out")
    }

    // MARK: Cost, proofs, journal, strings

    private static func cost(_ suite: TestSuite) {
        let start = t0
        let end = t0.addingTimeInterval(600)
        let samples = [ForkMacBackupBatterySample(date: t0.addingTimeInterval(-1_800), percent: 80, onAC: false),
                       ForkMacBackupBatterySample(date: t0, percent: 78, onAC: false),
                       ForkMacBackupBatterySample(date: end, percent: 76.5, onAC: false)]
        let drop = ForkMacBackupCostSupport.batteryDrop(samples: samples, start: start, end: end, startPercent: 78, endPercent: 76.5)
        suite.expect(drop.map { abs($0 - (1.5 - 2.0 / 3)) < 0.001 } == true,
                     "the battery a run cost is its drop beyond the 30 min slope before it")
        var charging = samples
        charging.append(ForkMacBackupBatterySample(date: t0.addingTimeInterval(300), percent: 77, onAC: true))
        suite.expect(ForkMacBackupCostSupport.batteryDrop(samples: charging, start: start, end: end, startPercent: 78, endPercent: 76.5) == nil,
                     "plugged in during the run: no battery cost")
        suite.expect(ForkMacBackupCostSupport.batteryDrop(samples: [], start: start, end: end, startPercent: 50, endPercent: 49) == 1,
                     "without a slope before, the plain drop")
        let runs = [
            ForkMacBackupRunRecord(kind: .backup, trigger: .scheduled, start: t0, end: t0.addingTimeInterval(100), bytesSent: 10, outcome: .complete),
            ForkMacBackupRunRecord(kind: .backup, trigger: .scheduled, start: t0, end: t0.addingTimeInterval(300), bytesSent: 30, outcome: .partial),
            ForkMacBackupRunRecord(kind: .backup, trigger: .scheduled, start: t0, end: t0.addingTimeInterval(9_000), outcome: .failed),
            ForkMacBackupRunRecord(kind: .verify, trigger: .window, start: t0, end: t0.addingTimeInterval(9_000), outcome: .complete),
        ]
        suite.expect(ForkMacBackupCostSupport.cost(runs) == .init(averageDuration: 200, averageBatteryDrop: nil, averageSent: 20, samples: 2)
                        && ForkMacBackupCostSupport.cost([]) == nil,
                     "the cost averages the backups that left a snapshot, nothing before any")
        let starts = [0.0, 1.5, 4.0, 6.0].map { ForkMacBackupRunRecord(kind: .backup, trigger: .scheduled, start: t0.addingTimeInterval($0 * hour), outcome: .complete) }
        suite.expect(ForkMacBackupCostSupport.automaticInterval(starts, now: t0.addingTimeInterval(7 * hour)) == 2 * hour
                        && ForkMacBackupCostSupport.automaticInterval(Array(starts.prefix(2)), now: t0) == nil,
                     "the rhythm Automatic keeps is the median gap of the week (after 3 backups)")
    }

    private static func proofStore(_ suite: TestSuite) {
        var store = ForkMacBackupProofStore()
        let old = manifest(id: "old", start: t0, end: t0.addingTimeInterval(10))
        let new = manifest(id: "new", start: t0.addingTimeInterval(hour), end: t0.addingTimeInterval(hour + 10), errors: ["x"])
        let canceled = manifest(id: "cancel", start: t0.addingTimeInterval(2 * hour), end: t0.addingTimeInterval(2 * hour + 5), incomplete: "canceled")
        let otherMac = manifest(id: "other", start: t0, end: t0.addingTimeInterval(5), host: "other-mac")
        store.reconcile(with: [old, new, canceled, otherMac], paths: [home], identity: repository.clientIdentity, iCloud: .local, now: t0)
        suite.expect(store.proofs.keys.sorted() == ["cancel", "new", "old"] && store.last(of: home)?.manifestID == "new"
                        && store.lastComplete(of: home)?.manifestID == "old" && store.lastBackup(paths: [home]) == new.endDate,
                     "the last (partial) and the last complete snapshot; a canceled one is never « the last », another Mac's never mine")
        store.raise(["old", "new"], to: .contentVerified, at: t0.addingTimeInterval(3 * hour), percent: 10)
        suite.expect(store.proofs["old"]?.level == .contentVerified && store.proofs["old"]?.verifiedPercent == 10
                        && store.proofs["new"]?.level == .present,
                     "a verification raises a complete snapshot, never a partial one")
        store.reconcile(with: [new], paths: [home], identity: repository.clientIdentity, iCloud: .local, now: t0)
        suite.expect(store.proofs["old"] == nil && store.lastComplete(of: home) == nil,
                     "a snapshot removed by the retention is not counted any more")
        store.reconcile(with: [old, new], paths: [home], identity: repository.clientIdentity, iCloud: .local, now: t0)
        store.raise(["old"], to: .restoreTested, at: t0)
        store.reconcile(with: [old, new], paths: [home], identity: repository.clientIdentity, iCloud: .local, now: t0)
        suite.expect(store.proofs["old"]?.level == .restoreTested, "a level reached survives the next reading")
        suite.expect(ForkMacBackupProofStore.decode(store.encoded()!) == store, "proofs.json round-trips")
    }

    private static func journal(_ suite: TestSuite) {
        var data = Data()
        for day in 0..<100 {
            data.append(ForkMacBackupJSON.line(ForkMacBackupSlotRecord(due: t0.addingTimeInterval(Double(day - 99) * 86_400),
                                                                       outcome: .done))!)
        }
        data.append(Data("torn line\n".utf8))
        let kept = ForkMacBackupJSON.lines(ForkMacBackupSlotRecord.self,
                                           from: ForkMacBackupJournal.trimmed(data, as: ForkMacBackupSlotRecord.self, now: t0) { $0.due })
        suite.expect(kept.count == 91 && kept.last?.due == t0, "the journals keep 90 days, torn lines dropped")
        let capped = ForkMacBackupJSON.lines(ForkMacBackupSlotRecord.self,
                                             from: ForkMacBackupJournal.trimmed(data, as: ForkMacBackupSlotRecord.self, now: t0,
                                                                                maxLines: 10) { $0.due })
        suite.expect(capped.count == 10 && capped.last?.due == t0, "and at most their line count, the newest")

        // The window appends a restore while the agent trims: no line is lost.
        let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("fork-macbackup-journal-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("runs.jsonl", isDirectory: false)
        let appends = 300
        let group = DispatchGroup()
        DispatchQueue.global().async(group: group) {
            for index in 0..<appends {
                ForkMacBackupJSON.append(ForkMacBackupSlotRecord(due: t0.addingTimeInterval(Double(index)), outcome: .done),
                                         to: url)
            }
        }
        DispatchQueue.global().async(group: group) {
            for _ in 0..<150 {
                ForkMacBackupJSON.rewrite(url) {
                    ForkMacBackupJournal.trimmed($0, as: ForkMacBackupSlotRecord.self, now: t0.addingTimeInterval(1_000)) { $0.due }
                }
            }
        }
        group.wait()
        let survived = (try? Data(contentsOf: url)).map { ForkMacBackupJSON.lines(ForkMacBackupSlotRecord.self, from: $0) } ?? []
        suite.expect(survived.count == appends && Set(survived.map(\.due)).count == appends,
                     "a trim and appends from another process side by side keep every line (\(survived.count)/\(appends))")
        let mode = (try? FileManager.default.attributesOfItem(atPath: url.path + ".lock"))?[.posixPermissions] as? Int
        suite.expect(mode == 0o600, "the journal's lock file is private")
    }

    private static func priorities(_ suite: TestSuite) {
        let low = settings([ForkDefaultsKey.macBackupPriority: "low"])
        suite.expect(low.enginePriority(for: .scheduled) == .background && low.enginePriority(for: .catchUp) == .background,
                     "the planner's runs follow « Priorité basse »")
        suite.expect(low.enginePriority(for: .island) == .normal, "« Sauvegarder maintenant » runs at normal priority")
        suite.expect(low.enginePriority(for: .scheduled, firstBackup: true) == .normal
                        && low.enginePriority(for: .agent, firstBackup: true) == .normal,
                     "the first backup after the setup runs at normal priority, even started by the planner")
        let background = ForkMacBackupKopiaInvocation.Priority.background
        suite.expect(background.darwinValue == PRIO_DARWIN_BG
                        && ForkMacBackupKopiaInvocation.Priority.normal.darwinValue == 0
                        && ForkMacBackupKopiaInvocation.Priority.utility.darwinValue == 0,
                     "only a scheduled run puts the server in the macOS background state")
        suite.expect(background.serverSpawn == .utility
                        && ForkMacBackupKopiaInvocation.Priority.normal.serverSpawn == .normal,
                     "a server is never spawned in a background class it could not leave for « Sauvegarder maintenant »")
    }

    /// Rules imported with the settings backup (the two keys) reach the agent, not the per-source copies.
    private static func importedRules(_ suite: TestSuite) {
        var all: [String: Any] = [ForkDefaultsKey.macBackupEnabled: true]
        all[ForkDefaultsKey.macBackupRepository] = try! ForkMacBackupJSON.encoder.encode(repository)
        // The machine state still carries the old copies.
        all[ForkDefaultsKey.macBackupSources] = try! ForkMacBackupJSON.encoder.encode([
            ForkMacBackupSource(path: "/Users/test", presets: [.trash], customRules: ["old.tmp"]),
            ForkMacBackupSource(path: "/Volumes/Data", presets: [.trash], customRules: ["old.tmp"])])
        all[ForkDefaultsKey.macBackupPresets] = "caches,logs"
        all[ForkDefaultsKey.macBackupRules] = "[\"node_modules\", \" *.iso \", \"\"]"
        let imported = ForkMacBackupAgentSettings { all[$0] }
        suite.expect(imported.sources.count == 2
                        && imported.sources.allSatisfy { $0.presets == ForkMacBackupPreset.parse("caches,logs") }
                        && imported.sources.allSatisfy { $0.customRules == ["node_modules", "*.iso"] },
                     "the agent reads the presets and rules from the keys the Settings write and the import restores")
        all[ForkDefaultsKey.macBackupRules] = ""
        all[ForkDefaultsKey.macBackupPresets] = ""
        let cleared = ForkMacBackupAgentSettings { all[$0] }
        suite.expect(cleared.sources.allSatisfy { $0.presets.isEmpty && $0.customRules.isEmpty },
                     "emptied in the Settings, emptied for the agent: no stale per-source copy")
        all[ForkDefaultsKey.macBackupPresets] = nil
        let fallback = ForkMacBackupAgentSettings { all[$0] }
        suite.expect(fallback.sources.allSatisfy { $0.presets == ForkMacBackupPreset.defaultApplied },
                     "an unset key reads as the registered default")
        suite.expect(imported.sources != ForkMacBackupAgentSettings { key in
            var other = all
            other[ForkDefaultsKey.macBackupRules] = "[\"node_modules\"]"
            return other[key]
        }.sources, "a change of the rules key changes the agent's sources, which makes it re-apply the policy on reload")
    }

    private static func prescanPlan(_ suite: TestSuite) {
        let source = ForkMacBackupSource(path: home)
        let localPrint = ForkMacBackupPrescanPlan.fingerprint(source: source, iCloud: .local)
        var usage = ForkMacBackupDiskUsage()
        usage.allocatedBytes = 40_000_000_000
        usage.sparseImages = [.init(relativePath: "vm/old.img", logicalBytes: 64_000_000_000, allocatedBytes: 2_000_000_000)]
        usage.dataless = ["Library/Mobile Documents/com~apple~CloudDocs/a.pdf", "Library/Mobile Documents/x/"]
        usage.datalessBytes = 3_000_000
        let walked = ForkMacBackupPrescanCache.Entry(date: t0, fingerprint: localPrint, usage: usage)
        func choice(_ cached: ForkMacBackupPrescanCache.Entry?, after: TimeInterval, onAC: Bool = true, known: Bool = true,
                    fingerprint: String? = nil) -> ForkMacBackupPrescanPlan.Choice {
            ForkMacBackupPrescanPlan.choose(cached: cached, fingerprint: fingerprint ?? localPrint, now: t0.addingTimeInterval(after),
                                            onAC: onAC, changesKnown: known)
        }
        suite.expect(choice(nil, after: 0) == .walk, "no walk yet: walk")
        suite.expect(choice(walked, after: 6 * hour) == .reuse && choice(walked, after: 23 * hour) == .reuse,
                     "a walk is reused a day, refreshed with the changes FSEvents saw")
        suite.expect(choice(walked, after: 25 * hour, onAC: true) == .walk, "past a day on mains power: walk again")
        suite.expect(choice(walked, after: 3 * 24 * hour, onAC: false) == .reuse
                        && choice(walked, after: 8 * 24 * hour, onAC: false) == .walk,
                     "on battery the walk waits, a week at most")
        suite.expect(choice(walked, after: hour, known: false) == .walk, "changes not known (events dropped): walk")
        suite.expect(choice(walked, after: -hour) == .walk, "a clock set back: walk")
        let excluding = ForkMacBackupSource(path: home, presets: ForkMacBackupPreset.defaultApplied.filter { $0 != .sparseDiskImages })
        suite.expect(choice(walked, after: hour, fingerprint: ForkMacBackupPrescanPlan.fingerprint(source: excluding, iCloud: .local)) == .walk
                        && choice(walked, after: hour, fingerprint: ForkMacBackupPrescanPlan.fingerprint(source: source, iCloud: .materialize)) == .walk,
                     "other rules or another iCloud mode: walk")

        suite.expect(ForkMacBackupPrescanPlan.relativeChanges(["/Users/test/vm/new.img", "/Users/testing/x", "/Users/test",
                                                               "/Users/test/Documents/a b.txt"], source: home)
                        == ["vm/new.img", "Documents/a b.txt"],
                     "the changes are taken relative to the source, never a neighbour's")

        typealias Change = ForkMacBackupPrescanPlan.Change
        let changes = [
            Change(relativePath: "vm/old.img", exists: true, isRegularFile: true, logicalBytes: 64_000_000_000,
                   allocatedBytes: 60_000_000_000, isDataless: false),
            Change(relativePath: "vm/new.img", exists: true, isRegularFile: true, logicalBytes: 20_000_000_000,
                   allocatedBytes: 1_000_000_000, isDataless: false),
            Change(relativePath: "Library/Caches/huge.img", exists: true, isRegularFile: true, logicalBytes: 20_000_000_000,
                   allocatedBytes: 1, isDataless: false),
            Change(relativePath: "Library/Mobile Documents/com~apple~CloudDocs/a.pdf", exists: true, isRegularFile: true,
                   logicalBytes: 1_000_000, allocatedBytes: 1_000_000, isDataless: false),
            Change(relativePath: "Library/Mobile Documents/com~apple~CloudDocs/b.mov", exists: true, isRegularFile: true,
                   logicalBytes: 5_000_000, allocatedBytes: 0, isDataless: true),
        ]
        let refreshed = ForkMacBackupPrescanPlan.refreshed(walked, changes: changes, matcher: ForkMacBackupRunRules.matcher(for: source),
                                                           collectDataless: true)
        suite.expect(refreshed.sparseImages.map(\.relativePath) == ["vm/new.img"],
                     "a refresh drops an image now written, adds a new one, ignores what the rules leave out")
        suite.expect(refreshed.dataless == ["Library/Mobile Documents/com~apple~CloudDocs/b.mov", "Library/Mobile Documents/x/"]
                        && refreshed.datalessBytes == 7_000_000 && refreshed.date == t0 && refreshed.realBytes == usage.allocatedBytes,
                     "and follows the files downloaded or evicted meanwhile, the walk's date and real size kept")
        let gone = ForkMacBackupPrescanPlan.refreshed(walked, changes: [Change(relativePath: "vm/old.img", exists: false,
                                                                               isRegularFile: false, logicalBytes: 0,
                                                                               allocatedBytes: 0, isDataless: false)],
                                                      matcher: ForkMacBackupRunRules.matcher(for: source), collectDataless: true)
        suite.expect(gone.sparseImages.isEmpty && gone.dataless == walked.dataless, "a deleted image leaves the list")
        let rules = ForkMacBackupRunRules.extra(for: source, sparseImages: refreshed.sparseImages, dataless: refreshed.dataless,
                                                iCloud: .local, home: home)
        suite.expect(rules.contains("/vm/new.img") && rules.contains("/Library/Mobile Documents/x/"),
                     "the refreshed walk gives the run's rules")
        let cache = ForkMacBackupPrescanCache(entries: [home: refreshed])
        suite.expect(cache.encoded().flatMap(ForkMacBackupPrescanCache.decode) == cache, "prescan.json reads back what it wrote")

        let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("fork-macbackup-probe-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let sparse = folder.appendingPathComponent("disk image.img")
        FileManager.default.createFile(atPath: sparse.path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: sparse) {
            try? handle.truncate(atOffset: 11_000_000_000)
            try? handle.close()
        }
        let probed = ForkMacBackupPrescanPlan.probe("disk image.img", root: folder.path)
        let missing = ForkMacBackupPrescanPlan.probe("nothing.txt", root: folder.path)
        suite.expect(probed.exists && probed.isRegularFile && probed.logicalBytes == 11_000_000_000
                        && probed.allocatedBytes < 1_000_000 && !probed.isDataless && !missing.exists,
                     "a changed file is looked at with lstat: a new sparse image is seen at its real size")
    }

    private static func materialize(_ suite: TestSuite) {
        let gb: Int64 = 1_000_000_000
        suite.expect(ForkMacBackupMaterializeCheck.refusal(datalessBytes: 0, datalessFolders: 0, freeBytes: nil) == nil,
                     "nothing in the cloud only: nothing to check")
        suite.expect(ForkMacBackupMaterializeCheck.refusal(datalessBytes: 10 * gb, datalessFolders: 0, freeBytes: 16 * gb) == nil,
                     "10 GB to download with 16 GB free: allowed (5 GB kept free)")
        let refused = ForkMacBackupMaterializeCheck.refusal(datalessBytes: 10 * gb, datalessFolders: 2, freeBytes: 14 * gb)
        suite.expect(refused?.contains("10000000000 bytes to download") == true && refused?.contains("2 cloud-only folder") == true,
                     "10 GB with 14 GB free: refused, the sizes said")
        suite.expect(ForkMacBackupMaterializeCheck.margin(datalessBytes: 200 * gb) == 20 * gb
                        && ForkMacBackupMaterializeCheck.refusal(datalessBytes: 200 * gb, datalessFolders: 0, freeBytes: 215 * gb) != nil,
                     "a big download keeps a tenth of it free")
        suite.expect(ForkMacBackupMaterializeCheck.refusal(datalessBytes: gb, datalessFolders: 0, freeBytes: nil) != nil,
                     "free space unknown: refused")

        var (machine, _) = startedMachine()
        let source = ForkMacBackupSource(path: "/Users/test")
        _ = machine.handle(.chainChecked(nil, nodeID: nil), now: t0)
        let actions = machine.handle(.policyApplied(source, .refused(.localSpace, "iCloud download refused")), now: t0)
        suite.expect(runEnded(actions)?.result == .failed(.localSpace) && !actions.contains(.triggerSnapshot(source))
                        && machine.lastError?.cause == .localSpace && machine.lastError?.message == "iCloud download refused",
                     "a refused download fails the run « Mac presque plein » before any snapshot, the reason kept")
    }

    private static func strings(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let text = ForkMacBackupAgentStrings.strings(language)
            let all = [text.keepAwakeReason, text.appOnly, text.needsApproval, text.development]
            suite.expect(all.allSatisfy { !$0.isEmpty } && text.appOnly.contains("%@") && text.needsApproval.contains("%@")
                            && !text.keepAwakeReason.contains("%@") && text.keepAwakeReason.count <= 40,
                         "\(language.rawValue): every agent text exists, the app's name where it is said")
        }
        let french = ForkMacBackupAgentStrings.fr
        let frenchTexts = [french.keepAwakeReason, french.appOnly, french.needsApproval, french.development]
        suite.expect(frenchTexts.allSatisfy { text in
            [":", ";", "!", "?"].allSatisfy { mark in !text.contains(" " + mark) }
                && !text.contains("'")
        } && french.keepAwakeReason == "Sauvegarde du Mac en cours",
                     "French: no plain space before « : ; ! ? », typographic apostrophes")
    }
}
