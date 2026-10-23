# Focus au regard — architecture

Feature du fork « Focus au regard » (en : *Glance Focus*) : la caméra du Mac est analysée **sur le Mac** par Apple
Vision (orientation de la tête, position du visage, pupilles), un calibrage apprend quelle zone du bureau correspond à
quelle position de tête, et le **focus clavier** passe à la dernière fenêtre utilisée de la zone regardée, avant la
première frappe. Plan : `PLAN-focus-regard.md` (hors dépôt) ; **les décisions de Martial du 23/10 priment** (D1–D12,
toutes validées) : nom « Focus au regard » / section « Regard » ; mode **Zones** par défaut ; Panneaux expérimentaux et
coupés ; couture `glance-mru` acceptée ; activité de l'île fermée pendant une pause ou un calibrage ; ⌃⌥⌘G pour la pause ;
« Continuer » pendant un appel ; halo ; pas de mascotte qui suit le regard ; une seule PR ; « Économe » sur batterie et
caméra coupée après 5 min ; apprentissage par les clics activé.

Règles du fork (`.claude/CLAUDE.md`) et de l'île (`Fork/Notch/README.md`) : elles restent la loi. La feature est
**prudente par construction** : rater une bascule coûte un clic, en faire une de trop coûte le texte de la personne.

## 1. Le flux, de la caméra au focus

```text
captureQueue (série, .userInitiated)                         fil principal
ForkGlanceCamera.frameHandler                                ForkGlanceService.received(frame)  (génération vérifiée)
  └─ ForkGlancePipeline.process                                ├─ ForkGlanceInputWatch.snapshot() → machine .inputs
       ├─ ForkGlanceVision.process → ForkGlanceObservation     ├─ ForkGlanceCalibrationModel.estimate → ForkGlanceEstimate
       ├─ ForkGlanceFeatures.sample → vecteur brut             ├─ ForkGlanceClassifier.classify → ForkGlanceGaze
       └─ ForkGlanceFilter (One Euro) → ForkGlanceSample       ├─ ForkGlanceMachine.handle(.gaze) → [ForkGlanceEffect]
              │ DispatchQueue.main.async                       └─ effets : caméra (start/stop/setRate), .focus(zone),
              ▼                                                    .showFeedback, .notice, .suggestRecalibration
                                                             .focus(zone) → ForkGlanceTargeting.target (MRU de la zone)
                                                                         → ForkGlanceFocuser.focus (WindowActivator /
                                                                           focusWithoutRaise), vérifié 150 ms plus tard
                                                                         → pointeur, panneaux, halo, « Dernières bascules »
```

- **Un seul orchestrateur** : `Service/ForkGlanceService.swift` (singleton, fil principal, `precondition`). Il publie
  l'état que **toutes** les surfaces lisent (`phase`, `status`, `zones`, `currentZone`, `candidate`, `profile`, `live`…) ;
  l'île, la page et l'assistant n'ouvrent jamais la caméra eux-mêmes.
- **Une seule décision** : `Pure/ForkGlanceMachine.swift` (struct pure, horloge injectée, patron `ForkDictationMachine`).
  Elle reçoit des événements horodatés (`.gaze`, `.inputs`, `.system`, `.settings`, `.zonesChanged`, `.focusChanged`,
  `.pause`/`.resume`, `.calibration*`, `.cameraFailure`, `.focusResult`, `.tick`) et rend des effets ; elle ne touche ni
  la caméra ni une fenêtre. La caméra tourne **exactement** dans les phases qui regardent (`ForkGlancePhase.isWatching`)
  ou pendant que l'assistant collecte des points.
