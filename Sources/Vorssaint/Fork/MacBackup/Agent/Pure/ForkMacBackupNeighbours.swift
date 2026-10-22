// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Tailscale, read through its CLI (`tailscale status --json`, plan §3.9):
/// where the CLI is, and whether the repository's peer is online. Pure.
enum ForkMacBackupTailscale {
    /// The standalone CLI first (Homebrew or the « Install CLI » link),
    /// then the app's own binary, which acts as the CLI only with
    /// `TAILSCALE_BE_CLI=1` in its environment.
    static let candidates = [
        "/usr/local/bin/tailscale",
        "/opt/homebrew/bin/tailscale",
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
    ]

    struct Command: Equatable {
        var path: String
        var arguments: [String]
        var environment: [String: String]
    }

    /// The command to run; nil without Tailscale.
    static func command(isExecutable: (String) -> Bool) -> Command? {
        guard let path = candidates.first(where: isExecutable) else { return nil }
        // The wrapper script installed in /usr/local/bin execs the app's
        // binary: the variable is harmless for a real CLI, needed for the app.
        return Command(path: path, arguments: ["status", "--json"], environment: ["TAILSCALE_BE_CLI": "1"])
    }

    struct Status: Decodable, Equatable {
        struct Node: Decodable, Equatable {
            var id: String?
            var dnsName: String?
            var hostName: String?
            var online: Bool?

            enum CodingKeys: String, CodingKey {
                case id = "ID"
                case dnsName = "DNSName"
                case hostName = "HostName"
                case online = "Online"
            }
        }

        var backendState: String?
        var peers: [String: Node]

        enum CodingKeys: String, CodingKey {
            case backendState = "BackendState"
            case peers = "Peer"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            backendState = try container.decodeIfPresent(String.self, forKey: .backendState)
            peers = (try? container.decodeIfPresent([String: Node].self, forKey: .peers)) ?? [:]
        }
    }

    static func decode(_ data: Data) -> Status? {
        ForkMacBackupKopia.decode(Status.self, from: data)
    }

    /// The peer by its stable ID, else by its DNS name (MagicDNS, with or
    /// without the final dot, any case).
    static func peer(_ wanted: ForkMacBackupRepository.Peer, in status: Status) -> Status.Node? {
        let nodes = Array(status.peers.values)
        if !wanted.stableID.isEmpty, let byID = nodes.first(where: { $0.id == wanted.stableID }) { return byID }
        let name = normalized(wanted.dnsName)
        guard !name.isEmpty else { return nil }
        return nodes.first { normalized($0.dnsName ?? "") == name }
    }

    /// Online, offline, or nil when it cannot be told (Tailscale missing).
    /// Tailscale stopped or logged out: the peer is out of reach.
    static func peerOnline(_ wanted: ForkMacBackupRepository.Peer, status: Status?) -> Bool? {
        guard let status else { return nil }
        guard status.backendState == "Running" else { return false }
        guard let node = peer(wanted, in: status) else { return false }
        return node.online ?? false
    }

    private static func normalized(_ name: String) -> String {
        var text = name.lowercased().trimmingCharacters(in: .whitespaces)
        while text.hasSuffix(".") { text.removeLast() }
        return text
    }
}

/// Another Kopia writing to the same repository (KopiaUI, Bran, a CLI run
/// by hand): our lock cannot see it, so the processes are looked at (plan
/// §3.11). Pure: the process list and the config reading are passed in.
enum ForkMacBackupOtherEngine {
    /// Whether these arguments make a process that writes to a repository.
    /// KopiaUI itself writes nothing: the `kopia server start` it spawns
    /// (with its own `--config-file`) does, and is seen as such.
    static func isWriter(executable: String, arguments: [String]) -> Bool {
        guard (executable as NSString).lastPathComponent == "kopia" else { return false }
        let words = arguments.dropFirst().filter { !$0.hasPrefix("-") }
        guard let first = words.first else { return false }
        let second = words.dropFirst().first
        switch first {
        case "snapshot": return second == "create" || second == "expire" || second == "delete" || second == "migrate"
        case "server": return second == "start"
        case "maintenance": return second == "run"
        case "content", "blob", "index": return second == "rewrite" || second == "delete" || second == "gc" || second == "optimize"
        default: return false
        }
    }

    /// The config a Kopia process uses: `--config-file=…`, `--config-file …`,
    /// `KOPIA_CONFIG_PATH`, else Kopia's default one.
    static func configPath(arguments: [String], environment: [String: String], home: String) -> String {
        for (index, argument) in arguments.enumerated() {
            if argument.hasPrefix("--config-file=") { return String(argument.dropFirst("--config-file=".count)) }
            if argument == "--config-file", index + 1 < arguments.count { return arguments[index + 1] }
        }
        if let path = environment["KOPIA_CONFIG_PATH"], !path.isEmpty { return path }
        return (home as NSString).appendingPathComponent("Library/Application Support/kopia/repository.config")
    }

    /// The storage a `repository.config` points at.
    struct Storage: Decodable, Equatable {
        struct Inner: Decodable, Equatable {
            var type: String?
            var config: Config?
        }

        struct Config: Decodable, Equatable {
            var bucket: String?
            var prefix: String?
            var endpoint: String?
            var path: String?
        }

        var storage: Inner?
    }

    /// Whether that config is our repository: the same bucket, prefix and
    /// host (the port and TLS aside), or the same folder.
    static func sameRepository(configData: Data, as repository: ForkMacBackupRepository) -> Bool {
        guard let storage = ForkMacBackupKopia.decode(Storage.self, from: configData)?.storage,
              let config = storage.config else { return false }
        switch repository.kind {
        case .s3:
            guard storage.type == "s3", config.bucket == repository.bucket else { return false }
            guard trimmedPrefix(config.prefix ?? "") == trimmedPrefix(repository.prefix) else { return false }
            let host = (config.endpoint ?? "").split(separator: ":").first.map(String.init)?.lowercased() ?? ""
            return host.isEmpty || host == repository.endpoint.host.lowercased()
                || repository.endpoint.observedIPs.contains(host)
        case .filesystem:
            guard storage.type == "filesystem", let path = config.path, let wanted = repository.path else { return false }
            return (path as NSString).standardizingPath == (wanted as NSString).standardizingPath
        }
    }

    private static func trimmedPrefix(_ prefix: String) -> String {
        prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
