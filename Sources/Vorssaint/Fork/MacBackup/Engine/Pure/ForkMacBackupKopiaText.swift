// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Kopia's text outputs, read robustly: the commands that have no `--json`
/// (`blob stats`, `restore` progress, `snapshot expire`), the server's
/// start-up lines, and the error lines of a failed call. Every parser takes
/// what it recognises and ignores the rest (a new warning line, a changed
/// spacing), and returns nil rather than a guess.
enum ForkMacBackupKopiaText {
    // MARK: Lines

    /// Splits on `\n` and on the `\r` Kopia uses to redraw a progress line;
    /// trims each line, drops the empty ones.
    static func lines(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: Sizes

    /// « 212.7 MB », « 67.7 KB », « 0 B », « 1.5 GiB », « 946878887 »: bytes.
    /// Kopia prints base-10 units by default (`KOPIA_BYTES_STRING_BASE_2`
    /// switches to KiB, MiB…), both are read.
    static func bytes(_ text: String) -> Int64? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let whole = Int64(trimmed) { return whole }
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        let number: Substring
        let unit: Substring
        if parts.count == 2 {
            number = parts[0]
            unit = parts[1]
        } else if parts.count == 1, let index = trimmed.firstIndex(where: { $0.isLetter }) {
            number = trimmed[..<index]
            unit = trimmed[index...]
        } else {
            return nil
        }
        guard let value = Double(number), value >= 0, let scale = unitScale(String(unit)) else { return nil }
        return Int64((value * scale).rounded())
    }

    private static func unitScale(_ unit: String) -> Double? {
        let decimal: [String: Double] = ["B": 1, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12, "PB": 1e15]
        let binary: [String: Double] = ["KIB": 1024, "MIB": 1_048_576, "GIB": 1_073_741_824,
                                        "TIB": 1_099_511_627_776, "PIB": 1_125_899_906_842_624]
        let upper = unit.uppercased()
        return decimal[upper] ?? binary[upper]
    }

    // MARK: blob stats

    /// `blob stats` (`--raw` or not): « Count: 122 » and « Total: 946878887 »
    /// (or « Total: 212.7 MB », less exact). Nil without both.
    static func blobStats(_ text: String, measuredAt: Date) -> ForkMacBackupBlobStats? {
        var count: Int64?
        var total: Int64?
        for line in lines(text) {
            if let value = field("Count", in: line) { count = Int64(value) }
            if let value = field("Total", in: line) { total = bytes(value) }
        }
        guard let count, let total else { return nil }
        return ForkMacBackupBlobStats(blobCount: count, totalBytes: total, measuredAt: measuredAt)
    }

    /// The value of « Name: value » at the start of a line.
    private static func field(_ name: String, in line: String) -> String? {
        let prefix = name + ":"
        guard line.hasPrefix(prefix) else { return nil }
        return line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
    }

    // MARK: restore

    /// One `restore --progress` reading.
    struct RestoreProgress: Equatable {
        var processedEntries: Int64
        var processedBytes: Int64
        /// Kopia's total; nil while it does not know (a single file: « of 0 (0 B) »).
        var totalEntries: Int64?
        var totalBytes: Int64?
        var skippedEntries: Int64
        var skippedBytes: Int64
        /// « (54.2%) » when printed.
        var percent: Double?
    }

    /// The last readable `Processed N (X) of M (Y) …` of `text`.
    static func restoreProgress(_ text: String) -> RestoreProgress? {
        for line in lines(text).reversed() {
            if let progress = restoreProgressLine(line) { return progress }
        }
        return nil
    }

    /// `Processed 1 (58.2 GB) of 1 (107.4 GB) 646 MB/s (54.2%) remaining 1m15s.`
    /// `Processed 3121 (20 B) of 3120 (67.7 KB), skipped 2999 (67.7 KB).`
    static func restoreProgressLine(_ line: String) -> RestoreProgress? {
        guard line.hasPrefix("Processed ") else { return nil }
        let pairs = countSizePairs(in: line)
        guard let processed = pairs.first else { return nil }
        let total = pairs.count > 1 ? pairs[1] : nil
        var skipped: (count: Int64, bytes: Int64)?
        if let range = line.range(of: "skipped ") {
            skipped = countSizePairs(in: String(line[range.lowerBound...])).first
        }
        var percent: Double?
        if let close = line.range(of: "%)"), let open = line[..<close.lowerBound].lastIndex(of: "(") {
            percent = Double(line[line.index(after: open)..<close.lowerBound])
        }
        let knownTotal = total.flatMap { $0.bytes > 0 || $0.count > 0 ? $0 : nil }
        return RestoreProgress(processedEntries: processed.count, processedBytes: processed.bytes,
                               totalEntries: knownTotal?.count, totalBytes: knownTotal?.bytes,
                               skippedEntries: skipped?.count ?? 0, skippedBytes: skipped?.bytes ?? 0,
                               percent: percent)
    }

    /// The `N (size)` pairs of a line, in order.
    private static func countSizePairs(in line: String) -> [(count: Int64, bytes: Int64)] {
        var pairs: [(Int64, Int64)] = []
        var rest = Substring(line)
        while let open = rest.firstIndex(of: "("), let close = rest[open...].firstIndex(of: ")") {
            let before = rest[..<open].trimmingCharacters(in: .whitespaces)
            let inside = String(rest[rest.index(after: open)..<close])
            if let countWord = before.split(separator: " ").last, let count = Int64(countWord),
               let size = bytes(inside) {
                pairs.append((count, size))
            }
            rest = rest[rest.index(after: close)...]
        }
        return pairs
    }