- **Fils** (plan §3.2) : Vision, les features et le filtre tournent sur la `captureQueue` de la caméra
  (`alwaysDiscardsLateVideoFrames` : une image en retard est jetée) ; la session est construite, démarrée, réglée et
  arrêtée sur sa `sessionQueue` ; chaque image revient au principal marquée de la génération du pipeline, et une image
  d'une génération périmée (caméra arrêtée ou changée entre-temps) est jetée. Le calibrage et les réajustements par les
  clics tournent sur des files d'arrière-plan, le disque sur les files des stores. Pas d'acteur, pas d'async/await.
- **Une seule minuterie**, armée à `machine.nextDeadline` (fin du temps d'arrêt, de la recharge, d'une garde, d'une pause
  minutée). La pause d'inactivité sonde l'âge des entrées à 2 Hz caméra coupée (`ForkGlanceInputWatch.onNextActivity`).
- **Interrupteur** : `ForkFeature.glanceFocus.sync()` → `ForkGlance.sync()` → `ForkGlanceWindowIndex.syncTracker()`
  (couture `glance-mru`), `ForkGlanceService.sync()`, `ForkGlanceIsland.sync()`. Éteint (`tearDown`) : caméra vraiment
  arrêtée, minuterie, observateurs, moniteurs, raccourcis Carbon, halo, tentative du Focuser, enregistrement de trace en
  cours ; l'assistant ouvert se ferme comme « Annuler ». `suspend()` (Accessibilité retirée, app qui quitte) fait de même.
