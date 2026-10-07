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
    # Grosser Huegel grau (Metall), kleiner Huegel Rost: der Haufen wirkt gemischt statt rot.
    dirt = jm.solid_material("metal_gray", 0.3, 0.7)
    # Huegel aus einer verbeulten, abgeflachten Ikosphaere; Unterseite plan auf z = 0
    for v in b.icosphere(1.0, 3, dirt, m):
        v.co = v.co * (1.0 + rng.uniform(-0.12, 0.12))
        v.co.x *= 8.0
        v.co.y *= 6.0
        v.co.z = max(v.co.z * 5.0, 0.0)
    b.reshape_last((8.0, 6.0, 5.0))
    # Zweiter, grauer Huegel: Haufen gemischt aus Rost- und Metalltoenen
    gray = jm.solid_material("rust_dark", 0.1, 0.9)
    for v in b.icosphere(3.6, 2, gray, m @ jm.transform((3.0, 1.5, 0.0), (0, 0, 0), (1.0, 0.9, 0.9))):
        v.co.z = max(v.co.z, 0.0)  # Unterseite plan, damit der Drehpunkt am Boden bleibt
    pieces = [
        (item_plate.add, (-3.5, -2.5, 3.4), (20, -30, 15), 2.2),
        (item_pipe.add, (2.5, -2.0, 3.3), (0, -25, -35), 2.4),
        (item_gear.add, (0.0, 1.0, 3.8), (-10, 15, 10), 2.0),
        (item_barrel.add, (5.0, 2.0, 1.7), (12, 25, 0), 1.8),
        (item_plate.add, (-5.0, 2.5, 1.9), (-25, 10, 60), 2.0),
        (item_pipe.add, (-1.0, -4.2, 1.5), (-15, 5, 80), 2.0),
    ]
    # Gemischte Teile: Rost, Grau, Chrom und einzelne bunte (blau, gruen, gelb)
    variants = ["gray", "blue", "rusty", "yellow", "chrome", "green"]
    for (add_fn, loc, rot, scale), variant in zip(pieces, variants):
        add_fn(b, variant, m @ jm.transform(loc, rot, (scale, scale, scale)))
    # Ein Reifen als Farbtupfer
    green = jm.solid_material("olive_green", 0.0, 0.8)
    b.tube(1.4, 0.8, 0.8, 14, green, m @ jm.transform((6.0, -3.0, 1.0), (70, 0, 20)))


def build(name: str):
    b = jm.Builder(name)
    add(b)
    return b.finish()


if __name__ == "__main__":
    jm.run_single(build, NAME, BUDGET)
