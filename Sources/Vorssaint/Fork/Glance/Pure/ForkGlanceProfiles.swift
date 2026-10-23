// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

/// Glance Focus: one profile per display layout and camera (plan §8.6). A
/// profile holds what only fits one desk: the splits, the calibration and
/// what the clicks taught. Pure: `Service/ForkGlanceStore` keeps the list in
/// `profiles.json`, outside the settings backup.
enum ForkGlanceProfiles {
    /// The oldest unused profile goes past this.
    static let capacity = 12

    /// Frames are rounded to this many points in the signature, and a layout
    /// whose displays all moved by no more than this is the same layout.
    static let grid: CGFloat = 8

    /// The version `encode` writes. `decode` reads any.
    static let fileVersion = 1

    // MARK: - Signature and title

    /// The camera's `uniqueID`, then each display (sorted by uuid, so the
    /// order AppKit lists them in does not count) with its frame rounded to
    /// 8 pt and its rotation. A profile's `id` is the signature of its own
    /// layout and camera.
    static func signature(layout: ForkGlanceDisplayLayout, cameraID: String) -> String {
        let displays = sorted(layout.displays).map { display -> String in
            let frame = display.frame
            let numbers = [frame.minX, frame.minY, frame.width, frame.height].map { String(rounded($0)) }
            return "\(display.uuid)@\(numbers.joined(separator: ","))@r\(Int(display.rotation.rounded()))"
        }
        return ([cameraID] + displays).joined(separator: "|")
    }

    /// « LG HDR WQHD + MacBook »: the main display first, then the others
    /// left to right and top to bottom. A laptop's built-in panel is called
    /// « MacBook », the same in every language (`isLaptopPanel`); every
    /// other display, an iMac's built-in one included, by the name macOS
    /// gives it (`NSScreen.localizedName`, in the system's language when the
    /// profile was made).
    static func title(for layout: ForkGlanceDisplayLayout) -> String {
        let main = layout.displays.firstIndex { $0.frame.origin == .zero } ?? 0
        let others = layout.displays.enumerated().filter { $0.offset != main }.map(\.element)
            .sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
        let ordered = (layout.displays.isEmpty ? [] : [layout.displays[main]]) + others
        return ordered.map { display -> String in
            isLaptopPanel(display) ? "MacBook" : display.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }.joined(separator: " + ")
    }

    /// A MacBook's panel measures at most 16.2" (412 mm) across, an iMac's at
    /// least 21.5" (546 mm): this lies between.
    static let laptopDiagonal: CGFloat = 450

    /// The built-in display is a laptop's: it has a notch (only MacBooks
    /// do), or its physical size (`CGDisplayScreenSize`) is a laptop's. A
    /// built-in display of unknown size without a notch is not assumed to be
    /// one: it keeps the name macOS gives it.
    static func isLaptopPanel(_ display: ForkGlanceDisplay) -> Bool {
        guard display.isBuiltIn else { return false }
        if display.hasNotch { return true }
        guard let size = display.millimeters, size.width > 0, size.height > 0 else { return false }
        return hypot(size.width, size.height) <= laptopDiagonal
    }

    private static func rounded(_ value: CGFloat) -> Int {
        guard value.isFinite, abs(value) < 1e9 else { return 0 }
        return Int((value / grid).rounded()) * Int(grid)
    }

    /// By uuid, then by place: two identical displays may share a uuid.
    private static func sorted(_ displays: [ForkGlanceDisplay]) -> [ForkGlanceDisplay] {
        displays.sorted { ($0.uuid, $0.frame.minX, $0.frame.minY) < ($1.uuid, $1.frame.minX, $1.frame.minY) }
    }

    // MARK: - Matching

    enum Match: Equatable {
        /// The same displays at the same places (within 8 pt), the same camera.
        case identical(ForkGlanceProfile)
        /// The same displays and camera, moved: loaded, with a hint to recenter.
        case moved(ForkGlanceProfile)
        /// Another display or another camera: a new calibration is needed.
        case unknown
    }

    /// When several profiles fit, the most recently used wins.
    static func match(layout: ForkGlanceDisplayLayout, cameraID: String,
                      in profiles: [ForkGlanceProfile]) -> Match {
        let current = signature(layout: layout, cameraID: cameraID)
        if let exact = profiles.first(where: { $0.id == current }) { return .identical(exact) }
        let sameDesk = profiles.filter { profile in
            signature(layout: profile.layout, cameraID: cameraID) == profile.id
                && sameDisplays(profile.layout, layout)
        }.sorted { $0.lastUsed > $1.lastUsed }
        if let close = sameDesk.first(where: { withinGrid($0.layout, layout) }) { return .identical(close) }
        if let moved = sameDesk.first { return .moved(moved) }
        return .unknown
    }

    private static func sameDisplays(_ lhs: ForkGlanceDisplayLayout, _ rhs: ForkGlanceDisplayLayout) -> Bool {
        lhs.displays.map(\.uuid).sorted() == rhs.displays.map(\.uuid).sorted()
    }

    /// Every display within 8 pt of where it was, turned the same way: a
    /// move that only crossed a rounding line of the signature.
    private static func withinGrid(_ lhs: ForkGlanceDisplayLayout, _ rhs: ForkGlanceDisplayLayout) -> Bool {
        let left = sorted(lhs.displays), right = sorted(rhs.displays)
        guard left.count == right.count else { return false }
        return zip(left, right).allSatisfy { a, b in
            a.uuid == b.uuid && a.rotation.rounded() == b.rotation.rounded()
                && abs(a.frame.minX - b.frame.minX) <= grid && abs(a.frame.minY - b.frame.minY) <= grid
                && abs(a.frame.width - b.frame.width) <= grid && abs(a.frame.height - b.frame.height) <= grid
        }
    }

