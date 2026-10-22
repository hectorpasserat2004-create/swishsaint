// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The exporters' secrets in their owner-only file (`ForkMeetingKeychain`):
/// saved, read, replaced and erased there; a file it cannot read is never
/// written over. The service is one no Keychain has, so nothing is copied
/// from there and no dialog can show.
enum ForkMeetingSecretsTests {
    static func run(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("fork-meeting-secrets-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("MeetingSecrets.json")
        let store = ForkMeetingKeychain(service: "swishsaint.tests.\(UUID().uuidString)", file: file, timeout: 5)
        let token = "castral-token#A"

        suite.expect(store.read(token) == .missing && !store.exists(token) && store.delete(token),
                     "without a file, a secret is missing and erasing it is done")
        suite.expect(store.save(Data("first".utf8), account: token) && store.read(token) == .found(Data("first".utf8))
                        && store.exists(token),
                     "a saved secret reads back")
        let mode = (try? FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int) ?? nil
        suite.expect(mode == 0o600, "the file is the owner's alone")
        suite.expect(store.save(Data("second".utf8), account: token) && store.save(Data("{\"a\":1}".utf8), account: "exporters")
                        && store.read(token) == .found(Data("second".utf8)),
                     "saving again replaces it, beside the other accounts")
        suite.expect(!store.save(Data(), account: token) && !store.save(Data([0xFF, 0xFE]), account: token)
                        && store.read(token) == .found(Data("second".utf8)),
                     "an empty secret or one that is not text is refused and changes nothing")
        suite.expect(store.delete(token) && store.read(token) == .missing && store.read("exporters") == .found(Data("{\"a\":1}".utf8)),
                     "erasing one leaves the others")

        try? Data("not json".utf8).write(to: file)
        suite.expect(store.read("exporters") == .failed && !store.save(Data("x".utf8), account: token)
                        && (try? String(contentsOf: file, encoding: .utf8)) == "not json",
                     "a file it cannot read fails and is never written over")

        let nowhere = ForkMeetingKeychain(service: "swishsaint.tests.\(UUID().uuidString)", file: nil, timeout: 5)
        suite.expect(nowhere.read(token) == .failed && !nowhere.save(Data("x".utf8), account: token),
                     "outside a real bundle, nothing is kept")
    }
}
