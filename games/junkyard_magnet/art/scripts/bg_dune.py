"""Hintergrund Duene: flacher, sanfter Sandhuegel mit wenigen Grasbueschen (seeded).

Groesse ca. 90 x 60 x 12 Studs, Budget 1.000 (wird oft und weit weg gesetzt).
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import jm_common as jm  # noqa: E402


def build(name: str):
    b = jm.Builder(name)
    rng = jm.seeded(31)
    sand = jm.solid_material("sand", 0.0, 0.95)
    grass = jm.solid_material("olive_green", 0.0, 0.85)
    for v in b.icosphere(1.0, 3, sand):
        v.co = v.co * (1.0 + rng.uniform(-0.05, 0.05))
        v.co.x *= 45.0
        v.co.y *= 30.0
        v.co.z = max(v.co.z * 12.0, 0.0)
    for _ in range(7):
        a = rng.uniform(0.0, 2 * math.pi)
        r = rng.uniform(0.25, 0.7)
        x, y = 45.0 * r * math.cos(a), 30.0 * r * math.sin(a)
        z = 12.0 * math.sqrt(max(1.0 - r * r, 0.0)) - 0.6
        b.cylinder(1.6, 2.2, 5, grass, jm.transform((x, y, z + 1.0)), radius_top=0.2)
    return b.finish()


ENTRIES = [("bg_dune", build, 1000)]
