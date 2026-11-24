"""
Starfall Ranch: S6-ART-04 Pilot + First S6-ART-02 Incubator Prototype Generator
Location: tools/blender/generate_s6_pilot_assets.py

Generates and exports the 5 pilot models:
1. CinderPup_Pilot      (`Body`, `Secondary`, `Eyes`, `Accent`) — 800..1200 tris target
2. SolarGolem_Pilot     (`Body`, `Secondary`, `Eyes`, `Accent`) — 800..1200 tris target
3. Ember_Pilot          (`RockBody`, `CoreShards`, `TraitCrest`) — 480..850 tris target
4. StarterCracker_Pilot (`Grip`, `Handle`, `Band`, `Head`, `Accent`) — 500..850 tris target
5. Incubator_Prototype  (`Base`, `Trim`, `Cradle`, `Canopy`, `Hinge`, `StatusRing`) — 650..1150 tris target

Usage (CLI):
    blender --background --factory-startup --python tools/blender/generate_s6_pilot_assets.py
"""

import argparse
import json
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

PILOT_CONFIGS = {
    "CinderPup_Pilot": {"max_parts": 8, "max_tris": 1200, "max_height": 8.0, "pivot": "ground"},
    "SolarGolem_Pilot": {"max_parts": 8, "max_tris": 1200, "max_height": 8.0, "pivot": "ground"},
    "Ember_Pilot": {"max_parts": 8, "max_tris": 850, "max_height": 8.0, "pivot": "ground"},
    "StarterCracker_Pilot": {"max_parts": 8, "max_tris": 850, "max_height": 4.0, "pivot": "grip"},
    "Incubator_Prototype": {"max_parts": 8, "max_tris": 1200, "max_height": 8.0, "pivot": "ground"},
    "ToolWorkbench_Prototype": {"max_parts": 8, "max_tris": 1200, "max_height": 8.0, "pivot": "ground"},
    "SellStand_Prototype": {"max_parts": 8, "max_tris": 1100, "max_height": 8.0, "pivot": "ground"},
    "HabitatPen_Prototype": {"max_parts": 8, "max_tris": 1100, "max_height": 8.0, "pivot": "ground"},
}


def srgb_channel_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def srgb255(rgb: tuple[int, int, int]) -> tuple[float, float, float, float]:
    return (
        srgb_channel_to_linear(rgb[0] / 255.0),
        srgb_channel_to_linear(rgb[1] / 255.0),
        srgb_channel_to_linear(rgb[2] / 255.0),
        1.0,
    )


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_mat(name: str, rgb: tuple[int, int, int], emission: float = 0.0, alpha: float = 1.0) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    if hasattr(mat, "use_nodes"):
        mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        rgba = srgb255(rgb)
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Roughness"].default_value = 0.42
        if alpha < 1.0 and "Alpha" in bsdf.inputs:
            bsdf.inputs["Alpha"].default_value = alpha
        if emission > 0.0 and "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = rgba
            bsdf.inputs["Emission Strength"].default_value = emission
    return mat


def finalize_obj(name: str, bm: bmesh.types.BMesh, mat: bpy.types.Material, smooth: bool = True) -> bpy.types.Object:
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


def add_ellipsoid(
    bm: bmesh.types.BMesh,
    center: tuple[float, float, float],
    radii: tuple[float, float, float],
    rot_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
    u_seg: int = 12,
    v_seg: int = 8,
) -> None:
    tmp = bmesh.new()
    bmesh.ops.create_uvsphere(tmp, u_segments=u_seg, v_segments=v_seg, radius=1.0)
    mat_s = Matrix.Diagonal((radii[0], radii[1], radii[2], 1.0))
    mat_r = Euler(tuple(math.radians(a) for a in rot_deg), "XYZ").to_matrix().to_4x4()
    mat_t = Matrix.Translation(Vector(center))
    bmesh.ops.transform(tmp, matrix=mat_t @ mat_r @ mat_s, verts=tmp.verts)
    for v in tmp.verts:
        pass
    vert_map = {}
    for v in tmp.verts:
        vert_map[v.index] = bm.verts.new(v.co)
    for f in tmp.faces:
        bm.faces.new([vert_map[v.index] for v in f.verts])
    tmp.free()


def add_lofted_tube(
    bm: bmesh.types.BMesh,
    rings: list[tuple[tuple[float, float, float], float, float, tuple[float, float, float]]],
    segments: int = 10,
    cap_start: bool = True,
    cap_end: bool = True,
) -> None:
    """Lofts elliptical rings: each ring = (center, rx, ry, rot_deg)."""
    ring_verts: list[list[bmesh.types.BMVert]] = []
    for center, rx, ry, rot_deg in rings:
        rot = Euler(tuple(math.radians(a) for a in rot_deg), "XYZ").to_matrix()
        cvec = Vector(center)
        verts = []
        for i in range(segments):
            ang = (2.0 * math.pi * i) / segments
            local = Vector((rx * math.cos(ang), ry * math.sin(ang), 0.0))
            verts.append(bm.verts.new(cvec + rot @ local))
        ring_verts.append(verts)

    for r_idx in range(len(ring_verts) - 1):
        r0 = ring_verts[r_idx]
        r1 = ring_verts[r_idx + 1]
        for i in range(segments):
            j = (i + 1) % segments
            bm.faces.new((r0[i], r0[j], r1[j], r1[i]))

    if cap_start:
        bm.faces.new(list(reversed(ring_verts[0])))
    if cap_end:
        bm.faces.new(ring_verts[-1])


def add_beveled_box(
    bm: bmesh.types.BMesh,
    center: tuple[float, float, float],
    size: tuple[float, float, float],
    rot_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
    bevel: float = 0.06,
) -> None:
    tmp = bmesh.new()
    bmesh.ops.create_cube(tmp, size=1.0)
    bmesh.ops.scale(tmp, vec=Vector(size), verts=tmp.verts)
    if bevel > 0.0:
        bmesh.ops.bevel(tmp, geom=list(tmp.edges), offset=bevel, segments=1, affect="EDGES")
    mat_r = Euler(tuple(math.radians(a) for a in rot_deg), "XYZ").to_matrix().to_4x4()
    mat_t = Matrix.Translation(Vector(center))
    bmesh.ops.transform(tmp, matrix=mat_t @ mat_r, verts=tmp.verts)
    vmap = {v.index: bm.verts.new(v.co) for v in tmp.verts}
    for f in tmp.faces:
        bm.faces.new([vmap[v.index] for v in f.verts])
    tmp.free()


