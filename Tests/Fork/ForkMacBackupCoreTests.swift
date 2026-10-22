// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Suite `fork-macbackup-core`: the frozen models, contracts, presentation,
/// formatting and shared words of Mac Backup (`Fork/MacBackup/Core`).
enum ForkMacBackupCoreTests {
    static func run(_ suite: TestSuite) {
        models(suite)
        presets(suite)
        classifier(suite)
        proofs(suite)
        contracts(suite)
        fixtures(suite)
        presentation(suite)
        ipc(suite)
        paths(suite)
        defaults(suite)
        formatting(suite)
        strings(suite)
        headlines(suite)
        staleAgent(suite)
    }

    // MARK: Helpers

    private static func roundTrips<Value: Codable & Equatable>(_ value: Value) -> Bool {
        guard let data = try? ForkMacBackupJSON.encoder.encode(value),
              let back = try? ForkMacBackupJSON.decoder.decode(Value.self, from: data) else { return false }
        return back == value
    }

    private static func json<Value: Decodable>(_ type: Value.Type, _ text: String) -> Value? {
        ForkMacBackupKopia.decode(type, from: Data(text.utf8))
    }

    private static func fixture(_ name: String) -> Data? {
        try? Data(contentsOf: URL(fileURLWithPath: "Tests/Fork/Fixtures/MacBackup/\(name)"))
    }

    private static func locale(_ identifier: String, twelveHour: Bool) -> Locale {
        var components = Locale.Components(identifier: identifier)
        components.hourCycle = twelveHour ? .oneToTwelve : .zeroToTwentyThree
        return Locale(components: components)
    }

    private static let now = Date(timeIntervalSince1970: 1_792_663_440) // 22/10/2026, a fixed instant

    private static let repository = ForkMacBackupRepository(
        endpoint: .init(host: "minio.example.ts.net", port: 9000, tls: false, observedIPs: ["100.64.0.7"]),
        bucket: "mac-test", region: "us-east-1", prefix: "home/", accessKeyID: "kopia-test",
        expectedUniqueID: "AC2952930000000000000000000000000000000000000000000000000000F120",
        clientIdentity: .init(userName: "test", hostName: "test-mac"),
        peer: .init(stableID: "nABC123CNTRL", dnsName: "minio.example.ts.net.", hostName: "minio"),
        serverFlavor: .minio)

    // MARK: Models

    private static func models(_ suite: TestSuite) {
        let profile = ForkMacBackupProfile(name: "Maison", repository: repository,
                                           chain: ForkMacBackupProfile.defaultChain(for: repository),
                                           explanation: "Le Mac chiffre tout.")
        suite.expect(roundTrips(repository) && roundTrips(profile), "a repository and a profile survive JSON")
        suite.expect(ForkMacBackupProfile.decode(try! ForkMacBackupJSON.encoder.encode(profile)) == profile,
                     "a profile file reads back")
        var newer = profile
        newer.formatVersion = ForkMacBackupProfile.formatVersion + 1
        suite.expect(ForkMacBackupProfile.decode(try! ForkMacBackupJSON.encoder.encode(newer)) == nil,
                     "a profile of a newer format is refused rather than misread")
        suite.expect(profile.chain.map(\.kind) == [.mac, .network, .tailscale, .s3, .repository]
                        && profile.chain.first { $0.kind == .s3 }?.probe?.kind == .minioHealth,
                     "the default chain follows the repository: Tailscale when a peer is set, MinIO probes for MinIO")

        var moved = repository
        moved.endpoint = .init(host: "100.64.0.7", port: 9000, tls: false)
        suite.expect(moved.key == repository.key && repository.key.hasPrefix("s3-") && repository.key.count == 19,
                     "the repository's folder key survives an endpoint change (IP ↔ MagicDNS)")
        var other = repository
        other.bucket = "mac-other"
        suite.expect(other.key != repository.key, "another bucket is another repository")
        suite.expect(repository.accepts(uniqueID: repository.expectedUniqueID!.lowercased())
                        && !repository.accepts(uniqueID: "deadbeef"),
                     "the expected unique ID locks the repository, whatever the case")
        suite.expect(ForkMacBackupRepository.Endpoint(host: "fd7a::1", port: 9000).hostAndPort == "[fd7a::1]:9000"
                        && ForkMacBackupRepository.Endpoint(host: "s3.example.com").hostAndPort == "s3.example.com",
                     "an endpoint is written the way Kopia's --endpoint takes it")
        suite.expect(ForkMacBackupRepository.Identity(parsing: "test@test-mac")?.description == "test@test-mac"
                        && ForkMacBackupRepository.Identity(parsing: "test@") == nil
                        && ForkMacBackupRepository.shortID("ac2952930000f120") == "ac29…f120",
                     "identities and short IDs read and print")

        let source = ForkMacBackupSource(path: "/Users/test", presets: [.logs, .trash, .logs], customRules: ["*.tmp", "*.log"])
        suite.expect(roundTrips(source) && source.presets == [.trash, .logs]
                        && source.ignoreRules == ["/.Trash/", "*.log", "*.tmp"],
                     "a source keeps its presets once, in a stable order, and its rules without duplicates")
        let fr = ForkMacBackupStrings.strings(.fr)
        suite.expect(source.displayName(fr, home: "/Users/test") == "Dossier personnel"
                        && source.displayName(fr, home: "/Users/other") == "test"
                        && ForkMacBackupFormat.sourceName("/Users/louis/", text: fr, userName: "louis", home: "/Users/m") == "Dossier personnel"
                        && ForkMacBackupFormat.sourceName("/Users/m/Documents", text: fr, home: "/Users/m") == "Documents"
                        && ForkMacBackupFormat.sourceName("/", text: fr, home: "/Users/m") == "/",
                     "a home folder reads « Dossier personnel », never the account's name; other sources their folder's")
        let rules = ForkMacBackupPolicyRules(source: source, extraRules: ["/big.raw"], retention: .balanced)
        suite.expect(rules.ignoreRules == rules.ignoreRules.sorted() && rules.manual && !rules.ignoreCacheDirs
                        && rules == ForkMacBackupPolicyRules(ignoreRules: rules.ignoreRules.reversed(),
                                                             ignoreCacheDirs: false, retention: .balanced),
                     "a policy compares equal whatever order Kopia reads its rules back in, and is always manual")

        let failure = ForkMacBackupFailure(path: "a.txt", message: "open a.txt: permission denied")
        let proof = ForkMacBackupSnapshotProof(manifestID: "k1", sourcePath: "/Users/test", endTime: now, level: .complete,
                                               bytes: 10, files: 2, failures: [failure], cloudOnly: ["x"])
        let run = ForkMacBackupRunRecord(kind: .backup, trigger: .scheduled, start: now, end: now.addingTimeInterval(180),
                                         bytesSent: 3, bytesRead: 4, cpuSeconds: 1.5, batteryDrop: 0.8, onBattery: true,
                                         proofs: [proof], outcome: .partial, stopReason: .meeting,
                                         verifyLevel: .contentSample(percent: 1))
        let slots = [ForkMacBackupSlotRecord(due: now, outcome: .missed(.asleep)),
                     ForkMacBackupSlotRecord(due: now, outcome: .done, startedAt: now.addingTimeInterval(600), runID: run.id)]
        let sample = ForkMacBackupCapacitySample(kind: .nasFree, bytes: 29_300_000_000_000, date: now, source: "qnap")
        suite.expect(roundTrips(proof) && roundTrips(run) && slots.allSatisfy(roundTrips) && roundTrips(sample),
                     "proofs, runs, slots (missed with its reason) and capacity samples survive JSON")
        suite.expect(run.duration == 180 && slots[1].startedLate && !slots[0].startedLate,
                     "a run knows its duration, a slot whether it started late")
        let jsonl = slots.compactMap(ForkMacBackupJSON.line).reduce(Data(), +) + Data("{torn".utf8)
        suite.expect(ForkMacBackupJSON.lines(ForkMacBackupSlotRecord.self, from: jsonl) == slots,
                     "a JSONL file reads every whole line and skips a torn one")
        suite.expect(ForkMacBackupMissedReason.allCases.count == 14
                        && ForkMacBackupWaitReason.allCases.compactMap(\.missedReason).allSatisfy {
                            ForkMacBackupMissedReason.allCases.contains($0)
                        },
                     "every missed reason of the plan exists, and a wait maps onto one")
        suite.expect(ForkMacBackupRetention.parse("10,48,30,8,12,3") == .balanced
                        && ForkMacBackupRetention.parse("1,2,3") == nil && ForkMacBackupRetention.parse("1,2,3,4,5,-1") == nil
                        && ForkMacBackupRetention.preset(.custom, custom: "junk") == .balanced
                        && ForkMacBackupRetention.long.storageValue == "10,48,60,26,36,10",
                     "retention presets and the custom six numbers read and write")
    }

