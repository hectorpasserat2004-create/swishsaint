// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

/// Suite `fork-glance-profiles` — A4: layout signature, profiles, matching.
enum ForkGlanceProfilesTests {
    static func run(_ suite: TestSuite) {
        signature(suite)
        title(suite)
        matching(suite)
        newProfile(suite)
        capacity(suite)
        file(suite)
        tolerantDecoding(suite)
    }

    // MARK: Fixtures

    private static let camera = "0x1420000005ac8600"
    private static let iPhone = "C0FFEE-IPHONE"
    private static let now = Date(timeIntervalSince1970: 1_792_750_000) // 23/10/2026, a fixed instant

    private static let lg = ForkGlanceZonesTests.lg
    private static let macBook = ForkGlanceZonesTests.macBook
    private static let desk = ForkGlanceZonesTests.desk

    private static func moving(_ display: ForkGlanceDisplay, dx: CGFloat = 0, dy: CGFloat = 0) -> ForkGlanceDisplay {
        var moved = display
        moved.frame = display.frame.offsetBy(dx: dx, dy: dy)
        return moved
    }

    private static func profile(_ id: String, lastUsed: TimeInterval) -> ForkGlanceProfile {
        var profile = ForkGlanceProfiles.newProfile(
            layout: ForkGlanceDisplayLayout(displays: [ForkGlanceDisplay(
                uuid: id, name: "Display \(id)", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))]),
            cameraID: camera, now: Date(timeIntervalSince1970: lastUsed))
        // A plain id, so the list tests read: the list treats ids as opaque.
        profile.id = id
        profile.lastUsed = Date(timeIntervalSince1970: lastUsed)
        return profile
    }

    private static func calibration(version: Int = ForkGlanceCalibration.currentVersion) -> ForkGlanceCalibration {
        ForkGlanceCalibration(
            version: version, date: now, cameraID: camera,
            layoutSignature: ForkGlanceProfiles.signature(layout: desk, cameraID: camera), usesEyes: true,
            coefficientsX: [1, 2.5, -0.25], coefficientsY: [0.5, -3, 4], normalization: [ForkGlanceRange(center: 0.1, scale: 0.2)],
            sigma: CGSize(width: 120, height: 90), bias: CGVector(dx: 4, dy: -2),
            yawRange: -0.6...0.6, pitchRange: -0.3...0.4, zoneAccuracy: ["LG-UUID#0": 0.97, "LG-UUID#1": 0.95])
    }

    private static func calibrated() -> ForkGlanceProfile {
        var profile = ForkGlanceProfiles.newProfile(layout: desk, cameraID: camera, now: now)
        profile.calibration = calibration()
        let sample = ForkGlanceSample(time: 12.5, vector: Array(repeating: 0.25, count: ForkGlanceVectorLayout.count),
                                      confidence: 0.9, eyesUsable: true, facePresent: true)
        profile.learning.add(sample, click: CGPoint(x: 860, y: 720), at: Date(timeIntervalSince1970: 1_792_663_440))
        return profile
    }

    /// The JSON of `profiles` as plain objects, to break it like an old or damaged file would be.
    private static func objects(_ profiles: [ForkGlanceProfile]) -> [[String: Any]] {
        let root = try? JSONSerialization.jsonObject(with: ForkGlanceProfiles.encode(profiles)) as? [String: Any]
        return root?["profiles"] as? [[String: Any]] ?? []
    }

    private static func data(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    // MARK: Signature

    private static func signature(_ suite: TestSuite) {
        let base = ForkGlanceProfiles.signature(layout: desk, cameraID: camera)
        let reversed = ForkGlanceDisplayLayout(displays: [macBook, lg])
        suite.expect(ForkGlanceProfiles.signature(layout: reversed, cameraID: camera) == base,
                     "the order the displays are listed in does not change the signature")
        let jitter = ForkGlanceDisplayLayout(displays: [lg, moving(macBook, dx: 1, dy: -2)])
        suite.expect(ForkGlanceProfiles.signature(layout: jitter, cameraID: camera) == base,
                     "a frame within the same 8 pt step gives the same signature")
        let nameless = ForkGlanceDisplayLayout(displays: [lg, ForkGlanceDisplay(uuid: macBook.uuid, name: "Other name",
                                                                             frame: macBook.frame, isBuiltIn: true)])
        suite.expect(ForkGlanceProfiles.signature(layout: nameless, cameraID: camera) == base,
                     "a display's name, size in mm or notch are not part of the signature")
        let lidClosed = ForkGlanceDisplayLayout(displays: desk.displays, lidClosed: true)
        suite.expect(ForkGlanceProfiles.signature(layout: lidClosed, cameraID: camera) == base,
                     "the lid flag alone does not change the signature, the displays do")
        suite.expect(ForkGlanceProfiles.signature(layout: desk, cameraID: iPhone) != base, "another camera changes it")
        let moved = ForkGlanceDisplayLayout(displays: [lg, moving(macBook, dx: -938)])
        suite.expect(ForkGlanceProfiles.signature(layout: moved, cameraID: camera) != base, "a display moved changes it")
        var turned = lg
        turned.rotation = 90
        suite.expect(ForkGlanceProfiles.signature(layout: ForkGlanceDisplayLayout(displays: [turned, macBook]),
                                                  cameraID: camera) != base, "a display turned changes it")
        let other = ForkGlanceDisplayLayout(displays: [lg, ForkGlanceDisplay(uuid: "DELL-UUID", name: "DELL",
                                                                          frame: macBook.frame)])
        suite.expect(ForkGlanceProfiles.signature(layout: other, cameraID: camera) != base,
                     "another display at the same place changes it")
        suite.expect(ForkGlanceProfiles.signature(layout: desk, cameraID: camera) == base, "it is stable from call to call")
        suite.expect(base.hasPrefix(camera) && base.contains("LG-UUID") && base.contains("BUILTIN-UUID"),
                     "it names the camera and every display")
    }

    private static func title(_ suite: TestSuite) {
        suite.expect(ForkGlanceProfiles.title(for: desk) == "LG HDR WQHD + MacBook", "appendix A is « LG HDR WQHD + MacBook »")
        suite.expect(ForkGlanceProfiles.title(for: ForkGlanceDisplayLayout(displays: [macBook, lg])) == "LG HDR WQHD + MacBook",
                     "the main display comes first whatever the order")
        let side = ForkGlanceDisplay(uuid: "SIDE", name: "  DELL U2720Q ", frame: CGRect(x: -2560, y: 0, width: 2560, height: 1440))
        let three = ForkGlanceDisplayLayout(displays: [macBook, side, lg])
        suite.expect(ForkGlanceProfiles.title(for: three) == "LG HDR WQHD + DELL U2720Q + MacBook",
                     "the others follow from left to right, names trimmed")
        suite.expect(ForkGlanceProfiles.title(for: ForkGlanceDisplayLayout(displays: [])).isEmpty, "no display, no title")
    }

    // MARK: Matching

    private static func matching(_ suite: TestSuite) {
        let home = calibrated()
        var older = ForkGlanceProfiles.newProfile(layout: ForkGlanceDisplayLayout(displays: [lg, moving(macBook, dx: 400)]),
                                                  cameraID: camera, now: now.addingTimeInterval(-86_400))
        older.title = "older"
        let profiles = [older, home]

        suite.expect(ForkGlanceProfiles.match(layout: desk, cameraID: camera, in: profiles) == .identical(home),
                     "the same layout and camera find their profile")
        suite.expect(ForkGlanceProfiles.match(layout: ForkGlanceDisplayLayout(displays: [macBook, lg]), cameraID: camera,
                                              in: profiles) == .identical(home),
                     "the same displays listed in another order find it too")
        let nudged = ForkGlanceDisplayLayout(displays: [lg, moving(macBook, dx: 5)]) // 938 → 943 crosses 940
        suite.expect(ForkGlanceProfiles.signature(layout: nudged, cameraID: camera) != home.id,
                     "a 5 pt nudge can cross a rounding line of the signature")
        suite.expect(ForkGlanceProfiles.match(layout: nudged, cameraID: camera, in: profiles) == .identical(home),
                     "but a move of 8 pt or less is still the same layout")

        let shifted = ForkGlanceDisplayLayout(displays: [lg, moving(macBook, dx: -938)])
        suite.expect(ForkGlanceProfiles.match(layout: shifted, cameraID: camera, in: profiles) == .moved(home),
                     "the same displays moved by more than 8 pt load the most recently used profile, marked moved")
        let barely = ForkGlanceDisplayLayout(displays: [lg, moving(macBook, dy: 9)])
        suite.expect(ForkGlanceProfiles.match(layout: barely, cameraID: camera, in: [home]) == .moved(home),
                     "9 pt is more than 8 pt: moved")

        let newDisplay = ForkGlanceDisplayLayout(displays: [lg, ForkGlanceDisplay(uuid: "DELL-UUID", name: "DELL",
                                                                               frame: macBook.frame)])
        suite.expect(ForkGlanceProfiles.match(layout: newDisplay, cameraID: camera, in: profiles) == .unknown,
                     "another display is an unknown layout")
        let lidClosed = ForkGlanceDisplayLayout(displays: [lg], lidClosed: true)
        suite.expect(ForkGlanceProfiles.match(layout: lidClosed, cameraID: camera, in: profiles) == .unknown,
                     "a display less (lid closed) is an unknown layout")
        suite.expect(ForkGlanceProfiles.match(layout: desk, cameraID: iPhone, in: profiles) == .unknown,
                     "the same displays with another camera are unknown")
        suite.expect(ForkGlanceProfiles.match(layout: shifted, cameraID: iPhone, in: profiles) == .unknown,
                     "moved displays with another camera are unknown too")
        suite.expect(ForkGlanceProfiles.match(layout: desk, cameraID: camera, in: []) == .unknown,
                     "no profile at all is unknown")

        let iPhoneHome = ForkGlanceProfiles.newProfile(layout: desk, cameraID: iPhone, now: now)
        suite.expect(ForkGlanceProfiles.match(layout: desk, cameraID: iPhone, in: profiles + [iPhoneHome]) == .identical(iPhoneHome),
                     "each camera finds its own profile for the same desk")
        suite.expect(ForkGlanceProfiles.match(layout: shifted, cameraID: camera, in: [iPhoneHome]) == .unknown,
                     "another camera's profile is never taken as moved")
    }

    private static func newProfile(_ suite: TestSuite) {
        let profile = ForkGlanceProfiles.newProfile(layout: desk, cameraID: camera, now: now)
        suite.expect(profile.id == ForkGlanceProfiles.signature(layout: desk, cameraID: camera), "a new profile's id is the signature")
        suite.expect(profile.title == "LG HDR WQHD + MacBook", "it carries the layout's title")
        suite.expect(profile.splits == ["LG-UUID": .columns2, "BUILTIN-UUID": .whole], "it starts with the default splits")
        suite.expect(profile.calibration == nil && profile.learning.pairs.isEmpty, "it starts uncalibrated, with nothing learned")
        suite.expect(profile.lastUsed == now && profile.layout == desk, "it keeps its layout and when it was made")
    }

    private static func capacity(_ suite: TestSuite) {
        suite.expect(ForkGlanceProfiles.capacity == 12, "twelve profiles at most")
        let twelve = (0..<12).map { profile("D\($0)", lastUsed: 1000 + Double($0) * 10) }
        let full = (0..<12).reduce([ForkGlanceProfile]()) { list, index in ForkGlanceProfiles.upserting(twelve[index], into: list) }
        suite.expect(full.map(\.id) == twelve.map(\.id), "up to twelve profiles are added in order")

        var touched = twelve[4]
        touched.lastUsed = Date(timeIntervalSince1970: 5000)
        touched.splits = ["D4": .grid2x2]
        let replaced = ForkGlanceProfiles.upserting(touched, into: full)
        suite.expect(replaced.count == 12 && replaced[4] == touched, "a profile already there is replaced where it stands")

        let thirteenth = profile("D12", lastUsed: 6000)
        let bounded = ForkGlanceProfiles.upserting(thirteenth, into: full)
        suite.expect(bounded.count == 12, "a thirteenth profile keeps the list at twelve")
        suite.expect(!bounded.contains { $0.id == "D0" } && bounded.last == thirteenth,
                     "the least recently used one goes and the new one is kept")

        let stale = profile("OLD", lastUsed: 1)
        let kept = ForkGlanceProfiles.upserting(stale, into: full)
        suite.expect(kept.count == 12 && kept.contains { $0.id == "OLD" } && !kept.contains { $0.id == "D0" },
                     "the profile being saved is never the one dropped, even when it is the oldest")

        var overfull = full + [profile("X", lastUsed: 2), profile("Y", lastUsed: 3)]
        overfull = ForkGlanceProfiles.upserting(profile("Z", lastUsed: 9000), into: overfull)
        suite.expect(overfull.count == 12 && !overfull.contains { ["X", "Y", "D0"].contains($0.id) },
                     "a list already too long is brought back to twelve")
    }

    // MARK: File

    private static func file(_ suite: TestSuite) {
        let profiles = [calibrated(), profile("D1", lastUsed: 1234.5)]
        let data = ForkGlanceProfiles.encode(profiles)
        suite.expect(ForkGlanceProfiles.decode(data) == profiles, "profiles come back from their file unchanged")
        suite.expect(ForkGlanceProfiles.encode(profiles) == data, "the same profiles always make the same bytes")
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        suite.expect(root?["version"] as? Int == ForkGlanceProfiles.fileVersion, "the file says its version")
        suite.expect(ForkGlanceProfiles.decode(ForkGlanceProfiles.encode([])).isEmpty, "an empty list stays empty")

        var odd = calibrated()
        odd.calibration?.sigma = CGSize(width: Double.infinity, height: 1)
        let oddBack = ForkGlanceProfiles.decode(ForkGlanceProfiles.encode([odd]))
        suite.expect(oddBack.first?.calibration?.sigma.width == .infinity,
                     "a non-finite number does not stop the file from being written and read")
    }

    private static func tolerantDecoding(_ suite: TestSuite) {
        let good = calibrated()
        let other = profile("D1", lastUsed: 100)
        suite.expect(ForkGlanceProfiles.decode(Data()).isEmpty, "an empty file gives no profile")
        suite.expect(ForkGlanceProfiles.decode(Data("{\"version\":1,\"profiles\":[{\"id\":".utf8)).isEmpty,
                     "a truncated file gives no profile, without failing")
        suite.expect(ForkGlanceProfiles.decode(Data([0xFF, 0xFE, 0x00, 0x42])).isEmpty, "bytes that are not JSON give no profile")
        suite.expect(ForkGlanceProfiles.decode(Data("{\"something\":\"else\"}".utf8)).isEmpty, "another JSON gives no profile")

        let list = objects([good, other])
        suite.expect(list.count == 2, "the fixture has two profiles")
        suite.expect(ForkGlanceProfiles.decode(data(list)) == [good, other],
                     "an early file, a bare array without version, is read")

        var broken = list
        broken.insert(["id": 42, "layout": "nope"], at: 1)
        broken.append(["title": "no id"])
        let salvaged = ForkGlanceProfiles.decode(data(["version": 1, "profiles": broken]))
        suite.expect(salvaged == [good, other], "a damaged profile is dropped and the others kept")

        var old = list[1]
        old.removeValue(forKey: "lastUsed")
        old.removeValue(forKey: "learned")
        old.removeValue(forKey: "title")
        if var layout = old["layout"] as? [String: Any] {
            layout.removeValue(forKey: "lidClosed")
            if var displays = layout["displays"] as? [[String: Any]] {
                displays[0].removeValue(forKey: "hasNotch")
                displays[0].removeValue(forKey: "rotation")
                layout["displays"] = displays
            }
            old["layout"] = layout
        }
        let oldBack = ForkGlanceProfiles.decode(data([old])).first
        suite.expect(oldBack?.id == other.id && oldBack?.layout == other.layout,
                     "a profile from an older version, fields missing, keeps its id and layout")
        suite.expect(oldBack?.lastUsed == .distantPast && oldBack?.learning.pairs.isEmpty == true && oldBack?.title == other.title,
                     "its missing fields take safe values: never used, nothing learned, the title from its displays")

        var futureSplit = list[0]
        futureSplit["splits"] = ["LG-UUID": "columns5", "BUILTIN-UUID": "whole"]
        suite.expect(ForkGlanceProfiles.decode(data([futureSplit])).first?.splits == ["BUILTIN-UUID": .whole],
                     "an unknown split is forgotten, the profile kept")

        var futureCalibration = list[0]
        if var calibration = futureCalibration["calibration"] as? [String: Any] {
            calibration["version"] = ForkGlanceCalibration.currentVersion + 1
            futureCalibration["calibration"] = calibration
        }
        let recalibrate = ForkGlanceProfiles.decode(data([futureCalibration])).first
        suite.expect(recalibrate?.id == good.id && recalibrate?.calibration == nil && recalibrate?.learning == good.learning,
                     "a calibration of another version is dropped, the profile and what it learned kept")

        var badCalibration = list[0]
        badCalibration["calibration"] = ["version": 1, "coefficientsX": "garbage"]
        suite.expect(ForkGlanceProfiles.decode(data([badCalibration])).first?.calibration == nil,
                     "an unreadable calibration is dropped, the profile kept")

        var badLearning = list[0]
        badLearning["learning"] = ["pairs": "garbage"]
        let relearn = ForkGlanceProfiles.decode(data([badLearning])).first
        suite.expect(relearn?.id == good.id && relearn?.calibration == good.calibration
                        && relearn?.learning.pairs.isEmpty == true,
                     "an unreadable learning is dropped, the profile and its calibration kept")
        suite.expect(!good.learning.pairs.isEmpty, "the stored profile does carry learned clicks, with their dates")

        var noDisplay = list[1]
        noDisplay["layout"] = ["displays": [], "lidClosed": false]
        suite.expect(ForkGlanceProfiles.decode(data([noDisplay, list[0]])) == [good], "a profile without a display is dropped")

        suite.expect(ForkGlanceProfiles.decode(data([list[0], list[1], list[0]])) == [good, other],
                     "a profile listed twice is read once, the first one")
    }
}
