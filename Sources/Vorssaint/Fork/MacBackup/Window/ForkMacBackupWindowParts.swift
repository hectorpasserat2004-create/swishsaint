// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import SwiftUI

/// The window's colours: teal for what is protected, orange for what needs
/// a look, red for what failed; the system's own greys for the rest.
enum ForkMacBackupWindowStyle {
    static let teal = Color.teal
    static let tealNS = NSColor.systemTeal

    static func color(_ tone: ForkMacBackupPresentation.Tone) -> Color {
        switch tone {
        case .calm: return .secondary
        case .teal: return teal
        case .orange: return .orange
        case .red: return .red
        }
    }

    static func color(_ state: ForkMacBackupPresentation.NodeState) -> Color {
        switch state {
        case .ok: return teal
        case .slow: return .orange
        case .broken: return .red
        case .unknown: return .secondary
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

    /// The SF Symbol of a source's folder.
    static func symbol(forSource path: String) -> String {
        switch (path as NSString).lastPathComponent {
        case "Documents": return "doc"
        case "Desktop", "Bureau": return "menubar.dock.rectangle"
        case "Pictures", "Images": return "photo"
        case "Music", "Musique": return "music.note"
        case "Movies", "Films": return "film"
        case "Downloads", "Téléchargements": return "arrow.down.circle"
        default: return path == NSHomeDirectory() || path.hasPrefix("/Users/") && path.split(separator: "/").count == 2
            ? "house" : "folder"
        }
    }

    static func symbol(_ status: ForkMacBackupLocalStatus) -> (name: String, color: NSColor)? {
        switch status {
        case .identical: return ("checkmark.circle", .tertiaryLabelColor)
        case .modifiedSince: return ("circle.lefthalf.filled", .systemOrange)
        case .deletedSince: return ("circle.slash", .systemRed)
        case .present, .unknown: return nil
        }
    }
}

/// The proof ladder (plan §5.1), drawn as on the island: four dots joined,
/// filled up to the level reached; orange when the snapshot is partial.
struct ForkMacBackupProofDots: View {
    let level: ForkMacBackupProofLevel
    var isPartial = false
    var dot: CGFloat = 7
    var gap: CGFloat = 5
    var labels: [String]? = nil

    private var fill: Color { isPartial ? .orange : ForkMacBackupWindowStyle.teal }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                ForEach(ForkMacBackupProofLevel.allCases, id: \.rawValue) { step in
                    if step != .present {
                        Rectangle()
                            .fill(step <= level ? fill.opacity(0.7) : Color.secondary.opacity(0.25))
                            .frame(width: gap, height: 1.5)
                    }
                    Circle()
                        .fill(step <= level ? fill : Color.clear)
                        .overlay(Circle().strokeBorder(step <= level ? fill : Color.secondary.opacity(0.5), lineWidth: 1.2))
                        .frame(width: dot, height: dot)
                }
            }
            if let labels {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(index <= level.rawValue ? Color.primary : Color.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
    }
}

/// The ladder with its four names below, as large as the inspector wants it.
struct ForkMacBackupWindowProofLadder: View {
    let level: ForkMacBackupProofLevel
    let isPartial: Bool
    let shared: ForkMacBackupStrings
    let text: ForkMacBackupWindowStrings

    var body: some View {
        GeometryReader { geometry in
            let step = (geometry.size.width - 12) / 3
            ZStack(alignment: .topLeading) {
                ForEach(ForkMacBackupProofLevel.allCases, id: \.rawValue) { item in
                    let reached = item <= level
                    let x = CGFloat(item.rawValue) * step
                    if item != .present {
                        Rectangle()
                            .fill(reached ? fill.opacity(0.7) : Color.secondary.opacity(0.25))
                            .frame(width: step - 12, height: 2)
                            .offset(x: x - step + 12, y: 5)
                    }
                    Circle()
                        .fill(reached ? fill : Color.clear)
                        .overlay(Circle().strokeBorder(reached ? fill : Color.secondary.opacity(0.5), lineWidth: 1.5))
                        .frame(width: 12, height: 12)
                        .offset(x: x)
                    Text(item.title(shared))
                        .font(.caption2)
                        .foregroundStyle(reached ? Color.primary : Color.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .multilineTextAlignment(textAlignment(item))
                        .frame(width: labelWidth(item, step: step), alignment: alignment(item))
                        .offset(x: labelOffset(item, x: x, step: step), y: 17)
                }
            }
        }
        .frame(height: 42)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: text.proofVoice, level.title(shared), level.rawValue + 1)
                            + (isPartial ? ", " + text.partial : ""))
    }

    private var fill: Color { isPartial ? .orange : ForkMacBackupWindowStyle.teal }

    private func alignment(_ item: ForkMacBackupProofLevel) -> Alignment {
        switch item {
        case .present: return .leading
        case .restoreTested: return .trailing
        default: return .center
        }
    }

    /// Each name keeps to its share of the line, so none runs into the next
    /// (they shrink a little, then wrap).
    private func labelWidth(_ item: ForkMacBackupProofLevel, step: CGFloat) -> CGFloat {
        switch item {
        case .present, .restoreTested: return max(10, step * 0.62)
        default: return max(10, step * 0.76)
        }
    }

    private func labelOffset(_ item: ForkMacBackupProofLevel, x: CGFloat, step: CGFloat) -> CGFloat {
        switch item {
        case .present: return 0
        case .restoreTested: return x + 12 - labelWidth(item, step: step)
        default: return x + 6 - labelWidth(item, step: step) / 2
        }
    }

    private func textAlignment(_ item: ForkMacBackupProofLevel) -> TextAlignment {
        switch item {
        case .present: return .leading
        case .restoreTested: return .trailing
        default: return .center
        }
    }
}

/// One snapshot's dot on the timeline: its proof in its fill, ◐ when partial.
struct ForkMacBackupSnapshotDot: View {
    let level: ForkMacBackupProofLevel
    let isPartial: Bool
    var selected = false
    var size: CGFloat = 10

