# Stage 4 (`S4-03`) Real-Device Soak & Asset-Publish Checklist (`v0.4.1-s4-03-soak`)

> **Target Private Test Place:** `Bioniccat4000's Place: 11222026_1` (`placeId: 106917003014718`, `universeId: 10778558732`, `serverSize: 6`)

> **Exit Gate Requirement (`DEVELOPMENT_ROADMAP.md` / `AGENT_TASKS.md` / Review #030):** Run a **15–30 minute** soak test on **real low-end phone/tablet hardware** (Studio Device Emulator validates layout/input only, never hardware FPS/memory) confirming sustained **$\ge 30$ FPS**, zero memory leaks, and zero runtime errors on the published build with all hero assets present.

---

## 1. Pre-Publish Asset & Template Gate *(Run Before Publishing)*

Because Rojo (`default.project.json`) syncs `src/` code and does **not** serialize `.fbx` `MeshPart` templates under `ReplicatedStorage.AssetTemplates`, verify both folders inside `StarfallRanch_Dev.rbxl` before publishing to `106917003014718`:

- [x] **6/6 Critter Templates in `ReplicatedStorage.AssetTemplates.Critters`:** `StarSlime`, `CinderPup`, `FrostBeetle`, `NebulaFox`, `SolarGolem`, `CometOwl` (4 flat `MeshPart`s `Accent`, `Body`, `Eyes`, `Secondary`; `PrimaryPart = Body`).
- [x] **3/3 Meteor Templates in `ReplicatedStorage.AssetTemplates.Meteors`:** Import `Ember.fbx`, `Frost.fbx`, and `Astral.fbx` from `tools/blender/exports/meteors/` via **File -> Import 3D** (**Scale Unit: Studs**, **Import as Single Mesh** unchecked), move them into `ReplicatedStorage.AssetTemplates.Meteors`, and run [`tools/studio/ApplyHeroMeshTemplateDefaults.luau`](../tools/studio/ApplyHeroMeshTemplateDefaults.luau).
- [x] **Rojo Connected & Build Synced:** Confirm `ReplicatedStorage.Shared.Constants.GAME_VERSION` equals `"0.4.1-s4-03-soak"` and `USE_MOCK_STORE == false`.
- [x] **Read-Only Preflight Audit PASS:** Run [`tools/studio/VerifyS403SoakPreflight.luau`](../tools/studio/VerifyS403SoakPreflight.luau) in the Studio Command Bar -> confirm **`Critters=6/6`**, **`Meteors=3/3`**, **`Greybox=PASS`**, and `Status=ASSETS_READY_FOR_PUBLISH`.
- [x] **Live Play Startup Verification (`57/57`):** Press **Play (F5)** in Studio -> confirm all `57` Server/Client self-test suites pass, `[PlotVisualController] Runtime Template Verified` prints all `6` species, and `[MeteorService] Runtime Template Verified` prints real **`Ember`**, **`Frost`**, and **`Astral`** (all with `PromptOk=true | ClaimOk=true`, zero mock fallback!).
- [ ] **Publish & Re-Verify on `106917003014718`:** Save `StarfallRanch_Dev.rbxl`, publish to `106917003014718` (`serverSize: 6`), run [`VerifyS403SoakPreflight.luau`](../tools/studio/VerifyS403SoakPreflight.luau) on the cloud place and record `Status=READY_FOR_SOAK`, `PlaceId`, `PlaceVersion`, `MaxPlayers=6`, runtime build/source SHA, and `6/6` critters + `3/3` meteors (per Review #032). *(Cloud place `PlaceVersion=21` passed `READY_FOR_SOAK`, `6/6` critters, `3/3` meteors, and `59/59` Play suites, but remains unchecked because `MaxPlayers=60` instead of `6` — set Place Max Players to `6` and publish `0.4.2-s4-04-starter-save` before the 6-player soak.)*

### Cloud-Place Preflight Record (`PlaceId=106917003014718`, `PlaceVersion=21` — `2026-11-23`)
- **Build & Source Identity:** `GAME_VERSION=0.4.2-s4-04-starter-save | SCHEMA_VERSION=2 | USE_MOCK_STORE=false | PlaceId=106917003014718 | PlaceVersion=21 | GameId=10778558732 | MaxPlayers=60` (Edit & Server `Players.MaxPlayers=60`; `SourceFingerprint: hasTagActiveMeteor=true | hasPerfBaselineMemMb=true | hasStarterCompletedHint=true`, matching `f12f3a4` + `Stage3VerificationSuite` Command-Bar init guard).
- **Preflight Summary:** `Status=READY_FOR_SOAK | Greybox=PASS | Critters=6/6 | Meteors=3/3`
  - `Critters=6/6`: `StarSlime`, `CinderPup`, `FrostBeetle`, `NebulaFox`, `SolarGolem`, `CometOwl` (all 4 MeshParts, `PivotDelta=0.0000`, `EyesZ < 0`).
  - `Meteors=3/3`: `Ember`, `Frost`, `Astral` (all 3 MeshParts, `PivotDelta=0.0000`).
- **Cloud Studio Play (`59/59`):** `59/59` startup suites passed on `106917003014718` (`Mode=LiveProfileStore`, `Store=StarfallRanch_StudioDev_v1`, `DataStoreState=Access`).
- **Build & Cap Notes (Review #032):**
  1. `MaxPlayers=60` (not `6`) on `PlaceVersion=21` — update **Game Settings -> Places -> Max Players = `6`** before running the 6-player soak.
  2. Solo Run #2 (`iPhone 17`) ran on `c8a99d9` (`0.4.1-s4-03-soak`), whereas the open cloud place (`PlaceVersion=21`) now has `0.4.2-s4-04-starter-save` (`f12f3a4`) synced via Rojo; publish to Roblox before launching the 6-player mobile soak.

---

## 2. Real-Device Test Setup

- **Device Under Test (Record Below):** Low-end mobile phone or budget tablet running the native Roblox mobile client (NOT Studio Device Emulator).
- **Server Target:** Private server / Playtest instance on `106917003014718` (`MaxPlayers = 6`). If multiple devices or testers join, aim for active pens across multiple plots (`<= 30` critters total server-wide).
- **Performance & Memory Overlays:**
  1. Tap **`⚙` (Settings) -> `Soak Perf Stats: ON`** inside the game HUD. This opens a compact non-blocking top-left monitor showing live **`FPS`**, **`Avg / Min FPS`**, **`Frame ms`**, **`Mem MB`**, **`LuaHeap MB`**, active Visuals (`Vis`), active Meteors (`Met`), and elapsed soak time (`T+MM:SS`), and automatically prints a `[SoakTelemetry]` baseline + 1-minute summary to the Developer Console (`/console`). *(Roblox's built-in mobile Performance Stats shows CPU/GPU frame time and Memory rather than a direct FPS counter.)*
  2. Optionally also enable Roblox Menu -> **Settings -> Performance Stats -> ON**, and open `/console` (**Memory** / **Log** tabs) at each checkpoint below to confirm zero warnings/errors alongside the in-game readout.

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
| Final End | `T+30:00+` | `60 (Avg 60 / Min 58)` | `16.7` | `839 (+2 vs baseline)` | `Not captured separately` | `0` | `Run #2 (iPhone 17, build c8a99d9): 1/6 occupied plot (solo) with max placed critters (5/5 pens); Vis 5, Met 6; spawns normal; GUI clean` |

### Run #1 Log (Initial Mobile Check — `iPhone 17`, `2026-11-23`)
- **Reported Reading (`T+15:00+`):** `FPS 60 (Avg 60 / Min 58) | 16.7ms | Mem 818MB (Lua 254.8MB) | Vis 0 | Met 0`
- **Notes & Gaps Remaining for Final `S4-03` Sign-Off:**
  1. `Met 0` in Run #1 was caused by `UIController` checking `workspace.StarfallActiveMeteors` instead of `#CollectionService:GetTagged("StarfallActiveMeteor")` (fixed in `UIController.luau` with live `Mem (Δ)` delta tracking).
  2. `Vis 0` indicates no critters were placed in habitat pens during that capture — Run #2 must exercise active gameplay (`Vis > 0`, `Met > 0`, Ember/Frost/Astral cracks, Bag/Field Guide/Settings toggles, Hub/Ranch travel).
  3. Capture both a `T+2m` baseline and `T+15m+` end reading (or `ΔMB` / `/console` `[SoakTelemetry]` lines), confirm `0` console script errors & clean touch controls, and test on a lower-end phone/tablet if available (or note transparently if `iPhone 17` is the only physical test device).

### Run #2 Log (Active Mobile Soak — `iPhone 17`, `2026-11-23`)
- **Reported Reading (`T+30:00+`):** `FPS 60 (AVG 60 / Min 58) | 16.7 ms | T+ 30:00+ | Mem: 839mb (+2) | Vis 5 | Met 6`
- **Tester Confirmations:**
  - **Occupancy & Load:** `1` occupied plot (`1/6`, solo) with **max placed critters** (`5/5` pens filled; `Vis 5` reflects client visuals folder children including effects).
  - **Meteor Spawns:** Confirmed normal (`Met 6` active during soak; real `Ember`, `Frost`, and `Astral` templates also passed `PromptOk=true | ClaimOk=true` in Studio Play `57/57`).
  - **GUI & Touch Controls:** Confirmed working cleanly on `iPhone 17`.
  - **Script Errors:** `0` errors confirmed.
- **Build / Hardware Notes:**
  - Overlay format (`+2` delta and `Met 6`) confirms the `c8a99d9` overlay/meteor-counter build is active; local `StarfallRanch_Dev.rbxl` (`PlaceId=0`) also passed `VerifyS403SoakPreflight` (`Status=ASSETS_READY_FOR_PUBLISH | Greybox=PASS | Critters=6/6 | Meteors=3/3`) and `57/57` live Studio Play startup suites (with `UIController` synced and `[SoakTelemetry]` reporting `Meteors=6`).
  - **Device Availability:** Tester confirmed **`iPhone 17` is the only physical mobile device available** — the low-end phone/tablet check remains explicitly open per Review #031.
- **Remaining Open Caveats for ChatGPT Review #031 Sign-Off:**
  1. Published cloud place (`106917003014718`) `PlaceVersion` + direct `VerifyS403SoakPreflight.luau` (`Status=READY_FOR_SOAK`) check has not been executed in Studio on the cloud place yet (local `StarfallRanch_Dev.rbxl` passed `ASSETS_READY_FOR_PUBLISH` + `57/57` Play suites).
  2. Scope caveats left transparently open: solo `1/6` plot (`5` placed critters) rather than 6-player server load, `T+30:00+` end reading + `+2 MB` baseline delta without separate intermediate `T+2m`/`T+15m` checkpoint rows, gamepad not tested, and low-end phone/tablet hardware check left open (`iPhone 17` only per Review #031).

### Pass / Fail Thresholds
- [ ] **Sustained Frame Rate:** Average & steady-state FPS remains **$\ge 30$ FPS** throughout the 15–30 minute run with active critters (`<= 30`), incubators, and meteors visible. *(Solo `iPhone 17` Run #2 passed `60 FPS` avg / `58 FPS` min, `16.7 ms` on `1/6` plot, `5/5` pens, `Met 6`; 6-player server load + low-end device coverage remain open per Review #032.)*
- [ ] **Memory Stability (Zero Leak):** Total Memory and `LuaHeap` plateau after initial warmup (no continuous monotonic climb across `T+10m -> T+30m`; destroyed pods/meteors/drawers release cleanly). *(Solo `iPhone 17` Run #2 ended at `839 MB (+2 MB vs baseline)` at `T+30:00+`; intermediate total & `LuaHeap` checkpoints remain open per Review #032.)*
- [ ] **Runtime Cleanliness:** `0` uncaught script errors in Client or Server Developer Console logs; no orphaned visuals on plot leave/rejoin; all **Ember**, **Frost**, and **Astral** meteors spawn grounded with working `Crack` prompts. *(Solo `iPhone 17` Run #2 reported `0` errors and normal spawns, and Studio Play `57/57` verified real `Ember`/`Frost`/`Astral` `PromptOk=true | ClaimOk=true`; explicit per-family live cracks during the 6-player published soak remain open per Review #032.)*

---

## 5. Physical Input & Safe-Area Field Check

*(Confirms real-device touch/gamepad ergonomics noted in Review #030.)*

- [x] **Top HUD Reachability (`>= 44×44` targets):** `Coins/Rate/Bag` bar and `Hub` / `Ranch` / `Bag` / `Guide` / `⚙` buttons never overlap Roblox CoreUI or device notches/home indicators. *(Confirmed `"gui works cleanly"` on solo `iPhone 17` Run #2.)*
- [x] **Bag & Field Guide Drawers:** Both scroll smoothly by touch drag, stay clear of the top HUD on compact landscape phones, and reveal species details/clues cleanly when tapped. *(Confirmed `"gui works cleanly"` on solo `iPhone 17` Run #2.)*
- [ ] **Meteor Quick-Burst:** Tapping the **Quick Burst** zone on touch (or pressing `E`/`Space` on keyboard / `X` on physical gamepad if tested) is responsive and never leaves the crack bar stuck. *(Solo `iPhone 17` Run #2 reported `"spawns were normal"` and `"gui works cleanly"`; explicit Quick-Burst + per-family live crack confirmation on the 6-player published soak remains open per Review #032.)*
- [ ] **Gamepad (If Tested):** `Y` (Bag), `L1` (Field Guide), `B` (Close Drawer), and D-pad traversal stay contained inside `SelectionGroup` without escaping to background buttons. *(Optional; not tested in Run #2.)*

---

## 6. Sign-Off Record

- **Tested Device & OS:** `iPhone 17 (only physical test device available; low-end device check left open per Review #031)`
- **Tester / Date:** `Human Lead / 2026-11-23`
- **Duration (`15–30 min`):** `30+ min (Run #2; Run #1 was 15+ min)`
- **Outcome:** `[ ] PASS` / `[ ] CHANGES REQUIRED` *(Run #2 accepted as solo mobile smoke test in Review #032; `S4-03` held `[~]` pending published cloud-place `106917003014718` preflight & 6-player/intermediate-telemetry soak)*
- **Record Results:** Summarize checkpoint metrics above and log sign-off in `docs/AGENT_REVIEWS.md` / [`docs/AGENT_TASKS.md`](./AGENT_TASKS.md) before proceeding to **Stage 5 (`S5-01`)**.