    // MARK: Presets

    private static func presets(_ suite: TestSuite) {
        suite.expect([.docker, .appleContainer, .sparseDiskImages, .trash, .caches, .devFolders, .cloudStorage, .logs,
                      .cacheDirTag].allSatisfy { (preset: ForkMacBackupPreset) in preset.isDefault },
                     "Docker, Apple Container and sparse disk images are excluded by default (decision 1 of 22/10)")
        suite.expect(![.genericBuildNames, .secrets, .virtualMachines].contains { (preset: ForkMacBackupPreset) in
            preset.isDefault
        }, "generic build names, secrets and virtual machines are never excluded by default")
        suite.expect(ForkMacBackupPreset.docker.patterns == ["/Library/Containers/com.docker.docker/"]
                        && ForkMacBackupPreset.appleContainer.patterns == ["/Library/Application Support/com.apple.container/"]
                        && ForkMacBackupPreset.sparseDiskImages.patterns.isEmpty,
                     "the container presets name their real folders; sparse images are found by size, not by path")
        let stored = ForkMacBackupPreset.storageValue(ForkMacBackupPreset.defaultApplied)
        suite.expect(ForkMacBackupPreset.parse(stored) == ForkMacBackupPreset.defaultApplied
                        && ForkMacBackupPreset.parse("logs, future,trash") == [.trash, .logs]
                        && ForkMacBackupPreset.parse("").isEmpty,
                     "the presets list reads back, skips a newer build's names and keeps declaration order")
    }

    // MARK: Failures