    var body: some View {
        ZStack {
            if isPartial {
                Circle().fill(Color(nsColor: .windowBackgroundColor))
                Circle().trim(from: 0.25, to: 0.75).fill(Color.orange).rotationEffect(.degrees(0))
                Circle().strokeBorder(Color.orange, lineWidth: 1.5)
            } else {
                Circle().fill(ForkMacBackupWindowStyle.teal.opacity(opacity))
                Circle().strokeBorder(ForkMacBackupWindowStyle.teal, lineWidth: level == .present ? 1.5 : 0)
                if level == .restoreTested {
                    Circle().fill(Color.white).frame(width: size * 0.34, height: size * 0.34)
                }
            }
        }
        .frame(width: size, height: size)
        .padding(selected ? 3 : 0)
        .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0))
    }

    private var opacity: Double {
        switch level {
        case .present: return 0.12
        case .complete: return 0.55
        case .contentVerified, .restoreTested: return 1
        }
    }
}

/// A rounded group, as the system's own settings draw them.
struct ForkMacBackupCard<Content: View>: View {
    var title: String?
    var symbol: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Label {
                    Text(title).font(.headline)
                } icon: {
                    if let symbol { Image(systemName: symbol).foregroundStyle(ForkMacBackupWindowStyle.teal) }
                }
                .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5))
    }
}

/// A centred message in place of a list.
struct ForkMacBackupEmptyState: View {
    let symbol: String
    let title: String
    var detail: String?
    var action: (title: String, run: () -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            if let detail {
                // No fixed height: a minimum that follows the width makes
                // the split view's minimum size chase itself until AppKit stops it.
                Text(detail)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let action {
                Button(action.title, action: action.run)
                    .padding(.top, 4)
            }
        }
        .padding(40)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The toolbar's search field: the system's own, so ⌘F can focus it and
/// Esc clears it as everywhere else.
struct ForkMacBackupSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let focusToken: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = false
        field.sendsWholeSearchString = false
        field.target = context.coordinator
        field.action = #selector(Coordinator.changed(_:))
        field.controlSize = .regular
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = placeholder
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: ForkMacBackupSearchField
        var focusToken: Int

        init(_ parent: ForkMacBackupSearchField) {
            self.parent = parent
            focusToken = parent.focusToken
        }

        @objc func changed(_ sender: NSSearchField) {
            if parent.text != sender.stringValue { parent.text = sender.stringValue }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            if parent.text != field.stringValue { parent.text = field.stringValue }
        }
    }
}
