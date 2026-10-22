// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// Fake states for SwiftUI previews, the island's settings preview
/// (`notchSettingsPreview`) and the offscreen renders. Nothing here starts
/// anything or reads a disk.
extension ForkMacBackupPresentation {
    enum Scenario: String, CaseIterable {
        case protected
        case running42
        case scanning
        case waitingPower
        case paused
        case partial
        case failedChainBroken
        case notConfigured
        case restoring
        case verifying
    }

    /// The sources and chain of a typical home setup: this Mac, Tailscale,
    /// MinIO, Proxmox, the NAS.
    static let previewChain: [ChainStatus] = [
        ChainStatus(id: "mac", kind: .mac, state: .ok),
        ChainStatus(id: "tailscale", kind: .tailscale, state: .ok, latencyMs: 12),
        ChainStatus(id: "server", kind: .s3, title: "MinIO", state: .ok, latencyMs: 18),
        ChainStatus(id: "proxmox", kind: .proxmox, state: .ok),
        ChainStatus(id: "nas", kind: .nas, title: "QNAP", state: .ok),
    ]

    static func preview(_ scenario: Scenario, now: Date = Date()) -> ForkMacBackupPresentation {
        let home = NSHomeDirectory()
        let twoHoursAgo = now.addingTimeInterval(-2 * 3_600)
        let lastWeek = now.addingTimeInterval(-6 * 86_400)
        let complete = SnapshotSummary(manifestID: "k5f3a9c2e1", date: twoHoursAgo, level: .complete,
                                       bytes: 412_000_000_000)
        let checkedChain = previewChain.map { node -> ChainStatus in
            var node = node
            node.checkedAt = now.addingTimeInterval(-300)
            return node
        }
        var state = ForkMacBackupPresentation(
            phase: .ready(next: now.addingTimeInterval(2 * 3_600)),
            sources: [SourceStatus(path: home, state: .done, last: complete, lastComplete: complete)],
            pendingChanges: 214,
            chain: checkedChain,
            nextRun: now.addingTimeInterval(2 * 3_600),
            rhythm: .automatic(about: 2 * 3_600),
            capacity: Capacity(protectedBytes: 412_000_000_000, lastSentBytes: 3_100_000_000,
                               repositoryBytes: 860_000_000_000, nasFreeBytes: 29_300_000_000_000,
                               measuredAt: now.addingTimeInterval(-6 * 3_600)),
            cost: Cost(averageDuration: 180, averageBatteryDrop: 0.8, averageSent: 1_200_000_000, samples: 12),
            updatedAt: now)

        switch scenario {
        case .protected:
            break
        case .running42:
            state.phase = .uploading
            state.sources[0].state = .running
            state.progress = Progress(bytesDone: 1_302_000_000, bytesTotal: 3_100_000_000, bytesUploaded: 1_250_000_000,
                                      files: 18_204, filesTotal: 41_000, bytesPerSecond: 18_000_000, eta: 120,
                                      currentPath: home + "/Documents/Castral/closing/pronic.com/devis.pdf")
        case .scanning:
            state.phase = .scanning
            state.sources[0].state = .running
            state.progress = Progress(bytesDone: 220_000_000, files: 2_310,
                                      currentPath: home + "/Library/Application Support")
        case .waitingPower:
            state.phase = .waiting(reason: .power, until: now.addingTimeInterval(6 * 3_600))
        case .paused:
            state.phase = .paused(until: now.addingTimeInterval(3_600))
        case .partial:
            let partial = SnapshotSummary(manifestID: "k77b01d4e2", date: twoHoursAgo, level: .present, failures: 1,
                                          bytes: 412_000_000_000)
            state.phase = .finished(.partial(files: 1))
            state.sources = [SourceStatus(path: home, state: .partial, last: partial,
                                          lastComplete: SnapshotSummary(manifestID: "k1c9d2e3f4", date: lastWeek,
                                                                        level: .contentVerified))]
        case .failedChainBroken:
            state.phase = .finished(.failed(.chainBroken))
            state.chain = checkedChain.map { node in
                var node = node
                if node.id == "server" || node.id == "proxmox" || node.id == "nas" { node.state = .unknown }
                if node.id == "server" { node.state = .broken; node.latencyMs = nil }
                return node
            }
            state.lastError = ErrorLine(cause: .chainBroken, nodeID: "server", at: now.addingTimeInterval(-60),
                                        message: "dial tcp: i/o timeout")
            state.sources[0].last = SnapshotSummary(manifestID: "k5f3a9c2e1", date: lastWeek, level: .complete)
            state.sources[0].lastComplete = state.sources[0].last
            state.sources[0].state = .failed
        case .notConfigured:
            state = ForkMacBackupPresentation(phase: .notConfigured, updatedAt: now)
        case .restoring:
            state.phase = .restoring
            state.progress = Progress(bytesDone: 640_000_000, bytesTotal: 1_000_000_000, files: 140, filesTotal: 214,
                                      bytesPerSecond: 42_000_000, eta: 9)
        case .verifying:
            state.phase = .verifying
            state.progress = Progress(bytesDone: 0, bytesTotal: nil, files: 9_000, filesTotal: 24_000)
        }
        return state
    }
}
