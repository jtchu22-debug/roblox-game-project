"""
Starfall Ranch: Procedural Low-Poly Asset Generator (Stage 4 Art Revision)
Location: tools/blender/generate_lowpoly_assets.py

Generates and exports the complete 9-asset Stage 4 hero catalog:
- 6 Soft-Stylized Cosmic Critters (`tools/blender/exports/critters/<SpeciesId>.fbx`):
  StarSlime, CinderPup, FrostBeetle, NebulaFox, SolarGolem, CometOwl
  Each exports as 4 flat top-level MeshParts (`Body`, `Secondary`, `Eyes`, `Accent`)
  with sculpted silhouettes, expressive faces + eye catchlights, and `<= 400` tris.
- 3 Angular Crater Meteors (`tools/blender/exports/meteors/<TraitId>.fbx`):
  Ember, Frost, Astral
  Each retains angular faceted rock geometry with embedded crystal shards and
  color-independent silhouettes (`RockBody`, `CoreShards`, `TraitCrest`, `<= 400` tris).

Studio-Validated Coordinate & Export Convention:
- 1 Blender unit = 1 Roblox stud.
- Blender Z-up (`+Z` up, `-Y` front -> Roblox `-Z` LookVector forward, `+Y` back -> `+Z`).
- Ground-contact pivot (`min_z = 0.0` across combined sub-meshes), `height <= 8.0` studs.
- `global_scale=0.01`, `apply_unit_scale=True`, `apply_scale_options="FBX_SCALE_ALL"`,
  `axis_forward="-Z"`, `axis_up="Y"`, `bake_space_transform=True`.

Safe Rerun Guard:
- Interactive sessions refuse to delete user objects or existing collections unless
  `--force` (or `ALLOW_DESTRUCTIVE_CLEAR = True`) is passed.

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
    "StarSlime": {"body": (95, 225, 165), "secondary": (42, 152, 116), "accent": (255, 225, 95)},
    "CinderPup": {"body": (255, 125, 85), "secondary": (245, 228, 204), "accent": (255, 215, 90)},
    "FrostBeetle": {"body": (85, 205, 245), "secondary": (42, 108, 170), "accent": (185, 245, 255)},
    "NebulaFox": {"body": (165, 115, 255), "secondary": (236, 228, 250), "accent": (95, 220, 255)},
    "SolarGolem": {"body": (255, 175, 65), "secondary": (168, 100, 44), "accent": (255, 240, 145)},
    "CometOwl": {"body": (105, 85, 210), "secondary": (228, 220, 246), "accent": (255, 215, 85)},
}

METEOR_PALETTES = {
    "Ember": {"rock": (145, 85, 95), "core": (255, 145, 60), "trail": (255, 130, 65), "seed": 104},
    "Frost": {"rock": (95, 135, 185), "core": (125, 240, 255), "trail": (85, 220, 255), "seed": 204},
    "Astral": {"rock": (90, 75, 135), "core": (255, 210, 80), "trail": (215, 110, 255), "seed": 304},
}


def srgb_channel_to_linear(channel_01: float) -> float:
    """Converts normalized sRGB (0..1) to linear RGB for Blender materials."""
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
    return name in {"Body", "Secondary", "Eyes", "Accent", "RockBody", "CoreShards", "TraitCrest"}


def guard_and_prepare_scene(
    allow_force: bool,
    force_interactive_guard: bool = False,
) -> tuple[bpy.types.Collection, bpy.types.Collection]:
    """
    Safely prepares `SR_Critters` and `SR_Meteors` collections.
    Refuses destructive clear in interactive sessions unless `--force` is passed.
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
    """Creates or replaces a Principled BSDF material without Blender 5/6 warnings."""
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
    """Copies vertices and faces from `source_bm` into `target_bm` cleanly."""
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
    """Rotates around origin and translates `bm` vertices."""
    if any(angle != 0.0 for angle in euler_deg):
        rot_mat = Euler(tuple(math.radians(a) for a in euler_deg), "XYZ").to_matrix()
        bmesh.ops.rotate(bm, cent=Vector((0.0, 0.0, 0.0)), matrix=rot_mat, verts=list(bm.verts))
    if any(c != 0.0 for c in center):
        bmesh.ops.translate(bm, vec=Vector(center), verts=list(bm.verts))


