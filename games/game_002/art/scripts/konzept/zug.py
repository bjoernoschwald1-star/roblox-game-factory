"""Konzeptbild zug.png: Nachtszene auf einem fahrenden Gueterzug.

Offene Wagen mit Kisten unter Planen, Funken an den Raedern, ein Schaffner-Roboter mit Laterne auf dem Wagen,
voraus ein Tunnelportal im Berg, Gleis und Schotter, Mondlicht und Bewegungsunschaerfe im Hintergrund durch
Tiefenschaerfe. Keine Marken, keine Schrift.
"""

import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import konzept_common as k  # noqa: E402


def track(ballast, rail, wood):
    k.box((8, 400, 1), (0, 150, -0.6), ballast, bevel=0, name="schotter")
    k.box((400, 400, 1), (0, 150, -1.6), k.pbr("gras", (0.03, 0.05, 0.03), roughness=0.95, dirt=0.6, scratch=0.0, scale=0.3),
          bevel=0, name="boeschung")
    for x in (-0.75, 0.75):
        k.box((0.12, 400, 0.18), (x, 150, 0.0), rail, bevel=0.01, name="schiene")
    for i in range(200):
        k.box((2.6, 0.3, 0.14), (0, -40 + i * 1.6, -0.15), wood, bevel=0.02, name="schwelle")


def wagon(y, body, dark, crate, tarp, spark_mat, rng):
    k.box((3.0, 11.0, 0.35), (0, y, 1.1), dark, bevel=0.05, name="plattform")
    for side in (-1, 1):
        k.box((0.12, 11.0, 0.9), (side * 1.45, y, 1.7), body, bevel=0.04, name="bordwand")
        for j in range(4):
            k.box((0.18, 0.18, 1.0), (side * 1.5, y - 4.5 + j * 3, 1.7), dark, bevel=0.03, name="runge")
    for dy in (-3.5, 3.5):
        for x in (-0.75, 0.75):
            k.cyl(0.42, 0.18, (x, y + dy, 0.45), dark, rot=(0, 90, 0), name="rad")
        # Funken an den Raedern
        # Funken auf der Kameraseite (links), damit sie nicht hinter der Bordwand verschwinden
        k.particles(40, (-1.0, y + dy - 0.4, 0.2), (0.35, 0.9, 0.25), 0.045, spark_mat, seed=int(y * 10 + dy))
        k.light("POINT", (-1.1, y + dy, 0.25), 150, color=(1.0, 0.55, 0.15), size=0.05, name="funkenlicht")
    for j in range(3):
        cy = y - 3.5 + j * 3.4 + rng.uniform(-0.3, 0.3)
        h = rng.uniform(1.0, 1.5)
        mat = tarp if j == 1 else crate
        k.box((2.2, 2.6, h), (rng.uniform(-0.2, 0.2), cy, 1.3 + h / 2), mat, rot=(0, 0, rng.uniform(-4, 4)),
              bevel=0.06, name="kiste")


def robot(x, y, z, metal, dark, eye, lamp_glass):
    k.box((0.9, 0.6, 1.1), (x, y, z + 1.35), metal, bevel=0.12, name="robo_rumpf")
    k.box((0.7, 0.55, 0.55), (x, y, z + 2.25), metal, bevel=0.1, name="robo_kopf")
    k.box((0.9, 0.62, 0.12), (x, y, z + 2.55), dark, bevel=0.03, name="muetze_schirm")
    k.cyl(0.36, 0.25, (x, y, z + 2.7), dark, name="muetze")
    k.box((0.5, 0.08, 0.12), (x, y - 0.29, z + 2.3), eye, bevel=0.02, name="augen")
    for side in (-1, 1):
        k.cyl(0.13, 0.9, (x + side * 0.6, y, z + 1.4), dark, rot=(0, side * 12, 0), name="robo_arm")
        k.cyl(0.16, 0.8, (x + side * 0.25, y, z + 0.4), dark, name="robo_bein")
    # Laterne in der rechten Hand
    k.box((0.25, 0.25, 0.35), (x + 0.75, y - 0.2, z + 0.85), lamp_glass, bevel=0.04, name="laterne")
    k.light("POINT", (x + 0.75, y - 0.3, z + 0.85), 120, color=(1.0, 0.7, 0.35), size=0.1, name="laternenlicht")