    private static func classifier(_ suite: TestSuite) {
        let cases: [(String, String, ForkMacBackupFailureCause)] = [
            ("unable to open file: open /Users/t/Library/Mobile Documents/x.mp4: resource deadlock avoided",
             "Library/Mobile Documents/x.mp4", .cloudOnly),
            ("read /Users/t/Library/Mobile Documents/com~apple~CloudDocs/a.pdf: operation canceled",
             "Library/Mobile Documents/com~apple~CloudDocs/a.pdf", .cloudOnly),
            ("read /Users/t/Documents/a.db: operation canceled", "Documents/a.db", .busy),
            ("unable to open file: open /Users/t/a: permission denied", "a", .permission),
            ("open /Users/t/Library/Mail: operation not permitted", "Library/Mail", .permission),
            ("lstat /Users/t/tmp/x: no such file or directory", "tmp/x", .vanished),
            ("read /Users/t/v.raw: resource busy", "v.raw", .busy),
            ("something else entirely", "z", .other),
        ]
        let wrong = cases.filter { ForkMacBackupFailureCause.classify(message: $0.0, path: $0.1) != $0.2 }
        suite.expect(wrong.isEmpty, "Kopia's error texts are classified by cause: \(wrong.map(\.0))")
        suite.expect(!ForkMacBackupFailureCause.cloudOnly.countsAsError(iCloud: .local)
                        && ForkMacBackupFailureCause.cloudOnly.countsAsError(iCloud: .materialize)
                        && ForkMacBackupFailureCause.permission.countsAsError(iCloud: .local),
                     "a cloud-only file does not make a snapshot partial unless iCloud is downloaded first")
        let text = ForkMacBackupStrings.strings(.fr)
        suite.expect(ForkMacBackupFailureCause.vanished.remedy(text) == nil
                        && ForkMacBackupFailureCause.allCases.filter { $0 != .vanished }.allSatisfy { $0.remedy(text) != nil }
                        && ForkMacBackupRunFailure.allCases.allSatisfy { !$0.remedy(text).isEmpty },
                     "every cause has its remedy, but a file deleted meanwhile")
        suite.expect(ForkMacBackupEngineError.wrongRepository(found: "x").runFailure == .wrongRepository
                        && ForkMacBackupEngineError.timeout.runFailure == .chainBroken
                        && ForkMacBackupEngineError.serverUnavailable.runFailure == .engineStopped,
                     "an engine error names the run's failure")
    }

    // MARK: Proofs

    private static func proofs(_ suite: TestSuite) {
        let levels = ForkMacBackupProofLevel.allCases
        suite.expect(levels == levels.sorted() && ForkMacBackupProofLevel.present < .complete
                        && ForkMacBackupProofLevel.complete < .contentVerified
                        && ForkMacBackupProofLevel.contentVerified < .restoreTested,
                     "proof levels order: present < complete < content verified < restore tested")
        suite.expect(ForkMacBackupVerifyLevel.contentSample(percent: 1).proofLevel == .contentVerified
                        && ForkMacBackupVerifyLevel.restoreTest(files: 50).proofLevel == .restoreTested
                        && ForkMacBackupVerifyLevel.references.proofLevel == .present,
                     "a verification raises the proof only as far as it reads")
    }

    // MARK: Kopia contracts (inline)

