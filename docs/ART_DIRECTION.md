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

## 3. Blender Automation Script Status (`R-010` Validated — Stage 4 `S4-01`)

The earlier Phase 0 caveats in [`tools/blender/generate_lowpoly_assets.py`](../tools/blender/generate_lowpoly_assets.py) have been resolved after completing single-sample validation (`R-010`):

1. **Single-Sample `R-010` Validation (`StarSlime.fbx` on Isolated `Place1` — Verified Nov 22, 2026):**
   - [`tools/blender/export_starslime_sample.py`](../tools/blender/export_starslime_sample.py) verified **exact `1:1` stud scaling** (`2.845 × 2.825 × 2.624` studs), clean outward-facing normals (`DoubleSided = false` across front/back/top renders), **ground-contact pivot** (`DeltaPivotToMinY = 0.0000`), single-level `Model -> {Body, Eyes, Accent}` hierarchy, **`-Z` forward orientation** (`EyesOffsetObj.Z = -1.2341`, matching `LookVector = (0, 0, -1)`), and clean runtime `SmoothPlastic` / `Neon` + `RadiantHalo` recoloring (`StarSlime_RadiantTest`, `4/8` BaseParts, `3.495` studs tall).
2. **Upgraded 9-Asset Stage 4 Hero Catalog (`<= 400` tris each):**
   - Removed the cut `SR_Crystals` generator and updated [`tools/blender/generate_lowpoly_assets.py`](../tools/blender/generate_lowpoly_assets.py) for Blender 5.3+ (plus 3.6/4.x compatibility) using the validated FBX export settings (`global_scale=0.01`, `apply_unit_scale=True`, `apply_scale_options="FBX_SCALE_ALL"`, `axis_forward="-Z"`, `axis_up="Y"`, `bake_space_transform=True`, Blender `-Y` front).
   - **6 Hero Critters** (`tools/blender/exports/critters/<SpeciesId>.fbx`, flat `Body` / `Eyes` / `Accent` meshes with sculpted eyes, tails/wings, and ground contact `min_z = 0.0`): *StarSlime* (`320` tris), *CinderPup* (`342` tris), *FrostBeetle* (`326` tris), *NebulaFox* (`346` tris), *SolarGolem* (`348` tris), *CometOwl* (`326` tris).
   - **3 Crater Meteors** (`tools/blender/exports/meteors/<TraitId>.fbx`, flat `RockBody` / `CoreShards` / `TraitCrest` meshes with embedded hex crystal shards and color-independent silhouettes): *Ember* (`246` tris), *Frost* (`284` tris), *Astral* (`398` tris).
   - **Safe Rerun Protection:** Interactive runs refuse to delete non-default scene objects or prior `SR_Critters` / `SR_Meteors` collections unless `--force` (`ALLOW_DESTRUCTIVE_CLEAR = True`) is explicitly passed.
   - **Studio Styling Helper:** [`tools/studio/ApplyHeroMeshTemplateDefaults.luau`](../tools/studio/ApplyHeroMeshTemplateDefaults.luau) applies `CritterConfig` / `MeteorConfig` `SmoothPlastic` & `Neon` defaults, disables collision/query/touch on child meshes, assigns `PrimaryPart`, and asserts `<= 8` BaseParts / `<= 8` stud height budgets.
   - **Full 9-Asset Studio Verification (`Place1` — Verified Nov 22, 2026):** Imported all 9 `.fbx` models into `Place1`, ran [`ApplyHeroMeshTemplateDefaults.luau`](../tools/studio/ApplyHeroMeshTemplateDefaults.luau), verified front and angled Studio screenshots across every model (clean facets, zero reversed normals or missing geometry), and confirmed runtime integration (`ScaleTo(1.15)` + `RadiantHalo` at `4/8` BaseParts and `<= 6.320` studs height on all 6 critters; `RescuePrompt`, `MeteorLabel`, and `StarfallActiveMeteor` tag on `RockBody` for all 3 meteors).
