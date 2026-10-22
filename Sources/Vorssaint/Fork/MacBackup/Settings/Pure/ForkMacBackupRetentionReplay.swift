// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Kopia's retention, replayed without Kopia (`snapshot/policy/retention_policy.go`
/// of v0.23.1), to show which snapshots a new setting would delete before it
/// is applied (plan §7.2). The newest first: each snapshot is kept by the
/// first « slot » of each rule it fills (the 10 latest, one per hour for 48
/// hours…), a slot counted once whatever rule fills it.
enum ForkMacBackupRetentionReplay {
    struct Snapshot: Equatable {
        var id: String
        var start: Date
        /// Kopia's `incomplete` reason (a checkpoint, a cancel).
        var incomplete: Bool
        var bytes: Int64?

        init(id: String, start: Date, incomplete: Bool = false, bytes: Int64? = nil) {
            self.id = id
            self.start = start
            self.incomplete = incomplete
            self.bytes = bytes
        }
    }

    enum Rule: String, CaseIterable {
        case latest
        case annual
        case monthly
        case weekly
        case daily
        case hourly
        /// An incomplete snapshot newer than every complete one.
        case incomplete
    }

    struct Decision: Equatable {
        var snapshot: Snapshot
        var reasons: [Rule]

        var kept: Bool { !reasons.isEmpty }
    }

    /// Every snapshot with why it stays (an empty list: deleted), newest first.
    static func evaluate(_ snapshots: [Snapshot], retention: ForkMacBackupRetention, now: Date,
                         calendar: Calendar = .current) -> [Decision] {
        let sorted = snapshots.sorted { ($0.start, $0.id) > ($1.start, $1.id) }
        let cutoffs: [Rule: Date] = [
            .annual: calendar.date(byAdding: .year, value: -retention.annual, to: now) ?? .distantPast,
            .monthly: calendar.date(byAdding: .month, value: -retention.monthly, to: now) ?? .distantPast,
            .weekly: calendar.date(byAdding: .day, value: -7 * retention.weekly, to: now) ?? .distantPast,
            .daily: calendar.date(byAdding: .day, value: -retention.daily, to: now) ?? .distantPast,
            .hourly: now.addingTimeInterval(-TimeInterval(retention.hourly) * 3_600),
        ]
        let limits: [Rule: Int] = [.latest: retention.latest, .annual: retention.annual, .monthly: retention.monthly,
                                   .weekly: retention.weekly, .daily: retention.daily, .hourly: retention.hourly]
        let newestComplete = sorted.first { !$0.incomplete }?.start

        var seenPeriods = Set<String>()
        var counters: [Rule: Int] = [:]
        var completeIndex = 0
        var decisions: [Decision] = []
        for snapshot in sorted {
            if snapshot.incomplete {
                // Kept only while no complete snapshot came after it.
                let keep = newestComplete.map { snapshot.start > $0 } ?? true
                decisions.append(Decision(snapshot: snapshot, reasons: keep ? [.incomplete] : []))
                continue
            }
            var reasons: [Rule] = []
            for rule in [Rule.latest, .annual, .monthly, .weekly, .daily, .hourly] {
                let limit = limits[rule] ?? 0
                guard limit > 0 else { continue }
                if let cutoff = cutoffs[rule], snapshot.start < cutoff { continue }
                let period = periodID(rule, of: snapshot.start, index: completeIndex, calendar: calendar)
                guard !seenPeriods.contains(period), counters[rule, default: 0] < limit else { continue }
                seenPeriods.insert(period)
                counters[rule, default: 0] += 1
                reasons.append(rule)
            }
            completeIndex += 1
            decisions.append(Decision(snapshot: snapshot, reasons: reasons))
        }
        return decisions
    }

    /// The snapshots `retention` would delete, newest first.
    static func deletions(_ snapshots: [Snapshot], retention: ForkMacBackupRetention, now: Date,
                          calendar: Calendar = .current) -> [Snapshot] {
        evaluate(snapshots, retention: retention, now: now, calendar: calendar).filter { !$0.kept }.map(\.snapshot)
    }

    /// Kopia's period keys: « latest-3 », « 2026 », « 2026-10 », ISO week,
    /// « 2026-10-22 », « 2026-10-22 14 », in the Mac's own time zone.
    static func periodID(_ rule: Rule, of date: Date, index: Int, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        let year = parts.year ?? 0
        let month = parts.month ?? 0
        let day = parts.day ?? 0
        switch rule {
        case .latest, .incomplete: return "latest-\(index)"
        case .annual: return String(format: "%04d", year)
        case .monthly: return String(format: "%04d-%02d", year, month)
        case .weekly:
            var iso = Calendar(identifier: .iso8601)
            iso.timeZone = calendar.timeZone
            let week = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return String(format: "%04d-W%02d", week.yearForWeekOfYear ?? 0, week.weekOfYear ?? 0)
        case .daily: return String(format: "%04d-%02d-%02d", year, month, day)
        case .hourly: return String(format: "%04d-%02d-%02d %02d", year, month, day, parts.hour ?? 0)
        }
    }

    /// From Kopia's manifests: one source's, by start time.
    static func snapshots(from manifests: [ForkMacBackupKopia.SnapshotManifest]) -> [Snapshot] {
        manifests.compactMap { manifest in
            guard let start = manifest.startDate else { return nil }
            return Snapshot(id: manifest.id, start: start, incomplete: manifest.incomplete != nil,
                            bytes: manifest.stats?.totalSize ?? manifest.rootEntry?.summ?.size)
        }
    }
}
