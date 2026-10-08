"""Hintergrund Schrottberg: hoher Berg aus Schrott ausserhalb des Zauns (seeded), nah und fern.

bg_scrap_mountain (nah, ca. 70 x 46 x 26 Studs, Budget 8.000): verbeulter Grauhuegel, Rosthuegel, eingesteckte
Wracks, Container, Reifen und vergroesserte Schrottteile. bg_scrap_mountain_far (fern, Silhouette, Budget 600):
nur zwei grobe Huegel und drei Kanten.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bmesh  # noqa: E402
from mathutils import Vector  # noqa: E402

import item_barrel  # noqa: E402
import item_gear  # noqa: E402
import item_pipe  # noqa: E402
import item_plate  # noqa: E402
import jm_common as jm  # noqa: E402
import prop_car_wreck  # noqa: E402
import prop_container  # noqa: E402
import prop_tire_stack  # noqa: E402


def mound(b: jm.Builder, rng, subdivisions, mat, size, offset=(0.0, 0.0, 0.0), jitter=0.14):
    # Erst im Ursprung verformen, dann verschieben (sonst skaliert die Verformung den Versatz mit).
    verts = b.icosphere(1.0, subdivisions, mat)
    for v in verts:
        v.co = v.co * (1.0 + rng.uniform(-jitter, jitter))
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z = max(v.co.z * size[2], 0.0)
    bmesh.ops.translate(b.bm, vec=Vector(offset), verts=verts)
    b.reshape_last(size)


def build_near(name: str):
    b = jm.Builder(name)
    rng = jm.seeded(21)
    gray = jm.solid_material("metal_gray", 0.3, 0.7)
    rust = jm.solid_material("rust_dark", 0.1, 0.9)
    mound(b, rng, 3, gray, (35.0, 22.0, 26.0))
    mound(b, rng, 2, rust, (16.0, 13.0, 15.0), (20.0, 6.0, 0.0))
    mound(b, rng, 2, rust, (14.0, 11.0, 11.0), (-22.0, -5.0, 0.0))
    prop_car_wreck.add(b, jm.transform((-8.0, -14.0, 18.0), (18, -12, 25), (1.2, 1.2, 1.2)))
    prop_car_wreck.add(b, jm.transform((14.0, -9.0, 20.0), (-20, 10, -35)))
    prop_container.add(b, jm.transform((-20.0, 4.0, 18.0), (0, -28, 60)))
    prop_tire_stack.add(b, jm.transform((26.0, -12.0, 8.0), (10, 0, 20), (1.4, 1.4, 1.4)))
    pieces = [
        (item_plate.add, (2.0, -16.0, 19.0), (25, -20, 15), 6.0, "rusty"),
        (item_pipe.add, (-12.0, -12.0, 19.0), (0, -30, -40), 6.0, "gray"),
        (item_gear.add, (4.0, -6.0, 24.0), (-15, 20, 10), 6.0, "yellow"),
        (item_barrel.add, (24.0, 2.0, 16.0), (15, 25, 0), 4.0, "blue"),
        (item_gear.add, (-28.0, -2.0, 13.0), (60, 0, 30), 5.0, "rusty"),
        (item_plate.add, (10.0, 10.0, 22.0), (-30, 15, 50), 5.0, "green"),
    ]
    for add_fn, loc, rot, scale, variant in pieces:
        add_fn(b, variant, jm.transform(loc, rot, (scale, scale, scale)))
    return b.finish()


def build_far(name: str):
    b = jm.Builder(name)
    rng = jm.seeded(22)
    gray = jm.solid_material("metal_gray", 0.3, 0.7)
    rust = jm.solid_material("rust_dark", 0.1, 0.9)
    mound(b, rng, 2, gray, (40.0, 24.0, 30.0), jitter=0.2)
    mound(b, rng, 1, rust, (18.0, 14.0, 17.0), (24.0, 4.0, 0.0), jitter=0.2)
    slabs = (
        ((-6, -14, 22), (20, 10, 30), (14, 3, 6)),
        ((12, -10, 18), (-15, 25, -20), (10, 3, 8)),
        ((-24, -6, 10), (0, 30, 50), (12, 4, 4)),
    )
    for loc, rot, size in slabs:
        b.box(size, gray, jm.transform(loc, rot))
    return b.finish()


ENTRIES = [("bg_scrap_mountain", build_near, 8000), ("bg_scrap_mountain_far", build_far, 600)]