def add_lathe_shape(
    target_bm: bmesh.types.BMesh,
    radial_segments: int,
    rings_spec: list[tuple[float, float, float, float, float, float]],
    bottom_cap_z: float | None,
    top_cap_z: float | None,
    center: tuple[float, float, float] = (0.0, 0.0, 0.0),
    euler_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
    snap_min_z: float | None = None,
) -> None:
    """
    Builds a closed manifold sculpted lathe form from ring descriptors
    `(z, rx, ry, y_shift, a2_cos2theta, b1_sintheta)` with optional flat/domed apex caps.
    """
    sub = bmesh.new()
    rings: list[list[bmesh.types.BMVert]] = []
    for z, rx, ry, y_shift, a2, b1 in rings_spec:
        ring: list[bmesh.types.BMVert] = []
        for k in range(radial_segments):
            theta = k * (2.0 * math.pi / radial_segments)
            mod = 1.0 + a2 * math.cos(2.0 * theta) + b1 * math.sin(theta)
            ring.append(sub.verts.new((rx * mod * math.cos(theta), ry * mod * math.sin(theta) + y_shift, z)))
        rings.append(ring)

    if bottom_cap_z is not None:
        b_center = sub.verts.new((0.0, rings_spec[0][3], bottom_cap_z))
        for k in range(radial_segments):
            nk = (k + 1) % radial_segments
            sub.faces.new((b_center, rings[0][nk], rings[0][k]))
    else:
        sub.faces.new(list(reversed(rings[0])))

    for r_idx in range(len(rings) - 1):
        for k in range(radial_segments):
            nk = (k + 1) % radial_segments
            sub.faces.new((rings[r_idx][k], rings[r_idx][nk], rings[r_idx + 1][nk], rings[r_idx + 1][k]))

    if top_cap_z is not None:
        t_center = sub.verts.new((0.0, rings_spec[-1][3], top_cap_z))
        top_r = rings[-1]
        for k in range(radial_segments):
            nk = (k + 1) % radial_segments
            sub.faces.new((top_r[k], top_r[nk], t_center))
    else:
        sub.faces.new(rings[-1])

    transform_bmesh(sub, center, euler_deg)
    if snap_min_z is not None:
        dz = snap_min_z - min(v.co.z for v in sub.verts)
        bmesh.ops.translate(sub, vec=Vector((0.0, 0.0, dz)), verts=list(sub.verts))
    bmesh.ops.recalc_face_normals(sub, faces=list(sub.faces))
    append_bmesh(target_bm, sub)
    sub.free()


def add_rounded_ellipsoid(
    target_bm: bmesh.types.BMesh,
    radial_segments: int,
    radii: tuple[float, float, float],
    center: tuple[float, float, float],
    euler_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
    ring_count: int = 3,
    taper_front_y: float = 0.0,
    snap_min_z: float | None = None,
) -> None:
    """
    Builds a smooth low-poly ellipsoid/capsule (`ring_count=2` or `3`) with optional
    `-Y` forward face tapering (ideal for foxes, heads, snouts, muzzles, and paws).
    """
    rx, ry, rz = radii
    if ring_count == 2:
        levels = [(-0.52, 0.84), (0.52, 0.84)]
    elif ring_count == 3:
        levels = [(-0.72, 0.68), (0.0, 1.0), (0.72, 0.68)]
    else:
        levels = [(-0.80, 0.56), (-0.30, 0.94), (0.30, 0.94), (0.80, 0.56)]

    rings_spec: list[tuple[float, float, float, float, float, float]] = []
    for z_frac, rad_scale in levels:
        rings_spec.append((z_frac * rz, rx * rad_scale, ry * rad_scale, 0.0, 0.0, 0.0))

    sub = bmesh.new()
    add_lathe_shape(sub, radial_segments, rings_spec, bottom_cap_z=-rz, top_cap_z=rz)
    if taper_front_y > 0.0:
        for v in sub.verts:
            if v.co.y < 0.0:
                t = max(0.0, min(1.0, -v.co.y / max(1e-4, ry)))
                shrink = 1.0 - taper_front_y * t
                v.co.x *= shrink
                v.co.z *= 1.0 - (taper_front_y * 0.55) * t

    transform_bmesh(sub, center, euler_deg)
    if snap_min_z is not None:
        dz = snap_min_z - min(v.co.z for v in sub.verts)
        bmesh.ops.translate(sub, vec=Vector((0.0, 0.0, dz)), verts=list(sub.verts))
    bmesh.ops.recalc_face_normals(sub, faces=list(sub.faces))
    append_bmesh(target_bm, sub)
    sub.free()


