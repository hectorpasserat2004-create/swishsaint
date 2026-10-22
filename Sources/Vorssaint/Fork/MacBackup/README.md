# Sauvegarde du Mac — guide des lots

Feature du fork « Sauvegarde du Mac » (en : *Mac Backup*) : Kopia v0.23.1 vers un stockage S3 (MinIO via Tailscale, ou
n'importe quel S3), même app fermée, état en direct dans l'île, restauration depuis une fenêtre « Sauvegardes ».
Plan complet : `PLAN-sauvegarde-mac.md` (hors dépôt) ; **les décisions de Martial du 22/10 priment** :

1. tailles **réelles** partout ; disques virtuels creux (Docker, Apple Container, tout fichier ≥ 10 Go écrit à moins de
   moitié) **exclus par défaut**, jamais supprimés ni redimensionnés ;
2. l'état ne vit que **dans la section de l'île, à la demande** ; l'île fermée ne montre qu'une sauvegarde, une
   restauration ou une vérification **en cours** (`ForkMacBackupPhase.showsInClosedIsland`), jamais un retard ni un problème ;
3. **aucune alerte hors de la section** ; notifications système à « Rien » par défaut, sauf la notice de fin de sauvegarde
   dans l'île (`ForkMacBackupNotifyEvent.defaultChannel`) ; pas d'écran verrouillé, pas de point dans la barre des menus ;
4. pas de seconde copie ;
5. rythme **Automatique** par défaut, feature générique, réglages simples avec la chaîne du profil dessinée.

Règles du fork (`.claude/CLAUDE.md`) et de l'île (`Fork/Notch/README.md`) : elles restent la loi.

## 1. Architecture

```text
Swishsaint.app (interface)                         Swishsaint --fork-backup-agent (même binaire, sans interface)
├─ Island/   section, activité, tuile, notices     ├─ Agent/  planificateur, créneaux, conditions, commandes
├─ Settings/ page, assistant, profils, kit          │          écrit state.json + notify_post(<bundle>.macbackup.state)
├─ Window/   fenêtre « Sauvegardes »                └─ Engine/ (propriétaire) ── enfant : kopia server (socket unix privé)
└─ Status/ForkMacBackupStatusModel ◄── state.json ──┘                 ▲
       │  commands/<uuid>.json + notify(<bundle>.macbackup.command)    │
       └──────────── Engine/ (client) : parcourir, versions, restaurer ┘  via run/server.json
```

- **Une seule autorité sur Kopia : l'agent.** L'app n'écrit jamais de politique et ne lance jamais de snapshot : elle
  envoie un `ForkMacBackupCommand` (`ForkMacBackupStatusModel.send`). Seuls le parcours, les versions et la restauration
  passent par le client de l'app (`ForkMacBackupEngineFactory.makeClient`), qui parle au `kopia server` de l'agent.
- **L'interface ne lit qu'une chose** : `ForkMacBackupPresentation`, publiée par `ForkMacBackupStatusModel.shared`.
  Aucune vue ne lit le disque. Les mots viennent de `ForkMacBackupStrings` au moment d'afficher.
- **Réglages** : même domaine `UserDefaults`. Tout changement de `fork.macbackup.*` poste `<bundle>.macbackup.settings`
  (fait une fois pour toutes par le modèle d'état, aucune page n'a à y penser).
- **Progression en direct** : une vue qui l'affiche appelle `beginLiveViewing()` / `endLiveViewing()` ; le modèle renouvelle
  `run/viewer.lease` toutes les 5 s ; l'agent publie à 1 Hz tant que le bail a moins de 15 s, sinon toutes les 10 s.
- **Interrupteur coupé** : `ForkFeature.macBackup.sync()` → `ForkMacBackupApp.sync()` → modèle d'état arrêté (phase
  `.off`), agent désenregistré (`ForkMacBackupAgentLink.sync()`), île retirée (`ForkMacBackupIsland.sync()`). Chaque lot
  arrête vraiment ce qu'il a démarré (minuteurs, observateurs, processus).

## 2. Dossiers et propriété (aucun lot ne modifie le dossier d'un autre)

