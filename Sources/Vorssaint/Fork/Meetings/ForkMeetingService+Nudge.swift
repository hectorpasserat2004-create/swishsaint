// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import AVFoundation

// MARK: Finish D

/// What listens to an offered meeting, held by the service.
struct ForkMeetingListening {
    var facts = ForkMeetingListenPlan.Facts()
    var plan = ForkMeetingListenPlan()
    var listener: ForkMeetingCallListener?
    /// The app the listener taps, to rebuild it when the meeting's app
    /// changes.
    var appPID: pid_t?
    var lookback: ForkMeetingLookback?
    var nudges = ForkMeetingNudgePlan()
    var locked = false
    var asleep = false
    /// Each nudge sent, for the recipe harness.
    var onNudge: ((ForkMeetingIdentity, Bool) -> Void)?
    /// A harness's stand-in for the app's tap, which must not raise the
    /// system's audio permission prompt; `nil`: the official tap.
    var makeTap: ForkMeetingRecorder.TapMaker?
}

/// "I forget to start the recording": while a detected meeting is offered
/// and left unanswered, its app's level is listened to; when others start
/// talking, the offer comes back (`ForkMeetingMachine.Event.nudge`). With
/// "the last 5 minutes" on, its sound and the microphone are kept in memory
/// meanwhile, and a recording of that meeting begins with them.
///
/// ```
/// refreshState ─► syncListening ─► plan (ForkMeetingListenPlan) ─► listener on / off, kept sound kept / emptied
/// listener (1 s) ─► listeningSecond ─► ForkMeetingNudgePlan ─► send(.nudge)
/// startCapture ─► lookback(for:) ─► recorder ─► writer takes it at the file's zero
/// ```
/// The kept sound is emptied whenever the plan stops keeping it: the call
/// over, "Not now" or "Never", the screen locked, the Mac asleep, the
/// feature or the setting off, the app quitting.
extension ForkMeetingService {
    /// After every run of the machine, a system event, a setting changed.
    func syncListening() {
        let old = listening.facts
        var facts = ForkMeetingListenPlan.Facts()
        facts.nudgeOn = defaults.bool(forKey: ForkDefaultsKey.meetingsNudge)
        facts.lookbackOn = defaults.bool(forKey: ForkDefaultsKey.meetingsLookback)
        facts.offersShown = ForkMeetingNotifyEvent.isOn(.offers, defaults: defaults)
        let candidate = listenedMeeting()
        facts.meeting = isWanted && consentAcknowledged ? candidate?.identity : nil
        facts.nudgesLeft = facts.meeting.map { listening.nudges.wantsMore(for: $0) } ?? false
        facts.locked = listening.locked
        facts.asleep = listening.asleep
        facts.terminating = terminating
        facts.systemAudio = defaults.object(forKey: ForkDefaultsKey.meetingsSystemAudioVerified) as? Bool == true
        // Allowed by macOS, and not turned off on the Meetings page.
        facts.microphoneAllowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            && captureSettings().microphone != ForkMeetingCaptureSettings.microphoneOff
        let plan = ForkMeetingListenPlan.plan(facts)
        listening.facts = facts

        if ForkMeetingListenPlan.clears(from: old, to: facts) || (!plan.keeps && listening.lookback != nil) {
            listening.lookback?.clear()
            listening.lookback = nil
            log.notice("kept sound emptied")
        }
        if facts.meeting == nil { listening.nudges.forget() }
        var keptNew = false
        if plan.keeps, let meeting = facts.meeting, listening.lookback?.meeting != meeting {
            listening.lookback = ForkMeetingLookback(meeting: meeting)
            keptNew = true
        }
        let appPID = candidate.flatMap(listenedPID)
        if plan != listening.plan || old.meeting != facts.meeting || appPID != listening.appPID || keptNew {
            listening.listener?.stop()
            listening.listener = nil
            listening.plan = plan
            listening.appPID = appPID
            if plan.listens, let meeting = facts.meeting {
                let listener = ForkMeetingCallListener(
                    plan: plan, appPID: appPID,
                    microphoneChoice: ForkMeetingMicrophoneChoice(stored: captureSettings().microphone),
                    meetingDevice: meetingMicrophone(for: candidate), lookback: listening.lookback,
                    makeTap: listening.makeTap ?? { await RecorderSystemAudioTap.make(hearing: $0) }
                ) { [weak self] app, microphone in
                    self?.listeningSecond(meeting, app: app, microphone: microphone)
                }
                listening.listener = listener
                listener.start()
                log.notice("listening: app \(plan.app, privacy: .public), microphone \(plan.microphone, privacy: .public), keeps \(plan.keeps, privacy: .public)")
            }
        }
        // "+N already kept" appears on the offer from the moment it keeps.
        if keptNew { presenter.refreshOffer() }
    }

