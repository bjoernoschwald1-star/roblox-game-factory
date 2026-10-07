"""Schrottteil kleines Fass: bauchiges Fass mit zwei Reifen, Deckelrand und Spund.

Groesse ca. 1.7 x 1.7 x 2.0 Studs, Budget 1.500 Dreiecke.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import jm_common as jm  # noqa: E402

NAME = "item_barrel"
BUDGET = 1500


def add(b: jm.Builder, rarity: str, matrix=None):
    primary, accent = jm.rarity_materials(rarity)
    m = matrix if matrix is not None else jm.transform()
    b.cylinder(0.75, 0.95, 14, primary, m @ jm.transform((0, 0, 0.475)), radius_top=0.82)
    b.cylinder(0.82, 0.95, 14, primary, m @ jm.transform((0, 0, 1.425)), radius_top=0.75)
    for z in (0.55, 1.35):
        b.tube(0.86, 0.72, 0.16, 14, accent, m @ jm.transform((0, 0, z)))
    b.tube(0.78, 0.62, 0.14, 14, accent, m @ jm.transform((0, 0, 1.94)))
    b.cylinder(0.14, 0.12, 6, accent, m @ jm.transform((0.35, 0.2, 1.95)))


def build(rarity: str, name: str):
    b = jm.Builder(name)
    add(b, rarity)
    return b.finish()


if __name__ == "__main__":
    jm.run_variants(build, NAME, BUDGET)
