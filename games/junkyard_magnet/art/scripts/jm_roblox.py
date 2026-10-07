"""Erzeugt aus den Objektskripten den Roblox-Ersatz aus einfachen Parts (Block, Cylinder, Ball) als Luau-Datenmodul
games/junkyard_magnet/server/PropShapes.luau. So ist die Karte in Studio sofort spielbar, ohne Mesh-Upload; sobald
die FBX-Modelle hochgeladen sind, kann World.luau sie stattdessen laden.

Koordinaten: Blender (x, y, z; Z oben, Vorderseite -Y) -> Roblox (x, z, -y; Y oben, Vorderseite +Z).
Blender-Wuerfel: lokale Achsen (ex, ey, ez) -> Roblox (C ex, C ez, -C ey), Groesse (sx, sz, sy).
Blender-Zylinder (Achse lokal Z) -> Roblox Cylinder (Achse lokal X): (C ez, C ex, C ey), Groesse (Hoehe, 2r, 2r).
Ball: Roblox-Kugeln sind gleichmaessig; Durchmesser = 2 r x kleinste waagrechte Skalierung.
Material: Emission -> Neon, Chrom (metallic >= 0.8) -> Foil (glaenzend), sonst metallic >= 0.8 -> Metal, sonst
SmoothPlastic; Farbe aus der Palette (STYLE.md).
Schrottteile (5 Formen x 4 Seltenheiten) gehen zusaetzlich nach games/junkyard_magnet/shared/ItemShapes.luau
(client-sichtbar, fuer kit ItemView), um ITEM_SCALE vergroessert, damit sie aus 10 m gut erkennbar sind.
Aufruf in Blender: runpy.run_path(".../jm_roblox.py", run_name="__main__")
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from mathutils import Matrix, Vector  # noqa: E402

import item_barrel  # noqa: E402
import item_bolt  # noqa: E402
import item_gear  # noqa: E402
import item_pipe  # noqa: E402
import item_plate  # noqa: E402
import jm_common as jm  # noqa: E402
import prop_car_wreck  # noqa: E402
import prop_container  # noqa: E402
import prop_fence  # noqa: E402
import prop_ground  # noqa: E402
import prop_magnet_crane  # noqa: E402
import prop_scrap_pile  # noqa: E402
import prop_sell_station  # noqa: E402
import prop_tire_stack  # noqa: E402
import tool_magnet  # noqa: E402

OUT = jm.REPO_ROOT / "games" / "junkyard_magnet" / "server" / "PropShapes.luau"
ITEM_OUT = jm.REPO_ROOT / "games" / "junkyard_magnet" / "shared" / "ItemShapes.luau"
ITEM_SCALE = 1.4
ITEMS = {"plate": item_plate, "pipe": item_pipe, "gear": item_gear, "bolt": item_bolt, "barrel": item_barrel}
C = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0)))

PROPS = {
    "prop_ground": prop_ground.add,
    "prop_fence": prop_fence.add,
    "prop_car_wreck": prop_car_wreck.add,
    "prop_tire_stack": prop_tire_stack.add,
    "prop_magnet_crane": prop_magnet_crane.add,
    "prop_sell_station": prop_sell_station.add,
    "prop_scrap_pile": prop_scrap_pile.add,
    "prop_container": prop_container.add,
    "tool_magnet": tool_magnet.add,
    # Fass-Gruppen in verschiedenen Lackfarben (Kulisse)
    "deco_barrel_red": lambda b: item_barrel.add(b, "red"),
    "deco_barrel_blue": lambda b: item_barrel.add(b, "blue"),
    "deco_barrel_green": lambda b: item_barrel.add(b, "green"),
    "deco_barrel_yellow": lambda b: item_barrel.add(b, "yellow"),
}


def material_info(mat) -> tuple[str, str]:
    name = mat.name.removeprefix("jm_").split(".")[0]
    for rarity, (primary, accent) in jm.RARITY_MATERIALS.items():
        if name in (f"{rarity}_primary", f"{rarity}_accent"):
            color, metallic, _rough, emission = primary if name.endswith("primary") else accent
            break
    else:
        bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        color = name
        metallic = bsdf.inputs["Metallic"].default_value
        emission = bsdf.inputs["Emission Strength"].default_value
    if emission > 0:
        kind = "Neon"
    elif metallic >= 0.8:
        kind = "Foil" if color.startswith("chrome") else "Metal"
    else:
        kind = "SmoothPlastic"
    return jm.PALETTE[color], kind


def convert(shape: dict, offset: Vector, factor: float = 1.0) -> list:
    matrix = Matrix.Diagonal((factor, factor, factor, 1.0)) @ Matrix.Translation(offset) @ shape["matrix"]
    loc, rot, scale = matrix.decompose()
    r = rot.to_matrix()
    ex, ey, ez = r.col[0], r.col[1], r.col[2]
    pos = C @ loc
    kind = shape["kind"]
    if kind == "Block":
        sx, sy, sz = (shape["dims"][i] * scale[i] for i in range(3))
        axes, size = (C @ ex, C @ ez, -(C @ ey)), (sx, sz, sy)
    elif kind == "Cylinder":
        radius, depth = shape["dims"]
        diameter = 2 * radius * max(scale[0], scale[1])
        axes, size = (C @ ez, C @ ex, C @ ey), (depth * scale[2], diameter, diameter)
    else:
        diameter = 2 * shape["dims"][0] * min(scale[0], scale[1])
        axes, size = (C @ ex, C @ ez, -(C @ ey)), (diameter, diameter, diameter)
    color, material = material_info(shape["mat"])
    row = [kind, *(round(v, 3) for v in size), *(round(v, 3) for v in pos)]
    for axis_row in range(3):
        row += [round(axes[col][axis_row], 4) for col in range(3)]
    return row + [color, material]


def luau_value(value) -> str:
    return f'"{value}"' if isinstance(value, str) else repr(value)


def write_items(report: list):
    lines = [
        "--!strict",
        "-- Erzeugt von games/junkyard_magnet/art/scripts/jm_roblox.py - nicht von Hand aendern.",
        "-- Schrottteile als Bauteile fuer kit ItemView (assetStyles[asset].parts / height), Schluessel = Asset-Name",
        "-- (item_<form>_<variante>). Zeilen wie in PropShapes, relativ zum Drehpunkt Mitte unten.",
        "",
        "return {",
    ]
    for shape_name, module in ITEMS.items():
        for rarity in jm.RARITIES:
            jm.reset_scene()
            b = jm.Builder(f"item_{shape_name}_{rarity}")
            module.add(b, rarity)
            obj = b.finish()
            rows = [convert(shape, b.offset, ITEM_SCALE) for shape in b.shapes]
            d = obj.dimensions * ITEM_SCALE
            lines.append(f"\titem_{shape_name}_{rarity} = {{")
            lines.append(f"\t\tsize = {round(max(d.x, d.y), 3)},")
            lines.append(f"\t\theight = {round(d.z, 3)},")
            lines.append("\t\tparts = {")
            for row in rows:
                lines.append("\t\t\t{ " + ", ".join(luau_value(v) for v in row) + " },")
            lines.append("\t\t},")
            lines.append("\t},")
            report.append(f"item_{shape_name}_{rarity}: {len(rows)} parts")
    lines.append("}")
    ITEM_OUT.write_bytes(("\n".join(lines) + "\n").encode())


def main():
    lines = [
        "--!strict",
        "-- Erzeugt von games/junkyard_magnet/art/scripts/jm_roblox.py - nicht von Hand aendern.",
        "-- Je Objekt: size (Studs, Roblox-Achsen) und parts = { { Form, sx, sy, sz, px, py, pz, R00..R22, Farbe,",
        "-- Material } } relativ zum Drehpunkt Mitte unten; Vorderseite +Z.",
        "",
        "return {",
    ]
    report = []
    for name, add in PROPS.items():
        jm.reset_scene()
        b = jm.Builder(name)
        add(b)
        obj = b.finish()
        d = obj.dimensions
        rows = [convert(shape, b.offset) for shape in b.shapes]
        lines.append(f"\t{name} = {{")
        lines.append(f"\t\tsize = {{ {round(d.x, 3)}, {round(d.z, 3)}, {round(d.y, 3)} }},")
        lines.append("\t\tparts = {")
        for row in rows:
            lines.append("\t\t\t{ " + ", ".join(luau_value(v) for v in row) + " },")
        lines.append("\t\t},")
        lines.append("\t},")
        report.append(f"{name}: {len(rows)} parts")
    lines.append("}")
    write_items(report)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(("\n".join(lines) + "\n").encode())
    print("\n".join(report))
    print(f"-> {OUT}")


if __name__ == "__main__":
    main()
