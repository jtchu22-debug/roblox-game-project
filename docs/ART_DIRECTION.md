# Art Direction & Low-Poly Asset Pipeline (Post-Audit Revision)

> **Last Updated:** November 15, 2026 (Revised per Phase 0 Technical Director Audit — `R-006` / `R-010`)  
> **Author:** Gemini (Primary Art & Technical Planner)  
> **Auditor:** ChatGPT (Independent Technical Director)  
> **Visual Pillar:** *"Toy-Box Cosmic Pastel"* — Chunky, high-saturation low-poly shapes with readable silhouettes, accessible contrast, and strict mobile performance budgets.

---

The [Stage 6 critter roster and concept sheet](./CRITTER_ROSTER.md#visual-reference) guide production of the 108-species launch collection. Use the approved soft-stylized v2 meshes as the technical baseline and the concept art for silhouettes, expressive faces, and restrained accent colors.

The [Starfall Valley world brief and concept](./WORLD_ART_DIRECTION.md) cover the environment, terrain, lighting, locations, and production order for replacing the greybox art.

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
   - **6 Hero Critters — Approved v2 Soft-Stylized Roster** (`tools/blender/exports/critters/<SpeciesId>.fbx`, plus standalone reference export [`tools/blender/export_starslime_v2.py`](../tools/blender/export_starslime_v2.py) -> `tools/blender/exports/variants/StarSlime_v2.fbx`; flat `Body` / `Secondary` / `Eyes` / `Accent` meshes with expressive eyes, contrast details, and ground contact `min_z = 0.0`): *StarSlime* (`388` tris, rounded squishy dome + darker emerald-mint lower base `(42, 152, 116)` for turquoise floor contrast), *CinderPup* (`382` tris, broad muzzle + chunky paws), *FrostBeetle* (`384` tris, domed shell + glacier hood & 4 arched legs), *NebulaFox* (`396` tris, tapered fox face + curled tail), chunky *SolarGolem* (`396` tris, faceted stone torso + bronze armor), and *CometOwl* (`386` tris, plump dome + giant eyes & swept wings).
   - **3 Crater Meteors — Angular Rock Forms Kept** (`tools/blender/exports/meteors/<TraitId>.fbx`, flat `RockBody` / `CoreShards` / `TraitCrest` meshes with embedded hex crystal shards and color-independent silhouettes): *Ember* (`246` tris), *Frost* (`284` tris), *Astral* (`398` tris).
   - **Safe Rerun Protection:** Interactive runs refuse to delete non-default scene objects or prior `SR_Critters` / `SR_Meteors` collections unless `--force` (`ALLOW_DESTRUCTIVE_CLEAR = True`) is explicitly passed.
   - **Studio Styling Helper:** [`tools/studio/ApplyHeroMeshTemplateDefaults.luau`](../tools/studio/ApplyHeroMeshTemplateDefaults.luau) applies `CritterConfig` / `MeteorConfig` + `SecondaryColor` `SmoothPlastic` & `Neon` defaults, disables collision/query/touch on child meshes, assigns `PrimaryPart`, and asserts `<= 8` BaseParts / `<= 8` stud height budgets.
   - **Full 9-Asset + Approved v2 Critter Studio Verification (`Place1` & `StarfallRanch_Dev.rbxl` — Verified Nov 22, 2026):** Verified the initial 9 `.fbx` models in `Place1` (`RescuePrompt`, `MeteorLabel`, and `StarfallActiveMeteor` on angular meteors), then imported and approved the revised **v2 soft-stylized critter roster** inside `StarfallRanch_Dev.rbxl` (`Plot_1.HabitatPen` phone `667×375` zoom, close 3/4, rear, Radiant, and charcoal silhouette checks): `4/8` flat `MeshPart`s (`5/8` Radiant with `RadiantHalo`), `0.0000` ground pivot delta, `-Z` forward, exact `1:1` stud scale, and `<= 6.415` studs max height at Fed `1.15×` Radiant scale.

## Launch tool models

Create one original low-poly Blender model for each launch Cracker tier. Give them a shared rounded handle, visible grip, and a head shape readable at avatar scale. Use the Observatory's brass, cream stone, and teal color accents alongside each meteor family's visual cues.

| Tool | Shape and material direction |
| --- | --- |
| **Starter Cracker** | Short rounded quarry mallet with a wood handle, copper band, and cream striking face. |
| **Frost Cracker** | Compact two-prong head with a cyan wedge and dark navy wrapped grip. |
| **Astral Cracker** | Curved brass head with a broken ring profile, compact violet core, and visible dark grip. Maps to the existing `StarCracker` upgrade. |

Export editable sources and Studio-ready meshes with consistent scale and grip alignment. Add locked and owned previews at the Observatory Tool Workbench, and show the currently eligible Cracker in hand during the existing meteor crack interaction. The existing server upgrade rules determine which tool tier the player may use. Verify grip alignment, tool cleanup after a cancelled crack or respawn, prompt readability, and first- and third-person visibility on desktop and touch. Use the same mesh optimization and restrained effects principles as the hero assets.

## Launch station models

Give each interactable launch location a finished original low-poly model or modular prop assembly. Use the [Starfall Valley world art direction](./WORLD_ART_DIRECTION.md) for materials and placement. Dress one ranch and the Tool Workbench first, then repeat the approved kit across all six plots. Use the existing plot anchors, upgrade IDs, prompt reach, and server rules to connect the models to gameplay.

| Location or station | Visual direction and states |
| --- | --- |
| Incubators | Rounded cream-and-brass hatchery with a glass canopy, visible pod cradle, and legible idle, incubating, and ready states. Show the remaining time without obscuring the pod. |
| Habitat pens | Low timber rails, grass pad and feeding area, with clean avatar access to each slot. Give empty, occupied, and locked or purchasable slots clear visual cues and keep the critter as the focal point. |
| Ranch selling station and upgrade pads | Compact scales and counter for selling, with small, readable signs on upgrade pads and visible locked or owned states. |
| Observatory Tool Workbench | Original timber-and-brass bench with a cradle or stand for each Cracker preview. Keep the price and upgrade prompt visible from the approach. |
| Hub fixtures | A labeled lure kiosk, contracts board, scanner and Critter Index exhibit. Give the brewing station and expedition entry their own recognizable props when those features come online. |

Keep interactive surfaces and walkways open, especially around fences, incubator doors, and displays. Verify prompts, camera and character clearance, mobile visibility, and legibility of locked, ready, and occupied states. Test the completed kit across all six plots.

## Launch item and interface artwork

Give every launch catalog entry displayed to players its own original icon, thumbnail, or render. Use the same artwork whenever that entry is shown. Let related screens share typography, card spacing, touch controls, and state treatments. Vary the screen layout for what the player is doing, such as comparing an inventory grid, checking a collection, previewing a tool, or buying an offer.

| Catalog or screen | Required artwork |
| --- | --- |
| Meteors and pods | One recognizable thumbnail for each of the five meteor families and each distinct player-visible stored pod type. Use these in inventory, meteor help, or source details wherever those entries appear. Show an unopened pod's visible identity and reveal the species artwork when the game reveals the outcome. |
| Critters | A rendered portrait for every launch species. Use consistent camera and lighting, and reuse the portrait in Bag, Field Guide, Critter Index, and applicable reward cards. Show discovery silhouettes and use a finish border or badge for Gold or Rainbow and separate marks for mutations. Show weight and income as text. |
| Tools and upgrades | A distinct thumbnail for each Cracker tier plus images for the displayed ranch upgrades. Use the Cracker model for static thumbnails and reuse it for Workbench previews. Display costs, requirements, and owned state in the UI. |
| Potions, lures, materials, and rewards | Give every distinct entry a recognizable shape and icon. Use different silhouettes and symbols for Field Luck and Coin Boost potions, and match lure artwork to its meteor family. Keep stack count and status readable next to the artwork. |
| Game passes, cosmetics, and shop offers | Give every approved game pass and product a dedicated cover, and every featured bundle cover art composed from its actual contents. Show the exact entitlement, price, and owned status in live UI text. Keep the original illustrated Shop style rooted in Starfall Ranch's warm brass, teal, lilac, and constellation motifs. |
| Navigation and stations | Draw original, distinct icons for primary destinations such as Bag, Guide, Hub, Ranch, Shop, and Settings, plus in-world signs for important stations. Pair icons with readable labels wherever the action or destination would otherwise be ambiguous. |

The supplied Shop screenshot is a visual reference for prominent item art, strong card hierarchy, and prices readable at a glance. Use the existing Starfall Valley visual language and original illustrations, layouts, and icons. Use bolder illustrated offer cards in the Shop and quieter, scalable grids in frequently used inventory screens.

Keep one reusable asset mapping keyed by stable species, meteor, tool, or item ID. Keep editable artwork or render sources alongside the project's art assets and check that uploaded images display in the private published game. Use lightweight cached thumbnails for lists and load the visible page as needed. Reserve live 3D previews for selected details or the Workbench. Verify every visible launch entry has the expected artwork, price and status text stay legible on phone screens, and cards remain operable with touch, keyboard, and gamepad. Derive artwork choice from public item metadata. Purchases, inventory and undisclosed outcomes remain server-authoritative.
