"""
Starfall Ranch: Procedural Low-Poly Asset Generator (Stage 4 / S4-01 / R-010)
Location: tools/blender/generate_lowpoly_assets.py

Generates and exports the complete 9-asset Stage 4 low-poly hero catalog:
- 6 Cosmic Critters (`tools/blender/exports/critters/<SpeciesId>.fbx`):
  StarSlime, CinderPup, FrostBeetle, NebulaFox, SolarGolem, CometOwl
- 3 Crater Meteors (`tools/blender/exports/meteors/<TraitId>.fbx`):
  Ember, Frost, Astral

Studio-Validated Coordinate & Export Convention (R-010 verified on Place1):
- 1 Blender unit = 1 Roblox stud.
- Blender Z-up (`+Z` up, `-Y` front -> Roblox `-Z` LookVector forward, `+Y` back -> `+Z`).
- All sub-meshes sit on `min_z = 0.0` with identity transforms `(0, 0, 0)` / `(1, 1, 1)`
  and export as flat top-level MeshParts (`Body`/`Eyes`/`Accent` for critters;
  `RockBody`/`CoreShards`/`TraitCrest` for meteors) so Studio Import 3D wraps each
  file in a single-level Model without double-nesting.
- Every asset strictly passes `<= 400` triangles, `<= 8.0` studs max height,
  positive closed-manifold volumes, and zero degenerate faces.

Safe Rerun Guard:
- When run interactively inside an existing Blender scene, refuses to delete user
  objects unless `--force` (or `ALLOW_DESTRUCTIVE_CLEAR = True`) is set.

Usage (CLI):
    blender --background --factory-startup --python tools/blender/generate_lowpoly_assets.py
"""

import json
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ALLOW_DESTRUCTIVE_CLEAR = False
TARGET_TRIS_MAX = 400
MAX_HEIGHT_STUDS = 8.0
DEFAULT_STARTUP_OBJECTS = frozenset({"Cube", "Camera", "Light"})
MANAGED_COLLECTIONS = ("SR_Critters", "SR_Meteors")

CRITTER_COLLECTIONS_ROW_Y = -6.0
METEOR_COLLECTIONS_ROW_Y = 6.0
SHOWCASE_SPACING_X = 7.0

COLOR_EYES_SRGB = (22, 20, 34)

CRITTER_PALETTES = {
    "StarSlime": {"body": (95, 225, 165), "accent": (255, 225, 95)},
    "CinderPup": {"body": (255, 125, 85), "accent": (255, 215, 90)},
    "FrostBeetle": {"body": (85, 205, 245), "accent": (185, 245, 255)},
    "NebulaFox": {"body": (165, 115, 255), "accent": (95, 220, 255)},
    "SolarGolem": {"body": (255, 175, 65), "accent": (255, 240, 145)},
    "CometOwl": {"body": (105, 85, 210), "accent": (255, 215, 85)},
}

METEOR_PALETTES = {
    "Ember": {"rock": (145, 85, 95), "core": (255, 145, 60), "trail": (255, 130, 65), "seed": 104},
    "Frost": {"rock": (95, 135, 185), "core": (125, 240, 255), "trail": (85, 220, 255), "seed": 204},
    "Astral": {"rock": (90, 75, 135), "core": (255, 210, 80), "trail": (215, 110, 255), "seed": 304},
}


def srgb_channel_to_linear(channel_01: float) -> float:
    """Converts a normalized sRGB channel (0..1) into linear RGB for Blender shaders."""
    if channel_01 <= 0.04045:
        return channel_01 / 12.92
    return ((channel_01 + 0.055) / 1.055) ** 2.4


def srgb255_to_linear_rgba(rgb: tuple[int, int, int]) -> tuple[float, float, float, float]:
    """Converts 0..255 sRGB tuple into linear RGBA tuple."""
    return (
        srgb_channel_to_linear(rgb[0] / 255.0),
        srgb_channel_to_linear(rgb[1] / 255.0),
        srgb_channel_to_linear(rgb[2] / 255.0),
        1.0,
    )


