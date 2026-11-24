"""
Starfall Ranch: Launch Cracker Tool Asset Generator (S6-ART-01)
Location: tools/blender/generate_cracker_tools.py

Generates and exports the 3 Launch Cracker models:
- StarterCracker (`tools/blender/exports/tools/StarterCracker.fbx`)
- FrostCracker   (`tools/blender/exports/tools/FrostCracker.fbx`)
- AstralCracker  (`tools/blender/exports/tools/AstralCracker.fbx`)

Each exports as 5 flat top-level MeshParts (`Grip`, `Handle`, `Band`, `Head`, `Accent`)
with <= 400 tris, <= 8 parts, <= 4.0 studs max dimension, and a shared grip-centered
pivot at (0, 0, 0) where +Z is handle-up and -Y is striking-head forward.

Usage (CLI):
    blender --background --factory-startup --python tools/blender/generate_cracker_tools.py -- --only StarterCracker
    blender --background --factory-startup --python tools/blender/generate_cracker_tools.py
"""

import argparse
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

TARGET_TRIS_MAX = 400
MAX_PARTS = 8
MAX_DIM_STUDS = 4.0

TOOL_PALETTES = {
    "StarterCracker": {
        "grip": (96, 60, 38),
        "handle": (142, 92, 54),
        "band": (198, 128, 72),
        "head": (238, 228, 208),
        "accent": (85, 195, 185),
        "accent_emission": 0.6,
    },
    "FrostCracker": {
        "grip": (28, 42, 74),
        "handle": (185, 152, 92),
        "band": (224, 218, 206),
        "head": (78, 118, 168),
        "accent": (95, 232, 255),
        "accent_emission": 1.2,
    },
    "AstralCracker": {
        "grip": (30, 26, 48),
        "handle": (205, 164, 78),
        "band": (235, 224, 202),
        "head": (215, 174, 82),
        "accent": (196, 110, 255),
        "accent_emission": 1.3,
    },
}


def srgb_channel_to_linear(channel_01: float) -> float:
    if channel_01 <= 0.04045:
        return channel_01 / 12.92
    return ((channel_01 + 0.055) / 1.055) ** 2.4


def srgb255_to_linear_rgba(rgb: tuple[int, int, int]) -> tuple[float, float, float, float]:
    return (
        srgb_channel_to_linear(rgb[0] / 255.0),
        srgb_channel_to_linear(rgb[1] / 255.0),
        srgb_channel_to_linear(rgb[2] / 255.0),
        1.0,
    )


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_material(name: str, rgb: tuple[int, int, int], emission_strength: float = 0.0) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        rgba = srgb255_to_linear_rgba(rgb)
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Roughness"].default_value = 0.45
        if emission_strength > 0.0 and "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = rgba
            bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def finalize_bmesh_object(name: str, bm: bmesh.types.BMesh, mat: bpy.types.Material, smooth: bool = True) -> bpy.types.Object:
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()

    for poly in mesh.polygons:
        poly.use_smooth = smooth

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def add_lathe_profile(
    bm: bmesh.types.BMesh,
    rings: list[tuple[float, float]],
    segments: int = 8,
    cap_bottom: bool = True,
    cap_top: bool = True,
) -> None:
    """Creates a closed cylindrical profile along +Z from (z, radius) pairs."""
    ring_verts: list[list[bmesh.types.BMVert]] = []
    for z, r in rings:
        verts = []
        for i in range(segments):
            ang = (2.0 * math.pi * i) / segments
            verts.append(bm.verts.new((r * math.cos(ang), r * math.sin(ang), z)))
        ring_verts.append(verts)

    for r_idx in range(len(ring_verts) - 1):
        v0 = ring_verts[r_idx]
        v1 = ring_verts[r_idx + 1]
        for i in range(segments):
            j = (i + 1) % segments
            bm.faces.new((v0[i], v0[j], v1[j], v1[i]))

    if cap_bottom:
        bm.faces.new(list(reversed(ring_verts[0])))
    if cap_top:
        bm.faces.new(ring_verts[-1])


