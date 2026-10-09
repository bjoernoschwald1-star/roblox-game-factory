"""Gemeinsame Hilfen fuer die Module der Forschungsstation (Game #002, Probe-Raum).

Geometrie: gefaste Grundformen (Bevel-Modifier, angewendet), je Modul zu einem Mesh vereint, trianguliert,
Smart-UV-Projektion. Materialien sind prozedural (Cycles) und liefern drei Kanaele getrennt (Farbe, Rauheit,
Metall) plus Relief; daraus werden je Modul vier Karten zu 1024x1024 gebacken:
  <modul>_color.png (sRGB), <modul>_normal.png (Tangentenraum, OpenGL: +Y), <modul>_roughness.png,
  <modul>_metalness.png (beide linear, Graustufen).
Verschleiss: Rost in Flecken und Hohlraeumen, Kratzer, blanke Kanten (Bevel-Normale gegen Flaechennormale),
Schmutz in Ecken (Umgebungsverdeckung). Einheit: 1 Blender-Einheit = 1 Stud (wie Junkyard).
Ausgabe: games/game_002/art/export/<modul>.fbx und games/game_002/art/textures/.
Gebacken wird auf der CPU (keine Aenderung an den Blender-Einstellungen des Nutzers).
"""

from __future__ import annotations

import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

ART_DIR = Path(__file__).resolve().parents[1]
EXPORT_DIR = ART_DIR / "export"
TEXTURE_DIR = ART_DIR / "textures"
TEXTURE_SIZE = 1024
TRIANGLE_BUDGET = 10000

# Oberflaechenarten: Grundfarbe (linear), Rauheit, Metall, Lack (Kanten zeigen blankes Metall), Rost-, Kratzer-
# und Schmutzanteil; optional streak (Schmutzlaeufe von oben nach unten) und oil (glaenzende Oelflecken, flach).
# Look-Runde 2: deutlich mehr Rost und Schmutzlaeufe (Befund "zu sauber"), Drohne dunkles Metall statt Gelb.
SURFACES = {
    "steel": dict(color=(0.22, 0.24, 0.26), rough=0.42, metal=0.9, paint=False, rust=0.65, scratch=0.5, dirt=0.75,
                  streak=0.6),
    "dark": dict(color=(0.045, 0.05, 0.055), rough=0.55, metal=0.75, paint=False, rust=0.5, scratch=0.4, dirt=0.6,
                 streak=0.5),
    "panel": dict(color=(0.12, 0.14, 0.16), rough=0.5, metal=0.0, paint=True, rust=0.85, scratch=0.6, dirt=0.8,
                  streak=0.9),
    "hazard": dict(color=(0.75, 0.5, 0.03), rough=0.55, metal=0.0, paint=True, rust=0.6, scratch=0.7, dirt=0.7,
                   stripes=True, streak=0.6),
    "drone": dict(color=(0.05, 0.055, 0.062), rough=0.38, metal=0.85, paint=False, rust=0.3, scratch=0.7, dirt=0.5,
                  streak=0.3),
    "pipe": dict(color=(0.45, 0.2, 0.08), rough=0.5, metal=0.85, paint=False, rust=0.8, scratch=0.3, dirt=0.8,
                 streak=0.5),
    "floor_steel": dict(color=(0.2, 0.21, 0.22), rough=0.45, metal=0.9, paint=False, rust=0.6, scratch=0.6, dirt=0.8,
                        oil=1.0),
    "floor_dark": dict(color=(0.04, 0.04, 0.045), rough=0.6, metal=0.7, paint=False, rust=0.6, scratch=0.3, dirt=0.8,
                       oil=1.0),
    "puddle": dict(color=(0.008, 0.009, 0.011), rough=0.04, metal=0.0, paint=False, rust=0.0, scratch=0.0, dirt=0.15),
    "sign": dict(color=(0.8, 0.55, 0.02), rough=0.5, metal=0.0, paint=True, rust=0.5, scratch=0.6, dirt=0.6,
                 streak=0.5),
    "ink": dict(color=(0.015, 0.015, 0.015), rough=0.6, metal=0.0, paint=True, rust=0.2, scratch=0.4, dirt=0.3),
    "button_red": dict(color=(0.55, 0.03, 0.02), rough=0.3, metal=0.0, paint=False, rust=0.0, scratch=0.3, dirt=0.4),
    "button_green": dict(color=(0.03, 0.4, 0.08), rough=0.3, metal=0.0, paint=False, rust=0.0, scratch=0.3, dirt=0.4),
    "button_amber": dict(color=(0.75, 0.35, 0.02), rough=0.3, metal=0.0, paint=False, rust=0.0, scratch=0.3,
                         dirt=0.4),
    "rubber": dict(color=(0.02, 0.02, 0.022), rough=0.8, metal=0.0, paint=False, rust=0.0, scratch=0.1, dirt=0.3),
    "frost": dict(color=(0.6, 0.7, 0.8), rough=0.35, metal=0.0, paint=False, rust=0.0, scratch=0.0, dirt=0.1),
}


