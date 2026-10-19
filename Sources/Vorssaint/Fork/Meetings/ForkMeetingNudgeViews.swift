// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import SwiftUI

// MARK: Finish D

/// A nudged offer draws the eye once: the card springs in (in the bubble;
/// the island springs it in itself) and its red ring pulses a few times,
/// then stays lit. With Reduce Motion, the ring is simply there
/// (`ForkMeetingAttentionStyle`). Drawn only: VoiceOver hears the nudge
/// from the machine's announcement, and the card's title says it started.
struct ForkMeetingAttention: ViewModifier {
    let on: Bool
    var inIsland = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = false
    @State private var settled = false

    private var style: ForkMeetingAttentionStyle {
        ForkMeetingAttentionStyle.style(inIsland: inIsland, reduceMotion: reduceMotion)
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(on && style.springs && !settled ? 0.94 : 1)
            .overlay {
                if on {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(nsColor: .systemRed).opacity(lit ? 0.9 : 0.4), lineWidth: 2)
                        .shadow(color: Color(nsColor: .systemRed).opacity(lit && style.pulses ? 0.55 : 0),
                                radius: lit ? 8 : 0)
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
            return
        }
        let style = style
        if style.springs {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { settled = true }
        } else {
            settled = true
        }
        if style.pulses {
            withAnimation(.easeInOut(duration: 0.55).repeatCount(5, autoreverses: true)) { lit = true }
        } else {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { lit = true }
        }
    }
}

/// "→ ● Record": the arrow nudges toward the button three times; still
/// with Reduce Motion.
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
            .onAppear {
                guard ForkMeetingAttentionStyle.style(inIsland: inIsland, reduceMotion: reduceMotion).arrowMoves else {
                    return
                }
                withAnimation(.easeInOut(duration: 0.4).repeatCount(6, autoreverses: true)) { pushed = true }
            }
    }
}

/// "+4 min 12 s already kept", a second at a time.
struct ForkMeetingKeptText: View {
    let since: Date

    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            Text(ForkMeetingLookbackText.kept(since: since, now: context.date, strings: .current))
                .accessibilityLabel(ForkMeetingLookbackText.spokenKept(since: since, now: context.date, strings: .current,
                                                                       language: l10n.language))
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

    var body: some View {
        Toggle(isOn: $nudge) {
            VStack(alignment: .leading, spacing: 2) {
                Text(text.nudgeSetting)
                caption(text.nudgeCaption)
            }
        }
        .onChange(of: nudge) { _, _ in ForkMeetingService.shared.syncListening() }
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
    }

    private func caption(_ string: String) -> some View {
        Text(string)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
