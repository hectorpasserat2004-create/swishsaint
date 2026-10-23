// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import SwiftUI

/// The calibration's target (plan §8.5): a white 14 pt disc in a ring that
/// tightens from 44 to 18 pt while the eyes land, an arc that fills while the
/// samples are kept, then a ✓ that bounces and fades. A point done again
/// shakes. Everything it draws comes from `ForkGlanceDotLook` (pure), which
/// already applies Reduce Motion; the ✓'s bounce follows it too.
struct ForkGlanceTargetDot: View {
    let look: ForkGlanceDotLook

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The arc runs just outside the closed ring.
    private static let arcDiameter: CGFloat = 26

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(0.55), lineWidth: 2)
                .frame(width: look.ring, height: look.ring)
            if look.arc > 0 {
                Circle()
                    .trim(from: 0, to: look.arc)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: Self.arcDiameter, height: Self.arcDiameter)
            }
            if look.check {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.black)
                    .frame(width: ForkGlanceDotLook.dot, height: ForkGlanceDotLook.dot)
                    .background(Circle().fill(Color.white))
                    .symbolEffect(.bounce, value: reduceMotion ? false : look.check)
            } else {
                Circle()
                    .fill(Color.white)
                    .frame(width: ForkGlanceDotLook.dot, height: ForkGlanceDotLook.dot)
                    .shadow(color: .white.opacity(0.5), radius: 6)
            }
        }
        .frame(width: ForkGlanceDotLook.ringOpen, height: ForkGlanceDotLook.ringOpen)
        .offset(x: look.shake)
        .opacity(look.opacity)
        .accessibilityElement()
    }
}