- **Démarrage** : `ForkBootstrap.start()` appelle `ForkGlanceIsland.start()` (crochets de l'île),
  `ForkGlanceWindowIndex.start()` (crochet `WindowUseTracker.forkDemand`) et `ForkGlance.start()`.

## 2. Fichiers

| Dossier | Fichiers | Rôle |
|---|---|---|
| `Pure/` (compilé dans les tests, Foundation + CoreGraphics) | `ForkGlanceContracts` | types partagés, **gelés** en vague 0 (signal, géométrie, calibrage, profil, phases, événements, effets, instantanés, réglages résolus) |
| | `ForkGlanceDefaults`, `ForkGlanceTuning` | clés `fork.glance.*`, valeurs par défaut, `ForkGlanceSettings.read`, paliers |
| | `ForkGlanceFeatures`, `ForkGlanceFilter` | observation → vecteur `[yaw, pitch, roll, cx, cy, s, exL, eyL, exR, eyR, open]` ; One Euro + rejet d'aberration |
| | `ForkGlanceRegression`, `ForkGlanceCalibrationModel`, `ForkGlanceLearning`, `ForkGlanceClassifier` | ridge polynomiale de degré 2 et validation croisée, σ, biais de recentrage, clics, dérive, classification avec marges |
| | `ForkGlanceZones`, `ForkGlanceProfiles`, `ForkGlanceTargeting` | zones des 3 modes, signature et correspondance des profils, zone → fenêtre (MRU), pointeur, règles des panneaux |
| | `ForkGlanceMachine`, `ForkGlanceGovernor`, `ForkGlanceTrace`, `ForkGlancePresentation` | décision, cadence et pauses automatiques, trace et rejeu, ligne d'état |
| | `ForkGlanceServiceRules`, `ForkGlanceShortcuts`, `ForkGlanceCalibrationPlan`, `ForkGlanceSettingsRules`, `ForkGlanceIslandRules` | règles pures du service (choix du profil, notices, rapport, coût), des raccourcis, de l'assistant (points, validation, jauges), de la page et de l'île |
| `Strings/` (compilé dans les tests) | `ForkGlanceStrings`, `…SettingsStrings`, `…CalibrationStrings`, `…IslandStrings` | les 15 langues, fr de référence ; ≤ 28 caractères dans l'île |
| `Engine/` (app seulement) | `ForkGlanceCamera`, `ForkGlanceCameraBusy`, `ForkGlanceVision`, `ForkGlanceDisplays`, `ForkGlanceInputWatch`, `ForkGlancePowerWatch` | capture, aperçu officiel ouvert, Vision, écrans, entrées, état du Mac |
| `Focus/` | `ForkGlanceWindowIndex`, `ForkGlanceFocuser`, `ForkGlancePanes`, `ForkGlanceHalo` | fenêtres et MRU, activation, panneaux, halo et point du regard |
| `Service/` | `ForkGlance`, `ForkGlanceService`, `ForkGlancePause`, `ForkGlanceStore`, `ForkGlanceHotKeys`, `ForkGlanceCommandBar` | point d'entrée, orchestrateur, pause sur disque, profils sur disque, raccourcis Carbon, lignes de la Command Bar |
| `Calibration/` | `…CalibrationWindow`, `…CalibrationSession`, `…CalibrationOverlay`, `…TargetDot`, `…FramingView`, `…ValidationView` | l'assistant (7 étapes, fenêtre 640×560), un panneau par écran, la cible, le cadrage, la validation |
| `Settings/` | `…SettingsView`, `…HeroCard`, `…LayoutMap`, `…CameraRow`, `…AppLists`, `…DiagnosticsView` | la page Extras › Focus au regard, la carte des écrans (réutilisée par l'île et l'assistant), le diagnostic |
| `Island/` | `ForkGlanceIsland`, `…IslandSection`, `…IslandStrip`, `…IslandTile`, `…IslandSettings` | section « Regard » (⌥⌘L), activité de l'île fermée, tuile, notices, options Contenu et carte Activité |

Tests : `Tests/Fork/ForkGlance*Tests.swift`, 19 suites `fork-glance-*` (`fork/test.sh --suite=fork-glance-machine`…).

## 3. Les briques, telles qu'elles sont codées

- **Caméra** (`Engine/ForkGlanceCamera`) : session à elle (l'aperçu officiel n'a pas de sortie d'images), le plus petit
  `activeFormat` ≥ 640×480 (sinon `.vga640x480`), pixels 420v, 2 à 15 img/s. La cadence de l'appareil est un réglage
  **partagé** : on ne la règle que si aucune autre app ne filme (`!isInUseByAnotherApplication`), on la rend dès qu'une
  autre arrive et à l'arrêt, sinon on décime en logiciel. Montée immédiate, descente après 2 s. Interruptions : nouvelle
  session après 1, 3, 10, 30 s, puis `cameraFailed`. Jamais une caméra Continuité d'elle-même, jamais
  `userPreferredCamera` modifié.
- **Aperçu officiel** (`Engine/ForkGlanceCameraBusy`) : l'aperçu de l'île ou la fenêtre miroir filment depuis la même app
  (donc invisible pour `isInUseByAnotherApplication`) ; deux sessions se battraient : pause `cameraBusy` tant que
  `CameraPreviewService` n'est pas au repos.
- **Vision** (`Engine/ForkGlanceVision`) : rectangles révision 3 (lacet, tangage, roulis continus) dans une ROI = boîte
  précédente ×1,8, image entière toutes les 2 s ou après une perte ; repères révision 3 seulement si le profil utilise
  les yeux (`inputFaceObservations`) ; qualité de capture seulement dans l'assistant ; repli sur
  `supportedRevisions.max()` affiché dans le diagnostic. Image lue `.up`, sans miroir.
- **Signal** : One Euro (`minCutoff 1,0 Hz`, `beta 0,02`, `dCutoff 1,0`), aberration > 6 σ glissants rejetée une fois ;
  clignement (ouverture < 35 % de la médiane) → `eyesUsable = false`.
- **Modèle** : ridge de degré 2 par axe, λ par validation croisée 5 plis parmi `[1e-3, 3e-3, 1e-2, 3e-2, 0,1, 0,3, 1]` ;
  « tête + yeux » choisi si les écrans sont **empilés** (recouvrement ≥ 25 % de la largeur) ou s'il gagne ≥ 10 % ; σ ≥ 2 pt ;
  recentrage borné à 15 % de la diagonale.
- **Classifieur** : entrer dans une zone demande un score ≥ `1 + s (+ anti ping-pong)`, rester ≥ `-0,6` ; un bord qui ne
  fait face à aucun autre écran ne compte pas (sinon la barre des menus et le Dock seraient inatteignables) ; `away` à plus
  de 1,5 σ de tous les écrans, sous le bas de l'écran le plus bas (le clavier) ou au-delà du lacet/tangage calibré + 15° ;
  anti ping-pong : A→B→A en moins de 1,5 s → `+0,5` pendant 30 s.
- **Machine** : temps d'arrêt tenu en continu, 2 images sans visage tolérées, recharge 400 ms, confiance < 0,5 →
  `lowConfidence`. Une garde levée **retient** le candidat (phase `blocked`) qui part dès qu'elle tombe. Un regard sur la
  zone courante ne fait jamais rien ; un focus raté rend la zone et n'est retenté qu'après que le regard l'a quittée.
  `focusChanged` (la personne a changé de fenêtre elle-même, lu par l'historique officiel ou à l'activation d'une app)
  déplace la zone courante.
- **Gardes** (`ForkGlanceGuard`) : frappe, souris, bouton ou modificateur tenu, saisie sécurisée, dictée du fork, menu /
  Mission Control / sélection de capture, île ouverte avec le clavier, fenêtre de l'app clé, app « Ne jamais quitter »,
  calibrage, recharge, confiance faible. Entrées lues par **âges** (`CGEventSource.secondsSinceLastEventType`), jamais une
  touche ; clics par un moniteur global (position et heure seulement, clics synthétiques ignorés).
- **Pauses** (`ForkGlanceGovernor.automaticPauses` + pauses explicites) : verrouillage, veille, écrans en veille, session
  en arrière-plan, inactivité, batterie (politique « Pause »), économie d'énergie, thermique ≥ `serious`, aperçu caméra,
  appel (politique « Pause »), un seul écran en mode Écrans, couvercle fermé sur la caméra intégrée. Caméra coupée.
  « Reprendre quand même » lève batterie, économie d'énergie et thermique jusqu'au prochain changement. La pause de la
  personne est sur disque (`fork.glance.pausedUntil`, heure murale) et reconvertie en `systemUptime` au lancement et au réveil.
- **Ciblage** : MRU officiel (`WindowUseTracker`, couture `glance-mru`) + cadres du window server (cache 250 ms) ; une
  fenêtre appartient à une zone si ≥ 40 % de la fenêtre ou ≥ 50 % de la zone ; « Ne jamais activer » passe à la suivante ;
  zone vide : rien. Focuser : `WindowActivator.activate` (premier plan) ou `SpaceWindowBridge.focusWithoutRaise`,
  vérifié 150 ms après, une nouvelle tentative, 3 échecs de suite → app mise de côté 5 min.
- **Pointeur** : `auto` = suivre l'écran en mode Écrans, ne pas bouger sinon ; jamais dans les 40 pt du haut d'un
  écran à encoche (l'île s'ouvrirait) ni à moins de 8 pt d'un bord (coins actifs, Dock caché) ; avec « le focus suit la souris », toujours dans la fenêtre ; ignoré par la garde souris
  pendant 300 ms.
- **Panneaux** (mode Fenêtres, expérimental, coupé) : Accessibilité d'abord (élément sous le point, demandé à l'app cible
  seule, remontée jusqu'à un `AXTextArea`/`AXScrollArea`/`AXWebArea`/`AXGroup` focalisable), puis clic de secours
  facultatif au centre du panneau, jamais sur un contrôle ni pendant la frappe, marqué pour l'apprentissage. Les apps
  Chromium/Electron (VS Code, Insiders, VSCodium, Cursor, Windsurf) ne sont **jamais** interrogées : l'Accessibilité les
  passe en mode coûteux pour toute la vie du processus (`AutoQuitService`).
- **Profils** (`ForkGlanceProfiles`, `ForkGlanceStore`) : signature = caméra + UUID des écrans triés + cadres arrondis à
  8 pt + rotation ; identique → chargé en silence ; mêmes écrans déplacés → chargé, bandeau « Les écrans ont bougé » et
  recalage rapide proposé ; inconnu → `needsCalibration(.newLayout)`, notice une fois par disposition, caméra coupée.
  12 profils au plus.
- **Apprentissage** : un clic réel avec un échantillon confiant (≥ 0,7) de ≤ 250 ms forme une paire ; 400 paires, demi-vie
  3 jours, réajustement hors principal toutes les 25 paires, refusé s'il dégrade de plus de 15 % l'erreur sur les points de
  calibrage ; dérive sur les 60 derniers clics (< 80 % d'accord, < 70 % en Fenêtres) → bandeau et notice une fois par jour.
- **Coût** (`ForkGlanceCostMeter`) : `proc_pid_rusage` du processus (v6 pour `ri_energy_nj`, v4 en repli sans énergie),
  une lecture toutes les 10 s, fenêtre de 5 min, moins le coût d'avant la caméra ; rien d'affiché avant 20 s de mesure.

## 4. Confidentialité

- Les images de la caméra sont analysées **en mémoire** sur la `captureQueue`, puis jetées. Aucune image n'est écrite,
  gardée ni envoyée ; aucune reconnaissance de personne (géométrie seulement : boîte, angles, contours des yeux, pupilles).
- Rien ne quitte le Mac. Le journal (`Logger(subsystem: "fork.glance")`) ne contient aucune donnée personnelle ; le nom
  d'une caméra (« Caméra de l'iPhone de … ») est affiché, jamais journalisé.
- Sur disque, dans `PrivateFileStore.containerURL/Glance/` (dossier 0700, fichiers 0600, écritures atomiques) :
  `profiles.json` (découpages, modèle calibré, clics appris : vecteurs et points d'écran) et `calibration-points.json`
  (les échantillons des points de calibrage, nécessaires aux réajustements). État propre à la machine, **hors sauvegarde
  des réglages**, comme `fork.glance.cameraID`, `fork.glance.pausedUntil` et `fork.glance.lastLayoutSignature`
  (`ForkGlanceDefaults.machineKeys`, jamais enregistrées).
- La **trace** n'existe que si la personne clique « Enregistrer une trace (60 s) » puis choisit où l'enregistrer : des
  nombres seulement (voir §6).
- Texte de la permission caméra : `fork/usage-descriptions.tsv` (`NSCameraUsageDescription`, base + 14 langues), appliqué
  par `fork/build-release.sh` à la place du texte officiel, qui ne parlait que de l'aperçu. `docs/PRIVACY.md` et
  `docs/PERMISSIONS.md` sont officiels : on n'y touche pas, la confidentialité de la feature vit ici et dans la page.
- Le voyant vert est allumé tant que la caméra tourne : c'est le contrôle de la personne, la feature ne cherche jamais à
  l'éviter. Il s'éteint en pause, en inactivité et quand on coupe l'interrupteur.

## 5. Réglage fin

**Paliers** (`Pure/ForkGlanceTuning.swift`, stockés en Int, index du palier par défaut en gras) :

| Palier | Clé | Valeurs | Défaut |
|---|---|---|---|
| Sensibilité `s` (σ en plus pour entrer) | `fork.glance.sensitivityStep` | 0,9 · 0,6 · 0,4 · 0,25 · 0,1 | **2** (0,4) |
| Temps d'arrêt, Zones et Fenêtres | `fork.glance.dwellStep` | 120 · 200 · 300 · 450 · 700 ms | **1** (200 ms) |
| Temps d'arrêt, Écrans | `fork.glance.dwellScreensStep` | idem | **2** (300 ms) |
| Pendant la frappe | `fork.glance.typingPauseStep` | 0,5 · 1 · 1,5 · 2,5 · 4 s | **2** (1,5 s) |
| Priorité à la souris | `fork.glance.pointerPauseStep` | 0,5 · 1 · 1,5 · 3 · 5 s | **2** (1,5 s) |
| Couper la caméra après | `fork.glance.idleOffStep` | 2 · 5 · 10 · 30 min · jamais | **1** (5 min) |

**Cadences** (`ForkGlanceGovernor.rates`, img/s) : Équilibré 12 / 6 (tête stable 2 s) / 3 (frappe) / 4 (souris) ;
Réactif 15 / 10 / 5 / 6 ; Économe 8 / 4 / 2 / 3. « En mouvement » au-delà de 20°/s. Économe forcé sur batterie avec
« Économe », en économie d'énergie et dès l'état thermique `fair`.

**Constantes clés** (à changer seulement avec une trace qui le justifie, §6) :

| Constante | Valeur | Où |
|---|---|---|
| marge pour rester, marge de base pour entrer | 0,6 σ, 1,0 σ | `ForkGlanceClassifier.stay`, `.enterBase` |
| hors écran : distance, angle | 1,5 σ, +15° | `ForkGlanceClassifier.awayMargin`, `.angleMargin` |
| anti ping-pong : fenêtre, ajout, durée | 1,5 s, +0,5 σ, 30 s | `ForkGlanceClassifier.pingPong*` |
| plusieurs visages | > 70 % de l'aire | `ForkGlanceClassifier.crowdedRatio` |
| recharge, images sans visage tolérées, confiance minimale | 400 ms, 2, 0,5 | `ForkGlanceMachine.cooldown`, `.toleratedMisses`, `.minimumConfidence` |
| One Euro | 1,0 Hz, 0,02, 1,0 | `ForkGlanceFilter.init` (défauts) |
| aberration, remise à zéro sans visage | 6 σ, 1 s | `ForkGlanceFilter.outlierSigmas`, `.gapReset` |
| clignement | 35 % de la médiane d'ouverture | `ForkGlanceFeatures.blinkRatio` |
| ROI Vision, image entière | ×1,8, toutes les 2 s | `ForkGlanceVision.regionGrowth`, `.fullImageInterval` |
| gain pour « tête + yeux », écrans empilés, biais max, σ min | 10 %, 25 %, 15 %, 2 pt | `ForkGlanceCalibrationModel.eyesGain`, `.stackedOverlap`, `.maximumBiasShare`, `.minimumSigma` |
| λ candidats, points minimum | 1e-3…1, 6 | `ForkGlanceRegression.defaultLambdas`, `.minimumPoints` |
| apprentissage : capacité, demi-vie, réajustement, confiance, âge, dégradation, fenêtre d'accord | 400, 3 j, 25, 0,7, 250 ms, 15 %, 60 | `ForkGlanceLearning.*` |
| appartenance d'une fenêtre à une zone | 40 % de la fenêtre ou 50 % de la zone | `ForkGlanceTargeting.windowShare`, `.zoneShare` |
| découpage par défaut en 2 colonnes | rapport ≥ 2,1 | `ForkGlanceZones.wideRatio` |
| mode Fenêtres « adapté » | σ ≤ 8 % de la largeur | `ForkGlanceSettingsRules.windowsSigmaShare` |
| vérification du focus, échecs avant mise de côté, durée | 150 ms, 3, 5 min | `ForkGlanceFocuser.*` |
| calibrage : trajet, stabilisation, collecte, échantillons, lacet max | 0,35 s, 0,45 s, 0,9 s, 8, 2,5° | `ForkGlanceCalibrationPlan.*` |
| validation : passages par zone, point faible | 2, < 85 % | `ForkGlanceCalibrationPlan` (validation) |
| notes de validation | Excellente ≥ 95 %, Bonne ≥ 85 %, Moyenne ≥ 70 % | `ForkGlanceGrade` |

Le **diagnostic** (page, section repliable, actif seulement ouvert, bail `ForkGlanceService.liveLease()`) montre ce qu'il
faut pour régler : aperçu caméra et repères, courbes de 10 s (lacet, tangage, yeux), point estimé et ellipse σ, cadence
réelle, ms Vision (moyenne, p95), confiance, gardes levées, phase, dernière bascule, échecs de focus par app, apps mises
de côté, accord des clics, marge anti ping-pong, révisions de Vision. « Copier le rapport » donne un texte court
(`ForkGlanceServiceRules.report`) : version, Mac, écrans, caméra (intégrée/externe/Continuité, jamais son nom), mode,
phase, calibrage (σ, score, biais), apprentissage, réglages, énergie, coût.

## 6. Traces : enregistrer, rejouer, en faire des fixtures

- **Enregistrer** : page › Diagnostic › « Enregistrer une trace (60 s) » → `ForkGlanceService.recordTrace(seconds:)`
  (60 s au plus, `ForkGlanceTrace.maxDuration`), puis un panneau d'enregistrement dans Téléchargements
  (`glance-trace-AAAA-MM-JJ-HHmmss.json`). Une trace par clic : pour une heure de travail, il en faut plusieurs.
  Couper la feature pendant l'enregistrement l'annule.
- **Contenu** (`ForkGlanceTrace`, version 1, JSON trié, dates ISO 8601) : réglages résolus, disposition (noms, cadres,
  mm des écrans), signature, `usesEyes`, zones, zone initiale ; par image : temps, échantillon filtré, regard classé (avec
  son estimation et σ), âges des entrées et drapeaux (dont « app à ne jamais quitter », sans son identifiant), gardes
  levées ; marques : clics (point, zone), changements de fenêtre par la personne, bascules (réussie ou non), zones.
  **Aucune image, aucun titre de fenêtre, aucune touche.** Les listes d'apps des réglages (identifiants de bundle) y sont.
- **Rejouer** : `ForkGlanceTrace.replay(trace, settings:)` refait passer la machine sur les images et les marques dans
  l'ordre, ses échéances tiquées comme par la minuterie, chaque focus compté réussi ; `replay(_:settings:reclassify:)`
  permet de refaire la classification (marges) à partir des estimations enregistrées. Déterministe. Résultat
  (`Metrics`) : bascules, **retours rapides** (retour vers la zone quittée en moins de 2 s, l'indicateur d'une bascule
  fausse), latence moyenne regard → bascule, part des images bloquées par une garde.
- **Fixtures** : les traces de Martial vont dans `Tests/Fork/Fixtures/Glance/*.json` (à créer avec la première), lues
  comme les fixtures de la Sauvegarde (`Data(contentsOf: URL(fileURLWithPath: "Tests/Fork/Fixtures/Glance/<nom>"))`,
  `fork/test.sh` tourne à la racine du dépôt) dans `ForkGlanceTraceTests`, avec `ForkGlanceTrace.decode`. Un test fixe
  le résultat d'aujourd'hui (bascules, retours rapides) ; un changement de constante ou de palier par défaut doit faire
  baisser les retours rapides sans faire chuter les bascules. Avant de committer une trace : vérifier qu'elle ne
  contient rien d'autre que des nombres, des identifiants d'écrans et de zones, des noms d'écrans et des identifiants de
  bundle, et garder les plus parlantes (la taille d'un fichier de 60 s n'a pas encore été mesurée).

## 7. Coutures

Toutes déclarées dans `fork/seams.txt` (bloc « Focus au regard ») ; aucune dans `Info.plist`, `Defaults.swift`,
`FeatureCatalog.swift`, `Localization.swift`, `build.sh`, `generate_sources.py`, `docs/`.

| id | Fichier | Rôle |
|---|---|---|
| `glance-mru` | `Services/Switcher/WindowUseTracker.swift` | `forkDemand` + en tête de `syncWithFeatures` : le traqueur officiel des fenêtres récentes tourne aussi pour Glance (D4) |
| `settings4` (id existant, +1 ligne) | `UI/Settings/SettingsDirectory.swift` | la ligne « Focus au regard » de la barre latérale, juste après les gestes |
| `bootstrap` (existant, 0 ligne) | `App/AppDelegate.swift` | `ForkBootstrap.start()` est du code du fork |
| `notch-glance` … `notch-glance9` | `NotchSupport`, `NotchEditorStrings`, `NotchView`, `NotchContentEditor`, `NotchSettings`, `NotchService` | section « Regard » : cas et crochets injectés, symbole `eyes`, ⌥⌘L, hauteur, ligne du Contenu, page et titre, aperçu et teinte indigo, options Contenu, carte Activité, clic sur une notice |
| `notch-glance-activity` … `-activity8` | `NotchSupport`, `NotchService`, `NotchView`, `NotchMirrorView`, `NotchTimerStrip`, `NotchCapsuleViews` | activité de l'île fermée (ordre avant Rester éveillé, ailes, capsule, miroirs, switch exhaustifs) |
| `notch-glance-tile` … `-tile5` | `NotchSupport`, `NotchControlsView`, `NotchService`, `NotchSettings` | tuile et bouton « Regard » |
| `notch-glance-event` … `-event3` | `NotchSupport` | `NotchEvent.glance` : clé, priorité 1, 4 s, routage |
| `command-bar-glance` | `Services/CommandBar/CommandBarCatalog.swift` | les lignes de la Command Bar |

Les coutures de `TEST_SOURCES` (`NotchSupport`, `NotchEditorStrings`) ne nomment aucun type du fork : elles déclarent des
crochets que `ForkGlanceIsland.start()` remplit. Lignes exactes : `grep -rn "FORK(notch-glance\|FORK(glance-mru\|FORK(command-bar-glance" Sources`.
Après un conflit avec l'officiel : ré-appliquer à l'endroit équivalent, `fork/check-seams.sh --fetch`.

## 8. Ce qui reste à mesurer

Rien de ce qui touche le matériel n'a tourné pendant le développement : aucun agent n'a allumé la caméra, lancé l'app
installée ni piloté l'interface. La recette se fait après la mise à jour en ligne (`RECETTE-focus-regard.md`, hors dépôt).
À mesurer en vrai, puis à régler par les traces :

- précision réelle (validation de l'assistant) : moitié gauche ↔ droite du LG (visé ≥ 95 %), LG ↔ MacBook (≥ 85 %) ;
- latence regard → focus (visé ≤ temps d'arrêt + 120 ms), bascules non voulues (≤ 1 par heure), retours rapides des traces ;
- coût : CPU du processus en Équilibré tête stable (≤ 3 % d'un cœur), mémoire (≤ 40 Mo), caméra éteinte ≤ 1 s après
  l'interrupteur ; `ri_energy_nj` réellement fourni par macOS 27 ;
- Vision : révisions réellement obtenues, ms par image, comportement avec lunettes, contre-jour, lumière du soir ;
- partage de la caméra pendant une visio (cadence de l'autre app intacte, décimation) ; aperçu de l'île (pause `cameraBusy`) ;
- activation des fenêtres par `WindowActivator` depuis l'arrière-plan sur macOS 27, `focusWithoutRaise` ;
- garde `menuOrOverview` (menus des autres apps au niveau 101, Mission Control, sélection de capture) ;
- panneaux par app : Terminal et Xcode probables ; iTerm2, Ghostty, JetBrains à mesurer ; kitty, WezTerm, Warp, Zed
  probablement rien (dessin GPU, un seul élément) ; VS Code, Cursor, Windsurf jamais essayés (voir §3) ;
- le point du regard sur tous les écrans (`fork.glance.gazeDot`) n'a pas d'interrupteur dans la page : seulement la clé.
