// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The Glance Focus words every surface shares (plan §16): the feature's
/// name, the status line (plan §9), the guards and pauses (plan §7.4–§7.5),
/// the zones' names, the modes, the splits, the grades, the settings'
/// option labels, the island's notices (plan §11.4), the Command Bar rows
/// (plan §11.5) and the shortcuts' names (plan §12.8). Each surface keeps
/// the sentences of its own screens in a strings file of its own
/// (settings, assistant, island); these are frozen, so they agree.
///
/// Same contract as the official FeatureStrings structs: memberwise init in
/// declaration order, one static per language. Every field marked *island*
/// fits in 28 characters once its placeholder is filled with a short name
/// (tested). Placeholders are filled by the functions below, never by
/// `String(format:)`: `%@` for one value, `%1$@` and `%2$@` for two.
/// French: `\u{00A0}` before « : ; ! ? » and inside « », typographic
/// apostrophes, no capital after « · ».
struct ForkGlanceStrings {
    // MARK: Names
    /// The feature, in the Settings and the Extras page (the same words as
    /// `ForkExtrasStrings.glanceTitle`, tested).
    let featureTitle: String
    /// The island's section (island).
    let sectionTitle: String
    /// What the Settings search matches, comma-separated.
    let searchKeywords: String
    /// The section's empty state while the feature is off.
    let featureOff: String

    // MARK: Status line (settings header, section)
    let statusOff: String
    let statusActive: String
    /// `%@`: a zone's name, « Actif · Zone gauche du LG ».
    let statusActiveZone: String
    let statusStarting: String
    let statusCalibrating: String
    /// `%@`: the points done over the points planned, « 12/30 ».
    let statusCalibratingCount: String
    /// `%@`: a guard, « En attente : vous tapez ».
    let statusWaiting: String
    let statusNoFace: String
    let statusAway: String
    let statusPaused: String
    /// `%@`: a time of day.
    let statusPausedUntil: String
    let statusPausedTomorrow: String
    /// `%@`: a day and a time, past tomorrow.
    let statusPausedUntilDay: String
    /// `%@`: an automatic pause's reason, « En pause : batterie ».
    let statusPausedReason: String

    // MARK: Guards, after « En attente : » (island)
    let guardTyping: String
    let guardPointer: String
    let guardButtonsOrModifiers: String
    let guardSecureInput: String
    let guardDictation: String
    let guardMenuOrOverview: String
    let guardIslandOpen: String
    let guardOwnPanel: String
    let guardExcludedSource: String
    let guardCalibrating: String
    let guardCooldown: String
    let guardLowConfidence: String

    // MARK: Pause reasons, after « En pause : »
    let pauseUser: String
    let pauseLocked: String
    let pauseAsleep: String
    let pauseScreensAsleep: String
    let pauseSessionInactive: String
    let pauseIdle: String
    let pauseBattery: String
    let pauseLowPower: String
    let pauseThermal: String
    let pauseCameraBusy: String
    let pauseCall: String
    let pauseSingleScreen: String
    let pauseLidClosed: String

    // MARK: Pause reasons, short: the tile's reading line (island)
    let shortUser: String
    let shortLocked: String
    let shortAsleep: String
    let shortScreensAsleep: String
    let shortSessionInactive: String
    let shortIdle: String
    let shortBattery: String
    let shortLowPower: String
    let shortThermal: String
    let shortCameraBusy: String
    let shortCall: String
    let shortSingleScreen: String
    let shortLidClosed: String
    /// Under a Screens-mode pause with one display (plan §5.1).
    let singleScreenHint: String

    // MARK: Unavailable
    let unavailableCameraPermission: String
    let unavailableAccessibility: String
    let unavailableNoCamera: String
    let unavailableCameraDisconnected: String
    let unavailableCameraFailed: String
    // Short (island)
    let shortCameraPermission: String
    let shortAccessibility: String
    let shortNoCamera: String
    let shortCameraDisconnected: String
    let shortCameraFailed: String

    // MARK: Calibration needed
    let needFirstTime: String
    let needNewLayout: String
    let needNewCamera: String
    let needRemoved: String
    // Short (island)
    let shortNeedFirstTime: String
    let shortNeedNewLayout: String
    let shortNeedNewCamera: String
    let shortNeedRemoved: String

    // MARK: Zones (island once filled with a short display name)
    /// `%@`: a display's short name, « MacBook entier ».
    let zoneWhole: String
    let zoneLeft: String
    let zoneCenter: String
    let zoneRight: String
    let zoneTop: String
    let zoneBottom: String
    let zoneTopLeft: String
    let zoneTopRight: String
    let zoneBottomLeft: String
    let zoneBottomRight: String
    /// `%@`: a display's short name: Windows mode, the app unknown.
    let zoneWindowOn: String
    /// `%@`: an app's name, « Fenêtre de Safari ».
    let zoneWindowApp: String
    /// The built-in display's short name.
    let builtInDisplay: String

    // MARK: Modes
    let modeScreens: String
    let modeZones: String
    let modeWindows: String
    let modeScreensCaption: String
    let modeZonesCaption: String
    let modeWindowsCaption: String
    let modeSuited: String
    /// Plan §5.3: Windows mode with a σ over 8 % of the display's width.
    let modeDiscouraged: String
    let panes: String

    // MARK: Splits (island)
    let splitWhole: String
    let splitColumns2: String
    let splitColumns3: String
    let splitRows2: String
    let splitGrid2x2: String

    // MARK: Grades and calibration (island)
    let gradeExcellent: String
    let gradeGood: String
    let gradeFair: String
    let gradePoor: String
    /// `%@`: a percentage, « Calibrage 97 % ».
    let calibrationScore: String
    /// `%1$@`: a percentage, `%2$@`: an age, « Calibrage 97 % · il y a 3 j ».
    let calibrationScoreAge: String
    let headOnly: String
    let headAndEyes: String

    // MARK: Pause durations (island menus)
    let durationFifteenMinutes: String
    let durationOneHour: String
    let durationUntilTomorrow: String
    let durationUntilResumed: String

    // MARK: Settings' option labels
    let energySaver: String
    let energyBalanced: String
    let energyReactive: String
    let batterySame: String
    let batterySaver: String
    let batteryPause: String
    let callKeepRunning: String
    let callPause: String
    let pointerAuto: String
    let pointerStay: String
    let pointerFollowScreen: String
    let pointerWindowCenter: String
    let feedbackNone: String
    let feedbackHalo: String
    let feedbackZone: String
    let islandNever: String
    let islandPaused: String
    let islandAlways: String
    /// The sensitivity slider's ends.
    let sensitivityCautious: String
    let sensitivityLively: String
    /// The last step of « Couper la caméra après ».
    let never: String

    // MARK: The notices' switches (island settings)
    let noticeKindPause: String
    let noticeKindNewLayout: String
    let noticeKindCamera: String
    let noticeKindRecenter: String
    let noticeKindCalibrated: String
    let noticeKindDrift: String

    // MARK: Notices: titles and subtitles (island)
    let noticePaused: String
    let noticeResumed: String
    let noticeNewLayout: String
    let noticeCameraUnavailable: String
    let noticeRecentered: String
    /// `%@`: a percentage, « Calibrage réussi · 97 % ».
    let noticeCalibrated: String
    let noticeDrift: String
    /// `%@`: a time of day.
    let noticePausedUntil: String
    let noticePausedTomorrow: String
    let noticePausedIndefinitely: String
    let noticeNewLayoutDetail: String
    let noticeCameraDetail: String
    let noticeDriftDetail: String

    // MARK: Pause banner (island)
    /// `%@`: the time left, « En pause · 14 min ».
    let pausedFor: String

    // MARK: Buttons (island)
    let pause: String
    let resume: String
    let resumeAnyway: String
    let recenter: String
    let calibrate: String
    let calibrateEllipsis: String
    let recalibrate: String
    let quickRecenter: String
    let test: String
    let enable: String
    let openSettings: String
    let allowCamera: String
    let allowAccessibility: String
    let retry: String
    let chooseCamera: String
    let switchToZones: String

    // MARK: Lines
    /// `%@`: an age, « Dernière bascule il y a 2 s ».
    let lastSwitch: String
    let recentSwitches: String

    // MARK: Command Bar (plan §11.5)
    let barPauseFifteenMinutes: String
    let barPauseOneHour: String
    let barPauseUntilTomorrow: String
    let barPauseUntilResumed: String
    let barResume: String
    let barRecenter: String
    let barCalibrate: String
    /// `%@`: a mode's name.
    let barSwitchMode: String
    let barSettings: String
    /// Comma-separated; `commandBarKeywords` adds the English ones.
    let barKeywords: String

    // MARK: Shortcuts (plan §12.8)
    let shortcutPauseResume: String
    let shortcutRecenter: String
    let shortcutMode: String

    // MARK: Grammar
    /// French: « du » and « de » before a vowel become « de l’ » and « d’ »
    /// when a name fills a zone's placeholder (« Zone gauche de l’iMac »).
    let elidesBeforeVowel: Bool

    static func strings(_ language: AppLanguage) -> ForkGlanceStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .uk: return .uk
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

// MARK: - Status

extension ForkGlanceStrings {
    /// The status line (plan §9) in words: the settings' header and the
    /// section's line. A timed pause says when it ends in the person's
    /// clock (`AppLanguage.formattingLocale()` in the app).
    func status(_ line: ForkGlanceStatusLine, locale: Locale, timeZone: TimeZone = .autoupdatingCurrent,
                now: Date = Date()) -> String {
        switch line {
        case .off:
            return statusOff
        case .unavailable(let reason):
            return unavailable(reason)
        case .needsCalibration(let need):
            return calibrationNeed(need)
        case .calibrating(let done, let total):
            guard total > 0 else { return statusCalibrating }
            return Self.fill(statusCalibratingCount, Self.progress(done: done, total: total))
        case .starting:
            return statusStarting
        case .active(let zoneName):
            guard let zoneName, !zoneName.isEmpty else { return statusActive }
            return Self.fill(statusActiveZone, zoneName)
        case .waiting(let held):
            return Self.fill(statusWaiting, guardText(held))
        case .noFace:
            return statusNoFace
        case .away:
            return statusAway
        case .paused(let reason, let until):
            guard reason == .user else { return Self.fill(statusPausedReason, pauseReason(reason)) }
            guard let until, until > now else { return statusPaused }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            if let tomorrow, abs(until.timeIntervalSince(tomorrow)) < 1 { return statusPausedTomorrow }
            if until.timeIntervalSince(now) < 86_400 {
                return Self.fill(statusPausedUntil, Self.time(until, locale: locale, timeZone: timeZone))
            }
            return Self.fill(statusPausedUntilDay, Self.dayAndTime(until, locale: locale, timeZone: timeZone))
        }
    }

    /// The tile's reading line (plan §11.3), 28 characters at most: the
    /// minutes left of a timed pause, « Pause », an automatic pause's
    /// reason, what is missing; nil while it runs.
    func tileReading(_ line: ForkGlanceStatusLine, locale: Locale, now: Date = Date()) -> String? {
        switch line {
        case .off, .starting, .active, .waiting, .noFace, .away:
            return nil
        case .unavailable(let reason):
            return unavailableShort(reason)
        case .needsCalibration(let need):
            return calibrationNeedShort(need)
        case .calibrating(let done, let total):
            return total > 0 ? Self.progress(done: done, total: total) : shortNeedFirstTime
        case .paused(let reason, let until):
            guard reason == .user else { return pauseReasonShort(reason) }
            guard let until, until > now else { return shortUser }
            return Self.timeLeft(until.timeIntervalSince(now), locale: locale)
        }
    }

    /// The section's pause banner: « En pause · 14 min », or « En pause ».
    func pauseBanner(until: Date?, locale: Locale, now: Date = Date()) -> String {
        guard let until, until > now else { return statusPaused }
        return Self.fill(pausedFor, Self.timeLeft(until.timeIntervalSince(now), locale: locale))
    }

    func guardText(_ held: ForkGlanceGuard) -> String {
        switch held {
        case .typing: return guardTyping
        case .pointer: return guardPointer
        case .buttonsOrModifiers: return guardButtonsOrModifiers
        case .secureInput: return guardSecureInput
        case .dictation: return guardDictation
        case .menuOrOverview: return guardMenuOrOverview
        case .islandOpen: return guardIslandOpen
        case .ownPanel: return guardOwnPanel
        case .excludedSource: return guardExcludedSource
        case .calibrating: return guardCalibrating
        case .cooldown: return guardCooldown
        case .lowConfidence: return guardLowConfidence
        }
    }

    /// After « En pause : », lowercase where the language allows.
    func pauseReason(_ reason: ForkGlancePauseReason) -> String {
        switch reason {
        case .user: return pauseUser
        case .locked: return pauseLocked
        case .asleep: return pauseAsleep
        case .screensAsleep: return pauseScreensAsleep
        case .sessionInactive: return pauseSessionInactive
        case .idle: return pauseIdle
        case .battery: return pauseBattery
        case .lowPower: return pauseLowPower
        case .thermal: return pauseThermal
        case .cameraBusy: return pauseCameraBusy
        case .call: return pauseCall
        case .singleScreen: return pauseSingleScreen
        case .lidClosedNoCamera: return pauseLidClosed
        }
    }

    /// On its own, 28 characters at most.
    func pauseReasonShort(_ reason: ForkGlancePauseReason) -> String {
        switch reason {
        case .user: return shortUser
        case .locked: return shortLocked
        case .asleep: return shortAsleep
        case .screensAsleep: return shortScreensAsleep
        case .sessionInactive: return shortSessionInactive
        case .idle: return shortIdle
        case .battery: return shortBattery
        case .lowPower: return shortLowPower
        case .thermal: return shortThermal
        case .cameraBusy: return shortCameraBusy
        case .call: return shortCall
        case .singleScreen: return shortSingleScreen
        case .lidClosedNoCamera: return shortLidClosed
        }
    }

    func unavailable(_ reason: ForkGlanceUnavailable) -> String {
        switch reason {
        case .cameraPermission: return unavailableCameraPermission
        case .accessibilityPermission: return unavailableAccessibility
        case .noCamera: return unavailableNoCamera
        case .cameraDisconnected: return unavailableCameraDisconnected
        case .cameraFailed: return unavailableCameraFailed
        }
    }

    /// 28 characters at most.
    func unavailableShort(_ reason: ForkGlanceUnavailable) -> String {
        switch reason {
        case .cameraPermission: return shortCameraPermission
        case .accessibilityPermission: return shortAccessibility
        case .noCamera: return shortNoCamera
        case .cameraDisconnected: return shortCameraDisconnected
        case .cameraFailed: return shortCameraFailed
        }
    }

    func calibrationNeed(_ need: ForkGlanceCalibrationNeed) -> String {
        switch need {
        case .firstTime: return needFirstTime
        case .newLayout: return needNewLayout
        case .newCamera: return needNewCamera
        case .removed: return needRemoved
        }
    }

    /// 28 characters at most.
    func calibrationNeedShort(_ need: ForkGlanceCalibrationNeed) -> String {
        switch need {
        case .firstTime: return shortNeedFirstTime
        case .newLayout: return shortNeedNewLayout
        case .newCamera: return shortNeedNewCamera
        case .removed: return shortNeedRemoved
        }
    }
}

// MARK: - Zones

extension ForkGlanceStrings {
    /// « Zone gauche du LG », « MacBook entier ». `display` is a short
    /// name (`displayShortName`); `.window` names the display, the app
    /// unknown (`windowZoneName` names the app).
    func zoneName(_ position: ForkGlancePosition, display: String) -> String {
        let template: String
        switch position {
        case .whole: template = zoneWhole
        case .left: template = zoneLeft
        case .center: template = zoneCenter
        case .right: template = zoneRight
        case .top: template = zoneTop
        case .bottom: template = zoneBottom
        case .topLeft: template = zoneTopLeft
        case .topRight: template = zoneTopRight
        case .bottomLeft: template = zoneBottomLeft
        case .bottomRight: template = zoneBottomRight
        case .window: template = zoneWindowOn
        }
        return fillName(template, display)
    }

    /// Windows mode: « Fenêtre de Safari », « Fenêtre d’Arc ».
    func windowZoneName(app: String) -> String {
        fillName(zoneWindowApp, app)
    }

    /// How a display is called in a zone's name: the built-in one
    /// « MacBook », another its name's first word (« LG » for « LG HDR
    /// WQHD »), or its whole name when another display starts alike.
    func displayShortName(_ display: ForkGlanceDisplay, among displays: [ForkGlanceDisplay]) -> String {
        if display.isBuiltIn { return builtInDisplay }
        let name = display.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = Self.firstWord(name), !first.isEmpty else { return name }
        let alike = displays.filter { $0.uuid != display.uuid && !$0.isBuiltIn && Self.firstWord($0.name) == first }
        return alike.isEmpty ? first : name
    }

    private static func firstWord(_ name: String) -> String? {
        name.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").first.map(String.init)
    }

    /// Fills `%@` with a name, eliding before a vowel where the language does.
    private func fillName(_ template: String, _ name: String) -> String {
        guard elidesBeforeVowel, Self.startsWithVowel(name) else { return Self.fill(template, name) }
        let elided = template
            .replacingOccurrences(of: "du %@", with: "de l’%@")
            .replacingOccurrences(of: "de %@", with: "d’%@")
        return Self.fill(elided, name)
    }

    private static func startsWithVowel(_ name: String) -> Bool {
        guard let first = name.first else { return false }
        let plain = String(first).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return ["a", "e", "i", "o", "u", "y"].contains(plain)
    }
}

// MARK: - Modes, splits, grades, settings

extension ForkGlanceStrings {
    func modeName(_ mode: ForkGlanceMode) -> String {
        switch mode {
        case .screens: return modeScreens
        case .zones: return modeZones
        case .windows: return modeWindows
        }
    }

    func modeCaption(_ mode: ForkGlanceMode) -> String {
        switch mode {
        case .screens: return modeScreensCaption
        case .zones: return modeZonesCaption
        case .windows: return modeWindowsCaption
        }
    }

    func splitName(_ split: ForkGlanceSplit) -> String {
        switch split {
        case .whole: return splitWhole
        case .columns2: return splitColumns2
        case .columns3: return splitColumns3
        case .rows2: return splitRows2
        case .grid2x2: return splitGrid2x2
        }
    }

    func gradeName(_ grade: ForkGlanceGrade) -> String {
        switch grade {
        case .excellent: return gradeExcellent
        case .good: return gradeGood
        case .fair: return gradeFair
        case .poor: return gradePoor
        }
    }

    /// « Calibrage 97 % ».
    func calibrationScoreLine(_ score: Double, locale: Locale) -> String {
        Self.fill(calibrationScore, Self.percent(score, locale: locale))
    }

    /// « Calibrage 97 % · il y a 3 j ».
    func calibrationScoreLine(_ score: Double, date: Date, now: Date = Date(), locale: Locale) -> String {
        Self.fill(calibrationScoreAge, Self.percent(score, locale: locale), Self.relative(date, now: now, locale: locale))
    }

