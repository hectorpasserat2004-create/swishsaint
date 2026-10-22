// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Darwin
import Foundation

/// Suite `fork-macbackup-engine`: WP Engine's pure files
/// (`MacBackup/Engine/Pure/`), driven by real Kopia v0.23.1 outputs captured
/// on the bench (`Tests/Fork/Fixtures/MacBackup/engine-*`, paths anonymized).
enum ForkMacBackupEngineTests {
    static func run(_ suite: TestSuite) {
        manifest(suite)
        commands(suite)
        sizes(suite)
        blobStats(suite)
        restoreText(suite)
        verifyText(suite)
        serverText(suite)
        errors(suite)
        http(suite)
        policies(suite)
        retention(suite)
        conclusion(suite)
        failureLists(suite)
        restorePlan(suite)
        versions(suite)
        contentScan(suite)
        serverPlan(suite)
        extras(suite)
        datalessPolicy(suite)
        strings(suite)
    }

    /// The spawn policy of the cloud-only files: compiled, linked and
    /// toggled for real on this process (no file is read, nothing spawned).
    private static func datalessPolicy(_ suite: TestSuite) {
        let before = ForkMacBackupDatalessPolicy.current
        let off = ForkMacBackupDatalessPolicy.spawning(materialize: false) { ForkMacBackupDatalessPolicy.current }
        let on = ForkMacBackupDatalessPolicy.spawning(materialize: true) { ForkMacBackupDatalessPolicy.current }
        suite.expect(before >= 0 && off == ForkMacBackupDatalessPolicy.value(materialize: false)
                        && on == ForkMacBackupDatalessPolicy.value(materialize: true),
                     "a Kopia child is spawned with the iCloud policy asked, OFF unless « Tout télécharger avant »")
        suite.expect(ForkMacBackupDatalessPolicy.current == before, "and the process gets its own policy back")
        let invocation = ForkMacBackupKopiaInvocation(arguments: [], environment: [:], timeout: 1)
        suite.expect(!invocation.materializeDataless, "a CLI call never downloads cloud-only files")
    }

    // MARK: Helpers

    private static func fixture(_ name: String) -> Data? {
        try? Data(contentsOf: URL(fileURLWithPath: "Tests/Fork/Fixtures/MacBackup/\(name)"))
    }

