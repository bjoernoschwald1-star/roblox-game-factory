# Roblox Game Factory – Arbeitsanweisung für Claude Code

## Projektziel
Die Factory baut Roblox-Games KI-gestützt aus einer theme-losen, getesteten Engine plus Game-Config.
Phase 0 richtet die Fabrik ein: Core Engine, Kit, Testbed, CI (Luau-Tests im privaten CI-Place) und Staging-Publish.
Danach folgen Game #001 und #002; erst das Bridge Gate entscheidet, ob es weitergeht.

Aufträge kommen als Dateien in `build/` (ignoriert, nie committen). Den Auftrag Satz für Satz als Checkliste
abarbeiten; Stopp-Regeln und Ausschlüsse des Auftrags gehen allem anderen vor.

## Architektur und Sichtbarkeit
- Monorepo: `core/` (Engine), `kit/` (theme-lose Client-Darstellung), `games/<id>/` (Config, Texte, Welt).
- `core/src` → `ServerScriptService.FactoryCore` (nur Server; Client sieht es nie).
- `core/client` → `ReplicatedStorage.FactoryClient`, `kit/src` → `ReplicatedStorage.FactoryKit`.
  Beide dürfen nie `core/src` requiren; das Kit darf `core/client` nutzen.
- Games liefern nur Daten und dünne Startskripte: `shared/Config` (Config, assetStyles, uiTokens),
  `server/World` + `Main.server`, `client/Main.client`. Spielentscheidungen fallen nur im Core.
- `src/` ist der Risikospike (Suiten green/red), `core/tests` die Suite "core".
- Projekte: `default.project.json` = CI-Test-Build (Tests, kein Game-Skript) → `build/spike.rbxl`;
  `testbed.project.json` = spielbares Testbed ohne Tests → `build/testbed.rbxl` (Staging).
- Details: Skills `architecture-datastore` und `factory-standards`.

## Code-Konventionen (Luau)
- Jede Datei beginnt mit `--!strict`; Kopfkommentar erklärt Zweck, Grenzen und offene Punkte.
- Spieler-Kontext ist immer `{ userId }` (`core/src/shared/PlayerContext.luau`), nie das Player-Objekt.
- Fachliche Fehler als `(ok, err)` bzw. Ergebnis-Tabelle mit Codes in GROSSBUCHSTABEN; `assert` nur bei
  Programmierfehlern (falsche Konstruktor-Optionen, Aufruf in falscher Reihenfolge).
- Fehlendes Profilfeld wird angelegt; ein vorhandener, beschädigter Wert ergibt `CORRUPT_VALUE` ohne Änderung.
- Fremde Callbacks (Hooks, Sinks, injizierte Dienste) laufen in `pcall`; Fehler ändern das Ergebnis nicht still.
- Warnungen über `core/src/shared/Log.luau` gedrosselt (`warnThrottled(key, message)`), kein nacktes `warn` im Takt.
- IDs (Items, Zonen, Upgrades, Rollen, Gründe) entsprechen `^[a-z][a-z0-9_]*$`; Remote-Namen `^[a-z][a-zA-Z0-9]*$`.
- Abhängigkeiten werden injiziert (Uhr, Speicher, RNG, Roblox-Dienste); Module rufen Engine-Dienste nur in
  `core/src/server/Engine/*Adapter` bzw. `ServerRuntime` auf.
- Keine Theme-Begriffe und keine Asset-IDs in `core/` und `kit/`; keine Unions/PartOperations (Publish-Weg).
- Formatierung: stylua (Tabs, 120 Spalten, Doppelte Anführungszeichen), Lint: selene (std roblox).
- Kommentare auf Deutsch ohne Umlaute im Luau-Code (bestehender Stil), sparsam und begründend.

## Sicherheitsgrundsätze
- Server ist autoritativ. Der Client sendet nur Absichten (`core/client/Intents.luau`): collect(), sell(),
  buyUpgrade(dimension), unlockZone(zoneId) – nie Werte, Preise oder Positionen.
- Jede Client-Anfrage läuft ausschließlich über `RemoteGateway` (Schema, Argumentanzahl, Rate Limit pro Spieler
  und Remote); abgelehnte Anfragen werden gezählt, nie beantwortet.
- Position kommt vom Server (`services.getPosition`), nie aus Remote-Argumenten.
- Rewards nur im Kauf-Handler (`Monetization.processReceipt`), idempotent über die gespeicherte PurchaseId;
  "PurchaseGranted" erst nach erfolgreichem Speichern, sonst Rückbau und "NotProcessedYet".
