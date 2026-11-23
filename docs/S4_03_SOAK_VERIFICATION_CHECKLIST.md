# Stage 4 (`S4-03`) Real-Device Soak & Asset-Publish Checklist (`v0.4.0-s4-02-polish`)

> **Target Private Test Place:** `Bioniccat4000's Place: 11222026_1` (`placeId: 106917003014718`, `universeId: 10778558732`, `serverSize: 6`)

> **Exit Gate Requirement (`DEVELOPMENT_ROADMAP.md` / `AGENT_TASKS.md` / Review #030):** Run a **15–30 minute** soak test on **real low-end phone/tablet hardware** (Studio Device Emulator validates layout/input only, never hardware FPS/memory) confirming sustained **$\ge 30$ FPS**, zero memory leaks, and zero runtime errors on the published build with all hero assets present.

---

## 1. Pre-Publish Asset & Template Gate *(Run Before Publishing)*

Because Rojo (`default.project.json`) syncs `src/` code and does **not** serialize `.fbx` `MeshPart` templates under `ReplicatedStorage.AssetTemplates`, verify both folders inside `StarfallRanch_Dev.rbxl` before publishing to `106917003014718`:

- [ ] **6/6 Critter Templates in `ReplicatedStorage.AssetTemplates.Critters`:** `StarSlime`, `CinderPup`, `FrostBeetle`, `NebulaFox`, `SolarGolem`, `CometOwl` (4 flat `MeshPart`s `Accent`, `Body`, `Eyes`, `Secondary`; `PrimaryPart = Body`).
- [ ] **3/3 Meteor Templates in `ReplicatedStorage.AssetTemplates.Meteors`:** Import `Ember.fbx`, `Frost.fbx`, and `Astral.fbx` from `tools/blender/exports/meteors/` via **File -> Import 3D** (**Scale Unit: Studs**, **Import as Single Mesh** unchecked), move them into `ReplicatedStorage.AssetTemplates.Meteors`, and run [`tools/studio/ApplyHeroMeshTemplateDefaults.luau`](../tools/studio/ApplyHeroMeshTemplateDefaults.luau).
- [ ] **Rojo Connected & Build Synced:** Confirm `ReplicatedStorage.Shared.Constants.GAME_VERSION` equals `"0.4.0-s4-02-polish"` and `USE_MOCK_STORE == false`.
- [ ] **Read-Only Preflight Audit PASS:** Run [`tools/studio/VerifyS403SoakPreflight.luau`](../tools/studio/VerifyS403SoakPreflight.luau) in the Studio Command Bar -> confirm **`Critters=6/6`**, **`Meteors=3/3`**, **`Greybox=PASS`**, and `Status=ASSETS_READY_FOR_PUBLISH`.
- [ ] **Live Play Startup Verification (`57/57`):** Press **Play (F5)** in Studio -> confirm all `57` Server/Client self-test suites pass, `[PlotVisualController] Runtime Template Verified` prints all `6` species, and `[MeteorService] Runtime Template Verified` prints real **`Ember`**, **`Frost`**, and **`Astral`** (all with `PromptOk=true | ClaimOk=true`, zero mock fallback!).
- [ ] **Publish & Re-Verify on `106917003014718`:** Save `StarfallRanch_Dev.rbxl`, publish to `106917003014718` (`serverSize: 6`), run [`VerifyS403SoakPreflight.luau`](../tools/studio/VerifyS403SoakPreflight.luau) (confirm `Status=READY_FOR_SOAK`), and boot once in a private live server to confirm `6/6` critters + `3/3` meteors render with working `RescuePrompt`s.

---

## 2. Real-Device Test Setup

- **Device Under Test (Record Below):** Low-end mobile phone or budget tablet running the native Roblox mobile client (NOT Studio Device Emulator).
- **Server Target:** Private server / Playtest instance on `106917003014718` (`MaxPlayers = 6`). If multiple devices or testers join, aim for active pens across multiple plots (`<= 30` critters total server-wide).
- **Performance & Memory Overlays:**
  1. Open Roblox Menu -> **Settings -> Performance Stats -> ON** (shows live `FPS` / Frame ms and `MEM`).
  2. Open chat or quick-console (`/console`) -> switch between **Log** (Client/Server warnings & errors) and **Memory** (`Total`, `LuaHeap`, `PlaceMemory` / `GraphicsMeshParts`) at each checkpoint below.

---

## 3. Repeatable 15–30 Minute Soak Loop

Repeat **3–6 full 5-minute cycles** continuously without closing the client:

1. **Crater Rescue & Tool Progression:**
   - Walk/tap through Central Crater -> **Ember Basin** (`Ember` rock) and **Frost Ridge** (`Frost` rock once `FrostCracker` is unlocked).
   - Trigger **Frost Lure** from Observatory Hub -> follow cyan guide beam -> complete 2-beat Frost Fracture crack.
   - Wait for/catch a timed **Astral Fall** (`Astral` rock + vertical beacon + gold target ring) -> complete Astral Pulse crack.
2. **Hatching, 30-Critter Stress & Pen Management:**
   - Fill `Incubator_1` / `Incubator_2`, hatch pods (check **Radiant** gold halo & sparkles when rolled, and verify `"NEW DISCOVERY"` Field Guide toast), place/feed/pick up/sell critters across `Pen_1..Pen_5` (stressing rebuilds & `PlotVisualController` hop animations).
3. **UI, Hub/Ranch Travel & Accessibility Stress:**
   - Toggle **Bag**, **Guide** (Cosmic Field Guide checklist), and **Settings** repeatedly on both narrow/portrait and landscape mobile orientation.
   - Travel back and forth via **Hub** / **Ranch** top-HUD buttons (verify no camera/prompt lockups and `2.0s` cooldown banner).
   - Toggle **Reduced Motion ON -> OFF** while near active **Radiant** critters and meteor cracks, confirming `RadiantSparkles`, hop tweening, and landing streaks stop and resume cleanly.

---

## 4. Device Soak Telemetry Log (`15–30 Minutes`)

| Checkpoint | Elapsed | FPS (Target `>= 30`) | Frame Time (ms) | Total Memory (MB) | `LuaHeap` / `GraphicsMeshParts` (MB) | Script Errors (`Log`) | Notes / Active Plots & Critters |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| Baseline | `T+2m` | | | | | | |
| Midpoint 1 | `T+10m` | | | | | | |
| Min Gate | `T+15m` | | | | | | |
| Checkpoint | `T+20m` | | | | | | |
| Final End | `T+30m` | | | | | | |

### Pass / Fail Thresholds
- [ ] **Sustained Frame Rate:** Average & steady-state FPS remains **$\ge 30$ FPS** throughout the 15–30 minute run with active critters (`<= 30`), incubators, and meteors visible.
- [ ] **Memory Stability (Zero Leak):** Total Memory and `LuaHeap` plateau after initial warmup (no continuous monotonic climb across `T+10m -> T+30m`; destroyed pods/meteors/drawers release cleanly).
- [ ] **Runtime Cleanliness:** `0` uncaught script errors in Client or Server Developer Console logs; no orphaned visuals on plot leave/rejoin; all **Ember**, **Frost**, and **Astral** meteors spawn grounded with working `Crack` prompts.

---

## 5. Physical Input & Safe-Area Field Check

*(Confirms real-device touch/gamepad ergonomics noted in Review #030.)*

- [ ] **Top HUD Reachability (`>= 44×44` targets):** `Coins/Rate/Bag` bar and `Hub` / `Ranch` / `Bag` / `Guide` / `⚙` buttons never overlap Roblox CoreUI or device notches/home indicators.
- [ ] **Bag & Field Guide Drawers:** Both scroll smoothly by touch drag, stay clear of the top HUD on compact landscape phones, and reveal species details/clues cleanly when tapped.
- [ ] **Meteor Quick-Burst:** Tapping the **Quick Burst** zone on touch (or pressing `E`/`Space` on keyboard / `X` on physical gamepad if tested) is responsive and never leaves the crack bar stuck.
- [ ] **Gamepad (If Tested):** `Y` (Bag), `L1` (Field Guide), `B` (Close Drawer), and D-pad traversal stay contained inside `SelectionGroup` without escaping to background buttons.

---

## 6. Sign-Off Record

- **Tested Device & OS:** `__________________________`
- **Tester / Date:** `__________________________`
- **Duration (`15–30 min`):** `__________ min`
- **Outcome:** `[ ] PASS` / `[ ] CHANGES REQUIRED`
- **Record Results:** Summarize checkpoint metrics above and log sign-off in `docs/AGENT_REVIEWS.md` / [`docs/AGENT_TASKS.md`](./AGENT_TASKS.md) before proceeding to **Stage 5 (`S5-01`)**.
