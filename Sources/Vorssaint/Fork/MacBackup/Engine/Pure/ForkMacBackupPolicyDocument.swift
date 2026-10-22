// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// A source's Kopia policy as JSON, written in ONE call (the server's
/// `PUT /api/v1/policy`, or `policy import`), then read back and turned into
/// `ForkMacBackupPolicyRules` for the caller's `==` (plan §4.3, audit
/// defect 13: never a two-step write).
///
/// Only what the feature owns is set: the ignore list (replaced whole),
/// `ignoreCacheDirs`, `scheduling.manual` (always true: our planner decides,
/// SPIKES §4) and the six `keep*` counts. Every other part of an existing
/// definition (compression, actions…) is kept as it was.
enum ForkMacBackupPolicyDocument {
    /// `existing` (the definition read before, nil when none) with the
    /// rules written over it.
    static func merged(_ existing: [String: Any]?, rules: ForkMacBackupPolicyRules) -> [String: Any] {
        var policy = existing ?? [:]
        var files = policy["files"] as? [String: Any] ?? [:]
        files["ignore"] = rules.ignoreRules
        files["ignoreCacheDirs"] = rules.ignoreCacheDirs
        policy["files"] = files

        var scheduling = policy["scheduling"] as? [String: Any] ?? [:]
        // Our planner owns the rhythm: no interval, no times, no cron.
        for key in ["intervalSeconds", "timeOfDay", "cron"] { scheduling.removeValue(forKey: key) }
        scheduling["manual"] = true
        policy["scheduling"] = scheduling

        var retention = policy["retention"] as? [String: Any] ?? [:]
        let keep = rules.retention
        retention["keepLatest"] = keep.latest
        retention["keepHourly"] = keep.hourly
        retention["keepDaily"] = keep.daily
        retention["keepWeekly"] = keep.weekly
        retention["keepMonthly"] = keep.monthly
        retention["keepAnnual"] = keep.annual
        policy["retention"] = retention
        return policy
    }

    /// The JSON bytes (sorted keys: a stable file and a stable request).
    static func data(_ policy: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: policy, options: [.sortedKeys])
    }

    /// `policy import`'s file: `{ "user@host:/path": policy }`.
    static func importData(_ policy: [String: Any], identity: ForkMacBackupRepository.Identity, path: String) -> Data? {
        data([target(identity: identity, path: path): policy])
    }

    /// `user@host:/path`, as Kopia names a source.
    static func target(identity: ForkMacBackupRepository.Identity, path: String) -> String {
        "\(identity.userName)@\(identity.hostName):\(path)"
    }

    /// A JSON object, nil for anything else (an empty body, an error page).
    static func object(_ data: Data) -> [String: Any]? {
        guard !data.isEmpty, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    /// `policy export`'s output: the policy under its single key.
    static func exported(_ data: Data) -> [String: Any]? {
        guard let object = object(data) else { return nil }
        if object.count == 1, let only = object.values.first as? [String: Any] { return only }
        return object
    }

    /// The rules a policy carries; nil unless it has the four parts the
    /// feature writes (a policy we did not write reads as « not applied »).
    static func rules(from policy: [String: Any]) -> ForkMacBackupPolicyRules? {
        guard let files = policy["files"] as? [String: Any],
              let retention = policy["retention"] as? [String: Any] else { return nil }
        let ignore = (files["ignore"] as? [Any] ?? []).compactMap { $0 as? String }
        let cacheDirs = bool(files["ignoreCacheDirs"]) ?? false
        let manual = bool((policy["scheduling"] as? [String: Any])?["manual"]) ?? false
        guard let latest = int(retention["keepLatest"]), let hourly = int(retention["keepHourly"]),
              let daily = int(retention["keepDaily"]), let weekly = int(retention["keepWeekly"]),
              let monthly = int(retention["keepMonthly"]), let annual = int(retention["keepAnnual"]) else {
            return nil
        }
        return ForkMacBackupPolicyRules(ignoreRules: ignore, ignoreCacheDirs: cacheDirs, manual: manual,
                                        retention: ForkMacBackupRetention(latest: latest, hourly: hourly, daily: daily,
                                                                          weekly: weekly, monthly: monthly,
                                                                          annual: annual))
    }

    private static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let number = value as? NSNumber { return number.boolValue }
        if let text = value as? String { return text == "true" }
        return nil
    }
}