    // MARK: - The list

    /// A layout seen for the first time: default splits, not calibrated yet.
    static func newProfile(layout: ForkGlanceDisplayLayout, cameraID: String, now: Date) -> ForkGlanceProfile {
        ForkGlanceProfile(id: signature(layout: layout, cameraID: cameraID), title: title(for: layout),
                          layout: layout, splits: ForkGlanceZones.defaultSplits(layout), calibration: nil,
                          learning: ForkGlanceLearning(), lastUsed: now)
    }

    /// Replaces the profile with the same id where it stands, or adds it at
    /// the end; past `capacity`, the least recently used others go.
    static func upserting(_ profile: ForkGlanceProfile, into profiles: [ForkGlanceProfile]) -> [ForkGlanceProfile] {
        var result = profiles
        if let index = result.firstIndex(where: { $0.id == profile.id }) {
            result[index] = profile
        } else {
            result.append(profile)
        }
        while result.count > capacity {
            let oldest = result.indices.filter { result[$0].id != profile.id }
                .min { result[$0].lastUsed < result[$1].lastUsed }
            guard let oldest else { break }
            result.remove(at: oldest)
        }
        return result
    }

    // MARK: - File

    /// `{"version": 1, "profiles": [...]}`. A profile that cannot be encoded
    /// (it never should) is left out rather than losing the others.
    static func encode(_ profiles: [ForkGlanceProfile]) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf",
                                                                      negativeInfinity: "-inf", nan: "nan")
        let kept = profiles.filter { (try? encoder.encode($0)) != nil }
        return (try? encoder.encode(File(version: fileVersion, profiles: kept))) ?? Data()
    }

    /// Whatever can be read: the current file, a bare array (an early
    /// format), a profile with fields missing or of another version. A
    /// profile without an id or a display is dropped, a calibration of
    /// another version too (the model could not read it), an unknown split
    /// is forgotten. Unreadable bytes give an empty list, never a failure.
    static func decode(_ data: Data) -> [ForkGlanceProfile] {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf",
                                                                        negativeInfinity: "-inf", nan: "nan")
        let elements: [Tolerant<LenientProfile>]
        if let file = try? decoder.decode(LenientFile.self, from: data) {
            elements = file.profiles
        } else if let array = try? decoder.decode([Tolerant<LenientProfile>].self, from: data) {
            elements = array
        } else {
            return []
        }
        var seen = Set<String>()
        return elements.compactMap(\.value?.profile).filter { seen.insert($0.id).inserted }
    }

    private struct File: Encodable {
        var version: Int
        var profiles: [ForkGlanceProfile]
    }

    private struct LenientFile: Decodable {
        var profiles: [Tolerant<LenientProfile>]
    }

    /// An element that never fails its array: nil when it cannot be read.
    private struct Tolerant<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
    }

    private struct LenientProfile: Decodable {
        let profile: ForkGlanceProfile

        private enum Keys: String, CodingKey { case id, title, layout, splits, calibration, learning, lastUsed }
        private enum LayoutKeys: String, CodingKey { case displays, lidClosed }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            let id = try container.decode(String.self, forKey: .id)
            let layoutContainer = try container.nestedContainer(keyedBy: LayoutKeys.self, forKey: .layout)
            let displays = try layoutContainer.decode([Tolerant<LenientDisplay>].self, forKey: .displays)
                .compactMap(\.value?.display)
            guard !id.isEmpty, !displays.isEmpty else {
                throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "no layout")
            }
            let layout = ForkGlanceDisplayLayout(
                displays: displays, lidClosed: (try? layoutContainer.decode(Bool.self, forKey: .lidClosed)) ?? false)
            let rawSplits = (try? container.decode([String: String].self, forKey: .splits)) ?? [:]
            var calibration = try? container.decode(ForkGlanceCalibration.self, forKey: .calibration)
            if calibration?.version != ForkGlanceCalibration.currentVersion { calibration = nil }
            profile = ForkGlanceProfile(
                id: id,
                title: (try? container.decode(String.self, forKey: .title)) ?? ForkGlanceProfiles.title(for: layout),
                layout: layout,
                splits: rawSplits.compactMapValues(ForkGlanceSplit.init(rawValue:)),
                calibration: calibration,
                learning: (try? container.decode(ForkGlanceLearning.self, forKey: .learning)) ?? ForkGlanceLearning(),
                lastUsed: (try? container.decode(Date.self, forKey: .lastUsed)) ?? .distantPast)
        }
    }

    private struct LenientDisplay: Decodable {
        let display: ForkGlanceDisplay

        private enum Keys: String, CodingKey { case uuid, name, frame, millimeters, isBuiltIn, hasNotch, rotation }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            display = ForkGlanceDisplay(
                uuid: try container.decode(String.self, forKey: .uuid),
                name: (try? container.decode(String.self, forKey: .name)) ?? "",
                frame: try container.decode(CGRect.self, forKey: .frame),
                millimeters: try? container.decode(CGSize.self, forKey: .millimeters),
                isBuiltIn: (try? container.decode(Bool.self, forKey: .isBuiltIn)) ?? false,
                hasNotch: (try? container.decode(Bool.self, forKey: .hasNotch)) ?? false,
                rotation: (try? container.decode(Double.self, forKey: .rotation)) ?? 0)
        }
    }
}