    private static func contracts(_ suite: TestSuite) {
        let manifest = json(ForkMacBackupKopia.SnapshotManifest.self, """
        {"id":"k1","source":{"host":"m","userName":"u","path":"/Users/u"},"startTime":"2026-10-22T08:00:00.123456789Z",
         "endTime":"2026-10-22T08:04:00Z","stats":{"totalSize":"1200","fileCount":3,"errorCount":1,"newField":true},
         "rootEntry":{"name":"u","type":"d","obj":"kroot","summ":{"size":1200,"files":3,"numFailed":1,
           "errors":[{"path":"Library/Mobile Documents/a","error":"resource deadlock avoided"}]}},
         "tags":{"tag:x":"y"},"somethingNew":{"deep":[1,2]}}
        """)
        suite.expect(manifest?.stats?.totalSize == 1200 && manifest?.tags["tag:x"] == "y"
                        && manifest?.rootEntry?.obj == "kroot" && manifest?.incomplete == nil,
                     "a manifest reads with unknown fields and a number written as text")
        let fraction = manifest?.startDate.map { $0.timeIntervalSince1970.truncatingRemainder(dividingBy: 1) } ?? 0
        suite.expect(abs(fraction - 0.123456789) < 0.000_01 && manifest?.endDate != nil
                        && ForkMacBackupKopia.date("0001-01-01T00:00:00Z") == nil
                        && ForkMacBackupKopia.date("2026-10-22T16:34:02.728836+02:00").map {
                            Int($0.timeIntervalSince1970)
                        } == ForkMacBackupKopia.date("2026-10-22T14:34:02Z").map { Int($0.timeIntervalSince1970) },
                     "Kopia's dates read with nanoseconds and offsets; Go's zero time is no date")
        let minimal = json(ForkMacBackupKopia.SnapshotManifest.self, #"{"id":"k2"}"#)
        suite.expect(minimal?.id == "k2" && minimal?.stats == nil && minimal?.rootEntry == nil && minimal?.pins == [],
                     "a manifest with every optional field missing still reads")
        if let manifest {
            let local = ForkMacBackupSnapshotProof(manifest: manifest, iCloud: .local)
            let downloaded = ForkMacBackupSnapshotProof(manifest: manifest, iCloud: .materialize)
            suite.expect(local.level == .complete && local.cloudOnly == ["Library/Mobile Documents/a"] && !local.isPartial
                            && downloaded.level == .present && downloaded.failures.count == 1 && downloaded.bytes == 1200,
                         "a cloud-only file is listed apart in local mode and is an error once iCloud is downloaded")
        }
        let noisy = "2026-10-22 ERROR snapshot had errors\n" + #"{"id":"k3","rootEntry":{"summ":{"numFailed":12,"errors":[{"path":"a","error":"permission denied"}]}}}"#
        if let partial = ForkMacBackupKopia.decode(ForkMacBackupKopia.SnapshotManifest.self, from: Data(noisy.utf8)) {
            let proof = ForkMacBackupSnapshotProof(manifest: partial, iCloud: .local)
            suite.expect(proof.level == .present && proof.failures.map(\.cause) == [.permission]
                            && proof.unnamedFailureCount == 11 && proof.failureCount == 12,
                         "an exit-1 output with a log line before its JSON still gives a partial, every failure counted")
        } else {
            suite.expect(false, "an exit-1 output with a log line before its JSON still decodes")
        }
        let sources = json(ForkMacBackupKopia.SourcesResponse.self, """
        {"localHost":"m","sources":[{"source":{"path":"/Users/u"},"status":"UPLOADING","currentTask":"7",
          "upload":{"hashedBytes":100,"cachedBytes":"50","estimatedBytes":0,"hashedFiles":2,"directory":"Documents"}}],
         "multiUser":true}
        """)
        let upload = sources?.source(path: "/Users/u")?.upload
        suite.expect(sources?.source(path: "/Users/u")?.isUploading == true && upload?.bytesDone == 150
                        && upload?.estimate == nil && upload?.directory == "Documents",
                     "the live counters read; an estimate of zero is no estimate")
        let task = json(ForkMacBackupKopia.TaskInfo.self, """
        {"id":"9","kind":"Restore","status":"FAILED","errorMessage":"boom","counters":{"Restored Files":{"value":3}}}
        """)
        suite.expect(task?.isFinished == true && task?.knownStatus == .failed && task?.counter("Restored Files") == 3
                        && task?.counter("missing") == nil,
                     "a task reads its status and counters")
        let status = json(ForkMacBackupKopia.RepositoryStatus.self, """
        {"uniqueIDHex":"abc","clientOptions":{"hostname":"h","username":"u"},"storage":{"type":"s3","config":{"bucket":"b","doNotUseTLS":true}}}
        """)
        suite.expect(status?.identity?.description == "u@h" && status?.storage?.config["bucket"]?.string == "b"
                        && status?.storage?.config["doNotUseTLS"] == .bool(true) && status?.clientOptions?.readonly == false,
                     "the repository status gives the unique ID, the identity and the storage")
        let folder = json(ForkMacBackupKopia.DirectoryManifest.self, """
        {"stream":"kopia:directory","entries":[{"name":"a.txt","type":"f","mode":420,"mtime":"2026-10-22T08:00:00Z","size":"12","obj":"k9"},
          {"name":"docs","type":"d","obj":"k8","summ":{"size":40,"files":2}}]}
        """)
        suite.expect(folder?.entries.count == 2 && folder?.entries[0].mode == "420" && folder?.entries[0].totalSize == 12
                        && folder?.entries[1].isDirectory == true && folder?.entries[1].totalSize == 40,
                     "a folder's entries read, a folder's size is its summary's")
        suite.expect(ForkMacBackupKopia.decode(ForkMacBackupKopia.SnapshotManifest.self, from: Data("no json".utf8)) == nil,
                     "text without JSON decodes to nothing")
    }

    // MARK: Kopia contracts (real v0.23.1 output, from the bench)

    private static func fixtures(_ suite: TestSuite) {
        guard let complete = fixture("snapshot-create-complete.json"),
              let partial = fixture("snapshot-create-partial.json"),
              let many = fixture("snapshot-create-partial-many.json"),
              let canceled = fixture("snapshot-list-canceled.json"),
              let status = fixture("repository-status.json"),
              let uploading = fixture("control-sources-uploading.json"),
              let paused = fixture("control-sources-paused.json"),
              let folder = fixture("objects-directory.json"),
              let task = fixture("task-estimate.json") else {
            suite.expect(false, "the Kopia fixtures are in Tests/Fork/Fixtures/MacBackup")
            return
        }
        let completeProof = ForkMacBackupKopia.decode(ForkMacBackupKopia.SnapshotManifest.self, from: complete)
            .map { ForkMacBackupSnapshotProof(manifest: $0, iCloud: .local) }
        suite.expect(completeProof?.level == .complete && completeProof?.failures.isEmpty == true,
                     "a real complete snapshot proves complete")
        let partialProof = ForkMacBackupKopia.decode(ForkMacBackupKopia.SnapshotManifest.self, from: partial)
            .map { ForkMacBackupSnapshotProof(manifest: $0, iCloud: .local) }
        suite.expect(partialProof?.level == .present && partialProof?.failures.map(\.cause) == [.permission]
                        && partialProof?.failures.first?.path == "unreadable/mode000.txt",
                     "a real partial snapshot names its unreadable file and why")
        let manyProof = ForkMacBackupKopia.decode(ForkMacBackupKopia.SnapshotManifest.self, from: many)
            .map { ForkMacBackupSnapshotProof(manifest: $0, iCloud: .local) }
        suite.expect((manyProof?.failureCount ?? 0) >= 15 && manyProof?.failures.allSatisfy { $0.cause == .permission } == true,
                     "a real snapshot with many errors counts them all")
        let list = ForkMacBackupKopia.decode([ForkMacBackupKopia.SnapshotManifest].self, from: canceled)
        let canceledProof = list?.first.map { ForkMacBackupSnapshotProof(manifest: $0, iCloud: .local) }
        suite.expect(list?.count == 1 && canceledProof?.incomplete == "canceled" && canceledProof?.level == .present,
                     "a real canceled snapshot is present, never complete")
        let repository = ForkMacBackupKopia.decode(ForkMacBackupKopia.RepositoryStatus.self, from: status)
        suite.expect(repository?.uniqueIDHex?.count == 64 && repository?.identity?.description == "bench@bench-mac"
                        && repository?.storage?.type == "s3" && repository?.storage?.config["bucket"]?.string == "kopia-bench",
                     "the real repository status reads")
        let live = ForkMacBackupKopia.decode(ForkMacBackupKopia.SourcesResponse.self, from: uploading)
        let running = live?.sources.first { $0.isUploading }
        suite.expect((live?.sources.count ?? 0) >= 2 && running?.upload != nil && running?.currentTask != nil,
                     "the real control sources read, with the live counters of the source uploading")
        let pausedSources = ForkMacBackupKopia.decode(ForkMacBackupKopia.SourcesResponse.self, from: paused)
        suite.expect(pausedSources?.sources.contains { $0.status == "PAUSED" } == true, "a real paused source reads")
        let directory = ForkMacBackupKopia.decode(ForkMacBackupKopia.DirectoryManifest.self, from: folder)
        suite.expect(directory?.stream == "kopia:directory" && directory?.entries.isEmpty == false
                        && directory?.entries.allSatisfy { $0.obj != nil && $0.modified != nil } == true,
                     "a real folder of a snapshot reads with its object IDs and dates")
        let estimate = ForkMacBackupKopia.decode(ForkMacBackupKopia.TaskInfo.self, from: task)
        suite.expect(estimate?.knownStatus == .success && estimate?.counter("Files") == 3001
                        && ForkMacBackupKopia.date(estimate?.startTime) != nil,
                     "a real task reads its counters and its offset dates")
    }

    // MARK: Presentation

    private static func presentation(_ suite: TestSuite) {
        let scanning = ForkMacBackupPresentation.preview(.scanning, now: now)
        let running = ForkMacBackupPresentation.preview(.running42, now: now)
        suite.expect(scanning.fraction == nil && running.fraction.map { abs($0 - 0.42) < 0.001 } == true,
                     "no percentage while scanning, 42 % while uploading")
        var noEstimate = running
        noEstimate.progress?.bytesTotal = nil
        var verifying = ForkMacBackupPresentation.preview(.verifying, now: now)
        suite.expect(noEstimate.fraction == nil && verifying.fraction == nil,
                     "no estimate, no percentage: never a fake one")
        verifying.progress = .init(bytesDone: 5, bytesTotal: 10)
        suite.expect(verifying.fraction == 0.5, "a verification with a byte count shows its share")
        let tones = Dictionary(uniqueKeysWithValues: ForkMacBackupPresentation.Scenario.allCases.map {
            ($0, ForkMacBackupPresentation.preview($0, now: now).tone)
        })
        suite.expect(tones[.protected] == .teal && tones[.running42] == .teal && tones[.waitingPower] == .calm
                        && tones[.paused] == .calm && tones[.partial] == .orange && tones[.failedChainBroken] == .red
                        && tones[.notConfigured] == .calm,
                     "each state has its colour: \(tones)")
        let closed = ForkMacBackupPresentation.Scenario.allCases.filter {
            ForkMacBackupPresentation.preview($0, now: now).phase.showsInClosedIsland
        }
        suite.expect(Set(closed) == [.running42, .scanning, .restoring, .verifying],
                     "the closed island shows only a backup, a restore or a verification running (decision 2)")
        var two = ForkMacBackupPresentation.preview(.protected, now: now)
        let old = ForkMacBackupPresentation.SnapshotSummary(manifestID: "k0", date: now.addingTimeInterval(-86_400),
                                                           level: .complete)
        two.sources.append(.init(path: "/Volumes/Photos", state: .done, last: old, lastComplete: old))
        suite.expect(two.protectedSince == old.date && two.lastBackup?.manifestID == "k5f3a9c2e1",
                     "the age protected is the oldest source's, the last backup the newest")
        two.sources.append(.init(path: "/Volumes/New"))
        suite.expect(two.protectedSince == nil, "a source never backed up means nothing is fully protected yet")
        suite.expect(ForkMacBackupPresentation.Scenario.allCases.allSatisfy {
            roundTrips(ForkMacBackupPresentation.preview($0, now: now))
        }, "every preview state survives the state file's JSON")
        suite.expect(ForkMacBackupPresentation.displayTime("21:05", locale: locale("en_US", twelveHour: true))
                        .contains("9:05")
                        && ForkMacBackupPresentation.displayTime("21:05", locale: locale("fr_FR", twelveHour: false))
                        .contains("21:05")
                        && ForkMacBackupPresentation.displayTime("nope", locale: .current) == "nope",
                     "fixed times are stored in 24-hour and shown in the person's clock")
    }

    // MARK: State file and commands

    private static func ipc(_ suite: TestSuite) {
        let state = ForkMacBackupStateFile(presentation: .preview(.running42, now: now), writtenAt: now, agentPID: 42,
                                           agentBuild: "2300")
        suite.expect(state.encoded().flatMap(ForkMacBackupStateFile.decode) == state,
                     "the state file reads back what the agent wrote")
        var future = state
        future.formatVersion = ForkMacBackupStateFile.formatVersion + 1
        suite.expect((try? ForkMacBackupJSON.encoder.encode(future)).flatMap(ForkMacBackupStateFile.decode) == nil
                        && ForkMacBackupStateFile.decode(Data("{}".utf8)) == nil,
                     "a newer agent's state or a broken one is ignored, never misread")
        let commands: [ForkMacBackupCommand] = [.backUpNow, .pause(until: now), .pause(until: nil), .resume,
                                                .slowDown(true), .verify(.restoreTest(files: 50)), .verify(.full),
                                                .cancel, .reloadSettings]
        suite.expect(commands.allSatisfy { command in
            let file = ForkMacBackupCommandFile(command: command, origin: .island, issuedAt: now)
            return file.encoded().flatMap(ForkMacBackupCommandFile.decode) == file
        }, "every command survives its file")
        let file = ForkMacBackupCommandFile(command: .backUpNow, origin: .commandBar, issuedAt: now)
        suite.expect(file.isFresh(now: now.addingTimeInterval(60)) && !file.isFresh(now: now.addingTimeInterval(3_600))
                        && file.fileName == file.id.uuidString + ".json",
                     "a command older than ten minutes is dropped, not replayed")
        let names = ForkMacBackupNotify(bundleID: "com.example.app")
        suite.expect(names.state == "com.example.app.macbackup.state" && names.command == "com.example.app.macbackup.command"
                        && names.settings == "com.example.app.macbackup.settings"
                        && ForkMacBackupNotify(bundleID: "com.example.app.dev").state != names.state,
                     "notification names derive from the bundle id, so two builds never hear each other")
        suite.expect(ForkMacBackupSecretKind.repositoryPassword.account(repositoryKey: "s3-1") == "repo-password#s3-1"
                        && ForkMacBackupSecretKind.service(bundleID: "a.b") == "a.b.macbackup",
                     "Keychain accounts name the secret and its repository")
    }

    // MARK: Paths

    private static func paths(_ suite: TestSuite) {
        let root = URL(fileURLWithPath: "/tmp/mb-test/MacBackup", isDirectory: true)
        let paths = ForkMacBackupPaths(root: root)
        suite.expect(ForkMacBackupPaths(container: URL(fileURLWithPath: "/tmp/mb-test", isDirectory: true)) == paths
                        && ForkMacBackupPaths(container: nil) == nil,
                     "the root is injected: <container>/MacBackup, nothing without a container")
        let repo = paths.repository("s3-abc")
        suite.expect(paths.state.path == "/tmp/mb-test/MacBackup/state.json"
                        && paths.engineBinary(version: "0.23.1").path == "/tmp/mb-test/MacBackup/engine/kopia-0.23.1/kopia"
                        && repo.config.path == "/tmp/mb-test/MacBackup/repo/s3-abc/repository.config"
                        && repo.cache.lastPathComponent == "cache" && repo.logs.lastPathComponent == "logs"
                        && paths.kopiaSocket.path == "/tmp/mb-test/MacBackup/run/kopia.sock"
                        && paths.agentLock.lastPathComponent == "agent.lock"
                        && paths.serverInfo.lastPathComponent == "server.json"
                        && [paths.runs, paths.slots, paths.capacity].map(\.lastPathComponent)
                            == ["runs.jsonl", "slots.jsonl", "capacity.jsonl"]
                        && paths.proofs.lastPathComponent == "proofs.json" && paths.pending.lastPathComponent == "pending.json"
                        && paths.preview.lastPathComponent == "preview",
                     "every file of the plan has its place under the root")
        suite.expect(paths.errorsFile(manifestID: "../../etc/k1").lastPathComponent == "etck1.json"
                        && paths.errorsFile(manifestID: "/").lastPathComponent == "unknown.json",
                     "a manifest ID never escapes the errors folder")
        let long = ForkMacBackupPaths(root: URL(fileURLWithPath: "/" + String(repeating: "x", count: 120)))
        suite.expect(paths.socketPathFits && !long.socketPathFits
                        && ForkMacBackupPaths.shortSocket(uid: 501).path == "/tmp/swishsaint-501/kopia.sock",
                     "a socket path too long for sun_path is detected, with a short fallback")
        let command = ForkMacBackupCommandFile(command: .resume, origin: .settings)
        suite.expect(paths.commandFile(command).deletingLastPathComponent() == paths.commands,
                     "command files go in commands/")
    }

    // MARK: Defaults

    private static func defaults(_ suite: TestSuite) {
        let registered = ForkMacBackupDefaults.registered
        suite.expect(registered.keys.allSatisfy { $0.hasPrefix("fork.macbackup.") }
                        && registered.values.allSatisfy { $0 is Bool || $0 is Int || $0 is String },
                     "every Mac Backup setting is fork.macbackup.*, Bool, Int or String (the import ignores the rest)")
        suite.expect(registered.allSatisfy { key, value in ForkDefaults.registered[key].map { "\($0)" } == "\(value)" },
                     "every Mac Backup setting is registered with the fork's")
        suite.expect(ForkMacBackupDefaults.machineKeys.allSatisfy {
            registered[$0] == nil && !ForkDefaults.backupKeys.contains($0) && $0.hasPrefix("fork.macbackup.")
        }, "the repository, sources, profile, engine and kit dates stay on this Mac")
        suite.expect(registered[ForkDefaultsKey.macBackupEnabled] as? Bool == false
                        && registered[ForkDefaultsKey.macBackupScheduleMode] as? String == "auto"
                        && registered[ForkDefaultsKey.macBackupIslandCompact] as? String == "running"
                        && registered[ForkDefaultsKey.macBackupICloudMode] as? String == "local"
                        && registered[ForkDefaultsKey.macBackupMeetingMode] as? String == "slow",
                     "off by default; once on: Automatic rhythm, closed island only while running, iCloud local files")
        let notices = ForkMacBackupNoticeEvent.allCases.map { (event: ForkMacBackupNoticeEvent) -> (ForkMacBackupNoticeEvent, Bool?) in
            (event, registered[ForkDefaultsKey.macBackupNotice(event)] as? Bool)
        }
        suite.expect(notices.allSatisfy { $0.1 == ($0.0 == .complete || $0.0 == .restoreDone) },
                     "only the end-of-backup notice and the restore's card are on by default (decision 3)")
        suite.expect(!registered.keys.contains { $0.contains(".notify.") || $0.hasSuffix("lateHours") }
                        && registered.keys.filter { $0.hasPrefix("fork.macbackup.notice.") }.count == 4,
                     "no late, chain, space, verification or kit notification key is left")
        suite.expect(!registered.keys.contains { $0.contains("lock") || $0.contains("menuBar") || $0.contains("secondCopy") }
                        && ForkMacBackupCompactSetting.allCases == [.running, .never],
                     "no lock screen, menu bar or second copy setting, and no « problems » choice for the closed island")
        suite.expect(ForkMacBackupPreset.parse(registered[ForkDefaultsKey.macBackupPresets] as? String ?? "")
                        == ForkMacBackupPreset.defaultApplied
                        && ForkMacBackupRetention.parse(registered[ForkDefaultsKey.macBackupRetentionCustom] as? String ?? "")
                        == .balanced,
                     "the presets and retention defaults read back as their models")
    }

    // MARK: Formatting

    private static func formatting(_ suite: TestSuite) {
        let fr = locale("fr_FR", twelveHour: false)
        let us = locale("en_US", twelveHour: true)
        suite.expect(ForkMacBackupFormat.bytes(1_300_000_000, locale: fr).hasSuffix("Go")
                        && ForkMacBackupFormat.bytes(1_300_000_000, locale: us) == "1.3 GB"
                        && ForkMacBackupFormat.bytes(-5, locale: us) == ForkMacBackupFormat.bytes(0, locale: us),
                     "sizes read as the Finder writes them, never negative")
        suite.expect(ForkMacBackupFormat.rate(18_000_000, locale: us) == "18 MB/s"
                        && ForkMacBackupFormat.rate(nil, locale: us) == nil
                        && ForkMacBackupFormat.rate(.nan, locale: us) == nil,
                     "a rate needs a real number")
        let evening = Date(timeIntervalSince1970: 1_792_699_440) // 22/10/2026 20:04 UTC
        let utc = TimeZone(identifier: "UTC")!
        let twelve = ForkMacBackupFormat.time(evening, locale: us, timeZone: utc)
        let twentyFour = ForkMacBackupFormat.time(evening, locale: fr, timeZone: utc)
        suite.expect(twelve.contains("8:04") && twelve.contains("PM") && twentyFour.contains("20:04"),
                     "times follow the locale's own clock, 12- or 24-hour: \(twelve) / \(twentyFour)")
        let duration = ForkMacBackupFormat.duration(7_500, locale: us)
        suite.expect(duration.contains("2") && duration.contains("5") && !duration.contains("s")
                        && ForkMacBackupFormat.duration(20, locale: us).hasPrefix("< ")
                        && ForkMacBackupFormat.duration(3 * 86_400, locale: us).contains("3"),
                     "durations keep two units at most, nothing under a minute: \(duration)")
        suite.expect(ForkMacBackupFormat.age(7_200, locale: fr).hasPrefix("2")
                        && ForkMacBackupFormat.age(7_200, locale: fr).contains("h")
                        && ForkMacBackupFormat.age(5, locale: us).hasPrefix("1")
                        && ForkMacBackupFormat.age(3 * 86_400, locale: us).hasPrefix("3"),
                     "an age keeps its largest unit: \(ForkMacBackupFormat.age(7_200, locale: fr))")
        let ago = ForkMacBackupFormat.relative(now.addingTimeInterval(-7_200), now: now, locale: fr)
        suite.expect(ago.contains("2") && ago.lowercased().contains("il y a"), "relative ages read « il y a 2 h »: \(ago)")
        suite.expect(ForkMacBackupFormat.percent(0.42, locale: us) == "42%"
                        && ForkMacBackupFormat.percent(3, locale: us) == "100%",
                     "percentages are clamped")
        let path = ForkMacBackupFormat.middleTruncated("/Users/t/Documents/Castral/closing/pronic.com/devis.pdf",
                                                       limit: 30, home: "/Users/t")
        suite.expect(path.count == 30 && path.hasPrefix("~/Documents") && path.hasSuffix("devis.pdf") && path.contains("…"),
                     "a long path loses its middle, keeps both ends: \(path)")
    }

    // MARK: Strings

    private static let longLabels: Set<String> = [
        "featureTitle", "fixChain", "fixWrongRepository", "fixAuthentication", "fixEngine", "fixDiskAccess", "fixSpace",
        "fixRetry", "lastBackup", "lastComplete", "never", "rhythmAuto", "rhythmAbout", "rhythmEvery", "rhythmTimes",
        "protectedSize", "sentSize", "repositorySize", "freeSpace", "unknown", "costLine",
    ]
    private static let sameEverywhere: Set<String> = ["nodeTailscale", "nodeProxmox", "nodeNAS", "nodeS3", "nodeCloud",
                                                      "pause"]
    private static let oneForms: Set<String> = ["partialOne", "pendingOne"]

    private static func fields(_ strings: ForkMacBackupStrings) -> [(String, String)] {
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
        suite.expect(AppLanguage.allCases.count == 15 && english.count > 100, "fifteen languages, every shared word")
        var empty: [String] = []
        var untranslated: [String] = []
        var wrongPlaceholders: [String] = []
        var tooLong: [String] = []
        for language in AppLanguage.allCases {
            for (label, value) in fields(.strings(language)) {
                let tag = "\(language.rawValue).\(label)"
                if value.trimmingCharacters(in: .whitespaces).isEmpty { empty.append(tag) }
                if language != .enUS, value == english[label], !sameEverywhere.contains(label) { untranslated.append(tag) }
                let expected = placeholders(english[label] ?? "")
                let actual = placeholders(value)
                if actual != expected, !(oneForms.contains(label) && actual == ["%d"]) { wrongPlaceholders.append(tag) }
                let filled = value.replacingOccurrences(of: "%@", with: "10:04 PM").replacingOccurrences(of: "%d", with: "999")
                if !longLabels.contains(label), filled.count > 28 { tooLong.append("\(tag): \(filled)") }
            }
        }
        suite.expect(empty.isEmpty, "every Mac Backup word exists in every language: \(empty)")
        suite.expect(untranslated.isEmpty, "every word is really translated: \(untranslated)")
        suite.expect(wrongPlaceholders.isEmpty, "every translation keeps its placeholders: \(wrongPlaceholders)")
        suite.expect(tooLong.isEmpty, "every island word fits in 28 characters: \(tooLong)")
        suite.expect(Set(AppLanguage.allCases.map { ForkMacBackupStrings.strings($0).fixChain }).count >= 14,
                     "each language has its own sentences (Taiwan's and Hong Kong's Chinese may share one)")

        var typography: [String] = []
        for (label, value) in fields(.fr) {
            let scalars = Array(value.unicodeScalars)
            for (index, scalar) in scalars.enumerated() where ":;!?".unicodeScalars.contains(scalar) {
                if index == 0 || scalars[index - 1] != "\u{00A0}" { typography.append(label) }
            }
            if value.contains("'") || value.contains("« ") || value.contains(" »") { typography.append(label) }
        }
        suite.expect(typography.isEmpty, "French: no-break space before : ; ! ?, typographic apostrophes: \(typography)")

        let text = ForkMacBackupStrings.strings(.ru)
        suite.expect(text.partial(21, language: .ru).contains("21") && text.partial(21, language: .ru) != text.partial(25, language: .ru)
                        && text.partial(22, language: .ru) != text.partial(25, language: .ru)
                        && text.partial(12, language: .ru) == text.partial(25, language: .ru).replacingOccurrences(of: "25", with: "12"),
                     "Russian agrees 21, 22 and 25 files each their own way, 12 like 25")
        let sk = ForkMacBackupStrings.strings(.sk)
        let en = ForkMacBackupStrings.strings(.enUS)
        suite.expect(sk.pending(3, language: .sk) != sk.pending(5, language: .sk).replacingOccurrences(of: "5", with: "3")
                        && en.partial(1, language: .enUS) == "Partial · 1 file" && en.partial(3, language: .enUS) == "Partial · 3 files"
                        && !en.pending(0, language: .enUS).contains("%d"),
                     "Slovak has a form for two to four; English one and many")
    }

    /// Every state's headline, in every language, fits the island.
    private static func headlines(_ suite: TestSuite) {
        var tooLong: [String] = []
        var untranslatedTitles: [String] = []
        for language in AppLanguage.allCases {
            let text = ForkMacBackupStrings.strings(language)
            let locale = locale(language.rawValue, twelveHour: true)
            for scenario in ForkMacBackupPresentation.Scenario.allCases {
                let state = ForkMacBackupPresentation.preview(scenario, now: now)
                for reading in ForkMacBackupReading.allCases {
                    let line = state.headline(text, language: language, locale: locale, now: now, reading: reading)
                    if line.count > 28 || line.isEmpty { tooLong.append("\(language.rawValue).\(scenario): \(line)") }
                }
            }
            let titled = ForkMacBackupWaitReason.allCases.map { $0.title(text) }
                + ForkMacBackupRunFailure.allCases.map { $0.title(text) }
                + ForkMacBackupChainNode.Kind.allCases.map { $0.title(text) }
                + ForkMacBackupProofLevel.allCases.map { $0.title(text) }
                + ForkMacBackupFailureCause.allCases.map { $0.title(text) }
            if titled.contains(where: \.isEmpty) { untranslatedTitles.append(language.rawValue) }
        }
        suite.expect(tooLong.isEmpty, "every headline fits the island in every language: \(tooLong)")
        suite.expect(untranslatedTitles.isEmpty, "every reason, failure, node, proof and cause has its word")
        let text = ForkMacBackupStrings.strings(.fr)
        let fr = locale("fr_FR", twelveHour: false)
        let protected = ForkMacBackupPresentation.preview(.protected, now: now)
        suite.expect(protected.headline(text, language: .fr, locale: fr, now: now) == "Protégé il y a 2\u{00A0}h"
                        || protected.headline(text, language: .fr, locale: fr, now: now).hasPrefix("Protégé il y a 2"),
                     "at rest the island says how old the protection is")
        suite.expect(ForkMacBackupPresentation.preview(.scanning, now: now).headline(text, language: .fr, locale: fr, now: now)
                        == "Analyse…"
                        && ForkMacBackupPresentation.preview(.running42, now: now)
                        .compactValue(text, locale: fr, reading: .remaining).contains("2")
                        && ForkMacBackupPresentation.preview(.scanning, now: now)
                        .compactValue(text, locale: fr, reading: .percent) == text.calculating,
                     "while scanning the island says so, never a number")
        let line = ForkMacBackupPresentation.preview(.running42, now: now).progressLine(text, locale: fr) ?? ""
        suite.expect(line.contains("/") && line.contains("/s") && line.contains("reste"),
                     "the progress line gives done / total, the rate and the time left: \(line)")
        suite.expect(ForkMacBackupPresentation.preview(.protected, now: now).rhythmLine(text, locale: fr).hasPrefix("Automatique")
                        && ForkMacBackupPresentation.preview(.protected, now: now).costLine(text, locale: fr) != nil,
                     "the rhythm and the cost read in words")
    }

    private static func staleAgent(_ suite: TestSuite) {
        let next = Date(timeIntervalSince1970: 1_792_670_000)
        var running = ForkMacBackupPresentation(phase: .uploading, progress: .init(bytesDone: 5, bytesTotal: 10), nextRun: next,
                                                updatedAt: Date(timeIntervalSince1970: 1_792_663_440))
        suite.expect(running.settled(agentAlive: true) == running, "a live agent's state is shown as written")
        let settled = running.settled(agentAlive: false)
        suite.expect(settled.phase == .ready(next: next) && settled.progress == nil && !settled.phase.showsInClosedIsland,
                     "a dead agent's backup is over: the closed island shows nothing running")
        running.phase = .verifying
        suite.expect(running.settled(agentAlive: false).phase == .ready(next: next), "nor a verification")
        running.phase = .waiting(reason: .power, until: nil)
        suite.expect(running.settled(agentAlive: false) == running, "a wait or a result stays as written")
    }
}
