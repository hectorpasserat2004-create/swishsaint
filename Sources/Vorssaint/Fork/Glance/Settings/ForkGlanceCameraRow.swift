// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import SwiftUI

/// The camera permission, made by hand (plan §12.2): `PermissionKind` has no
/// camera case and gets no seam for it. Modelled on the Dictation's speech
/// row: the state, « Autoriser » while macOS has not asked yet (the prompt
/// comes only from that click), « Ouvrir les Réglages » once refused. The
/// state is the service's, refreshed when the app comes back to the front
/// (the person may have just changed it in System Settings).
struct ForkGlanceCameraRow: View {
    let permission: ForkGlanceCameraPermission
    let text: ForkGlanceSettingsStrings
    var request: () -> Void
    /// The app came back to the front: read the permission again.
    var refresh: () -> Void = {}

    @ObservedObject private var l10n = L10n.shared

    init(permission: ForkGlanceCameraPermission, text: ForkGlanceSettingsStrings, request: @escaping () -> Void,
         refresh: @escaping () -> Void = {}) {
        self.permission = permission
        self.text = text
        self.request = request
        self.refresh = refresh
    }

    static let privacySettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")

    var body: some View {
        let granted = permission == .granted
        let color: Color = granted ? .green : (permission == .denied ? .red : .orange)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.camera)
                    Text(permission == .denied ? text.cameraDeniedCaption : text.cameraPermissionCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(granted ? l10n.s.permissionGranted : l10n.s.permissionMissing)
                    .font(.caption)
                    .foregroundStyle(color)
            }
            .accessibilityElement(children: .combine)
            if !granted {
                HStack(spacing: 8) {
                    if permission == .notDetermined {
                        Button(l10n.s.permissionRequest, action: request)
                            .buttonStyle(.borderedProminent)
                    }
                    Button(l10n.s.permissionOpenSettings) {
                        if let url = Self.privacySettings { NSWorkspace.shared.open(url) }
                    }
                }
                .controlSize(.small)
                .padding(.leading, 24)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }
}
