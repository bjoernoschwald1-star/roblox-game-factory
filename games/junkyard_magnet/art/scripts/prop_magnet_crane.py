"""Kulisse Magnetkran: Gitterturm, Ausleger, Fuehrerhaus, Seil und grosser roter Kranmagnet (Wahrzeichen).

Groesse ca. 22 x 8 x 30 Studs, Budget 8.000 Dreiecke. Ausleger zeigt nach +X.
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import jm_common as jm  # noqa: E402

NAME = "prop_magnet_crane"
BUDGET = 8000
TOWER_H = 24.0


def add(b: jm.Builder, matrix=None):
    m = matrix if matrix is not None else jm.transform()
    steel = jm.solid_material("gold", 0.6, 0.45)
    dark = jm.solid_material("chrome_dark", 0.6, 0.5)
    cab = jm.solid_material("steel_blue", 0.3, 0.5)
    red = jm.solid_material("magnet_red", 0.0, 0.45)
    silver = jm.solid_material("chrome_light", 1.0, 0.2)
    # Fuss
    b.box((6.0, 6.0, 1.0), dark, m @ jm.transform((0, 0, 0.5)), bevel=0.1)
    # Gitterturm: vier Eckstiele und Querstreben
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box((0.45, 0.45, TOWER_H), steel, m @ jm.transform((sx * 1.6, sy * 1.6, TOWER_H / 2 + 1)))
    z = 3.0
    while z < TOWER_H:
        for rot in (0, 90):
            for side in (-1, 1):
                off = jm.transform((0, side * 1.6, z), (0, 0, rot)) if rot == 0 else jm.transform((side * 1.6, 0, z), (0, 0, 0))
                size = (3.2, 0.25, 0.25) if rot == 0 else (0.25, 3.2, 0.25)
                b.box(size, steel, m @ off)
                diag = jm.transform((0, side * 1.6, z + 1.2), (0, 37, 0)) if rot == 0 else jm.transform((side * 1.6, 0, z + 1.2), (37, 0, 0))
                b.box((4.0, 0.2, 0.2) if rot == 0 else (0.2, 4.0, 0.2), steel, m @ diag)
        z += 3.0
    # Fuehrerhaus und Ausleger
    top = TOWER_H + 1
    b.box((4.0, 3.6, 3.0), cab, m @ jm.transform((-0.5, 0, top + 1.5)), bevel=0.15)
    b.box((3.0, 0.1, 1.4), silver, m @ jm.transform((-0.5, -1.82, top + 2.0)))
    boom_len = 18.0
    b.box((boom_len, 1.2, 1.2), steel, m @ jm.transform((boom_len / 2 + 1.0, 0, top + 3.6)))
    b.box((5.0, 1.0, 1.0), dark, m @ jm.transform((-4.0, 0, top + 3.6)))
    b.box((2.4, 2.4, 2.0), dark, m @ jm.transform((-6.0, 0, top + 2.8)))  # Gegengewicht
    # Seil und Magnet am Ausleger-Ende
    tip_x = boom_len - 1.0
    b.cylinder(0.12, 9.0, 6, dark, m @ jm.transform((tip_x, 0, top + 3.6 - 4.5)))
    magnet_z = top + 3.6 - 9.0
    b.cylinder(2.6, 1.2, 16, red, m @ jm.transform((tip_x, 0, magnet_z - 0.6)))
    b.cylinder(2.7, 0.35, 16, silver, m @ jm.transform((tip_x, 0, magnet_z - 1.35)))
    b.cylinder(0.6, 0.6, 8, dark, m @ jm.transform((tip_x, 0, magnet_z + 0.3)))
    for k in range(4):
        a = math.radians(45 + 90 * k)
        b.box((0.2, 0.2, 1.4), dark, m @ jm.transform((tip_x + 0.9 * math.cos(a), 0.9 * math.sin(a), magnet_z + 0.6)))


def build(name: str):
    b = jm.Builder(name)
    add(b)
    return b.finish()


if __name__ == "__main__":
    jm.run_single(build, NAME, BUDGET)
