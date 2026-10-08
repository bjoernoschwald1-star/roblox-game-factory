"""Gemeinsame Hilfen fuer die Junkyard-Magnet-Art-Skripte (Blender, bpy + bmesh).

Palette, Seltenheitsmaterialien, ein Mesh-Builder ohne bpy.ops-Kontext, Szenen-Reset und FBX-Export.
Einheiten: 1 Blender-Einheit = 1 Stud; die Szene setzt scale_length = 0.28 (1 Stud = 0.28 m), damit der
FBX-Export echte Meter schreibt und der Roblox-Importer sie wieder in Studs umrechnet.
Achsen: Z oben, Vorderseite zeigt nach Blender -Y (wird mit dem Standard-FBX-Export zu Roblox +Z).
Drehpunkt: Mitte unten (Builder.finish verschiebt die Geometrie entsprechend).

Offene Punkte: Ob der Roblox-Importer die Materialfarben aus dem FBX uebernimmt, ist ungeprueft;
Emission (neon) kommt in Roblox nur ueber Material Neon bzw. SurfaceAppearance an.
"""

from __future__ import annotations

import math
import random
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ART_DIR = Path(__file__).resolve().parents[1]
EXPORT_DIR = ART_DIR / "export"
REPO_ROOT = ART_DIR.parents[2]
RENDER_DIR = REPO_ROOT / "build" / "art" / "renders"

STUD_IN_METERS = 0.28

# Verbindliche Palette (15 Farben), identisch mit STYLE.md.
PALETTE = {
    "rust_dark": "#8A3B1E",
    "rust_orange": "#E0702E",
    "chrome_light": "#DCE6F0",
    "chrome_dark": "#7D8B99",
    "gold": "#FFC21A",
    "gold_deep": "#C9800C",
    "neon_cyan": "#2BF5E3",
    "neon_pink": "#FF45D6",
    "magnet_red": "#E8322F",
    "steel_blue": "#3F72A8",
    "olive_green": "#7A9E3E",
    "sand": "#D9B98A",
    # Ergaenzung (Bjoern): dunkle Reifen und Grau-/Metalltoene fuer gemischte Schrotthaufen.
    "tire_black": "#2B2B2E",
    "metal_gray": "#6E7781",
    # Ergaenzung (Bjoern): Holzbraun fuer Baumstaemme (rust_dark wirkte rot).
    "bark_brown": "#6B4A2F",
}

RARITIES = ("rusty", "chrome", "gold", "neon")

# Je Seltenheit Haupt- und Akzentmaterial: (Farbe, metallic, roughness, emission)
RARITY_MATERIALS = {
    "rusty": (("rust_orange", 0.2, 0.85, 0.0), ("rust_dark", 0.1, 0.9, 0.0)),
    "chrome": (("chrome_light", 1.0, 0.12, 0.0), ("chrome_dark", 0.8, 0.35, 0.0)),
    "gold": (("gold", 1.0, 0.25, 0.0), ("gold_deep", 1.0, 0.35, 0.0)),
    "neon": (("neon_cyan", 0.0, 0.4, 1.4), ("neon_pink", 0.0, 0.4, 3.5)),
    # Lackierte Varianten nur fuer Kulisse (Haufen, Fass-Gruppen); keine Seltenheiten.
    "gray": (("metal_gray", 0.6, 0.5, 0.0), ("chrome_dark", 0.6, 0.5, 0.0)),
    "blue": (("steel_blue", 0.3, 0.5, 0.0), ("chrome_dark", 0.6, 0.5, 0.0)),
    "green": (("olive_green", 0.2, 0.6, 0.0), ("chrome_dark", 0.6, 0.5, 0.0)),
    "yellow": (("gold", 0.2, 0.5, 0.0), ("tire_black", 0.0, 0.8, 0.0)),
    "red": (("magnet_red", 0.2, 0.5, 0.0), ("chrome_dark", 0.6, 0.5, 0.0)),
}


def hex_to_linear(hex_color: str) -> tuple[float, float, float, float]:
    def channel(c: int) -> float:
        s = c / 255.0
        return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4

    h = hex_color.lstrip("#")
    return (channel(int(h[0:2], 16)), channel(int(h[2:4], 16)), channel(int(h[4:6], 16)), 1.0)


def material(name: str, color: str, metallic: float = 0.0, roughness: float = 0.7, emission: float = 0.0):
    """Material aus einer Palettenfarbe; gleicher Name = gleiches Material (wird bei Bedarf neu gesetzt)."""
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    rgba = hex_to_linear(PALETTE[color])
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Emission Color"].default_value = rgba
    bsdf.inputs["Emission Strength"].default_value = emission
    mat.diffuse_color = rgba
    return mat


