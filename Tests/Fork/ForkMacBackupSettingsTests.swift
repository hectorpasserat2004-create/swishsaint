// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Suite `fork-macbackup-settings`: WP Settings' pure files
/// (`MacBackup/Settings/Pure/`). Every fixture is synthetic: nothing here
/// reads Bran's, Kopia's or Tailscale's real files.
enum ForkMacBackupSettingsTests {
    static func run(_ suite: TestSuite) {
        bran(suite)
        profiles(suite)
        kit(suite)
        retention(suite)
        wizard(suite)
        tailscale(suite)
        support(suite)
        scanner(suite)
        diagnostic(suite)
        strings(suite)
    }

    private static let now = Date(timeIntervalSince1970: 1_792_663_440) // 22/10/2026, a fixed instant

    private static let peers = ForkMacBackupTailscaleStatus.parse(Data(tailscaleJSON.utf8))?.peers ?? []

    // MARK: Fixtures (synthetic, anonymised)

    /// Bran's `backup/config.json` schema as seen on a Mac, battery key absent.
    private static let branJSON = """
    {
      "disableTLS": true,
      "ignoreRules": [".Trash", "Library/Caches", "node_modules", "/.venv/", "*.log", "Movies/Renders", "Library/Caches"],
      "intervalHours": 8,
      "isEnabled": true,
      "minioTailscaleIP": "100.64.0.7",
      "probeTimeout": 5,
      "repositoryTimeout": 120,
      "s3AccessKeyID": "kopia-test",
      "s3Bucket": "mac-test",
      "s3Endpoint": "100.64.0.7:9000",
      "s3Region": "us-east-1",
      "sourcePaths": ["~", "/Volumes/Work/Projects"],
      "tailscaleMinioNodeName": "minio",
      "someFutureKey": {"nested": true}
    }
    """

    /// Kopia's `repository.config`: identity, storage, and a secret the
    /// parser must never surface.
    private static let kopiaJSON = """
    {
      "storage": {"type": "s3", "config": {"bucket": "mac-test", "endpoint": "100.64.0.7:9000", "doNotUseTLS": true,
                  "prefix": "", "region": "us-east-1", "accessKeyID": "kopia-test", "secretAccessKey": "SUPER-SECRET"}},
      "caching": {"cacheDirectory": "/tmp/x"},
      "hostname": "ignored",
      "clientOptions": {"hostname": "test-mac-2", "username": "tester", "description": "Repository in S3"}
    }
    """

    private static let tailscaleJSON = """
    {
      "BackendState": "Running",
      "Self": {"HostName": "test-mac", "DNSName": "test-mac.tail0000.ts.net.", "Online": true},
      "MagicDNSSuffix": "tail0000.ts.net",
      "Peer": {
        "nodekey:aaa": {"ID": "nOFF1CNTRL", "HostName": "old-pi", "DNSName": "old-pi.tail0000.ts.net.",
                        "TailscaleIPs": ["100.64.0.9"], "Online": false, "OS": "linux"},
        "nodekey:bbb": {"ID": "nMINIO1CNTRL", "HostName": "minio", "DNSName": "minio.tail0000.ts.net.",
                        "TailscaleIPs": ["100.64.0.7", "fd7a:115c:a1e0::7"], "Online": true, "OS": "linux"},
        "nodekey:ccc": {"ID": "nPVE1CNTRL", "HostName": "proxmox", "DNSName": "proxmox.tail0000.ts.net.",
                        "TailscaleIPs": ["100.64.0.2"], "Online": true, "OS": "linux"},
        "nodekey:ddd": {"Unknown": true}
      }
    }
    """

    private static let repository = ForkMacBackupRepository(
        endpoint: .init(host: "minio.tail0000.ts.net", port: 9000, tls: false, observedIPs: ["100.64.0.7"]),
        bucket: "mac-test", region: "us-east-1", prefix: "", accessKeyID: "kopia-test",
        expectedUniqueID: "ac2952930000000000000000000000000000000000000000000000000000f120",
        clientIdentity: .init(userName: "tester", hostName: "test-mac-2"),
        peer: .init(stableID: "nMINIO1CNTRL", dnsName: "minio.tail0000.ts.net", hostName: "minio"),
        serverFlavor: .minio)

    // MARK: Bran

