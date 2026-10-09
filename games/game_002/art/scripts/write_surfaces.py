"""Schreibt aus games/game_002/art/assets.lock.json die Rojo-Dateien fuer den Probe-Raum:

- games/game_002/server/ModelAssets.luau: Modulname -> Asset-ID des Modells (FBX, Typ Model)
- games/game_002/surfaces/<modul>.model.json: SurfaceAppearance mit ColorMap, NormalMap, RoughnessMap und
  MetalnessMap (Bild-IDs, Typ Image). Die Karten-Eigenschaften sind fuer Skripte nicht schreibbar
  (PluginSecurity); Rojo setzt sie beim Bauen bzw. Sync, das Server-Skript klont die Vorlagen nur auf die MeshParts.

Revisionen: Neu gebackene Karten bzw. neu geformte Module tragen "_r<n>" im Dateinamen (z. B.
station_wall_panel_color_r2.png, station_console_r2.fbx; ohne Zusatz = Revision 1). Verwendet wird je Modul und
Karte die hoechste Revision; aeltere Eintraege bleiben in der Lock-Datei und bekommen den Status "Replaced".
Doku: https://create.roblox.com/docs/reference/engine/classes/SurfaceAppearance
      https://rojo.space/docs/v7/sync-details/#json-models

Aufruf: python games/game_002/art/scripts/write_surfaces.py  (bricht ab, wenn eine verwendete Datei fehlt oder
nicht "Approved" ist)
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

GAME_DIR = Path(__file__).resolve().parents[2]
LOCK_FILE = GAME_DIR / "art" / "assets.lock.json"
SURFACE_DIR = GAME_DIR / "surfaces"
ASSETS_LUAU = GAME_DIR / "server" / "ModelAssets.luau"

MAPS = (("color", "ColorMap"), ("normal", "NormalMap"), ("roughness", "RoughnessMap"), ("metalness", "MetalnessMap"))
REPLACED = "Replaced"

IMAGE_NAME = re.compile(r"^(?P<module>.+)_(?P<label>color|normal|roughness|metalness)(?:_r(?P<rev>\d+))?\.png$")
MODEL_NAME = re.compile(r"^(?P<module>.+?)(?:_r(?P<rev>\d+))?\.fbx$")


def load_lock(lock_file: Path = LOCK_FILE) -> dict[str, dict]:
    entries = json.loads(lock_file.read_text(encoding="utf-8"))["assets"]
    return {e["file"]: e for e in entries}


def latest(entries: dict[str, dict]) -> tuple[dict[str, str], dict[tuple[str, str], str], list[str]]:
    """Liefert (Modul -> FBX-Datei, (Modul, Karte) -> PNG-Datei, aeltere Dateien) jeweils zur hoechsten Revision."""
    models: dict[str, tuple[int, str]] = {}
    images: dict[tuple[str, str], tuple[int, str]] = {}
    older: list[str] = []

    def pick(table, key, rev, file):
        current = table.get(key)
        if current is None or rev > current[0]:
            if current is not None:
                older.append(current[1])
            table[key] = (rev, file)
        else:
            older.append(file)

    for file in sorted(entries):
        image = IMAGE_NAME.match(file)
        model = MODEL_NAME.match(file)
        if image:
            pick(images, (image["module"], image["label"]), int(image["rev"] or 1), file)
        elif model:
            pick(models, model["module"], int(model["rev"] or 1), file)
    return ({k: v[1] for k, v in models.items()}, {k: v[1] for k, v in images.items()}, sorted(older))


def require(entries: dict[str, dict], file: str | None, what: str) -> str:
    if file is None or file not in entries:
        sys.exit(f"{what} fehlt in {LOCK_FILE.name}")
    entry = entries[file]
    if entry["status"] != "Approved":
        sys.exit(f"{file} ist nicht freigegeben ({entry['status']})")
    return entry["assetId"]


def surface_json(entries: dict[str, dict], images: dict[tuple[str, str], str], module: str) -> dict:
    properties = {
        prop: f"rbxassetid://{require(entries, images.get((module, label)), f'{module} {label}')}"
        for label, prop in MAPS
    }
    return {"className": "SurfaceAppearance", "properties": properties}


def assets_luau(entries: dict[str, dict], models: dict[str, str]) -> str:
    lines = [
        "--!strict",
        "-- Asset-IDs der Stations-Module (Open Cloud, Typ Model), erzeugt von art/scripts/write_surfaces.py aus",
        "-- art/assets.lock.json (hoechste Revision je Modul) - nicht von Hand aendern. Nur Server; geladen per",
        "-- InsertService:LoadAsset.",
        "",
        "return {",
    ]
    for module in sorted(models):
        lines.append(f"\t{module} = {require(entries, models[module], module)},")
    lines.append("}")
    return "\n".join(lines) + "\n"


def mark_replaced(entries: dict[str, dict], older: list[str]) -> int:
    changed = 0
    for file in older:
        if entries[file]["status"] != REPLACED:
            entries[file]["status"] = REPLACED
            changed += 1
    return changed


def write_lock(entries: dict[str, dict], lock_file: Path = LOCK_FILE) -> None:
    payload = {"assets": [entries[f] for f in sorted(entries)]}
    lock_file.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8", newline="\n")


def main() -> int:
    entries = load_lock()
    models, images, older = latest(entries)
    SURFACE_DIR.mkdir(parents=True, exist_ok=True)
    for module in sorted(models):
        path = SURFACE_DIR / f"{module}.model.json"
        payload = json.dumps(surface_json(entries, images, module), indent=2) + "\n"
        path.write_text(payload, encoding="utf-8", newline="\n")
    ASSETS_LUAU.parent.mkdir(parents=True, exist_ok=True)
    ASSETS_LUAU.write_text(assets_luau(entries, models), encoding="utf-8", newline="\n")
    replaced = mark_replaced(entries, older)
    write_lock(entries)
    print(f"{len(models)} Module geschrieben, {len(older)} aeltere Eintraege ({replaced} neu als {REPLACED} markiert)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
