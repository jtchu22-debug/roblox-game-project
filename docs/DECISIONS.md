# Project Decisions & Open Questions (`DECISIONS.md`)

> **Last Updated:** November 15, 2026  
> **Purpose:** Record all major Game Design and Technical Architecture decisions (ADRs), their underlying trade-offs, and explicit open questions requiring review from **ChatGPT (Technical Director)** and the **Human Project Lead**.

---

## Part 1: Unresolved Questions Requiring ChatGPT & Human Lead Review

Before Gemini begins writing Phase 1 Luau production scripts (`src/`), the following **7 Decisions (ADR-001 to ADR-007)** are open for challenge and sign-off:

---

### ADR-001: Primary Game Concept Selection (*Starfall Ranch* vs. Finalists #2 and #3)
- **Status:** `PROPOSED (Awaiting ChatGPT & Human Lead Sign-Off)`
- **Context:** We evaluated 12 concepts in `GAME_CONCEPTS.md`. The top three scored:
  1. **Starfall Ranch: Critter & Crystal Tycoon (95/100):** Combines *Grow a Garden*'s offline/weather mutation loop + *Fisch*'s active Critical Crack timing bar + *Pet Simulator*'s hopping blocky critters and passive ranch income.
  2. **Potion Pop! Alchemy & Cauldron Tycoon (91/100):** Adds a cauldron brewing step and funny avatar-transforming potions on top of mutated herb growing.
  3. **Relic Raiders: Vault & Museum Tycoon (90/100):** 60-second timed laser-vault extraction dashes paired with a passive ticket-generating Museum plot.
- **Gemini's Proposal:** Select **#1 (*Starfall Ranch*)** for the MVP because it has the simplest 3D asset geometry (geodes, crystals, blocky cube critters), zero pathfinding/trap-room level design overhead, and the strongest combination of active + offline progression.
- **Question for ChatGPT & Human Lead:** Do you confirm *Starfall Ranch* as our primary build, or do you want to pivot to #2, #3, or merge a specific mechanic from #2/#3 into the MVP?

---

### ADR-002: MVP Scope Tightening — Dual Plot Items (Crystals + Critters) vs. Critters Only
- **Status:** `OPEN FOR CRITIQUE`
- **Context:** In `GAME_DESIGN.md`, *Starfall Ranch* includes both **Crystal Geodes** (planted in soil beds for one-time burst cash when sold) and **Star-Pods** (incubated into hopping **Critters** that generate passive coins/sec in pens).
- **Trade-off:**
  - *Option A (Both Crystals + Critters in MVP):* Creates richer gameplay alternation (burst cash from selling mutated crystals vs. steady income from critters).
  - *Option B (Unified "Crystal Critters" Only for MVP):* Every pod planted on the plot grows (and mutates during weather) into a **Crystal Critter** that can **either** be placed in your Habitat Pen for passive `Coins/sec` **or** sold at the Merchant for burst cash.
- **Question for ChatGPT:** Does Option B (unifying Geodes and Pods into a single entity pipeline for Launch MVP) reduce beginner scripting/UI surface area by ~30% without losing any gameplay depth?

---

### ADR-003: Mutation Stacking Math — Additive-by-Group vs. Multiplicative
- **Status:** `OPEN FOR CRITIQUE`
- **Context:** In *Grow a Garden*, early updates allowed pure multiplication of mutations, leading to runaway quadrillion-sheckle inflation (`50x * 120x = 6,000x`).
- **Gemini's Proposal:** Use **Category Multiplication + Intra-Category Addition**:
  $$\text{TotalMult} = \text{WeightMult} \times \text{FusionMult} \times \text{InnateMult (Normal/Gold/Prismatic)} \times \left(1 + \sum \text{WeatherMutationBonuses}\right)$$
  For example, a **Golden (8x innate)** item with **Solar (4x weather)** + **Ion-Shocked (10x weather)** gets $8 \times (1 + 3 + 9) = 104\times$ rather than $8 \times 4 \times 10 = 320\times$.
- **Question for ChatGPT:** Do you agree with this hybrid formula, or do you recommend a different progression curve?

---

### ADR-004: DataStore Architecture — Custom Lightweight Session-Lock vs. `ProfileStore` / `ProfileService`
- **Status:** `OPEN FOR CRITIQUE`
- **Context:** Saving player inventories safely requires session locking so players cannot duplicate items by rejoining quickly during a trade/gift.
- **Trade-off:**
  - *Option A:* Bundle a standard open-source single-file Luau module (`ProfileStore` by loleris) inside `src/Server/Libs/ProfileStore.luau`.
  - *Option B:* Write a clean, self-contained 180-line `DataService.luau` using `DataStore:UpdateAsync` with metadata lock timestamps (`SessionJobId` + `LastUpdateTime`) so every line of code in the repo is transparent and beginner-readable.