| Dossier | Propriétaire | Contenu |
|---|---|---|
| `Core/` | **fondation (gelé)** | modèles, contrats, présentation, formats, mots partagés, clés. Foundation seulement. |
| `Status/` | **fondation (gelé)** | `ForkMacBackupStatusModel` (côté app) |
| `ForkMacBackupApp.swift`, `README.md` | **fondation** | point d'entrée, ce guide |
| `Engine/` | **WP Engine** | installation et vérification de Kopia, processus et supervision du serveur, HTTP sur socket unix, connect / status / politique / snapshot / progression / vérification / maintenance / blob stats / parcours / restauration, extraction d'erreurs, Trousseau |
| `Agent/` | **WP Agent** | mode sans interface, enregistrement (`SMAppService` + repli dev), planificateur + registre des créneaux, conditions (alimentation, réseau, Tailscale, réunion, veille), assertion anti-veille, FSEvents, mesure du coût, commandes, écriture de `state.json` |
| `Island/` | **WP Island** | section ⌥⌘K, activité compacte, tuile, notices, cartes, Command Bar, réglages de l'île |
| `Settings/` | **WP Settings** | page de réglages, assistant de connexion, profils + schéma de la chaîne, feuilles d'options, import Bran, kit de récupération |
| `Window/` | **WP Window** | fenêtre « Sauvegardes » : parcourir, frise, restaurer, historique, santé, vérifications |
| `<WP>/Pure/` | le lot | ses fichiers **purs** (Foundation, testables) : compilés par `fork/test.sh` automatiquement (glob) |
| `Tests/Fork/ForkMacBackup<WP>Tests.swift` | le lot | sa suite `fork-macbackup-<wp>`, déjà inscrite dans `ForkTestsMain` |
| `Tests/Fork/Fixtures/MacBackup/` | fondation ; un lot **ajoute** ses fichiers (noms préfixés par le lot) | JSON réels de Kopia v0.23.1 (banc, chemins anonymisés) |

Fichiers partagés que les lots **ne modifient pas** : `fork/test.sh` (globs), `Tests/Fork/ForkTestsMain.swift` (suites
déjà inscrites), `Fork/Core/ForkDefaults.swift`, `ForkFeature.swift`, `ForkSettingsPages.swift`, `ForkBootstrap.swift`,
`ForkExtrasStrings.swift`. `fork/seams.txt` : chaque lot ajoute ses lignes **sous son titre** (`# macbackup · Agent`,
`# macbackup · Island`), jamais ailleurs, pour que les fusions ne se touchent pas.

Textes : les mots partagés sont dans `Core/ForkMacBackupStrings.swift` (gelé). Chaque lot met les mots de ses écrans dans
`<WP>/Pure/ForkMacBackup<WP>Strings.swift`, 15 langues, `\u{00A0}` avant « : ; ! ? » en français, ≤ 28 caractères dans
l'île, et les teste dans sa suite (modèle : `strings(_:)` de `ForkMacBackupCoreTests`).

## 3. Interfaces gelées (signatures dans les fichiers ; ne pas les changer sans la fondation)

**Modèles** (`Core/`, tous `Codable` + `Equatable`) : `ForkMacBackupRepository` (`Endpoint`, `Identity`, `Peer`,
`ServerFlavor`, `key`, `accepts(uniqueID:)`), `ForkMacBackupChainNode` (`Kind`, `Probe`), `ForkMacBackupProfile`
(`Rules`, `defaultChain(for:)`, `decode`), `ForkMacBackupPreset` (`isDefault`, `patterns`, `storageValue`/`parse`),
`ForkMacBackupICloudMode`, `ForkMacBackupSource` (`ignoreRules`), `ForkMacBackupRetention`, `ForkMacBackupPolicyRules`,
`ForkMacBackupProofLevel`, `ForkMacBackupFailureCause.classify(message:path:)`, `ForkMacBackupFailure`,
`ForkMacBackupSnapshotProof(manifest:iCloud:)`, `ForkMacBackupRunRecord`, `ForkMacBackupSlotRecord` +
`ForkMacBackupMissedReason`, `ForkMacBackupCapacitySample`, `ForkMacBackupRunFailure`, `ForkMacBackupTrigger`,
`ForkMacBackupStopReason`.