    /// The meeting offered and unanswered, or the one starting from that
    /// offer while its kept sound waits to be taken.
    private func listenedMeeting() -> ForkMeetingCandidate? {
        switch machine.phase {
        case let .offering(offer):
            return offer.candidate
        case let .starting(pending):
            guard let meeting = pending.config.meeting, listening.lookback?.meeting == meeting.identity else { return nil }
            return meeting
        case .idle, .recording, .paused, .stopping, .endingSoon:
            return nil
        }
    }

    /// The process whose sound is the meeting's: its app's, or for a call
    /// no app plays (FaceTime's `avconferenced`), that system process as
    /// the microphone watcher saw it.
    private func listenedPID(_ meeting: ForkMeetingCandidate) -> pid_t? {
        if ForkMeetingAppsSupport.soundOutsideApp(meeting) {
            let system = ForkMeetingProviderTable.current.systemProcessBundles
            return detection.lastMicrophones.first { $0.appBundle == nil && $0.processBundle.map(system.contains) == true }?.pid
        }
        return ForkMeetingAppsSupport.soundPID(
            for: meeting, running: NSRunningApplication.runningApplications(withBundleIdentifier: meeting.appBundle)
                .map(\.processIdentifier))
    }

    /// Once a second from the listener: whether to raise the offer again.
    /// Only an offer left alone counts: folded, or no longer open.
    private func listeningSecond(_ meeting: ForkMeetingIdentity, app: Bool, microphone: Bool) {
        guard case let .offering(offer) = machine.phase, offer.candidate.identity == meeting,
              listening.facts.nudgeOn, offer.collapsed || !presenter.offerIsOpen else { return }
        let source: ForkMeetingNudgePlan.Source = listening.plan.app ? .app : .microphone
        let answer = listening.nudges.second(meeting: meeting, source: source,
                                             speaking: source == .app ? app : microphone,
                                             microphoneOpen: detection.onMicrophone.contains(meeting))
        guard answer.nudge else { return }
        log.notice("others talk: the offer comes back\(answer.last ? " a last time" : "", privacy: .public)")
        listening.onNudge?(meeting, answer.last)
        send(.nudge(meeting))
    }

    /// The kept sound of the meeting a recording starts for, handed to its
    /// engine; `nil` for any other start.
    func lookback(for config: ForkMeetingCaptureConfig) -> ForkMeetingLookback? {
        guard let lookback = listening.lookback, config.meeting?.identity == lookback.meeting else { return nil }
        return lookback
    }

    /// "+4 min 12 s already kept" on the offer, from when.
    func lookbackSince(_ meeting: ForkMeetingIdentity) -> Date? {
        listening.lookback?.meeting == meeting && listening.plan.keeps ? listening.lookback?.since : nil
    }

    /// The screen locked or unlocked, the Mac asleep or awake.
    func listeningEvent(_ event: ForkMeetingSystemEvents.Event) {
        switch event {
        case .locked: listening.locked = true
        case .unlocked: listening.locked = false
        case .willSleep: listening.asleep = true
        case .didWake: listening.asleep = false
        default: return
        }
        syncListening()
    }
}