def add_curved_tube(
    target_bm: bmesh.types.BMesh,
    points_and_radii: list[tuple[tuple[float, float, float], float]],
    sides: int = 4,
    capped_tips: bool = True,
) -> None:
    """Sweeps a closed manifold low-poly tube along arbitrary 3D points & radii."""
    sub = bmesh.new()
    rings: list[list[bmesh.types.BMVert]] = []
    pts = [Vector(p) for p, _ in points_and_radii]

    prev_up = Vector((0.0, 0.0, 1.0))
    for idx, (_raw_pt, radius) in enumerate(points_and_radii):
        pt = pts[idx]
        if idx == 0:
            tangent = (pts[1] - pts[0]).normalized()
        elif idx == len(pts) - 1:
            tangent = (pts[-1] - pts[-2]).normalized()
        else:
            tangent = (pts[idx + 1] - pts[idx - 1]).normalized()

        ref = prev_up if abs(tangent.dot(prev_up)) < 0.92 else Vector((0.0, -1.0, 0.0))
        right = tangent.cross(ref).normalized()
        up = right.cross(tangent).normalized()
        prev_up = up

        ring: list[bmesh.types.BMVert] = []
        for k in range(sides):
            ang = k * (2.0 * math.pi / sides)
            ring.append(sub.verts.new(pt + (right * math.cos(ang) + up * math.sin(ang)) * radius))
        rings.append(ring)

    if capped_tips:
        sub.faces.new(list(reversed(rings[0])))
        sub.faces.new(rings[-1])
    else:
        start_tip = sub.verts.new(pts[0] - (pts[1] - pts[0]).normalized() * (points_and_radii[0][1] * 0.5))
        end_tip = sub.verts.new(pts[-1] + (pts[-1] - pts[-2]).normalized() * (points_and_radii[-1][1] * 0.7))
        for k in range(sides):
            nk = (k + 1) % sides
            sub.faces.new((start_tip, rings[0][nk], rings[0][k]))
            sub.faces.new((rings[-1][k], rings[-1][nk], end_tip))

    for i in range(len(rings) - 1):
        for k in range(sides):
            nk = (k + 1) % sides
            sub.faces.new((rings[i][k], rings[i][nk], rings[i + 1][nk], rings[i + 1][k]))

    bmesh.ops.recalc_face_normals(sub, faces=list(sub.faces))
    append_bmesh(target_bm, sub)
    sub.free()


def add_eye_pair_with_catchlights(
    eyes_bm: bmesh.types.BMesh,
    accent_bm: bmesh.types.BMesh,
    half_sep_x: float,
    pos_y: float,
    pos_z: float,
    radii: tuple[float, float, float],
    pitch_x_deg: float,
    yaw_z_deg: float,
    radial_segs: int = 8,
    catch_scale: float = 1.0,
) -> None:
    """
    Adds a symmetric pair of curved oval eyes facing `-Y` front plus nestled glowing
    upper-left octahedron eye-shine catchlights (`16` tris in `accent_bm`).
    """
    rx, ry, rz = radii
    for side in (-1, 1):
        # Eye lens oriented with polar axis along Y so radial_segs form the front XZ oval
        sub = bmesh.new()
        y_rings = [(-0.35, 0.88), (0.35, 0.88)]
        front_pole = sub.verts.new((0.0, -ry, 0.0))
        rings: list[list[bmesh.types.BMVert]] = []
        for y_frac, rad_scale in y_rings:
            ring: list[bmesh.types.BMVert] = []
            vy = y_frac * ry
            for k in range(radial_segs):
                ang = k * (2.0 * math.pi / radial_segs)
                ring.append(sub.verts.new((math.cos(ang) * rx * rad_scale, vy, math.sin(ang) * rz * rad_scale)))
            rings.append(ring)
        back_pole = sub.verts.new((0.0, ry, 0.0))

        for k in range(radial_segs):
            nk = (k + 1) % radial_segs
            sub.faces.new((front_pole, rings[0][k], rings[0][nk]))
            sub.faces.new((rings[-1][nk], rings[-1][k], back_pole))
        for r_idx in range(len(rings) - 1):
            for k in range(radial_segs):
                nk = (k + 1) % radial_segs
                sub.faces.new((rings[r_idx][k], rings[r_idx + 1][k], rings[r_idx + 1][nk], rings[r_idx][nk]))

        rot_mat = Euler((math.radians(pitch_x_deg), 0.0, math.radians(side * yaw_z_deg)), "XYZ").to_matrix()
        bmesh.ops.rotate(sub, cent=Vector((0.0, 0.0, 0.0)), matrix=rot_mat, verts=list(sub.verts))
        bmesh.ops.translate(sub, vec=Vector((side * half_sep_x, pos_y, pos_z)), verts=list(sub.verts))
        bmesh.ops.recalc_face_normals(sub, faces=list(sub.faces))
        append_bmesh(eyes_bm, sub)
        sub.free()

        # Nestled upper-left glowing starry catchlight octahedron
        gem = bmesh.new()
        grx, gry, grz = 0.068 * catch_scale, 0.048 * catch_scale, 0.076 * catch_scale
        gv = [
            gem.verts.new((-grx, 0.0, 0.0)),
            gem.verts.new((0.0, -gry, 0.0)),
            gem.verts.new((grx, 0.0, 0.0)),
            gem.verts.new((0.0, gry, 0.0)),
        ]
        gtop = gem.verts.new((0.0, 0.0, grz))
        gbot = gem.verts.new((0.0, 0.0, -grz))
        for k in range(4):
            nk = (k + 1) % 4
            gem.faces.new((gv[k], gv[nk], gtop))
            gem.faces.new((gv[nk], gv[k], gbot))
        local_offset = Vector((-rx * 0.30, -ry * 0.90, rz * 0.36))
        bmesh.ops.translate(gem, vec=local_offset, verts=list(gem.verts))
        bmesh.ops.rotate(gem, cent=Vector((0.0, 0.0, 0.0)), matrix=rot_mat, verts=list(gem.verts))
        bmesh.ops.translate(gem, vec=Vector((side * half_sep_x, pos_y, pos_z)), verts=list(gem.verts))
        bmesh.ops.recalc_face_normals(gem, faces=list(gem.faces))
        append_bmesh(accent_bm, gem)
        gem.free()


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


