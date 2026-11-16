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
| **S1-01** | **P0** | `S1-00` | Gemini | **Shared Config & Bounded Math:** Populate `CritterConfig` (*StarSlime* `2/s\|40`, *NebulaFox* `4/s\|95`, *SolarGolem* `7/s\|180`), `MeteorConfig` (*Ember*, *Frost*, *Astral*), `UpgradeConfig` (`60 / 150 / 320`), and deterministic `EconomyMath.SettleElapsedCoins` + `FormatUtil` + unit tests. | `src/Shared/Config/`, `src/Shared/Util/` | `[ ]` |
| **S1-02** | **P0** | `S1-00` | Gemini | **Idempotent Greybox Map Generator:** Write Studio Command-Bar script generating tagged `Workspace.StarfallGreyboxRoot` (`CentralCrater`, `Plot_1`, `Plot_2`, `Incubator_1..2`, `Pen_1..3`, Gate Sell Pad) with non-destructive rerun confirmation. | `tools/studio/GenerateGreyboxMap.luau` | `[ ]` |
| **S1-03** | **P0** | `S1-01` | Gemini | **Network & Inbound Validation:** Implement `NetworkService` remote creation (`SyncOwnerState`, `SyncPublicPlots`, `MeteorLifecycle`, `RequestInitialSnapshot`, `RequestStartCrack`, `RequestFinishCrack`, `RequestPlotAction`, `RequestBuyUpgrade`), strict `ValidationUtil` checks, and per-player token-bucket rate limiting. | `src/Server/Services/NetworkService.luau` | `[ ]` |
| **S1-04** | **P0** | `S1-01`, `S1-03` | Gemini | **Mock Data Service:** Implement in-memory `MockStore` profile creation, `IsReady(player)` gating, clean `PlayerRemoving` cleanup, and initial profile schema matching `Types.PlayerProfileData`. | `src/Server/Services/DataService.luau` | `[ ]` |
| **S1-05** | **P0** | `S1-01`, `S1-04` | Gemini | **Single-Writer Economy Service:** Implement atomic, non-yielding state transitions on the single `Items` map (`PodInBag` $\rightarrow$ `Incubating` $\rightarrow$ `HatchedInBag` $\rightarrow$ `InPen` / Sold), bag cap check (`10`), elapsed-time settlement before rate changes, and upgrade purchases. | `src/Server/Services/EconomyService.luau` | `[ ]` |
| **S1-06** | **P0** | `S1-02`, `S1-04`, `S1-05` | Gemini | **Plot Allocation & Public DTO Sync:** Assign unique plots (`Plot_1` / `Plot_2`) on ready, clean up on `PlayerRemoving`, update `PublicPlotDTO` revisions, and wire `ProximityPrompt`s on Ranch Pads & Gate. | `src/Server/Services/PlotService.luau` | `[ ]` |
| **S1-07** | **P0** | `S1-02`, `S1-05`, `S1-06` | Gemini | **Meteor Spawning & Nonce Claim Protocol:** Spawn distinct Ember/Frost/Astral crater meteors; enforce server-issued `AttemptNonce`, start/finish distance checks, single active claim, timeout/respawn release, and atomic pod grant before meteor removal. | `src/Server/Services/MeteorService.luau` | `[ ]` |
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
| **S4-03** | **P1** | `S4-02` | Human + ChatGPT | Run 15–30 min published full-server soak test on real low-end phone/tablet hardware verifying sustained $\ge 30$ FPS baseline and zero memory leaks. | `docs/AGENT_REVIEWS.md` | `[ ]` |

---

## Stage 5: Controlled Soft Launch & Telemetry (Priority P2)

| Task ID | Priority | Depends On | Owner | Task Description & Acceptance Criteria | Deliverable / Path | Status |
| :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| **S5-01** | **P2** | `S4-03` | Gemini | Instrument anonymous `AnalyticsService` onboarding funnel (`Spawn -> FirstMeteor -> FirstHatch -> FirstPen -> FirstUpgrade -> SecondRescue`) and economy source/sink events. | `src/Server/Services/AnalyticsService.luau` | `[ ]` |
| **S5-02** | **P2** | `S5-01` | Human + ChatGPT | Publish soft launch, monitor organic vs. ad cohorts, and evaluate pure fixed-price cosmetics **only** after stability & Roblox policy review. | `docs/MONETIZATION.md` | `[ ]` |