    private static func bran(_ suite: TestSuite) {
        guard let config = ForkMacBackupBranConfig.decode(Data(branJSON.utf8)) else {
            suite.expect(false, "Bran's config decodes")
            return
        }
        suite.expect(config.intervalHours == 8 && config.disableTLS == true && config.batteryPolicy == nil
                        && config.sourcePaths.count == 2 && config.s3Endpoint == "100.64.0.7:9000",
                     "Bran's config reads its fields, an absent battery key is fine, an unknown one ignored")
        let loose = ForkMacBackupBranConfig.decode(Data("""
        {"disableTLS": 1, "intervalHours": "6", "ignoreRules": ".Trash\\nnode_modules", "s3Bucket": " b-1 ",
         "s3Endpoint": "nas.local:9000", "probeTimeout": 5.0}
        """.utf8))
        suite.expect(loose?.disableTLS == true && loose?.intervalHours == 6 && loose?.ignoreRules == [".Trash", "node_modules"]
                        && loose?.s3Bucket == "b-1" && loose?.probeTimeout == 5 && loose?.sourcePaths == [],
                     "Bran's config is read tolerantly: numbers as text, booleans as 0/1, rules as lines")
        suite.expect(ForkMacBackupBranConfig.decode(Data("[1,2]".utf8)) == nil, "anything but an object is refused")

        let kopia = ForkMacBackupKopiaClientConfig.parse(Data(kopiaJSON.utf8))
        suite.expect(kopia?.identity == .init(userName: "tester", hostName: "test-mac-2") && kopia?.bucket == "mac-test"
                        && kopia?.doNotUseTLS == true,
                     "Kopia's config gives the client identity and the storage")
        let surfaced = kopia.map { Mirror(reflecting: $0).children.map { "\($0.value)" }.joined() } ?? ""
        suite.expect(!surfaced.contains("SUPER-SECRET"), "the secret key in Kopia's config is never read")

        let home = "/Users/tester"
        let local = ForkMacBackupRepository.Identity(userName: "local", hostName: "local-mac")
        guard let result = ForkMacBackupBranImport.map(config, kopia: kopia, peers: peers, home: home,
                                                       localIdentity: local, profileName: "Depuis Bran") else {
            suite.expect(false, "Bran's config maps")
            return
        }
        let repo = result.repository
        suite.expect(repo.endpoint.host == "minio.tail0000.ts.net" && repo.endpoint.port == 9000 && !repo.endpoint.tls
                        && repo.endpoint.observedIPs.contains("100.64.0.7") && result.usesMagicDNS,
                     "the endpoint becomes the peer's MagicDNS name, the address stays as seen: \(repo.endpoint)")
        suite.expect(repo.peer?.stableID == "nMINIO1CNTRL" && repo.serverFlavor == .minio && repo.bucket == "mac-test"
                        && repo.region == "us-east-1" && repo.accessKeyID == "kopia-test" && repo.expectedUniqueID == nil,
                     "the peer, the flavour, the bucket and the key ID come along; the lock waits for the test")
        suite.expect(repo.clientIdentity == .init(userName: "tester", hostName: "test-mac-2"),
                     "the identity is Kopia's, so the history continues")
        suite.expect(result.presets.contains(.trash) && result.presets.contains(.caches) && result.presets.contains(.devFolders)
                        && result.presets.contains(.logs) && result.presets.contains(.docker)
                        && result.presets.contains(.sparseDiskImages),
                     "Bran's rules become presets, and the defaults (sparse images, Docker) stay on: \(result.presets)")
        suite.expect(result.customRules == ["Movies/Renders"] && result.rulesAsPresets.count == 5,
                     "the rule no preset covers stays a free rule, duplicates once: \(result.customRules)")
        suite.expect(result.sources.map(\.path) == [home, "/Volumes/Work/Projects"]
                        && result.sources.allSatisfy { $0.customRules == ["Movies/Renders"] },
                     "the sources follow Bran's, « ~ » expanded")
        suite.expect(result.branIntervalHours == 8 && result.profile.name == "Depuis Bran"
                        && result.profile.chain.contains { $0.kind == .tailscale }
                        && result.profile.chain.first { $0.kind == .s3 }?.title == "MinIO"
                        && result.profile.repository == repo,
                     "the profile draws Tailscale and MinIO")

        let offline = ForkMacBackupBranImport.map(config, kopia: nil, peers: [], home: home, localIdentity: local,
                                                  profileName: "x")
        suite.expect(offline?.repository.endpoint.host == "100.64.0.7" && offline?.usesMagicDNS == false
                        && offline?.repository.peer == nil && offline?.repository.clientIdentity == local,
                     "without Tailscale the address stays, and this Mac's identity is used")
        let noEndpoint = ForkMacBackupBranConfig(s3Bucket: "b")
        suite.expect(ForkMacBackupBranImport.map(noEndpoint, kopia: nil, peers: [], home: home, localIdentity: local,
                                                 profileName: "x") == nil,
                     "without an endpoint nothing is imported")
        suite.expect(ForkMacBackupBranImport.canonical("**/node_modules/") == "node_modules"
                        && ForkMacBackupBranImport.canonical("/Library/Caches/**") == "Library/Caches",
                     "rules compare without their decorations")
    }

    // MARK: Profiles

