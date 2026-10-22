// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// What a person types for an address: « minio.tail.ts.net:9000 »,
/// « https://s3.eu-west-1.amazonaws.com », « [fd7a::1]:9000 », « 100.64.0.7 ».
struct ForkMacBackupEndpointInput: Equatable {
    var host: String
    var port: Int?
    /// From a scheme (`https://` → true, `http://` → false); nil when none.
    var tls: Bool?

    /// Nil for anything that is not a host with an optional port (a path, a
    /// space, a port out of range, an empty host).
    static func parse(_ text: String) -> ForkMacBackupEndpointInput? {
        var rest = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.isEmpty else { return nil }
        var tls: Bool?
        let lower = rest.lowercased()
        if lower.hasPrefix("https://") {
            tls = true
            rest.removeFirst("https://".count)
        } else if lower.hasPrefix("http://") {
            tls = false
            rest.removeFirst("http://".count)
        } else if lower.contains("://") {
            return nil
        }
        // A trailing slash is harmless; a real path is not an endpoint.
        while rest.hasSuffix("/") { rest.removeLast() }
        guard !rest.isEmpty, !rest.contains("/"), !rest.contains(where: \.isWhitespace), !rest.contains("@") else {
            return nil
        }

        var host = rest
        var port: Int?
        if rest.hasPrefix("[") {
            // [IPv6]:port
            guard let close = rest.firstIndex(of: "]") else { return nil }
            host = String(rest[rest.index(after: rest.startIndex)..<close])
            let after = rest[rest.index(after: close)...]
            if !after.isEmpty {
                guard after.hasPrefix(":"), let value = Int(after.dropFirst()) else { return nil }
                port = value
            }
        } else if rest.filter({ $0 == ":" }).count == 1, let colon = rest.firstIndex(of: ":") {
            host = String(rest[..<colon])
            guard let value = Int(rest[rest.index(after: colon)...]) else { return nil }
            port = value
        } else if rest.contains(":") {
            // A bare IPv6 address, no port.
            guard rest.allSatisfy({ $0.isHexDigit || $0 == ":" || $0 == "." }) else { return nil }
        }
        if let port, !(1...65_535).contains(port) { return nil }
        guard !host.isEmpty, host.allSatisfy({ $0.isLetter || $0.isNumber || "-._:%".contains($0) }) else { return nil }
        return ForkMacBackupEndpointInput(host: host.hasSuffix(".") ? String(host.dropLast()) : host, port: port, tls: tls)
    }

    /// Whether the host is a literal IP address (an IPv4 or an IPv6).
    var isIPAddress: Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 4, parts.allSatisfy({ Int($0).map { (0...255).contains($0) } ?? false }) { return true }
        return host.contains(":")
    }
}

/// The wizard's « Serveur » step (plan §11.2), what it validates and the
/// repository it makes. The secret key stays in memory and goes to the
/// Keychain only after a successful test.
struct ForkMacBackupServerForm: Equatable {
    enum Issue: String, CaseIterable {
        case address
        case port
        case bucket
        case region
        case accessKey
        case secretKey
    }

    var flavor: ForkMacBackupRepository.ServerFlavor = .minio
    var address = ""
    var port = ""
    var tls = false
    var bucket = ""
    var region = "us-east-1"
    var prefix = ""
    var accessKeyID = ""
    var secretKey = ""
    /// Chosen from the Tailscale suggestions.
    var peer: ForkMacBackupRepository.Peer?
    /// A secret already saved for this repository (an edit): it may stay empty.
    var hasSavedSecret = false

    /// The usual port of a flavour, when the address names none.
    static func defaultPort(flavor: ForkMacBackupRepository.ServerFlavor, tls: Bool) -> Int {
        flavor == .minio ? 9000 : (tls ? 443 : 80)
    }

    var endpoint: ForkMacBackupEndpointInput? { ForkMacBackupEndpointInput.parse(address) }

    /// The port typed, else the address's, else the flavour's.
    var effectivePort: Int? {
        let typed = port.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty {
            guard let value = Int(typed), (1...65_535).contains(value) else { return nil }
            return value
        }
        return endpoint?.port ?? Self.defaultPort(flavor: flavor, tls: tls)
    }

