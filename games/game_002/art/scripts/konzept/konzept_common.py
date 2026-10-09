"""Gemeinsame Hilfen fuer die Konzeptbilder von Game #002 (Blender, nur bpy, keine fremden Assets).

Stil: stilisiert-realistisch (gefaste Kanten, prozedurale PBR-Materialien mit Rauheits- und Schmutzvariation,
volumetrisches Licht), kein Low-Poly-Flat-Shading. Alles prozedural und fest geseedet; Ausgabe nach
build/art/konzept-002/. Aufruf je Szene: runpy.run_path(".../<szene>.py", run_name="__main__").
"""

from __future__ import annotations

import math
import random
from pathlib import Path

import bpy
from mathutils import Vector

REPO_ROOT = Path(__file__).resolve().parents[5]
OUT_DIR = REPO_ROOT / "build" / "art" / "konzept-002"


def reset(seed: int = 1) -> bpy.types.Scene:
    random.seed(seed)
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.lights, bpy.data.cameras, bpy.data.worlds):
        for item in list(block):
            if item.users == 0:
                block.remove(item)
    scene = bpy.context.scene
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    eevee = scene.eevee
    for name, value in (
        ("taa_render_samples", 64),
        ("use_raytracing", True),
        ("use_shadows", True),
        ("volumetric_tile_size", "4"),
        ("volumetric_samples", 96),
        ("use_volumetric_shadows", True),
    ):
        try:
            setattr(eevee, name, value)
        except (AttributeError, TypeError):
            pass
    try:
        scene.view_settings.view_transform = "AgX"
        scene.view_settings.look = "AgX - Medium High Contrast"
    except TypeError:
        pass
    scene.render.resolution_x, scene.render.resolution_y = 1920, 1080
    scene.render.resolution_percentage = 100
    return scene


