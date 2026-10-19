# Intégrer une feature du fork à la Dynamic Island

Ce guide dit comment une feature du fork (`Sources/Vorssaint/Fork/<Feature>/`) devient une vraie partie de la Dynamic
Island de Vorssaint : une section à elle, une activité dans l'île fermée, une tuile, un bouton autour de l'île, ses
notices, ses cartes et ses réglages dans les onglets de l'île, sans qu'un utilisateur puisse la distinguer d'une partie
officielle. Il complète les règles des coutures de `.claude/CLAUDE.md`, qui restent la loi.

Exemples complets dans le fork : **Réunions** (`Fork/Meetings/ForkMeetingIsland*.swift`, coutures `notch-meeting*`,
`notch-meeting-tile*`, `notch-meetings*`) et **Dictée** (`Fork/Dictation/History/ForkNotchDictations*.swift`, coutures
`notch-dictation*`, `notch-dictations`). Chemins relatifs à `Sources/Vorssaint/` ; numéros de ligne approximatifs (l'officiel
bouge tous les jours : cherche le symbole).

## 1. Les surfaces de l'île

| Surface | Ce que c'est | Type officiel | Modèle dans le fork |
|---|---|---|---|
| **Section** (page) | une page de l'île ouverte, une tuile de la grille Explorer, un raccourci ⌥⌘lettre, une ligne de l'onglet Contenu | `NotchModule` (`Services/Notch/NotchSupport.swift`) | Réunions : `ForkMeetingIslandSection` |
| **Onglet d'une page officielle** | un onglet de plus dans une page existante | la page elle-même (`NotchClipboardView`) | Dictées dans Presse-papiers : `forkDictationsTab` |
| **Activité compacte** | l'île fermée montre la feature autour de la caméra (ailes) ou dans la capsule | `NotchCompactActivity` (`NotchSupport.swift`) | `ForkMeetingIslandStrip` |
| **Tuile Commandes** | un bouton dans la page Commandes et dans la liste « Commandes et raccourcis » du Contenu | `NotchControlItem` (`NotchSupport.swift`) | `ForkMeetingIslandTile`, `ForkNotchDictationTile` |
| **Bouton autour de l'île** | onglet Disposition : un rond flottant à gauche, à droite ou en bas | `NotchQuickAction` (`.module`, `.control`) | gratuit dès qu'il y a une section ou une tuile |
| **Notice** | un message bref dans l'île fermée (« Réunion enregistrée ») | `NotchNotice` + `NotchService.show` | `ForkMeetingIsland.show`, `ForkDictationIsland` |
| **Carte** | l'île s'ouvre sur une carte à boutons, sans prendre le clavier | `NotchService.presentCapture` | `ForkMeetingIsland.present`, `ForkMeetingLiveCard` |
| **Réglages** | onglets **Disposition, Contenu, Activité, Comportement, Compagnon** (`UI/Settings/NotchSettings.swift`) | `NotchSettingsTab` | `ForkMeetingIslandSettings`, `ForkMeetingIslandActivityCard` |
| **Command Bar** | des lignes cherchables | `CommandBarCatalog` | `ForkMeetingCommandBar` (couture `command-bar-meeting`) |

Comment l'officiel branche ses propres sections de bout en bout (à lire avant d'en ajouter une) :

- **Presse-papiers** : `NotchModule.clipboard` (symbole, `shortcutKey` « b », `isAvailable` = `AppFeature.clipboardHistory`),
  page `NotchClipboardView` (rangée du haut via `.notchBand`, recherche cachée qui garde le focus, ⌘1…⌘9, Échap par
  `setPageLayer`), réglages dans Contenu (`moduleOptions(.clipboard)` : destination, notice, taille des cartes), notice
  `.clipboard` dans Activité, fenêtre par `arrow.up.forward.app`.
- **Calendrier** : `NotchModule.calendar` + interrupteur `notchCalendarEnabled` filtré dans `NotchSupport.modules`,
  activité compacte `.calendar`, tuile `NotchControlItem.calendar` (`setupRequirement: .page(.calendar, …)`), options dans
  Contenu (autorisation, compte à rebours).
- **Minuteur** : section, activité compacte prioritaire, tuile, bouton par défaut autour de l'île
  (`NotchQuickAccessConfiguration.initial`), notice `.timer`.
- **Agents IA** : section, activité compacte, options dans Contenu (`NotchAgentsSettingsControls`, une vue officielle à part :
  le modèle à suivre pour des options riches), état « au repos » dans Activité.

## 2. Coutures : où et comment

