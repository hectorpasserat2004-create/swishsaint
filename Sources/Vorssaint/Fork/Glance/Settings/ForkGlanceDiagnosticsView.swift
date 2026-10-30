// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import AVFoundation
import SwiftUI

/// What the diagnostics ask of the service; stand-ins in the off-screen
/// renders, so nothing there ever starts the camera.
struct ForkGlanceDiagnosticsActions {
    /// Live readings while the lease lives (plan §12.11).
    var liveLease: () -> ForkGlanceLease
    /// A preview of the running session; nil when it does not run.
    var makePreviewLayer: () -> AVCaptureVideoPreviewLayer?
    var recordTrace: (TimeInterval, @escaping (URL?) -> Void) -> Void
    var reportText: () -> String

    static var live: ForkGlanceDiagnosticsActions {
        ForkGlanceDiagnosticsActions(
            liveLease: { ForkGlanceService.shared.liveLease() },
            makePreviewLayer: { ForkGlanceCamera.shared.makePreviewLayer() },
            recordTrace: { ForkGlanceService.shared.recordTrace(seconds: $0, completion: $1) },
            reportText: { ForkGlanceService.shared.reportText() })
    }

    static let inert = ForkGlanceDiagnosticsActions(liveLease: { ForkGlanceLease {} }, makePreviewLayer: { nil },
                                                    recordTrace: { _, done in done(nil) }, reportText: { "" })
}

/// The live diagnostics (plan §12.11), folded under the page: active only
/// while shown. Appearing takes a lease on the service's live readings,
/// disappearing gives it back, so nothing is computed for a closed panel.
/// The camera preview is mirrored like a mirror, and so are the landmarks
/// drawn over it; the curves keep the last 10 s, here and nowhere else.
struct ForkGlanceDiagnosticsView: View {
    let live: ForkGlanceLive?
    let phase: ForkGlancePhase
    let layout: ForkGlanceDisplayLayout
    let zones: [ForkGlanceZone]
    let currentZone: String?
    let lastSwitch: Date?
    let text: ForkGlanceSettingsStrings
    let core: ForkGlanceStrings
    let locale: Locale
    var actions: ForkGlanceDiagnosticsActions = .live
    var zoneName: (String) -> String? = { _ in nil }

    @State private var lease: ForkGlanceLease?
    @State private var history: ForkGlanceCurveHistory
    @State private var recording = false
    @State private var traceResult: Bool?
    @State private var reportCopied = false
    /// The gaze dot over every display (plan §6.4): the service reads the
    /// key again as it changes and shows or hides the dot.
    @AppStorage(ForkDefaultsKey.glanceGazeDot) private var gazeDot = false