    /// « Dernière bascule il y a 2 s ».
    func lastSwitchLine(_ date: Date, now: Date = Date(), locale: Locale) -> String {
        Self.fill(lastSwitch, Self.relative(date, now: now, locale: locale))
    }

    func pauseDurationName(_ duration: ForkGlancePauseDuration) -> String {
        switch duration {
        case .fifteenMinutes: return durationFifteenMinutes
        case .oneHour: return durationOneHour
        case .untilTomorrow: return durationUntilTomorrow
        case .untilResumed: return durationUntilResumed
        }
    }

    func energyName(_ energy: ForkGlanceEnergy) -> String {
        switch energy {
        case .saver: return energySaver
        case .balanced: return energyBalanced
        case .reactive: return energyReactive
        }
    }

    func batteryPolicyName(_ policy: ForkGlanceBatteryPolicy) -> String {
        switch policy {
        case .same: return batterySame
        case .saver: return batterySaver
        case .pause: return batteryPause
        }
    }

    func callPolicyName(_ policy: ForkGlanceCallPolicy) -> String {
        switch policy {
        case .keepRunning: return callKeepRunning
        case .pause: return callPause
        }
    }

    func pointerName(_ behavior: ForkGlancePointerBehavior) -> String {
        switch behavior {
        case .auto: return pointerAuto
        case .stay: return pointerStay
        case .followScreen: return pointerFollowScreen
        case .windowCenter: return pointerWindowCenter
        }
    }

    func feedbackName(_ feedback: ForkGlanceFeedback) -> String {
        switch feedback {
        case .none: return feedbackNone
        case .halo: return feedbackHalo
        case .zoneFlash: return feedbackZone
        }
    }

    func islandClosedName(_ choice: ForkGlanceIslandClosed) -> String {
        switch choice {
        case .never: return islandNever
        case .paused: return islandPaused
        case .always: return islandAlways
        }
    }

    func noticeKindName(_ kind: ForkGlanceNoticeKind) -> String {
        switch kind {
        case .pause: return noticeKindPause
        case .newLayout: return noticeKindNewLayout
        case .camera: return noticeKindCamera
        case .recenter: return noticeKindRecenter
        case .calibrated: return noticeKindCalibrated
        case .drift: return noticeKindDrift
        }
    }
}

// MARK: - Notices

extension ForkGlanceStrings {
    /// 28 characters at most.
    func noticeTitle(_ notice: ForkGlanceNotice, locale: Locale) -> String {
        switch notice {
        case .paused: return noticePaused
        case .resumed: return noticeResumed
        case .newLayout: return noticeNewLayout
        case .cameraUnavailable: return noticeCameraUnavailable
        case .recentered: return noticeRecentered
        case .calibrated(let score): return Self.fill(noticeCalibrated, Self.percent(score, locale: locale))
        case .drift: return noticeDrift
        }
    }

    /// 28 characters at most; nil when the title says it all. A pause's end
    /// is in `systemUptime` (the machine's clock): `uptime` is the uptime
    /// at `now`.
    func noticeSubtitle(_ notice: ForkGlanceNotice, locale: Locale, timeZone: TimeZone = .autoupdatingCurrent,
                        now: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> String? {
        switch notice {
        case .paused(let until):
            guard let until else { return noticePausedIndefinitely }
            let end = now.addingTimeInterval(until - uptime)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            if let tomorrow, abs(end.timeIntervalSince(tomorrow)) < 1 { return noticePausedTomorrow }
            return Self.fill(noticePausedUntil, Self.time(end, locale: locale, timeZone: timeZone))
        case .resumed, .recentered:
            return nil
        case .newLayout:
            return noticeNewLayoutDetail
        case .cameraUnavailable:
            return noticeCameraDetail
        case .calibrated(let score):
            return gradeName(ForkGlanceGrade(score: score))
        case .drift:
            return noticeDriftDetail
        }
    }
}

// MARK: - Command Bar

extension ForkGlanceStrings {
    func barPause(_ duration: ForkGlancePauseDuration) -> String {
        switch duration {
        case .fifteenMinutes: return barPauseFifteenMinutes
        case .oneHour: return barPauseOneHour
        case .untilTomorrow: return barPauseUntilTomorrow
        case .untilResumed: return barPauseUntilResumed
        }
    }

    /// « Passer le regard en mode Zones ».
    func barMode(_ mode: ForkGlanceMode) -> String {
        Self.fill(barSwitchMode, modeName(mode))
    }

    /// The rows' keywords: this language's, then the English ones and the
    /// names, without repeats, so « glance » finds the rows in any language.
    var commandBarKeywords: String {
        let english = ForkGlanceStrings.enUS
        var seen = Set<String>()
        var words: [String] = []
        for list in [barKeywords, english.barKeywords, featureTitle, english.featureTitle,
                     sectionTitle, english.sectionTitle] {
            for word in list.split(separator: ",") {
                let trimmed = word.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted { words.append(trimmed) }
            }
        }
        return words.joined(separator: ", ")
    }
}

// MARK: - Formatting

extension ForkGlanceStrings {
    /// Fills `%@`, or `%1$@` then `%2$@`, with plain text (a value may hold
    /// a « % »: never `String(format:)`).
    static func fill(_ template: String, _ values: String...) -> String {
        if values.count == 1 { return template.replacingOccurrences(of: "%@", with: values[0]) }
        var text = template
        for (index, value) in values.enumerated() {
            text = text.replacingOccurrences(of: "%\(index + 1)$@", with: value)
        }
        return text
    }

    /// « 12/30 ».
    static func progress(done: Int, total: Int) -> String {
        "\(max(0, min(done, total)))/\(max(0, total))"
    }

    /// A time of day in the locale's own clock (« 15:42 » or « 3:42 PM »):
    /// never assume a 24-hour clock.
    static func time(_ date: Date, locale: Locale, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// « 24 oct. à 15:42 », past tomorrow: no year, a pause ends within days.
    static func dayAndTime(_ date: Date, locale: Locale, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        var style = Date.FormatStyle(locale: locale).day().month(.abbreviated).hour().minute()
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// « 97 % » in the locale's own percent.
    static func percent(_ fraction: Double, locale: Locale) -> String {
        let clamped = fraction.isFinite ? min(1, max(0, fraction)) : 0
        return clamped.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    /// A countdown, « 14 min », « 1 h 5 min »: whole minutes rounded up,
    /// one at least.
    static func timeLeft(_ seconds: TimeInterval, locale: Locale) -> String {
        let minutes = seconds.isFinite ? max(1, Int64((seconds / 60).rounded(.up))) : 1
        return Duration.seconds(minutes * 60).formatted(
            .units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2).locale(locale))
    }

    /// « il y a 2 s », « 3 days ago ».
    static func relative(_ date: Date, now: Date, locale: Locale) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.dateTimeStyle = .numeric
        formatter.unitsStyle = .short
        return formatter.localizedString(for: min(date, now), relativeTo: now)
    }
}

// MARK: - Languages

extension ForkGlanceStrings {
    static let enUS = ForkGlanceStrings(
        featureTitle: "Glance Focus",
        sectionTitle: "Glance",
        searchKeywords: "glance, gaze, eyes, head, head tracking, camera, face, focus, window, display, screen, zone, keyboard",
        featureOff: "Glance Focus is off",
        statusOff: "Off",
        statusActive: "Active",
        statusActiveZone: "Active · %@",
        statusStarting: "Starting the camera…",
        statusCalibrating: "Calibrating…",
        statusCalibratingCount: "Calibrating · %@",
        statusWaiting: "Waiting: %@",
        statusNoFace: "No face detected",
        statusAway: "Looking away from the displays",
        statusPaused: "Paused",
        statusPausedUntil: "Paused — resumes at %@",
        statusPausedTomorrow: "Paused until tomorrow",
        statusPausedUntilDay: "Paused — resumes on %@",
        statusPausedReason: "Paused: %@",
        guardTyping: "you are typing",
        guardPointer: "mouse",
        guardButtonsOrModifiers: "key or button held",
        guardSecureInput: "password entry",
        guardDictation: "dictation in progress",
        guardMenuOrOverview: "menu or Mission Control",
        guardIslandOpen: "island open",
        guardOwnPanel: "app window open",
        guardExcludedSource: "app never to leave",
        guardCalibrating: "calibration in progress",
        guardCooldown: "just switched",
        guardLowConfidence: "gaze unclear",
        pauseUser: "at your request",
        pauseLocked: "Mac locked",
        pauseAsleep: "Mac asleep",
        pauseScreensAsleep: "displays asleep",
        pauseSessionInactive: "session in the background",
        pauseIdle: "no activity",
        pauseBattery: "on battery",
        pauseLowPower: "Low Power Mode",
        pauseThermal: "Mac too hot",
        pauseCameraBusy: "camera preview open",
        pauseCall: "video call in progress",
        pauseSingleScreen: "only one display",
        pauseLidClosed: "lid closed",
        shortUser: "Paused",
        shortLocked: "Locked",
        shortAsleep: "Asleep",
        shortScreensAsleep: "Displays asleep",
        shortSessionInactive: "Session in background",
        shortIdle: "Idle",
        shortBattery: "Battery",
        shortLowPower: "Low Power Mode",
        shortThermal: "Mac too hot",
        shortCameraBusy: "Camera preview",
        shortCall: "Video call",
        shortSingleScreen: "One display",
        shortLidClosed: "Lid closed",
        singleScreenHint: "Only one display: switch to Zones mode",
        unavailableCameraPermission: "Camera access needed",
        unavailableAccessibility: "Accessibility access needed",
        unavailableNoCamera: "No camera",
        unavailableCameraDisconnected: "Camera disconnected",
        unavailableCameraFailed: "The camera is not responding",
        shortCameraPermission: "Camera access",
        shortAccessibility: "Accessibility",
        shortNoCamera: "No camera found",
        shortCameraDisconnected: "Camera unplugged",
        shortCameraFailed: "Camera unavailable",
        needFirstTime: "Calibrate to get started",
        needNewLayout: "Calibrate for this display layout",
        needNewCamera: "Calibrate for this camera",
        needRemoved: "Profile deleted: calibrate again",
        shortNeedFirstTime: "Calibrate",
        shortNeedNewLayout: "New layout",
        shortNeedNewCamera: "New camera",
        shortNeedRemoved: "Profile deleted",
        zoneWhole: "Whole %@",
        zoneLeft: "Left zone of the %@",
        zoneCenter: "Center zone of the %@",
        zoneRight: "Right zone of the %@",
        zoneTop: "Top zone of the %@",
        zoneBottom: "Bottom zone of the %@",
        zoneTopLeft: "Top left of the %@",
        zoneTopRight: "Top right of the %@",
        zoneBottomLeft: "Bottom left of the %@",
        zoneBottomRight: "Bottom right of the %@",
        zoneWindowOn: "Window on the %@",
        zoneWindowApp: "%@ window",
        builtInDisplay: "MacBook",
        modeScreens: "Screens",
        modeZones: "Zones",
        modeWindows: "Windows",
        modeScreensCaption: "One zone per display: the keyboard follows the display you look at.",
        modeZonesCaption: "Each display is split into zones, ideal for a wide display.",
        modeWindowsCaption: "Each visible window is a zone. Needs a precise calibration.",
        modeSuited: "Suited to this layout",
        modeDiscouraged: "Not precise enough for this mode on this layout",
        panes: "Panes (experimental)",
        splitWhole: "Whole",
        splitColumns2: "2 columns",
        splitColumns3: "3 columns",
        splitRows2: "2 rows",
        splitGrid2x2: "2×2 grid",
        gradeExcellent: "Excellent",
        gradeGood: "Good",
        gradeFair: "Fair",
        gradePoor: "Poor",
        calibrationScore: "Calibration %@",
        calibrationScoreAge: "Calibration %1$@ · %2$@",
        headOnly: "Head only",
        headAndEyes: "Head and eyes",
        durationFifteenMinutes: "For 15 minutes",
        durationOneHour: "For 1 hour",
        durationUntilTomorrow: "Until tomorrow",
        durationUntilResumed: "Until resumed",
        energySaver: "Saver",
        energyBalanced: "Balanced",
        energyReactive: "Responsive",
        batterySame: "Same as on power",
        batterySaver: "Saver",
        batteryPause: "Pause",
        callKeepRunning: "Keep going",
        callPause: "Pause",
        pointerAuto: "Automatic",
        pointerStay: "Don’t move",
        pointerFollowScreen: "Follow the display",
        pointerWindowCenter: "Window center",
        feedbackNone: "None",
        feedbackHalo: "Halo",
        feedbackZone: "Zone flash",
        islandNever: "Never",
        islandPaused: "During a pause or calibration",
        islandAlways: "Always (active zone)",
        sensitivityCautious: "Cautious",
        sensitivityLively: "Lively",
        never: "Never",
        noticeKindPause: "Pause and resume",
        noticeKindNewLayout: "New display layout",
        noticeKindCamera: "Camera unavailable",
        noticeKindRecenter: "Recentered",
        noticeKindCalibrated: "Calibration done",
        noticeKindDrift: "Recalibration suggested",
        noticePaused: "Glance paused",
        noticeResumed: "Glance resumed",
        noticeNewLayout: "New display layout",
        noticeCameraUnavailable: "Camera unavailable",
        noticeRecentered: "Recentered",
        noticeCalibrated: "Calibrated · %@",
        noticeDrift: "Glance often gets it wrong",
        noticePausedUntil: "Resumes at %@",
        noticePausedTomorrow: "Until tomorrow",
        noticePausedIndefinitely: "Until you resume",
        noticeNewLayoutDetail: "Calibrate for these displays",
        noticeCameraDetail: "Glance is paused",
        noticeDriftDetail: "Calibrate again to refine it",
        pausedFor: "Paused · %@",
        pause: "Pause",
        resume: "Resume",
        resumeAnyway: "Resume Anyway",
        recenter: "Recenter",
        calibrate: "Calibrate",
        calibrateEllipsis: "Calibrate…",
        recalibrate: "Calibrate Again",
        quickRecenter: "Quick Realign",
        test: "Test",
        enable: "Turn On",
        openSettings: "Open Settings",
        allowCamera: "Allow the Camera",
        allowAccessibility: "Allow Accessibility",
        retry: "Try Again",
        chooseCamera: "Choose Another Camera",
        switchToZones: "Switch to Zones Mode",
        lastSwitch: "Last switch %@",
        recentSwitches: "Recent switches",
        barPauseFifteenMinutes: "Pause Glance for 15 Minutes",
        barPauseOneHour: "Pause Glance for 1 Hour",
        barPauseUntilTomorrow: "Pause Glance Until Tomorrow",
        barPauseUntilResumed: "Pause Glance",
        barResume: "Resume Glance",
        barRecenter: "Recenter Glance",
        barCalibrate: "Calibrate Glance",
        barSwitchMode: "Switch Glance to %@ Mode",
        barSettings: "Glance Focus Settings",
        barKeywords: "glance, gaze, eyes, head, head tracking, camera, focus, window, display, screen, zone, pause, resume, recenter, calibrate",
        shortcutPauseResume: "Pause or resume",
        shortcutRecenter: "Recenter",
        shortcutMode: "Switch mode",
        elidesBeforeVowel: false
    )

