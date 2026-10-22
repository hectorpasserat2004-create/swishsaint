// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Suite `fork-macbackup-island`: WP Island's pure rules
/// (`MacBackup/Island/Pure/`): which activity shows for which phase and
/// where, what the wings read, the section's lead, the notices at the end of
/// a run, the mascot, the cards, the Command Bar rows, and the island's
/// words in fifteen languages.
enum ForkMacBackupIslandTests {
    static func run(_ suite: TestSuite) {
        activity(suite)
        ordering(suite)
        readings(suite)
        section(suite)
        tile(suite)
        notices(suite)
        mascot(suite)
        cards(suite)
        commandBar(suite)
        strings(suite)
    }

    private static let now = Date(timeIntervalSince1970: 1_792_663_440) // 22/10/2026, a fixed instant

    private static func locale(_ identifier: String, twelveHour: Bool = false) -> Locale {
        var components = Locale.Components(identifier: identifier)
        components.hourCycle = twelveHour ? .oneToTwelve : .zeroToTwentyThree
        return Locale(components: components)
    }

    private static var paris: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return calendar
    }

    private static let allPhases: [ForkMacBackupPhase] = [
        .off, .notConfigured, .ready(next: nil), .waiting(reason: .power, until: nil),
        .waiting(reason: .noDiskAccess, until: nil), .checkingChain, .preparing, .scanning, .uploading, .slowed,
        .paused(until: nil), .concluding, .finished(.complete), .finished(.partial(files: 2)),
        .finished(.failed(.chainBroken)), .finished(.nothingToDo), .restoring, .verifying, .maintaining,
    ]

    // MARK: Closed island

    private static func activity(_ suite: TestSuite) {
        let shown = allPhases.filter {
            ForkMacBackupIslandRules.showsActivity(enabled: true, setting: .running, phase: $0, finishing: false)
        }
        suite.expect(shown == [.checkingChain, .preparing, .scanning, .uploading, .slowed, .concluding, .restoring, .verifying],
                     "the closed island shows a backup, a restore or a verification running, nothing else: \(shown)")
        let late: [ForkMacBackupPhase] = [.waiting(reason: .power, until: nil), .finished(.failed(.chainBroken)),
                                          .finished(.partial(files: 1)), .paused(until: nil), .ready(next: nil)]
        suite.expect(late.allSatisfy {
            !ForkMacBackupIslandRules.showsActivity(enabled: true, setting: .running, phase: $0, finishing: false)
        }, "never a delay, a pause or a problem in the closed island")
        suite.expect(!allPhases.contains {
            ForkMacBackupIslandRules.showsActivity(enabled: true, setting: .never, phase: $0, finishing: false)
        } && !allPhases.contains {
            ForkMacBackupIslandRules.showsActivity(enabled: false, setting: .running, phase: $0, finishing: true)
        }, "« never » and the feature off show nothing")
        suite.expect(ForkMacBackupIslandRules.showsActivity(enabled: true, setting: .running,
                                                           phase: .finished(.complete), finishing: true),
                     "the finished ring stays for its checkmark")

        suite.expect(ForkMacBackupIslandRules.glyph(phase: .uploading, finishing: false) == .upload
                        && ForkMacBackupIslandRules.glyph(phase: .scanning, finishing: false).symbol == "arrow.up"
                        && ForkMacBackupIslandRules.glyph(phase: .restoring, finishing: false).symbol == "arrow.down"
                        && ForkMacBackupIslandRules.glyph(phase: .verifying, finishing: false).symbol == "checkmark.shield"
                        && ForkMacBackupIslandRules.glyph(phase: .finished(.complete), finishing: true) == .done,
                     "the ring's glyph: up for a backup, down for a restore, a shield for a verification, a checkmark at the end")

        let scanning = ForkMacBackupPresentation.preview(.scanning, now: now)
        let running = ForkMacBackupPresentation.preview(.running42, now: now)
        suite.expect(ForkMacBackupIslandRules.ringProgress(scanning, finishing: false) == nil,
                     "the ring turns while scanning: no fake share")
        suite.expect(abs((ForkMacBackupIslandRules.ringProgress(running, finishing: false) ?? 0) - 0.42) < 0.001
                        && ForkMacBackupIslandRules.ringProgress(scanning, finishing: true) == 1,
                     "the ring fills with the bytes, and fully once finished")
    }

    private static func ordering(_ suite: TestSuite) {
        let all: [NotchCompactActivity] = [.meeting, .timer, .watch, .downloads, .agents, .calendar, .music, .keepAwake]
        let ordered = ForkMacBackupIslandRules.ordered(all, showing: true)
        suite.expect(ordered == [.meeting, .timer, .watch, .downloads, .macBackup, .agents, .calendar, .music, .keepAwake],
                     "the backup comes after the downloads, before the agents, the calendar, the music and Keep Awake: \(ordered)")
        suite.expect(ForkMacBackupIslandRules.ordered([.music, .keepAwake], showing: true) == [.macBackup, .music, .keepAwake]
                        && ForkMacBackupIslandRules.ordered([.timer, .music], showing: true) == [.timer, .macBackup, .music]
                        && ForkMacBackupIslandRules.ordered([], showing: true) == [.macBackup],
                     "it takes its place whatever else is up")
        suite.expect(ForkMacBackupIslandRules.ordered([.downloads, .macBackup, .music], showing: false) == [.downloads, .music]
                        && ForkMacBackupIslandRules.ordered([.macBackup, .music], showing: true) == [.macBackup, .music],
                     "it leaves when not shown, and never appears twice")
    }

    private static func readings(_ suite: TestSuite) {
        let text = ForkMacBackupStrings.strings(.fr)
        let fr = locale("fr_FR")
        let running = ForkMacBackupPresentation.preview(.running42, now: now)
        let percent = ForkMacBackupIslandRules.reading(running, text: text, locale: fr, reading: .percent, finishing: false)
        let remaining = ForkMacBackupIslandRules.reading(running, text: text, locale: fr, reading: .remaining, finishing: false)
        suite.expect(percent.hasPrefix("42") && percent.contains("%"), "the right wing reads the percentage: \(percent)")
        suite.expect(remaining.contains("2") && remaining.contains("min"), "or the time left, as chosen: \(remaining)")

        var unstable = running
        unstable.progress?.eta = nil
        let fallback = ForkMacBackupIslandRules.reading(unstable, text: text, locale: fr, reading: .remaining, finishing: false)
        suite.expect(fallback == percent, "no stable time left yet: the percentage, never a guess: \(fallback)")

        let scanning = ForkMacBackupPresentation.preview(.scanning, now: now)
        let scanned = ForkMacBackupIslandRules.reading(scanning, text: text, locale: fr, reading: .percent, finishing: false)
        suite.expect(scanned.contains("220") && !scanned.contains("%"),
                     "no percentage while scanning: the real bytes read so far: \(scanned)")
        var checking = scanning
        checking.phase = .checkingChain
        checking.progress = nil
        suite.expect(ForkMacBackupIslandRules.reading(checking, text: text, locale: fr, reading: .remaining,
                                                      finishing: false) == "…",
                     "nothing to read yet: an ellipsis, never a word too long for the wing")
        let fits = AppLanguage.allCases.allSatisfy { language in
            let words = ForkMacBackupStrings.strings(language)
            return [ForkMacBackupPresentation.Scenario.running42, .scanning, .restoring, .verifying].allSatisfy { scenario in
                ForkMacBackupReading.allCases.allSatisfy { reading in
                    ForkMacBackupIslandRules.reading(.preview(scenario, now: now), text: words,
                                                     locale: Locale(identifier: language.rawValue),
                                                     reading: reading, finishing: false).count <= 8
                }
            }
        }
        suite.expect(fits, "every wing reading stays short in every language")
        suite.expect(ForkMacBackupIslandRules.reading(scanning, text: text, locale: fr, reading: .percent, finishing: true)
                        .hasPrefix("100"), "the finished ring reads 100 %")

        var meeting = running
        meeting.phase = .slowed
        var button = meeting
        button.slowDown = true
        suite.expect(ForkMacBackupIslandRules.readingIsSlowed(meeting) && !ForkMacBackupIslandRules.readingIsSlowed(button)
                        && !ForkMacBackupIslandRules.readingIsSlowed(running),
                     "orange when a meeting slows it, not for the person's own « Ralentir »")
    }

    // MARK: Section

    private static func section(_ suite: TestSuite) {
        suite.expect(ForkMacBackupIslandRules.top(.notConfigured) == .notConfigured
                        && ForkMacBackupIslandRules.top(.scanning) == .running
                        && ForkMacBackupIslandRules.top(.finished(.nothingToDo)) == .rest
                        && ForkMacBackupIslandRules.top(.finished(.partial(files: 3))) == .partial(files: 3)
                        && ForkMacBackupIslandRules.top(.waiting(reason: .power, until: nil)) == .waiting(.power),
                     "each phase leads the section with its own card")
        suite.expect(ForkMacBackupIslandRules.primary(.ready(next: nil)) == .backUpNow
                        && ForkMacBackupIslandRules.primary(.uploading) == .pause
                        && ForkMacBackupIslandRules.primary(.paused(until: nil)) == .resume
                        && ForkMacBackupIslandRules.primary(.waiting(reason: .power, until: nil)) == .backUpAnyway
                        && ForkMacBackupIslandRules.primary(.notConfigured) == .none,
                     "the button beside the camera: back up now, pause, resume or back up anyway")

        suite.expect(ForkMacBackupIslandRules.interval(of: .automatic(about: 7_200)) == 7_200
                        && ForkMacBackupIslandRules.interval(of: .automatic(about: nil)) == 86_400
                        && ForkMacBackupIslandRules.interval(of: .interval(hours: 4)) == 14_400
                        && ForkMacBackupIslandRules.interval(of: .times(["13:00", "21:00"])) == 43_200
                        && ForkMacBackupIslandRules.interval(of: .both(hours: 4, times: ["13:00"])) == 14_400,
                     "the interval the ring measures freshness against")
        let hour: TimeInterval = 3_600
        suite.expect(ForkMacBackupIslandRules.freshness(protectedSince: now, interval: 2 * hour, now: now) == 1
                        && ForkMacBackupIslandRules.freshness(protectedSince: now.addingTimeInterval(-hour),
                                                              interval: 2 * hour, now: now) == 0.5
                        && ForkMacBackupIslandRules.freshness(protectedSince: now.addingTimeInterval(-9 * hour),
                                                              interval: 2 * hour, now: now) == 0
                        && ForkMacBackupIslandRules.freshness(protectedSince: nil, interval: 2 * hour, now: now) == nil
                        && ForkMacBackupIslandRules.freshness(protectedSince: now.addingTimeInterval(-2 * hour),
                                                              nextRun: now.addingTimeInterval(2 * hour),
                                                              interval: 2 * hour, now: now) == 0.5,
                     "the ring at rest is full after a backup and empties toward the next")
        suite.expect(ForkMacBackupIslandRules.freshnessTone(protectedSince: now.addingTimeInterval(-hour), interval: 2 * hour,
                                                            lateHours: 24, now: now) == .teal
                        && ForkMacBackupIslandRules.freshnessTone(protectedSince: now.addingTimeInterval(-5 * hour),
                                                                  interval: 2 * hour, lateHours: 24, now: now) == .orange
                        && ForkMacBackupIslandRules.freshnessTone(protectedSince: now.addingTimeInterval(-30 * hour),
                                                                  interval: 2 * hour, lateHours: 24, now: now) == .red,
                     "sarcelle on time, orange past twice the interval, red past the late threshold (in the section only)")
        suite.expect(ForkMacBackupIslandRules.proofDots(nil) == 0 && ForkMacBackupIslandRules.proofDots(.present) == 1
                        && ForkMacBackupIslandRules.proofDots(.complete) == 2
                        && ForkMacBackupIslandRules.proofDots(.restoreTested) == 4,
                     "the proof ladder fills up to the level reached")

        let calendar = paris
        let tomorrow = ForkMacBackupIslandRules.pauseEnd(.untilTomorrow, now: now, calendar: calendar)
        let parts = tomorrow.map { calendar.dateComponents([.day, .hour, .minute], from: $0) }
        suite.expect(ForkMacBackupIslandRules.pauseEnd(.oneHour, now: now) == now.addingTimeInterval(3_600)
                        && ForkMacBackupIslandRules.pauseEnd(.untilResumed, now: now) == nil
                        && parts?.day == 23 && parts?.hour == 8 && parts?.minute == 0,
                     "pause: an hour, until tomorrow 8:00, or until resumed: \(String(describing: parts))")
        suite.expect(ForkMacBackupIslandRules.sectionHeight("spacious") == 264
                        && ForkMacBackupIslandRules.sectionHeight("compact") == 180
                        && ForkMacBackupIslandRules.sectionHeight(nil) == 180,
                     "the section is 180 pt, or 264 pt spacious")
        let bare = AppLanguage.allCases.map { ForkMacBackupIslandRules.bare(ForkMacBackupStrings.strings($0).running) }
        suite.expect(bare.allSatisfy { !$0.isEmpty && !$0.contains("%") && !$0.hasSuffix("·") && !$0.hasSuffix(" ") }
                        && ForkMacBackupIslandRules.bare(ForkMacBackupStrings.fr.running) == "Sauvegarde",
                     "the card's title without its figure, in every language: \(bare)")
        let frText = ForkMacBackupStrings.fr
        suite.expect(ForkMacBackupIslandRules.heroTitle(ForkMacBackupPresentation.preview(.protected, now: now), text: frText) == "Protégé"
                        && ForkMacBackupIslandRules.heroTitle(ForkMacBackupPresentation.preview(.running42, now: now), text: frText) == "Sauvegarde"
                        && ForkMacBackupIslandRules.heroTitle(ForkMacBackupPresentation.preview(.scanning, now: now), text: frText) == nil,
                     "the ring says the figure, the title never repeats it")

        let fr = locale("fr_FR")
        let today = ForkMacBackupIslandRules.when(now.addingTimeInterval(-2 * hour), now: now, locale: fr, calendar: calendar)
        let old = ForkMacBackupIslandRules.when(now.addingTimeInterval(-6 * 86_400), now: now, locale: fr, calendar: calendar)
        suite.expect(today.lowercased().contains("aujourd") && !old.lowercased().contains("aujourd") && old.contains("oct"),
                     "« aujourd’hui 10:04 », else the day: \(today) / \(old)")
    }

    private static func tile(_ suite: TestSuite) {
        let text = ForkMacBackupStrings.strings(.fr)
        let fr = locale("fr_FR")
        let rest = ForkMacBackupPresentation.preview(.protected, now: now)
        suite.expect(ForkMacBackupIslandRules.tileReading(rest, text: text, locale: fr, reading: .percent, now: now) == nil
                        && ForkMacBackupIslandRules.tileReading(ForkMacBackupPresentation.preview(.failedChainBroken, now: now),
                                                                text: text, locale: fr, reading: .percent, now: now) == nil,
                     "at rest the tile only names the section: the state lives inside it (decision 2)")
        let running = ForkMacBackupIslandRules.tileReading(ForkMacBackupPresentation.preview(.running42, now: now),
                                                           text: text, locale: fr, reading: .percent, now: now)
        suite.expect(running?.hasPrefix("42") == true, "« 42 % » while it runs")
        suite.expect(ForkMacBackupIslandRules.tileReading(ForkMacBackupPresentation.preview(.notConfigured, now: now),
                                                          text: text, locale: fr, reading: .percent, now: now) == nil,
                     "nothing before anything is set up")
        let broken = ForkMacBackupIslandRules.tileAccent(ForkMacBackupPresentation.preview(.failedChainBroken, now: now))
        let busy = ForkMacBackupIslandRules.tileAccent(ForkMacBackupPresentation.preview(.running42, now: now))
        let calm = ForkMacBackupIslandRules.tileAccent(rest)
        suite.expect(!broken.active && !broken.alert && busy.active && !busy.alert && !calm.active,
                     "the tile lights while running, never in red: no alert outside the section (decision 3)")
    }

    // MARK: Notices

    private static func notices(_ suite: TestSuite) {
        suite.expect(ForkMacBackupIslandRules.endedRun(from: .uploading, to: .finished(.complete)) == .complete
                        && ForkMacBackupIslandRules.endedRun(from: .concluding, to: .finished(.partial(files: 1)))
                            == .partial(files: 1)
                        && ForkMacBackupIslandRules.endedRun(from: .checkingChain, to: .finished(.failed(.chainBroken)))
                            == .failed(.chainBroken),
                     "a run that ends is seen from its last step")
        suite.expect(ForkMacBackupIslandRules.endedRun(from: .ready(next: nil), to: .finished(.complete)) == nil
                        && ForkMacBackupIslandRules.endedRun(from: .finished(.complete), to: .finished(.complete)) == nil
                        && ForkMacBackupIslandRules.endedRun(from: .uploading, to: .finished(.nothingToDo)) == nil
                        && ForkMacBackupIslandRules.endedRun(from: .uploading, to: .paused(until: nil)) == nil,
                     "no notice for a state read at rest, nothing to do, or a pause")
        suite.expect(ForkMacBackupIslandRules.endedRestore(from: .restoring, to: .ready(next: nil))
                        && !ForkMacBackupIslandRules.endedRestore(from: .ready(next: nil), to: .restoring),
                     "a restore's end")

        let defaults: (ForkMacBackupNotifyEvent) -> ForkMacBackupNotifyChannel = { $0.defaultChannel }
        suite.expect(ForkMacBackupIslandRules.notice(for: .complete, sent: 3_100_000_000, channel: defaults)
                        == .complete(sent: 3_100_000_000)
                        && ForkMacBackupIslandRules.notice(for: .partial(files: 1), sent: nil, channel: defaults) == nil
                        && ForkMacBackupIslandRules.notice(for: .failed(.chainBroken), sent: nil, channel: defaults) == nil,
                     "by default only the complete backup's notice (decision 3 of 22/10)")
        let all: (ForkMacBackupNotifyEvent) -> ForkMacBackupNotifyChannel = { _ in .both }
        suite.expect(ForkMacBackupIslandRules.notice(for: .partial(files: 2), sent: nil, channel: all) == .partial(files: 2)
                        && ForkMacBackupIslandRules.notice(for: .failed(.authentication), sent: nil, channel: all)
                            == .failed(.authentication)
                        && ForkMacBackupIslandRules.notice(for: .failed(.canceled), sent: nil, channel: all) == nil
                        && ForkMacBackupIslandRules.notice(for: .nothingToDo, sent: nil, channel: all) == nil,
                     "turned on, partial and failed ends are told; a cancel by the person is not")
        let system: (ForkMacBackupNotifyEvent) -> ForkMacBackupNotifyChannel = { _ in .system }
        suite.expect(ForkMacBackupIslandRules.notice(for: .complete, sent: nil, channel: system) == nil,
                     "a system-only channel puts nothing in the island")
        let events: [ForkMacBackupIslandRules.Notice] = [.complete(sent: nil), .partial(files: 1), .failed(.other), .restored(files: 2)]
        suite.expect(events.map(\.event) == [.complete, .partial, .failure, .restoreDone]
                        && Set(events.map(\.symbol)).count == 4,
                     "each notice follows its own key and has its own symbol")
        suite.expect(ForkMacBackupIslandRules.channel("garbage", event: .complete) == .island
                        && ForkMacBackupIslandRules.channel(nil, event: .partial) == ForkMacBackupNotifyChannel.none
                        && ForkMacBackupIslandRules.channel("both", event: .partial) == .both,
                     "an unknown stored channel reads as the default")
        suite.expect(ForkMacBackupIslandRules.channel(.system, island: true) == .both
                        && ForkMacBackupIslandRules.channel(.both, island: false) == .system
                        && ForkMacBackupIslandRules.channel(.island, island: false) == ForkMacBackupNotifyChannel.none
                        && ForkMacBackupIslandRules.channel(.none, island: true) == .island,
                     "the island's switch keeps the system notification the person chose")
    }

    private static func mascot(_ suite: TestSuite) {
        suite.expect(ForkMacBackupIslandRules.mascot(for: .complete, hadComplete: false, failuresBefore: 0) == .celebrate
                        && ForkMacBackupIslandRules.mascot(for: .complete, hadComplete: true, failuresBefore: 0) == nil
                        && ForkMacBackupIslandRules.mascot(for: .complete, hadComplete: true, failuresBefore: 2) == .celebrate
                        && ForkMacBackupIslandRules.mascot(for: .complete, hadComplete: true, failuresBefore: 1) == nil,
                     "it cheers the first complete backup and the end of a series of failures")
        suite.expect(ForkMacBackupIslandRules.mascot(for: .failed(.chainBroken), hadComplete: true, failuresBefore: 0) == .confused
                        && ForkMacBackupIslandRules.mascot(for: .failed(.canceled), hadComplete: true, failuresBefore: 0) == nil
                        && ForkMacBackupIslandRules.mascot(for: .partial(files: 1), hadComplete: true, failuresBefore: 3) == nil,
                     "a failure puzzles it, a cancel does not")
        var count = 0
        for result: ForkMacBackupRunResult in [.failed(.other), .failed(.canceled), .failed(.stalled)] {
            count = ForkMacBackupIslandRules.failures(after: result, before: count)
        }
        suite.expect(count == 2 && ForkMacBackupIslandRules.failures(after: .complete, before: count) == 0,
                     "failures in a row, a cancel aside, cleared by a success")
    }

    // MARK: Cards

    private static func cards(_ suite: TestSuite) {
        var first = ForkMacBackupPresentation.preview(.protected, now: now)
        first.sources[0].last = nil
        first.sources[0].lastComplete = nil
        suite.expect(ForkMacBackupIslandRules.offersFirstBackup(first, offered: []),
                     "the first heavy backup is offered")
        suite.expect(!ForkMacBackupIslandRules.offersFirstBackup(first, offered: [ForkMacBackupIslandRules.offeredFirstBackup])
                        && !ForkMacBackupIslandRules.offersFirstBackup(ForkMacBackupPresentation.preview(.protected, now: now),
                                                                       offered: []),
                     "once, and never after a first backup")
        var light = first
        light.capacity.protectedBytes = 800_000_000
        var running = first
        running.phase = .uploading
        suite.expect(!ForkMacBackupIslandRules.offersFirstBackup(light, offered: [])
                        && !ForkMacBackupIslandRules.offersFirstBackup(running, offered: []),
                     "not for a light one, nor once it runs")

        var bran = ForkMacBackupPresentation.preview(.protected, now: now)
        bran.phase = .waiting(reason: .otherEngine, until: nil)
        suite.expect(ForkMacBackupIslandRules.offersBranStop(bran, branImported: true, offered: [])
                        && !ForkMacBackupIslandRules.offersBranStop(bran, branImported: false, offered: [])
                        && !ForkMacBackupIslandRules.offersBranStop(bran, branImported: true,
                                                                   offered: [ForkMacBackupIslandRules.offeredBran])
                        && !ForkMacBackupIslandRules.offersBranStop(ForkMacBackupPresentation.preview(.protected, now: now),
                                                                   branImported: true, offered: []),
                     "Bran still running after its import is offered once")
        let stored = ForkMacBackupIslandRules.adding("island.bran", to: "kit, island.firstBackup")
        suite.expect(ForkMacBackupIslandRules.offered(stored) == ["kit", "island.firstBackup", "island.bran"]
                        && ForkMacBackupIslandRules.offered(nil).isEmpty,
                     "the offers made are kept with the others: \(stored)")
    }

    // MARK: Command Bar

    private static func commandBar(_ suite: TestSuite) {
        let off = ForkMacBackupIslandRules.barRows(enabled: false, phase: .off, fullDiskAccess: true)
        let unset = ForkMacBackupIslandRules.barRows(enabled: true, phase: .notConfigured, fullDiskAccess: true)
        suite.expect(off.trouble == .featureOff && unset.trouble == .notConfigured && off.backUpNow && !off.pause,
                     "off or not set up: the row still answers and leads to the page")
        let rest = ForkMacBackupIslandRules.barRows(enabled: true, phase: .ready(next: nil), fullDiskAccess: true)
        let running = ForkMacBackupIslandRules.barRows(enabled: true, phase: .uploading, fullDiskAccess: true)
        let paused = ForkMacBackupIslandRules.barRows(enabled: true, phase: .paused(until: nil), fullDiskAccess: true)
        suite.expect(rest.backUpNow && !rest.pause && !rest.resume && rest.verify && rest.trouble == nil,
                     "at rest: back up now and verify")
        suite.expect(!running.backUpNow && running.pause && !running.resume && !running.verify,
                     "running: pause")
        suite.expect(!paused.backUpNow && !paused.pause && paused.resume, "paused: resume")
        let access = ForkMacBackupIslandRules.barRows(enabled: true, phase: .ready(next: nil), fullDiskAccess: false)
        let waits = ForkMacBackupIslandRules.barRows(enabled: true, phase: .waiting(reason: .noDiskAccess, until: now),
                                                     fullDiskAccess: true)
        suite.expect(access.trouble == .diskAccess && waits.trouble == .diskAccess,
                     "without Full Disk Access the rows say so")

        let text = ForkMacBackupStrings.strings(.fr)
        let answer = ForkMacBackupIslandRules.statusAnswer(ForkMacBackupPresentation.preview(.protected, now: now),
                                                           text: text, language: .fr, locale: locale("fr_FR"), now: now)
        suite.expect(answer.hasPrefix("Protégé il y a") && answer.contains("Prochaine"),
                     "the status answer: « Protégé il y a 2 h · Prochaine à 13:00 »: \(answer)")
    }

    // MARK: Words

    private static let longLabels: Set<String> = [
        "sectionSummary", "emptyMessage", "chainSpoken", "chainHint", "seeHint", "activityHint", "closedIslandCaption",
        "noticesCaption", "allSettings", "islandSettings", "firstCaption", "firstCaptionUnknown", "branCaption",
        "barBackUpNow", "barPause", "barResume", "barStatus", "barRestore", "barNotBackedUp", "barVerify", "barKit",
        "barKeywords", "rightWing", "sectionSize",
    ]
    private static let oneForms: Set<String> = ["errorsOne", "restoredOne"]

    private static func fields(_ strings: ForkMacBackupIslandStrings) -> [(String, String)] {
        Mirror(reflecting: strings).children.compactMap { child in
            guard let label = child.label, let value = child.value as? String else { return nil }
            return (label, value)
        }
    }

    private static func placeholders(_ text: String) -> [String] {
        var found: [String] = []
        var rest = Substring(text)
        while let range = rest.range(of: "%") {
            let next = rest[range.upperBound...].prefix(1)
            if next == "@" || next == "d" { found.append("%" + next) }
            rest = rest[range.upperBound...]
        }
        return found
    }

    private static func strings(_ suite: TestSuite) {
        let english = Dictionary(uniqueKeysWithValues: fields(.enUS))
        suite.expect(AppLanguage.allCases.count == 15 && english.count > 60, "fifteen languages, every island word")
        var empty: [String] = []
        var untranslated: [String] = []
        var wrongPlaceholders: [String] = []
        var tooLong: [String] = []
        for language in AppLanguage.allCases {
            for (label, value) in fields(.strings(language)) {
                let tag = "\(language.rawValue).\(label)"
                if value.trimmingCharacters(in: .whitespaces).isEmpty { empty.append(tag) }
                if language != .enUS, value == english[label] { untranslated.append(tag) }
                let expected = placeholders(english[label] ?? "")
                let actual = placeholders(value)
                if actual != expected, !(oneForms.contains(label) && actual == ["%d"]) { wrongPlaceholders.append(tag) }
                let filled = value.replacingOccurrences(of: "%@", with: "18 204").replacingOccurrences(of: "%d", with: "999")
                if !longLabels.contains(label), filled.count > 28 { tooLong.append("\(tag): \(filled)") }
            }
        }
        suite.expect(empty.isEmpty, "every island word exists in every language: \(empty)")
        suite.expect(untranslated.isEmpty, "every island word is really translated: \(untranslated)")
        suite.expect(wrongPlaceholders.isEmpty, "every translation keeps its placeholders: \(wrongPlaceholders)")
        suite.expect(tooLong.isEmpty, "every island word fits in 28 characters: \(tooLong)")

        var typography: [String] = []
        for (label, value) in fields(.fr) {
            let scalars = Array(value.unicodeScalars)
            for (index, scalar) in scalars.enumerated() where ":;!?".unicodeScalars.contains(scalar) {
                if index == 0 || scalars[index - 1] != "\u{00A0}" { typography.append(label) }
            }
            if value.contains("'") || value.contains("« ") || value.contains(" »") { typography.append(label) }
        }
        suite.expect(typography.isEmpty, "French: no-break space before : ; ! ?, typographic apostrophes: \(typography)")

        let ru = ForkMacBackupIslandStrings.strings(.ru)
        let en = ForkMacBackupIslandStrings.strings(.enUS)
        suite.expect(ru.errors(21, language: .ru).contains("21") && ru.errors(21, language: .ru) != ru.errors(25, language: .ru)
                        && en.errors(0, language: .enUS) == "no errors" && en.errors(1, language: .enUS) == "1 error"
                        && en.restored(3, language: .enUS) == "3 files restored",
                     "counts agree in each language")

        // Every notice's title and detail fit the closed island.
        var noticeLong: [String] = []
        for language in AppLanguage.allCases {
            let text = ForkMacBackupStrings.strings(language)
            let island = ForkMacBackupIslandStrings.strings(language)
            let lines = [text.finished, island.noticePartial, text.failed, island.noticeRestore,
                         island.errors(999, language: language), island.restored(999, language: language)]
                + ForkMacBackupRunFailure.allCases.map { $0.title(text) }
            noticeLong += lines.filter { $0.count > 28 }.map { "\(language.rawValue): \($0)" }
        }
        suite.expect(noticeLong.isEmpty, "every notice line fits the island: \(noticeLong)")
    }
}
