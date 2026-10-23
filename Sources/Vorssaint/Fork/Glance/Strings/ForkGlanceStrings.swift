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

    /// How a display is called in a zone's name: a laptop's built-in panel
    /// « MacBook » (`ForkGlanceProfiles.isLaptopPanel`: never an iMac's),
    /// another its name's first word (« LG » for « LG HDR WQHD »), or its
    /// whole name when another display starts alike.
    func displayShortName(_ display: ForkGlanceDisplay, among displays: [ForkGlanceDisplay]) -> String {
        if ForkGlanceProfiles.isLaptopPanel(display) { return builtInDisplay }
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

    static let ptBR = ForkGlanceStrings(
        featureTitle: "Foco pelo olhar",
        sectionTitle: "Olhar",
        searchKeywords: "olhar, olhos, cabeça, rastreamento da cabeça, câmera, rosto, foco, janela, tela, monitor, zona, teclado",
        featureOff: "Foco pelo olhar está desativado",
        statusOff: "Desativado",
        statusActive: "Ativo",
        statusActiveZone: "Ativo · %@",
        statusStarting: "Iniciando a câmera…",
        statusCalibrating: "Calibrando…",
        statusCalibratingCount: "Calibrando · %@",
        statusWaiting: "Aguardando: %@",
        statusNoFace: "Nenhum rosto detectado",
        statusAway: "Olhar fora das telas",
        statusPaused: "Pausado",
        statusPausedUntil: "Pausado — retoma às %@",
        statusPausedTomorrow: "Pausado até amanhã",
        statusPausedUntilDay: "Pausado — retoma em %@",
        statusPausedReason: "Pausado: %@",
        guardTyping: "você está digitando",
        guardPointer: "mouse em uso",
        guardButtonsOrModifiers: "tecla ou botão pressionado",
        guardSecureInput: "digitação de senha",
        guardDictation: "ditado em andamento",
        guardMenuOrOverview: "menu ou Mission Control",
        guardIslandOpen: "ilha aberta",
        guardOwnPanel: "janela do app aberta",
        guardExcludedSource: "app que nunca se deixa",
        guardCalibrating: "calibração em andamento",
        guardCooldown: "troca recente",
        guardLowConfidence: "olhar incerto",
        pauseUser: "a seu pedido",
        pauseLocked: "Mac bloqueado",
        pauseAsleep: "Mac em repouso",
        pauseScreensAsleep: "telas em repouso",
        pauseSessionInactive: "sessão em segundo plano",
        pauseIdle: "sem atividade",
        pauseBattery: "na bateria",
        pauseLowPower: "Modo de Pouca Energia",
        pauseThermal: "Mac quente demais",
        pauseCameraBusy: "prévia da câmera aberta",
        pauseCall: "videochamada em andamento",
        pauseSingleScreen: "só uma tela",
        pauseLidClosed: "tampa fechada",
        shortUser: "Pausado",
        shortLocked: "Bloqueado",
        shortAsleep: "Em repouso",
        shortScreensAsleep: "Telas em repouso",
        shortSessionInactive: "Sessão em segundo plano",
        shortIdle: "Inativo",
        shortBattery: "Bateria",
        shortLowPower: "Pouca Energia",
        shortThermal: "Mac quente demais",
        shortCameraBusy: "Prévia da câmera",
        shortCall: "Videochamada",
        shortSingleScreen: "Só uma tela",
        shortLidClosed: "Tampa fechada",
        singleScreenHint: "Só uma tela: mude para o modo Zonas",
        unavailableCameraPermission: "Acesso à câmera necessário",
        unavailableAccessibility: "Acesso à Acessibilidade necessário",
        unavailableNoCamera: "Nenhuma câmera",
        unavailableCameraDisconnected: "Câmera desconectada",
        unavailableCameraFailed: "A câmera não está respondendo",
        shortCameraPermission: "Acesso à câmera",
        shortAccessibility: "Acessibilidade",
        shortNoCamera: "Nenhuma câmera encontrada",
        shortCameraDisconnected: "Câmera desconectada",
        shortCameraFailed: "Câmera indisponível",
        needFirstTime: "Calibre para começar",
        needNewLayout: "Calibre para esta disposição de telas",
        needNewCamera: "Calibre para esta câmera",
        needRemoved: "Perfil apagado: calibre de novo",
        shortNeedFirstTime: "Calibrar",
        shortNeedNewLayout: "Nova disposição",
        shortNeedNewCamera: "Nova câmera",
        shortNeedRemoved: "Perfil apagado",
        zoneWhole: "%@ inteiro",
        zoneLeft: "Zona esquerda do %@",
        zoneCenter: "Zona central do %@",
        zoneRight: "Zona direita do %@",
        zoneTop: "Zona superior do %@",
        zoneBottom: "Zona inferior do %@",
        zoneTopLeft: "Superior esquerdo do %@",
        zoneTopRight: "Superior direito do %@",
        zoneBottomLeft: "Inferior esquerdo do %@",
        zoneBottomRight: "Inferior direito do %@",
        zoneWindowOn: "Janela no %@",
        zoneWindowApp: "Janela do %@",
        builtInDisplay: "MacBook",
        modeScreens: "Telas",
        modeZones: "Zonas",
        modeWindows: "Janelas",
        modeScreensCaption: "Uma zona por tela: o teclado segue a tela para a qual você olha.",
        modeZonesCaption: "Cada tela é dividida em zonas, ideal para uma tela larga.",
        modeWindowsCaption: "Cada janela visível é uma zona. Requer uma calibração precisa.",
        modeSuited: "Adequado a esta disposição",
        modeDiscouraged: "Não é preciso o bastante para este modo nesta disposição",
        panes: "Painéis (experimental)",
        splitWhole: "Inteira",
        splitColumns2: "2 colunas",
        splitColumns3: "3 colunas",
        splitRows2: "2 linhas",
        splitGrid2x2: "Grade 2×2",
        gradeExcellent: "Excelente",
        gradeGood: "Boa",
        gradeFair: "Razoável",
        gradePoor: "Insuficiente",
        calibrationScore: "Calibração %@",
        calibrationScoreAge: "Calibração %1$@ · %2$@",
        headOnly: "Só a cabeça",
        headAndEyes: "Cabeça e olhos",
        durationFifteenMinutes: "Por 15 minutos",
        durationOneHour: "Por 1 hora",
        durationUntilTomorrow: "Até amanhã",
        durationUntilResumed: "Até retomar",
        energySaver: "Econômico",
        energyBalanced: "Equilibrado",
        energyReactive: "Responsivo",
        batterySame: "Igual à tomada",
        batterySaver: "Econômico",
        batteryPause: "Pausar",
        callKeepRunning: "Continuar",
        callPause: "Pausar",
        pointerAuto: "Automático",
        pointerStay: "Não mover",
        pointerFollowScreen: "Seguir a tela",
        pointerWindowCenter: "Centro da janela",
        feedbackNone: "Nenhum",
        feedbackHalo: "Halo",
        feedbackZone: "Destaque da zona",
        islandNever: "Nunca",
        islandPaused: "Durante uma pausa ou calibração",
        islandAlways: "Sempre (zona ativa)",
        sensitivityCautious: "Cauteloso",
        sensitivityLively: "Ágil",
        never: "Nunca",
        noticeKindPause: "Pausa e retomada",
        noticeKindNewLayout: "Nova disposição de telas",
        noticeKindCamera: "Câmera indisponível",
        noticeKindRecenter: "Recentralizado",
        noticeKindCalibrated: "Calibração concluída",
        noticeKindDrift: "Recalibração sugerida",
        noticePaused: "Olhar pausado",
        noticeResumed: "Olhar retomado",
        noticeNewLayout: "Nova disposição de telas",
        noticeCameraUnavailable: "Câmera indisponível",
        noticeRecentered: "Recentralizado",
        noticeCalibrated: "Calibrado · %@",
        noticeDrift: "O olhar erra com frequência",
        noticePausedUntil: "Retoma às %@",
        noticePausedTomorrow: "Até amanhã",
        noticePausedIndefinitely: "Até você retomar",
        noticeNewLayoutDetail: "Calibre para estas telas",
        noticeCameraDetail: "O olhar está pausado",
        noticeDriftDetail: "Calibre de novo para refinar",
        pausedFor: "Pausado · %@",
        pause: "Pausar",
        resume: "Retomar",
        resumeAnyway: "Retomar mesmo assim",
        recenter: "Recentralizar",
        calibrate: "Calibrar",
        calibrateEllipsis: "Calibrar…",
        recalibrate: "Calibrar de novo",
        quickRecenter: "Realinhamento rápido",
        test: "Testar",
        enable: "Ativar",
        openSettings: "Abrir Ajustes",
        allowCamera: "Permitir a câmera",
        allowAccessibility: "Permitir Acessibilidade",
        retry: "Tentar de novo",
        chooseCamera: "Escolher outra câmera",
        switchToZones: "Mudar para o modo Zonas",
        lastSwitch: "Última troca %@",
        recentSwitches: "Trocas recentes",
        barPauseFifteenMinutes: "Pausar o Foco pelo olhar por 15 minutos",
        barPauseOneHour: "Pausar o Foco pelo olhar por 1 hora",
        barPauseUntilTomorrow: "Pausar o Foco pelo olhar até amanhã",
        barPauseUntilResumed: "Pausar o Foco pelo olhar",
        barResume: "Retomar o Foco pelo olhar",
        barRecenter: "Recentralizar o Foco pelo olhar",
        barCalibrate: "Calibrar o Foco pelo olhar",
        barSwitchMode: "Mudar o Foco pelo olhar para o modo %@",
        barSettings: "Ajustes do Foco pelo olhar",
        barKeywords: "olhar, olhos, cabeça, rastreamento da cabeça, câmera, foco, janela, tela, zona, pausar, retomar, recentralizar, calibrar",
        shortcutPauseResume: "Pausar ou retomar",
        shortcutRecenter: "Recentralizar",
        shortcutMode: "Mudar de modo",
        elidesBeforeVowel: false
    )

    static let tr = ForkGlanceStrings(
        featureTitle: "Bakışla Odak",
        sectionTitle: "Bakış",
        searchKeywords: "bakış, göz, gözler, baş, baş takibi, kamera, yüz, odak, pencere, ekran, monitör, bölge, klavye",
        featureOff: "Bakışla Odak kapalı",
        statusOff: "Kapalı",
        statusActive: "Etkin",
        statusActiveZone: "Etkin · %@",
        statusStarting: "Kamera başlatılıyor…",
        statusCalibrating: "Kalibre ediliyor…",
        statusCalibratingCount: "Kalibre ediliyor · %@",
        statusWaiting: "Bekleniyor: %@",
        statusNoFace: "Yüz algılanmadı",
        statusAway: "Bakış ekranların dışında",
        statusPaused: "Duraklatıldı",
        statusPausedUntil: "Duraklatıldı — sürdürme saati: %@",
        statusPausedTomorrow: "Yarına kadar duraklatıldı",
        statusPausedUntilDay: "Duraklatıldı — sürdürme: %@",
        statusPausedReason: "Duraklatıldı: %@",
        guardTyping: "yazıyorsunuz",
        guardPointer: "fare",
        guardButtonsOrModifiers: "tuş veya düğme basılı",
        guardSecureInput: "parola girişi",
        guardDictation: "dikte sürüyor",
        guardMenuOrOverview: "menü veya Mission Control",
        guardIslandOpen: "ada açık",
        guardOwnPanel: "uygulama penceresi açık",
        guardExcludedSource: "hiç ayrılmayacak uygulama",
        guardCalibrating: "kalibrasyon sürüyor",
        guardCooldown: "az önce geçildi",
        guardLowConfidence: "bakış belirsiz",
        pauseUser: "isteğiniz üzerine",
        pauseLocked: "Mac kilitli",
        pauseAsleep: "Mac uykuda",
        pauseScreensAsleep: "ekranlar uykuda",
        pauseSessionInactive: "oturum arka planda",
        pauseIdle: "etkinlik yok",
        pauseBattery: "pilde",
        pauseLowPower: "Düşük Güç Modu",
        pauseThermal: "Mac çok sıcak",
        pauseCameraBusy: "kamera önizlemesi açık",
        pauseCall: "görüntülü arama sürüyor",
        pauseSingleScreen: "yalnızca bir ekran",
        pauseLidClosed: "kapak kapalı",
        shortUser: "Duraklatıldı",
        shortLocked: "Kilitli",
        shortAsleep: "Uykuda",
        shortScreensAsleep: "Ekranlar uykuda",
        shortSessionInactive: "Oturum arka planda",
        shortIdle: "Boşta",
        shortBattery: "Pil",
        shortLowPower: "Düşük Güç Modu",
        shortThermal: "Mac çok sıcak",
        shortCameraBusy: "Kamera önizlemesi",
        shortCall: "Görüntülü arama",
        shortSingleScreen: "Tek ekran",
        shortLidClosed: "Kapak kapalı",
        singleScreenHint: "Yalnızca bir ekran var: Bölgeler moduna geçin",
        unavailableCameraPermission: "Kamera izni gerekli",
        unavailableAccessibility: "Erişilebilirlik izni gerekli",
        unavailableNoCamera: "Kamera yok",
        unavailableCameraDisconnected: "Kamera bağlantısı kesildi",
        unavailableCameraFailed: "Kamera yanıt vermiyor",
        shortCameraPermission: "Kamera izni",
        shortAccessibility: "Erişilebilirlik",
        shortNoCamera: "Kamera bulunamadı",
        shortCameraDisconnected: "Kamera çıkarıldı",
        shortCameraFailed: "Kamera kullanılamıyor",
        needFirstTime: "Başlamak için kalibre edin",
        needNewLayout: "Bu ekran düzeni için kalibre edin",
        needNewCamera: "Bu kamera için kalibre edin",
        needRemoved: "Profil silindi: yeniden kalibre edin",
        shortNeedFirstTime: "Kalibre et",
        shortNeedNewLayout: "Yeni düzen",
        shortNeedNewCamera: "Yeni kamera",
        shortNeedRemoved: "Profil silindi",
        zoneWhole: "%@ (tamamı)",
        zoneLeft: "Sol bölge (%@)",
        zoneCenter: "Orta bölge (%@)",
        zoneRight: "Sağ bölge (%@)",
        zoneTop: "Üst bölge (%@)",
        zoneBottom: "Alt bölge (%@)",
        zoneTopLeft: "Sol üst köşe (%@)",
        zoneTopRight: "Sağ üst köşe (%@)",
        zoneBottomLeft: "Sol alt köşe (%@)",
        zoneBottomRight: "Sağ alt köşe (%@)",
        zoneWindowOn: "Pencere (%@)",
        zoneWindowApp: "%@ penceresi",
        builtInDisplay: "MacBook",
        modeScreens: "Ekranlar",
        modeZones: "Bölgeler",
        modeWindows: "Pencereler",
        modeScreensCaption: "Ekran başına bir bölge: klavye baktığınız ekranı izler.",
        modeZonesCaption: "Her ekran bölgelere ayrılır; geniş bir ekran için idealdir.",
        modeWindowsCaption: "Görünen her pencere bir bölgedir. Hassas bir kalibrasyon gerekir.",
        modeSuited: "Bu düzene uygun",
        modeDiscouraged: "Bu düzende bu mod için yeterince hassas değil",
        panes: "Bölmeler (deneysel)",
        splitWhole: "Tamamı",
        splitColumns2: "2 sütun",
        splitColumns3: "3 sütun",
        splitRows2: "2 satır",
        splitGrid2x2: "2×2 ızgara",
        gradeExcellent: "Mükemmel",
        gradeGood: "İyi",
        gradeFair: "Orta",
        gradePoor: "Yetersiz",
        calibrationScore: "Kalibrasyon %@",
        calibrationScoreAge: "Kalibrasyon %1$@ · %2$@",
        headOnly: "Yalnızca baş",
        headAndEyes: "Baş ve gözler",
        durationFifteenMinutes: "15 dakikalığına",
        durationOneHour: "1 saatliğine",
        durationUntilTomorrow: "Yarına kadar",
        durationUntilResumed: "Sürdürülene kadar",
        energySaver: "Tasarruflu",
        energyBalanced: "Dengeli",
        energyReactive: "Duyarlı",
        batterySame: "Güç bağlıyken olduğu gibi",
        batterySaver: "Tasarruflu",
        batteryPause: "Duraklat",
        callKeepRunning: "Devam et",
        callPause: "Duraklat",
        pointerAuto: "Otomatik",
        pointerStay: "Taşıma",
        pointerFollowScreen: "Ekranı izle",
        pointerWindowCenter: "Pencere ortası",
        feedbackNone: "Yok",
        feedbackHalo: "Hale",
        feedbackZone: "Bölge parlaması",
        islandNever: "Hiçbir zaman",
        islandPaused: "Duraklatma veya kalibrasyon sırasında",
        islandAlways: "Her zaman (etkin bölge)",
        sensitivityCautious: "Temkinli",
        sensitivityLively: "Canlı",
        never: "Hiçbir zaman",
        noticeKindPause: "Duraklatma ve sürdürme",
        noticeKindNewLayout: "Yeni ekran düzeni",
        noticeKindCamera: "Kamera kullanılamıyor",
        noticeKindRecenter: "Yeniden ortalandı",
        noticeKindCalibrated: "Kalibrasyon tamamlandı",
        noticeKindDrift: "Yeniden kalibrasyon önerisi",
        noticePaused: "Bakış duraklatıldı",
        noticeResumed: "Bakış sürdürüldü",
        noticeNewLayout: "Yeni ekran düzeni",
        noticeCameraUnavailable: "Kamera kullanılamıyor",
        noticeRecentered: "Yeniden ortalandı",
        noticeCalibrated: "Kalibre edildi · %@",
        noticeDrift: "Bakış sık sık yanılıyor",
        noticePausedUntil: "Sürdürme saati: %@",
        noticePausedTomorrow: "Yarına kadar",
        noticePausedIndefinitely: "Siz sürdürene kadar",
        noticeNewLayoutDetail: "Ekranlar için kalibre edin",
        noticeCameraDetail: "Bakış duraklatıldı",
        noticeDriftDetail: "Yeniden kalibre edin",
        pausedFor: "Duraklatıldı · %@",
        pause: "Duraklat",
        resume: "Sürdür",
        resumeAnyway: "Yine de sürdür",
        recenter: "Yeniden ortala",
        calibrate: "Kalibre et",
        calibrateEllipsis: "Kalibre et…",
        recalibrate: "Yeniden kalibre et",
        quickRecenter: "Hızlı hizalama",
        test: "Dene",
        enable: "Aç",
        openSettings: "Ayarları aç",
        allowCamera: "Kameraya izin ver",
        allowAccessibility: "Erişilebilirliğe izin ver",
        retry: "Yeniden dene",
        chooseCamera: "Başka bir kamera seç",
        switchToZones: "Bölgeler moduna geç",
        lastSwitch: "Son geçiş %@",
        recentSwitches: "Son geçişler",
        barPauseFifteenMinutes: "Bakışla Odak’ı 15 dakika duraklat",
        barPauseOneHour: "Bakışla Odak’ı 1 saat duraklat",
        barPauseUntilTomorrow: "Bakışla Odak’ı yarına kadar duraklat",
        barPauseUntilResumed: "Bakışla Odak’ı duraklat",
        barResume: "Bakışla Odak’ı sürdür",
        barRecenter: "Bakışla Odak’ı yeniden ortala",
        barCalibrate: "Bakışla Odak’ı kalibre et",
        barSwitchMode: "Bakışla Odak’ı %@ moduna geçir",
        barSettings: "Bakışla Odak Ayarları",
        barKeywords: "bakış, göz, baş, baş takibi, kamera, odak, pencere, ekran, bölge, duraklat, sürdür, ortala, kalibre et",
        shortcutPauseResume: "Duraklat veya sürdür",
        shortcutRecenter: "Yeniden ortala",
        shortcutMode: "Mod değiştir",
        elidesBeforeVowel: false
    )

    static let ru = ForkGlanceStrings(
        featureTitle: "Фокус взглядом",
        sectionTitle: "Взгляд",
        searchKeywords: "взгляд, глаза, голова, отслеживание головы, камера, лицо, фокус, окно, экран, монитор, зона, клавиатура",
        featureOff: "Фокус взглядом выключен",
        statusOff: "Выключено",
        statusActive: "Активно",
        statusActiveZone: "Активно · %@",
        statusStarting: "Запуск камеры…",
        statusCalibrating: "Калибровка…",
        statusCalibratingCount: "Калибровка · %@",
        statusWaiting: "Ожидание: %@",
        statusNoFace: "Лицо не обнаружено",
        statusAway: "Взгляд вне экранов",
        statusPaused: "Приостановлено",
        statusPausedUntil: "Приостановлено — возобновится в %@",
        statusPausedTomorrow: "Приостановлено до завтра",
        statusPausedUntilDay: "Приостановлено — возобновится %@",
        statusPausedReason: "Приостановлено: %@",
        guardTyping: "вы печатаете",
        guardPointer: "мышь",
        guardButtonsOrModifiers: "нажата клавиша или кнопка",
        guardSecureInput: "ввод пароля",
        guardDictation: "идёт диктовка",
        guardMenuOrOverview: "меню или Mission Control",
        guardIslandOpen: "остров открыт",
        guardOwnPanel: "открыто окно приложения",
        guardExcludedSource: "закреплённое приложение",
        guardCalibrating: "идёт калибровка",
        guardCooldown: "только что переключено",
        guardLowConfidence: "взгляд неясен",
        pauseUser: "по вашему запросу",
        pauseLocked: "Mac заблокирован",
        pauseAsleep: "Mac в режиме сна",
        pauseScreensAsleep: "экраны в режиме сна",
        pauseSessionInactive: "сеанс в фоне",
        pauseIdle: "нет активности",
        pauseBattery: "от батареи",
        pauseLowPower: "режим энергосбережения",
        pauseThermal: "Mac перегрет",
        pauseCameraBusy: "открыт предпросмотр камеры",
        pauseCall: "идёт видеозвонок",
        pauseSingleScreen: "только один экран",
        pauseLidClosed: "крышка закрыта",
        shortUser: "Пауза",
        shortLocked: "Заблокирован",
        shortAsleep: "Режим сна",
        shortScreensAsleep: "Экраны в режиме сна",
        shortSessionInactive: "Сеанс в фоне",
        shortIdle: "Бездействие",
        shortBattery: "Батарея",
        shortLowPower: "Энергосбережение",
        shortThermal: "Mac перегрет",
        shortCameraBusy: "Предпросмотр камеры",
        shortCall: "Видеозвонок",
        shortSingleScreen: "Один экран",
        shortLidClosed: "Крышка закрыта",
        singleScreenHint: "Только один экран: переключитесь в режим «Зоны»",
        unavailableCameraPermission: "Нужен доступ к камере",
        unavailableAccessibility: "Нужен Универсальный доступ",
        unavailableNoCamera: "Нет камеры",
        unavailableCameraDisconnected: "Камера отключена",
        unavailableCameraFailed: "Камера не отвечает",
        shortCameraPermission: "Доступ к камере",
        shortAccessibility: "Универсальный доступ",
        shortNoCamera: "Камера не найдена",
        shortCameraDisconnected: "Камера отсоединена",
        shortCameraFailed: "Камера недоступна",
        needFirstTime: "Откалибруйте, чтобы начать",
        needNewLayout: "Откалибруйте для этого расположения экранов",
        needNewCamera: "Откалибруйте для этой камеры",
        needRemoved: "Профиль удалён: откалибруйте заново",
        shortNeedFirstTime: "Откалибровать",
        shortNeedNewLayout: "Новое расположение",
        shortNeedNewCamera: "Новая камера",
        shortNeedRemoved: "Профиль удалён",
        zoneWhole: "Весь экран %@",
        zoneLeft: "Левая зона %@",
        zoneCenter: "Центральная зона %@",
        zoneRight: "Правая зона %@",
        zoneTop: "Верхняя зона %@",
        zoneBottom: "Нижняя зона %@",
        zoneTopLeft: "Левый верхний угол %@",
        zoneTopRight: "Правый верхний угол %@",
        zoneBottomLeft: "Левый нижний угол %@",
        zoneBottomRight: "Правый нижний угол %@",
        zoneWindowOn: "Окно на экране %@",
        zoneWindowApp: "Окно %@",
        builtInDisplay: "MacBook",
        modeScreens: "Экраны",
        modeZones: "Зоны",
        modeWindows: "Окна",
        modeScreensCaption: "Одна зона на экран: клавиатура следует за экраном, на который вы смотрите.",
        modeZonesCaption: "Каждый экран делится на зоны — идеально для широкого монитора.",
        modeWindowsCaption: "Каждое видимое окно — отдельная зона. Нужна точная калибровка.",
        modeSuited: "Подходит для этого расположения",
        modeDiscouraged: "Недостаточно точно для этого режима при таком расположении",
        panes: "Панели (экспериментально)",
        splitWhole: "Целиком",
        splitColumns2: "2 столбца",
        splitColumns3: "3 столбца",
        splitRows2: "2 строки",
        splitGrid2x2: "Сетка 2×2",
        gradeExcellent: "Отлично",
        gradeGood: "Хорошо",
        gradeFair: "Средне",
        gradePoor: "Недостаточно",
        calibrationScore: "Калибровка %@",
        calibrationScoreAge: "Калибровка %1$@ · %2$@",
        headOnly: "Только голова",
        headAndEyes: "Голова и глаза",
        durationFifteenMinutes: "На 15 минут",
        durationOneHour: "На 1 час",
        durationUntilTomorrow: "До завтра",
        durationUntilResumed: "До возобновления",
        energySaver: "Экономно",
        energyBalanced: "Сбалансированно",
        energyReactive: "Отзывчиво",
        batterySame: "Как от сети",
        batterySaver: "Экономно",
        batteryPause: "Приостанавливать",
        callKeepRunning: "Продолжать",
        callPause: "Приостанавливать",
        pointerAuto: "Автоматически",
        pointerStay: "Не перемещать",
        pointerFollowScreen: "Следовать за экраном",
        pointerWindowCenter: "Центр окна",
        feedbackNone: "Нет",
        feedbackHalo: "Ореол",
        feedbackZone: "Вспышка зоны",
        islandNever: "Никогда",
        islandPaused: "Во время паузы или калибровки",
        islandAlways: "Всегда (активная зона)",
        sensitivityCautious: "Осторожно",
        sensitivityLively: "Живо",
        never: "Никогда",
        noticeKindPause: "Пауза и возобновление",
        noticeKindNewLayout: "Новое расположение экранов",
        noticeKindCamera: "Камера недоступна",
        noticeKindRecenter: "Центровка",
        noticeKindCalibrated: "Калибровка завершена",
        noticeKindDrift: "Совет перекалибровать",
        noticePaused: "Взгляд на паузе",
        noticeResumed: "Взгляд возобновлён",
        noticeNewLayout: "Новое расположение",
        noticeCameraUnavailable: "Камера недоступна",
        noticeRecentered: "Отцентровано",
        noticeCalibrated: "Откалибровано · %@",
        noticeDrift: "Взгляд часто ошибается",
        noticePausedUntil: "Возобновится в %@",
        noticePausedTomorrow: "До завтра",
        noticePausedIndefinitely: "Пока вы не возобновите",
        noticeNewLayoutDetail: "Откалибруйте эти экраны",
        noticeCameraDetail: "Взгляд на паузе",
        noticeDriftDetail: "Откалибруйте заново",
        pausedFor: "Пауза · %@",
        pause: "Приостановить",
        resume: "Возобновить",
        resumeAnyway: "Всё равно возобновить",
        recenter: "Отцентровать",
        calibrate: "Откалибровать",
        calibrateEllipsis: "Откалибровать…",
        recalibrate: "Откалибровать заново",
        quickRecenter: "Быстрая подстройка",
        test: "Проверить",
        enable: "Включить",
        openSettings: "Открыть настройки",
        allowCamera: "Разрешить камеру",
        allowAccessibility: "Дать Универсальный доступ",
        retry: "Повторить",
        chooseCamera: "Выбрать другую камеру",
        switchToZones: "Перейти в режим «Зоны»",
        lastSwitch: "Последнее переключение %@",
        recentSwitches: "Недавние переключения",
        barPauseFifteenMinutes: "Приостановить Фокус взглядом на 15 минут",
        barPauseOneHour: "Приостановить Фокус взглядом на 1 час",
        barPauseUntilTomorrow: "Приостановить Фокус взглядом до завтра",
        barPauseUntilResumed: "Приостановить Фокус взглядом",
        barResume: "Возобновить Фокус взглядом",
        barRecenter: "Отцентровать Фокус взглядом",
        barCalibrate: "Откалибровать Фокус взглядом",
        barSwitchMode: "Фокус взглядом: режим «%@»",
        barSettings: "Настройки Фокуса взглядом",
        barKeywords: "взгляд, глаза, голова, отслеживание головы, камера, фокус, окно, экран, зона, пауза, возобновить, центровка, калибровка",
        shortcutPauseResume: "Приостановить или возобновить",
        shortcutRecenter: "Отцентровать",
        shortcutMode: "Сменить режим",
        elidesBeforeVowel: false
    )

    static let es = ForkGlanceStrings(
        featureTitle: "Foco con la mirada",
        sectionTitle: "Mirada",
        searchKeywords: "mirada, ojos, cabeza, seguimiento de la cabeza, cámara, cara, foco, ventana, pantalla, monitor, zona, teclado",
        featureOff: "Foco con la mirada está desactivado",
        statusOff: "Desactivado",
        statusActive: "Activo",
        statusActiveZone: "Activo · %@",
        statusStarting: "Iniciando la cámara…",
        statusCalibrating: "Calibrando…",
        statusCalibratingCount: "Calibrando · %@",
        statusWaiting: "En espera: %@",
        statusNoFace: "No se detecta ninguna cara",
        statusAway: "Mirada fuera de las pantallas",
        statusPaused: "En pausa",
        statusPausedUntil: "En pausa — se reanuda a las %@",
        statusPausedTomorrow: "En pausa hasta mañana",
        statusPausedUntilDay: "En pausa — se reanuda el %@",
        statusPausedReason: "En pausa: %@",
        guardTyping: "estás escribiendo",
        guardPointer: "ratón",
        guardButtonsOrModifiers: "tecla o botón pulsado",
        guardSecureInput: "introducción de contraseña",
        guardDictation: "dictado en curso",
        guardMenuOrOverview: "menú o Mission Control",
        guardIslandOpen: "isla abierta",
        guardOwnPanel: "ventana de la app abierta",
        guardExcludedSource: "app que nunca se deja",
        guardCalibrating: "calibración en curso",
        guardCooldown: "cambio reciente",
        guardLowConfidence: "mirada poco clara",
        pauseUser: "a petición tuya",
        pauseLocked: "Mac bloqueado",
        pauseAsleep: "Mac en reposo",
        pauseScreensAsleep: "pantallas en reposo",
        pauseSessionInactive: "sesión en segundo plano",
        pauseIdle: "sin actividad",
        pauseBattery: "con batería",
        pauseLowPower: "modo de bajo consumo",
        pauseThermal: "Mac demasiado caliente",
        pauseCameraBusy: "vista previa de la cámara abierta",
        pauseCall: "videollamada en curso",
        pauseSingleScreen: "una sola pantalla",
        pauseLidClosed: "tapa cerrada",
        shortUser: "En pausa",
        shortLocked: "Bloqueado",
        shortAsleep: "En reposo",
        shortScreensAsleep: "Pantallas en reposo",
        shortSessionInactive: "Sesión en segundo plano",
        shortIdle: "Inactivo",
        shortBattery: "Batería",
        shortLowPower: "Bajo consumo",
        shortThermal: "Mac demasiado caliente",
        shortCameraBusy: "Vista previa de cámara",
        shortCall: "Videollamada",
        shortSingleScreen: "Una sola pantalla",
        shortLidClosed: "Tapa cerrada",
        singleScreenHint: "Solo hay una pantalla: cambia al modo Zonas",
        unavailableCameraPermission: "Se necesita acceso a la cámara",
        unavailableAccessibility: "Se necesita acceso a Accesibilidad",
        unavailableNoCamera: "No hay cámara",
        unavailableCameraDisconnected: "Cámara desconectada",
        unavailableCameraFailed: "La cámara no responde",
        shortCameraPermission: "Acceso a la cámara",
        shortAccessibility: "Accesibilidad",
        shortNoCamera: "No se encontró cámara",
        shortCameraDisconnected: "Cámara desconectada",
        shortCameraFailed: "Cámara no disponible",
        needFirstTime: "Calibra para empezar",
        needNewLayout: "Calibra para esta disposición de pantallas",
        needNewCamera: "Calibra para esta cámara",
        needRemoved: "Perfil eliminado: vuelve a calibrar",
        shortNeedFirstTime: "Calibrar",
        shortNeedNewLayout: "Nueva disposición",
        shortNeedNewCamera: "Nueva cámara",
        shortNeedRemoved: "Perfil eliminado",
        zoneWhole: "%@ completo",
        zoneLeft: "Zona izquierda del %@",
        zoneCenter: "Zona central del %@",
        zoneRight: "Zona derecha del %@",
        zoneTop: "Zona superior del %@",
        zoneBottom: "Zona inferior del %@",
        zoneTopLeft: "Arriba izquierda del %@",
        zoneTopRight: "Arriba derecha del %@",
        zoneBottomLeft: "Abajo izquierda del %@",
        zoneBottomRight: "Abajo derecha del %@",
        zoneWindowOn: "Ventana en el %@",
        zoneWindowApp: "Ventana de %@",
        builtInDisplay: "MacBook",
        modeScreens: "Pantallas",
        modeZones: "Zonas",
        modeWindows: "Ventanas",
        modeScreensCaption: "Una zona por pantalla: el teclado sigue la pantalla que miras.",
        modeZonesCaption: "Cada pantalla se divide en zonas, ideal para una pantalla ancha.",
        modeWindowsCaption: "Cada ventana visible es una zona. Requiere una calibración precisa.",
        modeSuited: "Adecuado para esta disposición",
        modeDiscouraged: "No es lo bastante preciso para este modo con esta disposición",
        panes: "Paneles (experimental)",
        splitWhole: "Completa",
        splitColumns2: "2 columnas",
        splitColumns3: "3 columnas",
        splitRows2: "2 filas",
        splitGrid2x2: "Cuadrícula 2×2",
        gradeExcellent: "Excelente",
        gradeGood: "Buena",
        gradeFair: "Regular",
        gradePoor: "Insuficiente",
        calibrationScore: "Calibración %@",
        calibrationScoreAge: "Calibración %1$@ · %2$@",
        headOnly: "Solo la cabeza",
        headAndEyes: "Cabeza y ojos",
        durationFifteenMinutes: "Durante 15 minutos",
        durationOneHour: "Durante 1 hora",
        durationUntilTomorrow: "Hasta mañana",
        durationUntilResumed: "Hasta reanudar",
        energySaver: "Ahorro",
        energyBalanced: "Equilibrado",
        energyReactive: "Reactivo",
        batterySame: "Igual que con corriente",
        batterySaver: "Ahorro",
        batteryPause: "Pausar",
        callKeepRunning: "Continuar",
        callPause: "Pausar",
        pointerAuto: "Automático",
        pointerStay: "No mover",
        pointerFollowScreen: "Seguir la pantalla",
        pointerWindowCenter: "Centro de la ventana",
        feedbackNone: "Ninguno",
        feedbackHalo: "Halo",
        feedbackZone: "Destello de zona",
        islandNever: "Nunca",
        islandPaused: "Durante una pausa o calibración",
        islandAlways: "Siempre (zona activa)",
        sensitivityCautious: "Prudente",
        sensitivityLively: "Ágil",
        never: "Nunca",
        noticeKindPause: "Pausa y reanudación",
        noticeKindNewLayout: "Nueva disposición de pantallas",
        noticeKindCamera: "Cámara no disponible",
        noticeKindRecenter: "Recentrado",
        noticeKindCalibrated: "Calibración completada",
        noticeKindDrift: "Recalibración sugerida",
        noticePaused: "Mirada en pausa",
        noticeResumed: "Mirada reanudada",
        noticeNewLayout: "Nueva disposición",
        noticeCameraUnavailable: "Cámara no disponible",
        noticeRecentered: "Recentrado",
        noticeCalibrated: "Calibrado · %@",
        noticeDrift: "La mirada falla a menudo",
        noticePausedUntil: "Se reanuda a las %@",
        noticePausedTomorrow: "Hasta mañana",
        noticePausedIndefinitely: "Hasta que reanudes",
        noticeNewLayoutDetail: "Calibra para estas pantallas",
        noticeCameraDetail: "La mirada está en pausa",
        noticeDriftDetail: "Recalibra para afinarla",
        pausedFor: "En pausa · %@",
        pause: "Pausar",
        resume: "Reanudar",
        resumeAnyway: "Reanudar igualmente",
        recenter: "Recentrar",
        calibrate: "Calibrar",
        calibrateEllipsis: "Calibrar…",
        recalibrate: "Volver a calibrar",
        quickRecenter: "Reajuste rápido",
        test: "Probar",
        enable: "Activar",
        openSettings: "Abrir Ajustes",
        allowCamera: "Permitir la cámara",
        allowAccessibility: "Permitir Accesibilidad",
        retry: "Reintentar",
        chooseCamera: "Elegir otra cámara",
        switchToZones: "Cambiar al modo Zonas",
        lastSwitch: "Último cambio %@",
        recentSwitches: "Cambios recientes",
        barPauseFifteenMinutes: "Pausar Foco con la mirada durante 15 minutos",
        barPauseOneHour: "Pausar Foco con la mirada durante 1 hora",
        barPauseUntilTomorrow: "Pausar Foco con la mirada hasta mañana",
        barPauseUntilResumed: "Pausar Foco con la mirada",
        barResume: "Reanudar Foco con la mirada",
        barRecenter: "Recentrar Foco con la mirada",
        barCalibrate: "Calibrar Foco con la mirada",
        barSwitchMode: "Cambiar Foco con la mirada al modo %@",
        barSettings: "Ajustes de Foco con la mirada",
        barKeywords: "mirada, ojos, cabeza, seguimiento de la cabeza, cámara, foco, ventana, pantalla, zona, pausar, reanudar, recentrar, calibrar",
        shortcutPauseResume: "Pausar o reanudar",
        shortcutRecenter: "Recentrar",
        shortcutMode: "Cambiar de modo",
        elidesBeforeVowel: false
    )

    static let sk = ForkGlanceStrings(
        featureTitle: "Fokus pohľadom",
        sectionTitle: "Pohľad",
        searchKeywords: "pohľad, oči, hlava, sledovanie hlavy, kamera, tvár, fokus, okno, obrazovka, displej, zóna, klávesnica",
        featureOff: "Fokus pohľadom je vypnutý",
        statusOff: "Vypnuté",
        statusActive: "Aktívne",
        statusActiveZone: "Aktívne · %@",
        statusStarting: "Spúšťa sa kamera…",
        statusCalibrating: "Prebieha kalibrácia…",
        statusCalibratingCount: "Prebieha kalibrácia · %@",
        statusWaiting: "Čaká sa: %@",
        statusNoFace: "Nezistila sa žiadna tvár",
        statusAway: "Pohľad mimo obrazoviek",
        statusPaused: "Pozastavené",
        statusPausedUntil: "Pozastavené — pokračuje o %@",
        statusPausedTomorrow: "Pozastavené do zajtra",
        statusPausedUntilDay: "Pozastavené — pokračuje %@",
        statusPausedReason: "Pozastavené: %@",
        guardTyping: "píšete",
        guardPointer: "myš",
        guardButtonsOrModifiers: "stlačený kláves či tlačidlo",
        guardSecureInput: "zadávanie hesla",
        guardDictation: "prebieha diktovanie",
        guardMenuOrOverview: "menu alebo Mission Control",
        guardIslandOpen: "otvorený ostrov",
        guardOwnPanel: "otvorené okno aplikácie",
        guardExcludedSource: "nikdy neopúšťaná aplikácia",
        guardCalibrating: "prebieha kalibrácia",
        guardCooldown: "práve prepnuté",
        guardLowConfidence: "nejasný pohľad",
        pauseUser: "na vašu žiadosť",
        pauseLocked: "Mac je zamknutý",
        pauseAsleep: "Mac je v režime spánku",
        pauseScreensAsleep: "obrazovky v režime spánku",
        pauseSessionInactive: "relácia na pozadí",
        pauseIdle: "žiadna aktivita",
        pauseBattery: "na batérii",
        pauseLowPower: "režim nízkej spotreby",
        pauseThermal: "Mac je príliš horúci",
        pauseCameraBusy: "otvorený náhľad kamery",
        pauseCall: "prebieha videohovor",
        pauseSingleScreen: "len jedna obrazovka",
        pauseLidClosed: "zatvorené veko",
        shortUser: "Pozastavené",
        shortLocked: "Zamknuté",
        shortAsleep: "Spánok",
        shortScreensAsleep: "Obrazovky v spánku",
        shortSessionInactive: "Relácia na pozadí",
        shortIdle: "Nečinnosť",
        shortBattery: "Batéria",
        shortLowPower: "Nízka spotreba",
        shortThermal: "Mac je príliš horúci",
        shortCameraBusy: "Náhľad kamery",
        shortCall: "Videohovor",
        shortSingleScreen: "Jedna obrazovka",
        shortLidClosed: "Zatvorené veko",
        singleScreenHint: "Len jedna obrazovka: prepnite na režim Zóny",
        unavailableCameraPermission: "Treba prístup ku kamere",
        unavailableAccessibility: "Treba povolenie Prístupnosť",
        unavailableNoCamera: "Žiadna kamera",
        unavailableCameraDisconnected: "Kamera je odpojená",
        unavailableCameraFailed: "Kamera nereaguje",
        shortCameraPermission: "Prístup ku kamere",
        shortAccessibility: "Prístupnosť",
        shortNoCamera: "Nenašla sa žiadna kamera",
        shortCameraDisconnected: "Kamera odpojená",
        shortCameraFailed: "Kamera nie je dostupná",
        needFirstTime: "Začnite kalibráciou",
        needNewLayout: "Kalibrujte pre toto usporiadanie obrazoviek",
        needNewCamera: "Kalibrujte pre túto kameru",
        needRemoved: "Profil vymazaný: kalibrujte znova",
        shortNeedFirstTime: "Kalibrovať",
        shortNeedNewLayout: "Nové usporiadanie",
        shortNeedNewCamera: "Nová kamera",
        shortNeedRemoved: "Profil vymazaný",
        zoneWhole: "Celá obrazovka %@",
        zoneLeft: "Ľavá zóna %@",
        zoneCenter: "Stredná zóna %@",
        zoneRight: "Pravá zóna %@",
        zoneTop: "Horná zóna %@",
        zoneBottom: "Dolná zóna %@",
        zoneTopLeft: "Ľavý horný roh %@",
        zoneTopRight: "Pravý horný roh %@",
        zoneBottomLeft: "Ľavý dolný roh %@",
        zoneBottomRight: "Pravý dolný roh %@",
        zoneWindowOn: "Okno na obrazovke %@",
        zoneWindowApp: "Okno %@",
        builtInDisplay: "MacBook",
        modeScreens: "Obrazovky",
        modeZones: "Zóny",
        modeWindows: "Okná",
        modeScreensCaption: "Jedna zóna na obrazovku: klávesnica sleduje obrazovku, na ktorú sa pozeráte.",
        modeZonesCaption: "Každá obrazovka je rozdelená na zóny, ideálne pre široký displej.",
        modeWindowsCaption: "Každé viditeľné okno je zóna. Vyžaduje presnú kalibráciu.",
        modeSuited: "Vhodné pre toto usporiadanie",
        modeDiscouraged: "Pre tento režim pri tomto usporiadaní nedostatočne presné",
        panes: "Panely (experimentálne)",
        splitWhole: "Celá",
        splitColumns2: "2 stĺpce",
        splitColumns3: "3 stĺpce",
        splitRows2: "2 riadky",
        splitGrid2x2: "Mriežka 2×2",
        gradeExcellent: "Výborná",
        gradeGood: "Dobrá",
        gradeFair: "Priemerná",
        gradePoor: "Nedostatočná",
        calibrationScore: "Kalibrácia %@",
        calibrationScoreAge: "Kalibrácia %1$@ · %2$@",
        headOnly: "Len hlava",
        headAndEyes: "Hlava a oči",
        durationFifteenMinutes: "Na 15 minút",
        durationOneHour: "Na 1 hodinu",
        durationUntilTomorrow: "Do zajtra",
        durationUntilResumed: "Do pokračovania",
        energySaver: "Úsporný",
        energyBalanced: "Vyvážený",
        energyReactive: "Pohotový",
        batterySame: "Ako pri napájaní",
        batterySaver: "Úsporný",
        batteryPause: "Pozastaviť",
        callKeepRunning: "Pokračovať",
        callPause: "Pozastaviť",
        pointerAuto: "Automaticky",
        pointerStay: "Nehýbať",
        pointerFollowScreen: "Sledovať obrazovku",
        pointerWindowCenter: "Stred okna",
        feedbackNone: "Žiadna",
        feedbackHalo: "Žiara",
        feedbackZone: "Zablikanie zóny",
        islandNever: "Nikdy",
        islandPaused: "Počas pozastavenia alebo kalibrácie",
        islandAlways: "Vždy (aktívna zóna)",
        sensitivityCautious: "Opatrná",
        sensitivityLively: "Živá",
        never: "Nikdy",
        noticeKindPause: "Pozastavenie a pokračovanie",
        noticeKindNewLayout: "Nové usporiadanie obrazoviek",
        noticeKindCamera: "Kamera nedostupná",
        noticeKindRecenter: "Vycentrovanie",
        noticeKindCalibrated: "Kalibrácia dokončená",
        noticeKindDrift: "Odporúčaná rekalibrácia",
        noticePaused: "Pohľad pozastavený",
        noticeResumed: "Pohľad pokračuje",
        noticeNewLayout: "Nové usporiadanie",
        noticeCameraUnavailable: "Kamera nedostupná",
        noticeRecentered: "Vycentrované",
        noticeCalibrated: "Kalibrované · %@",
        noticeDrift: "Pohľad sa často mýli",
        noticePausedUntil: "Pokračuje o %@",
        noticePausedTomorrow: "Do zajtra",
        noticePausedIndefinitely: "Kým nebudete pokračovať",
        noticeNewLayoutDetail: "Kalibrujte tieto obrazovky",
        noticeCameraDetail: "Pohľad je pozastavený",
        noticeDriftDetail: "Kalibrujte znova",
        pausedFor: "Pozastavené · %@",
        pause: "Pozastaviť",
        resume: "Pokračovať",
        resumeAnyway: "Napriek tomu pokračovať",
        recenter: "Vycentrovať",
        calibrate: "Kalibrovať",
        calibrateEllipsis: "Kalibrovať…",
        recalibrate: "Kalibrovať znova",
        quickRecenter: "Rýchle zarovnanie",
        test: "Otestovať",
        enable: "Zapnúť",
        openSettings: "Otvoriť nastavenia",
        allowCamera: "Povoliť kameru",
        allowAccessibility: "Povoliť Prístupnosť",
        retry: "Skúsiť znova",
        chooseCamera: "Vybrať inú kameru",
        switchToZones: "Prepnúť na režim Zóny",
        lastSwitch: "Posledné prepnutie %@",
        recentSwitches: "Nedávne prepnutia",
        barPauseFifteenMinutes: "Pozastaviť Fokus pohľadom na 15 minút",
        barPauseOneHour: "Pozastaviť Fokus pohľadom na 1 hodinu",
        barPauseUntilTomorrow: "Pozastaviť Fokus pohľadom do zajtra",
        barPauseUntilResumed: "Pozastaviť Fokus pohľadom",
        barResume: "Pokračovať vo Fokuse pohľadom",
        barRecenter: "Vycentrovať Fokus pohľadom",
        barCalibrate: "Kalibrovať Fokus pohľadom",
        barSwitchMode: "Prepnúť Fokus pohľadom na režim %@",
        barSettings: "Nastavenia Fokusu pohľadom",
        barKeywords: "pohľad, oči, hlava, sledovanie hlavy, kamera, fokus, okno, obrazovka, zóna, pozastaviť, pokračovať, vycentrovať, kalibrovať",
        shortcutPauseResume: "Pozastaviť alebo pokračovať",
        shortcutRecenter: "Vycentrovať",
        shortcutMode: "Zmeniť režim",
        elidesBeforeVowel: false
    )

    static let de = ForkGlanceStrings(
        featureTitle: "Blickfokus",
        sectionTitle: "Blick",
        searchKeywords: "blick, blickfokus, augen, kopf, kopfverfolgung, kamera, gesicht, fokus, fenster, bildschirm, display, zone, tastatur",
        featureOff: "Blickfokus ist aus",
        statusOff: "Aus",
        statusActive: "Aktiv",
        statusActiveZone: "Aktiv · %@",
        statusStarting: "Kamera wird gestartet…",
        statusCalibrating: "Kalibrierung läuft…",
        statusCalibratingCount: "Kalibrierung läuft · %@",
        statusWaiting: "Wartet: %@",
        statusNoFace: "Kein Gesicht erkannt",
        statusAway: "Blick neben den Bildschirmen",
        statusPaused: "Pausiert",
        statusPausedUntil: "Pausiert – weiter um %@",
        statusPausedTomorrow: "Pausiert bis morgen",
        statusPausedUntilDay: "Pausiert – weiter am %@",
        statusPausedReason: "Pausiert: %@",
        guardTyping: "du tippst",
        guardPointer: "Maus",
        guardButtonsOrModifiers: "Taste oder Knopf gedrückt",
        guardSecureInput: "Passworteingabe",
        guardDictation: "Diktat läuft",
        guardMenuOrOverview: "Menü oder Mission Control",
        guardIslandOpen: "Insel geöffnet",
        guardOwnPanel: "App-Fenster geöffnet",
        guardExcludedSource: "nie zu verlassende App",
        guardCalibrating: "Kalibrierung läuft",
        guardCooldown: "gerade gewechselt",
        guardLowConfidence: "Blick unklar",
        pauseUser: "auf deinen Wunsch",
        pauseLocked: "Mac gesperrt",
        pauseAsleep: "Mac im Ruhezustand",
        pauseScreensAsleep: "Bildschirme im Ruhezustand",
        pauseSessionInactive: "Sitzung im Hintergrund",
        pauseIdle: "keine Aktivität",
        pauseBattery: "Batteriebetrieb",
        pauseLowPower: "Stromsparmodus",
        pauseThermal: "Mac zu heiß",
        pauseCameraBusy: "Kameravorschau geöffnet",
        pauseCall: "Videoanruf läuft",
        pauseSingleScreen: "nur ein Bildschirm",
        pauseLidClosed: "Deckel geschlossen",
        shortUser: "Pausiert",
        shortLocked: "Gesperrt",
        shortAsleep: "Ruhezustand",
        shortScreensAsleep: "Bildschirme im Ruhezustand",
        shortSessionInactive: "Sitzung im Hintergrund",
        shortIdle: "Inaktiv",
        shortBattery: "Batterie",
        shortLowPower: "Stromsparmodus",
        shortThermal: "Mac zu heiß",
        shortCameraBusy: "Kameravorschau",
        shortCall: "Videoanruf",
        shortSingleScreen: "Ein Bildschirm",
        shortLidClosed: "Deckel geschlossen",
        singleScreenHint: "Nur ein Bildschirm: Wechsle in den Modus Zonen",
        unavailableCameraPermission: "Kamerazugriff erforderlich",
        unavailableAccessibility: "Zugriff auf Bedienungshilfen erforderlich",
        unavailableNoCamera: "Keine Kamera",
        unavailableCameraDisconnected: "Kamera getrennt",
        unavailableCameraFailed: "Die Kamera reagiert nicht",
        shortCameraPermission: "Kamerazugriff",
        shortAccessibility: "Bedienungshilfen",
        shortNoCamera: "Keine Kamera gefunden",
        shortCameraDisconnected: "Kamera abgesteckt",
        shortCameraFailed: "Kamera nicht verfügbar",
        needFirstTime: "Kalibriere, um loszulegen",
        needNewLayout: "Kalibriere für diese Bildschirmanordnung",
        needNewCamera: "Kalibriere für diese Kamera",
        needRemoved: "Profil gelöscht: Kalibriere neu",
        shortNeedFirstTime: "Kalibrieren",
        shortNeedNewLayout: "Neue Anordnung",
        shortNeedNewCamera: "Neue Kamera",
        shortNeedRemoved: "Profil gelöscht",
        zoneWhole: "%@ komplett",
        zoneLeft: "Links auf dem %@",
        zoneCenter: "Mitte auf dem %@",
        zoneRight: "Rechts auf dem %@",
        zoneTop: "Oben auf dem %@",
        zoneBottom: "Unten auf dem %@",
        zoneTopLeft: "Oben links auf dem %@",
        zoneTopRight: "Oben rechts auf dem %@",
        zoneBottomLeft: "Unten links auf dem %@",
        zoneBottomRight: "Unten rechts auf dem %@",
        zoneWindowOn: "Fenster auf dem %@",
        zoneWindowApp: "%@-Fenster",
        builtInDisplay: "MacBook",
        modeScreens: "Bildschirme",
        modeZones: "Zonen",
        modeWindows: "Fenster",
        modeScreensCaption: "Eine Zone pro Bildschirm: Die Tastatur folgt dem Bildschirm, den du ansiehst.",
        modeZonesCaption: "Jeder Bildschirm wird in Zonen geteilt, ideal für einen breiten Bildschirm.",
        modeWindowsCaption: "Jedes sichtbare Fenster ist eine Zone. Erfordert eine genaue Kalibrierung.",
        modeSuited: "Passt zu dieser Anordnung",
        modeDiscouraged: "Für diesen Modus bei dieser Anordnung nicht genau genug",
        panes: "Bereiche (experimentell)",
        splitWhole: "Ganz",
        splitColumns2: "2 Spalten",
        splitColumns3: "3 Spalten",
        splitRows2: "2 Zeilen",
        splitGrid2x2: "2×2-Raster",
        gradeExcellent: "Ausgezeichnet",
        gradeGood: "Gut",
        gradeFair: "Mittel",
        gradePoor: "Unzureichend",
        calibrationScore: "Kalibrierung %@",
        calibrationScoreAge: "Kalibrierung %1$@ · %2$@",
        headOnly: "Nur Kopf",
        headAndEyes: "Kopf und Augen",
        durationFifteenMinutes: "Für 15 Minuten",
        durationOneHour: "Für 1 Stunde",
        durationUntilTomorrow: "Bis morgen",
        durationUntilResumed: "Bis zum Fortsetzen",
        energySaver: "Sparsam",
        energyBalanced: "Ausgewogen",
        energyReactive: "Reaktionsschnell",
        batterySame: "Wie am Netzteil",
        batterySaver: "Sparsam",
        batteryPause: "Pausieren",
        callKeepRunning: "Weiterlaufen",
        callPause: "Pausieren",
        pointerAuto: "Automatisch",
        pointerStay: "Nicht bewegen",
        pointerFollowScreen: "Dem Bildschirm folgen",
        pointerWindowCenter: "Fenstermitte",
        feedbackNone: "Keine",
        feedbackHalo: "Halo",
        feedbackZone: "Zone aufleuchten",
        islandNever: "Nie",
        islandPaused: "Bei Pause oder Kalibrierung",
        islandAlways: "Immer (aktive Zone)",
        sensitivityCautious: "Vorsichtig",
        sensitivityLively: "Lebhaft",
        never: "Nie",
        noticeKindPause: "Pausieren und Fortsetzen",
        noticeKindNewLayout: "Neue Bildschirmanordnung",
        noticeKindCamera: "Kamera nicht verfügbar",
        noticeKindRecenter: "Neu zentriert",
        noticeKindCalibrated: "Kalibrierung abgeschlossen",
        noticeKindDrift: "Neukalibrierung empfohlen",
        noticePaused: "Blickfokus pausiert",
        noticeResumed: "Blickfokus fortgesetzt",
        noticeNewLayout: "Neue Bildschirmanordnung",
        noticeCameraUnavailable: "Kamera nicht verfügbar",
        noticeRecentered: "Neu zentriert",
        noticeCalibrated: "Kalibriert · %@",
        noticeDrift: "Blick oft falsch erkannt",
        noticePausedUntil: "Weiter um %@",
        noticePausedTomorrow: "Bis morgen",
        noticePausedIndefinitely: "Bis du fortsetzt",
        noticeNewLayoutDetail: "Kalibriere diese Anordnung",
        noticeCameraDetail: "Blickfokus ist pausiert",
        noticeDriftDetail: "Neu kalibrieren hilft",
        pausedFor: "Pausiert · %@",
        pause: "Pausieren",
        resume: "Fortsetzen",
        resumeAnyway: "Trotzdem fortsetzen",
        recenter: "Neu zentrieren",
        calibrate: "Kalibrieren",
        calibrateEllipsis: "Kalibrieren…",
        recalibrate: "Neu kalibrieren",
        quickRecenter: "Schnell ausrichten",
        test: "Testen",
        enable: "Einschalten",
        openSettings: "Einstellungen öffnen",
        allowCamera: "Kamera erlauben",
        allowAccessibility: "Bedienungshilfen erlauben",
        retry: "Erneut versuchen",
        chooseCamera: "Andere Kamera wählen",
        switchToZones: "Zum Modus Zonen wechseln",
        lastSwitch: "Letzter Wechsel %@",
        recentSwitches: "Letzte Wechsel",
        barPauseFifteenMinutes: "Blickfokus für 15 Minuten pausieren",
        barPauseOneHour: "Blickfokus für 1 Stunde pausieren",
        barPauseUntilTomorrow: "Blickfokus bis morgen pausieren",
        barPauseUntilResumed: "Blickfokus pausieren",
        barResume: "Blickfokus fortsetzen",
        barRecenter: "Blickfokus neu zentrieren",
        barCalibrate: "Blickfokus kalibrieren",
        barSwitchMode: "Blickfokus auf %@ umschalten",
        barSettings: "Blickfokus-Einstellungen",
        barKeywords: "blick, augen, kopf, kopfverfolgung, kamera, fokus, fenster, bildschirm, zone, pausieren, fortsetzen, zentrieren, kalibrieren",
        shortcutPauseResume: "Pausieren oder fortsetzen",
        shortcutRecenter: "Neu zentrieren",
        shortcutMode: "Modus wechseln",
        elidesBeforeVowel: false
    )

    static let it = ForkGlanceStrings(
        featureTitle: "Focus con lo sguardo",
        sectionTitle: "Sguardo",
        searchKeywords: "sguardo, occhi, testa, tracciamento della testa, fotocamera, viso, focus, finestra, schermo, monitor, zona, tastiera",
        featureOff: "Focus con lo sguardo è disattivato",
        statusOff: "Disattivato",
        statusActive: "Attivo",
        statusActiveZone: "Attivo · %@",
        statusStarting: "Avvio della fotocamera…",
        statusCalibrating: "Calibrazione in corso…",
        statusCalibratingCount: "Calibrazione in corso · %@",
        statusWaiting: "In attesa: %@",
        statusNoFace: "Nessun volto rilevato",
        statusAway: "Sguardo fuori dagli schermi",
        statusPaused: "In pausa",
        statusPausedUntil: "In pausa — riprende alle %@",
        statusPausedTomorrow: "In pausa fino a domani",
        statusPausedUntilDay: "In pausa — riprende il %@",
        statusPausedReason: "In pausa: %@",
        guardTyping: "stai scrivendo",
        guardPointer: "mouse in uso",
        guardButtonsOrModifiers: "tasto o pulsante premuto",
        guardSecureInput: "inserimento password",
        guardDictation: "dettatura in corso",
        guardMenuOrOverview: "menu o Mission Control",
        guardIslandOpen: "isola aperta",
        guardOwnPanel: "finestra dell’app aperta",
        guardExcludedSource: "app da non lasciare mai",
        guardCalibrating: "calibrazione in corso",
        guardCooldown: "appena cambiato",
        guardLowConfidence: "sguardo incerto",
        pauseUser: "su tua richiesta",
        pauseLocked: "Mac bloccato",
        pauseAsleep: "Mac in stop",
        pauseScreensAsleep: "schermi in stop",
        pauseSessionInactive: "sessione in background",
        pauseIdle: "nessuna attività",
        pauseBattery: "a batteria",
        pauseLowPower: "modalità Risparmio energetico",
        pauseThermal: "Mac troppo caldo",
        pauseCameraBusy: "anteprima della fotocamera aperta",
        pauseCall: "videochiamata in corso",
        pauseSingleScreen: "un solo schermo",
        pauseLidClosed: "coperchio chiuso",
        shortUser: "In pausa",
        shortLocked: "Bloccato",
        shortAsleep: "In stop",
        shortScreensAsleep: "Schermi in stop",
        shortSessionInactive: "Sessione in background",
        shortIdle: "Inattivo",
        shortBattery: "Batteria",
        shortLowPower: "Risparmio energetico",
        shortThermal: "Mac troppo caldo",
        shortCameraBusy: "Anteprima fotocamera",
        shortCall: "Videochiamata",
        shortSingleScreen: "Un solo schermo",
        shortLidClosed: "Coperchio chiuso",
        singleScreenHint: "Un solo schermo: passa alla modalità Zone",
        unavailableCameraPermission: "Serve l’accesso alla fotocamera",
        unavailableAccessibility: "Serve l’accesso ad Accessibilità",
        unavailableNoCamera: "Nessuna fotocamera",
        unavailableCameraDisconnected: "Fotocamera scollegata",
        unavailableCameraFailed: "La fotocamera non risponde",
        shortCameraPermission: "Accesso fotocamera",
        shortAccessibility: "Accessibilità",
        shortNoCamera: "Nessuna fotocamera trovata",
        shortCameraDisconnected: "Fotocamera scollegata",
        shortCameraFailed: "Fotocamera non disponibile",
        needFirstTime: "Calibra per iniziare",
        needNewLayout: "Calibra per questa disposizione degli schermi",
        needNewCamera: "Calibra per questa fotocamera",
        needRemoved: "Profilo eliminato: calibra di nuovo",
        shortNeedFirstTime: "Calibra",
        shortNeedNewLayout: "Nuova disposizione",
        shortNeedNewCamera: "Nuova fotocamera",
        shortNeedRemoved: "Profilo eliminato",
        zoneWhole: "%@ intero",
        zoneLeft: "Zona sinistra di %@",
        zoneCenter: "Zona centrale di %@",
        zoneRight: "Zona destra di %@",
        zoneTop: "Zona alta di %@",
        zoneBottom: "Zona bassa di %@",
        zoneTopLeft: "Alto a sinistra di %@",
        zoneTopRight: "Alto a destra di %@",
        zoneBottomLeft: "Basso a sinistra di %@",
        zoneBottomRight: "Basso a destra di %@",
        zoneWindowOn: "Finestra su %@",
        zoneWindowApp: "Finestra di %@",
        builtInDisplay: "MacBook",
        modeScreens: "Schermi",
        modeZones: "Zone",
        modeWindows: "Finestre",
        modeScreensCaption: "Una zona per schermo: la tastiera segue lo schermo che guardi.",
        modeZonesCaption: "Ogni schermo è diviso in zone, ideale per uno schermo largo.",
        modeWindowsCaption: "Ogni finestra visibile è una zona. Richiede una calibrazione precisa.",
        modeSuited: "Adatta a questa disposizione",
        modeDiscouraged: "Precisione insufficiente per questa modalità con questa disposizione",
        panes: "Riquadri (sperimentale)",
        splitWhole: "Intero",
        splitColumns2: "2 colonne",
        splitColumns3: "3 colonne",
        splitRows2: "2 righe",
        splitGrid2x2: "Griglia 2×2",
        gradeExcellent: "Eccellente",
        gradeGood: "Buona",
        gradeFair: "Discreta",
        gradePoor: "Insufficiente",
        calibrationScore: "Calibrazione %@",
        calibrationScoreAge: "Calibrazione %1$@ · %2$@",
        headOnly: "Solo testa",
        headAndEyes: "Testa e occhi",
        durationFifteenMinutes: "Per 15 minuti",
        durationOneHour: "Per 1 ora",
        durationUntilTomorrow: "Fino a domani",
        durationUntilResumed: "Finché non riprendi",
        energySaver: "Risparmio",
        energyBalanced: "Bilanciato",
        energyReactive: "Reattivo",
        batterySame: "Come con l’alimentatore",
        batterySaver: "Risparmio",
        batteryPause: "Metti in pausa",
        callKeepRunning: "Continua",
        callPause: "Metti in pausa",
        pointerAuto: "Automatico",
        pointerStay: "Non spostare",
        pointerFollowScreen: "Segui lo schermo",
        pointerWindowCenter: "Centro della finestra",
        feedbackNone: "Nessuno",
        feedbackHalo: "Alone",
        feedbackZone: "Lampo sulla zona",
        islandNever: "Mai",
        islandPaused: "Durante una pausa o una calibrazione",
        islandAlways: "Sempre (zona attiva)",
        sensitivityCautious: "Prudente",
        sensitivityLively: "Vivace",
        never: "Mai",
        noticeKindPause: "Pausa e ripresa",
        noticeKindNewLayout: "Nuova disposizione degli schermi",
        noticeKindCamera: "Fotocamera non disponibile",
        noticeKindRecenter: "Ricentrato",
        noticeKindCalibrated: "Calibrazione riuscita",
        noticeKindDrift: "Ricalibrazione suggerita",
        noticePaused: "Sguardo in pausa",
        noticeResumed: "Sguardo ripreso",
        noticeNewLayout: "Nuova disposizione",
        noticeCameraUnavailable: "Fotocamera non disponibile",
        noticeRecentered: "Ricentrato",
        noticeCalibrated: "Calibrato · %@",
        noticeDrift: "Lo sguardo sbaglia spesso",
        noticePausedUntil: "Riprende alle %@",
        noticePausedTomorrow: "Fino a domani",
        noticePausedIndefinitely: "Finché non riprendi",
        noticeNewLayoutDetail: "Calibra per questi schermi",
        noticeCameraDetail: "Lo sguardo è in pausa",
        noticeDriftDetail: "Ricalibra per affinarlo",
        pausedFor: "In pausa · %@",
        pause: "Pausa",
        resume: "Riprendi",
        resumeAnyway: "Riprendi comunque",
        recenter: "Ricentra",
        calibrate: "Calibra",
        calibrateEllipsis: "Calibra…",
        recalibrate: "Ricalibra",
        quickRecenter: "Riallineamento rapido",
        test: "Prova",
        enable: "Attiva",
        openSettings: "Apri Impostazioni",
        allowCamera: "Consenti la fotocamera",
        allowAccessibility: "Consenti Accessibilità",
        retry: "Riprova",
        chooseCamera: "Scegli un’altra fotocamera",
        switchToZones: "Passa alla modalità Zone",
        lastSwitch: "Ultimo cambio %@",
        recentSwitches: "Cambi recenti",
        barPauseFifteenMinutes: "Metti in pausa lo sguardo per 15 minuti",
        barPauseOneHour: "Metti in pausa lo sguardo per 1 ora",
        barPauseUntilTomorrow: "Metti in pausa lo sguardo fino a domani",
        barPauseUntilResumed: "Metti in pausa lo sguardo",
        barResume: "Riprendi lo sguardo",
        barRecenter: "Ricentra lo sguardo",
        barCalibrate: "Calibra lo sguardo",
        barSwitchMode: "Passa lo sguardo alla modalità %@",
        barSettings: "Impostazioni di Focus con lo sguardo",
        barKeywords: "sguardo, occhi, testa, tracciamento della testa, fotocamera, focus, finestra, schermo, zona, pausa, riprendi, ricentra, calibra",
        shortcutPauseResume: "Metti in pausa o riprendi",
        shortcutRecenter: "Ricentra",
        shortcutMode: "Cambia modalità",
        elidesBeforeVowel: false
    )

    static let ja = ForkGlanceStrings(
        featureTitle: "視線フォーカス",
        sectionTitle: "視線",
        searchKeywords: "視線, 目, 頭, ヘッドトラッキング, カメラ, 顔, フォーカス, ウインドウ, 画面, ディスプレイ, ゾーン, キーボード",
        featureOff: "視線フォーカスはオフです",
        statusOff: "オフ",
        statusActive: "アクティブ",
        statusActiveZone: "アクティブ · %@",
        statusStarting: "カメラを起動中…",
        statusCalibrating: "キャリブレーション中…",
        statusCalibratingCount: "キャリブレーション中 · %@",
        statusWaiting: "待機中：%@",
        statusNoFace: "顔が検出されません",
        statusAway: "画面の外を見ています",
        statusPaused: "一時停止中",
        statusPausedUntil: "一時停止中 — %@に再開",
        statusPausedTomorrow: "明日まで一時停止中",
        statusPausedUntilDay: "一時停止中 — %@に再開",
        statusPausedReason: "一時停止中：%@",
        guardTyping: "入力中",
        guardPointer: "マウス操作中",
        guardButtonsOrModifiers: "キーまたはボタンを押下中",
        guardSecureInput: "パスワード入力中",
        guardDictation: "音声入力中",
        guardMenuOrOverview: "メニューまたはMission Control",
        guardIslandOpen: "島を表示中",
        guardOwnPanel: "アプリのウインドウを表示中",
        guardExcludedSource: "切り替え対象外のアプリ",
        guardCalibrating: "キャリブレーション中",
        guardCooldown: "切り替えた直後",
        guardLowConfidence: "視線が不明確",
        pauseUser: "手動",
        pauseLocked: "Macがロック中",
        pauseAsleep: "Macがスリープ中",
        pauseScreensAsleep: "ディスプレイがスリープ中",
        pauseSessionInactive: "セッションがバックグラウンド",
        pauseIdle: "操作なし",
        pauseBattery: "バッテリー駆動",
        pauseLowPower: "低電力モード",
        pauseThermal: "Macが高温",
        pauseCameraBusy: "カメラのプレビューを表示中",
        pauseCall: "ビデオ通話中",
        pauseSingleScreen: "ディスプレイが1台のみ",
        pauseLidClosed: "ふたが閉じている",
        shortUser: "一時停止中",
        shortLocked: "ロック中",
        shortAsleep: "スリープ中",
        shortScreensAsleep: "ディスプレイがスリープ中",
        shortSessionInactive: "バックグラウンドのセッション",
        shortIdle: "アイドル状態",
        shortBattery: "バッテリー",
        shortLowPower: "低電力モード",
        shortThermal: "Macが高温",
        shortCameraBusy: "カメラのプレビュー",
        shortCall: "ビデオ通話",
        shortSingleScreen: "ディスプレイ1台",
        shortLidClosed: "ふたが閉じている",
        singleScreenHint: "ディスプレイが1台のみです。ゾーンモードに切り替えてください",
        unavailableCameraPermission: "カメラへのアクセスが必要です",
        unavailableAccessibility: "アクセシビリティへのアクセスが必要です",
        unavailableNoCamera: "カメラがありません",
        unavailableCameraDisconnected: "カメラの接続が切れました",
        unavailableCameraFailed: "カメラが応答しません",
        shortCameraPermission: "カメラへのアクセス",
        shortAccessibility: "アクセシビリティ",
        shortNoCamera: "カメラが見つかりません",
        shortCameraDisconnected: "カメラ未接続",
        shortCameraFailed: "カメラを使用できません",
        needFirstTime: "キャリブレーションして開始",
        needNewLayout: "このディスプレイ配置用にキャリブレーション",
        needNewCamera: "このカメラ用にキャリブレーション",
        needRemoved: "プロファイルを削除しました。再キャリブレーションしてください",
        shortNeedFirstTime: "キャリブレーション",
        shortNeedNewLayout: "新しい配置",
        shortNeedNewCamera: "新しいカメラ",
        shortNeedRemoved: "プロファイル削除済み",
        zoneWhole: "%@全体",
        zoneLeft: "%@の左ゾーン",
        zoneCenter: "%@の中央ゾーン",
        zoneRight: "%@の右ゾーン",
        zoneTop: "%@の上ゾーン",
        zoneBottom: "%@の下ゾーン",
        zoneTopLeft: "%@の左上",
        zoneTopRight: "%@の右上",
        zoneBottomLeft: "%@の左下",
        zoneBottomRight: "%@の右下",
        zoneWindowOn: "%@上のウインドウ",
        zoneWindowApp: "%@のウインドウ",
        builtInDisplay: "MacBook",
        modeScreens: "画面",
        modeZones: "ゾーン",
        modeWindows: "ウインドウ",
        modeScreensCaption: "ディスプレイごとに1ゾーン。見ているディスプレイにキーボードが追従します。",
        modeZonesCaption: "各ディスプレイをゾーンに分割します。ワイドディスプレイに最適です。",
        modeWindowsCaption: "表示中の各ウインドウが1つのゾーンになります。精度の高いキャリブレーションが必要です。",
        modeSuited: "この配置に適しています",
        modeDiscouraged: "この配置ではこのモードに十分な精度がありません",
        panes: "ペイン（実験的）",
        splitWhole: "全体",
        splitColumns2: "2列",
        splitColumns3: "3列",
        splitRows2: "2行",
        splitGrid2x2: "2×2グリッド",
        gradeExcellent: "非常に良い",
        gradeGood: "良い",
        gradeFair: "普通",
        gradePoor: "不十分",
        calibrationScore: "キャリブレーション：%@",
        calibrationScoreAge: "キャリブレーション：%1$@ · %2$@",
        headOnly: "頭のみ",
        headAndEyes: "頭と目",
        durationFifteenMinutes: "15分間",
        durationOneHour: "1時間",
        durationUntilTomorrow: "明日まで",
        durationUntilResumed: "再開するまで",
        energySaver: "省エネ",
        energyBalanced: "バランス",
        energyReactive: "高応答",
        batterySame: "電源接続時と同じ",
        batterySaver: "省エネ",
        batteryPause: "一時停止",
        callKeepRunning: "続行",
        callPause: "一時停止",
        pointerAuto: "自動",
        pointerStay: "移動しない",
        pointerFollowScreen: "ディスプレイに追従",
        pointerWindowCenter: "ウインドウの中央",
        feedbackNone: "なし",
        feedbackHalo: "ハロー",
        feedbackZone: "ゾーンを点滅",
        islandNever: "しない",
        islandPaused: "一時停止中またはキャリブレーション中",
        islandAlways: "常に（アクティブなゾーン）",
        sensitivityCautious: "慎重",
        sensitivityLively: "機敏",
        never: "しない",
        noticeKindPause: "一時停止と再開",
        noticeKindNewLayout: "新しいディスプレイ配置",
        noticeKindCamera: "カメラを使用できない",
        noticeKindRecenter: "中心の再設定",
        noticeKindCalibrated: "キャリブレーション完了",
        noticeKindDrift: "再キャリブレーションの提案",
        noticePaused: "視線フォーカスを一時停止",
        noticeResumed: "視線フォーカスを再開",
        noticeNewLayout: "新しいディスプレイ配置",
        noticeCameraUnavailable: "カメラを使用できません",
        noticeRecentered: "中心を再設定しました",
        noticeCalibrated: "キャリブレーション完了 · %@",
        noticeDrift: "視線の誤判定が多い",
        noticePausedUntil: "%@に再開",
        noticePausedTomorrow: "明日まで",
        noticePausedIndefinitely: "再開するまで",
        noticeNewLayoutDetail: "これらの画面でキャリブレーション",
        noticeCameraDetail: "視線フォーカスは一時停止中",
        noticeDriftDetail: "再キャリブレーションで改善",
        pausedFor: "一時停止中 · %@",
        pause: "一時停止",
        resume: "再開",
        resumeAnyway: "このまま再開",
        recenter: "中心を再設定",
        calibrate: "キャリブレーション",
        calibrateEllipsis: "キャリブレーション…",
        recalibrate: "再キャリブレーション",
        quickRecenter: "クイック補正",
        test: "テスト",
        enable: "オンにする",
        openSettings: "設定を開く",
        allowCamera: "カメラを許可",
        allowAccessibility: "アクセシビリティを許可",
        retry: "再試行",
        chooseCamera: "別のカメラを選択",
        switchToZones: "ゾーンモードに切り替える",
        lastSwitch: "最後の切り替え：%@",
        recentSwitches: "最近の切り替え",
        barPauseFifteenMinutes: "視線フォーカスを15分間一時停止",
        barPauseOneHour: "視線フォーカスを1時間一時停止",
        barPauseUntilTomorrow: "視線フォーカスを明日まで一時停止",
        barPauseUntilResumed: "視線フォーカスを一時停止",
        barResume: "視線フォーカスを再開",
        barRecenter: "視線フォーカスの中心を再設定",
        barCalibrate: "視線フォーカスをキャリブレーション",
        barSwitchMode: "視線フォーカスを%@モードに切り替える",
        barSettings: "視線フォーカスの設定",
        barKeywords: "視線, 目, 頭, ヘッドトラッキング, カメラ, フォーカス, ウインドウ, 画面, ゾーン, 一時停止, 再開, 中心, キャリブレーション",
        shortcutPauseResume: "一時停止または再開",
        shortcutRecenter: "中心を再設定",
        shortcutMode: "モードを切り替える",
        elidesBeforeVowel: false
    )

    static let ko = ForkGlanceStrings(
        featureTitle: "시선 포커스",
        sectionTitle: "시선",
        searchKeywords: "시선, 눈, 머리, 머리 추적, 카메라, 얼굴, 포커스, 윈도우, 화면, 디스플레이, 영역, 키보드",
        featureOff: "시선 포커스가 꺼져 있습니다",
        statusOff: "끔",
        statusActive: "활성",
        statusActiveZone: "활성 · %@",
        statusStarting: "카메라 시작 중…",
        statusCalibrating: "보정 중…",
        statusCalibratingCount: "보정 중 · %@",
        statusWaiting: "대기 중: %@",
        statusNoFace: "얼굴이 감지되지 않음",
        statusAway: "화면 밖을 보고 있음",
        statusPaused: "일시 정지됨",
        statusPausedUntil: "일시 정지됨 — %@에 재개",
        statusPausedTomorrow: "내일까지 일시 정지됨",
        statusPausedUntilDay: "일시 정지됨 — %@에 재개",
        statusPausedReason: "일시 정지됨: %@",
        guardTyping: "입력 중",
        guardPointer: "마우스 사용 중",
        guardButtonsOrModifiers: "키 또는 버튼 누르는 중",
        guardSecureInput: "암호 입력 중",
        guardDictation: "받아쓰기 중",
        guardMenuOrOverview: "메뉴 또는 미션 컨트롤",
        guardIslandOpen: "아일랜드 열림",
        guardOwnPanel: "앱 윈도우 열림",
        guardExcludedSource: "전환 제외 앱",
        guardCalibrating: "보정 중",
        guardCooldown: "방금 전환함",
        guardLowConfidence: "시선 불확실",
        pauseUser: "사용자 요청",
        pauseLocked: "Mac 잠김",
        pauseAsleep: "Mac 잠자기",
        pauseScreensAsleep: "디스플레이 잠자기",
        pauseSessionInactive: "백그라운드 세션",
        pauseIdle: "활동 없음",
        pauseBattery: "배터리 사용 중",
        pauseLowPower: "저전력 모드",
        pauseThermal: "Mac 과열",
        pauseCameraBusy: "카메라 미리보기 열림",
        pauseCall: "영상 통화 중",
        pauseSingleScreen: "디스플레이 1개뿐",
        pauseLidClosed: "덮개 닫힘",
        shortUser: "일시 정지됨",
        shortLocked: "잠김",
        shortAsleep: "잠자기",
        shortScreensAsleep: "디스플레이 잠자기",
        shortSessionInactive: "백그라운드 세션",
        shortIdle: "유휴 상태",
        shortBattery: "배터리",
        shortLowPower: "저전력 모드",
        shortThermal: "Mac 과열",
        shortCameraBusy: "카메라 미리보기",
        shortCall: "영상 통화",
        shortSingleScreen: "디스플레이 1개",
        shortLidClosed: "덮개 닫힘",
        singleScreenHint: "디스플레이가 1개뿐입니다. 영역 모드로 전환하세요",
        unavailableCameraPermission: "카메라 접근 권한 필요",
        unavailableAccessibility: "손쉬운 사용 권한 필요",
        unavailableNoCamera: "카메라 없음",
        unavailableCameraDisconnected: "카메라 연결 끊김",
        unavailableCameraFailed: "카메라가 응답하지 않습니다",
        shortCameraPermission: "카메라 권한",
        shortAccessibility: "손쉬운 사용",
        shortNoCamera: "카메라를 찾을 수 없음",
        shortCameraDisconnected: "카메라 분리됨",
        shortCameraFailed: "카메라 사용 불가",
        needFirstTime: "시작하려면 보정하세요",
        needNewLayout: "이 디스플레이 배열에 맞게 보정하세요",
        needNewCamera: "이 카메라에 맞게 보정하세요",
        needRemoved: "프로필이 삭제됨: 다시 보정하세요",
        shortNeedFirstTime: "보정",
        shortNeedNewLayout: "새로운 배열",
        shortNeedNewCamera: "새로운 카메라",
        shortNeedRemoved: "프로필 삭제됨",
        zoneWhole: "%@ 전체",
        zoneLeft: "%@ 왼쪽 영역",
        zoneCenter: "%@ 가운데 영역",
        zoneRight: "%@ 오른쪽 영역",
        zoneTop: "%@ 위쪽 영역",
        zoneBottom: "%@ 아래쪽 영역",
        zoneTopLeft: "%@ 왼쪽 위",
        zoneTopRight: "%@ 오른쪽 위",
        zoneBottomLeft: "%@ 왼쪽 아래",
        zoneBottomRight: "%@ 오른쪽 아래",
        zoneWindowOn: "%@ 화면의 윈도우",
        zoneWindowApp: "%@ 윈도우",
        builtInDisplay: "MacBook",
        modeScreens: "화면",
        modeZones: "영역",
        modeWindows: "윈도우",
        modeScreensCaption: "디스플레이마다 영역 하나: 키보드가 보고 있는 디스플레이를 따라갑니다.",
        modeZonesCaption: "각 디스플레이를 여러 영역으로 나눕니다. 와이드 디스플레이에 적합합니다.",
        modeWindowsCaption: "보이는 각 윈도우가 하나의 영역입니다. 정밀한 보정이 필요합니다.",
        modeSuited: "이 배열에 적합",
        modeDiscouraged: "이 배열에서는 이 모드에 충분히 정확하지 않음",
        panes: "패널(실험적)",
        splitWhole: "전체",
        splitColumns2: "2열",
        splitColumns3: "3열",
        splitRows2: "2행",
        splitGrid2x2: "2×2 격자",
        gradeExcellent: "매우 좋음",
        gradeGood: "좋음",
        gradeFair: "보통",
        gradePoor: "부족함",
        calibrationScore: "보정 %@",
        calibrationScoreAge: "보정 %1$@ · %2$@",
        headOnly: "머리만",
        headAndEyes: "머리와 눈",
        durationFifteenMinutes: "15분 동안",
        durationOneHour: "1시간 동안",
        durationUntilTomorrow: "내일까지",
        durationUntilResumed: "재개할 때까지",
        energySaver: "절약",
        energyBalanced: "균형",
        energyReactive: "빠른 반응",
        batterySame: "전원 연결 시와 동일",
        batterySaver: "절약",
        batteryPause: "일시 정지",
        callKeepRunning: "계속",
        callPause: "일시 정지",
        pointerAuto: "자동",
        pointerStay: "이동 안 함",
        pointerFollowScreen: "디스플레이 따라가기",
        pointerWindowCenter: "윈도우 중앙",
        feedbackNone: "없음",
        feedbackHalo: "후광",
        feedbackZone: "영역 깜박임",
        islandNever: "안 함",
        islandPaused: "일시 정지 또는 보정 중",
        islandAlways: "항상(활성 영역)",
        sensitivityCautious: "신중하게",
        sensitivityLively: "민첩하게",
        never: "안 함",
        noticeKindPause: "일시 정지 및 재개",
        noticeKindNewLayout: "새로운 디스플레이 배열",
        noticeKindCamera: "카메라 사용 불가",
        noticeKindRecenter: "중심 재설정",
        noticeKindCalibrated: "보정 완료",
        noticeKindDrift: "재보정 제안",
        noticePaused: "시선 포커스 일시 정지됨",
        noticeResumed: "시선 포커스 재개됨",
        noticeNewLayout: "새로운 디스플레이 배열",
        noticeCameraUnavailable: "카메라 사용 불가",
        noticeRecentered: "중심 재설정됨",
        noticeCalibrated: "보정 완료 · %@",
        noticeDrift: "시선 인식이 자주 틀림",
        noticePausedUntil: "%@에 재개",
        noticePausedTomorrow: "내일까지",
        noticePausedIndefinitely: "재개할 때까지",
        noticeNewLayoutDetail: "이 디스플레이에 맞게 보정하세요",
        noticeCameraDetail: "시선 포커스 일시 정지됨",
        noticeDriftDetail: "다시 보정하여 개선하세요",
        pausedFor: "일시 정지됨 · %@",
        pause: "일시 정지",
        resume: "재개",
        resumeAnyway: "그래도 재개",
        recenter: "중심 재설정",
        calibrate: "보정",
        calibrateEllipsis: "보정…",
        recalibrate: "다시 보정",
        quickRecenter: "빠른 재정렬",
        test: "테스트",
        enable: "켜기",
        openSettings: "설정 열기",
        allowCamera: "카메라 허용",
        allowAccessibility: "손쉬운 사용 허용",
        retry: "다시 시도",
        chooseCamera: "다른 카메라 선택",
        switchToZones: "영역 모드로 전환",
        lastSwitch: "마지막 전환 %@",
        recentSwitches: "최근 전환",
        barPauseFifteenMinutes: "시선 포커스 15분 동안 일시 정지",
        barPauseOneHour: "시선 포커스 1시간 동안 일시 정지",
        barPauseUntilTomorrow: "시선 포커스 내일까지 일시 정지",
        barPauseUntilResumed: "시선 포커스 일시 정지",
        barResume: "시선 포커스 재개",
        barRecenter: "시선 포커스 중심 재설정",
        barCalibrate: "시선 포커스 보정",
        barSwitchMode: "시선 포커스를 %@ 모드로 전환",
        barSettings: "시선 포커스 설정",
        barKeywords: "시선, 눈, 머리, 머리 추적, 카메라, 포커스, 윈도우, 화면, 영역, 일시 정지, 재개, 중심, 보정",
        shortcutPauseResume: "일시 정지 또는 재개",
        shortcutRecenter: "중심 재설정",
        shortcutMode: "모드 전환",
        elidesBeforeVowel: false
    )

    static let uk = ForkGlanceStrings(
        featureTitle: "Фокус поглядом",
        sectionTitle: "Погляд",
        searchKeywords: "погляд, очі, голова, відстеження голови, камера, обличчя, фокус, вікно, екран, монітор, зона, клавіатура",
        featureOff: "Фокус поглядом вимкнено",
        statusOff: "Вимкнено",
        statusActive: "Активно",
        statusActiveZone: "Активно · %@",
        statusStarting: "Запуск камери…",
        statusCalibrating: "Калібрування…",
        statusCalibratingCount: "Калібрування · %@",
        statusWaiting: "Очікування: %@",
        statusNoFace: "Обличчя не виявлено",
        statusAway: "Погляд поза екранами",
        statusPaused: "Призупинено",
        statusPausedUntil: "Призупинено — продовження о %@",
        statusPausedTomorrow: "Призупинено до завтра",
        statusPausedUntilDay: "Призупинено — продовження %@",
        statusPausedReason: "Призупинено: %@",
        guardTyping: "ви друкуєте",
        guardPointer: "миша",
        guardButtonsOrModifiers: "натиснуто клавішу чи кнопку",
        guardSecureInput: "введення пароля",
        guardDictation: "триває диктування",
        guardMenuOrOverview: "меню або Mission Control",
        guardIslandOpen: "острів відкрито",
        guardOwnPanel: "відкрито вікно програми",
        guardExcludedSource: "закріплена програма",
        guardCalibrating: "триває калібрування",
        guardCooldown: "щойно перемкнуто",
        guardLowConfidence: "погляд неясний",
        pauseUser: "на ваш запит",
        pauseLocked: "Mac заблоковано",
        pauseAsleep: "Mac у режимі сну",
        pauseScreensAsleep: "екрани в режимі сну",
        pauseSessionInactive: "сеанс у фоні",
        pauseIdle: "немає активності",
        pauseBattery: "від акумулятора",
        pauseLowPower: "режим енергозбереження",
        pauseThermal: "Mac перегрівся",
        pauseCameraBusy: "відкрито перегляд камери",
        pauseCall: "триває відеодзвінок",
        pauseSingleScreen: "лише один екран",
        pauseLidClosed: "кришку закрито",
        shortUser: "Пауза",
        shortLocked: "Заблоковано",
        shortAsleep: "Режим сну",
        shortScreensAsleep: "Екрани в режимі сну",
        shortSessionInactive: "Сеанс у фоні",
        shortIdle: "Бездіяльність",
        shortBattery: "Акумулятор",
        shortLowPower: "Енергозбереження",
        shortThermal: "Mac перегрівся",
        shortCameraBusy: "Перегляд камери",
        shortCall: "Відеодзвінок",
        shortSingleScreen: "Один екран",
        shortLidClosed: "Кришку закрито",
        singleScreenHint: "Лише один екран: перейдіть у режим «Зони»",
        unavailableCameraPermission: "Потрібен доступ до камери",
        unavailableAccessibility: "Потрібен дозвіл «Доступність»",
        unavailableNoCamera: "Немає камери",
        unavailableCameraDisconnected: "Камеру від’єднано",
        unavailableCameraFailed: "Камера не відповідає",
        shortCameraPermission: "Доступ до камери",
        shortAccessibility: "Доступність",
        shortNoCamera: "Камеру не знайдено",
        shortCameraDisconnected: "Камеру витягнуто",
        shortCameraFailed: "Камера недоступна",
        needFirstTime: "Відкалібруйте, щоб почати",
        needNewLayout: "Відкалібруйте для цього розташування екранів",
        needNewCamera: "Відкалібруйте для цієї камери",
        needRemoved: "Профіль видалено: відкалібруйте знову",
        shortNeedFirstTime: "Відкалібрувати",
        shortNeedNewLayout: "Нове розташування",
        shortNeedNewCamera: "Нова камера",
        shortNeedRemoved: "Профіль видалено",
        zoneWhole: "Весь екран %@",
        zoneLeft: "Ліва зона %@",
        zoneCenter: "Центральна зона %@",
        zoneRight: "Права зона %@",
        zoneTop: "Верхня зона %@",
        zoneBottom: "Нижня зона %@",
        zoneTopLeft: "Лівий верхній кут %@",
        zoneTopRight: "Правий верхній кут %@",
        zoneBottomLeft: "Лівий нижній кут %@",
        zoneBottomRight: "Правий нижній кут %@",
        zoneWindowOn: "Вікно на екрані %@",
        zoneWindowApp: "Вікно %@",
        builtInDisplay: "MacBook",
        modeScreens: "Екрани",
        modeZones: "Зони",
        modeWindows: "Вікна",
        modeScreensCaption: "Одна зона на екран: клавіатура слідує за екраном, на який ви дивитеся.",
        modeZonesCaption: "Кожен екран поділено на зони — ідеально для широкого монітора.",
        modeWindowsCaption: "Кожне видиме вікно — окрема зона. Потрібне точне калібрування.",
        modeSuited: "Підходить для цього розташування",
        modeDiscouraged: "Недостатньо точно для цього режиму за такого розташування",
        panes: "Панелі (експериментально)",
        splitWhole: "Цілком",
        splitColumns2: "2 стовпці",
        splitColumns3: "3 стовпці",
        splitRows2: "2 рядки",
        splitGrid2x2: "Сітка 2×2",
        gradeExcellent: "Відмінно",
        gradeGood: "Добре",
        gradeFair: "Середньо",
        gradePoor: "Недостатньо",
        calibrationScore: "Калібрування %@",
        calibrationScoreAge: "Калібрування %1$@ · %2$@",
        headOnly: "Лише голова",
        headAndEyes: "Голова й очі",
        durationFifteenMinutes: "На 15 хвилин",
        durationOneHour: "На 1 годину",
        durationUntilTomorrow: "До завтра",
        durationUntilResumed: "До продовження",
        energySaver: "Економно",
        energyBalanced: "Збалансовано",
        energyReactive: "Чутливо",
        batterySame: "Як від мережі",
        batterySaver: "Економно",
        batteryPause: "Призупиняти",
        callKeepRunning: "Продовжувати",
        callPause: "Призупиняти",
        pointerAuto: "Автоматично",
        pointerStay: "Не переміщувати",
        pointerFollowScreen: "Слідувати за екраном",
        pointerWindowCenter: "Центр вікна",
        feedbackNone: "Немає",
        feedbackHalo: "Ореол",
        feedbackZone: "Спалах зони",
        islandNever: "Ніколи",
        islandPaused: "Під час паузи чи калібрування",
        islandAlways: "Завжди (активна зона)",
        sensitivityCautious: "Обережно",
        sensitivityLively: "Жваво",
        never: "Ніколи",
        noticeKindPause: "Пауза й продовження",
        noticeKindNewLayout: "Нове розташування екранів",
        noticeKindCamera: "Камера недоступна",
        noticeKindRecenter: "Центрування",
        noticeKindCalibrated: "Калібрування завершено",
        noticeKindDrift: "Порада перекалібрувати",
        noticePaused: "Погляд на паузі",
        noticeResumed: "Погляд продовжено",
        noticeNewLayout: "Нове розташування",
        noticeCameraUnavailable: "Камера недоступна",
        noticeRecentered: "Відцентровано",
        noticeCalibrated: "Відкалібровано · %@",
        noticeDrift: "Погляд часто помиляється",
        noticePausedUntil: "Продовження о %@",
        noticePausedTomorrow: "До завтра",
        noticePausedIndefinitely: "Доки ви не продовжите",
        noticeNewLayoutDetail: "Відкалібруйте ці екрани",
        noticeCameraDetail: "Погляд на паузі",
        noticeDriftDetail: "Відкалібруйте знову",
        pausedFor: "Пауза · %@",
        pause: "Призупинити",
        resume: "Продовжити",
        resumeAnyway: "Усе одно продовжити",
        recenter: "Відцентрувати",
        calibrate: "Відкалібрувати",
        calibrateEllipsis: "Відкалібрувати…",
        recalibrate: "Відкалібрувати знову",
        quickRecenter: "Швидке підлаштування",
        test: "Перевірити",
        enable: "Увімкнути",
        openSettings: "Відкрити налаштування",
        allowCamera: "Дозволити камеру",
        allowAccessibility: "Дозволити «Доступність»",
        retry: "Повторити",
        chooseCamera: "Вибрати іншу камеру",
        switchToZones: "Перейти в режим «Зони»",
        lastSwitch: "Останнє перемикання %@",
        recentSwitches: "Нещодавні перемикання",
        barPauseFifteenMinutes: "Призупинити Фокус поглядом на 15 хвилин",
        barPauseOneHour: "Призупинити Фокус поглядом на 1 годину",
        barPauseUntilTomorrow: "Призупинити Фокус поглядом до завтра",
        barPauseUntilResumed: "Призупинити Фокус поглядом",
        barResume: "Продовжити Фокус поглядом",
        barRecenter: "Відцентрувати Фокус поглядом",
        barCalibrate: "Відкалібрувати Фокус поглядом",
        barSwitchMode: "Фокус поглядом: режим «%@»",
        barSettings: "Налаштування Фокуса поглядом",
        barKeywords: "погляд, очі, голова, відстеження голови, камера, фокус, вікно, екран, зона, пауза, продовжити, центрування, калібрування",
        shortcutPauseResume: "Призупинити чи продовжити",
        shortcutRecenter: "Відцентрувати",
        shortcutMode: "Змінити режим",
        elidesBeforeVowel: false
    )

    static let zhHans = ForkGlanceStrings(
        featureTitle: "目光焦点",
        sectionTitle: "目光",
        searchKeywords: "目光, 视线, 眼睛, 头部, 头部追踪, 摄像头, 面部, 焦点, 窗口, 屏幕, 显示器, 区域, 键盘",
        featureOff: "目光焦点已关闭",
        statusOff: "关闭",
        statusActive: "运行中",
        statusActiveZone: "运行中 · %@",
        statusStarting: "正在启动摄像头…",
        statusCalibrating: "正在校准…",
        statusCalibratingCount: "正在校准 · %@",
        statusWaiting: "等待中：%@",
        statusNoFace: "未检测到面孔",
        statusAway: "目光不在屏幕上",
        statusPaused: "已暂停",
        statusPausedUntil: "已暂停 — %@ 继续",
        statusPausedTomorrow: "暂停到明天",
        statusPausedUntilDay: "已暂停 — %@ 继续",
        statusPausedReason: "已暂停：%@",
        guardTyping: "正在输入",
        guardPointer: "正在使用鼠标",
        guardButtonsOrModifiers: "按住了按键或按钮",
        guardSecureInput: "正在输入密码",
        guardDictation: "正在听写",
        guardMenuOrOverview: "菜单或调度中心",
        guardIslandOpen: "灵动岛已展开",
        guardOwnPanel: "本 App 的窗口已打开",
        guardExcludedSource: "不切换离开的 App",
        guardCalibrating: "正在校准",
        guardCooldown: "刚刚切换",
        guardLowConfidence: "目光不明确",
        pauseUser: "按你的要求",
        pauseLocked: "Mac 已锁定",
        pauseAsleep: "Mac 已睡眠",
        pauseScreensAsleep: "显示器已睡眠",
        pauseSessionInactive: "会话在后台",
        pauseIdle: "无活动",
        pauseBattery: "使用电池",
        pauseLowPower: "低电量模式",
        pauseThermal: "Mac 过热",
        pauseCameraBusy: "摄像头预览已打开",
        pauseCall: "正在视频通话",
        pauseSingleScreen: "只有一个显示器",
        pauseLidClosed: "已合盖",
        shortUser: "已暂停",
        shortLocked: "已锁定",
        shortAsleep: "睡眠中",
        shortScreensAsleep: "显示器睡眠中",
        shortSessionInactive: "后台会话",
        shortIdle: "闲置",
        shortBattery: "电池",
        shortLowPower: "低电量模式",
        shortThermal: "Mac 过热",
        shortCameraBusy: "摄像头预览",
        shortCall: "视频通话",
        shortSingleScreen: "单个显示器",
        shortLidClosed: "已合盖",
        singleScreenHint: "只有一个显示器：请切换到区域模式",
        unavailableCameraPermission: "需要摄像头访问权限",
        unavailableAccessibility: "需要辅助功能权限",
        unavailableNoCamera: "没有摄像头",
        unavailableCameraDisconnected: "摄像头已断开",
        unavailableCameraFailed: "摄像头无响应",
        shortCameraPermission: "摄像头权限",
        shortAccessibility: "辅助功能",
        shortNoCamera: "未找到摄像头",
        shortCameraDisconnected: "摄像头已拔出",
        shortCameraFailed: "摄像头不可用",
        needFirstTime: "校准后即可开始",
        needNewLayout: "请为此显示器排列校准",
        needNewCamera: "请为此摄像头校准",
        needRemoved: "校准档案已删除：请重新校准",
        shortNeedFirstTime: "校准",
        shortNeedNewLayout: "新的排列",
        shortNeedNewCamera: "新的摄像头",
        shortNeedRemoved: "档案已删除",
        zoneWhole: "整个 %@",
        zoneLeft: "%@ 左侧区域",
        zoneCenter: "%@ 中间区域",
        zoneRight: "%@ 右侧区域",
        zoneTop: "%@ 上方区域",
        zoneBottom: "%@ 下方区域",
        zoneTopLeft: "%@ 左上角",
        zoneTopRight: "%@ 右上角",
        zoneBottomLeft: "%@ 左下角",
        zoneBottomRight: "%@ 右下角",
        zoneWindowOn: "%@ 上的窗口",
        zoneWindowApp: "%@ 窗口",
        builtInDisplay: "MacBook",
        modeScreens: "屏幕",
        modeZones: "区域",
        modeWindows: "窗口",
        modeScreensCaption: "每个显示器一个区域：键盘跟随你注视的显示器。",
        modeZonesCaption: "每个显示器划分为多个区域，适合宽屏显示器。",
        modeWindowsCaption: "每个可见窗口都是一个区域。需要精确的校准。",
        modeSuited: "适合此排列",
        modeDiscouraged: "在此排列下精度不足，不适合此模式",
        panes: "窗格（实验性）",
        splitWhole: "整体",
        splitColumns2: "2 列",
        splitColumns3: "3 列",
        splitRows2: "2 行",
        splitGrid2x2: "2×2 网格",
        gradeExcellent: "优秀",
        gradeGood: "良好",
        gradeFair: "一般",
        gradePoor: "不足",
        calibrationScore: "校准 %@",
        calibrationScoreAge: "校准 %1$@ · %2$@",
        headOnly: "仅头部",
        headAndEyes: "头部和眼睛",
        durationFifteenMinutes: "15 分钟",
        durationOneHour: "1 小时",
        durationUntilTomorrow: "直到明天",
        durationUntilResumed: "直到继续",
        energySaver: "节能",
        energyBalanced: "均衡",
        energyReactive: "灵敏",
        batterySame: "与接通电源时相同",
        batterySaver: "节能",
        batteryPause: "暂停",
        callKeepRunning: "继续运行",
        callPause: "暂停",
        pointerAuto: "自动",
        pointerStay: "不移动",
        pointerFollowScreen: "跟随显示器",
        pointerWindowCenter: "窗口中心",
        feedbackNone: "无",
        feedbackHalo: "光晕",
        feedbackZone: "区域闪烁",
        islandNever: "从不",
        islandPaused: "暂停或校准期间",
        islandAlways: "始终（当前区域）",
        sensitivityCautious: "谨慎",
        sensitivityLively: "灵敏",
        never: "从不",
        noticeKindPause: "暂停与继续",
        noticeKindNewLayout: "新的显示器排列",
        noticeKindCamera: "摄像头不可用",
        noticeKindRecenter: "重新居中",
        noticeKindCalibrated: "校准完成",
        noticeKindDrift: "建议重新校准",
        noticePaused: "目光焦点已暂停",
        noticeResumed: "目光焦点已恢复",
        noticeNewLayout: "新的显示器排列",
        noticeCameraUnavailable: "摄像头不可用",
        noticeRecentered: "已重新居中",
        noticeCalibrated: "校准完成 · %@",
        noticeDrift: "目光经常判断错误",
        noticePausedUntil: "%@ 继续",
        noticePausedTomorrow: "直到明天",
        noticePausedIndefinitely: "直到你继续",
        noticeNewLayoutDetail: "请为这些显示器校准",
        noticeCameraDetail: "目光焦点已暂停",
        noticeDriftDetail: "重新校准以提高精度",
        pausedFor: "已暂停 · %@",
        pause: "暂停",
        resume: "继续",
        resumeAnyway: "仍然继续",
        recenter: "重新居中",
        calibrate: "校准",
        calibrateEllipsis: "校准…",
        recalibrate: "重新校准",
        quickRecenter: "快速对齐",
        test: "测试",
        enable: "开启",
        openSettings: "打开设置",
        allowCamera: "允许摄像头",
        allowAccessibility: "允许辅助功能",
        retry: "重试",
        chooseCamera: "选择其他摄像头",
        switchToZones: "切换到区域模式",
        lastSwitch: "上次切换：%@",
        recentSwitches: "最近切换",
        barPauseFifteenMinutes: "将目光焦点暂停 15 分钟",
        barPauseOneHour: "将目光焦点暂停 1 小时",
        barPauseUntilTomorrow: "将目光焦点暂停到明天",
        barPauseUntilResumed: "暂停目光焦点",
        barResume: "继续目光焦点",
        barRecenter: "将目光焦点重新居中",
        barCalibrate: "校准目光焦点",
        barSwitchMode: "将目光焦点切换到%@模式",
        barSettings: "目光焦点设置",
        barKeywords: "目光, 视线, 眼睛, 头部, 头部追踪, 摄像头, 焦点, 窗口, 屏幕, 区域, 暂停, 继续, 居中, 校准",
        shortcutPauseResume: "暂停或继续",
        shortcutRecenter: "重新居中",
        shortcutMode: "切换模式",
        elidesBeforeVowel: false
    )

    static let zhTW = ForkGlanceStrings(
        featureTitle: "目光焦點",
        sectionTitle: "目光",
        searchKeywords: "目光, 視線, 眼睛, 頭部, 頭部追蹤, 相機, 臉部, 焦點, 視窗, 螢幕, 顯示器, 區域, 鍵盤",
        featureOff: "目光焦點已關閉",
        statusOff: "關閉",
        statusActive: "運作中",
        statusActiveZone: "運作中 · %@",
        statusStarting: "正在啟動相機…",
        statusCalibrating: "正在校正…",
        statusCalibratingCount: "正在校正 · %@",
        statusWaiting: "等待中：%@",
        statusNoFace: "未偵測到臉孔",
        statusAway: "目光不在螢幕上",
        statusPaused: "已暫停",
        statusPausedUntil: "已暫停 — %@ 繼續",
        statusPausedTomorrow: "暫停到明天",
        statusPausedUntilDay: "已暫停 — %@ 繼續",
        statusPausedReason: "已暫停：%@",
        guardTyping: "正在輸入",
        guardPointer: "正在使用滑鼠",
        guardButtonsOrModifiers: "按住了按鍵或按鈕",
        guardSecureInput: "正在輸入密碼",
        guardDictation: "正在聽寫",
        guardMenuOrOverview: "選單或指揮中心",
        guardIslandOpen: "動態島已展開",
        guardOwnPanel: "本 App 的視窗已開啟",
        guardExcludedSource: "不切換離開的 App",
        guardCalibrating: "正在校正",
        guardCooldown: "剛剛切換",
        guardLowConfidence: "目光不明確",
        pauseUser: "依你的要求",
        pauseLocked: "Mac 已鎖定",
        pauseAsleep: "Mac 已睡眠",
        pauseScreensAsleep: "螢幕已睡眠",
        pauseSessionInactive: "工作階段在背景",
        pauseIdle: "無活動",
        pauseBattery: "使用電池",
        pauseLowPower: "低耗電模式",
        pauseThermal: "Mac 過熱",
        pauseCameraBusy: "相機預覽已開啟",
        pauseCall: "正在視訊通話",
        pauseSingleScreen: "只有一個螢幕",
        pauseLidClosed: "已闔上螢幕",
        shortUser: "已暫停",
        shortLocked: "已鎖定",
        shortAsleep: "睡眠中",
        shortScreensAsleep: "螢幕睡眠中",
        shortSessionInactive: "背景工作階段",
        shortIdle: "閒置",
        shortBattery: "電池",
        shortLowPower: "低耗電模式",
        shortThermal: "Mac 過熱",
        shortCameraBusy: "相機預覽",
        shortCall: "視訊通話",
        shortSingleScreen: "單一螢幕",
        shortLidClosed: "已闔上螢幕",
        singleScreenHint: "只有一個螢幕：請切換為區域模式",
        unavailableCameraPermission: "需要相機取用權限",
        unavailableAccessibility: "需要輔助使用權限",
        unavailableNoCamera: "沒有相機",
        unavailableCameraDisconnected: "相機已中斷連線",
        unavailableCameraFailed: "相機沒有回應",
        shortCameraPermission: "相機權限",
        shortAccessibility: "輔助使用",
        shortNoCamera: "找不到相機",
        shortCameraDisconnected: "相機已拔除",
        shortCameraFailed: "無法使用相機",
        needFirstTime: "請先校正再開始使用",
        needNewLayout: "請為此螢幕排列方式校正",
        needNewCamera: "請為此相機校正",
        needRemoved: "校正檔案已刪除：請重新校正",
        shortNeedFirstTime: "校正",
        shortNeedNewLayout: "新的排列方式",
        shortNeedNewCamera: "新的相機",
        shortNeedRemoved: "檔案已刪除",
        zoneWhole: "整個 %@",
        zoneLeft: "%@ 左側區域",
        zoneCenter: "%@ 中間區域",
        zoneRight: "%@ 右側區域",
        zoneTop: "%@ 上方區域",
        zoneBottom: "%@ 下方區域",
        zoneTopLeft: "%@ 左上角",
        zoneTopRight: "%@ 右上角",
        zoneBottomLeft: "%@ 左下角",
        zoneBottomRight: "%@ 右下角",
        zoneWindowOn: "%@ 上的視窗",
        zoneWindowApp: "%@ 視窗",
        builtInDisplay: "MacBook",
        modeScreens: "螢幕",
        modeZones: "區域",
        modeWindows: "視窗",
        modeScreensCaption: "每個螢幕一個區域：鍵盤跟隨你注視的螢幕。",
        modeZonesCaption: "每個螢幕分成多個區域，適合寬螢幕。",
        modeWindowsCaption: "每個可見視窗都是一個區域。需要精確的校正。",
        modeSuited: "適合此排列方式",
        modeDiscouraged: "在此排列方式下精確度不足，不適合此模式",
        panes: "窗格（實驗性）",
        splitWhole: "整體",
        splitColumns2: "2 欄",
        splitColumns3: "3 欄",
        splitRows2: "2 列",
        splitGrid2x2: "2×2 格線",
        gradeExcellent: "優異",
        gradeGood: "良好",
        gradeFair: "普通",
        gradePoor: "不足",
        calibrationScore: "校正 %@",
        calibrationScoreAge: "校正 %1$@ · %2$@",
        headOnly: "僅頭部",
        headAndEyes: "頭部和眼睛",
        durationFifteenMinutes: "15 分鐘",
        durationOneHour: "1 小時",
        durationUntilTomorrow: "直到明天",
        durationUntilResumed: "直到繼續",
        energySaver: "節能",
        energyBalanced: "平衡",
        energyReactive: "靈敏",
        batterySame: "與接上電源時相同",
        batterySaver: "節能",
        batteryPause: "暫停",
        callKeepRunning: "繼續運作",
        callPause: "暫停",
        pointerAuto: "自動",
        pointerStay: "不移動",
        pointerFollowScreen: "跟隨螢幕",
        pointerWindowCenter: "視窗中央",
        feedbackNone: "無",
        feedbackHalo: "光暈",
        feedbackZone: "區域閃爍",
        islandNever: "永不",
        islandPaused: "暫停或校正期間",
        islandAlways: "永遠（目前區域）",
        sensitivityCautious: "謹慎",
        sensitivityLively: "靈敏",
        never: "永不",
        noticeKindPause: "暫停與繼續",
        noticeKindNewLayout: "新的螢幕排列方式",
        noticeKindCamera: "無法使用相機",
        noticeKindRecenter: "重新置中",
        noticeKindCalibrated: "校正完成",
        noticeKindDrift: "建議重新校正",
        noticePaused: "目光焦點已暫停",
        noticeResumed: "目光焦點已繼續",
        noticeNewLayout: "新的螢幕排列方式",
        noticeCameraUnavailable: "無法使用相機",
        noticeRecentered: "已重新置中",
        noticeCalibrated: "校正完成 · %@",
        noticeDrift: "目光經常判斷錯誤",
        noticePausedUntil: "%@ 繼續",
        noticePausedTomorrow: "直到明天",
        noticePausedIndefinitely: "直到你繼續",
        noticeNewLayoutDetail: "請為這些螢幕校正",
        noticeCameraDetail: "目光焦點已暫停",
        noticeDriftDetail: "重新校正以提高精確度",
        pausedFor: "已暫停 · %@",
        pause: "暫停",
        resume: "繼續",
        resumeAnyway: "仍要繼續",
        recenter: "重新置中",
        calibrate: "校正",
        calibrateEllipsis: "校正…",
        recalibrate: "重新校正",
        quickRecenter: "快速對齊",
        test: "測試",
        enable: "開啟",
        openSettings: "開啟設定",
        allowCamera: "允許相機",
        allowAccessibility: "允許輔助使用",
        retry: "再試一次",
        chooseCamera: "選擇其他相機",
        switchToZones: "切換為區域模式",
        lastSwitch: "上次切換：%@",
        recentSwitches: "最近切換",
        barPauseFifteenMinutes: "將目光焦點暫停 15 分鐘",
        barPauseOneHour: "將目光焦點暫停 1 小時",
        barPauseUntilTomorrow: "將目光焦點暫停到明天",
        barPauseUntilResumed: "暫停目光焦點",
        barResume: "繼續目光焦點",
        barRecenter: "將目光焦點重新置中",
        barCalibrate: "校正目光焦點",
        barSwitchMode: "將目光焦點切換為%@模式",
        barSettings: "目光焦點設定",
        barKeywords: "目光, 視線, 眼睛, 頭部, 頭部追蹤, 相機, 焦點, 視窗, 螢幕, 區域, 暫停, 繼續, 置中, 校正",
        shortcutPauseResume: "暫停或繼續",
        shortcutRecenter: "重新置中",
        shortcutMode: "切換模式",
        elidesBeforeVowel: false
    )

    static let zhHK = ForkGlanceStrings(
        featureTitle: "目光焦點",
        sectionTitle: "目光",
        searchKeywords: "目光, 視線, 眼睛, 頭部, 頭部追蹤, 相機, 臉部, 焦點, 視窗, 螢幕, 顯示器, 區域, 鍵盤",
        featureOff: "目光焦點已關閉",
        statusOff: "關閉",
        statusActive: "運作中",
        statusActiveZone: "運作中 · %@",
        statusStarting: "正在啟動相機…",
        statusCalibrating: "正在校正…",
        statusCalibratingCount: "正在校正 · %@",
        statusWaiting: "等待中：%@",
        statusNoFace: "未偵測到臉孔",
        statusAway: "目光不在螢幕上",
        statusPaused: "已暫停",
        statusPausedUntil: "已暫停 — %@ 繼續",
        statusPausedTomorrow: "暫停至明天",
        statusPausedUntilDay: "已暫停 — %@ 繼續",
        statusPausedReason: "已暫停：%@",
        guardTyping: "正在輸入",
        guardPointer: "正在使用滑鼠",
        guardButtonsOrModifiers: "按住了按鍵或按鈕",
        guardSecureInput: "正在輸入密碼",
        guardDictation: "正在聽寫",
        guardMenuOrOverview: "選單或指揮中心",
        guardIslandOpen: "動態島已展開",
        guardOwnPanel: "本 App 的視窗已開啟",
        guardExcludedSource: "不切換離開的 App",
        guardCalibrating: "正在校正",
        guardCooldown: "剛剛切換",
        guardLowConfidence: "目光不明確",
        pauseUser: "按你的要求",
        pauseLocked: "Mac 已鎖定",
        pauseAsleep: "Mac 已睡眠",
        pauseScreensAsleep: "顯示器已睡眠",
        pauseSessionInactive: "工作階段在背景",
        pauseIdle: "沒有活動",
        pauseBattery: "使用電池",
        pauseLowPower: "低耗電模式",
        pauseThermal: "Mac 過熱",
        pauseCameraBusy: "相機預覽已開啟",
        pauseCall: "正在視像通話",
        pauseSingleScreen: "只有一部顯示器",
        pauseLidClosed: "已合上機蓋",
        shortUser: "已暫停",
        shortLocked: "已鎖定",
        shortAsleep: "睡眠中",
        shortScreensAsleep: "顯示器睡眠中",
        shortSessionInactive: "背景工作階段",
        shortIdle: "閒置",
        shortBattery: "電池",
        shortLowPower: "低耗電模式",
        shortThermal: "Mac 過熱",
        shortCameraBusy: "相機預覽",
        shortCall: "視像通話",
        shortSingleScreen: "單一顯示器",
        shortLidClosed: "已合上機蓋",
        singleScreenHint: "只有一部顯示器：請切換至區域模式",
        unavailableCameraPermission: "需要相機取用權限",
        unavailableAccessibility: "需要輔助使用權限",
        unavailableNoCamera: "沒有相機",
        unavailableCameraDisconnected: "相機已中斷連線",
        unavailableCameraFailed: "相機沒有回應",
        shortCameraPermission: "相機權限",
        shortAccessibility: "輔助使用",
        shortNoCamera: "找不到相機",
        shortCameraDisconnected: "相機已拔除",
        shortCameraFailed: "無法使用相機",
        needFirstTime: "請先校正再開始使用",
        needNewLayout: "請為此顯示器排列方式校正",
        needNewCamera: "請為此相機校正",
        needRemoved: "校正檔案已刪除：請重新校正",
        shortNeedFirstTime: "校正",
        shortNeedNewLayout: "新的排列方式",
        shortNeedNewCamera: "新的相機",
        shortNeedRemoved: "檔案已刪除",
        zoneWhole: "整個 %@",
        zoneLeft: "%@ 左側區域",
        zoneCenter: "%@ 中間區域",
        zoneRight: "%@ 右側區域",
        zoneTop: "%@ 上方區域",
        zoneBottom: "%@ 下方區域",
        zoneTopLeft: "%@ 左上角",
        zoneTopRight: "%@ 右上角",
        zoneBottomLeft: "%@ 左下角",
        zoneBottomRight: "%@ 右下角",
        zoneWindowOn: "%@ 上的視窗",
        zoneWindowApp: "%@ 視窗",
        builtInDisplay: "MacBook",
        modeScreens: "螢幕",
        modeZones: "區域",
        modeWindows: "視窗",
        modeScreensCaption: "每部顯示器一個區域：鍵盤跟隨你注視的顯示器。",
        modeZonesCaption: "每部顯示器分成多個區域，適合寬螢幕顯示器。",
        modeWindowsCaption: "每個可見視窗都是一個區域。需要精確的校正。",
        modeSuited: "適合此排列方式",
        modeDiscouraged: "在此排列方式下精確度不足，不適合此模式",
        panes: "窗格（實驗性）",
        splitWhole: "整體",
        splitColumns2: "2 欄",
        splitColumns3: "3 欄",
        splitRows2: "2 列",
        splitGrid2x2: "2×2 格線",
        gradeExcellent: "優異",
        gradeGood: "良好",
        gradeFair: "一般",
        gradePoor: "不足",
        calibrationScore: "校正 %@",
        calibrationScoreAge: "校正 %1$@ · %2$@",
        headOnly: "僅頭部",
        headAndEyes: "頭部和眼睛",
        durationFifteenMinutes: "15 分鐘",
        durationOneHour: "1 小時",
        durationUntilTomorrow: "直至明天",
        durationUntilResumed: "直至繼續",
        energySaver: "節能",
        energyBalanced: "平衡",
        energyReactive: "靈敏",
        batterySame: "與接駁電源時相同",
        batterySaver: "節能",
        batteryPause: "暫停",
        callKeepRunning: "繼續運作",
        callPause: "暫停",
        pointerAuto: "自動",
        pointerStay: "不移動",
        pointerFollowScreen: "跟隨顯示器",
        pointerWindowCenter: "視窗中央",
        feedbackNone: "無",
        feedbackHalo: "光暈",
        feedbackZone: "區域閃爍",
        islandNever: "永不",
        islandPaused: "暫停或校正期間",
        islandAlways: "永遠（目前區域）",
        sensitivityCautious: "謹慎",
        sensitivityLively: "靈敏",
        never: "永不",
        noticeKindPause: "暫停與繼續",
        noticeKindNewLayout: "新的顯示器排列方式",
        noticeKindCamera: "無法使用相機",
        noticeKindRecenter: "重新置中",
        noticeKindCalibrated: "校正完成",
        noticeKindDrift: "建議重新校正",
        noticePaused: "目光焦點已暫停",
        noticeResumed: "目光焦點已繼續",
        noticeNewLayout: "新的顯示器排列方式",
        noticeCameraUnavailable: "無法使用相機",
        noticeRecentered: "已重新置中",
        noticeCalibrated: "校正完成 · %@",
        noticeDrift: "目光經常判斷錯誤",
        noticePausedUntil: "%@ 繼續",
        noticePausedTomorrow: "直至明天",
        noticePausedIndefinitely: "直至你繼續",
        noticeNewLayoutDetail: "請為這些顯示器校正",
        noticeCameraDetail: "目光焦點已暫停",
        noticeDriftDetail: "重新校正以提高精確度",
        pausedFor: "已暫停 · %@",
        pause: "暫停",
        resume: "繼續",
        resumeAnyway: "仍要繼續",
        recenter: "重新置中",
        calibrate: "校正",
        calibrateEllipsis: "校正…",
        recalibrate: "重新校正",
        quickRecenter: "快速對齊",
        test: "測試",
        enable: "開啟",
        openSettings: "開啟設定",
        allowCamera: "允許相機",
        allowAccessibility: "允許輔助使用",
        retry: "再試一次",
        chooseCamera: "選擇其他相機",
        switchToZones: "切換至區域模式",
        lastSwitch: "上次切換：%@",
        recentSwitches: "最近切換",
        barPauseFifteenMinutes: "將目光焦點暫停 15 分鐘",
        barPauseOneHour: "將目光焦點暫停 1 小時",
        barPauseUntilTomorrow: "將目光焦點暫停至明天",
        barPauseUntilResumed: "暫停目光焦點",
        barResume: "繼續目光焦點",
        barRecenter: "將目光焦點重新置中",
        barCalibrate: "校正目光焦點",
        barSwitchMode: "將目光焦點切換至%@模式",
        barSettings: "目光焦點設定",
        barKeywords: "目光, 視線, 眼睛, 頭部, 頭部追蹤, 相機, 焦點, 視窗, 螢幕, 區域, 暫停, 繼續, 置中, 校正",
        shortcutPauseResume: "暫停或繼續",
        shortcutRecenter: "重新置中",
        shortcutMode: "切換模式",
        elidesBeforeVowel: false
    )
}
