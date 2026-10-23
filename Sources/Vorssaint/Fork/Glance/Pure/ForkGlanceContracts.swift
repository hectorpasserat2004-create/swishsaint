// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import CoreGraphics
import Foundation

// Glance Focus: the types every part of the feature shares (plan §4). Frozen
// after wave 0: a change goes through the orchestrator, who tells the parts
// that use it. Pure: no AppKit, AVFoundation or Vision, so the tests compile
// it (fork/test.sh). Geometry is in global points with the origin at the top
// left, like `CGDisplayBounds` and Accessibility, unless a field says otherwise.

// MARK: - Signal

/// What Vision saw in one camera image (`Engine/ForkGlanceVision`).
struct ForkGlanceObservation: Sendable, Equatable {
    /// `ProcessInfo.systemUptime` of the image.
    var time: TimeInterval
    /// Normalized 0…1, origin at the bottom left (Vision's own space).
    var faceBox: CGRect
    /// Radians, revision 3 (continuous). Nil when Vision gave none.
    var yaw: Double?
    var pitch: Double?
    var roll: Double?
    /// Normalized in the image, origin at the bottom left.
    var leftPupil: CGPoint?
    var rightPupil: CGPoint?
    /// Eye outlines (landmarks), image-normalized; empty when not computed.
    var leftEye: [CGPoint]
    var rightEye: [CGPoint]
    /// Faces in the image, the kept one included (`lowConfidence` guard).
    var faceCount: Int
    /// The largest other face's area over the kept one's, 0 when alone.
    var otherFaceRatio: Double
    /// `VNDetectFaceCaptureQualityRequest`, only asked for in the assistant.
    var captureQuality: Double?

    init(time: TimeInterval, faceBox: CGRect, yaw: Double? = nil, pitch: Double? = nil, roll: Double? = nil,
         leftPupil: CGPoint? = nil, rightPupil: CGPoint? = nil, leftEye: [CGPoint] = [], rightEye: [CGPoint] = [],
         faceCount: Int = 1, otherFaceRatio: Double = 0, captureQuality: Double? = nil) {
        self.time = time
        self.faceBox = faceBox
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
        self.leftPupil = leftPupil
        self.rightPupil = rightPupil
        self.leftEye = leftEye
        self.rightEye = rightEye
        self.faceCount = faceCount
        self.otherFaceRatio = otherFaceRatio
        self.captureQuality = captureQuality
    }
}

/// Where each component sits in `ForkGlanceSample.vector` (plan §8.1). The
/// head-only profile uses the first `headCount` components.
enum ForkGlanceVectorLayout {
    static let yaw = 0
    static let pitch = 1
    static let roll = 2
    /// Face center, image-normalized.
    static let centerX = 3
    static let centerY = 4
    /// Distance between the eyes, image-normalized: a proxy for distance.
    static let size = 5
    /// Pupil inside the eye outline, 0…1 on each axis.
    static let leftEyeX = 6
    static let leftEyeY = 7
    static let rightEyeX = 8
    static let rightEyeY = 9
    /// Eye opening (height over width of the outline).
    static let openness = 10

    static let count = 11
    static let headCount = 6

    /// The components a profile's model reads.
    static func components(usesEyes: Bool) -> Range<Int> { 0..<(usesEyes ? count : headCount) }
}

/// One filtered measure, the model's input (`Pure/ForkGlanceFeatures`).
struct ForkGlanceSample: Sendable, Codable, Equatable {
    var time: TimeInterval
    /// `ForkGlanceVectorLayout.count` values, raw units (radians, normalized
    /// image coordinates); the model reduces them with the calibration's ranges.
    var vector: [Double]
    /// 0…1.
    var confidence: Double
    /// False on a blink or doubtful pupils: the eye components then repeat
    /// their last filtered value.
    var eyesUsable: Bool
    var facePresent: Bool
}

/// How a vector component is reduced: `(value - center) / scale`.
struct ForkGlanceRange: Sendable, Codable, Equatable {
    var center: Double
    /// Always > 0.
    var scale: Double

    func reduce(_ value: Double) -> Double { (value - center) / scale }
    func expand(_ reduced: Double) -> Double { reduced * scale + center }
}

// MARK: - Geometry