def add_crystal_prism(
    bm: bmesh.types.BMesh,
    base_center: tuple[float, float, float],
    radius: float,
    height: float,
    rot_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
    sides: int = 6,
) -> None:
    rot = Euler(tuple(math.radians(a) for a in rot_deg), "XYZ").to_matrix()
    c = Vector(base_center)
    base_v = []
    mid_v = []
    for i in range(sides):
        ang = (2.0 * math.pi * i) / sides
        base_v.append(bm.verts.new(c + rot @ Vector((radius * math.cos(ang), radius * math.sin(ang), 0.0))))
        mid_v.append(bm.verts.new(c + rot @ Vector((radius * 0.78 * math.cos(ang), radius * 0.78 * math.sin(ang), height * 0.72))))
    tip_v = bm.verts.new(c + rot @ Vector((0.0, 0.0, height)))
    bm.faces.new(list(reversed(base_v)))
    for i in range(sides):
        j = (i + 1) % sides
        bm.faces.new((base_v[i], base_v[j], mid_v[j], mid_v[i]))
        bm.faces.new((mid_v[i], mid_v[j], tip_v))


# ==============================================================================
# 1. CINDER PUP PILOT (Soft sculpted anatomy + expression, 800..1200 tris)
# ==============================================================================
def build_cinderpup_pilot() -> list[bpy.types.Object]:
    m_body = make_mat("CinderPup_Body", (255, 125, 85))
    m_sec = make_mat("CinderPup_Secondary", (245, 228, 204))
    m_eyes = make_mat("CinderPup_Eyes", (22, 20, 34))
    m_acc = make_mat("CinderPup_Accent", (255, 215, 90), emission=0.8)

    bm_body = bmesh.new()
    # Sculpted seated pear-shaped torso (haunches -> chest -> neck)
    add_lofted_tube(
        bm_body,
        [
            ((0.0, 0.34, 0.14), 0.62, 0.68, (-8, 0, 0)),
            ((0.0, 0.28, 0.56), 0.78, 0.84, (-6, 0, 0)),
            ((0.0, 0.12, 1.08), 0.66, 0.68, (8, 0, 0)),
            ((0.0, -0.06, 1.48), 0.50, 0.48, (12, 0, 0)),
        ],
        segments=10,
    )
    # Rounded head + puffed cheeks + tapered snout
    add_ellipsoid(bm_body, (0.0, -0.22, 2.02), (0.76, 0.72, 0.68), (-4, 0, 0), u_seg=10, v_seg=6)
    for sx in (-1.0, 1.0):
        add_ellipsoid(bm_body, (sx * 0.44, -0.52, 1.88), (0.34, 0.32, 0.28), (0, 0, sx * 12), u_seg=8, v_seg=5)
    add_ellipsoid(bm_body, (0.0, -0.82, 1.84), (0.36, 0.34, 0.26), (8, 0, 0), u_seg=8, v_seg=5)

    # Floppy curved ears (left & right)
    for sx in (-1.0, 1.0):
        add_lofted_tube(
            bm_body,
            [
                ((sx * 0.62, -0.10, 2.38), 0.14, 0.22, (0, sx * 28, sx * -15)),
                ((sx * 0.88, -0.04, 2.04), 0.18, 0.30, (10, sx * 18, sx * -8)),
                ((sx * 0.94, 0.06, 1.62), 0.12, 0.24, (20, sx * 8, 0)),
            ],
            segments=6,
        )

    # 4 rounded paws with sculpted toe bumps
    paw_coords = [
        (-0.46, -0.54, 0.22),
        (0.46, -0.54, 0.22),
        (-0.66, 0.44, 0.20),
        (0.66, 0.44, 0.20),
    ]
    for px, py, pz in paw_coords:
        add_ellipsoid(bm_body, (px, py, pz), (0.24, 0.30, 0.20), (0, 0, 0), u_seg=7, v_seg=4)

    # Curled tail base
    add_lofted_tube(
        bm_body,
        [
            ((0.0, 0.88, 0.64), 0.18, 0.18, (60, 0, 0)),
            ((0.0, 1.18, 0.98), 0.16, 0.16, (35, 0, 0)),
            ((0.0, 1.24, 1.38), 0.13, 0.13, (5, 0, 0)),
        ],
        segments=6,
    )
    body_obj = finalize_obj("Body", bm_body, m_body, smooth=True)

    # Secondary: fluffy chest ruff, muzzle cheeks/chin, inner ear cushions, paw toes
    bm_sec = bmesh.new()
    add_ellipsoid(bm_sec, (0.0, -0.50, 1.26), (0.52, 0.38, 0.42), (-16, 0, 0), u_seg=8, v_seg=5)
    add_ellipsoid(bm_sec, (0.0, -0.84, 1.78), (0.28, 0.24, 0.18), (6, 0, 0), u_seg=7, v_seg=4)
    for sx in (-1.0, 1.0):
        add_ellipsoid(bm_sec, (sx * 0.46, -0.54, 0.14), (0.19, 0.24, 0.13), (0, 0, 0), u_seg=6, v_seg=4)
    sec_obj = finalize_obj("Secondary", bm_sec, m_sec, smooth=True)

    # Eyes + cute nose button
    bm_eyes = bmesh.new()
    for sx in (-1.0, 1.0):
        add_ellipsoid(bm_eyes, (sx * 0.32, -0.80, 2.08), (0.14, 0.11, 0.17), (0, sx * -16, 0), u_seg=7, v_seg=4)
    add_ellipsoid(bm_eyes, (0.0, -1.10, 1.90), (0.14, 0.11, 0.10), (10, 0, 0), u_seg=6, v_seg=4)
    eyes_obj = finalize_obj("Eyes", bm_eyes, m_eyes, smooth=True)

    # Accent: 3-tongue sculpted flame head crest + ember tail plume
    bm_acc = bmesh.new()
    add_crystal_prism(bm_acc, (0.0, -0.22, 2.60), 0.20, 0.42, (12, 0, 0), sides=6)
    add_crystal_prism(bm_acc, (-0.16, -0.14, 2.52), 0.14, 0.30, (18, -22, 0), sides=6)
    add_crystal_prism(bm_acc, (0.16, -0.14, 2.52), 0.14, 0.30, (18, 22, 0), sides=6)
    add_crystal_prism(bm_acc, (0.0, 1.24, 1.36), 0.20, 0.44, (-18, 0, 0), sides=6)
    acc_obj = finalize_obj("Accent", bm_acc, m_acc, smooth=False)

    return [body_obj, sec_obj, eyes_obj, acc_obj]


