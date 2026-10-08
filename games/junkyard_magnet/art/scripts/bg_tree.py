"""Hintergrund Baum und Busch: Low-Poly-Kronen aus Ikosphaeren, Stamm aus einem Sechskant (seeded).

bg_tree ca. 10 x 10 x 15 Studs, bg_bush ca. 8 x 5 x 4 Studs; Budget je 600.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import jm_common as jm  # noqa: E402


def crown(b: jm.Builder, rng, radius, mat, loc):
    for v in b.icosphere(radius, 1, mat, jm.transform(loc)):
        v.co = v.co * (1.0 + rng.uniform(-0.12, 0.12))


def build_tree(name: str):
    b = jm.Builder(name)
    rng = jm.seeded(51)
    bark = jm.solid_material("rust_dark", 0.0, 0.9)
    leaves = jm.solid_material("olive_green", 0.0, 0.85)
    b.cylinder(0.9, 8.0, 6, bark, jm.transform((0, 0, 4.0)), radius_top=0.6)
    crown(b, rng, 4.2, leaves, (0, 0, 11.0))
    crown(b, rng, 3.0, leaves, (2.6, 1.0, 9.0))
    crown(b, rng, 2.8, leaves, (-2.4, -1.2, 9.5))
    return b.finish()


def build_bush(name: str):
    b = jm.Builder(name)
    rng = jm.seeded(52)
    leaves = jm.solid_material("olive_green", 0.0, 0.85)
    for loc, r in (((0, 0, 1.2), 2.4), ((2.2, 0.6, 0.9), 1.8), ((-2.0, -0.4, 0.8), 1.7)):
        crown(b, rng, r, leaves, loc)
    return b.finish()


ENTRIES = [("bg_tree", build_tree, 600), ("bg_bush", build_bush, 600)]