def add_beveled_box(
    target_bm: bmesh.types.BMesh,
    size: tuple[float, float, float],
    center: tuple[float, float, float],
    bevel_offset: float = 0.0,
    bevel_segments: int = 0,
    euler_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
    snap_min_z: float | None = None,
) -> list[bmesh.types.BMVert]:
    """Adds a closed beveled block (kept for SolarGolem stone character & angular trims)."""
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


def add_crystal_shard(
    target_bm: bmesh.types.BMesh,
    radius: float,
    shaft_height: float,
    tip_height: float,
    base_center: tuple[float, float, float],
    euler_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
    sides: int = 6,
) -> list[bmesh.types.BMVert]:
    """Builds a closed faceted crystal prism tapering to a sharp apex (retained for angular meteors)."""
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
    """Builds a closed diamond-profile torus ring around `center` (for Astral meteor)."""
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
    """
    StarSlime (soft squishy dome + darker emerald-mint lower base contrast, <= 400 tris):
    - Secondary (`84` tris): wide flattened base puddle skirt (`Z = 0.00..0.58`)
    - Body (`140` tris): soft rounded upper dome (`Z = 0.58..2.12`)
    - Eyes (`108` tris): large 10-sided oval eyes + cute U-smile above seam
    - Accent (`56` tris): 5-point star crest + twin starry eye catchlights
    """
    radial = 14
    lower_rings = [
        (0.00, 1.46, 1.38, 0.03, 0.045, 0.035),
        (0.24, 1.56, 1.48, 0.04, 0.040, 0.030),
        (0.58, 1.47, 1.40, 0.03, 0.025, 0.020),
    ]
    upper_rings = [
        (0.58, 1.47, 1.40, 0.03, 0.025, 0.020),
        (1.00, 1.28, 1.24, 0.01, 0.010, 0.010),
        (1.42, 1.01, 0.98, 0.00, 0.000, 0.000),
        (1.78, 0.64, 0.62, 0.00, 0.000, 0.000),
        (2.02, 0.28, 0.27, 0.00, 0.000, 0.000),
    ]

    secondary = bmesh.new()
    add_lathe_shape(secondary, radial, lower_rings, bottom_cap_z=0.0, top_cap_z=0.58)

    body = bmesh.new()
    add_lathe_shape(body, radial, upper_rings, bottom_cap_z=0.58, top_cap_z=2.12)

    eyes = bmesh.new()
    accent = bmesh.new()
    add_eye_pair_with_catchlights(
        eyes,
        accent,
        half_sep_x=0.50,
        pos_y=-1.15,
        pos_z=1.00,
        radii=(0.27, 0.14, 0.37),
        pitch_x_deg=-20.0,
        yaw_z_deg=20.0,
        radial_segs=10,
        catch_scale=1.05,
    )
    add_curved_tube(
        eyes,
        [
            ((-0.24, -1.34, 0.75), 0.046),
            ((-0.09, -1.36, 0.67), 0.048),
            ((0.09, -1.36, 0.67), 0.048),
            ((0.24, -1.34, 0.75), 0.046),
        ],
        sides=4,
        capped_tips=True,
    )
    add_star_crest(accent, outer_r=0.58, inner_r=0.28, rim_half_depth=0.10, apex_half_depth=0.22, center=(0.0, -0.02, 2.30), euler_deg=(-12.0, 0.0, 0.0))

    return {"Body": body, "Secondary": secondary, "Eyes": eyes, "Accent": accent}


