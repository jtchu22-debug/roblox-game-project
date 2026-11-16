# Project Task Board (`AGENT_TASKS.md`)

> **Last Updated:** November 15, 2026  
> **Current Active Milestone:** Phase 0 — Market Research, Concept Selection & Architecture Review

---

## Status Legend
- `[x]` **COMPLETED** — Verified and committed to repository.
- `[~]` **IN REVIEW / BLOCKED ON EXTERNAL STEP** — Waiting on Human Lead or ChatGPT review.
- `[ ]` **TODO** — Queued for upcoming phase.

---

## Milestone 0: Research, Planning & Repository Setup (Current)

| Task ID | Owner | Task Description | Deliverable File | Status |
| :---: | :---: | :--- | :--- | :---: |
| **T-001** | Gemini | Research 2025–2026 trending Roblox games, CCU peaks, player sentiment, and the 28-day RFY discovery algorithm. | `docs/MARKET_RESEARCH.md` | `[x]` |
| **T-002** | Gemini | Identify and analyze 8 recurring gameplay, retention, social, and viral mechanics. | `docs/TREND_ANALYSIS.md` | `[x]` |
| **T-003** | Gemini | Generate 12 original game concepts, score on a 100-point rubric, recommend Top 3, and select #1 concept (*Starfall Ranch*). | `docs/GAME_CONCEPTS.md` | `[x]` |
| **T-004** | Gemini | Draft comprehensive Game Design Document (GDD) and strict 3-bucket MVP scope. | `docs/GAME_DESIGN.md` | `[x]` |
| **T-005** | Gemini | Design server-authoritative Luau technical architecture, DataStore schema, remotes, and security checks. | `docs/TECHNICAL_ARCHITECTURE.md` | `[x]` |
| **T-006** | Gemini | Create beginner-friendly 6-phase development roadmap with testing & Definition of Done. | `docs/DEVELOPMENT_ROADMAP.md` | `[x]` |
| **T-007** | Gemini | Define low-poly art direction, Part-vs-Blender strategy, and write procedural Blender Python asset script. | `docs/ART_DIRECTION.md`, `tools/blender/generate_lowpoly_assets.py` | `[x]` |
| **T-008** | Gemini | Design child-safe, ethical monetization strategy (GamePasses, communal Weather Beacons, guardrails). | `docs/MONETIZATION.md` | `[x]` |
| **T-009** | Gemini | Establish multi-agent governance (`AGENT_RULES.md`, `AGENT_TASKS.md`, `AGENT_REVIEWS.md`, `DECISIONS.md`) and initialize local Git repository. | `docs/AGENT_*.md`, `docs/DECISIONS.md` | `[x]` |
| **T-010** | **Human Lead** | Authenticate GitHub remote and push local `main` branch to `roblox-game-project` on GitHub so ChatGPT can connect. | [GitHub Remote](https://github.com/jtchu22-debug/roblox-game-project) | `[x]` |
| **T-011** | **ChatGPT** | Conduct independent Technical Director audit of all Phase 0 docs; critique concept selection, economy math, and technical architecture; answer open ADRs. | `docs/AGENT_REVIEWS.md`, `docs/DECISIONS.md` | `[~]` |
| **T-012** | Gemini + Human | Incorporate ChatGPT's Phase 0 review feedback and lock final MVP spec before starting Phase 1 code. | `docs/**` | `[ ]` |

---

## Milestone 1: Greybox Map & Core Plot Loop (Queued — Starts After T-011/T-012)

| Task ID | Owner | Task Description | Deliverable File | Status |
| :---: | :---: | :--- | :--- | :---: |
| **T-101** | Gemini | Create `src/Shared/Types.luau` and `src/Shared/Constants.luau` with strict Luau typing. | `src/Shared/` | `[ ]` |
| **T-102** | Gemini | Populate `CritterConfig.luau`, `CrystalConfig.luau`, `MutationConfig.luau`, `WeatherConfig.luau`, and `UpgradeConfig.luau`. | `src/Shared/Config/` | `[ ]` |
| **T-103** | Gemini | Implement `EconomyMath.luau` (value formula, offline vault math) + unit test verification script. | `src/Shared/Util/EconomyMath.luau` | `[ ]` |
| **T-104** | Gemini | Implement `DataService.luau` with session-locking, Studio mock fallback, and auto-save loop. | `src/Server/Services/DataService.luau` | `[ ]` |
| **T-105** | Gemini | Implement `PlotService.luau` (6-plot claiming, Soil Bed planting, Incubator hatching, Critter Pen passive income). | `src/Server/Services/PlotService.luau` | `[ ]` |
| **T-106** | Gemini | Write step-by-step Studio Greybox setup guide (or automated Studio command-bar generator script) so the beginner developer can generate the 6-plot greybox map in 1 click! | `tools/studio/GenerateGreyboxMap.luau` | `[ ]` |
| **T-107** | ChatGPT | Code review of Phase 1 server modules (`DataService`, `PlotService`, `EconomyMath`). | `docs/AGENT_REVIEWS.md` | `[ ]` |