    static let fr = ForkGlanceStrings(
        featureTitle: "Focus au regard",
        sectionTitle: "Regard",
        searchKeywords: "regard, yeux, tête, suivi de la tête, caméra, visage, focus, fenêtre, écran, zone, clavier",
        featureOff: "Focus au regard est désactivé",
        statusOff: "Désactivé",
        statusActive: "Actif",
        statusActiveZone: "Actif · %@",
        statusStarting: "Démarrage de la caméra…",
        statusCalibrating: "Calibrage en cours…",
        statusCalibratingCount: "Calibrage en cours · %@",
        statusWaiting: "En attente\u{00A0}: %@",
        statusNoFace: "Visage non détecté",
        statusAway: "Regard hors des écrans",
        statusPaused: "En pause",
        statusPausedUntil: "En pause — reprise à %@",
        statusPausedTomorrow: "En pause jusqu’à demain",
        statusPausedUntilDay: "En pause — reprise le %@",
        statusPausedReason: "En pause\u{00A0}: %@",
        guardTyping: "vous tapez",
        guardPointer: "souris",
        guardButtonsOrModifiers: "touche ou bouton enfoncé",
        guardSecureInput: "saisie d’un mot de passe",
        guardDictation: "dictée en cours",
        guardMenuOrOverview: "menu ou Mission Control",
        guardIslandOpen: "île ouverte",
        guardOwnPanel: "fenêtre de l’app ouverte",
        guardExcludedSource: "app à ne jamais quitter",
        guardCalibrating: "calibrage en cours",
        guardCooldown: "bascule à l’instant",
        guardLowConfidence: "regard incertain",
        pauseUser: "à votre demande",
        pauseLocked: "Mac verrouillé",
        pauseAsleep: "Mac en veille",
        pauseScreensAsleep: "écrans en veille",
        pauseSessionInactive: "session en arrière-plan",
        pauseIdle: "aucune activité",
        pauseBattery: "batterie",
        pauseLowPower: "mode économie d’énergie",
        pauseThermal: "Mac trop chaud",
        pauseCameraBusy: "aperçu de la caméra ouvert",
        pauseCall: "appel vidéo en cours",
        pauseSingleScreen: "un seul écran",
        pauseLidClosed: "couvercle fermé",
        shortUser: "Pause",
        shortLocked: "Verrouillé",
        shortAsleep: "En veille",
        shortScreensAsleep: "Écrans en veille",
        shortSessionInactive: "Session en arrière-plan",
        shortIdle: "Inactivité",
        shortBattery: "Batterie",
        shortLowPower: "Économie d’énergie",
        shortThermal: "Mac trop chaud",
        shortCameraBusy: "Aperçu caméra",
        shortCall: "Appel vidéo",
        shortSingleScreen: "Un seul écran",
        shortLidClosed: "Couvercle fermé",
        singleScreenHint: "Un seul écran\u{00A0}: passez en mode Zones",
        unavailableCameraPermission: "Autorisation caméra manquante",
        unavailableAccessibility: "Autorisation Accessibilité manquante",
        unavailableNoCamera: "Aucune caméra",
        unavailableCameraDisconnected: "Caméra débranchée",
        unavailableCameraFailed: "La caméra ne répond pas",
        shortCameraPermission: "Autorisation caméra",
        shortAccessibility: "Accessibilité",
        shortNoCamera: "Aucune caméra trouvée",
        shortCameraDisconnected: "Caméra débranchée",
        shortCameraFailed: "Caméra indisponible",
        needFirstTime: "Calibrez pour commencer",
        needNewLayout: "Calibrez pour cette disposition",
        needNewCamera: "Calibrez pour cette caméra",
        needRemoved: "Profil supprimé\u{00A0}: recalibrez",
        shortNeedFirstTime: "Calibrer",
        shortNeedNewLayout: "Nouvelle disposition",
        shortNeedNewCamera: "Nouvelle caméra",
        shortNeedRemoved: "Profil supprimé",
        zoneWhole: "%@ entier",
        zoneLeft: "Zone gauche du %@",
        zoneCenter: "Zone centrale du %@",
        zoneRight: "Zone droite du %@",
        zoneTop: "Zone haute du %@",
        zoneBottom: "Zone basse du %@",
        zoneTopLeft: "Coin haut gauche du %@",
        zoneTopRight: "Coin haut droit du %@",
        zoneBottomLeft: "Coin bas gauche du %@",
        zoneBottomRight: "Coin bas droit du %@",
        zoneWindowOn: "Fenêtre du %@",
        zoneWindowApp: "Fenêtre de %@",
        builtInDisplay: "MacBook",
        modeScreens: "Écrans",
        modeZones: "Zones",
        modeWindows: "Fenêtres",
        modeScreensCaption: "Une zone par écran\u{00A0}: le clavier suit l’écran que vous regardez.",
        modeZonesCaption: "Chaque écran est découpé en zones, idéal pour un grand écran.",
        modeWindowsCaption: "Chaque fenêtre visible est une zone. Demande un calibrage précis.",
        modeSuited: "Adapté à cette disposition",
        modeDiscouraged: "Précision insuffisante pour ce mode sur cette disposition",
        panes: "Panneaux (expérimental)",
        splitWhole: "Entier",
        splitColumns2: "2 colonnes",
        splitColumns3: "3 colonnes",
        splitRows2: "2 lignes",
        splitGrid2x2: "Grille 2×2",
        gradeExcellent: "Excellente",
        gradeGood: "Bonne",
        gradeFair: "Moyenne",
        gradePoor: "Insuffisante",
        calibrationScore: "Calibrage %@",
        calibrationScoreAge: "Calibrage %1$@ · %2$@",
        headOnly: "Tête seule",
        headAndEyes: "Tête et yeux",
        durationFifteenMinutes: "Pendant 15 minutes",
        durationOneHour: "Pendant 1 heure",
        durationUntilTomorrow: "Jusqu’à demain",
        durationUntilResumed: "Jusqu’à reprise",
        energySaver: "Économe",
        energyBalanced: "Équilibré",
        energyReactive: "Réactif",
        batterySame: "Comme sur secteur",
        batterySaver: "Économe",
        batteryPause: "Mettre en pause",
        callKeepRunning: "Continuer",
        callPause: "Mettre en pause",
        pointerAuto: "Automatique",
        pointerStay: "Ne pas bouger",
        pointerFollowScreen: "Suivre l’écran",
        pointerWindowCenter: "Centre de la fenêtre",
        feedbackNone: "Aucun",
        feedbackHalo: "Halo",
        feedbackZone: "Zone",
        islandNever: "Jamais",
        islandPaused: "Pendant une pause ou un calibrage",
        islandAlways: "Toujours (zone active)",
        sensitivityCautious: "Prudent",
        sensitivityLively: "Vif",
        never: "Jamais",
        noticeKindPause: "Pause et reprise",
        noticeKindNewLayout: "Nouvelle disposition",
        noticeKindCamera: "Caméra indisponible",
        noticeKindRecenter: "Recentrage",
        noticeKindCalibrated: "Calibrage réussi",
        noticeKindDrift: "Recalibrage suggéré",
        noticePaused: "Regard en pause",
        noticeResumed: "Regard repris",
        noticeNewLayout: "Nouvelle disposition",
        noticeCameraUnavailable: "Caméra indisponible",
        noticeRecentered: "Recentré",
        noticeCalibrated: "Calibrage réussi · %@",
        noticeDrift: "Le regard se trompe souvent",
        noticePausedUntil: "Reprise à %@",
        noticePausedTomorrow: "Jusqu’à demain",
        noticePausedIndefinitely: "Jusqu’à reprise",
        noticeNewLayoutDetail: "Calibrez pour ces écrans",
        noticeCameraDetail: "Le regard est en pause",
        noticeDriftDetail: "Recalibrez pour l’affiner",
        pausedFor: "En pause · %@",
        pause: "Pause",
        resume: "Reprendre",
        resumeAnyway: "Reprendre quand même",
        recenter: "Recentrer",
        calibrate: "Calibrer",
        calibrateEllipsis: "Calibrer…",
        recalibrate: "Recalibrer",
        quickRecenter: "Recalage rapide",
        test: "Tester",
        enable: "Activer",
        openSettings: "Ouvrir les réglages",
        allowCamera: "Autoriser la caméra",
        allowAccessibility: "Autoriser l’Accessibilité",
        retry: "Réessayer",
        chooseCamera: "Choisir une autre caméra",
        switchToZones: "Passer en mode Zones",
        lastSwitch: "Dernière bascule %@",
        recentSwitches: "Dernières bascules",
        barPauseFifteenMinutes: "Mettre le regard en pause pendant 15 minutes",
        barPauseOneHour: "Mettre le regard en pause pendant 1 heure",
        barPauseUntilTomorrow: "Mettre le regard en pause jusqu’à demain",
        barPauseUntilResumed: "Mettre le regard en pause",
        barResume: "Reprendre le regard",
        barRecenter: "Recentrer le regard",
        barCalibrate: "Calibrer le regard",
        barSwitchMode: "Passer le regard en mode %@",
        barSettings: "Réglages du Focus au regard",
        barKeywords: "regard, yeux, tête, suivi de la tête, caméra, focus, fenêtre, écran, zone, pause, reprendre, recentrer, calibrer",
        shortcutPauseResume: "Mettre en pause ou reprendre",
        shortcutRecenter: "Recentrer",
        shortcutMode: "Changer de mode",
        elidesBeforeVowel: true
    )

    // A copy of the English until its translation (plan §19, package C1); only
    // the feature's name is already this language's (`ForkExtrasStrings`).
    static let ptBR = ForkGlanceStrings(
        featureTitle: "Foco pelo olhar",
        sectionTitle: "Glance",
        searchKeywords: "glance, gaze, eyes, head, head tracking, camera, face, focus, window, display, screen, zone, keyboard",
        featureOff: "Glance Focus is off",
        statusOff: "Off",
        statusActive: "Active",
        statusActiveZone: "Active · %@",
        statusStarting: "Starting the camera…",
        statusCalibrating: "Calibrating…",
        statusCalibratingCount: "Calibrating · %@",
        statusWaiting: "Waiting: %@",
        statusNoFace: "No face detected",
        statusAway: "Looking away from the displays",
        statusPaused: "Paused",
        statusPausedUntil: "Paused — resumes at %@",
        statusPausedTomorrow: "Paused until tomorrow",
        statusPausedUntilDay: "Paused — resumes on %@",
        statusPausedReason: "Paused: %@",
        guardTyping: "you are typing",
        guardPointer: "mouse",
        guardButtonsOrModifiers: "key or button held",
        guardSecureInput: "password entry",
        guardDictation: "dictation in progress",
        guardMenuOrOverview: "menu or Mission Control",
        guardIslandOpen: "island open",
        guardOwnPanel: "app window open",
        guardExcludedSource: "app never to leave",
        guardCalibrating: "calibration in progress",
        guardCooldown: "just switched",
        guardLowConfidence: "gaze unclear",
        pauseUser: "at your request",
        pauseLocked: "Mac locked",
        pauseAsleep: "Mac asleep",
        pauseScreensAsleep: "displays asleep",
        pauseSessionInactive: "session in the background",
        pauseIdle: "no activity",
        pauseBattery: "on battery",
        pauseLowPower: "Low Power Mode",
        pauseThermal: "Mac too hot",
        pauseCameraBusy: "camera preview open",
        pauseCall: "video call in progress",
        pauseSingleScreen: "only one display",
        pauseLidClosed: "lid closed",
        shortUser: "Paused",
        shortLocked: "Locked",
        shortAsleep: "Asleep",
        shortScreensAsleep: "Displays asleep",
        shortSessionInactive: "Session in background",
        shortIdle: "Idle",
        shortBattery: "Battery",
        shortLowPower: "Low Power Mode",
        shortThermal: "Mac too hot",
        shortCameraBusy: "Camera preview",
        shortCall: "Video call",
        shortSingleScreen: "One display",
        shortLidClosed: "Lid closed",
        singleScreenHint: "Only one display: switch to Zones mode",
        unavailableCameraPermission: "Camera access needed",
        unavailableAccessibility: "Accessibility access needed",
        unavailableNoCamera: "No camera",
        unavailableCameraDisconnected: "Camera disconnected",
        unavailableCameraFailed: "The camera is not responding",
        shortCameraPermission: "Camera access",
        shortAccessibility: "Accessibility",
        shortNoCamera: "No camera found",
        shortCameraDisconnected: "Camera unplugged",
        shortCameraFailed: "Camera unavailable",
        needFirstTime: "Calibrate to get started",
        needNewLayout: "Calibrate for this display layout",
        needNewCamera: "Calibrate for this camera",
        needRemoved: "Profile deleted: calibrate again",
        shortNeedFirstTime: "Calibrate",
        shortNeedNewLayout: "New layout",
        shortNeedNewCamera: "New camera",
        shortNeedRemoved: "Profile deleted",
        zoneWhole: "Whole %@",
        zoneLeft: "Left zone of the %@",
        zoneCenter: "Center zone of the %@",
        zoneRight: "Right zone of the %@",
        zoneTop: "Top zone of the %@",
        zoneBottom: "Bottom zone of the %@",
        zoneTopLeft: "Top left of the %@",
        zoneTopRight: "Top right of the %@",
        zoneBottomLeft: "Bottom left of the %@",
        zoneBottomRight: "Bottom right of the %@",
        zoneWindowOn: "Window on the %@",
        zoneWindowApp: "%@ window",
        builtInDisplay: "MacBook",
        modeScreens: "Screens",
        modeZones: "Zones",
        modeWindows: "Windows",
        modeScreensCaption: "One zone per display: the keyboard follows the display you look at.",
        modeZonesCaption: "Each display is split into zones, ideal for a wide display.",
        modeWindowsCaption: "Each visible window is a zone. Needs a precise calibration.",
        modeSuited: "Suited to this layout",
        modeDiscouraged: "Not precise enough for this mode on this layout",
        panes: "Panes (experimental)",
        splitWhole: "Whole",
        splitColumns2: "2 columns",
        splitColumns3: "3 columns",
        splitRows2: "2 rows",
        splitGrid2x2: "2×2 grid",
        gradeExcellent: "Excellent",
        gradeGood: "Good",
        gradeFair: "Fair",
        gradePoor: "Poor",
        calibrationScore: "Calibration %@",
        calibrationScoreAge: "Calibration %1$@ · %2$@",
        headOnly: "Head only",
        headAndEyes: "Head and eyes",
        durationFifteenMinutes: "For 15 minutes",
        durationOneHour: "For 1 hour",
        durationUntilTomorrow: "Until tomorrow",
        durationUntilResumed: "Until resumed",
        energySaver: "Saver",
        energyBalanced: "Balanced",
        energyReactive: "Responsive",
        batterySame: "Same as on power",
        batterySaver: "Saver",
        batteryPause: "Pause",
        callKeepRunning: "Keep going",
        callPause: "Pause",
        pointerAuto: "Automatic",
        pointerStay: "Don’t move",
        pointerFollowScreen: "Follow the display",
        pointerWindowCenter: "Window center",
        feedbackNone: "None",
        feedbackHalo: "Halo",
        feedbackZone: "Zone flash",
        islandNever: "Never",
        islandPaused: "During a pause or calibration",
        islandAlways: "Always (active zone)",
        sensitivityCautious: "Cautious",
        sensitivityLively: "Lively",
        never: "Never",
        noticeKindPause: "Pause and resume",
        noticeKindNewLayout: "New display layout",
        noticeKindCamera: "Camera unavailable",
        noticeKindRecenter: "Recentered",
        noticeKindCalibrated: "Calibration done",
        noticeKindDrift: "Recalibration suggested",
        noticePaused: "Glance paused",
        noticeResumed: "Glance resumed",
        noticeNewLayout: "New display layout",
        noticeCameraUnavailable: "Camera unavailable",
        noticeRecentered: "Recentered",
        noticeCalibrated: "Calibrated · %@",
        noticeDrift: "Glance often gets it wrong",
        noticePausedUntil: "Resumes at %@",
        noticePausedTomorrow: "Until tomorrow",
        noticePausedIndefinitely: "Until you resume",
        noticeNewLayoutDetail: "Calibrate for these displays",
        noticeCameraDetail: "Glance is paused",
        noticeDriftDetail: "Calibrate again to refine it",
        pausedFor: "Paused · %@",
        pause: "Pause",
        resume: "Resume",
        resumeAnyway: "Resume Anyway",
        recenter: "Recenter",
        calibrate: "Calibrate",
        calibrateEllipsis: "Calibrate…",
        recalibrate: "Calibrate Again",
        quickRecenter: "Quick Realign",
        test: "Test",
        enable: "Turn On",
        openSettings: "Open Settings",
        allowCamera: "Allow the Camera",
        allowAccessibility: "Allow Accessibility",
        retry: "Try Again",
        chooseCamera: "Choose Another Camera",
        switchToZones: "Switch to Zones Mode",
        lastSwitch: "Last switch %@",
        recentSwitches: "Recent switches",
        barPauseFifteenMinutes: "Pause Glance for 15 Minutes",
        barPauseOneHour: "Pause Glance for 1 Hour",
        barPauseUntilTomorrow: "Pause Glance Until Tomorrow",
        barPauseUntilResumed: "Pause Glance",
        barResume: "Resume Glance",
        barRecenter: "Recenter Glance",
        barCalibrate: "Calibrate Glance",
        barSwitchMode: "Switch Glance to %@ Mode",
        barSettings: "Glance Focus Settings",
        barKeywords: "glance, gaze, eyes, head, head tracking, camera, focus, window, display, screen, zone, pause, resume, recenter, calibrate",
        shortcutPauseResume: "Pause or resume",
        shortcutRecenter: "Recenter",
        shortcutMode: "Switch mode",
        elidesBeforeVowel: false
    )

    // A copy of the English until its translation (plan §19, package C1); only
    // the feature's name is already this language's (`ForkExtrasStrings`).
    static let tr = ForkGlanceStrings(
        featureTitle: "Bakışla Odak",
        sectionTitle: "Glance",
        searchKeywords: "glance, gaze, eyes, head, head tracking, camera, face, focus, window, display, screen, zone, keyboard",
        featureOff: "Glance Focus is off",
        statusOff: "Off",
        statusActive: "Active",
        statusActiveZone: "Active · %@",
        statusStarting: "Starting the camera…",
        statusCalibrating: "Calibrating…",
        statusCalibratingCount: "Calibrating · %@",
        statusWaiting: "Waiting: %@",
        statusNoFace: "No face detected",
        statusAway: "Looking away from the displays",
        statusPaused: "Paused",
        statusPausedUntil: "Paused — resumes at %@",
        statusPausedTomorrow: "Paused until tomorrow",
        statusPausedUntilDay: "Paused — resumes on %@",
        statusPausedReason: "Paused: %@",
        guardTyping: "you are typing",
        guardPointer: "mouse",
        guardButtonsOrModifiers: "key or button held",
        guardSecureInput: "password entry",
        guardDictation: "dictation in progress",
        guardMenuOrOverview: "menu or Mission Control",
        guardIslandOpen: "island open",
        guardOwnPanel: "app window open",
        guardExcludedSource: "app never to leave",
        guardCalibrating: "calibration in progress",
        guardCooldown: "just switched",
        guardLowConfidence: "gaze unclear",
        pauseUser: "at your request",
        pauseLocked: "Mac locked",
        pauseAsleep: "Mac asleep",
        pauseScreensAsleep: "displays asleep",
        pauseSessionInactive: "session in the background",
        pauseIdle: "no activity",
        pauseBattery: "on battery",
        pauseLowPower: "Low Power Mode",
        pauseThermal: "Mac too hot",
        pauseCameraBusy: "camera preview open",
        pauseCall: "video call in progress",
        pauseSingleScreen: "only one display",
        pauseLidClosed: "lid closed",
        shortUser: "Paused",
        shortLocked: "Locked",
        shortAsleep: "Asleep",
        shortScreensAsleep: "Displays asleep",
        shortSessionInactive: "Session in background",
        shortIdle: "Idle",
        shortBattery: "Battery",
        shortLowPower: "Low Power Mode",
        shortThermal: "Mac too hot",
        shortCameraBusy: "Camera preview",
        shortCall: "Video call",
        shortSingleScreen: "One display",
        shortLidClosed: "Lid closed",
        singleScreenHint: "Only one display: switch to Zones mode",
        unavailableCameraPermission: "Camera access needed",
        unavailableAccessibility: "Accessibility access needed",
        unavailableNoCamera: "No camera",
        unavailableCameraDisconnected: "Camera disconnected",
        unavailableCameraFailed: "The camera is not responding",
        shortCameraPermission: "Camera access",
        shortAccessibility: "Accessibility",
        shortNoCamera: "No camera found",
        shortCameraDisconnected: "Camera unplugged",
        shortCameraFailed: "Camera unavailable",
        needFirstTime: "Calibrate to get started",
        needNewLayout: "Calibrate for this display layout",
        needNewCamera: "Calibrate for this camera",
        needRemoved: "Profile deleted: calibrate again",
        shortNeedFirstTime: "Calibrate",
        shortNeedNewLayout: "New layout",
        shortNeedNewCamera: "New camera",
        shortNeedRemoved: "Profile deleted",
        zoneWhole: "Whole %@",
        zoneLeft: "Left zone of the %@",
        zoneCenter: "Center zone of the %@",
        zoneRight: "Right zone of the %@",
        zoneTop: "Top zone of the %@",
        zoneBottom: "Bottom zone of the %@",
        zoneTopLeft: "Top left of the %@",
        zoneTopRight: "Top right of the %@",
        zoneBottomLeft: "Bottom left of the %@",
        zoneBottomRight: "Bottom right of the %@",
        zoneWindowOn: "Window on the %@",
        zoneWindowApp: "%@ window",
        builtInDisplay: "MacBook",
        modeScreens: "Screens",
        modeZones: "Zones",
        modeWindows: "Windows",
        modeScreensCaption: "One zone per display: the keyboard follows the display you look at.",
        modeZonesCaption: "Each display is split into zones, ideal for a wide display.",
        modeWindowsCaption: "Each visible window is a zone. Needs a precise calibration.",
        modeSuited: "Suited to this layout",
        modeDiscouraged: "Not precise enough for this mode on this layout",
        panes: "Panes (experimental)",
        splitWhole: "Whole",
        splitColumns2: "2 columns",
        splitColumns3: "3 columns",
        splitRows2: "2 rows",
        splitGrid2x2: "2×2 grid",
        gradeExcellent: "Excellent",
        gradeGood: "Good",
        gradeFair: "Fair",
        gradePoor: "Poor",
        calibrationScore: "Calibration %@",
        calibrationScoreAge: "Calibration %1$@ · %2$@",
        headOnly: "Head only",
        headAndEyes: "Head and eyes",
        durationFifteenMinutes: "For 15 minutes",
        durationOneHour: "For 1 hour",
        durationUntilTomorrow: "Until tomorrow",
        durationUntilResumed: "Until resumed",
        energySaver: "Saver",
        energyBalanced: "Balanced",
        energyReactive: "Responsive",
        batterySame: "Same as on power",
        batterySaver: "Saver",
        batteryPause: "Pause",
        callKeepRunning: "Keep going",
        callPause: "Pause",
        pointerAuto: "Automatic",
        pointerStay: "Don’t move",
        pointerFollowScreen: "Follow the display",
        pointerWindowCenter: "Window center",
        feedbackNone: "None",
        feedbackHalo: "Halo",
        feedbackZone: "Zone flash",
        islandNever: "Never",
        islandPaused: "During a pause or calibration",
        islandAlways: "Always (active zone)",
        sensitivityCautious: "Cautious",
        sensitivityLively: "Lively",
        never: "Never",
        noticeKindPause: "Pause and resume",
        noticeKindNewLayout: "New display layout",
        noticeKindCamera: "Camera unavailable",
        noticeKindRecenter: "Recentered",
        noticeKindCalibrated: "Calibration done",
        noticeKindDrift: "Recalibration suggested",
        noticePaused: "Glance paused",
        noticeResumed: "Glance resumed",
        noticeNewLayout: "New display layout",
        noticeCameraUnavailable: "Camera unavailable",
        noticeRecentered: "Recentered",
        noticeCalibrated: "Calibrated · %@",
        noticeDrift: "Glance often gets it wrong",
        noticePausedUntil: "Resumes at %@",
        noticePausedTomorrow: "Until tomorrow",
        noticePausedIndefinitely: "Until you resume",
        noticeNewLayoutDetail: "Calibrate for these displays",
        noticeCameraDetail: "Glance is paused",
        noticeDriftDetail: "Calibrate again to refine it",
        pausedFor: "Paused · %@",
        pause: "Pause",
        resume: "Resume",
        resumeAnyway: "Resume Anyway",
        recenter: "Recenter",
        calibrate: "Calibrate",
        calibrateEllipsis: "Calibrate…",
        recalibrate: "Calibrate Again",
        quickRecenter: "Quick Realign",
        test: "Test",
        enable: "Turn On",
        openSettings: "Open Settings",
        allowCamera: "Allow the Camera",
        allowAccessibility: "Allow Accessibility",
        retry: "Try Again",
        chooseCamera: "Choose Another Camera",
        switchToZones: "Switch to Zones Mode",
        lastSwitch: "Last switch %@",
        recentSwitches: "Recent switches",
        barPauseFifteenMinutes: "Pause Glance for 15 Minutes",
        barPauseOneHour: "Pause Glance for 1 Hour",
        barPauseUntilTomorrow: "Pause Glance Until Tomorrow",
        barPauseUntilResumed: "Pause Glance",
        barResume: "Resume Glance",
        barRecenter: "Recenter Glance",
        barCalibrate: "Calibrate Glance",
        barSwitchMode: "Switch Glance to %@ Mode",
        barSettings: "Glance Focus Settings",
        barKeywords: "glance, gaze, eyes, head, head tracking, camera, focus, window, display, screen, zone, pause, resume, recenter, calibrate",
        shortcutPauseResume: "Pause or resume",
        shortcutRecenter: "Recenter",
        shortcutMode: "Switch mode",
        elidesBeforeVowel: false
    )

