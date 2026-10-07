"""Schrottteil Rohrstueck: hohles Rohr mit zwei Flanschen und Schrauben.

Groesse ca. 2.6 x 1.3 x 1.3 Studs, Budget 1.500 Dreiecke.
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import jm_common as jm  # noqa: E402

NAME = "item_pipe"
BUDGET = 1500


def add(b: jm.Builder, rarity: str, matrix=None):
    primary, accent = jm.rarity_materials(rarity)
    m = matrix if matrix is not None else jm.transform()
    axis = m @ jm.transform((0, 0, 0.65), (0, 90, 0))
    b.tube(0.42, 0.3, 2.3, 12, primary, axis)
    for x in (-1.15, 1.15):
        b.tube(0.65, 0.3, 0.2, 12, accent, axis @ jm.transform((0, 0, x)))
        for k in range(6):
            a = 2 * math.pi * k / 6
            b.cylinder(0.07, 0.3, 6, accent, axis @ jm.transform((0.53 * math.cos(a), 0.53 * math.sin(a), x)))


def build(rarity: str, name: str):
    b = jm.Builder(name)
    add(b, rarity)
    return b.finish()


if __name__ == "__main__":
    jm.run_variants(build, NAME, BUDGET)
