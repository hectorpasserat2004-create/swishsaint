// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Darwin
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
    /// The cloud-only entries (`SF_DATALESS`), relative to the root; a
    /// folder ends with « / » and was not entered. Only filled when asked.
    var dataless: [String] = []
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

    // MARK: Walking

    /// One entry met by `walk`, with what every scan of this feature needs.
    struct Entry {
        var url: URL
        /// Relative to the walked root, no leading « / ».
        var relativePath: String
        var name: String
        /// 1 for the root's children.
        var depth: Int
        var isDirectory: Bool
        var isSymbolicLink: Bool
        var isRegularFile: Bool
        var allocatedBytes: Int64
        var logicalBytes: Int64
        /// Read lazily (one `lstat`), except for folders, always checked.
        var isDataless: Bool {
            if let known = datalessFolder { return known }
            var info = stat()
            return lstat(url.path, &info) == 0 && ForkMacBackupContentScan.isDataless(flags: info.st_flags)
        }

        fileprivate var datalessFolder: Bool?
    }

    enum Step {
        case enter
        /// Do not go below this folder.
        case skip
    }

    struct WalkResult: Equatable {
        var unreadable: Int64 = 0
        var canceled = false
    }

    static let walkKeys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey,
                                             .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]

    /// The one walk of the feature (the agent's pre-scan, the Settings'
    /// preview): packages included, symlinks never followed, sizes
    /// ALLOCATED, and a cloud-only folder never entered (listing it would
    /// download it). `visit` says whether to go below a folder.
    @discardableResult
    static func walk(root: URL, isCanceled: () -> Bool = { false }, visit: (Entry) -> Step) -> WalkResult {
        var result = WalkResult()
        var unreadable: Int64 = 0
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: walkKeys, options: [],
                                                          errorHandler: { _, _ in unreadable += 1; return true }) else {
            result.unreadable = 1
            return result
        }
        let rootPath = root.standardizedFileURL.path
        while let url = walker.nextObject() as? URL {
            if isCanceled() {
                result.canceled = true
                break
            }
            guard let values = try? url.resourceValues(forKeys: Set(walkKeys)) else {
                unreadable += 1
                continue
            }
            let relative = relativePath(of: url, root: rootPath)
            let isLink = values.isSymbolicLink == true
            let isDirectory = values.isDirectory == true && !isLink
            var entry = Entry(url: url, relativePath: relative, name: url.lastPathComponent,
                              depth: relative.split(separator: "/").count, isDirectory: isDirectory, isSymbolicLink: isLink,
                              isRegularFile: values.isRegularFile == true && !isLink,
                              allocatedBytes: Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0),
                              logicalBytes: Int64(values.fileSize ?? 0))
            if isDirectory {
                var info = stat()
                entry.datalessFolder = lstat(url.path, &info) == 0 && isDataless(flags: info.st_flags)
            }
            let step = visit(entry)
            if isDirectory, step == .skip || entry.datalessFolder == true { walker.skipDescendants() }
        }
        result.unreadable += unreadable
        return result
    }

    // MARK: Scanning

    /// Walks `root`, skipping what `matcher` excludes, and measures what is
    /// left: real sizes, the biggest folders, the sparse disk images and,
    /// with `collectDataless`, the cloud-only entries. `topFolders`: how
    /// many folders per depth.
    static func scan(root: URL, matcher: ForkMacBackupIgnoreMatcher = .init(rules: []), collectDataless: Bool = false,
                     topFolders: Int = 10, isCanceled: () -> Bool = { false }) -> ForkMacBackupDiskUsage {
        var usage = ForkMacBackupDiskUsage()
        var byFolder: [String: (bytes: Int64, files: Int64)] = [:]
        let walked = walk(root: root, isCanceled: isCanceled) { entry in
            if matcher.excludes(entry.relativePath, isDirectory: entry.isDirectory) {
                usage.excludedEntries += 1
                if !entry.isDirectory { usage.excludedAllocatedBytes += entry.allocatedBytes }
                return .skip
            }
            if entry.isDirectory {
                if collectDataless, entry.isDataless {
                    usage.dataless.append(entry.relativePath + "/")
                    return .skip
                }
                usage.directories += 1
                return .enter
            }
            if collectDataless, !entry.isSymbolicLink, entry.isDataless {
                // Its data is in the cloud: nothing of it is on this Mac.
                usage.dataless.append(entry.relativePath)
                return .enter
            }
            usage.files += 1
            usage.allocatedBytes += entry.allocatedBytes
            usage.logicalBytes += entry.logicalBytes
            if entry.isRegularFile, isSparseImage(logicalBytes: entry.logicalBytes, allocatedBytes: entry.allocatedBytes) {
                usage.sparseImages.append(.init(relativePath: entry.relativePath, logicalBytes: entry.logicalBytes,
                                                allocatedBytes: entry.allocatedBytes))
            }
            let parts = entry.relativePath.split(separator: "/")
            if parts.count > 1 {
                let first = String(parts[0])
                byFolder[first, default: (0, 0)].bytes += entry.allocatedBytes
                byFolder[first, default: (0, 0)].files += 1
                if parts.count > 2 {
                    let second = first + "/" + parts[1]
                    byFolder[second, default: (0, 0)].bytes += entry.allocatedBytes
                    byFolder[second, default: (0, 0)].files += 1
                }
            }
            return .enter
        }
        usage.unreadable = walked.unreadable
        usage.canceled = walked.canceled
        let all = byFolder.map { ForkMacBackupDiskUsage.Folder(relativePath: $0.key, allocatedBytes: $0.value.bytes,
                                                                files: $0.value.files) }
        for depth in 1...2 {
            usage.folders += all.filter { $0.depth == depth }
                .sorted { $0.allocatedBytes != $1.allocatedBytes ? $0.allocatedBytes > $1.allocatedBytes
                    : $0.relativePath < $1.relativePath }
                .prefix(topFolders)
        }
        usage.sparseImages.sort { $0.logicalBytes > $1.logicalBytes }
        usage.dataless.sort()
        return usage
    }

    /// The cloud-only entries below `root` (iCloud Drive's
    /// `Library/Mobile Documents`), relative to `root`; a folder whose
    /// listing is itself in the cloud ends with « / » and is not entered.
    static func dataless(root: URL, isCanceled: () -> Bool = { false }) -> [String] {
        var found: [String] = []
        walk(root: root, isCanceled: isCanceled) { entry in
            guard !entry.isSymbolicLink, entry.isDataless else { return .enter }
            found.append(entry.isDirectory ? entry.relativePath + "/" : entry.relativePath)
            return .skip
        }
        return found.sorted()
    }

    static func relativePath(of url: URL, root rootPath: String) -> String {
        let path = url.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if path.hasPrefix(prefix) { return String(path.dropFirst(prefix.count)) }
        let resolvedRoot = realPath(rootPath)
        let resolved = realPath(path)
        let resolvedPrefix = resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/"
        return resolved.hasPrefix(resolvedPrefix) ? String(resolved.dropFirst(resolvedPrefix.count)) : url.lastPathComponent
    }

    /// The path with every link resolved, `/private` kept (unlike
    /// `resolvingSymlinksInPath`, which strips it again).
    static func realPath(_ path: String) -> String {
        guard let resolved = Darwin.realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
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

/// One ignore rule, in Kopia's gitignore syntax, relative to a source's
/// root: `name` matches at any depth, `/name` only at the root, `a/b` from
/// the root too, a trailing `/` only folders, `*`, `?`, `[…]` and `**` as in
/// Kopia, `\\` escaping. A negation (« ! ») is not a rule by itself: the
/// matcher reads it.
struct ForkMacBackupIgnoreRule: Equatable {
    let text: String
    let pattern: String
    let anchored: Bool
    let directoryOnly: Bool
    /// For an anchored rule: how many path components it spans.
    let depth: Int
    let crossesFolders: Bool

    init?(_ text: String) {
        var pattern = text.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty, !pattern.hasPrefix("#"), !pattern.hasPrefix("!") else { return nil }
        self.text = pattern
        directoryOnly = pattern.hasSuffix("/")
        while pattern.hasSuffix("/") { pattern.removeLast() }
        var anchored = false
        if pattern.hasPrefix("/") {
            anchored = true
            while pattern.hasPrefix("/") { pattern.removeFirst() }
        }
        if pattern.hasPrefix("**/") {
            pattern.removeFirst(3)
            anchored = false
        }
        if pattern.contains("/") { anchored = true }
        guard !pattern.isEmpty else { return nil }
        self.pattern = pattern
        self.anchored = anchored
        crossesFolders = pattern.contains("**")
        depth = pattern.split(separator: "/").count
    }

    /// `relativePath` has no leading slash; `name` is its last component,
    /// `depth` its number of components.
    func matches(relativePath: String, name: String, depth pathDepth: Int, isDirectory: Bool) -> Bool {
        if directoryOnly && !isDirectory { return false }
        if anchored {
            if crossesFolders { return fnmatch(pattern, relativePath, 0) == 0 }
            guard pathDepth == depth else { return false }
            return fnmatch(pattern, relativePath, FNM_PATHNAME) == 0
        }
        return fnmatch(pattern, name, 0) == 0
    }
}

/// A source's rules, read as Kopia reads them: the last rule that matches
/// decides, a « ! » takes a path back, and nothing comes back out of a
/// folder left out. Used to size what the rules leave out before Kopia
/// runs and to answer « Ce fichier est-il sauvegardé ? »; the server's
/// estimate (`POST /api/v1/estimate`) stays the exact count.
struct ForkMacBackupIgnoreMatcher: Equatable {
    private struct Line: Equatable {
        var rule: ForkMacBackupIgnoreRule
        var negated: Bool
    }

    private let lines: [Line]

    init(rules: [String]) {
        lines = rules.compactMap { raw in
            let text = raw.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("!") {
                return ForkMacBackupIgnoreRule(String(text.dropFirst())).map { Line(rule: $0, negated: true) }
            }
            return ForkMacBackupIgnoreRule(text).map { Line(rule: $0, negated: false) }
        }
    }

    /// The rule that leaves `relativePath` ITSELF out (its folders above
    /// are the walker's business), nil when kept.
    func rule(excluding relativePath: String, isDirectory: Bool) -> String? {
        let parts = relativePath.split(separator: "/")
        guard let name = parts.last.map(String.init) else { return nil }
        var excludedBy: String?
        for line in lines where line.rule.matches(relativePath: relativePath, name: name, depth: parts.count,
                                                  isDirectory: isDirectory) {
            excludedBy = line.negated ? nil : line.rule.text
        }
        return excludedBy
    }

    func excludes(_ relativePath: String, isDirectory: Bool) -> Bool {
        rule(excluding: relativePath, isDirectory: isDirectory) != nil
    }

    /// The rule that leaves `relativePath` out, itself or through one of
    /// its folders; nil when it is kept.
    func excludingRule(for relativePath: String, isDirectory: Bool) -> String? {
        let parts = ForkMacBackupFailureList.normalize(relativePath).split(separator: "/").map(String.init)
        guard !parts.isEmpty else { return nil }
        for depth in 1...parts.count {
            let candidate = parts.prefix(depth).joined(separator: "/")
            if let rule = rule(excluding: candidate, isDirectory: depth < parts.count || isDirectory) { return rule }
        }
        return nil
    }
}