# ---------------------------------------------------------------------------------------------- Szene und Formen


def reset():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.curves):
        for item in list(block):
            if item.users == 0:
                block.remove(item)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 16
    # feste Abtast-Saat: gleiche Skripte ergeben gleiche Karten (Cycles-Vorgabe ist 0, hier ausdruecklich)
    scene.cycles.seed = 0
    scene.cycles.use_animated_seed = False
    scene.render.bake.margin = 8
    try:
        scene.view_settings.view_transform = "Standard"
    except TypeError:
        pass


_materials: dict[str, bpy.types.Material] = {}


def _finish(obj, surface, bevel, segments=2):
    obj.data.materials.append(material(surface))
    if bevel > 0:
        mod = obj.modifiers.new("Fase", "BEVEL")
        mod.width = bevel
        mod.segments = segments
        mod.limit_method = "ANGLE"
        mod.harden_normals = True
    return obj


def box(name, size, loc, surface, rot=(0, 0, 0), bevel=0.06):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=[math.radians(r) for r in rot])
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _finish(obj, surface, bevel)


def cyl(name, radius, depth, loc, surface, rot=(0, 0, 0), verts=16, bevel=0.03):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=loc,
                                        rotation=[math.radians(r) for r in rot])
    obj = bpy.context.active_object
    obj.name = name
    return _finish(obj, surface, bevel)


def torus(name, major, minor, loc, surface, rot=(0, 0, 0), major_seg=24, minor_seg=8):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, location=loc,
                                     rotation=[math.radians(r) for r in rot], major_segments=major_seg,
                                     minor_segments=minor_seg)
    obj = bpy.context.active_object
    obj.name = name
    return _finish(obj, surface, 0)


def sphere(name, radius, loc, surface, scale=(1, 1, 1), subdiv=2):
    bpy.ops.mesh.primitive_ico_sphere_add(radius=radius, location=loc, subdivisions=subdiv)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _finish(obj, surface, 0)


def _outward(mesh):
    """Flaechennormalen nach aussen (Roblox blendet Rueckseiten aus)."""
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    mesh.validate()
    mesh.update()


def prism(name, outline, depth, y, surface, bevel=0.02):
    """Flaches Prisma: outline = [(x, z), ...] in der XZ-Ebene, Dicke depth entlang Y ab y (Vorderseite -Y)."""
    n = len(outline)
    verts = [(x, y, z) for x, z in outline] + [(x, y + depth, z) for x, z in outline]
    faces = [list(range(n))[::-1], list(range(n, 2 * n))]
    for i in range(n):
        j = (i + 1) % n
        faces.append([i, j, n + j, n + i])
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    _outward(mesh)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    return _finish(obj, surface, bevel)


def slab(name, outline, height, z, surface, bevel=0.01):
    """Flaches Bodenstueck: outline = [(x, y), ...], Dicke height nach oben ab z."""
    n = len(outline)
    verts = [(x, yy, z) for x, yy in outline] + [(x, yy, z + height) for x, yy in outline]
    faces = [list(range(n))[::-1], list(range(n, 2 * n))]
    for i in range(n):
        j = (i + 1) % n
        faces.append([i, j, n + j, n + i])
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    _outward(mesh)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return _finish(obj, surface, bevel)


