// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// How a file of a snapshot compares with the same path on this Mac now
/// (plan §6.2): the column after the name in « Parcourir ».
enum ForkMacBackupLocalStatus: String, Equatable, CaseIterable {
    /// Same size and same modification date as on the Mac.
    case identical
    /// The Mac's file changed after this snapshot (◐).
    case modifiedSince
    /// Not on the Mac any more (⊘).
    case deletedSince
    /// A folder still on the Mac: its content is compared file by file.
    case present
    /// Another Mac's snapshot, or not checked yet.
    case unknown

    /// What `stat` says about a path on this Mac, nil when it is missing.
    struct LocalFacts: Equatable {
        var isDirectory: Bool
        /// The logical size: Kopia keeps the logical size of each file, so
        /// the comparison is on that one (the display shows real sizes).
        var size: Int64
        var modified: Date?
    }

    /// Kopia keeps nanoseconds; a copy through SMB or FAT rounds to two
    /// seconds. Within this the dates are the same.
    static let dateTolerance: TimeInterval = 2

    /// The status of a snapshot entry (`isDirectory`, `size`, `modified`)
    /// against `local`.
    static func compare(isDirectory: Bool, size: Int64?, modified: Date?, local: LocalFacts?) -> Self {
        guard let local else { return .deletedSince }
        if isDirectory { return local.isDirectory ? .present : .modifiedSince }
        if local.isDirectory { return .modifiedSince }
        if let size, size != local.size { return .modifiedSince }
        guard let modified, let localModified = local.modified else { return size == nil ? .unknown : .identical }
        return abs(modified.timeIntervalSince(localModified)) <= dateTolerance ? .identical : .modifiedSince
    }

    /// Reads `path` on this Mac without following a final symlink; nil when
    /// it is not there. Never on the main thread for a whole folder.
    static func facts(atPath path: String, fileManager: FileManager = .default) -> LocalFacts? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path) else { return nil }
        let type = attributes[.type] as? FileAttributeType
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        return LocalFacts(isDirectory: type == .typeDirectory, size: size,
                          modified: attributes[.modificationDate] as? Date)
    }
}

/// One line of the browser: an entry of a snapshot's folder.
struct ForkMacBackupBrowseEntry: Equatable, Identifiable {
    var name: String
    /// Relative to the source's root, « Documents/Castral/devis.pdf ».
    var relativePath: String
    var isDirectory: Bool
    var isSymlink: Bool
    var objectID: String
    /// The snapshot's size: a folder's is its summary's. Sparse images are
    /// out of the sources by default, so it reads as a real size.
    var size: Int64?
    /// Files inside a folder (its summary), 1 for a file.
    var fileCount: Int64
    var modified: Date?
    /// Files of this folder Kopia could not read.
    var failedCount: Int64
    var localStatus: ForkMacBackupLocalStatus

    var id: String { relativePath }

    /// The entries of a directory manifest under `folder` (relative path,
    /// empty for the root), symlinks kept, unnamed entries dropped.
    static func entries(of manifest: ForkMacBackupKopia.DirectoryManifest, folder: String) -> [ForkMacBackupBrowseEntry] {
        manifest.entries.compactMap { entry in
            guard let name = entry.name, !name.isEmpty, let objectID = entry.obj, !objectID.isEmpty else { return nil }
            return ForkMacBackupBrowseEntry(
                name: name,
                relativePath: ForkMacBackupFolderPath.join(folder, name),
                isDirectory: entry.isDirectory,
                isSymlink: entry.isSymlink,
                objectID: objectID,
                size: entry.totalSize,
                fileCount: entry.isDirectory ? (entry.summ?.files ?? 0) : 1,
                modified: entry.modified,
                failedCount: entry.summ?.numFailed ?? 0,
                localStatus: .unknown)
        }
    }

    /// Finder's order: by name, as the Finder compares them (« 2 » before « 10 »).
    static func finderOrder(_ lhs: ForkMacBackupBrowseEntry, _ rhs: ForkMacBackupBrowseEntry) -> Bool {
        let order = lhs.name.localizedStandardCompare(rhs.name)
        return order == .orderedSame ? lhs.relativePath < rhs.relativePath : order == .orderedAscending
    }
}

/// What a selection of the browser weighs, for « Restaurer… ».
struct ForkMacBackupSelectionSize: Equatable {
    var bytes: Int64
    var files: Int64
    /// One entry at least had no size.
    var isEstimate: Bool

    static func of(_ entries: [ForkMacBackupBrowseEntry]) -> ForkMacBackupSelectionSize {
        var total = ForkMacBackupSelectionSize(bytes: 0, files: 0, isEstimate: false)
        for entry in entries {
            if let size = entry.size { total.bytes += max(0, size) } else { total.isEstimate = true }
            total.files += max(0, entry.fileCount)
        }
        return total
    }
}

/// A folder inside a snapshot, as path components from the source's root.
/// Kept when the date changes: the browser walks the same components in the
/// new snapshot and stops at the deepest one that existed then.
enum ForkMacBackupFolderPath {
    static func components(_ relativePath: String) -> [String] {
        relativePath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    static func join(_ folder: String, _ name: String) -> String {
        folder.isEmpty ? name : folder + "/" + name
    }

    static func join(_ components: [String]) -> String { components.joined(separator: "/") }

    /// The parent folder; nil at the root.
    static func parent(of relativePath: String) -> String? {
        let parts = components(relativePath)
        guard !parts.isEmpty else { return nil }
        return join(Array(parts.dropLast()))
    }

    /// The absolute path on this Mac of `relativePath` in `sourcePath`.
    static func absolute(_ relativePath: String, in sourcePath: String) -> String {
        guard !relativePath.isEmpty else { return sourcePath }
        return (sourcePath as NSString).appendingPathComponent(relativePath)
    }

    /// `path` relative to `sourcePath`; nil when it is not inside it.
    static func relative(_ path: String, to sourcePath: String) -> String? {
        let root = sourcePath.hasSuffix("/") && sourcePath.count > 1 ? String(sourcePath.dropLast()) : sourcePath
        if path == root { return "" }
        let prefix = root == "/" ? "/" : root + "/"
        guard path.hasPrefix(prefix) else { return nil }
        return String(path.dropFirst(prefix.count))
    }
}

/// The search in a snapshot (plan §6.2): by name, diacritics and case
/// ignored, every word of the query somewhere in the name.
struct ForkMacBackupNameQuery: Equatable {
    let words: [String]

    init(_ text: String) {
        words = text.split(whereSeparator: { $0.isWhitespace }).map { Self.fold(String($0)) }.filter { !$0.isEmpty }
    }

    var isEmpty: Bool { words.isEmpty }

    func matches(_ name: String) -> Bool {
        guard !words.isEmpty else { return false }
        let folded = Self.fold(name)
        return words.allSatisfy { folded.contains($0) }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