    init(live: ForkGlanceLive?, phase: ForkGlancePhase, layout: ForkGlanceDisplayLayout, zones: [ForkGlanceZone],
         currentZone: String?, lastSwitch: Date?, text: ForkGlanceSettingsStrings, core: ForkGlanceStrings,
         locale: Locale, actions: ForkGlanceDiagnosticsActions = .live, history: ForkGlanceCurveHistory = .init(),
         zoneName: @escaping (String) -> String? = { _ in nil }) {
        self.live = live
        self.phase = phase
        self.layout = layout
        self.zones = zones
        self.currentZone = currentZone
        self.lastSwitch = lastSwitch
        self.text = text
        self.core = core
        self.locale = locale
        self.actions = actions
        self.zoneName = zoneName
        _history = State(initialValue: history)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if live == nil {
                Text(text.diagnosticsIdle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 12) {
                cameraPanel
                mapPanel
            }
            curves
            table
            Toggle(text.showGazeDot, isOn: $gazeDot)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.caption)
            buttons
        }
        .padding(.vertical, 4)
        .onAppear { lease = actions.liveLease() }
        .onDisappear {
            lease?.release()
            lease = nil
        }
        .onChange(of: live?.time) { _, _ in
            guard let live else { return }
            history.append(time: live.time, observation: live.observation, sample: live.sample)
        }
    }

    // MARK: Camera

    private var cameraRunning: Bool { live?.observation != nil || (live?.frameRate ?? 0) > 0 }

    private var cameraPanel: some View {
        ZStack {
            Color.black.opacity(0.85)
            if cameraRunning {
                ForkGlanceCameraPreview(makeLayer: actions.makePreviewLayer, running: cameraRunning)
            } else {
                Label(text.previewUnavailable, systemImage: "video.slash")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            if let observation = live?.observation {
                ForkGlanceLandmarks(observation: observation)
            }
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .frame(width: 200)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }

    // MARK: Map

    private var mapPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text.estimateTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForkGlanceLayoutMap(layout: layout, zones: zones, activeZone: currentZone,
                                gazePoint: live?.estimate?.point, style: .settings, gazeSigma: live?.estimate?.sigma)
                .frame(maxWidth: .infinity, maxHeight: 130)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Curves

    private var curves: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(text.curvesTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                legend(text.curveYaw, .blue)
                legend(text.curvePitch, .green)
                legend(text.curveEyes, .orange)
            }
            Canvas { context, size in
                var axis = Path()
                axis.move(to: CGPoint(x: 0, y: size.height / 2))
                axis.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                context.stroke(axis, with: .color(.secondary.opacity(0.3)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                for (series, color) in [(ForkGlanceCurveHistory.Series.yaw, Color.blue), (.pitch, .green), (.eyes, .orange)] {
                    for segment in history.segments(series) where !segment.isEmpty {
                        var path = Path()
                        path.addLines(segment.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) })
                        context.stroke(path, with: .color(color), lineWidth: 1.4)
                    }
                }
            }
            .frame(height: 64)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .accessibilityHidden(true)
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Capsule().fill(color).frame(width: 10, height: 3)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: Table

    private var readings: ForkGlanceDiagnosticReadings {
        guard let live else {
            return ForkGlanceDiagnosticReadings(frameRate: 0, visionMean: 0, visionP95: 0, confidence: nil, guards: [],
                                                extraEntry: 0, setAside: [:], focusFailures: [:], clickAgreement: nil,
                                                cpuCores: nil, watts: nil, revisions: "")
        }
        return ForkGlanceDiagnosticReadings(frameRate: live.frameRate, visionMean: live.visionMean,
                                            visionP95: live.visionP95,
                                            confidence: live.sample?.confidence ?? live.gaze?.confidence,
                                            guards: live.guards, extraEntry: live.extraEntry, setAside: live.setAside,
                                            focusFailures: live.focusFailures, clickAgreement: live.clickAgreement,
                                            cpuCores: live.cpuCores, watts: live.watts, revisions: live.revisions)
    }

    private var table: some View {
        let lines = ForkGlanceSettingsRules.diagnosticLines(readings, phase: phase, lastSwitch: lastSwitch, now: Date(),
                                                            locale: locale, text: text, core: core, zoneName: zoneName)
        return Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 3) {
            ForEach(lines) { line in
                GridRow {
                    Text(line.label)
                        .foregroundStyle(.secondary)
                    Text(line.value)
                        .monospacedDigit()
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
            }
        }
    }

    // MARK: Trace and report

    private var buttons: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    recording = true
                    traceResult = nil
                    actions.recordTrace(60) { url in
                        recording = false
                        traceResult = url != nil
                    }
                } label: {
                    Label(text.recordTrace, systemImage: "record.circle")
                }
                .disabled(recording || live == nil)
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(actions.reportText(), forType: .string)
                    reportCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { reportCopied = false }
                } label: {
                    Label(text.copyReport, systemImage: "doc.on.doc")
                }
                Spacer(minLength: 0)
                if recording {
                    ProgressView().controlSize(.small)
                    Text(text.recordingTrace).font(.caption).foregroundStyle(.secondary)
                } else if let traceResult {
                    Label(traceResult ? text.traceSaved : text.traceNotSaved,
                          systemImage: traceResult ? "checkmark.circle.fill" : "xmark.circle")
                        .font(.caption)
                        .foregroundStyle(traceResult ? .green : .secondary)
                } else if reportCopied {
                    Label(text.reportCopied, systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .controlSize(.small)
            Text(text.traceCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Landmarks

/// The face box, the eyes' outlines and the pupils over the mirrored
/// preview, in the image's 4:3 frame.
private struct ForkGlanceLandmarks: View {
    let observation: ForkGlanceObservation

    var body: some View {
        Canvas { context, size in
            func place(_ point: CGPoint) -> CGPoint {
                let unit = ForkGlanceSettingsRules.previewPoint(point, mirrored: true)
                return CGPoint(x: unit.x * size.width, y: unit.y * size.height)
            }
            let box = ForkGlanceSettingsRules.previewRect(observation.faceBox, mirrored: true)
            let frame = CGRect(x: box.minX * size.width, y: box.minY * size.height,
                               width: box.width * size.width, height: box.height * size.height)
            context.stroke(Path(roundedRect: frame, cornerRadius: 4), with: .color(.yellow), lineWidth: 1.5)
            for eye in [observation.leftEye, observation.rightEye] where eye.count > 1 {
                var path = Path()
                path.addLines(eye.map(place))
                path.closeSubpath()
                context.stroke(path, with: .color(.cyan), lineWidth: 1)
            }
            for pupil in [observation.leftPupil, observation.rightPupil].compactMap({ $0 }) {
                let center = place(pupil)
                context.fill(Path(ellipseIn: CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)),
                             with: .color(.red))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Camera preview

/// The running session's preview, mirrored. A new layer each time the
/// camera starts again: an old one shows nothing once the session is rebuilt.
private struct ForkGlanceCameraPreview: NSViewRepresentable {
    let makeLayer: () -> AVCaptureVideoPreviewLayer?
    let running: Bool

    final class Host: NSView {
        var preview: AVCaptureVideoPreviewLayer?
        var wasRunning = false

        override func layout() {
            super.layout()
            preview?.frame = bounds
        }

        func install(_ layer: AVCaptureVideoPreviewLayer?) {
            preview?.removeFromSuperlayer()
            preview = layer
            guard let layer else { return }
            layer.videoGravity = .resizeAspect
            if let connection = layer.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
            layer.frame = bounds
            self.layer?.addSublayer(layer)
        }
    }

    func makeNSView(context: Context) -> Host {
        let host = Host()
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.black.cgColor
        return host
    }

    func updateNSView(_ host: Host, context: Context) {
        if running && (!host.wasRunning || host.preview == nil) {
            host.install(makeLayer())
        } else if !running && host.preview != nil {
            host.install(nil)
        }
        host.wasRunning = running
    }

    static func dismantleNSView(_ host: Host, coordinator: ()) {
        host.install(nil)
    }
}