# ==============================================================================
# 2. SOLAR GOLEM PILOT (Irregular stone plates, tapered limbs, expressive face)
# ==============================================================================
def add_stone_slab(
    bm: bmesh.types.BMesh,
    center: tuple[float, float, float],
    radii: tuple[float, float, float],
    rot_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
    seed: int = 1,
) -> None:
    """Creates an irregular chiseled stone boulder slab from a displaced 1-subdiv icosphere."""
    tmp = bmesh.new()
    bmesh.ops.create_icosphere(tmp, subdivisions=1, radius=1.0)
    rng = random.Random(seed)
    for v in tmp.verts:
        jitter = rng.uniform(0.84, 1.14)
        v.co.x *= radii[0] * jitter
        v.co.y *= radii[1] * jitter
        v.co.z *= radii[2] * jitter
    mat_r = Euler(tuple(math.radians(a) for a in rot_deg), "XYZ").to_matrix().to_4x4()
    mat_t = Matrix.Translation(Vector(center))
    bmesh.ops.transform(tmp, matrix=mat_t @ mat_r, verts=tmp.verts)
    vmap = {v.index: bm.verts.new(v.co) for v in tmp.verts}
    for f in tmp.faces:
        bm.faces.new([vmap[v.index] for v in f.verts])
    tmp.free()


def build_solargolem_pilot() -> list[bpy.types.Object]:
    m_body = make_mat("SolarGolem_Body", (255, 175, 65))
    m_sec = make_mat("SolarGolem_Secondary", (168, 100, 44))
    m_eyes = make_mat("SolarGolem_Eyes", (22, 20, 34))
    m_acc = make_mat("SolarGolem_Accent", (255, 240, 145), emission=1.1)

    bm_body = bmesh.new()
    # Irregular sculpted chest stone slabs (asymmetric left/right boulder plates)
    add_stone_slab(bm_body, (-0.56, -0.10, 2.98), (0.64, 0.72, 0.78), (4, -10, 8), seed=11)
    add_stone_slab(bm_body, (0.58, -0.06, 2.94), (0.66, 0.70, 0.80), (-3, 12, -6), seed=22)

    for sx in (-1.0, 1.0):
        s_seed = 30 if sx < 0 else 40
        # Irregular overhanging boulder shoulder plates
        add_stone_slab(bm_body, (sx * 1.46, 0.0, 3.56), (0.58, 0.62, 0.44), (6, sx * 22, sx * -8), seed=s_seed)
        add_stone_slab(bm_body, (sx * 1.62, 0.05, 3.82), (0.42, 0.48, 0.26), (-4, sx * 28, 0), seed=s_seed + 1)
        # Tapered organic stone forearms (narrow elbow -> broad boulder fist)
        add_lofted_tube(
            bm_body,
            [
                ((sx * 1.46, 0.02, 2.66), 0.24, 0.26, (0, 0, 0)),
                ((sx * 1.56, -0.08, 2.20), 0.34, 0.38, (-8, 0, sx * -4)),
                ((sx * 1.60, -0.18, 1.72), 0.42, 0.46, (-12, 0, sx * -6)),
                ((sx * 1.58, -0.22, 1.48), 0.28, 0.30, (-12, 0, 0)),
            ],
            segments=7,
        )
        # Tapered pillar stone legs (narrow knee -> wide grounded boulder foot)
        add_lofted_tube(
            bm_body,
            [
                ((sx * 0.66, 0.04, 1.38), 0.28, 0.30, (0, 0, 0)),
                ((sx * 0.72, 0.0, 0.80), 0.38, 0.44, (0, 0, sx * 3)),
                ((sx * 0.76, -0.06, 0.20), 0.46, 0.54, (0, 0, 0)),
                ((sx * 0.76, -0.06, 0.0), 0.42, 0.50, (0, 0, 0)),
            ],
            segments=7,
        )

    # Rounded carved-stone creature head + expressive brow ridge
    add_ellipsoid(bm_body, (0.0, -0.08, 4.18), (0.64, 0.58, 0.54), (4, 0, 0), u_seg=10, v_seg=6)
    add_stone_slab(bm_body, (0.0, -0.32, 4.46), (0.58, 0.36, 0.20), (-10, 0, 0), seed=55)
    body_obj = finalize_obj("Body", bm_body, m_body, smooth=False)

    # Secondary: inner warm bronze-stone core spine, waist stone belt, tapered limb joints
    bm_sec = bmesh.new()
    add_lofted_tube(
        bm_sec,
        [
            ((0.0, 0.02, 1.62), 0.72, 0.54, (0, 0, 0)),
            ((0.0, 0.04, 2.25), 0.58, 0.48, (0, 0, 0)),
            ((0.0, 0.02, 3.35), 0.68, 0.52, (0, 0, 0)),
        ],
        segments=8,
    )
    add_stone_slab(bm_sec, (0.0, 0.0, 1.72), (0.86, 0.62, 0.28), (0, 0, 0), seed=66)
    for sx in (-1.0, 1.0):
        add_ellipsoid(bm_sec, (sx * 1.24, 0.0, 3.16), (0.28, 0.28, 0.26), (0, 0, 0), u_seg=6, v_seg=4)
        add_ellipsoid(bm_sec, (sx * 1.48, -0.04, 2.74), (0.22, 0.22, 0.24), (0, 0, 0), u_seg=6, v_seg=4)
    sec_obj = finalize_obj("Secondary", bm_sec, m_sec, smooth=False)

    # Eyes: expressive large rounded creature eyes + friendly carved nose/smile dimple
    bm_eyes = bmesh.new()
    for sx in (-1.0, 1.0):
        add_ellipsoid(bm_eyes, (sx * 0.24, -0.58, 4.22), (0.14, 0.10, 0.16), (0, sx * -14, 0), u_seg=7, v_seg=4)
    add_ellipsoid(bm_eyes, (0.0, -0.64, 4.02), (0.12, 0.08, 0.07), (0, 0, 0), u_seg=6, v_seg=4)
    eyes_obj = finalize_obj("Eyes", bm_eyes, m_eyes, smooth=True)

    # Accent: faceted solar heart crystal in chest + eye catchlights + asymmetric sun-shard crest
    bm_acc = bmesh.new()
    add_crystal_prism(bm_acc, (0.0, -0.44, 2.76), 0.28, 0.46, (82, 0, 0), sides=6)
    for sx in (-1.0, 1.0):
        add_ellipsoid(bm_acc, (sx * 0.27, -0.66, 4.27), (0.05, 0.04, 0.06), (0, 0, 0), u_seg=5, v_seg=3)
        add_crystal_prism(bm_acc, (sx * 0.56, 0.42, 3.92), 0.18, 0.86, (-18, sx * 26, 0), sides=5)
    add_crystal_prism(bm_acc, (0.0, 0.48, 4.14), 0.22, 0.92, (-22, 0, 0), sides=5)
    acc_obj = finalize_obj("Accent", bm_acc, m_acc, smooth=False)

    return [body_obj, sec_obj, eyes_obj, acc_obj]