def rarity_materials(rarity: str):
    primary, accent = RARITY_MATERIALS[rarity]
    return (
        material(f"jm_{rarity}_primary", *primary),
        material(f"jm_{rarity}_accent", *accent),
    )


def solid_material(color: str, metallic: float = 0.0, roughness: float = 0.7, emission: float = 0.0):
    return material(f"jm_{color}", color, metallic, roughness, emission)


def transform(loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)) -> Matrix:
    """Matrix aus Ort, Drehung in Grad und Skalierung."""
    r = Euler([math.radians(a) for a in rot]).to_matrix().to_4x4()
    s = Matrix.Diagonal((*scale, 1.0))
    return Matrix.Translation(Vector(loc)) @ r @ s


class Builder:
    """Sammelt Primitive in einem bmesh; jedes Primitiv bekommt ein Material und eine Matrix."""

    def __init__(self, name: str):
        self.name = name
        self.bm = bmesh.new()
        self.materials: list = []
        self.parent = Matrix.Identity(4)
        # Grundformen fuer den Roblox-Ersatz aus Parts (jm_roblox.py): (art, Masse, Weltmatrix, Material)
        self.shapes: list[dict] = []
        self.offset = Vector((0.0, 0.0, 0.0))

    def _shape(self, kind: str, dims, matrix: Matrix, mat):
        self.shapes.append({"kind": kind, "dims": tuple(dims), "matrix": (self.parent @ matrix).copy(), "mat": mat})

    def reshape_last(self, scale):
        """Passt die zuletzt erfasste Grundform an, wenn Skripte Vertices direkt verformen (z. B. Huegel)."""
        last = self.shapes[-1]
        last["matrix"] = last["matrix"] @ Matrix.Diagonal((*scale, 1.0))

    def _slot(self, mat) -> int:
        if mat not in self.materials:
            self.materials.append(mat)
        return self.materials.index(mat)

    def _finish_part(self, verts, mat, matrix: Matrix):
        verts = list(verts)
        bmesh.ops.transform(self.bm, matrix=self.parent @ matrix, verts=verts)
        idx = self._slot(mat)
        faces = {f for v in verts for f in v.link_faces}
        for f in faces:
            f.material_index = idx
        return verts

    def box(self, size, mat, matrix: Matrix = Matrix.Identity(4), bevel: float = 0.0):
        self._shape("Block", size, matrix, mat)
        res = bmesh.ops.create_cube(self.bm, size=1.0)
        verts = res["verts"]
        bmesh.ops.scale(self.bm, vec=Vector(size), verts=verts)
        if bevel > 0:
            # Fasen fangen Glanzlichter (chrome/gold); Teilflaechen vor und nach dem Bevel einsammeln
            faces = {f for v in verts for f in v.link_faces}
            edges = list({e for v in verts for e in v.link_edges})
            out = bmesh.ops.bevel(self.bm, geom=list(verts) + edges, offset=bevel, segments=1,
                                  affect="EDGES", profile=0.5)
            faces = {f for f in faces if f.is_valid} | set(out["faces"])
            verts = list({v for f in faces for v in f.verts})
        return self._finish_part(verts, mat, matrix)

    def cylinder(self, radius, depth, sides, mat, matrix: Matrix = Matrix.Identity(4), radius_top=None):
        self._shape("Cylinder", (max(radius, radius_top or 0.0), depth), matrix, mat)
        res = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=sides, radius1=radius,
                                    radius2=radius if radius_top is None else radius_top, depth=depth)
        return self._finish_part(res["verts"], mat, matrix)

    def tube(self, r_out, r_in, length, sides, mat, matrix: Matrix = Matrix.Identity(4)):
        self._shape("Cylinder", (r_out, length), matrix, mat)
        """Hohlzylinder entlang Z, mittig."""
        bm = self.bm
        rings = []
        for r in (r_out, r_in):
            for z in (-length / 2, length / 2):
                rings.append([bm.verts.new((r * math.cos(2 * math.pi * i / sides),
                                            r * math.sin(2 * math.pi * i / sides), z)) for i in range(sides)])
        ob, ot, ib, it = rings
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new((ob[i], ob[j], ot[j], ot[i]))
            bm.faces.new((ib[j], ib[i], it[i], it[j]))
            bm.faces.new((ot[i], ot[j], it[j], it[i]))
            bm.faces.new((ob[j], ob[i], ib[i], ib[j]))
        return self._finish_part([v for ring in rings for v in ring], mat, matrix)

    def icosphere(self, radius, subdivisions, mat, matrix: Matrix = Matrix.Identity(4)):
        self._shape("Ball", (radius,), matrix, mat)
        res = bmesh.ops.create_icosphere(self.bm, subdivisions=subdivisions, radius=radius)
        return self._finish_part(res["verts"], mat, matrix)

    def sweep(self, path, profile, mat, matrix: Matrix = Matrix.Identity(4)):
        # Fuer den Roblox-Ersatz: je Pfadabschnitt ein Quader (Laenge entlang des Pfads).
        width = 2 * max(abs(a) for a, _ in profile)
        depth = 2 * max(abs(b) for _, b in profile)
        for k in range(len(path) - 1):
            p0, p1 = Vector(path[k]), Vector(path[k + 1])
            t = (p1 - p0)
            if t.length < 1e-6:
                continue
            t = t.normalized()
            y = Vector((0.0, 1.0, 0.0))
            z = t.cross(y)
            rot = Matrix((t, y, z)).transposed().to_4x4()
            seg = Matrix.Translation((p0 + p1) / 2) @ rot
            self._shape("Block", ((p1 - p0).length + 0.05, depth, width), matrix @ seg, mat)
        """Profil (Liste von (a, b)) entlang eines Pfads in der XZ-Ebene; a = Normale in der Ebene, b = Y."""
        bm = self.bm
        rings = []
        for k, p in enumerate(path):
            p = Vector(p)
            prev_p = Vector(path[max(k - 1, 0)])
            next_p = Vector(path[min(k + 1, len(path) - 1)])
            t = (next_p - prev_p).normalized()
            n = Vector((t.z, 0.0, -t.x))
            rings.append([bm.verts.new(p + n * a + Vector((0, b, 0))) for a, b in profile])
        m = len(profile)
        for k in range(len(rings) - 1):
            for i in range(m):
                j = (i + 1) % m
                bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
        return self._finish_part([v for ring in rings for v in ring], mat, matrix)

    def finish(self, collection=None):
        """Normalen, Drehpunkt Mitte unten, flache Schattierung; liefert das Objekt."""
        bm = self.bm
        bm.normal_update()
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        xs = [v.co.x for v in bm.verts]
        ys = [v.co.y for v in bm.verts]
        zs = [v.co.z for v in bm.verts]
        offset = Vector((-(min(xs) + max(xs)) / 2, -(min(ys) + max(ys)) / 2, -min(zs)))
        bmesh.ops.translate(bm, vec=offset, verts=bm.verts)
        self.offset = offset
        mesh = bpy.data.meshes.new(self.name)
        bm.to_mesh(mesh)
        bm.free()
        for poly in mesh.polygons:
            poly.use_smooth = False
        for mat in self.materials:
            mesh.materials.append(mat)
        obj = bpy.data.objects.new(self.name, mesh)
        (collection or bpy.context.scene.collection).objects.link(obj)
        return obj


