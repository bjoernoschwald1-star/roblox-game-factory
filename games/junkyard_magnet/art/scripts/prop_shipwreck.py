"""Kulisse Schiffswrack: gestrandeter, leicht gekippter Rumpf mit Rostflecken, Deck, Kajuete, abgeknicktem Mast,
Bullaugen und einer Ankerkette am Bug (Hafen-Zone).

Groesse ca. 36 x 11 x 15 Studs, Budget 8.000 Dreiecke. Bug nach +X, Vorderseite nach -Y.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import jm_common as jm  # noqa: E402

NAME = "prop_shipwreck"
BUDGET = 8000


def add(b: jm.Builder, matrix=None):
    m = matrix if matrix is not None else jm.transform()
    hull = jm.solid_material("steel_blue", 0.3, 0.6)
    keel = jm.solid_material("magnet_red", 0.1, 0.7)
    rust = jm.solid_material("rust_orange", 0.2, 0.85)
    deck = jm.solid_material("bark_brown", 0.0, 0.9)
    white = jm.solid_material("chrome_light", 0.2, 0.4)
    dark = jm.solid_material("tire_black", 0.0, 0.9)
    metal = jm.solid_material("chrome_dark", 0.6, 0.5)
    # Ganzes Schiff leicht gekippt und im Sand versunken
    s = m @ jm.transform((0, 0, -0.8), (6, 0, 0))
    # Rumpf: roter Unterteil, blauer Oberteil, spitzer Bug aus zwei schraegen Platten
    b.box((26.0, 9.0, 3.0), keel, s @ jm.transform((-2.0, 0, 2.0)), bevel=0.2)
    b.box((26.0, 9.4, 4.0), hull, s @ jm.transform((-2.0, 0, 5.4)), bevel=0.2)
    for side in (-1, 1):
        b.box((9.0, 0.8, 7.2), hull, s @ jm.transform((14.0, side * 2.6, 3.8), (0, 0, side * -28)), bevel=0.15)
    # Rostflecken
    for x, z in ((-8.0, 4.6), (2.0, 6.0), (8.5, 3.6)):
        b.box((3.0, 0.3, 1.6), rust, s @ jm.transform((x, -4.75, z)))
    # Deck und Kajuete
    b.box((24.0, 8.4, 0.5), deck, s @ jm.transform((-2.0, 0, 7.6)))
    b.box((7.0, 6.0, 3.6), white, s @ jm.transform((-9.0, 0, 9.6)), bevel=0.15)
    b.box((7.6, 6.6, 0.5), metal, s @ jm.transform((-9.0, 0, 11.6)))
    for x in (-11.0, -9.0, -7.0):
        b.cylinder(0.45, 0.3, 10, dark, s @ jm.transform((x, -3.05, 10.0), (90, 0, 0)))
    # Bullaugen im Rumpf
    for x in (-10.0, -5.0, 0.0, 5.0):
        b.cylinder(0.55, 0.3, 10, white, s @ jm.transform((x, -4.75, 5.8), (90, 0, 0)))
    # Abgeknickter Mast
    b.cylinder(0.4, 6.0, 8, metal, s @ jm.transform((2.0, 0, 10.8)))
    b.cylinder(0.35, 5.0, 8, metal, s @ jm.transform((3.6, 0, 14.6), (0, 52, 0)))
    # Ankerkette vom Bug in den Sand
    for k in range(7):
        b.tube(0.4, 0.22, 0.18, 8, metal, s @ jm.transform((16.0 + 0.5 * k, -3.4, 6.0 - 0.85 * k), (90 * (k % 2), 0, 0)))


def build(name: str):
    b = jm.Builder(name)
    add(b)
    return b.finish()


if __name__ == "__main__":
    jm.run_single(build, NAME, BUDGET)