def tube(name, points, radius, surface, resolution=6, bevel_resolution=2):
    """Rohr/Kabel als Kurve; wird beim Vereinen in ein Mesh umgewandelt."""
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = bevel_resolution
    curve.resolution_u = resolution
    curve.use_fill_caps = True
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for p, co in zip(spline.bezier_points, points):
        p.co = co
        p.handle_left_type = p.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, curve)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(material(surface))
    return obj


def join(name, objects):
    """Kurven in Meshes wandeln, Modifier anwenden, vereinen, Ursprung in die Mitte der Huelle."""
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    tri = obj.modifiers.new("Dreiecke", "TRIANGULATE")
    tri.keep_custom_normals = True
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    obj["bounds_center"] = obj.location.copy()
    obj.location = (0, 0, 0)
    return obj


def unwrap(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.006, area_weight=0.0,
                             correct_aspect=True, scale_to_bounds=False)
    try:
        bpy.ops.uv.pack_islands(rotate=True, margin=0.006)
    except (RuntimeError, TypeError):
        pass
    bpy.ops.object.mode_set(mode="OBJECT")


def triangles(obj) -> int:
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def size_of(obj) -> tuple[float, float, float]:
    return tuple(round(v, 3) for v in obj.dimensions)


# ---------------------------------------------------------------------------------------------- Materialien