def build_cinderpup() -> dict[str, bmesh.types.BMesh]:
    """
    CinderPup (<= 400 tris: softly rounded puppy torso/head, broad warm-cream muzzle,
    4 chunky paws, twin ember ears & upright curved flame-plume tail):
    """
    body = bmesh.new()
    add_rounded_ellipsoid(body, radial_segments=8, radii=(0.90, 1.12, 0.70), center=(0.0, 0.24, 1.06), ring_count=3)
    add_rounded_ellipsoid(body, radial_segments=8, radii=(0.94, 0.86, 0.76), center=(0.0, -0.62, 1.56), ring_count=3)

    secondary = bmesh.new()
    # Broad plush rounded cream muzzle
    add_rounded_ellipsoid(secondary, radial_segments=8, radii=(0.58, 0.44, 0.34), center=(0.0, -1.28, 1.32), ring_count=2)
    # Four chunky rounded puppy paws flat on Z = 0.0
    for px in (-0.54, 0.54):
        for py in (-0.58, 0.84):
            add_rounded_ellipsoid(secondary, radial_segments=6, radii=(0.33, 0.37, 0.30), center=(px, py, 0.30), ring_count=2, snap_min_z=0.0)

    eyes = bmesh.new()
    accent = bmesh.new()
    add_eye_pair_with_catchlights(
        eyes,
        accent,
        half_sep_x=0.45,
        pos_y=-1.33,
        pos_z=1.74,
        radii=(0.21, 0.12, 0.27),
        pitch_x_deg=-16.0,
        yaw_z_deg=20.0,
        radial_segs=8,
        catch_scale=0.95,
    )
    # Cute button nose atop broad muzzle
    add_rounded_ellipsoid(eyes, radial_segments=4, radii=(0.15, 0.12, 0.11), center=(0.0, -1.68, 1.46), ring_count=2)

    # Twin soft-faceted curved leaf-flame puppy ears
    for side in (-1, 1):
        s = float(side)
        add_curved_tube(
            accent,
            [
                ((s * 0.60, -0.58, 2.08), 0.25),
                ((s * 0.86, -0.46, 2.82), 0.15),
            ],
            sides=4,
            capped_tips=False,
        )
    # Playful upward curving ember flame-plume tail at +Y back
    add_curved_tube(
        accent,
        [
            ((0.0, 1.18, 1.22), 0.22),
            ((0.0, 1.58, 1.68), 0.30),
            ((0.0, 1.48, 2.30), 0.14),
        ],
        sides=5,
        capped_tips=False,
    )

    return {"Body": body, "Secondary": secondary, "Eyes": eyes, "Accent": accent}


