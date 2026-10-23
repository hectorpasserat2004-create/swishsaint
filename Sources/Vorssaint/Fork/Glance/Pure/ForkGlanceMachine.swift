// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The only place where Glance Focus decides anything (plan §7).
///
/// Like `ForkDictationMachine`, it does nothing itself: it never touches the
/// camera, a window or the screen. It takes an event stamped with the
/// service's clock and returns the effects to run, so every path is a
/// table of timed events in the tests. Being prudent is the design: a
/// missed switch costs a click, a wrong one costs the person's text.
///
/// ```
///  off ◄─ disabled          unavailable ◄─ permission, no camera, camera failure
///                           calibrating ◄─ the assistant runs
///                           paused ◄─ user, Mac state, idle (camera off)
///                           needsCalibration ◄─ no profile for this layout
///  starting ──first image──► settled ──zone Z≠current──► candidate ──held `dwell`──► focus(Z), cooldown 400 ms
///                              ▲  │ between: candidate dropped        │ a guard: blocked (kept, no switch)
///                              │  └─ away: never act                  │ 3rd image without a face: searching
/// ```
///
/// Rules, in the order they apply:
/// - The phase is the first that holds: `off` (feature disabled), then
///   `unavailable` (camera permission, Accessibility, no camera, a camera
///   failure), `calibrating`, `paused` (the reason shown by
///   `ForkGlancePauseReason.shown`), `needsCalibration`, and only then a
///   watching phase. The camera runs exactly in the watching phases: entering
///   one emits `startCamera` and the rate, leaving it emits `stopCamera`.
///   Until the service has sent `.system` and `.calibrationNeed` once, the
///   phase is `starting` with the camera off.
/// - Gazes arrive classified (`Pure/ForkGlanceClassifier`). `.zone(Z)` with Z
///   not the current zone starts a candidate; held without a break for
///   `settings.dwell` with no guard raised, it becomes `focus(zone: Z)`, the
///   current zone moves to Z and a 400 ms cooldown starts. A candidate kept
///   through a guard fires as soon as the guards drop, at the next image or
///   at the guard's deadline. `.between` drops the candidate and keeps the
///   current zone; `.away` drops it too and never acts. Up to two images
///   without a face (`nil` or `.noFace`) are forgiven, the candidate kept but
///   unable to fire; the third makes the phase `searching`.
/// - A gaze on the current zone does nothing, ever. A failed focus gives the
///   keyboard's zone back and is not retried until the gaze leaves that zone.
/// - Pauses (plan §7.5) come from the system snapshot and the idle time
///   (`ForkGlanceGovernor.automaticPauses`), plus the explicit ones
///   (`.pause`): `user`, timed or not, ends at its deadline (`nextDeadline`)
///   or on `.resume(.user)`. `.resumeAnyway` lifts the battery, Low Power
///   and thermal pauses until their condition ends; when it comes back, they
///   pause again.
/// - Notices: `.paused` and `.resumed` for the user pause only (the service
///   knows whether a shortcut asked for it), `.newLayout` when the need
///   becomes `.newLayout`, `.cameraUnavailable` when a camera failure starts
///   or the lid closes over the chosen built-in camera, `.calibrated(score:)`
///   when the assistant finishes. The feedback (halo) is asked for once the
///   service reports the focus succeeded.
struct ForkGlanceMachine {
    /// No new switch this long after one (the `cooldown` guard).
    static let cooldown: TimeInterval = 0.4
    /// Images without a face forgiven before `searching`.
    static let toleratedMisses = 2
    /// Below this confidence, the `lowConfidence` guard holds.
    static let minimumConfidence = 0.5

    private struct Candidate: Equatable {
        var zone: String
        var since: TimeInterval
    }

    private(set) var settings: ForkGlanceSettings
    private(set) var phase: ForkGlancePhase
    /// The zone that has the keyboard: the last switch or `focusChanged`.
    private(set) var currentZone: String?
    /// Raised at the last evaluation, `cooldown` included (diagnostics, trace).
    private(set) var guards: [ForkGlanceGuard] = []
    /// Every pause holding now, the overridden ones excluded.
    private(set) var pauses: Set<ForkGlancePauseReason> = []