def material(surface: str) -> bpy.types.Material:
    """Prozedurales Material; die Ausgaenge der drei Kanaele liegen als Knoten "out_color/out_rough/out_metal"."""
    if surface in _materials:
        return _materials[surface]
    spec = SURFACES[surface]
    mat = bpy.data.materials.new(f"st_{surface}")
    mat.use_nodes = True
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")

    def node(kind, **inputs):
        n = nodes.new(kind)
        for key, value in inputs.items():
            n.inputs[key].default_value = value
        return n

    def math_node(op, a, b=None, clamp=False):
        n = nodes.new("ShaderNodeMath")
        n.operation = op
        n.use_clamp = clamp
        for i, value in enumerate((a, b)):
            if value is None:
                continue
            if isinstance(value, (int, float)):
                n.inputs[i].default_value = value
            else:
                links.new(value, n.inputs[i])
        return n.outputs[0]

    def ramp(value, low, high):
        n = nodes.new("ShaderNodeMapRange")
        n.clamp = True
        n.inputs["From Min"].default_value = low
        n.inputs["From Max"].default_value = high
        links.new(value, n.inputs["Value"])
        return n.outputs["Result"]

    def mix_color(a, b, factor):
        n = nodes.new("ShaderNodeMix")
        n.data_type = "RGBA"
        for socket, value in (("A", a), ("B", b)):
            if isinstance(value, tuple):
                n.inputs[socket].default_value = (*value, 1)
            else:
                links.new(value, n.inputs[socket])
        links.new(factor, n.inputs["Factor"])
        return n.outputs["Result"]

    def mix_float(a, b, factor):
        n = nodes.new("ShaderNodeMix")
        n.data_type = "FLOAT"
        for socket, value in (("A", a), ("B", b)):
            if isinstance(value, (int, float)):
                n.inputs[socket].default_value = value
            else:
                links.new(value, n.inputs[socket])
        links.new(factor, n.inputs["Factor"])
        return n.outputs["Result"]

    coord = nodes.new("ShaderNodeTexCoord").outputs["Object"]
    # Kanten: Bevel-Normale weicht an Kanten von der Flaechennormale ab
    bevel = node("ShaderNodeBevel")
    bevel.inputs["Radius"].default_value = 0.04
    bevel.samples = 8
    geo = nodes.new("ShaderNodeNewGeometry")
    dot = nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    links.new(bevel.outputs["Normal"], dot.inputs[0])
    links.new(geo.outputs["Normal"], dot.inputs[1])
    edge_noise = node("ShaderNodeTexNoise", Scale=18.0, Detail=6.0)
    links.new(coord, edge_noise.inputs["Vector"])
    edge = math_node("MULTIPLY", ramp(dot.outputs["Value"], 0.96, 0.82), ramp(edge_noise.outputs["Fac"], 0.45, 0.65),
                     clamp=True)
    # Hohlraeume: Umgebungsverdeckung (nur das eigene Objekt)
    ao = nodes.new("ShaderNodeAmbientOcclusion")
    ao.only_local = True
    ao.samples = 16
    ao.inputs["Distance"].default_value = 0.6
    cavity = ramp(ao.outputs["AO"], 0.9, 0.3)
    # Flecken fuer Rost und Schmutz
    blot = node("ShaderNodeTexNoise", Scale=2.2, Detail=10.0, Roughness=0.65)
    links.new(coord, blot.inputs["Vector"])
    fine = node("ShaderNodeTexNoise", Scale=40.0, Detail=8.0)
    links.new(coord, fine.inputs["Vector"])
    # Rost in Flecken, in Fugen/Hohlraeumen und an Kanten (dort nur, wo die Flecken-Maske ihn zulaesst)
    rust_base = math_node("ADD", ramp(blot.outputs["Fac"], 0.56, 0.68), math_node("MULTIPLY", cavity, 1.1))
    rust_base = math_node("ADD", rust_base, math_node("MULTIPLY", edge, ramp(blot.outputs["Fac"], 0.4, 0.6)))
    rust = math_node("MULTIPLY", math_node("MULTIPLY", rust_base, ramp(fine.outputs["Fac"], 0.35, 0.55)),
                     spec["rust"], clamp=True)
    # Kratzer: feine, verzerrte Wellenlinien
    wave = node("ShaderNodeTexWave", Scale=6.0, Distortion=18.0, Detail=4.0)
    wave.wave_profile = "SAW"
    links.new(coord, wave.inputs["Vector"])
    # nur in Flecken (grobes Rauschen), sonst wirkt die Flaeche wie gemustert
    patch = node("ShaderNodeTexNoise", Scale=1.3, Detail=2.0)
    links.new(coord, patch.inputs["Vector"])
    scratch = math_node("MULTIPLY", ramp(wave.outputs["Fac"], 0.95, 0.99), ramp(patch.outputs["Fac"], 0.55, 0.68))
    scratch = math_node("MULTIPLY", scratch, spec["scratch"], clamp=True)
    dirt = math_node("MULTIPLY", math_node("ADD", cavity, ramp(blot.outputs["Fac"], 0.45, 0.3)), spec["dirt"] * 0.5,
                     clamp=True)
    # Schmutzlaeufe: Rauschen in Z stark gestreckt (senkrechte Spuren), in Bahnen unterbrochen
    streak_map = nodes.new("ShaderNodeMapping")
    streak_map.inputs["Scale"].default_value = (9.0, 9.0, 0.35)
    links.new(coord, streak_map.inputs["Vector"])
    streak_noise = node("ShaderNodeTexNoise", Scale=2.5, Detail=5.0)
    links.new(streak_map.outputs["Vector"], streak_noise.inputs["Vector"])
    streak = math_node("MULTIPLY", ramp(streak_noise.outputs["Fac"], 0.5, 0.7), ramp(blot.outputs["Fac"], 0.3, 0.55))
    streak = math_node("MULTIPLY", streak, spec.get("streak", 0.0), clamp=True)
    # Oelflecken: flaches Rauschen nur in X/Y (Boden), sehr glatt und dunkel
    oil_map = nodes.new("ShaderNodeMapping")
    oil_map.inputs["Scale"].default_value = (1.0, 1.0, 0.0)
    links.new(coord, oil_map.inputs["Vector"])
    oil_noise = node("ShaderNodeTexNoise", Scale=0.9, Detail=4.0, Roughness=0.55)
    links.new(oil_map.outputs["Vector"], oil_noise.inputs["Vector"])
    oil = math_node("MULTIPLY", ramp(oil_noise.outputs["Fac"], 0.6, 0.64), spec.get("oil", 0.0), clamp=True)

    base = spec["color"]
    color = (0, 0, 0)
    if spec.get("stripes"):
        stripes = node("ShaderNodeTexWave", Scale=1.2, Distortion=0.0)
        stripes.wave_type = "BANDS"
        stripes.bands_direction = "DIAGONAL"
        links.new(coord, stripes.inputs["Vector"])
        band = ramp(stripes.outputs["Fac"], 0.48, 0.52)
        color = mix_color(base, (0.02, 0.02, 0.02), band)
    else:
        variation = node("ShaderNodeTexNoise", Scale=0.8, Detail=3.0)
        links.new(coord, variation.inputs["Vector"])
        color = mix_color(tuple(c * 0.85 for c in base), tuple(min(1.0, c * 1.12) for c in base),
                          variation.outputs["Fac"])
    rust_color = mix_color((0.16, 0.05, 0.015), (0.32, 0.12, 0.03), fine.outputs["Fac"])
    color = mix_color(color, rust_color, rust)
    color = mix_color(color, (0.03, 0.025, 0.02), dirt)
    color = mix_color(color, mix_color((0.02, 0.016, 0.012), (0.12, 0.045, 0.015), rust), math_node(
        "MULTIPLY", streak, 0.85))
    bare = (0.55, 0.55, 0.56)
    wear = math_node("MAXIMUM", edge, scratch)
    color = mix_color(color, bare, math_node("MULTIPLY", wear, 0.6, clamp=True))
    color = mix_color(color, (0.006, 0.006, 0.007), oil)

    rough = mix_float(spec["rough"], 0.92, rust)
    rough = mix_float(rough, 0.85, dirt)
    rough = mix_float(rough, 0.28, wear)
    metal = mix_float(spec["metal"], 0.05, rust)
    metal = mix_float(metal, spec["metal"] * 0.5, dirt)
    metal = mix_float(metal, 1.0 if spec["paint"] or spec["metal"] > 0.5 else spec["metal"], wear)
    rough = mix_float(rough, 0.9, math_node("MULTIPLY", streak, 0.4))
    rough = mix_float(rough, 0.05, oil)
    metal = mix_float(metal, 0.0, oil)

    links.new(color, bsdf.inputs["Base Color"])
    links.new(rough, bsdf.inputs["Roughness"])
    links.new(metal, bsdf.inputs["Metallic"])
    # Relief: Rostnarben (erhaben), Kratzer (vertieft), feines Korn
    height = math_node("ADD", math_node("MULTIPLY", rust, 0.6), math_node("MULTIPLY", scratch, -0.5))
    height = math_node("ADD", height, math_node("MULTIPLY", fine.outputs["Fac"], 0.15))
    bump = node("ShaderNodeBump", Strength=0.35, Distance=0.02)
    links.new(height, bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])

    for label, socket in (("out_color", color), ("out_rough", rough), ("out_metal", metal)):
        reroute = nodes.new("NodeReroute")
        reroute.name = label
        links.new(socket, reroute.inputs[0])
    _materials[surface] = mat
    return mat