    private static func text(_ name: String) -> String {
        fixture(name).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    private static func manifest(json: String) -> ForkMacBackupKopia.SnapshotManifest? {
        ForkMacBackupKopia.decode(ForkMacBackupKopia.SnapshotManifest.self, from: Data(json.utf8))
    }

    /// A deterministic generator (SplitMix64), for the sample picks.
    private struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private static let files = ForkMacBackupPaths(root: URL(fileURLWithPath: "/Users/test/Library/Application Support/x/MacBackup"))
        .repository("s3-0123456789abcdef")

    private static let repository = ForkMacBackupRepository(
        endpoint: .init(host: "minio.example.ts.net", port: 9000, tls: false), bucket: "mac-test", region: "us-east-1",
        prefix: "home/", accessKeyID: "kopia-test", clientIdentity: .init(userName: "test", hostName: "test-mac"))

    private static let credentials = ForkMacBackupCredentials(repositoryPassword: "repo-SECRET-pass",
                                                              accessKeyID: "AKIA-TEST", secretAccessKey: "s3-SECRET-key")

    // MARK: Manifest

    private static func manifest(_ suite: TestSuite) {
        typealias M = ForkMacBackupEngineManifest
        suite.expect(M.version == "0.23.1" && M.archiveSize == 15_257_600
                        && M.archiveSHA256 == "19e6ed637221f4dfd46a46e978ec4c509c386b522d746db2cd6762b217478111"
                        && M.url.absoluteString.hasSuffix("/v0.23.1/kopia-0.23.1-macOS-arm64.tar.gz"),
                     "the engine is pinned: Kopia 0.23.1, its archive's size and SHA-256")
        suite.expect(M.matchesVersionOutput("0.23.1 build: 72ec08fd8edb86c67ed27099bf1b955e1f308ffa from: kopia/kopia\n")
                        && !M.matchesVersionOutput("0.23.2 build: 72ec08fd8edb from: kopia/kopia")
                        && !M.matchesVersionOutput("0.23.1 build: deadbeef from: kopia/kopia")
                        && M.matchesVersionOutput("0.23.1") && !M.matchesVersionOutput(""),
                     "`kopia --version` must print the pinned version and build")
        suite.expect(M.hex([0x00, 0x0f, 0xab, 0xff]) == "000fabff", "SHA-256 in lower-case hexadecimal")
        suite.expect(M.codeRequirement.contains("7299Z9ZVTK") && M.codeRequirement.hasPrefix("anchor apple generic"),
                     "every launch checks Kopia LLC's Developer ID team")
        suite.expect(ForkMacBackupEngineInstallFailure.allCases.allSatisfy { ForkMacBackupEngineInstallFailure.parse($0.rawValue) == $0 }
                        && ForkMacBackupEngineInstallFailure.parse("from-a-newer-build") == .io,
                     "an install failure's code reads back; an unknown one reads as an I/O failure")
    }

    // MARK: Commands

    private static func commands(_ suite: TestSuite) {
        typealias C = ForkMacBackupKopiaCommand
        let inherited = ["KOPIA_CACHE_DIRECTORY": "/shared/cache", "KOPIA_CONFIG_PATH": "/Users/x/Library/Application Support/kopia/repository.config",
                         "AWS_SESSION_TOKEN": "stale", "AWS_SECRET_ACCESS_KEY": "parent-secret", "TMPDIR": "/var/folders/t/",
                         "USER": "test", "HOME": "/Users/test", "PATH": "/opt/homebrew/bin:/usr/bin", "DYLD_INSERT_LIBRARIES": "/evil.dylib"]
        let invocations: [ForkMacBackupKopiaInvocation] = [
            C.invocation(C.connect(repository, files: files, readOnly: false, create: false), files: files, credentials: credentials,
                         timeout: 60, inherited: inherited),
            C.invocation(C.connect(repository, files: files, readOnly: false, create: true), files: files, credentials: credentials,
                         timeout: 60, inherited: inherited),
            C.invocation(C.status, files: files, credentials: credentials, timeout: 60, inherited: inherited),
            C.invocation(C.snapshotList(path: "/Users/test", incomplete: true), files: files, credentials: credentials,
                         timeout: 60, inherited: inherited),
            C.invocation(C.verify(percent: 10), files: files, credentials: credentials, timeout: 60, inherited: inherited),
            C.invocation(C.blobStats, files: files, credentials: credentials, timeout: 60, inherited: inherited),
            C.invocation(C.maintenanceRun(full: true), files: files, credentials: credentials, timeout: 60, inherited: inherited),
            C.invocation(C.serverStart(socketPath: "/tmp/swishsaint-501/kopia-1.sock"), files: files, credentials: credentials,
                         timeout: 60, inherited: inherited),
            C.invocation(C.restore(manifestID: "abc", relativePath: "Documents/x", target: "/tmp/r", overwrite: false,
                                   skipExisting: true, skipOwners: true, ignorePermissionErrors: true),
                         files: files, credentials: credentials, timeout: 60, inherited: inherited),
        ]
        let secrets = ["repo-SECRET-pass", "s3-SECRET-key", "SECRET"]
        suite.expect(invocations.allSatisfy { invocation in
            !invocation.arguments.contains { argument in secrets.contains { argument.contains($0) } }
                && !secrets.contains { invocation.displayLine.contains($0) }
        }, "no secret ever on a Kopia command line")
        suite.expect(invocations.allSatisfy { Array($0.arguments.prefix(3)) == C.global(files) }
                        && C.global(files) == ["--config-file=\(files.config.path)", "--log-dir=\(files.logs.path)", "--no-use-keychain"],
                     "every call names its own config and log folder and turns Kopia's Keychain off, first")
        suite.expect(invocations.allSatisfy { !$0.arguments.contains { $0.hasPrefix("--help") } },
                     "never `--help-long` nor `--help-full` (they run the command, SPIKES §0.1)")
        let environment = invocations[0].environment
        suite.expect(environment["KOPIA_PASSWORD"] == "repo-SECRET-pass" && environment["AWS_ACCESS_KEY_ID"] == "AKIA-TEST"
                        && environment["AWS_SECRET_ACCESS_KEY"] == "s3-SECRET-key" && environment["KOPIA_CHECK_FOR_UPDATES"] == "false",
                     "secrets travel in the environment only, update checks off")
        suite.expect(invocations.allSatisfy { invocation in
            invocation.environment["KOPIA_CACHE_DIRECTORY"] == nil && invocation.environment["KOPIA_CONFIG_PATH"] == nil
                && invocation.environment["AWS_SESSION_TOKEN"] == nil && invocation.environment["DYLD_INSERT_LIBRARIES"] == nil
        }, "the environment is built from nothing: no KOPIA_CACHE_DIRECTORY (cross-repository corruption), no stray AWS or DYLD")
        suite.expect(environment["HOME"] == files.folder.appendingPathComponent("home").path && environment["TMPDIR"] == "/var/folders/t/"
                        && environment["USER"] == "test" && environment["PATH"] == "/usr/bin:/bin:/usr/sbin:/sbin",
                     "a private HOME, the temporary folder and the user's name, a fixed PATH")
        let noKeys = C.environment(credentials: .init(repositoryPassword: "p"), files: files, inherited: inherited)
        suite.expect(noKeys["AWS_SECRET_ACCESS_KEY"] == nil && noKeys["AWS_ACCESS_KEY_ID"] == nil,
                     "no S3 key: none inherited from the parent either")
        let extra = C.environment(credentials: nil, files: files, inherited: [:], extra: ["KOPIA_CACHE_DIRECTORY": "/x", "A": "b"])
        suite.expect(extra["KOPIA_CACHE_DIRECTORY"] == nil && extra["A"] == "b", "not even an explicit KOPIA_CACHE_DIRECTORY")

        let connect = C.connect(repository, files: files, readOnly: true, create: false)
        suite.expect(Array(connect.prefix(3)) == ["repository", "connect", "s3"]
                        && connect.contains("--access-key=") && connect.contains("--secret-access-key=") && connect.contains("--session-token=")
                        && connect.contains("--endpoint=minio.example.ts.net:9000") && connect.contains("--disable-tls")
                        && connect.contains("--prefix=home/") && connect.contains("--cache-directory=\(files.cache.path)")
                        && connect.contains("--override-hostname=test-mac") && connect.contains("--override-username=test")
                        && connect.contains("--no-persist-credentials") && connect.contains("--readonly"),
                     "connect: empty S3 keys (the secret never lands in repository.config), own cache, identity, nothing persisted")
        let create = C.connect(repository, files: files, readOnly: true, create: true)
        suite.expect(create[1] == "create" && !create.contains("--readonly"), "create never read-only")
        var tls = repository
        tls.endpoint = .init(host: "s3.example.com", tls: true)
        tls.prefix = ""
        let secure = C.connect(tls, files: files, readOnly: false, create: false)
        suite.expect(!secure.contains("--disable-tls") && !secure.contains { $0.hasPrefix("--prefix") }
                        && secure.contains("--endpoint=s3.example.com"), "TLS by default, no empty prefix flag")

        suite.expect(C.snapshotList(path: nil, incomplete: false) == ["snapshot", "list", "--json", "--all"]
                        && C.snapshotList(path: "/Users/test", incomplete: true) == ["snapshot", "list", "--json", "/Users/test", "--incomplete"],
                     "snapshot list: all or one source, incomplete ones on demand")
        suite.expect(C.percentText(10) == "10" && C.percentText(0.5) == "0.5" && C.percentText(150) == "100" && C.percentText(-1) == "0",
                     "verify percent written as Kopia reads it")
        suite.expect(C.maintenanceRun(full: true) == ["maintenance", "run", "--full"]
                        && !C.maintenanceRun(full: true).contains { $0.contains("safety") }, "maintenance never `--safety=none`")
        let restore = C.restore(manifestID: "abc", relativePath: "/Documents//x/", target: "/tmp/r", overwrite: false,
                                skipExisting: false, skipOwners: true, ignorePermissionErrors: false)
        suite.expect(restore[1] == "abc/Documents/x" && restore.contains("--write-sparse-files")
                        && restore.contains("--no-write-files-atomically") && restore.contains("--no-overwrite-files")
                        && restore.contains("--progress") && restore.contains("--skip-owners")
                        && !restore.contains("--ignore-permission-errors"),
                     "restore: snapshot/path root, sparse files kept, never atomic writes, progress on")
        let server = C.serverStart(socketPath: "/tmp/s.sock")
        suite.expect(server.contains("--address=unix:/tmp/s.sock") && server.contains("--insecure") && server.contains("--async-repo-connect")
                        && server.contains("--shutdown-on-stdin") && server.contains("--ui")
                        && !server.contains { $0.contains("password") },
                     "server: unix socket, async connect, stops with its stdin, UI API, passwords in the environment only")
        suite.expect(C.serverEnvironment(serverPassword: "a", controlPassword: "b")
                        == ["KOPIA_SERVER_PASSWORD": "a", "KOPIA_SERVER_CONTROL_PASSWORD": "b"], "server passwords by environment")
        suite.expect(C.policyImport(file: URL(fileURLWithPath: "/tmp/p.json")) == ["policy", "import", "--from-file=/tmp/p.json"],
                     "policy import from a file")
        suite.expect(ForkMacBackupSourcePath.normalized("/Users/test/") == "/Users/test"
                        && ForkMacBackupSourcePath.normalized("/") == "/", "source paths without a trailing slash")
    }

    // MARK: Text

    private static func sizes(_ suite: TestSuite) {
        let t = ForkMacBackupKopiaText.self
        suite.expect(t.bytes("212.7 MB") == 212_700_000 && t.bytes("67.7 KB") == 67_700 && t.bytes("0 B") == 0
                        && t.bytes("107.4 GB") == 107_400_000_000 && t.bytes("946878887") == 946_878_887
                        && t.bytes("1.5 GiB") == 1_610_612_736 && t.bytes("2MB") == 2_000_000,
                     "Kopia's sizes read, decimal and binary units")
        suite.expect(t.bytes("") == nil && t.bytes("lots") == nil && t.bytes("12 parsecs") == nil && t.bytes("-3 MB") == nil,
                     "an unreadable size is nil, never a guess")
        suite.expect(t.lines("a\rb\n\n  c  \r\n") == ["a", "b", "c"], "lines split on \\n and \\r, trimmed")
    }

    private static func blobStats(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 1_792_663_440)
        let raw = ForkMacBackupKopiaText.blobStats(text("engine-cli-blob-stats-raw.txt"), measuredAt: now)
        suite.expect(raw == ForkMacBackupBlobStats(blobCount: 122, totalBytes: 946_878_887, measuredAt: now),
                     "blob stats --raw: 122 blobs, 946 878 887 bytes exactly")
        let human = ForkMacBackupKopiaText.blobStats(text("engine-cli-blob-stats.txt"), measuredAt: now)
        suite.expect(human?.blobCount == 78 && human?.totalBytes == 212_700_000, "blob stats in units: 78 blobs, 212.7 MB")
        suite.expect(ForkMacBackupKopiaText.blobStats("Listing blobs...\nCount: 3\n", measuredAt: now) == nil,
                     "no total, no stats")
        suite.expect(ForkMacBackupKopiaText.blobStats("WARN something\n  Count: 5\nTotal: 1 KB\nHistogram:\n", measuredAt: now)?.totalBytes == 1000,
                     "a warning line before is ignored")
    }

