"""Beurteilungs-Renders fuer den Art-Pilot: Seltenheits-Reihen, Magnet, Kulisse, Thumbnail- und Icon-Entwurf.

Baut jede Szene aus den Objektskripten neu (reproduzierbar) und schreibt PNGs nach build/art/renders/.
Kulissenfarben (Boden, Himmel) stammen aus der Palette; Licht ist neutral und nicht das Roblox-Licht.
Aufruf in Blender: runpy.run_path(".../jm_render.py", run_name="__main__") oder blender -b -P jm_render.py
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import item_barrel  # noqa: E402
import item_bolt  # noqa: E402
import item_gear  # noqa: E402
import item_pipe  # noqa: E402
import item_plate  # noqa: E402
import jm_common as jm  # noqa: E402
import prop_container  # noqa: E402
import prop_scrap_pile  # noqa: E402
import tool_magnet  # noqa: E402

ITEMS = {
    "plate": item_plate,
    "pipe": item_pipe,
    "gear": item_gear,
    "bolt": item_bolt,
    "barrel": item_barrel,
}
SKY = "chrome_light"
ZENITH = "steel_blue"
GROUND = "sand"


def setup_stage(scene):
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    # Standard statt AgX: kraeftige, unverfaelschte Palettenfarben (naeher am Roblox-Look)
    try:
        scene.view_settings.view_transform = "Standard"
        scene.view_settings.look = "None"
    except TypeError as err:
        print(f"View Transform unveraendert: {err}")
    try:
        scene.eevee.taa_render_samples = 32
    except AttributeError:
        pass
    world = bpy.data.worlds.get("jm_world") or bpy.data.worlds.new("jm_world")
    world.use_nodes = True
    nodes, links = world.node_tree.nodes, world.node_tree.links
    bg = next(n for n in nodes if n.type == "BACKGROUND")
    bg.inputs["Strength"].default_value = 0.65
    # Verlauf Horizont (hell) -> Zenit (blau), damit Chrom und Gold etwas zum Spiegeln haben;
    # der Faktor 3 zieht das Blau nah an den Horizont, sonst bleibt der sichtbare Himmel grau
    if not any(n.type == "TEX_COORD" for n in nodes):
        coord = nodes.new("ShaderNodeTexCoord")
        split = nodes.new("ShaderNodeSeparateXYZ")
        boost = nodes.new("ShaderNodeMath")
        boost.operation = "MULTIPLY"
        boost.use_clamp = True
        boost.inputs[1].default_value = 3.0
        mix = nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        links.new(coord.outputs["Generated"], split.inputs[0])
        links.new(split.outputs["Z"], boost.inputs[0])
        links.new(boost.outputs["Value"], mix.inputs["Factor"])
        links.new(mix.outputs["Result"], bg.inputs["Color"])
    mix = next(n for n in nodes if n.type == "MIX")
    mix.inputs["A"].default_value = jm.hex_to_linear(jm.PALETTE[SKY])
    mix.inputs["B"].default_value = jm.hex_to_linear(jm.PALETTE[ZENITH])
    scene.world = world
    sun_data = bpy.data.lights.new("jm_sun", "SUN")
    sun_data.energy = 4.0
    sun_data.angle = math.radians(8)
    sun = bpy.data.objects.new("jm_sun", sun_data)
    sun.rotation_euler = (math.radians(50), 0, math.radians(-35))
    scene.collection.objects.link(sun)
    ground = jm.Builder("jm_ground")
    ground.box((400, 400, 1), jm.solid_material(GROUND, 0.0, 0.95))
    g = ground.finish()
    g.location.z = -1.0
    setup_bloom(scene)


def setup_bloom(scene):
    """Leichter Glow fuer neon ueber den Compositor; faellt still weg, wenn die API abweicht."""
    try:
        old = bpy.data.node_groups.get("jm_comp")
        if old is not None:
            bpy.data.node_groups.remove(old)
        tree = bpy.data.node_groups.new("jm_comp", "CompositorNodeTree")
        layers = tree.nodes.new("CompositorNodeRLayers")
        glare = tree.nodes.new("CompositorNodeGlare")
        out = tree.nodes.new("NodeGroupOutput")
        tree.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
        for name, value in (("Type", "Bloom"), ("Threshold", 1.2), ("Strength", 0.6), ("Size", 0.4)):
            if name in glare.inputs:
                glare.inputs[name].default_value = value
        tree.links.new(layers.outputs["Image"], glare.inputs["Image"])
        tree.links.new(glare.outputs["Image"], out.inputs[0])
        scene.compositing_node_group = tree
        scene.render.use_compositing = True
        return True
    except (AttributeError, KeyError, TypeError, RuntimeError) as err:
        print(f"Bloom nicht aktiv: {err}")
        return False


def camera(scene, target_objs, direction=(0.0, -1.0, 0.55), lens=50.0, margin=1.15):
    bpy.context.view_layer.update()
    corners = [o.matrix_world @ Vector(c) for o in target_objs for c in o.bound_box]
    lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    center = (lo + hi) / 2
    size = hi - lo
    cam_data = bpy.data.cameras.get("jm_cam") or bpy.data.cameras.new("jm_cam")
    cam_data.lens = lens
    cam = bpy.data.objects.get("jm_cam") or bpy.data.objects.new("jm_cam", cam_data)
    if cam.name not in scene.collection.objects:
        scene.collection.objects.link(cam)
    aspect = scene.render.resolution_x / scene.render.resolution_y
    # Sensor passt auf die laengere Bildseite; Abstand aus Breite und Hoehe der Zielgruppe (Blick etwa entlang +Y)
    half = math.atan(36.0 / 2 / lens)
    tan_h = math.tan(half) if aspect >= 1 else math.tan(half) * aspect
    tan_v = math.tan(half) / aspect if aspect >= 1 else math.tan(half)
    d = Vector(direction).normalized()
    half_w = max(size.x, size.y * abs(d.x)) / 2
    half_h = (size.z * math.sqrt(1 - d.z**2) + size.y * abs(d.z)) / 2
    dist = max(half_w / tan_h, half_h / tan_v) * margin + size.length / 4
    cam.location = center + d * dist
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    cam_data.clip_end = dist * 4
    scene.camera = cam


def render(scene, filename, resolution=(1600, 900)):
    jm.RENDER_DIR.mkdir(parents=True, exist_ok=True)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    path = jm.RENDER_DIR / filename
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    print(f"render {path.name}")
    return path


def fresh():
    scene = jm.reset_scene()
    setup_stage(scene)
    return scene


def lineup(key, module):
    scene = fresh()
    objs = []
    for i, rarity in enumerate(jm.RARITIES):
        obj = module.build(rarity, f"{module.NAME}_{rarity}")
        obj.location.x = (i - 1.5) * 3.4
        objs.append(obj)
    scene.render.resolution_x, scene.render.resolution_y = 1600, 900
    camera(scene, objs, margin=0.95)
    render(scene, f"lineup_{key}.png")


def single(module, filename, direction=(0.6, -1.0, 0.5)):
    scene = fresh()
    obj = module.build(module.NAME)
    scene.render.resolution_x, scene.render.resolution_y = 1600, 900
    camera(scene, [obj], direction=direction, margin=1.25)
    render(scene, filename)


def thumbnail_scene(scene):
    pile = prop_scrap_pile.build(prop_scrap_pile.NAME)
    pile.location = (-9.0, 8.0, 0)
    container = prop_container.build(prop_container.NAME)
    container.location = (9.0, 14.0, 0)
    container.rotation_euler.z = math.radians(-12)
    rng = jm.seeded(7)
    scatter = []
    # Items im Halbkreis vor der Kamera, je Grundform zwei Seltenheiten; das Neon-Zahnrad schwebt am Magneten
    spots = [(-5.5, -4.0), (-3.0, -6.5), (-1.5, -3.0), (2.5, -6.0), (4.0, -3.0), (6.5, -5.0),
             (-6.5, -1.0), (1.0, -0.5), (5.5, 0.0), (-3.0, 0.5)]
    keys = list(ITEMS)
    for k, (x, y) in enumerate(spots):
        module = ITEMS[keys[k % len(keys)]]
        rarity = jm.RARITIES[(k + k // len(keys)) % len(jm.RARITIES)]
        obj = module.build(rarity, f"scatter_{k}_{rarity}")
        obj.location = (x, y, 0)
        obj.rotation_euler.z = math.radians(rng.uniform(-50, 50))
        scatter.append(obj)
    magnet = tool_magnet.build(tool_magnet.NAME)
    magnet.scale = (3.0, 3.0, 3.0)
    magnet.location = (0.6, -3.6, 4.2)
    magnet.rotation_euler = (math.radians(10), math.radians(-12), math.radians(8))
    prize = item_gear.build("neon", "prize_gear_neon")
    prize.location = (0.4, -3.4, 1.4)
    prize.rotation_euler = (math.radians(8), math.radians(14), 0)
    scatter.append(prize)
    return pile, container, scatter, magnet


def thumbnail_and_icon():
    scene = fresh()
    pile, container, scatter, magnet = thumbnail_scene(scene)
    scene.render.resolution_x, scene.render.resolution_y = 1920, 1080
    camera(scene, [pile, container, magnet] + scatter, direction=(0.08, -1.0, 0.4), lens=32, margin=0.66)
    render(scene, "thumbnail_draft.png", (1920, 1080))
    scene.render.resolution_x, scene.render.resolution_y = 512, 512
    focus = [magnet] + [o for o in scatter if abs(o.location.x - 0.5) < 3.0 and o.location.y < 0]
    camera(scene, focus, direction=(0.2, -1.0, 0.4), lens=50, margin=0.9)
    render(scene, "icon_draft.png", (512, 512))


def main(which=None):
    for key, module in ITEMS.items():
        if which in (None, key):
            lineup(key, module)
    if which in (None, "magnet"):
        single(tool_magnet, "magnet.png", direction=(0.5, -1.0, 0.35))
    if which in (None, "scrap_pile"):
        single(prop_scrap_pile, "scrap_pile.png")
    if which in (None, "container"):
        single(prop_container, "container.png")
    if which in (None, "thumbnail"):
        thumbnail_and_icon()


if __name__ == "__main__":
    main()