Rappel des règles (`.claude/CLAUDE.md`) : une couture = 1 à 3 lignes nouvelles dans un fichier officiel, chacune marquée
`// FORK(<id>)`, l'id déclaré dans `fork/seams.txt` avec le fichier, aucune logique dans la couture (elle appelle le fork),
`fork/check-seams.sh --fetch` vert. **La demande de Martial vaut accord pour les coutures d'intégration à l'île
nécessaires**, pas pour d'autres : liste-les toutes dans la PR.

### Le patron « crochet injecté » (fichiers de `TEST_SOURCES`)

`NotchSupport.swift`, `Core/NotchEditorStrings.swift`, `UI/Settings/NotchSettingsTabRow.swift` (et d'autres : la liste
`TEST_SOURCES=( … )` de `build.sh`) sont compilés par `./build.sh --test` **sans le code du fork**. Une couture là ne peut
nommer aucun type du fork. On y déclare donc un crochet que le fork remplit au lancement :

```swift
case meetings // FORK(notch-meetings)
static var meetingsHooks: (title: (AppLanguage) -> String, summary: () -> String,
                           isAvailable: (UserDefaults) -> Bool) = ({ _ in "" }, { "" }, { _ in false }) // FORK(notch-meetings)
```

et dans `Fork/Core/ForkBootstrap.start()` : `ForkMeetingIslandSection.start()` qui pose
`NotchModule.meetingsHooks = (...)`. Par défaut le crochet dit « indisponible » : dans les tests officiels la section
n'existe pas pour l'île, et leurs boucles sur `allCases` passent. Mêmes patrons : `NotchCompactActivity.meetingHooks`,
`NotchControlItem.dictationIsAvailable` / `meetingIsAvailable`.

### Pièges de `Tests/generate_sources.py`

Ce script **recopie mot pour mot** des fonctions officielles dans les tests (`./build.sh --test`). Une couture dans l'une
d'elles doit compiler sans le fork :

- `NotchView.swift` : `extension NotchModule: PanelOrderItem { func title(_:) }` → la ligne de la section passe par le
  crochet (`return Self.meetingsHooks.title(language)`), jamais par un type du fork ; aussi `pageSize`, `headerFeedback`.
- `NotchService.swift` : `compactActivities`, `compactGeometry(`, `compactActivityGeometry`, `capsuleStripSize(`
  (sa branche `.music` doit rester la première) → une activité y passe par `NotchCompactActivity.meetingHooks`.
- `NotchSettings.swift` : `destination(`, la `SettingsChoiceRow` de la taille des cartes.

Avant d'ajouter une couture dans un fichier officiel, `grep -n "<fichier>" Tests/generate_sources.py` et lis ce qui est
extrait.

### Une nouvelle **section** : toutes les lignes (exemple Réunions)

Ajouter un cas à `NotchModule` casse chaque `switch` exhaustif ; le compilateur les liste (`./build.sh --dev`). Pour
Réunions, 15 lignes :

| id | fichier | ligne |
|---|---|---|
| `notch-meetings` | `Services/Notch/NotchSupport.swift` (après la liste des cas) | `case meetings` + `static var meetingsHooks` |
| `notch-meetings2` | idem : `symbol`, `shortcutKey`, `isAvailable` | `case .meetings: return "person.2.wave.2"` / `"e"` / `Self.meetingsHooks.isAvailable(defaults)` |
| `notch-meetings3` | idem : `expandedSize(module:)` | `case .meetings: contentHeight = budget` (une liste prend la hauteur choisie) |
| `notch-meetings4` | `Core/NotchEditorStrings.swift` : `summary(_:)` | `case .meetings: return NotchModule.meetingsHooks.summary()` |
| `notch-meetings5` | `UI/Notch/NotchView.swift` : le `switch service.selected` et `title(_:)` | `case .meetings: ForkMeetingIslandSection(service:size:)` / `return Self.meetingsHooks.title(language)` |
| `notch-meetings6` | `UI/Settings/NotchContentEditor.swift` : `NotchPagePreview` et `settingsTint` | l'aperçu, la couleur |
| `notch-meetings7` | `UI/Settings/NotchSettings.swift` : `moduleOptions`, `moduleFeature`, bouton de l'en-tête | les options, `return nil` (pas d'`AppFeature`), le lien vers Extras quand la feature est coupée |
| `notch-meetings8` | idem : `activityPage` | la carte de l'onglet Activité |
| `notch-meetings9` | `Services/Notch/NotchService.swift` : `activateNotice` | un clic sur la notice ouvre la section |