# ==============================================================================
# 3. EMBER METEOR PILOT (Asymmetric faceted strata + fissures + twin-horn crest)
# ==============================================================================
def build_ember_pilot() -> list[bpy.types.Object]:
    m_rock = make_mat("Ember_RockBody", (145, 85, 95))
    m_core = make_mat("Ember_CoreShards", (255, 145, 60), emission=1.1)
    m_crest = make_mat("Ember_TraitCrest", (255, 130, 65), emission=1.2)

    rng = random.Random(404)
    bm_rock = bmesh.new()
    bmesh.ops.create_icosphere(bm_rock, subdivisions=2, radius=1.55)
    for v in bm_rock.verts:
        # Asymmetric faceted meteorite mass with stepped strata shelves & chipped base
        strata = 0.10 if int((v.co.z + 2.0) * 3.2) % 2 == 0 else -0.06
        asym = 1.0 + 0.18 * math.sin(v.co.x * 1.9 + 0.6) * math.cos(v.co.y * 1.7)
        jitter = rng.uniform(0.88, 1.12)
        v.co.x *= 1.18 * asym * jitter
        v.co.y *= 1.08 * jitter
        v.co.z = v.co.z * 0.86 * jitter + strata
        if v.co.z < -0.95:
            v.co.z = -0.95 + (v.co.z + 0.95) * 0.25
    # Add asymmetric exposed tectonic strata plates & chipped rim facets
    add_beveled_box(bm_rock, (-0.85, -0.45, -0.35), (1.15, 0.95, 0.42), (8, -14, 18), bevel=0.05)
    add_beveled_box(bm_rock, (0.78, 0.35, -0.15), (1.05, 1.15, 0.46), (-12, 16, -10), bevel=0.05)
    add_beveled_box(bm_rock, (0.10, -0.78, 0.22), (1.25, 0.85, 0.36), (14, 6, -8), bevel=0.04)
    body_obj = finalize_obj("RockBody", bm_rock, m_rock, smooth=False)

    # Embedded hexagonal magma crystal clusters erupting from fissures
    bm_core = bmesh.new()
    shard_specs = [
        ((-0.72, -0.92, 0.45), 0.26, 0.85, (52, -32, 12)),
        ((0.84, -0.76, 0.35), 0.24, 0.80, (48, 36, -15)),
        ((-0.25, 1.02, 0.55), 0.25, 0.78, (-54, -14, 0)),
        ((0.68, 0.82, 0.22), 0.22, 0.68, (-46, 38, 0)),
        ((0.05, -1.16, -0.10), 0.22, 0.65, (72, 6, 0)),
    ]
    for pos, r, h, rot in shard_specs:
        add_crystal_prism(bm_core, pos, r, h, rot, sides=6)
    core_obj = finalize_obj("CoreShards", bm_core, m_core, smooth=False)

    # Sweeping twin-horn flame crest bursting from the upper ridge
    bm_crest = bmesh.new()
    add_crystal_prism(bm_crest, (-0.36, -0.12, 0.95), 0.30, 1.48, (14, -22, 0), sides=6)
    add_crystal_prism(bm_crest, (0.34, 0.08, 0.92), 0.28, 1.38, (-10, 24, 0), sides=6)
    add_crystal_prism(bm_crest, (0.02, -0.22, 1.04), 0.22, 1.12, (24, 4, 0), sides=6)
    crest_obj = finalize_obj("TraitCrest", bm_crest, m_crest, smooth=False)

    return [body_obj, core_obj, crest_obj]


