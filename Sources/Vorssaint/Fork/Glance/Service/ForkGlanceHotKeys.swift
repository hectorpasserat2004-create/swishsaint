// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Carbon.HIToolbox
import Foundation
import os

/// Glance Focus's global shortcuts (plan §12.8): Pause/Reprendre, Recentrer,
/// Changer de mode, as Carbon hotkeys like `ForkMeetingHotKey`: no permission
/// needed. Installed while the feature is on, each with a combination that
/// has no problem (`ForkGlanceShortcuts.usable`); everything is removed when
/// it turns off, the event handler included.
///
/// Main thread only.
final class ForkGlanceHotKeys {
    static let shared = ForkGlanceHotKeys()

    /// 'SwGl'. The dispatcher hands every registered hotkey to every handler:
    /// the signature tells ours from the official ones and the Meetings'.
    private static let signature: OSType = 0x5377_476C

    /// Main thread, once per press.
    var onPress: ((ForkGlanceShortcutRole) -> Void)?

    /// The combinations installed now.
    private(set) var registered: [ForkGlanceShortcutRole: GlobalShortcut] = [:]
    /// macOS refused the combination asked for: another app holds it.
    private(set) var refused: Set<ForkGlanceShortcutRole> = []

    private var refs: [ForkGlanceShortcutRole: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private let log = Logger(subsystem: "fork.glance", category: "hotkeys")

    private init() {}

    /// Installs what each role should have now, or removes everything.
    func sync(enabled: Bool) {
        precondition(Thread.isMainThread)
        for role in ForkGlanceShortcutRole.allCases {
            set(role, enabled ? ForkGlanceShortcuts.usable(role) : nil)
        }
        if refs.isEmpty, let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func set(_ role: ForkGlanceShortcutRole, _ shortcut: GlobalShortcut?) {
        guard let shortcut else {
            unregister(role)
            refused.remove(role)
            return
        }
        if refs[role] != nil, registered[role] == shortcut { return }
        unregister(role)
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.carbonKeyCode, shortcut.carbonModifiers,
                                         EventHotKeyID(signature: Self.signature, id: Self.identifier(role)),
                                         GetEventDispatcherTarget(), 0, &ref)
        if status == noErr, let ref {
            refs[role] = ref
            registered[role] = shortcut
            refused.remove(role)
        } else {
            refused.insert(role)
            log.notice("a shortcut was refused by macOS (\(role.rawValue, privacy: .public))")
        }
    }

    private func unregister(_ role: ForkGlanceShortcutRole) {
        if let ref = refs.removeValue(forKey: role) { UnregisterEventHotKey(ref) }
        registered[role] = nil
    }

    private static func identifier(_ role: ForkGlanceShortcutRole) -> UInt32 {
        switch role {
        case .pause: return 1
        case .recenter: return 2
        case .mode: return 3
        }
    }

    fileprivate static func role(for identifier: UInt32) -> ForkGlanceShortcutRole? {
        ForkGlanceShortcutRole.allCases.first { Self.identifier($0) == identifier }
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData -> OSStatus in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            // Someone else's key: handed back, so the dispatcher goes on.
            guard id.signature == ForkGlanceHotKeys.signature, let role = ForkGlanceHotKeys.role(for: id.id) else {
                return OSStatus(eventNotHandledErr)
            }
            let hotKeys = Unmanaged<ForkGlanceHotKeys>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { hotKeys.onPress?(role) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }
}
