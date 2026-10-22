// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Bran's backup settings, `~/Library/Application Support/bran/backup/config.json`
/// (read only, and only when the person clicks « Importer depuis Bran »).
/// Tolerant: every field may be missing or of a neighbouring type (a number
/// written as text, a boolean as 0/1); unknown fields are ignored.
struct ForkMacBackupBranConfig: Decodable, Equatable {
    var disableTLS: Bool?
    var ignoreRules: [String]
    var intervalHours: Int?
    var isEnabled: Bool?
    var minioTailscaleIP: String?
    var probeTimeout: Int?
    var repositoryTimeout: Int?
    var s3AccessKeyID: String?
    var s3Bucket: String?
    /// « host:port ».
    var s3Endpoint: String?
    var s3Region: String?
    var sourcePaths: [String]
    var tailscaleMinioNodeName: String?
    /// Not always written.
    var batteryPolicy: String?

    /// The service and accounts of Bran's Keychain items (read only, with the
    /// system's own prompt).
    static let keychainService = "com.opahventures.bran.backup"
    static let secretKeyAccount = "bran.backup.s3SecretAccessKey"
    static let passwordAccount = "bran.backup.repositoryPassword"
    /// Bran's LaunchAgent label, for « Arrêter Bran ».
    static let agentLabel = "com.opahventures.bran.backup"
    /// Relative to the home folder.
    static let relativePath = "Library/Application Support/bran/backup/config.json"

    init(disableTLS: Bool? = nil, ignoreRules: [String] = [], intervalHours: Int? = nil, isEnabled: Bool? = nil,
         minioTailscaleIP: String? = nil, probeTimeout: Int? = nil, repositoryTimeout: Int? = nil,
         s3AccessKeyID: String? = nil, s3Bucket: String? = nil, s3Endpoint: String? = nil, s3Region: String? = nil,
         sourcePaths: [String] = [], tailscaleMinioNodeName: String? = nil, batteryPolicy: String? = nil) {
        self.disableTLS = disableTLS
        self.ignoreRules = ignoreRules
        self.intervalHours = intervalHours
        self.isEnabled = isEnabled
        self.minioTailscaleIP = minioTailscaleIP
        self.probeTimeout = probeTimeout
        self.repositoryTimeout = repositoryTimeout
        self.s3AccessKeyID = s3AccessKeyID
        self.s3Bucket = s3Bucket
        self.s3Endpoint = s3Endpoint
        self.s3Region = s3Region
        self.sourcePaths = sourcePaths
        self.tailscaleMinioNodeName = tailscaleMinioNodeName
        self.batteryPolicy = batteryPolicy
    }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        func string(_ name: String) -> String? {
            if let value = try? c.decodeIfPresent(String.self, forKey: Key(name)) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            if let value = try? c.decodeIfPresent(Int.self, forKey: Key(name)) { return String(value) }
            return nil
        }
        func int(_ name: String) -> Int? {
            if let value = try? c.decodeIfPresent(Int.self, forKey: Key(name)) { return value }
            if let value = try? c.decodeIfPresent(Double.self, forKey: Key(name)) { return Int(value) }
            return string(name).flatMap { Int($0) }
        }
        func bool(_ name: String) -> Bool? {
            if let value = try? c.decodeIfPresent(Bool.self, forKey: Key(name)) { return value }
            if let value = try? c.decodeIfPresent(Int.self, forKey: Key(name)) { return value != 0 }
            switch string(name)?.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        }
        func strings(_ name: String) -> [String] {
            if let values = try? c.decodeIfPresent([String].self, forKey: Key(name)) {
                return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            }
            // One rule per line, as a text field would keep them.
            return string(name)?.split(whereSeparator: \.isNewline).map {
                $0.trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty } ?? []
        }
        disableTLS = bool("disableTLS")
        ignoreRules = strings("ignoreRules")
        intervalHours = int("intervalHours")
        isEnabled = bool("isEnabled")
        minioTailscaleIP = string("minioTailscaleIP")
        probeTimeout = int("probeTimeout")
        repositoryTimeout = int("repositoryTimeout")
        s3AccessKeyID = string("s3AccessKeyID")
        s3Bucket = string("s3Bucket")
        s3Endpoint = string("s3Endpoint")
        s3Region = string("s3Region")
        sourcePaths = strings("sourcePaths")
        tailscaleMinioNodeName = string("tailscaleMinioNodeName")
        batteryPolicy = string("batteryPolicy") ?? string("batteryMode")
    }

    static func decode(_ data: Data) -> ForkMacBackupBranConfig? {
        try? JSONDecoder().decode(ForkMacBackupBranConfig.self, from: data)
    }
}