Ce qui vient **sans couture** une fois le cas ajouté : la tuile de la grille Explorer (`NotchSectionsView`, titre, symbole,
`⌥⌘E`), la recherche des sections, la ligne cochable et réordonnable de l'onglet Contenu (`orderedModules` =
ordre enregistré + `allCases`), le bouton « Réunions » de l'onglet Disposition (`NotchQuickAction.optionalActions`), le choix
« Réouvrir sur » de l'onglet Comportement (`NotchSupport.modules()`), ⌃Tab entre sections, et le rafraîchissement quand la
feature change (`UserDefaults.didChangeNotification` → `schedulePreferenceSync` → `refreshModules`).

Règles de la section :

- **Place** : un nouveau cas va sur une ligne à lui, après la liste officielle → la section arrive en dernier tant que la
  personne ne la déplace pas (on ne modifie jamais la ligne `case controls, mixer, …`).
- **Raccourci** : `shortcutKey` unique (test officiel « every section has a unique direct shortcut »). Prises :
  c v m b s f i t a n r w d p g o, et e (Réunions). Libres : h j k l q u x y z — mais ⌥⌘H masque les autres apps
  (menu de l'app) : évite-la. ⌥⌘lettre ne vaut que dans l'île ouverte (`NotchService.installEventMonitors`), vérifie
  quand même qu'aucun raccourci global par défaut ne la prend (`Core/GlobalShortcut.swift`).
- **Disponibilité** : `isAvailable` = l'interrupteur de la feature du fork (comme une section officielle suit son
  `AppFeature`). Feature coupée : la section disparaît de l'île, reste grisée dans Contenu avec le texte officiel
  « Activez la fonctionnalité… » ; le bouton de l'en-tête mène à Extras (`notch-meetings7`).
- **Symbole** : celui de sa tuile Commandes s'il y en a une (comme `.mixer`, `.timer`, `.calendar`).

### Une nouvelle **activité compacte**

