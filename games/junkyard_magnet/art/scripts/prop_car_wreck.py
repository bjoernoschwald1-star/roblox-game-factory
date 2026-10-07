"""Kulisse Autowrack: generische Kompaktwagen-Form ohne Marken/Logos, eingedrueckt, ein Rad fehlt, Rost.

Groesse ca. 14 x 6.5 x 5 Studs, Budget 8.000 Dreiecke. Laengsachse X, Vorderseite -Y.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import jm_common as jm  # noqa: E402

NAME = "prop_car_wreck"
BUDGET = 8000


def add(b: jm.Builder, matrix=None):
    m = matrix if matrix is not None else jm.transform()
    body = jm.solid_material("olive_green", 0.3, 0.55)
    rust = jm.solid_material("rust_orange", 0.2, 0.85)
    dark = jm.solid_material("chrome_dark", 0.6, 0.5)
    glass = jm.solid_material("chrome_light", 0.1, 0.1)
    tire = jm.solid_material("tire_black", 0.0, 0.9)
    # Karosserie leicht schief (ein Rad fehlt hinten links)
    tilt = jm.transform((0, 0, 0), (0, 3, 2))
    b.box((13.0, 6.0, 2.4), body, m @ tilt @ jm.transform((0, 0, 2.1)), bevel=0.25)
    b.box((7.0, 5.4, 2.0), body, m @ tilt @ jm.transform((-0.5, 0, 4.1), (0, -4, 0)), bevel=0.25)
    # Fenster (ohne Text), eins zerbrochen = fehlt
    b.box((2.6, 0.1, 1.4), glass, m @ tilt @ jm.transform((-2.2, -2.72, 4.2)))
    b.box((2.4, 0.1, 1.4), glass, m @ tilt @ jm.transform((1.0, 2.72, 4.2)))
    b.box((0.1, 4.6, 1.4), glass, m @ tilt @ jm.transform((3.0, 0, 4.15), (0, -20, 0)))
    # Stossstangen und Scheinwerfer-Hoehlen
    for sx in (-1, 1):
        b.box((0.5, 6.2, 0.7), dark, m @ tilt @ jm.transform((sx * 6.6, 0, 1.3)))
    # Raeder: drei vorhanden, hinten links nur die Felge am Boden
    for x, y in ((4.2, -3.1), (4.2, 3.1), (-4.2, 3.1)):
        b.tube(1.25, 0.55, 0.9, 14, tire, m @ jm.transform((x, y, 1.25), (90, 0, 0)))
        b.cylinder(0.6, 0.7, 8, dark, m @ jm.transform((x, y, 1.25), (90, 0, 0)))
    b.cylinder(0.6, 0.5, 8, dark, m @ jm.transform((-4.6, -3.4, 0.3), (0, 0, 0)))
    # Rostflaechen und Beule
    for loc, size in (((-3.0, -3.02, 2.2), (2.5, 0.05, 1.2)), ((3.5, -3.02, 1.8), (1.5, 0.05, 0.8)),
                      ((-1.0, 0, 5.12), (3.0, 3.0, 0.05))):
        b.box(size, rust, m @ tilt @ jm.transform(loc))


def build(name: str):
    b = jm.Builder(name)
    add(b)
    return b.finish()


if __name__ == "__main__":
    jm.run_single(build, NAME, BUDGET)
