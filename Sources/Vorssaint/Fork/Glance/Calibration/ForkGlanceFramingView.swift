// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AVFoundation
import AppKit
import CoreMedia
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
                ForkGlanceFramingPreview(previewLayer: layer)
                    .id(ObjectIdentifier(layer))
                if let box = Self.mirroredBox(session.observation, in: size,
                                              imageSize: ForkGlanceFramingPreview.imageSize(of: layer),
                                              mirrored: layer.connection?.isVideoMirrored ?? true) {
                    faceFrame(box)
                }
            } else if session.receiving {
                // No live image to draw on (the renders): the frame alone, mirrored.
                if let box = Self.mirroredBox(session.observation, in: size, imageSize: nil) {
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
    /// view) in the preview of `size`, mirrored like the layer, which an
    /// image of `imageSize` fills (cropped); unknown, the image is taken to
    /// fill it exactly.
    static func mirroredBox(_ observation: ForkGlanceObservation?, in size: CGSize, imageSize: CGSize?,
                            mirrored: Bool = true) -> CGRect? {
        guard let box = observation?.faceBox, !box.isEmpty else { return nil }
        return ForkGlancePreviewGeometry(size: size, imageSize: imageSize, fills: true, mirrored: mirrored).rect(box)
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

/// The running camera's preview, mirrored, filling its frame (cropped). The
/// face's frame is drawn over it in SwiftUI (`ForkGlancePreviewGeometry`),
/// from the image's size this layer's camera films.
struct ForkGlanceFramingPreview: NSViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    /// The size of the images the layer's camera films; nil before it is known.
    static func imageSize(of layer: AVCaptureVideoPreviewLayer) -> CGSize? {
        guard let format = layer.connection?.inputPorts.first(where: { $0.mediaType == .video })?.formatDescription
        else { return nil }
        let dimensions = CMVideoFormatDescriptionGetDimensions(format)
        guard dimensions.width > 0, dimensions.height > 0 else { return nil }
        return CGSize(width: CGFloat(dimensions.width), height: CGFloat(dimensions.height))
    }

    final class LayerHostView: NSView {
        let previewLayer: AVCaptureVideoPreviewLayer

        init(previewLayer: AVCaptureVideoPreviewLayer) {
            self.previewLayer = previewLayer
            super.init(frame: .zero)
            previewLayer.videoGravity = .resizeAspectFill
            layer = previewLayer
            wantsLayer = true
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
    }

    func makeNSView(context: Context) -> LayerHostView {
        LayerHostView(previewLayer: previewLayer)
    }

    func updateNSView(_ view: LayerHostView, context: Context) {}

    static func dismantleNSView(_ view: LayerHostView, coordinator: ()) {
        view.previewLayer.session = nil
    }
}
