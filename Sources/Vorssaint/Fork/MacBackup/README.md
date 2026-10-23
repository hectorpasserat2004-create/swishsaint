# Sauvegarde du Mac — architecture

Feature du fork « Sauvegarde du Mac » (en : *Mac Backup*) : Kopia v0.23.1 vers un stockage S3 (MinIO via Tailscale, ou
n'importe quel S3), même app fermée, état en direct dans l'île, restauration depuis la fenêtre « Sauvegardes ».
Plan : `PLAN-sauvegarde-mac.md` (hors dépôt) ; **les décisions de Martial du 22/10 priment** :

1. tailles **réelles** partout (`totalFileAllocatedSize`) ; disques virtuels creux (≥ 10 Go écrits à moins de moitié) :
   seuls ceux de Docker Desktop et d'Apple Container (recréables) sont **exclus par défaut** ; tout autre (un clone de VM,
   le disque d'un serveur) est de vraies données, **sauvegardé** sauf « Laisser de côté » sur ce fichier
   (`fork.macbackup.sparse.excluded`, `ForkMacBackupSparsePolicy`, correctif du 23/10) ; jamais supprimés ni redimensionnés ;
2. l'état ne vit que **dans la section de l'île, à la demande** ; l'île fermée ne montre qu'une sauvegarde, une
   restauration ou une vérification **en cours** (`ForkMacBackupPhase.showsInClosedIsland`) ;
3. **aucune alerte hors de la section** : seules des notices dans l'île, à la fin d'une sauvegarde (terminée, partielle, échouée)
   et d'une restauration (`fork.macbackup.notice.*`, Bool) ; aucune notification système, aucune carte qui ouvre l'île d'elle-même
   sauf « restauration terminée » (suite d'une action de la personne). Tuile : l'âge de la dernière sauvegarde au repos, le
   pourcentage en cours, accent neutre. Le choix de la première sauvegarde et l'arrêt de Bran sont dans l'assistant de connexion ;
4. pas de seconde copie ; 5. rythme **Automatique** par défaut, réglages simples, chaîne du profil dessinée.

Règles du fork (`.claude/CLAUDE.md`) et de l'île (`Fork/Notch/README.md`) : elles restent la loi.

## 1. Qui fait quoi

```text
Swishsaint.app                                     Swishsaint --fork-backup-agent (même binaire, launchd)
├─ Status/  ForkMacBackupStatusModel ◄─ state.json ─┤ Agent/ ForkMacBackupRunner : planificateur, machine,
│           (+ restauration en cours de l'app)      │        conditions, pré-scan, registres, state.json
├─ Island/  section, activité, tuile, cartes ◄──────┤   └─ Engine/ propriétaire ── enfant : kopia server
├─ Settings/ page, assistant, kit ── commands/ ─────►         (socket unix privé, run/server.json)
└─ Window/  parcourir, versions, restaurer ── Engine/ client ──► même kopia server (server.json)
```

- **Une seule autorité sur Kopia : le runner.** Il tourne dans l'agent ; tant que l'agent n'est pas autorisé
  (`ForkMacBackupAgentLink.mode == .appWhileOpen`), le même runner tourne dans l'app ouverte, et la page le dit
  (`ForkMacBackupAgentStrings.appOnly` / `needsApproval`). Un verrou (`run/agent.lock`) garantit un seul runner ;
  l'app le rend à l'agent qui démarre (`handover`), **après** avoir arrêté son `kopia server`.
- L'app n'écrit jamais de politique et ne lance jamais de snapshot : elle envoie un `ForkMacBackupCommand`
  (`ForkMacBackupStatusModel.send`). Son client Engine (`ForkMacBackupEngineFactory.makeClient`) sert au parcours,
  aux versions, aux restaurations et à la sonde de l'assistant (une config jetable, qui **crée** le dépôt sur un préfixe
  vide tant qu'aucun identifiant unique n'est verrouillé).
- **L'interface ne lit qu'une chose** : `ForkMacBackupStatusModel.presentation`. Les restaurations tournent dans l'app
  (fenêtre) : `restoreStarted / restoreProgressed / restoreEnded` posent leur progression sur l'état de l'agent (phase
  `.restoring`), et `ForkMacBackupIsland.restoreFinished(report)` montre la carte « Afficher dans le Finder / Ouvrir ».
- Un nom de source se lit partout avec `ForkMacBackupFormat.sourceName` : « Dossier personnel » pour un dossier
  personnel, jamais le nom du compte.

## 2. Moteur : `ForkMacBackupEngineDriving` + `ForkMacBackupEngineExtras`

Le protocole gelé (`Core/ForkMacBackupContracts.swift`) et ses extras (`Engine/Pure/ForkMacBackupEngineExtras.swift`,
`engine as? ForkMacBackupEngineExtras`), implémentés par `ForkMacBackupKopiaEngine` (rôles `owner` et `client`).
Une complétion par appel, sur la file de rappel (principale pour le client, celle du runner pour le propriétaire),
`.canceled` après un `cancel()`.

| Extra | Utilisé par | Pour |
|---|---|---|
| `startServer` | runner | démarrer le serveur sur la config existante, sans réseau (`repo/<key>/connected` = même dépôt) ; sinon `connect` |
| `priority` | runner | normale pour « Sauvegarder maintenant » et la première sauvegarde, `fork.macbackup.priority` pour le planificateur ; appliquée (`setpriority(PRIO_DARWIN_BG)`) au serveur vivant **et** à chaque nouveau pid ; l'agent lui-même est un processus standard (plist sans `Background` ni `LowPriorityBackgroundIO`) |
| `serverProcessID` | runner | coût réel (CPU, lectures) ; à défaut `run/server.json` |
| `liveProgress(of:)` | runner | octets **vraiment** envoyés (le « Uploaded Bytes » de la tâche ; celui de l'API de contrôle reste 0) |
| `conclude(…)` | runner | fin d'un run lue dans le manifeste, échecs complets → `errors/<manifest>.json` |
| `failures(of:taskID:)` | runner | listes d'échecs manquantes après un arrêt |
| `maintenanceInfo` | runner | les maintenances de Kopia notées dans `runs.jsonl` |
| `versions(of:in:owner:)` | fenêtre | versions d'un fichier d'**un** Mac et d'**un** compte (le protocole gelé : ce Mac) |
| `shutdown` | runner | arrêt du serveur avant de rendre le verrou ; un moteur relâché arrête aussi son enfant |

Avant chaque run, le runner pré-scanne la source avec `ForkMacBackupContentScan.scan` (le **seul**
parcours de la feature, aussi celui de l'« Aperçu » des Réglages) et `ForkMacBackupIgnoreMatcher` (la **seule** lecture des
règles Kopia, aussi celle de « Ce fichier est-il sauvegardé ? ») : images creuses et fichiers iCloud absents du Mac
deviennent des règles du run (`ForkMacBackupRunRules`), et la taille réelle va dans la preuve (`realBytes`, `diskBytes`).
Un parcours complet coûte cher (mesuré le 22/10 : 2,4 M fichiers, 2,5 à 3,5 min, 2 min de CPU) : il est gardé dans
`prescan.json` un jour (une semaine sur batterie) et rafraîchi avant chaque run par un `lstat` des seuls fichiers que
FSEvents a vus changer depuis l'événement du dernier parcours ou rafraîchissement (`Entry.eventID`,
`Tally.pathsKnownSince`, `ForkMacBackupPrescanPlan`) ; sans liste complète depuis (événements perdus, plafond), on
reparcourt. Pendant le parcours, « Préparation » dit ce qu'il fait (`ForkMacBackupPresentation.Preparation` : fichiers
examinés, dossier, durée), jusque dans l'île fermée (« 1,2 M »).
Chemins des sources : **une seule forme** (`ForkMacBackupSourcePath.normalized`, celle de Kopia, sans « / » final),
appliquée au décodage des sources, à l'import Bran, aux clés du pré-scan, aux preuves, à la capacité, aux sources de
Kopia et aux racines FSEvents ; `ForkMacBackupDefaults.migrate` réécrit au lancement une valeur d'avant (build 2331 :
« /Users/x/ » d'un import Bran faisait rater toutes les preuves au planificateur, d'où des sauvegardes en boucle).
Filet du rythme Automatique (`ForkMacBackupPlanner`) : jamais deux sauvegardes à moins d'une heure, comptée depuis la fin
du dernier run complet ou partiel de `runs.jsonl` (`lastRunEnd`), quoi que disent les preuves ; chaque run écrit son créneau.
iCloud : chaque enfant Kopia naît avec la politique `IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES` voulue
(`ForkMacBackupDatalessPolicy`) : OFF partout (un fichier absent du Mac échoue en EDEADLK, classé « iCloud seulement »),
ON pour le seul serveur du mode « Tout télécharger avant », refusé (`localSpace`) si l'espace libre ne couvre pas le
téléchargement + max(5 Go, 10 %) (`ForkMacBackupMaterializeCheck`).
Préréglages et règles : l'agent les lit dans `fork.macbackup.presets` / `.rules` (les clés des Réglages, celles de l'import
des réglages), jamais dans les copies par source de l'état de la machine (`ForkMacBackupSource.applying`).
Rétention : `ForkMacBackupRetentionReplay` (portage vérifié de Kopia), par source. Noms d'une restauration :
`ForkMacBackupRestoreNaming` (« garder les deux »).

