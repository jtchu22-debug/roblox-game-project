"""
Starfall Ranch: StarSlime v2 Soft-Low-Poly Variant Exporter
Location: tools/blender/export_starslime_v2.py

Exports `StarSlime` v2 (with ChatGPT's darker emerald-mint lower base contrast tweak)
to `tools/blender/exports/variants/StarSlime_v2.fbx`, delegating directly to the
canonical `build_starslime()` geometry in `generate_lowpoly_assets.py` so the v2
variant stays synchronized with zero duplicated mesh logic.

Usage (CLI):
    blender --background --factory-startup --python tools/blender/export_starslime_v2.py
"""

import os
import sys

import bpy

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import generate_lowpoly_assets as catalog  # noqa: E402

COLLECTION_NAME = "SR_StarSlimeV2Variant"


def get_output_fbx_path() -> str:
    """Resolves `tools/blender/exports/variants/StarSlime_v2.fbx`."""
    export_dir = os.path.join(SCRIPT_DIR, "exports", "variants")
    os.makedirs(export_dir, exist_ok=True)
    return os.path.join(export_dir, "StarSlime_v2.fbx")


def guard_and_prepare_variant_scene(allow_force: bool) -> bpy.types.Collection:
    """Protects interactive user scenes unless `--force` is passed."""
    managed = {"Body", "Secondary", "Eyes", "Accent"}
    unexpected = [
        obj.name
        for obj in bpy.data.objects
        if obj.name not in managed and obj.name not in catalog.DEFAULT_STARTUP_OBJECTS
    ]
    if not bpy.app.background and (unexpected or COLLECTION_NAME in bpy.data.collections) and not allow_force:
        raise RuntimeError(
            "Safety guard aborted destructive clear in interactive scene. "
            "Open a clean scene or pass `--force`."
        )

    if COLLECTION_NAME in bpy.data.collections:
        col = bpy.data.collections[COLLECTION_NAME]
        for obj in list(col.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.collections.remove(col)

    for obj in list(bpy.data.objects):
        if obj.name in managed or (bpy.app.background and obj.name in catalog.DEFAULT_STARTUP_OBJECTS):
            bpy.data.objects.remove(obj, do_unlink=True)

    col = bpy.data.collections.new(COLLECTION_NAME)
    bpy.context.scene.collection.children.link(col)
    return col


def export_starslime_v2() -> str:
    """Builds `StarSlime` v2, enforces budgets, and exports `variants/StarSlime_v2.fbx`."""
    collection = guard_and_prepare_variant_scene(allow_force="--force" in sys.argv)
    pal = catalog.CRITTER_PALETTES["StarSlime"]
    mats = {
        "Body": catalog.create_material("Mat_StarSlimeV2_Body", pal["body"], roughness=0.30),
        "Secondary": catalog.create_material("Mat_StarSlimeV2_Secondary", pal["secondary"], roughness=0.35),
        "Eyes": catalog.create_material("Mat_StarSlimeV2_Eyes", catalog.COLOR_EYES_SRGB, roughness=0.15),
        "Accent": catalog.create_material("Mat_StarSlimeV2_Accent", pal["accent"], roughness=0.20, emission_strength=0.6),
    }
    bms = catalog.build_starslime()
    objs, sub_stats, summary = catalog.finalize_and_validate_submeshes(
        "StarSlime_v2", "Critter", bms, mats, collection
    )
    out_path = get_output_fbx_path()
    file_bytes = catalog.export_selected_fbx(objs, out_path)

    print("=== Starfall Ranch StarSlime v2 Variant Export Summary ===")
    for s in sub_stats:
        dx = s["max"][0] - s["min"][0]
        dy = s["max"][1] - s["min"][1]
        dz = s["max"][2] - s["min"][2]
        print(
            f"  SubMesh={s['name']} | Tris={s['tris']} | Volume={s['volume']:.4f} "
            f"| Studs(W={dx:.3f}, D={dy:.3f}, H={dz:.3f}) | MinZ={s['min'][2]:.5f}"
        )
    w, d, h = summary["studs_wdh"]
    print(
        f"  Combined | TotalTris={summary['total_tris']}/{catalog.TARGET_TRIS_MAX} | "
        f"Studs(W={w:.3f}, D={d:.3f}, H={h:.3f}) | MinZ={summary['min_z']:.5f} | FileSizeBytes={file_bytes}"
    )
    print(f"  ExportedPath={out_path}")
    return out_path


if __name__ == "__main__":
    export_starslime_v2()
