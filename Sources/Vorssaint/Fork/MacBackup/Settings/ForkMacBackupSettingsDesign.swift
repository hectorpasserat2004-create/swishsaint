// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import SwiftUI

/// The Settings package's visual vocabulary: teal for the backup (plan §2),
/// orange for « needs a look », red for a broken chain; native controls
/// everywhere else.
enum ForkMacBackupStyle {
    static let accent = Color.teal

    static func color(_ tone: ForkMacBackupPresentation.Tone) -> Color {
        switch tone {
        case .calm: return .secondary
        case .teal: return accent
        case .orange: return .orange
        case .red: return .red
        }
    }

    static func color(_ state: ForkMacBackupPresentation.NodeState) -> Color {
        switch state {
        case .ok: return accent
        case .slow: return .orange
        case .broken: return .red
        case .unknown: return Color(nsColor: .tertiaryLabelColor)
        }
    }

    static func symbol(_ state: ForkMacBackupPresentation.NodeState) -> String {
        switch state {
        case .ok: return "checkmark.circle.fill"
        case .slow: return "tortoise.fill"
        case .broken: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    static func title(_ state: ForkMacBackupPresentation.NodeState, _ shared: ForkMacBackupStrings) -> String {
        switch state {
        case .ok: return shared.nodeOK
        case .slow: return shared.nodeSlow
        case .broken: return shared.nodeBroken
        case .unknown: return shared.nodeUnknown
        }
    }
}

enum ForkMacBackupDay {
    /// « 19 oct. », or « 19 oct. 2025 » in another year.
    static func text(_ date: Date, locale: Locale, now: Date = Date()) -> String {
        let calendar = Calendar.current
        var style = Date.FormatStyle(locale: locale).day().month(.abbreviated)
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) { style = style.year() }
        return date.formatted(style)
    }
}

/// A rounded tile with a white symbol, the System Settings way.
struct ForkMacBackupIconTile: View {
    let symbol: String
    var color: Color = ForkMacBackupStyle.accent
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}

/// One of the page's four rows: icon, title, summary, chevron; the whole row
/// is the button.
struct ForkMacBackupNavigationRow: View {
    let symbol: String
    let color: Color
    let title: String
    let summary: String
    var summaryColor: Color = .secondary
    var badge: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ForkMacBackupIconTile(symbol: symbol, color: color, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(summaryColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(summary)")
        .accessibilityAddTraits(.isButton)
    }
}

/// The four proof dots (plan §5.1), filled in teal up to the level reached.
struct ForkMacBackupProofLadder: View {
    let level: ForkMacBackupProofLevel?
    let shared: ForkMacBackupStrings
    var showsLabels = true

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(ForkMacBackupProofLevel.allCases, id: \.self) { step in
                let reached = level.map { step <= $0 } ?? false
                VStack(spacing: 3) {
                    HStack(spacing: 0) {
                        connector(visible: step != ForkMacBackupProofLevel.allCases.first, filled: reached)
                        Circle()
                            .fill(reached ? ForkMacBackupStyle.accent : Color.clear)
                            .overlay(Circle().strokeBorder(reached ? ForkMacBackupStyle.accent : Color.secondary.opacity(0.5),
                                                           lineWidth: 1.5))
                            .frame(width: 9, height: 9)
                        connector(visible: step != ForkMacBackupProofLevel.allCases.last,
                                  filled: level.map { step < $0 } ?? false)
                    }
                    if showsLabels {
                        Text(step.title(shared))
                            .font(.system(size: 9.5))
                            .foregroundStyle(reached ? .primary : .secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .frame(minWidth: 52)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }

    private func connector(visible: Bool, filled: Bool) -> some View {
        Rectangle()
            .fill(visible ? (filled ? ForkMacBackupStyle.accent : Color.secondary.opacity(0.35)) : .clear)
            .frame(height: 1.5)
            .frame(maxWidth: .infinity)
    }

    private var accessibility: String {
        guard let level else { return shared.never }
        return ForkMacBackupProofLevel.allCases.filter { $0 <= level }.map { $0.title(shared) }.joined(separator: ", ")
    }
}

/// The big round badge of the status card: a ring for a run, a shield at
/// rest, a warning when something is wrong.
struct ForkMacBackupStateBadge: View {
    let presentation: ForkMacBackupPresentation
    var size: CGFloat = 54

    var body: some View {
        let color = ForkMacBackupStyle.color(presentation.tone)
        ZStack {
            Circle()
                .fill(color.opacity(0.13))
            Circle()
                .strokeBorder(color.opacity(0.25), lineWidth: 3)
            if let fraction = presentation.fraction {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(1.5)
            } else if presentation.phase.isBackingUp || presentation.phase.showsInClosedIsland {
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(1.5)
            }
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var symbol: String {
        switch presentation.phase {
        case .off: return "pause.circle"
        case .notConfigured: return "externaldrive.badge.plus"
        case .checkingChain, .preparing, .scanning, .uploading, .slowed, .concluding: return "arrow.up"
        case .restoring: return "arrow.down"
        case .verifying: return "checkmark.shield"
        case .maintaining: return "wrench.and.screwdriver"
        case .paused: return "pause.fill"
        case .waiting: return "hourglass"
        case .finished(.failed): return "exclamationmark.triangle.fill"
        case .finished(.partial): return "exclamationmark.circle"
        case .ready, .finished(.complete), .finished(.nothingToDo):
            switch presentation.tone {
            case .red: return "exclamationmark.triangle.fill"
            case .orange: return "exclamationmark.circle"
            case .teal: return "checkmark.shield.fill"
            case .calm: return "clock.arrow.circlepath"
            }
        }
    }
}

/// A sheet's frame: a header with its icon and a Done button, then a
/// grouped form, the size of the Settings window's own sheets.
struct ForkMacBackupSheetScaffold<Content: View, Footer: View>: View {
    let symbol: String
    var color: Color = ForkMacBackupStyle.accent
    let title: String
    let subtitle: String?
    let done: String
    var width: CGFloat = 600
    var height: CGFloat = 640
    let content: Content
    let footer: Footer

    @Environment(\.dismiss) private var dismiss
    @Environment(\.forkMacBackupSheetHeight) private var heightOverride

    init(symbol: String, color: Color = ForkMacBackupStyle.accent, title: String, subtitle: String? = nil,
         done: String, width: CGFloat = 600, height: CGFloat = 640, @ViewBuilder content: () -> Content,
         @ViewBuilder footer: () -> Footer) {
        self.symbol = symbol
        self.color = color
        self.title = title
        self.subtitle = subtitle
        self.done = done
        self.width = width
        self.height = height
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ForkMacBackupIconTile(symbol: symbol, color: color, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)
            Form {
                content
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                footer
                Spacer()
                Button(done) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: width, height: heightOverride ?? height)
    }
}

/// Offscreen renders only: a taller sheet, so a whole sheet fits one image.
private struct ForkMacBackupSheetHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var forkMacBackupSheetHeight: CGFloat? {
        get { self[ForkMacBackupSheetHeightKey.self] }
        set { self[ForkMacBackupSheetHeightKey.self] = newValue }
    }
}

extension ForkMacBackupSheetScaffold where Footer == EmptyView {
    init(symbol: String, color: Color = ForkMacBackupStyle.accent, title: String, subtitle: String? = nil,
         done: String, width: CGFloat = 600, height: CGFloat = 640, @ViewBuilder content: () -> Content) {
        self.init(symbol: symbol, color: color, title: title, subtitle: subtitle, done: done, width: width, height: height,
                  content: content, footer: { EmptyView() })
    }
}

/// A caption under a control, wrapping.
struct ForkMacBackupCaption: View {
    let text: String
    var color: Color = .secondary

    init(_ text: String, color: Color = .secondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A stacked bar: what is kept (teal) and what is left out (grey).
struct ForkMacBackupSplitBar: View {
    let kept: Int64
    let left: Int64

    var body: some View {
        GeometryReader { geometry in
            let total = max(1, Double(kept + left))
            let keptWidth = geometry.size.width * Double(kept) / total
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(ForkMacBackupStyle.accent.gradient)
                    .frame(width: max(kept > 0 ? 4 : 0, keptWidth - 1))
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.25))
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

/// A stepper row: the title, its value on the right, the arrows.
struct ForkMacBackupStepperRow: View {
    let title: String
    let value: String
    @Binding var number: Int
    let range: ClosedRange<Int>
    var step: Int = 1

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Stepper(title, value: $number, in: range, step: step)
                .labelsHidden()
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(value)
    }
}
