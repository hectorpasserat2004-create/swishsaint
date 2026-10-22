// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

#if VORSSAINT_DEVELOPMENT
import Foundation

/// A rich fake of the engine and of the agent's records, for the offscreen
/// renders and the Developer build's demo (`ForkMacBackupWindow.openDemo`):
/// a home folder backed up every six hours for thirty days, files that
/// change, appear and go, one partial snapshot, another Mac in the same
/// repository. Nothing here reads the Mac's disk or starts Kopia; a restore
/// writes small placeholder files where it is asked to.
final class ForkMacBackupDemoEngine: ForkMacBackupEngineDriving {
    struct File {
        var path: String
        var size: Int64
        /// The file changes every `editEvery` snapshots.
        var editEvery: Int?
        var addedAt: Int
        var removedAt: Int?
    }

    let now: Date
    let home: String
    let snapshotCount = 120
    let spacing: TimeInterval = 6 * 3_600
    let partialIndex = 113
    let localHost = "macbook-pro-de-martial"
    let localUser = "martial"
    let otherHost = "macbook-air-de-louis"
    let otherUser = "louis"
    /// Answers after this delay (0 in renders).
    var delay: TimeInterval = 0

    private(set) var files: [File]
    /// Deleted on the Mac since the last backup (⊘ in the browser).
    static let goneFromMac: Set<String> = ["Documents/Castral/closing/pronic.com/devis-pronic.pdf",
                                           "Documents/Budget 2026.numbers"]
    private let otherFiles: [File]

    init(now: Date, home: String = "/Users/martial") {
        self.now = now
        self.home = home
        let mb: Int64 = 1_000_000
        files = [
            File(path: "Documents/Castral/closing/pronic.com/devis-pronic.pdf", size: 412_000, editEvery: 40, addedAt: 0),
            File(path: "Documents/Castral/closing/pronic.com/contrat-signé.pdf", size: 1_840_000, addedAt: 30),
            File(path: "Documents/Castral/closing/pronic.com/notes.md", size: 3_200, editEvery: 9, addedAt: 0),
            File(path: "Documents/Castral/closing/vertbaudet/proposition.key", size: 48 * mb, editEvery: 25, addedAt: 10),
            File(path: "Documents/Castral/closing/vertbaudet/brief.pdf", size: 2_300_000, addedAt: 10),
            File(path: "Documents/Castral/contrats/cadre-2026.docx", size: 220_000, addedAt: 0),
            File(path: "Documents/Castral/contrats/avenant-1.docx", size: 96_000, addedAt: 70),
            File(path: "Documents/Castral/prospects.numbers", size: 1_200_000, editEvery: 12, addedAt: 0),
            File(path: "Documents/Factures/2026-08.pdf", size: 180_000, addedAt: 0),
            File(path: "Documents/Factures/2026-09.pdf", size: 176_000, addedAt: 0),
            File(path: "Documents/Factures/2026-10.pdf", size: 181_000, addedAt: 90),
            File(path: "Documents/notes.md", size: 12_400, editEvery: 6, addedAt: 0),
            File(path: "Documents/Budget 2026.numbers", size: 640_000, editEvery: 30, addedAt: 0),
            File(path: "Documents/brouillon lettre.pages", size: 380_000, addedAt: 0, removedAt: 100),
            File(path: "Desktop/Capture d’écran 2026-10-21 à 18.40.12.png", size: 2_100_000, addedAt: 110),
            File(path: "Desktop/à trier.txt", size: 1_400, editEvery: 4, addedAt: 0),
            File(path: "Pictures/Vacances Biarritz/IMG_0412.HEIC", size: 3_400_000, addedAt: 0),
            File(path: "Pictures/Vacances Biarritz/IMG_0413.HEIC", size: 3_100_000, addedAt: 0),
            File(path: "Pictures/Vacances Biarritz/IMG_0414.HEIC", size: 2_900_000, addedAt: 0),
            File(path: "Pictures/Vacances Biarritz/IMG_0415.MOV", size: 184 * mb, addedAt: 0),
            File(path: "Projets/swishsaint/README.md", size: 9_800, editEvery: 8, addedAt: 0),
            File(path: "Projets/swishsaint/build.sh", size: 41_000, editEvery: 15, addedAt: 0),
            File(path: "Projets/swishsaint/Sources/main.swift", size: 6_200, editEvery: 5, addedAt: 0),
            File(path: "Music/Playlists/Focus.m3u", size: 2_000, addedAt: 0),
            File(path: "Library/Application Support/Swishsaint/settings.plist", size: 14_000, editEvery: 3, addedAt: 0),
            File(path: "Library/Mail/V10/MailData/Envelope Index", size: 96 * mb, editEvery: 1, addedAt: 0),
        ]
        otherFiles = [
            File(path: "Cours/Économie/chapitre-3.pdf", size: 3_200_000, addedAt: 0),
            File(path: "Cours/Économie/notes.md", size: 8_000, editEvery: 4, addedAt: 0),
            File(path: "Oracle/serveur.txt", size: 2_000, addedAt: 10),
        ]
    }