- Game Passes wirken nur als Modifier-Quelle, nie auf gespeicherte Werte.
- Schnappschuss an den Client (`StateSync`) enthält nur den eigenen Zustand: keine anderen Spieler, Preise,
  Produkt-/Pass-IDs, PurchaseIds oder Funnel-Daten.
- Details und Prüfliste: Skill `security-monetization`.

## Test- und Prüfablauf
Vor jedem Bericht über eine Code-Änderung, aus der Repo-Wurzel:
1. `python -m unittest discover -s tools/spike -p "test_*.py"` – Tooling-Tests, alle bestanden.
2. `stylua --check src core kit games` und `selene src core kit games` – ohne Fehler.
3. `python tools/core_boundary.py` – 0 Funde (core/src, core/client, kit/src).
4. `python tools/spike/build.py` und `python tools/spike/build.py --project testbed.project.json` – beide Builds.
5. `python tools/spike/selfcheck.py` – green PASS, red DETECTED, core PASS (Testzahl im Auftrag).
   Nur bei Luau-Änderungen; höchstens zwei Läufe mit mindestens 70 s Abstand; Luau Execution höchstens
   5 Task-Erstellungen pro Minute.
6. `python tools/spike/check_secrets.py` – 0 Funde.
Neue Pfade bekommen Tests in der Suite "core" (Spec in `core/tests/`, Eintrag in `core/tests/Suite.luau`).
Details: Skill `testing-publishing`.

## Git und Freigaben
- Kein Commit und kein Push ohne Björns ausdrückliche Freigabe für genau diesen Stand.
- Diff nach `git add -A` immer per `git diff --cached --binary --output=build/<name>.diff`;
  danach `git apply --check -R --cached build/<name>.diff` und prüfen, dass `.env` und
  `.claude/settings.local.json` nicht vorkommen.
- Commit-Nachricht unter PowerShell als Datei schreiben und `git commit -F <datei>` nutzen.
- Kein Force-Push, kein Rebase, kein Merge, keine Pull Request ohne Auftrag.
- `.env` nie lesen oder ausgeben; keine Schlüssel, Universe- oder Place-IDs in Repo-Dateien oder Berichten.
- CI-Place nie in Studio öffnen (Upload sonst HTTP 409). Bei 401/403 von Roblox: stoppen und melden.
- Workflow `spike` nur auslösen, wenn der Auftrag es verlangt (Push auf `spike/phase-0` löst ihn aus).

Manuelle Gates (immer Björn, nie selbst entscheiden oder ausführen):
- Production-Publish
- Preise und Produkte (Developer Products, Game Passes)
- Secrets und API-Schlüssel
- Migrationen von Live-DataStores
- Jede Geldausgabe, auch Robux und bezahlter Testtraffic
- Kill- und Skalierungsentscheidungen
- Änderungen an Abbruchkriterien, Zeitlimits und Phase-3-Schwellen

## Roblox-Studio-MCP
- Nur mit der lokalen Testbed- bzw. Game-Datei arbeiten (`build/testbed.rbxl`, PlaceId 0); vor jeder Aktion mit
  `list_roblox_studios` prüfen, welcher Place verbunden ist. Nie mit dem CI-Place.
- Studio ist nicht die Quelle der Wahrheit: Alles, was bleiben soll, gehört ins Repo (Rojo). Den Place in Studio
  nicht speichern; Änderungen nur innerhalb eines Spieltests.
- Im unveröffentlichten Place scheitert `DataStoreService` ("publish this place"); für Spieltests die Engine im
  Server-Datamodel mit einem flüchtigen In-Memory-Speicher starten (siehe Skill `testing-publishing`).
- Keine Mesh-/Textur-/Material-Generierung, kein Creator-Store-Einfügen, kein `upload_image` ohne Auftrag;
  generierte Assets erst nach Björns Freigabe dauerhaft verwenden.
- QA mit Spieltest, Screenshot, Eingabe und Konsole: Agent `qa-reviewer` (`.claude/agents/qa-reviewer.md`).

## Berichte
- Keine Tabellen; Prosa oder kurze Aufzählungen, Gliederung wie im Auftrag.
- Belege statt Behauptungen: Exit-Codes, Task-IDs, `[spike] SUMMARY`-Zeilen, Lauf-IDs, Versionsnummern,
  Anzahl Dateien und Zeilen im Diff.
- Abweichungen vom Auftrag und offene Fragen ausdrücklich nennen; danach auf Freigabe warten.