def build_frostbeetle() -> dict[str, bmesh.types.BMesh]:
    """
    FrostBeetle (<= 400 tris: plump domed scarab carapace shell, rounded dark glacier-blue
    head hood & 4 sturdy rounded beetle legs on Z=0, curved ice horn & crystal wing fins):
    """
    body = bmesh.new()
    shell_rings = [
        (0.42, 1.10, 1.24, 0.18, 0.0, 0.0),
        (0.84, 1.28, 1.44, 0.18, 0.0, 0.0),
        (1.38, 1.14, 1.32, 0.18, 0.0, 0.0),
        (1.80, 0.74, 0.90, 0.18, 0.0, 0.0),
    ]
    add_lathe_shape(body, 12, shell_rings, bottom_cap_z=0.38, top_cap_z=1.98)

    secondary = bmesh.new()
    # Rounded front head hood protruding -Y
    add_rounded_ellipsoid(secondary, radial_segments=8, radii=(0.82, 0.68, 0.56), center=(0.0, -1.04, 0.86), ring_count=3, taper_front_y=0.14)
    # Rounded rear tail plate at +Y
    add_rounded_ellipsoid(secondary, radial_segments=6, radii=(0.64, 0.44, 0.34), center=(0.0, 1.46, 0.70), ring_count=2)
    # Four sturdy arched beetle legs grounded cleanly at Z = 0.0
    for side in (-1, 1):
        s = float(side)
        for py in (-0.42, 0.66):
            add_curved_tube(
                secondary,
                [
                    ((s * 0.84, py, 0.68), 0.19),
                    ((s * 1.24, py - 0.05, 0.38), 0.18),
                    ((s * 1.30, py - 0.08, 0.14), 0.15),
                ],
                sides=4,
                capped_tips=True,
            )
    sec_min_z = min(v.co.z for v in secondary.verts)
    if sec_min_z > 0.0:
        for v in secondary.verts:
            if v.co.z < 0.25:
                v.co.z = max(0.0, v.co.z - sec_min_z)

    eyes = bmesh.new()
    accent = bmesh.new()
    add_eye_pair_with_catchlights(
        eyes,
        accent,
        half_sep_x=0.45,
        pos_y=-1.52,
        pos_z=0.96,
        radii=(0.19, 0.11, 0.23),
        pitch_x_deg=-18.0,
        yaw_z_deg=24.0,
        radial_segs=8,
        catch_scale=0.88,
    )
    # Curved ice rhino horn sweeping forward then upward
    add_curved_tube(
        accent,
        [
            ((0.0, -1.26, 1.18), 0.22),
            ((0.0, -1.68, 1.46), 0.16),
            ((0.0, -1.80, 1.98), 0.10),
        ],
        sides=4,
        capped_tips=False,
    )
    # Twin ice wing-fins on carapace
    for side in (-1, 1):
        s = float(side)
        add_curved_tube(
            accent,
            [
                ((s * 0.72, 0.04, 1.44), 0.24),
                ((s * 1.02, 1.00, 1.88), 0.14),
            ],
            sides=4,
            capped_tips=False,
        )

    return {"Body": body, "Secondary": secondary, "Eyes": eyes, "Accent": accent}


def build_nebulafox() -> dict[str, bmesh.types.BMesh]:
    """
    NebulaFox (<= 400 tris: sleek rounded torso, tapered soft fox head + tapered cream muzzle,
    4 sleek paws on Z=0, tall swept ears, and large curled comet tail):
    """
    body = bmesh.new()
    add_rounded_ellipsoid(body, radial_segments=8, radii=(0.82, 1.14, 0.68), center=(0.0, 0.22, 1.04), ring_count=3)
    add_rounded_ellipsoid(body, radial_segments=10, radii=(0.94, 0.88, 0.74), center=(0.0, -0.56, 1.58), ring_count=3, taper_front_y=0.34)

    secondary = bmesh.new()
    # Tapered cream fox muzzle
    add_rounded_ellipsoid(secondary, radial_segments=8, radii=(0.48, 0.58, 0.30), center=(0.0, -1.26, 1.38), ring_count=2, taper_front_y=0.45)
    # Fluffy chest bib
    add_rounded_ellipsoid(secondary, radial_segments=6, radii=(0.56, 0.34, 0.48), center=(0.0, -0.78, 1.00), ring_count=2)
    # Four sleek fox paws grounded at Z = 0.0
    for px in (-0.48, 0.48):
        for py in (-0.60, 0.82):
            add_rounded_ellipsoid(secondary, radial_segments=4, radii=(0.25, 0.30, 0.30), center=(px, py, 0.30), euler_deg=(0.0, 0.0, 45.0), ring_count=2, snap_min_z=0.0)

    eyes = bmesh.new()
    accent = bmesh.new()
    add_eye_pair_with_catchlights(
        eyes,
        accent,
        half_sep_x=0.44,
        pos_y=-1.24,
        pos_z=1.74,
        radii=(0.20, 0.12, 0.26),
        pitch_x_deg=-18.0,
        yaw_z_deg=28.0,
        radial_segs=8,
        catch_scale=0.92,
    )
    add_rounded_ellipsoid(eyes, radial_segments=4, radii=(0.13, 0.11, 0.10), center=(0.0, -1.78, 1.44), ring_count=2)

    # Tall swept fox ears
    for side in (-1, 1):
        s = float(side)
        add_curved_tube(
            accent,
            [
                ((s * 0.54, -0.48, 2.12), 0.25),
                ((s * 0.82, -0.18, 3.04), 0.12),
            ],
            sides=4,
            capped_tips=False,
        )
    # Iconic curled comet tail sweeping up and curling forward over back
    add_curved_tube(
        accent,
        [
            ((0.0, 1.12, 1.16), 0.24),
            ((0.0, 1.62, 1.46), 0.40),
            ((0.0, 1.76, 2.04), 0.44),
            ((0.0, 1.16, 2.42), 0.22),
        ],
        sides=5,
        capped_tips=False,
    )

    return {"Body": body, "Secondary": secondary, "Eyes": eyes, "Accent": accent}


