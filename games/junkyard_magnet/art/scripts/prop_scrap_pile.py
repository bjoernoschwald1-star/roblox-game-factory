"""Kulisse Schrotthaufen: niedriger Huegel mit eingesteckten, vergroesserten Schrottteilen (seeded).

Groesse ca. 16 x 12 x 7 Studs, Budget 8.000 Dreiecke.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import item_barrel  # noqa: E402
import item_gear  # noqa: E402
import item_pipe  # noqa: E402
import item_plate  # noqa: E402
import jm_common as jm  # noqa: E402

NAME = "prop_scrap_pile"
BUDGET = 8000
SEED = 1


def add(b: jm.Builder, matrix=None):
    m = matrix if matrix is not None else jm.transform()
    rng = jm.seeded(SEED)
    dirt = jm.solid_material("rust_dark", 0.1, 0.95)
    # Huegel aus einer verbeulten, abgeflachten Ikosphaere; Unterseite plan auf z = 0
    for v in b.icosphere(1.0, 3, dirt, m):
        v.co = v.co * (1.0 + rng.uniform(-0.12, 0.12))
        v.co.x *= 8.0
        v.co.y *= 6.0
        v.co.z = max(v.co.z * 5.0, 0.0)
    pieces = [
        (item_plate.add, (-3.5, -2.5, 3.4), (20, -30, 15), 2.2),
        (item_pipe.add, (2.5, -2.0, 3.3), (0, -25, -35), 2.4),
        (item_gear.add, (0.0, 1.0, 3.8), (-10, 15, 10), 2.0),
        (item_barrel.add, (5.0, 2.0, 1.7), (12, 25, 0), 1.8),
        (item_plate.add, (-5.0, 2.5, 1.9), (-25, 10, 60), 2.0),
        (item_pipe.add, (-1.0, -4.2, 1.5), (-15, 5, 80), 2.0),
    ]
    for add_fn, loc, rot, scale in pieces:
        add_fn(b, "rusty", m @ jm.transform(loc, rot, (scale, scale, scale)))
    # Ein Reifen als Farbtupfer
    green = jm.solid_material("olive_green", 0.0, 0.8)
    b.tube(1.4, 0.8, 0.8, 14, green, m @ jm.transform((6.0, -3.0, 1.0), (70, 0, 20)))


def build(name: str):
    b = jm.Builder(name)
    add(b)
    return b.finish()


if __name__ == "__main__":
    jm.run_single(build, NAME, BUDGET)
