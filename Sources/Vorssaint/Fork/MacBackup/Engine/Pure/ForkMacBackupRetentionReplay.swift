// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Kopia's retention, replayed (plan §7.2): which snapshots a retention
/// would keep, and why, BEFORE it is applied. `snapshot expire` without
/// `--delete` only prints a count (SPIKES §4); this lists them.
///
/// A line-by-line port of `snapshot/policy/retention_policy.go`
/// (`ComputeRetentionReasons`, v0.23.1), checked against `snapshot list
/// --json`'s own `retentionReason` on the bench. Its quirks are kept on
/// purpose: period names (« 2026-10-22 15 ») are formatted in UTC while the
/// ISO week and the cut-off dates use the Mac's time zone, the newest
/// incomplete snapshots are kept while younger than 4 h or among the 3
/// newest, and all-zero counts keep everything.
enum ForkMacBackupRetentionReplay {
    struct Snapshot: Equatable {
        var id: String
        var startTime: Date
        var endTime: Date?
        /// Kopia's `incomplete` reason; nil when whole.
        var incomplete: String?

        init(id: String, startTime: Date, endTime: Date? = nil, incomplete: String? = nil) {
            self.id = id
            self.startTime = startTime
            self.endTime = endTime
            self.incomplete = incomplete
        }

        /// From a manifest; nil without a start time.
        init?(manifest: ForkMacBackupKopia.SnapshotManifest) {
            guard let start = manifest.startDate else { return nil }
            self.init(id: manifest.id, startTime: start, endTime: manifest.endDate, incomplete: manifest.incomplete)
        }
    }

    struct Verdict: Equatable {
        var snapshot: Snapshot
        /// « latest-1 », « daily-3 », « incomplete »… Empty: deleted.
        var reasons: [String]

        var isKept: Bool { !reasons.isEmpty }
    }

    static let retainIncompleteYoungerThan: TimeInterval = 4 * 3600
    static let retainIncompleteMinimumCount = 3

