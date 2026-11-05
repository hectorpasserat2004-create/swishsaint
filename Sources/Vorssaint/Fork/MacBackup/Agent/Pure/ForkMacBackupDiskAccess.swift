// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Darwin
import Foundation

/// Whether the process about to spawn Kopia (the agent, or the app while it
/// backs up in the agent's place) really has Full Disk Access. Kopia is its
/// child (`Process`, no `setsid`, no responsibility disclaim: see
/// `ForkMacBackupKopiaProcess.start`), so macOS judges Kopia's reads by
/// this very process; probing it here is probing what Kopia will get.
///
/// The probe used until build 2340 only read `~/Library/Application
/// Support/com.apple.TCC/TCC.db`, and treated a missing file as « not
/// refused ». On macOS 27 that file is not there (checked 23/10 on
/// Martial's Mac), so the probe never refused anything and the app's
/// fallback ran a snapshot with 535 « operation not permitted ». It now
/// also lists the folders `Permissions` lists (none prompts), and a run
/// whose failures show the refusal holds the next scheduled ones.
enum ForkMacBackupDiskAccess {
    enum Verdict: Equatable {
        case granted
        case refused
        /// Nothing to probe on this Mac: never blocks a backup.
        case unknown
    }

    /// One probe's answer.
    enum Answer: Equatable {
        case readable
        case denied
        case absent
        /// Any other error: says nothing about the access.
        case other
    }

    /// The same protected folders as `Permissions` (listing them never
    /// shows a prompt), relative to the home folder.
    static let gatedFolders = [
        "Library/Safari",
        "Library/Mail",
        "Library/Messages",
        "Library/Cookies",
        "Library/Suggestions",
        "Library/Application Support/MobileSync",
    ]

    static let tccDatabase = "Library/Application Support/com.apple.TCC/TCC.db"

    /// Granted as soon as one protected place reads; refused when one
    /// exists and every existing one is denied; unknown otherwise.
    static func verdict(database: Answer, folders: [Answer]) -> Verdict {
        let all = [database] + folders
        if all.contains(.readable) { return .granted }
        if all.contains(.denied) { return .refused }
        return .unknown
    }

    static func answer(errno code: Int32) -> Answer {
        switch code {
        case EPERM, EACCES: return .denied
        case ENOENT, ENOTDIR: return .absent
        default: return .other
        }
    }

    /// Probes from this process (bounded: one `open`, a few `opendir`).
    static func probe(home: String = NSHomeDirectory()) -> Verdict {
        let database = (home as NSString).appendingPathComponent(tccDatabase)
        let descriptor = open(database, O_RDONLY)
        let databaseAnswer: Answer
        if descriptor >= 0 {
            close(descriptor)
            databaseAnswer = .readable
        } else {
            databaseAnswer = answer(errno: errno)
        }
        if databaseAnswer == .readable { return .granted }
        var answers: [Answer] = []
        for folder in gatedFolders {
            let path = (home as NSString).appendingPathComponent(folder)
            guard let directory = opendir(path) else {
                answers.append(answer(errno: errno))
                continue
            }
            closedir(directory)
            return .granted
        }
        return verdict(database: databaseAnswer, folders: answers)
    }

    // MARK: Learned from a run

    /// Folders macOS keeps behind Full Disk Access (or a consent the agent
    /// cannot ask for), relative to the home folder.
    static let protectedRoots = [
        "Library/Containers/", "Library/Group Containers/", "Library/Mail", "Library/Safari", "Library/Messages",
        "Downloads", "Desktop", "Documents", "Pictures/Photos Library", "Music/Music", "Movies/TV",
    ]

    /// Past this many « operation not permitted » in protected folders, a
    /// run says the process lacks Full Disk Access (a Mac with it read the
    /// same folders with no failure at all).
    static let refusalThreshold = 20

    /// The failures of a run show that Full Disk Access did not apply.
    static func runShowsRefusal(_ failures: [ForkMacBackupFailure]) -> Bool {
        var count = 0
        for failure in failures where failure.cause == .permission && isProtected(failure.path) {
            count += 1
            if count >= refusalThreshold { return true }
        }
        return false
    }

    /// `path` relative to the source (a home folder), as Kopia names it.
    static func isProtected(_ path: String) -> Bool {
        let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return protectedRoots.contains { root in
            root.hasSuffix("/") ? relative.hasPrefix(root) : relative == root || relative.hasPrefix(root + "/")
        }
    }
}