    // A copy of the English until its translation (plan §19, package C1); only
    // the feature's name is already this language's (`ForkExtrasStrings`).
    static let ru = ForkGlanceStrings(
        featureTitle: "Фокус взглядом",
        sectionTitle: "Glance",
        searchKeywords: "glance, gaze, eyes, head, head tracking, camera, face, focus, window, display, screen, zone, keyboard",
        featureOff: "Glance Focus is off",
        statusOff: "Off",
        statusActive: "Active",
        statusActiveZone: "Active · %@",
        statusStarting: "Starting the camera…",
        statusCalibrating: "Calibrating…",
        statusCalibratingCount: "Calibrating · %@",
        statusWaiting: "Waiting: %@",
        statusNoFace: "No face detected",
        statusAway: "Looking away from the displays",
        statusPaused: "Paused",
        statusPausedUntil: "Paused — resumes at %@",
        statusPausedTomorrow: "Paused until tomorrow",
        statusPausedUntilDay: "Paused — resumes on %@",
        statusPausedReason: "Paused: %@",
        guardTyping: "you are typing",
        guardPointer: "mouse",
        guardButtonsOrModifiers: "key or button held",
        guardSecureInput: "password entry",
        guardDictation: "dictation in progress",
        guardMenuOrOverview: "menu or Mission Control",
        guardIslandOpen: "island open",
        guardOwnPanel: "app window open",
        guardExcludedSource: "app never to leave",
        guardCalibrating: "calibration in progress",
        guardCooldown: "just switched",
        guardLowConfidence: "gaze unclear",
        pauseUser: "at your request",
        pauseLocked: "Mac locked",
        pauseAsleep: "Mac asleep",
        pauseScreensAsleep: "displays asleep",
        pauseSessionInactive: "session in the background",
        pauseIdle: "no activity",
        pauseBattery: "on battery",
        pauseLowPower: "Low Power Mode",
        pauseThermal: "Mac too hot",
        pauseCameraBusy: "camera preview open",
        pauseCall: "video call in progress",
        pauseSingleScreen: "only one display",
        pauseLidClosed: "lid closed",
        shortUser: "Paused",
        shortLocked: "Locked",
        shortAsleep: "Asleep",
        shortScreensAsleep: "Displays asleep",
        shortSessionInactive: "Session in background",
        shortIdle: "Idle",
        shortBattery: "Battery",
        shortLowPower: "Low Power Mode",
        shortThermal: "Mac too hot",
        shortCameraBusy: "Camera preview",
        shortCall: "Video call",
        shortSingleScreen: "One display",
        shortLidClosed: "Lid closed",
        singleScreenHint: "Only one display: switch to Zones mode",
        unavailableCameraPermission: "Camera access needed",
        unavailableAccessibility: "Accessibility access needed",
        unavailableNoCamera: "No camera",
        unavailableCameraDisconnected: "Camera disconnected",
        unavailableCameraFailed: "The camera is not responding",
        shortCameraPermission: "Camera access",
        shortAccessibility: "Accessibility",
        shortNoCamera: "No camera found",
        shortCameraDisconnected: "Camera unplugged",
        shortCameraFailed: "Camera unavailable",
        needFirstTime: "Calibrate to get started",
        needNewLayout: "Calibrate for this display layout",
        needNewCamera: "Calibrate for this camera",
        needRemoved: "Profile deleted: calibrate again",
        shortNeedFirstTime: "Calibrate",
        shortNeedNewLayout: "New layout",
        shortNeedNewCamera: "New camera",
        shortNeedRemoved: "Profile deleted",
        zoneWhole: "Whole %@",
        zoneLeft: "Left zone of the %@",
        zoneCenter: "Center zone of the %@",
        zoneRight: "Right zone of the %@",
        zoneTop: "Top zone of the %@",
        zoneBottom: "Bottom zone of the %@",
        zoneTopLeft: "Top left of the %@",
        zoneTopRight: "Top right of the %@",
        zoneBottomLeft: "Bottom left of the %@",
        zoneBottomRight: "Bottom right of the %@",
        zoneWindowOn: "Window on the %@",
        zoneWindowApp: "%@ window",
        builtInDisplay: "MacBook",
        modeScreens: "Screens",
        modeZones: "Zones",
        modeWindows: "Windows",
        modeScreensCaption: "One zone per display: the keyboard follows the display you look at.",
        modeZonesCaption: "Each display is split into zones, ideal for a wide display.",
        modeWindowsCaption: "Each visible window is a zone. Needs a precise calibration.",
        modeSuited: "Suited to this layout",
        modeDiscouraged: "Not precise enough for this mode on this layout",
        panes: "Panes (experimental)",
        splitWhole: "Whole",
        splitColumns2: "2 columns",
        splitColumns3: "3 columns",
        splitRows2: "2 rows",
        splitGrid2x2: "2×2 grid",
        gradeExcellent: "Excellent",
        gradeGood: "Good",
        gradeFair: "Fair",
        gradePoor: "Poor",
        calibrationScore: "Calibration %@",
        calibrationScoreAge: "Calibration %1$@ · %2$@",
        headOnly: "Head only",
        headAndEyes: "Head and eyes",
        durationFifteenMinutes: "For 15 minutes",
        durationOneHour: "For 1 hour",
        durationUntilTomorrow: "Until tomorrow",
        durationUntilResumed: "Until resumed",
        energySaver: "Saver",
        energyBalanced: "Balanced",
        energyReactive: "Responsive",
        batterySame: "Same as on power",
        batterySaver: "Saver",
        batteryPause: "Pause",
        callKeepRunning: "Keep going",
        callPause: "Pause",
        pointerAuto: "Automatic",
        pointerStay: "Don’t move",
        pointerFollowScreen: "Follow the display",
        pointerWindowCenter: "Window center",
        feedbackNone: "None",
        feedbackHalo: "Halo",
        feedbackZone: "Zone flash",
        islandNever: "Never",
        islandPaused: "During a pause or calibration",
        islandAlways: "Always (active zone)",
        sensitivityCautious: "Cautious",
        sensitivityLively: "Lively",
        never: "Never",
        noticeKindPause: "Pause and resume",
        noticeKindNewLayout: "New display layout",
        noticeKindCamera: "Camera unavailable",
        noticeKindRecenter: "Recentered",
        noticeKindCalibrated: "Calibration done",
        noticeKindDrift: "Recalibration suggested",
        noticePaused: "Glance paused",
        noticeResumed: "Glance resumed",
        noticeNewLayout: "New display layout",
        noticeCameraUnavailable: "Camera unavailable",
        noticeRecentered: "Recentered",
        noticeCalibrated: "Calibrated · %@",
        noticeDrift: "Glance often gets it wrong",
        noticePausedUntil: "Resumes at %@",
        noticePausedTomorrow: "Until tomorrow",
        noticePausedIndefinitely: "Until you resume",
        noticeNewLayoutDetail: "Calibrate for these displays",
        noticeCameraDetail: "Glance is paused",
        noticeDriftDetail: "Calibrate again to refine it",
        pausedFor: "Paused · %@",
        pause: "Pause",
        resume: "Resume",
        resumeAnyway: "Resume Anyway",
        recenter: "Recenter",
        calibrate: "Calibrate",
        calibrateEllipsis: "Calibrate…",
        recalibrate: "Calibrate Again",
        quickRecenter: "Quick Realign",
        test: "Test",
        enable: "Turn On",
        openSettings: "Open Settings",
        allowCamera: "Allow the Camera",
        allowAccessibility: "Allow Accessibility",
        retry: "Try Again",
        chooseCamera: "Choose Another Camera",
        switchToZones: "Switch to Zones Mode",
        lastSwitch: "Last switch %@",
        recentSwitches: "Recent switches",
        barPauseFifteenMinutes: "Pause Glance for 15 Minutes",
        barPauseOneHour: "Pause Glance for 1 Hour",
        barPauseUntilTomorrow: "Pause Glance Until Tomorrow",
        barPauseUntilResumed: "Pause Glance",
        barResume: "Resume Glance",
        barRecenter: "Recenter Glance",
        barCalibrate: "Calibrate Glance",
        barSwitchMode: "Switch Glance to %@ Mode",
        barSettings: "Glance Focus Settings",
        barKeywords: "glance, gaze, eyes, head, head tracking, camera, focus, window, display, screen, zone, pause, resume, recenter, calibrate",
        shortcutPauseResume: "Pause or resume",
        shortcutRecenter: "Recenter",
        shortcutMode: "Switch mode",
        elidesBeforeVowel: false
    )

    // A copy of the English until its translation (plan §19, package C1); only
    // the feature's name is already this language's (`ForkExtrasStrings`).
    static let es = ForkGlanceStrings(
        featureTitle: "Foco con la mirada",
        sectionTitle: "Glance",
        searchKeywords: "glance, gaze, eyes, head, head tracking, camera, face, focus, window, display, screen, zone, keyboard",
        featureOff: "Glance Focus is off",
        statusOff: "Off",
        statusActive: "Active",
        statusActiveZone: "Active · %@",
        statusStarting: "Starting the camera…",
        statusCalibrating: "Calibrating…",
        statusCalibratingCount: "Calibrating · %@",
        statusWaiting: "Waiting: %@",
        statusNoFace: "No face detected",
        statusAway: "Looking away from the displays",
        statusPaused: "Paused",
        statusPausedUntil: "Paused — resumes at %@",
        statusPausedTomorrow: "Paused until tomorrow",
        statusPausedUntilDay: "Paused — resumes on %@",
        statusPausedReason: "Paused: %@",
        guardTyping: "you are typing",
        guardPointer: "mouse",
        guardButtonsOrModifiers: "key or button held",
        guardSecureInput: "password entry",
        guardDictation: "dictation in progress",
        guardMenuOrOverview: "menu or Mission Control",
        guardIslandOpen: "island open",
        guardOwnPanel: "app window open",
        guardExcludedSource: "app never to leave",
        guardCalibrating: "calibration in progress",
        guardCooldown: "just switched",
        guardLowConfidence: "gaze unclear",
        pauseUser: "at your request",
        pauseLocked: "Mac locked",
        pauseAsleep: "Mac asleep",
        pauseScreensAsleep: "displays asleep",
        pauseSessionInactive: "session in the background",
        pauseIdle: "no activity",
        pauseBattery: "on battery",
        pauseLowPower: "Low Power Mode",
        pauseThermal: "Mac too hot",
        pauseCameraBusy: "camera preview open",
        pauseCall: "video call in progress",
        pauseSingleScreen: "only one display",
        pauseLidClosed: "lid closed",
        shortUser: "Paused",
        shortLocked: "Locked",
        shortAsleep: "Asleep",
        shortScreensAsleep: "Displays asleep",
        shortSessionInactive: "Session in background",
        shortIdle: "Idle",
        shortBattery: "Battery",
        shortLowPower: "Low Power Mode",
        shortThermal: "Mac too hot",
        shortCameraBusy: "Camera preview",
        shortCall: "Video call",
        shortSingleScreen: "One display",
        shortLidClosed: "Lid closed",
        singleScreenHint: "Only one display: switch to Zones mode",
        unavailableCameraPermission: "Camera access needed",
        unavailableAccessibility: "Accessibility access needed",
        unavailableNoCamera: "No camera",
        unavailableCameraDisconnected: "Camera disconnected",
        unavailableCameraFailed: "The camera is not responding",
        shortCameraPermission: "Camera access",
        shortAccessibility: "Accessibility",
        shortNoCamera: "No camera found",
        shortCameraDisconnected: "Camera unplugged",
        shortCameraFailed: "Camera unavailable",
        needFirstTime: "Calibrate to get started",
        needNewLayout: "Calibrate for this display layout",
        needNewCamera: "Calibrate for this camera",
        needRemoved: "Profile deleted: calibrate again",
        shortNeedFirstTime: "Calibrate",
        shortNeedNewLayout: "New layout",
        shortNeedNewCamera: "New camera",
        shortNeedRemoved: "Profile deleted",
        zoneWhole: "Whole %@",
        zoneLeft: "Left zone of the %@",
        zoneCenter: "Center zone of the %@",
        zoneRight: "Right zone of the %@",
        zoneTop: "Top zone of the %@",
        zoneBottom: "Bottom zone of the %@",
        zoneTopLeft: "Top left of the %@",
        zoneTopRight: "Top right of the %@",
        zoneBottomLeft: "Bottom left of the %@",
        zoneBottomRight: "Bottom right of the %@",
        zoneWindowOn: "Window on the %@",
        zoneWindowApp: "%@ window",
        builtInDisplay: "MacBook",
        modeScreens: "Screens",
        modeZones: "Zones",
        modeWindows: "Windows",
        modeScreensCaption: "One zone per display: the keyboard follows the display you look at.",
        modeZonesCaption: "Each display is split into zones, ideal for a wide display.",
        modeWindowsCaption: "Each visible window is a zone. Needs a precise calibration.",
        modeSuited: "Suited to this layout",
        modeDiscouraged: "Not precise enough for this mode on this layout",
        panes: "Panes (experimental)",
        splitWhole: "Whole",
        splitColumns2: "2 columns",
        splitColumns3: "3 columns",
        splitRows2: "2 rows",
        splitGrid2x2: "2×2 grid",
        gradeExcellent: "Excellent",
        gradeGood: "Good",
        gradeFair: "Fair",
        gradePoor: "Poor",
        calibrationScore: "Calibration %@",
        calibrationScoreAge: "Calibration %1$@ · %2$@",
        headOnly: "Head only",
        headAndEyes: "Head and eyes",
        durationFifteenMinutes: "For 15 minutes",
        durationOneHour: "For 1 hour",
        durationUntilTomorrow: "Until tomorrow",
        durationUntilResumed: "Until resumed",
        energySaver: "Saver",
        energyBalanced: "Balanced",
        energyReactive: "Responsive",
        batterySame: "Same as on power",
        batterySaver: "Saver",
        batteryPause: "Pause",
        callKeepRunning: "Keep going",
        callPause: "Pause",
        pointerAuto: "Automatic",
        pointerStay: "Don’t move",
        pointerFollowScreen: "Follow the display",
        pointerWindowCenter: "Window center",
        feedbackNone: "None",
        feedbackHalo: "Halo",
        feedbackZone: "Zone flash",
        islandNever: "Never",
        islandPaused: "During a pause or calibration",
        islandAlways: "Always (active zone)",
        sensitivityCautious: "Cautious",
        sensitivityLively: "Lively",
        never: "Never",
        noticeKindPause: "Pause and resume",
        noticeKindNewLayout: "New display layout",
        noticeKindCamera: "Camera unavailable",
        noticeKindRecenter: "Recentered",
        noticeKindCalibrated: "Calibration done",
        noticeKindDrift: "Recalibration suggested",
        noticePaused: "Glance paused",
        noticeResumed: "Glance resumed",
        noticeNewLayout: "New display layout",
        noticeCameraUnavailable: "Camera unavailable",
        noticeRecentered: "Recentered",
        noticeCalibrated: "Calibrated · %@",
        noticeDrift: "Glance often gets it wrong",
        noticePausedUntil: "Resumes at %@",
        noticePausedTomorrow: "Until tomorrow",
        noticePausedIndefinitely: "Until you resume",
        noticeNewLayoutDetail: "Calibrate for these displays",
        noticeCameraDetail: "Glance is paused",
        noticeDriftDetail: "Calibrate again to refine it",
        pausedFor: "Paused · %@",
        pause: "Pause",
        resume: "Resume",
        resumeAnyway: "Resume Anyway",
        recenter: "Recenter",
        calibrate: "Calibrate",
        calibrateEllipsis: "Calibrate…",
        recalibrate: "Calibrate Again",
        quickRecenter: "Quick Realign",
        test: "Test",
        enable: "Turn On",
        openSettings: "Open Settings",
        allowCamera: "Allow the Camera",
        allowAccessibility: "Allow Accessibility",
        retry: "Try Again",
        chooseCamera: "Choose Another Camera",
        switchToZones: "Switch to Zones Mode",
        lastSwitch: "Last switch %@",
        recentSwitches: "Recent switches",
        barPauseFifteenMinutes: "Pause Glance for 15 Minutes",
        barPauseOneHour: "Pause Glance for 1 Hour",
        barPauseUntilTomorrow: "Pause Glance Until Tomorrow",
        barPauseUntilResumed: "Pause Glance",
        barResume: "Resume Glance",
        barRecenter: "Recenter Glance",
        barCalibrate: "Calibrate Glance",
        barSwitchMode: "Switch Glance to %@ Mode",
        barSettings: "Glance Focus Settings",
        barKeywords: "glance, gaze, eyes, head, head tracking, camera, focus, window, display, screen, zone, pause, resume, recenter, calibrate",
        shortcutPauseResume: "Pause or resume",
        shortcutRecenter: "Recenter",
        shortcutMode: "Switch mode",
        elidesBeforeVowel: false
    )

