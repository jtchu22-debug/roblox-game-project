"""
Starfall Ranch: Single-Sample Blender Validation Script (Stage 4 / S4-01 / R-010)
Location: tools/blender/export_starslime_sample.py

Builds ONLY the single validation critter model (`StarSlime`) and exports it to:
    tools/blender/exports/sample/StarSlime.fbx

Coordinate & Export Convention (1 Blender unit = 1 Roblox stud):
- Modeled in Blender Z-up (`+Z` up, `-Y` front, `+Y` back) with all vertices baked
  around world origin `(0, 0, 0)` and ground contact resting flat at `Z = 0.0`.
- Exported via FBX (`axis_forward='-Z'`, `axis_up='Y'`, `global_scale=0.01`,
  `apply_unit_scale=True`, `apply_scale_options='FBX_SCALE_ALL'`,
  `bake_space_transform=True`), empirically verified in Roblox Studio 3D Importer
  (`Scale Unit: Studs`): Blender `-Y` imports to Roblox `-Z` (`LookVector` forward),
  Blender `+Y` imports to Roblox `+Z` back, and Blender `+Z` imports to Roblox `+Y` up.
- Exports `Body`, `Eyes`, and `Accent` as flat top-level objects (no Empty
  wrapper), because Studio's 3D Importer wraps the `.fbx` file in a `StarSlime`
  root `Model` automatically without double-nesting.

Usage (CLI):
    blender --background --factory-startup --python tools/blender/export_starslime_sample.py
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

COLLECTION_NAME = "SR_SampleValidation"
DEFAULT_STARTUP_OBJECTS = frozenset({"Cube", "Camera", "Light"})
TARGET_TRIS_MAX = 400
MAX_HEIGHT_STUDS = 8.0
EXPECTED_AXIS_MAX_STUDS = 3.2

# CritterConfig.ById.StarSlime palette in sRGB 0..255
COLOR_BODY_SRGB = (95, 225, 165)
COLOR_EYES_SRGB = (22, 20, 34)
COLOR_ACCENT_SRGB = (255, 225, 95)


def srgb_channel_to_linear(channel_01: float) -> float:
    """Converts a normalized sRGB channel (0..1) into linear RGB for Blender shaders."""
    if channel_01 <= 0.04045:
        return channel_01 / 12.92
    return ((channel_01 + 0.055) / 1.055) ** 2.4


def srgb255_to_linear_rgba(rgb: tuple[int, int, int]) -> tuple[float, float, float, float]:
    """Converts 0..255 sRGB tuple into Blender linear RGBA tuple."""
    return (
        srgb_channel_to_linear(rgb[0] / 255.0),
        srgb_channel_to_linear(rgb[1] / 255.0),
        srgb_channel_to_linear(rgb[2] / 255.0),
        1.0,
    )


def get_output_fbx_path() -> str:
    """Resolves `tools/blender/exports/sample/StarSlime.fbx` relative to this script."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    export_dir = os.path.join(script_dir, "exports", "sample")
    os.makedirs(export_dir, exist_ok=True)
    return os.path.join(export_dir, "StarSlime.fbx")


