// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

/// The calibration assistant's words (plan §8.4, §16): its window, its seven
/// steps, the overlay over the displays, the validation and its hints. The
/// names every surface shares (modes, splits, grades, zones, « Recalibrer »,
/// « Tester »…) come from the core strings (`ForkGlanceStrings`).
///
/// Same contract as the other Glance strings: memberwise init in declaration
/// order, one static per language, placeholders filled by
/// `ForkGlanceStrings.fill` (`%@`, or `%1$@` and `%2$@`), French with
/// `\u{00A0}` before « : ; ! ? » and inside « », typographic apostrophes.
struct ForkGlanceCalibrationStrings {
    // MARK: Window
    let windowTitle: String
    /// The window's title on « Tester ».
    let testTitle: String
    /// The window's title on « Vérifier le cadrage… ».
    let framingTitle: String
    /// `%1$@`: the step's number, `%2$@`: the steps' count.
    let stepCounter: String
    let stepWelcome: String
    let stepPermissions: String
    let stepFraming: String
    let stepLayout: String
    let stepPoints: String
    let stepValidation: String
    let stepDone: String
    let cancel: String
    let back: String
    let next: String
    let start: String
    let finish: String
    let close: String

    // MARK: 1. Welcome
    let welcomeTitle: String
    let welcomeBody: String
    let privacyNothingStored: String
    let privacyOnDevice: String
    let privacyPause: String
    /// `%@`: a share of one core, « 3 % ».
    let welcomeCost: String
    /// `%@`: a duration, « Environ 1 min ».
    let welcomeDuration: String

    // MARK: 2. Permissions
    let permissionsTitle: String
    let permissionsBody: String
    let cameraName: String
    let cameraDenied: String
    let cameraRequired: String
    let accessibilityLater: String

    // MARK: 3. Framing
    let framingBody: String
    let gaugeFace: String
    let gaugeLight: String
    let gaugeDistance: String
    let gaugeFacing: String
    let adviceNoFace: String
    let adviceSeveralFaces: String
    let adviceMoreLight: String
    let adviceCloser: String
    let adviceFarther: String
    let adviceFaceScreens: String
    let adviceReady: String
    let framingHold: String
    let cameraFailed: String
    let previewLabel: String

    // MARK: 4. Layout
    let layoutTitle: String
    let layoutBody: String
    let modeLabel: String
    let splitLabel: String
    let zoneCountOne: String
    /// `%@`: a count above one.
    let zoneCountMany: String
    let windowsModeNote: String

    // MARK: 5. Points
    let pointsTitle: String
    let pointsBody: String
    let quickBody: String
    /// `%1$@`: the points, `%2$@`: a duration, « 29 points · environ 1 min ».
    let pointsSummary: String
    let keySpace: String
    let keyEscape: String
    let keyDelete: String
    /// `%1$@`: the point, `%2$@`: the points, « Point 12 sur 29 ».
    let pointsProgress: String
    let instruction: String
    let holdEyes: String
    let again: String
    let pausedHint: String
    let cancelTitle: String
    let cancelMessage: String
    let cancelConfirm: String
    let keepGoing: String
    let fitting: String
    let fitTooFew: String
    let fitDegenerate: String
    let fitFailed: String
    let startAgain: String
    let layoutChanged: String
    let cameraLost: String
    let dotLabel: String

    // MARK: 6. Validation
    let validationTitle: String
    let validationBody: String
    let startTest: String
    /// `%1$@`: the zone lit, `%2$@`: the zones lit in all, « Zone 3 sur 6 ».
    let validationProgress: String
    let lookAtZone: String
    let resultTitle: String
    let overall: String
    /// `%@`: the « Bonne » bar, « 85 % ».
    let weakCaption: String
    let redoWeak: String
    /// `%@`: a display's name.
    let adviceStacked: String
    /// `%@`: a display's name.
    let adviceSplit: String
    let adviceWindows: String
    let adviceLow: String
    let adviceExcellent: String

    // MARK: 7. Done
    let doneTitle: String
    let doneBody: String