    /// The closing `Restored 3000 files, 121 directories and 0 symbolic links (67.7 KB)[, skipped 2999 (67.7 KB)].`
    struct RestoreSummary: Equatable {
        var files: Int64
        var directories: Int64
        var symlinks: Int64
        var bytes: Int64
        var skippedFiles: Int64
        var skippedBytes: Int64
    }

    static func restoreSummary(_ text: String) -> RestoreSummary? {
        guard let line = lines(text).last(where: { $0.hasPrefix("Restored ") }) else { return nil }
        let words = line.replacingOccurrences(of: ",", with: " ").split(separator: " ").map(String.init)
        func number(before noun: String) -> Int64? {
            guard let index = words.firstIndex(where: { $0.hasPrefix(noun) }), index > 0 else { return nil }
            return Int64(words[index - 1])
        }
        guard let files = number(before: "file") else { return nil }
        var bytes: Int64 = 0
        if let open = line.firstIndex(of: "("), let close = line[open...].firstIndex(of: ")") {
            bytes = self.bytes(String(line[line.index(after: open)..<close])) ?? 0
        }
        var skipped: (count: Int64, bytes: Int64)?
        if let range = line.range(of: "skipped ") {
            skipped = countSizePairs(in: String(line[range.lowerBound...])).first
        }
        return RestoreSummary(files: files, directories: number(before: "director") ?? 0,
                              symlinks: number(before: "symbolic") ?? 0, bytes: bytes,
                              skippedFiles: skipped?.count ?? 0, skippedBytes: skipped?.bytes ?? 0)
    }

    // MARK: snapshot verify

    /// `snapshot verify --json`: stdout's result.
    struct VerifyResult: Decodable, Equatable {
        struct Stats: Decodable, Equatable {
            var processedObjectCount: Int64?
            var processedBytes: Int64?
            var readFileCount: Int64?
            var readBytes: Int64?
            var expectedTotalObjectCount: Int64?
            var expectedTotalFileCount: Int64?
            var expectedTotalBytes: Int64?
        }

        var stats: Stats?
        var errorCount: Int64?
    }

    static func verifyResult(_ data: Data) -> VerifyResult? {
        ForkMacBackupKopia.decode(VerifyResult.self, from: data)
    }

    /// A stderr progress line of `snapshot verify --json`
    /// (`{"processedObjectCount":…,"expectedTotalObjectCount":…}`).
    static func verifyProgress(_ line: String) -> ForkMacBackupVerifyProgress? {
        guard line.hasPrefix("{"), let stats = ForkMacBackupKopia.decode(VerifyResult.Stats.self, from: Data(line.utf8)),
              let checked = stats.processedObjectCount else { return nil }
        let total = stats.expectedTotalObjectCount.flatMap { $0 > 0 ? $0 : nil }
        return ForkMacBackupVerifyProgress(checked: checked, total: total)
    }

    // MARK: snapshot expire

    /// « 4 snapshot(s) of user@host:/path would be deleted. »: 4.
    static func expireCount(_ text: String) -> Int? {
        for line in lines(text) where line.contains("snapshot(s)") {
            if let first = line.split(separator: " ").first, let count = Int(first) { return count }
        }
        return nil
    }

    // MARK: server start

    enum ServerLine: Equatable {
        /// `SERVER CONTROL PASSWORD: …` (only with a random one).
        case controlPassword(String)
        /// `SERVER ADDRESS: unix+http://kopia.sock`: the socket answers.
        case address(String)
        case other(String)
    }

    static func serverLine(_ line: String) -> ServerLine {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if let value = field("SERVER CONTROL PASSWORD", in: trimmed) { return .controlPassword(value) }
        if let value = field("SERVER ADDRESS", in: trimmed) { return .address(value) }
        return .other(trimmed)
    }

    // MARK: Errors

    /// The line that says what went wrong, from a failed call's stderr: the
    /// last `ERROR …` / `kopia: error: …` line, else the last line.
    static func errorLine(_ stderr: String) -> String {
        let all = lines(stderr).filter { !$0.hasPrefix("{") }
        if let line = all.last(where: { $0.hasPrefix("ERROR") || $0.hasPrefix("kopia: error:") || $0.hasPrefix("error") }) {
            for prefix in ["kopia: error:", "ERROR", "error:"] where line.hasPrefix(prefix) {
                return line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            }
            return line
        }
        return all.last ?? ""
    }

    /// What a Kopia failure means for the person (`ForkMacBackupEngineError`).
    static func classify(stderr: String, exitCode: Int32) -> ForkMacBackupEngineError {
        let message = errorLine(stderr)
        let text = stderr.lowercased()
        func has(_ needles: String...) -> Bool { needles.contains { text.contains($0) } }
        if has("invalid repository password", "password prompt error", "invalid password") {
            return .authentication
        }
        if has("access denied", "the access key id you provided does not exist", "invalidaccesskeyid",
               "signaturedoesnotmatch", "the request signature we calculated does not match",
               "invalid access key", "403 forbidden") {
            return .authentication
        }
        if has("repository not initialized") {
            return .notConnected
        }
        if has("repository is not connected", "not_connected", "error loading config file") {
            return .notConnected
        }
        if has("connection refused", "no such host", "i/o timeout", "network is unreachable", "dial tcp",
               "no route to host", "connection reset", "tls: ", "x509:", "context deadline exceeded",
               "server misbehaving", "the specified bucket does not exist", "nosuchbucket") {
            return .unreachable(message)
        }
        return .kopia(exitCode: exitCode, message: message)
    }

    /// Whether `repository connect` found an empty storage (create it).
    static func isNotInitialized(_ stderr: String) -> Bool {
        stderr.lowercased().contains("repository not initialized")
    }
}
