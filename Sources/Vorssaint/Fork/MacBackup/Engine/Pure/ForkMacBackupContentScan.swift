// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// What a source really weighs on this Mac (decision 1 of 22/10): sizes
/// are ALLOCATED sizes (`totalFileAllocatedSize`), never the logical size a
/// sparse disk image announces. Also finds the sparse disk images to leave
/// out (`ForkMacBackupPreset.sparseDiskImages`) and the iCloud files with no
/// data on the Mac (plan §4.4), and turns them into the run's ignore rules.
///
/// Foundation only, synchronous, cancellable between two files: run it on
/// a utility queue, never on the main thread.
struct ForkMacBackupDiskUsage: Equatable {
    struct Folder: Equatable {
        /// Relative to the scanned root, « Library » or « Library/Caches ».
        var relativePath: String
        var allocatedBytes: Int64
        var files: Int64
        var depth: Int { relativePath.split(separator: "/").count }
    }

    /// A file that announces much more than it holds (Docker's
    /// `Docker.raw`, Apple Container's `.ext4`, a VM disk).
    struct SparseImage: Equatable {
        var relativePath: String
        var logicalBytes: Int64
        var allocatedBytes: Int64
    }

    var allocatedBytes: Int64 = 0
    var logicalBytes: Int64 = 0
    var files: Int64 = 0
    var directories: Int64 = 0
    /// What the rules leave out: the bytes of the excluded FILES (an
    /// excluded folder is not entered, so its size stays unknown here) and
    /// how many entries, files and folders, were excluded.
    var excludedAllocatedBytes: Int64 = 0
    var excludedEntries: Int64 = 0
    /// The biggest folders at depth 1 and 2, biggest first.
    var folders: [Folder] = []
    var sparseImages: [SparseImage] = []
    /// Entries the scan could not read (permissions).
    var unreadable: Int64 = 0
    var canceled = false
}

enum ForkMacBackupContentScan {
    /// « ≥ 10 GB » (decimal, as Finder counts).
    static let sparseMinimumLogicalBytes: Int64 = 10_000_000_000
    /// `SF_DATALESS` of `<sys/stat.h>`: a file (or folder) whose data is in
    /// the cloud only.
    static let datalessFlag: UInt32 = 0x4000_0000

    /// A sparse disk image: at least 10 GB announced, less than half written.
    static func isSparseImage(logicalBytes: Int64, allocatedBytes: Int64) -> Bool {
        logicalBytes >= sparseMinimumLogicalBytes && allocatedBytes * 2 < logicalBytes
    }

    static func isDataless(flags: UInt32) -> Bool { flags & datalessFlag != 0 }

    // MARK: Scanning

    /// Walks `root` (packages included, symlinks not followed), skipping
    /// what `matcher` excludes. `topFolders`: how many folders per depth.
    static func scan(root: URL, matcher: ForkMacBackupIgnoreMatcher = .init(rules: []), topFolders: Int = 10,
                     isCanceled: () -> Bool = { false }) -> ForkMacBackupDiskUsage {
        var usage = ForkMacBackupDiskUsage()
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey,
                                      .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        var unreadable: Int64 = 0
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [],
                                                          errorHandler: { _, _ in unreadable += 1; return true }) else {
            usage.unreadable = 1
            return usage
        }
        var byFolder: [String: (bytes: Int64, files: Int64)] = [:]
        let rootPath = root.standardizedFileURL.path
        while let url = walker.nextObject() as? URL {
            if isCanceled() {
                usage.canceled = true
                break
            }
            let relative = relativePath(of: url, root: rootPath)
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else {
                unreadable += 1
                continue
            }
            let isDirectory = values.isDirectory == true && values.isSymbolicLink != true
            if matcher.excludes(relative, isDirectory: isDirectory) {
                usage.excludedEntries += 1
                if isDirectory {
                    walker.skipDescendants()
                } else {
                    usage.excludedAllocatedBytes += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                }
                continue
            }
            if isDirectory {
                usage.directories += 1
                continue
            }
            let allocated = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            let logical = Int64(values.fileSize ?? 0)
            usage.files += 1
            usage.allocatedBytes += allocated
            usage.logicalBytes += logical
            if values.isRegularFile == true, isSparseImage(logicalBytes: logical, allocatedBytes: allocated) {
                usage.sparseImages.append(.init(relativePath: relative, logicalBytes: logical, allocatedBytes: allocated))
            }
            let parts = relative.split(separator: "/")
            if parts.count > 1 {
                let first = String(parts[0])
                byFolder[first, default: (0, 0)].bytes += allocated
                byFolder[first, default: (0, 0)].files += 1
                if parts.count > 2 {
                    let second = first + "/" + parts[1]
                    byFolder[second, default: (0, 0)].bytes += allocated
                    byFolder[second, default: (0, 0)].files += 1
                }
            }
        }
        usage.unreadable += unreadable
        let all = byFolder.map { ForkMacBackupDiskUsage.Folder(relativePath: $0.key, allocatedBytes: $0.value.bytes,
                                                                files: $0.value.files) }
        for depth in 1...2 {
            usage.folders += all.filter { $0.depth == depth }
                .sorted { $0.allocatedBytes != $1.allocatedBytes ? $0.allocatedBytes > $1.allocatedBytes
                    : $0.relativePath < $1.relativePath }
                .prefix(topFolders)
        }
        usage.sparseImages.sort { $0.logicalBytes > $1.logicalBytes }
        return usage
    }

    /// The cloud-only entries below `root` (iCloud Drive's
    /// `Library/Mobile Documents`), relative to `root`; a folder whose
    /// listing is itself in the cloud ends with « / » and is not entered
    /// (entering it would download its listing).
    static func dataless(root: URL, isCanceled: () -> Bool = { false }) -> [String] {
        let rootPath = root.standardizedFileURL.path
        var found: [String] = []
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                          options: [], errorHandler: { _, _ in true }) else { return [] }
        while let url = walker.nextObject() as? URL {
            if isCanceled() { break }
            var info = stat()
            guard lstat(url.path, &info) == 0 else { continue }
            let isDirectory = (info.st_mode & S_IFMT) == S_IFDIR
            guard isDataless(flags: info.st_flags) else { continue }
            let relative = relativePath(of: url, root: rootPath)
            if isDirectory {
                walker.skipDescendants()
                found.append(relative + "/")
            } else {
                found.append(relative)
            }
        }
        return found.sorted()
    }

    static func relativePath(of url: URL, root rootPath: String) -> String {
        let path = url.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if path.hasPrefix(prefix) { return String(path.dropFirst(prefix.count)) }
        let resolvedRoot = URL(fileURLWithPath: rootPath).resolvingSymlinksInPath().path
        let resolved = url.resolvingSymlinksInPath().path
        let resolvedPrefix = resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/"
        return resolved.hasPrefix(resolvedPrefix) ? String(resolved.dropFirst(resolvedPrefix.count)) : url.lastPathComponent
    }

    // MARK: Rules

    /// One path, relative to the source, as an anchored Kopia ignore rule
    /// matching only it: `/a/b c/x\*y.txt` (wildcards escaped, a folder
    /// marked by its final « / »).
    static func ignoreRule(relativePath: String, isDirectory: Bool) -> String {
        let clean = ForkMacBackupFailureList.normalize(relativePath)
        var rule = "/" + clean.split(separator: "/").map { escape(String($0)) }.joined(separator: "/")
        if isDirectory { rule += "/" }
        return rule
    }

    /// Kopia's wildcard syntax (`internal/wcmatch`): `\`, `*`, `?` and `[`
    /// are escaped with a backslash, and so is a trailing space (Kopia trims
    /// spaces otherwise).
    static func escape(_ component: String) -> String {
        var escaped = ""
        for character in component {
            if "\\*?[".contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        if escaped.hasSuffix(" ") {
            escaped.removeLast()
            escaped += "\\ "
        }
        return escaped
    }

    /// The run's extra rules for a source (`ForkMacBackupPolicyRules(source:
    /// extraRules:retention:)`): its sparse disk images and, in `.local`
    /// iCloud mode, its cloud-only entries. Paths are relative to the
    /// source's root; a dataless folder keeps its final « / ».
    static func runRules(sparseImages: [ForkMacBackupDiskUsage.SparseImage], dataless: [String]) -> [String] {
        var rules = sparseImages.map { ignoreRule(relativePath: $0.relativePath, isDirectory: false) }
        rules += dataless.map { ignoreRule(relativePath: $0, isDirectory: $0.hasSuffix("/")) }
        var seen = Set<String>()
        return rules.filter { seen.insert($0).inserted }
    }
}