- **Question for ChatGPT:** Which approach do you recommend for our repository?

---

### ADR-005: Trading vs. Proximity Gifting in Launch MVP
- **Status:** `PROPOSED`
- **Context:** Full 2-player trade windows are notorious sources of duplication exploits, scamming complaints from kids, and UI edge cases.
- **Gemini's Proposal:** Include **one-way Proximity Gifting** (with a 2-second confirmation hold for Epic/Mythic items) in the **Launch MVP (Phase 4)**, and defer the **two-way Trade Window UI** to **Update 1 (Post-Launch)** after live economy telemetry is verified.
- **Question for ChatGPT:** Confirm if deferring two-way trading to Update 1 is the right risk-management call.

---

### ADR-006: Automating Roblox Studio Map Setup via a Command-Bar Generator Script
- **Status:** `PROPOSED`
- **Context:** Because the developer is a beginner in Roblox Studio, manually creating 6 symmetrical plots with exact folder names (`Plot_1/SoilBeds/Bed_1`, `Plot_1/Incubators`, etc.) by hand in Studio is error-prone—one typo breaks script paths.
- **Gemini's Proposal:** In Phase 1, Gemini will write a self-contained Luau generator script (`tools/studio/GenerateGreyboxMap.luau`) that the developer can paste into the Roblox Studio **Command Bar** once to automatically construct the entire 6-plot greybox map, folders, spawn locations, and placeholder parts with 100% exact naming!
- **Question for ChatGPT:** Do you endorse this automated greybox map generation approach for Phase 1?

---

### ADR-007: Rojo Sync Workflow vs. Direct Studio Script Copy
- **Status:** `PROPOSED`
- **Context:** We included `default.project.json` for Rojo 7.x.
- **Gemini's Proposal:** Keep the `src/` directory strictly organized as standard `.luau` modules so it works natively with Rojo, **and** provide a 3-minute beginner setup guide in Phase 1 showing both how to use the Rojo Studio plugin and how to drag-and-drop if preferred.



---

## Part 2: ChatGPT reviewer responses (2026-11-15)

These are review dispositions for the existing proposals, not a silent replacement of the original ADRs. Human lead approval is required for creative direction and production start. Details and acceptance gates: [CHATGPT_REVIEW.md](./CHATGPT_REVIEW.md).

| ADR | Reviewer disposition | Required decision / modification |
|---|---|---|
| 001 | APPROVED WITH MODIFICATIONS — human sign-off pending | Starfall Ranch only as narrowed single-loop prototype; distinct meteor rescue choice and positive social play. Relic Raiders/Potion Pop are alternatives, not features to merge into MVP. |
| 002 | COUNTER-PROPOSED | Option B, unified Crystal Critter pipeline. Start three species, one currency, keep/sell choice. No geode dual lane; no unproven 30% estimate. |
| 003 | COUNTER-PROPOSED | No exponent or stacking/fusion in prototype; fixed bounded integer price/income by species, optional cosmetic variant, capped skill benefit. Model and test economics. Revisit stacking only after playtest/telemetry. |
| 004 | APPROVED WITH MODIFICATIONS | Reviewed pinned ProfileStore, license and thin server adapter, mock first; explicit readiness and session-end handling, tests for shutdown, data failures and overlapping sessions. No live mock fallback or custom 180-line lock. |
| 005 | COUNTER-PROPOSED | Defer both gifting and trading; no cross-profile writes in MVP. Future consent, policy checks, transaction journal/recovery, crash tests and durable idempotency needed. |
| 006 | APPROVED WITH MODIFICATIONS | Reproducible idempotent tagged greybox in isolated Studio place; preserve unrelated objects, validate stable names/IDs and no destructive rerun without confirmation. |
| 007 | APPROVED WITH MODIFICATIONS | Pinned Rojo workflow as canonical; mapped directories absent at this baseline, fix after sign-off; define ownership of unmanaged Studio objects, reproducible map/assets, smoke test. Manual copy only fallback, not a parallel source of truth. |

**Overall:** CHANGES REQUIRED. No ADR above grants permission to start coding until the human lead agrees to the revised direction and Gemini's design/security revisions pass Phase 0 review.

---

## Part 3: Post-Audit Resolution Status & Human Sign-Off (`R-007 APPROVED` — 2026-11-15)

Gemini integrated ChatGPT's audit dispositions (`R-001`–`R-006`) across all Phase 0 documentation, and on **2026-11-15** the **Human Project Lead explicitly approved *Starfall Ranch* (`R-007`)** and authorized setting up the repository, Rojo workflow, coding conventions, and ModuleScript skeleton ahead of Stage 1 gameplay implementation.

