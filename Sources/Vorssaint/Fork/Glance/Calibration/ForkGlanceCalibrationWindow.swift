// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import SwiftUI

/// The calibration assistant's window (plan §8.4), like `ForkMacBackupWizard`:
/// 640×560, step chips, Annuler / Retour / Suivant. One window only: asked
/// again, it comes back to the front (a calibration under way is never
/// replaced). While it is open the app has a Dock icon and a place in ⌘Tab.
enum ForkGlanceCalibrationWindow {
    /// Opens it on `entry`, or brings it forward. Main thread.
    static func show(_ entry: ForkGlanceCalibrationEntry) {
        precondition(Thread.isMainThread)
        ForkGlanceCalibrationWindowController.shared.show(entry)
    }

    static var isOpen: Bool { ForkGlanceCalibrationWindowController.shared.isOpen }

    /// Closes it as « Annuler » would (the feature switched off, the app quits).
    static func close() {
        precondition(Thread.isMainThread)
        ForkGlanceCalibrationWindowController.shared.closeWindow()
    }
}

final class ForkGlanceCalibrationWindowController: NSObject, NSWindowDelegate {
    static let shared = ForkGlanceCalibrationWindowController()
    static let size = NSSize(width: 640, height: 560)

    private var window: NSWindow?
    private var session: ForkGlanceCalibrationSession?
    /// The window is closing on its own (its close button): do not close it again.
    private var windowClosing = false

    var isOpen: Bool { window != nil }

    func show(_ entry: ForkGlanceCalibrationEntry) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let session = ForkGlanceCalibrationSession(entry: entry, backend: ForkGlanceServiceCalibrationBackend())
        session.onClose = { [weak self] in self?.sessionClosed() }
        session.onReopen = { [weak self] entry in
            DispatchQueue.main.async { self?.show(entry) }
        }
        let window = Self.makeWindow(session: session)
        window.delegate = self
        self.window = window
        self.session = session
        WindowActivationPolicy.retain()
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func closeWindow() {
        session?.close()
    }

    /// The window itself, also built by the offscreen renders.
    static func makeWindow(session: ForkGlanceCalibrationSession) -> NSWindow {
        let host = NSHostingController(rootView: ForkGlanceCalibrationView(session: session))
        host.sizingOptions = []
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable]
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.hidesOnDeactivate = false
        window.tabbingMode = .disallowed
        window.title = title(for: session)
        return window
    }

    static func title(for session: ForkGlanceCalibrationSession) -> String {
        switch session.entry {
        case .full: return session.text.windowTitle
        case .recalibrate: return session.core.recalibrate
        case .test: return session.text.testTitle
        case .quickRecenter: return session.core.quickRecenter
        case .framing: return session.text.framingTitle
        }
    }

    func windowWillClose(_ notification: Notification) {
        windowClosing = true
        session?.close()
        windowClosing = false
    }

    private func sessionClosed() {
        guard let window else { return }
        self.window = nil
        session = nil
        window.delegate = nil
        if !windowClosing { window.close() }
        WindowActivationPolicy.release()
    }
}

// MARK: - The assistant

/// The window's content: the header with the step chips, the step, the footer.
struct ForkGlanceCalibrationView: View {
    @ObservedObject var session: ForkGlanceCalibrationSession