def add_box(
    bm: bmesh.types.BMesh,
    center: tuple[float, float, float],
    size: tuple[float, float, float],
    rot_euler: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> None:
    mat_scale = Matrix.Diagonal((size[0], size[1], size[2], 1.0))
    mat_rot = Euler(rot_euler, "XYZ").to_matrix().to_4x4()
    mat_loc = Matrix.Translation(Vector(center))
    bmesh.ops.create_cube(bm, size=1.0, matrix=mat_loc @ mat_rot @ mat_scale)


def build_shared_grip(mat: bpy.types.Material) -> bpy.types.Object:
    """Shared wrapped grip with pommel cap centered around (0, 0, 0)."""
    bm = bmesh.new()
    rings = [
        (-0.46, 0.135),
        (-0.40, 0.170),
        (-0.32, 0.130),
        (0.00, 0.138),
        (0.32, 0.130),
        (0.42, 0.145),
        (0.46, 0.125),
    ]
    add_lathe_profile(bm, rings, segments=8)
    return finalize_bmesh_object("Grip", bm, mat, smooth=True)


def build_shared_handle(mat: bpy.types.Material) -> bpy.types.Object:
    """Shared rounded upper shaft from Z=0.42 to Z=1.52."""
    bm = bmesh.new()
    rings = [
        (0.42, 0.105),
        (0.95, 0.112),
        (1.42, 0.128),
        (1.54, 0.115),
    ]
    add_lathe_profile(bm, rings, segments=8)
    return finalize_bmesh_object("Handle", bm, mat, smooth=True)


def build_shared_band(mat: bpy.types.Material, radius: float = 0.175) -> bpy.types.Object:
    """Observatory bolster collar at head junction."""
    bm = bmesh.new()
    rings = [
        (1.44, radius * 0.88),
        (1.52, radius),
        (1.66, radius),
        (1.74, radius * 0.88),
    ]
    add_lathe_profile(bm, rings, segments=8)
    return finalize_bmesh_object("Band", bm, mat, smooth=False)


def build_starter_head_and_accent(
    head_mat: bpy.types.Material,
    accent_mat: bpy.types.Material,
) -> tuple[bpy.types.Object, bpy.types.Object]:
    """StarterCracker: Short rounded quarry mallet with cream striking caps + teal inlays."""
    bm_head = bmesh.new()
    # Build mallet barrel along Z then rotate into Y-axis at Z=2.04
    rings = [
        (-0.56, 0.25),
        (-0.46, 0.34),
        (-0.22, 0.32),
        (0.22, 0.32),
        (0.46, 0.34),
        (0.56, 0.25),
    ]
    add_lathe_profile(bm_head, rings, segments=8)
    rot_x = Matrix.Rotation(math.radians(90.0), 4, "X")
    loc_z = Matrix.Translation(Vector((0.0, -0.04, 2.04)))
    bmesh.ops.transform(bm_head, matrix=loc_z @ rot_x, verts=bm_head.verts)
    head_obj = finalize_bmesh_object("Head", bm_head, head_mat, smooth=True)

    # Recessed teal inlay medallions on left/right faces of the mallet head
    bm_acc = bmesh.new()
    for sx in (-1.0, 1.0):
        add_box(bm_acc, (sx * 0.33, -0.04, 2.04), (0.06, 0.32, 0.22))
    accent_obj = finalize_bmesh_object("Accent", bm_acc, accent_mat, smooth=False)
    return head_obj, accent_obj


def build_frost_head_and_accent(
    head_mat: bpy.types.Material,
    accent_mat: bpy.types.Material,
) -> tuple[bpy.types.Object, bpy.types.Object]:
    """FrostCracker: Compact two-prong ice-splitter head with glowing cyan wedge."""
    bm_head = bmesh.new()
    # Central housing block at top of collar
    add_box(bm_head, (0.0, 0.04, 1.98), (0.42, 0.44, 0.46))
    # Rear counterweight bevel
    add_box(bm_head, (0.0, 0.34, 1.98), (0.30, 0.24, 0.34))

    # Two distinct forward-swept prongs along -Y (split along X)
    for sx in (-1.0, 1.0):
        p_verts = [
            # Base at housing (y = -0.16)
            (sx * 0.14, -0.16, 1.80),
            (sx * 0.24, -0.16, 1.80),
            (sx * 0.24, -0.16, 2.18),
            (sx * 0.14, -0.16, 2.18),
            # Tapered prong tip (y = -0.82)
            (sx * 0.18, -0.82, 1.92),
            (sx * 0.25, -0.82, 1.92),
            (sx * 0.25, -0.82, 2.12),
            (sx * 0.18, -0.82, 2.12),
        ]
        bv = [bm_head.verts.new(p) for p in p_verts]
        faces = [
            (0, 1, 2, 3),
            (7, 6, 5, 4),
            (0, 4, 5, 1),
            (1, 5, 6, 2),
            (2, 6, 7, 3),
            (3, 7, 4, 0),
        ]
        for f in faces:
            bm_head.faces.new([bv[idx] for idx in f])

    head_obj = finalize_bmesh_object("Head", bm_head, head_mat, smooth=False)

    # Cyan splitting wedge nestled cleanly between the two prongs
    bm_acc = bmesh.new()
    wedge_pts = [
        (-0.11, -0.12, 1.84),
        (0.11, -0.12, 1.84),
        (0.11, -0.12, 2.14),
        (-0.11, -0.12, 2.14),
        (0.0, -0.74, 1.94),
        (0.0, -0.74, 2.04),
    ]
    wv = [bm_acc.verts.new(p) for p in wedge_pts]
    bm_acc.faces.new((wv[0], wv[1], wv[2], wv[3]))
    bm_acc.faces.new((wv[0], wv[4], wv[5], wv[3]))
    bm_acc.faces.new((wv[1], wv[2], wv[5], wv[4]))
    bm_acc.faces.new((wv[0], wv[1], wv[4]))
    bm_acc.faces.new((wv[3], wv[5], wv[2]))
    accent_obj = finalize_bmesh_object("Accent", bm_acc, accent_mat, smooth=False)
    return head_obj, accent_obj


def build_astral_head_and_accent(
    head_mat: bpy.types.Material,
    accent_mat: bpy.types.Material,
) -> tuple[bpy.types.Object, bpy.types.Object]:
    """AstralCracker: Curved brass broken-ring arch with compact violet core."""
    bm_head = bmesh.new()
    # Curved crescent / broken-ring arch in Y-Z plane centered at (0, -0.08, 2.18)
    # Gap faces forward-down (-Y) so the broken ring silhouette is unmistakable.
    center_y = -0.08
    center_z = 2.18
    major_r = 0.44
    minor_r = 0.115
    arc_steps = 8
    ring_sides = 6

    # Arc sweeps from -125 deg (lower-front tip) around the back (+Y) and top (+Z) to +125 deg?
    # Angle 0 = +Y (back), 90 = +Z (top), 180 = -Y (front), 270 = -Z (bottom/handle).
    # Leave gap at front (-Y, around 180 deg) from 140 deg to 220 deg? Wait: handle attaches at 270 deg (-Z).
    # So sweep from 235 deg (bottom-front jaw) through 270 (handle), 360 (+Y back), 90 (+Z top), to 145 deg (top-front jaw)!
    start_deg = 232.0
    end_deg = 148.0 + 360.0  # 508 deg, total 276 deg sweep

    cross_rings: list[list[bmesh.types.BMVert]] = []
    for step in range(arc_steps + 1):
        t = step / arc_steps
        theta = math.radians(start_deg + (end_deg - start_deg) * t)
        # Taper slightly toward both front jaws
        taper = 0.72 + 0.28 * math.sin(math.pi * t)
        r_tube = minor_r * taper

        cy = center_y + major_r * math.cos(theta)
        cz = center_z + major_r * math.sin(theta)
        radial_y = math.cos(theta)
        radial_z = math.sin(theta)

        verts = []
        for s in range(ring_sides):
            phi = (2.0 * math.pi * s) / ring_sides
            vx = r_tube * math.cos(phi)
            vr = r_tube * math.sin(phi)
            vy = cy + vr * radial_y
            vz = cz + vr * radial_z
            verts.append(bm_head.verts.new((vx, vy, vz)))
        cross_rings.append(verts)

    for idx in range(len(cross_rings) - 1):
        r0 = cross_rings[idx]
        r1 = cross_rings[idx + 1]
        for s in range(ring_sides):
            ns = (s + 1) % ring_sides
            bm_head.faces.new((r0[s], r0[ns], r1[ns], r1[s]))

    bm_head.faces.new(list(reversed(cross_rings[0])))
    bm_head.faces.new(cross_rings[-1])
    head_obj = finalize_bmesh_object("Head", bm_head, head_mat, smooth=True)

    # Compact faceted violet octahedron core cradled in the broken ring
    bm_acc = bmesh.new()
    bmesh.ops.create_icosphere(
        bm_acc,
        subdivisions=1,
        radius=0.19,
        matrix=Matrix.Translation(Vector((0.0, center_y, center_z))),
    )
    accent_obj = finalize_bmesh_object("Accent", bm_acc, accent_mat, smooth=False)
    return head_obj, accent_obj


def validate_tool_objects(tool_id: str, objs: list[bpy.types.Object]) -> dict:
    assert len(objs) <= MAX_PARTS, f"{tool_id}: part count {len(objs)} > {MAX_PARTS}"

    total_tris = 0
    min_co = Vector((math.inf, math.inf, math.inf))
    max_co = Vector((-math.inf, -math.inf, -math.inf))
    grip_center = None

    for obj in objs:
        mesh = obj.data
        mesh.calc_loop_triangles()
        total_tris += len(mesh.loop_triangles)

        o_min = Vector((math.inf, math.inf, math.inf))
        o_max = Vector((-math.inf, -math.inf, -math.inf))
        for corner in obj.bound_box:
            wc = obj.matrix_world @ Vector(corner)
            for axis in range(3):
                min_co[axis] = min(min_co[axis], wc[axis])
                max_co[axis] = max(max_co[axis], wc[axis])
                o_min[axis] = min(o_min[axis], wc[axis])
                o_max[axis] = max(o_max[axis], wc[axis])
        if obj.name == "Grip":
            grip_center = (o_min + o_max) * 0.5

    size = max_co - min_co
    max_dim = max(size.x, size.y, size.z)

    assert total_tris <= TARGET_TRIS_MAX, f"{tool_id}: tris {total_tris} > {TARGET_TRIS_MAX}"
    assert max_dim <= MAX_DIM_STUDS, f"{tool_id}: max dim {max_dim:.3f} > {MAX_DIM_STUDS}"
    assert grip_center is not None and grip_center.length <= 0.05, (
        f"{tool_id}: Grip center {grip_center} is too far from origin (0,0,0)"
    )

    return {
        "tool_id": tool_id,
        "parts": len(objs),
        "triangles": total_tris,
        "size_studs": [round(size.x, 3), round(size.y, 3), round(size.z, 3)],
        "grip_center": [round(grip_center.x, 4), round(grip_center.y, 4), round(grip_center.z, 4)],
    }


def generate_tool(tool_id: str, sources_dir: str, exports_dir: str) -> dict:
    clear_scene()
    pal = TOOL_PALETTES[tool_id]

    grip_mat = make_material(f"{tool_id}_GripMat", pal["grip"])
    handle_mat = make_material(f"{tool_id}_HandleMat", pal["handle"])
    band_mat = make_material(f"{tool_id}_BandMat", pal["band"])
    head_mat = make_material(f"{tool_id}_HeadMat", pal["head"])
    accent_mat = make_material(f"{tool_id}_AccentMat", pal["accent"], pal["accent_emission"])

    grip_obj = build_shared_grip(grip_mat)
    handle_obj = build_shared_handle(handle_mat)
    band_obj = build_shared_band(band_mat)

    if tool_id == "StarterCracker":
        head_obj, accent_obj = build_starter_head_and_accent(head_mat, accent_mat)
    elif tool_id == "FrostCracker":
        head_obj, accent_obj = build_frost_head_and_accent(head_mat, accent_mat)
    elif tool_id == "AstralCracker":
        head_obj, accent_obj = build_astral_head_and_accent(head_mat, accent_mat)
    else:
        raise ValueError(f"Unknown tool_id: {tool_id}")

    objs = [grip_obj, handle_obj, band_obj, head_obj, accent_obj]
    stats = validate_tool_objects(tool_id, objs)

    blend_path = os.path.join(sources_dir, f"{tool_id}.blend")
    fbx_path = os.path.join(exports_dir, f"{tool_id}.fbx")

    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    bpy.ops.export_scene.fbx(
        filepath=fbx_path,
        use_selection=False,
        object_types={"MESH"},
        global_scale=0.01,
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Z",
        axis_up="Y",
        bake_space_transform=True,
        use_mesh_modifiers=True,
        mesh_smooth_type="FACE",
        add_leaf_bones=False,
        path_mode="AUTO",
    )

    stats["blend_path"] = blend_path
    stats["fbx_path"] = fbx_path
    print(
        f"[ToolGen] {tool_id} | Parts={stats['parts']}/{MAX_PARTS} | "
        f"Tris={stats['triangles']}/{TARGET_TRIS_MAX} | Size={stats['size_studs']} | "
        f"GripCenter={stats['grip_center']}"
    )
    return stats


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Generate Launch Cracker FBX & .blend assets.")
    parser.add_argument(
        "--only",
        nargs="*",
        choices=list(TOOL_PALETTES.keys()),
        default=list(TOOL_PALETTES.keys()),
        help="Subset of tools to generate.",
    )
    args = parser.parse_args(argv)

    script_dir = os.path.dirname(os.path.abspath(__file__))
    sources_dir = os.path.join(script_dir, "sources", "tools")
    exports_dir = os.path.join(script_dir, "exports", "tools")
    os.makedirs(sources_dir, exist_ok=True)
    os.makedirs(exports_dir, exist_ok=True)

    manifest_path = os.path.join(exports_dir, "manifest.json")
    manifest = {}
    if os.path.exists(manifest_path):
        try:
            with open(manifest_path, "r", encoding="utf-8") as f:
                manifest = json.load(f)
        except Exception:
            manifest = {}

    for tool_id in args.only:
        manifest[tool_id] = generate_tool(tool_id, sources_dir, exports_dir)

    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)


if __name__ == "__main__":
    main()
