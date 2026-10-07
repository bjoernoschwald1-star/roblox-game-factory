"""Kulisse Zaunelement: Wellblech-Paneele zwischen Pfosten, oben ein Rohr, mit Rostflecken.

Groesse ca. 16 x 0.8 x 8 Studs, Budget 8.000 Dreiecke. Laengsachse X, Vorderseite -Y.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import jm_common as jm  # noqa: E402

NAME = "prop_fence"
BUDGET = 8000
LENGTH, HEIGHT = 16.0, 8.0


def add(b: jm.Builder, matrix=None):
    m = matrix if matrix is not None else jm.transform()
    rng = jm.seeded(5)
    panel = jm.solid_material("chrome_dark", 0.5, 0.6)
    post = jm.solid_material("steel_blue", 0.3, 0.6)
    rust = jm.solid_material("rust_orange", 0.2, 0.85)
    # Wellblech: abwechselnd vor- und zurueckgesetzte Streifen
    x = -LENGTH / 2 + 0.25
    k = 0
    while x < LENGTH / 2 - 0.2:
        y = -0.12 if k % 2 == 0 else 0.12
        b.box((0.5, 0.16, HEIGHT - 1.2), panel, m @ jm.transform((x, y, (HEIGHT - 1.2) / 2 + 0.4)))
        x += 0.5
        k += 1
    for px in (-LENGTH / 2, 0.0, LENGTH / 2):
        b.box((0.6, 0.6, HEIGHT), post, m @ jm.transform((px, 0, HEIGHT / 2)), bevel=0.06)
    b.cylinder(0.18, LENGTH, 8, post, m @ jm.transform((0, 0, HEIGHT - 0.6), (0, 90, 0)))
    for _ in range(4):
        rx = rng.uniform(-LENGTH / 2 + 1, LENGTH / 2 - 1)
        rz = rng.uniform(1.0, HEIGHT - 2.5)
        b.box((rng.uniform(0.6, 1.4), 0.05, rng.uniform(0.6, 1.8)), rust, m @ jm.transform((rx, -0.23, rz)))


def build(name: str):
    b = jm.Builder(name)
    add(b)
    return b.finish()


if __name__ == "__main__":
    jm.run_single(build, NAME, BUDGET)
