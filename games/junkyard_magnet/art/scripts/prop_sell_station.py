"""Kulisse Verkaufsstation: Waagenplattform mit gelb-schwarzem Rand, Bude mit Dach, Waage und Muenz-Symbol
(Scheibe ohne Schrift).

Groesse ca. 16 x 16 x 10 Studs, Budget 8.000 Dreiecke. Plattform mittig, Bude hinten (+Y).
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import jm_common as jm  # noqa: E402

NAME = "prop_sell_station"
BUDGET = 8000


def add(b: jm.Builder, matrix=None):
    m = matrix if matrix is not None else jm.transform()
    plate = jm.solid_material("chrome_dark", 0.6, 0.4)
    gold = jm.solid_material("gold", 1.0, 0.25)
    rim = jm.solid_material("rust_dark", 0.0, 0.8)
    hut = jm.solid_material("steel_blue", 0.2, 0.6)
    roof = jm.solid_material("magnet_red", 0.0, 0.5)
    glass = jm.solid_material("chrome_light", 0.1, 0.1)
    # Waagenplattform 12 x 12 mit Warnrand (abwechselnd gold / dunkel)
    b.box((12.0, 12.0, 0.4), plate, m @ jm.transform((0, -1.5, 0.2)))
    for k in range(12):
        mat = gold if k % 2 == 0 else rim
        off = -5.5 + k
        b.box((1.0, 0.6, 0.45), mat, m @ jm.transform((off, -7.8, 0.22)))
        b.box((1.0, 0.6, 0.45), mat, m @ jm.transform((off, 4.8, 0.22)))
        b.box((0.6, 1.0, 0.45), mat, m @ jm.transform((-6.3, off - 1.5, 0.22)))
        b.box((0.6, 1.0, 0.45), mat, m @ jm.transform((6.3, off - 1.5, 0.22)))
    # Bude hinten
    b.box((6.0, 3.0, 5.0), hut, m @ jm.transform((0, 6.8, 2.5)), bevel=0.1)
    b.box((7.0, 4.0, 0.4), roof, m @ jm.transform((0, 6.6, 5.2), (8, 0, 0)))
    b.box((3.0, 0.1, 1.6), glass, m @ jm.transform((0, 5.25, 3.2)))
    # Muenz-Symbol auf Mast (Scheibe, keine Schrift)
    b.cylinder(0.2, 4.0, 6, plate, m @ jm.transform((3.6, 6.0, 7.0)))
    b.cylinder(1.4, 0.35, 16, gold, m @ jm.transform((3.6, 5.9, 9.4), (90, 0, 0)))
    b.cylinder(0.9, 0.4, 16, glass, m @ jm.transform((3.6, 5.85, 9.4), (90, 0, 0)))
    # Waage-Anzeige
    b.box((1.6, 1.0, 2.4), plate, m @ jm.transform((-4.5, 5.0, 1.2)), bevel=0.08)
    b.box((1.2, 0.1, 0.8), gold, m @ jm.transform((-4.5, 4.48, 2.0)))


def build(name: str):
    b = jm.Builder(name)
    add(b)
    return b.finish()


if __name__ == "__main__":
    jm.run_single(build, NAME, BUDGET)