struct ForkGlanceDisplay: Sendable, Codable, Equatable, Hashable {
    /// `CGDisplayCreateUUIDFromDisplayID`, stable across launches.
    var uuid: String
    /// `NSScreen.localizedName`.
    var name: String
    /// Global points, origin at the top left of the main display.
    var frame: CGRect
    /// `CGDisplayScreenSize`; nil when the display reports none.
    var millimeters: CGSize?
    var isBuiltIn: Bool
    var hasNotch: Bool
    /// `CGDisplayRotation`, degrees.
    var rotation: Double

    init(uuid: String, name: String, frame: CGRect, millimeters: CGSize? = nil, isBuiltIn: Bool = false,
         hasNotch: Bool = false, rotation: Double = 0) {
        self.uuid = uuid
        self.name = name
        self.frame = frame
        self.millimeters = millimeters
        self.isBuiltIn = isBuiltIn
        self.hasNotch = hasNotch
        self.rotation = rotation
    }
}

struct ForkGlanceDisplayLayout: Sendable, Codable, Equatable {
    var displays: [ForkGlanceDisplay]
    /// The built-in display's lid (`AppleClamshellState`).
    var lidClosed: Bool

    init(displays: [ForkGlanceDisplay], lidClosed: Bool = false) {
        self.displays = displays
        self.lidClosed = lidClosed
    }
}

enum ForkGlanceMode: String, Sendable, Codable, CaseIterable {
    case screens
    case zones
    case windows

    static let fallback: ForkGlanceMode = .zones
}

enum ForkGlanceSplit: String, Sendable, Codable, CaseIterable {
    case whole
    case columns2
    case columns3
    case rows2
    case grid2x2
}

/// Where a zone sits on its display, to name it (« Zone gauche du LG »).
enum ForkGlancePosition: String, Sendable, Codable, Hashable, CaseIterable {
    case whole
    case left
    case center
    case right
    case top
    case bottom
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    /// Windows mode: the zone is a window.
    case window
}

struct ForkGlanceZone: Sendable, Codable, Equatable, Hashable {
    /// "<display uuid>#<index>", or "win:<CGWindowID>" in Windows mode.
    var id: String
    var displayUUID: String
    /// Global points. In Windows mode, the largest rectangle of the window
    /// left visible on its display.
    var rect: CGRect
    var position: ForkGlancePosition
    /// Windows mode only.
    var windowID: UInt32?

    init(id: String, displayUUID: String, rect: CGRect, position: ForkGlancePosition, windowID: UInt32? = nil) {
        self.id = id
        self.displayUUID = displayUUID
        self.rect = rect
        self.position = position
        self.windowID = windowID
    }
}

/// A window on screen, read from the window server (`Focus/ForkGlanceWindowIndex`).
struct ForkGlanceWindow: Sendable, Codable, Equatable, Hashable {
    /// `CGWindowID`.
    var id: UInt32
    var pid: Int32
    var bundleID: String?
    var appName: String
    /// Global points.
    var frame: CGRect
    /// Parked on a hidden Space (`SpaceWindowBridge.isParkedOnHiddenSpace`).
    var isOnHiddenSpace: Bool

    init(id: UInt32, pid: Int32, bundleID: String?, appName: String, frame: CGRect, isOnHiddenSpace: Bool = false) {
        self.id = id
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.frame = frame
        self.isOnHiddenSpace = isOnHiddenSpace
    }
}

/// The window a zone hands the keyboard to.
struct ForkGlanceTarget: Sendable, Equatable {
    var zoneID: String
    var window: ForkGlanceWindow
}

// MARK: - Calibration and profiles

struct ForkGlanceCalibrationPoint: Sendable, Codable, Equatable {
    /// Global points.
    var target: CGPoint
    var samples: [ForkGlanceSample]
}

struct ForkGlanceCalibration: Sendable, Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var date: Date
    /// `AVCaptureDevice.uniqueID`.
    var cameraID: String
    var layoutSignature: String
    var usesEyes: Bool
    /// Ridge coefficients over the reduced vector's degree-2 terms
    /// (`Pure/ForkGlanceRegression`), one set per axis.
    var coefficientsX: [Double]
    var coefficientsY: [Double]
    /// One range per component of `ForkGlanceVectorLayout.components(usesEyes:)`.
    var normalization: [ForkGlanceRange]
    /// Standard error in points, from the cross-validation, per axis.
    var sigma: CGSize
    /// The « Recentrer » offset, points.
    var bias: CGVector
    /// Yaw and pitch seen during the calibration, radians: past them by a
    /// margin, the gaze is away (plan §7.2).
    var yawRange: ClosedRange<Double>
    var pitchRange: ClosedRange<Double>
    /// Zone id → share of validation hits, 0…1.
    var zoneAccuracy: [String: Double]
}