def seeded(seed: int) -> random.Random:
    return random.Random(seed)


def reset_scene():
    """Leere Szene in Studs."""
    scene = bpy.context.scene
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for item in list(block):
            if item.users == 0:
                block.remove(item)
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = STUD_IN_METERS
    return scene


def triangle_count(obj) -> int:
    mesh = obj.data
    mesh.calc_loop_triangles()
    return len(mesh.loop_triangles)


def dimensions(obj) -> tuple[float, float, float]:
    d = obj.dimensions
    return (round(d.x, 2), round(d.y, 2), round(d.z, 2))


def export_fbx(obj, filename: str) -> Path:
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    path = EXPORT_DIR / filename
    for o in bpy.context.scene.objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.fbx(
        filepath=str(path),
        use_selection=True,
        object_types={"MESH"},
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_UNITS",
        mesh_smooth_type="FACE",
        use_mesh_modifiers=True,
        add_leaf_bones=False,
        bake_anim=False,
        path_mode="STRIP",
    )
    return path


def report(obj, budget: int) -> str:
    tris = triangle_count(obj)
    assert tris <= budget, f"{obj.name}: {tris} Dreiecke > Budget {budget}"
    return f"{obj.name}: {tris} tris, {dimensions(obj)} studs"


def run_variants(build, base_name: str, budget: int, export: bool = True):
    """Baut alle Seltenheiten einer Grundform und exportiert je eine FBX."""
    reset_scene()
    lines = []
    for i, rarity in enumerate(RARITIES):
        obj = build(rarity, f"{base_name}_{rarity}")
        obj.location.x = i * 4.0
        lines.append(report(obj, budget))
        if export:
            saved = obj.location.copy()
            obj.location = (0, 0, 0)
            path = export_fbx(obj, f"{base_name}_{rarity}.fbx")
            obj.location = saved
            lines.append(f"  -> {path.name} {path.stat().st_size} bytes")
    print("\n".join(lines))


def run_single(build, name: str, budget: int, export: bool = True):
    reset_scene()
    obj = build(name)
    line = report(obj, budget)
    if export:
        path = export_fbx(obj, f"{name}.fbx")
        line += f"\n  -> {path.name} {path.stat().st_size} bytes"
    print(line)
    return obj
