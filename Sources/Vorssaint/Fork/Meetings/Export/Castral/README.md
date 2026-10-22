# CRM export (recorder contract `castral-recorder/1`)

Sends a meeting's sound to a CRM that speaks the recorder contract, attached to its
appointment, for its transcript and report. **Nothing of any installation is in the code**:
everything comes from a profile the person imports once. Without one, the Meetings page shows
only the generic "Import a Profile…" in its Add menu.

## The profile (`*.swishsaint-profile`, JSON)

```json
{
  "kind": "castral-recorder/1",
  "name": "Example CRM",
  "baseURL": "https://crm.example.test",
  "uploadHost": "storage.example.test",
  "tokenHeader": "x-example-recorder-token",
  "authors": ["Alice", "Bob"],
  "filenamePrefix": "Call_",
  "dashboardPath": "/records/{company}",
  "maxUploadBytes": 50000000
}
```

`name` (≤ 16 characters) and `maxUploadBytes` (1 MB to 500 MB, default 50 000 000) are optional.
Every field is checked at the import and at every read (`ForkCastralProfile.parse`): HTTPS, ASCII
host, no user, query or fragment; the upload host is matched **exactly**; the header cannot be one
the system sets. The profile and the token live in the Keychain only (`castral-profile#<id>`,
`castral-token#<id>`); the preferences hold the exporter's id, mode, author and speakers.
A profile never holds the token: it is typed once on the page, written at Save.

## A send

1. **Appointment** (`ForkCastralMatch`): by hand, the person picks it in a sheet (the likeliest
   first: the meeting's own Google Meet code, then a time overlap ± 15 min, then the closest start
   within 2 h). On its own, only a sure one (code, or the only overlap) that has a company and no
   report yet; anything else is recorded as waiting for its appointment (`needsChoice`): the notice
   says "Choose the appointment" and its button, like the detail's, opens this sheet. `is_active`, then only
   `cancelled`/`no_show`, block; a report is a deposit `ready` or with `has_summary`.
2. **Sound** (`ForkCastralAudioPlan`, `ForkCastralAudio`): FLAC mono from the mix, 16 kHz, or
   8 kHz when 16 kHz is over the cap, else refused before anything opens on the server.
3. **Steps** (`ForkCastralRecord`, `castral` in `meeting.json`): `uploading` (the upload address
   in the Keychain, `castral-upload#<deposit>`) → `uploaded` → `started`. A quit resumes: the same
   address while valid (2 h, less 10 min), else that deposit is deleted and a new one opened; after
   `uploaded`, only `start`; the server's `retry` only after `started` + `failed`.
4. **Follow** (`ForkCastralTracker`): `status` every 4 s, then 10 s, then 30 s, for 30 min (2 h for a
   batch engine), resumed at launch and at each look at the meeting's detail.

The island's Meetings page reads `ForkMeetingExports.castralStatus(folder)` (phase, share, failure)
and `ForkCastralStatus.short(_:)`, 28 characters at most.

## The island's calendar

`ForkCalendarAppointments` (`Fork/Notch/Calendar/`) reads `targets` with the same client and
token, only while the island shows its calendar, at most every 5 minutes, from 12 hours ago to
two weeks ahead, in memory only. Its setting is `fork.meetings.islandAppointments` (the CRM's
block here, and the island's Content › Calendar), shown once the CRM has its token. They step
aside while a call is detected or a meeting records, if the island is visible in screenshots and
videos; the Settings window's preview of the calendar leaves them out during any call.

Known limit, kept on purpose (no extra seam): while the open island browses another month with
a countdown on, the official read for the closed island's countdown is the current week's own,
without the CRM's appointments; they count again as soon as the page closes or comes back to now.
