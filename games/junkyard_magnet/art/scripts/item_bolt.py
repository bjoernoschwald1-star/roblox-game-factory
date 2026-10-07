"""Schrottteil Schraube mit Mutter: dicke Sechskantschraube, stehend, Mutter halb aufgedreht.

Groesse ca. 1.4 x 1.3 x 2.1 Studs, Budget 1.500 Dreiecke.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import jm_common as jm  # noqa: E402

NAME = "item_bolt"
BUDGET = 1500


def add(b: jm.Builder, rarity: str, matrix=None):
    primary, accent = jm.rarity_materials(rarity)
    m = matrix if matrix is not None else jm.transform()
    b.cylinder(0.7, 0.45, 6, primary, m @ jm.transform((0, 0, 0.225)))
    b.cylinder(0.32, 1.6, 10, primary, m @ jm.transform((0, 0, 1.25)))
    for z in (0.75, 0.95, 1.15, 1.75, 1.95):
        b.cylinder(0.36, 0.08, 10, accent, m @ jm.transform((0, 0, z)))
    b.tube(0.62, 0.32, 0.4, 6, accent, m @ jm.transform((0, 0, 1.45), (0, 0, 30)))


def build(rarity: str, name: str):
    b = jm.Builder(name)
    add(b, rarity)
    return b.finish()


if __name__ == "__main__":
    jm.run_variants(build, NAME, BUDGET)