def clear_materials():
    _materials.clear()


# ---------------------------------------------------------------------------------------------- Backen und Export


PASSES = (
    ("color", "out_color", "sRGB"),
    ("normal", None, "Non-Color"),
    ("roughness", "out_rough", "Non-Color"),
    ("metalness", "out_metal", "Non-Color"),
)


def bake(obj, suffix: str = "") -> list[Path]:
    """suffix kennzeichnet neu gebackene Karten (z. B. "_r2"), damit alte Lock-Eintraege erhalten bleiben."""
    TEXTURE_DIR.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    mats = [slot.material for slot in obj.material_slots if slot.material]
    written = []
    for label, socket_name, space in PASSES:
        image = bpy.data.images.new(f"{obj.name}_{label}", TEXTURE_SIZE, TEXTURE_SIZE, alpha=False)
        image.colorspace_settings.name = space
        if label == "normal":
            image.generated_color = (0.5, 0.5, 1.0, 1.0)
        restore = []
        for mat in mats:
            nodes, links = mat.node_tree.nodes, mat.node_tree.links
            target = nodes.new("ShaderNodeTexImage")
            target.image = image
            nodes.active = target
            out = next(n for n in nodes if n.type == "OUTPUT_MATERIAL")
            if socket_name is not None:
                emit = nodes.new("ShaderNodeEmission")
                links.new(nodes[socket_name].outputs[0], emit.inputs["Color"])
                old = out.inputs["Surface"].links[0].from_socket
                links.new(emit.outputs[0], out.inputs["Surface"])
                restore.append((mat, target, emit, old))
            else:
                restore.append((mat, target, None, None))
        if socket_name is None:
            scene.render.bake.normal_space = "TANGENT"
            scene.render.bake.normal_r, scene.render.bake.normal_g, scene.render.bake.normal_b = (
                "POS_X", "POS_Y", "POS_Z")  # OpenGL-Konvention (Roblox erwartet +Y)
            bpy.ops.object.bake(type="NORMAL", use_clear=True, margin=8)
        else:
            bpy.ops.object.bake(type="EMIT", use_clear=True, margin=8)
        for mat, target, emit, old in restore:
            nodes, links = mat.node_tree.nodes, mat.node_tree.links
            if emit is not None:
                out = next(n for n in nodes if n.type == "OUTPUT_MATERIAL")
                links.new(old, out.inputs["Surface"])
                nodes.remove(emit)
            nodes.remove(target)
        path = TEXTURE_DIR / f"{obj.name}_{label}{suffix}.png"
        image.filepath_raw = str(path)
        image.file_format = "PNG"
        image.save()
        written.append(path)
    return written


