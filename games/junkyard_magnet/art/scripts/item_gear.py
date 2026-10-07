"""Schrottteil Zahnrad: aufrecht stehendes Zahnrad mit Nabe und Loechern als Akzent.

Groesse ca. 2.4 x 0.5 x 2.4 Studs, Budget 1.500 Dreiecke.
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import jm_common as jm  # noqa: E402

NAME = "item_gear"
BUDGET = 1500
TEETH = 10


def add(b: jm.Builder, rarity: str, matrix=None):
    primary, accent = jm.rarity_materials(rarity)
    m = matrix if matrix is not None else jm.transform()
    # Achse entlang Y (Vorderseite zeigt nach -Y), Zahnrad steht auf den Zaehnen
    center = m @ jm.transform((0, 0, 1.2), (90, 0, 0))
    b.tube(0.95, 0.42, 0.34, 20, primary, center)
    for k in range(TEETH):
        a = 360.0 * k / TEETH
        r = math.radians(a)
        tooth = jm.transform((1.05 * math.cos(r), 1.05 * math.sin(r), 0), (0, 0, a))
        b.box((0.34, 0.34, 0.3), primary, center @ tooth, bevel=0.04)
    b.tube(0.42, 0.18, 0.5, 8, accent, center)
    for k in range(4):
        r = math.radians(45 + 90 * k)
        b.cylinder(0.1, 0.4, 6, accent, center @ jm.transform((0.68 * math.cos(r), 0.68 * math.sin(r), 0)))


def build(rarity: str, name: str):
    b = jm.Builder(name)
    add(b, rarity)
    return b.finish()


if __name__ == "__main__":
    jm.run_variants(build, NAME, BUDGET)