    private var system: ForkGlanceSystemSnapshot?
    private var needKnown = false
    private var need: ForkGlanceCalibrationNeed?
    private var failure: ForkGlanceUnavailable?
    private var calibrating = false
    /// `.pause` events, with their end (systemUptime); nil: until resumed.
    private var explicitPauses: [ForkGlancePauseReason: TimeInterval?] = [:]
    /// Lifted by « Reprendre quand même » until their condition ends.
    private var overridden = Set<ForkGlancePauseReason>()
    private var wasLidClosed = false

    private var input = ForkGlanceInputSnapshot.idle
    private var inputKnown = false
    private var lastKey: TimeInterval?
    private var lastPointer: TimeInterval?
    /// Nil until the first `zonesChanged`: any zone id is taken.
    private var zoneIDs: Set<String>?

    private var cameraOn = false
    private var sawImage = false
    private var misses = 0
    private var lastTarget: ForkGlanceGazeTarget?
    /// The last gaze with a face, for `lowConfidence`.
    private var lastSeen: ForkGlanceGaze?
    private var moving = false
    private var candidate: Candidate?
    private var cooldownUntil: TimeInterval?
    private var zoneBeforeSwitch: String?
    private var failedZone: String?

    private var governor = ForkGlanceGovernor()
    private var rate: Double?
    private var lastNow: TimeInterval = -.infinity

    init(settings: ForkGlanceSettings) {
        self.settings = settings
        phase = settings.enabled ? .starting : .off
    }

    /// The next time the machine wants a `.tick`: the end of the dwell, of
    /// the cooldown, of a guard holding a candidate back, of a timed pause,
    /// or the idle cut. Only times after the last event; the service arms one
    /// timer for it.
    var nextDeadline: TimeInterval? {
        var times = explicitPauses.values.compactMap { $0 }
        if cameraOn {
            if let cooldownUntil { times.append(cooldownUntil) }
            if let candidate {
                if misses == 0 { times.append(candidate.since + settings.dwell) }
                if let lastKey { times.append(lastKey + settings.typingPause) }
                if let lastPointer { times.append(lastPointer + settings.pointerPause) }
            }
            if let idleOff = settings.idleOff, let last = lastInput { times.append(last + idleOff) }
        }
        return times.filter { $0 > lastNow }.min()
    }

