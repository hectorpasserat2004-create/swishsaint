// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import SwiftUI

extension ForkMacBackupPresentation.Tone {
    /// The tone as the island paints it.
    var color: Color {
        switch self {
        case .calm: return .white.opacity(0.55)
        case .teal: return .teal
        case .orange: return .orange
        case .red: return Color(nsColor: .systemRed)
        }
    }
}

extension ForkMacBackupPresentation.NodeState {
    var color: Color {
        switch self {
        case .ok: return .green
        case .slow: return .orange
        case .broken: return Color(nsColor: .systemRed)
        case .unknown: return .white.opacity(0.3)
        }
    }

    func title(_ text: ForkMacBackupStrings) -> String {
        switch self {
        case .ok: return text.nodeOK
        case .slow: return text.nodeSlow
        case .broken: return text.nodeBroken
        case .unknown: return text.nodeUnknown
        }
    }
}

/// The section's ring: the freshness at rest (full right after a backup,
/// empty when the next is due), the bytes while something runs, a turning
/// arc while nothing honest can be said. In its middle the age (« 2 h »),
/// the percentage, or the step's mark. Reduce Motion: no turning, no
/// sliding, the arc still at its place.
struct ForkMacBackupIslandHeroRing: View {
    /// 0…1; nil: the turning arc.
    let progress: Double?
    let tint: Color
    /// The middle's words, rolling as they change; nil: `symbol`.
    let value: String?
    let symbol: String?
    /// The middle mark's own colour, when not the ring's.
    var symbolTint: Color? = nil
    var side: CGFloat = 52
    /// Turning while nil (something runs) rather than an empty ring (rest).
    var turnsWhenUnknown = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turning = false

    var body: some View {
        let line: CGFloat = 5
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: line)
            if let progress {
                Circle()
                    .trim(from: 0, to: max(0.015, min(1, progress)))
                    .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: progress)
            } else if turnsWhenUnknown {
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(turning ? 270 : -90))
                    .animation(reduceMotion ? nil : .linear(duration: 1.1).repeatForever(autoreverses: false),
                               value: turning)
                    .onAppear { turning = !reduceMotion }
            }
            Group {
                if let value {
                    Text(value)
                        .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .padding(.horizontal, line + 3)
                        .modifier(NotchRollingDigits(value: value, countsDown: false, everySecond: false))
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(symbolTint ?? tint)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .id(value == nil ? (symbol ?? "") : "value")
            .transition(.blurReplace)
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: value == nil)
        }
        .padding(line / 2)
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// The proof ladder (plan §5.1): four dots joined by a line, filled in
/// sarcelle up to the level reached, « Present, Complete, Verified,
/// Restored ».
struct ForkMacBackupIslandProofLadder: View {
    let level: ForkMacBackupProofLevel?
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let filled = ForkMacBackupIslandRules.proofDots(level)
        let text = ForkMacBackupStrings.strings(l10n.language)
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                if index > 0 {
                    Capsule()
                        .fill(index < filled ? Color.teal.opacity(0.8) : Color.white.opacity(0.18))
                        .frame(width: 4, height: 1.5)
                }
                Circle()
                    .fill(index < filled ? Color.teal : Color.white.opacity(0.18))
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: ForkMacBackupIslandStrings.strings(l10n.language).proofSpoken,
                                   level?.title(text) ?? text.never))
        .help(ForkMacBackupProofLevel.allCases.map { $0.title(text) }.joined(separator: " → "))
    }
}

/// The chain (plan §8): one dot per node, green, orange, red or grey, its
/// name beside it where the row has room. A hover names the node with its
/// state and latency (`hovered`); a click opens the window's Health tab.
struct ForkMacBackupIslandChain: View {
    let chain: [ForkMacBackupPresentation.ChainStatus]
    @Binding var hovered: String?
    let open: () -> Void
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let text = ForkMacBackupStrings.strings(l10n.language)
        Button(action: open) {
            ViewThatFits(in: .horizontal) {
                row(text, named: true)
                row(text, named: false)
            }
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 8, lifts: false))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: ForkMacBackupIslandStrings.strings(l10n.language).chainSpoken,
                                   chain.map { "\($0.displayTitle(text)), \($0.state.title(text))" }
                                    .joined(separator: "; ")))
        .accessibilityHint(ForkMacBackupIslandStrings.strings(l10n.language).chainHint)
        .accessibilityAddTraits(.isButton)
    }

    private func row(_ text: ForkMacBackupStrings, named: Bool) -> some View {
        HStack(spacing: named ? 5 : 4) {
            ForEach(Array(chain.enumerated()), id: \.element.id) { index, node in
                if index > 0 {
                    Capsule()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: named ? 6 : 8, height: 1)
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(node.state.color)
                        .frame(width: 7, height: 7)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: node.state)
                    if named {
                        Text(node.displayTitle(text))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(hovered == node.id ? 0.95 : 0.6))
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { hovered = node.id } else if hovered == node.id { hovered = nil }
                }
                .help("\(node.displayTitle(text)) · \(node.state.title(text))")
            }
        }
        .padding(.horizontal, 4)
        .fixedSize()
    }

    /// « MinIO · En ligne · 18 ms » for the node under the pointer.
    static func label(_ node: ForkMacBackupPresentation.ChainStatus, text: ForkMacBackupStrings) -> String {
        var parts = [node.displayTitle(text), node.state.title(text)]
        if let latency = node.latencyMs, node.state != .broken { parts.append("\(latency) ms") }
        return parts.joined(separator: " · ")
    }
}

/// While a view shows live progress, the agent publishes every second
/// (`beginLiveViewing`); never in the Settings preview.
struct ForkMacBackupLiveLease: ViewModifier {
    let status: ForkMacBackupStatusModel
    let active: Bool
    @Environment(\.notchSettingsPreview) private var preview
    @State private var holding = false

    func body(content: Content) -> some View {
        content
            .onAppear { update(active) }
            .onChange(of: active) { _, value in update(value) }
            .onDisappear { update(false) }
    }

    private func update(_ wanted: Bool) {
        let wanted = wanted && !preview
        guard wanted != holding else { return }
        holding = wanted
        if wanted { status.beginLiveViewing() } else { status.endLiveViewing() }
    }
}