def build_solargolem() -> dict[str, bmesh.types.BMesh]:
    """
    SolarGolem (<= 400 tris: preserves chunky stone guardian silhouette with chamfered
    stone torso/arms, bronze pauldrons/gauntlets/pillar legs on Z=0, core diamond & sun crown):
    """
    body = bmesh.new()
    add_beveled_box(body, (2.52, 2.16, 2.64), (0.0, 0.04, 2.52), bevel_offset=0.24, bevel_segments=1)
    for side in (-1, 1):
        add_rounded_ellipsoid(body, radial_segments=4, radii=(0.52, 0.62, 0.68), center=(side * 1.54, -0.02, 2.74), euler_deg=(0.0, side * 4.0, 45.0), ring_count=3)

    secondary = bmesh.new()
    for side in (-1, 1):
        add_rounded_ellipsoid(secondary, radial_segments=4, radii=(0.60, 0.70, 0.34), center=(side * 1.52, -0.02, 3.50), euler_deg=(0.0, side * -8.0, 45.0), ring_count=2)
        add_rounded_ellipsoid(secondary, radial_segments=4, radii=(0.58, 0.68, 0.64), center=(side * 1.58, -0.10, 1.72), euler_deg=(-6.0, side * 4.0, 45.0), ring_count=3)
    for px in (-0.72, 0.72):
        add_rounded_ellipsoid(secondary, radial_segments=4, radii=(0.60, 0.70, 0.70), center=(px, 0.04, 0.70), euler_deg=(0.0, 0.0, 45.0), ring_count=3, snap_min_z=0.0)
    add_rounded_ellipsoid(secondary, radial_segments=4, radii=(0.44, 0.46, 0.58), center=(0.0, 1.16, 1.56), euler_deg=(-38.0, 0.0, 45.0), ring_count=2)

    eyes = bmesh.new()
    accent = bmesh.new()
    add_eye_pair_with_catchlights(
        eyes,
        accent,
        half_sep_x=0.60,
        pos_y=-1.04,
        pos_z=3.18,
        radii=(0.24, 0.13, 0.24),
        pitch_x_deg=-4.0,
        yaw_z_deg=6.0,
        radial_segs=8,
        catch_scale=1.0,
    )
    add_crystal_shard(accent, radius=0.56, shaft_height=0.20, tip_height=0.36, base_center=(0.0, -1.04, 2.20), euler_deg=(90.0, 0.0, 0.0), sides=4)
    add_lathe_shape(
        accent,
        6,
        [(3.74, 1.08, 1.04, 0.02, 0.0, 0.0), (4.06, 1.16, 1.10, 0.02, 0.0, 0.0)],
        bottom_cap_z=3.74,
        top_cap_z=4.06,
    )
    for side in (-1, 0, 1):
        h_s = 0.76 if side == 0 else 0.58
        add_crystal_shard(accent, radius=0.24, shaft_height=h_s * 0.58, tip_height=h_s * 0.68, base_center=(side * 0.64, -0.06, 3.96), euler_deg=(-8.0, side * 16.0, 0.0), sides=4)

    return {"Body": body, "Secondary": secondary, "Eyes": eyes, "Accent": accent}