    // A copy of the English until its translation (plan §19, package C1); only
    // the feature's name is already this language's (`ForkExtrasStrings`).
    static let sk = ForkGlanceStrings(
        featureTitle: "Fokus pohľadom",
        sectionTitle: "Glance",
        searchKeywords: "glance, gaze, eyes, head, head tracking, camera, face, focus, window, display, screen, zone, keyboard",
        featureOff: "Glance Focus is off",
        statusOff: "Off",
        statusActive: "Active",
        statusActiveZone: "Active · %@",
        statusStarting: "Starting the camera…",
        statusCalibrating: "Calibrating…",
        statusCalibratingCount: "Calibrating · %@",
        statusWaiting: "Waiting: %@",
        statusNoFace: "No face detected",
        statusAway: "Looking away from the displays",
        statusPaused: "Paused",
        statusPausedUntil: "Paused — resumes at %@",
        statusPausedTomorrow: "Paused until tomorrow",
        statusPausedUntilDay: "Paused — resumes on %@",
        statusPausedReason: "Paused: %@",
        guardTyping: "you are typing",
        guardPointer: "mouse",
        guardButtonsOrModifiers: "key or button held",
        guardSecureInput: "password entry",
        guardDictation: "dictation in progress",
        guardMenuOrOverview: "menu or Mission Control",
        guardIslandOpen: "island open",
        guardOwnPanel: "app window open",
        guardExcludedSource: "app never to leave",
        guardCalibrating: "calibration in progress",
        guardCooldown: "just switched",
        guardLowConfidence: "gaze unclear",
        pauseUser: "at your request",
        pauseLocked: "Mac locked",
        pauseAsleep: "Mac asleep",
        pauseScreensAsleep: "displays asleep",
        pauseSessionInactive: "session in the background",
        pauseIdle: "no activity",
        pauseBattery: "on battery",
        pauseLowPower: "Low Power Mode",
        pauseThermal: "Mac too hot",
        pauseCameraBusy: "camera preview open",
        pauseCall: "video call in progress",
        pauseSingleScreen: "only one display",
        pauseLidClosed: "lid closed",
        shortUser: "Paused",
        shortLocked: "Locked",
        shortAsleep: "Asleep",
        shortScreensAsleep: "Displays asleep",
        shortSessionInactive: "Session in background",
        shortIdle: "Idle",
        shortBattery: "Battery",
        shortLowPower: "Low Power Mode",
        shortThermal: "Mac too hot",
        shortCameraBusy: "Camera preview",
        shortCall: "Video call",
        shortSingleScreen: "One display",
        shortLidClosed: "Lid closed",
        singleScreenHint: "Only one display: switch to Zones mode",
        unavailableCameraPermission: "Camera access needed",
        unavailableAccessibility: "Accessibility access needed",
        unavailableNoCamera: "No camera",
        unavailableCameraDisconnected: "Camera disconnected",
        unavailableCameraFailed: "The camera is not responding",
        shortCameraPermission: "Camera access",
        shortAccessibility: "Accessibility",
        shortNoCamera: "No camera found",
        shortCameraDisconnected: "Camera unplugged",
        shortCameraFailed: "Camera unavailable",
        needFirstTime: "Calibrate to get started",
        needNewLayout: "Calibrate for this display layout",
        needNewCamera: "Calibrate for this camera",
        needRemoved: "Profile deleted: calibrate again",
        shortNeedFirstTime: "Calibrate",
        shortNeedNewLayout: "New layout",
        shortNeedNewCamera: "New camera",
        shortNeedRemoved: "Profile deleted",
        zoneWhole: "Whole %@",
        zoneLeft: "Left zone of the %@",
        zoneCenter: "Center zone of the %@",
        zoneRight: "Right zone of the %@",
        zoneTop: "Top zone of the %@",
        zoneBottom: "Bottom zone of the %@",
        zoneTopLeft: "Top left of the %@",
        zoneTopRight: "Top right of the %@",
        zoneBottomLeft: "Bottom left of the %@",
        zoneBottomRight: "Bottom right of the %@",
        zoneWindowOn: "Window on the %@",
        zoneWindowApp: "%@ window",
        builtInDisplay: "MacBook",
        modeScreens: "Screens",
        modeZones: "Zones",
        modeWindows: "Windows",
        modeScreensCaption: "One zone per display: the keyboard follows the display you look at.",
        modeZonesCaption: "Each display is split into zones, ideal for a wide display.",
        modeWindowsCaption: "Each visible window is a zone. Needs a precise calibration.",
        modeSuited: "Suited to this layout",
        modeDiscouraged: "Not precise enough for this mode on this layout",
        panes: "Panes (experimental)",
        splitWhole: "Whole",
        splitColumns2: "2 columns",
        splitColumns3: "3 columns",
        splitRows2: "2 rows",
        splitGrid2x2: "2×2 grid",
        gradeExcellent: "Excellent",
        gradeGood: "Good",
        gradeFair: "Fair",
        gradePoor: "Poor",
        calibrationScore: "Calibration %@",
        calibrationScoreAge: "Calibration %1$@ · %2$@",
        headOnly: "Head only",
        headAndEyes: "Head and eyes",
        durationFifteenMinutes: "For 15 minutes",
        durationOneHour: "For 1 hour",
        durationUntilTomorrow: "Until tomorrow",
        durationUntilResumed: "Until resumed",
        energySaver: "Saver",
        energyBalanced: "Balanced",
        energyReactive: "Responsive",
        batterySame: "Same as on power",
        batterySaver: "Saver",
        batteryPause: "Pause",
        callKeepRunning: "Keep going",
        callPause: "Pause",
        pointerAuto: "Automatic",
        pointerStay: "Don’t move",
        pointerFollowScreen: "Follow the display",
        pointerWindowCenter: "Window center",
        feedbackNone: "None",
        feedbackHalo: "Halo",
        feedbackZone: "Zone flash",
        islandNever: "Never",
        islandPaused: "During a pause or calibration",
        islandAlways: "Always (active zone)",
        sensitivityCautious: "Cautious",
        sensitivityLively: "Lively",
        never: "Never",
        noticeKindPause: "Pause and resume",
        noticeKindNewLayout: "New display layout",
        noticeKindCamera: "Camera unavailable",
        noticeKindRecenter: "Recentered",
        noticeKindCalibrated: "Calibration done",
        noticeKindDrift: "Recalibration suggested",
        noticePaused: "Glance paused",
        noticeResumed: "Glance resumed",
        noticeNewLayout: "New display layout",
        noticeCameraUnavailable: "Camera unavailable",
        noticeRecentered: "Recentered",
        noticeCalibrated: "Calibrated · %@",
        noticeDrift: "Glance often gets it wrong",
        noticePausedUntil: "Resumes at %@",
        noticePausedTomorrow: "Until tomorrow",
        noticePausedIndefinitely: "Until you resume",
        noticeNewLayoutDetail: "Calibrate for these displays",
        noticeCameraDetail: "Glance is paused",
        noticeDriftDetail: "Calibrate again to refine it",
        pausedFor: "Paused · %@",
        pause: "Pause",
        resume: "Resume",
        resumeAnyway: "Resume Anyway",
        recenter: "Recenter",
        calibrate: "Calibrate",
        calibrateEllipsis: "Calibrate…",
        recalibrate: "Calibrate Again",
        quickRecenter: "Quick Realign",
        test: "Test",
        enable: "Turn On",
        openSettings: "Open Settings",
        allowCamera: "Allow the Camera",
        allowAccessibility: "Allow Accessibility",
        retry: "Try Again",
        chooseCamera: "Choose Another Camera",
        switchToZones: "Switch to Zones Mode",
        lastSwitch: "Last switch %@",
        recentSwitches: "Recent switches",
        barPauseFifteenMinutes: "Pause Glance for 15 Minutes",
        barPauseOneHour: "Pause Glance for 1 Hour",
        barPauseUntilTomorrow: "Pause Glance Until Tomorrow",
        barPauseUntilResumed: "Pause Glance",
        barResume: "Resume Glance",
        barRecenter: "Recenter Glance",
        barCalibrate: "Calibrate Glance",
        barSwitchMode: "Switch Glance to %@ Mode",
        barSettings: "Glance Focus Settings",
        barKeywords: "glance, gaze, eyes, head, head tracking, camera, focus, window, display, screen, zone, pause, resume, recenter, calibrate",
        shortcutPauseResume: "Pause or resume",
        shortcutRecenter: "Recenter",
        shortcutMode: "Switch mode",
        elidesBeforeVowel: false
    )

    // A copy of the English until its translation (plan §19, package C1); only
    // the feature's name is already this language's (`ForkExtrasStrings`).
    static let de = ForkGlanceStrings(
        featureTitle: "Blickfokus",
        sectionTitle: "Glance",
        searchKeywords: "glance, gaze, eyes, head, head tracking, camera, face, focus, window, display, screen, zone, keyboard",
        featureOff: "Glance Focus is off",
        statusOff: "Off",
        statusActive: "Active",
        statusActiveZone: "Active · %@",
        statusStarting: "Starting the camera…",
        statusCalibrating: "Calibrating…",
        statusCalibratingCount: "Calibrating · %@",
        statusWaiting: "Waiting: %@",
        statusNoFace: "No face detected",
        statusAway: "Looking away from the displays",
        statusPaused: "Paused",
        statusPausedUntil: "Paused — resumes at %@",
        statusPausedTomorrow: "Paused until tomorrow",
        statusPausedUntilDay: "Paused — resumes on %@",
        statusPausedReason: "Paused: %@",
        guardTyping: "you are typing",
        guardPointer: "mouse",
        guardButtonsOrModifiers: "key or button held",
        guardSecureInput: "password entry",
        guardDictation: "dictation in progress",
        guardMenuOrOverview: "menu or Mission Control",
        guardIslandOpen: "island open",
        guardOwnPanel: "app window open",
        guardExcludedSource: "app never to leave",
        guardCalibrating: "calibration in progress",
        guardCooldown: "just switched",
        guardLowConfidence: "gaze unclear",
        pauseUser: "at your request",
        pauseLocked: "Mac locked",
        pauseAsleep: "Mac asleep",
        pauseScreensAsleep: "displays asleep",
        pauseSessionInactive: "session in the background",
        pauseIdle: "no activity",
        pauseBattery: "on battery",
        pauseLowPower: "Low Power Mode",
        pauseThermal: "Mac too hot",
        pauseCameraBusy: "camera preview open",
        pauseCall: "video call in progress",
        pauseSingleScreen: "only one display",
        pauseLidClosed: "lid closed",
        shortUser: "Paused",
        shortLocked: "Locked",
        shortAsleep: "Asleep",
        shortScreensAsleep: "Displays asleep",
        shortSessionInactive: "Session in background",
        shortIdle: "Idle",
        shortBattery: "Battery",
        shortLowPower: "Low Power Mode",
        shortThermal: "Mac too hot",
        shortCameraBusy: "Camera preview",
        shortCall: "Video call",
        shortSingleScreen: "One display",
        shortLidClosed: "Lid closed",
        singleScreenHint: "Only one display: switch to Zones mode",
        unavailableCameraPermission: "Camera access needed",
        unavailableAccessibility: "Accessibility access needed",
        unavailableNoCamera: "No camera",
        unavailableCameraDisconnected: "Camera disconnected",
        unavailableCameraFailed: "The camera is not responding",
        shortCameraPermission: "Camera access",
        shortAccessibility: "Accessibility",
        shortNoCamera: "No camera found",
        shortCameraDisconnected: "Camera unplugged",
        shortCameraFailed: "Camera unavailable",
        needFirstTime: "Calibrate to get started",
        needNewLayout: "Calibrate for this display layout",
        needNewCamera: "Calibrate for this camera",
        needRemoved: "Profile deleted: calibrate again",
        shortNeedFirstTime: "Calibrate",
        shortNeedNewLayout: "New layout",
        shortNeedNewCamera: "New camera",
        shortNeedRemoved: "Profile deleted",
        zoneWhole: "Whole %@",
        zoneLeft: "Left zone of the %@",
        zoneCenter: "Center zone of the %@",
        zoneRight: "Right zone of the %@",
        zoneTop: "Top zone of the %@",
        zoneBottom: "Bottom zone of the %@",
        zoneTopLeft: "Top left of the %@",
        zoneTopRight: "Top right of the %@",
        zoneBottomLeft: "Bottom left of the %@",
        zoneBottomRight: "Bottom right of the %@",
        zoneWindowOn: "Window on the %@",
        zoneWindowApp: "%@ window",
        builtInDisplay: "MacBook",
        modeScreens: "Screens",
        modeZones: "Zones",
        modeWindows: "Windows",
        modeScreensCaption: "One zone per display: the keyboard follows the display you look at.",
        modeZonesCaption: "Each display is split into zones, ideal for a wide display.",
        modeWindowsCaption: "Each visible window is a zone. Needs a precise calibration.",
        modeSuited: "Suited to this layout",
        modeDiscouraged: "Not precise enough for this mode on this layout",
        panes: "Panes (experimental)",
        splitWhole: "Whole",
        splitColumns2: "2 columns",
        splitColumns3: "3 columns",
        splitRows2: "2 rows",
        splitGrid2x2: "2×2 grid",
        gradeExcellent: "Excellent",
        gradeGood: "Good",
        gradeFair: "Fair",
        gradePoor: "Poor",
        calibrationScore: "Calibration %@",
        calibrationScoreAge: "Calibration %1$@ · %2$@",
        headOnly: "Head only",
        headAndEyes: "Head and eyes",
        durationFifteenMinutes: "For 15 minutes",
        durationOneHour: "For 1 hour",
        durationUntilTomorrow: "Until tomorrow",
        durationUntilResumed: "Until resumed",
        energySaver: "Saver",
        energyBalanced: "Balanced",
        energyReactive: "Responsive",
        batterySame: "Same as on power",
        batterySaver: "Saver",
        batteryPause: "Pause",
        callKeepRunning: "Keep going",
        callPause: "Pause",
        pointerAuto: "Automatic",
        pointerStay: "Don’t move",
        pointerFollowScreen: "Follow the display",
        pointerWindowCenter: "Window center",
        feedbackNone: "None",
        feedbackHalo: "Halo",
        feedbackZone: "Zone flash",
        islandNever: "Never",
        islandPaused: "During a pause or calibration",
        islandAlways: "Always (active zone)",
        sensitivityCautious: "Cautious",
        sensitivityLively: "Lively",
        never: "Never",
        noticeKindPause: "Pause and resume",
        noticeKindNewLayout: "New display layout",
        noticeKindCamera: "Camera unavailable",
        noticeKindRecenter: "Recentered",
        noticeKindCalibrated: "Calibration done",
        noticeKindDrift: "Recalibration suggested",
        noticePaused: "Glance paused",
        noticeResumed: "Glance resumed",
        noticeNewLayout: "New display layout",
        noticeCameraUnavailable: "Camera unavailable",
        noticeRecentered: "Recentered",
        noticeCalibrated: "Calibrated · %@",
        noticeDrift: "Glance often gets it wrong",
        noticePausedUntil: "Resumes at %@",
        noticePausedTomorrow: "Until tomorrow",
        noticePausedIndefinitely: "Until you resume",
        noticeNewLayoutDetail: "Calibrate for these displays",
        noticeCameraDetail: "Glance is paused",
        noticeDriftDetail: "Calibrate again to refine it",
        pausedFor: "Paused · %@",
        pause: "Pause",
        resume: "Resume",
        resumeAnyway: "Resume Anyway",
        recenter: "Recenter",
        calibrate: "Calibrate",
        calibrateEllipsis: "Calibrate…",
        recalibrate: "Calibrate Again",
        quickRecenter: "Quick Realign",
        test: "Test",
        enable: "Turn On",
        openSettings: "Open Settings",
        allowCamera: "Allow the Camera",
        allowAccessibility: "Allow Accessibility",
        retry: "Try Again",
        chooseCamera: "Choose Another Camera",
        switchToZones: "Switch to Zones Mode",
        lastSwitch: "Last switch %@",
        recentSwitches: "Recent switches",
        barPauseFifteenMinutes: "Pause Glance for 15 Minutes",
        barPauseOneHour: "Pause Glance for 1 Hour",
        barPauseUntilTomorrow: "Pause Glance Until Tomorrow",
        barPauseUntilResumed: "Pause Glance",
        barResume: "Resume Glance",
        barRecenter: "Recenter Glance",
        barCalibrate: "Calibrate Glance",
        barSwitchMode: "Switch Glance to %@ Mode",
        barSettings: "Glance Focus Settings",
        barKeywords: "glance, gaze, eyes, head, head tracking, camera, focus, window, display, screen, zone, pause, resume, recenter, calibrate",
        shortcutPauseResume: "Pause or resume",
        shortcutRecenter: "Recenter",
        shortcutMode: "Switch mode",
        elidesBeforeVowel: false
    )

