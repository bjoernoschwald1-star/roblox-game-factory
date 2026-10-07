"""Werkzeug Hufeisenmagnet: rotes U-Profil mit silbernen Polschuhen und Griff oben.

Groesse ca. 1.6 x 0.5 x 2.0 Studs (Avatarhand), Budget 3.000 Dreiecke. Pole zeigen nach unten.
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import jm_common as jm  # noqa: E402

NAME = "tool_magnet"
BUDGET = 3000
PROFILE = [(-0.2, -0.22), (0.2, -0.22), (0.2, 0.22), (-0.2, 0.22)]


def add(b: jm.Builder, matrix=None):
    m = matrix if matrix is not None else jm.transform()
    red = jm.solid_material("magnet_red", 0.0, 0.45)
    silver = jm.solid_material("chrome_light", 1.0, 0.2)
    dark = jm.solid_material("chrome_dark", 0.6, 0.5)
    radius, leg, base = 0.6, 0.7, 0.45
    # Pfad: rechter Schenkel hoch, Bogen oben, linker Schenkel runter
    path = [(radius, 0, base + leg * t / 2) for t in (0, 1, 2)]
    path += [
        (radius * math.cos(math.pi * k / 12), 0, base + leg + radius * math.sin(math.pi * k / 12))
        for k in range(1, 12)
    ]
    path += [(-radius, 0, base + leg * t / 2) for t in (2, 1, 0)]
    b.sweep(path, PROFILE, red, m)
    for x in (-radius, radius):
        b.box((0.44, 0.48, base), silver, m @ jm.transform((x, 0, base / 2)), bevel=0.05)
    top = base + leg + radius
    b.cylinder(0.13, 0.7, 8, dark, m @ jm.transform((0, 0, top + 0.2), (0, 90, 0)))
    b.box((0.12, 0.2, 0.25), dark, m @ jm.transform((0, 0, top + 0.05)))


def build(name: str):
    b = jm.Builder(name)
    add(b)
    return b.finish()


if __name__ == "__main__":
    jm.run_single(build, NAME, BUDGET)