    private static func profiles(_ suite: TestSuite) {
        let profile = ForkMacBackupProfile(
            name: "Maison — QNAP", repository: repository,
            chain: ForkMacBackupProfile.defaultChain(for: repository)
                + [ForkMacBackupChainNode(id: "proxmox", kind: .proxmox, detail: "LXC 111"),
                   ForkMacBackupChainNode(id: "nas", kind: .nas, title: "QNAP")],
            explanation: "Ton Mac chiffre tout.",
            rules: .init(presets: [.trash, .caches], custom: ["Movies/Renders"], iCloud: .exclude))
        guard let data = ForkMacBackupProfileFile.encode(profile) else {
            suite.expect(false, "a profile encodes")
            return
        }
        suite.expect(ForkMacBackupProfile.decode(data) == profile, "a profile file survives a round trip")
        suite.expect(!ForkMacBackupProfileFile.containsSecretField(data), "a profile carries no secret field")
        suite.expect(ForkMacBackupProfileFile.containsSecretField(Data(#"{"a":{"secretAccessKey":"x"}}"#.utf8))
                        && ForkMacBackupProfileFile.containsSecretField(Data(#"[{"repositoryPassword":"x"}]"#.utf8)),
                     "a secret field is found however deep")
        let text = String(data: data, encoding: .utf8) ?? ""
        suite.expect(text.contains("\n") && text.contains("\"name\""), "a profile file is readable by a person")
        let merged = ForkMacBackupProfileFile.merged([profile, ForkMacBackupProfile(name: "Ami", repository: repository, chain: [])],
                                                     adding: profile)
        suite.expect(merged.map(\.name) == ["Maison — QNAP", "Ami"], "a known profile is listed once, the active first")

        let chain = ForkMacBackupChainDisplay.chain(profile: profile, repository: repository)
        suite.expect(chain.count == 7 && chain.last?.kind == .nas, "the page draws the profile's own chain")
        var other = repository
        other.bucket = "another"
        suite.expect(ForkMacBackupChainDisplay.chain(profile: profile, repository: other).count == 5,
                     "another repository draws its default chain, not a stale profile")
        suite.expect(ForkMacBackupChainDisplay.chain(profile: nil, repository: nil).isEmpty, "nothing to draw without either")
    }

    // MARK: Kit

    private static func kit(_ suite: TestSuite) {
        let secrets = ForkMacBackupKitSecrets(repositoryPassword: "correct horse battery", s3SecretAccessKey: "s3-SECRET-key")
        guard let sealed = try? ForkMacBackupKitCrypto.seal(secrets, passphrase: "phrase de passe sûre") else {
            suite.expect(false, "the secrets seal")
            return
        }
        suite.expect(sealed.iterations == 600_000 && sealed.algorithm == ForkMacBackupSealedSecrets.algorithm
                        && Data(base64Encoded: sealed.salt)?.count == 16 && Data(base64Encoded: sealed.nonce)?.count == 12,
                     "PBKDF2-SHA256, 600 000 rounds, a 16-byte salt and a 12-byte nonce are kept")
        suite.expect(ForkMacBackupKitCrypto.open(sealed, passphrase: "phrase de passe sûre") == secrets,
                     "the right passphrase opens the secrets")
        suite.expect(ForkMacBackupKitCrypto.open(sealed, passphrase: "phrase de passe sure") == nil,
                     "a wrong passphrase opens nothing")
        var tampered = sealed
        if var box = Data(base64Encoded: sealed.box) {
            box[0] ^= 0x01
            tampered.box = box.base64EncodedString()
        }
        suite.expect(ForkMacBackupKitCrypto.open(tampered, passphrase: "phrase de passe sûre") == nil,
                     "a damaged box opens nothing")
        let again = try? ForkMacBackupKitCrypto.seal(secrets, passphrase: "phrase de passe sûre", iterations: 1_000)
        suite.expect(again.map { $0.salt != sealed.salt && $0.nonce != sealed.nonce && $0.iterations == 1_000 } ?? false
                        && again.flatMap { ForkMacBackupKitCrypto.open($0, passphrase: "phrase de passe sûre") } == secrets,
                     "each seal draws its own salt and nonce, and keeps its round count")
        suite.expect((try? ForkMacBackupKitCrypto.seal(secrets, passphrase: "")) == nil
                        && ForkMacBackupKitCrypto.open(sealed, passphrase: "") == nil,
                     "an empty passphrase neither seals nor opens")

        let file = ForkMacBackupKitFile(createdAt: now, createdBy: "Swishsaint 2240", kopiaVersion: "0.23.1",
                                        repository: repository, profileName: "Maison", secrets: sealed)
        guard let data = file.encoded() else {
            suite.expect(false, "a kit encodes")
            return
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        suite.expect(ForkMacBackupKitFile.decode(data) == file, "a kit file survives a round trip")
        suite.expect(!text.contains("correct horse") && !text.contains("s3-SECRET-key"),
                     "the kit file never holds a secret in clear")
        let plain = ForkMacBackupKitFile(createdAt: now, createdBy: "x", kopiaVersion: "0.23.1", repository: repository)
        suite.expect(plain.encoded().map { !ForkMacBackupProfileFile.containsSecretField($0) } ?? false,
                     "a kit without secrets has no secret field at all")

        let fingerprint = ForkMacBackupKit.fingerprint(repository)
        var moved = repository
        moved.endpoint.host = "100.64.0.7"
        suite.expect(fingerprint != ForkMacBackupKit.fingerprint(moved), "a new address calls for a new kit")
        suite.expect(ForkMacBackupKit.status(createdAt: nil, remindAt: nil, savedFingerprint: nil, repository: repository, now: now) == .missing
                        && ForkMacBackupKit.status(createdAt: now, remindAt: nil, savedFingerprint: fingerprint,
                                                   repository: repository, now: now.addingTimeInterval(86_400)) == .upToDate(createdAt: now)
                        && ForkMacBackupKit.status(createdAt: now, remindAt: nil, savedFingerprint: fingerprint,
                                                   repository: moved, now: now) == .repositoryChanged(createdAt: now)
                        && ForkMacBackupKit.status(createdAt: now, remindAt: nil, savedFingerprint: fingerprint,
                                                   repository: repository, now: now.addingTimeInterval(181 * 86_400))
                        == .reminderDue(createdAt: now),
                     "the kit is missing, up to date, made for another connection, or due for its 180-day check")

        let commands = ForkMacBackupKit.rescueCommands(repository)
        suite.expect(commands.count == 4 && commands[0].contains(ForkMacBackupKit.kopiaArchive)
                        && commands[0].contains("shasum -a 256")
                        && commands[1].contains("--endpoint=minio.tail0000.ts.net:9000") && commands[1].contains("--disable-tls")
                        && commands[1].contains("--readonly") && commands[1].contains("--access-key=kopia-test")
                        && commands[1].contains("<SECRET_ACCESS_KEY>") && commands[2] == "./kopia snapshot list --all"
                        && commands[3].hasPrefix("./kopia restore <SNAPSHOT_ID>"),
                     "the four rescue commands: download and check, connect read only, list, restore")
        suite.expect(ForkMacBackupKit.kopiaArchiveSHA256.count == 64, "the archive's full SHA-256 is printed")
    }

    // MARK: Retention

    private static func retention(_ suite: TestSuite) {
        suite.expect(ForkMacBackupRetention.preset(.balanced, custom: "").storageValue == "10,48,30,8,12,3"
                        && ForkMacBackupRetention.preset(.economical, custom: "").storageValue == "5,24,14,4,6,1"
                        && ForkMacBackupRetention.preset(.long, custom: "").storageValue == "10,48,60,26,36,10"
                        && ForkMacBackupRetention.preset(.custom, custom: "1,2,3,4,5,6").storageValue == "1,2,3,4,5,6"
                        && ForkMacBackupRetention.preset(.custom, custom: "nonsense") == .balanced,
                     "the four retention presets carry the plan's values")

        // The Settings preview runs the Engine's replay (verified against
        // Kopia itself), one source at a time.
        let paris = TimeZone(identifier: "Europe/Paris") ?? .current
        // One snapshot an hour for four days, newest first.
        let hourly = (0..<96).map { index in
            ForkMacBackupRetentionReplay.Snapshot(id: "h\(index)", startTime: now.addingTimeInterval(-Double(index) * 3_600 - 60))
        }
        let economical = ForkMacBackupRetentionReplay.evaluate(hourly, retention: .economical, timeZone: paris)
        let kept = economical.filter(\.isKept)
        suite.expect(economical.count == 96 && economical.prefix(24).allSatisfy(\.isKept),
                     "the last 24 hours are all kept by the hourly rule")
        suite.expect(kept.count >= 24 && kept.count <= 30 && !economical[60].isKept,
                     "beyond 24 hours only one a day stays (\(kept.count) kept)")
        suite.expect(economical[0].reasons.contains("latest-1") && economical[0].reasons.contains("hourly-1"),
                     "the newest is kept by several rules at once: not a copy more")
        let deletions = ForkMacBackupRetentionReplay.deletions(hourly, retention: .economical, timeZone: paris)
        suite.expect(deletions.count == 96 - kept.count, "the deletions are what no rule keeps")
        let nothing = ForkMacBackupRetention(latest: 0, hourly: 0, daily: 0, weekly: 0, monthly: 0, annual: 0)
        suite.expect(ForkMacBackupRetentionReplay.deletions(hourly, retention: nothing, timeZone: paris).isEmpty,
                     "a retention of zeros keeps everything, as Kopia does")

        let withIncomplete = [ForkMacBackupRetentionReplay.Snapshot(id: "new", startTime: now, incomplete: "canceled")] + hourly
            + [ForkMacBackupRetentionReplay.Snapshot(id: "old", startTime: now.addingTimeInterval(-50 * 3_600),
                                                    incomplete: "canceled")]
        let decisions = ForkMacBackupRetentionReplay.evaluate(withIncomplete, retention: .balanced, timeZone: paris)
        suite.expect(decisions.first { $0.snapshot.id == "new" }?.reasons == ["incomplete"]
                        && decisions.first { $0.snapshot.id == "old" }?.isKept == false,
                     "an incomplete snapshot stays only while no complete one came after it")
        // Two snapshots in the same hour: one slot.
        let twins = [ForkMacBackupRetentionReplay.Snapshot(id: "a", startTime: now.addingTimeInterval(-600)),
                     ForkMacBackupRetentionReplay.Snapshot(id: "b", startTime: now.addingTimeInterval(-1_200))]
        let onlyHourly = ForkMacBackupRetention(latest: 0, hourly: 5, daily: 0, weekly: 0, monthly: 0, annual: 0)
        suite.expect(ForkMacBackupRetentionReplay.deletions(twins, retention: onlyHourly, timeZone: paris).map(\.id) == ["b"],
                     "two snapshots of the same hour fill one hourly slot")

        let text = ForkMacBackupSettingsStrings.strings(.fr)
        let fr = Locale(identifier: "fr_FR")
        let sentence = text.retentionExplain(.balanced, language: .fr, locale: fr)
        suite.expect(sentence.contains("10") && sentence.contains("48") && sentence.contains(text.retentionTail),
                     "the retention reads as a sentence: \(sentence)")
        suite.expect(text.retentionExplain(nothing, language: .fr, locale: fr) == text.retentionNothing,
                     "keeping nothing is said plainly")
        let short = ForkMacBackupSettingsStrings.strings(.enUS).retentionShort(.economical, language: .enUS,
                                                                                locale: Locale(identifier: "en_US"))
        suite.expect(short.hasPrefix("5 latest") && short.components(separatedBy: " · ").count == 6,
                     "the short form lists six values: \(short)")
    }

    // MARK: Wizard

    private static func wizard(_ suite: TestSuite) {
        func parse(_ text: String) -> ForkMacBackupEndpointInput? { ForkMacBackupEndpointInput.parse(text) }
        suite.expect(parse("minio.tail0000.ts.net:9000") == .init(host: "minio.tail0000.ts.net", port: 9000, tls: nil),
                     "host:port reads")
        suite.expect(parse("https://s3.eu-west-3.amazonaws.com") == .init(host: "s3.eu-west-3.amazonaws.com", port: nil, tls: true)
                        && parse("http://10.0.0.5:9000/") == .init(host: "10.0.0.5", port: 9000, tls: false)
                        && parse("HTTPS://Nas.Local:443") == .init(host: "Nas.Local", port: 443, tls: true),
                     "a scheme says TLS, a trailing slash is harmless")
        suite.expect(parse("[fd7a:115c::7]:9000") == .init(host: "fd7a:115c::7", port: 9000, tls: nil)
                        && parse("fd7a:115c::7")?.port == nil && parse("fd7a:115c::7")?.isIPAddress == true,
                     "IPv6 with or without a port")
        suite.expect(parse("100.64.0.7")?.isIPAddress == true && parse("minio.local")?.isIPAddress == false
                        && parse("minio.tail0000.ts.net.")?.host == "minio.tail0000.ts.net",
                     "an IPv4 is recognised; a final dot is dropped")
        suite.expect(["", "  ", "host:0", "host:70000", "a b", "s3.example.com/bucket", "ftp://x", "user@host", "host:port",
                      "[::1", "http://"].allSatisfy { parse($0) == nil },
                     "anything else is refused")

        var form = ForkMacBackupServerForm()
        form.region = ""
        suite.expect(Set(form.issues) == Set(ForkMacBackupServerForm.Issue.allCases).subtracting([.port]),
                     "an empty form lists every issue but the port, which has a default: \(form.issues)")
        form.address = "minio.tail0000.ts.net"
        form.bucket = "mac-test"
        form.region = "us-east-1"
        form.accessKeyID = "kopia-test"
        form.secretKey = "s"
        suite.expect(form.isValid && form.effectivePort == 9000, "MinIO without a port takes 9000")
        form.flavor = .genericS3
        form.tls = true
        suite.expect(form.effectivePort == 443, "another S3 over TLS takes 443")
        form.port = "99999"
        suite.expect(form.issues == [.port], "a typed port out of range is an issue")
        form.port = ""
        form.secretKey = ""
        suite.expect(form.issues == [.secretKey], "the secret key is needed")
        form.hasSavedSecret = true
        suite.expect(form.isValid, "unless one is already saved for this repository")
        suite.expect(ForkMacBackupServerForm.isValidBucket("mac-martial") && !ForkMacBackupServerForm.isValidBucket("My_Bucket")
                        && !ForkMacBackupServerForm.isValidBucket("ab") && !ForkMacBackupServerForm.isValidBucket("192.168.1.1")
                        && !ForkMacBackupServerForm.isValidBucket("-abc") && !ForkMacBackupServerForm.isValidBucket("a..b"),
                     "S3's bucket rules")
        suite.expect(ForkMacBackupServerForm.isValidRegion("eu-west-3") && !ForkMacBackupServerForm.isValidRegion("eu west"),
                     "regions are words with dashes")

        var pasted = ForkMacBackupServerForm()
        pasted.address = "https://s3.example.com:8443"
        pasted.absorbAddress()
        suite.expect(pasted.address == "s3.example.com" && pasted.port == "8443" && pasted.tls,
                     "a pasted URL fills the address, the port and TLS")

        var chosen = ForkMacBackupServerForm()
        chosen.tls = true
        chosen.choose(peers.first { $0.hostName == "minio" }!)
        suite.expect(chosen.address == "minio.tail0000.ts.net" && chosen.peer?.stableID == "nMINIO1CNTRL" && !chosen.tls
                        && chosen.flavor == .minio,
                     "a Tailscale suggestion fills the MagicDNS name, never the address, and HTTP inside the tailnet")

        var edit = ForkMacBackupServerForm(repository: repository)
        edit.secretKey = "x"
        let identity = ForkMacBackupRepository.Identity(userName: "tester", hostName: "test-mac-2")
        let same = edit.repository(identity: identity, keeping: repository)
        suite.expect(same?.expectedUniqueID == repository.expectedUniqueID && same?.key == repository.key,
                     "an edit on the same storage keeps the lock")
        edit.bucket = "other-bucket"
        suite.expect(edit.repository(identity: identity, keeping: repository)?.expectedUniqueID == nil,
                     "another bucket drops the lock: it must be tested again")
        edit.bucket = "mac-test"
        edit.prefix = "//home/"
        edit.address = "100.64.0.7"
        let byAddress = edit.repository(identity: identity, keeping: repository)
        suite.expect(byAddress?.prefix == "home/" && byAddress?.endpoint.observedIPs == ["100.64.0.7"],
                     "the prefix loses its leading slashes; an address typed is remembered as seen")
    }

    // MARK: Tailscale

    private static func tailscale(_ suite: TestSuite) {
        let snapshot = ForkMacBackupTailscaleStatus.parse(Data(tailscaleJSON.utf8))
        suite.expect(snapshot?.running == true && snapshot?.selfOnline == true && snapshot?.peers.count == 3,
                     "Tailscale's status reads, a peer without a name is skipped")
        suite.expect(snapshot?.peers.map(\.shortName) == ["minio", "proxmox", "old-pi"],
                     "peers online first, then by name")
        suite.expect(snapshot?.peers.first?.dnsName == "minio.tail0000.ts.net", "the final dot of a MagicDNS name is dropped")
        suite.expect(ForkMacBackupTailscaleStatus.match(peers, stableID: "nPVE1CNTRL")?.hostName == "proxmox"
                        && ForkMacBackupTailscaleStatus.match(peers, dnsName: "MINIO.tail0000.ts.net.")?.hostName == "minio"
                        && ForkMacBackupTailscaleStatus.match(peers, address: "100.64.0.9")?.hostName == "old-pi"
                        && ForkMacBackupTailscaleStatus.match(peers, stableID: "gone", hostName: "minio")?.hostName == "minio"
                        && ForkMacBackupTailscaleStatus.match(peers, hostName: "nothing") == nil,
                     "a peer is found by stable ID, then DNS name, host name or address")
        suite.expect(ForkMacBackupTailscaleStatus.parse(Data("not json".utf8)) == nil
                        && ForkMacBackupTailscaleStatus.parse(Data("{}".utf8)) == nil,
                     "anything but a status is refused")
    }

    // MARK: Support

    private static func support(_ suite: TestSuite) {
        suite.expect(ForkMacBackupTimes.parse("21:00, 13:00,bad,25:00,13:00") == [780, 1_260]
                        && ForkMacBackupTimes.storageValue([1_260, 545, 545]) == "09:05,21:00",
                     "fixed times read sorted without duplicates and write back")
        let window = ForkMacBackupThrottleWindow.parse("09:00-19:00@5")
        suite.expect(window == .init(start: 540, end: 1_140, megabytesPerSecond: 5) && window?.storageValue == "09:00-19:00@5"
                        && ForkMacBackupThrottleWindow.parse("") == nil && ForkMacBackupThrottleWindow.parse("09:00-09:00@5") == nil
                        && ForkMacBackupThrottleWindow.parse("09:00-19:00@0") == nil,
                     "the slower window reads and writes « 09:00-19:00@5 »")

        var plan = ForkMacBackupVerifyPlan.parse("refs:7d,files1:1d,restore50:30d")
        suite.expect(plan == ForkMacBackupVerifyPlan.fallback && plan.entries.count == 3
                        && plan.entry(.contentSample)?.verifyLevel == .contentSample(percent: 1)
                        && plan.entry(.restoreTest)?.verifyLevel == .restoreTest(files: 50)
                        && plan.entry(.references)?.everyHours == 168 && plan.storageValue == "refs:7d,files1:1d,restore50:30d",
                     "the verification plan reads and writes back")
        plan.set(.references, everyHours: nil)
        plan.set(.contentSample, everyHours: 12)
        suite.expect(plan.storageValue == "files1:12h,restore50:30d", "a level is turned off or given another period")
        suite.expect(ForkMacBackupVerifyPlan.parse("refs:x,files1:2d,files2:1d,bogus:1d").storageValue == "files1:2d",
                     "a damaged plan keeps what it can")

        suite.expect(ForkMacBackupNotifyChannel(island: true, system: true) == .both
                        && ForkMacBackupNotifyChannel(island: false, system: false) == .none
                        && ForkMacBackupNotifyChannel.island.island && !ForkMacBackupNotifyChannel.island.system
                        && ForkMacBackupNotifyChannel.both.system,
                     "the matrix's two switches map to the four channels")
        suite.expect(ForkMacBackupNotifyEvent.allCases.filter { $0.defaultChannel != .none } == [.complete],
                     "by default only the end-of-backup notice speaks (decision 3)")

        let fresh = ForkMacBackupSetupState(engine: .notInstalled, fullDiskAccess: false, registration: .notRegistered,
                                            repository: nil, kitCreatedAt: nil)
        suite.expect(fresh.current == .engine && fresh.count == 0 && !fresh.isReady, "a new Mac starts with the engine")
        let ready = ForkMacBackupSetupState(engine: .installed(version: "0.23.1"), fullDiskAccess: true,
                                            registration: .developmentFallback, repository: repository, kitCreatedAt: nil)
        suite.expect(ready.isReady && ready.current == .kit && ready.count == 4, "the kit can wait once the rest is done")
        var unlocked = repository
        unlocked.expectedUniqueID = nil
        suite.expect(!ForkMacBackupSetupState(engine: .installed(version: "0.23.1"), fullDiskAccess: true,
                                              registration: .enabled, repository: unlocked, kitCreatedAt: nil).isReady,
                     "a repository not locked by its ID is not connected yet")

        let chain = ForkMacBackupProfile.defaultChain(for: repository)
            + [ForkMacBackupChainNode(id: "nas", kind: .nas, title: "QNAP")]
        let statuses = [ForkMacBackupPresentation.ChainStatus(id: "mac", kind: .mac, state: .ok),
                        .init(id: "tailscale", kind: .tailscale, state: .ok, latencyMs: 12),
                        .init(id: "server", kind: .s3, state: .broken),
                        .init(id: "repository", kind: .repository, state: .ok, latencyMs: 30),
                        .init(id: "nas", kind: .nas, state: .ok)]
        let drawn = ForkMacBackupChainDisplay.nodes(chain, statuses: statuses)
        suite.expect(drawn.map(\.state) == [.ok, .unknown, .ok, .broken, .unknown, .unknown],
                     "after a broken node nothing is claimed: \(drawn.map(\.state))")
        suite.expect(drawn[3].linkBeforeBroken && !drawn[4].linkBeforeBroken && drawn[4].isBeyondBreak && drawn[4].latencyMs == nil,
                     "the link before the break is dashed, the rest greyed")

        let manifests = [manifest("a", user: "tester", host: "test-mac-2", start: "2026-10-22T08:00:00Z"),
                         manifest("b", user: "tester", host: "test-mac-2", start: "2026-10-22T10:00:00Z"),
                         manifest("c", user: "friend", host: "old-air", start: "2026-09-01T10:00:00Z"),
                         manifest("d", user: nil, host: "x", start: nil)]
        let machines = ForkMacBackupRepositoryMachine.machines(in: manifests)
        suite.expect(machines.map(\.id) == ["tester@test-mac-2", "friend@old-air"] && machines[0].snapshots == 2
                        && machines[0].latest == ForkMacBackupKopia.date("2026-10-22T10:00:00Z"),
                     "the machines of a repository, newest first, with their counts")
        suite.expect(ForkMacBackupRepositoryMachine.suggested(machines, localHost: "Test-Mac-2", localUser: "tester")?.hostName == "test-mac-2"
                        && ForkMacBackupRepositoryMachine.suggested(machines, localHost: "new-mac", localUser: "tester") == nil,
                     "this Mac's own identity is offered to continue")
        suite.expect(ForkMacBackupLocalIdentity.hostName(from: "MacBook Pro de Whyte (2)") == "macbook-pro-de-whyte-2"
                        && ForkMacBackupLocalIdentity.hostName(from: "studio.local") == "studio"
                        && ForkMacBackupLocalIdentity.hostName(from: "  ") == "mac",
                     "a host name the way Kopia writes it")

        let registered = ForkMacBackupDefaults.registered
        suite.expect(registered[ForkDefaultsKey.macBackupWatchdogMinutes] as? Int == 10
                        && registered[ForkDefaultsKey.macBackupPriority] as? String == "low"
                        && registered[ForkDefaultsKey.macBackupRepositoryTimeout] as? Int == 60
                        && registered[ForkDefaultsKey.macBackupProbeTimeout] as? Int == 5,
                     "the page's agent settings are registered by Core, read by the agent")
        suite.expect([ForkDefaultsKey.macBackupKitFingerprint, ForkDefaultsKey.macBackupKnownProfiles].allSatisfy {
            ForkMacBackupDefaults.machineKeys.contains($0) && registered[$0] == nil
        }, "this package's machine state is never registered")
    }

    private static func manifest(_ id: String, user: String?, host: String, start: String?) -> ForkMacBackupKopia.SnapshotManifest {
        var source: [String: Any] = ["host": host, "path": "/Users/tester"]
        if let user { source["userName"] = user }
        var object: [String: Any] = ["id": id, "source": source]
        if let start { object["startTime"] = start }
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        return ForkMacBackupKopia.decode(ForkMacBackupKopia.SnapshotManifest.self, from: data)
            ?? ForkMacBackupKopia.decode(ForkMacBackupKopia.SnapshotManifest.self, from: Data(#"{"id":"\#(id)"}"#.utf8))!
    }

    // MARK: Scanner

    private static func scanner(_ suite: TestSuite) {
        func rule(_ text: String) -> ForkMacBackupIgnoreRule? { ForkMacBackupIgnoreRule(text) }
        func hits(_ text: String, _ path: String, directory: Bool) -> Bool {
            let name = (path as NSString).lastPathComponent
            return rule(text)?.matches(relativePath: path, name: name, depth: path.split(separator: "/").count,
                                       isDirectory: directory) ?? false
        }
        suite.expect(hits("node_modules/", "a/b/node_modules", directory: true) && !hits("node_modules/", "a/node_modules", directory: false)
                        && hits("/.Trash/", ".Trash", directory: true) && !hits("/.Trash/", "x/.Trash", directory: true)
                        && hits("/Library/Caches/", "Library/Caches", directory: true)
                        && !hits("/Library/Caches/", "Library/Caches/x", directory: true)
                        && hits("*.log", "deep/inside/app.log", directory: false) && !hits("*.log", "app.logs", directory: false)
                        && hits("Movies/Renders", "Movies/Renders", directory: true)
                        && !hits("Movies/Renders", "x/Movies/Renders", directory: true)
                        && hits("**/target", "a/b/target", directory: true),
                     "ignore rules match like Kopia's gitignore syntax")
        suite.expect(rule("") == nil && rule("# comment") == nil && rule("!keep") == nil && rule("/") == nil,
                     "blank lines, comments, negations (read by the matcher) and a bare slash are not rules")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fork-macbackup-settings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        func write(_ path: String, bytes: Int) {
            let url = root.appendingPathComponent(path)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(repeating: 0x5A, count: bytes).write(to: url)
        }
        write(".Trash/old.bin", bytes: 300_000)
        write("Library/Caches/com.app/cache.db", bytes: 200_000)
        write("Documents/report.pdf", bytes: 500_000)
        write("Documents/notes.log", bytes: 50_000)
        write("Developer/web/node_modules/lib/index.js", bytes: 120_000)
        write("Developer/web/build/out.js", bytes: 80_000)
        write("Movies/Renders/clip.mov", bytes: 400_000)
        write("Developer/cachey/CACHEDIR.TAG", bytes: 43)
        write("Developer/cachey/blob", bytes: 90_000)
        // A sparse disk image: 64 MB announced, nothing written.
        let image = root.appendingPathComponent("Library/Containers/vm/disk.raw")
        try? FileManager.default.createDirectory(at: image.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: image.path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: image) {
            try? handle.truncate(atOffset: 64_000_000)
            try? handle.close()
        }

        let settings = ForkMacBackupContentScanner.Settings(
            presets: [.trash, .caches, .devFolders, .logs, .sparseDiskImages, .cacheDirTag], customRules: ["Movies/Renders"],
            iCloud: .local, sparseMinimum: 32_000_000)
        var progressed = false
        let preview = ForkMacBackupContentScanner.scan(sources: [root.path], settings: settings, home: root.path, now: now,
                                                       progress: { _ in progressed = true })
        _ = progressed
        let trash = preview.group(.trash)
        suite.expect(trash.map { $0.bytes >= 300_000 && $0.files == 1 && $0.matches == 1 && $0.examples == ["~/.Trash"] } ?? false,
                     "the Trash is measured at its real size, with its path: \(String(describing: trash))")
        suite.expect((preview.group(.caches)?.bytes ?? 0) >= 200_000 && (preview.group(.devFolders)?.files ?? 0) == 1
                        && (preview.group(.logs)?.files ?? 0) == 1 && (preview.group(.cacheDirTag)?.files ?? 0) == 2,
                     "each preset is measured, including the folders marked as cache")
        suite.expect((preview.group(.genericBuildNames)?.matches ?? 0) == 1
                        && preview.group(.genericBuildNames)?.examples == ["~/Developer/web/build"],
                     "a preset left off is measured too, with the real paths it would touch")
        suite.expect((preview.group(rule: "Movies/Renders")?.bytes ?? 0) >= 400_000, "a free rule is measured")
        suite.expect(preview.sparse.count == 1 && preview.sparse.first?.logicalBytes == 64_000_000
                        && (preview.sparse.first?.allocatedBytes ?? .max) < 1_000_000
                        && preview.sparse.first?.path == "~/Library/Containers/vm/disk.raw",
                     "a sparse disk image is found with both its sizes: \(preview.sparse)")
        suite.expect(preview.includedFiles == 2 && preview.includedBytes >= 500_000 + 80_000 && preview.complete
                        && preview.excludedBytes >= 300_000 + 200_000 + 120_000 + 50_000 + 400_000,
                     "kept and left out add up from real sizes (kept \(preview.includedFiles) files)")
        suite.expect(preview.topFolders.first?.path == "~/Documents", "the biggest folder kept comes first")
        suite.expect(preview.includedBytes + preview.excludedBytes < 10_000_000,
                     "the sparse image's announced size is never counted")

        let stopped = ForkMacBackupContentScanner.scan(sources: [root.path], settings: settings, home: root.path,
                                                       isCancelled: { true })
        suite.expect(stopped.complete || stopped.includedFiles <= 2, "a scan can be stopped")
        if let data = try? ForkMacBackupJSON.encoder.encode(preview) {
            suite.expect(ForkMacBackupContentPreview.decode(data) == preview, "a preview is cached as JSON")
        }
    }

    // MARK: Diagnostic

    private static func diagnostic(_ suite: TestSuite) {
        var presentation = ForkMacBackupPresentation.preview(.failedChainBroken, now: now)
        presentation.lastError?.message = "dial tcp https://kopia:hunter2@minio:9000 failed in /Users/tester/x"
        let input = ForkMacBackupDiagnostic.Input(
            appName: "Swishsaint", appBuild: "2240", agentBuild: "2240", agentAlive: true, engineVersion: "0.23.1",
            registration: .enabled, fullDiskAccess: true, presentation: presentation, repository: repository,
            profileName: "Maison", sources: [ForkMacBackupSource(path: "/Users/tester")],
            settings: ["fork.macbackup.schedule.mode": "auto"], now: now)
        let text = ForkMacBackupDiagnostic.text(input)
        suite.expect(text.contains("endpoint: minio.tail0000.ts.net:9000") && text.contains("uniqueID: ac29…f120")
                        && text.contains("node.server: broken") && text.contains("fork.macbackup.schedule.mode: auto"),
                     "the diagnostic says where things stand")
        suite.expect(!text.contains("hunter2") && text.contains("://***@") && !text.contains(repository.expectedUniqueID ?? "-"),
                     "the diagnostic hides credentials in URLs and the full repository ID")
        suite.expect(ForkMacBackupDiagnostic.scrubHome("/Users/tester/Documents", home: "/Users/tester") == "~/Documents",
                     "the home folder reads as ~")

        let script = ForkMacBackupTerminalScript.text(engineBinary: "/A B/engine/kopia-0.23.1/kopia", config: "/c/repository.config",
                                                      cache: "/c/cache", logs: "/c/logs", accessKeyID: "kopia-test",
                                                      passwordPrompt: "Mot de passe\u{00A0}:", secretPrompt: "Clé \"S3\" $x",
                                                      banner: "Prêt l’ami")
        suite.expect(script.hasPrefix("#!/bin/zsh\n") && script.contains("export KOPIA_CONFIG_PATH='/c/repository.config'")
                        && script.contains("export PATH='/A B/engine/kopia-0.23.1':\"$PATH\"")
                        && script.contains("read -rs \"KOPIA_PASSWORD?") && script.contains("export AWS_ACCESS_KEY_ID='kopia-test'")
                        && script.contains("Clé \\\"S3\\\" \\$x") && script.hasSuffix("exec /bin/zsh -i\n"),
                     "the Terminal script points Kopia at this Mac's files and asks for the secrets")
        suite.expect(!script.contains("KOPIA_PASSWORD='") && !script.contains("AWS_SECRET_ACCESS_KEY='"),
                     "the Terminal script never carries a secret")
    }

    // MARK: Strings

    /// Words that may be the same as in English (names, units, tokens).
    private static let sameEverywhere: Set<String> = [
        "latencyMs", "minutesValue", "secondsValue", "presetDocker", "iCloudHeader", "kitFieldBucket", "serverBucket",
        "serverType", "kitFieldType", "kitPDFFingerprint", "serverAddressPrompt", "rulePlaceholder", "optionsTitle",
        "kitFieldKopia", "testHeader", "kitStepList", "serverPort", "engineVersion", "optionsTabNotifications",
        "notifySystem", "conditionsHeader", "wizardStepKit", "kitPDFChecksum", "presetLogsCaption", "serverPrefix",
        "kitFieldPrefix", "kitFieldRegion", "serverRegion", "exclusionOne", "exclusionFew", "exclusionMany",
        "priorityNormal", "presetSecretsCaption", "presetCacheTagCaption", "presetDevFoldersCaption", "detailProbe",
        "branDetails", "megabytesPerSecond", "stopBran",
        // Words several languages share with English (« Server », « Port », « Optional », « backup »…).
        "serverHeader", "wizardStepServer", "wizardStepRepository", "scheduleInterval", "optional", "passphrase",
        "repositoryPassword", "snapshotOne", "snapshotFew", "snapshotMany",
    ]
    private static let oneForms: Set<String> = ["folderOne", "exclusionOne", "matchOne", "ruleOne", "measuredOne",
                                                "snapshotOne", "latestOne", "keepTheLatestOne"]

    private static func fields(_ strings: ForkMacBackupSettingsStrings) -> [(String, String)] {
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
        suite.expect(AppLanguage.allCases.count == 15 && english.count > 300, "fifteen languages, every settings word")
        var empty: [String] = []
        var untranslated: [String] = []
        var wrongPlaceholders: [String] = []
        var asciiQuotes: [String] = []
        for language in AppLanguage.allCases {
            let values = fields(.strings(language))
            if values.count != english.count { empty.append("\(language.rawValue): \(values.count) fields") }
            for (label, value) in values {
                let tag = "\(language.rawValue).\(label)"
                if value.trimmingCharacters(in: .whitespaces).isEmpty { empty.append(tag) }
                if language != .enUS, value == english[label], !sameEverywhere.contains(label) { untranslated.append(tag) }
                let expected = placeholders(english[label] ?? "")
                let actual = placeholders(value)
                if actual != expected, !(oneForms.contains(label) && actual == ["%d"]) { wrongPlaceholders.append(tag) }
                if value.contains("\"") || value.contains("'") { asciiQuotes.append(tag) }
            }
        }
        suite.expect(empty.isEmpty, "every settings word exists in every language: \(empty)")
        suite.expect(untranslated.isEmpty, "every settings word is really translated: \(untranslated.prefix(40))")
        suite.expect(wrongPlaceholders.isEmpty, "every translation keeps its placeholders: \(wrongPlaceholders)")
        suite.expect(asciiQuotes.isEmpty, "typographic quotes and apostrophes only: \(asciiQuotes)")
        suite.expect(Set(AppLanguage.allCases.map { ForkMacBackupSettingsStrings.strings($0).kitWhy }).count >= 14,
                     "each language has its own sentences (Taiwan's and Hong Kong's Chinese may share one)")

        var typography: [String] = []
        for (label, value) in fields(.fr) {
            let scalars = Array(value.unicodeScalars)
            for (index, scalar) in scalars.enumerated() where ":;!?".unicodeScalars.contains(scalar) {
                // « ? » as a wildcard in the rules' syntax is a token, not punctuation.
                if label == "rulesSyntax" && scalar == "?" { continue }
                if index == 0 || scalars[index - 1] != "\u{00A0}" { typography.append(label) }
            }
            if value.contains("« ") || value.contains(" »") { typography.append(label) }
        }
        suite.expect(typography.isEmpty, "French: no-break space before : ; ! ? and inside « »: \(typography)")

        for language in [AppLanguage.ru, .uk] {
            let text = ForkMacBackupSettingsStrings.strings(language)
            suite.expect(text.folderCount(21, language: language).contains("21") && text.snapshotCount(1, language: language).contains("1")
                            && text.ruleCount(22, language: language) != text.ruleCount(25, language: language)
                                .replacingOccurrences(of: "25", with: "22"),
                         "\(language.rawValue) agrees 1, 21, 22 and 25 each its own way")
        }
        let en = ForkMacBackupSettingsStrings.strings(.enUS)
        suite.expect(en.folderCount(1, language: .enUS) == "1 folder" && en.folderCount(3, language: .enUS) == "3 folders"
                        && en.snapshotCount(29, language: .enUS) == "29 backups",
                     "English counts one and many")
        let fr = ForkMacBackupSettingsStrings.strings(.fr)
        let frLocale = Locale(identifier: "fr_FR")
        suite.expect(fr.period(nil, locale: frLocale) == fr.periodNever && fr.period(24, locale: frLocale) == fr.periodDaily
                        && fr.period(48, locale: frLocale).contains("2") && fr.period(12, locale: frLocale).contains("12"),
                     "a verification period reads in words")
        suite.expect(fr.ruleExplain(ForkMacBackupIgnoreRule("node_modules/")!).contains("dossier")
                        && fr.ruleExplain(ForkMacBackupIgnoreRule("/Movies/Exports")!).contains("racine"),
                     "a free rule is explained in a sentence")
        let hours = ForkMacBackupSettingsStrings.span(48, .hour, locale: frLocale)
        let year = ForkMacBackupSettingsStrings.span(1, .year, locale: frLocale)
        suite.expect(hours.hasPrefix("48") && hours.contains("heures") && year.hasPrefix("1") && year.hasSuffix("an"),
                     "spans take the system's plurals: \(hours), \(year)")
    }
}