struct ForkGlanceProfile: Sendable, Codable, Equatable, Identifiable {
    /// The layout signature (`Pure/ForkGlanceProfiles`).
    var id: String
    /// « LG HDR WQHD + MacBook », from the display names.
    var title: String
    var layout: ForkGlanceDisplayLayout
    /// Display uuid → split (Zones mode).
    var splits: [String: ForkGlanceSplit]
    var calibration: ForkGlanceCalibration?
    /// Pairs learned from clicks, bounded (`Pure/ForkGlanceLearning`).
    var learned: [ForkGlanceCalibrationPoint]
    /// Last time this profile was loaded, to drop the oldest unused one.
    var lastUsed: Date
}

/// How good a validation score is (plan §8.4, step 6).
enum ForkGlanceGrade: String, Sendable, Codable, CaseIterable {
    case excellent
    case good
    case fair
    case poor

    init(score: Double) {
        switch score {
        case 0.95...: self = .excellent
        case 0.85..<0.95: self = .good
        case 0.70..<0.85: self = .fair
        default: self = .poor
        }
    }
}

// MARK: - Decision

/// Where the model puts the gaze.
struct ForkGlanceEstimate: Sendable, Codable, Equatable {
    /// Global points.
    var point: CGPoint
    /// Points, per axis.
    var sigma: CGSize
    var time: TimeInterval
    /// 0…1.
    var confidence: Double
}

/// What the classifier makes of an estimate (`Pure/ForkGlanceClassifier`).
enum ForkGlanceGazeTarget: Sendable, Codable, Equatable {
    /// Clearly in this zone: past the entry margin, or within the stay
    /// margin of the current zone.
    case zone(String)
    /// On a screen, but no zone wins with enough margin: keep the current one.
    case between
    /// Off every screen, past the calibrated yaw, or below the lowest screen
    /// (the keyboard): never act.
    case away
    /// No usable face this image.
    case noFace
}

struct ForkGlanceGaze: Sendable, Codable, Equatable {
    var estimate: ForkGlanceEstimate?
    var target: ForkGlanceGazeTarget
    /// The winning zone's signed margin in σ (positive inside), 0 otherwise.
    var margin: Double
    /// Filtered head speed, degrees per second (the governor's « moving »).
    var headSpeed: Double
    /// The sample's confidence and face count, for the `lowConfidence` guard.
    var confidence: Double
    var crowded: Bool
}

/// What holds a switch back (plan §7.4).
enum ForkGlanceGuard: String, Sendable, Codable, CaseIterable {
    case typing
    case pointer
    case buttonsOrModifiers
    case secureInput
    case dictation
    case menuOrOverview
    case islandOpen
    case ownPanel
    case excludedSource
    case calibrating
    case cooldown
    case lowConfidence
}

/// Why the camera is off for now (plan §7.5).
enum ForkGlancePauseReason: String, Sendable, Codable, CaseIterable {
    case user
    case locked
    case asleep
    case screensAsleep
    case sessionInactive
    case idle
    case battery
    case lowPower
    case thermal
    case cameraBusy
    case call
    case singleScreen
    case lidClosedNoCamera

    /// Shown first when several hold (plan §7.5): user > locked > call >
    /// cameraBusy > battery > lowPower > thermal > idle > the others.
    static let displayOrder: [ForkGlancePauseReason] = [
        .user, .locked, .call, .cameraBusy, .battery, .lowPower, .thermal, .idle,
        .asleep, .screensAsleep, .sessionInactive, .singleScreen, .lidClosedNoCamera,
    ]

    /// The reason shown among several.
    static func shown(_ reasons: Set<ForkGlancePauseReason>) -> ForkGlancePauseReason? {
        displayOrder.first(where: reasons.contains)
    }

