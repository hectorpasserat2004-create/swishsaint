// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Suite `fork-glance-strings` — A8: the core strings in fifteen languages.
///
/// `mirrorChecks` and its helpers are shared: the settings', assistant's
/// and island's strings (B2, B3, B4) run them on their own structs.
enum ForkGlanceStringsTests {
    static func run(_ suite: TestSuite) {
        mirrorChecks(suite, "ForkGlanceStrings", ForkGlanceStrings.strings,
                     island: island, sameInFrench: sameInFrench, untranslated: untranslated)
        names(suite)
        statusLines(suite)
        tileReadings(suite)
        everyCaseHasItsWords(suite)
        zones(suite)
        notices(suite)
        islandRoom(suite)
        commandBar(suite)
        formatting(suite)
    }

    // MARK: - Shared checks

    /// Every `String` property of a strings struct, by name (Mirror).
    static func fields(_ strings: Any) -> [(String, String)] {
        Mirror(reflecting: strings).children.compactMap { child in
            guard let label = child.label, let value = child.value as? String else { return nil }
            return (label, value)
        }
    }

    /// The checks every Glance strings struct passes (plan §16): fifteen
    /// languages, no empty field, the same fields and placeholders as the
    /// English, the `island` fields in 28 characters once a short name fills
    /// their placeholder, the French typography, no straight apostrophe,
    /// and the French really written (only the `sameInFrench` labels may
    /// match the English).
    ///
    /// `untranslated` checks the thirteen other languages the same way: a
    /// field that reads as the English in one of them fails unless it is
    /// listed (a brand, a unit, a word both languages share). nil leaves
    /// them unchecked, for a struct whose translations are still to come.
    static func mirrorChecks<Strings>(_ suite: TestSuite, _ name: String, _ strings: (AppLanguage) -> Strings,
                                      island: [KeyPath<Strings, String>] = [], sameInFrench: Set<String> = [],
                                      untranslated: Set<String>? = nil, sample: String = "MacBook") {
        let languages = AppLanguage.allCases
        suite.expect(languages.count == 15, "\(name) speaks the app's fifteen languages")
        let english = fields(strings(.enUS))
        let englishByLabel = Dictionary(english, uniquingKeysWith: { first, _ in first })
        suite.expect(!english.isEmpty, "\(name) has texts")

        var empty: [String] = []
        var otherFields: [String] = []
        var placeholders: [String] = []
        for language in languages {
            let texts = fields(strings(language))
            if texts.map(\.0) != english.map(\.0) { otherFields.append(language.rawValue) }
            for (label, value) in texts {
                if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    empty.append("\(language.rawValue).\(label)")
                }
                let reference = englishByLabel[label].flatMap { TestFormat.parse($0)?.arguments }
                if TestFormat.parse(value)?.arguments != reference { placeholders.append("\(language.rawValue).\(label)") }
            }
        }
        suite.expect(empty.isEmpty, "every \(name) text exists in every language: \(empty)")
        suite.expect(otherFields.isEmpty, "every language fills the same \(name) fields: \(otherFields)")
        suite.expect(placeholders.isEmpty, "every \(name) text takes the same placeholders as the English: \(placeholders)")

        var long: [String] = []
        for language in languages {
            let table = strings(language)
            for path in island {
                let shown = filled(table[keyPath: path], with: sample)
                if shown.count > 28 { long.append("\(language.rawValue): \(shown)") }
            }
        }
        suite.expect(long.isEmpty, "every \(name) text the island shows fits in 28 characters: \(long)")

        let french = fields(strings(.fr))
        let loose = frenchTypographyProblems(french.map(\.1))
        suite.expect(loose.isEmpty, "\(name)'s French uses no-break spaces, typographic apostrophes, no capital after « · »: \(loose)")
        let straight = languages.flatMap { fields(strings($0)).map(\.1) }.filter { $0.contains("'") }
        suite.expect(straight.isEmpty, "no \(name) text uses a straight apostrophe: \(straight)")
        let leftInEnglish = french.filter { englishByLabel[$0.0] == $0.1 && !sameInFrench.contains($0.0) }.map(\.0)
        suite.expect(leftInEnglish.isEmpty, "every \(name) text is written in French, none left in English: \(leftInEnglish)")

