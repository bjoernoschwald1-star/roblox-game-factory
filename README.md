# Roblox Game Factory – Phase 0 (Risikospike)

Zweck: nachweisen, dass die Factory automatisiert testen (Open Cloud Luau Execution im privaten Place "Factory CI")
und veröffentlichen (Place Publishing nach "Factory Staging") kann. Enthält keine Spiellogik.

Lokal ausführen (Voraussetzungen: Rokit, Python 3, `.env` mit den sechs `ROBLOX_*`-Variablen):

1. `rokit install` – installiert die gepinnten Versionen von rojo, stylua und selene
2. `stylua --check src` und `selene src` – Format- und Lint-Check
3. `python tools/spike/build.py` – baut `build/spike.rbxl`
4. `python tools/spike/selfcheck.py` – Suite „green“ muss bestehen, Suite „red“ muss als fehlgeschlagen erkannt werden
5. `python tools/spike/publish.py --target staging` – gibt die neue Versionsnummer aus
6. `python tools/spike/check_secrets.py` – Exit ≠ 0, falls ein API-Schlüssel in Repo-Dateien oder Logs auftaucht