# ==============================================================================
# 4. STARTER CRACKER PILOT (Contoured grip wrap, tapered shaft, capped mallet)
# ==============================================================================
def build_startercracker_pilot() -> list[bpy.types.Object]:
    m_grip = make_mat("StarterPilot_Grip", (96, 60, 38))
    m_handle = make_mat("StarterPilot_Handle", (142, 92, 54))
    m_band = make_mat("StarterPilot_Band", (198, 128, 72))
    m_head = make_mat("StarterPilot_Head", (238, 228, 208))
    m_acc = make_mat("StarterPilot_Accent", (85, 195, 185), emission=0.7)

    # Grip centered at (0, 0, 0) with visible wrap ridges + beveled pommel cap
    bm_grip = bmesh.new()
    grip_rings = [
        ((0.0, 0.0, -0.48), 0.145, 0.145, (0, 0, 0)),
        ((0.0, 0.0, -0.40), 0.185, 0.185, (0, 0, 0)),
        ((0.0, 0.0, -0.32), 0.130, 0.145, (0, 0, 0)),
        ((0.0, 0.0, -0.18), 0.148, 0.162, (0, 0, 0)),
        ((0.0, 0.0, -0.08), 0.128, 0.142, (0, 0, 0)),
        ((0.0, 0.0, 0.02), 0.148, 0.162, (0, 0, 0)),
        ((0.0, 0.0, 0.14), 0.128, 0.142, (0, 0, 0)),
        ((0.0, 0.0, 0.26), 0.148, 0.162, (0, 0, 0)),
        ((0.0, 0.0, 0.40), 0.155, 0.165, (0, 0, 0)),
        ((0.0, 0.0, 0.46), 0.125, 0.135, (0, 0, 0)),
    ]
    add_lofted_tube(bm_grip, grip_rings, segments=10)
    grip_obj = finalize_obj("Grip", bm_grip, m_grip, smooth=True)

    # Smoothly tapered oval wooden shaft flaring into the head
    bm_handle = bmesh.new()
    add_lofted_tube(
        bm_handle,
        [
            ((0.0, 0.0, 0.42), 0.105, 0.120, (0, 0, 0)),
            ((0.0, 0.0, 0.96), 0.112, 0.132, (0, 0, 0)),
            ((0.0, 0.0, 1.44), 0.136, 0.160, (0, 0, 0)),
            ((0.0, 0.0, 1.62), 0.120, 0.142, (0, 0, 0)),
        ],
        segments=10,
    )
    handle_obj = finalize_obj("Handle", bm_handle, m_handle, smooth=True)

    # Stepped copper bolster collar + shoulder straps
    bm_band = bmesh.new()
    add_lofted_tube(
        bm_band,
        [
            ((0.0, 0.0, 1.44), 0.155, 0.175, (0, 0, 0)),
            ((0.0, 0.0, 1.52), 0.195, 0.215, (0, 0, 0)),
            ((0.0, 0.0, 1.66), 0.195, 0.215, (0, 0, 0)),
            ((0.0, 0.0, 1.74), 0.165, 0.185, (0, 0, 0)),
        ],
        segments=10,
    )
    add_beveled_box(bm_band, (0.0, -0.04, 2.04), (0.64, 0.42, 0.72), (0, 0, 0), bevel=0.04)
    band_obj = finalize_obj("Band", bm_band, m_band, smooth=False)

    # Chamfered quarry mallet head with stepped cream striking caps
    bm_head = bmesh.new()
    add_lofted_tube(
        bm_head,
        [
            ((0.0, -0.62, 2.04), 0.24, 0.24, (90, 0, 0)),
            ((0.0, -0.50, 2.04), 0.35, 0.35, (90, 0, 0)),
            ((0.0, -0.36, 2.04), 0.32, 0.32, (90, 0, 0)),
            ((0.0, 0.28, 2.04), 0.32, 0.32, (90, 0, 0)),
            ((0.0, 0.42, 2.04), 0.35, 0.35, (90, 0, 0)),
            ((0.0, 0.54, 2.04), 0.24, 0.24, (90, 0, 0)),
        ],
        segments=10,
    )
    head_obj = finalize_obj("Head", bm_head, m_head, smooth=True)

    # Faceted Observatory teal prism medallions on left/right mallet faces
    bm_acc = bmesh.new()
    for sx in (-1.0, 1.0):
        add_crystal_prism(bm_acc, (sx * 0.31, -0.04, 2.04), 0.15, 0.10, (0, sx * 90, 0), sides=6)
    acc_obj = finalize_obj("Accent", bm_acc, m_acc, smooth=False)

    return [grip_obj, handle_obj, band_obj, head_obj, acc_obj]


# ==============================================================================
# 5. INCUBATOR PROTOTYPE (S6-ART-02 — Cream & Brass Hatchery + Glass Canopy)
# ==============================================================================
def build_incubator_prototype() -> list[bpy.types.Object]:
    m_base = make_mat("Incubator_Base", (245, 235, 220))
    m_trim = make_mat("Incubator_Trim", (210, 164, 82))
    m_cradle = make_mat("Incubator_Cradle", (52, 50, 72))
    m_canopy = make_mat("Incubator_Canopy", (185, 235, 255), alpha=0.35)
    m_hinge = make_mat("Incubator_Hinge", (196, 146, 64))
    m_status = make_mat("Incubator_StatusRing", (65, 210, 255), emission=1.1)

    # Stepped rounded-octagonal cream-stone pedestal + front console apron (-Y)
    bm_base = bmesh.new()
    add_lofted_tube(
        bm_base,
        [
            ((0.0, 0.0, 0.0), 3.35, 3.35, (0, 0, 0)),
            ((0.0, 0.0, 0.42), 3.25, 3.25, (0, 0, 0)),
            ((0.0, 0.0, 0.56), 2.85, 2.85, (0, 0, 0)),
            ((0.0, 0.0, 1.28), 2.65, 2.65, (0, 0, 0)),
            ((0.0, 0.0, 1.48), 2.40, 2.40, (0, 0, 0)),
        ],
        segments=12,
    )
    add_beveled_box(bm_base, (0.0, -2.55, 0.72), (1.85, 0.92, 1.10), (-18, 0, 0), bevel=0.08)
    base_obj = finalize_obj("Base", bm_base, m_base, smooth=True)

    # Observatory brass trim rings + twin arched side ribs framing the canopy
    bm_trim = bmesh.new()
    add_lofted_tube(
        bm_trim,
        [
            ((0.0, 0.0, 1.38), 2.52, 2.52, (0, 0, 0)),
            ((0.0, 0.0, 1.56), 2.58, 2.58, (0, 0, 0)),
            ((0.0, 0.0, 1.64), 2.38, 2.38, (0, 0, 0)),
        ],
        segments=12,
    )
    for sx in (-1.0, 1.0):
        add_lofted_tube(
            bm_trim,
            [
                ((sx * 2.15, 0.0, 1.56), 0.16, 0.22, (0, 0, 0)),
                ((sx * 1.98, 0.0, 3.10), 0.15, 0.20, (0, sx * 22, 0)),
                ((sx * 1.10, 0.0, 4.35), 0.14, 0.18, (0, sx * 52, 0)),
                ((0.0, 0.0, 4.78), 0.16, 0.18, (0, sx * 90, 0)),
            ],
            segments=8,
        )
    trim_obj = finalize_obj("Trim", bm_trim, m_trim, smooth=True)

    # Contoured dark-slate pod cradle nest
    bm_cradle = bmesh.new()
    add_lofted_tube(
        bm_cradle,
        [
            ((0.0, 0.0, 1.48), 1.55, 1.55, (0, 0, 0)),
            ((0.0, 0.0, 1.88), 1.72, 1.72, (0, 0, 0)),
            ((0.0, 0.0, 1.98), 1.45, 1.45, (0, 0, 0)),
            ((0.0, 0.0, 1.68), 1.05, 1.05, (0, 0, 0)),
        ],
        segments=12,
    )
    cradle_obj = finalize_obj("Cradle", bm_cradle, m_cradle, smooth=True)

    # Rounded glass dome canopy over the pod cradle
    bm_canopy = bmesh.new()
    add_lofted_tube(
        bm_canopy,
        [
            ((0.0, 0.0, 1.62), 2.26, 2.26, (0, 0, 0)),
            ((0.0, 0.0, 2.65), 2.18, 2.18, (0, 0, 0)),
            ((0.0, 0.0, 3.65), 1.76, 1.76, (0, 0, 0)),
            ((0.0, 0.0, 4.38), 1.02, 1.02, (0, 0, 0)),
            ((0.0, 0.0, 4.65), 0.36, 0.36, (0, 0, 0)),
        ],
        segments=14,
        cap_start=False,
    )
    canopy_obj = finalize_obj("Canopy", bm_canopy, m_canopy, smooth=True)

    # Rear hinge knuckle + top brass Observatory finial
    bm_hinge = bmesh.new()
    add_beveled_box(bm_hinge, (0.0, 2.28, 1.78), (1.10, 0.42, 0.56), (0, 0, 0), bevel=0.05)
    add_lofted_tube(
        bm_hinge,
        [
            ((0.0, 0.0, 4.62), 0.46, 0.46, (0, 0, 0)),
            ((0.0, 0.0, 4.86), 0.32, 0.32, (0, 0, 0)),
            ((0.0, 0.0, 5.18), 0.08, 0.08, (0, 0, 0)),
        ],
        segments=10,
    )
    hinge_obj = finalize_obj("Hinge", bm_hinge, m_hinge, smooth=True)

    # State-driven status ring + front console indicator bar
    bm_status = bmesh.new()
    add_lofted_tube(
        bm_status,
        [
            ((0.0, 0.0, 1.90), 1.80, 1.80, (0, 0, 0)),
            ((0.0, 0.0, 2.02), 1.84, 1.84, (0, 0, 0)),
            ((0.0, 0.0, 2.06), 1.70, 1.70, (0, 0, 0)),
        ],
        segments=12,
        cap_start=False,
    )
    add_beveled_box(bm_status, (0.0, -2.96, 0.94), (1.12, 0.14, 0.20), (-18, 0, 0), bevel=0.02)
    status_obj = finalize_obj("StatusRing", bm_status, m_status, smooth=False)

    return [base_obj, trim_obj, cradle_obj, canopy_obj, hinge_obj, status_obj]


