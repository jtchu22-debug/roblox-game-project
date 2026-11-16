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
| **T-011** | **ChatGPT** | Conduct independent Technical Director audit of all Phase 0 docs; critique concept selection, economy math, and technical architecture; answer open ADRs. | [CHATGPT_REVIEW.md](./CHATGPT_REVIEW.md), `docs/AGENT_REVIEWS.md`, `docs/DECISIONS.md` | `[x]` |
| **T-012** | Gemini | Incorporate ChatGPT's Phase 0 review feedback (`R-001`–`R-006`) across all Phase 0 documentation ahead of Human Lead sign-off (`R-007`). | `docs/**`, `README.md` | `[x]` |

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



---

## Phase 0 independent review follow-up (2026-11-15 — proposed on review branch)

See [CHATGPT_REVIEW.md](./CHATGPT_REVIEW.md), Review #001 in [AGENT_REVIEWS.md](./AGENT_REVIEWS.md) and reviewer responses in [DECISIONS.md](./DECISIONS.md). The independent audit (T-011) is completed on this branch; original task statuses above describe the existing baseline until the owner approves/merges the review. **T-012 remains blocked: no production code until the revised direction and scope are approved by the human lead.** T-101–107 are superseded as a proposed sequence, not authorized work.

| ID | Priority | Owner | Action and acceptance criteria | Status |
|---|---|---|---|---|
| R-001 | P0 | Gemini | Correct market data with timestamped URLs, place IDs, comparable windows; include Break and Steal an Egg, Fish It!, Shovel It! and mid-tier/failed competitors. Separate telemetry, hypothesis and firsthand observation; fix RFY/retention claims. | `[x]` |
| R-002 | P0 | Gemini | Propose unified critter-only rescue/meteor loop with 3 species, one currency, keep-vs-sell decision and visible upgrade; first 5-minute experience and one differentiator. Remove crystal lane, weather/shop timers, fusion/rebirth, bosses, transfers, paid progression, streaks and secondary worlds from prototype. | `[x]` |
| R-003 | P0 | Gemini | Replace multiplicative economy with bounded simple integer income; align tutorial, prices, probabilities and terminology. Include time-to-upgrade, starter/average/best-case simulation, inventory/capacity tests; offline growth only initially. | `[x]` |
| R-004 | P0 | Gemini | Revise architecture: authoritative item lifecycle and unique IDs, non-yield atomic transitions, server nonce/claim validation, finite/bounded remote payloads, readiness, rate limits, public/private DTOs and late-join resync; document ProfileStore pin/license, save/session failure and checkpoint tests. | `[x]` |
| R-005 | P0 | Gemini | Revise monetization doc: Creator Rewards replaces EBP, no paid random item/currency/odds modifiers or social spending pressure; cosmetics only after stability and review. Specify ProcessReceipt durable recovery strategy if products ever added. | `[x]` |
| R-006 | P0 | Gemini + human lead | Revise roadmap into mock vertical slice → observed 5-minute playtest → persistence alpha → mobile polish → controlled launch. Agree acceptance targets and all ADRs before Phase 1. | `[x]` |
| R-007 | P0 | Human lead | Approve narrowed Starfall prototype or request alternate concept. Review R-001–006 deliverables, then explicitly authorize Phase 1. | `[~]` |
| R-008 | P1 | Gemini | After R-007: pin Rojo, create mapped paths, test isolated Studio place, tagged idempotent greybox map, one vertical slice with mock profiles; verify 2-player concurrency and remote abuse. No additional systems yet. | `[ ]` |
| R-009 | P1 | Human lead + ChatGPT | After prototype: unguided playtest and evidence-based go/iterate/pivot decision, code/security review, real device checks. | `[ ]` |
| R-010 | P2 | Gemini | After fun gate: validate one Blender export/import, fix generator discrepancies and safe reruns; performance/asset license budget. | `[ ]` |

**Gate sequence:** R-001 → R-002/R-003/R-004/R-005 → R-006 → R-007 → R-008 → R-009; R-010 only after prototype proves useful. R-001–006 may be coordinated without overlapping edits. Do not mark any gameplay implementation complete based on planning alone.
