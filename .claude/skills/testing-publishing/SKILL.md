---
name: testing-publishing
description: Tests, Builds, Selfcheck, Staging-Publish und Diff-/Commit-Ablauf der Factory. Verwenden, wenn Luau-Tests oder Specs geschrieben, die Suite "core" erweitert, Fakes gebraucht, Builds oder Projektdateien geändert, selfcheck.py/run_tests.py/publish.py ausgeführt, ein Spieltest in Studio mit MCP vorbereitet oder ein Diff/Commit erstellt wird.
---

# Testen und Veröffentlichen

## Runner und Suiten
- Eigener Runner ohne Pakete: `core/src/testing/Runner.luau` (describe/it/expect mit toBe, toEqual).
- Spec = Funktion `(t, ctx) -> ()`; eine Datei pro Modul in `core/tests/<Modul>Spec.luau`, Eintrag in
  `core/tests/Suite.luau`. Die Suite "core" läuft als eine Luau-Execution-Task.
- Spike-Suiten `green`/`red` in `src/` beweisen Rot/Grün der Pipeline; nicht anfassen ohne Auftrag.
- Gemeinsame Test-Config: `core/tests/fixtures/SampleConfig.luau`; Testbed-Config wird in
  `core/tests/TestbedSpec.luau` validiert und simuliert.
- LocalScripts laufen in der Suite nicht; Kit-Logik daher kopflos testen (`core/tests/KitSpec.luau`).

## Fakes
- `core/src/testing/MemoryAdapter.luau`: Speicher mit `failReads(n)`, `failUpdates(n)`,
  `failUpdatesAfterWrite(n)`, `seed`, `peek`, `stats`. Nur für Tests; im Testbed-Build ausgeschlossen.
- `Scheduler.fake()` in `core/src/server/Engine/Scheduler.luau`: `advance(seconds)` statt Warten.
- Fake-Adapter für Players, Character, Remotes, World, Market, Analytics: siehe
  `core/tests/EngineAdaptersSpec.luau` und `core/tests/ServerRuntimeSpec.luau`.
- Uhr immer injizieren (`clock`), nie echte Wartezeiten in Tests.
- Echter DataStore nur in `core/tests/DataStoreIntegrationSpec.luau` (CI-Place).

## Tooling (Python, aus der Repo-Wurzel)
- `python -m unittest discover -s tools/spike -p "test_*.py"` – offline Tooling-Tests (Fake-HTTP, Fake-Uhr).
- `python tools/spike/build.py` -> `build/spike.rbxl` (default.project.json, CI-Test-Build).
- `python tools/spike/build.py --project testbed.project.json` -> `build/testbed.rbxl` (Staging, ohne Tests,
  `core/src/testing/**` per globIgnorePaths ausgeschlossen). Projektinhalte prüft `tools/spike/test_projects.py`.
- `python tools/spike/selfcheck.py`: publiziert auf den CI-Place und erzeugt drei Tasks (green, red, core);
  Erwartung green PASS, red DETECTED, core PASS. Höchstens zwei Läufe mit mindestens 70 s Abstand;
  Grenze 5 Task-Erstellungen pro Minute pro Key-Besitzer. Nur nötig bei Luau-Änderungen.
- `python tools/spike/run_tests.py --suite <green|red|core> [--version N]`: einzelne Suite.
- Hängende Task: nach Zeitlimit (180 s) + 60 s genau ein Ersatz (`[spike] task <id> hung ..., retrying once`);
  hängt auch der Ersatz -> Exit 2. Testergebnisse, Roblox-Fehler und 401/403 werden nie wiederholt.
- Belege für Berichte: `[spike] SUMMARY ...`-Zeilen, Task-IDs, Exit-Codes, `selfcheck: OK`.
- Logs unter `build/logs/` (ignoriert); `check_secrets.py` durchsucht sie mit.

## Staging-Publish
- Nur über die CI: Push auf `spike/phase-0` startet Workflow `spike` (`.github/workflows/spike.yml`):
  Format, Lint, Core boundary, Tooling tests, Build, Selfcheck, Testbed-Build + `publish.py --target staging
  --file build/testbed.rbxl`, Check secrets. Lauf mit `gh run list --branch spike/phase-0` / `gh run watch`.
- Schlägt ein Schritt fehl: nichts ändern, nicht neu starten; `gh run view --log-failed`, Vorschlag, Freigabe.
- CI-Place nie in Studio öffnen (HTTP 409 beim Upload). Production-Publish ist ein manuelles Gate.

## Spieltest in Studio (MCP)
- Nur `build/testbed.rbxl` (PlaceId 0). Der Place ist unveröffentlicht, daher bricht `ServerRuntime.start` mit
  "You must publish this place to the web to access DataStore" ab und `FactoryRemotes` fehlt.
- Im laufenden Spieltest (Server-Datamodel, `execute_luau`) die Engine mit flüchtigem Speicher starten:
  `ServerRuntime.start(Testbed.config, { storage = <Tabelle mit read/update/remove> })` – die Schnittstelle steht
  in `core/src/server/Storage/StorageAdapter.luau`. Nur im Spieltest, nie im Edit-Datamodel, nie speichern.
- Danach: `character_navigation` (Client) zu `Workspace.FactoryWorld.Zones.zone_a` bzw. `...SellPad`,
  `user_keyboard_input` E/Q, `screen_capture`, HUD-Texte per `execute_luau` (Client) aus
  `PlayerGui.FactoryHud` lesen, `get_console_output`, `start_stop_play` false.

## Diff und Commit
1. `git add -A`, dann `git status --short` prüfen (keine `.env`, keine `.claude/settings.local.json`).
2. `git diff --cached --binary --output=build/<name>.diff`; `git apply --check -R --cached build/<name>.diff`.
3. Bericht mit Anzahl Dateien und Zeilen im Diff; auf Freigabe warten.
4. Erst nach Freigabe: Nachricht als Datei (vorhandene vollständig überschreiben), `git commit -F <datei>`,
   `git log -1`, Push auf `origin spike/phase-0` ohne Force, CI abwarten und auswerten.
