# Art Direction & Low-Poly Asset Pipeline (Post-Audit Revision)

> **Last Updated:** November 15, 2026 (Revised per Phase 0 Technical Director Audit — `R-006` / `R-010`)  
> **Author:** Gemini (Primary Art & Technical Planner)  
> **Auditor:** ChatGPT (Independent Technical Director)  
> **Visual Pillar:** *"Toy-Box Cosmic Pastel"* — Sculpted, high-saturation toy forms with readable silhouettes, accessible contrast, and measured mobile performance budgets.

---

The [Stage 6 critter roster and concept sheet](./CRITTER_ROSTER.md#visual-reference) guide production of the 108-species launch collection. Use the soft-stylized v2 meshes as the technical baseline and the concept art for silhouettes, expressive faces, and restrained accent colors. The [Stage 6 launch model detail pass](#stage-6-launch-model-detail-pass) sets the visual target for the next Blender iteration.

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

## Stage 6 launch model detail pass

Use the [Steal an Egg gameplay gallery](https://bo3.gg/games/articles/steal-an-egg-pets-guide) as a reference for how different creature silhouettes and body landmarks read in a crowded pen. Starfall Ranch's own [critter concepts](./CRITTER_ROSTER.md#visual-reference) and [Starfall Valley](./WORLD_ART_DIRECTION.md) set the anatomy, colors, and materials. Aim for sculpted toy figures, shaped rock, and crafted Observatory machinery. A flat-sided torso, straight limbs, and flat colored inserts can still read as a block assembly after the corners are rounded. Shape the profile and transitions first, then add detail that survives normal gameplay zoom.

| Asset group | What to change |
| --- | --- |
| **Critters** | Sculpt the head, cheeks, muzzle, body and paws as rounded, tapered volumes. Blend transitions, then separate a few large landmarks such as wings, ears, shell plates, or a tail. Give each species its own proportions, pose and facial expression. Use clean highlights and a restrained detail pass for eyes, spots, fur tufts or seams. Keep Star-Slime smooth and squishy. Keep Solar Golem heavy, with offset armor plates, bevels and readable gaps. Give chase critters such as Eclipse Dragon a distinctive outline and visible secondary forms that read with effects turned down. |
| **Meteors and pods** | Give each rock an asymmetric mass with broad facets, chips, exposed strata and crystal or core shapes embedded in the surface. Round the edges on manufactured pod shells and add a readable seam and clasp. Keep Ember, Frost, and Astral identifiable by shape. |
| **Crackers and handheld gear** | Add tapered handles, visible grip wraps, fitted collars and believable striking faces. Give Starter a capped mallet, Frost a shaped fork around its crystal, and Astral a layered brass ring with a visible core. Concentrate detail on the face visible when held and leave enough clearance for the hand and camera. |
| **Stations and world props** | Shape the incubator cradle, glass canopy and hinges. Give the Tool Workbench fitted drawers, beveled edges and recessed cradles. Use timber joins and curved rails around the ranch. Group smaller details near interaction points and keep walkways and signs clear. |
| **Prestige rides and suits** | Carry the same warm metal, enamel and Observatory fittings into shaped body panels, wheel arches and articulated mech joints. Give each ride or suit a silhouette recognizable from across the plaza. Use the existing [garage concepts](./OBSERVATORY_GEAR_SHOP.md#prestige-garage) to guide the forms. |

### First review in Studio

1. Create a before/after pilot for **Cinder Pup, Solar Golem, Ember Meteor, and the Starter Cracker**. Include the S6-ART-02 **incubator prototype** when it is ready. Cinder Pup tests soft anatomy and expression, while Solar Golem tests shaped hard surfaces on a heavy creature. Review the pilot before batch remodeling the six heroes or producing the wider roster.
2. Match the camera, light and size for each before/after. Capture normal ranch gameplay and phone framing at `667×375`, plus front, three-quarter and rear views. Show the Cracker in a real crack and the incubator with a pod. Review critters on the pen floor and in a small Index thumbnail. Check that standard, Gold, Rainbow and mutation treatments remain distinct wherever those variants are implemented.
3. Keep shipped part counts, placement pivots, grip offsets, clearance, interaction anchors, and the eight-stud critter height cap. Preserve the Stage 4 triangle target as the shipped baseline until the pilot is measured. For the two pilot critters, try up to **800–1,200 triangles per displayed model** where the silhouette needs them. Record the counts and compare frame time and memory with six plots and up to 30 displayed critters, active meteors, and the same view and device in each run. Record whether the run used physical hardware or Studio emulation. Use flat, material-grouped meshes and baked detail where it improves the final read. Apply a higher launch budget only after a measured review.
4. Reuse stable IDs and template names. Save editable Blender sources and Studio-ready exports with the comparison captures. Use approved front three-quarter renders to drive Index portraits and shop artwork. The narrow pilot can run alongside Cracker fixes and the first station prototype.

- **S6-ART-04 Pilot & First S6-ART-02 Incubator Prototype (`StarfallRanch_Dev.rbxl` — Nov 23, 2026):**
  - **Generator, Sources & Exports:** [`tools/blender/generate_s6_pilot_assets.py`](../tools/blender/generate_s6_pilot_assets.py), `.blend` sources in `tools/blender/sources/pilot/`, Studio-ready `.fbx` exports + `manifest.json` in `tools/blender/exports/pilot/`, imported under isolated `ReplicatedStorage.AssetTemplates.Pilot` (Stage 4 shipped baselines remain untouched pending review). Workflow documented in [`tools/studio/ASSET_IMPORT_WORKFLOW.md`](../tools/studio/ASSET_IMPORT_WORKFLOW.md).
  - **Pilot Budgets & Dimensions (`<= 8` parts, `<= 1,200` tris critters/stations, `<= 850` tris meteor/tool):**
    - `CinderPup_Pilot`: `4/8` parts, `1,018` tris (`382` Stage 4 baseline), `2.118 × 3.011 × 2.675` studs, `0.0000` ground pivot delta.
    - `SolarGolem_Pilot` *(v2)*: `4/8` parts, `892` tris (`396` Stage 4 baseline), `4.078 × 4.993 × 1.775` studs, `0.0000` ground pivot delta (irregular chiseled stone plates, tapered limbs, carved brow, rounded creature eyes).
    - `Ember_Pilot`: `3/8` parts, `388` tris (`246` Stage 4 baseline), `3.476 × 3.309 × 3.471` studs, `0.0000` ground pivot delta.
    - `StarterCracker_Pilot`: `5/8` parts, `552` tris (`344` baseline), `0.820 × 2.880 × 1.160` studs, `(0, 0, 0)` grip pivot.
    - `Incubator_Prototype` *(S6-ART-02)*: `6/8` parts, `766` tris, `6.700 × 5.180 × 6.700` studs, `0.0000` ground pivot delta (integrated on `Plot_1` via [`StationVisualController.luau`](../src/Client/Controllers/StationVisualController.luau) with `Locked`/`Idle`/`Incubating`/`Ready` states and cradled Star-Pod offset).
    - `ToolWorkbench_Prototype` *(S6-ART-02)*: `6/8` parts, `1,076` tris, `22.200 × 3.660 × 4.285` studs, `0.0000` ground pivot delta (integrated on `CentralHub.ToolWorkbench` preserving display & upgrade pad placement).
  - **Populated-Map Studio 3-Run A/B Benchmark (Studio Play Solo, 30 critters + 5 meteors, identical locked overview camera, 2 × 5.0s `RenderStepped` windows per run):**
    - **Run A (Stage 4 Baseline, 0 pilot stations, `12,900` tris):** S1 `15.0`/`14.7` FPS (`66.66 ms`), S2 `15.0`/`14.7` FPS (`66.67 ms`), `2576.8 MB` TotalMem, `1062.9 MB` LuaHeap.
    - **Run B1 (Pilot Critters/Meteors ONLY, 0 pilot stations, `30,590` tris):** S1 `15.0`/`14.7` FPS (`66.65 ms`), S2 `15.0`/`14.8` FPS (`66.67 ms`), `2576.8 MB` TotalMem (`+0.0 MB`), `1058.5 MB` LuaHeap.
    - **Run B2 (Combined Load — Pilot + 12 Incubators + 1 Workbench, `40,858` tris):** S1 `15.0`/`14.7` FPS (`66.67 ms`), S2 `15.0`/`14.8` FPS (`66.66 ms`), `2573.9 MB` TotalMem, `1048.5 MB` LuaHeap.
    - *Note:* Automated MCP `Play Solo` hit Studio's `15.0 FPS` (`66.66 ms`) background cap across all 3 runs; uncapped interactive foreground and physical low-end mobile frame-time checks remain gated on `S4-03`.

## Launch tool models

Create one original low-poly Blender model for each launch Cracker tier. Give them a shared rounded handle, visible grip, and a head shape readable at avatar scale. Use the Observatory's brass, cream stone, and teal color accents alongside each meteor family's visual cues.

| Tool | Shape and material direction |
| --- | --- |
| **Starter Cracker** | Short rounded quarry mallet with a wood handle, copper band, and cream striking face. |
| **Frost Cracker** | Compact two-prong head with a cyan wedge and dark navy wrapped grip. |
| **Astral Cracker** | Curved brass head with a broken ring profile, compact violet core, and visible dark grip. Maps to the existing `StarCracker` upgrade. |

Export editable sources and Studio-ready meshes with consistent scale and grip alignment. Add locked and owned previews at the Observatory Tool Workbench, and show the currently eligible Cracker in hand during the existing meteor crack interaction. The existing server upgrade rules determine which tool tier the player may use. Verify grip alignment, tool cleanup after a cancelled crack or respawn, prompt readability, and first- and third-person visibility on desktop and touch. Use the same mesh optimization and restrained effects principles as the hero assets.

- **S6-ART-01 Implemented Assets & Verification (`StarfallRanch_Dev.rbxl` — Nov 23, 2026):**
  - **Generator & Editable Sources:** [`tools/blender/generate_cracker_tools.py`](../tools/blender/generate_cracker_tools.py), `.blend` sources in `tools/blender/sources/tools/{StarterCracker,FrostCracker,AstralCracker}.blend`, and Studio-ready `.fbx` exports in `tools/blender/exports/tools/{StarterCracker,FrostCracker,AstralCracker}.fbx` (`manifest.json`).
  - **Shared Config & Client Visuals:** [`src/Shared/Config/ToolConfig.luau`](../src/Shared/Config/ToolConfig.luau), [`src/Client/Controllers/ToolVisualController.luau`](../src/Client/Controllers/ToolVisualController.luau), and [`src/Client/Controllers/CrackController.luau`](../src/Client/Controllers/CrackController.luau) (`Tools` support added to [`tools/studio/ApplyHeroMeshTemplateDefaults.luau`](../tools/studio/ApplyHeroMeshTemplateDefaults.luau)).
  - **Verified Budgets (`<= 8` parts, `<= 400` tris, `<= 4.0` studs, `(0, 0, 0)` grip pivot):**
    - `StarterCracker`: `5/8` flat `MeshPart`s (`Grip`, `Handle`, `Band`, `Head`, `Accent`), `344/400` tris, `0.720 × 2.840 × 1.120` studs.
    - `FrostCracker`: `5/8` flat `MeshPart`s, `284/400` tris, `0.500 × 2.670 × 1.280` studs.
    - `AstralCracker`: `5/8` flat `MeshPart`s, `352/400` tris, `0.350 × 3.162 × 0.965` studs.
  - **Runtime Behavior:** Observatory `ToolWorkbench` displays locked/owned previews live from `OwnerStateDTO.Upgrades` (clear of `UpgradePad_FrostCracker` / `UpgradePad_StarCracker` prompts), equips the highest eligible Cracker in `RightHand` (`Motor6D`, `Massless`, `LocalTransparencyModifier = 0`, Reduced-Motion safe) only after server `RequestStartCrack` approval, cleans up on cancel/finish/`Humanoid.Died`/`CharacterRemoving`, and preserves server `ToolRequired` gating.

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

- **S6-ART-02 Six-Ranch Station Integration & Review #040 Ownership Fix (`StarfallRanch_Dev.rbxl` — Nov 23, 2026):**
  - **Modeled Station Kit (`<= 8` parts, `<= 1,100` tris, `0.0000` ground pivot delta; sources in [`generate_s6_pilot_assets.py`](../tools/blender/generate_s6_pilot_assets.py) & `tools/blender/exports/pilot/manifest.json`):**
    - `Incubator_Prototype`: `6/8` parts, `766` tris, `6.700 × 5.180 × 6.700` studs (`12` mounted across `Plot_1..6`, cradling incubated Star-Pods at `+2.95` studs).
    - `ToolWorkbench_Prototype`: `6/8` parts, `1,076` tris, `22.200 × 3.660 × 4.285` studs (`1` mounted at `CentralHub.ToolWorkbench`).
    - `SellStand_Prototype`: `6/8` parts, `522` tris, `6.200 × 5.060 × 4.200` studs (`6` mounted across `Plot_1..6`, brass scales + ledger + gold gem).
    - `HabitatPen_Prototype`: `5/8` parts, `620` tris, `26.660 × 2.240 × 34.660` studs (`6` mounted across `Plot_1..6`, preserving the 12-stud open aisle gate + feeding trough).
  - **Per-Plot Ownership Isolation & Live Verification:** [`StationVisualController.luau`](../src/Client/Controllers/StationVisualController.luau) mounts all `25` station models (`StarfallStationVisuals`) using each plot's `plotRot` and resolves Incubator `Locked`/`Idle`/`Incubating`/`Ready` states strictly from each plot's `PublicPlotDTO` (`OwnerUserId ~= 0` so Studio `-1..-6` test occupants resolve cleanly; `3/3` self-tests passing including two-player negative-ID `Incubator_2` isolation, plot release, and replacement-owner reassignment). Live Studio Play Solo verified `Idle (85,195,185) → Incubating (65,210,255) → Ready (255,205,45) → Hatch("Incubator_1") → Idle (85,195,185)` on `Plot_1.Incubator_1` and mirrored `SellStand` prompts on `Plot_1` & `Plot_4`.

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

For the earned-Coin equipment catalog, use the [Observatory Gear Shop concept and UI reference](./OBSERVATORY_GEAR_SHOP.md#shop-ui-and-model-handoff) for Star Lens, Trail Boots, and Bond Charm.

- **S6-ART-03 Phase 1 — Reusable Registry, Editable SVG Icons & UI Layouts (`Nov 23, 2026`):**
  - **Shared Catalog Registry:** [`src/Shared/Config/ArtAssetConfig.luau`](../src/Shared/Config/ArtAssetConfig.luau) maps all `27` launch entries (`6` Nav, `6` Critters, `3` Meteors, `3` Tools, `9` Upgrades + `FrostLure`) with `ImageId = ""` (zero broken placeholder `ContentId`s) and `SharedSelfTest` `ArtAssetConfig_Full_Catalog_Coverage` (`8/8` shared suites).
  - **Editable Icon Sources:** [`tools/art/generate_ui_icons.py`](../tools/art/generate_ui_icons.py) generates `16` editable `256×256` Observatory SVG icons under `tools/art/icons/{nav,meteors,tools,upgrades}/` (`manifest.json`).
  - **Consistent UI Layouts:** [`UIController.luau`](../src/Client/Controllers/UIController.luau) renders shared `ArtMedallion` badges across Bag (hatched critters, pods, incubating, pen, upgrades, Frost Lure) and Field Guide cards (undiscovered `?` silhouette vs. discovered dual-tone + Radiant `★`), preserving `>= 44×44` touch targets and `320×568`–`1280×720` Safe-Area bounds (`76/76` Studio startup suites passing). Final 3D portrait renders remain held pending `S6-ART-04` pilot clearance.
- **S6-ART-03 Phase 2 — Review #042 Portrait Bag Fix, Strict Medallion Tests & `256×256` PNG Exports (`Nov 23, 2026`):**
  - **Responsive Portrait Cards:** [`UIController.ComputeBagRowLayout`](../src/Client/Controllers/UIController.luau) stacks Bag row actions below text when the drawer width is `< 460 px` (`RowHeight = 112`, `>= 44 px` touch targets, `210 px` title/subtitle width on `320 px` portrait screens across Hatched `Place`/`Sell`, `Incubate`, `Hatch!`, `Feed`/`Pick Up`, Upgrades, `FrostLure`, and Checklist rows) and uses a compact top-right status pill on narrow `FieldGuideDrawer` cards.
  - **Strict Artwork & Portrait Tests:** `UIController.RunSelfTest()` verifies `ArtMedallion` in Bag (`StarSlime`, `FrostCracker`) and Field Guide (`StarSlime` discovered vs. `CometOwl` `?` undiscovered) separately without tautological fallbacks, plus live `300 px`-wide portrait Bag row geometry (`titleW = 210`, `44 px` buttons below subtitle).
  - **Upload-Ready PNG Icons:** [`tools/art/render_ui_icons_png.ps1`](../tools/art/render_ui_icons_png.ps1) exports all `16` `256×256` transparent PNGs, `manifest.json`, and a labeled `4×4` [`contact_sheet.png`](../tools/art/icons_png/contact_sheet.png) under `tools/art/icons_png/`.
