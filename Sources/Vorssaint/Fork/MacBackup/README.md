# Sauvegarde du Mac — architecture

Feature du fork « Sauvegarde du Mac » (en : *Mac Backup*) : Kopia v0.23.1 vers un stockage S3 (MinIO via Tailscale, ou
n'importe quel S3), même app fermée, état en direct dans l'île, restauration depuis la fenêtre « Sauvegardes ».
Plan : `PLAN-sauvegarde-mac.md` (hors dépôt) ; **les décisions de Martial du 22/10 priment** :

1. tailles **réelles** partout (`totalFileAllocatedSize`) ; disques virtuels creux (≥ 10 Go écrits à moins de moitié)
   **exclus par défaut**, jamais supprimés ni redimensionnés ;
2. l'état ne vit que **dans la section de l'île, à la demande** ; l'île fermée ne montre qu'une sauvegarde, une
   restauration ou une vérification **en cours** (`ForkMacBackupPhase.showsInClosedIsland`) ;
3. **aucune alerte hors de la section** ; notifications à « Rien » par défaut, sauf la notice de fin dans l'île ;
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
| `priority` | runner | normale pour « Sauvegarder maintenant », `fork.macbackup.priority` pour le planificateur, appliquée au serveur vivant |
| `serverProcessID` | runner | coût réel (CPU, lectures) ; à défaut `run/server.json` |
| `liveProgress(of:)` | runner | octets **vraiment** envoyés (le « Uploaded Bytes » de la tâche ; celui de l'API de contrôle reste 0) |
| `conclude(…)` | runner | fin d'un run lue dans le manifeste, échecs complets → `errors/<manifest>.json` |
| `failures(of:taskID:)` | runner | listes d'échecs manquantes après un arrêt |
| `maintenanceInfo` | runner | les maintenances de Kopia notées dans `runs.jsonl` |
| `versions(of:in:owner:)` | fenêtre | versions d'un fichier d'**un** Mac et d'**un** compte (le protocole gelé : ce Mac) |
| `shutdown` | runner | arrêt du serveur avant de rendre le verrou ; un moteur relâché arrête aussi son enfant |

Avant chaque run (6 h de cache), le runner pré-scanne la source avec `ForkMacBackupContentScan.scan` (le **seul**
parcours de la feature, aussi celui de l'« Aperçu » des Réglages) et `ForkMacBackupIgnoreMatcher` (la **seule** lecture des
règles Kopia, aussi celle de « Ce fichier est-il sauvegardé ? ») : images creuses et fichiers iCloud absents du Mac
deviennent des règles du run (`ForkMacBackupRunRules`), et la taille réelle va dans la preuve (`realBytes`, `diskBytes`).
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
| `repo/<key>/{repository.config,cache,logs,connected}` | moteur | moteur | Kopia, cache propre à chaque dépôt |
| `engine/kopia-<v>/kopia` | `ForkMacBackupEngineStore` | moteur | binaire épinglé, signé Kopia LLC |

Jamais `~/Library/Application Support/kopia` ni celui de Bran. Secrets : Trousseau (`<bundle>.macbackup`,
`AfterFirstUnlockThisDeviceOnly`), passés à Kopia par l'environnement, jamais dans les defaults ni la ligne de commande.

## 4. Réglages (`Core/ForkMacBackupDefaults.swift`)

Réglages de la personne (Bool/Int/String, exportés) : rythme, alimentation, réseau, réunion, débit, garder éveillé,
sauvegarde anticipée, iCloud, préréglages, règles, rétention, vérifications, notifications, île, et pour l'agent
`fork.macbackup.priority` et `fork.macbackup.timeout.{watchdogMinutes,repositorySeconds,probeSeconds}`.
État de la machine (jamais enregistré ni exporté, `machineKeys`) : dépôt, sources, profil, adaptateurs, version du
moteur, dates et empreinte du kit, profils connus, import Bran, offres faites.

## 5. Interrupteur

`ForkFeature.macBackup.sync()` → `ForkMacBackupApp.sync()` : modèle d'état (phase `.off`, observateurs coupés, bail
rendu), `ForkMacBackupAgentLink` (agent désenregistré, runner de l'app arrêté : serveur Kopia, minuteurs, FSEvents,
assertion), île (section, activité, cartes), téléchargement du moteur annulé ; la fenêtre se ferme sur `.off`. L'agent
lit le changement et sort (code 0). Rallumé : enregistrement, puis l'agent ou le runner de l'app repart.

## 6. Tests et banc

`fork/test.sh --suite=fork-macbackup-<core|engine|agent|island|settings|window>` : fichiers `Core/` et `*/Pure/`, avec
les JSON réels de Kopia de `Tests/Fork/Fixtures/MacBackup/`. Rendus : `ForkMacBackupStatusModel(preview:)` et
`ForkMacBackupWindowController.demoModel` (Developer seulement), jamais de faux moteur ailleurs.
Banc de bout en bout (hors dépôt) : MinIO local, le vrai runner, le vrai moteur, le client de la fenêtre.

Interdits sur le Mac de Martial : `--install`, enregistrer un LaunchAgent ou un `SMAppService`, toucher
`~/Library/Application Support/kopia` ou `bran`, lancer Kopia contre autre chose que le banc.