## 3. Fichiers et IPC

`PrivateFileStore.containerURL/MacBackup/` (dossiers 0700, fichiers 0600) :

| Fichier | Écrit par | Lu par | Format |
|---|---|---|---|
| `state.json` + notify `<bundle>.macbackup.state` | runner | modèle d'état | `ForkMacBackupStateFile` |
| `commands/<uuid>.json` + notify `.command` | app (`send`) | runner | `ForkMacBackupCommandFile` (10 min) |
| notify `.settings` | modèle d'état (tout changement `fork.macbackup.*`) | runner (`reloadSettings`) | — |
| `run/viewer.lease` | modèle d'état (vue en direct) | runner : 1 Hz sinon 10 s | date du fichier |
| `run/server.json`, `run/kopia.sock` | moteur propriétaire | client, coût | `ForkMacBackupServerInfo` |
| `runs.jsonl` | runner (sauvegardes, vérifs, maintenances) **et** fenêtre (restaurations) | fenêtre, réglages | `ForkMacBackupRunRecord`, une ligne par `write` `O_APPEND` (`ForkMacBackupJSON.append`), sous `flock` de `runs.jsonl.lock`, comme la purge du runner (`rewrite`) |
| `slots.jsonl`, `capacity.jsonl` | runner | fenêtre | idem |
| `proofs.json` | runner | fenêtre | `ForkMacBackupProofStore` |
| `errors/<manifest>.json` | runner | fenêtre | `[ForkMacBackupFailure]` |
| `pending.json` | runner (FSEvents) | runner | — |
| `prescan.json` | runner (pré-scan) | runner | `ForkMacBackupPrescanCache` |
| `repo/<key>/{repository.config,cache,logs,connected}` | moteur | moteur | Kopia, cache propre à chaque dépôt |
| `engine/kopia-<v>/kopia` | `ForkMacBackupEngineStore` | moteur | binaire épinglé, signé Kopia LLC |

