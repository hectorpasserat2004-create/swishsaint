// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Combine
import Foundation

/// « The camera is taken » for Glance Focus, the part `ForkGlanceCamera`
/// cannot see: the official camera preview (the floating mirror or the
/// island's camera) films from this same app, so `isInUseByAnotherApplication`
/// stays false. Two sessions of one app on one camera « would fight over the
/// camera » [V] `CameraPreviewService.startSession`, so Glance pauses
/// (`cameraBusy`, plan §7.5) for as long as the preview is not idle, the
/// permission prompt it may show included. Another app filming is
/// `ForkGlanceCamera.isInUseElsewhere`.
enum ForkGlanceCameraBusy {
    /// Main thread.
    static var officialPreviewOpen: Bool {
        precondition(Thread.isMainThread)
        return isOpen(CameraPreviewService.shared.state)
    }

    /// Calls `handler` on the main thread at once with the current value,
    /// then on each change, until the returned value is cancelled or released.
    /// The preview's state only changes on the main thread.
    static func observe(_ handler: @escaping (Bool) -> Void) -> AnyCancellable {
        precondition(Thread.isMainThread)
        return CameraPreviewService.shared.$state
            .map(isOpen)
            .removeDuplicates()
            .sink(receiveValue: handler)
    }

    private static func isOpen(_ state: CameraPreviewService.PreviewState) -> Bool {
        state != .idle
    }
}
