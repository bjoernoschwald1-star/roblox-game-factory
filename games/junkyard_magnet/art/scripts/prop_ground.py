"""Kulisse Bodenplatte: 32 x 32 Studs Sandboden mit flachen Erdflecken und Oelflecken (seeded), kachelbar.

Groesse 32 x 32 x 0.6 Studs, Budget 8.000 Dreiecke.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import jm_common as jm  # noqa: E402

NAME = "prop_ground"
BUDGET = 8000
SEED = 3
SIZE = 32.0


def add(b: jm.Builder, matrix=None):
    m = matrix if matrix is not None else jm.transform()
    rng = jm.seeded(SEED)
    sand = jm.solid_material("sand", 0.0, 0.95)
    dirt = jm.solid_material("rust_dark", 0.0, 0.95)
    oil = jm.solid_material("chrome_dark", 0.2, 0.4)
    b.box((SIZE, SIZE, 0.5), sand, m @ jm.transform((0, 0, 0.25)))
    for _ in range(9):
        x, y = rng.uniform(-13, 13), rng.uniform(-13, 13)
        r = rng.uniform(1.0, 2.8)
        b.cylinder(r, 0.08, 8, dirt, m @ jm.transform((x, y, 0.52), (0, 0, rng.uniform(0, 45)), (1.0, 0.7, 1.0)))
    for _ in range(3):
        x, y = rng.uniform(-12, 12), rng.uniform(-12, 12)
        b.cylinder(rng.uniform(0.8, 1.6), 0.06, 10, oil, m @ jm.transform((x, y, 0.53)))
    # Kleine Steine fuer Struktur
    for _ in range(14):
        x, y = rng.uniform(-15, 15), rng.uniform(-15, 15)
        s = rng.uniform(0.2, 0.45)
        b.icosphere(s, 1, dirt, m @ jm.transform((x, y, 0.5), (0, 0, 0), (1.0, 1.0, 0.6)))


def build(name: str):
    b = jm.Builder(name)
    add(b)
    return b.finish()


if __name__ == "__main__":
    jm.run_single(build, NAME, BUDGET)
