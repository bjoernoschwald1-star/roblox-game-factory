"""Konzeptbild station.png: Gang einer verlassenen Forschungsstation im Eis.

Metallwaende mit Paneelen, Rohre und Kabel an der Decke, rotes Notlicht und eine flackernde (halb erloschene)
Deckenleuchte, Reif an den Kanten, eine schwebende Sicherheitsdrohne mit Suchscheinwerfer und ein leuchtendes
Artefakt auf einem Rollwagen im Vordergrund. Leichter Dunst im Gang.
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import konzept_common as k  # noqa: E402

LENGTH = 26.0
WIDTH = 6.0
HEIGHT = 4.2


def corridor(steel, dark, frost, floor):
    # Boden mit Gitterplatten, Waende aus Paneelen mit Fugen, Deckenrahmen
    k.box((WIDTH, LENGTH, 0.2), (0, LENGTH / 2, -0.1), floor, bevel=0.02, name="boden")
    for i in range(int(LENGTH / 2)):
        y = 1 + i * 2
        k.box((WIDTH - 1.2, 1.8, 0.06), (0, y, 0.03), dark, bevel=0.02, name="gitter")
        for side in (-1, 1):
            k.box((0.18, 1.9, HEIGHT - 0.3), (side * (WIDTH / 2 - 0.09), y, HEIGHT / 2), steel, bevel=0.03,
                  name="paneel")
            k.box((0.1, 1.2, 0.5), (side * (WIDTH / 2 - 0.2), y, 1.0), dark, bevel=0.03, name="sockel")
            # Reif an der Unterkante
            k.box((0.3, 1.9, 0.08), (side * (WIDTH / 2 - 0.25), y, 0.05), frost, bevel=0.03, name="reif")
        k.box((WIDTH, 0.25, 0.3), (0, y + 1, HEIGHT - 0.15), dark, bevel=0.03, name="rahmen")
    k.box((WIDTH + 0.4, LENGTH, 0.2), (0, LENGTH / 2, HEIGHT + 0.1), dark, bevel=0, name="decke")
    # Schott mit halb offener Tuer am Ende
    k.box((WIDTH, 0.4, HEIGHT), (0, LENGTH, HEIGHT / 2), steel, bevel=0.05, name="schott")
    k.box((1.6, 0.5, 2.8), (0.6, LENGTH - 0.05, 1.4), dark, bevel=0.06, name="tuer")


def ceiling_pipes(pipe, cable):
    for x, r in ((-2.2, 0.16), (-1.7, 0.1), (2.0, 0.2)):
        k.pipe_run([(x, 0, HEIGHT - 0.4), (x, LENGTH / 2, HEIGHT - 0.45), (x, LENGTH, HEIGHT - 0.4)], r, pipe,
                   name="rohr")
    for i, x in enumerate((-1.0, -0.8, 1.2)):
        sag = 0.35 + 0.1 * i
        pts = []
        for j in range(9):
            y = j * LENGTH / 8
            pts.append((x, y, HEIGHT - 0.25 - sag * math.sin(math.pi * (j % 2 + 0.5) / 1.5) * 0.6))
        k.pipe_run(pts, 0.035, cable, name="kabel")


def lights(red_glass, lamp_glass, off_glass):
    # Rotes Notlicht an der Wand (gross, weich) und eine halb erloschene Deckenleuchte
    for y in (6.0, 15.0, 23.0):
        k.box((0.12, 0.5, 0.25), (WIDTH / 2 - 0.25, y, 3.2), red_glass, bevel=0.03, name="notlicht")
        k.light("POINT", (WIDTH / 2 - 0.6, y, 3.2), 45, color=(1.0, 0.08, 0.05), size=0.3, name="rot")
    k.box((1.4, 0.4, 0.08), (0, 9.0, HEIGHT - 0.25), lamp_glass, bevel=0.02, name="leuchte_an")
    k.light("SPOT", (0, 9.0, HEIGHT - 0.35), 450, color=(0.75, 0.9, 1.0), rot=(0, 0, 0), size=0.3, spot=80,
            name="decke_an")
    k.box((1.4, 0.4, 0.08), (0, 18.0, HEIGHT - 0.25), off_glass, bevel=0.02, name="leuchte_aus")
    k.light("SPOT", (0, 18.0, HEIGHT - 0.35), 60, color=(0.75, 0.9, 1.0), size=0.3, spot=70, name="flacker")


def drone(body, dark, lens):
    center = (0.4, 8.0, 2.6)
    k.sphere(0.5, center, body, scale=(1.25, 1.0, 0.75), name="drohne")
    k.torus(0.7, 0.06, center, dark, name="drohne_ring")
    for dx in (-0.8, 0.8):
        k.cyl(0.22, 0.08, (center[0] + dx, center[1], center[2] + 0.15), dark, name="rotor")
    k.sphere(0.14, (center[0], center[1] - 0.45, center[2] - 0.05), lens, name="drohne_auge")
    k.light("SPOT", (center[0], center[1] - 0.6, center[2] - 0.1), 900, color=(1.0, 0.95, 0.8),
            rot=(70, 0, 0), size=0.05, spot=28, name="suchlicht")


def cart_with_artifact(steel, dark, artifact):
    base = (-1.2, 3.2, 0)
    k.box((1.4, 0.9, 0.08), (base[0], base[1], 0.75), steel, bevel=0.03, name="wagen")
    k.box((1.3, 0.8, 0.06), (base[0], base[1], 0.25), steel, bevel=0.03, name="wagen_unten")
    for dx in (-0.6, 0.6):
        for dy in (-0.35, 0.35):
            k.cyl(0.03, 0.75, (base[0] + dx, base[1] + dy, 0.45), dark, name="stange")
            k.cyl(0.08, 0.06, (base[0] + dx, base[1] + dy, 0.08), dark, rot=(90, 0, 0), name="rad")
    k.box((0.5, 0.5, 0.06), (base[0], base[1], 0.82), dark, bevel=0.02, name="sockelplatte")
    crystal = k.sphere(0.22, (base[0], base[1], 1.15), artifact, scale=(0.7, 0.7, 1.4), name="artefakt")
    crystal.rotation_euler = (0.2, 0.3, 0.5)
    k.torus(0.32, 0.025, (base[0], base[1], 1.15), dark, rot=(70, 0, 20), name="halter")
    k.light("POINT", (base[0], base[1], 1.2), 45, color=(0.2, 1.0, 0.8), size=0.15, name="artefakt_licht")
    # kaltes Streulicht vom Eis durch das Schott (blaue Grundstimmung)
    k.light("AREA", (0, LENGTH - 1.0, 2.0), 600, color=(0.45, 0.7, 1.0), rot=(90, 0, 0), size=3.0, name="eis")


def main():
    k.reset(seed=4)
    k.world((0.02, 0.03, 0.05), strength=0.15, fog_density=0.035, fog_color=(0.8, 0.9, 1.0), anisotropy=0.5)
    steel = k.pbr("stahl", (0.42, 0.46, 0.5), metallic=0.85, roughness=0.38, dirt=0.45)
    dark = k.pbr("dunkel", (0.08, 0.09, 0.1), metallic=0.7, roughness=0.5, dirt=0.3)
    floor = k.pbr("boden", (0.16, 0.17, 0.18), metallic=0.6, roughness=0.6, dirt=0.6)
    frost = k.pbr("reif", (0.85, 0.92, 1.0), metallic=0.0, roughness=0.3, dirt=0.05, scratch=0.0)
    pipe = k.pbr("rohr", (0.55, 0.3, 0.15), metallic=0.8, roughness=0.45, dirt=0.6)
    cable = k.pbr("kabel", (0.03, 0.03, 0.035), metallic=0.0, roughness=0.6, dirt=0.1, scratch=0.0)
    corridor(steel, dark, frost, floor)
    ceiling_pipes(pipe, cable)
    lights(k.emissive("notglas", (1.0, 0.1, 0.05), 30), k.emissive("lampe", (0.8, 0.92, 1.0), 25),
           k.emissive("lampe_aus", (0.4, 0.45, 0.5), 1.5))
    drone(k.pbr("drohne", (0.85, 0.75, 0.2), metallic=0.4, roughness=0.35), dark,
          k.emissive("linse", (1.0, 0.25, 0.1), 40))
    cart_with_artifact(steel, dark, k.emissive("kristall", (0.15, 1.0, 0.75), 5))
    k.camera((1.6, -1.8, 1.6), (-0.4, 12.0, 1.8), lens=26, dof_distance=5.4, fstop=5.6)
    k.render("station.png")


if __name__ == "__main__":
    main()