def build_cometowl() -> dict[str, bmesh.types.BMesh]:
    """
    CometOwl (<= 400 tris: plump rounded owl dome, soft cream belly shield, 2 grounded
    talon feet on Z=0, giant 10-sided stargazer eyes + beak + swept comet wings):
    """
    body = bmesh.new()
    owl_rings = [
        (0.36, 0.92, 0.88, 0.06, 0.0, 0.0),
        (0.95, 1.24, 1.18, 0.06, 0.0, 0.0),
        (1.75, 1.18, 1.14, 0.06, 0.0, 0.0),
        (2.55, 1.00, 0.98, 0.06, 0.0, 0.0),
        (2.96, 0.58, 0.56, 0.06, 0.0, 0.0),
    ]
    add_lathe_shape(body, 10, owl_rings, bottom_cap_z=0.30, top_cap_z=3.08)
    for side in (-1, 1):
        add_rounded_ellipsoid(body, radial_segments=4, radii=(0.36, 0.58, 0.24), center=(side * 0.28, 1.24, 0.78), euler_deg=(-35.0, 0.0, side * 14.0), ring_count=2)

    secondary = bmesh.new()
    add_rounded_ellipsoid(secondary, radial_segments=6, radii=(0.84, 0.34, 0.78), center=(0.0, -0.96, 1.22), ring_count=2)
    for side in (-1, 1):
        add_rounded_ellipsoid(secondary, radial_segments=5, radii=(0.34, 0.44, 0.22), center=(side * 0.54, -0.18, 0.22), ring_count=2, snap_min_z=0.0)

    eyes = bmesh.new()
    accent = bmesh.new()
    add_eye_pair_with_catchlights(
        eyes,
        accent,
        half_sep_x=0.50,
        pos_y=-0.98,
        pos_z=2.34,
        radii=(0.32, 0.14, 0.35),
        pitch_x_deg=-16.0,
        yaw_z_deg=20.0,
        radial_segs=10,
        catch_scale=1.1,
    )
    add_crystal_shard(accent, radius=0.24, shaft_height=0.16, tip_height=0.38, base_center=(0.0, -1.04, 2.08), euler_deg=(114.0, 0.0, 0.0), sides=4)
    for side in (-1, 1):
        s = float(side)
        add_curved_tube(
            accent,
            [
                ((s * 1.06, -0.06, 2.08), 0.24),
                ((s * 1.42, 0.24, 1.56), 0.34),
                ((s * 1.38, 0.62, 0.96), 0.22),
            ],
            sides=4,
            capped_tips=False,
        )
        add_curved_tube(
            accent,
            [
                ((s * 0.66, -0.10, 2.86), 0.20),
                ((s * 0.98, 0.06, 3.52), 0.10),
            ],
            sides=4,
            capped_tips=False,
        )

    return {"Body": body, "Secondary": secondary, "Eyes": eyes, "Accent": accent}


def build_bisected_rock(seed: int, scale_xyz: tuple[float, float, float]) -> bmesh.types.BMesh:
    """Builds a seeded jagged angular low-poly boulder cleanly sliced flat at `Z = 0.0`."""
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
    Generates one angular low-poly Crater Meteor (`RockBody`, `CoreShards`, `TraitCrest`)
    with embedded glowing crystal shards and color-independent silhouettes (unchanged from S4-01).
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
        for side in (-1, 1):
            add_crystal_shard(crest, radius=0.40, shaft_height=0.95, tip_height=0.85, base_center=(side * 0.92, 0.0, rock_max_z * 0.68), euler_deg=(-10.0, side * 24.0, 0.0), sides=4)
            add_crystal_shard(crest, radius=0.26, shaft_height=0.60, tip_height=0.65, base_center=(side * 1.18, -0.35, rock_max_z * 0.52), euler_deg=(18.0, side * 36.0, 0.0), sides=4)
    elif trait_id == "Frost":
        add_crystal_shard(crest, radius=0.42, shaft_height=1.15, tip_height=0.95, base_center=(0.0, 0.0, rock_max_z * 0.72), euler_deg=(4.0, -6.0, 0.0), sides=6)
        for idx in range(3):
            ang = math.radians(idx * 120.0 + 30.0)
            add_crystal_shard(crest, radius=0.30, shaft_height=0.90, tip_height=0.75, base_center=(math.cos(ang) * 1.08, math.sin(ang) * 1.08, rock_max_z * 0.60), euler_deg=(math.sin(ang) * 28.0, -math.cos(ang) * 28.0, 0.0), sides=6)
    else:
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
    """Exports flat top-level sub-meshes using the Studio-validated Roblox FBX settings."""
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


def stage_in_viewport_row(
    objs: list[bpy.types.Object],
    prefix: str,
    asset_name: str,
    row_idx: int,
    total_count: int,
    row_y: float,
) -> None:
    """Renames exported objects uniquely and positions them neatly in a Blender showcase row."""
    offset_x = (row_idx - (total_count - 1) * 0.5) * SHOWCASE_SPACING_X
    for obj in objs:
        obj.name = f"SR_{prefix}_{asset_name}_{obj.name}"
        obj.location = (offset_x, row_y, 0.0)


def generate_catalog(allow_force: bool = False) -> list[dict]:
    """Builds, validates, exports, and logs all 6 soft hero critters + 3 angular meteors."""
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
            "Secondary": create_material(f"Mat_{species_id}_Secondary", pal["secondary"], roughness=0.35),
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

    print("=== Starfall Ranch Soft-Critter + Angular-Meteor Catalog Export Summary ===")
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
