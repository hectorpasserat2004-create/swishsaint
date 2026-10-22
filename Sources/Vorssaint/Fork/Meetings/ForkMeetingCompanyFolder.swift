// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// A meeting filed in its company's folder: `<meetings folder>/<domain>/<meeting>/`,
/// the domain the CRM knows the company by ("acme.com"), once the CRM
/// exporter's "file by company" is on and the meeting's appointment known.
///
/// The library names a meeting by its path under the meetings folder:
/// "<meeting>" at the root, "acme.com/<meeting>" once filed. Only folders
/// named like a domain are read one level down, and only for the meeting
/// folders in them (a `meeting.json` inside): the rest of the meetings
/// folder is never read deeper, so nothing changes for someone who never
/// files. New recordings, the free space and the recovery at launch stay at
/// the root: a meeting is always recorded there, and filed only once
/// complete.
enum ForkMeetingCompanyFolder {
    static let maximumLength = 100

    /// The company folder's name for a domain as the CRM gives it: trimmed,
    /// in lower case, without `www.`; `nil` for anything that is not a plain
    /// domain (a path, a dot alone, an address with a scheme).
    static func name(domain: String?) -> String? {
        guard var text = domain?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !text.isEmpty else {
            return nil
        }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        return isName(text) ? text : nil
    }

    /// A name a company folder may have: letters, digits, dots and hyphens,
    /// with a dot, never at either end, never two in a row.
    static func isName(_ name: String) -> Bool {
        guard (3...maximumLength).contains(name.count), name.contains("."), !name.hasPrefix("."), !name.hasSuffix("."),
              !name.hasPrefix("-"), !name.contains("..") else { return false }
        return name.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "." || $0 == "-"
        }
    }

    // MARK: - Names in the library

    /// "acme.com/<meeting>", or "<meeting>" at the root.
    static func relative(_ leaf: String, company: String?) -> String {
        company.map { $0 + "/" + leaf } ?? leaf
    }

    /// The meeting folder's own name, without its company folder.
    static func leaf(of relative: String) -> String {
        relative.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? relative
    }

    /// The company folder a meeting is filed in, `nil` at the root.
    static func company(of relative: String) -> String? {
        let parts = relative.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 2 else { return nil }
        return String(parts[0])
    }

    /// The meeting's name in the library from its folder: `nil` when the
    /// folder is neither at the root nor in one of its company folders.
    static func relativeName(of folder: URL, root: URL) -> String? {
        let base = root.standardizedFileURL.path
        let parent = folder.standardizedFileURL.deletingLastPathComponent().path
        let leaf = folder.standardizedFileURL.lastPathComponent
        if parent == base { return leaf }
        let company = (parent as NSString).lastPathComponent
        guard (parent as NSString).deletingLastPathComponent == base, isName(company) else { return nil }
        return relative(leaf, company: company)
    }

    /// A scan of `names` alone covers this meeting: its own name, or its
    /// company folder's (a change anywhere in it).
    static func covers(_ names: Set<String>, _ relative: String) -> Bool {
        names.contains(relative) || company(of: relative).map(names.contains) == true
    }

    // MARK: - On the disk

    /// The meeting folders of `root` as library names, in order: its own,
    /// and those of its company folders. `only`: these names alone, a
    /// company folder's name standing for every meeting in it. Any thread.
    static func meetings(in root: URL, only: Set<String>? = nil) -> [String] {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: root.path) else { return [] }
        func isMeeting(_ folder: URL) -> Bool {
            manager.fileExists(atPath: folder.appendingPathComponent(ForkMeetingFolder.sidecarName).path)
        }
        var found: [String] = []
        for name in names.sorted() where !name.hasPrefix(".") {
            let folder = root.appendingPathComponent(name, isDirectory: true)
            let whole = only?.contains(name) != false
            if isMeeting(folder) {
                if whole { found.append(name) }
                continue
            }
            var isDirectory: ObjCBool = false
            guard isName(name), manager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue,
                  let inside = try? manager.contentsOfDirectory(atPath: folder.path) else { continue }
            for child in inside.sorted() where !child.hasPrefix(".") {
                let relative = relative(child, company: name)
                guard whole || only?.contains(relative) == true,
                      isMeeting(folder.appendingPathComponent(child, isDirectory: true)) else { continue }
                found.append(relative)
            }
        }
        return found
    }

    enum Filing: Equatable {
        case filed(URL)
        /// Already in that company's folder.
        case already
        /// A file, not a folder, has the company's name in the meetings folder.
        case blockedByFile
        /// A folder of the meeting's name is already in the company's folder.
        case taken
        /// Neither at the root nor in a company folder: filed by the person.
        case notInLibrary
        case failed(String)
    }

    /// Moves a meeting's folder into `<root>/<company>/`, made when missing
    /// and kept as it is when it exists (other files the person keeps for
    /// that company stay beside the meetings). One rename on the same disk:
    /// the folder is whole at either place, never half moved.
    static func file(_ folder: URL, root: URL, company: String) -> Filing {
        guard isName(company) else { return .failed("not a company folder name") }
        guard relativeName(of: folder, root: root) != nil else { return .notInLibrary }
        let manager = FileManager.default
        let target = root.appendingPathComponent(company, isDirectory: true)
        if folder.standardizedFileURL.deletingLastPathComponent().path == target.standardizedFileURL.path {
            return .already
        }
        var isDirectory: ObjCBool = false
        if manager.fileExists(atPath: target.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { return .blockedByFile }
        } else {
            do {
                try manager.createDirectory(at: target, withIntermediateDirectories: false)
            } catch {
                return .failed(error.localizedDescription)
            }
        }
        let destination = target.appendingPathComponent(folder.lastPathComponent, isDirectory: true)
        guard !manager.fileExists(atPath: destination.path) else { return .taken }
        do {
            try manager.moveItem(at: folder, to: destination)
        } catch {
            return .failed(error.localizedDescription)
        }
        return .filed(destination)
    }
}