    var issues: [Issue] {
        var issues: [Issue] = []
        if endpoint == nil { issues.append(.address) }
        if effectivePort == nil { issues.append(.port) }
        if !Self.isValidBucket(bucket) { issues.append(.bucket) }
        if !Self.isValidRegion(region) { issues.append(.region) }
        if accessKeyID.trimmingCharacters(in: .whitespaces).isEmpty { issues.append(.accessKey) }
        if secretKey.isEmpty && !hasSavedSecret { issues.append(.secretKey) }
        return issues
    }

    var isValid: Bool { issues.isEmpty }

    /// S3's rules: 3 to 63 lower-case letters, digits, dots and dashes,
    /// starting and ending with a letter or a digit, not an IP address.
    static func isValidBucket(_ name: String) -> Bool {
        guard (3...63).contains(name.count),
              name.allSatisfy({ ($0.isASCII && ($0.isLowercase || $0.isNumber)) || $0 == "." || $0 == "-" }),
              let first = name.first, let last = name.last,
              first.isLetter || first.isNumber, last.isLetter || last.isNumber,
              !name.contains(".."), !name.contains(".-"), !name.contains("-.") else { return false }
        return !ForkMacBackupEndpointInput(host: name, port: nil, tls: nil).isIPAddress
    }

    /// « us-east-1 », « eu-west-3 », « garage »: letters, digits, dashes.
    static func isValidRegion(_ region: String) -> Bool {
        !region.isEmpty && region.count <= 64
            && region.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "-" || $0 == "_" }
    }

    /// « backups/mac » without a leading slash; Kopia joins it as is.
    static func normalizedPrefix(_ prefix: String) -> String {
        var text = prefix.trimmingCharacters(in: .whitespaces)
        while text.hasPrefix("/") { text.removeFirst() }
        return text
    }

    /// Fills the form from a repository (an edit, a profile, an import).
    init() {}

    init(repository: ForkMacBackupRepository, hasSavedSecret: Bool = false) {
        flavor = repository.serverFlavor
        address = repository.endpoint.host
        port = repository.endpoint.port.map(String.init) ?? ""
        tls = repository.endpoint.tls
        bucket = repository.bucket
        region = repository.region
        prefix = repository.prefix
        accessKeyID = repository.accessKeyID ?? ""
        peer = repository.peer
        self.hasSavedSecret = hasSavedSecret
    }

    /// The repository this form describes, keeping what the form does not
    /// edit (the lock, the identity, the addresses seen); nil while invalid
    /// (the secret key aside: it is not part of the repository).
    func repository(identity: ForkMacBackupRepository.Identity,
                    keeping existing: ForkMacBackupRepository? = nil) -> ForkMacBackupRepository? {
        guard let endpoint, let port = effectivePort, Self.isValidBucket(bucket), Self.isValidRegion(region),
              !accessKeyID.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        var observed = existing?.endpoint.observedIPs ?? []
        if endpoint.isIPAddress, !observed.contains(endpoint.host) { observed.append(endpoint.host) }
        var repository = ForkMacBackupRepository(
            kind: .s3,
            endpoint: .init(host: endpoint.host, port: port, tls: tls, observedIPs: observed),
            bucket: bucket, region: region.trimmingCharacters(in: .whitespaces),
            prefix: Self.normalizedPrefix(prefix),
            accessKeyID: accessKeyID.trimmingCharacters(in: .whitespaces),
            expectedUniqueID: nil, clientIdentity: identity, peer: peer, serverFlavor: flavor)
        // The lock stays only on the same storage.
        if let existing, existing.key == repository.key { repository.expectedUniqueID = existing.expectedUniqueID }
        return repository
    }

    /// Applies the scheme of a pasted URL and its port, so the fields agree.
    mutating func absorbAddress() {
        guard let parsed = endpoint else { return }
        if let tls = parsed.tls { self.tls = tls }
        if let port = parsed.port { self.port = String(port) }
        if parsed.port != nil || parsed.tls != nil { address = parsed.host }
    }

    /// Picks a Tailscale peer: its MagicDNS name, never its address.
    mutating func choose(_ peer: ForkMacBackupTailscalePeer) {
        address = peer.dnsName.isEmpty ? (peer.addresses.first ?? peer.hostName) : peer.dnsName
        self.peer = ForkMacBackupRepository.Peer(stableID: peer.stableID, dnsName: peer.dnsName, hostName: peer.hostName)
        if peer.hostName.lowercased().contains("minio") { flavor = .minio }
        // Tailscale already encrypts; MinIO behind it usually speaks HTTP.
        tls = false
    }
}