/// The subset of Kopia's ignore syntax the presets use, to size what the
/// rules leave out before Kopia runs: anchored paths (`/Library/Caches/`),
/// names anywhere (`node_modules/`, `.venv/`) and suffixes (`*.log`).
/// Any other pattern is not understood here and counts as included (the
/// server's estimate, `POST /api/v1/estimate`, is the exact one).
struct ForkMacBackupIgnoreMatcher: Equatable {
    private var anchored: [(path: String, directoryOnly: Bool)] = []
    private var names: [(name: String, directoryOnly: Bool)] = []
    private var suffixes: [String] = []

    init(rules: [String]) {
        for raw in rules {
            var rule = raw.trimmingCharacters(in: .whitespaces)
            guard !rule.isEmpty, !rule.hasPrefix("!"), !rule.hasPrefix("#") else { continue }
            let directoryOnly = rule.hasSuffix("/")
            if directoryOnly { rule.removeLast() }
            if rule.hasPrefix("/") {
                let path = String(rule.dropFirst())
                if !Self.hasWildcard(path) { anchored.append((Self.unescape(path), directoryOnly)) }
            } else if rule.hasPrefix("*"), !Self.hasWildcard(String(rule.dropFirst())), !rule.contains("/") {
                suffixes.append(Self.unescape(String(rule.dropFirst())))
            } else if !rule.contains("/"), !Self.hasWildcard(rule) {
                names.append((Self.unescape(rule), directoryOnly))
            }
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.anchored.map { "\($0.path)|\($0.directoryOnly)" } == rhs.anchored.map { "\($0.path)|\($0.directoryOnly)" }
            && lhs.names.map { "\($0.name)|\($0.directoryOnly)" } == rhs.names.map { "\($0.name)|\($0.directoryOnly)" }
            && lhs.suffixes == rhs.suffixes
    }

    func excludes(_ relativePath: String, isDirectory: Bool) -> Bool {
        let name = relativePath.split(separator: "/").last.map(String.init) ?? relativePath
        for rule in anchored where rule.path == relativePath && (isDirectory || !rule.directoryOnly) { return true }
        for rule in names where rule.name == name && (isDirectory || !rule.directoryOnly) { return true }
        if !isDirectory { for suffix in suffixes where name.hasSuffix(suffix) { return true } }
        return false
    }

    private static func hasWildcard(_ text: String) -> Bool {
        var escaped = false
        for character in text {
            if escaped { escaped = false; continue }
            if character == "\\" { escaped = true; continue }
            if "*?[".contains(character) { return true }
        }
        return false
    }

    private static func unescape(_ text: String) -> String {
        var result = ""
        var escaped = false
        for character in text {
            if !escaped, character == "\\" { escaped = true; continue }
            escaped = false
            result.append(character)
        }
        return result
    }
}