    static func strings(_ language: AppLanguage) -> ForkGlanceCalibrationStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .uk: return .uk
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

// MARK: - Helpers

extension ForkGlanceCalibrationStrings {
    func stepName(_ step: ForkGlanceAssistantStep) -> String {
        switch step {
        case .welcome: return stepWelcome
        case .permissions: return stepPermissions
        case .framing: return stepFraming
        case .layout: return stepLayout
        case .points: return stepPoints
        case .validation: return stepValidation
        case .done: return stepDone
        }
    }

    /// « Étape 3 sur 6 ».
    func stepLine(_ number: Int, of count: Int) -> String {
        ForkGlanceStrings.fill(stepCounter, "\(number)", "\(count)")
    }

    func gaugeName(_ gauge: ForkGlanceFraming.Gauge) -> String {
        switch gauge {
        case .face: return gaugeFace
        case .light: return gaugeLight
        case .distance: return gaugeDistance
        case .facing: return gaugeFacing
        }
    }

    func framingAdvice(_ advice: ForkGlanceFraming.Advice) -> String {
        switch advice {
        case .noFace: return adviceNoFace
        case .severalFaces: return adviceSeveralFaces
        case .moreLight: return adviceMoreLight
        case .closer: return adviceCloser
        case .farther: return adviceFarther
        case .faceScreens: return adviceFaceScreens
        case .ready: return adviceReady
        }
    }

    /// « 1 zone », « 3 zones ».
    func zoneCount(_ count: Int) -> String {
        count == 1 ? zoneCountOne : ForkGlanceStrings.fill(zoneCountMany, "\(max(0, count))")
    }

    /// « Coût visé : environ 3 % d’un cœur… » (plan §10.5's target, not a measure).
    func costLine(locale: Locale) -> String {
        ForkGlanceStrings.fill(welcomeCost, ForkGlanceStrings.percent(0.03, locale: locale))
    }

    /// « Points faibles : les zones sous 85 %. »
    func weakLine(locale: Locale) -> String {
        ForkGlanceStrings.fill(weakCaption, ForkGlanceStrings.percent(ForkGlanceValidation.weakBelow, locale: locale))
    }

    /// « Environ 1 min », rounded up to the minute.
    func duration(_ seconds: TimeInterval, locale: Locale) -> String {
        ForkGlanceStrings.fill(welcomeDuration, ForkGlanceStrings.timeLeft(seconds, locale: locale))
    }

    /// « 29 points · environ 1 min ».
    func pointsLine(_ count: Int, locale: Locale) -> String {
        ForkGlanceStrings.fill(pointsSummary, "\(max(0, count))",
                               ForkGlanceStrings.timeLeft(ForkGlanceCalibrationPlan.duration(points: count), locale: locale))
    }

    /// « Point 12 sur 29 », the point under way (from 1).
    func progressLine(_ number: Int, of count: Int) -> String {
        ForkGlanceStrings.fill(pointsProgress, "\(max(0, min(number, count)))", "\(max(0, count))")
    }

    /// « Zone 3 sur 6 ».
    func validationLine(_ number: Int, of count: Int) -> String {
        ForkGlanceStrings.fill(validationProgress, "\(max(0, min(number, count)))", "\(max(0, count))")
    }