    private var text: ForkGlanceCalibrationStrings { session.text }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: ForkGlanceCalibrationWindowController.size.width,
               height: ForkGlanceCalibrationWindowController.size.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.locale, session.locale)
    }

    // MARK: Header and footer

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ForkGlanceIconTile(symbol: "viewfinder", size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(ForkGlanceCalibrationWindowController.title(for: session))
                        .font(.headline)
                    Text(session.steps.count > 1 ? text.stepLine(session.stepNumber, of: session.steps.count)
                                                 : text.stepName(session.step))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if session.steps.count > 1 {
                HStack(spacing: 6) {
                    ForEach(Array(session.steps.enumerated()), id: \.element) { index, step in
                        chip(step, index: index)
                        if index < session.steps.count - 1 {
                            Rectangle()
                                .fill(index < session.stepNumber - 1 ? Color.indigo : Color.secondary.opacity(0.25))
                                .frame(height: 1.5)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func chip(_ step: ForkGlanceAssistantStep, index: Int) -> some View {
        let done = index < session.stepNumber - 1
        let current = step == session.step
        return HStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(done || current ? Color.indigo : Color.secondary.opacity(0.18))
                    .frame(width: 18, height: 18)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(current ? .white : .secondary)
                }
            }
            if current || session.steps.count <= 4 {
                Text(text.stepName(step))
                    .font(.caption.weight(current ? .semibold : .regular))
                    .foregroundStyle(current ? .primary : .secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(index + 1). \(text.stepName(step))")
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    private var footer: some View {
        HStack {
            if session.step != .done {
                Button(text.cancel) { session.cancel() }
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            if session.canGoBack {
                Button(text.back) { session.back() }
            }
            primary
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var primary: some View {
        switch session.step {
        case .welcome, .permissions, .layout:
            prominent(text.next, enabled: session.canGoNext) { session.next() }
        case .framing:
            if session.problem == .cameraUnavailable {
                prominent(session.core.retry) { session.retryCamera() }
            } else if session.steps.count == 1 {
                prominent(text.finish) { session.close() }
            } else {
                prominent(text.next, enabled: session.canGoNext) { session.next() }
            }
        case .points:
            if let problem = session.problem {
                if problem == .cameraUnavailable {
                    prominent(session.core.retry) { session.retryCamera() }
                } else {
                    prominent(text.startAgain) { session.startAgain() }
                }
            } else if !session.isRunning && !session.fitting {
                prominent(text.start) { session.startPoints() }
            }
        case .validation:
            if session.problem == .cameraUnavailable {
                prominent(session.core.retry) { session.retryCamera() }
            } else if let accuracy = session.accuracy {
                if !ForkGlanceValidation.weakZones(accuracy, zones: session.zones).isEmpty {
                    if session.entry == .test {
                        Button(session.core.recalibrate) { session.redoWeakPoints() }
                    } else {
                        Button(text.redoWeak) { session.redoWeakPoints() }
                    }
                }
                prominent(text.finish) { session.finishValidation() }
            } else if !session.isRunning && !session.fitting {
                prominent(text.startTest) { session.startValidation() }
            }
        case .done:
            prominent(text.finish) { session.close() }
        }
    }

    private func prominent(_ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .keyboardShortcut(.defaultAction)
            .disabled(!enabled)
    }

    // MARK: Steps

    @ViewBuilder
    private var content: some View {
        switch session.step {
        case .welcome: ForkGlanceWelcomeStep(session: session)
        case .permissions: ForkGlancePermissionsStep(session: session)
        case .framing: ForkGlanceFramingView(session: session)
        case .layout: ForkGlanceLayoutStep(session: session)
        case .points: ForkGlancePointsStep(session: session)
        case .validation: ForkGlanceValidationView(session: session)
        case .done: ForkGlanceDoneStep(session: session)
        }
    }
}

/// The feature's tile: its symbol, white on indigo.
struct ForkGlanceIconTile: View {
    let symbol: String
    var size: CGFloat = 30

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(Color.indigo.gradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}

/// A caption under a row, wrapping.
struct ForkGlanceCaption: View {
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

// MARK: 1. Welcome

private struct ForkGlanceWelcomeStep: View {
    @ObservedObject var session: ForkGlanceCalibrationSession

    var body: some View {
        let text = session.text
        Form {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    ForkGlanceIconTile(symbol: "eyes", size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(text.welcomeTitle)
                            .font(.title3.weight(.semibold))
                        Text(text.welcomeBody)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                bullet("lock.shield", .green, text.privacyNothingStored)
                bullet("desktopcomputer", .blue, text.privacyOnDevice)
                bullet("eye.slash", .orange, text.privacyPause)
            }
            Section {
                bullet("gauge.with.dots.needle.33percent", .indigo, text.costLine(locale: session.locale))
                bullet("clock", .indigo,
                       text.duration(ForkGlanceCalibrationPlan.duration(points: session.planTargets.count), locale: session.locale))
            }
        }
        .formStyle(.grouped)
    }

    private func bullet(_ symbol: String, _ color: Color, _ line: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(line)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: 2. Permissions

private struct ForkGlancePermissionsStep: View {
    @ObservedObject var session: ForkGlanceCalibrationSession
    @ObservedObject private var permissions = Permissions.shared

    var body: some View {
        let text = session.text
        Form {
            Section {
                Text(text.permissionsBody)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text(text.permissionsTitle)
            }
            Section {
                cameraRow
                PermissionRow(kind: .accessibility)
                if !permissions.accessibility {
                    ForkGlanceCaption(text.accessibilityLater)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Hand-made like the Dictation's speech row: `PermissionKind` has no camera.
    @ViewBuilder
    private var cameraRow: some View {
        let text = session.text
        let official = session.official
        let permission = session.backend.cameraPermission
        let granted = permission == .granted
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(granted ? .green : .orange)
                    .accessibilityHidden(true)
                Text(text.cameraName)
                Spacer()
                Text(granted ? official.permissionGranted : official.permissionMissing)
                    .font(.caption)
                    .foregroundStyle(granted ? .green : .orange)
            }
            .accessibilityElement(children: .combine)
            if !granted {
                HStack(spacing: 8) {
                    if permission == .notDetermined {
                        Button(official.permissionRequest) { session.requestCamera() }
                    }
                    Button(official.permissionOpenSettings) { Permissions.shared.openCameraSettings() }
                }
                .controlSize(.small)
                ForkGlanceCaption(permission == .denied ? text.cameraDenied : text.cameraRequired, color: .orange)
            }
        }
    }
}

// MARK: 4. Layout

private struct ForkGlanceLayoutStep: View {
    @ObservedObject var session: ForkGlanceCalibrationSession

    var body: some View {
        let text = session.text
        let core = session.core
        Form {
            Section {
                ForkGlanceLayoutMap(layout: session.layout, zones: session.zones, splits: session.splits,
                                    onSplit: { uuid, split in session.setSplit(split, display: uuid) })
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                ForkGlanceCaption(text.layoutBody)
            } header: {
                Text(text.layoutTitle)
            }
            Section {
                Picker(text.modeLabel, selection: Binding(get: { session.mode }, set: { session.setMode($0) })) {
                    ForEach(ForkGlanceMode.allCases, id: \.self) { mode in
                        Text(core.modeName(mode)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                ForkGlanceCaption(core.modeCaption(session.mode))
                if session.mode == .screens && !ForkGlanceZones.screensModePossible(session.layout) {
                    ForkGlanceCaption(core.singleScreenHint, color: .orange)
                }
                if session.mode == .windows {
                    ForkGlanceCaption(text.windowsModeNote, color: .orange)
                }
            }
            if session.mode == .zones {
                Section {
                    ForEach(session.layout.displays, id: \.uuid) { display in
                        Picker(display.name, selection: Binding(
                            get: { session.splits[display.uuid] ?? ForkGlanceZones.defaultSplit(for: display) },
                            set: { session.setSplit($0, display: display.uuid) })) {
                            ForEach(ForkGlanceSplit.allCases, id: \.self) { split in
                                Text(core.splitName(split)).tag(split)
                            }
                        }
                    }
                } header: {
                    Text(text.splitLabel)
                } footer: {
                    Text(text.zoneCount(session.zones.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: 5. Points

private struct ForkGlancePointsStep: View {
    @ObservedObject var session: ForkGlanceCalibrationSession

    var body: some View {
        let text = session.text
        let quick = session.entry == .quickRecenter
        let count = quick ? ForkGlanceCalibrationPlan.quickTargets(zones: session.zones).count : session.planTargets.count
        Form {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    ForkGlanceIconTile(symbol: quick ? "scope" : "viewfinder", size: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(quick ? session.core.quickRecenter : text.pointsTitle)
                            .font(.title3.weight(.semibold))
                        Text(quick ? text.quickBody : text.pointsBody)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(text.pointsLine(count, locale: session.locale))
                            .font(.callout.monospacedDigit())
                            .padding(.top, 2)
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                key("space", text.keySpace)
                key("escape", text.keyEscape)
                key("delete.left", text.keyDelete)
            }
            if session.isRunning || session.fitting || session.problem != nil {
                Section {
                    status
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var status: some View {
        let text = session.text
        if let problem = session.problem {
            Label {
                ForkGlanceCaption(session.problemText(problem), color: .orange)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        } else if session.fitting {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(text.fitting)
            }
        } else if let run = session.run {
            VStack(alignment: .leading, spacing: 6) {
                Text(session.runLine ?? "")
                    .font(.callout.monospacedDigit())
                ProgressView(value: Double(run.done), total: Double(max(1, run.targets.count)))
                    .tint(.indigo)
            }
        }
    }

    private func key(_ symbol: String, _ line: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(line)
        }
    }
}

// MARK: 7. Done

private struct ForkGlanceDoneStep: View {
    @ObservedObject var session: ForkGlanceCalibrationSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        let text = session.text
        let core = session.core
        let score = session.accuracy.map(ForkGlanceValidation.overall)
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: reduceMotion ? false : appeared)
            Text(text.doneTitle)
                .font(.title2.weight(.semibold))
            if let score {
                HStack(spacing: 8) {
                    Text(core.calibrationScoreLine(score, locale: session.locale))
                        .font(.headline.monospacedDigit())
                    ForkGlanceGradeBadge(grade: ForkGlanceGrade(score: score), core: core)
                }
            }
            Text(text.doneBody)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440)
            Spacer()
        }
        .padding(24)
        .onAppear { appeared = true }
    }
}

/// « Excellente », « Bonne »… in its color.
struct ForkGlanceGradeBadge: View {
    let grade: ForkGlanceGrade
    let core: ForkGlanceStrings

    static func color(_ grade: ForkGlanceGrade) -> Color {
        switch grade {
        case .excellent: return .green
        case .good: return .teal
        case .fair: return .orange
        case .poor: return .red
        }
    }

    var body: some View {
        Text(core.gradeName(grade))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(Self.color(grade))
            .background(Capsule().fill(Self.color(grade).opacity(0.15)))
    }
}