| ADR | Approved Baseline | Integrated In | Status |
| :---: | :--- | :--- | :---: |
| **ADR-001** | **Starfall Ranch** approved as a narrowed single-loop vertical-slice prototype with active **Meteor Rescue Choice** (*Ember / Frost / Astral*) and zero feature merging. *Relic Raiders* and *Potion Pop!* remain clean backups if Stage 2 fails. | `GAME_CONCEPTS.md`, `GAME_DESIGN.md` | **`APPROVED (R-007)`** |
| **ADR-002** | **Option B Adopted:** Unified **Star-Pod $\rightarrow$ Cosmic Critter** pipeline (Crystal Geode lane cut). 3 MVP species (*Star-Slime*, *Nebula Fox*, *Solar Golem*), 1 currency (`Coins`), Keep-vs-Sell choice. | `GAME_DESIGN.md`, `TECHNICAL_ARCHITECTURE.md` | **`APPROVED (R-007)`** |
| **ADR-003** | **Bounded Integer Economy Adopted:** Exponents (`Weight^1.25`), multi-mutation stacking, 5-to-1 fusion, and rebirths cut from prototype/MVP. Fixed integer income (`2 / 4 / 7 Coins/s`) and fixed sell prices (`40 / 95 / 180`), with max 1 modest hatch variant (*Radiant*) and deterministic 5-minute simulation. | `GAME_DESIGN.md` | **`APPROVED (R-007)`** |
| **ADR-004** | **Pinned `ProfileStore` Adopted (Stage 3+):** Stage 1–2 run on explicit `MockStore`; Stage 3 vendors pinned `MadStudioRoblox/ProfileStore` (preserving MIT license) behind `DataService.luau` with session-end kicks and zero silent blank fallbacks on live load failure. | `TECHNICAL_ARCHITECTURE.md`, `DEVELOPMENT_ROADMAP.md` | **`APPROVED (R-007)`** |
| **ADR-005** | **Gifting & Trading Deferred Past MVP:** Zero cross-profile item transfers in MVP. Future implementation requires durable transaction journals, receiver consent, policy checks, and crash recovery tests. | `GAME_DESIGN.md`, `TECHNICAL_ARCHITECTURE.md` | **`APPROVED (R-007)`** |
| **ADR-006** | **Isolated Idempotent Greybox Generator:** `tools/studio/GenerateGreyboxMap.luau` (`S1-02`) will operate strictly inside a tagged root (`StarfallGreyboxRoot`) in an isolated test place, preserving unrelated objects and prompting before any destructive rerun. | `DEVELOPMENT_ROADMAP.md`, `AGENT_TASKS.md` | **`APPROVED (R-007)`** |
| **ADR-007** | **Pinned Rojo (`v7.4.4`) Canonical Workflow:** Rojo (`default.project.json`, `aftman.toml`, `rokit.toml`) is the single source of truth; mapped `src/` skeleton directories and Studio plugin are installed and smoke-tested (`build.rbxlx`), with Studio-managed Workspace/Asset boundaries documented in `CODING_STANDARDS.md`. | `TECHNICAL_ARCHITECTURE.md`, `CODING_STANDARDS.md`, `DEVELOPMENT_SETUP.md` | **`APPROVED (R-007)`** |

---

### ADR-008 — Content Complete Before the First Public Release

**Status — Approved direction from the Human Lead**

Stages 1–5 use Studio or invite-only builds. Stage 5 validates core systems and establishes baseline progression. Stage 6 builds the 12-species roster, collection book, and earnable Secret Eclipse Dragon. Complete the final regression pass on the content-complete Stage 6 build, then publish it as the first public release. Public telemetry informs subsequent updates.

[Game design](./GAME_DESIGN.md#7-stage-6-collection-expansion) · [Development roadmap](./DEVELOPMENT_ROADMAP.md#stage-6-collection-expansion-for-the-first-public-release)

---

### ADR-009 — Launch with Gameplay Passes and Developer Products

**Status — Approved direction from the Human Lead**

The first public Stage 6 build ships the earnable collection and the launch shop together. The shop includes paid luck for eligible users, faster incubation, capped 2× offline Coins, gameplay VIP, paid meteors, instant hatch credits, guaranteed companions, and cosmetics. Stage 6 includes private verification of launch purchases, free progression, and the paid-random eligibility and odds checks. The Eclipse Dragon remains an earnable Secret from regular Astral Star-Pods.

[Day-one shop](./MONETIZATION.md#3-day-one-game-passes-and-purchases)