**État** : `ForkMacBackupPhase` (+ `ForkMacBackupWaitReason`, `ForkMacBackupRunResult`) et
`ForkMacBackupPresentation` (`fraction`, `tone`, `headline`, `compactValue`, `progressLine`, `rhythmLine`, `costLine`,
`preview(_:now:)` pour 10 scénarios).

**Fichiers et IPC** : `ForkMacBackupPaths(root:)` / `(container:)`, `ForkMacBackupStateFile`, `ForkMacBackupCommand` +
`ForkMacBackupCommandFile` (`maxAge` 10 min), `ForkMacBackupServerInfo` (`run/server.json`), `ForkMacBackupNotify(bundleID:)`,
`ForkMacBackupJSON` (dates en secondes, clés triées, JSONL tolérant).

**Kopia** : `ForkMacBackupKopia` (`decode` tolérant au texte avant le JSON, `date` RFC 3339 nanosecondes,
`SnapshotManifest`, `RepositoryStatus`, `SourcesResponse` / `UploadCounters`, `TaskInfo`, `DirectoryManifest`,
`SnapshotsResponse`, `JSONValue`).

**Appels entre lots** (`Core/ForkMacBackupContracts.swift`) : `ForkMacBackupEngineDriving` (connect, repositoryStatus,
applyPolicy → relecture, readPolicy, startSnapshot, progress, cancelSnapshot, setThrottle, listSnapshots, verify,
blobStats, maintenance, browse, versions, restore), `ForkMacBackupSecrets` (+ `ForkMacBackupSecretKind`,
`ForkMacBackupSecretRead`), `ForkMacBackupCredentials`, `ForkMacBackupEngineError` (`runFailure`),
`ForkMacBackupCancellable`, `ForkMacBackupRestoreRequest`/`Progress`/`Report`, `ForkMacBackupVerifyLevel`/`Report`,
`ForkMacBackupWindowTab`, `ForkMacBackupAgentRegistration`, `ForkMacBackupEngineInstallState`.

**Points d'entrée** (stubs à remplir par leur lot, signatures gelées) :

| Type | Lot | Signature |
|---|---|---|
| `ForkMacBackupEngineFactory` | Engine | `makeClient(paths:)`, `makeOwner(paths:secrets:callbackQueue:)`, `makeSecrets()` → optionnels |
| `ForkMacBackupEngineStore` | Engine | `shared`, `@Published state`, `install()`, `cancel()` |
| `ForkMacBackupAgent` | Agent | `argument`, `isRequested(_:)`, `runAndExit() -> Never` |
| `ForkMacBackupAgentLink` | Agent | `shared`, `@Published registration`, `start()`, `sync()`, `openApprovalSettings()` |
| `ForkMacBackupIsland` | Island | `start()`, `sync()` |
| `ForkMacBackupSettingsView` | Settings | `View`, sans paramètre (posée par `ForkSettingsPages`) |
| `ForkMacBackupWindow` | Window | `open(_ tab: ForkMacBackupWindowTab = .browse)` |
| `ForkMacBackupStatusModel` | fondation | `shared`, `init(preview:now:)`, `@Published presentation / agentAlive / stateWrittenAt / agentBuild`, `sync()`, `reload()`, `send(_:origin:completion:)`, `beginLiveViewing()`, `endLiveViewing()` |

Un lot qui a besoin d'un nouveau champ ou d'un nouveau cas dans `Core/` le **demande** au lieu de l'ajouter : on le pose
à l'intégration, une seule fois.

## 4. Fils d'exécution

- **App** : `ForkMacBackupStatusModel` et toutes les vues sur le fil principal ; disque lu et écrit sur la file
  utilitaire du modèle. Le client Engine de l'app rend ses résultats sur la **file principale**.
- **Agent** : une file série `fork.macbackup.agent` pour la machine et le planificateur ; le moteur propriétaire rend ses
  résultats sur cette file (`callbackQueue`). Trousseau : appels bornés, **jamais sur le fil principal**.
