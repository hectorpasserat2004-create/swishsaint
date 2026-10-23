// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AVFoundation
import AppKit
import SwiftUI

/// The framing step (plan §8.4, step 3; also « Vérifier le cadrage… » on its
/// own): the camera to film with, its live preview, mirrored like the
/// official one, with the face's frame drawn over it, the four gauges and one
/// hint. « Suivant » turns on once the gauges stay green for a second. The
/// preview's layer is the service's running session
/// (`ForkGlanceCamera.makePreviewLayer`): this view never starts a camera.
struct ForkGlanceFramingView: View {
    @ObservedObject var session: ForkGlanceCalibrationSession

    static let previewSize = CGSize(width: 300, height: 225)

    var body: some View {
        let text = session.text
        Form {
            Section {
                HStack(alignment: .top, spacing: 18) {
                    preview
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(ForkGlanceFraming.Gauge.allCases, id: \.self) { gauge in
                            gaugeRow(gauge)
                        }
                        Divider()
                        Text(text.framingAdvice(session.framing.advice))
                            .font(.callout.weight(.medium))
                            .foregroundStyle(session.framing.allGood ? .green : .primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
            } footer: {
                ForkGlanceCaption(text.framingBody)
            }
            Section {
                cameraPicker
                if let problem = session.problem {
                    ForkGlanceCaption(session.problemText(problem), color: .orange)
                } else if session.steps.count > 1 {
                    ForkGlanceCaption(text.framingHold)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Parts

    @ViewBuilder
    private var preview: some View {
        let size = Self.previewSize
        ZStack {
            Color.black
            if let layer = session.previewLayer {
                ForkGlanceFramingPreview(previewLayer: layer, observation: session.observation)
                    .id(ObjectIdentifier(layer))
            } else if session.receiving {
                // No live image to draw on (the renders): the frame alone, mirrored.
                if let box = Self.mirroredBox(session.observation, in: size) {
                    Image(systemName: "person.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.white.opacity(0.18))
                        .frame(width: box.width * 1.1, height: box.height * 1.4)
                        .position(x: box.midX, y: box.midY + box.height * 0.25)
                    faceFrame(box)
                }
            } else {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(.white)
                    Text(session.core.statusStarting)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .accessibilityElement()
        .accessibilityLabel(session.text.previewLabel)
    }

    private func faceFrame(_ box: CGRect) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(session.framing.allGood ? Color.green : Color.yellow, lineWidth: 2)
            .frame(width: box.width, height: box.height)
            .position(x: box.midX, y: box.midY)
    }

    /// Vision's box (normalized, origin at the bottom left, the camera's own
    /// view) in a mirrored preview of `size` filled by a 4:3 image.
    static func mirroredBox(_ observation: ForkGlanceObservation?, in size: CGSize) -> CGRect? {
        guard let box = observation?.faceBox, !box.isEmpty else { return nil }
        return CGRect(x: (1 - box.maxX) * size.width, y: (1 - box.maxY) * size.height,
                      width: box.width * size.width, height: box.height * size.height)
    }

    private func gaugeRow(_ gauge: ForkGlanceFraming.Gauge) -> some View {
        let good = session.framing.reading(gauge) == .good
        return HStack(spacing: 8) {
            Image(systemName: good ? "checkmark.circle.fill" : "circle.dotted")
                .foregroundStyle(good ? .green : .orange)
                .font(.system(size: 15))
            Text(session.text.gaugeName(gauge))
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(good ? session.text.gaugeGood : session.text.gaugeLow)
    }

    @ViewBuilder
    private var cameraPicker: some View {
        let devices = session.backend.cameraDevices
        if !devices.isEmpty {
            Picker(session.text.cameraName, selection: Binding(
                get: { session.backend.cameraID ?? devices.first?.id ?? "" },
                set: { session.selectCamera($0) })) {
                ForEach(devices) { device in
                    Text(device.name).tag(device.id)
                }
            }
        }
    }
}

/// The running camera's preview, mirrored, with the face's frame converted by
/// the layer itself (its gravity and mirroring included).
struct ForkGlanceFramingPreview: NSViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer
    let observation: ForkGlanceObservation?

    final class LayerHostView: NSView {
        let previewLayer: AVCaptureVideoPreviewLayer
        private let frameLayer = CAShapeLayer()

        init(previewLayer: AVCaptureVideoPreviewLayer) {
            self.previewLayer = previewLayer
            super.init(frame: .zero)
            previewLayer.videoGravity = .resizeAspectFill
            layer = previewLayer
            wantsLayer = true
            frameLayer.fillColor = nil
            frameLayer.lineWidth = 2
            frameLayer.strokeColor = NSColor.systemYellow.cgColor
            previewLayer.addSublayer(frameLayer)
            mirror()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        /// What a mirror shows, like the official preview (`CameraPreviewView`).
        private func mirror() {
            guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else { return }
            if connection.automaticallyAdjustsVideoMirroring { connection.automaticallyAdjustsVideoMirroring = false }
            if !connection.isVideoMirrored { connection.isVideoMirrored = true }
        }

        override func layout() {
            super.layout()
            frameLayer.frame = previewLayer.bounds
        }

        func update(_ observation: ForkGlanceObservation?) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }
            guard let box = observation?.faceBox, !box.isEmpty else {
                frameLayer.path = nil
                return
            }
            // Vision's origin is at the bottom left, the metadata space's at the top left.
            let metadata = CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
            let rect = previewLayer.layerRectConverted(fromMetadataOutputRect: metadata)
            frameLayer.path = CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        }
    }

    func makeNSView(context: Context) -> LayerHostView {
        LayerHostView(previewLayer: previewLayer)
    }

    func updateNSView(_ view: LayerHostView, context: Context) {
        view.update(observation)
    }

    static func dismantleNSView(_ view: LayerHostView, coordinator: ()) {
        view.previewLayer.session = nil
    }
}