    // A copy of the English until its translation (plan §19, package C1); only
    // the feature's name is already this language's (`ForkExtrasStrings`).
    static let it = ForkGlanceStrings(
        featureTitle: "Focus con lo sguardo",
        sectionTitle: "Glance",
        searchKeywords: "glance, gaze, eyes, head, head tracking, camera, face, focus, window, display, screen, zone, keyboard",
        featureOff: "Glance Focus is off",
        statusOff: "Off",
        statusActive: "Active",
        statusActiveZone: "Active · %@",
        statusStarting: "Starting the camera…",
        statusCalibrating: "Calibrating…",
        statusCalibratingCount: "Calibrating · %@",
        statusWaiting: "Waiting: %@",
        statusNoFace: "No face detected",
        statusAway: "Looking away from the displays",
        statusPaused: "Paused",
        statusPausedUntil: "Paused — resumes at %@",
        statusPausedTomorrow: "Paused until tomorrow",
        statusPausedUntilDay: "Paused — resumes on %@",
        statusPausedReason: "Paused: %@",
        guardTyping: "you are typing",
        guardPointer: "mouse",
        guardButtonsOrModifiers: "key or button held",
        guardSecureInput: "password entry",
        guardDictation: "dictation in progress",
        guardMenuOrOverview: "menu or Mission Control",
        guardIslandOpen: "island open",
        guardOwnPanel: "app window open",
        guardExcludedSource: "app never to leave",
        guardCalibrating: "calibration in progress",
        guardCooldown: "just switched",
        guardLowConfidence: "gaze unclear",
        pauseUser: "at your request",
        pauseLocked: "Mac locked",
        pauseAsleep: "Mac asleep",
        pauseScreensAsleep: "displays asleep",
        pauseSessionInactive: "session in the background",
        pauseIdle: "no activity",
        pauseBattery: "on battery",
        pauseLowPower: "Low Power Mode",
        pauseThermal: "Mac too hot",
        pauseCameraBusy: "camera preview open",
        pauseCall: "video call in progress",
        pauseSingleScreen: "only one display",
        pauseLidClosed: "lid closed",
        shortUser: "Paused",
        shortLocked: "Locked",
        shortAsleep: "Asleep",
        shortScreensAsleep: "Displays asleep",
        shortSessionInactive: "Session in background",
        shortIdle: "Idle",
        shortBattery: "Battery",
        shortLowPower: "Low Power Mode",
        shortThermal: "Mac too hot",
        shortCameraBusy: "Camera preview",
        shortCall: "Video call",
        shortSingleScreen: "One display",
        shortLidClosed: "Lid closed",
        singleScreenHint: "Only one display: switch to Zones mode",
        unavailableCameraPermission: "Camera access needed",
        unavailableAccessibility: "Accessibility access needed",
        unavailableNoCamera: "No camera",
        unavailableCameraDisconnected: "Camera disconnected",
        unavailableCameraFailed: "The camera is not responding",
        shortCameraPermission: "Camera access",
        shortAccessibility: "Accessibility",
        shortNoCamera: "No camera found",
        shortCameraDisconnected: "Camera unplugged",
        shortCameraFailed: "Camera unavailable",
        needFirstTime: "Calibrate to get started",
        needNewLayout: "Calibrate for this display layout",
        needNewCamera: "Calibrate for this camera",
        needRemoved: "Profile deleted: calibrate again",
        shortNeedFirstTime: "Calibrate",
        shortNeedNewLayout: "New layout",
        shortNeedNewCamera: "New camera",
        shortNeedRemoved: "Profile deleted",
        zoneWhole: "Whole %@",
        zoneLeft: "Left zone of the %@",
        zoneCenter: "Center zone of the %@",
        zoneRight: "Right zone of the %@",
        zoneTop: "Top zone of the %@",
        zoneBottom: "Bottom zone of the %@",
        zoneTopLeft: "Top left of the %@",
        zoneTopRight: "Top right of the %@",
        zoneBottomLeft: "Bottom left of the %@",
        zoneBottomRight: "Bottom right of the %@",
        zoneWindowOn: "Window on the %@",
        zoneWindowApp: "%@ window",
        builtInDisplay: "MacBook",
        modeScreens: "Screens",
        modeZones: "Zones",
        modeWindows: "Windows",
        modeScreensCaption: "One zone per display: the keyboard follows the display you look at.",
        modeZonesCaption: "Each display is split into zones, ideal for a wide display.",
        modeWindowsCaption: "Each visible window is a zone. Needs a precise calibration.",
        modeSuited: "Suited to this layout",
        modeDiscouraged: "Not precise enough for this mode on this layout",
        panes: "Panes (experimental)",
        splitWhole: "Whole",
        splitColumns2: "2 columns",
        splitColumns3: "3 columns",
        splitRows2: "2 rows",
        splitGrid2x2: "2×2 grid",
        gradeExcellent: "Excellent",
        gradeGood: "Good",
        gradeFair: "Fair",
        gradePoor: "Poor",
        calibrationScore: "Calibration %@",
        calibrationScoreAge: "Calibration %1$@ · %2$@",
        headOnly: "Head only",
        headAndEyes: "Head and eyes",
        durationFifteenMinutes: "For 15 minutes",
        durationOneHour: "For 1 hour",
        durationUntilTomorrow: "Until tomorrow",
        durationUntilResumed: "Until resumed",
        energySaver: "Saver",
        energyBalanced: "Balanced",
        energyReactive: "Responsive",
        batterySame: "Same as on power",
        batterySaver: "Saver",
        batteryPause: "Pause",
        callKeepRunning: "Keep going",
        callPause: "Pause",
        pointerAuto: "Automatic",
        pointerStay: "Don’t move",
        pointerFollowScreen: "Follow the display",
        pointerWindowCenter: "Window center",
        feedbackNone: "None",
        feedbackHalo: "Halo",
        feedbackZone: "Zone flash",
        islandNever: "Never",
        islandPaused: "During a pause or calibration",
        islandAlways: "Always (active zone)",
        sensitivityCautious: "Cautious",
        sensitivityLively: "Lively",
        never: "Never",
        noticeKindPause: "Pause and resume",
        noticeKindNewLayout: "New display layout",
        noticeKindCamera: "Camera unavailable",
        noticeKindRecenter: "Recentered",
        noticeKindCalibrated: "Calibration done",
        noticeKindDrift: "Recalibration suggested",
        noticePaused: "Glance paused",
        noticeResumed: "Glance resumed",
        noticeNewLayout: "New display layout",
        noticeCameraUnavailable: "Camera unavailable",
        noticeRecentered: "Recentered",
        noticeCalibrated: "Calibrated · %@",
        noticeDrift: "Glance often gets it wrong",
        noticePausedUntil: "Resumes at %@",
        noticePausedTomorrow: "Until tomorrow",
        noticePausedIndefinitely: "Until you resume",
        noticeNewLayoutDetail: "Calibrate for these displays",
        noticeCameraDetail: "Glance is paused",
        noticeDriftDetail: "Calibrate again to refine it",
        pausedFor: "Paused · %@",
        pause: "Pause",
        resume: "Resume",
        resumeAnyway: "Resume Anyway",
        recenter: "Recenter",
        calibrate: "Calibrate",
        calibrateEllipsis: "Calibrate…",
        recalibrate: "Calibrate Again",
        quickRecenter: "Quick Realign",
        test: "Test",
        enable: "Turn On",
        openSettings: "Open Settings",
        allowCamera: "Allow the Camera",
        allowAccessibility: "Allow Accessibility",
        retry: "Try Again",
        chooseCamera: "Choose Another Camera",
        switchToZones: "Switch to Zones Mode",
        lastSwitch: "Last switch %@",
        recentSwitches: "Recent switches",
        barPauseFifteenMinutes: "Pause Glance for 15 Minutes",
        barPauseOneHour: "Pause Glance for 1 Hour",
        barPauseUntilTomorrow: "Pause Glance Until Tomorrow",
        barPauseUntilResumed: "Pause Glance",
        barResume: "Resume Glance",
        barRecenter: "Recenter Glance",
        barCalibrate: "Calibrate Glance",
        barSwitchMode: "Switch Glance to %@ Mode",
        barSettings: "Glance Focus Settings",
        barKeywords: "glance, gaze, eyes, head, head tracking, camera, focus, window, display, screen, zone, pause, resume, recenter, calibrate",
        shortcutPauseResume: "Pause or resume",
        shortcutRecenter: "Recenter",
        shortcutMode: "Switch mode",
        elidesBeforeVowel: false
    )

    // A copy of the English until its translation (plan §19, package C1); only
    // the feature's name is already this language's (`ForkExtrasStrings`).
    static let ja = ForkGlanceStrings(
        featureTitle: "視線フォーカス",
        sectionTitle: "Glance",
        searchKeywords: "glance, gaze, eyes, head, head tracking, camera, face, focus, window, display, screen, zone, keyboard",
        featureOff: "Glance Focus is off",
        statusOff: "Off",
        statusActive: "Active",
        statusActiveZone: "Active · %@",
        statusStarting: "Starting the camera…",
        statusCalibrating: "Calibrating…",
        statusCalibratingCount: "Calibrating · %@",
        statusWaiting: "Waiting: %@",
        statusNoFace: "No face detected",
        statusAway: "Looking away from the displays",
        statusPaused: "Paused",
        statusPausedUntil: "Paused — resumes at %@",
        statusPausedTomorrow: "Paused until tomorrow",
        statusPausedUntilDay: "Paused — resumes on %@",
        statusPausedReason: "Paused: %@",
        guardTyping: "you are typing",
        guardPointer: "mouse",
        guardButtonsOrModifiers: "key or button held",
        guardSecureInput: "password entry",
        guardDictation: "dictation in progress",
        guardMenuOrOverview: "menu or Mission Control",
        guardIslandOpen: "island open",
        guardOwnPanel: "app window open",
        guardExcludedSource: "app never to leave",
        guardCalibrating: "calibration in progress",
        guardCooldown: "just switched",
        guardLowConfidence: "gaze unclear",
        pauseUser: "at your request",
        pauseLocked: "Mac locked",
        pauseAsleep: "Mac asleep",
        pauseScreensAsleep: "displays asleep",
        pauseSessionInactive: "session in the background",
        pauseIdle: "no activity",
        pauseBattery: "on battery",
        pauseLowPower: "Low Power Mode",
        pauseThermal: "Mac too hot",
        pauseCameraBusy: "camera preview open",
        pauseCall: "video call in progress",
        pauseSingleScreen: "only one display",
        pauseLidClosed: "lid closed",
        shortUser: "Paused",
        shortLocked: "Locked",
        shortAsleep: "Asleep",
        shortScreensAsleep: "Displays asleep",
        shortSessionInactive: "Session in background",
        shortIdle: "Idle",
        shortBattery: "Battery",
        shortLowPower: "Low Power Mode",
        shortThermal: "Mac too hot",
        shortCameraBusy: "Camera preview",
        shortCall: "Video call",
        shortSingleScreen: "One display",
        shortLidClosed: "Lid closed",
        singleScreenHint: "Only one display: switch to Zones mode",
        unavailableCameraPermission: "Camera access needed",
        unavailableAccessibility: "Accessibility access needed",
        unavailableNoCamera: "No camera",
        unavailableCameraDisconnected: "Camera disconnected",
        unavailableCameraFailed: "The camera is not responding",
        shortCameraPermission: "Camera access",
        shortAccessibility: "Accessibility",
        shortNoCamera: "No camera found",
        shortCameraDisconnected: "Camera unplugged",
        shortCameraFailed: "Camera unavailable",
        needFirstTime: "Calibrate to get started",
        needNewLayout: "Calibrate for this display layout",
        needNewCamera: "Calibrate for this camera",
        needRemoved: "Profile deleted: calibrate again",
        shortNeedFirstTime: "Calibrate",
        shortNeedNewLayout: "New layout",
        shortNeedNewCamera: "New camera",
        shortNeedRemoved: "Profile deleted",
        zoneWhole: "Whole %@",
        zoneLeft: "Left zone of the %@",
        zoneCenter: "Center zone of the %@",
        zoneRight: "Right zone of the %@",
        zoneTop: "Top zone of the %@",
        zoneBottom: "Bottom zone of the %@",
        zoneTopLeft: "Top left of the %@",
        zoneTopRight: "Top right of the %@",
        zoneBottomLeft: "Bottom left of the %@",
        zoneBottomRight: "Bottom right of the %@",
        zoneWindowOn: "Window on the %@",
        zoneWindowApp: "%@ window",
        builtInDisplay: "MacBook",
        modeScreens: "Screens",
        modeZones: "Zones",
        modeWindows: "Windows",
        modeScreensCaption: "One zone per display: the keyboard follows the display you look at.",
        modeZonesCaption: "Each display is split into zones, ideal for a wide display.",
        modeWindowsCaption: "Each visible window is a zone. Needs a precise calibration.",
        modeSuited: "Suited to this layout",
        modeDiscouraged: "Not precise enough for this mode on this layout",
        panes: "Panes (experimental)",
        splitWhole: "Whole",
        splitColumns2: "2 columns",
        splitColumns3: "3 columns",
        splitRows2: "2 rows",
        splitGrid2x2: "2×2 grid",
        gradeExcellent: "Excellent",
        gradeGood: "Good",
        gradeFair: "Fair",
        gradePoor: "Poor",
        calibrationScore: "Calibration %@",
        calibrationScoreAge: "Calibration %1$@ · %2$@",
        headOnly: "Head only",
        headAndEyes: "Head and eyes",
        durationFifteenMinutes: "For 15 minutes",
        durationOneHour: "For 1 hour",
        durationUntilTomorrow: "Until tomorrow",
        durationUntilResumed: "Until resumed",
        energySaver: "Saver",
        energyBalanced: "Balanced",
        energyReactive: "Responsive",
        batterySame: "Same as on power",
        batterySaver: "Saver",
        batteryPause: "Pause",
        callKeepRunning: "Keep going",
        callPause: "Pause",
        pointerAuto: "Automatic",
        pointerStay: "Don’t move",
        pointerFollowScreen: "Follow the display",
        pointerWindowCenter: "Window center",
        feedbackNone: "None",
        feedbackHalo: "Halo",
        feedbackZone: "Zone flash",
        islandNever: "Never",
        islandPaused: "During a pause or calibration",
        islandAlways: "Always (active zone)",
        sensitivityCautious: "Cautious",
        sensitivityLively: "Lively",
        never: "Never",
        noticeKindPause: "Pause and resume",
        noticeKindNewLayout: "New display layout",
        noticeKindCamera: "Camera unavailable",
        noticeKindRecenter: "Recentered",
        noticeKindCalibrated: "Calibration done",
        noticeKindDrift: "Recalibration suggested",
        noticePaused: "Glance paused",
        noticeResumed: "Glance resumed",
        noticeNewLayout: "New display layout",
        noticeCameraUnavailable: "Camera unavailable",
        noticeRecentered: "Recentered",
        noticeCalibrated: "Calibrated · %@",
        noticeDrift: "Glance often gets it wrong",
        noticePausedUntil: "Resumes at %@",
        noticePausedTomorrow: "Until tomorrow",
        noticePausedIndefinitely: "Until you resume",
        noticeNewLayoutDetail: "Calibrate for these displays",
        noticeCameraDetail: "Glance is paused",
        noticeDriftDetail: "Calibrate again to refine it",
        pausedFor: "Paused · %@",
        pause: "Pause",
        resume: "Resume",
        resumeAnyway: "Resume Anyway",
        recenter: "Recenter",
        calibrate: "Calibrate",
        calibrateEllipsis: "Calibrate…",
        recalibrate: "Calibrate Again",
        quickRecenter: "Quick Realign",
        test: "Test",
        enable: "Turn On",
        openSettings: "Open Settings",
        allowCamera: "Allow the Camera",
        allowAccessibility: "Allow Accessibility",
        retry: "Try Again",
        chooseCamera: "Choose Another Camera",
        switchToZones: "Switch to Zones Mode",
        lastSwitch: "Last switch %@",
        recentSwitches: "Recent switches",
        barPauseFifteenMinutes: "Pause Glance for 15 Minutes",
        barPauseOneHour: "Pause Glance for 1 Hour",
        barPauseUntilTomorrow: "Pause Glance Until Tomorrow",
        barPauseUntilResumed: "Pause Glance",
        barResume: "Resume Glance",
        barRecenter: "Recenter Glance",
        barCalibrate: "Calibrate Glance",
        barSwitchMode: "Switch Glance to %@ Mode",
        barSettings: "Glance Focus Settings",
        barKeywords: "glance, gaze, eyes, head, head tracking, camera, focus, window, display, screen, zone, pause, resume, recenter, calibrate",
        shortcutPauseResume: "Pause or resume",
        shortcutRecenter: "Recenter",
        shortcutMode: "Switch mode",
        elidesBeforeVowel: false
    )