- **Moteur** : une seule complétion par appel, aussi après `cancel()` (`.canceled`) ; jamais d'appel sur le fil d'E/S.
- Swift 5, macOS 14+, compatible Swift 6.0.3, zéro warning, **pas d'async/await ni d'actors**, complétions seulement.

## 5. Fichiers sur le disque

`PrivateFileStore.containerURL/MacBackup/` (dossiers 0700, fichiers 0600 par `PrivateFileStore`) :
`engine/kopia-<v>/kopia`, `repo/<key>/{repository.config,cache,logs}`, `run/{agent.lock,kopia.sock,server.json,viewer.lease}`,
`commands/<uuid>.json`, `state.json`, `runs.jsonl`, `slots.jsonl`, `proofs.json`, `errors/<manifest>.json`,
`capacity.jsonl`, `pending.json`, `preview/`. Jamais `~/Library/Application Support/kopia` ni celui de Bran.

Socket : `sun_path` tient 103 octets ; si `paths.socketPathFits` est faux, le moteur prend
`ForkMacBackupPaths.shortSocket(uid:)` et écrit le vrai chemin dans `server.json`.

## 6. Réglages

Déclarés dans `Core/ForkMacBackupDefaults.swift` (extension de `ForkDefaultsKey`), fusionnés dans
`ForkDefaults.registered`, donc exportés avec les réglages : rythme (`auto` par défaut), alimentation, réseau, réunion,
débit, garder éveillé, sauvegarde anticipée, iCloud, préréglages, règles, rétention, vérifications,
`notify.<événement>` (tout à `none` sauf `complete` = `island`), seuils, île (`compact` = `running`/`never`, lecture,
chaîne, en attente, taille).

**État propre à la machine** (jamais enregistré, jamais exporté, `ForkMacBackupDefaults.machineKeys`) :
`fork.macbackup.repository`, `.sources`, `.profile`, `.adapters`, `.engineVersion`, `.kitCreatedAt`, `.kitRemindAt`,
`.branImportedAt`, `.offered`. Un lot qui a besoin d'une autre clé machine la déclare dans son propre fichier
(`extension ForkDefaultsKey`, jamais dans `registered`). Les secrets ne vont **jamais** dans les defaults (Trousseau,
service `<bundle>.macbackup`, `AfterFirstUnlockThisDeviceOnly`).

## 7. Coutures prévues (chaque lot les ajoute lui-même, sous son titre dans `fork/seams.txt`)

- **Agent** : `macbackup-agent` dans `main.swift` (hors `TEST_SOURCES`), après le bloc `--uninstall` :
  `if ForkMacBackupAgent.isRequested(CommandLine.arguments) { ForkMacBackupAgent.runAndExit() } // FORK(macbackup-agent)`.
  Le plist de l'agent est posé par `fork/build-release.sh` (fichier du fork), jamais par `build.sh`.
- **Island** : `notch-macbackups*`, `notch-macbackup*`, `notch-macbackup-tile*`, `notch-macbackup-event`,
  `command-bar-macbackup`, selon `Fork/Notch/README.md` (crochets injectés dans les fichiers de `TEST_SOURCES`).
- **Déjà posée** : `settings4` (ligne de la page dans la barre latérale).

## 8. Tests

`fork/test.sh --suite=fork-macbackup-core` (fondation) ; chaque lot a `fork-macbackup-<engine|agent|island|settings|window>`.
Les fixtures Kopia réelles sont dans `Tests/Fork/Fixtures/MacBackup/` (lues par chemin relatif à la racine du dépôt,
`fork/test.sh` s'y place). Pour un rendu : `ForkMacBackupStatusModel(preview: .running42)` ou
`ForkMacBackupPresentation.preview(_:)`, jamais de lecture disque.

Interdits sur le Mac de Martial : `--install`, enregistrer un LaunchAgent ou un `SMAppService`, toucher
`~/Library/Application Support/kopia` ou `bran`, lancer Kopia contre autre chose que le banc, la souris et le clavier.