    // MARK: Snapshots

    func date(of index: Int) -> Date {
        now.addingTimeInterval(-Double(snapshotCount - 1 - index) * spacing - 3_600)
    }

    func manifestID(_ index: Int, other: Bool = false) -> String {
        (other ? "o" : "k") + String(format: "%08x%02d", 0x5f3a_9c00 + index * 7_919, index % 97)
    }

    private func index(of manifestID: String) -> (Int, Bool)? {
        let other = manifestID.hasPrefix("o")
        let count = other ? snapshotCount / 4 : snapshotCount
        for index in 0..<count where self.manifestID(index, other: other) == manifestID { return (index, other) }
        return nil
    }

    private func pool(_ other: Bool) -> [File] { other ? otherFiles : files }

    private func present(_ file: File, at index: Int) -> Bool {
        index >= file.addedAt && (file.removedAt.map { index < $0 } ?? true)
    }

    /// The edit the file is at, in snapshot `index`.
    private func edition(_ file: File, at index: Int) -> Int {
        guard let every = file.editEvery else { return 0 }
        return (index - file.addedAt) / every
    }

    private func objectID(_ file: File, at index: Int) -> String {
        "I" + String(format: "%016llx", UInt64(truncatingIfNeeded: stableHash(file.path) &+ UInt64(edition(file, at: index))))
    }

    private func modified(_ file: File, at index: Int) -> Date {
        let first = file.addedAt + edition(file, at: index) * (file.editEvery ?? 0)
        return date(of: first).addingTimeInterval(-1_800)
    }

    private func size(_ file: File, at index: Int) -> Int64 {
        file.size + Int64(edition(file, at: index) * 1_337)
    }

    /// The Mac's own state now: the last snapshot's files, a few changed since.
    func localFacts(_ absolutePath: String) -> ForkMacBackupLocalStatus.LocalFacts? {
        guard let relative = ForkMacBackupFolderPath.relative(absolutePath, to: home) else { return nil }
        let last = snapshotCount - 1
        if relative.isEmpty { return .init(isDirectory: true, size: 0, modified: nil) }
        if let file = files.first(where: { $0.path == relative }) {
            guard present(file, at: snapshotCount), !Self.goneFromMac.contains(file.path) else { return nil }
            let changed = file.editEvery.map { $0 <= 9 } ?? false
            return .init(isDirectory: false, size: size(file, at: last) + (changed ? 120 : 0),
                         modified: changed ? now.addingTimeInterval(-1_200) : modified(file, at: last))
        }
        let isFolder = files.contains { $0.path.hasPrefix(relative + "/") && present($0, at: snapshotCount) }
        return isFolder ? .init(isDirectory: true, size: 0, modified: nil) : nil
    }

    private func entriesJSON(folder: String, index: Int, other: Bool) -> (entries: [[String: Any]], size: Int64, files: Int64) {
        let prefix = folder.isEmpty ? "" : folder + "/"
        var children: [String: [File]] = [:]
        var direct: [File] = []
        for file in pool(other) where present(file, at: index) && file.path.hasPrefix(prefix) {
            let rest = String(file.path.dropFirst(prefix.count))
            if let slash = rest.firstIndex(of: "/") {
                children[String(rest[..<slash]), default: []].append(file)
            } else {
                direct.append(file)
            }
        }
        var entries: [[String: Any]] = []
        var total: Int64 = 0
        var count: Int64 = 0
        for name in children.keys.sorted() {
            let path = prefix + name
            let content = children[name] ?? []
            let size = content.reduce(Int64(0)) { $0 + self.size($1, at: index) }
            var summary: [String: Any] = ["size": size, "files": content.count, "dirs": 1]
            if index == partialIndex, !other, path == "Library" || path == "Library/Mail" {
                summary["numFailed"] = 2
            }
            entries.append(["name": name, "type": "d", "mode": "0755",
                            "mtime": rfc(content.map { modified($0, at: index) }.max() ?? date(of: index)),
                            "obj": "d:\(other ? 1 : 0):\(index):\(path)", "summ": summary])
            total += size
            count += Int64(content.count)
        }
        for file in direct {
            entries.append(["name": (file.path as NSString).lastPathComponent, "type": "f", "mode": "0644",
                            "mtime": rfc(modified(file, at: index)), "size": size(file, at: index),
                            "obj": objectID(file, at: index)])
            total += size(file, at: index)
            count += 1
        }
        return (entries, total, count)
    }