# ==============================================================================
# 6. TOOL WORKBENCH PROTOTYPE (S6-ART-02 — Timber, Cream Stone, Brass, 3 Cradles)
# ==============================================================================
def build_toolworkbench_prototype() -> list[bpy.types.Object]:
    m_timber = make_mat("Workbench_Timber", (118, 76, 48))
    m_stone = make_mat("Workbench_StoneTop", (245, 235, 220))
    m_brass = make_mat("Workbench_Brass", (210, 164, 82))
    m_drawer = make_mat("Workbench_Drawers", (82, 54, 38))
    m_cradle = make_mat("Workbench_Cradles", (46, 44, 66))
    m_accent = make_mat("Workbench_Accent", (85, 195, 185), emission=0.8)

    # Timber bench carcass: 22.0 wide (X) x 3.9 deep (Y), Z=0.0..3.25
    bm_timber = bmesh.new()
    add_beveled_box(bm_timber, (0.0, 0.0, 1.65), (21.6, 3.7, 2.95), (0, 0, 0), bevel=0.08)
    for sx in (-10.3, -3.5, 3.5, 10.3):
        add_beveled_box(bm_timber, (sx, 0.0, 1.55), (0.65, 4.05, 3.10), (0, 0, 0), bevel=0.06)
    timber_obj = finalize_obj("TimberFrame", bm_timber, m_timber, smooth=False)

    # Cream stone beveled countertop: Z=3.15..3.60 (top at exact 3.60 studs above Y=0.5 -> 4.10)
    bm_stone = bmesh.new()
    add_beveled_box(bm_stone, (0.0, 0.0, 3.375), (22.2, 4.25, 0.45), (0, 0, 0), bevel=0.08)
    stone_obj = finalize_obj("StoneTop", bm_stone, m_stone, smooth=False)

    # Brass trim plinth + drawer pulls + edge corner brackets
    bm_brass = bmesh.new()
    add_beveled_box(bm_brass, (0.0, 0.0, 0.18), (22.0, 4.10, 0.36), (0, 0, 0), bevel=0.05)
    for dx in (-6.8, 0.0, 6.8):
        add_beveled_box(bm_brass, (dx, -2.02, 2.35), (1.10, 0.14, 0.16), (0, 0, 0), bevel=0.02)
        add_beveled_box(bm_brass, (dx, -2.02, 1.35), (1.10, 0.14, 0.16), (0, 0, 0), bevel=0.02)
    brass_obj = finalize_obj("BrassTrim", bm_brass, m_brass, smooth=False)

    # Fitted front drawers facing -Y (East toward plaza)
    bm_drawers = bmesh.new()
    for dx in (-6.8, 0.0, 6.8):
        add_beveled_box(bm_drawers, (dx, -1.86, 2.35), (5.4, 0.24, 0.82), (0, 0, 0), bevel=0.04)
        add_beveled_box(bm_drawers, (dx, -1.86, 1.35), (5.4, 0.24, 0.82), (0, 0, 0), bevel=0.04)
    drawer_obj = finalize_obj("Drawers", bm_drawers, m_drawer, smooth=False)

    # 3 recessed Cracker cradle bases at X = -8.0, 0.0, +8.0 (Z = -32, -24, -16 in Hub)
    bm_cradles = bmesh.new()
    for cx in (-8.0, 0.0, 8.0):
        add_lofted_tube(
            bm_cradles,
            [
                ((cx, 0.0, 3.54), 1.32, 1.32, (0, 0, 0)),
                ((cx, 0.0, 3.66), 1.24, 1.24, (0, 0, 0)),
            ],
            segments=10,
        )
    cradle_obj = finalize_obj("Cradles", bm_cradles, m_cradle, smooth=False)

    # Observatory teal accent trim strips on front apron
    bm_acc = bmesh.new()
    for cx in (-8.0, 0.0, 8.0):
        add_beveled_box(bm_acc, (cx, -2.12, 3.38), (2.4, 0.08, 0.14), (0, 0, 0), bevel=0.02)
    acc_obj = finalize_obj("AccentInlay", bm_acc, m_accent, smooth=False)

    return [timber_obj, stone_obj, brass_obj, drawer_obj, cradle_obj, acc_obj]


