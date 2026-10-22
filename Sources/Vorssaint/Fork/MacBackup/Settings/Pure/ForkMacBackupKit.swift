// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CommonCrypto
import CryptoKit
import Foundation

/// The recovery kit (plan §9): what it takes to reach the backups without
/// this Mac, and without the app. A PDF to print, and a
/// `.swishsaint-backupkit` file (JSON) that may carry the two secrets,
/// sealed with a passphrase of its own.
struct ForkMacBackupKitFile: Codable, Equatable {
    static let fileExtension = "swishsaint-backupkit"
    static let formatVersion = 1

    var formatVersion: Int
    var createdAt: Date
    /// The app that wrote it (« Swishsaint 2237 »), for the reader.
    var createdBy: String
    var kopiaVersion: String
    /// Without a secret; the S3 key's ID is not one.
    var repository: ForkMacBackupRepository
    var profileName: String?
    /// `ForkMacBackupKit.fingerprint(repository)` when it was made.
    var fingerprint: String
    var secrets: ForkMacBackupSealedSecrets?

    init(createdAt: Date, createdBy: String, kopiaVersion: String, repository: ForkMacBackupRepository,
         profileName: String? = nil, secrets: ForkMacBackupSealedSecrets? = nil) {
        formatVersion = Self.formatVersion
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.kopiaVersion = kopiaVersion
        self.repository = repository
        self.profileName = profileName
        fingerprint = ForkMacBackupKit.fingerprint(repository)
        self.secrets = secrets
    }

    func encoded() -> Data? {
        let encoder = ForkMacBackupJSON.encoder
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try? encoder.encode(self)
    }

    static func decode(_ data: Data) -> ForkMacBackupKitFile? {
        guard let file = try? ForkMacBackupJSON.decoder.decode(ForkMacBackupKitFile.self, from: data),
              file.formatVersion <= formatVersion else { return nil }
        return file
    }
}

/// The two secrets, in clear only in memory.
struct ForkMacBackupKitSecrets: Codable, Equatable {
    var repositoryPassword: String
    var s3SecretAccessKey: String?
}

/// AES-GCM (CryptoKit) under a key derived from the passphrase by
/// PBKDF2-SHA256 (CommonCrypto), 600 000 rounds; salt and nonce kept with
/// the box. Tampering, or another passphrase, opens nothing.
struct ForkMacBackupSealedSecrets: Codable, Equatable {
    static let algorithm = "AES-256-GCM/PBKDF2-SHA256"
    static let defaultIterations = 600_000

    var algorithm: String
    var iterations: Int
    /// Base64, 16 bytes.
    var salt: String
    /// Base64, 12 bytes.
    var nonce: String
    /// Base64: the ciphertext followed by its 16-byte tag.
    var box: String
}

enum ForkMacBackupKitCrypto {
    enum Failure: Error, Equatable {
        case emptyPassphrase
        case derivation
        case sealing
    }

    /// Binds the box to its format: the same bytes under another label do
    /// not open.
    private static let associatedData = Data("swishsaint-backupkit-v1".utf8)

    static func seal(_ secrets: ForkMacBackupKitSecrets, passphrase: String,
                     iterations: Int = ForkMacBackupSealedSecrets.defaultIterations) throws -> ForkMacBackupSealedSecrets {
        guard !passphrase.isEmpty else { throw Failure.emptyPassphrase }
        let salt = randomBytes(16)
        guard let key = deriveKey(passphrase: passphrase, salt: salt, iterations: iterations),
              let plain = try? JSONEncoder().encode(secrets) else { throw Failure.derivation }
        do {
            let nonce = AES.GCM.Nonce()
            let sealed = try AES.GCM.seal(plain, using: key, nonce: nonce, authenticating: associatedData)
            return ForkMacBackupSealedSecrets(algorithm: ForkMacBackupSealedSecrets.algorithm, iterations: iterations,
                                              salt: salt.base64EncodedString(),
                                              nonce: Data(nonce).base64EncodedString(),
                                              box: (sealed.ciphertext + sealed.tag).base64EncodedString())
        } catch {
            throw Failure.sealing
        }
    }