    /// The person may override it (« Reprendre quand même »).
    var canResumeAnyway: Bool { self == .battery || self == .lowPower || self == .thermal }
}

enum ForkGlanceUnavailable: String, Sendable, Codable, CaseIterable {
    case cameraPermission
    case accessibilityPermission
    case noCamera
    case cameraDisconnected
    case cameraFailed
}

/// Why the feature waits for a calibration.
enum ForkGlanceCalibrationNeed: String, Sendable, Codable, CaseIterable {
    /// Never calibrated on this Mac.
    case firstTime
    /// A display layout without a profile.
    case newLayout
    /// Another camera than the profile's.
    case newCamera
    /// The profile was deleted.
    case removed
}

/// The machine's state (plan §7.1), what every surface draws (plan §9).
enum ForkGlancePhase: Sendable, Equatable {
    case off
    case unavailable(ForkGlanceUnavailable)
    case needsCalibration(ForkGlanceCalibrationNeed)
    case calibrating
    /// The reason shown (`ForkGlancePauseReason.shown`), and the end of a
    /// timed user pause (systemUptime), nil until resumed.
    case paused(ForkGlancePauseReason, until: TimeInterval?)
    case starting
    /// No face.
    case searching
    /// Looking off the screens; the zone the keyboard is in stays.
    case away(zone: String?)
    case settled(zone: String?)
    /// `zone` held since `since`, a switch at `since + dwell`.
    case candidate(zone: String, current: String?, since: TimeInterval)
    case blocked(zone: String?, guards: [ForkGlanceGuard])
    case cooldown(zone: String?, until: TimeInterval)

    /// The camera runs in this phase.
    var isWatching: Bool {
        switch self {
        case .starting, .searching, .away, .settled, .candidate, .blocked, .cooldown: return true
        case .off, .unavailable, .needsCalibration, .calibrating, .paused: return false
        }
    }
}

/// What the person's input is doing, read at each image (`Engine/ForkGlanceInputWatch`).
/// Ages only: no key is ever read.
struct ForkGlanceInputSnapshot: Sendable, Codable, Equatable {
    /// Seconds since the last key event.
    var sinceKey: TimeInterval
    /// Seconds since the pointer last moved or scrolled, the pointer Glance
    /// moved itself excluded.
    var sincePointer: TimeInterval
    var buttonsDown: Bool
    /// ⌘⌃⌥⇧ held.
    var modifiersDown: Bool
    /// `IsSecureEventInputEnabled()`.
    var secureInput: Bool
    /// The fork's Dictation records or pastes.
    var dictationActive: Bool
    /// A menu, Mission Control, App Exposé or a screenshot selection.
    var menuOrOverview: Bool
    /// The island is open with the keyboard.
    var islandKey: Bool
    /// A Swishsaint window is key: Settings, Command Bar, the assistant.
    var ownPanelKey: Bool
    var frontmostBundleID: String?

    static let idle = ForkGlanceInputSnapshot(sinceKey: .infinity, sincePointer: .infinity, buttonsDown: false,
                                              modifiersDown: false, secureInput: false, dictationActive: false,
                                              menuOrOverview: false, islandKey: false, ownPanelKey: false,
                                              frontmostBundleID: nil)
}

enum ForkGlanceThermal: Int, Sendable, Codable, CaseIterable, Comparable {
    case nominal
    case fair
    case serious
    case critical

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum ForkGlanceCameraPermission: String, Sendable, Codable {
    case granted
    case denied
    case notDetermined
}

/// The Mac's state (`Engine/ForkGlancePowerWatch`, `ForkMeetingSystemEvents`,
/// `SessionActivity`, the camera's sharing).
struct ForkGlanceSystemSnapshot: Sendable, Codable, Equatable {
    var locked: Bool
    var asleep: Bool
    var screensAsleep: Bool
    var sessionInactive: Bool
    var onBattery: Bool
    var lowPower: Bool
    var thermal: ForkGlanceThermal
    /// The official camera preview is open (`CameraPreviewService`).
    var officialPreviewOpen: Bool
    /// Another app films with the chosen camera (`isInUseByAnotherApplication`).
    var cameraInUseElsewhere: Bool
    /// The lid is closed and the chosen camera is the built-in one.
    var lidClosedOnBuiltInCamera: Bool
    var displayCount: Int
    var cameraPermission: ForkGlanceCameraPermission
    var accessibility: Bool
    /// A camera is chosen and connected.
    var cameraPresent: Bool

