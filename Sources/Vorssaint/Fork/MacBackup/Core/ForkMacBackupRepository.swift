// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Everything that describes ONE Kopia repository, without a secret (the
/// password and the S3 secret key live in the Keychain, `ForkMacBackupSecrets`).
/// Machine state: saved under `ForkDefaultsKey.macBackupRepository` (JSON),
/// never in the settings backup.
struct ForkMacBackupRepository: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case s3
        /// An external disk or a mounted share (phase 3).
        case filesystem
    }

    /// Which health probes the S3 server answers.
    enum ServerFlavor: String, Codable, CaseIterable {
        case minio
        case genericS3
    }

    struct Endpoint: Codable, Equatable {
        /// A DNS name preferred (MagicDNS), else an address.
        var host: String
        var port: Int?
        var tls: Bool
        /// Addresses seen for `host`, for display only: an address change
        /// breaks nothing, the unique ID check catches a wrong repository.
        var observedIPs: [String]

        init(host: String, port: Int? = nil, tls: Bool = true, observedIPs: [String] = []) {
            self.host = host
            self.port = port
            self.tls = tls
            self.observedIPs = observedIPs
        }

        /// `host:port` as Kopia's `--endpoint` takes it.
        var hostAndPort: String {
            guard let port else { return host }
            return host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
        }
    }

    /// Kopia's `user@host`: the same identity keeps one continuous history.
    struct Identity: Codable, Equatable {
        var userName: String
        var hostName: String

        var description: String { "\(userName)@\(hostName)" }

        /// `user@host`; nil when either side is missing.
        init?(parsing text: String) {
            let parts = text.split(separator: "@", maxSplits: 1).map(String.init)
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
            userName = parts[0]
            hostName = parts[1]
        }

        init(userName: String, hostName: String) {
            self.userName = userName
            self.hostName = hostName
        }
    }

    /// The Tailscale peer that serves the endpoint, found by its stable ID
    /// first, then by its DNS name.
    struct Peer: Codable, Equatable {
        var stableID: String
        var dnsName: String
        var hostName: String
    }

    var kind: Kind
    var endpoint: Endpoint
    var bucket: String
    var region: String
    var prefix: String
    /// The S3 access key's ID (not a secret: it is printed in the recovery
    /// kit). The secret key is in the Keychain.
    var accessKeyID: String?
    /// `repository status --json` › `uniqueIDHex`: the lock on the right
    /// repository. Nil until « C'est bien mon dépôt ».
    var expectedUniqueID: String?
    var clientIdentity: Identity
    var peer: Peer?
    var serverFlavor: ServerFlavor
    /// For `.filesystem`: the folder that holds the repository.
    var path: String?

    init(kind: Kind = .s3, endpoint: Endpoint, bucket: String, region: String = "us-east-1", prefix: String = "",
         accessKeyID: String? = nil, expectedUniqueID: String? = nil, clientIdentity: Identity,
         peer: Peer? = nil, serverFlavor: ServerFlavor = .genericS3, path: String? = nil) {
        self.kind = kind
        self.endpoint = endpoint
        self.bucket = bucket
        self.region = region
        self.prefix = prefix
        self.accessKeyID = accessKeyID
        self.expectedUniqueID = expectedUniqueID
        self.clientIdentity = clientIdentity
        self.peer = peer
        self.serverFlavor = serverFlavor
        self.path = path
    }

    /// Names the repository's own folder (`repo/<key>/`) and its Keychain
    /// accounts. Stable across an endpoint change (IP → MagicDNS): only what
    /// designates the storage itself goes in.
    var key: String {
        let designation: String
        switch kind {
        case .s3: designation = "s3|\(bucket)|\(prefix)|\(region)"
        case .filesystem: designation = "fs|\(path ?? "")"
        }
        return kind.rawValue + "-" + ForkMacBackupHash.fnv1a64Hex(designation)
    }

    /// Whether `status` is the expected repository: no expectation yet
    /// accepts anything (the wizard asks the person to lock it).
    func accepts(uniqueID: String) -> Bool {
        guard let expected = expectedUniqueID, !expected.isEmpty else { return true }
        return expected.lowercased() == uniqueID.lowercased()
    }

    /// « ac29…f120 », for a line that has no room for 64 characters.
    static func shortID(_ id: String) -> String {
        guard id.count > 10 else { return id }
        return "\(id.prefix(4))…\(id.suffix(4))"
    }
}

/// A 64-bit FNV-1a, enough to name a folder; never for security.
enum ForkMacBackupHash {
    static func fnv1a64Hex(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}

/// One step of the chain between this Mac and the storage, as a profile
/// draws it (Settings › « Ma chaîne ») and as the island lists its dots.
struct ForkMacBackupChainNode: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable {
        case mac
        case network
        case tailscale
        /// The endpoint's DNS name.
        case name
        case s3
        case repository
        case proxmox
        case nas
        case cloud

        /// The SF Symbol drawn when the profile names none.
        var defaultSymbol: String {
            switch self {
            case .mac: return "laptopcomputer"
            case .network: return "wifi"
            case .tailscale: return "lock.shield"
            case .name: return "globe"
            case .s3: return "server.rack"
            case .repository: return "archivebox"
            case .proxmox: return "cpu"
            case .nas: return "externaldrive.connected.to.line.below"
            case .cloud: return "cloud"
            }
        }