    @discardableResult
    mutating func handle(_ event: ForkGlanceEvent, now: TimeInterval) -> [ForkGlanceEffect] {
        var notices: [ForkGlanceEffect] = []
        var effects: [ForkGlanceEffect] = []

        switch event {
        case let .gaze(gaze):
            // A late image after the camera was asked to stop.
            guard cameraOn else { return [] }
            see(gaze, now: now)

        case let .zonesChanged(zones):
            let ids = Set(zones.map(\.id))
            zoneIDs = ids
            if let zone = currentZone, !ids.contains(zone) { currentZone = nil }
            if let zone = candidate?.zone, !ids.contains(zone) { candidate = nil }
            if let zone = failedZone, !ids.contains(zone) { failedZone = nil }

        case let .focusChanged(zone):
            currentZone = zone
            failedZone = nil
            if candidate?.zone == zone { candidate = nil }

        case let .inputs(snapshot):
            input = snapshot
            inputKnown = true
            lastKey = snapshot.sinceKey.isFinite ? now - max(0, snapshot.sinceKey) : nil
            lastPointer = snapshot.sincePointer.isFinite ? now - max(0, snapshot.sincePointer) : nil

        case let .system(snapshot):
            system = snapshot
            if snapshot.lidClosedOnBuiltInCamera && !wasLidClosed && settings.enabled {
                notices.append(.notice(.cameraUnavailable))
            }
            wasLidClosed = snapshot.lidClosedOnBuiltInCamera

        case let .settings(newSettings):
            settings = newSettings

        case let .calibrationNeed(newNeed):
            if newNeed == .newLayout && !(needKnown && need == .newLayout) { notices.append(.notice(.newLayout)) }
            needKnown = true
            need = newNeed

        case let .cameraFailure(newFailure):
            if newFailure != nil && failure == nil && settings.enabled { notices.append(.notice(.cameraUnavailable)) }
            failure = newFailure

        case let .pause(reason, until):
            explicitPauses[reason] = .some(until)
            if reason == .user { notices.append(.notice(.paused(until: until))) }

        case let .resume(reason):
            if explicitPauses.removeValue(forKey: reason) != nil && reason == .user {
                notices.append(.notice(.resumed))
            }

        case .resumeAnyway:
            overridden.formUnion(automaticPauses(now: now).filter(\.canResumeAnyway))

        case .calibrationStarted:
            calibrating = true

        case let .calibrationFinished(score):
            calibrating = false
            needKnown = true
            need = nil
            notices.append(.notice(.calibrated(score: score)))

        case .calibrationCancelled:
            calibrating = false

        case let .focusResult(zone, succeeded):
            if succeeded {
                if zone == currentZone && settings.feedback != .none { effects.append(.showFeedback(zone: zone)) }
            } else if zone == currentZone {
                currentZone = zoneBeforeSwitch
                failedZone = zone
                if candidate?.zone == zone { candidate = nil }
            }

        case .tick:
            break
        }

        effects += evaluate(now: now, notices: &notices)
        lastNow = max(lastNow, now)
        return effects + notices
    }

    // MARK: - Images

    private mutating func see(_ gaze: ForkGlanceGaze?, now: TimeInterval) {
        sawImage = true
        moving = (gaze?.headSpeed ?? 0) >= ForkGlanceGovernor.movingSpeed
        var target = gaze?.target ?? .noFace
        if case let .zone(zone) = target, let zoneIDs, !zoneIDs.contains(zone) { target = .between }

        guard target != .noFace else {
            misses += 1
            if misses > Self.toleratedMisses {
                candidate = nil
                lastTarget = .noFace
            }
            return
        }
        misses = 0
        lastTarget = target
        lastSeen = gaze

        switch target {
        case let .zone(zone):
            if zone != failedZone { failedZone = nil }
            if zone == currentZone || zone == failedZone {
                candidate = nil
            } else if candidate?.zone != zone {
                candidate = Candidate(zone: zone, since: now)
            }
        case .between, .away, .noFace:
            candidate = nil
            failedZone = nil
        }
    }

    // MARK: - Evaluation

    private var lastInput: TimeInterval? {
        switch (lastKey, lastPointer) {
        case let (key?, pointer?): return max(key, pointer)
        case let (key?, nil): return key
        case let (nil, pointer?): return pointer
        case (nil, nil): return nil
        }
    }

    private func automaticPauses(now: TimeInterval) -> Set<ForkGlancePauseReason> {
        guard let system else { return [] }
        let sinceInput: TimeInterval = inputKnown ? lastInput.map { now - $0 } ?? .infinity : 0
        return ForkGlanceGovernor.automaticPauses(settings: settings, system: system, sinceInput: sinceInput)
    }

    private var unavailable: ForkGlanceUnavailable? {
        if let system {
            if system.cameraPermission != .granted { return .cameraPermission }
            if !system.accessibility { return .accessibilityPermission }
            if !system.cameraPresent { return .noCamera }
        }
        return failure
    }

