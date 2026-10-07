"""Kulisse Reifenstapel: fuenf Reifen versetzt gestapelt, einer angelehnt (seeded).

Groesse ca. 7 x 6 x 6 Studs, Budget 8.000 Dreiecke.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import jm_common as jm  # noqa: E402

NAME = "prop_tire_stack"
BUDGET = 8000


def tire(b: jm.Builder, matrix, rubber, rim):
    b.tube(1.6, 0.9, 1.0, 16, rubber, matrix)
    b.tube(0.95, 0.7, 0.6, 12, rim, matrix)


def add(b: jm.Builder, matrix=None):
    m = matrix if matrix is not None else jm.transform()
    rng = jm.seeded(8)
    rubber = jm.solid_material("tire_black", 0.0, 0.9)
    rim = jm.solid_material("chrome_dark", 0.7, 0.4)
    for level in range(5):
        dx, dy = rng.uniform(-0.35, 0.35), rng.uniform(-0.35, 0.35)
        tire(b, m @ jm.transform((dx, dy, 0.5 + level * 1.0), (rng.uniform(-3, 3), rng.uniform(-3, 3), 0)), rubber, rim)
    tire(b, m @ jm.transform((2.9, -0.8, 1.6), (90, 0, 15)), rubber, rim)
    green = jm.solid_material("olive_green", 0.0, 0.8)
    tire(b, m @ jm.transform((-2.6, 1.2, 0.5), (0, 0, 0)), green, rim)


def build(name: str):
    b = jm.Builder(name)
    add(b)
    return b.finish()


if __name__ == "__main__":
    jm.run_single(build, NAME, BUDGET)
