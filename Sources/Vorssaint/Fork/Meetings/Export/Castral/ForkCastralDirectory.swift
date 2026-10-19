// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The CRM's appointments read **at the moment of an offer** (B7), not at
/// launch: the offer of a call whose Google Meet code is an appointment's
/// says so ("Appointment: ACME · 10:00").
///
/// - Only with a CRM set up (its profile and its token in the Keychain,
///   asked there off the main thread, not from what the page last saw),
///   only for a call with a code, once per offer.
/// - Forgotten when the offer ends (B2): nothing here ever reaches a
///   meeting. A send reads the appointments again, and matches them to the
///   code the recorded meeting itself keeps.
///
/// Main thread, but the reading.
final class ForkCastralDirectory {
    static let shared = ForkCastralDirectory()

    private let exports: ForkMeetingExports
    /// The appointment found for the offer's code, while it lasts.
    private var found: (code: String, booking: ForkCastralContract.Booking)?
    /// The code asked for the offer shown, while it lasts.
    private var asked: String?
    /// Bumped by `forget`: an answer for an offer gone is dropped.
    private var generation = 0

    init(exports: ForkMeetingExports = .shared) {
        self.exports = exports
    }

    func offered(meetCode: String?) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let code = meetCode?.lowercased(), !code.isEmpty, asked != code,
              let config = exports.castralConfig, !exports.listChanged else { return }
        asked = code
        let job = generation
        let exporter = exports.castralExporter(config, request: nil)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let now = Date()
            guard let client = try? exporter.credentials(),
                  case let .success(bookings) = (try? ForkMeetingExports.blocking({
                      await client.targets(from: now.addingTimeInterval(-6 * 3600), to: now.addingTimeInterval(6 * 3600))
                  })) else { return }
            let booking = ForkCastralMatch.byCode(bookings, meetCode: code, now: now)
            DispatchQueue.main.async { [weak self] in
                guard let self, job == generation, asked == code, let booking else { return }
                found = (code, booking)
                ForkMeetingService.shared.presenter.redrawOffer()
            }
        }
    }

    /// The offer's line for this code, when its appointment was found.
    func line(meetCode: String?, text: ForkMeetingStrings) -> String? {
        guard let found, found.code == meetCode?.lowercased() else { return nil }
        let who = found.booking.who ?? text.castralNoCompany
        guard let start = found.booking.startAt else { return text.castralBooking(who) }
        return text.castralBooking("\(who) · \(ForkMeetingLibraryText.time(start, language: L10n.shared.language))")
    }

    func forget() {
        dispatchPrecondition(condition: .onQueue(.main))
        generation += 1
        found = nil
        asked = nil
    }
}
