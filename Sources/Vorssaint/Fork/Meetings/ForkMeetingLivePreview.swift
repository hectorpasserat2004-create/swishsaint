// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import CoreImage
import CoreMedia
import SwiftUI

/// A still of what the recording films, about once a second, for the
/// island's Meetings page while it shows it, and only then: so the person
/// sees that the right window is filmed without opening anything.
///
/// The recorder offers each frame it writes (`offer`, on the capture
/// queue). One is kept only while a page watches, a second after the last
/// one, and one at a time: it is scaled down on a queue of its own, never
/// the capture's, and handed to the main thread. In memory only, never
/// written: the still goes when the last page stops watching or the
/// recording ends.
final class ForkMeetingLivePreview: ObservableObject, @unchecked Sendable {
    static let shared = ForkMeetingLivePreview()

    /// The latest still. Main thread.
    @Published private(set) var image: CGImage?

    private let lock = NSLock()
    // Under `lock`.
    private var watchers = 0
    private var lastTaken: TimeInterval = -.infinity
    private var scaling = false

    private let queue = DispatchQueue(label: "fork.meetings.preview", qos: .utility)
    /// Used on `queue` only.
    private lazy var context = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: false])

    private init() {}

    /// A page that shows the still appeared. Main thread.
    func watch() {
        lock.withLock {
            watchers += 1
            // The first still comes with the next frame, not a second later.
            lastTaken = -.infinity
        }
    }

    /// That page left: with no page left, the still goes. Main thread.
    func unwatch() {
        let none = lock.withLock { () -> Bool in
            watchers = max(0, watchers - 1)
            return watchers == 0
        }
        if none { image = nil }
    }

    /// The recording ended: its last still must not stand for the next one.
    /// Main thread.
    func reset() {
        lock.withLock { lastTaken = -.infinity }
        image = nil
    }

    /// Every frame the recorder writes, on the capture queue: nearly always
    /// a lock and a comparison, nothing more.
    func offer(_ sample: CMSampleBuffer) {
        let now = ProcessInfo.processInfo.systemUptime
        let takes = lock.withLock { () -> Bool in
            guard watchers > 0, !scaling, now - lastTaken >= ForkMeetingIslandPage.previewInterval else { return false }
            scaling = true
            lastTaken = now
            return true
        }
        guard takes else { return }
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else {
            lock.withLock { scaling = false }
            return
        }
        queue.async { [self] in
            let still = Self.still(of: buffer, context: context)
            lock.withLock { scaling = false }
            DispatchQueue.main.async { [weak self] in
                guard let self, let still, self.lock.withLock({ self.watchers > 0 }) else { return }
                self.image = still
            }
        }
    }

    /// The frame scaled down to `ForkMeetingIslandPage.previewPixels` on its
    /// longer side.
    private static func still(of buffer: CVPixelBuffer, context: CIContext) -> CGImage? {
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let size = ForkMeetingIslandPage.previewSize(width: width, height: height)
        guard size.width > 0, size.height > 0 else { return nil }
        let image = CIImage(cvPixelBuffer: buffer)
            .transformed(by: CGAffineTransform(scaleX: CGFloat(size.width) / CGFloat(width),
                                               y: CGFloat(size.height) / CGFloat(height)))
        return context.createCGImage(image, from: CGRect(x: 0, y: 0, width: size.width, height: size.height))
    }
}

/// The still in a small frame, the picture fitted whole; while none has
/// come yet, or for a meeting recorded without picture, the mark of what
/// is recorded instead. It watches only while it is on screen, and never
/// in the Settings preview.
struct ForkMeetingLivePreviewView: View {
    let snapshot: ForkMeetingIslandSnapshot
    var width: CGFloat = 64
    var height: CGFloat = 40
    @ObservedObject private var preview = ForkMeetingLivePreview.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.notchSettingsPreview) private var settingsPreview

    private var filmsPicture: Bool { snapshot.context.target.filmsPicture }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        ZStack {
            Color.black.opacity(0.55)
            if filmsPicture, let image = preview.image, !settingsPreview {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fit)
                    // A frozen picture reads as such: the still dims.
                    .opacity(snapshot.context.pictureFrozen || snapshot.context.sourceGone ? 0.45 : 1)
                    .transition(.opacity)
            } else {
                Image(systemName: filmsPicture ? snapshot.context.target == .window ? "macwindow" : "display"
                                               : "waveform")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.white.opacity(0.1), lineWidth: 0.5) }
        .animation(.easeOut(duration: 0.2), value: preview.image == nil)
        .accessibilityElement()
        .accessibilityLabel(ForkMeetingIslandStrings.strings(l10n.language).previewLabel)
        .onAppear { if !settingsPreview { preview.watch() } }
        .onDisappear { if !settingsPreview { preview.unwatch() } }
    }
}
