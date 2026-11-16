# Art Direction & Low-Poly Asset Pipeline (Post-Audit Revision)

> **Last Updated:** November 15, 2026 (Revised per Phase 0 Technical Director Audit — `R-006` / `R-010`)  
> **Author:** Gemini (Primary Art & Technical Planner)  
> **Auditor:** ChatGPT (Independent Technical Director)  
> **Visual Pillar:** *"Toy-Box Cosmic Pastel"* — Chunky, high-saturation low-poly shapes with readable silhouettes, accessible contrast, and strict mobile performance budgets.

---

## 1. Visual Style, Accessibility & Performance Budgets

1. **Readable Silhouettes + Color-Independent Cues:**  
   Never rely on color alone to communicate gameplay choices. Each of the 3 meteor traits uses a distinct shape and icon alongside its trail color:
   - **Ember Meteor:** Warm coral-orange + flame-horn crest silhouette + Flame icon.
   - **Frost Meteor:** Sky-cyan + jagged ice-crystal spike silhouette + Snowflake icon.
   - **Astral Meteor:** Violet-gold + orbiting star-ring silhouette + Star icon.
2. **Strict Scale & Instance Budget (MVP):**
   - **Max Display Height:** $\le 8$ studs inside `60x60` stud plots (35-stud giant models are **removed** from MVP to prevent camera occlusion and plot visual overlap).
   - **Max Active Visual Critters Server-Wide:** `6 plots × 5 active critters = 30 models max`.
   - **Part/Triangle Budget:** Each prototype Part critter uses $\le 8$ non-colliding `BasePart`s (`CanCollide = false`, `CanQuery = false`, `CanTouch = false`, `CastShadow = false` on small parts). Each future Blender hero mesh targets $\le 400$ triangles.
   - **Accessibility & Contrast:** High-contrast UI labels, light/dark surface readability, Touch/Keyboard/Gamepad button prompts, and a **Reduced Motion** setting that disables bounce tweens and particle flashes.

### Master Color Palette (`Color3.fromRGB`)
| Palette Role | Color Name | RGB Values | Hex | Where Used |
| :--- | :--- | :---: | :---: | :--- |
| **Environment Base** | Meadow Mint | `(95, 215, 145)` | `#5FD791` | Floating island grass tops |
| **Environment Cliff** | Warm Lilac Stone | `(120, 105, 155)` | `#78699B` | Island rock undersides & Crater rim |
| **Plot Structure** | Clean Cream Trim | `(245, 235, 220)` | `#F5EBDC` | Ranch fences, gates, Incubator frames |
| **Tech / Interactive** | Orbital Cyan | `(65, 210, 255)` | `#41D2FF` | Incubator pads, Upgrade indicators |
| **Highlight / Radiant** | Starlight Gold | `(255, 205, 45)` | `#FFCD2D` | Coins, Radiant cosmetic variant |

---

## 2. Two-Stage Asset Strategy (Parts First, Blender Only After Stage 2 Fun Gate)

- **Stages 1–3 (Native Roblox Parts Only):**  
  Build the entire vertical slice and persistence alpha using crisp native Roblox primitives (`Part`, `WedgePart`, `Cylinder`, `Sphere`). Prototype critters (*Star-Slime*, *Nebula Fox*, *Solar Golem*) use charming stylized blocky Part assemblies (cube body + sphere eyes + wedge ears/crown), letting us test the 5-minute gameplay loop immediately without Blender bottlenecks.
- **Stage 4 (`R-010` — Custom Low-Poly Meshes After Fun Gate Passes):**  
  Only *after* the Stage 2 uncoached playtest validates that players love rescuing meteors and collecting critters do we upgrade the 3 hero critters and 3 meteor rocks to custom Blender `.fbx` meshes.

---

## 3. Blender Automation Script Status & Required Fixes (`R-010` Caveats)

The starter generator script at [`tools/blender/generate_lowpoly_assets.py`](../tools/blender/generate_lowpoly_assets.py) was statically inspected during the Phase 0 audit and **must not be used for production exports as-is** until `R-010` runs in Stage 4. Known gaps documented for `R-010`:

1. **Scope Mismatch:** Currently creates 3 sample crystal clusters (cut from MVP), 2 meteors, and 2 critters—not the 3 MVP species (*Star-Slime*, *Nebula Fox*, *Solar Golem*) + 3 meteor traits (*Ember*, *Frost*, *Astral*).
2. **Incomplete Geometry:** `create_meteor_geode` currently ignores its `core_rgba` parameter and does not embed crystal shards; `create_blocky_critter` does not generate visible eyes or tail attachments.
3. **Missing `.fbx` Exporter:** No automated `bpy.ops.export_scene.fbx` step is implemented yet.
4. **Destructive Collection Cleanup:** `clear_generated_collections()` removes existing objects in `SR_Crystals`, `SR_Meteors`, and `SR_Critters` on rerun. **Never run this script inside an artist's main `.blend` scene**—use a dedicated clean generator `.blend` file only and add an explicit confirmation guard before `R-010`.
5. **Single-Sample Validation First:** When `R-010` begins in Stage 4, export **one sample model (`StarSlime.fbx`)**, import it into an isolated Roblox Studio test place, and verify exact stud dimensions, face normals, ground-contact pivot, material assignment, and runtime `Radiant` recoloring before generating the rest of the catalog.