def world(color, strength=0.3, fog_density=0.0, fog_color=(1, 1, 1), anisotropy=0.3):
    w = bpy.data.worlds.new("konzept_world")
    w.use_nodes = True
    nodes, links = w.node_tree.nodes, w.node_tree.links
    bg = next(n for n in nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (*color, 1)
    bg.inputs["Strength"].default_value = strength
    if fog_density > 0:
        out = next(n for n in nodes if n.type == "OUTPUT_WORLD")
        vol = nodes.new("ShaderNodeVolumePrincipled")
        vol.inputs["Density"].default_value = fog_density
        vol.inputs["Color"].default_value = (*fog_color, 1)
        vol.inputs["Anisotropy"].default_value = anisotropy
        links.new(vol.outputs[0], out.inputs["Volume"])
    bpy.context.scene.world = w
    return w


def pbr(name, base, metallic=0.0, roughness=0.5, dirt=0.35, scratch=0.25, emission=None, strength=0.0, scale=4.0):
    """Prozedurales PBR-Material: Grundfarbe mit Schmutz (Noise) und Kratzern (Wave), Rauheit variiert, Relief."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    coord = nodes.new("ShaderNodeTexCoord")
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = 8.0
    links.new(coord.outputs["Object"], noise.inputs["Vector"])
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.45
    ramp.color_ramp.elements[1].position = 0.75
    links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    dirt_color = nodes.new("ShaderNodeMix")
    dirt_color.data_type = "RGBA"
    dirt_color.inputs["A"].default_value = (*base, 1)
    dirt_color.inputs["B"].default_value = (base[0] * 0.35, base[1] * 0.3, base[2] * 0.28, 1)
    fac = nodes.new("ShaderNodeMath")
    fac.operation = "MULTIPLY"
    fac.inputs[1].default_value = dirt
    links.new(ramp.outputs["Color"], fac.inputs[0])
    links.new(fac.outputs[0], dirt_color.inputs["Factor"])
    links.new(dirt_color.outputs["Result"], bsdf.inputs["Base Color"])
    # Kratzer: feine Wellen, die die Rauheit senken (blanke Stellen)
    wave = nodes.new("ShaderNodeTexWave")
    wave.inputs["Scale"].default_value = scale * 6
    wave.inputs["Distortion"].default_value = 12.0
    links.new(coord.outputs["Object"], wave.inputs["Vector"])
    scr = nodes.new("ShaderNodeValToRGB")
    scr.color_ramp.elements[0].position = 0.9
    scr.color_ramp.elements[1].position = 0.97
    links.new(wave.outputs["Fac"], scr.inputs["Fac"])
    rough = nodes.new("ShaderNodeMapRange")
    rough.inputs["To Min"].default_value = roughness
    rough.inputs["To Max"].default_value = min(1.0, roughness + 0.35)
    links.new(ramp.outputs["Color"], rough.inputs["Value"])
    rough_mix = nodes.new("ShaderNodeMix")
    rough_mix.inputs["B"].default_value = max(0.05, roughness - 0.3)
    links.new(rough.outputs["Result"], rough_mix.inputs["A"])
    sfac = nodes.new("ShaderNodeMath")
    sfac.operation = "MULTIPLY"
    sfac.inputs[1].default_value = scratch
    links.new(scr.outputs["Color"], sfac.inputs[0])
    links.new(sfac.outputs[0], rough_mix.inputs["Factor"])
    links.new(rough_mix.outputs["Result"], bsdf.inputs["Roughness"])
    bsdf.inputs["Metallic"].default_value = metallic
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.15
    links.new(noise.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1)
        bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def emissive(name, color, strength):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Emission Color"].default_value = (*color, 1)
    bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def _finish(obj, mat, bevel):
    if mat is not None:
        obj.data.materials.append(mat)
    if bevel > 0:
        mod = obj.modifiers.new("Fase", "BEVEL")
        mod.width = bevel
        mod.segments = 3
        mod.limit_method = "ANGLE"
    for poly in obj.data.polygons:
        poly.use_smooth = True
    try:
        obj.data.shade_auto_smooth(angle=math.radians(35))
    except (AttributeError, TypeError, RuntimeError):
        pass
    return obj


def box(size, loc, mat=None, rot=(0, 0, 0), bevel=0.04, name="box"):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=[math.radians(r) for r in rot])
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _finish(obj, mat, bevel)


def cyl(radius, depth, loc, mat=None, rot=(0, 0, 0), verts=32, bevel=0.02, name="cyl"):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=loc,
                                        rotation=[math.radians(r) for r in rot])
    obj = bpy.context.active_object
    obj.name = name
    return _finish(obj, mat, bevel)


def sphere(radius, loc, mat=None, scale=(1, 1, 1), name="sphere"):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=loc, segments=32, ring_count=16)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    return _finish(obj, mat, 0)


def torus(major, minor, loc, mat=None, rot=(0, 0, 0), name="torus"):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, location=loc,
                                     rotation=[math.radians(r) for r in rot])
    obj = bpy.context.active_object
    obj.name = name
    return _finish(obj, mat, 0)


def pipe_run(points, radius, mat, name="pipe"):
    """Rohr oder Kabel entlang einer Punktliste (Kurve mit Bevel)."""
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 6
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for p, co in zip(spline.bezier_points, points):
        p.co = co
        p.handle_left_type = p.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, curve)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def light(kind, loc, energy, color=(1, 1, 1), rot=(0, 0, 0), size=0.2, spot=45.0, name="licht"):
    data = bpy.data.lights.new(name, kind)
    data.energy = energy
    data.color = color
    if hasattr(data, "shadow_soft_size"):
        data.shadow_soft_size = size
    if kind == "SPOT":
        data.spot_size = math.radians(spot)
        data.spot_blend = 0.4
    obj = bpy.data.objects.new(name, data)
    obj.location = loc
    obj.rotation_euler = [math.radians(r) for r in rot]
    bpy.context.scene.collection.objects.link(obj)
    return obj


def particles(count, center, extent, radius, mat, seed=3, name="teilchen"):
    """Schwebeteilchen als kleine Kugeln (Staub, Plankton, Funken)."""
    rng = random.Random(seed)
    objs = []
    base = sphere(radius, center, mat, name=name)
    objs.append(base)
    for k in range(count - 1):
        copy = base.copy()
        copy.data = base.data
        copy.location = Vector(center) + Vector(
            (rng.uniform(-1, 1) * extent[0], rng.uniform(-1, 1) * extent[1], rng.uniform(-1, 1) * extent[2])
        )
        s = rng.uniform(0.4, 1.4)
        copy.scale = (s, s, s)
        bpy.context.scene.collection.objects.link(copy)
        objs.append(copy)
    return objs


def camera(loc, look_at, lens=28, dof_distance=None, fstop=2.8):
    data = bpy.data.cameras.new("konzept_cam")
    data.lens = lens
    data.clip_end = 500
    if dof_distance is not None:
        data.dof.use_dof = True
        data.dof.focus_distance = dof_distance
        data.dof.aperture_fstop = fstop
    cam = bpy.data.objects.new("konzept_cam", data)
    cam.location = loc
    cam.rotation_euler = (Vector(look_at) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(cam)
    bpy.context.scene.camera = cam
    return cam


def render(filename):
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(OUT_DIR / filename)
    bpy.ops.render.render(write_still=True)
    print(f"render {filename}")