/// What Kopia's own `repository.config` (the one Bran used) tells about this
/// Mac's identity and the storage. Only the fields below are read; the
/// secret key some configs hold is never decoded.
struct ForkMacBackupKopiaClientConfig: Equatable {
    var hostName: String?
    var userName: String?
    var storageType: String?
    var bucket: String?
    var endpoint: String?
    var prefix: String?
    var region: String?
    var doNotUseTLS: Bool?
    var accessKeyID: String?

    var identity: ForkMacBackupRepository.Identity? {
        guard let userName, let hostName, !userName.isEmpty, !hostName.isEmpty else { return nil }
        return .init(userName: userName, hostName: hostName)
    }

    static func parse(_ data: Data) -> ForkMacBackupKopiaClientConfig? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let client = root["clientOptions"] as? [String: Any] ?? [:]
        let storage = root["storage"] as? [String: Any] ?? [:]
        let config = storage["config"] as? [String: Any] ?? [:]
        func text(_ dictionary: [String: Any], _ key: String) -> String? {
            guard let value = dictionary[key] as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
        let parsed = ForkMacBackupKopiaClientConfig(
            hostName: text(client, "hostname"), userName: text(client, "username"),
            storageType: text(storage, "type"), bucket: text(config, "bucket"), endpoint: text(config, "endpoint"),
            prefix: config["prefix"] as? String, region: text(config, "region"),
            doNotUseTLS: config["doNotUseTLS"] as? Bool, accessKeyID: text(config, "accessKeyID"))
        guard parsed.hostName != nil || parsed.userName != nil || parsed.bucket != nil else { return nil }
        return parsed
    }
}

/// Bran's settings turned into ours (plan §18): a repository (MagicDNS name
/// preferred when the Tailscale peer is known), a profile, the sources and
/// their rules (as presets where they match one, free rules for the rest).
enum ForkMacBackupBranImport {
    struct Result: Equatable {
        var repository: ForkMacBackupRepository
        var profile: ForkMacBackupProfile
        var sources: [ForkMacBackupSource]
        var presets: [ForkMacBackupPreset]
        /// Bran's rules no preset covers, kept as free rules.
        var customRules: [String]
        /// Bran's own rules a preset now covers.
        var rulesAsPresets: [String]
        /// Bran's pace, shown next to our Automatic rhythm.
        var branIntervalHours: Int?
        /// The endpoint moved from an address to the peer's MagicDNS name.
        var usesMagicDNS: Bool
        var branWasEnabled: Bool
    }

    enum Failure: Error, Equatable {
        /// No endpoint or no bucket: nothing to connect to.
        case incomplete
    }

