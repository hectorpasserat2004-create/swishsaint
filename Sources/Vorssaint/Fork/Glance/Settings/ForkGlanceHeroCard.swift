// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import SwiftUI

/// The page's drawing (plan §12.1): a head turns from one screen to the
/// other and the halo follows to the window there. A 4 s loop, still under
/// Reduce Motion; grey while the feature is off. Shapes only, no image.
struct ForkGlanceHeroCard: View {
    var isOn: Bool
    /// Seconds of each half of the loop.
    static let beat: TimeInterval = 2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(isOn: Bool) {
        self.isOn = isOn
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.beat)) { context in
            let right = reduceMotion || !isOn ? false
                : Int(context.date.timeIntervalSinceReferenceDate / Self.beat) % 2 == 1
            ForkGlanceHeroDrawing(lookingRight: right, tint: isOn ? .accentColor : .secondary)
                .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.82), value: right)
        }
        .frame(width: 176, height: 108)
        .accessibilityHidden(true)
    }
}

/// One frame of the drawing, in a fixed 176 × 108 space.
private struct ForkGlanceHeroDrawing: View {
    let lookingRight: Bool
    let tint: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            screen(x: 4, width: 96, height: 50, windows: [CGRect(x: 6, y: 7, width: 40, height: 34),
                                                         CGRect(x: 50, y: 7, width: 40, height: 34)],
                   lit: lookingRight ? nil : 0)
            screen(x: 108, width: 64, height: 42, windows: [CGRect(x: 6, y: 6, width: 52, height: 28)],
                   lit: lookingRight ? 0 : nil)
            // Where the head looks: a faint cone toward the lit window.
            Path { path in
                path.move(to: CGPoint(x: 88, y: 80))
                path.addLine(to: CGPoint(x: lookingRight ? 140 : 32, y: 44))
            }
            .stroke(tint.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [2, 3]))
            head
                .offset(x: 72, y: 72)
        }
        .frame(width: 176, height: 108, alignment: .topLeading)
    }

    private func screen(x: CGFloat, width: CGFloat, height: CGFloat, windows: [CGRect], lit: Int?) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1.2)
                }
                .frame(width: width, height: height)
            ForEach(windows.indices, id: \.self) { index in
                let frame = windows[index]
                let isLit = lit == index
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(isLit ? tint.opacity(0.16) : Color.primary.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(isLit ? tint : Color.primary.opacity(0.15), lineWidth: isLit ? 2 : 0.8)
                            .shadow(color: isLit ? tint.opacity(0.6) : .clear, radius: 3)
                    }
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
            }
            // The stand.
            Rectangle()
                .fill(Color.primary.opacity(0.2))
                .frame(width: 10, height: 6)
                .offset(x: width / 2 - 5, y: height)
        }
        .offset(x: x, y: 4)
    }

    /// A round head whose face turns: the eyes and the nose slide toward the
    /// side it looks at, as a face seen from above the screens would.
    private var head: some View {
        let turn: CGFloat = lookingRight ? 5 : -5
        return ZStack {
            Circle()
                .fill(Color.primary.opacity(0.08))
                .overlay { Circle().strokeBorder(Color.primary.opacity(0.35), lineWidth: 1.2) }
                .frame(width: 32, height: 32)
            HStack(spacing: 7) {
                Circle().frame(width: 3.5, height: 3.5)
                Circle().frame(width: 3.5, height: 3.5)
            }
            .foregroundStyle(Color.primary.opacity(0.7))
            .offset(x: turn, y: -3)
            Capsule()
                .fill(Color.primary.opacity(0.35))
                .frame(width: 2.5, height: 6)
                .offset(x: turn * 1.25, y: 3)
        }
        .frame(width: 32, height: 32)
    }
}