Jamais `~/Library/Application Support/kopia` ni celui de Bran. Secrets : Trousseau (`<bundle>.macbackup`,
`AfterFirstUnlockThisDeviceOnly`), passés à Kopia par l'environnement, jamais dans les defaults ni la ligne de commande.

## 4. Réglages (`Core/ForkMacBackupDefaults.swift`)

Réglages de la personne (Bool/Int/String, exportés) : rythme, alimentation, réseau, réunion, débit, garder éveillé,
sauvegarde anticipée, iCloud, préréglages, règles, rétention, vérifications, notifications, île, et pour l'agent
`fork.macbackup.priority` et `fork.macbackup.timeout.{watchdogMinutes,repositorySeconds,probeSeconds}`.
État de la machine (jamais enregistré ni exporté, `machineKeys`) : dépôt, sources, profil, adaptateurs, version du
moteur, dates et empreinte du kit, profils connus, import Bran, disques creux laissés de côté.

## 5. Interrupteur

`ForkFeature.macBackup.sync()` → `ForkMacBackupApp.sync()` : modèle d'état (phase `.off`, observateurs coupés, bail
rendu), `ForkMacBackupAgentLink` (agent désenregistré, runner de l'app arrêté : serveur Kopia, minuteurs, FSEvents,
assertion), île (section, activité, carte de restauration), téléchargement du moteur annulé ; la fenêtre se ferme sur `.off`. L'agent
lit le changement et sort (code 0). Rallumé : enregistrement, puis l'agent ou le runner de l'app repart.

## 6. Tests et banc

`fork/test.sh --suite=fork-macbackup-<core|engine|agent|island|settings|window>` : fichiers `Core/` et `*/Pure/`, avec
les JSON réels de Kopia de `Tests/Fork/Fixtures/MacBackup/`. Rendus : `ForkMacBackupStatusModel(preview:)` et
`ForkMacBackupWindowController.demoModel` (Developer seulement), jamais de faux moteur ailleurs.
Banc de bout en bout (hors dépôt) : MinIO local, le vrai runner, le vrai moteur, le client de la fenêtre.

Interdits sur le Mac de Martial : `--install`, enregistrer un LaunchAgent ou un `SMAppService`, toucher
`~/Library/Application Support/kopia` ou `bran`, lancer Kopia contre autre chose que le banc.