    private func manifestJSON(_ index: Int, other: Bool) -> [String: Any] {
        let (_, size, count) = entriesJSON(folder: "", index: index, other: other)
        let start = date(of: other ? index * 4 + 2 : index)
        var summary: [String: Any] = ["size": size, "files": count, "dirs": 12]
        var stats: [String: Any] = ["totalSize": size, "fileCount": count, "dirCount": 12, "errorCount": 0]
        if index == partialIndex && !other {
            summary["numFailed"] = 2
            summary["errors"] = [
                ["path": "Library/Mail/V10/MailData/Envelope Index-wal",
                 "error": "unable to open file: open …/Envelope Index-wal: operation not permitted"],
                ["path": "Documents/Castral/closing/pronic.com/scan-contrat.pdf",
                 "error": "unable to read file: resource deadlock avoided"],
            ]
            stats["errorCount"] = 2
        }
        return [
            "id": manifestID(index, other: other),
            "source": ["host": other ? otherHost : localHost, "userName": other ? otherUser : localUser,
                       "path": other ? "/Users/louis/Documents" : home],
            "startTime": rfc(start), "endTime": rfc(start.addingTimeInterval(170 + Double(index % 7) * 23)),
            "stats": stats,
            "rootEntry": ["name": other ? "Documents" : (home as NSString).lastPathComponent, "type": "d",
                          "obj": "d:\(other ? 1 : 0):\(index):", "summ": summary],
        ]
    }

    // MARK: Engine

    private func answer<Value>(_ value: ForkMacBackupEngineResult<Value>,
                               _ completion: @escaping (ForkMacBackupEngineResult<Value>) -> Void) {
        if delay <= 0 {
            completion(value)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { completion(value) }
        }
    }

    func listSnapshots(source: ForkMacBackupSource?,
                       completion: @escaping (ForkMacBackupEngineResult<[ForkMacBackupKopia.SnapshotManifest]>) -> Void) {
        let raw = (0..<snapshotCount).map { manifestJSON($0, other: false) }
            + (0..<(snapshotCount / 4)).map { manifestJSON($0, other: true) }
        let data = (try? JSONSerialization.data(withJSONObject: raw)) ?? Data("[]".utf8)
        answer(.success(ForkMacBackupKopia.decode([ForkMacBackupKopia.SnapshotManifest].self, from: data) ?? []), completion)
    }

