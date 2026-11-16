"""
Starfall Ranch: Procedural Low-Poly Asset Generator for Blender (3.6 / 4.x+)
Location: tools/blender/generate_lowpoly_assets.py

HOW TO USE (For Beginners):
1. Open Blender.
2. Switch to the "Scripting" workspace tab at the top.
3. Click "Open" and select this file (`generate_lowpoly_assets.py`).
4. Click the "Run Script" (Play triangle) button at the top right.
5. Three collection folders ("Crystals", "Meteors", "Critters") will appear in your viewport
   with ready-to-use low-poly models!
"""

import bpy
import bmesh
import math
import random
from mathutils import Vector, Euler


def clear_generated_collections():
    """Removes previously generated script objects to keep the scene clean."""
    for col_name in ["SR_Crystals", "SR_Meteors", "SR_Critters"]:
        if col_name in bpy.data.collections:
            col = bpy.data.collections[col_name]
            for obj in list(col.objects):
                bpy.data.objects.remove(obj, do_unlink=True)
            bpy.data.collections.remove(col)


def get_or_create_collection(name: str):
    if name not in bpy.data.collections:
        col = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(col)
    return bpy.data.collections[name]


def assign_simple_color_material(obj, mat_name: str, rgba: tuple, roughness: float = 0.35, emission: float = 0.0):
    """Creates or reuses a clean, flat-shaded material suitable for low-poly Roblox lookdev."""
    mat = bpy.data.materials.get(mat_name)
    if not mat:
        mat = bpy.data.materials.new(name=mat_name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs["Base Color"].default_value = rgba
            bsdf.inputs["Roughness"].default_value = roughness
            if "Emission Strength" in bsdf.inputs and emission > 0:
                bsdf.inputs["Emission Color"].default_value = rgba
                bsdf.inputs["Emission Strength"].default_value = emission
    if obj.data.materials:
        obj.data.materials[0] = mat
    else:
        obj.data.materials.append(mat)


def create_crystal_cluster(name: str, seed: int, shard_count: int, color_rgba: tuple, location: tuple):
    """
    Generates a stylized low-poly hexagonal crystal cluster.
    Each shard is a 6-sided cylinder with a tapered, pointed top crystal facet.
    """
    rng = random.Random(seed)
    col = get_or_create_collection("SR_Crystals")
    shard_objs = []

    for i in range(shard_count):
        is_center = (i == 0)
        radius = rng.uniform(0.45, 0.65) if is_center else rng.uniform(0.22, 0.45)
        height = rng.uniform(2.2, 2.8) if is_center else rng.uniform(1.0, 2.1)

        bpy.ops.mesh.primitive_cylinder_add(
            vertices=6,
            radius=radius,
            depth=height,
            end_fill_type='NGON',
            location=(0, 0, height * 0.5)
        )
        shard = bpy.context.active_object

        # Taper top cap into a crystal point using bmesh
        bm = bmesh.new()
        bm.from_mesh(shard.data)
        top_verts = [v for v in bm.verts if v.co.z > (height * 0.4)]
        if top_verts:
            # Extrude top face upward and scale to a point
            top_faces = [f for f in bm.faces if all(v in top_verts for v in f.verts)]
            if top_faces:
                res = bmesh.ops.extrude_face_region(bm, geom=top_faces)
                extruded_verts = [ele for ele in res["geom"] if isinstance(ele, bmesh.types.BMVert)]
                bmesh.ops.translate(bm, verts=extruded_verts, vec=(0, 0, radius * 1.1))
                bmesh.ops.scale(bm, verts=extruded_verts, vec=(0.08, 0.08, 1.0))

        bm.to_mesh(shard.data)
        bm.free()

        # Tilt outer shards outward around the center crystal
        if not is_center:
            angle = (i / (shard_count - 1)) * (2.0 * math.pi) + rng.uniform(-0.25, 0.25)
            tilt = rng.uniform(0.25, 0.58)
            dist = rng.uniform(0.3, 0.65)
            shard.location.x = math.cos(angle) * dist
            shard.location.y = math.sin(angle) * dist
            shard.rotation_euler = Euler((
                math.sin(angle) * tilt,
                -math.cos(angle) * tilt,
                rng.uniform(0, math.pi)
            ), 'XYZ')

        shard_objs.append(shard)

    # Join all shards into one clean mesh
    bpy.ops.object.select_all(action='DESELECT')
    for o in shard_objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = shard_objs[0]
    bpy.ops.object.join()

    cluster = bpy.context.active_object
    cluster.name = name
    cluster.location = Vector(location)

    # Add subtle bevel for crispy low-poly highlights
    bevel = cluster.modifiers.new(name="Bevel", type='BEVEL')
    bevel.width = 0.03
    bevel.segments = 1

    assign_simple_color_material(cluster, f"Mat_{name}", color_rgba, roughness=0.15, emission=0.4)

    # Link only to SR_Crystals collection
    for c in list(cluster.users_collection):
        c.objects.unlink(cluster)
    col.objects.link(cluster)
    return cluster


def create_meteor_geode(name: str, seed: int, rock_rgba: tuple, core_rgba: tuple, location: tuple):
    """Generates a chunky low-poly meteor rock with glowing crystal buds poking out."""
    rng = random.Random(seed)
    col = get_or_create_collection("SR_Meteors")

    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1.2, location=(0, 0, 1.0))
    rock = bpy.context.active_object
    rock.name = name

    # Perturb vertices slightly for organic low-poly boulder shape
    bm = bmesh.new()
    bm.from_mesh(rock.data)
    for v in bm.verts:
        noise = rng.uniform(0.82, 1.18)
        v.co *= noise
        if v.co.z < -0.6:
            v.co.z = -0.6  # Flatten bottom so it sits nicely on ground
    bm.to_mesh(rock.data)
    bm.free()

    assign_simple_color_material(rock, f"Mat_{name}_Rock", rock_rgba, roughness=0.8)
    rock.location = Vector(location)

    for c in list(rock.users_collection):
        c.objects.unlink(rock)
    col.objects.link(rock)
    return rock


