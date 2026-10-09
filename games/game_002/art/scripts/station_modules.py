"""Module der Forschungsstation (Vorlage build/art/konzept-002/station.png) fuer den Probe-Raum von Game #002.

Je Modul: Grundformen bauen, gefast vereinen, UV, vier PBR-Karten backen (station_common.bake), FBX exportieren.
Achsen in Blender: X = Breite, Y = Tiefe (Vorderseite zeigt nach -Y), Z = Hoehe; 1 Einheit = 1 Stud.
Ursprung = Mitte der Huelle; das Server-Skript (games/game_002/server/Room.luau) liest die Groessen aus den
MeshParts, Akzent-Positionen stehen dort relativ zur Modulmitte.
Das Artefakt hat zusaetzlich einen Kristall als eigenes Mesh ohne Karten (wird im Spiel Neon).

Look-Runde 2: Boden mit Oelflecken, Konsole mit Knoepfen, Schaltern, Drehreglern und Kabeln, neue Module Pfuetze,
Lueftungsgitter, Wand mit Fenster, beschaedigte Wand, Warnschild (nur Symbol). Neu gebackene Karten bestehender
Module tragen die Revision im Dateinamen (z. B. station_wall_panel_color_r2.png, station_console_r2.fbx).

Aufruf in Blender: runpy.run_path(".../station_modules.py", run_name="__main__") baut alle Module;
build_one("<name>", revision="_r2") baut eines. Ausgabe: art/export/*.fbx, art/textures/*.png.
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import station_common as sc  # noqa: E402
from mathutils import Vector  # noqa: E402


WALL_W, WALL_D, WALL_H = 8.0, 0.8, 12.0


def _wall_frame(back=True):
    """Gemeinsamer Rahmen der Wandvarianten: Rueckplatte (optional), Pfosten, Sockel mit Warnstreifen, Kopfleiste."""
    w, d, h = WALL_W, WALL_D, WALL_H
    parts = []
    if back:
        parts.append(sc.box("back", (w, d * 0.6, h), (0, d * 0.2, h / 2), "panel", bevel=0.04))
    for x in (-w / 2 + 0.3, w / 2 - 0.3):
        parts.append(sc.box("pillar", (0.6, d, h), (x, 0, h / 2), "dark", bevel=0.08))
    for z in (0.6, h - 0.5):
        parts.append(sc.box("rail", (w - 0.6, d * 0.9, 0.5 if z > 1 else 1.2), (0, -0.02, z), "hazard" if z < 1 else
                            "dark", bevel=0.06))
    return parts


def _back_with_hole(x0, x1, z0, z1):
    """Rueckplatte aus vier Stuecken um eine Oeffnung (x0..x1, z0..z1)."""
    w, d, h = WALL_W, WALL_D, WALL_H
    y = d * 0.2
    t = d * 0.6
    return [
        sc.box("back_l", (x0 + w / 2, t, h), ((x0 - w / 2) / 2, y, h / 2), "panel", bevel=0.04),
        sc.box("back_r", (w / 2 - x1, t, h), ((x1 + w / 2) / 2, y, h / 2), "panel", bevel=0.04),
        sc.box("back_b", (x1 - x0, t, z0), ((x0 + x1) / 2, y, z0 / 2), "panel", bevel=0.04),
        sc.box("back_t", (x1 - x0, t, h - z1), ((x0 + x1) / 2, y, (z1 + h) / 2), "panel", bevel=0.04),
    ]


def _inset(parts, zc, height, w=WALL_W):
    parts.append(sc.box("inset", (w - 2.2, 0.16, height), (0, -0.12, zc), "panel", bevel=0.08))
    for sx in (-1, 1):
        for sz in (-1, 1):
            parts.append(sc.cyl("bolt", 0.1, 0.12, (sx * (w / 2 - 1.4), -0.22, zc + sz * (height / 2 - 0.25)),
                                "steel", rot=(90, 0, 0), verts=8, bevel=0))


def wall_panel():
    parts = _wall_frame()
    for zc in (3.6, 8.2):
        _inset(parts, zc, 3.8)
    # Lueftungsschlitze oben
    for i in range(6):
        parts.append(sc.box("vent", (2.2, 0.12, 0.12), (1.6, -0.1, 10.4 - i * 0.28), "dark", bevel=0.02))
    return parts


def wall_window():
    """Wandvariante mit Fenster in einen dunklen Nebenraum (Glas und Nebenraum setzt das Spiel)."""
    x0, x1, z0, z1 = -2.3, 2.3, 3.7, 6.9
    parts = _wall_frame(back=False) + _back_with_hole(x0, x1, z0, z1)
    d = WALL_D
    # schwerer Fensterrahmen mit Bolzen, nach vorn abgesetzt
    for name, size, loc in (
        ("frame_b", (x1 - x0 + 0.7, d + 0.3, 0.35), (0, -0.05, z0 - 0.17)),
        ("frame_t", (x1 - x0 + 0.7, d + 0.3, 0.35), (0, -0.05, z1 + 0.17)),
        ("frame_l", (0.35, d + 0.3, z1 - z0), (x0 - 0.17, -0.05, (z0 + z1) / 2)),
        ("frame_r", (0.35, d + 0.3, z1 - z0), (x1 + 0.17, -0.05, (z0 + z1) / 2)),
    ):
        parts.append(sc.box(name, size, loc, "dark", bevel=0.06))
    for x in (x0 - 0.17, x1 + 0.17):
        for z in (z0 + 0.4, z1 - 0.4):
            parts.append(sc.cyl("bolt", 0.09, 0.12, (x, -0.56, z), "steel", rot=(90, 0, 0), verts=8, bevel=0))
    # Fensterbank mit Rostkante
    parts.append(sc.box("sill", (x1 - x0 + 1.0, 0.7, 0.18), (0, -0.55, z0 - 0.42), "steel", bevel=0.04))
    _inset(parts, 9.5, 2.8)
    _inset(parts, 1.95, 1.4)
    return parts


def wall_damaged():
    """Wandvariante mit aufgerissener Platte: Hohlraum, offene Kabel, verbogene Abdeckung."""
    x0, x1, z0, z1 = -2.4, 1.6, 2.0, 5.6
    parts = _wall_frame(back=False) + _back_with_hole(x0, x1, z0, z1)
    # Hohlraum hinter der Oeffnung (Rueckwand, Streben)
    parts.append(sc.box("cavity", (x1 - x0 + 0.4, 0.2, z1 - z0 + 0.4), ((x0 + x1) / 2, 0.55, (z0 + z1) / 2), "dark",
                        bevel=0.03))
    for x in (x0 + 1.0, x1 - 1.2):
        parts.append(sc.box("strut", (0.25, 0.4, z1 - z0), (x, 0.35, (z0 + z1) / 2), "steel", bevel=0.03))
    # offene Kabel: aus dem Hohlraum heraus, haengen nach unten bis zum Sockel
    for i, (x, r) in enumerate(((-1.6, 0.07), (-1.1, 0.09), (-0.4, 0.06), (0.4, 0.08), (0.9, 0.05))):
        sag = 0.25 + 0.12 * i
        parts.append(sc.tube("cable", [(x, 0.4, z1 - 0.4), (x + 0.15, -0.2, z1 - 1.2), (x + 0.3, -0.5 - sag, z0 + 0.5),
                                       (x + 0.1, -0.4, 1.4)], r, "rubber", resolution=6))
    # verbogene Abdeckplatte, haengt schraeg an der Unterkante
    parts.append(sc.box("bent_plate", (x1 - x0 - 0.3, 0.12, 2.2), ((x0 + x1) / 2 - 0.2, -0.75, z0 - 0.35), "panel",
                        rot=(-38, 6, -9), bevel=0.05))
    # Ersatz-Bolzen fehlen: nur zwei uebrig, dazu obere Platte normal
    parts.append(sc.cyl("bolt", 0.1, 0.12, (x1 + 0.3, -0.22, z1 + 0.3), "steel", rot=(90, 0, 0), verts=8, bevel=0))
    parts.append(sc.cyl("bolt", 0.1, 0.12, (x0 - 0.3, -0.22, z0 - 0.3), "steel", rot=(90, 0, 0), verts=8, bevel=0))
    _inset(parts, 8.6, 3.6)
    return parts


def vent():
    """Lueftungsgitter zum Aufsetzen auf Waende: Rahmen, schraege Lamellen, dunkle Rueckseite."""
    s, d = 2.4, 0.4
    parts = [sc.box("vent_back", (s - 0.2, 0.08, s - 0.2), (0, 0.12, 0), "dark", bevel=0.02)]
    for name, size, loc in (
        ("vent_frame_t", (s, d, 0.25), (0, 0, s / 2 - 0.125)),
        ("vent_frame_b", (s, d, 0.25), (0, 0, -s / 2 + 0.125)),
        ("vent_frame_l", (0.25, d, s - 0.5), (-s / 2 + 0.125, 0, 0)),
        ("vent_frame_r", (0.25, d, s - 0.5), (s / 2 - 0.125, 0, 0)),
    ):
        parts.append(sc.box(name, size, loc, "steel", bevel=0.05))
    for i in range(7):
        z = -s / 2 + 0.45 + i * (s - 0.9) / 6
        parts.append(sc.box("louver", (s - 0.5, 0.06, 0.32), (0, -0.02, z), "dark", rot=(38, 0, 0), bevel=0.01))
    for sx in (-1, 1):
        for sz in (-1, 1):
            parts.append(sc.cyl("bolt", 0.07, 0.08, (sx * (s / 2 - 0.13), -0.22, sz * (s / 2 - 0.13)), "steel",
                                rot=(90, 0, 0), verts=8, bevel=0))
    return parts


def warning_sign():
    """Warnschild ohne Text: Dreieck mit schwarzem Rand und Blitz-Symbol auf einer Montageplatte."""
    def triangle(size, z0=0.0):
        r = size / math.sqrt(3)
        return [(r * math.cos(math.radians(a)), z0 + r * math.sin(math.radians(a))) for a in (90, 210, 330)]

    parts = [sc.box("mount", (1.9, 0.08, 1.7), (0, 0.06, -0.05), "steel", bevel=0.03)]
    parts.append(sc.prism("border", triangle(2.3), 0.08, -0.06, "ink", bevel=0.02))
    parts.append(sc.prism("field", triangle(1.9, -0.03), 0.04, -0.09, "sign", bevel=0.01))
    bolt = [(0.12, 0.42), (-0.2, -0.02), (0.0, -0.02), (-0.14, -0.42), (0.22, 0.06), (0.02, 0.06)]
    parts.append(sc.prism("symbol", [(x, z - 0.1) for x, z in bolt], 0.04, -0.12, "ink", bevel=0.005))
    for x in (-0.75, 0.75):
        parts.append(sc.cyl("bolt", 0.06, 0.06, (x, -0.01, -0.7), "steel", rot=(90, 0, 0), verts=8, bevel=0))
    return parts


def puddle():
    """Abdeckblech auf dem Gitterboden mit glaenzender Oelpfuetze (flach)."""
    parts = [sc.box("cover", (4.2, 3.4, 0.12), (0, 0, 0.06), "floor_steel", bevel=0.03)]
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(sc.cyl("bolt", 0.09, 0.05, (sx * 1.9, sy * 1.5, 0.13), "steel", verts=8, bevel=0))

    def blob(cx, cy, radius, seed):
        pts = []
        for i in range(28):
            a = 2 * math.pi * i / 28
            k = 1 + 0.22 * math.sin(3 * a + seed) + 0.1 * math.cos(5 * a + 2 * seed)
            pts.append((cx + radius * 1.25 * k * math.cos(a), cy + radius * k * math.sin(a)))
        return pts

    parts.append(sc.slab("oil", blob(-0.2, 0.1, 1.15, 0.7), 0.02, 0.12, "puddle", bevel=0.005))
    parts.append(sc.slab("oil_drop", blob(1.35, -0.95, 0.32, 2.1), 0.02, 0.12, "puddle", bevel=0.005))
    return parts


def floor_plate():
    w, h = 8.0, 0.6
    parts = [sc.box("base", (w, w, h * 0.5), (0, 0, h * 0.25), "floor_dark", bevel=0.03)]
    for sx in (-1, 1):
        parts.append(sc.box("frame_x", (0.7, w, h), (sx * (w / 2 - 0.35), 0, h / 2), "floor_steel", bevel=0.06))
        parts.append(sc.box("frame_y", (w - 1.4, 0.7, h), (0, sx * (w / 2 - 0.35), h / 2), "floor_steel", bevel=0.06))
    # Gitterrost in der Mitte
    n = 11
    span = w - 1.6
    for i in range(n):
        offset = -span / 2 + (i + 0.5) * span / n
        parts.append(sc.box("bar_x", (0.12, span, 0.25), (offset, 0, h - 0.14), "floor_steel", bevel=0.02))
    for i in range(4):
        offset = -span / 2 + (i + 0.5) * span / 4
        parts.append(sc.box("bar_y", (span, 0.14, 0.18), (0, offset, h - 0.2), "floor_steel", bevel=0.02))
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(sc.cyl("bolt", 0.12, 0.1, (sx * (w / 2 - 0.35), sy * (w / 2 - 0.35), h + 0.02), "steel",
                                verts=8, bevel=0))
    return parts


def ceiling_pipes():
    w = 8.0
    parts = [sc.box("slab", (w, w, 0.5), (0, 0, 2.25), "panel", bevel=0.04)]
    for sx in (-1, 1):
        parts.append(sc.box("beam", (0.6, w, 0.7), (sx * (w / 2 - 0.3), 0, 1.65), "dark", bevel=0.06))
    # Leuchtengehaeuse in der Mitte (die Leuchtflaeche ist im Spiel ein Neon-Teil)
    parts.append(sc.box("lamp_housing", (3.2, 1.0, 0.35), (0, 0, 1.83), "dark", bevel=0.05))
    for x, r, mat in ((-2.6, 0.32, "pipe"), (-1.9, 0.2, "steel"), (2.4, 0.4, "pipe")):
        parts.append(sc.cyl("pipe", r, w, (x, 0, 2.0 - r - 0.1), mat, rot=(90, 0, 0), verts=16, bevel=0))
        for y in (-2.8, 2.8):
            parts.append(sc.cyl("flange", r + 0.08, 0.2, (x, y, 2.0 - r - 0.1), "dark", rot=(90, 0, 0), verts=16,
                                bevel=0.02))
            parts.append(sc.box("clamp", (0.18, 0.18, r + 0.25), (x, y + 0.3, 2.0 - (r + 0.25) / 2), "dark", bevel=0.02))
    # Ventil am grossen Rohr (dort tritt im Spiel Dampf aus)
    parts.append(sc.cyl("valve_stem", 0.08, 0.5, (2.4, 1.2, 2.0 - 0.8 - 0.35), "steel", verts=8, bevel=0))
    parts.append(sc.torus("valve_wheel", 0.28, 0.05, (2.4, 1.2, 2.0 - 0.8 - 0.6), "pipe"))
    return parts


def door():
    w, d, h = 8.0, 1.4, 12.0
    opening_w, opening_h = 5.0, 8.5
    side = (w - opening_w) / 2
    parts = []
    for sx in (-1, 1):
        parts.append(sc.box("jamb", (side, d, h), (sx * (opening_w / 2 + side / 2), 0, h / 2), "panel", bevel=0.06))
        parts.append(sc.box("jamb_stripe", (0.35, d + 0.1, opening_h), (sx * (opening_w / 2 + 0.17), 0, opening_h / 2),
                            "hazard", bevel=0.05))
    parts.append(sc.box("lintel", (opening_w, d, h - opening_h), (0, 0, opening_h + (h - opening_h) / 2), "panel",
                        bevel=0.06))
    parts.append(sc.box("lintel_beam", (opening_w + 0.7, d + 0.12, 0.6), (0, 0, opening_h + 0.3), "hazard",
                        bevel=0.06))
    # halb offenes Schott: ein Fluegel steckt zur Haelfte in der Wand
    parts.append(sc.box("leaf", (1.6, 0.35, opening_h - 0.1), (-opening_w / 2 + 0.8, 0, (opening_h - 0.1) / 2),
                        "steel", bevel=0.06))
    for z in (2.0, 4.2, 6.4):
        parts.append(sc.box("leaf_rib", (1.5, 0.45, 0.25), (-opening_w / 2 + 0.8, 0, z), "dark", bevel=0.03))
    # Warnleuchte ueber der Tuer (Fassung; Glas im Spiel Neon)
    parts.append(sc.cyl("beacon_base", 0.35, 0.25, (0, -d / 2 - 0.1, opening_h + 1.4), "dark", rot=(90, 0, 0),
                        verts=12))
    return parts


def console():
    parts = [sc.box("cabinet", (5.0, 2.0, 2.6), (0, 0.25, 1.3), "panel", bevel=0.08)]
    parts.append(sc.box("kick", (4.8, 0.3, 0.3), (0, -0.7, 0.15), "dark", bevel=0.03))
    desk = sc.box("desk", (5.2, 1.6, 0.25), (0, -0.55, 2.7), "dark", rot=(-14, 0, 0), bevel=0.06)
    parts.append(desk)
    for x in (-1.3, 1.3):
        parts.append(sc.box("monitor", (2.2, 0.35, 1.5), (x, 0.9, 3.65), "dark", rot=(8, 0, 0), bevel=0.08))
        parts.append(sc.box("monitor_arm", (0.2, 0.2, 0.9), (x, 1.05, 2.9), "steel", bevel=0.03))
    for i in range(6):
        parts.append(sc.cyl("button", 0.1, 0.12, (-2.0 + i * 0.32, -0.95, 2.66), "steel", rot=(-14, 0, 0), verts=8,
                            bevel=0))
    parts.append(sc.box("keyboard", (1.8, 0.6, 0.08), (0.9, -0.75, 2.78), "steel", rot=(-14, 0, 0), bevel=0.02))
    parts.append(sc.cyl("lever", 0.05, 0.5, (-0.6, -0.9, 2.95), "steel", rot=(-30, 0, 0), verts=8, bevel=0))
    parts.append(sc.sphere("lever_knob", 0.11, (-0.6, -1.03, 3.18), "rubber", subdiv=1))
    return parts


def console_r2():
    """Konsole Look-Runde 2: Grundform wie console() (Monitore an gleicher Stelle), dazu Knopffelder in Farbe,
    Kippschalter, Drehregler, Warnstreifen am Sockel, Lueftungsschlitze und Kabel an der Rueckseite."""
    parts = console()
    tilt = (-14, 0, 0)

    def on_desk(x, ly, lz=0.16):
        # Punkt auf der Pultoberseite: Pult-lokal (ly quer, lz ueber der Mitte), Pult bei (0, -0.55, 2.7) um X -14 Grad
        a = math.radians(-14)
        return (x, -0.55 + ly * math.cos(a) - lz * math.sin(a), 2.7 + ly * math.sin(a) + lz * math.cos(a))

    colors = ("button_red", "button_green", "button_amber")
    for row, y in enumerate((-0.25, -0.05)):
        for i in range(6):
            parts.append(sc.cyl("key", 0.08, 0.1, on_desk(-2.2 + i * 0.28, y), colors[(i + row) % 3], rot=tilt, verts=8,
                                bevel=0))
    for i in range(4):
        x = 0.25 + i * 0.32
        parts.append(sc.box("switch_base", (0.18, 0.22, 0.08), on_desk(x, -0.15), "dark", rot=tilt, bevel=0.02))
        parts.append(sc.cyl("switch_lever", 0.025, 0.22, on_desk(x, -0.2), "steel", rot=(-14 - 30 * (1 if i % 2 else -1),
                                                                                         0, 0), verts=6, bevel=0))
    for x in (1.9, 2.3):
        parts.append(sc.cyl("dial", 0.12, 0.08, on_desk(x, -0.3), "dark", rot=tilt, verts=16, bevel=0.01))
        parts.append(sc.box("dial_mark", (0.03, 0.1, 0.03), on_desk(x + 0.03, -0.33), "button_amber", rot=tilt, bevel=0))
    parts.append(sc.box("kick_stripe", (4.9, 0.08, 0.25), (0, -0.88, 0.45), "hazard", bevel=0.02))
    for i in range(5):
        parts.append(sc.box("side_vent", (0.08, 1.2, 0.08), (2.53, 0.25, 0.8 + i * 0.22), "dark", bevel=0.01))
    # Kabel aus der Rueckseite: oben heraus, hinten am Boden seitlich weg
    for i, (x, r) in enumerate(((-1.6, 0.09), (-1.2, 0.07), (0.8, 0.1), (1.3, 0.06))):
        side = -1 if x < 0 else 1
        parts.append(sc.tube("rear_cable", [(x, 1.26, 2.2), (x + 0.1 * side, 1.5, 1.3), (x + 0.6 * side, 1.45, 0.12),
                                            (side * (3.1 + 0.2 * i), 1.35, 0.1)], r, "rubber", resolution=6))
    parts.append(sc.box("rear_box", (1.2, 0.3, 0.8), (0, 1.32, 1.9), "steel", bevel=0.04))
    return parts


def cart():
    parts = []
    for z, name in ((2.4, "top"), (0.9, "shelf")):
        parts.append(sc.box(name, (3.0, 1.8, 0.14), (0, 0, z), "steel", bevel=0.04))
        parts.append(sc.box(name + "_lip", (3.0, 0.1, 0.25), (0, -0.85, z + 0.15), "steel", bevel=0.02))
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(sc.cyl("post", 0.07, 2.2, (sx * 1.38, sy * 0.78, 1.4), "dark", verts=10, bevel=0))
            parts.append(sc.cyl("wheel", 0.2, 0.12, (sx * 1.38, sy * 0.78, 0.2), "rubber", rot=(0, 90, 0), verts=12,
                                bevel=0.02))
    parts.append(sc.tube("handle", [(1.5, -0.7, 2.5), (1.85, -0.7, 2.8), (1.85, 0.7, 2.8), (1.5, 0.7, 2.5)], 0.06,
                         "dark"))
    # Halterung fuer das Artefakt
    parts.append(sc.box("cradle", (0.9, 0.9, 0.2), (-0.6, 0, 2.57), "dark", bevel=0.05))
    return parts


def crate():
    s = 3.0
    parts = [sc.box("body", (s - 0.2, s - 0.2, s - 0.2), (0, 0, s / 2), "panel", bevel=0.06)]
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(sc.box("corner", (0.35, 0.35, s), (sx * (s / 2 - 0.17), sy * (s / 2 - 0.17), s / 2), "dark",
                                bevel=0.05))
    for z in (0.25, s - 0.25):
        parts.append(sc.box("band", (s, s, 0.3), (0, 0, z), "dark", bevel=0.05))
    parts.append(sc.box("rib", (s - 0.4, 0.3, 0.2), (0, -s / 2 + 0.05, s / 2), "hazard", bevel=0.04))
    parts.append(sc.box("latch", (0.4, 0.2, 0.5), (0, -s / 2 - 0.05, s - 0.6), "steel", bevel=0.04))
    return parts


def drone():
    parts = [sc.sphere("body", 0.9, (0, 0, 0), "drone", scale=(1.25, 1.0, 0.6), subdiv=3)]
    parts.append(sc.torus("ring", 1.35, 0.1, (0, 0, 0), "dark", major_seg=32))
    for sx in (-1, 1):
        parts.append(sc.box("arm", (0.6, 0.18, 0.12), (sx * 1.6, 0, 0.1), "dark", bevel=0.03))
        parts.append(sc.cyl("rotor_hub", 0.45, 0.14, (sx * 2.05, 0, 0.22), "dark", verts=16))
        parts.append(sc.box("rotor_blade", (0.9, 0.12, 0.03), (sx * 2.05, 0, 0.32), "steel", rot=(0, 0, 35 * sx),
                            bevel=0))
    # Fassung fuer Auge und Suchscheinwerfer (Linse im Spiel Neon)
    parts.append(sc.cyl("eye_mount", 0.32, 0.3, (0, -0.85, -0.12), "dark", rot=(90, 0, 0), verts=16))
    parts.append(sc.box("antenna", (0.05, 0.05, 0.6), (0.5, 0.3, 0.75), "steel", bevel=0))
    return parts


def artifact():
    parts = [sc.cyl("base", 0.6, 0.3, (0, 0, 0.15), "dark", verts=16)]
    parts.append(sc.cyl("collar", 0.4, 0.25, (0, 0, 0.42), "steel", verts=16))
    parts.append(sc.torus("halo", 0.62, 0.05, (0, 0, 1.25), "steel", rot=(70, 0, 20)))
    for a in range(3):
        ang = math.radians(a * 120)
        parts.append(sc.box("prong", (0.1, 0.1, 1.0), (0.42 * math.cos(ang), 0.42 * math.sin(ang), 0.95), "dark",
                            rot=(0, 0, a * 120), bevel=0.02))
    return parts


def artifact_crystal():
    crystal = sc.sphere("crystal", 0.35, (0, 0, 1.25), "frost", scale=(0.65, 0.65, 1.5), subdiv=1)
    crystal.rotation_euler = (0.15, 0.2, 0.4)
    return crystal


def cable_bundle():
    parts = []
    for i, (x, y, r) in enumerate(((-0.35, 0, 0.11), (-0.1, 0.12, 0.09), (0.15, -0.05, 0.13), (0.38, 0.1, 0.08))):
        sag = 0.6 + i * 0.25
        parts.append(sc.tube("cable", [(x, y, 11.8), (x + 0.2, y - 0.2, 9.0), (x + 0.8 + sag, y - 0.5, 6.0),
                                        (x + 0.3, y - 0.3, 3.0), (x, y, 1.2)], r, "rubber", resolution=8))
    for z in (11.2, 1.0):
        parts.append(sc.box("clamp", (1.2, 0.6, 0.3), (0, 0.05, z), "steel", bevel=0.04))
    parts.append(sc.box("junction", (1.4, 0.7, 1.0), (0, 0.05, 0.5), "panel", bevel=0.06))
    return parts


MODULES = {
    "station_wall_panel": wall_panel,
    "station_floor_plate": floor_plate,
    "station_ceiling_pipes": ceiling_pipes,
    "station_door": door,
    "station_console": console,
    "station_cart": cart,
    "station_crate": crate,
    "station_drone": drone,
    "station_artifact": artifact,
    "station_cable_bundle": cable_bundle,
    "station_wall_window": wall_window,
    "station_wall_damaged": wall_damaged,
    "station_vent": vent,
    "station_warning_sign": warning_sign,
    "station_puddle": puddle,
}

# Look-Runde 2: Revision je Modul (Konsole mit neuer Form, die anderen nur neu gebacken)
REVISION_2 = {
    "station_wall_panel": "_r2",
    "station_floor_plate": "_r2",
    "station_ceiling_pipes": "_r2",
    "station_door": "_r2",
    "station_drone": "_r2",
    "station_console": "_r2",
    "station_wall_window": "",
    "station_wall_damaged": "",
    "station_vent": "",
    "station_warning_sign": "",
    "station_puddle": "",
}
BUILDERS_R2 = {"station_console": console_r2}
RETEXTURE_ONLY = {"station_wall_panel", "station_floor_plate", "station_ceiling_pipes", "station_door", "station_drone"}


def build_one(name: str, do_bake: bool = True, revision: str = "", export: bool = True) -> str:
    """Baut ein Modul; revision haengt sich an Karten- und FBX-Namen (das Objekt behaelt den Modulnamen)."""
    sc.reset()
    sc.clear_materials()
    builder = BUILDERS_R2.get(name, MODULES[name]) if revision else MODULES[name]
    obj = sc.join(name, builder())
    sc.unwrap(obj)
    tris = sc.triangles(obj)
    assert tris <= sc.TRIANGLE_BUDGET, f"{name}: {tris} Dreiecke > {sc.TRIANGLE_BUDGET}"
    objects = [obj]
    if name == "station_artifact":
        # gleiche Verschiebung wie der Sockel beim Zentrieren, damit der Kristall im Halter sitzt
        crystal = artifact_crystal()
        crystal.location -= Vector(obj["bounds_center"])
        objects.append(crystal)
    center = [round(v, 3) for v in obj["bounds_center"]]
    if do_bake:
        sc.bake(obj, revision)
    if export:
        sc.export_fbx(objects, f"{name}{revision}.fbx")
    if do_bake:
        sc.preview(obj, suffix=revision)
    return f"{name}{revision}: {tris} tris, Groesse {sc.size_of(obj)}, Mitte {center}"


def main():
    for name, revision in REVISION_2.items():
        # Form unveraendert: nur neue Karten, das hochgeladene Mesh bleibt
        print(build_one(name, revision=revision, export=name not in RETEXTURE_ONLY))


if __name__ == "__main__":
    main()