        guard let untranslated else { return }
        let unknown = untranslated.filter { englishByLabel[$0] == nil }.sorted()
        suite.expect(unknown.isEmpty, "\(name)'s untranslated list names only its own fields: \(unknown)")
        var stillEnglish: [String] = []
        for language in languages where language != .enUS && language != .fr {
            stillEnglish += fields(strings(language))
                .filter { englishByLabel[$0.0] == $0.1 && !untranslated.contains($0.0) }
                .map { "\(language.rawValue).\($0.0)" }
        }
        suite.expect(stillEnglish.isEmpty, "every \(name) text is translated in every language, none left in English: \(stillEnglish)")
    }

    /// A template as shown: each `%@` or `%n$@` filled with `sample`, each
    /// `%d` or `%n$d` with « 30 ».
    static func filled(_ template: String, with sample: String) -> String {
        template.replacingOccurrences(of: #"%([0-9]+\$)?@"#, with: sample, options: .regularExpression)
            .replacingOccurrences(of: #"%([0-9]+\$)?l?d"#, with: "30", options: .regularExpression)
    }

    /// The French texts that break the official typography: a straight
    /// apostrophe, a plain space (or none) before « : ; ! ? » or inside
    /// « », a capital right after « · ». A colon between digits is a time.
    /// `capitalAfterDot` lets a filled line keep a name's capital
    /// (« Actif · Zone gauche du LG »): templates never allow it.
    static func frenchTypographyProblems(_ texts: [String], capitalAfterDot: Bool = false) -> [String] {
        let tight: Set<Character> = ["\u{00A0}", "\u{202F}"]
        return texts.filter { text in
            if text.contains("'") { return true }
            let characters = Array(text)
            for (index, character) in characters.enumerated() {
                let before = index > 0 ? characters[index - 1] : nil
                let after = index + 1 < characters.count ? characters[index + 1] : nil
                switch character {
                case ":" where before?.isNumber == true && after?.isNumber == true:
                    continue
                case ":", ";", "!", "?", "»":
                    if before.map(tight.contains) != true { return true }
                case "«":
                    if after.map(tight.contains) != true { return true }
                case "·" where !capitalAfterDot:
                    if index + 2 < characters.count, characters[index + 1] == " ",
                       characters[index + 2].isUppercase { return true }
                default:
                    continue
                }
            }
            return false
        }
    }

    /// The texts over 28 characters, prefixed for the failure message.
    static func tooLong(_ texts: [String], _ prefix: String = "") -> [String] {
        texts.filter { $0.count > 28 }.map { prefix + $0 }
    }

    // MARK: - This struct

    private static let languages = AppLanguage.allCases
    private static let all = languages.map(ForkGlanceStrings.strings)
    private static let english = ForkGlanceStrings.strings(.enUS)
    private static let french = ForkGlanceStrings.strings(.fr)
    private static let frenchLocale = Locale(identifier: "fr_FR")
    private static let englishLocale = Locale(identifier: "en_US")
    private static let paris = TimeZone(identifier: "Europe/Paris")!

    /// Thursday 23 October 2026, 15:28 in Paris.
    private static let now: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = paris
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 15, minute: 28))!
    }()

    private static let tomorrow: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = paris
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
    }()

    /// The fields shown in the island as they are.
    private static let island: [KeyPath<ForkGlanceStrings, String>] = [
        \.sectionTitle,
        \.guardTyping, \.guardPointer, \.guardButtonsOrModifiers, \.guardSecureInput, \.guardDictation,
        \.guardMenuOrOverview, \.guardIslandOpen, \.guardOwnPanel, \.guardExcludedSource, \.guardCalibrating,
        \.guardCooldown, \.guardLowConfidence,
        \.shortUser, \.shortLocked, \.shortAsleep, \.shortScreensAsleep, \.shortSessionInactive, \.shortIdle,
        \.shortBattery, \.shortLowPower, \.shortThermal, \.shortCameraBusy, \.shortCall, \.shortSingleScreen,
        \.shortLidClosed,
        \.shortCameraPermission, \.shortAccessibility, \.shortNoCamera, \.shortCameraDisconnected, \.shortCameraFailed,
        \.shortNeedFirstTime, \.shortNeedNewLayout, \.shortNeedNewCamera, \.shortNeedRemoved,
        \.zoneWhole, \.zoneLeft, \.zoneCenter, \.zoneRight, \.zoneTop, \.zoneBottom, \.zoneTopLeft, \.zoneTopRight,
        \.zoneBottomLeft, \.zoneBottomRight, \.zoneWindowOn, \.zoneWindowApp, \.builtInDisplay,
        \.modeScreens, \.modeZones, \.modeWindows,
        \.splitWhole, \.splitColumns2, \.splitColumns3, \.splitRows2, \.splitGrid2x2,
        \.gradeExcellent, \.gradeGood, \.gradeFair, \.gradePoor,
        \.durationFifteenMinutes, \.durationOneHour, \.durationUntilTomorrow, \.durationUntilResumed,
        \.noticePaused, \.noticeResumed, \.noticeNewLayout, \.noticeCameraUnavailable, \.noticeRecentered,
        \.noticeDrift, \.noticePausedTomorrow, \.noticePausedIndefinitely, \.noticeNewLayoutDetail,
        \.noticeCameraDetail, \.noticeDriftDetail,
        \.pause, \.resume, \.resumeAnyway, \.recenter, \.calibrate, \.calibrateEllipsis, \.recalibrate,
        \.quickRecenter, \.test, \.enable, \.openSettings, \.allowCamera, \.allowAccessibility, \.retry,
        \.chooseCamera, \.switchToZones, \.recentSwitches,
    ]

    /// French words that are the English ones too.
    private static let sameInFrench: Set<String> = ["builtInDisplay", "modeZones", "feedbackHalo", "pause"]

    /// Words the other languages share with the English: the built-in
    /// display's name, and « Halo » (German, Spanish, Portuguese).
    private static let untranslated: Set<String> = ["builtInDisplay", "feedbackHalo"]

    private static func names(_ suite: TestSuite) {
        suite.expect(zip(languages, all).allSatisfy { $0.1.featureTitle == ForkExtrasStrings.strings($0.0).glanceTitle },
                     "the feature has the Extras page's name in every language")
        suite.expect(french.featureTitle == "Focus au regard" && english.featureTitle == "Glance Focus"
                        && french.sectionTitle == "Regard" && english.sectionTitle == "Glance",
                     "the feature is Focus au regard, its island section Regard (Glance Focus and Glance in English)")
        suite.expect(!fields(french).contains { $0.1.localizedCaseInsensitiveContains("concentration") },
                     "the French never calls it Concentration, macOS's Focus")
        suite.expect(all.allSatisfy { $0.searchKeywords.split(separator: ",").count >= 5 },
                     "the Settings search finds the feature by several words in every language")
    }

    private static func sampleLines() -> [ForkGlanceStatusLine] {
        var lines: [ForkGlanceStatusLine] = [.off, .calibrating(done: 0, total: 0), .calibrating(done: 12, total: 30),
                                             .starting, .active(zoneName: nil), .active(zoneName: "Zone gauche du LG"),
                                             .noFace, .away]
        lines += ForkGlanceUnavailable.allCases.map { .unavailable($0) }
        lines += ForkGlanceCalibrationNeed.allCases.map { .needsCalibration($0) }
        lines += ForkGlanceGuard.allCases.map { .waiting($0) }
        lines += ForkGlancePauseReason.allCases.map { .paused($0, until: nil) }
        lines += [.paused(.user, until: now.addingTimeInterval(14 * 60)), .paused(.user, until: tomorrow),
                  .paused(.user, until: now.addingTimeInterval(3 * 86_400)), .paused(.user, until: now.addingTimeInterval(-60)),
                  .paused(.battery, until: now.addingTimeInterval(600))]
        return lines
    }

    private static func statusLines(_ suite: TestSuite) {
        let lines = sampleLines()
        var empty: [String] = []
        for (language, strings) in zip(languages, all) {
            for line in lines where strings.status(line, locale: frenchLocale, timeZone: paris, now: now).isEmpty {
                empty.append("\(language.rawValue): \(line)")
            }
        }
        suite.expect(empty.isEmpty, "every status line has its words in every language: \(empty)")

        func fr(_ line: ForkGlanceStatusLine) -> String { french.status(line, locale: frenchLocale, timeZone: paris, now: now) }
        func en(_ line: ForkGlanceStatusLine) -> String { english.status(line, locale: englishLocale, timeZone: paris, now: now) }
        suite.expect(fr(.active(zoneName: french.zoneName(.left, display: "LG"))) == "Actif · Zone gauche du LG"
                        && fr(.active(zoneName: nil)) == "Actif",
                     "an active line names the zone the keyboard is in, once one is known")
        suite.expect(fr(.waiting(.typing)) == "En attente\u{00A0}: vous tapez" && fr(.waiting(.pointer)) == "En attente\u{00A0}: souris"
                        && en(.waiting(.typing)) == "Waiting: you are typing",
                     "a held switch says which guard holds it")
        suite.expect(fr(.noFace) == "Visage non détecté" && fr(.unavailable(.noCamera)) == "Aucune caméra"
                        && fr(.needsCalibration(.newLayout)) == "Calibrez pour cette disposition",
                     "no face, no camera and a new layout each say so")
        suite.expect(fr(.paused(.user, until: now.addingTimeInterval(14 * 60))) == "En pause — reprise à 15:42"
                        && en(.paused(.user, until: now.addingTimeInterval(14 * 60))).contains("3:42"),
                     "a timed pause says when it ends, in the person's clock")
        suite.expect(fr(.paused(.user, until: tomorrow)) == "En pause jusqu’à demain",
                     "a pause until tomorrow says tomorrow, not midnight")
        suite.expect(fr(.paused(.user, until: now.addingTimeInterval(3 * 86_400))).hasPrefix("En pause — reprise le 26"),
                     "a pause past tomorrow says the day it ends")
        suite.expect(fr(.paused(.user, until: nil)) == "En pause" && fr(.paused(.user, until: now.addingTimeInterval(-60))) == "En pause",
                     "a pause until resumed, or one whose end has passed, just says paused")
        suite.expect(fr(.paused(.battery, until: nil)) == "En pause\u{00A0}: batterie"
                        && fr(.paused(.battery, until: now.addingTimeInterval(600))) == "En pause\u{00A0}: batterie",
                     "an automatic pause says its reason, never a time")
        suite.expect(fr(.calibrating(done: 12, total: 30)) == "Calibrage en cours · 12/30"
                        && fr(.calibrating(done: 0, total: 0)) == "Calibrage en cours…",
                     "a calibration counts its points once they are planned")
        let frenchLines = lines.map(fr)
        let loose = frenchTypographyProblems(frenchLines, capitalAfterDot: true)
        suite.expect(loose.isEmpty, "the French status lines keep the typography: \(loose)")
    }

    private static func tileReadings(_ suite: TestSuite) {
        func fr(_ line: ForkGlanceStatusLine) -> String? { french.tileReading(line, locale: frenchLocale, now: now) }
        suite.expect(fr(.paused(.user, until: now.addingTimeInterval(14 * 60))) == "14\u{00A0}min"
                        && fr(.paused(.user, until: now.addingTimeInterval(13 * 60 + 1))) == "14\u{00A0}min",
                     "a timed pause's tile counts the minutes left, rounded up")
        suite.expect(fr(.paused(.user, until: nil)) == "Pause" && fr(.paused(.battery, until: nil)) == "Batterie"
                        && fr(.unavailable(.cameraPermission)) == "Autoriser"
                        && fr(.needsCalibration(.firstTime)) == "Calibrer" && fr(.calibrating(done: 12, total: 30)) == "12/30",
                     "a stopped tile says why in a word")
        suite.expect([ForkGlanceStatusLine.off, .starting, .active(zoneName: "LG"), .waiting(.typing), .noFace, .away]
                        .allSatisfy { fr($0) == nil },
                     "a running tile has no reading line")
        // The space before « h » is the locale's (a narrow no-break one today).
        let oneHour = fr(.paused(.user, until: now.addingTimeInterval(60 * 60))) ?? ""
        let nineHours = fr(.paused(.user, until: now.addingTimeInterval(8 * 3600 + 32 * 60))) ?? ""
        suite.expect(oneHour.hasPrefix("1") && oneHour.hasSuffix("h") && oneHour.count == 3
                        && nineHours.hasPrefix("9") && nineHours.hasSuffix("h") && nineHours.count == 3,
                     "a pause of more than an hour counts whole hours on the tile, rounded up")
        // The tile is about 84 pt wide: 12 characters, a Chinese, Japanese
        // or Korean one counting one and a half (8 of them at most).
        var long: [String] = []
        let lines = sampleLines() + [.paused(.user, until: now.addingTimeInterval(65 * 60)),
                                     .paused(.user, until: now.addingTimeInterval(8 * 3600 + 32 * 60))]
        for (language, strings) in zip(languages, all) {
            let readings = lines.compactMap { strings.tileReading($0, locale: language.formattingLocale(), now: now) }
            long += readings.filter { tileWidth($0) > 12 }.map { "\(language.rawValue): \($0)" }
            if readings.contains(where: \.isEmpty) { long.append("\(language.rawValue): empty reading") }
        }
        suite.expect(long.isEmpty, "every tile reading fits the tile in every language: \(long)")
        suite.expect(french.pauseBanner(until: now.addingTimeInterval(14 * 60), locale: frenchLocale, now: now) == "En pause · 14\u{00A0}min"
                        && french.pauseBanner(until: nil, locale: frenchLocale, now: now) == "En pause",
                     "the section's banner counts down a timed pause")
    }

    /// A reading's width in Latin characters: a wide (Chinese, Japanese,
    /// Korean) character counts one and a half.
    private static func tileWidth(_ text: String) -> Double {
        text.unicodeScalars.reduce(0) { width, scalar in
            switch scalar.value {
            case 0x1100...0x11FF, 0x2E80...0x303F, 0x3040...0x30FF, 0x3130...0x318F, 0x3400...0x4DBF,
                 0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFF00...0xFFEF:
                return width + 1.5
            default:
                return width + 1
            }
        }
    }

    /// Each case of each contract has its own words, in every language.
    private static func everyCaseHasItsWords(_ suite: TestSuite) {
        func distinct<T>(_ cases: [T], _ text: (T) -> String) -> Bool {
            let texts = cases.map(text)
            return Set(texts).count == texts.count && texts.allSatisfy { !$0.isEmpty }
        }
        var failing: [String] = []
        for (language, s) in zip(languages, all) {
            let checks: [(String, Bool)] = [
                ("guards", distinct(ForkGlanceGuard.allCases, s.guardText)),
                ("pauses", distinct(ForkGlancePauseReason.allCases, s.pauseReason)),
                ("short pauses", distinct(ForkGlancePauseReason.allCases, s.pauseReasonShort)),
                ("unavailable", distinct(ForkGlanceUnavailable.allCases, s.unavailable)),
                ("short unavailable", distinct(ForkGlanceUnavailable.allCases, s.unavailableShort)),
                ("needs", distinct(ForkGlanceCalibrationNeed.allCases, s.calibrationNeed)),
                ("short needs", distinct(ForkGlanceCalibrationNeed.allCases, s.calibrationNeedShort)),
                ("modes", distinct(ForkGlanceMode.allCases, s.modeName)),
                ("captions", distinct(ForkGlanceMode.allCases, s.modeCaption)),
                ("splits", distinct(ForkGlanceSplit.allCases, s.splitName)),
                ("grades", distinct(ForkGlanceGrade.allCases, s.gradeName)),
                ("durations", distinct(ForkGlancePauseDuration.allCases, s.pauseDurationName)),
                ("energy", distinct(ForkGlanceEnergy.allCases, s.energyName)),
                ("battery", distinct(ForkGlanceBatteryPolicy.allCases, s.batteryPolicyName)),
                ("calls", distinct(ForkGlanceCallPolicy.allCases, s.callPolicyName)),
                ("pointer", distinct(ForkGlancePointerBehavior.allCases, s.pointerName)),
                ("feedback", distinct(ForkGlanceFeedback.allCases, s.feedbackName)),
                ("island closed", distinct(ForkGlanceIslandClosed.allCases, s.islandClosedName)),
                ("notice switches", distinct(ForkGlanceNoticeKind.allCases, s.noticeKindName)),
                ("bar pauses", distinct(ForkGlancePauseDuration.allCases, s.barPause)),
                ("bar modes", distinct(ForkGlanceMode.allCases, s.barMode)),
                ("zones", distinct(ForkGlancePosition.allCases) { s.zoneName($0, display: "LG") }),
                ("shortcuts", distinct([s.shortcutPauseResume, s.shortcutRecenter, s.shortcutMode]) { $0 }),
            ]
            failing += checks.filter { !$0.1 }.map { "\(language.rawValue).\($0.0)" }
        }
        suite.expect(failing.isEmpty, "every guard, pause, mode, split, grade, option and row has words of its own: \(failing)")
        suite.expect(french.gradeName(.excellent) == "Excellente" && french.gradeName(.good) == "Bonne"
                        && french.gradeName(.fair) == "Moyenne" && french.gradeName(.poor) == "Insuffisante",
                     "the validation's grades read Excellente, Bonne, Moyenne, Insuffisante")
        suite.expect(french.modeName(.screens) == "Écrans" && french.modeName(.zones) == "Zones"
                        && french.modeName(.windows) == "Fenêtres",
                     "the modes read Écrans, Zones, Fenêtres")
        suite.expect(french.pauseReason(.battery) == "batterie" && french.pauseReasonShort(.battery) == "Batterie",
                     "a pause reason reads in a sentence and on its own")
    }

    private static func zones(_ suite: TestSuite) {
        suite.expect(french.zoneName(.left, display: "LG") == "Zone gauche du LG"
                        && french.zoneName(.whole, display: "MacBook") == "MacBook entier"
                        && english.zoneName(.left, display: "LG") == "Left zone of the LG"
                        && english.zoneName(.whole, display: "MacBook") == "Whole MacBook",
                     "a zone is named by its place on its display")
        suite.expect(french.zoneName(.right, display: "iMac") == "Zone droite de l’iMac"
                        && french.windowZoneName(app: "Xcode") == "Fenêtre de Xcode"
                        && french.windowZoneName(app: "Safari") == "Fenêtre de Safari"
                        && french.windowZoneName(app: "Arc") == "Fenêtre d’Arc"
                        && english.zoneName(.right, display: "iMac") == "Right zone of the iMac",
                     "the French elides before a vowel, the English never does")
        suite.expect(english.windowZoneName(app: "Safari") == "Safari window",
                     "a window zone is named by its app")
        let lg = ForkGlanceDisplay(uuid: "LG", name: "LG HDR WQHD", frame: .zero)
        let macBook = ForkGlanceDisplay(uuid: "MB", name: "Built-in Retina Display", frame: .zero, isBuiltIn: true,
                                        hasNotch: true)
        let iMac = ForkGlanceDisplay(uuid: "IM", name: "iMac", frame: .zero,
                                     millimeters: CGSize(width: 597, height: 336), isBuiltIn: true)
        let dellA = ForkGlanceDisplay(uuid: "A", name: "DELL U2720Q", frame: .zero)
        let dellB = ForkGlanceDisplay(uuid: "B", name: "DELL P2422H", frame: .zero)
        suite.expect(french.displayShortName(lg, among: [lg, macBook]) == "LG"
                        && french.displayShortName(macBook, among: [lg, macBook]) == "MacBook",
                     "a display is called by its brand, the built-in one MacBook")
        suite.expect(french.displayShortName(iMac, among: [iMac, lg]) == "iMac"
                        && french.zoneName(.left, display: french.displayShortName(iMac, among: [iMac, lg])) == "Zone gauche de l’iMac",
                     "an iMac’s built-in display keeps its own name, never MacBook")
        suite.expect(french.displayShortName(dellA, among: [dellA, dellB]) == "DELL U2720Q"
                        && french.displayShortName(dellA, among: [dellA, macBook]) == "DELL",
                     "two displays of one brand keep their whole names")
        var long: [String] = []
        for (language, strings) in zip(languages, all) {
            for display in ["MacBook", "LG"] {
                long += tooLong(ForkGlancePosition.allCases.map { strings.zoneName($0, display: display) }, "\(language.rawValue): ")
            }
        }
        suite.expect(long.isEmpty, "a zone of a short-named display fits in 28 characters: \(long)")
    }

    private static func allNotices() -> [ForkGlanceNotice] {
        [.paused(until: nil), .paused(until: 1_000 + 14 * 60), .paused(until: 1_000 + tomorrow.timeIntervalSince(now)),
         .resumed, .newLayout, .cameraUnavailable, .recentered, .calibrated(score: 0.97), .calibrated(score: 1),
         .calibrated(score: 0.42), .drift]
    }

    private static func notices(_ suite: TestSuite) {
        func title(_ notice: ForkGlanceNotice) -> String { french.noticeTitle(notice, locale: frenchLocale) }
        func subtitle(_ notice: ForkGlanceNotice) -> String? {
            french.noticeSubtitle(notice, locale: frenchLocale, timeZone: paris, now: now, uptime: 1_000)
        }
        suite.expect(title(.calibrated(score: 0.97)) == "Calibrage réussi · 97\u{00A0}%" && subtitle(.calibrated(score: 0.97)) == "Excellente"
                        && subtitle(.calibrated(score: 0.42)) == "Insuffisante",
                     "a calibration's notice gives its score and grade")
        suite.expect(title(.paused(until: nil)) == "Regard en pause" && title(.resumed) == "Regard repris"
                        && title(.newLayout) == "Nouvelle disposition" && title(.cameraUnavailable) == "Caméra indisponible"
                        && title(.recentered) == "Recentré" && title(.drift) == "Le regard se trompe souvent",
                     "the notices read as the plan writes them")
        suite.expect(subtitle(.paused(until: 1_000 + 14 * 60)) == "Reprise à 15:42"
                        && subtitle(.paused(until: 1_000 + tomorrow.timeIntervalSince(now))) == "Jusqu’à demain"
                        && subtitle(.paused(until: nil)) == "Jusqu’à reprise",
                     "a pause's notice says when it ends, from the machine's clock")
        suite.expect(subtitle(.resumed) == nil && subtitle(.recentered) == nil,
                     "a resume or a recenter needs no second line")
        var long: [String] = []
        for (language, strings) in zip(languages, all) {
            for locale in [frenchLocale, englishLocale] {
                for notice in allNotices() {
                    long += tooLong([strings.noticeTitle(notice, locale: locale)], "\(language.rawValue): ")
                    let detail = strings.noticeSubtitle(notice, locale: locale, timeZone: paris, now: now, uptime: 1_000)
                    long += tooLong([detail].compactMap { $0 }, "\(language.rawValue): ")
                    if detail?.isEmpty == true { long.append("\(language.rawValue): empty subtitle") }
                }
            }
        }
        suite.expect(long.isEmpty, "every notice's title and subtitle fits in 28 characters: \(long)")
        let kinds = Set(allNotices().map(\.kind))
        suite.expect(kinds == Set(ForkGlanceNoticeKind.allCases), "the notices checked cover every notice switch")
    }

    /// What the island shows built by the functions, in every language.
    private static func islandRoom(_ suite: TestSuite) {
        var long: [String] = []
        for (language, strings) in zip(languages, all) {
            let texts = [strings.pauseBanner(until: now.addingTimeInterval(14 * 60), locale: frenchLocale, now: now),
                         strings.pauseBanner(until: now.addingTimeInterval(86_340), locale: englishLocale, now: now),
                         strings.calibrationScoreLine(1, locale: frenchLocale),
                         strings.windowZoneName(app: "Safari")]
            long += tooLong(texts, "\(language.rawValue): ")
        }
        suite.expect(long.isEmpty, "the pause banner, the score and a window's name fit in 28 characters: \(long)")
    }

    private static func commandBar(_ suite: TestSuite) {
        let keywords = french.commandBarKeywords.lowercased()
        suite.expect(["regard", "glance", "caméra", "camera", "focus au regard", "glance focus"].allSatisfy(keywords.contains),
                     "the Command Bar finds the rows by French and English words")
        let words = french.commandBarKeywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        suite.expect(Set(words).count == words.count, "the Command Bar keywords never repeat")
        suite.expect(all.allSatisfy { $0.commandBarKeywords.lowercased().contains("glance") },
                     "« glance » finds the rows in every language")
        suite.expect(french.barMode(.zones) == "Passer le regard en mode Zones" && english.barMode(.screens) == "Switch Glance to Screens Mode",
                     "a mode row names its mode")
        suite.expect(french.barPause(.fifteenMinutes) == "Mettre le regard en pause pendant 15 minutes"
                        && french.barPause(.untilResumed) == "Mettre le regard en pause",
                     "the pause rows say for how long")
        suite.expect(french.shortcutPauseResume == "Mettre en pause ou reprendre" && french.shortcutRecenter == "Recentrer"
                        && french.shortcutMode == "Changer de mode",
                     "the three shortcuts have their names")
    }

    private static func formatting(_ suite: TestSuite) {
        suite.expect(ForkGlanceStrings.fill("Calibrage %@", "97 %") == "Calibrage 97 %"
                        && ForkGlanceStrings.fill("%1$@ · %2$@", "a", "b") == "a · b"
                        && ForkGlanceStrings.fill("%2$@ avant %1$@", "a", "b") == "b avant a",
                     "a value holding a percent sign fills its placeholder as it is, in any order")
        suite.expect(ForkGlanceStrings.progress(done: 31, total: 30) == "30/30" && ForkGlanceStrings.progress(done: -1, total: 30) == "0/30",
                     "a calibration's progress stays within its points")
        suite.expect(ForkGlanceStrings.percent(0.974, locale: frenchLocale) == "97\u{00A0}%"
                        && ForkGlanceStrings.percent(.nan, locale: englishLocale) == "0%"
                        && ForkGlanceStrings.percent(1.4, locale: englishLocale) == "100%",
                     "a score is a whole percentage, in the locale's own way, kept within 0 and 100")
        suite.expect(ForkGlanceStrings.timeLeft(0, locale: frenchLocale) == "1\u{00A0}min"
                        && ForkGlanceStrings.timeLeft(.infinity, locale: frenchLocale) == "1\u{00A0}min",
                     "a countdown never reads zero or nonsense")
        // The assistant's line, here beside the countdown it shares.
        let assistant = ForkGlanceCalibrationStrings.fr
        suite.expect(assistant.pointsLine(6, locale: frenchLocale) == "6 points · environ 15\u{00A0}s"
                        && ForkGlanceCalibrationStrings.enUS.pointsLine(6, locale: englishLocale) == "6 points · about 15 s"
                        && assistant.pointsLine(29, locale: frenchLocale) == "29 points · environ 1\u{00A0}min",
                     "a quick recenter says its seconds, rounded up to five, a full calibration its minutes")
        suite.expect(french.calibrationScoreLine(0.97, date: now.addingTimeInterval(-3 * 86_400), now: now, locale: frenchLocale)
                        == "Calibrage 97\u{00A0}% · il y a 3\u{00A0}j",
                     "the score line says how old the calibration is")
        suite.expect(french.lastSwitchLine(now.addingTimeInterval(-2), now: now, locale: frenchLocale).hasPrefix("Dernière bascule il y a 2"),
                     "the last switch is dated relative to now")
    }
}