    /// Every snapshot of ONE source, newest first, with its reasons.
    static func evaluate(_ snapshots: [Snapshot], retention: ForkMacBackupRetention,
                         timeZone: TimeZone = .current) -> [Verdict] {
        guard !snapshots.isEmpty else { return [] }
        // ISO 8601 weeks (Monday first, week 1 holds the year's first Thursday), as Go's `ISOWeek`.
        var local = Calendar(identifier: .iso8601)
        local.timeZone = timeZone
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!

        var maxStart = Date.distantPast
        var maxCompleteStart = Date.distantPast
        for snapshot in snapshots {
            maxStart = max(maxStart, snapshot.startTime)
            if snapshot.incomplete == nil { maxCompleteStart = max(maxCompleteStart, snapshot.startTime) }
        }
        // Go's zero time when nothing is complete: every cut-off is far back.
        if maxCompleteStart == .distantPast { maxCompleteStart = Date(timeIntervalSince1970: -62_135_596_800) }

        let cutoffAnnual = goAddDate(maxCompleteStart, years: -retention.annual, calendar: local)
        let cutoffMonthly = goAddDate(maxCompleteStart, months: -retention.monthly, calendar: local)
        let cutoffDaily = goAddDate(maxCompleteStart, days: -retention.daily, calendar: local)
        let cutoffWeekly = goAddDate(maxCompleteStart, days: -retention.weekly * 7, calendar: local)
        let cutoffHourly = maxCompleteStart.addingTimeInterval(-Double(retention.hourly) * 3600)

        let allZero = retention.latest + retention.hourly + retention.daily + retention.weekly
            + retention.monthly + retention.annual == 0
        let keepLatest = allZero ? Int.max : retention.latest

        let sorted = snapshots.sorted { a, b in
            if a.startTime != b.startTime { return a.startTime > b.startTime }
            return (a.endTime ?? .distantPast) > (b.endTime ?? .distantPast)
        }

        var ids = Set<String>()
        var counters: [String: Int] = [:]
        var verdicts: [Verdict] = []
        for (index, snapshot) in sorted.enumerated() {
            guard snapshot.incomplete == nil else {
                verdicts.append(Verdict(snapshot: snapshot, reasons: []))
                continue
            }
            let start = snapshot.startTime
            let week = local.dateComponents([.yearForWeekOfYear, .weekOfYear], from: start)
            let isoWeek = String(format: "%04d-%02d", week.yearForWeekOfYear ?? 0, week.weekOfYear ?? 0)
            let cases: [(cutoff: Date?, id: String, kind: String, max: Int)] = [
                (nil, String(index), "latest", keepLatest),
                (cutoffAnnual, format(start, "yyyy", utc), "annual", retention.annual),
                (cutoffMonthly, format(start, "yyyy-MM", utc), "monthly", retention.monthly),
                (cutoffWeekly, isoWeek, "weekly", retention.weekly),
                (cutoffDaily, format(start, "yyyy-MM-dd", utc), "daily", retention.daily),
                (cutoffHourly, format(start, "yyyy-MM-dd HH", utc), "hourly", retention.hourly),
            ]
            var reasons: [String] = []
            for entry in cases {
                if let cutoff = entry.cutoff, start < cutoff { continue }
                if ids.contains(entry.id) { continue }
                if counters[entry.kind, default: 0] < entry.max {
                    ids.insert(entry.id)
                    counters[entry.kind, default: 0] += 1
                    reasons.append("\(entry.kind)-\(counters[entry.kind]!)")
                }
            }
            verdicts.append(Verdict(snapshot: snapshot, reasons: sortedReasons(reasons)))
        }

        // The newest incomplete snapshots, until the first complete one.
        for index in verdicts.indices {
            let snapshot = verdicts[index].snapshot
            guard snapshot.incomplete != nil else { break }
            let age = maxStart.timeIntervalSince(snapshot.startTime)
            if age < retainIncompleteYoungerThan || index < retainIncompleteMinimumCount {
                verdicts[index].reasons.append("incomplete")
            } else {
                break
            }
        }
        return verdicts
    }

    /// The snapshots `retention` would delete, newest first.
    static func deletions(_ snapshots: [Snapshot], retention: ForkMacBackupRetention,
                          timeZone: TimeZone = .current) -> [Snapshot] {
        evaluate(snapshots, retention: retention, timeZone: timeZone).filter { !$0.isKept }.map(\.snapshot)
    }

    /// Kopia's order: latest, hourly, daily, weekly, monthly, annual, then
    /// by name.
    static func sortedReasons(_ reasons: [String]) -> [String] {
        let rank = ["latest": 1, "hourly": 2, "daily": 3, "weekly": 4, "monthly": 5, "annual": 6]
        func split(_ reason: String) -> (String, String) {
            guard let dash = reason.lastIndex(of: "-") else { return (reason, "") }
            return (String(reason[..<dash]), String(reason[reason.index(after: dash)...]))
        }
        return reasons.sorted { a, b in
            let (p1, s1) = split(a)
            let (p2, s2) = split(b)
            let r1 = rank[p1] ?? 0
            let r2 = rank[p2] ?? 0
            if r1 != r2 { return r1 < r2 }
            if p1 != p2 { return p1 < p2 }
            return s1 < s2
        }
    }

    /// Go's `time.AddDate`: the fields are added, then normalized, so
    /// 31 March minus one month is 3 March (31 February), not 28 February.
    static func goAddDate(_ date: Date, years: Int = 0, months: Int = 0, days: Int = 0, calendar: Calendar) -> Date {
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date)
        parts.year = (parts.year ?? 0) + years
        parts.month = (parts.month ?? 1) + months
        parts.day = (parts.day ?? 1) + days
        return calendar.date(from: parts) ?? date
    }

    private static func format(_ date: Date, _ pattern: String, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