    private mutating func evaluate(now: TimeInterval, notices: inout [ForkGlanceEffect]) -> [ForkGlanceEffect] {
        for (reason, until) in explicitPauses {
            guard let until, now >= until else { continue }
            explicitPauses.removeValue(forKey: reason)
            if reason == .user { notices.append(.notice(.resumed)) }
        }
        let automatic = automaticPauses(now: now)
        overridden.formIntersection(automatic)
        pauses = automatic.subtracting(overridden).union(explicitPauses.keys)

        let resting: ForkGlancePhase?
        if !settings.enabled {
            resting = .off
        } else if let unavailable {
            resting = .unavailable(unavailable)
        } else if calibrating {
            resting = .calibrating
        } else if let shown = ForkGlancePauseReason.shown(pauses) {
            resting = .paused(shown, until: explicitPauses[shown] ?? nil)
        } else if system == nil || !needKnown {
            resting = .starting
        } else if let need {
            resting = .needsCalibration(need)
        } else {
            resting = nil
        }

        var effects: [ForkGlanceEffect] = []
        guard resting == nil else {
            if cameraOn {
                cameraOn = false
                effects.append(.stopCamera)
            }
            resetWatching()
            phase = resting ?? .off
            return effects
        }

        if !cameraOn {
            cameraOn = true
            resetWatching()
            governor.reset()
            effects.append(.startCamera)
        }
        guards = raisedGuards(now: now)
        if let candidate, misses == 0, lastTarget == .zone(candidate.zone), guards.isEmpty,
           now >= candidate.since + settings.dwell {
            zoneBeforeSwitch = currentZone
            currentZone = candidate.zone
            self.candidate = nil
            cooldownUntil = now + Self.cooldown
            effects.append(.focus(zone: candidate.zone))
            guards = raisedGuards(now: now)
        }
        phase = watchingPhase(now: now)

        if let system {
            let newRate = governor.rate(settings: settings, system: system, moving: moving, candidate: candidate != nil,
                                        guards: guards, now: now)
            if newRate != rate {
                rate = newRate
                effects.append(.setRate(newRate))
            }
        }
        moving = false
        return effects
    }

    private func raisedGuards(now: TimeInterval) -> [ForkGlanceGuard] {
        var raised = Set<ForkGlanceGuard>()
        if let lastKey, now < lastKey + settings.typingPause { raised.insert(.typing) }
        if let lastPointer, now < lastPointer + settings.pointerPause { raised.insert(.pointer) }
        if input.buttonsDown || input.modifiersDown { raised.insert(.buttonsOrModifiers) }
        if input.secureInput { raised.insert(.secureInput) }
        if input.dictationActive { raised.insert(.dictation) }
        if input.menuOrOverview { raised.insert(.menuOrOverview) }
        if input.islandKey { raised.insert(.islandOpen) }
        if input.ownPanelKey { raised.insert(.ownPanel) }
        if ForkGlanceSettings.list(Array(settings.neverLeaveApps), contains: input.frontmostBundleID) {
            raised.insert(.excludedSource)
        }
        if calibrating { raised.insert(.calibrating) }
        if let cooldownUntil, now < cooldownUntil { raised.insert(.cooldown) }
        if let lastSeen, lastSeen.confidence < Self.minimumConfidence || lastSeen.crowded {
            raised.insert(.lowConfidence)
        }
        return ForkGlanceGuard.allCases.filter(raised.contains)
    }

    private func watchingPhase(now: TimeInterval) -> ForkGlancePhase {
        guard sawImage else { return .starting }
        if lastTarget == .noFace { return .searching }
        if lastTarget == .away { return .away(zone: currentZone) }
        let holding = guards.filter { $0 != .cooldown }
        if candidate != nil && !holding.isEmpty { return .blocked(zone: currentZone, guards: holding) }
        if let cooldownUntil, now < cooldownUntil { return .cooldown(zone: currentZone, until: cooldownUntil) }
        if let candidate { return .candidate(zone: candidate.zone, current: currentZone, since: candidate.since) }
        return .settled(zone: currentZone)
    }

    /// What the images taught is dropped when the camera starts or stops;
    /// the keyboard's zone stays.
    private mutating func resetWatching() {
        sawImage = false
        misses = 0
        lastTarget = nil
        lastSeen = nil
        moving = false
        candidate = nil
        cooldownUntil = nil
        failedZone = nil
        rate = nil
        guards = []
    }
}