    private static func restoreText(_ suite: TestSuite) {
        let t = ForkMacBackupKopiaText.self
        let sparse = t.restoreProgress(text("engine-cli-restore-sparse-dir-stderr.txt"))
        suite.expect(sparse?.processedEntries == 2 && sparse?.processedBytes == 107_400_000_000 && sparse?.totalBytes == 107_400_000_000
                        && sparse?.percent == 100.0, "restore progress: the last `Processed … (100.0%)` line of a 107 GB sparse restore")
        let first = t.restoreProgressLine("Processed 1 (58.2 GB) of 1 (107.4 GB) 646 MB/s (54.2%) remaining 1m15s.")
        suite.expect(first == .init(processedEntries: 1, processedBytes: 58_200_000_000, totalEntries: 1, totalBytes: 107_400_000_000,
                                    skippedEntries: 0, skippedBytes: 0, percent: 54.2),
                     "restore progress line: done, total, percentage (the rate is not a size)")
        let file = t.restoreProgress(text("engine-cli-restore-file-stderr-notty.txt"))
        suite.expect(file?.processedBytes == 209_700_000 && file?.totalBytes == nil && file?.totalEntries == nil,
                     "a single file has no total (« of 0 (0 B) »): nil, not zero")
        let skipped = t.restoreProgress(text("engine-cli-restore-skip-existing-stderr.txt"))
        suite.expect(skipped?.processedEntries == 3121 && skipped?.totalBytes == 67_700 && skipped?.skippedEntries == 2999
                        && skipped?.skippedBytes == 67_700, "skip-existing: skipped files and bytes read")
        suite.expect(t.restoreProgressLine("Restoring to local filesystem (/x) with parallelism=8...") == nil
                        && t.restoreProgressLine("Processed lots") == nil, "other lines are not progress")
        let dir = t.restoreSummary(text("engine-cli-restore-dir-stderr.txt"))
        suite.expect(dir == .init(files: 3000, directories: 121, symlinks: 0, bytes: 67_700, skippedFiles: 0, skippedBytes: 0),
                     "restore summary: 3000 files, 121 folders, 67.7 KB")
        let skip = t.restoreSummary(text("engine-cli-restore-skip-existing-stderr.txt"))
        suite.expect(skip == .init(files: 1, directories: 121, symlinks: 0, bytes: 20, skippedFiles: 2999, skippedBytes: 67_700),
                     "restore summary with skipped files")
        suite.expect(t.restoreSummary(text("engine-cli-restore-file-stderr-notty.txt"))?.bytes == 209_700_000
                        && t.restoreSummary("nothing here") == nil, "single file summary; none without the line")
    }

    private static func verifyText(_ suite: TestSuite) {
        let result = ForkMacBackupKopiaText.verifyResult(fixture("engine-cli-snapshot-verify-10pct.json") ?? Data())
        suite.expect(result?.errorCount == 0 && result?.stats?.processedObjectCount == 3142 && result?.stats?.readFileCount == 294
                        && result?.stats?.expectedTotalObjectCount == 9401, "snapshot verify --json: objects checked, files read, no error")
        let lines = ForkMacBackupKopiaText.lines(text("engine-cli-snapshot-verify-10pct.stderr.txt"))
        let progress = lines.compactMap(ForkMacBackupKopiaText.verifyProgress)
        suite.expect(progress == [ForkMacBackupVerifyProgress(checked: 0, total: 9401)], "verify progress from its stderr JSON line only")
        suite.expect(ForkMacBackupKopiaText.verifyProgress("{\"processedObjectCount\":5,\"expectedTotalObjectCount\":0}")?.total == nil,
                     "no total yet: nil")
        suite.expect(ForkMacBackupKopiaText.expireCount(text("engine-cli-snapshot-expire-dryrun.txt")) == 4
                        && ForkMacBackupKopiaText.expireCount("nothing to do") == nil, "snapshot expire dry run: only a count")
    }

    private static func serverText(_ suite: TestSuite) {
        let lines = ForkMacBackupKopiaText.lines(text("engine-server-startup-stderr.txt")).map(ForkMacBackupKopiaText.serverLine)
        suite.expect(lines.first == .controlPassword("REDACTED") && lines.last == .address("unix+http://kopia.sock")
                        && lines.contains(.other("Server will close when stdin is closed...")),
                     "server start-up: the control password line, then the address (ready)")
    }

    private static func errors(_ suite: TestSuite) {
        let classify = { (text: String) in ForkMacBackupKopiaText.classify(stderr: text, exitCode: 1) }
        suite.expect(classify("ERROR error connecting to repository: invalid repository password") == .authentication
                        && classify("ERROR password prompt error: operation not supported by device") == .authentication,
                     "a wrong or missing repository password is an authentication failure")
        suite.expect(classify("ERROR error retrieving storage config from bucket \"kopia-bench\": Access Denied.") == .authentication
                        && classify("ERROR unable to get metadata: The Access Key Id you provided does not exist in our records.") == .authentication,
                     "a refused S3 key is an authentication failure (bench errors)")
        if case .unreachable(let message) = classify("ERROR error connecting: Get \"http://127.0.0.1:19001/kopia-bench/\": dial tcp 127.0.0.1:19001: connect: connection refused") {
            suite.expect(message.contains("connection refused"), "an unreachable storage carries its own words")
        } else {
            suite.expect(false, "connection refused → unreachable")
        }
        suite.expect(classify("ERROR repository not initialized in the provided storage") == .notConnected
                        && ForkMacBackupKopiaText.isNotInitialized("ERROR repository not initialized in the provided storage"),
                     "an empty storage reads as « create it »")
        suite.expect(classify("ERROR something unexpected\n") == .kopia(exitCode: 1, message: "something unexpected"),
                     "anything else keeps Kopia's message")
        suite.expect(ForkMacBackupKopiaText.errorLine("Listing blobs...\n{\"a\":1}\nkopia: error: expected command but got \"false\", try --help\n")
                        == "expected command but got \"false\", try --help", "the error line, without Kopia's prefix nor the JSON")
        // Core's classifier on the failures Kopia really wrote on the bench.
        let partial = manifest(json: text("engine-cli-snapshot-create-partial-15errors.json"))
        let causes = Set((partial?.rootEntry?.summ?.errors ?? []).map { ForkMacBackupFailureCause.classify(message: $0.error ?? "", path: $0.path ?? "") })
        suite.expect(causes == [.permission], "Kopia's « permission denied » entries are permission failures")
        suite.expect(ForkMacBackupFailureCause.classify(message: "unable to open file: read /Users/x/Library/Mobile Documents/com~apple~CloudDocs/a.pdf: resource deadlock avoided")
                        == .cloudOnly, "EDEADLK on an iCloud file: cloud only")
        suite.expect(ForkMacBackupAPIFailure.from(status: 400, body: Data("{\"code\":\"NOT_CONNECTED\",\"error\":\"not connected\"}".utf8))
                        == .engine(.notConnected)
                        && ForkMacBackupAPIFailure.from(status: 401, body: Data()) == .engine(.serverUnavailable)
                        && ForkMacBackupAPIFailure.from(status: 400, body: Data("{\"code\":\"INTERNAL\",\"error\":\"policy not found\"}".utf8)).isNotFound
                        && ForkMacBackupAPIFailure.from(status: 404, body: Data("{\"error\":\"no source matching the provided filters\"}".utf8)).isNotFound,
                     "server answers: not connected, stale passwords, not found")
    }

    // MARK: HTTP

