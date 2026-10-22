// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The one Kopia build the feature runs, pinned. The GPG signature of
/// Kopia's `checksums.txt` was checked when these values were written
/// (key `7FB99DFD47809F0D5339D7D92273699AFD56A556`, « Kopia Builder »); the
/// app checks the size and the SHA-256 of the archive it downloads, then the
/// Developer ID team of the binary before every launch.
///
/// Raising the version is a pull request that changes these values and
/// passes the bench again (the server API is undocumented, plan §3.2).
enum ForkMacBackupEngineManifest {
    static let version = "0.23.1"
    /// `kopia --version` prints `0.23.1 build: <commit> from: kopia/kopia`.
    static let buildCommitPrefix = "72ec08fd8edb"
    static let archiveName = "kopia-0.23.1-macOS-arm64.tar.gz"
    static let url = URL(string: "https://github.com/kopia/kopia/releases/download/v0.23.1/kopia-0.23.1-macOS-arm64.tar.gz")!
    static let archiveSize: Int64 = 15_257_600
    static let archiveSHA256 = "19e6ed637221f4dfd46a46e978ec4c509c386b522d746db2cd6762b217478111"
    /// The folder the archive holds its three files in.
    static let archiveFolder = "kopia-0.23.1-macOS-arm64"
    /// Apache-2.0: kept beside the binary (plan §3.7).
    static let licenseFile = "LICENSE"
    static let binaryName = "kopia"
    /// Kopia LLC's Developer ID team.
    static let teamIdentifier = "7299Z9ZVTK"
    /// The code requirement every launch checks.
    static let codeRequirement = "anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\""

    /// The archive, the unpacked folder and the installed copy, with room
    /// to spare: never start a download the volume cannot finish.
    static var requiredFreeBytes: Int64 { archiveSize + 3 * 50_000_000 }

    /// Whether `kopia --version` printed this build.
    static func matchesVersionOutput(_ output: String) -> Bool {
        guard let line = output.split(whereSeparator: \.isNewline).first.map(String.init) else { return false }
        let words = line.split(separator: " ").map(String.init)
        guard words.first == version else { return false }
        guard let build = words.firstIndex(of: "build:"), build + 1 < words.count else { return true }
        return words[build + 1].hasPrefix(buildCommitPrefix)
    }

    /// Lower-case hexadecimal, as `shasum -a 256` prints it.
    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

/// Why installing the engine failed: the stable code carried by
/// `ForkMacBackupEngineInstallState.failed(_:)` (its raw value), so the page
/// words it in the language of the moment it is shown
/// (`title(_:)`).
enum ForkMacBackupEngineInstallFailure: String, CaseIterable, Error {
    /// No connection, or GitHub answered with an error.
    case network
    /// The volume lacks room for the archive and the unpacked engine.
    case space
    /// The archive is not the pinned one (size or SHA-256): deleted.
    case checksum
    /// `tar` failed or the archive lacks the binary.
    case extract
    /// The binary is not signed by Kopia LLC, or does not start.
    case launch
    /// A folder could not be created, written or moved.
    case io

    func title(_ text: ForkMacBackupEngineStrings) -> String {
        switch self {
        case .network: return text.installNetwork
        case .space: return text.installSpace
        case .checksum: return text.installChecksum
        case .extract: return text.installExtract
        case .launch: return text.installLaunch
        case .io: return text.installIO
        }
    }

    /// Reads `ForkMacBackupEngineInstallState.failed`'s text; an unknown code
    /// (a newer build) reads as an I/O failure.
    static func parse(_ code: String) -> ForkMacBackupEngineInstallFailure {
        ForkMacBackupEngineInstallFailure(rawValue: code) ?? .io
    }
}
