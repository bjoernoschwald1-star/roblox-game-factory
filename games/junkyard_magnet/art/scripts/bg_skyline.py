"""Hintergrund Fabrik-Silhouette am Horizont: Hallen mit Saegezahndaechern, Schornsteine, Tanks (seeded).

Breite ca. 260 Studs, Hoehe bis 70 Studs, Tiefe 20. Nur grosse Formen (Silhouette im Dunst), Budget 1.200.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import jm_common as jm  # noqa: E402


def build(name: str):
    b = jm.Builder(name)
    rng = jm.seeded(41)
    wall = jm.solid_material("chrome_dark", 0.0, 0.8)
    dark = jm.solid_material("metal_gray", 0.0, 0.8)
    x = -130.0
    while x < 130.0:
        w = rng.uniform(16.0, 34.0)
        h = rng.uniform(14.0, 34.0)
        mat = wall if rng.random() < 0.6 else dark
        b.box((w, 16.0, h), mat, jm.transform((x + w / 2, rng.uniform(-3, 3), h / 2)))
        if rng.random() < 0.5:
            # Saegezahndach aus schraegen Platten
            for k in range(int(w // 8)):
                b.box((8.0, 15.0, 1.2), mat, jm.transform((x + 4 + k * 8, 0, h + 2.0), (0, -28, 0)))
        x += w + rng.uniform(0.0, 6.0)
    for cx in (-80.0, -20.0, 55.0, 100.0):
        hh = rng.uniform(50.0, 70.0)
        b.cylinder(2.6, hh, 8, dark, jm.transform((cx, 4.0, hh / 2)), radius_top=2.0)
    for cx in (-50.0, 20.0):
        b.cylinder(9.0, 20.0, 10, wall, jm.transform((cx, -6.0, 10.0)))
    return b.finish()


ENTRIES = [("bg_skyline", build, 1200)]