    static let ready = ForkGlanceSystemSnapshot(locked: false, asleep: false, screensAsleep: false,
                                                sessionInactive: false, onBattery: false, lowPower: false,
                                                thermal: .nominal, officialPreviewOpen: false,
                                                cameraInUseElsewhere: false, lidClosedOnBuiltInCamera: false,
                                                displayCount: 2, cameraPermission: .granted, accessibility: true,
                                                cameraPresent: true)
}

// MARK: - Settings

enum ForkGlancePointerBehavior: String, Sendable, Codable, CaseIterable {
    /// Follow the screen in Screens mode, stay otherwise.
    case auto
    case stay
    case followScreen
    case windowCenter

    static let fallback: ForkGlancePointerBehavior = .auto

    func resolved(for mode: ForkGlanceMode) -> ForkGlancePointerBehavior {
        guard self == .auto else { return self }
        return mode == .screens ? .followScreen : .stay
    }
}

enum ForkGlanceFeedback: String, Sendable, Codable, CaseIterable {
    case none
    case halo
    case zoneFlash

    static let fallback: ForkGlanceFeedback = .halo
}

enum ForkGlanceEnergy: String, Sendable, Codable, CaseIterable {
    case saver
    case balanced
    case reactive

    static let fallback: ForkGlanceEnergy = .balanced
}

enum ForkGlanceBatteryPolicy: String, Sendable, Codable, CaseIterable {
    case same
    case saver
    case pause

    static let fallback: ForkGlanceBatteryPolicy = .saver
}

enum ForkGlanceCallPolicy: String, Sendable, Codable, CaseIterable {
    case keepRunning = "continue"
    case pause

    static let fallback: ForkGlanceCallPolicy = .keepRunning
}

/// What the closed island shows (plan §11.6, D5).
enum ForkGlanceIslandClosed: String, Sendable, Codable, CaseIterable {
    case never
    case paused
    case always

    static let fallback: ForkGlanceIslandClosed = .paused
}

/// The island's notices, each with its switch (plan §11.4).
enum ForkGlanceNoticeKind: String, Sendable, Codable, CaseIterable {
    /// « Regard en pause » and « Regard repris ».
    case pause
    case newLayout
    case camera
    case recenter
    case calibrated
    case drift

    var defaultOn: Bool { self != .recenter }
}

/// Every setting, resolved from the person's steps (`ForkGlanceSettings.read`
/// in `Pure/ForkGlanceDefaults`). Durations in seconds.
struct ForkGlanceSettings: Sendable, Codable, Equatable {
    var enabled: Bool
    var mode: ForkGlanceMode
    /// The entry margin's extra `s` (plan §7.2).
    var sensitivity: Double
    /// For the current mode.
    var dwell: TimeInterval
    var typingPause: TimeInterval
    var pointerPause: TimeInterval
    var raise: Bool
    /// Already resolved for the mode (never `.auto`).
    var pointer: ForkGlancePointerBehavior
    var feedback: ForkGlanceFeedback
    var learnFromClicks: Bool
    var panes: Bool
    var panesClickFallback: Bool
    /// Bundle ids; one ending with "." matches a prefix (« com.jetbrains. »).
    var panesApps: [String]
    var neverLeaveApps: Set<String>
    var neverFocusApps: Set<String>
    var energy: ForkGlanceEnergy
    var onBattery: ForkGlanceBatteryPolicy
    var pauseInLowPower: Bool
    /// Nil: never.
    var idleOff: TimeInterval?
    var duringCalls: ForkGlanceCallPolicy
    var islandClosed: ForkGlanceIslandClosed
    var gazeDot: Bool
}

// MARK: - Machine

/// What happens to the machine (plan §7.1).
enum ForkGlanceEvent: Sendable, Equatable {
    /// One processed image; nil when the camera gave nothing usable.
    case gaze(ForkGlanceGaze?)
    case zonesChanged([ForkGlanceZone])
    /// The person changed window themselves: the zone it lies in, if any.
    case focusChanged(zone: String?)
    case inputs(ForkGlanceInputSnapshot)
    case system(ForkGlanceSystemSnapshot)
    case settings(ForkGlanceSettings)
    /// Nil: the profile for this layout and camera is calibrated.
    case calibrationNeed(ForkGlanceCalibrationNeed?)
    case cameraFailure(ForkGlanceUnavailable?)
    case pause(ForkGlancePauseReason, until: TimeInterval?)
    case resume(ForkGlancePauseReason)
    /// « Reprendre quand même » for a battery, Low Power or thermal pause.
    case resumeAnyway
    case calibrationStarted
    case calibrationFinished(score: Double)
    case calibrationCancelled
    case focusResult(zone: String, succeeded: Bool)
    case tick
}

/// What the machine asks the service to do.
enum ForkGlanceEffect: Sendable, Equatable {
    case startCamera
    case stopCamera
    /// Images per second.
    case setRate(Double)
    case focus(zone: String)
    case showFeedback(zone: String)
    case notice(ForkGlanceNotice)
    case suggestRecalibration
}

/// A notice the island may show (each kind follows its switch).
enum ForkGlanceNotice: Sendable, Equatable {
    case paused(until: TimeInterval?)
    case resumed
    case newLayout
    case cameraUnavailable
    case recentered
    case calibrated(score: Double)
    case drift