# ==============================================================================
# 7. SELL STAND PROTOTYPE (S6-ART-02 — Timber Counter, Cream Top, Brass Scales)
# ==============================================================================
def build_sellstand_prototype() -> list[bpy.types.Object]:
    m_timber = make_mat("SellStand_Timber", (118, 76, 48))
    m_top = make_mat("SellStand_CounterTop", (245, 235, 220))
    m_brass = make_mat("SellStand_Brass", (210, 164, 82))
    m_pans = make_mat("SellStand_ScalePans", (230, 194, 118))
    m_ledger = make_mat("SellStand_Ledger", (46, 44, 66))
    m_gem = make_mat("SellStand_AccentGem", (255, 205, 45), emission=1.0)

    # Timber counter base (6.0 x 4.0 x 3.25)
    bm_timber = bmesh.new()
    add_beveled_box(bm_timber, (0.0, 0.0, 1.60), (5.7, 3.7, 3.05), (0, 0, 0), bevel=0.07)
    for sx in (-2.75, 2.75):
        for sy in (-1.75, 1.75):
            add_beveled_box(bm_timber, (sx, sy, 1.55), (0.48, 0.48, 3.10), (0, 0, 0), bevel=0.05)
    timber_obj = finalize_obj("TimberBase", bm_timber, m_timber, smooth=False)

    # Cream stone countertop (top at exact 3.60 above Y=0.5 -> 4.10)
    bm_top = bmesh.new()
    add_beveled_box(bm_top, (0.0, 0.0, 3.38), (6.2, 4.2, 0.44), (0, 0, 0), bevel=0.08)
    top_obj = finalize_obj("CounterTop", bm_top, m_top, smooth=False)

    # Brass scale pillar + crossbeam on right side of counter
    bm_brass = bmesh.new()
    add_lofted_tube(
        bm_brass,
        [
            ((1.45, 0.0, 3.60), 0.42, 0.42, (0, 0, 0)),
            ((1.45, 0.0, 3.76), 0.14, 0.14, (0, 0, 0)),
            ((1.45, 0.0, 4.88), 0.11, 0.11, (0, 0, 0)),
            ((1.45, 0.0, 5.06), 0.18, 0.18, (0, 0, 0)),
        ],
        segments=8,
    )
    add_beveled_box(bm_brass, (1.45, 0.0, 4.86), (1.85, 0.14, 0.14), (0, 0, 0), bevel=0.03)
    brass_obj = finalize_obj("BrassScales", bm_brass, m_brass, smooth=True)

    # Twin suspended weighing dishes
    bm_pans = bmesh.new()
    for px in (0.68, 2.22):
        add_lofted_tube(
            bm_pans,
            [
                ((px, 0.0, 4.18), 0.16, 0.16, (0, 0, 0)),
                ((px, 0.0, 4.28), 0.42, 0.42, (0, 0, 0)),
                ((px, 0.0, 4.34), 0.36, 0.36, (0, 0, 0)),
            ],
            segments=8,
        )
    pans_obj = finalize_obj("ScalePans", bm_pans, m_pans, smooth=True)

    # Ledger/coin box angled neatly on left side of counter
    bm_ledger = bmesh.new()
    add_beveled_box(bm_ledger, (-1.45, -0.15, 3.78), (1.45, 1.15, 0.34), (0, 0, 14), bevel=0.05)
    ledger_obj = finalize_obj("LedgerBox", bm_ledger, m_ledger, smooth=False)

    # Starlight Gold Observatory emblem medallion on front apron (-Y)
    bm_gem = bmesh.new()
    add_crystal_prism(bm_gem, (0.0, -1.92, 1.95), 0.46, 0.18, (90, 0, 0), sides=6)
    gem_obj = finalize_obj("AccentGem", bm_gem, m_gem, smooth=False)

    return [timber_obj, top_obj, brass_obj, pans_obj, ledger_obj, gem_obj]


