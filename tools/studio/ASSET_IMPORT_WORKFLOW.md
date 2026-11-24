# Starfall Ranch — Reproducible Studio FBX Import & Styling Workflow

> **Purpose:** Documents how Blender-exported `.fbx` models are imported into `StarfallRanch_Dev.rbxl`, styled via [`ApplyHeroMeshTemplateDefaults.luau`](./ApplyHeroMeshTemplateDefaults.luau), placed under `ReplicatedStorage.AssetTemplates`, and verified in Play Solo & private published builds. (Added per Review #038.)

---

## 1. Generate Editable `.blend` + Studio-Ready `.fbx` Files

- **Critters & Meteors (Stage 4):** `blender --background --factory-startup --python tools/blender/generate_lowpoly_assets.py` -> `tools/blender/exports/{critters,meteors}/*.fbx`
- **Launch Cracker Tools (S6-ART-01):** `blender --background --factory-startup --python tools/blender/generate_cracker_tools.py` -> `tools/blender/exports/tools/*.fbx`
- **Stage 6 Pilot + Incubator Prototype (S6-ART-04 / S6-ART-02):** `blender --background --factory-startup --python tools/blender/generate_s6_pilot_assets.py` -> `tools/blender/exports/pilot/*.fbx`

All generators enforce:
- `1 Blender unit = 1 Roblox stud` (`global_scale=0.01`, `apply_unit_scale=True`, `FBX_SCALE_ALL`, `axis_forward="-Z"`, `axis_up="Y"`, `bake_space_transform=True`)
- Flat top-level `MeshPart`s (`<= 8` parts per model), outward normals, zero `SurfaceAppearance`
- Ground-contact pivot (`minY == 0`) for critters, meteors, and stations; grip-centered pivot `(0, 0, 0)` for handheld tools

---

## 2. Import `.fbx` into Roblox Studio (`StarfallRanch_Dev.rbxl`)

1. Open `StarfallRanch_Dev.rbxl` in Roblox Studio (Edit mode) with Rojo serving (`tools/start-rojo.ps1`).
2. Go to **File → Import 3D** and select the `.fbx` file(s).
3. In the Import 3D settings:
   - **Scale Unit:** `Studs`
   - **Single Mesh:** **Unchecked** (preserves separate `Grip`/`Handle`/`Band`/`Head`/`Accent`, `Body`/`Secondary`/`Eyes`/`Accent`, etc.)
   - **Anchored:** Optional (the styling helper sets `Anchored = true` on templates).
4. Click **Import**.

---

## 3. Organize Under `ReplicatedStorage.AssetTemplates` & Apply Defaults

Move imported `Model` instances into their canonical template folders (note `default.project.json` does not serialize binary `.fbx` `MeshPart` assets; they live inside the `.rbxl` place file):

- `ReplicatedStorage.AssetTemplates.Critters.<SpeciesId>`
- `ReplicatedStorage.AssetTemplates.Meteors.<TraitId>`
- `ReplicatedStorage.AssetTemplates.Tools.<CrackerToolId>`
- `ReplicatedStorage.AssetTemplates.Pilot.<PilotModelName>` *(isolated from shipped Stage 4 baselines during pilot review)*

Then paste and run [`tools/studio/ApplyHeroMeshTemplateDefaults.luau`](./ApplyHeroMeshTemplateDefaults.luau) in the **Studio Command Bar**:
- Strips any `SurfaceAppearance`
- Applies `CritterConfig`, `MeteorConfig`, `ToolConfig`, and `Incubator_Prototype` materials (`SmoothPlastic` / `Metal` / `Glass` / `Neon`) and colors
- Sets `CanCollide = false`, `CanQuery = false`, `CanTouch = false`, `Anchored = true`
- Assigns `PrimaryPart` (`Body`, `RockBody`, `Grip`, or `Base`)
- Verifies `<= 8` parts, height/dimension caps, and ground pivot delta `<= 0.05`

---

## 4. Save & Verify Runtime Loading

1. **Save** `StarfallRanch_Dev.rbxl` (`Ctrl+S`).
2. Press **Play (F5)** and inspect the Output window:
   - `[PlotVisualController] Runtime Template Verified ...` (6/6 critters)
   - `[MeteorService] Runtime Template Verified ...` (3/3 meteors)
   - `[StarfallRanch][SelfTest] PASS: All 4 ToolVisualController client test suites passed.`
   - All `ToolWorkbench` displays and held Crackers report `AssetSource = MeshTemplate`.
3. Before publishing to the private test place (`106917003014718`), run `tools/build-place.ps1` / sync Rojo into `StarfallRanch_Dev.rbxl`, save, publish to Roblox, and verify `MeshTemplate` loading in a fresh private server.
