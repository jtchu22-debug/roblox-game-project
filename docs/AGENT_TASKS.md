# Prioritized MVP Task List & Project Board (`AGENT_TASKS.md`)

> **Last Updated:** November 22, 2026
> **Current Active Milestone** — **S6-ART-01 is ready for private implementation.** S5-01 telemetry passed, and all six clients passed the Studio multiplayer functionality check. The S4-03 published six-player low-end soak remains open before the S5-02 wider playtest. Round 3 product approval remains pending. [Review #037](./AGENT_REVIEWS.md#review-037--six-client-studio-check-and-cracker-art-handoff)

---

## Status Legend
- `[x]` **COMPLETED** — Verified and committed to repository.
- `[~]` **IN REVIEW / BLOCKED ON EXTERNAL STEP** — Waiting on Human Lead or ChatGPT review.
- `[ ]` **TODO** — Queued and ordered by priority & dependency.

---

## Stage 0: Research, Audit & Sign-Off (Completed)

| Task ID | Owner | Task Description | Deliverable File | Status |
| :---: | :---: | :--- | :--- | :---: |
| **T-001–T-010** | Gemini + Human | Initial market research, 12 concepts, GDD, architecture, Blender starter script, GitHub setup. | `docs/**`, `tools/blender/` | `[x]` |
| **T-011** | ChatGPT | Independent Technical Director audit of Phase 0 package (`CHANGES REQUIRED`). | [CHATGPT_REVIEW.md](./CHATGPT_REVIEW.md), [AGENT_REVIEWS.md](./AGENT_REVIEWS.md) | `[x]` |
| **T-012 / R-001–R-006** | Gemini | Integrate ChatGPT audit revisions: corrected research, unified critter loop, bounded integer economy, hardened server architecture, Creator Rewards / cosmetics-only policy, 5-stage gated roadmap. | `docs/**`, `README.md` | `[x]` |
| **R-007** | **Human Lead** | Approve narrowed **Starfall Ranch** vertical-slice prototype (`ADR-001`–`ADR-007`) and authorize Stage 1 environment prep. | [DECISIONS.md](./DECISIONS.md) | `[x]` |

---

## Stage 1: Foundation + Mock Vertical Slice (`R-008` — Priority P0)

> **Goal:** Deliver one complete, exploit-checked 5-minute playable loop (`Meteor Rescue -> Incubate -> Keep-vs-Sell -> Ranch Upgrade`) with 2 plots and `MockStore` persistence.

| Task ID | Priority | Depends On | Owner | Task Description & Acceptance Criteria | Deliverable / Path | Status |
| :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| **S1-00** | **P0** | `R-007` | Gemini | **Environment & Architecture Skeleton:** Pin Rojo `v7.4.4` (`aftman.toml`, `rokit.toml`, Studio plugin), create `src/` ModuleScript skeletons (no gameplay logic yet), smoke-test `build.rbxlx`, write `CODING_STANDARDS.md` & `DEVELOPMENT_SETUP.md`. | `src/**`, `tools/*.ps1`, `docs/CODING_STANDARDS.md`, `docs/DEVELOPMENT_SETUP.md` | `[x]` |
| **S1-01** | **P0** | `S1-00` | Gemini | **Shared Config & Bounded Math:** Populate `CritterConfig` (*StarSlime* `2/s\|40`, *NebulaFox* `4/s\|95`, *SolarGolem* `7/s\|180`), `MeteorConfig` (*Ember*, *Frost*, *Astral*), `UpgradeConfig` (`60 / 150 / 320`), and deterministic `EconomyMath.SettleElapsedCoins` + `FormatUtil` + `ValidationUtil` + `SharedSelfTest`. | `src/Shared/Config/`, `src/Shared/Util/` | `[x]` |
| **S1-02** | **P0** | `S1-00` | Gemini | **Idempotent Greybox Map Generator:** Implemented `GreyboxBuilder` + Studio Command-Bar script generating tagged `Workspace.StarfallGreyboxRoot`, updated with ChatGPT Review #002 ownership/off-tree swap and strict contract validation fixes. | `src/Shared/Util/GreyboxBuilder.luau`, `tools/studio/GenerateGreyboxMap.luau` | `[x]` |
| **S1-03** | **P0** | `S1-01` | Gemini | **Network & Inbound Validation:** Implemented `NetworkService` remote creation (`SyncOwnerState`, `SyncPublicPlots`, `MeteorLifecycle`, `RequestInitialSnapshot`, `RequestStartCrack`, `RequestFinishCrack`, `RequestPlotAction`, `RequestBuyUpgrade`), strict `ValidationUtil` checks, per-player token-bucket rate limiting, and `RunSelfTest()`. | `src/Server/Services/NetworkService.luau` | `[x]` |
| **S1-04** | **P0** | `S1-01`, `S1-03` | Gemini | **Mock Data Service:** Implemented in-memory `MockStore` profile lifecycle (`Loading -> Ready -> Closing`), `IsReady(player)` / `GetProfile(player)` boundary, independent profile tables, queued pre-ready snapshot delivery, existing-player startup init, `UIController` snapshot listener, and `DataService.RunSelfTest()`. | `src/Server/Services/DataService.luau`, `src/Client/Controllers/UIController.luau`, `src/Client/ClientInit.client.luau` | `[x]` |
| **S1-05** | **P0** | `S1-01`, `S1-04` | Gemini | **Single-Writer Economy Service:** Implemented `DataService` MockStore environment guard (Review #004) + `EconomyService` atomic transitions with reserved hatch capacity, fractional server clock settlement (`GetServerTimeNow`), cap-accurate `CoinsEarned`, 1s accrual loop, and 5 `RunSelfTest()` suites (Review #005 fixes). | `src/Server/Services/EconomyService.luau`, `src/Server/Services/DataService.luau`, `src/Shared/Types.luau` | `[x]` |
| **S1-06** | **P0** | `S1-02`, `S1-04`, `S1-05` | Gemini | **Plot Allocation & Public DTO Sync:** Implemented unique `Plot_1`/`Plot_2` assignment & leave release, `NoFreePlot` admission rejection, finite distance & fail-closed station authorizer (Review #007), live 1s incubator countdown labels, `ProximityPrompt`s, `SyncPublicPlots`, and `PlotService.RunSelfTest()`. | `src/Server/Services/PlotService.luau`, `src/Server/Services/EconomyService.luau`, `src/Client/Controllers/PlotVisualController.luau` | `[x]` |
| **S1-07** | **P0** | `S1-02`, `S1-05`, `S1-06` | Gemini | **Meteor Spawning & Nonce Claim Protocol (Review #008 Fixes):** Unprefixed 36-char GUID `MeteorUID`s passing `NetworkService` 40-char validation, separate Starter (`StarSlime`) & Wild Crater pools, centralized `ClaimReleased` & single `Despawn` notifications, 28-stud abandonment / character / leave cleanup sweep, `CrackController` prompt & cancellation bridge, and 4 `MeteorService.RunSelfTest()` suites (Approved in Review #009). | `src/Server/Services/MeteorService.luau`, `src/Client/Controllers/CrackController.luau` | `[x]` |
| **S1-08** | **P0** | `S1-03`–`S1-07` | Gemini | **Client Controllers & Accessibility Polish (`v0.1.12-s1-09-fix`):** Implemented `SoundController`, `PlotVisualController`, `UIController` (deterministic `AbsoluteContentSize` Bag canvas, post-`RenderStepped` scroll/gamepad focus restore, `>= 320px` stacked narrow-HUD reflow & `RunSelfTest()`), `CrackController`, and `InputController`. *(Studio startup and UI self-tests passed. The project owner confirmed mobile play.)* | `src/Client/Controllers/*.luau`, `src/Client/ClientInit.client.luau`, `src/Shared/Constants.luau` | `[x]` |
| **S1-09** | **P0** | `S1-08` | Gemini + Human | **Stage 1 Adversarial & 2-Player Verification (`v0.1.12-s1-09-fix`):** All 33 startup suites passed. The project owner confirmed the mobile check, two-player Studio run, and timed solo playthrough. [Stage 1 sign-off](./AGENT_REVIEWS.md#review-011-follow-up--stage-1-sign-off-and-stage-2-handoff). | `src/Server/Services/Stage1VerificationSuite.luau`, `docs/S1_09_VERIFICATION_CHECKLIST.md` | `[x]` |

---

## Stage 2: Discovery Playtest Gate (`R-009` — Priority P0)

| Task ID | Priority | Depends On | Owner | Task Description & Acceptance Criteria | Deliverable / Path | Status |
| :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| **S2-01** | **P0** | `S1-09` | Human + ChatGPT | **Uncoached Playtest & Stage 2C (`v0.2.4-s2c-astral-fall` -> Review #015 Fix):** Round 2 (`N = 3`), **Review #013 (`d9036b4`)**, **Review #014 (`c604289`)**, and **Review #015 (`c095138`)** drove timed **Astral Fall** (fixed in Stage 3A to exact `75s` warning-to-warning fall cadence in `MeteorService.luau`), marked Basin/Ridge routes, mobile declutter, and Frost Lure fixes. **Human Lead fast-tracked progression into Stage 3–6 on Nov 21, 2026** (skipping extended Round 3 wait while retaining ChatGPT commit-gate confirmation per step). | [S2_01_PLAYTEST_KIT.md](./S2_01_PLAYTEST_KIT.md), [AGENT_REVIEWS.md](./AGENT_REVIEWS.md) | `[x]` |

---

## Stage 3: Persistence Alpha (`ProfileStore` & 6-Plot Scale — Priority P1)

| Task ID | Priority | Depends On | Owner | Task Description & Acceptance Criteria | Deliverable / Path | Status |
| :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| **S3-01** | **P1** | `S2-01` (Fast-Track) | Gemini | Vendor pinned `MadStudioRoblox/ProfileStore` (`v1.0.3`, commit `45c9847cbcf1fc260369c50eb335aba7c35aecdd`, preserving upstream **Apache-2.0** `LICENSE` — correcting Stage 0 MIT note) and document commit/SHA-256 in `VERSION.md`. | `src/Server/Libs/ProfileStore/` | `[x]` |
| **S3-02** | **P1** | `S3-01` | Gemini | Upgrade `DataService` to `ProfileStore` (`StartSessionAsync`, `OnSessionEnd` lock-loss kick, `ReconcileAndMigrateProfileData`, final Coin settlement before teardown, per-operation `Profile.OnFinalSaveResult` ownership confirmation, strict `DataStoreState == "Access"` gate on live paths, `BindToClose` flush, offline `MaturesAt` preservation, plus live API-backed `Write`/`Verify` round-trip verified in [Review #021](./AGENT_REVIEWS.md#review-021--s3-02-live-datastore-verification)). | `src/Server/Services/DataService.luau`, `src/Server/Libs/ProfileStore/init.luau`, `tools/studio/RunLiveDataStoreSmokeTest.luau` | `[x]` |
| **S3-03** | **P1** | `S3-02` | Gemini | Scale greybox map & `PlotService`/`MeteorService` from `2` $\rightarrow$ `6` plots (`MaxPlayers = 6`), build spacious `76×68` plots with `16`-stud central aisles + `CentralHub` (Observatory landmark, Tool Workbench for `FrostCracker`/`StarCracker`, Frost Lure Kiosk, Contracts Board placeholder) per the [ranch and hub brief](./STARFALL_RANCH_GAMEPLAY_PLAN.md#ranch-plots-central-hub-and-navigation), add server-acknowledged **Hub**/**Ranch** navigation controls (`RequestNavigate` `RemoteFunction` + `2.0s` client cooldown, `320px` & `667×375` tested), late-join `PublicPlotDTO` resync & plot reuse `PlotRevision` visual cleanup, preserve `PenSlot_4`, add `BagCap_20` & `PenSlot_5`, and regenerate/verify `2.0.0-s3-03-6plots` on published 6-player test place (`106917003014718`). Approved in [Review #026](./AGENT_REVIEWS.md#review-026--s3-03-technical-sign-off). | `src/Server/Services/PlotService.luau`, `src/Shared/Util/GreyboxBuilder.luau`, `src/Client/Controllers/` | `[x]` |
| **S3-04** | **P1** | `S3-03` | ChatGPT + Gemini | Pass full persistence failure-injection suite (`DataService` Suite 12, `Stage3VerificationSuite` Suites 1–3, live API `Write`/`Verify` across fresh sessions on `106917003014718`), `MeteorService` Suite 5 & `PlotVisualController` Suite 3 (`30`-critter budget), 6-client live Studio verification (unique ranches, `Player2` leave/`Player10` freed-ranch handoff, mid-crack Hub release), and overlapping two-server live persistence handoff ([Review #028](./AGENT_REVIEWS.md#review-028--s3-04-technical-sign-off)). | `src/Server/Services/Stage3VerificationSuite.luau`, `tools/studio/RunS304LivePersistenceCheck.luau`, `docs/S3_04_VERIFICATION_CHECKLIST.md` | `[x]` |

---

## Stage 4: Hero Low-Poly Art, Mobile Polish & Soak Beta (Priority P1–P2)

| Task ID | Priority | Depends On | Owner | Task Description & Acceptance Criteria | Deliverable / Path | Status |
| :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| **S4-01** | **P2** (`R-010`) | `S2-01` (Go) | Gemini + Human | Validated **one** sample Blender `.fbx` export (`StarSlime`) in Studio `Place1`, upgraded `generate_lowpoly_assets.py` (embedded meteor shards, safe rerun guard, validated FBX exporter) + art-approved **v2 soft-stylized critter pass** (`tools/blender/export_starslime_v2.py` -> `variants/StarSlime_v2.fbx`, darker emerald-mint `StarSlime` base `(42, 152, 116)`, chunky `SolarGolem`, angular meteors), exported & round-trip verified **6 critters + 3 meteors** ($\le 400$ tris each), updated `ApplyHeroMeshTemplateDefaults.luau`, and verified all v2 critters in `StarfallRanch_Dev.rbxl` (`4/8` MeshParts, `5/8` Radiant, `0.0000` pivot delta, `-Z` forward, `<= 6.415` studs Fed `1.15×` height). | `tools/blender/export_starslime_sample.py`, `tools/blender/export_starslime_v2.py`, `tools/blender/generate_lowpoly_assets.py`, `tools/blender/exports/manifest.json`, `tools/studio/ApplyHeroMeshTemplateDefaults.luau`, `docs/ART_DIRECTION.md` | `[x]` |
| **S4-02** | **P1** | `S3-04`, `S4-01` | Gemini | Wired runtime template cloning (`ReplicatedStorage.AssetTemplates.{Critters, Meteors}`) in `PlotVisualController` & `MeteorService` with `<= 8` parts / `<= 8.0` studs caps & exact `minY` grounding (`StarSlime` `2.888`/`3.558`/`4.074` Fed, `SolarGolem` `4.908`/`5.578`/`6.397` Fed), added dedicated cosmetic `FieldGuideDrawer` (`G`/`ButtonL1`/top-HUD `Guide` button, trait badges, discovery toasts, Coin-tick stability), Radiant `RadiantSparkles` honoring `Reduced Motion`, `>= 44×44` Safe-Area `ComputeDrawerLayout` (`320×568`–`1280×720`) & Gamepad `SelectionGroup` modal trapping, and verified all 57 startup suites passing in live Studio Play (`v0.4.0-s4-02-polish`). | `src/Client/Controllers/`, `src/Server/Services/MeteorService.luau`, `src/Shared/`, `tools/studio/ApplyHeroMeshTemplateDefaults.luau` | `[x]` |
| **S4-03** | **P1** | `S4-02` | Human + ChatGPT + Gemini | Cloud Studio preflight on `106917003014718` passed 6/6 critter and 3/3 meteor templates. Set the private place cap to six, publish the fix build, verify the new place version in a fresh server, and record the 15–30 minute six-player low-end device soak (sustained ≥30 FPS, stable memory, and clean runtime). | [Soak checklist](./S4_03_SOAK_VERIFICATION_CHECKLIST.md) · [Review #033](./AGENT_REVIEWS.md#review-033--s4-04-starter-persistence-and-s4-03-cloud-preflight) | `[~]` |
| **S4-04** | **P1** | `S4-02` | Gemini | One-time starter completion persists with the pod grant. Spawn and HUD use the loaded profile. Legacy migration, reconnect, duplicate-grant prevention, and isolated live DataStore write/reload passed technical review. | [Starter meteor persistence](#starter-meteor-persistence) · [Review #033](./AGENT_REVIEWS.md#review-033--s4-04-starter-persistence-and-s4-03-cloud-preflight) | `[x]` |

### Starter meteor persistence

The starter meteor currently checks a server-local `starterClaimedByUserId` table. Finishing the crack sets that table, plot release clears it, and plot assignment calls the spawn path again. The empty-ranch HUD can also show the starter prompt after the player has completed it. [Spawn gate](../src/Server/Services/MeteorService.luau#L489-L519) · [Starter pod grant](../src/Server/Services/MeteorService.luau#L864-L892) · [Plot release](../src/Server/Services/MeteorService.luau#L963-L977) · [HUD hint](../src/Client/Controllers/UIController.luau#L722-L746)

1. Add a server-owned starter completion field to the player profile. Record it in the same successful profile update as granting the guaranteed Star-Slime pod, and persist both together through the existing save lifecycle. A cancelled crack, closed connection before the grant, or full bag keeps the starter available. Repeat completion requests can deliver at most one starter pod.
2. Use the loaded completion field for starter spawn eligibility and the owner HUD. A rejoin before opening the meteor restores the opportunity. A rejoin after opening it restores the saved pod or subsequent critter state and skips both the respawn and starter hint, including after the critter is sold. An empty ranch that already completed the starter can point players toward ordinary Ember meteors.
3. Use a versioned migration for old profiles with positive saved evidence of starter progress, such as a saved Star-Slime pod or a Star-Slime discovery. Existing saves lack item origin, so document how ambiguous profiles remain eligible for onboarding. Keep an explicit completion value authoritative once the migration has run. Preserve inventory, Coins, and other progression.
4. Verify a fresh player, leaving mid-crack, full-bag failure, repeated completion, rejoin to the same and a fresh server with an unopened pod in the bag, and rejoin after hatching or selling the critter. Cover new and legacy profile paths. Record an isolated published save and reload that shows no duplicate grant and working starter spawn for another eligible player.

- **Migration Note (`SchemaVersion` `1 -> 2`):** Legacy v0/v1 saves lacked item origin, so `DataService.ReconcileAndMigrateProfileData` runs before `ProfileStore:Reconcile()` and sets `StarterMeteorCompleted = true` on positive `StarSlime` evidence (a saved `StarSlime` item in `Items` or `DiscoveredSpecies.StarSlime == true`), while ambiguous legacy profiles without `StarSlime` evidence remain eligible (`false`) for onboarding. Once migrated to `SchemaVersion >= 2`, the explicit `StarterMeteorCompleted` boolean is authoritative. Live isolated verification helper: [`tools/studio/RunS404StarterPersistenceCheck.luau`](../tools/studio/RunS404StarterPersistenceCheck.luau).
- **Isolated Live DataStore Verification (`2026-11-23`, `PlaceId=106917003014718`, `PlaceVersion=21`, `GameId=10778558732`):**
  - Cloud Studio Play passed **`59/59`** startup suites (`Mode=LiveProfileStore`, `DataStoreState=Access`).
  - Two-session `RunS404StarterPersistenceCheck` (`"Write"` in Session 1 -> stop Play -> `"Verify"` in fresh Session 2 on `StarfallRanch_StudioDev_v1_Smoke`, `Version=0.4.2-s4-04-starter-save`, `SchemaVersion=2`) passed with `Ok=true`: `CompletedUser=-960401[StarterMeteorCompleted=true, Pods=1, RespawnBlocked=true]` (no duplicate grant) and `EligibleUser=-960402[SpawnedAndCompleted=true]` (working starter spawn & crack). Approved in [Review #033](./AGENT_REVIEWS.md#review-033--s4-04-starter-persistence-and-s4-03-cloud-preflight).

---

## Stage 5: Controlled Soft Launch & Telemetry (Priority P2)

| Task ID | Priority | Depends On | Owner | Task Description & Acceptance Criteria | Deliverable / Path | Status |
| :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| **S5-01** | **P2** | `S4-04` | Gemini | Server-controlled onboarding and Coin source/sink telemetry passed technical review. Verified ordered funnel submissions, retry after API failure, pen-placement accrual, and private published-server submissions on place `106917003014718`, version `24`. | [Telemetry](../src/Server/Services/AnalyticsService.luau) · [Review #036](./AGENT_REVIEWS.md#review-036--s5-01-telemetry-sign-off) | `[x]` |
| **S5-02** | **P2** | `S5-01`, `S4-03` | Human + ChatGPT | Publish soft launch, monitor organic vs. ad cohorts, and evaluate pure fixed-price cosmetics **only** after stability & Roblox policy review. | `docs/MONETIZATION.md` | `[ ]` |

### S5-01 Private Published-Server Telemetry Evidence (`2026-11-23`)
- **Published Server Identity:** `PlaceId=106917003014718 | PlaceVersion=24 | MaxPlayers=6 | Version=v0.5.1-s5-01-telemetry-fix (9b91887) | Mode=LiveProfileStore | Store=StarfallRanch_Alpha_v1 | Reason=PublishedLiveDataStore | DataStoreState=Access | Server Script Errors=0` *(Note: `PlotService` logged `Players.MaxPlayers=60` at startup tick `18:31:33`, and `game:GetService("Players").MaxPlayers` confirmed `6` at `18:33:41`.)*
- **Onboarding Funnel (`Cohort=Fresh`, sequential `1..6`):**
  - `18:31:34` `Step=1 (Spawn)` -> `18:31:41` `Step=2 (FirstMeteor)` -> `18:32:01` `Step=3 (FirstHatch)` -> `18:32:04` `Step=4 (FirstPen)` -> `18:32:37` `Step=5 (FirstUpgrade)` -> `18:32:58` `Step=6 (SecondRescue)`.
- **Coin Economy Ledger (running balances reconciled, pre-spend accrual flush verified):**
  - `Source 26 Coins (Balance=26, Tx=Gameplay, Sku=PenAccrual)` -> `Source 26 (Balance=52)` -> pre-spend flush `Source 12 (Balance=64)` -> `Sink 60 Coins (Balance=4, Tx=Shop, Sku=Upgrade_PenSlot_2)` -> `Source 26 (Balance=30)` -> `Source 25 (Balance=55)` -> `Source 26 (Balance=81)` -> `Source 26 (Balance=107)` -> `Source 25 (Balance=132)`.
- **Dashboard Note:** Creator Hub Analytics dashboard charts can be spot-checked after Roblox's standard ingestion window; server-side submission succeeded with zero script errors.

---

## Stage 6: Launch Tools, Station Models & UI Art

| Task ID | Priority | Depends On | Owner | Task Description & Acceptance Criteria | Deliverable / Path | Status |
| :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| **S6-ART-01** | **P2** | `S4-02` | Gemini | Model and integrate the Starter, Frost, and Astral Crackers. Verify each Workbench preview, the current tier's held model during a crack, mobile readability, and the existing server tool requirements. Finish before the launch candidate. | [Launch tool models](./ART_DIRECTION.md#launch-tool-models) | `[~]` |
| **S6-ART-02** | **P2** | `S4-02` | Gemini | Replace station placeholders with modeled incubators, habitat pens, selling station, Tool Workbench, and other launch interaction fixtures. Review one ranch and the Workbench first. Verify state readability, prompts, ownership, camera clearance, and six-plot placement. | [Launch station models](./ART_DIRECTION.md#launch-station-models) | `[~]` |
| **S6-ART-03** | **P2** | `S4-02` | Gemini | Create distinct item thumbnails, original screen and navigation artwork, and illustrated cards for every approved shop offer. Implement the [gameplay HUD direction](./ART_DIRECTION.md#gameplay-hud-direction) with illustrated travel and utility groups, a Coin ledger and the Observatory Beacon. Verify catalog coverage and published image loading across Bag, Field Guide, Critter Index, Workbench and Shop on touch, keyboard, and gamepad. Reuse approved model renders where useful and finish before the launch candidate. | [Launch item and interface artwork](./ART_DIRECTION.md#launch-item-and-interface-artwork) | `[~]` |
| **S6-ART-04** | **P2** | `S4-02` | Gemini | Establish the launch detail standard with side-by-side Studio pilots for Cinder Pup, Solar Golem, Ember Meteor, and the Starter Cracker. Include the first incubator prototype as it becomes available. Review gameplay, phone and thumbnail readability and measure a populated map before approving a higher mesh budget or expanding to the existing models and wider launch roster. | [Launch model detail pass](./ART_DIRECTION.md#stage-6-launch-model-detail-pass) | `[~]` |

- **S6-ART-03 Phase 2 Update (`2026-11-23`, Review #042 fixes):** Responsive `< 460 px` stacked Bag cards (`RowHeight = 112`, `210 px` text width at `320 px` portrait, `>= 44 px` touch buttons below text), strict separate Bag/Field Guide `ArtMedallion` + portrait geometry self-tests (`76/76` Studio startup suites), and `16` upload-ready `256×256` PNG icons + `contact_sheet.png` in `tools/art/icons_png/`. Remaining open: published image loading after Roblox Creator Hub upload, `S6-ART-02` two-client Local Server smoke, `S6-ART-01` private published mesh check, and `S6-ART-04` uncapped benchmark.

## Stage 6: Coin progression

| Task ID | Priority | Depends On | Owner | Task Description & Acceptance Criteria | Deliverable / Path | Status |
| :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| **S6-ECO-01** | **P1** | `S5-01` | Gemini | Build the earned-Coin Observatory Gear Shop as a core launch loop. Prove a hatch-to-purchase run with Star Lens, Trail Boots, and Bond Charm, then tune all five price tiers against measured ranch income and integrate bounded gear effects with expeditions and drop pools. Verify save/rejoin, purchases, stat/odds displays, and mobile UI. | [Economy and Gear Shop spec](./OBSERVATORY_GEAR_SHOP.md) · [GUI prototype](./prototypes/observatory-gear-shop.html) | `[ ]` |
| **S6-ECO-02** | **P2** | `S6-ECO-01` | Gemini | Build the five earned-Coin prestige garage items. Verify original models, fixed price and prerequisites, single-slot equip and save/rejoin, bounded movement/luck/PvE effects, and responsive shop cards. Prototype Cometboard and Starwarden first, then reuse the setup for Rover, Speeder, and Surveyor. | [Prestige garage](./OBSERVATORY_GEAR_SHOP.md#prestige-garage) · [GUI prototype](./prototypes/observatory-gear-shop.html) | `[ ]` |
