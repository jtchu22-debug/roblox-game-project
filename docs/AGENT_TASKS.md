# Prioritized MVP Task List & Project Board (`AGENT_TASKS.md`)

> **Last Updated:** November 15, 2026  
> **Current Active Milestone:** Stage 1 Setup Complete (`S1-00`) — Ready for Stage 1 Vertical Slice Implementation (`S1-01`+)

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
| **S1-07** | **P0** | `S1-02`, `S1-05`, `S1-06` | Gemini | **Meteor Spawning & Nonce Claim Protocol:** Implemented separate plot-scoped Starter (`StarSlime`) & Wild Crater (`Ember`/`Frost`/`Astral`) meteor pools, server `AttemptNonce` + distance + committed-bag checks, timeout/death/plot-release cleanup, `CrackController` prompt bridge, and `MeteorService.RunSelfTest()`. | `src/Server/Services/MeteorService.luau`, `src/Client/Controllers/CrackController.luau` | `[x]` |
| **S1-08** | **P0** | `S1-03`–`S1-07` | Gemini | **Client Controllers & Accessibility Polish:** Implement `InputController` (Touch/Keyboard/Gamepad), `CrackController` (forgiving tap + feel ring), `PlotVisualController` (centralized hop loop for blocky critters), `UIController` (Safe-Area HUD, Bag, Keep-vs-Sell, Settings), and `SoundController` (Mute + Reduced Motion). | `src/Client/Controllers/*.luau`, `src/Client/ClientInit.client.luau` | `[ ]` |
| **S1-09** | **P0** | `S1-08` | Gemini + Human | **Stage 1 Adversarial & 2-Player Verification:** Run 2-Player Studio Local Server tests (simultaneous crack race, expired/forged nonce, out-of-range claim, `NaN`/negative remote fuzzing, bag-full rejection, mid-crack respawn/leave) + verify 5-minute loop pacing. | Test Report in `docs/AGENT_REVIEWS.md` | `[ ]` |

---

## Stage 2: Discovery Playtest Gate (`R-009` — Priority P0)

| Task ID | Priority | Depends On | Owner | Task Description & Acceptance Criteria | Deliverable / Path | Status |
| :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| **S2-01** | **P0** | `S1-09` | Human + ChatGPT | **Uncoached 5–10 Tester Playtest:** Observe 5–10 consenting testers (no coaching, zero personal data) against directional targets ($\ge 80\%$ hatch in 90s; median first reward $\le 45\text{s}$; $\ge 70\%$ initiate another rescue in 5 min). **Go / Iterate / Pivot Decision.** | `docs/AGENT_REVIEWS.md` | `[ ]` |

---

## Stage 3: Persistence Alpha (`ProfileStore` & 6-Plot Scale — Priority P1)

| Task ID | Priority | Depends On | Owner | Task Description & Acceptance Criteria | Deliverable / Path | Status |
| :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| **S3-01** | **P1** | `S2-01` (Go) | Gemini | Vendor pinned `MadStudioRoblox/ProfileStore` (preserving MIT `LICENSE`) and document pinned commit/version. | `src/Server/Libs/ProfileStore/` | `[ ]` |
| **S3-02** | **P1** | `S3-01` | Gemini | Upgrade `DataService` to `ProfileStore` (`StartSessionAsync`, `OnSessionEnd` kick, schema reconciliation, `BindToClose`, zero silent blank live fallback) + offline `MaturesAt` incubation check. | `src/Server/Services/DataService.luau` | `[ ]` |
| **S3-03** | **P1** | `S3-02` | Gemini | Scale greybox map & `PlotService` from `2` $\rightarrow$ `6` plots (`MaxPlayers = 6`), add late-join `PublicPlotDTO` resync and plot reuse revision cleanup, add Stage 3 upgrades (`PenSlot_4`, `BagCap_20`, `PenSlot_5`). | `PlotService.luau`, `GenerateGreyboxMap.luau` | `[ ]` |
| **S3-04** | **P1** | `S3-03` | ChatGPT + Gemini | Pass full persistence failure-injection suite (load fail clean kick, dual-server lock theft, shutdown flush, `MaturesAt` clock boundary tests) and 6-player full-server exploit review. | `docs/AGENT_REVIEWS.md` | `[ ]` |

