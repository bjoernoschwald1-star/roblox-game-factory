"""Kulisse Schmelzofen: gemauerter Sockel, runder Ofenkoerper mit gluehender Oeffnung, Schornstein, Giessrinne
mit gluehendem Strahl und Tiegel davor (Ort der Schmelze/Prestige im Junkyard).

Groesse ca. 14 x 12 x 19 Studs, Budget 8.000 Dreiecke. Vorderseite (Oeffnung, Rinne) nach -Y.
Glut als Emission (rust_orange und gold_deep) -> in Roblox Neon.
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import jm_common as jm  # noqa: E402

NAME = "prop_furnace"
BUDGET = 8000


def add(b: jm.Builder, matrix=None):
    m = matrix if matrix is not None else jm.transform()
    brick = jm.solid_material("rust_dark", 0.0, 0.9)
    body = jm.solid_material("metal_gray", 0.5, 0.55)
    dark = jm.solid_material("tire_black", 0.0, 0.9)
    frame = jm.solid_material("chrome_dark", 0.6, 0.5)
    # Glut: eigene Palettenfarben nur fuer Leuchtteile (der Materialname ist die Palettenfarbe, jm_roblox).
    glow = jm.solid_material("rust_orange", 0.0, 0.4, 3.0)
    hot = jm.solid_material("gold_deep", 0.0, 0.4, 3.0)
    trim = jm.solid_material("gold", 0.6, 0.4)
    # Sockel aus Ziegeln (zwei Lagen, leicht versetzt)
    b.box((12.0, 10.0, 1.6), brick, m @ jm.transform((0, 0, 0.8)), bevel=0.1)
    b.box((10.6, 8.8, 1.4), brick, m @ jm.transform((0, 0.3, 2.3)), bevel=0.1)
    # Ofenkoerper: zwei Zylinder, oben verjuengt, mit Baendern
    b.cylinder(4.2, 7.0, 16, body, m @ jm.transform((0, 0.6, 6.5)))
    b.cylinder(4.2, 3.2, 16, body, m @ jm.transform((0, 0.6, 11.6)), radius_top=2.4)
    for z in (3.4, 9.6):
        b.cylinder(4.45, 0.45, 16, trim, m @ jm.transform((0, 0.6, z)))
    # Gluehende Oeffnung vorn mit dunklem Rahmen
    b.box((3.6, 0.6, 3.0), dark, m @ jm.transform((0, -3.3, 6.2)), bevel=0.1)
    b.box((2.8, 0.4, 2.2), glow, m @ jm.transform((0, -3.6, 6.2)))
    # Schornstein mit Kappe
    b.cylinder(1.1, 6.0, 10, frame, m @ jm.transform((0, 0.6, 16.0)))
    b.cylinder(1.5, 0.6, 10, dark, m @ jm.transform((0, 0.6, 19.0)))
    # Giessrinne (schraeg nach vorn unten) mit gluehendem Strahl, Tiegel davor
    b.box((1.4, 4.0, 0.5), frame, m @ jm.transform((2.4, -5.0, 4.4), (-22, 0, 0)), bevel=0.05)
    b.box((0.8, 3.6, 0.2), hot, m @ jm.transform((2.4, -5.0, 4.75), (-22, 0, 0)))
    b.cylinder(1.6, 1.8, 12, dark, m @ jm.transform((2.4, -7.6, 0.9)), radius_top=1.9)
    b.cylinder(1.5, 0.2, 12, hot, m @ jm.transform((2.4, -7.6, 1.85)))
    # Stuetzen seitlich
    for side in (-1, 1):
        for front in (-1, 1):
            b.box((0.5, 0.5, 8.0), frame, m @ jm.transform((side * 4.6, 0.6 + front * 2.6, 6.8)), bevel=0.05)
    # Ein paar Barren als Ausbeute neben dem Tiegel
    for k in range(3):
        a = math.radians(20 * k)
        b.box((1.1, 0.5, 0.4), trim, m @ jm.transform((-2.0 + 0.4 * k, -6.8 - 0.2 * k, 0.2 + 0.4 * k), (0, 0, 15 + a)))


def build(name: str):
    b = jm.Builder(name)
    add(b)
    return b.finish()


if __name__ == "__main__":
    jm.run_single(build, NAME, BUDGET)
