"""Hintergrund Strommast: Holzmast mit zwei Traversen und Isolatoren (die Leitungen setzt das Spiel als Parts).

Groesse ca. 12 x 1.2 x 35 Studs, Budget 600. Traversen entlang Blender X (quer zur Leitung, die entlang Y laeuft).
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import jm_common as jm  # noqa: E402

HEIGHT = 34.0


def build(name: str):
    b = jm.Builder(name)
    wood = jm.solid_material("rust_dark", 0.0, 0.9)
    metal = jm.solid_material("chrome_dark", 0.6, 0.5)
    glass = jm.solid_material("chrome_light", 0.0, 0.3)
    b.cylinder(0.6, HEIGHT, 6, wood, jm.transform((0, 0, HEIGHT / 2)), radius_top=0.45)
    for z, w in ((HEIGHT - 2.0, 12.0), (HEIGHT - 6.0, 8.0)):
        b.box((w, 0.7, 0.7), metal, jm.transform((0, 0, z)))
        for x in (-w / 2 + 0.6, w / 2 - 0.6):
            b.cylinder(0.3, 1.2, 6, glass, jm.transform((x, 0, z + 0.95)))
    return b.finish()


ENTRIES = [("bg_power_pole", build, 600)]