def tunnel(rock, dark):
    k.box((90, 40, 40), (0, 100, 18), rock, bevel=0.8, name="berg")
    k.box((7, 2, 8), (0, 79.5, 3.5), dark, bevel=0.2, name="tunnelloch")
    k.box((10, 1.5, 1.4), (0, 79, 8.3), rock, bevel=0.2, name="portal")
    for side in (-1, 1):
        k.box((1.5, 1.5, 8.5), (side * 4.3, 79, 4.0), rock, bevel=0.2, name="portalpfeiler")


def main():
    k.reset(seed=12)
    k.world((0.03, 0.05, 0.12), strength=1.4, fog_density=0.006, fog_color=(0.5, 0.6, 0.9), anisotropy=0.4)
    rng = random.Random(5)
    ballast = k.pbr("schotter", (0.12, 0.11, 0.1), roughness=0.95, dirt=0.5, scratch=0.0, scale=12)
    rail = k.pbr("schiene", (0.35, 0.33, 0.3), metallic=1.0, roughness=0.3, dirt=0.2)
    wood = k.pbr("holz", (0.18, 0.11, 0.06), roughness=0.85, dirt=0.4, scratch=0.0)
    body = k.pbr("wagen", (0.35, 0.1, 0.06), metallic=0.6, roughness=0.6, dirt=0.6)
    dark = k.pbr("dunkel", (0.04, 0.04, 0.045), metallic=0.8, roughness=0.5, dirt=0.4)
    crate = k.pbr("kiste", (0.42, 0.3, 0.16), roughness=0.75, dirt=0.5, scratch=0.1, scale=6)
    tarp = k.pbr("plane", (0.15, 0.25, 0.18), roughness=0.9, dirt=0.4, scratch=0.0)
    metal = k.pbr("robo", (0.55, 0.5, 0.42), metallic=0.9, roughness=0.35, dirt=0.4)
    rock = k.pbr("fels", (0.08, 0.08, 0.09), roughness=0.9, dirt=0.4, scratch=0.0, scale=0.5)
    spark = k.emissive("funken", (1.0, 0.6, 0.15), 60)
    track(ballast, rail, wood)
    for y in (0, 12, 24, 36, 48, 60):
        wagon(y, body, dark, crate, tarp, spark, rng)
    robot(0.2, 6.2, 1.3, metal, dark, k.emissive("augen", (0.3, 0.9, 1.0), 25), k.emissive("laterne", (1.0, 0.7, 0.35), 20))
    tunnel(rock, dark)
    # Mondlicht von schraeg hinten, warmes Licht aus dem Tunnel voraus (Lok-Scheinwerfer)
    k.light("SUN", (0, 0, 50), 2.5, color=(0.55, 0.65, 1.0), rot=(55, 0, 150), size=0.6, name="mond")
    # Mondschein auf den Wagen von der Seite (Kanten und Kisten lesbar)
    k.light("AREA", (-30, 20, 25), 9000, color=(0.5, 0.6, 1.0), rot=(0, -50, 0), size=30, name="mondfuell")
    # Licht im Tunnel voraus (Lok-Scheinwerfer leuchten hinein)
    # vor dem Portal, damit Pfeiler und Felswand angestrahlt werden
    k.light("POINT", (0, 76, 3.0), 6000, color=(1.0, 0.8, 0.5), size=1.0, name="tunnelglut")
    k.light("AREA", (0, 60, 20), 20000, color=(0.5, 0.6, 1.0), rot=(-60, 0, 0), size=40, name="bergmond")
    k.camera((-4.2, -3.5, 4.6), (0.6, 22, 1.6), lens=24, dof_distance=10.5, fstop=5.6)
    k.render("zug.png")


if __name__ == "__main__":
    main()
