// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// « Exporter le diagnostic » (plan §8.1): a text a friend can read, without
/// a key, a password or a personal path beyond the sources' own.
enum ForkMacBackupDiagnostic {
    struct Input {
        var appName: String
        var appBuild: String
        var agentBuild: String?
        var agentAlive: Bool
        var engineVersion: String?
        var registration: ForkMacBackupAgentRegistration
        var fullDiskAccess: Bool
        var presentation: ForkMacBackupPresentation
        var repository: ForkMacBackupRepository?
        var profileName: String?
        var sources: [ForkMacBackupSource]
        var settings: [String: String]
        var now: Date
    }

    static func text(_ input: Input) -> String {
        var lines: [String] = []
        func add(_ label: String, _ value: String?) { lines.append("\(label): \(value ?? "-")") }
        let iso = ISO8601DateFormatter()
        lines.append("# Mac Backup diagnostic")
        add("generated", iso.string(from: input.now))
        add("app", "\(input.appName) \(input.appBuild)")
        add("agent", "\(input.agentAlive ? "running" : "not running") \(input.agentBuild ?? "")")
        add("engine", input.engineVersion)
        add("background", input.registration.rawValue)
        add("fullDiskAccess", input.fullDiskAccess ? "yes" : "no")
        lines.append("")
        lines.append("## State")
        add("phase", describe(input.presentation.phase))
        add("tone", input.presentation.tone.rawValue)
        if let error = input.presentation.lastError {
            add("lastError", "\(error.cause.rawValue) node=\(error.nodeID ?? "-") at=\(iso.string(from: error.at))")
            add("lastErrorMessage", error.message.map(scrub))
        }
        for node in input.presentation.chain {
            add("node.\(node.id)", "\(node.state.rawValue) \(node.latencyMs.map { "\($0) ms" } ?? "")"
                + (node.checkedAt.map { " checked=\(iso.string(from: $0))" } ?? ""))
        }
        for source in input.presentation.sources {
            add("source", "\(scrubHome(source.path)) state=\(source.state.rawValue) last=\(source.last.map { iso.string(from: $0.date) } ?? "-") level=\(source.last.map { "\($0.level)" } ?? "-") complete=\(source.lastComplete.map { iso.string(from: $0.date) } ?? "-")")
        }
        lines.append("")
        lines.append("## Repository")
        if let repository = input.repository {
            add("profile", input.profileName)
            add("kind", repository.kind.rawValue)
            add("endpoint", repository.endpoint.hostAndPort)
            add("tls", repository.endpoint.tls ? "yes" : "no")
            add("observedIPs", repository.endpoint.observedIPs.joined(separator: ", "))
            add("bucket", repository.bucket)
            add("prefix", repository.prefix)
            add("region", repository.region)
            add("flavor", repository.serverFlavor.rawValue)
            add("uniqueID", repository.expectedUniqueID.map(ForkMacBackupRepository.shortID))
            add("identity", repository.clientIdentity.description)
            add("peer", repository.peer.map { "\($0.hostName) \($0.dnsName)" })
        } else {
            lines.append("not connected")
        }
        lines.append("")
        lines.append("## Content")
        for source in input.sources {
            add("source", "\(scrubHome(source.path)) presets=\(source.presets.map(\.rawValue).joined(separator: ",")) rules=\(source.customRules.count)")
        }
        lines.append("")
        lines.append("## Settings")
        for key in input.settings.keys.sorted() {
            add(key, input.settings[key])
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func describe(_ phase: ForkMacBackupPhase) -> String {
        guard let data = try? ForkMacBackupJSON.encoder.encode(phase), let text = String(data: data, encoding: .utf8) else {
            return "?"
        }
        return text
    }

    /// The home folder as `~`, anywhere in a text.
    static func scrubHome(_ text: String, home: String = NSHomeDirectory()) -> String {
        guard !home.isEmpty else { return text }
        return text.replacingOccurrences(of: home, with: "~")
    }

    /// Kopia's messages may quote a URL with credentials or a path: the
    /// user part of a URL and the home are removed.
    static func scrub(_ text: String) -> String {
        var result = scrubHome(text)
        while let range = result.range(of: #"://[^/\s@]+@"#, options: .regularExpression) {
            result.replaceSubrange(range, with: "://***@")
        }
        return result
    }
}

/// « Ouvrir un Terminal configuré » (plan §11.1): a script that points
/// Kopia at this Mac's own config, cache and logs, and asks for the
/// password and the secret key instead of carrying them.
enum ForkMacBackupTerminalScript {
    static func text(engineBinary: String, config: String, cache: String, logs: String, accessKeyID: String?,
                     passwordPrompt: String, secretPrompt: String, banner: String) -> String {
        var lines = ["#!/bin/zsh",
                     "export KOPIA_CONFIG_PATH=\(quoted(config))",
                     "export KOPIA_CACHE_DIRECTORY=\(quoted(cache))",
                     "export KOPIA_LOG_DIR=\(quoted(logs))",
                     "export KOPIA_CHECK_FOR_UPDATES=false",
                     "export PATH=\(quoted((engineBinary as NSString).deletingLastPathComponent)):\"$PATH\"",
                     "read -rs \"KOPIA_PASSWORD?\(escapedPrompt(passwordPrompt)) \"; echo; export KOPIA_PASSWORD"]
        if let accessKeyID, !accessKeyID.isEmpty {
            lines.append("export AWS_ACCESS_KEY_ID=\(quoted(accessKeyID))")
            lines.append("read -rs \"AWS_SECRET_ACCESS_KEY?\(escapedPrompt(secretPrompt)) \"; echo; export AWS_SECRET_ACCESS_KEY")
        }
        lines.append("echo \(quoted(banner))")
        // A new interactive shell keeps the variables above: `kopia` is on the PATH.
        lines.append("exec /bin/zsh -i")
        return lines.joined(separator: "\n") + "\n"
    }

    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func escapedPrompt(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$").replacingOccurrences(of: "`", with: "\\`")
    }
}