    // A copy of the English until its translation (plan §19, package C1); only
    // the feature's name is already this language's (`ForkExtrasStrings`).
    static let ko = ForkGlanceStrings(
        featureTitle: "시선 포커스",
        sectionTitle: "Glance",
        searchKeywords: "glance, gaze, eyes, head, head tracking, camera, face, focus, window, display, screen, zone, keyboard",
        featureOff: "Glance Focus is off",
        statusOff: "Off",
        statusActive: "Active",
        statusActiveZone: "Active · %@",
        statusStarting: "Starting the camera…",
        statusCalibrating: "Calibrating…",
        statusCalibratingCount: "Calibrating · %@",
        statusWaiting: "Waiting: %@",
        statusNoFace: "No face detected",
        statusAway: "Looking away from the displays",
        statusPaused: "Paused",
        statusPausedUntil: "Paused — resumes at %@",
        statusPausedTomorrow: "Paused until tomorrow",
        statusPausedUntilDay: "Paused — resumes on %@",
        statusPausedReason: "Paused: %@",
        guardTyping: "you are typing",
        guardPointer: "mouse",
        guardButtonsOrModifiers: "key or button held",
        guardSecureInput: "password entry",
        guardDictation: "dictation in progress",
        guardMenuOrOverview: "menu or Mission Control",
        guardIslandOpen: "island open",
        guardOwnPanel: "app window open",
        guardExcludedSource: "app never to leave",
        guardCalibrating: "calibration in progress",
        guardCooldown: "just switched",
        guardLowConfidence: "gaze unclear",
        pauseUser: "at your request",
        pauseLocked: "Mac locked",
        pauseAsleep: "Mac asleep",
        pauseScreensAsleep: "displays asleep",
        pauseSessionInactive: "session in the background",
        pauseIdle: "no activity",
        pauseBattery: "on battery",
        pauseLowPower: "Low Power Mode",
        pauseThermal: "Mac too hot",
        pauseCameraBusy: "camera preview open",
        pauseCall: "video call in progress",
        pauseSingleScreen: "only one display",
        pauseLidClosed: "lid closed",
        shortUser: "Paused",
        shortLocked: "Locked",
        shortAsleep: "Asleep",
        shortScreensAsleep: "Displays asleep",
        shortSessionInactive: "Session in background",
        shortIdle: "Idle",
        shortBattery: "Battery",
        shortLowPower: "Low Power Mode",
        shortThermal: "Mac too hot",
        shortCameraBusy: "Camera preview",
        shortCall: "Video call",
        shortSingleScreen: "One display",
        shortLidClosed: "Lid closed",
        singleScreenHint: "Only one display: switch to Zones mode",
        unavailableCameraPermission: "Camera access needed",
        unavailableAccessibility: "Accessibility access needed",
        unavailableNoCamera: "No camera",
        unavailableCameraDisconnected: "Camera disconnected",
        unavailableCameraFailed: "The camera is not responding",
        shortCameraPermission: "Camera access",
        shortAccessibility: "Accessibility",
        shortNoCamera: "No camera found",
        shortCameraDisconnected: "Camera unplugged",
        shortCameraFailed: "Camera unavailable",
        needFirstTime: "Calibrate to get started",
        needNewLayout: "Calibrate for this display layout",
        needNewCamera: "Calibrate for this camera",
        needRemoved: "Profile deleted: calibrate again",
        shortNeedFirstTime: "Calibrate",
        shortNeedNewLayout: "New layout",
        shortNeedNewCamera: "New camera",
        shortNeedRemoved: "Profile deleted",
        zoneWhole: "Whole %@",
        zoneLeft: "Left zone of the %@",
        zoneCenter: "Center zone of the %@",
        zoneRight: "Right zone of the %@",
        zoneTop: "Top zone of the %@",
        zoneBottom: "Bottom zone of the %@",
        zoneTopLeft: "Top left of the %@",
        zoneTopRight: "Top right of the %@",
        zoneBottomLeft: "Bottom left of the %@",
        zoneBottomRight: "Bottom right of the %@",
        zoneWindowOn: "Window on the %@",
        zoneWindowApp: "%@ window",
        builtInDisplay: "MacBook",
        modeScreens: "Screens",
        modeZones: "Zones",
        modeWindows: "Windows",
        modeScreensCaption: "One zone per display: the keyboard follows the display you look at.",
        modeZonesCaption: "Each display is split into zones, ideal for a wide display.",
        modeWindowsCaption: "Each visible window is a zone. Needs a precise calibration.",
        modeSuited: "Suited to this layout",
        modeDiscouraged: "Not precise enough for this mode on this layout",
        panes: "Panes (experimental)",
        splitWhole: "Whole",
        splitColumns2: "2 columns",
        splitColumns3: "3 columns",
        splitRows2: "2 rows",
        splitGrid2x2: "2×2 grid",
        gradeExcellent: "Excellent",
        gradeGood: "Good",
        gradeFair: "Fair",
        gradePoor: "Poor",
        calibrationScore: "Calibration %@",
        calibrationScoreAge: "Calibration %1$@ · %2$@",
        headOnly: "Head only",
        headAndEyes: "Head and eyes",
        durationFifteenMinutes: "For 15 minutes",
        durationOneHour: "For 1 hour",
        durationUntilTomorrow: "Until tomorrow",
        durationUntilResumed: "Until resumed",
        energySaver: "Saver",
        energyBalanced: "Balanced",
        energyReactive: "Responsive",
        batterySame: "Same as on power",
        batterySaver: "Saver",
        batteryPause: "Pause",
        callKeepRunning: "Keep going",
        callPause: "Pause",
        pointerAuto: "Automatic",
        pointerStay: "Don’t move",
        pointerFollowScreen: "Follow the display",
        pointerWindowCenter: "Window center",
        feedbackNone: "None",
        feedbackHalo: "Halo",
        feedbackZone: "Zone flash",
        islandNever: "Never",
        islandPaused: "During a pause or calibration",
        islandAlways: "Always (active zone)",
        sensitivityCautious: "Cautious",
        sensitivityLively: "Lively",
        never: "Never",
        noticeKindPause: "Pause and resume",
        noticeKindNewLayout: "New display layout",
        noticeKindCamera: "Camera unavailable",
        noticeKindRecenter: "Recentered",
        noticeKindCalibrated: "Calibration done",
        noticeKindDrift: "Recalibration suggested",
        noticePaused: "Glance paused",
        noticeResumed: "Glance resumed",
        noticeNewLayout: "New display layout",
        noticeCameraUnavailable: "Camera unavailable",
        noticeRecentered: "Recentered",
        noticeCalibrated: "Calibrated · %@",
        noticeDrift: "Glance often gets it wrong",
        noticePausedUntil: "Resumes at %@",
        noticePausedTomorrow: "Until tomorrow",
        noticePausedIndefinitely: "Until you resume",
        noticeNewLayoutDetail: "Calibrate for these displays",
        noticeCameraDetail: "Glance is paused",
        noticeDriftDetail: "Calibrate again to refine it",
        pausedFor: "Paused · %@",
        pause: "Pause",
        resume: "Resume",
        resumeAnyway: "Resume Anyway",
        recenter: "Recenter",
        calibrate: "Calibrate",
        calibrateEllipsis: "Calibrate…",
        recalibrate: "Calibrate Again",
        quickRecenter: "Quick Realign",
        test: "Test",
        enable: "Turn On",
        openSettings: "Open Settings",
        allowCamera: "Allow the Camera",
        allowAccessibility: "Allow Accessibility",
        retry: "Try Again",
        chooseCamera: "Choose Another Camera",
        switchToZones: "Switch to Zones Mode",
        lastSwitch: "Last switch %@",
        recentSwitches: "Recent switches",
        barPauseFifteenMinutes: "Pause Glance for 15 Minutes",
        barPauseOneHour: "Pause Glance for 1 Hour",
        barPauseUntilTomorrow: "Pause Glance Until Tomorrow",
        barPauseUntilResumed: "Pause Glance",
        barResume: "Resume Glance",
        barRecenter: "Recenter Glance",
        barCalibrate: "Calibrate Glance",
        barSwitchMode: "Switch Glance to %@ Mode",
        barSettings: "Glance Focus Settings",
        barKeywords: "glance, gaze, eyes, head, head tracking, camera, focus, window, display, screen, zone, pause, resume, recenter, calibrate",
        shortcutPauseResume: "Pause or resume",
        shortcutRecenter: "Recenter",
        shortcutMode: "Switch mode",
        elidesBeforeVowel: false
    )

    // A copy of the English until its translation (plan §19, package C1); only
    // the feature's name is already this language's (`ForkExtrasStrings`).
    static let uk = ForkGlanceStrings(
        featureTitle: "Фокус поглядом",
        sectionTitle: "Glance",
        searchKeywords: "glance, gaze, eyes, head, head tracking, camera, face, focus, window, display, screen, zone, keyboard",
        featureOff: "Glance Focus is off",
        statusOff: "Off",
        statusActive: "Active",
        statusActiveZone: "Active · %@",
        statusStarting: "Starting the camera…",
        statusCalibrating: "Calibrating…",
        statusCalibratingCount: "Calibrating · %@",
        statusWaiting: "Waiting: %@",
        statusNoFace: "No face detected",
        statusAway: "Looking away from the displays",
        statusPaused: "Paused",
        statusPausedUntil: "Paused — resumes at %@",
        statusPausedTomorrow: "Paused until tomorrow",
        statusPausedUntilDay: "Paused — resumes on %@",
        statusPausedReason: "Paused: %@",
        guardTyping: "you are typing",
        guardPointer: "mouse",
        guardButtonsOrModifiers: "key or button held",
        guardSecureInput: "password entry",
        guardDictation: "dictation in progress",
        guardMenuOrOverview: "menu or Mission Control",
        guardIslandOpen: "island open",
        guardOwnPanel: "app window open",
        guardExcludedSource: "app never to leave",
        guardCalibrating: "calibration in progress",
        guardCooldown: "just switched",
        guardLowConfidence: "gaze unclear",
        pauseUser: "at your request",
        pauseLocked: "Mac locked",
        pauseAsleep: "Mac asleep",
        pauseScreensAsleep: "displays asleep",
        pauseSessionInactive: "session in the background",
        pauseIdle: "no activity",
        pauseBattery: "on battery",
        pauseLowPower: "Low Power Mode",
        pauseThermal: "Mac too hot",
        pauseCameraBusy: "camera preview open",
        pauseCall: "video call in progress",
        pauseSingleScreen: "only one display",
        pauseLidClosed: "lid closed",
        shortUser: "Paused",
        shortLocked: "Locked",
        shortAsleep: "Asleep",
        shortScreensAsleep: "Displays asleep",
        shortSessionInactive: "Session in background",
        shortIdle: "Idle",
        shortBattery: "Battery",
        shortLowPower: "Low Power Mode",
        shortThermal: "Mac too hot",
        shortCameraBusy: "Camera preview",
        shortCall: "Video call",
        shortSingleScreen: "One display",
        shortLidClosed: "Lid closed",
        singleScreenHint: "Only one display: switch to Zones mode",
        unavailableCameraPermission: "Camera access needed",
        unavailableAccessibility: "Accessibility access needed",
        unavailableNoCamera: "No camera",
        unavailableCameraDisconnected: "Camera disconnected",
        unavailableCameraFailed: "The camera is not responding",
        shortCameraPermission: "Camera access",
        shortAccessibility: "Accessibility",
        shortNoCamera: "No camera found",
        shortCameraDisconnected: "Camera unplugged",
        shortCameraFailed: "Camera unavailable",
        needFirstTime: "Calibrate to get started",
        needNewLayout: "Calibrate for this display layout",
        needNewCamera: "Calibrate for this camera",
        needRemoved: "Profile deleted: calibrate again",
        shortNeedFirstTime: "Calibrate",
        shortNeedNewLayout: "New layout",
        shortNeedNewCamera: "New camera",
        shortNeedRemoved: "Profile deleted",
        zoneWhole: "Whole %@",
        zoneLeft: "Left zone of the %@",
        zoneCenter: "Center zone of the %@",
        zoneRight: "Right zone of the %@",
        zoneTop: "Top zone of the %@",
        zoneBottom: "Bottom zone of the %@",
        zoneTopLeft: "Top left of the %@",
        zoneTopRight: "Top right of the %@",
        zoneBottomLeft: "Bottom left of the %@",
        zoneBottomRight: "Bottom right of the %@",
        zoneWindowOn: "Window on the %@",
        zoneWindowApp: "%@ window",
        builtInDisplay: "MacBook",
        modeScreens: "Screens",
        modeZones: "Zones",
        modeWindows: "Windows",
        modeScreensCaption: "One zone per display: the keyboard follows the display you look at.",
        modeZonesCaption: "Each display is split into zones, ideal for a wide display.",
        modeWindowsCaption: "Each visible window is a zone. Needs a precise calibration.",
        modeSuited: "Suited to this layout",
        modeDiscouraged: "Not precise enough for this mode on this layout",
        panes: "Panes (experimental)",
        splitWhole: "Whole",
        splitColumns2: "2 columns",
        splitColumns3: "3 columns",
        splitRows2: "2 rows",
        splitGrid2x2: "2×2 grid",
        gradeExcellent: "Excellent",
        gradeGood: "Good",
        gradeFair: "Fair",
        gradePoor: "Poor",
        calibrationScore: "Calibration %@",
        calibrationScoreAge: "Calibration %1$@ · %2$@",
        headOnly: "Head only",
        headAndEyes: "Head and eyes",
        durationFifteenMinutes: "For 15 minutes",
        durationOneHour: "For 1 hour",
        durationUntilTomorrow: "Until tomorrow",
        durationUntilResumed: "Until resumed",
        energySaver: "Saver",
        energyBalanced: "Balanced",
        energyReactive: "Responsive",
        batterySame: "Same as on power",
        batterySaver: "Saver",
        batteryPause: "Pause",
        callKeepRunning: "Keep going",
        callPause: "Pause",
        pointerAuto: "Automatic",
        pointerStay: "Don’t move",
        pointerFollowScreen: "Follow the display",
        pointerWindowCenter: "Window center",
        feedbackNone: "None",
        feedbackHalo: "Halo",
        feedbackZone: "Zone flash",
        islandNever: "Never",
        islandPaused: "During a pause or calibration",
        islandAlways: "Always (active zone)",
        sensitivityCautious: "Cautious",
        sensitivityLively: "Lively",
        never: "Never",
        noticeKindPause: "Pause and resume",
        noticeKindNewLayout: "New display layout",
        noticeKindCamera: "Camera unavailable",
        noticeKindRecenter: "Recentered",
        noticeKindCalibrated: "Calibration done",
        noticeKindDrift: "Recalibration suggested",
        noticePaused: "Glance paused",
        noticeResumed: "Glance resumed",
        noticeNewLayout: "New display layout",
        noticeCameraUnavailable: "Camera unavailable",
        noticeRecentered: "Recentered",
        noticeCalibrated: "Calibrated · %@",
        noticeDrift: "Glance often gets it wrong",
        noticePausedUntil: "Resumes at %@",
        noticePausedTomorrow: "Until tomorrow",
        noticePausedIndefinitely: "Until you resume",
        noticeNewLayoutDetail: "Calibrate for these displays",
        noticeCameraDetail: "Glance is paused",
        noticeDriftDetail: "Calibrate again to refine it",
        pausedFor: "Paused · %@",
        pause: "Pause",
        resume: "Resume",
        resumeAnyway: "Resume Anyway",
        recenter: "Recenter",
        calibrate: "Calibrate",
        calibrateEllipsis: "Calibrate…",
        recalibrate: "Calibrate Again",
        quickRecenter: "Quick Realign",
        test: "Test",
        enable: "Turn On",
        openSettings: "Open Settings",
        allowCamera: "Allow the Camera",
        allowAccessibility: "Allow Accessibility",
        retry: "Try Again",
        chooseCamera: "Choose Another Camera",
        switchToZones: "Switch to Zones Mode",
        lastSwitch: "Last switch %@",
        recentSwitches: "Recent switches",
        barPauseFifteenMinutes: "Pause Glance for 15 Minutes",
        barPauseOneHour: "Pause Glance for 1 Hour",
        barPauseUntilTomorrow: "Pause Glance Until Tomorrow",
        barPauseUntilResumed: "Pause Glance",
        barResume: "Resume Glance",
        barRecenter: "Recenter Glance",
        barCalibrate: "Calibrate Glance",
        barSwitchMode: "Switch Glance to %@ Mode",
        barSettings: "Glance Focus Settings",
        barKeywords: "glance, gaze, eyes, head, head tracking, camera, focus, window, display, screen, zone, pause, resume, recenter, calibrate",
        shortcutPauseResume: "Pause or resume",
        shortcutRecenter: "Recenter",
        shortcutMode: "Switch mode",
        elidesBeforeVowel: false
    )

    // A copy of the English until its translation (plan §19, package C1); only
    // the feature's name is already this language's (`ForkExtrasStrings`).
    static let zhHans = ForkGlanceStrings(
        featureTitle: "目光焦点",
        sectionTitle: "Glance",
        searchKeywords: "glance, gaze, eyes, head, head tracking, camera, face, focus, window, display, screen, zone, keyboard",
        featureOff: "Glance Focus is off",
        statusOff: "Off",
        statusActive: "Active",
        statusActiveZone: "Active · %@",
        statusStarting: "Starting the camera…",
        statusCalibrating: "Calibrating…",
        statusCalibratingCount: "Calibrating · %@",
        statusWaiting: "Waiting: %@",
        statusNoFace: "No face detected",
        statusAway: "Looking away from the displays",
        statusPaused: "Paused",
        statusPausedUntil: "Paused — resumes at %@",
        statusPausedTomorrow: "Paused until tomorrow",
        statusPausedUntilDay: "Paused — resumes on %@",
        statusPausedReason: "Paused: %@",
        guardTyping: "you are typing",
        guardPointer: "mouse",
        guardButtonsOrModifiers: "key or button held",
        guardSecureInput: "password entry",
        guardDictation: "dictation in progress",
        guardMenuOrOverview: "menu or Mission Control",
        guardIslandOpen: "island open",
        guardOwnPanel: "app window open",
        guardExcludedSource: "app never to leave",
        guardCalibrating: "calibration in progress",
        guardCooldown: "just switched",
        guardLowConfidence: "gaze unclear",
        pauseUser: "at your request",
        pauseLocked: "Mac locked",
        pauseAsleep: "Mac asleep",
        pauseScreensAsleep: "displays asleep",
        pauseSessionInactive: "session in the background",
        pauseIdle: "no activity",
        pauseBattery: "on battery",
        pauseLowPower: "Low Power Mode",
        pauseThermal: "Mac too hot",
        pauseCameraBusy: "camera preview open",
        pauseCall: "video call in progress",
        pauseSingleScreen: "only one display",
        pauseLidClosed: "lid closed",
        shortUser: "Paused",
        shortLocked: "Locked",
        shortAsleep: "Asleep",
        shortScreensAsleep: "Displays asleep",
        shortSessionInactive: "Session in background",
        shortIdle: "Idle",
        shortBattery: "Battery",
        shortLowPower: "Low Power Mode",
        shortThermal: "Mac too hot",
        shortCameraBusy: "Camera preview",
        shortCall: "Video call",
        shortSingleScreen: "One display",
        shortLidClosed: "Lid closed",
        singleScreenHint: "Only one display: switch to Zones mode",
        unavailableCameraPermission: "Camera access needed",
        unavailableAccessibility: "Accessibility access needed",
        unavailableNoCamera: "No camera",
        unavailableCameraDisconnected: "Camera disconnected",
        unavailableCameraFailed: "The camera is not responding",
        shortCameraPermission: "Camera access",
        shortAccessibility: "Accessibility",
        shortNoCamera: "No camera found",
        shortCameraDisconnected: "Camera unplugged",
        shortCameraFailed: "Camera unavailable",
        needFirstTime: "Calibrate to get started",
        needNewLayout: "Calibrate for this display layout",
        needNewCamera: "Calibrate for this camera",
        needRemoved: "Profile deleted: calibrate again",
        shortNeedFirstTime: "Calibrate",
        shortNeedNewLayout: "New layout",
        shortNeedNewCamera: "New camera",
        shortNeedRemoved: "Profile deleted",
        zoneWhole: "Whole %@",
        zoneLeft: "Left zone of the %@",
        zoneCenter: "Center zone of the %@",
        zoneRight: "Right zone of the %@",
        zoneTop: "Top zone of the %@",
        zoneBottom: "Bottom zone of the %@",
        zoneTopLeft: "Top left of the %@",
        zoneTopRight: "Top right of the %@",
        zoneBottomLeft: "Bottom left of the %@",
        zoneBottomRight: "Bottom right of the %@",
        zoneWindowOn: "Window on the %@",
        zoneWindowApp: "%@ window",
        builtInDisplay: "MacBook",
        modeScreens: "Screens",
        modeZones: "Zones",
        modeWindows: "Windows",
        modeScreensCaption: "One zone per display: the keyboard follows the display you look at.",
        modeZonesCaption: "Each display is split into zones, ideal for a wide display.",
        modeWindowsCaption: "Each visible window is a zone. Needs a precise calibration.",
        modeSuited: "Suited to this layout",
        modeDiscouraged: "Not precise enough for this mode on this layout",
        panes: "Panes (experimental)",
        splitWhole: "Whole",
        splitColumns2: "2 columns",
        splitColumns3: "3 columns",
        splitRows2: "2 rows",
        splitGrid2x2: "2×2 grid",
        gradeExcellent: "Excellent",
        gradeGood: "Good",
        gradeFair: "Fair",
        gradePoor: "Poor",
        calibrationScore: "Calibration %@",
        calibrationScoreAge: "Calibration %1$@ · %2$@",
        headOnly: "Head only",
        headAndEyes: "Head and eyes",
        durationFifteenMinutes: "For 15 minutes",
        durationOneHour: "For 1 hour",
        durationUntilTomorrow: "Until tomorrow",
        durationUntilResumed: "Until resumed",
        energySaver: "Saver",
        energyBalanced: "Balanced",
        energyReactive: "Responsive",
        batterySame: "Same as on power",
        batterySaver: "Saver",
        batteryPause: "Pause",
        callKeepRunning: "Keep going",
        callPause: "Pause",
        pointerAuto: "Automatic",
        pointerStay: "Don’t move",
        pointerFollowScreen: "Follow the display",
        pointerWindowCenter: "Window center",
        feedbackNone: "None",
        feedbackHalo: "Halo",
        feedbackZone: "Zone flash",
        islandNever: "Never",
        islandPaused: "During a pause or calibration",
        islandAlways: "Always (active zone)",
        sensitivityCautious: "Cautious",
        sensitivityLively: "Lively",
        never: "Never",
        noticeKindPause: "Pause and resume",
        noticeKindNewLayout: "New display layout",
        noticeKindCamera: "Camera unavailable",
        noticeKindRecenter: "Recentered",
        noticeKindCalibrated: "Calibration done",
        noticeKindDrift: "Recalibration suggested",
        noticePaused: "Glance paused",
        noticeResumed: "Glance resumed",
        noticeNewLayout: "New display layout",
        noticeCameraUnavailable: "Camera unavailable",
        noticeRecentered: "Recentered",
        noticeCalibrated: "Calibrated · %@",
        noticeDrift: "Glance often gets it wrong",
        noticePausedUntil: "Resumes at %@",
        noticePausedTomorrow: "Until tomorrow",
        noticePausedIndefinitely: "Until you resume",
        noticeNewLayoutDetail: "Calibrate for these displays",
        noticeCameraDetail: "Glance is paused",
        noticeDriftDetail: "Calibrate again to refine it",
        pausedFor: "Paused · %@",
        pause: "Pause",
        resume: "Resume",
        resumeAnyway: "Resume Anyway",
        recenter: "Recenter",
        calibrate: "Calibrate",
        calibrateEllipsis: "Calibrate…",
        recalibrate: "Calibrate Again",
        quickRecenter: "Quick Realign",
        test: "Test",
        enable: "Turn On",
        openSettings: "Open Settings",
        allowCamera: "Allow the Camera",
        allowAccessibility: "Allow Accessibility",
        retry: "Try Again",
        chooseCamera: "Choose Another Camera",
        switchToZones: "Switch to Zones Mode",
        lastSwitch: "Last switch %@",
        recentSwitches: "Recent switches",
        barPauseFifteenMinutes: "Pause Glance for 15 Minutes",
        barPauseOneHour: "Pause Glance for 1 Hour",
        barPauseUntilTomorrow: "Pause Glance Until Tomorrow",
        barPauseUntilResumed: "Pause Glance",
        barResume: "Resume Glance",
        barRecenter: "Recenter Glance",
        barCalibrate: "Calibrate Glance",
        barSwitchMode: "Switch Glance to %@ Mode",
        barSettings: "Glance Focus Settings",
        barKeywords: "glance, gaze, eyes, head, head tracking, camera, focus, window, display, screen, zone, pause, resume, recenter, calibrate",
        shortcutPauseResume: "Pause or resume",
        shortcutRecenter: "Recenter",
        shortcutMode: "Switch mode",
        elidesBeforeVowel: false
    )

