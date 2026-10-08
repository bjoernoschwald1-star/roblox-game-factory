"""Hintergrund-Kulisse (bg_*): Export je Material als eigenes Mesh-Objekt.

Der Roblox-Import macht aus jedem Mesh-Objekt einer FBX genau einen MeshPart mit einer Farbe; die
Blender-Materialien kommen nicht an. Deshalb teilt export_split ein fertiges Objekt nach Materialien und
benennt jedes Teil c_<HEX>_<Material> (z. B. c_6E7781_SmoothPlastic). Das Spiel faerbt die MeshParts nach
diesem Namen (games/junkyard_magnet/server/Backdrop.luau). Alle Teile behalten den gemeinsamen Drehpunkt
(Mitte unten), damit die Lage im importierten Model stimmt.
Hintergrund hat keine Kollision und keinen Bauteil-Ersatz (nur Kulisse ausserhalb des Zauns).
Aufruf in Blender: runpy.run_path(".../jm_backdrop.py", run_name="__main__") baut und exportiert alle bg_*.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bmesh  # noqa: E402
import bpy  # noqa: E402

import jm_common as jm  # noqa: E402
from jm_roblox import material_info  # noqa: E402


def tag(mat) -> str:
    color, kind = material_info(mat)
    return f"c_{color.lstrip('#').upper()}_{kind}"


def split(obj) -> list:
    """Teilt obj in ein Objekt je Farbe/Material (gleiche Tags werden zusammengefasst)."""
    groups: dict[str, list[int]] = {}
    for index, mat in enumerate(obj.data.materials):
        groups.setdefault(tag(mat), []).append(index)
    parts = []
    for name, indices in groups.items():
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index not in indices], context="FACES")
        mesh = bpy.data.meshes.new(name)
        bm.to_mesh(mesh)
        bm.free()
        mesh.materials.append(obj.data.materials[indices[0]])
        for poly in mesh.polygons:
            poly.material_index = 0
            poly.use_smooth = False
        part = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(part)
        part.location = obj.location
        parts.append(part)
    return parts


def export_split(obj, filename: str) -> Path:
    parts = split(obj)
    jm.EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    path = jm.EXPORT_DIR / filename
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
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
    for part in parts:
        bpy.data.objects.remove(part, do_unlink=True)
    return path


def run(entries, export: bool = True) -> list[str]:
    """entries: Liste (Name, build(name), Budget). Baut nebeneinander, prueft Budget, exportiert geteilt."""
    jm.reset_scene()
    lines = []
    x = 0.0
    for name, build, budget in entries:
        obj = build(name)
        lines.append(jm.report(obj, budget) + f", {len(obj.data.materials)} Materialien")
        if export:
            path = export_split(obj, f"{name}.fbx")
            lines.append(f"  -> {path.name} {path.stat().st_size} bytes")
        obj.location.x = x
        x += obj.dimensions.x + 10.0
    return lines


if __name__ == "__main__":
    import bg_dune  # noqa: E402
    import bg_power_pole  # noqa: E402
    import bg_scrap_mountain  # noqa: E402
    import bg_skyline  # noqa: E402
    import bg_tree  # noqa: E402

    print("\n".join(run([*bg_scrap_mountain.ENTRIES, *bg_dune.ENTRIES, *bg_skyline.ENTRIES, *bg_tree.ENTRIES,
                         *bg_power_pole.ENTRIES])))