def export_fbx(objects, filename: str) -> Path:
    """Wie Junkyard (jm_common.export_fbx): 1 Stud = 1 Einheit, ohne Texturen in der FBX."""
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    path = EXPORT_DIR / filename
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.fbx(
        filepath=str(path),
        use_selection=True,
        object_types={"MESH"},
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_UNITS",
        mesh_smooth_type="OFF",
        use_tspace=True,
        use_mesh_modifiers=True,
        add_leaf_bones=False,
        bake_anim=False,
        path_mode="STRIP",
    )
    return path


def center_of(obj) -> Vector:
    return obj.matrix_world.translation.copy()


PREVIEW_DIR = ART_DIR.parents[2] / "build" / "art" / "probe-002-module"


def preview(obj, distance=None, suffix: str = "") -> Path:
    """Rendert das Modul nur mit den gebackenen Karten (wie in Roblox) zur Sichtpruefung nach build/."""
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    mat = bpy.data.materials.new(f"{obj.name}_baked")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    for label, socket in (("color", "Base Color"), ("roughness", "Roughness"), ("metalness", "Metallic"),
                          ("normal", None)):
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(str(TEXTURE_DIR / f"{obj.name}_{label}{suffix}.png"), check_existing=False)
        if label != "color":
            tex.image.colorspace_settings.name = "Non-Color"
        if socket is None:
            nmap = nodes.new("ShaderNodeNormalMap")
            links.new(tex.outputs["Color"], nmap.inputs["Color"])
            links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
        else:
            links.new(tex.outputs["Color"], bsdf.inputs[socket])
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    scene = bpy.context.scene
    radius = distance or max(obj.dimensions) * 1.6
    cam_data = bpy.data.cameras.new("preview_cam")
    cam = bpy.data.objects.new("preview_cam", cam_data)
    cam.location = (radius * 0.7, -radius, radius * 0.55)
    cam.rotation_euler = (Vector((0, 0, 0)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(cam)
    scene.camera = cam
    for loc, energy, color in (((radius, -radius, radius), 900, (1, 0.95, 0.9)), ((-radius, radius * 0.3, radius),
                                                                                 400, (0.5, 0.7, 1.0))):
        light = bpy.data.lights.new("preview_light", "AREA")
        light.energy = energy * radius * radius / 9
        light.color = color
        light.size = radius
        lobj = bpy.data.objects.new("preview_light", light)
        lobj.location = loc
        lobj.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(lobj)
    world = bpy.data.worlds.new("preview_world")
    world.use_nodes = True
    next(n for n in world.node_tree.nodes if n.type == "BACKGROUND").inputs["Strength"].default_value = 0.15
    scene.world = world
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.render.resolution_x = scene.render.resolution_y = 640
    path = PREVIEW_DIR / f"{obj.name}{suffix}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    scene.render.engine = "CYCLES"
    return path
