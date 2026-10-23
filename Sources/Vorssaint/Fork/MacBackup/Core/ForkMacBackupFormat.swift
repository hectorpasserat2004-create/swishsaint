// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Sizes, durations, ages and rates in the person's language. Pure: the
/// locale is passed in (`AppLanguage.formattingLocale()` in the app), so
/// tests pin it. Never assume a 24-hour clock: the locale's hour cycle
/// decides (the CI runs in 12-hour).
enum ForkMacBackupFormat {
    /// How a source is named everywhere (island, window, settings): a home
    /// folder is « Dossier personnel » (this Mac's, or `userName`'s on
    /// another Mac), any other source its folder's name. Never the account's
    /// name.
    static func sourceName(_ path: String, text: ForkMacBackupStrings, userName: String? = nil,
                           home: String = NSHomeDirectory()) -> String {
        func trimmed(_ value: String) -> String {
            var value = value
            while value.count > 1, value.hasSuffix("/") { value.removeLast() }
            return value
        }
        let normalized = trimmed(path)
        if normalized == trimmed(home) { return text.homeFolder }
        if let userName, !userName.isEmpty, normalized == "/Users/" + userName { return text.homeFolder }
        let name = (normalized as NSString).lastPathComponent
        return name.isEmpty || name == "/" ? normalized : name
    }

    /// A size as the Finder writes it (« 1,3 Go »). Every size the feature
    /// shows is a real one (decision 1 of 22/10): sparse images are out of
    /// the sources by default, and the scanner reads allocated sizes.
    static func bytes(_ count: Int64, locale: Locale) -> String {
        max(0, count).formatted(.byteCount(style: .file).locale(locale))
    }

    /// « 18 Mo/s »; nil for no rate yet.
    static func rate(_ bytesPerSecond: Double?, locale: Locale) -> String? {
        guard let bytesPerSecond, bytesPerSecond.isFinite, bytesPerSecond >= 0 else { return nil }
        return bytes(Int64(bytesPerSecond.rounded()), locale: locale) + "/s"
    }

    /// « 2 h 5 min », at most two units, nothing under a minute but « < 1 min ».
    static func duration(_ seconds: TimeInterval, locale: Locale) -> String {
        guard seconds.isFinite else { return "–" }
        let rounded = max(0, seconds.rounded())
        if rounded < 60 {
            return "< " + Duration.seconds(60).formatted(
                .units(allowed: [.minutes], width: .abbreviated).locale(locale))
        }
        let units: Set<Duration.UnitsFormatStyle.Unit> = rounded >= 2 * 86_400 ? [.days, .hours] : [.hours, .minutes]
        return Duration.seconds(Int64(rounded)).formatted(
            .units(allowed: units, width: .abbreviated, maximumUnitCount: 2).locale(locale))
    }

    /// An age in its largest unit, « 2 h », « 3 j », for « Protégé il y a %@ »
    /// and the island's ring.
    static func age(_ seconds: TimeInterval, locale: Locale) -> String {
        guard seconds.isFinite else { return "–" }
        let value = max(0, seconds)
        let units: Set<Duration.UnitsFormatStyle.Unit>
        if value < 3_600 {
            units = [.minutes]
        } else if value < 2 * 86_400 {
            units = [.hours]
        } else {
            units = [.days]
        }
        let shown = max(60, value)
        return Duration.seconds(Int64(shown.rounded(.down))).formatted(
            .units(allowed: units, width: .abbreviated, maximumUnitCount: 1, fractionalPart: .hide(rounded: .down))
                .locale(locale))
    }

    /// « il y a 2 h », « in 3 hr. ».
    static func relative(_ date: Date, now: Date, locale: Locale) -> String {
        relativeFormatter(locale).localizedString(for: date, relativeTo: now)
    }

    /// A time of day in the locale's own clock (« 10:04 PM » or « 22:04 »).
    static func time(_ date: Date, locale: Locale, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// A day and a time, « 22 oct., 10:04 ».
    static func dayAndTime(_ date: Date, locale: Locale, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// A count in at most 5 characters, the locale's own compact form
    /// (« 1,2 M », « 845 k », « 312 »): the closed island's files examined.
    static func count(_ value: Int64, locale: Locale) -> String {
        let value = max(0, value)
        let digits = value >= 1_000_000 ? 1...2 : 1...3
        return value.formatted(.number.notation(.compactName).precision(.significantDigits(digits)).locale(locale))
    }

    /// « 42 % » in the locale's own percent.
    static func percent(_ fraction: Double, locale: Locale) -> String {
        let clamped = fraction.isFinite ? min(1, max(0, fraction)) : 0
        return clamped.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    /// « 0,8 % » for a battery drop in points.
    static func batteryPoints(_ points: Double, locale: Locale) -> String {
        let value = points.isFinite ? max(0, points) / 100 : 0
        return value.formatted(.percent.precision(.fractionLength(0...1)).locale(locale))
    }

    /// A path for one line: the middle cut, both ends kept
    /// (« ~/Documents/Castral/…/pronic.com »).
    static func middleTruncated(_ path: String, limit: Int, home: String? = NSHomeDirectory()) -> String {
        var text = path
        if let home, !home.isEmpty, text.hasPrefix(home) {
            text = "~" + text.dropFirst(home.count)
        }
        guard limit > 1, text.count > limit else { return text }
        let keep = limit - 1
        let head = keep / 2
        let tail = keep - head
        return String(text.prefix(head)) + "…" + String(text.suffix(tail))
    }

    private static func relativeFormatter(_ locale: Locale) -> RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.dateTimeStyle = .numeric
        formatter.unitsStyle = .short
        return formatter
    }

    /// This Mac's host name as Kopia names it (`gethostname`, before the
    /// first dot), read once: `ProcessInfo.hostName` goes through DNS and
    /// may block for seconds on the main thread.
    static let localHostName: String = {
        var buffer = [CChar](repeating: 0, count: 256)
        guard gethostname(&buffer, buffer.count) == 0 else { return "" }
        let name = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return name.split(separator: ".").first.map(String.init) ?? ""
    }()
}
