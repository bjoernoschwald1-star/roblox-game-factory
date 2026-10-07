"""Schrottteil Blechplatte: leicht geknickte Platte mit Nieten (Seltenheit = Materialvariante).

Groesse ca. 2.4 x 1.8 x 0.6 Studs, Budget 1.500 Dreiecke.
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import jm_common as jm  # noqa: E402

NAME = "item_plate"
BUDGET = 1500


def add(b: jm.Builder, rarity: str, matrix=None):
    primary, accent = jm.rarity_materials(rarity)
    m = matrix if matrix is not None else jm.transform()
    # Zwei Plattenhaelften mit Knick ergeben eine klare, nicht flache Silhouette
    b.box((1.25, 1.8, 0.22), primary, m @ jm.transform((-0.58, 0, 0.32), (0, -14, 0)), bevel=0.05)
    b.box((1.25, 1.8, 0.22), primary, m @ jm.transform((0.58, 0, 0.32), (0, 14, 0)), bevel=0.05)
    # Nieten sitzen auf der Oberseite (Mitte 0.43, Neigung 14 Grad zum First hin ansteigend)
    for x in (-0.95, -0.35, 0.35, 0.95):
        for y in (-0.65, 0.65):
            z = 0.43 + (0.58 - abs(x)) * math.tan(math.radians(14)) + 0.02
            tilt = -14 if x < 0 else 14
            b.cylinder(0.11, 0.12, 6, accent, m @ jm.transform((x, y, z), (0, tilt, 0)))


def build(rarity: str, name: str):
    b = jm.Builder(name)
    add(b, rarity)
    return b.finish()


if __name__ == "__main__":
    jm.run_variants(build, NAME, BUDGET)