---

## Stage 4: Hero Low-Poly Art, Mobile Polish & Soak Beta (Priority P1–P2)

| Task ID | Priority | Depends On | Owner | Task Description & Acceptance Criteria | Deliverable / Path | Status |
| :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| **S4-01** | **P2** (`R-010`) | `S2-01` (Go) | Gemini + Human | Validate **one** sample Blender `.fbx` export (`StarSlime`) in an isolated Studio place (scale, normals, pivot, materials), then update `generate_lowpoly_assets.py` (embedded meteor shards, critter eyes/tails, safe rerun prompt, FBX exporter) and produce 3 critters + 3 meteor models ($\le 400$ tris each). | `tools/blender/generate_lowpoly_assets.py` | `[ ]` |
| **S4-02** | **P1** | `S3-04`, `S4-01` | Gemini | Add simple **Discovered Species Checklist** UI (no stat multipliers), optional **Radiant** cosmetic hatch variant ($\le 30$ critters server-wide, $\le 8$ studs max height), Touch/Gamepad focus & Safe-Area polish. | `src/Client/`, `src/Shared/` | `[ ]` |
| **S4-03** | **P1** | `S4-02` | Human + ChatGPT | Run 15–30 min full-server soak test in a published private test place on real low-end phone/tablet hardware verifying sustained $\ge 30$ FPS baseline and zero memory leaks. | `docs/AGENT_REVIEWS.md` | `[ ]` |

---

## Stage 5: Private Baseline Testing & Launch Preparation

| Task ID | Priority | Depends On | Owner | Task Description & Acceptance Criteria | Deliverable / Path | Status |
| :---: | :---: | :---: | :--- | :--- | :--- | :---: |
| **S5-01** | **P2** | `S4-03` | Gemini | Instrument and verify the anonymous onboarding funnel (`Spawn -> FirstMeteor -> FirstHatch -> FirstPen -> FirstUpgrade -> SecondRescue`) and economy events in a private test build. | `src/Server/Services/AnalyticsService.luau` | `[ ]` |
| **S5-02** | **P1** | `S5-01` | Gemini + Human + ChatGPT | Run invite-only baseline playtests and onboarding, multiplayer, save/load, and economy regressions. Record pacing and resolve core blockers. | `docs/AGENT_REVIEWS.md` | `[ ]` |

---

## Stage 6: Collection Expansion for the First Public Release

| Task ID | Priority | Depends On | Owner | Task Description & Acceptance Criteria | Deliverable / Path | Status |
| :---: | :---: | :---: | :--- | :--- | :--- | :---: |
| **S6-01** | **P1** | `S5-02` | Gemini + Human | Implement the [12-species launch roster](./GAME_DESIGN.md#7-stage-6-collection-expansion) and the Ember, Frost, and Astral drop pools. Preserve the guaranteed starter Star-Slime and tune hatches, odds, income, and sell prices. | Critter and meteor configs | `[ ]` |
| **S6-02** | **P1** | `S6-01` | Gemini | Finish critter art, rarity labels, the collection book, and the Astral-exclusive Secret Eclipse Dragon. Add the silhouette, hint, and reveal with Reduced Motion support. | Critter assets and collection UI | `[ ]` |
| **S6-05** | **P1** | `S6-01` | Gemini + Human | Build the [day-one launch shop](./MONETIZATION.md#3-day-one-game-passes-and-purchases), capped offline Coins, server-side entitlements, and durable receipt delivery. Configure Robux offers and verify effective odds and per-player eligibility in the private build. | Shop UI, economy and purchase services | `[ ]` |
| **S6-03** | **P1** | `S6-02`, `S6-05` | Gemini + Human + ChatGPT | Test the content-complete private release candidate. Verify acquisition, Secret and starter behavior, save/load, progression, multiplayer, accessibility, mobile performance, valid purchase delivery, receipt retries, offline settlement, and paid-random restrictions and odds. Record final sign-off. | `docs/AGENT_REVIEWS.md` | `[ ]` |
| **S6-04** | **P1** | `S6-03` | Human | Publish the signed-off build as the first public release with all 12 core critters, the Secret chase, and the verified shop available on day one. | Public launch | `[ ]` |