// MARK: - Tailscale

/// A Tailscale peer as `tailscale status --json` describes it.
struct ForkMacBackupTailscalePeer: Equatable, Identifiable {
    /// `ID`: stable across renames and address changes.
    var stableID: String
    /// `DNSName` without its final dot (« minio.tailef3e9f.ts.net »).
    var dnsName: String
    var hostName: String
    var addresses: [String]
    var online: Bool
    var os: String

    var id: String { stableID.isEmpty ? dnsName : stableID }

    /// The first label of the MagicDNS name, else the host name.
    var shortName: String { dnsName.split(separator: ".").first.map(String.init) ?? hostName }
}

enum ForkMacBackupTailscaleStatus {
    struct Snapshot: Equatable {
        var running: Bool
        var selfOnline: Bool
        var peers: [ForkMacBackupTailscalePeer]
    }

    /// Tolerant: unknown fields are ignored, a peer without a name is
    /// skipped; nil only when the text is not a status at all.
    static func parse(_ data: Data) -> Snapshot? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        guard root["BackendState"] != nil || root["Peer"] != nil || root["Self"] != nil else { return nil }
        let running = (root["BackendState"] as? String) == "Running"
        let selfOnline = ((root["Self"] as? [String: Any])?["Online"] as? Bool) ?? running
        var peers: [ForkMacBackupTailscalePeer] = []
        for value in ((root["Peer"] as? [String: Any]) ?? [:]).values {
            guard let peer = value as? [String: Any] else { continue }
            var dns = (peer["DNSName"] as? String) ?? ""
            if dns.hasSuffix(".") { dns.removeLast() }
            let host = (peer["HostName"] as? String) ?? ""
            guard !dns.isEmpty || !host.isEmpty else { continue }
            peers.append(ForkMacBackupTailscalePeer(stableID: (peer["ID"] as? String) ?? "", dnsName: dns,
                                                    hostName: host, addresses: (peer["TailscaleIPs"] as? [String]) ?? [],
                                                    online: (peer["Online"] as? Bool) ?? false,
                                                    os: (peer["OS"] as? String) ?? ""))
        }
        peers.sort { ($0.online ? 0 : 1, $0.shortName.lowercased()) < ($1.online ? 0 : 1, $1.shortName.lowercased()) }
        return Snapshot(running: running, selfOnline: selfOnline, peers: peers)
    }

    /// The peer a repository names: by stable ID first, then by DNS name,
    /// then by host name.
    static func match(_ peers: [ForkMacBackupTailscalePeer], stableID: String? = nil, dnsName: String? = nil,
                      hostName: String? = nil, address: String? = nil) -> ForkMacBackupTailscalePeer? {
        if let stableID, !stableID.isEmpty, let peer = peers.first(where: { $0.stableID == stableID }) { return peer }
        func clean(_ name: String) -> String { (name.hasSuffix(".") ? String(name.dropLast()) : name).lowercased() }
        if let dnsName, !dnsName.isEmpty, let peer = peers.first(where: { clean($0.dnsName) == clean(dnsName) }) {
            return peer
        }
        if let hostName, !hostName.isEmpty {
            let wanted = hostName.lowercased()
            if let peer = peers.first(where: { $0.hostName.lowercased() == wanted || $0.shortName.lowercased() == wanted }) {
                return peer
            }
        }
        if let address, !address.isEmpty, let peer = peers.first(where: { $0.addresses.contains(address) }) {
            return peer
        }
        return nil
    }
}