Le tableau complet est dans l'audit de la finition Réunions (coutures `notch-meeting` … `notch-meeting7`) :
`NotchCompactActivity` (cas + crochet), son titre et son `module` (la page qu'ouvre un survol : la section si la feature en
a une), `NotchService.compactActivities` (ordre), `compactGeometry` (ailes), `capsuleStripSize` (capsule), `NotchView`
(ailes et capsule), `NotchMirrorView` (**les copies sur les autres écrans** : sans elles, l'île est vide ailleurs),
`NotchTimerStrip` et `NotchCapsuleViews` (compagnons, switch exhaustifs). Modèle : `UI/Notch/NotchKeepAwakeStrip.swift`.

### Une nouvelle **tuile Commandes**

Patron `notch-dictation` / `notch-meeting-tile` : cas + disponibilité injectée dans `NotchControlItem`, symbole,
`setupRequirement`, `isAvailable` ; tuile et titre dans `NotchControlsView` ; action du bouton rapide dans
`NotchService` ; raison et lien quand la feature est coupée dans `NotchSettings.controlReason` /
`controlUnavailableAction`. `NotchControlItem.defaultHidden` est une constante officielle : une tuile du fork est donc
visible par défaut.

### Notices et cartes

- Notice : `NotchService.shared.show(NotchNotice(event: .capture, …))` ; elle suit l'interrupteur officiel de son
  `NotchEvent` (onglet Activité, carte « Captures » pour `.capture`) et `NotchEvent.duration` (12 s pour `.capture`).
  Garde la dernière notice montrée pour reconnaître un clic (`ForkMeetingIsland.activate`, couture `notch-meetings9`).
- Carte : `NotchService.presentCapture(id:content:actions:height:takeFocus: false, closeOnCollapse: true, …)` ; mesure sa
  hauteur à la largeur de l'île (`ForkMeetingIsland.height(of:)`), rends le clavier après un bouton qui la laisse ouverte
  (`resignPanelKey`).

### Réglages (onglets de l'île)

- **Disposition** : rien à faire (boutons automatiques). **Contenu** : la vue d'options de la section
  (`moduleOptions`), dans le `SettingsCard` que la page pose ; une vue à part, comme `NotchAgentsSettingsControls`.
- **Activité** : une `SettingsCard` de plus après les officielles (une ligne dans le `VStack` d'`activityPage`).
- **Comportement** : en général rien (la réouverture et « ouvrir l'activité » suivent la section).
- **Compagnon** : rien.
- **Un seul réglage, plusieurs endroits** : la même clé `fork.<feature>.*` lue par chaque vue (`@AppStorage`), jamais une
  copie. Chaque endroit mène aux autres : `ForkSettingsPages.open(.feature)` vers la page de la feature,
  `SettingsRouter.shared.notchModule = .x` + `request(FeatureSettingsDestination(.notch))` vers l'onglet Contenu de l'île
  sur la section.

## 3. Le design d'une page

- Fond noir de l'île, texte blanc ; surfaces `NotchControlSurface(cornerRadius: 14)` pour les lignes, `.panelCard()` (18)
  pour une carte ; espacements `NotchLayout.rowSpacing` (10) et `clipboardCardSpacing` (8) ; polices 12 (texte),
  10–11 (légendes), 13 semibold (titre de carte) ; boutons `NotchIconButton` (28 × 28), `NotchPillButton`,
  `NotchMenuButton` (jamais `Menu` : il casse le rendu).
- La rangée du haut (à côté de la caméra) se remplit avec `.notchBand(leading:trailing:)` : loupe à gauche, actions et
  fenêtre (`arrow.up.forward.app`) à droite. Échap ferme d'abord la recherche : `service.setPageLayer(.x, close:)`.
- État vide : `NotchEmptyView(symbol:message:) { NotchPillButton(…, prominent: true) }`.
- Une action qui ouvre une fenêtre ou filme : `service.perform { … }` (l'île se replie d'abord).
- Hauteur : budget compact 180 pt, spacieux 264 pt ; fais tenir l'essentiel dans le compact.
- **Settings preview** : la même vue est dessinée dans l'onglet Contenu (`NotchPagePreview`) avec
  `@Environment(\.notchSettingsPreview) == true` : n'y démarre rien (caméra, aperçu, clavier, observateurs).

## 4. Pièges

- **`TEST_SOURCES`** : aucun type du fork dans une couture d'un de ces fichiers (crochet injecté, § 2).
- **`generate_sources.py`** : les fonctions recopiées (§ 2) ; une couture dedans casse `./build.sh --test` si elle nomme le
  fork.
- **Fil principal** : aucune lecture disque dans une vue ; réutilise les modèles qui lisent ailleurs
  (`ForkMeetingLibraryModel` : scan hors fil principal, surveillance FSEvents seulement pendant que la page est là).
- **Réduire les animations** : `@Environment(\.accessibilityReduceMotion)` → `nil` à la place des animations ; le point
  rouge ne pulse plus ; les échanges en `.blurReplace` deviennent instantanés.
- **VoiceOver** : un libellé et une valeur par élément (`accessibilityLabel` / `Value` / `Hint`), une ligne lue en une
  phrase (`ForkMeetingLiveText.sentences`), les en-têtes `.isHeader`.
- **Miroirs** (`NotchMirrorView`) et **capsule** (écran sans encoche) : toute activité compacte a les deux.
- **Textes** : 15 langues, fr avec `\u{00A0}` avant « : ; ! ? » et dans « », apostrophes typographiques, ≤ 28 caractères
  pour tout ce qui tient dans l'île ; test Mirror sur la struct de textes.
- **Performances** : une vue qui suit une progression (transcription, envoi) l'observe seule, pour ne pas redessiner la
  page ; une image en direct ne vit que pendant que la page est ouverte (`ForkMeetingLivePreview`).
- **Captures d'écran** : jamais l'écran réel ; rendus hors écran des vues (`NSHostingView.cacheDisplay`), avec un faisceau
  compilé contre toutes les sources (voir les rapports des lots).

## 5. Checklist

1. Choisir les surfaces (section ? activité ? tuile ? notice ? carte ?) et lire l'officiel le plus proche.
2. Ajouter le cas ; `./build.sh --dev` liste les `switch` exhaustifs ; une couture par ligne, `// FORK(<id>)`.
3. Crochets injectés dans les fichiers de `TEST_SOURCES` ; `grep` dans `generate_sources.py`.
4. Déclarer chaque id dans `fork/seams.txt` (fichier + pourquoi).
5. Poser les crochets dans `ForkBootstrap.start()`.
6. Vues dans `Fork/<Feature>/`, textes ×15, règles pures + tests dans `Tests/Fork/` (suite dans `ForkTestsMain`, fichiers
   purs dans `FORK_SOURCES`).
7. Réglages : Contenu (options), Activité si l'île fermée la montre, liens dans les deux sens avec la page de la feature.
8. Vérifier : `fork/test.sh && fork/check-seams.sh --fetch && ./build.sh --test && ./build.sh --dev &&
   ./build/VorssaintDeveloper --selftest`, 0 warning ; rendus hors écran clair/sombre, fr/en/de.
9. Lister toutes les coutures (id, fichier, ligne) dans la PR.