    /// The secrets, or nil for a wrong passphrase or a damaged box.
    static func open(_ sealed: ForkMacBackupSealedSecrets, passphrase: String) -> ForkMacBackupKitSecrets? {
        guard sealed.algorithm == ForkMacBackupSealedSecrets.algorithm, sealed.iterations > 0,
              let salt = Data(base64Encoded: sealed.salt), let nonceData = Data(base64Encoded: sealed.nonce),
              let box = Data(base64Encoded: sealed.box), box.count > 16,
              let nonce = try? AES.GCM.Nonce(data: nonceData),
              let key = deriveKey(passphrase: passphrase, salt: salt, iterations: sealed.iterations),
              let sealedBox = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: box.dropLast(16), tag: box.suffix(16)),
              let plain = try? AES.GCM.open(sealedBox, using: key, authenticating: associatedData) else { return nil }
        return try? JSONDecoder().decode(ForkMacBackupKitSecrets.self, from: plain)
    }

    /// PBKDF2-HMAC-SHA256 → a 256-bit key.
    static func deriveKey(passphrase: String, salt: Data, iterations: Int) -> SymmetricKey? {
        let password = Array(passphrase.utf8).map { Int8(bitPattern: $0) }
        guard !password.isEmpty, !salt.isEmpty, iterations > 0, iterations <= 50_000_000 else { return nil }
        var derived = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltBytes -> Int32 in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, password.count,
                                 saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                                 &derived, derived.count)
        }
        guard status == kCCSuccess else { return nil }
        return SymmetricKey(data: derived)
    }

    static func randomBytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}

/// The kit's state on this Mac (« Kit à jour » / « Kit à refaire »).
enum ForkMacBackupKitStatus: Equatable {
    case missing
    case upToDate(createdAt: Date)
    /// Made for another address, bucket, password lock or identity.
    case repositoryChanged(createdAt: Date)
    /// Older than its reminder date (180 days).
    case reminderDue(createdAt: Date)

    var needsAction: Bool {
        if case .upToDate = self { return false }
        return true
    }
}

enum ForkMacBackupKit {
    /// Plan §9.1: every 180 days.
    static let reminderInterval: TimeInterval = 180 * 86_400
    /// The pinned engine the commands download.
    static let kopiaVersion = "0.23.1"
    static let kopiaArchive = "kopia-0.23.1-macOS-arm64.tar.gz"
    static let kopiaArchiveSHA256 = "19e6ed637221f4dfd46a46e978ec4c509c386b522d746db2cd6762b217478111"
    static var kopiaDownloadURL: String {
        "https://github.com/kopia/kopia/releases/download/v\(kopiaVersion)/\(kopiaArchive)"
    }

    /// What a kit depends on: a change of any of these calls for a new one.
    static func fingerprint(_ repository: ForkMacBackupRepository) -> String {
        let parts = [repository.kind.rawValue, repository.endpoint.host.lowercased(),
                     repository.endpoint.port.map(String.init) ?? "", repository.endpoint.tls ? "tls" : "plain",
                     repository.bucket, repository.prefix, repository.region, repository.accessKeyID ?? "",
                     (repository.expectedUniqueID ?? "").lowercased(), repository.clientIdentity.description,
                     repository.path ?? ""]
        return ForkMacBackupHash.fnv1a64Hex(parts.joined(separator: "|"))
    }

    static func status(createdAt: Date?, remindAt: Date?, savedFingerprint: String?,
                       repository: ForkMacBackupRepository?, now: Date) -> ForkMacBackupKitStatus {
        guard let createdAt else { return .missing }
        if let repository, let savedFingerprint, savedFingerprint != fingerprint(repository) {
            return .repositoryChanged(createdAt: createdAt)
        }
        let due = remindAt ?? createdAt.addingTimeInterval(reminderInterval)
        return now >= due ? .reminderDue(createdAt: createdAt) : .upToDate(createdAt: createdAt)
    }

    /// The four commands that reach the backups without the app (plan §9.3),
    /// with placeholders where a secret would go. `restoreFolder` is where
    /// the last one writes.
    static func rescueCommands(_ repository: ForkMacBackupRepository, restoreFolder: String = "~/Restored")
        -> [String] {
        var connect = ["./kopia repository connect s3",
                       "--endpoint=\(repository.endpoint.hostAndPort)",
                       "--bucket=\(repository.bucket)",
                       "--region=\(repository.region)"]
        if !repository.prefix.isEmpty { connect.append("--prefix=\(shellQuoted(repository.prefix))") }
        if !repository.endpoint.tls { connect.append("--disable-tls") }
        connect.append("--access-key=\(repository.accessKeyID ?? "<ACCESS_KEY_ID>")")
        connect.append("--secret-access-key=<SECRET_ACCESS_KEY>")
        connect.append("--readonly")
        return [
            "curl -LO \(kopiaDownloadURL) && shasum -a 256 \(kopiaArchive) && tar xzf \(kopiaArchive) --strip-components=1",
            connect.joined(separator: " "),
            "./kopia snapshot list --all",
            "./kopia restore <SNAPSHOT_ID> \(restoreFolder)",
        ]
    }

    private static func shellQuoted(_ text: String) -> String {
        text.allSatisfy { $0.isLetter || $0.isNumber || "-_./".contains($0) } ? text : "'\(text.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