    var kind: ForkGlanceNoticeKind {
        switch self {
        case .paused, .resumed: return .pause
        case .newLayout: return .newLayout
        case .cameraUnavailable: return .camera
        case .recentered: return .recenter
        case .calibrated: return .calibrated
        case .drift: return .drift
        }
    }
}

// MARK: - Surfaces

/// The status line every surface reads (plan §9), without its words:
/// `Pure/ForkGlancePresentation` makes it from the phase, the core strings
/// (`Strings/ForkGlanceStrings`) say it.
enum ForkGlanceStatusLine: Sendable, Equatable {
    case off
    case unavailable(ForkGlanceUnavailable)
    case needsCalibration(ForkGlanceCalibrationNeed)
    case calibrating(done: Int, total: Int)
    case starting
    /// « Actif · Zone gauche du LG »; nil before the first zone is known.
    case active(zoneName: String?)
    /// « En attente : vous tapez »: the first guard that holds.
    case waiting(ForkGlanceGuard)
    /// « Visage non détecté », shown after 3 s without a face.
    case noFace
    case away
    /// A timed user pause carries its end; « jusqu'à reprise » and the
    /// automatic pauses carry none.
    case paused(ForkGlancePauseReason, until: Date?)
}

/// The pauses a person picks (tile, shortcut, Command Bar, section, page).
enum ForkGlancePauseDuration: String, Sendable, Codable, CaseIterable {
    case fifteenMinutes
    case oneHour
    case untilTomorrow
    case untilResumed

    /// When the pause ends; nil: until resumed. « Jusqu'à demain » ends at
    /// the next local midnight.
    func end(from now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .fifteenMinutes: return now.addingTimeInterval(15 * 60)
        case .oneHour: return now.addingTimeInterval(60 * 60)
        case .untilTomorrow:
            let today = calendar.startOfDay(for: now)
            return calendar.date(byAdding: .day, value: 1, to: today)
        case .untilResumed: return nil
        }
    }
}

// MARK: - Injection (real in the service, stand-ins in the tests)

protocol ForkGlanceClock {
    /// `ProcessInfo.systemUptime`-like seconds.
    var now: TimeInterval { get }
}

struct ForkGlanceSystemClock: ForkGlanceClock {
    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
}

/// The window server, read on the main thread.
protocol ForkGlanceWindowSource: AnyObject {
    /// Layer-0 windows on the current Space, front to back.
    func windows() -> [ForkGlanceWindow]
    /// Window ids, most recently used first.
    func recentWindowIDs() -> [UInt32]
    func focusedWindowID() -> UInt32?
}

protocol ForkGlanceFocusPerforming: AnyObject {
    /// Gives `target` the keyboard; false when it could not even try.
    func focus(_ target: ForkGlanceTarget, raise: Bool) -> Bool
}

protocol ForkGlanceInputSource: AnyObject {
    func snapshot() -> ForkGlanceInputSnapshot
}

protocol ForkGlanceSystemSource: AnyObject {
    func snapshot() -> ForkGlanceSystemSnapshot
}
