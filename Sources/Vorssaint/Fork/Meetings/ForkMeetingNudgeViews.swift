// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AVFoundation
import SwiftUI

// MARK: Finish D

/// A nudged offer draws the eye once: the card springs in (in the bubble;
/// the island springs it in itself) and its red ring pulses five times with
/// a glow, then stays, quieter, without it. With Reduce Motion, the ring is
/// simply there (`ForkMeetingAttentionStyle`), also when it is turned on
/// mid-pulse. Drawn only: VoiceOver hears the nudge from the machine's
/// announcement, and the card's title says it started.
struct ForkMeetingAttention: ViewModifier {
    let on: Bool
    var inIsland = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = false
    @State private var settled = false
    /// The pulses are over: the glow is off, the ring at rest.
    @State private var calm = false

    /// Five pulses of 0.55 s each way.
    private static let pulse: TimeInterval = 0.55
    private static let pulses = 5

    private var style: ForkMeetingAttentionStyle {
        ForkMeetingAttentionStyle.style(inIsland: inIsland, reduceMotion: reduceMotion)
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(on && style.springs && !settled ? 0.94 : 1)
            .overlay {
                if on {
                    // In the island it follows the card's own panel; in the
                    // bubble, whose card has no panel, it goes out into the
                    // bubble's margin (14, 10 and 12 pt), off the icon and
                    // the buttons, inside its 16 pt corners.
                    RoundedRectangle(cornerRadius: inIsland ? 14 : 12, style: .continuous)
                        .strokeBorder(Color(nsColor: .systemRed).opacity(calm ? 0.6 : lit ? 0.9 : 0.4), lineWidth: 2)
                        .shadow(color: Color(nsColor: .systemRed).opacity(lit && style.pulses && !calm ? 0.55 : 0),
                                radius: lit && !calm ? 8 : 0)
                        .padding(inIsland ? 0 : -7)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onAppear(perform: draw)
            .onChange(of: on) { _, _ in draw() }
            // Reduce Motion turned on mid-pulse: still at once.
            .onChange(of: reduceMotion) { _, _ in draw() }
    }

    private func draw() {
        guard on else {
            lit = false
            settled = false
            calm = false
            return
        }
        let style = style
        if style.springs {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { settled = true }
        } else {
            settled = true
        }
        guard style.pulses else {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                lit = true
                calm = true
            }
            return
        }
        calm = false
        withAnimation(.easeInOut(duration: Self.pulse).repeatCount(Self.pulses, autoreverses: true)) { lit = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pulse * Double(Self.pulses)) {
            withAnimation(.easeOut(duration: 0.3)) { calm = true }
        }
    }
}

/// "→ ● Record": the arrow nudges toward the button three times and comes
/// back to rest; still with Reduce Motion, also turned on meanwhile.
struct ForkMeetingNudgeArrow: View {
    var inIsland = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pushed = false

    var body: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color(nsColor: .systemRed))
            .offset(x: pushed ? 3 : 0)
            .accessibilityHidden(true)
            .onAppear(perform: nudge)
            .onChange(of: reduceMotion) { _, _ in nudge() }
    }

    private func nudge() {
        guard ForkMeetingAttentionStyle.style(inIsland: inIsland, reduceMotion: reduceMotion).arrowMoves else {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { pushed = false }
            return
        }
        // An odd count: it ends pushed, then eases back once.
        withAnimation(.easeInOut(duration: 0.4).repeatCount(5, autoreverses: true)) { pushed = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.4)) { pushed = false }
        }
    }
}

/// "+4 min 12 s already kept", a second at a time, in the card's words.
struct ForkMeetingKeptText: View {
    let kept: ForkMeetingCard.Kept

    var body: some View {
        TimelineView(.periodic(from: kept.since, by: 1)) { context in
            Text(kept.words(context.date))
                .accessibilityLabel(kept.spoken(context.date))
        }
    }
}

/// The Meetings page's two choices for a forgotten recording, in the
/// detection's section right after the apps offered (before the calendar
/// naming and the automatic stop): the offer back when the meeting really
/// starts, and the last 5 minutes kept in memory.
struct ForkMeetingForgetRows: View {
    let text: ForkMeetingStrings
    @AppStorage(ForkDefaultsKey.meetingsNudge) private var nudge = true
    @AppStorage(ForkDefaultsKey.meetingsLookback) private var lookback = false
    @AppStorage(ForkDefaultsKey.meetingsNotifyOffers) private var offers = true
    @AppStorage(ForkDefaultsKey.meetingsSystemAudioVerified) private var systemAudioVerified = false
    @AppStorage(ForkDefaultsKey.meetingsMicrophone) private var microphone = ForkMeetingMicrophoneChoice.fallback.storageValue

    var body: some View {
        Toggle(isOn: $nudge) {
            VStack(alignment: .leading, spacing: 2) {
                Text(text.nudgeSetting)
                caption(text.nudgeCaption)
            }
        }
        .onChange(of: nudge) { _, _ in ForkMeetingService.shared.syncListening() }
        .disabled(!offers)
        // Both rows act through the offer: silenced, neither does anything.
        if !offers {
            Label(text.nudgeOffersOff, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Toggle(isOn: $lookback) {
            VStack(alignment: .leading, spacing: 2) {
                Text(text.lookbackSetting)
                caption(text.lookbackCaption)
            }
        }
        // Turned off, what was kept goes at once.
        .onChange(of: lookback) { _, _ in ForkMeetingService.shared.syncListening() }
        .disabled(!offers)
        if offers, lookback, !canKeep {
            Label(text.lookbackNothingToKeep, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// As `ForkMeetingService.syncListening` decides it.
    private var canKeep: Bool {
        let microphoneAllowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            && microphone != ForkMeetingCaptureSettings.microphoneOff
        return ForkMeetingListenPlan.canKeep(systemAudio: systemAudioVerified, microphoneAllowed: microphoneAllowed)
    }

    private func caption(_ string: String) -> some View {
        Text(string)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
