"""Store-Bilder in voller Aufloesung: Vorschaubild 1920 x 1080 und Icon 512 x 512, Varianten c und d.

Eigene, generische Arbeiterfigur im Low-Poly-Stil (Schutzhelm, Warnweste, kein Roblox-Avatar, keine Marken), die den
Hufeisenmagneten (tool_magnet) haelt; Schrottteile in allen Seltenheiten fliegen mit Leuchtspuren heran, dahinter
Magnetkran und Schrottberge. Ohne Text. Licht und Himmel wie jm_render (Palette, Bloom fuer Neon).
Ausgabe: games/junkyard_magnet/art/store/{vorschau_c_1920x1080, icon_c_512, vorschau_d_1920x1080, icon_d_512}.png
Aufruf in Blender: runpy.run_path(".../store_render.py", run_name="__main__")
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import bg_scrap_mountain  # noqa: E402
import item_anchor  # noqa: E402
import item_barrel  # noqa: E402
import item_bolt  # noqa: E402
import item_gear  # noqa: E402
import item_pipe  # noqa: E402
import item_plate  # noqa: E402
import jm_common as jm  # noqa: E402
import jm_render  # noqa: E402
import prop_magnet_crane  # noqa: E402
import prop_scrap_pile  # noqa: E402
import tool_magnet  # noqa: E402

STORE_DIR = jm.ART_DIR / "store"
ITEMS = [item_gear, item_plate, item_barrel, item_bolt, item_pipe, item_anchor]


def build_worker(name: str):
    """Arbeiter (ca. 5,6 Studs), Blick nach Blender -Y, rechter Arm nach vorn (haelt den Magneten)."""
    b = jm.Builder(name)
    skin = jm.solid_material("sand", 0.0, 0.7)
    vest = jm.solid_material("rust_orange", 0.0, 0.6)
    stripe = jm.solid_material("chrome_light", 0.3, 0.3)
    shirt = jm.solid_material("metal_gray", 0.0, 0.8)
    pants = jm.solid_material("steel_blue", 0.0, 0.8)
    boots = jm.solid_material("tire_black", 0.0, 0.9)
    helmet = jm.solid_material("gold", 0.2, 0.4)
    eyes = jm.solid_material("tire_black", 0.0, 0.5)
    # Beine und Stiefel
    for side in (-1, 1):
        b.box((0.62, 0.7, 0.5), boots, jm.transform((side * 0.42, -0.08, 0.25)), bevel=0.06)
        b.box((0.55, 0.55, 1.6), pants, jm.transform((side * 0.42, 0, 1.3)), bevel=0.05)
    # Rumpf: Hemd, darueber Weste mit zwei Reflexstreifen
    b.box((1.55, 0.85, 1.75), shirt, jm.transform((0, 0, 2.95)), bevel=0.08)
    b.box((1.62, 0.92, 1.45), vest, jm.transform((0, 0, 2.85)), bevel=0.08)
    for z in (2.5, 3.0):
        b.box((1.66, 0.96, 0.16), stripe, jm.transform((0, 0, z)))
    # Linker Arm haengend, rechter Arm nach vorn (zum Magneten)
    b.box((0.45, 0.5, 1.5), shirt, jm.transform((-1.05, 0, 2.95), (0, 8, 0)), bevel=0.05)
    b.box((0.42, 0.45, 0.42), skin, jm.transform((-1.15, 0, 2.05)), bevel=0.06)
    b.box((0.45, 1.55, 0.45), shirt, jm.transform((1.0, -0.75, 3.45), (8, 0, 0)), bevel=0.05)
    b.box((0.42, 0.42, 0.42), skin, jm.transform((1.0, -1.6, 3.55)), bevel=0.06)
    # Kopf mit Augen und Laecheln, Schutzhelm mit Krempe
    b.box((1.05, 0.95, 1.0), skin, jm.transform((0, 0, 4.4)), bevel=0.12)
    for side in (-1, 1):
        b.box((0.13, 0.06, 0.2), eyes, jm.transform((side * 0.22, -0.49, 4.5)))
    b.box((0.36, 0.06, 0.07), eyes, jm.transform((0, -0.49, 4.15)))
    for v in b.icosphere(0.72, 2, helmet, jm.transform((0, 0, 4.8))):
        v.co.z = max(v.co.z, 4.8)
    b.cylinder(0.85, 0.12, 16, helmet, jm.transform((0, -0.08, 4.86)))
    b.box((0.18, 0.2, 0.28), helmet, jm.transform((0, -0.68, 5.25)))
    return b.finish()


def fly_in(target: Vector, source: Vector, count: int, seed: int, scale: float):
    """Schrottteile in allen Seltenheiten auf der Linie source -> target, mit Leuchtspur nach hinten."""
    rng = jm.seeded(seed)
    objs = []
    for k in range(count):
        t = (k + 0.6) / count
        module = ITEMS[k % len(ITEMS)]
        rarity = jm.RARITIES[(k * 3 + seed) % len(jm.RARITIES)]
        obj = module.build(rarity, f"fly_{seed}_{k}_{rarity}")
        jitter = Vector((rng.uniform(-1.2, 1.2), rng.uniform(-1.2, 1.2), rng.uniform(-0.9, 0.9)))
        pos = target.lerp(source, t) + jitter * (0.4 + t)
        size = scale * (1.25 if rarity in ("gold", "neon") else 1.0)
        obj.scale = (size, size, size)
        obj.location = pos
        obj.rotation_euler = tuple(math.radians(rng.uniform(-60, 60)) for _ in range(3))
        objs.append(obj)
        # Leuchtspur: schmaler Balken in Flugrichtung hinter dem Teil
        color = {"rusty": "rust_orange", "chrome": "chrome_light", "gold": "gold", "neon": "neon_cyan"}[rarity]
        trail = jm.Builder(f"trail_{seed}_{k}")
        direction = (source - target).normalized()
        length = 1.4 + 2.2 * t
        mat = jm.material(f"jm_trail_{color}", color, 0.0, 0.4, 2.0)
        trail.box((0.09, 0.09, length), mat)
        trail_obj = trail.finish()
        trail_obj.location = pos + direction * (0.9 * size)
        trail_obj.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
        objs.append(trail_obj)
    return objs


def bright_sky(scene):
    """Kraeftigeres Blau fuer das Schaufenster: Verlauf steiler, Himmel etwas heller als bei den Pruef-Renders."""
    tree = scene.world.node_tree
    nodes, links = tree.nodes, tree.links
    boost = next((n for n in nodes if n.type == "MATH"), None)
    if boost is None:
        # Aeltere jm_world (aus frueheren Laeufen in derselben Blender-Datei) hat noch keinen Verstaerker.
        split = next(n for n in nodes if n.type == "SEPXYZ")
        mix = next(n for n in nodes if n.type == "MIX")
        boost = nodes.new("ShaderNodeMath")
        boost.operation = "MULTIPLY"
        boost.use_clamp = True
        links.new(split.outputs["Z"], boost.inputs[0])
        links.new(boost.outputs["Value"], mix.inputs["Factor"])
    boost.inputs[1].default_value = 9.0
    bg = next(n for n in nodes if n.type == "BACKGROUND")
    bg.inputs["Strength"].default_value = 0.85


def stage():
    scene = jm_render.fresh()
    bright_sky(scene)
    crane = prop_magnet_crane.build("store_crane")
    crane.location = (-4.0, 26.0, 0)
    crane.rotation_euler.z = math.radians(15)
    mountain = bg_scrap_mountain.build_near("store_mountain")
    mountain.location = (-48.0, 90.0, 0)
    mountain.rotation_euler.z = math.radians(-10)
    far = bg_scrap_mountain.build_far("store_mountain_far")
    far.location = (70.0, 170.0, 0)
    pile = prop_scrap_pile.build("store_pile")
    pile.location = (-22.0, 34.0, 0)
    pile.rotation_euler.z = math.radians(30)
    return scene


def place_worker(yaw_degrees: float):
    worker = build_worker("store_worker")
    worker.rotation_euler.z = math.radians(yaw_degrees)
    magnet = tool_magnet.build("store_magnet")
    scale = 1.25
    magnet.scale = (scale, scale, scale)
    magnet.parent = worker
    # Pole zeigen nach vorn (-Y der Figur), der Griff (Modell-Oberkante, etwa 2,1 Studs) sitzt in der rechten Hand
    # (1,0 / -1,6 / 3,55): Drehung -90 Grad um X legt Modell-+Z auf Figur-+Y.
    magnet.location = (1.0, -1.6 - 2.1 * scale, 3.55)
    magnet.rotation_euler = (math.radians(-90), 0, 0)
    bpy.context.view_layer.update()
    pole = magnet.matrix_world @ Vector((0, 0, 0))
    return worker, magnet, pole


def shoot(scene, cam_pos, look_at, lens, filename, resolution):
    cam_data = bpy.data.cameras.get("store_cam") or bpy.data.cameras.new("store_cam")
    cam_data.lens = lens
    cam_data.clip_end = 600
    cam = bpy.data.objects.get("store_cam") or bpy.data.objects.new("store_cam", cam_data)
    if cam.name not in scene.collection.objects:
        scene.collection.objects.link(cam)
    cam.location = Vector(cam_pos)
    cam.rotation_euler = (Vector(look_at) - Vector(cam_pos)).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    STORE_DIR.mkdir(parents=True, exist_ok=True)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(STORE_DIR / filename)
    bpy.ops.render.render(write_still=True)
    print(f"render {filename}")


def variant_c():
    """Seitlich-schraeg: Figur links, Blick nach rechts, Teile kommen von rechts hinten."""
    scene = stage()
    _, _, pole = place_worker(90)  # Figur-Front (-Y) zeigt nach +X
    fly_in(pole + Vector((0.8, 0, 0.2)), pole + Vector((10.0, 5.0, 2.5)), 9, 3, 0.8)
    shoot(scene, (4.0, -13.0, 3.0), (6.0, 3.0, 5.2), 26, "vorschau_c_1920x1080.png", (1920, 1080))
    shoot(scene, (3.2, -6.2, 2.8), (2.7, 0.0, 4.0), 32, "icon_c_512.png", (512, 512))


def variant_d():
    """Frontal von schraeg unten: Figur blickt zur Kamera, Teile kommen von hinten rechts auf den Magneten zu."""
    scene = stage()
    _, _, pole = place_worker(25)
    # Teile kommen von rechts (quer zur Kamera), damit sie im Bild nebeneinander statt hintereinander liegen.
    fly_in(pole + Vector((0.7, 0.0, 0.2)), pole + Vector((13.0, 1.0, 4.0)), 10, 7, 0.85)
    shoot(scene, (-1.5, -12.0, 2.4), (4.0, 1.0, 4.8), 28, "vorschau_d_1920x1080.png", (1920, 1080))
    shoot(scene, (1.6, -8.6, 3.2), (3.2, 0.0, 4.4), 30, "icon_d_512.png", (512, 512))


if __name__ == "__main__":
    variant_c()
    variant_d()
