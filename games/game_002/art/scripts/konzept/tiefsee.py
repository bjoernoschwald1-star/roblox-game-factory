"""Konzeptbild tiefsee.png: Taucher in schweren Anzuegen auf dem Meeresboden vor einem versunkenen Frachtschiff.

Lichtkegel der Helmlampen im dichten, blaugruenen Wasser (Volumen), Schwebeteilchen, eine Tauchglocke im
Hintergrund, Felsen und Sandwellen am Boden. Taucher als Silhouetten (Helm, Rumpf, Arme, Beine, Atemschlaeuche).
"""

import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import konzept_common as k  # noqa: E402


def seabed(sand, rock):
    k.box((200, 200, 1), (0, 40, -0.5), sand, bevel=0, name="meeresboden")
    rng = random.Random(9)
    for _ in range(26):
        x, y = rng.uniform(-30, 30), rng.uniform(6, 60)
        r = rng.uniform(0.6, 2.6)
        stone = k.sphere(r, (x, y, -r * 0.4), rock, scale=(1.3, 1.0, 0.6), name="fels")
        stone.rotation_euler = (0, 0, rng.uniform(0, math.pi))


def wreck(hull, rust, dark):
    # Gekippter Frachter: Rumpf, Aufbau, Ladekraene, Container-Reste
    tilt = (0, -8, 25)
    k.box((10, 36, 7), (6, 34, 2.6), hull, rot=tilt, bevel=0.3, name="rumpf")
    k.box((7.5, 8, 6), (6.8, 46, 8.5), rust, rot=tilt, bevel=0.2, name="aufbau")
    for i in range(4):
        k.box((0.6, 0.6, 9), (3 + i * 0.6, 26 + i * 5.5, 9), dark, rot=(0, -20 + i * 6, 25), bevel=0.05, name="kran")
    for i in range(3):
        k.box((2.4, 5.5, 2.4), (-1.5 - i * 1.4, 22 + i * 4, 1.0 + i * 0.3), rust, rot=(4, 12, 25 + i * 9),
              bevel=0.08, name="container")
    for i in range(6):
        k.cyl(0.35, 0.3, (1.4, 25 + i * 3.2, 4.6), dark, rot=(0, 90, 25), name="bullauge")


def diver(x, y, yaw, suit, brass, glass, hose, lamp_glass):
    rad = math.radians(yaw)
    fx, fy = -math.sin(rad), math.cos(rad)

    def at(dx, dy, z):
        return (x + dx * math.cos(rad) - dy * math.sin(rad), y + dx * math.sin(rad) + dy * math.cos(rad), z)

    k.sphere(0.55, at(0, 0, 3.15), brass, name="helm")
    k.cyl(0.24, 0.05, at(0, 0.5, 3.15), glass, rot=(90, 0, yaw), name="sichtfenster")
    k.cyl(0.6, 0.25, at(0, 0, 2.62), brass, name="kragen")
    k.sphere(0.75, at(0, 0, 1.95), suit, scale=(1.0, 0.75, 1.15), name="rumpf")
    k.box((0.75, 0.35, 0.9), at(0, -0.62, 2.0), brass, bevel=0.08, name="tank")
    for side in (-1, 1):
        k.cyl(0.21, 1.1, at(side * 0.75, 0.15, 1.95), suit, rot=(15, side * 20, yaw), name="arm")
        k.cyl(0.24, 1.2, at(side * 0.3, 0, 0.75), suit, name="bein")
        k.box((0.4, 0.62, 0.25), at(side * 0.3, 0.1, 0.12), brass, bevel=0.06, name="stiefel")
    k.pipe_run([at(0.25, -0.7, 2.4), at(0.6, -1.4, 2.9), at(1.5, -2.6, 2.6)], 0.06, hose, name="schlauch")
    # Helmlampe mit Lichtkegel nach vorn
    k.cyl(0.11, 0.18, at(0.3, 0.45, 3.45), lamp_glass, rot=(90, 0, yaw), name="lampe")
    lamp = k.light("SPOT", at(0.3, 0.6, 3.45), 1800, color=(1.0, 0.92, 0.75), size=0.05, spot=30, name="helmlicht")
    lamp.rotation_euler = (math.radians(80), 0, rad)
    _ = (fx, fy)


