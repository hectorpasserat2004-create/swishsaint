// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation
import os
import Security

/// The repository's secrets in the login Keychain (modelled on
/// `ForkMeetingKeychain`): service `<bundle id>.macbackup`, one account per
/// secret and repository (`repo-password#<key>`, `s3-secret#<key>`),
/// readable after the first unlock (the night backup runs with the screen
/// locked), on this Mac only, never synchronized.
///
/// Bounded: a Keychain that does not answer (a dialog nobody sees) fails
/// after `timeout` instead of holding the agent. Never logs a secret, nor
/// an account's value; never on the main thread for a read.
final class ForkMacBackupKeychain: ForkMacBackupSecrets {
    let service: String
    let timeout: TimeInterval
    private static let log = Logger(subsystem: "fork.macbackup", category: "keychain")
    private let queue = DispatchQueue(label: "fork.macbackup.keychain", qos: .userInitiated, attributes: .concurrent)

    init(service: String, timeout: TimeInterval = 30) {
        self.service = service
        self.timeout = timeout
    }

    static func forCurrentBundle() -> ForkMacBackupKeychain {
        ForkMacBackupKeychain(service: ForkMacBackupSecretKind.service(bundleID: Bundle.main.bundleIdentifier ?? "swishsaint"))
    }

    private func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    private final class Box<Value>: @unchecked Sendable {
        let lock = NSLock()
        var value: Value?
    }

    /// One Keychain call on a queue of its own, waited for `timeout`.
    private func bounded<Value>(_ call: @escaping () -> Value) -> Value? {
        let box = Box<Value>()
        let done = DispatchSemaphore(value: 0)
        queue.async {
            let value = call()
            box.lock.withLock { box.value = value }
            done.signal()
        }
        guard done.wait(timeout: .now() + timeout) == .success else {
            Self.log.error("no answer in \(Int(self.timeout), privacy: .public) s")
            return nil
        }
        return box.lock.withLock { box.value }
    }

    // MARK: ForkMacBackupSecrets

    func exists(_ kind: ForkMacBackupSecretKind, repositoryKey: String) -> Bool {
        var query = query(kind.account(repositoryKey: repositoryKey))
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let dictionary = query as CFDictionary
        return bounded { SecItemCopyMatching(dictionary, nil) } == errSecSuccess
    }

    func read(_ kind: ForkMacBackupSecretKind, repositoryKey: String) -> ForkMacBackupSecretRead {
        var query = query(kind.account(repositoryKey: repositoryKey))
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let dictionary = query as CFDictionary
        let answer: (OSStatus, Data?)? = bounded {
            var result: AnyObject?
            let status = SecItemCopyMatching(dictionary, &result)
            return (status, result as? Data)
        }
        guard let (status, data) = answer else { return .failed }
        if status == errSecItemNotFound { return .missing }
        guard status == errSecSuccess, let data, !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
            Self.log.error("read refused: \(status, privacy: .public)")
            return .failed
        }
        return .found(text)
    }

    @discardableResult
    func save(_ value: String, kind: ForkMacBackupSecretKind, repositoryKey: String) -> Bool {
        guard !value.isEmpty else { return false }
        let account = kind.account(repositoryKey: repositoryKey)
        let secret = Data(value.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: secret,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrLabel as String: "Swishsaint — Mac Backup",
        ]
        let match = query(account) as CFDictionary
        var item = query(account)
        item.merge(attributes) { $1 }
        let added = item as CFDictionary
        let changes = attributes as CFDictionary
        let status: OSStatus? = bounded {
            var status = SecItemUpdate(match, changes)
            if status == errSecItemNotFound { status = SecItemAdd(added, nil) }
            return status
        }
        guard status == errSecSuccess else {
            Self.log.error("save refused: \(status ?? errSecNotAvailable, privacy: .public)")
            return false
        }
        return read(kind, repositoryKey: repositoryKey) == .found(value)
    }

    @discardableResult
    func delete(_ kind: ForkMacBackupSecretKind, repositoryKey: String) -> Bool {
        let dictionary = query(kind.account(repositoryKey: repositoryKey)) as CFDictionary
        let status = bounded { SecItemDelete(dictionary) }
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