    private static func http(_ suite: TestSuite) {
        typealias H = ForkMacBackupHTTP
        let request = H.Request(method: "PUT", target: H.path("/api/v1/policy", query: [("path", "/Users/x y/Été & co")]),
                                headers: [("Authorization", H.basicAuthorization(user: "swishsaint", password: "p:w"))],
                                body: Data("{}".utf8))
        let wire = String(decoding: request.serialized(), as: UTF8.self)
        suite.expect(wire.hasPrefix("PUT /api/v1/policy?path=%2FUsers%2Fx%20y%2F%C3%89t%C3%A9%20%26%20co HTTP/1.1\r\n")
                        && wire.contains("Connection: close\r\n") && wire.contains("Content-Length: 2\r\n")
                        && wire.contains("Authorization: Basic c3dpc2hzYWludDpwOnc=\r\n") && wire.hasSuffix("\r\n\r\n{}"),
                     "request on the wire: encoded query, Basic auth, length, one request per connection")
        let post = String(decoding: H.Request(method: "POST", target: "/x").serialized(), as: UTF8.self)
        suite.expect(post.contains("Content-Length: 0\r\n"), "an empty POST says so")

        // Content-Length, delivered in pieces.
        let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nSet-Cookie: Kopia-Session-Cookie=abc-123; Path=/\r\n"
            + "Set-Cookie: Kopia-Auth=jwt; Path=/; Expires=x\r\nContent-Length: 11\r\n\r\n{\"ok\":true}"
        var reader = H.ResponseReader()
        var body = Data()
        for byte in Data(response.utf8) { body += (try? reader.consume(Data([byte]))) ?? Data() }
        suite.expect(reader.isComplete && reader.head?.status == 200 && String(decoding: body, as: UTF8.self) == "{\"ok\":true}"
                        && reader.head?.cookies == ["Kopia-Session-Cookie": "abc-123", "Kopia-Auth": "jwt"],
                     "a response read byte by byte: status, cookies, body")
        // Chunked, with an extension and a trailer, split anywhere.
        let chunked = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4;x=1\r\nWiki\r\n5\r\npedia\r\nE\r\n in\r\n\r\nchunks.\r\n0\r\nX-T: 1\r\n\r\n"
        var all = true
        for split in stride(from: 1, to: chunked.utf8.count, by: 7) {
            var reader = H.ResponseReader()
            let bytes = Data(chunked.utf8)
            var body = (try? reader.consume(bytes.prefix(split))) ?? Data()
            body += (try? reader.consume(bytes.dropFirst(split))) ?? Data()
            all = all && reader.isComplete && String(decoding: body, as: UTF8.self) == "Wikipedia in\r\n\r\nchunks."
        }
        suite.expect(all, "chunked bodies de-chunked wherever the bytes split")
        var closeDelimited = H.ResponseReader()
        let partial = (try? closeDelimited.consume(Data("HTTP/1.1 200 OK\r\n\r\nabc".utf8))) ?? Data()
        suite.expect(!closeDelimited.isComplete && closeDelimited.finishAtClose() && partial == Data("abc".utf8),
                     "no length: the body ends with the connection")
        var empty = H.ResponseReader()
        _ = try? empty.consume(Data("HTTP/1.1 204 No Content\r\n\r\n".utf8))
        suite.expect(empty.isComplete, "204 has no body")
        var bad = H.ResponseReader()
        suite.expect((try? bad.consume(Data("SSH-2.0-OpenSSH\r\n\r\n".utf8))) == nil, "a non-HTTP answer is refused")
        var badChunk = H.ResponseReader()
        suite.expect((try? badChunk.consume(Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nzz\r\n".utf8))) == nil,
                     "a malformed chunk size is refused")
        let html = "<html><head><meta name=\"kopia-csrf-token\" content=\"0123abcd\"><title>KopiaUI</title></head></html>"
        suite.expect(H.csrfToken(inHTML: html) == "0123abcd" && H.csrfToken(inHTML: "<html></html>") == nil,
                     "the CSRF token from the UI page's meta tag")
        suite.expect(H.apiError(Data("{\"code\":\"NOT_CONNECTED\"}".utf8))?.code == "NOT_CONNECTED" && H.apiError(Data("{}".utf8)) == nil,
                     "the server's error body")
    }

    // MARK: Policies

    private static func policies(_ suite: TestSuite) {
        let rules = ForkMacBackupPolicyRules(ignoreRules: ["/.Trash/", "*.log", "node_modules/"], ignoreCacheDirs: true,
                                             retention: .economical)
        let existing: [String: Any] = ["compression": ["compressorName": "zstd"],
                                       "scheduling": ["intervalSeconds": 3600, "timeOfDay": [["hour": 2, "min": 0]], "manual": false],
                                       "files": ["ignore": ["old/"], "ignoreDotFiles": [".kopiaignore"]]]
        let merged = ForkMacBackupPolicyDocument.merged(existing, rules: rules)
        let scheduling = merged["scheduling"] as? [String: Any] ?? [:]
        let mergedFiles = merged["files"] as? [String: Any] ?? [:]
        suite.expect((merged["compression"] as? [String: String]) == ["compressorName": "zstd"]
                        && (mergedFiles["ignoreDotFiles"] as? [String]) == [".kopiaignore"],
                     "a policy's other parts are kept")
        suite.expect((mergedFiles["ignore"] as? [String]) == rules.ignoreRules && scheduling["manual"] as? Bool == true
                        && scheduling["intervalSeconds"] == nil && scheduling["timeOfDay"] == nil,
                     "the ignore list is REPLACED whole, manual always on, Kopia's own schedule removed")
        let data = ForkMacBackupPolicyDocument.data(merged) ?? Data()
        suite.expect(ForkMacBackupPolicyDocument.object(data).flatMap(ForkMacBackupPolicyDocument.rules(from:)) == rules,
                     "what is written reads back equal (the agent's comparison)")
        let show = ForkMacBackupPolicyDocument.object(fixture("engine-cli-policy-show.json") ?? Data())
        let shown = show.flatMap(ForkMacBackupPolicyDocument.rules(from:))
        suite.expect(shown == ForkMacBackupPolicyRules(ignoreRules: ["/sparse/", "*.iso", "node_modules/"], ignoreCacheDirs: false,
                                                       manual: true, retention: .init(latest: 10, hourly: 48, daily: 7, weekly: 4,
                                                                                      monthly: 24, annual: 3)),
                     "`policy show --json` (bench) read as rules")
        let exported = ForkMacBackupPolicyDocument.exported(fixture("engine-cli-policy-export.json") ?? Data())
        suite.expect((exported?["files"] as? [String: Any])?["ignore"] as? [String] == ["*.bak", "*.tmp"]
                        && exported.flatMap(ForkMacBackupPolicyDocument.rules(from:)) == nil,
                     "`policy export` unwrapped; a policy without our retention reads as « not applied »")
        let server = ForkMacBackupPolicyDocument.object(fixture("engine-server-ui-policy-get.json") ?? Data())
        suite.expect(server != nil && ForkMacBackupPolicyDocument.rules(from: server ?? [:]) == nil,
                     "the server's policy (bench) decodes; ours not written yet")
        let identity = ForkMacBackupRepository.Identity(userName: "test", hostName: "test-mac")
        let importFile = ForkMacBackupPolicyDocument.importData(merged, identity: identity, path: "/Users/test")
            .flatMap(ForkMacBackupPolicyDocument.object)
        suite.expect(importFile?.keys.sorted() == ["test@test-mac:/Users/test"], "`policy import`'s file names the source")
        suite.expect(ForkMacBackupPolicyDocument.object(Data()) == nil && ForkMacBackupPolicyDocument.object(Data("[1]".utf8)) == nil,
                     "an empty or non-object body is no policy")
    }

    // MARK: Retention

    private struct KopiaRetention: Decodable {
        var id: String
        var startTime: String
        var endTime: String
        var retentionReason: [String]
    }

    private static func retention(_ suite: TestSuite) {
        let paris = TimeZone(identifier: "Europe/Paris")!
        for (name, retention) in [("economical", ForkMacBackupRetention.economical), ("balanced", ForkMacBackupRetention.balanced)] {
            guard let data = fixture("engine-snapshot-list-retention-\(name)-paris.json"),
                  let kopia = try? JSONDecoder().decode([KopiaRetention].self, from: data) else {
                suite.expect(false, "retention fixture \(name)")
                continue
            }
            let snapshots = kopia.compactMap { item in
                ForkMacBackupKopia.date(item.startTime).map {
                    ForkMacBackupRetentionReplay.Snapshot(id: item.id, startTime: $0, endTime: ForkMacBackupKopia.date(item.endTime))
                }
            }
            let replay = ForkMacBackupRetentionReplay.evaluate(snapshots, retention: retention, timeZone: paris)
            let ours = Dictionary(uniqueKeysWithValues: replay.map { ($0.snapshot.id, $0.reasons) })
            let mismatches = kopia.filter { ours[$0.id] != $0.retentionReason }.map { "\($0.startTime) kopia \($0.retentionReason) ours \(ours[$0.id] ?? [])" }
            suite.expect(snapshots.count == 129 && mismatches.isEmpty,
                         "retention replay = Kopia's own reasons for 129 snapshots over two years (\(name), Paris, DST, new year): \(mismatches.prefix(3))")
            let deleted = ForkMacBackupRetentionReplay.deletions(snapshots, retention: retention, timeZone: paris).map(\.id)
            suite.expect(Set(deleted) == Set(kopia.filter { $0.retentionReason.isEmpty }.map(\.id)),
                         "the preview lists exactly what `snapshot expire` would delete (\(name): \(deleted.count))")
        }
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        let canceledNewest = [
            ForkMacBackupRetentionReplay.Snapshot(id: "c1", startTime: base.addingTimeInterval(7200), incomplete: "canceled"),
            .init(id: "c2", startTime: base.addingTimeInterval(3600), incomplete: "canceled"),
            .init(id: "ok", startTime: base),
            .init(id: "c-old", startTime: base.addingTimeInterval(-86_400), incomplete: "canceled"),
        ]
        let verdicts = ForkMacBackupRetentionReplay.evaluate(canceledNewest, retention: .init(latest: 1, hourly: 0, daily: 0, weekly: 0,
                                                                                               monthly: 0, annual: 0))
        suite.expect(verdicts.map(\.reasons) == [["incomplete"], ["incomplete"], ["latest-1"], []],
                     "incomplete snapshots newer than the last complete one are kept, older ones go")
        let keepAll = ForkMacBackupRetentionReplay.evaluate((0..<30).map { .init(id: "\($0)", startTime: base.addingTimeInterval(Double($0))) },
                                                           retention: .init(latest: 0, hourly: 0, daily: 0, weekly: 0, monthly: 0, annual: 0))
        suite.expect(keepAll.allSatisfy(\.isKept), "all counts at zero keep everything (Kopia's rule)")
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = paris
        let march31 = calendar.date(from: DateComponents(year: 2026, month: 3, day: 31, hour: 12))!
        let minusOneMonth = ForkMacBackupRetentionReplay.goAddDate(march31, months: -1, calendar: calendar)
        suite.expect(calendar.dateComponents([.month, .day], from: minusOneMonth) == DateComponents(month: 3, day: 3),
                     "dates move like Go's AddDate: 31 March minus a month is 3 March")
        suite.expect(ForkMacBackupRetentionReplay.sortedReasons(["annual-1", "daily-2", "latest-1", "hourly-10", "hourly-2"])
                        == ["latest-1", "hourly-10", "hourly-2", "daily-2", "annual-1"], "reasons in Kopia's order")
    }

    // MARK: Conclusion

    private static func conclusion(_ suite: TestSuite) {
        let partial = manifest(json: text("snapshot-create-partial.json"))!
        let start = (partial.startDate ?? Date()).addingTimeInterval(-1)
        let concluded = ForkMacBackupRunConclusion.conclude(sourcePath: "/Users/bench/bench/data", startedAt: start,
                                                            manifests: [partial], failures: nil, iCloud: .local)
        suite.expect(concluded.outcome == .partial && concluded.proof?.failures.first?.cause == .permission,
                     "exit 1 with a manifest: partial, its failure named (bench)")
        let late = ForkMacBackupRunConclusion.conclude(sourcePath: "/Users/bench/bench/data", startedAt: start.addingTimeInterval(600),
                                                       manifests: [partial], failures: nil, iCloud: .local)
        suite.expect(late.outcome == .failed && late.manifest == nil, "an older manifest is not this run's: failed")
        let other = ForkMacBackupRunConclusion.conclude(sourcePath: "/Users/bench/bench/other", startedAt: start,
                                                        manifests: [partial], failures: nil, iCloud: .local)
        suite.expect(other.outcome == .failed, "another source's manifest is not this run's")
        let canceledList = ForkMacBackupKopia.decode([ForkMacBackupKopia.SnapshotManifest].self, from: fixture("snapshot-list-canceled.json") ?? Data()) ?? []
        if let canceled = canceledList.first, let path = canceled.source?.path, let begin = canceled.startDate {
            let result = ForkMacBackupRunConclusion.conclude(sourcePath: path, startedAt: begin, manifests: canceledList,
                                                             failures: [], iCloud: .local)
            suite.expect(result.outcome == .canceled, "« incomplete: canceled »: canceled with a checkpoint, not failed")
        } else {
            suite.expect(false, "canceled fixture")
        }
        let complete = manifest(json: text("snapshot-create-complete.json"))!
        let ok = ForkMacBackupRunConclusion.conclude(sourcePath: complete.source?.path ?? "", startedAt: complete.startDate ?? Date(),
                                                     manifests: [partial, complete], failures: [], iCloud: .local)
        suite.expect(ok.outcome == .complete && ok.proof?.level == .complete, "no error: complete")
        let cloud = ForkMacBackupFailure(path: "Library/Mobile Documents/com~apple~CloudDocs/a.pdf",
                                         message: "read: resource deadlock avoided")
        let local = ForkMacBackupRunConclusion.conclude(sourcePath: "/Users/bench/bench/data", startedAt: start, manifests: [partial],
                                                        failures: [cloud], iCloud: .local)
        suite.expect(local.proof?.cloudOnly == [cloud.path] && local.proof?.failures.isEmpty == true,
                     "a cloud-only file is listed apart in local mode")

        let tasks = ForkMacBackupKopia.decode(ForkMacBackupKopia.TaskInfo.self, from: fixture("engine-server-ui-task-2-snapshot-data.json") ?? Data())
        suite.expect(tasks.flatMap(ForkMacBackupLiveProgress.uploadedBytes(of:)) == 198_561_297,
                     "the real bytes sent: the task's « Uploaded Bytes » (upload.uploadedBytes stays 0)")
        if let task = tasks {
            let identity = ForkMacBackupRepository.Identity(userName: "bench", hostName: "bench-mac")
            let started = ForkMacBackupKopia.date(task.startTime)!
            suite.expect(ForkMacBackupRunConclusion.snapshotTask(in: [task], identity: identity, sourcePath: "/Users/bench/bench/data",
                                                                 startedAt: started)?.id == "2"
                            && ForkMacBackupRunConclusion.snapshotTask(in: [task], identity: identity, sourcePath: "/Users/bench/bench/dat",
                                                                       startedAt: started) == nil
                            && ForkMacBackupRunConclusion.snapshotTask(in: [task], identity: identity, sourcePath: "/Users/bench/bench/data",
                                                                       startedAt: started.addingTimeInterval(60)) == nil,
                         "a short run's task found by its source and start, not a prefix of another path")
        }
    }

    private static func failureLists(_ suite: TestSuite) {
        let directory = ForkMacBackupKopia.decode(ForkMacBackupKopia.DirectoryManifest.self, from: fixture("engine-cli-show-dir-errors-root.json") ?? Data())
        let summaries: [(folder: String, errors: [ForkMacBackupKopia.EntryError])] =
            [("", directory?.summary?.errors ?? [])] + (directory?.entries ?? []).map { ("", $0.summ?.errors ?? []) }
        let merged = ForkMacBackupFailureList.merge(summaries: summaries, taskLogs: nil)
        suite.expect(merged.count == 18 && merged.contains { $0.path == "nested/deeper/bad1.txt" } && merged.allSatisfy { $0.cause == .permission },
                     "18 failures over two folders, each named once (root summary and folder summaries overlap)")
        let nested: [(folder: String, errors: [ForkMacBackupKopia.EntryError])] =
            [("nested", ForkMacBackupKopia.decode([ForkMacBackupKopia.EntryError].self,
                                                  from: Data("[{\"path\":\"deeper/bad9.txt\",\"error\":\"x: permission denied\"}]".utf8)) ?? [])]
        suite.expect(ForkMacBackupFailureList.merge(summaries: nested, taskLogs: nil).map(\.path) == ["nested/deeper/bad9.txt"],
                     "a folder's own listing names paths relative to it")
        let logs = ForkMacBackupKopia.decode(ForkMacBackupFailureList.TaskLogs.self, from: fixture("engine-server-ui-task-2-logs.json") ?? Data())
        let fromLogs = ForkMacBackupFailureList.merge(summaries: [], taskLogs: logs)
        suite.expect(logs?.logs.count == 134 && fromLogs.map(\.path) == ["unreadable/mode000.txt"] && fromLogs.first?.cause == .permission,
                     "the server task's log names the failure too (134 entries, one failure)")
        let both = ForkMacBackupFailureList.merge(summaries: [("", [ForkMacBackupKopia.EntryError].decode("[{\"path\":\"./unreadable//mode000.txt\",\"error\":\"permission denied\"}]"))],
                                                  taskLogs: logs)
        suite.expect(both.count == 1, "the same file from two places is listed once")
        let fifteen = manifest(json: text("engine-cli-snapshot-create-partial-15errors.json"))
        suite.expect(fifteen.map(ForkMacBackupFailureList.needsWalk) == false, "every failure named at the root: no walk")
        let capped = manifest(json: "{\"id\":\"x\",\"rootEntry\":{\"obj\":\"k1\",\"summ\":{\"numFailed\":25,\"errors\":[{\"path\":\"a\",\"error\":\"e\"}]}}}")
        suite.expect(capped.map(ForkMacBackupFailureList.needsWalk) == true, "more counted than named: walk the folders")
    }

    // MARK: Restore

    private static func restorePlan(_ suite: TestSuite) {
        typealias P = ForkMacBackupRestorePlan
        suite.expect(P.rootReference(manifestID: "m1", relativePath: "") == "m1" && P.rootReference(manifestID: "m1", relativePath: "./a//b/") == "m1/a/b",
                     "restore root: snapshot ID, then the path (keeps mode and date)")
        let body = P.apiRequest(root: "m1/a", target: "/tmp/x", mode: .init(overwrite: false, skipOwners: true, ignorePermissionErrors: true))
        let output = body["fsOutput"] as? [String: Any] ?? [:]
        let options = body["options"] as? [String: Any] ?? [:]
        suite.expect(options["restoreDirEntryAtDepth"] as? Int32 == Int32.max && options["minSizeForPlaceholder"] as? Int32 == Int32.max
                        && output["writeSparseFiles"] as? Bool == true && output["writeFilesAtomically"] as? Bool == false
                        && output["skipOwners"] as? Bool == true && output["overwriteFiles"] as? Bool == false,
                     "restore API: full depth (the default is shallow), sparse kept, never atomic, owners skipped on demand")
        let items: [ForkMacBackupRestoreRequest.Item] = [.init(objectID: "o1", relativePath: "Docs/report.pdf", isDirectory: false),
                                                         .init(objectID: "o2", relativePath: "Photos", isDirectory: true),
                                                         .init(objectID: "o3", relativePath: "Other/report.pdf", isDirectory: false)]
        let apart = P.steps(.init(manifestID: "m", sourcePath: "/Users/t", items: items, destination: .folder(path: "/Users/t/Downloads/R"),
                                  skipOwners: false, ignorePermissionErrors: false), word: "restauré",
                            exists: { $0 == "/Users/t/Downloads/R/Photos" })
        suite.expect(apart.map(\.target) == ["/Users/t/Downloads/R/report.pdf", "/Users/t/Downloads/R/Photos (restauré)",
                                             "/Users/t/Downloads/R/report (restauré).pdf"]
                        && apart.allSatisfy { $0.kind == .direct && !$0.overwrite },
                     "into a folder apart: never over something there, nor over each other")
        let original = P.steps(.init(manifestID: "m", sourcePath: "/Users/t", items: items, destination: .original(.keepBoth),
                                     skipOwners: false, ignorePermissionErrors: false), word: "restored", exists: { _ in true })
        suite.expect(original.first?.target == "/Users/t/Docs/report.pdf" && original.allSatisfy { $0.kind == .staged(.keepBoth) },
                     "keep both: staged, then merged by the engine")
        let all = P.steps(.init(manifestID: "m", sourcePath: "/Users/t", items: items, destination: .original(.replaceAll),
                                skipOwners: false, ignorePermissionErrors: false), word: "restored", exists: { _ in true })
        suite.expect(all.allSatisfy { $0.kind == .direct && $0.overwrite }, "replace all: Kopia overwrites")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let restored = P.FileFacts(size: 10, modified: now)
        let taken: (String) -> Bool = { $0 == "a (restored).txt" }
        suite.expect(P.decision(rule: .keepBoth, name: "a.txt", restored: restored, existing: nil, suffix: "restored", isTaken: taken) == .move
                        && P.decision(rule: .keepBoth, name: "a.txt", restored: restored, existing: .init(size: 10, modified: now.addingTimeInterval(0.4)),
                                      suffix: "restored", isTaken: taken) == .keep
                        && P.decision(rule: .keepBoth, name: "a.txt", restored: restored, existing: .init(size: 11, modified: now),
                                      suffix: "restored", isTaken: taken) == .moveRenamed("a (restored 2).txt"),
                     "keep both: nothing there → move; identical → keep; different → beside it, never over a name taken")
        suite.expect(P.decision(rule: .replaceIfOlder, name: "a", restored: restored, existing: .init(size: 1, modified: now.addingTimeInterval(-60)),
                                suffix: "r", isTaken: taken) == .replace
                        && P.decision(rule: .replaceIfOlder, name: "a", restored: restored, existing: .init(size: 1, modified: now.addingTimeInterval(60)),
                                      suffix: "r", isTaken: taken) == .keep
                        && P.decision(rule: .replaceIfOlder, name: "a", restored: restored, existing: .init(size: 1, modified: now),
                                      suffix: "r", isTaken: taken) == .keep,
                     "replace if older: only a strictly older local file is replaced")
        var generator = Seeded(state: 42)
        let candidates = (1...100).map { Int64($0) }
        let sample = P.sample(candidates, count: 10, size: { $0 }, using: &generator)
        suite.expect(sample.count == 10 && Set(sample).count == 10 && sample.filter { $0 > 50 }.count == 5,
                     "the sample spreads over sizes: half among the larger files")
        var generator2 = Seeded(state: 7)
        suite.expect(P.sample([1, 2, 3], count: 10, size: { Int64($0) }, using: &generator2).sorted() == [1, 2, 3]
                        && P.sample([Int](), count: 3, size: { Int64($0) }, using: &generator2).isEmpty,
                     "fewer candidates than asked: all of them")
    }

    // MARK: Versions

    private static func versions(_ suite: TestSuite) {
        suite.expect(ForkMacBackupVersionsPlan.components("./Documents//a.txt") == ["Documents", "a.txt"]
                        && ForkMacBackupVersionsPlan.components("") == [], "a relative path in components")
        func snap(_ id: String, _ time: String, _ oid: String?) -> ForkMacBackupVersionsPlan.Found {
            let json = "{\"id\":\"\(id)\",\"startTime\":\"\(time)\",\"source\":{\"path\":\"/Users/t\"},\"rootEntry\":{\"obj\":\"r\(id)\",\"type\":\"d\"}}"
            let entry = oid.flatMap { ForkMacBackupKopia.decode(ForkMacBackupKopia.DirEntry.self,
                                                                from: Data("{\"name\":\"a\",\"type\":\"f\",\"obj\":\"\($0)\",\"size\":3}".utf8)) }
            return .init(manifest: manifest(json: json)!, entry: entry)
        }
        let found = [snap("s1", "2026-10-01T10:00:00Z", "o1"), snap("s3", "2026-10-03T10:00:00Z", "o2"),
                     snap("s2", "2026-10-02T10:00:00Z", "o1"), snap("s4", "2026-10-04T10:00:00Z", nil),
                     snap("s5", "2026-10-05T10:00:00Z", "o2")]
        let distinct = ForkMacBackupVersionsPlan.distinct(found)
        suite.expect(distinct.map(\.manifestID) == ["s5", "s2"] && distinct.map(\.objectID) == ["o2", "o1"],
                     "distinct versions by object ID, newest first, each under its newest snapshot; absent in one is skipped")
        let mapped = ForkMacBackupKopia.decode(ForkMacBackupKopia.SnapshotsResponse.self, from: fixture("engine-server-ui-snapshots-data.json") ?? Data())
        let source = ForkMacBackupKopia.SourceInfo(host: "bench-mac", userName: "bench", path: "/Users/bench/bench/data")
        let manifests = (mapped?.snapshots ?? []).compactMap { ForkMacBackupSnapshotMapping.manifest($0, source: source) }
        suite.expect(manifests.count == 1 && manifests.first?.rootEntry?.obj == "k12329afa9d1527bf4b01f55afcfda45f"
                        && manifests.first?.source?.path == "/Users/bench/bench/data" && manifests.first?.startDate != nil
                        && manifests.first?.rootEntry?.summ?.errors.first?.path == "unreadable/mode000.txt"
                        && manifests.first.map { ForkMacBackupVersionsPlan.manifests(of: "/Users/bench/bench/data", in: [$0]).count } == 1,
                     "the server's snapshot list (bench) read in the CLI's shape")
    }

    // MARK: Content scan

    private static func contentScan(_ suite: TestSuite) {
        typealias S = ForkMacBackupContentScan
        suite.expect(S.isSparseImage(logicalBytes: 926_000_000_000, allocatedBytes: 2_000_000_000)
                        && S.isSparseImage(logicalBytes: 10_000_000_000, allocatedBytes: 4_999_999_999)
                        && !S.isSparseImage(logicalBytes: 10_000_000_000, allocatedBytes: 5_000_000_000)
                        && !S.isSparseImage(logicalBytes: 9_999_999_999, allocatedBytes: 0),
                     "sparse disk image: ≥ 10 GB announced and less than half written (Docker.raw: 926 GB / 2 GB)")
        suite.expect(S.isDataless(flags: 0x4000_0000) && S.isDataless(flags: 0x4000_0020) && !S.isDataless(flags: 0x20),
                     "SF_DATALESS: iCloud files with no data on the Mac")
        suite.expect(S.ignoreRule(relativePath: "Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw", isDirectory: false)
                        == "/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
                        && S.ignoreRule(relativePath: "a/b [1]/x*y?.txt", isDirectory: false) == "/a/b \\[1]/x\\*y\\?.txt"
                        && S.ignoreRule(relativePath: "a\\b/trailing ", isDirectory: true) == "/a\\\\b/trailing\\ /",
                     "one path as an anchored, escaped ignore rule; a folder ends with « / »")
        let run = S.runRules(sparseImages: [.init(relativePath: "vm/disk.img", logicalBytes: 12_000_000_000, allocatedBytes: 0)],
                             dataless: ["Library/Mobile Documents/com~apple~CloudDocs/big.mov", "Library/Mobile Documents/x/",
                                        "Library/Mobile Documents/com~apple~CloudDocs/big.mov"])
        suite.expect(run == ["/vm/disk.img", "/Library/Mobile Documents/com~apple~CloudDocs/big.mov", "/Library/Mobile Documents/x/"],
                     "the run's rules: sparse images and cloud-only entries, once each")
        let rules = ForkMacBackupSource(path: "/Users/t").ignoreRules
        let matcher = ForkMacBackupIgnoreMatcher(rules: rules + ["weird*/x/", "/a\\*b/"])
        suite.expect(matcher.excludes(".Trash", isDirectory: true) && matcher.excludes("Library/Caches", isDirectory: true)
                        && !matcher.excludes("Library/Caches", isDirectory: false) && matcher.excludes("dev/app/node_modules", isDirectory: true)
                        && matcher.excludes("logs/today.log", isDirectory: false) && matcher.excludes("logs/old.log", isDirectory: true)
                        && !matcher.excludes("Documents/Library/Caches", isDirectory: true) && matcher.excludes("a*b", isDirectory: true)
                        && !matcher.excludes("ab", isDirectory: true) && matcher.excludes("weirdo/x", isDirectory: true)
                        && !matcher.excludes("a/weirdo/x", isDirectory: true),
                     "the rules read as Kopia reads them: anchored, by name, by suffix, wildcards, escapes")
        let negated = ForkMacBackupIgnoreMatcher(rules: ["*.log", "!keep.log", "build/"])
        suite.expect(!negated.excludes("logs/keep.log", isDirectory: false) && negated.excludes("logs/x.log", isDirectory: false)
                        && negated.excludingRule(for: "build/keep.log", isDirectory: false) == "build/",
                     "« ! » takes a file back, never out of a folder left out")

        // A real scan of a temporary folder with a 11 GB sparse file.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fork-macbackup-engine-\(getpid())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = FileManager.default
        try? manager.createDirectory(at: root.appendingPathComponent("vm"), withIntermediateDirectories: true)
        try? manager.createDirectory(at: root.appendingPathComponent("docs/sub"), withIntermediateDirectories: true)
        try? manager.createDirectory(at: root.appendingPathComponent("node_modules/pkg"), withIntermediateDirectories: true)
        try? Data(repeating: 1, count: 200_000).write(to: root.appendingPathComponent("docs/sub/big.bin"))
        try? Data(repeating: 2, count: 50_000).write(to: root.appendingPathComponent("docs/small.txt"))
        try? Data(repeating: 3, count: 300_000).write(to: root.appendingPathComponent("node_modules/pkg/index.js"))
        try? Data(repeating: 4, count: 10).write(to: root.appendingPathComponent("today.log"))
        let descriptor = open(root.appendingPathComponent("vm/disk.img").path, O_CREAT | O_WRONLY, 0o644)
        ftruncate(descriptor, 11_000_000_000)
        close(descriptor)
        let usage = S.scan(root: root, matcher: ForkMacBackupIgnoreMatcher(rules: rules))
        suite.expect(usage.sparseImages.map(\.relativePath) == ["vm/disk.img"] && usage.sparseImages.first?.logicalBytes == 11_000_000_000
                        && (usage.sparseImages.first?.allocatedBytes ?? .max) < 1_000_000,
                     "a sparse 11 GB file is found, with both its sizes")
        suite.expect(usage.logicalBytes > 11_000_000_000 && usage.allocatedBytes < 2_000_000 && usage.files == 3,
                     "sizes are real ones (allocated), the logical total only counted apart")
        suite.expect(usage.excludedEntries == 2 && usage.excludedAllocatedBytes > 0
                        && !usage.folders.contains { $0.relativePath.hasPrefix("node_modules") },
                     "excluded folders are not entered, excluded files are counted")
        suite.expect(usage.folders.first?.relativePath == "docs" && usage.folders.contains { $0.relativePath == "docs/sub" && $0.depth == 2 },
                     "the biggest folders, first and second level")
        var calls = 0
        let canceled = S.scan(root: root, isCanceled: { calls += 1; return calls > 2 })
        suite.expect(canceled.canceled && canceled.files < 4, "a scan stops when canceled")
        suite.expect(S.dataless(root: root).isEmpty, "no cloud-only file in a local folder")
    }

    // MARK: Server plan

    private static func serverPlan(_ suite: TestSuite) {
        let short = ForkMacBackupPaths(root: URL(fileURLWithPath: "/Users/t/Library/Application Support/s/MacBackup"))
        let long = ForkMacBackupPaths(root: URL(fileURLWithPath: "/Users/" + String(repeating: "x", count: 60)
                                                + "/Library/Application Support/com.example.swishsaint.dev/MacBackup"))
        let other = ForkMacBackupPaths(root: URL(fileURLWithPath: "/Users/" + String(repeating: "y", count: 60)
                                                 + "/Library/Application Support/com.example.swishsaint/MacBackup"))
        suite.expect(ForkMacBackupServerPlan.socketPath(paths: short, uid: 501) == short.kopiaSocket, "a socket path that fits: run/kopia.sock")
        let fallback = ForkMacBackupServerPlan.socketPath(paths: long, uid: 501).path
        suite.expect(!long.socketPathFits && fallback.hasPrefix("/tmp/swishsaint-501/kopia-") && fallback.hasSuffix(".sock")
                        && fallback.utf8.count <= ForkMacBackupPaths.maxSocketPathBytes
                        && fallback != ForkMacBackupServerPlan.socketPath(paths: other, uid: 501).path,
                     "a path over 103 bytes falls back to /tmp/swishsaint-<uid>/, one socket per build")
        suite.expect(ForkMacBackupServerPlan.isSafeSocketFolder(ownerUID: 501, mode: 0o700, isSymlink: false, uid: 501)
                        && !ForkMacBackupServerPlan.isSafeSocketFolder(ownerUID: 0, mode: 0o700, isSymlink: false, uid: 501)
                        && !ForkMacBackupServerPlan.isSafeSocketFolder(ownerUID: 501, mode: 0o755, isSymlink: false, uid: 501)
                        && !ForkMacBackupServerPlan.isSafeSocketFolder(ownerUID: 501, mode: 0o700, isSymlink: true, uid: 501),
                     "the /tmp fallback folder must be ours, 0700, not a planted link")
        let first = ForkMacBackupServerPlan.randomPassword()
        suite.expect(first.count == 64 && first.allSatisfy(\.isHexDigit) && first != ForkMacBackupServerPlan.randomPassword(),
                     "a random 256-bit password per start")
        let info = ForkMacBackupServerPlan.info(socket: URL(fileURLWithPath: "/tmp/s.sock"), serverPassword: "a", controlPassword: "b",
                                                pid: 42, startedAt: Date(timeIntervalSince1970: 1_800_000_000))
        suite.expect(ForkMacBackupServerPlan.encode(info).flatMap(ForkMacBackupServerPlan.decode) == info
                        && info.serverUser == "swishsaint" && info.controlUser == "server-control" && info.kopiaVersion == "0.23.1",
                     "server.json round trip")
        var newer = info
        newer.formatVersion = ForkMacBackupServerInfo.formatVersion + 1
        suite.expect(ForkMacBackupServerPlan.encode(newer).flatMap(ForkMacBackupServerPlan.decode) == nil
                        && ForkMacBackupServerPlan.decode(Data("{}".utf8)) == nil, "a newer or broken server.json is ignored")
        suite.expect((0..<8).map(ForkMacBackupServerPlan.restartDelay) == [1, 2, 5, 10, 30, 60, 300, 300],
                     "restart delays after a crash")
    }

    // MARK: Extras

    private static func extras(_ suite: TestSuite) {
        let info = ForkMacBackupMaintenanceInfo.decode(fixture("engine-cli-maintenance-info.json") ?? Data())
        suite.expect(info?.owner == "bench@bench-mac" && info?.quickInterval == 3600 && info?.fullInterval == 86_400
                        && info?.quickEnabled == true && info?.fullEnabled == true && info?.nextFull != nil && info?.lastRunSucceeded == true
                        && info?.isOwned(by: .init(userName: "bench", hostName: "bench-mac")) == true,
                     "maintenance info (bench): owner, intervals, next runs, last run")
        suite.expect(ForkMacBackupMaintenanceInfo.decode(Data("{\"owner\":\"x\"}".utf8)) == nil, "not maintenance info: nil")
        let restoreTask = ForkMacBackupKopia.decode(ForkMacBackupKopia.TaskInfo.self, from: fixture("engine-server-ui-restore-task-result.json") ?? Data())
        suite.expect(restoreTask?.counter("Restored Files") == 3000 && restoreTask?.knownStatus == .success,
                     "a restore task's counters (bench)")
        let trigger = ForkMacBackupPolicyDocument.object(fixture("engine-server-control-trigger-snapshot.json") ?? Data())
        let answers = trigger?["sources"] as? [String: Any]
        suite.expect(answers?.values.contains { ($0 as? [String: Any])?["success"] as? Bool == true } == true,
                     "trigger-snapshot's answer (bench) reads as a success")
        let down = ForkMacBackupPolicyDocument.object(fixture("engine-server-control-status-storage-down.json") ?? Data())
        suite.expect(down?["connected"] as? Bool == false, "a server whose storage is down says « not connected »")
    }

    // MARK: Strings

    private static func strings(_ suite: TestSuite) {
        func fields(_ value: ForkMacBackupEngineStrings) -> [(String, String)] {
            Mirror(reflecting: value).children.compactMap { child in (child.value as? String).map { (child.label ?? "", $0) } }
        }
        let english = Dictionary(uniqueKeysWithValues: fields(.enUS))
        var problems: [String] = []
        for language in AppLanguage.allCases {
            for (label, value) in fields(.strings(language)) {
                if value.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("\(language.rawValue).\(label) empty") }
                if language != .enUS, value == english[label] { problems.append("\(language.rawValue).\(label) untranslated") }
            }
            let suffix = ForkMacBackupEngineStrings.strings(language).restoredSuffix
            if suffix.contains("/") || suffix.contains(":") || suffix.contains("(") { problems.append("\(language.rawValue) suffix") }
        }
        suite.expect(english.count == 7 && problems.isEmpty, "the Engine's words exist and are translated in 15 languages: \(problems)")
        var typography: [String] = []
        for (label, value) in fields(.fr) {
            let scalars = Array(value.unicodeScalars)
            for (index, scalar) in scalars.enumerated() where ":;!?".unicodeScalars.contains(scalar) {
                if index == 0 || scalars[index - 1] != "\u{00A0}" { typography.append(label) }
            }
            if value.contains("'") { typography.append(label) }
        }
        suite.expect(typography.isEmpty, "French typography: \(typography)")
        suite.expect(ForkMacBackupEngineStrings.fr.restoredParenthesized == "(restauré)"
                        && ForkMacBackupEngineInstallFailure.checksum.title(.fr).contains("supprimé"),
                     "« (restauré) » and a failure worded in French")
    }
}

private extension Array where Element == ForkMacBackupKopia.EntryError {
    static func decode(_ json: String) -> [ForkMacBackupKopia.EntryError] {
        ForkMacBackupKopia.decode([ForkMacBackupKopia.EntryError].self, from: Data(json.utf8)) ?? []
    }
}
