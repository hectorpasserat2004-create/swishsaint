// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The agent's launchd property list (plan §3.3), in its two forms:
/// - the release one, put in `Contents/Library/LaunchAgents/` by
///   `fork/build-release.sh` (template `fork/macbackup-agent.plist`) and
///   registered with `SMAppService.agent(plistName:)`;
/// - the Developer one, written in `~/Library/LaunchAgents/` and
///   bootstrapped with `launchctl` when the bundle carries none.
/// Pure: the tests check both, and that the template matches.
enum ForkMacBackupAgentPlist {
    /// The launchd label: `<bundle id>.backup-agent`.
    static func label(bundleID: String) -> String { bundleID + ".backup-agent" }

    /// The file name, in the bundle and in `~/Library/LaunchAgents`.
    static func fileName(bundleID: String) -> String { label(bundleID: bundleID) + ".plist" }

    /// Where the release plist lives inside the app.
    static func bundledURL(appURL: URL, bundleID: String) -> URL {
        appURL.appendingPathComponent("Contents/Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent(fileName(bundleID: bundleID), isDirectory: false)
    }

    /// `~/Library/LaunchAgents/<label>.plist`.
    static func legacyURL(home: URL, bundleID: String) -> URL {
        home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent(fileName(bundleID: bundleID), isDirectory: false)
    }

    /// The keys both forms share. `KeepAlive.SuccessfulExit = false`:
    /// relaunched after a crash or an update (the agent exits non-zero to
    /// move to the new binary), never after a clean exit (switched off, a
    /// second instance). `ExitTimeOut`: the clean stop (the snapshot
    /// canceled with its checkpoint, up to 25 s, then the server and a
    /// verification stopped) needs more than launchd's default 20 s before
    /// its SIGKILL, which would orphan a `kopia snapshot verify`.
    private static func common(bundleID: String) -> [String: Any] {
        [
            "Label": label(bundleID: bundleID),
            "KeepAlive": ["SuccessfulExit": false],
            "ExitTimeOut": 60,
            "RunAtLoad": true,
            "ProcessType": "Background",
            "LowPriorityBackgroundIO": true,
            "ThrottleInterval": 30,
            "AssociatedBundleIdentifiers": [bundleID],
        ]
    }

    /// For `SMAppService.agent`: the program is named inside the bundle.
    /// `ProgramArguments[0]` is the program itself, as launchd hands it on
    /// as `argv[0]`.
    static func release(bundleID: String, executable: String) -> [String: Any] {
        var plist = common(bundleID: bundleID)
        let program = "Contents/MacOS/\(executable)"
        plist["BundleProgram"] = program
        plist["ProgramArguments"] = [program, ForkMacBackupAgent.argument]
        return plist
    }

    /// For `launchctl bootstrap gui/<uid>`: the absolute path.
    static func legacy(bundleID: String, executablePath: String) -> [String: Any] {
        var plist = common(bundleID: bundleID)
        plist["Program"] = executablePath
        plist["ProgramArguments"] = [executablePath, ForkMacBackupAgent.argument]
        plist["LimitLoadToSessionType"] = "Aqua"
        return plist
    }

    /// XML, as written on disk.
    static func data(_ plist: [String: Any]) -> Data? {
        try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    /// The template of `fork/macbackup-agent.plist` filled as the release
    /// script fills it (`__LABEL__`, `__BUNDLE_ID__`, `__EXECUTABLE__`).
    static func filledTemplate(_ template: String, bundleID: String, executable: String) -> String {
        template.replacingOccurrences(of: "__LABEL__", with: label(bundleID: bundleID))
            .replacingOccurrences(of: "__BUNDLE_ID__", with: bundleID)
            .replacingOccurrences(of: "__EXECUTABLE__", with: executable)
    }

    /// Whether two property lists say the same (order and format aside).
    static func same(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
        NSDictionary(dictionary: lhs).isEqual(to: rhs)
    }
}
