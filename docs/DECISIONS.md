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
