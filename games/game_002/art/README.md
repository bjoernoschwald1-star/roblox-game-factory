# Game #002 – Art (Forschungsstation)

## Was im Repo liegt und was nicht

Im Repo liegen nur die Quellen und die Ergebnisse, die das Spiel braucht:

- `scripts/` – Blender-Skripte, aus denen alle Modelle und Texturen entstehen
- `assets.lock.json` – Asset-IDs der hochgeladenen Modelle und Bilder (Feld `status`: `Approved` oder `Replaced`)
- `../surfaces/*.model.json` – SurfaceAppearance-Vorlagen mit den Bild-IDs (von `scripts/write_surfaces.py` erzeugt)
- `../server/ModelAssets.luau` – Modell-IDs je Modul (ebenfalls von `write_surfaces.py` erzeugt)

Bewusst **nicht** versioniert (siehe `.gitignore`) sind die erzeugten Binärdateien:

- `textures/` – PBR-Karten als PNG, 1024x1024, je Modul `color`, `normal` (OpenGL), `roughness`, `metalness`
- `export/` – Modelle als FBX

Das Spiel lädt Modelle und Texturen zur Laufzeit über die Asset-IDs (InsertService:LoadAsset und die
SurfaceAppearance-Vorlagen). Die PNG- und FBX-Dateien werden nur zum Hochladen gebraucht.

## Herkunft

- `scripts/station_modules.py` baut die Module der Station (Wandvarianten, Boden, Decke, Tür, Konsole, Rollwagen,
  Kiste, Drohne, Artefakt, Kabelbündel, Lüftungsgitter, Warnschild, Pfütze), backt die vier Karten und exportiert
  die FBX. Gemeinsame Teile (Formen, prozedurale Materialien, Backen, Export) stehen in `scripts/station_common.py`.
- Neu gebackene Karten oder neu geformte Module tragen eine Revision im Dateinamen (`_r2`); `write_surfaces.py`
  nimmt je Modul und Karte die höchste Revision und markiert ältere Einträge als `Replaced`.
- `scripts/konzept/` erzeugt die Konzeptbilder (`build/art/konzept-002/`, ebenfalls nicht versioniert).

## Neu erzeugen

1. Blender (getestet mit 5.2) mit dem MCP-Addon oder der Python-Konsole öffnen und ausführen:
   `runpy.run_path("<repo>/games/game_002/art/scripts/station_modules.py", run_name="__main__")`
   Das baut alle Module der aktuellen Revision; ein einzelnes Modul mit
   `build_one("station_console", revision="_r2")`. Dauer etwa 45 s je Modul (Cycles, CPU).
2. Hochladen (nur wenn sich Karten oder Formen geändert haben), höchstens 13 Dateien je Aufruf:
   `python tools/assets/upload_models.py --lock games/game_002/art/assets.lock.json --description "Game 002 research station probe" <dateien>`
3. `python games/game_002/art/scripts/write_surfaces.py` schreibt Vorlagen und `ModelAssets.luau` neu.

## Reproduzierbarkeit

- Die Module verwenden keinen Python-Zufall; Formen, UV-Projektion und prozedurale Muster sind deterministisch.
- Das Backen nutzt einen festen Cycles-Seed (`scene.cycles.seed = 0`, kein animierter Seed).
- Die Konzeptbilder sind fest geseedet (`konzept_common.reset(seed=...)`, `random.Random(n)`).
- Gleiche Skripte und gleiche Blender-Version ergeben dieselben Formen und UVs. Die Karten sind sichtbar gleich,
  aber nicht zwingend bytegleich: Rundung in Cycles kann sich je nach CPU und Blender-Version unterscheiden.
  Deshalb sind die Asset-IDs in `assets.lock.json` die verbindliche Quelle, nicht die lokalen Dateien.