def get_export_roots() -> tuple[str, str, str]:
    """Resolves and creates `exports/critters`, `exports/meteors`, and `manifest.json` path."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    export_root = os.path.join(script_dir, "exports")
    critters_dir = os.path.join(export_root, "critters")
    meteors_dir = os.path.join(export_root, "meteors")
    os.makedirs(critters_dir, exist_ok=True)
    os.makedirs(meteors_dir, exist_ok=True)
    return critters_dir, meteors_dir, os.path.join(export_root, "manifest.json")


def is_managed_object_name(name: str) -> bool:
    """Identifies objects owned by previous runs of this generator."""
    if name.startswith("SR_"):
        return True
    return name in {"Body", "Eyes", "Accent", "RockBody", "CoreShards", "TraitCrest"}


def guard_and_prepare_scene(allow_force: bool, force_interactive_guard: bool = False) -> tuple[bpy.types.Collection, bpy.types.Collection]:
    """
    Safely prepares `SR_Critters` and `SR_Meteors` collections.
    Refuses destructive cleanup when non-default user objects or prior managed collections
    exist in interactive mode unless `--force` / `ALLOW_DESTRUCTIVE_CLEAR` is enabled.
    """
    interactive = force_interactive_guard or (not bpy.app.background)
    has_prior_collections = any(c in bpy.data.collections for c in MANAGED_COLLECTIONS)
    unexpected_objects = [
        obj.name
        for obj in bpy.data.objects
        if obj.name not in DEFAULT_STARTUP_OBJECTS and not is_managed_object_name(obj.name)
    ]

    if interactive and not allow_force and (unexpected_objects or has_prior_collections):
        details = []
        if unexpected_objects:
            details.append(f"scene objects: {', '.join(unexpected_objects[:5])}")
        if has_prior_collections:
            details.append("existing SR_Critters/SR_Meteors collections")
        raise RuntimeError(
            "Safety guard aborted destructive clear ("
            + "; ".join(details)
            + "). Open a clean .blend file or run with `--force` / `ALLOW_DESTRUCTIVE_CLEAR = True`."
        )

    for col_name in MANAGED_COLLECTIONS:
        if col_name in bpy.data.collections:
            col = bpy.data.collections[col_name]
            for obj in list(col.objects):
                bpy.data.objects.remove(obj, do_unlink=True)
            bpy.data.collections.remove(col)

    for obj in list(bpy.data.objects):
        if is_managed_object_name(obj.name):
            bpy.data.objects.remove(obj, do_unlink=True)
        elif bpy.app.background and not force_interactive_guard and obj.name in DEFAULT_STARTUP_OBJECTS:
            bpy.data.objects.remove(obj, do_unlink=True)

    for mesh in list(bpy.data.meshes):
        if mesh.users == 0 and (mesh.name.startswith("SR_") or mesh.name.startswith("Hero_")):
            bpy.data.meshes.remove(mesh)
    for mat in list(bpy.data.materials):
        if mat.users == 0 and mat.name.startswith("Mat_"):
            bpy.data.materials.remove(mat)

    critters_col = bpy.data.collections.new("SR_Critters")
    meteors_col = bpy.data.collections.new("SR_Meteors")
    bpy.context.scene.collection.children.link(critters_col)
    bpy.context.scene.collection.children.link(meteors_col)
    return critters_col, meteors_col


def create_material(
    mat_name: str,
    srgb_rgb: tuple[int, int, int],
    roughness: float,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    """Creates or replaces a flat low-poly Principled BSDF material."""
    existing = bpy.data.materials.get(mat_name)
    if existing is not None:
        bpy.data.materials.remove(existing)

    mat = bpy.data.materials.new(name=mat_name)
    if bpy.app.version < (5, 0, 0):
        mat.use_nodes = True

    rgba = srgb255_to_linear_rgba(srgb_rgb)
    bsdf = mat.node_tree.nodes.get("Principled BSDF") if mat.node_tree is not None else None
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Roughness"].default_value = roughness
        if "Emission Strength" in bsdf.inputs and emission_strength > 0.0:
            if "Emission Color" in bsdf.inputs:
                bsdf.inputs["Emission Color"].default_value = rgba
            bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def append_bmesh(target_bm: bmesh.types.BMesh, source_bm: bmesh.types.BMesh) -> list[bmesh.types.BMVert]:
    """Copies vertices and faces from `source_bm` into `target_bm` and returns created verts."""
    vert_map: dict[bmesh.types.BMVert, bmesh.types.BMVert] = {}
    new_verts: list[bmesh.types.BMVert] = []
    for src_vert in source_bm.verts:
        nv = target_bm.verts.new(src_vert.co)
        vert_map[src_vert] = nv
        new_verts.append(nv)
    for src_face in source_bm.faces:
        try:
            target_bm.faces.new([vert_map[v] for v in src_face.verts])
        except ValueError:
            pass
    return new_verts


def transform_bmesh(
    bm: bmesh.types.BMesh,
    center: tuple[float, float, float],
    euler_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> None:
    """Rotates around origin and translates `bm` vertices cleanly."""
    if any(angle != 0.0 for angle in euler_deg):
        rot_mat = Euler(tuple(math.radians(a) for a in euler_deg), "XYZ").to_matrix()
        bmesh.ops.rotate(bm, cent=Vector((0.0, 0.0, 0.0)), matrix=rot_mat, verts=list(bm.verts))
    if any(c != 0.0 for c in center):
        bmesh.ops.translate(bm, vec=Vector(center), verts=list(bm.verts))


def add_beveled_box(
    target_bm: bmesh.types.BMesh,
    size: tuple[float, float, float],
    center: tuple[float, float, float],
    bevel_offset: float = 0.0,
    bevel_segments: int = 0,
    euler_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
    snap_min_z: float | None = None,
) -> list[bmesh.types.BMVert]:
    """Adds a closed cube (optionally beveled) transformed into `target_bm`."""
    sub = bmesh.new()
    bmesh.ops.create_cube(sub, size=1.0)
    bmesh.ops.scale(sub, vec=Vector(size), verts=list(sub.verts))
    if bevel_segments > 0 and bevel_offset > 0.0:
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
    transform_bmesh(sub, center, euler_deg)
    if snap_min_z is not None:
        dz = snap_min_z - min(v.co.z for v in sub.verts)
        bmesh.ops.translate(sub, vec=Vector((0.0, 0.0, dz)), verts=list(sub.verts))
    bmesh.ops.recalc_face_normals(sub, faces=list(sub.faces))
    verts = append_bmesh(target_bm, sub)
    sub.free()
    return verts


def add_tapered_prism(
    target_bm: bmesh.types.BMesh,
    sides: int,
    radius_bottom: float,
    radius_top: float,
    height: float,
    center: tuple[float, float, float],
    euler_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
    scale_xy: tuple[float, float] = (1.0, 1.0),
    snap_min_z: float | None = None,
) -> list[bmesh.types.BMVert]:
    """Adds a closed N-sided tapered prism/limb (non-zero caps so zero degenerate tris)."""
    sub = bmesh.new()
    bmesh.ops.create_cone(
        sub,
        cap_ends=True,
        cap_tris=False,
        segments=sides,
        radius1=radius_bottom,
        radius2=max(0.02, radius_top),
        depth=height,
    )
    if scale_xy != (1.0, 1.0):
        bmesh.ops.scale(sub, vec=Vector((scale_xy[0], scale_xy[1], 1.0)), verts=list(sub.verts))
    transform_bmesh(sub, center, euler_deg)
    if snap_min_z is not None:
        dz = snap_min_z - min(v.co.z for v in sub.verts)
        bmesh.ops.translate(sub, vec=Vector((0.0, 0.0, dz)), verts=list(sub.verts))
    bmesh.ops.recalc_face_normals(sub, faces=list(sub.faces))
    verts = append_bmesh(target_bm, sub)
    sub.free()
    return verts


def add_crystal_shard(
    target_bm: bmesh.types.BMesh,
    radius: float,
    shaft_height: float,
    tip_height: float,
    base_center: tuple[float, float, float],
    euler_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
    sides: int = 6,
) -> list[bmesh.types.BMVert]:
    """Builds a closed hexagonal crystal prism tapering to a sharp crystal apex (22 tris for 6 sides)."""
    sub = bmesh.new()
    bottom_ring: list[bmesh.types.BMVert] = []
    shoulder_ring: list[bmesh.types.BMVert] = []
    for idx in range(sides):
        angle = idx * (2.0 * math.pi / sides)
        bx = math.cos(angle) * radius
        by = math.sin(angle) * radius
        sx = math.cos(angle) * (radius * 0.78)
        sy = math.sin(angle) * (radius * 0.78)
        bottom_ring.append(sub.verts.new((bx, by, 0.0)))
        shoulder_ring.append(sub.verts.new((sx, sy, shaft_height)))

    apex = sub.verts.new((0.0, 0.0, shaft_height + tip_height))
    sub.faces.new(list(reversed(bottom_ring)))
    for idx in range(sides):
        nxt = (idx + 1) % sides
        sub.faces.new((bottom_ring[idx], bottom_ring[nxt], shoulder_ring[nxt], shoulder_ring[idx]))
        sub.faces.new((shoulder_ring[idx], shoulder_ring[nxt], apex))

    transform_bmesh(sub, base_center, euler_deg)
    bmesh.ops.recalc_face_normals(sub, faces=list(sub.faces))
    verts = append_bmesh(target_bm, sub)
    sub.free()
    return verts


def add_eye_pair(
    target_bm: bmesh.types.BMesh,
    half_sep_x: float,
    pos_y: float,
    pos_z: float,
    radii: tuple[float, float, float],
    yaw_deg: float = 10.0,
) -> None:
    """Adds a symmetric left/right faceted icosphere eye pair facing `-Y` front (40 tris total)."""
    for side in (-1, 1):
        sub = bmesh.new()
        bmesh.ops.create_icosphere(sub, subdivisions=1, radius=1.0)
        bmesh.ops.scale(sub, vec=Vector(radii), verts=list(sub.verts))
        transform_bmesh(sub, (side * half_sep_x, pos_y, pos_z), (0.0, 0.0, -side * yaw_deg))
        bmesh.ops.recalc_face_normals(sub, faces=list(sub.faces))
        append_bmesh(target_bm, sub)
        sub.free()


def add_star_crest(
    target_bm: bmesh.types.BMesh,
    outer_r: float,
    inner_r: float,
    rim_half_depth: float,
    apex_half_depth: float,
    center: tuple[float, float, float],
    euler_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> None:
    """Adds a closed puffed 5-point low-poly star mesh (40 tris)."""
    sub = bmesh.new()
    front_ring: list[bmesh.types.BMVert] = []
    back_ring: list[bmesh.types.BMVert] = []
    for idx in range(10):
        angle = math.pi * 0.5 + idx * (2.0 * math.pi / 10)
        radius = outer_r if idx % 2 == 0 else inner_r
        px = math.cos(angle) * radius
        pz = math.sin(angle) * radius
        front_ring.append(sub.verts.new((px, -rim_half_depth, pz)))
        back_ring.append(sub.verts.new((px, rim_half_depth, pz)))

    front_apex = sub.verts.new((0.0, -apex_half_depth, 0.0))
    back_apex = sub.verts.new((0.0, apex_half_depth, 0.0))
    for idx in range(10):
        nxt = (idx + 1) % 10
        sub.faces.new((front_ring[idx], front_ring[nxt], front_apex))
        sub.faces.new((back_ring[nxt], back_ring[idx], back_apex))
        sub.faces.new((front_ring[nxt], front_ring[idx], back_ring[idx], back_ring[nxt]))

    transform_bmesh(sub, center, euler_deg)
    bmesh.ops.recalc_face_normals(sub, faces=list(sub.faces))
    append_bmesh(target_bm, sub)
    sub.free()


def add_orbiting_ring(
    target_bm: bmesh.types.BMesh,
    major_r: float,
    tube_rx: float,
    tube_rz: float,
    major_segments: int,
    minor_segments: int,
    center: tuple[float, float, float],
    euler_deg: tuple[float, float, float],
) -> None:
    """Builds a closed diamond-profile low-poly torus ring around `center`."""
    sub = bmesh.new()
    rings: list[list[bmesh.types.BMVert]] = []
    for i in range(major_segments):
        u = i * (2.0 * math.pi / major_segments)
        cu, su = math.cos(u), math.sin(u)
        ring: list[bmesh.types.BMVert] = []
        for j in range(minor_segments):
            v = j * (2.0 * math.pi / minor_segments)
            r = major_r + math.cos(v) * tube_rx
            z = math.sin(v) * tube_rz
            ring.append(sub.verts.new((r * cu, r * su, z)))
        rings.append(ring)

    for i in range(major_segments):
        ni = (i + 1) % major_segments
        for j in range(minor_segments):
            nj = (j + 1) % minor_segments
            sub.faces.new((rings[i][j], rings[ni][j], rings[ni][nj], rings[i][nj]))

    transform_bmesh(sub, center, euler_deg)
    bmesh.ops.recalc_face_normals(sub, faces=list(sub.faces))
    append_bmesh(target_bm, sub)
    sub.free()


def build_starslime() -> dict[str, bmesh.types.BMesh]:
    """StarSlime (~320 tris, 2.85 x 2.62 x 2.83 studs): jelly body + nubs + eyes + star crest."""
    body = bmesh.new()
    torso_verts = add_beveled_box(body, (2.32, 2.28, 2.08), (0.0, 0.0, 1.04), bevel_offset=0.28, bevel_segments=2, snap_min_z=0.0)
    for v in torso_verts:
        z_norm = max(0.0, min(1.0, v.co.z / 2.08))
        if z_norm > 0.65:
            taper = 1.0 - 0.14 * ((z_norm - 0.65) / 0.35)
            v.co.x *= taper
            v.co.y *= taper
        elif 0.12 <= z_norm <= 0.50:
            belly = 1.0 + 0.05 * math.sin(((z_norm - 0.12) / 0.38) * math.pi)
            v.co.x *= belly
            v.co.y *= belly

    for side in (-1, 1):
        add_beveled_box(body, (0.56, 0.70, 0.64), (side * 1.12, -0.04, 0.34), bevel_offset=0.14, bevel_segments=1, euler_deg=(0.0, side * 8.0, 0.0), snap_min_z=0.0)
    add_beveled_box(body, (0.56, 0.62, 0.52), (0.0, 1.06, 0.44), bevel_offset=0.13, bevel_segments=1, euler_deg=(-18.0, 0.0, 0.0))

    eyes = bmesh.new()
    add_eye_pair(eyes, half_sep_x=0.48, pos_y=-1.11, pos_z=1.08, radii=(0.21, 0.13, 0.27), yaw_deg=10.0)

    accent = bmesh.new()
    add_star_crest(accent, outer_r=0.56, inner_r=0.25, rim_half_depth=0.09, apex_half_depth=0.20, center=(0.0, -0.04, 2.26), euler_deg=(-14.0, 0.0, 0.0))

    return {"Body": body, "Eyes": eyes, "Accent": accent}


def build_cinderpup() -> dict[str, bmesh.types.BMesh]:
    """CinderPup (~290 tris, ~2.7 x 3.0 x 2.8 studs): chunky pup + snout + 4 paws + ember ears + flame tail."""
    body = bmesh.new()
    add_beveled_box(body, (1.76, 2.08, 1.32), (0.0, 0.18, 1.06), bevel_offset=0.20, bevel_segments=2)
    add_beveled_box(body, (1.84, 1.62, 1.36), (0.0, -0.62, 1.56), bevel_offset=0.20, bevel_segments=1)
    add_tapered_prism(body, sides=4, radius_bottom=0.58, radius_top=0.42, height=0.66, center=(0.0, -1.52, 1.30), euler_deg=(90.0, 0.0, 45.0), scale_xy=(1.2, 0.72))
    for px in (-0.58, 0.58):
        for py in (-0.65, 0.78):
            add_tapered_prism(body, sides=4, radius_bottom=0.30, radius_top=0.24, height=0.56, center=(px, py, 0.28), euler_deg=(0.0, 0.0, 45.0), scale_xy=(1.0, 1.15), snap_min_z=0.0)

    eyes = bmesh.new()
    add_eye_pair(eyes, half_sep_x=0.48, pos_y=-1.39, pos_z=1.74, radii=(0.20, 0.12, 0.24), yaw_deg=8.0)

    accent = bmesh.new()
    for side in (-1, 1):
        add_crystal_shard(accent, radius=0.28, shaft_height=0.35, tip_height=0.52, base_center=(side * 0.62, -0.58, 2.12), euler_deg=(12.0, side * 18.0, 0.0), sides=4)
    # Upright twin-faceted flame plume tail at +Y back
    add_beveled_box(accent, (0.56, 0.60, 0.74), (0.0, 1.18, 1.48), bevel_offset=0.10, bevel_segments=1, euler_deg=(-32.0, 0.0, 0.0))
    add_crystal_shard(accent, radius=0.32, shaft_height=0.42, tip_height=0.62, base_center=(0.0, 1.28, 1.68), euler_deg=(-22.0, 0.0, 0.0), sides=5)

    return {"Body": body, "Eyes": eyes, "Accent": accent}


def build_frostbeetle() -> dict[str, bmesh.types.BMesh]:
    """FrostBeetle (~302 tris, ~2.9 x 3.2 x 2.5 studs): domed shell + head shield + 4 legs + ice horn & wing crystals."""
    body = bmesh.new()
    shell_verts = add_beveled_box(body, (2.36, 2.56, 1.44), (0.0, 0.16, 1.04), bevel_offset=0.28, bevel_segments=2)
    for v in shell_verts:
        if v.co.z > 1.2:
            v.co.x *= 0.88
            v.co.y *= 0.90
    add_beveled_box(body, (1.42, 0.92, 0.88), (0.0, -1.06, 0.78), bevel_offset=0.14, bevel_segments=1)
    for px in (-1.10, 1.10):
        for py in (-0.48, 0.62):
            sign_x = -1.0 if px < 0 else 1.0
            add_tapered_prism(body, sides=4, radius_bottom=0.26, radius_top=0.20, height=0.68, center=(px, py, 0.34), euler_deg=(0.0, sign_x * 16.0, 45.0), snap_min_z=0.0)
    add_tapered_prism(body, sides=6, radius_bottom=0.52, radius_top=0.26, height=0.56, center=(0.0, 1.38, 0.72), euler_deg=(-72.0, 0.0, 0.0))

    eyes = bmesh.new()
    add_eye_pair(eyes, half_sep_x=0.45, pos_y=-1.48, pos_z=0.88, radii=(0.18, 0.12, 0.21), yaw_deg=12.0)

    accent = bmesh.new()
    # Forward-angled crystal rhino horn
    add_crystal_shard(accent, radius=0.28, shaft_height=0.56, tip_height=0.68, base_center=(0.0, -1.25, 1.05), euler_deg=(38.0, 0.0, 0.0), sides=6)
    # Flanking back crystal wing-spines
    for side in (-1, 1):
        add_crystal_shard(accent, radius=0.28, shaft_height=0.58, tip_height=0.56, base_center=(side * 0.72, 0.32, 1.48), euler_deg=(-36.0, side * 24.0, 0.0), sides=6)

    return {"Body": body, "Eyes": eyes, "Accent": accent}


def build_nebulafox() -> dict[str, bmesh.types.BMesh]:
    """NebulaFox (~342 tris, ~2.8 x 3.2 x 3.0 studs): chibi fox + snout + 4 paws + swept ears + comet tail."""
    body = bmesh.new()
    add_beveled_box(body, (1.62, 2.04, 1.30), (0.0, 0.18, 1.05), bevel_offset=0.20, bevel_segments=1)
    add_beveled_box(body, (1.92, 1.66, 1.40), (0.0, -0.58, 1.64), bevel_offset=0.24, bevel_segments=2)
    add_tapered_prism(body, sides=4, radius_bottom=0.58, radius_top=0.28, height=0.76, center=(0.0, -1.48, 1.38), euler_deg=(90.0, 0.0, 45.0), scale_xy=(1.1, 0.7))
    for px in (-0.54, 0.54):
        for py in (-0.64, 0.78):
            add_tapered_prism(body, sides=4, radius_bottom=0.26, radius_top=0.20, height=0.58, center=(px, py, 0.29), euler_deg=(0.0, 0.0, 45.0), snap_min_z=0.0)

    eyes = bmesh.new()
    add_eye_pair(eyes, half_sep_x=0.50, pos_y=-1.36, pos_z=1.78, radii=(0.19, 0.12, 0.24), yaw_deg=12.0)

    accent = bmesh.new()
    for side in (-1, 1):
        add_crystal_shard(accent, radius=0.30, shaft_height=0.45, tip_height=0.62, base_center=(side * 0.62, -0.45, 2.18), euler_deg=(-10.0, side * 18.0, 0.0), sides=4)
    # Iconic sweeping upward nebula comet tail
    add_beveled_box(accent, (0.76, 0.86, 0.96), (0.0, 1.24, 1.48), bevel_offset=0.14, bevel_segments=1, euler_deg=(-38.0, 0.0, 0.0))
    add_crystal_shard(accent, radius=0.40, shaft_height=0.54, tip_height=0.68, base_center=(0.0, 1.56, 1.88), euler_deg=(-18.0, 0.0, 0.0), sides=6)

    return {"Body": body, "Eyes": eyes, "Accent": accent}


def build_solargolem() -> dict[str, bmesh.types.BMesh]:
    """SolarGolem (~348 tris, ~3.8 x 3.4 x 4.6 studs): guardian torso + heavy arms + pillar legs + core + sun crown."""
    body = bmesh.new()
    add_beveled_box(body, (2.56, 2.18, 2.68), (0.0, 0.04, 2.52), bevel_offset=0.24, bevel_segments=2)
    for side in (-1, 1):
        add_beveled_box(body, (0.86, 1.04, 2.16), (side * 1.54, -0.04, 2.18), bevel_offset=0.14, bevel_segments=1, euler_deg=(0.0, side * 5.0, 0.0))
    for px in (-0.72, 0.72):
        add_tapered_prism(body, sides=4, radius_bottom=0.56, radius_top=0.48, height=1.32, center=(px, 0.04, 0.66), euler_deg=(0.0, 0.0, 45.0), snap_min_z=0.0)
    add_tapered_prism(body, sides=4, radius_bottom=0.48, radius_top=0.20, height=0.86, center=(0.0, 1.18, 1.48), euler_deg=(-55.0, 0.0, 45.0))

    eyes = bmesh.new()
    add_eye_pair(eyes, half_sep_x=0.62, pos_y=-1.08, pos_z=3.18, radii=(0.24, 0.13, 0.22), yaw_deg=6.0)

    accent = bmesh.new()
    # Front chest SolarCore faceted octa-diamond
    add_crystal_shard(accent, radius=0.56, shaft_height=0.22, tip_height=0.38, base_center=(0.0, -1.04, 2.18), euler_deg=(90.0, 0.0, 0.0), sides=4)
    # Sun Crown band + 3 solar crest spikes on head
    add_tapered_prism(accent, sides=6, radius_bottom=1.08, radius_top=1.18, height=0.36, center=(0.0, 0.02, 3.88))
    for side in (-1, 0, 1):
        height_scale = 0.74 if side == 0 else 0.56
        add_crystal_shard(accent, radius=0.24, shaft_height=height_scale * 0.6, tip_height=height_scale * 0.7, base_center=(side * 0.64, -0.06, 3.96), euler_deg=(-8.0, side * 16.0, 0.0), sides=4)

    return {"Body": body, "Eyes": eyes, "Accent": accent}


def build_cometowl() -> dict[str, bmesh.types.BMesh]:
    """CometOwl (~348 tris, ~3.4 x 3.0 x 3.9 studs): plump owl body + talons + tail fan + beak + wings + ear tufts."""
    body = bmesh.new()
    owl_verts = add_beveled_box(body, (2.28, 2.16, 2.76), (0.0, 0.06, 1.72), bevel_offset=0.28, bevel_segments=2)
    for v in owl_verts:
        z_norm = max(0.0, min(1.0, (v.co.z - 0.34) / 2.76))
        if z_norm > 0.70:
            taper = 1.0 - 0.12 * ((z_norm - 0.70) / 0.30)
            v.co.x *= taper
            v.co.y *= taper
    for side in (-1, 1):
        add_tapered_prism(body, sides=4, radius_bottom=0.40, radius_top=0.30, height=0.48, center=(side * 0.56, -0.14, 0.24), euler_deg=(0.0, 0.0, 45.0), scale_xy=(0.85, 1.25), snap_min_z=0.0)
    # Layered rear tail fan
    for side in (-1, 1):
        add_tapered_prism(body, sides=4, radius_bottom=0.42, radius_top=0.18, height=0.92, center=(side * 0.28, 1.18, 0.88), euler_deg=(-58.0, side * 14.0, 45.0), scale_xy=(0.9, 0.45))

    eyes = bmesh.new()
    add_eye_pair(eyes, half_sep_x=0.52, pos_y=-1.04, pos_z=2.36, radii=(0.30, 0.14, 0.32), yaw_deg=12.0)

    accent = bmesh.new()
    # Curved golden beak
    add_crystal_shard(accent, radius=0.24, shaft_height=0.18, tip_height=0.42, base_center=(0.0, -1.06, 2.08), euler_deg=(112.0, 0.0, 0.0), sides=4)
    # Sweeping cosmic wings
    for side in (-1, 1):
        add_beveled_box(accent, (0.52, 1.38, 1.72), (side * 1.24, 0.16, 1.66), bevel_offset=0.10, bevel_segments=1, euler_deg=(16.0, side * -18.0, side * 10.0))
        add_crystal_shard(accent, radius=0.24, shaft_height=0.42, tip_height=0.56, base_center=(side * 0.74, -0.12, 2.94), euler_deg=(10.0, side * 26.0, 0.0), sides=4)

    return {"Body": body, "Eyes": eyes, "Accent": accent}


def build_bisected_rock(seed: int, scale_xyz: tuple[float, float, float]) -> bmesh.types.BMesh:
    """Builds a seeded jagged low-poly boulder cleanly sliced flat at `Z = 0.0`."""
    rng = random.Random(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
    bmesh.ops.scale(bm, vec=Vector(scale_xyz), verts=list(bm.verts))

    for v in bm.verts:
        jitter = rng.uniform(0.84, 1.16)
        v.co.x *= jitter
        v.co.y *= jitter
        v.co.z *= rng.uniform(0.88, 1.12)

    cut_z = -scale_xyz[2] * 0.48
    bmesh.ops.bisect_plane(
        bm,
        geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
        dist=1e-4,
        plane_co=Vector((0.0, 0.0, cut_z)),
        plane_no=Vector((0.0, 0.0, 1.0)),
        clear_inner=True,
        clear_outer=False,
    )
    boundary_edges = [e for e in bm.edges if e.is_boundary]
    if boundary_edges:
        bmesh.ops.holes_fill(bm, edges=boundary_edges, sides=0)

    bmesh.ops.dissolve_degenerate(bm, dist=1e-4, edges=list(bm.edges))
    min_z = min(v.co.z for v in bm.verts)
    bmesh.ops.translate(bm, vec=Vector((0.0, 0.0, -min_z)), verts=list(bm.verts))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return bm


def build_meteor(trait_id: str, seed: int) -> dict[str, bmesh.types.BMesh]:
    """
    Generates one low-poly Crater Meteor (`RockBody`, `CoreShards`, `TraitCrest`)
    with embedded glowing crystal shards and color-independent silhouette.
    """
    is_astral = trait_id == "Astral"
    rock_scale = (2.45, 2.45, 2.20) if is_astral else (1.85, 1.85, 1.75)
    rock = build_bisected_rock(seed, rock_scale)
    rock_max_z = max(v.co.z for v in rock.verts)

    shards = bmesh.new()
    rng = random.Random(seed + 77)
    shard_count = 5 if is_astral else 4
    shard_ring_r = 1.42 if is_astral else 1.02
    for idx in range(shard_count):
        ang = idx * (2.0 * math.pi / shard_count) + rng.uniform(-0.2, 0.2)
        cx = math.cos(ang) * shard_ring_r
        cy = math.sin(ang) * shard_ring_r
        cz = rock_max_z * rng.uniform(0.55, 0.72)
        tilt_x = math.degrees(math.sin(ang) * 0.58)
        tilt_y = math.degrees(-math.cos(ang) * 0.58)
        r = rng.uniform(0.32, 0.44) if is_astral else rng.uniform(0.26, 0.36)
        shaft = rng.uniform(0.85, 1.25) if is_astral else rng.uniform(0.65, 1.00)
        tip = rng.uniform(0.50, 0.78)
        add_crystal_shard(shards, radius=r, shaft_height=shaft, tip_height=tip, base_center=(cx, cy, cz), euler_deg=(tilt_x, tilt_y, math.degrees(ang)), sides=6)

    crest = bmesh.new()
    if trait_id == "Ember":
        # Twin flame-horn crests flanking top ridge
        for side in (-1, 1):
            add_crystal_shard(crest, radius=0.40, shaft_height=0.95, tip_height=0.85, base_center=(side * 0.92, 0.0, rock_max_z * 0.68), euler_deg=(-10.0, side * 24.0, 0.0), sides=4)
            add_crystal_shard(crest, radius=0.26, shaft_height=0.60, tip_height=0.65, base_center=(side * 1.18, -0.35, rock_max_z * 0.52), euler_deg=(18.0, side * 36.0, 0.0), sides=4)
    elif trait_id == "Frost":
        # Crown spike + 3 jagged radial ice-crystal spikes
        add_crystal_shard(crest, radius=0.42, shaft_height=1.15, tip_height=0.95, base_center=(0.0, 0.0, rock_max_z * 0.72), euler_deg=(4.0, -6.0, 0.0), sides=6)
        for idx in range(3):
            ang = math.radians(idx * 120.0 + 30.0)
            add_crystal_shard(crest, radius=0.30, shaft_height=0.90, tip_height=0.75, base_center=(math.cos(ang) * 1.08, math.sin(ang) * 1.08, rock_max_z * 0.60), euler_deg=(math.sin(ang) * 28.0, -math.cos(ang) * 28.0, 0.0), sides=6)
    else:
        # Astral: tilted orbiting low-poly diamond star-ring + 4 cardinal star nodes
        ring_center = (0.0, 0.0, rock_max_z * 0.60)
        ring_euler = (16.0, -10.0, 0.0)
        add_orbiting_ring(crest, major_r=2.95, tube_rx=0.22, tube_rz=0.16, major_segments=16, minor_segments=4, center=ring_center, euler_deg=ring_euler)
        rot_m = Euler(tuple(math.radians(a) for a in ring_euler), "XYZ").to_matrix()
        for idx in range(4):
            ang = idx * (math.pi * 0.5)
            local_pt = Vector((math.cos(ang) * 2.95, math.sin(ang) * 2.95, -0.22))
            world_pt = Vector(ring_center) + (rot_m @ local_pt)
            add_crystal_shard(crest, radius=0.24, shaft_height=0.22, tip_height=0.26, base_center=(world_pt.x, world_pt.y, world_pt.z), euler_deg=ring_euler, sides=4)

    return {"RockBody": rock, "CoreShards": shards, "TraitCrest": crest}


def finalize_and_validate_submeshes(
    asset_name: str,
    prefix: str,
    bm_by_name: dict[str, bmesh.types.BMesh],
    mat_by_name: dict[str, bpy.types.Material],
    collection: bpy.types.Collection,
) -> tuple[list[bpy.types.Object], list[dict], dict]:
    """Validates manifold/volume/budgets, exports clean flat Blender meshes, and returns metrics."""
    created_objs: list[bpy.types.Object] = []
    sub_stats: list[dict] = []

    for sub_name, bm in bm_by_name.items():
        non_manifold = [e for e in bm.edges if not e.is_manifold or len(e.link_faces) != 2]
        assert not non_manifold, f"{asset_name}.{sub_name} has {len(non_manifold)} non-manifold edges"
        degenerate = [f for f in bm.faces if f.calc_area() <= 1e-6]
        assert not degenerate, f"{asset_name}.{sub_name} has {len(degenerate)} degenerate faces"
        vol = bm.calc_volume()
        assert vol > 0.0, f"{asset_name}.{sub_name} volume <= 0 ({vol}); inverted normals?"

        mesh_data = bpy.data.meshes.new(f"Hero_{prefix}_{asset_name}_{sub_name}_Mesh")
        bm.to_mesh(mesh_data)
        bm.free()

        for poly in mesh_data.polygons:
            poly.use_smooth = False
        mesh_data.calc_loop_triangles()
        tris = len(mesh_data.loop_triangles)
        mesh_data.materials.append(mat_by_name[sub_name])

        # Exact Studio sub-mesh name (`Body`/`Eyes`/`Accent` or `RockBody`/`CoreShards`/`TraitCrest`)
        obj = bpy.data.objects.new(sub_name, mesh_data)
        obj.matrix_world = Matrix.Identity(4)
        obj.location = (0.0, 0.0, 0.0)
        obj.rotation_euler = (0.0, 0.0, 0.0)
        obj.scale = (1.0, 1.0, 1.0)
        collection.objects.link(obj)
        created_objs.append(obj)

        xs = [v.co.x for v in mesh_data.vertices]
        ys = [v.co.y for v in mesh_data.vertices]
        zs = [v.co.z for v in mesh_data.vertices]
        sub_stats.append({
            "name": sub_name,
            "tris": tris,
            "volume": round(vol, 4),
            "min": (min(xs), min(ys), min(zs)),
            "max": (max(xs), max(ys), max(zs)),
        })

    bpy.context.view_layer.update()

    total_tris = sum(s["tris"] for s in sub_stats)
    min_x = min(s["min"][0] for s in sub_stats)
    min_y = min(s["min"][1] for s in sub_stats)
    min_z = min(s["min"][2] for s in sub_stats)
    max_x = max(s["max"][0] for s in sub_stats)
    max_y = max(s["max"][1] for s in sub_stats)
    max_z = max(s["max"][2] for s in sub_stats)
    width, depth, height = max_x - min_x, max_y - min_y, max_z - min_z

    assert total_tris <= TARGET_TRIS_MAX, f"{asset_name} total tris {total_tris} > {TARGET_TRIS_MAX}"
    assert abs(min_z) < 1e-4, f"{asset_name} min_z={min_z:.6f} (must sit on Z=0.0)"
    assert height <= MAX_HEIGHT_STUDS, f"{asset_name} height {height:.3f} > {MAX_HEIGHT_STUDS}"

    summary = {
        "name": asset_name,
        "category": prefix,
        "total_tris": total_tris,
        "sub_tris": {s["name"]: s["tris"] for s in sub_stats},
        "studs_wdh": [round(width, 3), round(depth, 3), round(height, 3)],
        "min_z": round(min_z, 5),
        "volumes": {s["name"]: s["volume"] for s in sub_stats},
    }
    return created_objs, sub_stats, summary


def export_selected_fbx(objs: list[bpy.types.Object], out_path: str) -> int:
    """Exports flat top-level sub-meshes using the Place1-validated Roblox FBX settings."""
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]

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
    return os.path.getsize(out_path)


def stage_in_viewport_row(objs: list[bpy.types.Object], prefix: str, asset_name: str, row_idx: int, total_count: int, row_y: float) -> None:
    """Renames exported objects uniquely and positions them neatly in a Blender showcase row."""
    offset_x = (row_idx - (total_count - 1) * 0.5) * SHOWCASE_SPACING_X
    for obj in objs:
        obj.name = f"SR_{prefix}_{asset_name}_{obj.name}"
        obj.location = (offset_x, row_y, 0.0)


def generate_catalog(allow_force: bool = False) -> list[dict]:
    """Builds, validates, exports, and logs all 6 hero critters + 3 crater meteors."""
    critters_col, meteors_col = guard_and_prepare_scene(allow_force)
    critters_dir, meteors_dir, manifest_path = get_export_roots()

    critter_builders = {
        "StarSlime": build_starslime,
        "CinderPup": build_cinderpup,
        "FrostBeetle": build_frostbeetle,
        "NebulaFox": build_nebulafox,
        "SolarGolem": build_solargolem,
        "CometOwl": build_cometowl,
    }

    manifest_entries: list[dict] = []
    critter_names = list(critter_builders.keys())
    for idx, species_id in enumerate(critter_names):
        pal = CRITTER_PALETTES[species_id]
        mats = {
            "Body": create_material(f"Mat_{species_id}_Body", pal["body"], roughness=0.30),
            "Eyes": create_material(f"Mat_{species_id}_Eyes", COLOR_EYES_SRGB, roughness=0.15),
            "Accent": create_material(f"Mat_{species_id}_Accent", pal["accent"], roughness=0.22, emission_strength=0.45),
        }
        bms = critter_builders[species_id]()
        objs, _sub_stats, summary = finalize_and_validate_submeshes(species_id, "Critter", bms, mats, critters_col)
        out_path = os.path.join(critters_dir, f"{species_id}.fbx")
        summary["file_bytes"] = export_selected_fbx(objs, out_path)
        summary["fbx_rel_path"] = os.path.relpath(out_path, os.path.dirname(manifest_path)).replace("\\", "/")
        manifest_entries.append(summary)
        stage_in_viewport_row(objs, "Critter", species_id, idx, len(critter_names), CRITTER_COLLECTIONS_ROW_Y)

    meteor_names = list(METEOR_PALETTES.keys())
    for idx, trait_id in enumerate(meteor_names):
        pal = METEOR_PALETTES[trait_id]
        mats = {
            "RockBody": create_material(f"Mat_{trait_id}_Rock", pal["rock"], roughness=0.80),
            "CoreShards": create_material(f"Mat_{trait_id}_Core", pal["core"], roughness=0.20, emission_strength=0.55),
            "TraitCrest": create_material(f"Mat_{trait_id}_Trail", pal["trail"], roughness=0.25, emission_strength=0.50),
        }
        bms = build_meteor(trait_id, pal["seed"])
        objs, _sub_stats, summary = finalize_and_validate_submeshes(trait_id, "Meteor", bms, mats, meteors_col)
        out_path = os.path.join(meteors_dir, f"{trait_id}.fbx")
        summary["file_bytes"] = export_selected_fbx(objs, out_path)
        summary["fbx_rel_path"] = os.path.relpath(out_path, os.path.dirname(manifest_path)).replace("\\", "/")
        manifest_entries.append(summary)
        stage_in_viewport_row(objs, "Meteor", trait_id, idx, len(meteor_names), METEOR_COLLECTIONS_ROW_Y)

    with open(manifest_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump({"assets": manifest_entries}, f, indent=2)
        f.write("\n")

    print("=== Starfall Ranch S4-01 Hero Catalog Export Summary ===")
    for entry in manifest_entries:
        w, d, h = entry["studs_wdh"]
        print(
            f"  [{entry['category']:7s}] {entry['name']:12s} | Tris={entry['total_tris']:3d}/{TARGET_TRIS_MAX} "
            f"{entry['sub_tris']} | Studs=(W={w:.3f}, D={d:.3f}, H={h:.3f}) "
            f"| MinZ={entry['min_z']:.5f} | Bytes={entry['file_bytes']} | File={entry['fbx_rel_path']}"
        )
    print(f"Exported {len(manifest_entries)} assets cleanly. Manifest={manifest_path}")
    return manifest_entries


if __name__ == "__main__":
    generate_catalog(allow_force=ALLOW_DESTRUCTIVE_CLEAR or ("--force" in sys.argv))
