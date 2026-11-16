# Starfall Ranch: Critter & Crystal Tycoon (`roblox-game-project`)

> **Project Status:** Phase 0 — Market Research, Concept Selection & Architecture Planning (Awaiting Technical Director Review)  
> **Last Updated:** November 15, 2026  
> **Primary Research & Planning Agent:** Gemini (Antigravity)  
> **Independent Technical Director & Reviewer:** ChatGPT  

---

## 1. Project Overview

This repository houses the market research, game design documentation, technical architecture, and source code for an original Roblox Simulator/Tycoon hybrid experience targeting younger audiences (ages 8–14) with a vibrant, low-poly stylized art direction.

Following a comprehensive analysis of the 2025–2026 Roblox market—including breakout phenomena such as *Grow a Garden*, *Fisch*, *Steal An Egg*, *Steal a Brainrot*, *Dead Rails*, *The Forge*, and *Restaurant Tycoon 3*—we evaluated **12 original game concepts** against a weighted scoring matrix prioritizing market opportunity, 28-day algorithmic retention, beginner development feasibility, and ethical monetization.

### Recommended Concept: **Starfall Ranch: Critter & Crystal Tycoon**
Players claim a customizable floating ranch plot surrounding a dynamic Meteor Crater. Every few minutes, cosmic meteors crash down and global supply ships restock. Players use a snappy timing minigame (**Critical Crack**) to harvest **Star-Pods and Crystal Geodes**, place them on their ranch to grow (including **full offline growth**), and watch server-wide **Cosmic Weather Events** (*Solar Flare*, *Frost Nebula*, *Aurora Storm*, *Void Eclipse*) stack exponential visual and value **Mutations** (*Golden*, *Prismatic*, *Giant*, *Galactic*) onto their critters and crystals. Matured critters hop around ranch pens generating passive currency, can be held overhead to flex or gifted in the central plaza, cataloged in a **Cosmic Bestiary**, and reinvested into automated tycoon upgrades and **Ranch Rebirths**.

---

## 2. Repository Structure

```text
roblox-game-project/
├── README.md                          # Project overview, status, and navigation guide
├── default.project.json               # Rojo project configuration mapping src/ to Roblox Studio
├── .gitignore                         # Ignore rules for Roblox Studio (.rbxlx.lock), OS, and build artifacts
├── docs/
│   ├── MARKET_RESEARCH.md             # 2025–2026 Roblox market analysis, verified stats, and algorithm shifts
│   ├── TREND_ANALYSIS.md              # 8 core gameplay, retention, social, and viral mechanics analyzed
│   ├── GAME_CONCEPTS.md               # 12 original concepts, 100-point scoring matrix, and Top 3 deep dive
│   ├── GAME_DESIGN.md                 # Full GDD & MVP scope for Starfall Ranch: Critter & Crystal Tycoon
│   ├── TECHNICAL_ARCHITECTURE.md      # Server-authoritative Luau architecture, DataStores, networking, security
│   ├── DEVELOPMENT_ROADMAP.md         # Beginner-friendly phased roadmap with testing & Definition of Done
│   ├── ART_DIRECTION.md               # Low-poly style guide, Part-to-Blender pipeline, and Blender Python scripts
│   ├── MONETIZATION.md                # Ethical, child-safe monetization strategy (GamePasses, DevProducts, Payouts)
│   ├── AGENT_RULES.md                 # Multi-agent collaboration protocol between Gemini and ChatGPT
│   ├── AGENT_TASKS.md                 # Actionable task board and current execution status
│   ├── AGENT_REVIEWS.md               # Structured review log and critique template for ChatGPT
│   └── DECISIONS.md                   # Architecture & Design Decision Records (ADRs) + open questions
├── src/                               # Luau source code (populated after Phase 0 review sign-off)
│   ├── Client/                        # StarterPlayerScripts (UI controllers, VFX, input, client tweens)
│   ├── Server/                        # ServerScriptService (PlotManager, DataService, WeatherService, Economy)
│   └── Shared/                        # ReplicatedStorage (Config tables, Item/Mutation registries, Types)
└── tools/
    └── blender/                       # Blender Python (bpy) procedural low-poly asset generation scripts
```

---

## 3. Documentation Reading Order (For Human Lead & ChatGPT Reviewer)

If you are connecting to this repository as the **Technical Director / Reviewer (ChatGPT)** or reviewing the project as the **Project Owner**, follow this reading sequence:

1. **[docs/MARKET_RESEARCH.md](./docs/MARKET_RESEARCH.md)** — Understand the empirical data (2025–2026 CCU peaks, evergreen benchmarks, player complaints, and the 28-day Roblox Recommended For You algorithm).
2. **[docs/TREND_ANALYSIS.md](./docs/TREND_ANALYSIS.md)** — Review the 8 underlying psychological and mechanical trends extracted from top-performing games.
3. **[docs/GAME_CONCEPTS.md](./docs/GAME_CONCEPTS.md)** — Examine all 12 generated concepts, the transparent scoring rubric, the Top 3 finalists, and challenge or validate the selection of *Starfall Ranch*.
4. **[docs/GAME_DESIGN.md](./docs/GAME_DESIGN.md)** — Critique the core loop, math formulas, retention hooks, and strict MVP scope boundaries.
5. **[docs/TECHNICAL_ARCHITECTURE.md](./docs/TECHNICAL_ARCHITECTURE.md)** — Audit the server-authoritative state management, `ProfileStore`/`DataStoreService` schema, RemoteEvent rate-limiting, and offline timestamp calculation.
6. **[docs/DEVELOPMENT_ROADMAP.md](./docs/DEVELOPMENT_ROADMAP.md)** — Verify whether the step-by-step milestones are realistic for a beginner developer assisted by AI agents.
7. **[docs/ART_DIRECTION.md](./docs/ART_DIRECTION.md)** & **[docs/MONETIZATION.md](./docs/MONETIZATION.md)** — Evaluate the Part-first asset strategy, procedural Blender Python scripts, and child-safe monetization guardrails.
8. **[docs/DECISIONS.md](./docs/DECISIONS.md)** & **[docs/AGENT_REVIEWS.md](./docs/AGENT_REVIEWS.md)** — Review open architectural/design questions awaiting ChatGPT's critique and log formal review findings.

---

## 4. Multi-Agent Collaboration Workflow

This project uses a dual-agent governance model documented in **[docs/AGENT_RULES.md](./docs/AGENT_RULES.md)**:
- **Gemini (Antigravity):** Primary Researcher, Game Designer, and Implementation Agent.
- **ChatGPT:** Independent Technical Director, Systems Auditor, and Design Critic.

**Current Gate:** No gameplay code (`src/`) will be implemented until ChatGPT completes the **Phase 0 Architecture & Concept Review** in [docs/AGENT_REVIEWS.md](./docs/AGENT_REVIEWS.md) and open questions in [docs/DECISIONS.md](./docs/DECISIONS.md) are resolved.
