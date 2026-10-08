"""Schrottteil Anker: aufrecht stehender Schiffsanker mit Ring, Querstock, Schaft und zwei Armen mit Flunken.

Groesse ca. 1.9 x 0.5 x 2.6 Studs, Budget 1.500 Dreiecke. Hauptmaterial Schaft und Arme, Akzent Ring, Stock und
Flunken (wie bei den anderen Teilen: Seltenheit = Materialvariante).
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import jm_common as jm  # noqa: E402

NAME = "item_anchor"
BUDGET = 1500


def add(b: jm.Builder, rarity: str, matrix=None):
    primary, accent = jm.rarity_materials(rarity)
    m = matrix if matrix is not None else jm.transform()
    # Schaft (senkrecht) und Krone unten
    b.box((0.32, 0.32, 1.9), primary, m @ jm.transform((0, 0, 1.25)), bevel=0.04)
    b.box((0.5, 0.36, 0.3), primary, m @ jm.transform((0, 0, 0.32)), bevel=0.04)
    # Arme: schraeg nach oben aussen, mit breiten Flunken
    for side in (-1, 1):
        b.box((0.95, 0.3, 0.26), primary, m @ jm.transform((side * 0.5, 0, 0.42), (0, side * -32, 0)), bevel=0.03)
        b.box((0.42, 0.38, 0.5), accent, m @ jm.transform((side * 0.92, 0, 0.78), (0, side * -32, 0)), bevel=0.04)
    # Querstock oben und Ring
    b.cylinder(0.12, 1.3, 8, accent, m @ jm.transform((0, 0, 2.05), (0, 90, 0)))
    b.tube(0.32, 0.18, 0.16, 12, accent, m @ jm.transform((0, 0, 2.42), (90, 0, 0)))


def build(rarity: str, name: str):
    b = jm.Builder(name)
    add(b, rarity)
    return b.finish()


if __name__ == "__main__":
    jm.run_variants(build, NAME, BUDGET)