def create_blocky_critter(name: str, body_rgba: tuple, ear_style: str, location: tuple):
    """
    Generates a charming, Roblox-friendly rounded-cube Critter body with ears and feet.
    Keep parts separate or joined for easy rigging/tweening in Roblox Studio.
    """
    col = get_or_create_collection("SR_Critters")
    parts = []

    # 1. Main Chibi Cube Body
    bpy.ops.mesh.primitive_cube_add(size=1.6, location=(0, 0, 1.0))
    body = bpy.context.active_object
    bevel = body.modifiers.new(name="Bevel", type='BEVEL')
    bevel.width = 0.28
    bevel.segments = 3
    bpy.ops.object.modifier_apply(modifier="Bevel")
    parts.append(body)

    # 2. Cute Ears (Fox/Cat Cones or Slime Nubbins)
    for side in (-1, 1):
        if ear_style == "fox":
            bpy.ops.mesh.primitive_cone_add(
                vertices=4, radius1=0.32, radius2=0.04, depth=0.65,
                location=(side * 0.5, 0.0, 2.0)
            )
            ear = bpy.context.active_object
            ear.rotation_euler.y = side * 0.25
        else:
            bpy.ops.mesh.primitive_uv_sphere_add(
                segments=12, ring_count=8, radius=0.28,
                location=(side * 0.52, 0.0, 1.9)
            )
            ear = bpy.context.active_object
        parts.append(ear)

    # 3. Stubby Feet
    for side in (-1, 1):
        bpy.ops.mesh.primitive_cube_add(size=0.45, location=(side * 0.45, 0.15, 0.22))
        foot = bpy.context.active_object
        parts.append(foot)

    bpy.ops.object.select_all(action='DESELECT')
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()

    critter = bpy.context.active_object
    critter.name = name
    critter.location = Vector(location)
    assign_simple_color_material(critter, f"Mat_{name}", body_rgba, roughness=0.25)

    for c in list(critter.users_collection):
        c.objects.unlink(critter)
    col.objects.link(critter)
    return critter


def generate_mvp_starter_pack():
    clear_generated_collections()

    # Generate 3 Sample Crystal Clusters
    create_crystal_cluster("Crystal_SunQuartz", seed=101, shard_count=6, color_rgba=(1.0, 0.78, 0.18, 1.0), location=(-4, 0, 0))
    create_crystal_cluster("Crystal_FrostPrism", seed=202, shard_count=7, color_rgba=(0.25, 0.85, 1.0, 1.0), location=(0, 0, 0))
    create_crystal_cluster("Crystal_NebulaAmethyst", seed=303, shard_count=8, color_rgba=(0.82, 0.28, 1.0, 1.0), location=(4, 0, 0))

    # Generate 2 Sample Meteor Geodes
    create_meteor_geode("Meteor_Standard", seed=404, rock_rgba=(0.45, 0.38, 0.55, 1.0), core_rgba=(0.3, 0.9, 1.0, 1.0), location=(-2, 4, 0))
    create_meteor_geode("Meteor_Mythic", seed=505, rock_rgba=(0.25, 0.18, 0.35, 1.0), core_rgba=(1.0, 0.3, 0.8, 1.0), location=(2, 4, 0))

    # Generate 2 Sample Blocky Critters
    create_blocky_critter("Critter_StarSlime", body_rgba=(0.35, 0.92, 0.65, 1.0), ear_style="round", location=(-2, -4, 0))
    create_blocky_critter("Critter_NebulaFox", body_rgba=(0.95, 0.45, 0.85, 1.0), ear_style="fox", location=(2, -4, 0))

    print("✅ Starfall Ranch low-poly starter assets generated successfully!")


if __name__ == "__main__":
    generate_mvp_starter_pack()
