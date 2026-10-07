"""Kulisse Container: Schiffscontainer mit Sicken, Rahmen, Tuerverriegelung und Rostflecken.

Groesse ca. 20 x 8 x 8.5 Studs, Budget 8.000 Dreiecke. Lange Seite zeigt nach vorn (-Y), Tueren an +X.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import jm_common as jm  # noqa: E402

NAME = "prop_container"
BUDGET = 8000
L, W, H = 20.0, 8.0, 8.5


def add(b: jm.Builder, matrix=None):
    m = matrix if matrix is not None else jm.transform()
    body = jm.solid_material("steel_blue", 0.3, 0.6)
    frame = jm.solid_material("chrome_dark", 0.5, 0.55)
    rust = jm.solid_material("rust_dark", 0.1, 0.9)
    b.box((L - 0.4, W - 0.4, H - 0.6), body, m @ jm.transform((0, 0, H / 2)))
    # Sicken an den Laengsseiten
    x = -L / 2 + 1.2
    while x < L / 2 - 1.0:
        for y in (-W / 2 + 0.15, W / 2 - 0.15):
            b.box((0.5, 0.2, H - 1.4), body, m @ jm.transform((x, y, H / 2)))
        x += 1.1
    # Rahmen: Eckpfosten, Ober- und Untergurte
    for sx in (-1, 1):
        for sy in (-1, 1):
            post = jm.transform((sx * (L / 2 - 0.3), sy * (W / 2 - 0.3), H / 2))
            b.box((0.6, 0.6, H), frame, m @ post, bevel=0.06)
        for z in (0.3, H - 0.3):
            b.box((0.4, W, 0.6), frame, m @ jm.transform((sx * (L / 2 - 0.2), 0, z)))
    for sy in (-1, 1):
        for z in (0.3, H - 0.3):
            b.box((L, 0.4, 0.6), frame, m @ jm.transform((0, sy * (W / 2 - 0.2), z)))
    # Tuer an +X mit Verriegelungsstangen
    for y in (-2.6, -1.2, 1.2, 2.6):
        b.cylinder(0.12, H - 1.2, 6, frame, m @ jm.transform((L / 2 + 0.05, y, H / 2)))
    b.box((0.1, 0.1, H - 1.0), frame, m @ jm.transform((L / 2 - 0.15, 0, H / 2)))
    # Rostfahnen unter den Eckbeschlaegen und an der Unterkante (unregelmaessig, damit sie nicht wie Schilder wirken)
    streaks = (
        ((-L / 2 + 0.9, 2.4), (0.35, 2.2)),
        ((-6.0, 1.0), (1.6, 0.9)),
        ((3.5, 1.3), (0.4, 1.6)),
        ((L / 2 - 0.9, 6.8), (0.3, 1.4)),
    )
    for (x, z), (sx, sz) in streaks:
        b.box((sx, 0.05, sz), rust, m @ jm.transform((x, -W / 2 + 0.03, z)))


def build(name: str):
    b = jm.Builder(name)
    add(b)
    return b.finish()


if __name__ == "__main__":
    jm.run_single(build, NAME, BUDGET)