    /// A validation hint; `displayName` names a display by its uuid.
    func advice(_ advice: ForkGlanceValidationAdvice, displayName: (String) -> String) -> String {
        switch advice {
        case .stackedDisplay(let uuid): return ForkGlanceStrings.fill(adviceStacked, displayName(uuid))
        case .splitTooFine(let uuid): return ForkGlanceStrings.fill(adviceSplit, displayName(uuid))
        case .windowsMode: return adviceWindows
        case .lowOverall: return adviceLow
        case .excellent: return adviceExcellent
        }
    }
}

// MARK: - Languages

extension ForkGlanceCalibrationStrings {
    static let enUS = ForkGlanceCalibrationStrings(
        windowTitle: "Glance Calibration",
        testTitle: "Test the Calibration",
        framingTitle: "Check the Framing",
        stepCounter: "Step %1$@ of %2$@",
        stepWelcome: "Welcome",
        stepPermissions: "Access",
        stepFraming: "Framing",
        stepLayout: "Layout",
        stepPoints: "Points",
        stepValidation: "Test",
        stepDone: "Done",
        cancel: "Cancel",
        back: "Back",
        next: "Continue",
        start: "Start",
        finish: "Done",
        close: "Close",
        welcomeTitle: "The keyboard follows your gaze",
        welcomeBody: "Turn your head toward a part of your displays: the last window you used there gets the keyboard, before you even type.",
        privacyNothingStored: "No image is ever recorded: each one is analyzed in memory, then discarded.",
        privacyOnDevice: "Everything stays on this Mac: nothing is sent, and no one is recognized.",
        privacyPause: "Pause it any time, from the island, the Command Bar or a shortcut.",
        welcomeCost: "Target cost: about %@ of one core. The camera turns off when you leave the Mac alone, and its green light stays on while it runs.",
        welcomeDuration: "About %@, sitting as you usually do.",
        permissionsTitle: "Two permissions",
        permissionsBody: "The camera measures where your head turns; Accessibility hands the keyboard to the window you look at.",
        cameraName: "Camera",
        cameraDenied: "Camera access is turned off: allow it in System Settings › Privacy & Security › Camera.",
        cameraRequired: "The camera is needed to go on.",
        accessibilityLater: "Without Accessibility you can calibrate, but the keyboard will not follow your gaze yet.",
        framingBody: "Sit as you usually do, facing your displays. The frame follows your face.",
        gaugeFace: "Face detected",
        gaugeLight: "Light",
        gaugeDistance: "Distance",
        gaugeFacing: "Facing",
        adviceNoFace: "Bring your face into the picture.",
        adviceSeveralFaces: "Only one person in front of the camera, please.",
        adviceMoreLight: "A little more light on your face.",
        adviceCloser: "Come a little closer.",
        adviceFarther: "Move back a little.",
        adviceFaceScreens: "Face your displays, your face in the middle of the picture.",
        adviceReady: "Perfect: keep this position.",
        framingHold: "Continue turns on once the four gauges stay green for a second.",
        cameraFailed: "The camera does not start. Check its permission, or choose another camera.",
        previewLabel: "Camera preview",
        layoutTitle: "Your displays",
        layoutBody: "Your displays at their real size. Choose the mode, then how each display is split.",
        modeLabel: "Mode",
        splitLabel: "Split",
        zoneCountOne: "1 zone",
        zoneCountMany: "%@ zones",
        windowsModeNote: "Windows mode needs a precise calibration: the test will tell whether it holds.",
        pointsTitle: "Look at each point",
        pointsBody: "Points light up on each display. Turn your head naturally toward each one: there is nothing to click.",
        quickBody: "One point in the middle of each zone, to fix a slight drift without calibrating again.",
        pointsSummary: "%1$@ points · about %2$@",
        keySpace: "Space: pause",
        keyEscape: "Esc: cancel",
        keyDelete: "Delete: previous point again",
        pointsProgress: "Point %1$@ of %2$@",
        instruction: "Turn your head naturally toward each point.",
        holdEyes: "Keep your eyes on the point until it fills.",
        again: "Once more.",
        pausedHint: "Space to resume, Esc to cancel.",
        cancelTitle: "Cancel the calibration?",
        cancelMessage: "The points done so far will be lost.",
        cancelConfirm: "Cancel Calibration",
        keepGoing: "Keep Going",
        fitting: "Computing the calibration…",
        fitTooFew: "Too few points could be measured. Check the framing, then start again.",
        fitDegenerate: "The points measured do not tell your displays apart. Start again, turning your head a little more.",
        fitFailed: "The calibration failed. Start again.",
        startAgain: "Start Again",
        layoutChanged: "The display layout changed: start again.",
        cameraLost: "The camera stopped. Check it, then start again.",
        dotLabel: "Calibration point",
        validationTitle: "Test the zones",
        validationBody: "Each zone lights up twice, in random order. Look at it: the test measures whether the gaze lands right.",
        startTest: "Start the Test",
        validationProgress: "Zone %1$@ of %2$@",
        lookAtZone: "Look at this zone.",
        resultTitle: "Result",
        overall: "Overall score",
        weakCaption: "Weak points: the zones under %@.",
        redoWeak: "Redo the Weak Points",
        adviceStacked: "Switching to “%@” is fragile: lengthen the delay before switching, or place the camera between the displays.",
        adviceSplit: "The zones of “%@” blur together: try a simpler split.",
        adviceWindows: "Windows mode needs more precision: Zones mode will hold better.",
        adviceLow: "The gaze often lands off: add light on your face, keep the same distance, then calibrate again.",
        adviceExcellent: "Excellent: the gaze lands right everywhere.",
        doneTitle: "Calibration done",
        doneBody: "Look at a zone, then type: the keyboard follows you. You can calibrate again or test at any time in Settings."
    )