def bell(brass, glass):
    k.sphere(2.2, (-9, 30, 7.5), brass, scale=(1, 1, 1.15), name="glocke")
    for a in range(4):
        ang = math.radians(a * 90 + 20)
        k.cyl(0.45, 0.1, (-9 + 2.1 * math.cos(ang), 30 + 2.1 * math.sin(ang), 7.8), glass,
              rot=(90, 0, math.degrees(ang) + 90), name="fenster")
    k.pipe_run([(-9, 30, 10), (-8.5, 30, 20), (-8, 30, 40)], 0.08, brass, name="seil")
    k.light("POINT", (-9, 30, 7.4), 260, color=(1.0, 0.75, 0.4), size=1.0, name="glockenlicht")


def main():
    k.reset(seed=6)
    k.world((0.02, 0.12, 0.16), strength=1.5, fog_density=0.03, fog_color=(0.3, 0.8, 0.85), anisotropy=0.6)
    sand = k.pbr("sand", (0.32, 0.3, 0.24), roughness=0.9, dirt=0.4, scratch=0.0, scale=1.5)
    rock = k.pbr("fels", (0.12, 0.14, 0.13), roughness=0.85, dirt=0.5, scratch=0.0)
    hull = k.pbr("rumpf", (0.25, 0.08, 0.06), metallic=0.6, roughness=0.75, dirt=0.8, scale=1.2)
    rust = k.pbr("rost", (0.45, 0.2, 0.08), metallic=0.4, roughness=0.85, dirt=0.7, scale=1.5)
    dark = k.pbr("dunkel", (0.05, 0.06, 0.06), metallic=0.7, roughness=0.6, dirt=0.4)
    suit = k.pbr("anzug", (0.35, 0.33, 0.28), roughness=0.75, dirt=0.4, scratch=0.0)
    brass = k.pbr("messing", (0.75, 0.55, 0.25), metallic=1.0, roughness=0.35, dirt=0.45)
    glass = k.emissive("glas", (0.4, 0.85, 0.9), 2.0)
    hose = k.pbr("schlauch", (0.05, 0.05, 0.05), roughness=0.6, dirt=0.1, scratch=0.0)
    lamp_glass = k.emissive("lampenglas", (1.0, 0.93, 0.75), 30)
    seabed(sand, rock)
    wreck(hull, rust, dark)
    bell(brass, glass)
    diver(-1.0, 4.5, -15, suit, brass, glass, hose, lamp_glass)
    diver(2.6, 7.5, 20, suit, brass, glass, hose, lamp_glass)
    diver(-3.8, 10.5, -5, suit, brass, glass, hose, lamp_glass)
    # Licht von oben (Wasseroberflaeche) und Schwebeteilchen
    k.light("SUN", (0, 0, 50), 4.0, color=(0.4, 0.8, 0.9), rot=(15, 0, 10), size=0.3, name="oben")
    # Gegenlicht hinter dem Wrack: Taucher und Rumpf heben sich als Silhouette ab
    k.light("AREA", (0, 70, 18), 60000, color=(0.35, 0.85, 0.9), rot=(-75, 0, 0), size=40, name="gegenlicht")
    k.particles(260, (0, 16, 4), (14, 12, 5), 0.012, k.emissive("plankton", (0.8, 1.0, 1.0), 1.5), seed=7)
    k.camera((1.5, -6.5, 1.6), (0.5, 14, 3.5), lens=26, dof_distance=11, fstop=5.6)
    k.render("tiefsee.png")


if __name__ == "__main__":
    main()