def guard_and_prepare_scene(allow_non_empty: bool) -> bpy.types.Collection:
    """
    Aborts safely if run interactively inside a populated scene without `--force`.
    Cleans only previous validation objects or factory-startup defaults.
    """
    managed_names = {"StarSlime", "Body", "Eyes", "Accent"}
    unexpected = [
        obj.name
        for obj in bpy.data.objects
        if obj.name not in managed_names and obj.name not in DEFAULT_STARTUP_OBJECTS
    ]
    if unexpected and not allow_non_empty:
        raise RuntimeError(
            "Aborting R-010 sample export: scene contains existing objects "
            f"({', '.join(unexpected[:5])}). Open a clean scene or pass `--force`."
        )

    # Remove previous sample collection & managed objects only.
    if COLLECTION_NAME in bpy.data.collections:
        col = bpy.data.collections[COLLECTION_NAME]
        for obj in list(col.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.collections.remove(col)

    for obj in list(bpy.data.objects):
        if obj.name in managed_names:
            bpy.data.objects.remove(obj, do_unlink=True)
        elif bpy.app.background and obj.name in DEFAULT_STARTUP_OBJECTS:
            bpy.data.objects.remove(obj, do_unlink=True)

    # Remove orphaned StarSlime data blocks from prior runs.
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0 and mesh.name.startswith("StarSlime_"):
            bpy.data.meshes.remove(mesh)
    for mat in list(bpy.data.materials):
        if mat.users == 0 and mat.name.startswith("Mat_StarSlime_"):
            bpy.data.materials.remove(mat)

    sample_col = bpy.data.collections.new(COLLECTION_NAME)
    bpy.context.scene.collection.children.link(sample_col)
    return sample_col


def create_material(
    mat_name: str,
    srgb_rgb: tuple[int, int, int],
    roughness: float,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    """Creates a clean Principled BSDF material without external textures."""
    existing = bpy.data.materials.get(mat_name)
    if existing is not None:
        bpy.data.materials.remove(existing)

    mat = bpy.data.materials.new(name=mat_name)
    if bpy.app.version < (5, 0, 0):
        mat.use_nodes = True
    rgba = srgb255_to_linear_rgba(srgb_rgb)

    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Roughness"].default_value = roughness
        if "Emission Strength" in bsdf.inputs and emission_strength > 0.0:
            if "Emission Color" in bsdf.inputs:
                bsdf.inputs["Emission Color"].default_value = rgba
            bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def append_bmesh(target_bm: bmesh.types.BMesh, source_bm: bmesh.types.BMesh) -> None:
    """Copies vertices and faces from `source_bm` into `target_bm` cleanly."""
    vert_map: dict[bmesh.types.BMVert, bmesh.types.BMVert] = {}
    for src_vert in source_bm.verts:
        vert_map[src_vert] = target_bm.verts.new(src_vert.co)
    for src_face in source_bm.faces:
        try:
            target_bm.faces.new([vert_map[v] for v in src_face.verts])
        except ValueError:
            pass


def add_beveled_box(
    target_bm: bmesh.types.BMesh,
    size: tuple[float, float, float],
    center: tuple[float, float, float],
    bevel_offset: float,
    bevel_segments: int,
    euler_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> list[bmesh.types.BMVert]:
    """Builds a closed beveled box shell inside a temporary bmesh and appends it."""
    sub = bmesh.new()
    bmesh.ops.create_cube(sub, size=1.0)
    bmesh.ops.scale(sub, vec=Vector(size), verts=list(sub.verts))
    bmesh.ops.bevel(
        sub,
        geom=list(sub.edges),
        offset=bevel_offset,
        offset_type="OFFSET",
        segments=bevel_segments,
        profile=0.5,
        affect="EDGES",
        clamp_overlap=True,
    )
    if any(angle != 0.0 for angle in euler_deg):
        rot_mat = Euler(tuple(math.radians(a) for a in euler_deg), "XYZ").to_matrix()
        bmesh.ops.rotate(sub, cent=Vector((0.0, 0.0, 0.0)), matrix=rot_mat, verts=list(sub.verts))
    bmesh.ops.translate(sub, vec=Vector(center), verts=list(sub.verts))
    bmesh.ops.recalc_face_normals(sub, faces=list(sub.faces))

    start_index = len(target_bm.verts)
    append_bmesh(target_bm, sub)
    sub.free()
    target_bm.verts.ensure_lookup_table()
    return list(target_bm.verts)[start_index:]


def build_body_bmesh() -> bmesh.types.BMesh:
    """
    Builds StarSlime's `Body` sub-mesh:
    - Chibi rounded-cube jelly torso resting flat at `Z = 0.0`
    - Two stubby side feet/nubs resting flush on `Z = 0.0`
    - Small rounded cosmic tail nub at the back (`+Y`)
    """
    bm = bmesh.new()

    # 1. Main chibi jelly torso (~2.32 x 2.28 x 2.08 studs)
    torso_verts = add_beveled_box(
        bm,
        size=(2.32, 2.28, 2.08),
        center=(0.0, 0.0, 1.04),
        bevel_offset=0.28,
        bevel_segments=2,
    )

    # Gentle jelly silhouette sculpt: plump lower cheeks, subtly domed top
    for v in torso_verts:
        z_norm = max(0.0, min(1.0, v.co.z / 2.08))
        if z_norm > 0.65:
            t = (z_norm - 0.65) / 0.35
            taper = 1.0 - 0.14 * t
            v.co.x *= taper
            v.co.y *= taper
        elif 0.12 <= z_norm <= 0.50:
            belly = 1.0 + 0.05 * math.sin(((z_norm - 0.12) / 0.38) * math.pi)
            v.co.x *= belly
            v.co.y *= belly

    # Ensure exact flat ground contact on Z = 0.0
    torso_min_z = min(v.co.z for v in torso_verts)
    for v in torso_verts:
        v.co.z -= torso_min_z

    # 2. Two stubby side feet / jelly nubbins resting at Z = 0.0
    for side in (-1, 1):
        foot_verts = add_beveled_box(
            bm,
            size=(0.56, 0.70, 0.64),
            center=(side * 1.12, -0.04, 0.34),
            bevel_offset=0.14,
            bevel_segments=1,
            euler_deg=(0.0, side * 8.0, 0.0),
        )
        foot_min_z = min(v.co.z for v in foot_verts)
        for v in foot_verts:
            v.co.z -= foot_min_z

    # 3. Tiny low-poly cosmic tail nub at +Y back (Roblox +Z back)
    add_beveled_box(
        bm,
        size=(0.56, 0.62, 0.52),
        center=(0.0, 1.06, 0.44),
        bevel_offset=0.13,
        bevel_segments=1,
        euler_deg=(-18.0, 0.0, 0.0),
    )

    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return bm


def build_eyes_bmesh() -> bmesh.types.BMesh:
    """Builds StarSlime's `Eyes` sub-mesh: two faceted low-poly oval eyes on `-Y` front (Roblox `-Z`)."""
    bm = bmesh.new()

    for side in (-1, 1):
        sub = bmesh.new()
        bmesh.ops.create_icosphere(sub, subdivisions=1, radius=1.0)
        bmesh.ops.scale(sub, vec=Vector((0.21, 0.13, 0.27)), verts=list(sub.verts))
        rot_mat = Euler((0.0, 0.0, math.radians(-side * 10.0)), "XYZ").to_matrix()
        bmesh.ops.rotate(sub, cent=Vector((0.0, 0.0, 0.0)), matrix=rot_mat, verts=list(sub.verts))
        bmesh.ops.translate(sub, vec=Vector((side * 0.48, -1.11, 1.08)), verts=list(sub.verts))
        bmesh.ops.recalc_face_normals(sub, faces=list(sub.faces))
        append_bmesh(bm, sub)
        sub.free()

    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return bm


def build_accent_bmesh() -> bmesh.types.BMesh:
    """
    Builds StarSlime's `Accent` sub-mesh: a crisp closed 3D 5-point cosmic star crest
    perched symmetrically on top of the jelly head (40 tris).
    """
    bm = bmesh.new()

    outer_r = 0.56
    inner_r = 0.25
    rim_half_depth = 0.09
    apex_half_depth = 0.20

    front_ring: list[bmesh.types.BMVert] = []
    back_ring: list[bmesh.types.BMVert] = []
    point_count = 10
    for idx in range(point_count):
        angle = math.pi * 0.5 + idx * (2.0 * math.pi / point_count)
        radius = outer_r if idx % 2 == 0 else inner_r
        px = math.cos(angle) * radius
        pz = math.sin(angle) * radius
        front_ring.append(bm.verts.new((px, -rim_half_depth, pz)))
        back_ring.append(bm.verts.new((px, rim_half_depth, pz)))

    front_apex = bm.verts.new((0.0, -apex_half_depth, 0.0))
    back_apex = bm.verts.new((0.0, apex_half_depth, 0.0))

    # Front & back star fans + extruded rim quads
    for idx in range(point_count):
        nxt = (idx + 1) % point_count
        bm.faces.new((front_ring[idx], front_ring[nxt], front_apex))
        bm.faces.new((back_ring[nxt], back_ring[idx], back_apex))
        bm.faces.new((front_ring[nxt], front_ring[idx], back_ring[idx], back_ring[nxt]))

    # Tilt crest face slightly toward -Y front / +Z up for crisp eye-level & top-down silhouette
    rot_mat = Euler((math.radians(-14.0), 0.0, 0.0), "XYZ").to_matrix()
    bmesh.ops.rotate(bm, cent=Vector((0.0, 0.0, 0.0)), matrix=rot_mat, verts=list(bm.verts))
    bmesh.ops.translate(bm, vec=Vector((0.0, -0.04, 2.26)), verts=list(bm.verts))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return bm


def finalize_mesh_object(
    obj_name: str,
    bm: bmesh.types.BMesh,
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    parent_empty: bpy.types.Object | None = None,
) -> tuple[bpy.types.Object, dict]:
    """Validates manifold/normals/volume/tris, turns `bm` into a flat-shaded Blender Mesh object."""
    # Geometry integrity checks on source bmesh before writing Mesh data
    non_manifold = [e for e in bm.edges if not e.is_manifold or len(e.link_faces) != 2]
    assert not non_manifold, f"{obj_name} has {len(non_manifold)} non-manifold edges"
    degenerate_faces = [f for f in bm.faces if f.calc_area() <= 1e-6]
    assert not degenerate_faces, f"{obj_name} has {len(degenerate_faces)} zero-area faces"

    signed_volume = bm.calc_volume()
    assert signed_volume > 0.0, f"{obj_name} volume must be > 0 (inverted normals?), got {signed_volume}"

    mesh_data = bpy.data.meshes.new(f"StarSlime_{obj_name}_Mesh")
    bm.to_mesh(mesh_data)
    bm.free()

    for poly in mesh_data.polygons:
        poly.use_smooth = False
    mesh_data.calc_loop_triangles()
    tri_count = len(mesh_data.loop_triangles)

    mesh_data.materials.append(material)

    obj = bpy.data.objects.new(obj_name, mesh_data)
    obj.matrix_world = Matrix.Identity(4)
    obj.location = (0.0, 0.0, 0.0)
    obj.rotation_euler = (0.0, 0.0, 0.0)
    obj.scale = (1.0, 1.0, 1.0)
    obj.parent = parent_empty
    collection.objects.link(obj)

    xs = [v.co.x for v in mesh_data.vertices]
    ys = [v.co.y for v in mesh_data.vertices]
    zs = [v.co.z for v in mesh_data.vertices]
    stats = {
        "name": obj_name,
        "tris": tri_count,
        "volume": signed_volume,
        "min": (min(xs), min(ys), min(zs)),
        "max": (max(xs), max(ys), max(zs)),
    }
    return obj, stats


def export_starslime_sample() -> str:
    """Builds `Body`, `Eyes`, `Accent` at origin, validates budgets, and exports `StarSlime.fbx`."""
    allow_non_empty = "--force" in sys.argv
    collection = guard_and_prepare_scene(allow_non_empty)

    mat_body = create_material("Mat_StarSlime_Body", COLOR_BODY_SRGB, roughness=0.30)
    mat_eyes = create_material("Mat_StarSlime_Eyes", COLOR_EYES_SRGB, roughness=0.15)
    mat_accent = create_material("Mat_StarSlime_Accent", COLOR_ACCENT_SRGB, roughness=0.20, emission_strength=0.6)

    sub_specs = [
        ("Body", build_body_bmesh(), mat_body),
        ("Eyes", build_eyes_bmesh(), mat_eyes),
        ("Accent", build_accent_bmesh(), mat_accent),
    ]

    created_objects: list[bpy.types.Object] = []
    all_stats: list[dict] = []
    for name, bm, mat in sub_specs:
        obj, stats = finalize_mesh_object(name, bm, mat, collection)
        created_objects.append(obj)
        all_stats.append(stats)

    bpy.context.view_layer.update()

    total_tris = sum(s["tris"] for s in all_stats)
    min_x = min(s["min"][0] for s in all_stats)
    min_y = min(s["min"][1] for s in all_stats)
    min_z = min(s["min"][2] for s in all_stats)
    max_x = max(s["max"][0] for s in all_stats)
    max_y = max(s["max"][1] for s in all_stats)
    max_z = max(s["max"][2] for s in all_stats)
    width = max_x - min_x
    depth = max_y - min_y
    height = max_z - min_z

    assert total_tris <= TARGET_TRIS_MAX, f"Triangle count {total_tris} exceeds {TARGET_TRIS_MAX}"
    assert abs(min_z) < 1e-4, f"Ground-contact pivot check failed: min_z={min_z:.6f}"
    assert height <= MAX_HEIGHT_STUDS, f"Height {height:.3f} exceeds max {MAX_HEIGHT_STUDS}"
    assert width <= EXPECTED_AXIS_MAX_STUDS, f"Width {width:.3f} exceeds expected {EXPECTED_AXIS_MAX_STUDS}"
    assert depth <= EXPECTED_AXIS_MAX_STUDS, f"Depth {depth:.3f} exceeds expected {EXPECTED_AXIS_MAX_STUDS}"
    assert height <= EXPECTED_AXIS_MAX_STUDS, f"Height {height:.3f} exceeds expected {EXPECTED_AXIS_MAX_STUDS}"

    out_path = get_output_fbx_path()
    bpy.ops.object.select_all(action="DESELECT")
    for obj in created_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = created_objects[0]

    bpy.ops.export_scene.fbx(
        filepath=out_path,
        use_selection=True,
        global_scale=0.01,
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Z",
        axis_up="Y",
        bake_space_transform=True,
        use_mesh_modifiers=True,
        use_triangles=True,
        mesh_smooth_type="FACE",
        colors_type="SRGB",
        add_leaf_bones=False,
    )

    print("=== Starfall Ranch R-010 Sample Export Summary ===")
    for s in all_stats:
        dx = s["max"][0] - s["min"][0]
        dy = s["max"][1] - s["min"][1]
        dz = s["max"][2] - s["min"][2]
        print(
            f"  SubMesh={s['name']} | Tris={s['tris']} | Volume={s['volume']:.4f} "
            f"| Studs(W={dx:.3f}, D={dy:.3f}, H={dz:.3f}) | MinZ={s['min'][2]:.5f}"
        )
    print(
        f"  Combined | TotalTris={total_tris}/{TARGET_TRIS_MAX} | "
        f"Studs(W={width:.3f}, D={depth:.3f}, H={height:.3f}) | MinZ={min_z:.5f} | FileSizeBytes={os.path.getsize(out_path)}"
    )
    print(f"  ExportedPath={out_path}")
    return out_path


if __name__ == "__main__":
    export_starslime_sample()