    static let fr = ForkGlanceCalibrationStrings(
        windowTitle: "Calibrage du regard",
        testTitle: "Tester le calibrage",
        framingTitle: "Vérifier le cadrage",
        stepCounter: "Étape %1$@ sur %2$@",
        stepWelcome: "Bienvenue",
        stepPermissions: "Autorisations",
        stepFraming: "Cadrage",
        stepLayout: "Disposition",
        stepPoints: "Calibrage",
        stepValidation: "Validation",
        stepDone: "Terminé",
        cancel: "Annuler",
        back: "Retour",
        next: "Suivant",
        start: "Commencer",
        finish: "Terminer",
        close: "Fermer",
        welcomeTitle: "Le clavier suit votre regard",
        welcomeBody: "Tournez la tête vers une partie de vos écrans\u{00A0}: la dernière fenêtre utilisée à cet endroit reçoit le clavier, avant même votre première frappe.",
        privacyNothingStored: "Aucune image n’est enregistrée\u{00A0}: chacune est analysée en mémoire, puis jetée.",
        privacyOnDevice: "Tout reste sur ce Mac\u{00A0}: rien n’est envoyé, personne n’est reconnu.",
        privacyPause: "Mettez en pause à tout moment, depuis l’île, la Command Bar ou un raccourci.",
        welcomeCost: "Coût visé\u{00A0}: environ %@ d’un cœur. La caméra s’éteint quand vous ne touchez plus à rien, et son voyant vert reste allumé tant qu’elle tourne.",
        welcomeDuration: "Environ %@, assis comme d’habitude.",
        permissionsTitle: "Deux autorisations",
        permissionsBody: "La caméra mesure l’orientation de votre tête\u{00A0}; l’Accessibilité donne le clavier à la fenêtre regardée.",
        cameraName: "Caméra",
        cameraDenied: "L’accès à la caméra est refusé\u{00A0}: autorisez-le dans Réglages Système › Confidentialité et sécurité › Caméra.",
        cameraRequired: "La caméra est nécessaire pour continuer.",
        accessibilityLater: "Sans l’Accessibilité, vous pouvez calibrer, mais le clavier ne suivra pas encore votre regard.",
        framingBody: "Asseyez-vous comme d’habitude, face à vos écrans. Le cadre suit votre visage.",
        gaugeFace: "Visage détecté",
        gaugeLight: "Lumière",
        gaugeDistance: "Distance",
        gaugeFacing: "De face",
        adviceNoFace: "Placez votre visage dans l’image.",
        adviceSeveralFaces: "Une seule personne devant la caméra, s’il vous plaît.",
        adviceMoreLight: "Un peu plus de lumière de face.",
        adviceCloser: "Approchez-vous un peu.",
        adviceFarther: "Reculez un peu.",
        adviceFaceScreens: "Tournez-vous vers vos écrans, le visage au centre de l’image.",
        adviceReady: "Parfait\u{00A0}: gardez cette position.",
        framingHold: "Suivant s’active quand les quatre jauges restent vertes une seconde.",
        cameraFailed: "La caméra ne démarre pas. Vérifiez son autorisation, ou choisissez une autre caméra.",
        previewLabel: "Aperçu de la caméra",
        layoutTitle: "Vos écrans",
        layoutBody: "Vos écrans à leur taille réelle. Choisissez le mode, puis le découpage de chaque écran.",
        modeLabel: "Mode",
        splitLabel: "Découpage",
        zoneCountOne: "1 zone",
        zoneCountMany: "%@ zones",
        windowsModeNote: "Le mode Fenêtres demande un calibrage précis\u{00A0}: le test dira s’il tient.",
        pointsTitle: "Regardez chaque point",
        pointsBody: "Des points s’allument sur chaque écran. Tournez la tête naturellement vers chacun\u{00A0}: aucun clic à faire.",
        quickBody: "Un point au centre de chaque zone, pour corriger un léger décalage sans tout recalibrer.",
        pointsSummary: "%1$@ points · environ %2$@",
        keySpace: "Espace\u{00A0}: pause",
        keyEscape: "Échap\u{00A0}: annuler",
        keyDelete: "Supprimer\u{00A0}: refaire le point précédent",
        pointsProgress: "Point %1$@ sur %2$@",
        instruction: "Tournez la tête naturellement vers chaque point.",
        holdEyes: "Gardez les yeux sur le point jusqu’à ce qu’il se remplisse.",
        again: "Encore une fois.",
        pausedHint: "Espace pour reprendre, Échap pour annuler.",
        cancelTitle: "Annuler le calibrage\u{00A0}?",
        cancelMessage: "Les points déjà faits seront perdus.",
        cancelConfirm: "Annuler le calibrage",
        keepGoing: "Continuer",
        fitting: "Calcul du calibrage…",
        fitTooFew: "Trop peu de points ont pu être mesurés. Vérifiez le cadrage, puis recommencez.",
        fitDegenerate: "Les points mesurés ne distinguent pas vos écrans. Recommencez en tournant un peu plus la tête.",
        fitFailed: "Le calibrage a échoué. Recommencez.",
        startAgain: "Recommencer",
        layoutChanged: "La disposition des écrans a changé\u{00A0}: recommencez.",
        cameraLost: "La caméra s’est arrêtée. Vérifiez-la, puis recommencez.",
        dotLabel: "Point de calibrage",
        validationTitle: "Testez les zones",
        validationBody: "Chaque zone s’allume deux fois, dans le désordre. Regardez-la\u{00A0}: le test mesure si le regard tombe juste.",
        startTest: "Lancer le test",
        validationProgress: "Zone %1$@ sur %2$@",
        lookAtZone: "Regardez cette zone.",
        resultTitle: "Résultat",
        overall: "Score global",
        weakCaption: "Points faibles\u{00A0}: les zones sous %@.",
        redoWeak: "Refaire les points faibles",
        adviceStacked: "La bascule vers «\u{00A0}%@\u{00A0}» est fragile\u{00A0}: allongez le délai avant de basculer, ou placez la caméra entre les deux écrans.",
        adviceSplit: "Les zones de «\u{00A0}%@\u{00A0}» se confondent\u{00A0}: essayez un découpage plus simple.",
        adviceWindows: "Le mode Fenêtres demande plus de précision\u{00A0}: le mode Zones sera plus fiable.",
        adviceLow: "Le regard tombe souvent à côté\u{00A0}: ajoutez de la lumière de face, gardez la même distance, puis recalibrez.",
        adviceExcellent: "Excellent\u{00A0}: le regard tombe juste partout.",
        doneTitle: "Calibrage réussi",
        doneBody: "Regardez une zone, puis tapez\u{00A0}: le clavier vous suit. Vous pouvez recalibrer ou tester à tout moment dans les réglages."
    )

    // A copy of the English until its translation (plan §19, package C1).
    static let ptBR = enUS
    // A copy of the English until its translation (plan §19, package C1).
    static let tr = enUS
    // A copy of the English until its translation (plan §19, package C1).
    static let ru = enUS
    // A copy of the English until its translation (plan §19, package C1).
    static let es = enUS
    // A copy of the English until its translation (plan §19, package C1).
    static let sk = enUS
    // A copy of the English until its translation (plan §19, package C1).
    static let de = enUS
    // A copy of the English until its translation (plan §19, package C1).
    static let it = enUS
    // A copy of the English until its translation (plan §19, package C1).
    static let ja = enUS
    // A copy of the English until its translation (plan §19, package C1).
    static let ko = enUS
    // A copy of the English until its translation (plan §19, package C1).
    static let uk = enUS
    // A copy of the English until its translation (plan §19, package C1).
    static let zhHans = enUS
    // A copy of the English until its translation (plan §19, package C1).
    static let zhTW = enUS
    // A copy of the English until its translation (plan §19, package C1).
    static let zhHK = enUS
}