    func browse(objectID: String,
                completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupKopia.DirectoryManifest>) -> Void) {
        let parts = objectID.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "d", let index = Int(parts[2]) else {
            answer(.failure(.other("not a folder")), completion)
            return
        }
        let (entries, size, count) = entriesJSON(folder: String(parts[3]), index: index, other: parts[1] == "1")
        let raw: [String: Any] = ["stream": "kopia:directory", "entries": entries,
                                  "summary": ["size": size, "files": count]]
        let data = (try? JSONSerialization.data(withJSONObject: raw)) ?? Data()
        if let manifest = ForkMacBackupKopia.decode(ForkMacBackupKopia.DirectoryManifest.self, from: data) {
            answer(.success(manifest), completion)
        } else {
            answer(.failure(.decoding("demo")), completion)
        }
    }

    func versions(of relativePath: String, in source: ForkMacBackupSource,
                  completion: @escaping (ForkMacBackupEngineResult<[ForkMacBackupFileVersion]>) -> Void) {
        let other = source.path != home
        guard let file = pool(other).first(where: { $0.path == relativePath }) else {
            answer(.success([]), completion)
            return
        }
        let versions = (0..<snapshotCount).reversed().filter { present(file, at: $0) }.map { index in
            ForkMacBackupFileVersion(manifestID: manifestID(index), snapshotTime: date(of: index),
                                     objectID: objectID(file, at: index), size: size(file, at: index),
                                     modified: modified(file, at: index))
        }
        answer(.success(versions), completion)
    }

    func restore(_ request: ForkMacBackupRestoreRequest, progress: @escaping (ForkMacBackupRestoreProgress) -> Void,
                 completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupRestoreReport>) -> Void)
        -> ForkMacBackupCancellable {
        let handle = DemoHandle()
        let folder: String
        switch request.destination {
        case .folder(let path): folder = path
        case .original: folder = home
        }
        let total = Int64(request.items.count) * 2_000_000
        var step: Int64 = 0
        func tick() {
            guard !handle.canceled else {
                completion(.failure(.canceled))
                return
            }
            step += 1
            progress(ForkMacBackupRestoreProgress(bytesDone: min(total, step * total / 10), bytesTotal: total,
                                                  files: min(Int64(request.items.count), step), filesTotal: nil, errors: 0))
            if step < 10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { tick() }
                return
            }
            if case .folder = request.destination {
                for item in request.items where !item.isDirectory {
                    let url = URL(fileURLWithPath: folder).appendingPathComponent((item.relativePath as NSString).lastPathComponent)
                    try? Data("Demo: \(item.relativePath)\n".utf8).write(to: url)
                }
            }
            completion(.success(ForkMacBackupRestoreReport(files: Int64(request.items.count), bytes: total, failures: [],
                                                           destinationPath: folder)))
        }
        DispatchQueue.main.async { tick() }
        return handle
    }

    func connect(_ repository: ForkMacBackupRepository, credentials: ForkMacBackupCredentials, readOnly: Bool,
                 completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupKopia.RepositoryStatus>) -> Void) {
        answer(.failure(.other("demo")), completion)
    }

    func repositoryStatus(completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupKopia.RepositoryStatus>) -> Void) {
        answer(.failure(.other("demo")), completion)
    }

    func applyPolicy(_ rules: ForkMacBackupPolicyRules, to source: ForkMacBackupSource,
                     completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupPolicyRules>) -> Void) {
        answer(.success(rules), completion)
    }

    func readPolicy(of source: ForkMacBackupSource,
                    completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupPolicyRules>) -> Void) {
        answer(.failure(.other("demo")), completion)
    }

    func startSnapshot(_ source: ForkMacBackupSource, completion: @escaping (ForkMacBackupEngineResult<Void>) -> Void) {
        answer(.success(()), completion)
    }

    func progress(completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupKopia.SourcesResponse>) -> Void) {
        answer(.failure(.other("demo")), completion)
    }

    func cancelSnapshot(_ source: ForkMacBackupSource, completion: @escaping (ForkMacBackupEngineResult<Void>) -> Void) {
        answer(.success(()), completion)
    }

    func setThrottle(uploadBytesPerSecond: Int64?, completion: @escaping (ForkMacBackupEngineResult<Void>) -> Void) {
        answer(.success(()), completion)
    }

    func verify(_ level: ForkMacBackupVerifyLevel, progress: @escaping (ForkMacBackupVerifyProgress) -> Void,
                completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupVerifyReport>) -> Void)
        -> ForkMacBackupCancellable {
        answer(.failure(.other("demo")), completion)
        return DemoHandle()
    }

    func blobStats(completion: @escaping (ForkMacBackupEngineResult<ForkMacBackupBlobStats>) -> Void) {
        answer(.failure(.other("demo")), completion)
    }

    func maintenance(full: Bool, completion: @escaping (ForkMacBackupEngineResult<Void>) -> Void)
        -> ForkMacBackupCancellable {
        answer(.success(()), completion)
        return DemoHandle()
    }

    private final class DemoHandle: ForkMacBackupCancellable {
        var canceled = false
        func cancel() { canceled = true }
    }

    private func rfc(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    // MARK: Records

    /// The agent's records that go with these snapshots.
    func ledger(calendar: Calendar) -> ForkMacBackupWindowLedger {
        var ledger = ForkMacBackupWindowLedger()
        ledger.sources = [ForkMacBackupSource(path: home)]
        ledger.repository = ForkMacBackupRepository(
            kind: .s3, endpoint: .init(host: "minio.tailnet.ts.net", port: 9000, tls: true), bucket: "macs", region: "us-east-1",
            prefix: "martial/", clientIdentity: .init(userName: localUser, hostName: localHost), serverFlavor: .minio)
        ledger.profile = ForkMacBackupProfile(
            name: "Maison", repository: ledger.repository!,
            chain: [ForkMacBackupChainNode(id: "mac", kind: .mac),
                    ForkMacBackupChainNode(id: "tailscale", kind: .tailscale, detail: "tailnet"),
                    ForkMacBackupChainNode(id: "server", kind: .s3, title: "MinIO", detail: "minio.tailnet.ts.net:9000"),
                    ForkMacBackupChainNode(id: "proxmox", kind: .proxmox, detail: "LXC 111"),
                    ForkMacBackupChainNode(id: "nas", kind: .nas, title: "QNAP", detail: "TS-464")])
        ledger.engineVersion = "0.23.1"
        var runs: [ForkMacBackupRunRecord] = []
        var proofs: [String: ForkMacBackupSnapshotProof] = [:]
        for index in 0..<snapshotCount {
            let start = date(of: index)
            let level: ForkMacBackupProofLevel = index == partialIndex ? .present
                : index < snapshotCount - 30 && index % 8 == 0 ? .restoreTested
                : index < snapshotCount - 4 ? .contentVerified : .complete
            let (_, size, count) = entriesJSON(folder: "", index: index, other: false)
            var proof = ForkMacBackupSnapshotProof(manifestID: manifestID(index), sourcePath: home, startTime: start,
                                                   endTime: start.addingTimeInterval(170), level: level, bytes: size,
                                                   files: count)
            if level >= .contentVerified {
                proof.verifiedAt = start.addingTimeInterval(86_400)
                proof.verifiedPercent = 1
            }
            if level == .restoreTested { proof.restoreTestedAt = start.addingTimeInterval(2 * 86_400) }
            if index == partialIndex {
                proof.failures = [
                    ForkMacBackupFailure(path: "Library/Mail/V10/MailData/Envelope Index-wal",
                                         message: "unable to open file: operation not permitted"),
                    ForkMacBackupFailure(path: "Documents/Castral/closing/pronic.com/scan-contrat.pdf",
                                         message: "unable to read file: resource deadlock avoided"),
                    ForkMacBackupFailure(path: "Library/Containers/com.apple.Notes/Data/NoteStore.sqlite-wal",
                                         message: "unable to open file: resource busy"),
                ]
                proof.unnamedFailureCount = 4
            }
            proofs[proof.manifestID] = proof
            let onBattery = index % 5 == 2
            runs.append(ForkMacBackupRunRecord(
                kind: .backup, trigger: index % 9 == 4 ? .catchUp : (index % 13 == 6 ? .island : .scheduled),
                start: start, end: start.addingTimeInterval(170 + Double(index % 7) * 23),
                bytesSent: Int64(80_000_000 + (index % 11) * 41_000_000), bytesRead: size, cpuSeconds: 40,
                batteryDrop: onBattery ? 0.6 + Double(index % 3) * 0.3 : nil, onBattery: onBattery, proofs: [proof],
                outcome: index == partialIndex ? .partial : .complete))
        }
        runs.append(ForkMacBackupRunRecord(kind: .backup, trigger: .scheduled, start: now.addingTimeInterval(-3 * 86_400 - 7_200),
                                           end: now.addingTimeInterval(-3 * 86_400 - 7_000), outcome: .failed,
                                           failure: .chainBroken))
        runs.append(ForkMacBackupRunRecord(kind: .backup, trigger: .scheduled, start: now.addingTimeInterval(-5 * 86_400 - 900),
                                           end: now.addingTimeInterval(-5 * 86_400 - 300), bytesSent: 30_000_000,
                                           outcome: .canceled, stopReason: .meeting))
        for day in stride(from: 1, to: 30, by: 1) {
            let start = now.addingTimeInterval(-Double(day) * 86_400 + 4 * 3_600)
            let level: ForkMacBackupVerifyLevel = day % 7 == 3 ? .references : (day % 15 == 9 ? .restoreTest(files: 50)
                                                                                 : .contentSample(percent: 1))
            runs.append(ForkMacBackupRunRecord(kind: .verify, trigger: .scheduled, start: start,
                                               end: start.addingTimeInterval(day % 15 == 9 ? 610 : 95),
                                               outcome: day == 12 ? .failed : .complete,
                                               failure: day == 12 ? .chainBroken : nil, verifyLevel: level))
        }
        runs.append(ForkMacBackupRunRecord(kind: .maintenance, trigger: .agent, start: now.addingTimeInterval(-86_400 * 1.2),
                                           end: now.addingTimeInterval(-86_400 * 1.2 + 420), outcome: .complete))
        runs.append(ForkMacBackupRunRecord(kind: .restore, trigger: .window, start: now.addingTimeInterval(-86_400 * 2.4),
                                           end: now.addingTimeInterval(-86_400 * 2.4 + 12), bytesRead: 412_000,
                                           outcome: .complete))
        ledger.runs = runs.sorted { $0.start < $1.start }
        ledger.proofs = proofs

        // Slots every two hours, with the night's sleep, the train's
        // battery, the café's network, a meeting's pause.
        var slots: [ForkMacBackupSlotRecord] = []
        let today = calendar.startOfDay(for: now)
        for back in 0..<30 {
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
            for hour in stride(from: 0, to: 24, by: 2) {
                guard let due = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day), due <= now else { continue }
                let outcome: ForkMacBackupSlotRecord.Outcome
                let seed = (back * 12 + hour / 2) % 41
                if hour < 7 && back % 3 != 1 {
                    outcome = .missed(.asleep)
                } else if seed == 7 || seed == 29 {
                    outcome = .missed(.battery)
                } else if seed == 13 {
                    outcome = .missed(.network)
                } else if seed == 19 {
                    outcome = .missed(.meeting)
                } else if back == 3 && hour == 8 {
                    outcome = .failed
                } else if back == 0 && hour == 8 {
                    outcome = .partial
                } else if seed % 5 == 0 {
                    outcome = .nothingToDo
                } else {
                    outcome = .done
                }
                let late = hour == 8 && back % 3 != 1
                let started: Date?
                switch outcome {
                case .missed: started = nil
                default: started = due.addingTimeInterval(late ? 2_100 : 30)
                }
                slots.append(ForkMacBackupSlotRecord(due: due, outcome: outcome, startedAt: started))
            }
        }
        ledger.slots = slots.sorted { $0.due < $1.due }

        var capacity: [ForkMacBackupCapacitySample] = []
        for back in stride(from: 89, through: 0, by: -1) {
            let date = now.addingTimeInterval(-Double(back) * 86_400 - 6 * 3_600)
            let wave = sin(Double(back) / 6) * 2_000_000_000
            capacity.append(.init(kind: .real, bytes: Int64(412_000_000_000 - Double(back) * 300_000_000 + wave),
                                  date: date, source: "snapshot"))
            capacity.append(.init(kind: .physical, bytes: Int64(860_000_000_000 - Double(back) * 700_000_000),
                                  date: date, source: "blobStats"))
            capacity.append(.init(kind: .sent, bytes: Int64(1_200_000_000 + (back % 9) * 310_000_000),
                                  date: date, source: "run"))
            capacity.append(.init(kind: .nasFree, bytes: Int64(29_300_000_000_000 + Double(back) * 2_000_000_000),
                                  date: date, source: "qnap"))
        }
        ledger.capacity = capacity
        return ledger
    }
}

/// The fake records, handed as they are.
final class ForkMacBackupDemoLedger: ForkMacBackupWindowLedgerReading {
    let ledger: ForkMacBackupWindowLedger

    init(_ ledger: ForkMacBackupWindowLedger) {
        self.ledger = ledger
    }

    func load(completion: @escaping (ForkMacBackupWindowLedger) -> Void) { completion(ledger) }

    func failures(manifestID: String, completion: @escaping ([ForkMacBackupFailure]?) -> Void) {
        let proof = ledger.proofs[manifestID]
        guard let proof, proof.unnamedFailureCount > 0 else {
            completion(nil)
            return
        }
        let more = (1...proof.unnamedFailureCount).map {
            ForkMacBackupFailure(path: "Library/Mail/V10/MailData/Attachments/\($0)/pièce-jointe.pdf",
                                 message: "unable to open file: operation not permitted")
        }
        completion(proof.failures + more)
    }

    func append(_ run: ForkMacBackupRunRecord) {}
}
#endif