    // A copy of the English until its translation (plan §19, package C1); only
    // the feature's name is already this language's (`ForkExtrasStrings`).
    static let zhTW = ForkGlanceStrings(
        featureTitle: "目光焦點",
        sectionTitle: "Glance",
        searchKeywords: "glance, gaze, eyes, head, head tracking, camera, face, focus, window, display, screen, zone, keyboard",
        featureOff: "Glance Focus is off",
        statusOff: "Off",
        statusActive: "Active",
        statusActiveZone: "Active · %@",
        statusStarting: "Starting the camera…",
        statusCalibrating: "Calibrating…",
        statusCalibratingCount: "Calibrating · %@",
        statusWaiting: "Waiting: %@",
        statusNoFace: "No face detected",
        statusAway: "Looking away from the displays",
        statusPaused: "Paused",
        statusPausedUntil: "Paused — resumes at %@",
        statusPausedTomorrow: "Paused until tomorrow",
        statusPausedUntilDay: "Paused — resumes on %@",
        statusPausedReason: "Paused: %@",
        guardTyping: "you are typing",
        guardPointer: "mouse",
        guardButtonsOrModifiers: "key or button held",
        guardSecureInput: "password entry",
        guardDictation: "dictation in progress",
        guardMenuOrOverview: "menu or Mission Control",
        guardIslandOpen: "island open",
        guardOwnPanel: "app window open",
        guardExcludedSource: "app never to leave",
        guardCalibrating: "calibration in progress",
        guardCooldown: "just switched",
        guardLowConfidence: "gaze unclear",
        pauseUser: "at your request",
        pauseLocked: "Mac locked",
        pauseAsleep: "Mac asleep",
        pauseScreensAsleep: "displays asleep",
        pauseSessionInactive: "session in the background",
        pauseIdle: "no activity",
        pauseBattery: "on battery",
        pauseLowPower: "Low Power Mode",
        pauseThermal: "Mac too hot",
        pauseCameraBusy: "camera preview open",
        pauseCall: "video call in progress",
        pauseSingleScreen: "only one display",
        pauseLidClosed: "lid closed",
        shortUser: "Paused",
        shortLocked: "Locked",
        shortAsleep: "Asleep",
        shortScreensAsleep: "Displays asleep",
        shortSessionInactive: "Session in background",
        shortIdle: "Idle",
        shortBattery: "Battery",
        shortLowPower: "Low Power Mode",
        shortThermal: "Mac too hot",
        shortCameraBusy: "Camera preview",
        shortCall: "Video call",
        shortSingleScreen: "One display",
        shortLidClosed: "Lid closed",
        singleScreenHint: "Only one display: switch to Zones mode",
        unavailableCameraPermission: "Camera access needed",
        unavailableAccessibility: "Accessibility access needed",
        unavailableNoCamera: "No camera",
        unavailableCameraDisconnected: "Camera disconnected",
        unavailableCameraFailed: "The camera is not responding",
        shortCameraPermission: "Camera access",
        shortAccessibility: "Accessibility",
        shortNoCamera: "No camera found",
        shortCameraDisconnected: "Camera unplugged",
        shortCameraFailed: "Camera unavailable",
        needFirstTime: "Calibrate to get started",
        needNewLayout: "Calibrate for this display layout",
        needNewCamera: "Calibrate for this camera",
        needRemoved: "Profile deleted: calibrate again",
        shortNeedFirstTime: "Calibrate",
        shortNeedNewLayout: "New layout",
        shortNeedNewCamera: "New camera",
        shortNeedRemoved: "Profile deleted",
        zoneWhole: "Whole %@",
        zoneLeft: "Left zone of the %@",
        zoneCenter: "Center zone of the %@",
        zoneRight: "Right zone of the %@",
        zoneTop: "Top zone of the %@",
        zoneBottom: "Bottom zone of the %@",
        zoneTopLeft: "Top left of the %@",
        zoneTopRight: "Top right of the %@",
        zoneBottomLeft: "Bottom left of the %@",
        zoneBottomRight: "Bottom right of the %@",
        zoneWindowOn: "Window on the %@",
        zoneWindowApp: "%@ window",
        builtInDisplay: "MacBook",
        modeScreens: "Screens",
        modeZones: "Zones",
        modeWindows: "Windows",
        modeScreensCaption: "One zone per display: the keyboard follows the display you look at.",
        modeZonesCaption: "Each display is split into zones, ideal for a wide display.",
        modeWindowsCaption: "Each visible window is a zone. Needs a precise calibration.",
        modeSuited: "Suited to this layout",
        modeDiscouraged: "Not precise enough for this mode on this layout",
        panes: "Panes (experimental)",
        splitWhole: "Whole",
        splitColumns2: "2 columns",
        splitColumns3: "3 columns",
        splitRows2: "2 rows",
        splitGrid2x2: "2×2 grid",
        gradeExcellent: "Excellent",
        gradeGood: "Good",
        gradeFair: "Fair",
        gradePoor: "Poor",
        calibrationScore: "Calibration %@",
        calibrationScoreAge: "Calibration %1$@ · %2$@",
        headOnly: "Head only",
        headAndEyes: "Head and eyes",
        durationFifteenMinutes: "For 15 minutes",
        durationOneHour: "For 1 hour",
        durationUntilTomorrow: "Until tomorrow",
        durationUntilResumed: "Until resumed",
        energySaver: "Saver",
        energyBalanced: "Balanced",
        energyReactive: "Responsive",
        batterySame: "Same as on power",
        batterySaver: "Saver",
        batteryPause: "Pause",
        callKeepRunning: "Keep going",
        callPause: "Pause",
        pointerAuto: "Automatic",
        pointerStay: "Don’t move",
        pointerFollowScreen: "Follow the display",
        pointerWindowCenter: "Window center",
        feedbackNone: "None",
        feedbackHalo: "Halo",
        feedbackZone: "Zone flash",
        islandNever: "Never",
        islandPaused: "During a pause or calibration",
        islandAlways: "Always (active zone)",
        sensitivityCautious: "Cautious",
        sensitivityLively: "Lively",
        never: "Never",
        noticeKindPause: "Pause and resume",
        noticeKindNewLayout: "New display layout",
        noticeKindCamera: "Camera unavailable",
        noticeKindRecenter: "Recentered",
        noticeKindCalibrated: "Calibration done",
        noticeKindDrift: "Recalibration suggested",
        noticePaused: "Glance paused",
        noticeResumed: "Glance resumed",
        noticeNewLayout: "New display layout",
        noticeCameraUnavailable: "Camera unavailable",
        noticeRecentered: "Recentered",
        noticeCalibrated: "Calibrated · %@",
        noticeDrift: "Glance often gets it wrong",
        noticePausedUntil: "Resumes at %@",
        noticePausedTomorrow: "Until tomorrow",
        noticePausedIndefinitely: "Until you resume",
        noticeNewLayoutDetail: "Calibrate for these displays",
        noticeCameraDetail: "Glance is paused",
        noticeDriftDetail: "Calibrate again to refine it",
        pausedFor: "Paused · %@",
        pause: "Pause",
        resume: "Resume",
        resumeAnyway: "Resume Anyway",
        recenter: "Recenter",
        calibrate: "Calibrate",
        calibrateEllipsis: "Calibrate…",
        recalibrate: "Calibrate Again",
        quickRecenter: "Quick Realign",
        test: "Test",
        enable: "Turn On",
        openSettings: "Open Settings",
        allowCamera: "Allow the Camera",
        allowAccessibility: "Allow Accessibility",
        retry: "Try Again",
        chooseCamera: "Choose Another Camera",
        switchToZones: "Switch to Zones Mode",
        lastSwitch: "Last switch %@",
        recentSwitches: "Recent switches",
        barPauseFifteenMinutes: "Pause Glance for 15 Minutes",
        barPauseOneHour: "Pause Glance for 1 Hour",
        barPauseUntilTomorrow: "Pause Glance Until Tomorrow",
        barPauseUntilResumed: "Pause Glance",
        barResume: "Resume Glance",
        barRecenter: "Recenter Glance",
        barCalibrate: "Calibrate Glance",
        barSwitchMode: "Switch Glance to %@ Mode",
        barSettings: "Glance Focus Settings",
        barKeywords: "glance, gaze, eyes, head, head tracking, camera, focus, window, display, screen, zone, pause, resume, recenter, calibrate",
        shortcutPauseResume: "Pause or resume",
        shortcutRecenter: "Recenter",
        shortcutMode: "Switch mode",
        elidesBeforeVowel: false
    )

    // A copy of the English until its translation (plan §19, package C1); only
    // the feature's name is already this language's (`ForkExtrasStrings`).
    static let zhHK = ForkGlanceStrings(
        featureTitle: "目光焦點",
        sectionTitle: "Glance",
        searchKeywords: "glance, gaze, eyes, head, head tracking, camera, face, focus, window, display, screen, zone, keyboard",
        featureOff: "Glance Focus is off",
        statusOff: "Off",
        statusActive: "Active",
        statusActiveZone: "Active · %@",
        statusStarting: "Starting the camera…",
        statusCalibrating: "Calibrating…",
        statusCalibratingCount: "Calibrating · %@",
        statusWaiting: "Waiting: %@",
        statusNoFace: "No face detected",
        statusAway: "Looking away from the displays",
        statusPaused: "Paused",
        statusPausedUntil: "Paused — resumes at %@",
        statusPausedTomorrow: "Paused until tomorrow",
        statusPausedUntilDay: "Paused — resumes on %@",
        statusPausedReason: "Paused: %@",
        guardTyping: "you are typing",
        guardPointer: "mouse",
        guardButtonsOrModifiers: "key or button held",
        guardSecureInput: "password entry",
        guardDictation: "dictation in progress",
        guardMenuOrOverview: "menu or Mission Control",
        guardIslandOpen: "island open",
        guardOwnPanel: "app window open",
        guardExcludedSource: "app never to leave",
        guardCalibrating: "calibration in progress",
        guardCooldown: "just switched",
        guardLowConfidence: "gaze unclear",
        pauseUser: "at your request",
        pauseLocked: "Mac locked",
        pauseAsleep: "Mac asleep",
        pauseScreensAsleep: "displays asleep",
        pauseSessionInactive: "session in the background",
        pauseIdle: "no activity",
        pauseBattery: "on battery",
        pauseLowPower: "Low Power Mode",
        pauseThermal: "Mac too hot",
        pauseCameraBusy: "camera preview open",
        pauseCall: "video call in progress",
        pauseSingleScreen: "only one display",
        pauseLidClosed: "lid closed",
        shortUser: "Paused",
        shortLocked: "Locked",
        shortAsleep: "Asleep",
        shortScreensAsleep: "Displays asleep",
        shortSessionInactive: "Session in background",
        shortIdle: "Idle",
        shortBattery: "Battery",
        shortLowPower: "Low Power Mode",
        shortThermal: "Mac too hot",
        shortCameraBusy: "Camera preview",
        shortCall: "Video call",
        shortSingleScreen: "One display",
        shortLidClosed: "Lid closed",
        singleScreenHint: "Only one display: switch to Zones mode",
        unavailableCameraPermission: "Camera access needed",
        unavailableAccessibility: "Accessibility access needed",
        unavailableNoCamera: "No camera",
        unavailableCameraDisconnected: "Camera disconnected",
        unavailableCameraFailed: "The camera is not responding",
        shortCameraPermission: "Camera access",
        shortAccessibility: "Accessibility",
        shortNoCamera: "No camera found",
        shortCameraDisconnected: "Camera unplugged",
        shortCameraFailed: "Camera unavailable",
        needFirstTime: "Calibrate to get started",
        needNewLayout: "Calibrate for this display layout",
        needNewCamera: "Calibrate for this camera",
        needRemoved: "Profile deleted: calibrate again",
        shortNeedFirstTime: "Calibrate",
        shortNeedNewLayout: "New layout",
        shortNeedNewCamera: "New camera",
        shortNeedRemoved: "Profile deleted",
        zoneWhole: "Whole %@",
        zoneLeft: "Left zone of the %@",
        zoneCenter: "Center zone of the %@",
        zoneRight: "Right zone of the %@",
        zoneTop: "Top zone of the %@",
        zoneBottom: "Bottom zone of the %@",
        zoneTopLeft: "Top left of the %@",
        zoneTopRight: "Top right of the %@",
        zoneBottomLeft: "Bottom left of the %@",
        zoneBottomRight: "Bottom right of the %@",
        zoneWindowOn: "Window on the %@",
        zoneWindowApp: "%@ window",
        builtInDisplay: "MacBook",
        modeScreens: "Screens",
        modeZones: "Zones",
        modeWindows: "Windows",
        modeScreensCaption: "One zone per display: the keyboard follows the display you look at.",
        modeZonesCaption: "Each display is split into zones, ideal for a wide display.",
        modeWindowsCaption: "Each visible window is a zone. Needs a precise calibration.",
        modeSuited: "Suited to this layout",
        modeDiscouraged: "Not precise enough for this mode on this layout",
        panes: "Panes (experimental)",
        splitWhole: "Whole",
        splitColumns2: "2 columns",
        splitColumns3: "3 columns",
        splitRows2: "2 rows",
        splitGrid2x2: "2×2 grid",
        gradeExcellent: "Excellent",
        gradeGood: "Good",
        gradeFair: "Fair",
        gradePoor: "Poor",
        calibrationScore: "Calibration %@",
        calibrationScoreAge: "Calibration %1$@ · %2$@",
        headOnly: "Head only",
        headAndEyes: "Head and eyes",
        durationFifteenMinutes: "For 15 minutes",
        durationOneHour: "For 1 hour",
        durationUntilTomorrow: "Until tomorrow",
        durationUntilResumed: "Until resumed",
        energySaver: "Saver",
        energyBalanced: "Balanced",
        energyReactive: "Responsive",
        batterySame: "Same as on power",
        batterySaver: "Saver",
        batteryPause: "Pause",
        callKeepRunning: "Keep going",
        callPause: "Pause",
        pointerAuto: "Automatic",
        pointerStay: "Don’t move",
        pointerFollowScreen: "Follow the display",
        pointerWindowCenter: "Window center",
        feedbackNone: "None",
        feedbackHalo: "Halo",
        feedbackZone: "Zone flash",
        islandNever: "Never",
        islandPaused: "During a pause or calibration",
        islandAlways: "Always (active zone)",
        sensitivityCautious: "Cautious",
        sensitivityLively: "Lively",
        never: "Never",
        noticeKindPause: "Pause and resume",
        noticeKindNewLayout: "New display layout",
        noticeKindCamera: "Camera unavailable",
        noticeKindRecenter: "Recentered",
        noticeKindCalibrated: "Calibration done",
        noticeKindDrift: "Recalibration suggested",
        noticePaused: "Glance paused",
        noticeResumed: "Glance resumed",
        noticeNewLayout: "New display layout",
        noticeCameraUnavailable: "Camera unavailable",
        noticeRecentered: "Recentered",
        noticeCalibrated: "Calibrated · %@",
        noticeDrift: "Glance often gets it wrong",
        noticePausedUntil: "Resumes at %@",
        noticePausedTomorrow: "Until tomorrow",
        noticePausedIndefinitely: "Until you resume",
        noticeNewLayoutDetail: "Calibrate for these displays",
        noticeCameraDetail: "Glance is paused",
        noticeDriftDetail: "Calibrate again to refine it",
        pausedFor: "Paused · %@",
        pause: "Pause",
        resume: "Resume",
        resumeAnyway: "Resume Anyway",
        recenter: "Recenter",
        calibrate: "Calibrate",
        calibrateEllipsis: "Calibrate…",
        recalibrate: "Calibrate Again",
        quickRecenter: "Quick Realign",
        test: "Test",
        enable: "Turn On",
        openSettings: "Open Settings",
        allowCamera: "Allow the Camera",
        allowAccessibility: "Allow Accessibility",
        retry: "Try Again",
        chooseCamera: "Choose Another Camera",
        switchToZones: "Switch to Zones Mode",
        lastSwitch: "Last switch %@",
        recentSwitches: "Recent switches",
        barPauseFifteenMinutes: "Pause Glance for 15 Minutes",
        barPauseOneHour: "Pause Glance for 1 Hour",
        barPauseUntilTomorrow: "Pause Glance Until Tomorrow",
        barPauseUntilResumed: "Pause Glance",
        barResume: "Resume Glance",
        barRecenter: "Recenter Glance",
        barCalibrate: "Calibrate Glance",
        barSwitchMode: "Switch Glance to %@ Mode",
        barSettings: "Glance Focus Settings",
        barKeywords: "glance, gaze, eyes, head, head tracking, camera, focus, window, display, screen, zone, pause, resume, recenter, calibrate",
        shortcutPauseResume: "Pause or resume",
        shortcutRecenter: "Recenter",
        shortcutMode: "Switch mode",
        elidesBeforeVowel: false
    )
}