        func title(_ text: ForkMacBackupStrings) -> String {
            switch self {
            case .mac: return text.nodeMac
            case .network: return text.nodeNetwork
            case .tailscale: return text.nodeTailscale
            case .name: return text.nodeName
            case .s3: return text.nodeS3
            case .repository: return text.nodeRepository
            case .proxmox: return text.nodeProxmox
            case .nas: return text.nodeNAS
            case .cloud: return text.nodeCloud
            }
        }
    }

    /// How a node is checked; nil: drawn, never probed.
    struct Probe: Codable, Equatable {
        enum Kind: String, Codable, CaseIterable {
            /// Engine installed, Full Disk Access, cache room, agent approved.
            case macReadiness
            case network
            case tailscalePeer
            case nameResolution
            case s3Endpoint
            /// `/minio/health/live`, `/ready`, `/cluster`.
            case minioHealth
            /// `repository status --json` › `uniqueIDHex`.
            case repositoryIdentity
            /// A read-only command over SSH (`target` = the alias), phase 3.
            case sshReadOnly
        }

        var kind: Kind
        var target: String?
        var command: String?

        init(kind: Kind, target: String? = nil, command: String? = nil) {
            self.kind = kind
            self.target = target
            self.command = command
        }
    }

    /// Stable within a profile: `ForkMacBackupPresentation.ChainStatus`
    /// refers to it.
    var id: String
    var kind: Kind
    /// Empty: the kind's own word (`Kind.title`).
    var title: String
    /// « minio.tailnet.ts.net:9000 », « LXC 111 »…
    var detail: String
    var symbol: String
    var probe: Probe?

    init(id: String, kind: Kind, title: String = "", detail: String = "", symbol: String? = nil, probe: Probe? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.symbol = symbol ?? kind.defaultSymbol
        self.probe = probe
    }

    func displayTitle(_ text: ForkMacBackupStrings) -> String {
        title.isEmpty ? kind.title(text) : title
    }
}

/// A `.swishsaint-backup-profile`: what pre-fills the connection wizard and
/// draws « Ma chaîne », without a secret and without anything machine
/// specific beyond the repository template. Martial's own lives outside the
/// Git repository; friends write theirs for their S3.
struct ForkMacBackupProfile: Codable, Equatable {
    static let fileExtension = "swishsaint-backup-profile"
    static let formatVersion = 1

    struct Rules: Codable, Equatable {
        /// The presets applied (`ForkMacBackupPreset`), in their order.
        var presets: [ForkMacBackupPreset]
        /// Free rules, in Kopia's ignore syntax.
        var custom: [String]
        var iCloud: ForkMacBackupICloudMode

        init(presets: [ForkMacBackupPreset] = ForkMacBackupPreset.defaultApplied, custom: [String] = [],
             iCloud: ForkMacBackupICloudMode = .fallback) {
            self.presets = presets
            self.custom = custom
            self.iCloud = iCloud
        }
    }

    var formatVersion: Int
    var name: String
    /// The repository to connect to; its `expectedUniqueID` locks it when
    /// known.
    var repository: ForkMacBackupRepository
    var chain: [ForkMacBackupChainNode]
    /// One sentence under the drawing (« Ton Mac chiffre tout, l'envoie par
    /// Tailscale à MinIO… »), in the profile author's words.
    var explanation: String
    var rules: Rules

    init(name: String, repository: ForkMacBackupRepository, chain: [ForkMacBackupChainNode], explanation: String = "",
         rules: Rules = Rules(), formatVersion: Int = ForkMacBackupProfile.formatVersion) {
        self.formatVersion = formatVersion
        self.name = name
        self.repository = repository
        self.chain = chain
        self.explanation = explanation
        self.rules = rules
    }

    /// The chain a profile-less S3 gets: this Mac, then the server.
    static func defaultChain(for repository: ForkMacBackupRepository) -> [ForkMacBackupChainNode] {
        var nodes = [ForkMacBackupChainNode(id: "mac", kind: .mac, probe: .init(kind: .macReadiness)),
                     ForkMacBackupChainNode(id: "network", kind: .network, probe: .init(kind: .network))]
        if let peer = repository.peer {
            nodes.append(ForkMacBackupChainNode(id: "tailscale", kind: .tailscale, detail: peer.hostName,
                                                probe: .init(kind: .tailscalePeer, target: peer.stableID)))
        }
        let serverProbe: ForkMacBackupChainNode.Probe.Kind = repository.serverFlavor == .minio ? .minioHealth : .s3Endpoint
        nodes.append(ForkMacBackupChainNode(id: "server", kind: .s3, detail: repository.endpoint.hostAndPort,
                                            probe: .init(kind: serverProbe, target: repository.endpoint.hostAndPort)))
        nodes.append(ForkMacBackupChainNode(id: "repository", kind: .repository, detail: repository.bucket,
                                            probe: .init(kind: .repositoryIdentity)))
        return nodes
    }

    /// A profile file's content; nil for anything else or a newer format.
    static func decode(_ data: Data) -> ForkMacBackupProfile? {
        guard let profile = try? ForkMacBackupJSON.decoder.decode(ForkMacBackupProfile.self, from: data),
              profile.formatVersion <= formatVersion else { return nil }
        return profile
    }
}