    /// Maps Bran's settings. `peers` is Tailscale's view (may be empty);
    /// `kopia` is Kopia's own config (identity, prefix); `localIdentity` is
    /// used when Kopia's config names none.
    static func map(_ config: ForkMacBackupBranConfig, kopia: ForkMacBackupKopiaClientConfig?,
                    peers: [ForkMacBackupTailscalePeer], home: String,
                    localIdentity: ForkMacBackupRepository.Identity,
                    profileName: String) -> Result? {
        guard let endpointText = config.s3Endpoint ?? kopia?.endpoint,
              let parsed = ForkMacBackupEndpointInput.parse(endpointText),
              let bucket = config.s3Bucket ?? kopia?.bucket else { return nil }

        let tls = !(config.disableTLS ?? kopia?.doNotUseTLS ?? false)
        var host = parsed.host
        var observed: [String] = []
        if parsed.isIPAddress { observed.append(parsed.host) }
        if let ip = config.minioTailscaleIP, !observed.contains(ip),
           ForkMacBackupEndpointInput(host: ip, port: nil, tls: nil).isIPAddress {
            observed.append(ip)
        }

        // The peer: by node name, then by address.
        let peer = ForkMacBackupTailscaleStatus.match(peers, hostName: config.tailscaleMinioNodeName,
                                                      address: parsed.isIPAddress ? parsed.host : config.minioTailscaleIP)
            ?? ForkMacBackupTailscaleStatus.match(peers, dnsName: parsed.isIPAddress ? nil : parsed.host)
        var usesMagicDNS = false
        if let peer, !peer.dnsName.isEmpty {
            if host != peer.dnsName { usesMagicDNS = parsed.isIPAddress }
            host = peer.dnsName
            for address in peer.addresses where !observed.contains(address) && !address.contains(":") {
                observed.append(address)
            }
        }
        let isMinIO = config.tailscaleMinioNodeName != nil
            || (config.tailscaleMinioNodeName ?? peer?.hostName ?? host).lowercased().contains("minio")
        let identity = kopia?.identity ?? localIdentity

        let repository = ForkMacBackupRepository(
            kind: .s3,
            endpoint: .init(host: host, port: parsed.port ?? (isMinIO ? 9000 : (tls ? 443 : 80)), tls: tls,
                            observedIPs: observed),
            bucket: bucket,
            region: config.s3Region ?? kopia?.region ?? "us-east-1",
            prefix: ForkMacBackupServerForm.normalizedPrefix(kopia?.prefix ?? ""),
            accessKeyID: config.s3AccessKeyID ?? kopia?.accessKeyID,
            expectedUniqueID: nil,
            clientIdentity: identity,
            peer: peer.map { .init(stableID: $0.stableID, dnsName: $0.dnsName, hostName: $0.hostName) },
            serverFlavor: isMinIO ? .minio : .genericS3)

        let rules = translateRules(config.ignoreRules)
        let presets = ForkMacBackupPreset.normalized(ForkMacBackupPreset.defaultApplied + rules.presets)
        let paths = config.sourcePaths.isEmpty ? [home] : config.sourcePaths
        let sources = paths.map { path in
            ForkMacBackupSource(path: expand(path, home: home), presets: presets, customRules: rules.custom)
        }

        var chain = ForkMacBackupProfile.defaultChain(for: repository)
        if isMinIO, let index = chain.firstIndex(where: { $0.kind == .s3 }) { chain[index].title = "MinIO" }
        let profile = ForkMacBackupProfile(
            name: profileName, repository: repository, chain: chain, explanation: "",
            rules: .init(presets: presets, custom: rules.custom, iCloud: .fallback))

        return Result(repository: repository, profile: profile, sources: sources, presets: presets,
                      customRules: rules.custom, rulesAsPresets: rules.covered,
                      branIntervalHours: config.intervalHours, usesMagicDNS: usesMagicDNS,
                      branWasEnabled: config.isEnabled ?? true)
    }

    /// « ~/Documents » → the home's own path.
    static func expand(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + String(path.dropFirst()) }
        return path
    }

    /// A rule without its decorations, for comparing: no leading `/` or
    /// `**/`, no trailing `/`.
    static func canonical(_ rule: String) -> String {
        var text = rule.trimmingCharacters(in: .whitespaces)
        while text.hasPrefix("**/") { text.removeFirst(3) }
        while text.hasPrefix("/") { text.removeFirst() }
        while text.hasSuffix("/") { text.removeLast() }
        while text.hasSuffix("/**") { text.removeLast(3) }
        return text
    }

    /// Bran's rules as presets (a preset is on when one of its patterns is
    /// among Bran's rules) and the rest as free rules, in Bran's order.
    static func translateRules(_ rules: [String]) -> (presets: [ForkMacBackupPreset], custom: [String], covered: [String]) {
        var presets: [ForkMacBackupPreset] = []
        var custom: [String] = []
        var covered: [String] = []
        let index = Dictionary(ForkMacBackupPreset.allCases.flatMap { preset in
            preset.patterns.map { (canonical($0).lowercased(), preset) }
        }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        for rule in rules {
            let key = canonical(rule).lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            if let preset = index[key] {
                if !presets.contains(preset) { presets.append(preset) }
                covered.append(rule)
            } else {
                custom.append(rule.trimmingCharacters(in: .whitespaces))
            }
        }
        return (ForkMacBackupPreset.normalized(presets), custom, covered)
    }
}
