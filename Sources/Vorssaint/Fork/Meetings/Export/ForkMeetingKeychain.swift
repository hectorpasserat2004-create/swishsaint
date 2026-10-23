// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation
import os
import Security

/// The exporters' secrets (tokens, keys, a CRM's profile, an upload address,
/// the list's fingerprint), in one owner-only file of the app's container:
/// `~/Library/Application Support/<bundle id>/MeetingSecrets.json`, mode 0600
/// (`PrivateFileStore`), one entry per account, the secret as text.
///
/// Not the login Keychain any more: the fork is signed without an Apple team,
/// so the Keychain tied each item to one build and asked for the session's
/// password again after every update, once per item. The file asks nothing.
/// What it gives up: any process of this account may read it, as it may the
/// rest of the container (clipboard history, recordings).
///
/// - Never in the preferences, the settings backup or a log; the page never
///   shows a secret again once saved.
/// - **Copied on first use**: an account the file lacks but the Keychain of
///   an earlier version has (service `<bundle id>.meetings`) is read there
///   one last time and written to the file, which answers from then on.
///   Asking whether it exists reads only its attributes, which never
///   prompts. The Keychain's copy goes only with `delete`, so that a copy
///   never comes back from there.
/// - **Bounded**: a Keychain that does not answer during that move (a dialog
///   nobody sees) fails after `timeout` instead of holding the sends.
/// - Keeps the fingerprint of the exporters' list the page wrote
///   (`fingerprintAccount`): another process may rewrite the preferences
///   without matching it.
struct ForkMeetingKeychain {
    let service: String
    /// `nil` outside a real bundle: nothing is kept.
    let file: URL?
    var timeout: TimeInterval = 60

    static let shared = ForkMeetingKeychain(
        service: (Bundle.main.bundleIdentifier ?? "swishsaint") + ".meetings",
        file: PrivateFileStore.containerURL?.appendingPathComponent("MeetingSecrets.json"))
    static let fingerprintAccount = "exporters"
    private static let log = Logger(subsystem: "fork.meetings", category: "secrets")
    /// One reader or writer of the file at a time, across every copy of the store.
    private static let lock = NSLock()

    /// A read: the data, nothing saved, or a store that refused or did not
    /// answer in time.
    enum Read: Equatable {
        case found(Data)
        case missing
        case failed
    }

    /// Whether a secret is saved for `account`.
    func exists(_ account: String) -> Bool {
        if Self.lock.withLock({ load()?[account] }) != nil { return true }
        return legacyExists(account)
    }

    /// The secret itself.
    func read(_ account: String) -> Read {
        guard let entries = Self.lock.withLock({ load() }) else { return .failed }
        if let text = entries[account] { return text.isEmpty ? .failed : .found(Data(text.utf8)) }
        return moveLegacy(account)
    }

    /// Saves or replaces the secret; `false` when it is not text or the file
    /// could not be written.
    @discardableResult
    func save(_ secret: Data, account: String) -> Bool {
        guard !secret.isEmpty, let text = String(data: secret, encoding: .utf8) else { return false }
        let saved = Self.lock.withLock { () -> Bool in
            guard var entries = load() else { return false }
            entries[account] = text
            return store(entries)
        }
        if !saved { Self.log.error("save refused") }
        return saved
    }

    /// Erases the secret; `true` when none is left.
    @discardableResult
    func delete(_ account: String) -> Bool {
        let erased = Self.lock.withLock { () -> Bool in
            guard var entries = load() else { return false }
            guard entries.removeValue(forKey: account) != nil else { return true }
            return store(entries)
        }
        return legacyDelete(account) && erased
    }

    // MARK: - The file

    /// Under `lock`. The entries, empty when there is no file yet; `nil` when
    /// it cannot be read (unreadable, not ours to parse): nothing is then
    /// written over it.
    private func load() -> [String: String]? {
        guard let file else { return nil }
        guard let data = try? Data(contentsOf: file) else {
            return FileManager.default.fileExists(atPath: file.path) ? nil : [:]
        }
        guard let entries = try? JSONDecoder().decode([String: String].self, from: data) else {
            Self.log.error("secrets file unreadable")
            return nil
        }
        return entries
    }

    /// Under `lock`. Owner-only directory and file, swapped in at once.
    private func store(_ entries: [String: String]) -> Bool {
        guard let file else { return false }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(entries),
              PrivateFileStore.createDirectory(at: file.deletingLastPathComponent()) else { return false }
        return PrivateFileStore.write(data, to: file)
    }

    // MARK: - The Keychain of earlier versions

    private func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    /// Its attributes only: never a dialog.
    private func legacyExists(_ account: String) -> Bool {
        var query = query(account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let dictionary = query as CFDictionary
        return bounded { SecItemCopyMatching(dictionary, nil) } == errSecSuccess
    }

    /// Read there one last time and kept in the file.
    private func moveLegacy(_ account: String) -> Read {
        guard legacyExists(account) else { return .missing }
        var query = query(account)
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
        guard status == errSecSuccess, let data, !data.isEmpty else {
            Self.log.error("keychain read refused: \(status, privacy: .public)")
            return .failed
        }
        if !save(data, account: account) { Self.log.error("not copied out of the keychain") }
        return .found(data)
    }

    /// `true` when the Keychain has none left.
    private func legacyDelete(_ account: String) -> Bool {
        guard legacyExists(account) else { return true }
        let dictionary = query(account) as CFDictionary
        let status = bounded { SecItemDelete(dictionary) }
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Runs one Keychain call on a queue of its own and waits `timeout` for
    /// it; `nil` when it did not come back.
    private func bounded<Value>(_ call: @escaping () -> Value) -> Value? {
        let box = Box<Value>()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            let value = call()
            box.lock.withLock { box.value = value }
            done.signal()
        }
        guard done.wait(timeout: .now() + timeout) == .success else {
            Self.log.error("no answer in \(Int(timeout), privacy: .public) s")
            return nil
        }
        return box.lock.withLock { box.value }
    }

    private final class Box<Value>: @unchecked Sendable {
        let lock = NSLock()
        var value: Value?
    }
}
