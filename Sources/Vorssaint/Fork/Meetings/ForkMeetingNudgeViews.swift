// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import SwiftUI

// MARK: Finish D

/// A nudged offer draws the eye once: the card springs in and its red ring
/// pulses a few times, then stays lit. With Reduce Motion, the ring is
/// simply there.
struct ForkMeetingAttention: ViewModifier {
    let on: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = false
    @State private var settled = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(on && !reduceMotion && !settled ? 0.94 : 1)
            .overlay {
                if on {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(nsColor: .systemRed).opacity(lit ? 0.9 : 0.4), lineWidth: 2)
                        .shadow(color: Color(nsColor: .systemRed).opacity(lit && !reduceMotion ? 0.55 : 0),
                                radius: lit ? 8 : 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onAppear(perform: draw)
            .onChange(of: on) { _, _ in draw() }
    }

    private func draw() {
        guard on else {
            lit = false
            settled = false
            return
        }
        guard !reduceMotion else {
            lit = true
            settled = true
            return
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { settled = true }
        withAnimation(.easeInOut(duration: 0.55).repeatCount(5, autoreverses: true)) { lit = true }
    }
}

/// "→ ● Record": the arrow nudges toward the button three times.
struct ForkMeetingNudgeArrow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pushed = false

    var body: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color(nsColor: .systemRed))
            .offset(x: pushed ? 3 : 0)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.4).repeatCount(6, autoreverses: true)) { pushed = true }
            }
    }
}

/// "+4 min 12 s already kept", a second at a time.
struct ForkMeetingKeptText: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            Text(ForkMeetingLookbackText.kept(since: since, now: context.date, strings: .current))
        }
    }
}

/// The Meetings page's two choices for a forgotten recording, under the
/// detection's: the offer back when the meeting really starts, and the
/// last 5 minutes kept in memory.
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
