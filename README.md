# Roblox Game Factory – Phase 0

Zweck: nachweisen, dass die Factory automatisiert testen (Open Cloud Luau Execution im privaten Place "Factory CI")
und veröffentlichen (Place Publishing nach "Factory Staging") kann, und darauf die theme-lose Core Engine aufbauen.
Enthält keine Spiellogik.

## Ordnerstruktur

- `core/src/server/` – Server-Module der Core Engine (ProfileStore, PlayerSession, `Storage/` mit der
  Speicher-Schnittstelle und dem RobloxDataStoreAdapter)
- `core/src/shared/` – gemeinsame Typen und Hilfen (PlayerContext, TableCopy)
- `core/src/testing/` – Testcode: eigener Testrunner (describe/it/expect) und MemoryAdapter mit Fehlereinspeisung
- `core/tests/` – Tests der Core Engine (Suite "core")
- `src/` – Risikospike: Einstiegspunkt `Main`, Suite-Definitionen `Suites`, Specs der Suiten "green" und "red"
- `tools/spike/` – Build, Publish, Testausführung, Selfcheck, Secret-Check
- `tools/core_boundary.py` – Grenzcheck: `core/src` darf keine Theme-Begriffe und keine Asset-IDs enthalten

Zuordnung im Place (`default.project.json`): `src` → `ServerScriptService.Spike`,
`core/src` → `ServerScriptService.FactoryCore`, `core/tests` → `ServerScriptService.FactoryCoreTests`.

## Toolchain

Gepinnt in `rokit.toml`: rojo 7.6.1, stylua 2.5.2, selene 0.31.0 (neuere Versionen blockiert Windows Smart App Control).

## Lokal ausführen

Voraussetzungen: Rokit, Python 3, `.env` mit den sechs `ROBLOX_*`-Variablen.

1. `rokit install` – installiert die gepinnten Versionen von rojo, stylua und selene
2. `stylua --check src core` und `selene src core` – Format- und Lint-Check
3. `python tools/core_boundary.py` – Grenzcheck der Core Engine, Exit ≠ 0 bei Fund
4. `python tools/spike/build.py` – baut `build/spike.rbxl`
5. `python tools/spike/selfcheck.py` – Suite „green“ muss bestehen, Suite „red“ muss als fehlgeschlagen erkannt
   werden, Suite „core“ muss bestehen (drei Luau-Execution-Tasks pro Lauf; Limit 5 pro Minute)
6. `python tools/spike/publish.py --target staging` – gibt die neue Versionsnummer aus
7. `python tools/spike/check_secrets.py` – Exit ≠ 0, falls ein API-Schlüssel in Repo-Dateien oder Logs auftaucht

Der CI-Place darf beim Upload nicht in Studio geöffnet sein (sonst HTTP 409).