# ==============================================================================
# 8. HABITAT PEN PROTOTYPE (S6-ART-02 — 26x34 Timber Rails + Feeding Trough)
# ==============================================================================
def build_habitatpen_prototype() -> list[bpy.types.Object]:
    m_posts = make_mat("Pen_TimberPosts", (134, 88, 56))
    m_rails = make_mat("Pen_TimberRails", (236, 224, 202))
    m_caps = make_mat("Pen_BrassCaps", (210, 164, 82))
    m_trough = make_mat("Pen_FeedTrough", (118, 76, 48))
    m_fill = make_mat("Pen_TroughFill", (95, 215, 145), emission=0.6)

    # Exact 26x34 perimeter around PenFloor center (0,0), with open 12-stud gate at X=-13, Y=-6..+6
    # Wait: GreyboxBuilder PenFloor is at local (24, 0.65, 2) with Size (26, 0.3, 34).
    # Fence_1..5 sit at offsets relative to PenFloor center:
    # Back (+X = +13, Y=-17..+17), North (Y=-17, X=-13..+13), South (Y=+17, X=-13..+13),
    # Front-North (X=-13, Y=-17..-6), Front-South (X=-13, Y=+6..+17).
    post_coords = [
        (-13.0, -17.0), (-6.5, -17.0), (0.0, -17.0), (6.5, -17.0), (13.0, -17.0),
        (13.0, -8.5), (13.0, 0.0), (13.0, 8.5), (13.0, 17.0),
        (6.5, 17.0), (0.0, 17.0), (-6.5, 17.0), (-13.0, 17.0),
        (-13.0, 11.5), (-13.0, 6.0),
        (-13.0, -6.0), (-13.0, -11.5),
    ]
    bm_posts = bmesh.new()
    bm_caps = bmesh.new()
    for px, py in post_coords:
        add_beveled_box(bm_posts, (px, py, 1.05), (0.56, 0.56, 2.10), (0, 0, 0), bevel=0.0)
        add_beveled_box(bm_caps, (px, py, 2.16), (0.66, 0.66, 0.16), (0, 0, 0), bevel=0.0)
    posts_obj = finalize_obj("TimberPosts", bm_posts, m_posts, smooth=False)
    caps_obj = finalize_obj("BrassCaps", bm_caps, m_caps, smooth=False)

    # Double horizontal rails along all 5 fence segments (leaving X=-13, Y=-6..+6 open!)
    bm_rails = bmesh.new()
    rail_segs = [
        ((0.0, -17.0), (26.0, 0.28)),
        ((0.0, 17.0), (26.0, 0.28)),
        ((13.0, 0.0), (0.28, 34.0)),
        ((-13.0, -11.5), (0.28, 11.0)),
        ((-13.0, 11.5), (0.28, 11.0)),
    ]
    for (rx, ry), (sx, sy) in rail_segs:
        for rz in (0.72, 1.58):
            add_beveled_box(bm_rails, (rx, ry, rz), (sx, sy, 0.26), (0, 0, 0), bevel=0.0)
    rails_obj = finalize_obj("TimberRails", bm_rails, m_rails, smooth=False)

    # Compact feeding trough tucked cleanly inside front-left corner (-10.8, -13.5), clear of Pen_1..5
    bm_trough = bmesh.new()
    add_beveled_box(bm_trough, (-10.6, -13.8, 0.42), (1.8, 3.6, 0.84), (0, 0, 0), bevel=0.06)
    trough_obj = finalize_obj("FeedTrough", bm_trough, m_trough, smooth=False)

    bm_fill = bmesh.new()
    add_ellipsoid(bm_fill, (-10.6, -13.8, 0.82), (0.65, 1.45, 0.22), (0, 0, 0), u_seg=8, v_seg=4)
    fill_obj = finalize_obj("TroughFill", bm_fill, m_fill, smooth=True)

    return [posts_obj, rails_obj, caps_obj, trough_obj, fill_obj]


BUILDERS = {
    "CinderPup_Pilot": build_cinderpup_pilot,
    "SolarGolem_Pilot": build_solargolem_pilot,
    "Ember_Pilot": build_ember_pilot,
    "StarterCracker_Pilot": build_startercracker_pilot,
    "Incubator_Prototype": build_incubator_prototype,
    "ToolWorkbench_Prototype": build_toolworkbench_prototype,
    "SellStand_Prototype": build_sellstand_prototype,
    "HabitatPen_Prototype": build_habitatpen_prototype,
}


def normalize_and_validate(name: str, objs: list[bpy.types.Object], cfg: dict) -> dict:
    assert len(objs) <= cfg["max_parts"], f"{name}: parts {len(objs)} > {cfg['max_parts']}"

    min_co = Vector((math.inf, math.inf, math.inf))
    max_co = Vector((-math.inf, -math.inf, -math.inf))
    for obj in objs:
        for corner in obj.bound_box:
            wc = obj.matrix_world @ Vector(corner)
            for a in range(3):
                min_co[a] = min(min_co[a], wc[a])
                max_co[a] = max(max_co[a], wc[a])

    if cfg["pivot"] == "ground" and abs(min_co.z) > 1e-4:
        shift = -min_co.z
        for obj in objs:
            mesh = obj.data
            for v in mesh.vertices:
                v.co.z += shift
            mesh.update()
        max_co.z += shift
        min_co.z = 0.0

    total_tris = 0
    grip_center = None
    for obj in objs:
        mesh = obj.data
        mesh.calc_loop_triangles()
        total_tris += len(mesh.loop_triangles)
        if obj.name == "Grip":
            o_min = Vector((math.inf, math.inf, math.inf))
            o_max = Vector((-math.inf, -math.inf, -math.inf))
            for corner in obj.bound_box:
                wc = obj.matrix_world @ Vector(corner)
                for a in range(3):
                    o_min[a] = min(o_min[a], wc[a])
                    o_max[a] = max(o_max[a], wc[a])
            grip_center = (o_min + o_max) * 0.5

    size = max_co - min_co
    assert total_tris <= cfg["max_tris"], f"{name}: tris {total_tris} > {cfg['max_tris']}"
    assert size.z <= cfg["max_height"], f"{name}: height {size.z:.3f} > {cfg['max_height']}"
    if cfg["pivot"] == "grip":
        assert grip_center is not None and grip_center.length <= 0.05, f"{name}: grip center {grip_center}"

    return {
        "name": name,
        "parts": len(objs),
        "triangles": total_tris,
        "size_studs": [round(size.x, 3), round(size.y, 3), round(size.z, 3)],
        "pivot": cfg["pivot"],
    }


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", nargs="*", choices=list(PILOT_CONFIGS.keys()), default=list(PILOT_CONFIGS.keys()))
    args = parser.parse_args(argv)

    script_dir = os.path.dirname(os.path.abspath(__file__))
    sources_dir = os.path.join(script_dir, "sources", "pilot")
    exports_dir = os.path.join(script_dir, "exports", "pilot")
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

    for name in args.only:
        clear_scene()
        objs = BUILDERS[name]()
        stats = normalize_and_validate(name, objs, PILOT_CONFIGS[name])
        blend_path = os.path.join(sources_dir, f"{name}.blend")
        fbx_path = os.path.join(exports_dir, f"{name}.fbx")
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
        stats["blend_path"] = f"tools/blender/sources/pilot/{name}.blend"
        stats["fbx_path"] = f"tools/blender/exports/pilot/{name}.fbx"
        manifest[name] = stats
        print(
            f"[PilotGen] {name} | Parts={stats['parts']}/{PILOT_CONFIGS[name]['max_parts']} | "
            f"Tris={stats['triangles']}/{PILOT_CONFIGS[name]['max_tris']} | Size={stats['size_studs']}"
        )

    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)


if __name__ == "__main__":
    main()
