# Starfall Ranch (`roblox-game-project`)

> **Project Status:** Stage 1 Ready (`S1-00` Complete) — Rojo Environment, Coding Conventions & ModuleScript Skeleton Initialized  
> **Last Updated:** November 15, 2026  
> **Primary Research & Implementation Agent:** Gemini (Antigravity)  
> **Independent Technical Director & Reviewer:** ChatGPT  

---

## 1. Project Overview

This repository houses the market research, finalized game design, hardened technical architecture, development setup guides, and Luau source skeleton for **Starfall Ranch**—an original, non-griefing Roblox Meteor Rescue & Creature Habitat Tycoon designed for younger audiences (ages 8–14) with a bright low-poly stylized aesthetic.

Following Phase 0 market research, an independent Technical Director audit ([docs/CHATGPT_REVIEW.md](./docs/CHATGPT_REVIEW.md)), and Human Lead sign-off (`R-007`), the development environment and Rojo module skeleton are now ready for **Stage 1: Vertical Slice Implementation (`S1-01`–`S1-09`)**.

### Approved Vertical-Slice Loop (*Starfall Ranch*)
- **Active Crater Choice:** Falling meteors leave distinct trails and shapes in a shared, non-griefing Crater (**Ember**, **Frost**, **Astral**), letting players choose between fast common hatches and slower higher-value pods.
- **Unified Critter Pipeline:** Rescued meteors yield **Star-Pods** that incubate on your Ranch Pad (supporting offline incubation in Stage 3+) and hatch into blocky **Cosmic Critters** (*Star-Slime*, *Nebula Fox*, *Solar Golem*).
- **Keep vs. Sell Decision:** Place hatched critters inside your Habitat Pen for steady bounded integer `Coins/sec` (`2 / 4 / 7 Coins/s`) or sell duplicates at your Ranch Gate for instant coins toward visible Ranch upgrades (`60 / 150 / 320 Coins`).

---

## 2. Repository Structure

```text
roblox-game-project/
├── README.md                          # Project overview, current stage, and quick-start links
├── default.project.json               # Rojo configuration mapping src/ to Roblox Studio
├── aftman.toml                        # Pinned Rojo version (v7.4.4) for Aftman
├── rokit.toml                         # Pinned Rojo version (v7.4.4) for Rokit
├── .gitignore                         # Ignore rules for Roblox Studio (.rbxl/.rbxlx), tools/bin/, OS temp files
├── docs/
│   ├── DEVELOPMENT_SETUP.md           # Beginner guide: Roblox Studio, Rojo live-sync, testing & Git commands
│   ├── CODING_STANDARDS.md            # Mandatory --!strict Luau rules, Init/Start pattern & Rojo ownership
│   ├── GAME_DESIGN.md                 # Narrowed Prototype & MVP spec, bounded integer economy & 5-min simulation
│   ├── TECHNICAL_ARCHITECTURE.md      # Single-item-map schema, nonce claim protocol, DTOs & ProfileStore lifecycle
│   ├── DEVELOPMENT_ROADMAP.md         # Gated roadmap from the mock vertical slice through Stage 6 collection expansion
│   ├── ART_DIRECTION.md               # Low-poly style guide, accessibility, scale/instance budgets & Blender caveats
│   ├── MONETIZATION.md                # Child-safe policy (Creator Rewards, zero paid random items, cosmetics-only)
│   ├── MARKET_RESEARCH.md             # Verified 2025–2026 CCU snapshots, rivals, negative controls & hypotheses
│   ├── TREND_ANALYSIS.md              # Post-audit disposition of 8 Roblox design trends
│   ├── GAME_CONCEPTS.md               # 12 original concepts, qualitative audit & Top 3 selection
│   ├── CHATGPT_REVIEW.md              # Full independent Phase 0 Technical Director audit report
│   ├── AGENT_RULES.md                 # Multi-agent collaboration protocol between Gemini and ChatGPT
│   ├── AGENT_TASKS.md                 # Prioritized Stage 1–5 MVP task list with clear dependencies
│   ├── AGENT_REVIEWS.md               # Structured review log and audit trail
│   └── DECISIONS.md                   # Approved Architecture & Design Decision Records (ADR-001 to ADR-007)
├── src/
│   ├── Shared/                        # -> ReplicatedStorage.Shared
│   │   ├── Constants.luau             # Structural & security bounds
│   │   ├── Types.luau                 # Strict exported Luau types & DTO contracts
│   │   ├── Config/                    # CritterConfig, MeteorConfig, UpgradeConfig (Stage 1 stubs)
│   │   └── Util/                      # EconomyMath, FormatUtil, ValidationUtil
│   ├── Server/                        # -> ServerScriptService.Server
│   │   ├── ServerInit.server.luau     # Single server entry point (Init -> Start)
│   │   └── Services/                  # NetworkService, DataService, EconomyService, PlotService, MeteorService
│   └── Client/                        # -> StarterPlayer.StarterPlayerScripts.Client
│       ├── ClientInit.client.luau     # Single client entry point (Init -> Start)
│       └── Controllers/               # Input, Crack, PlotVisual, UI, Sound controllers
└── tools/
    ├── start-rojo.ps1                 # One-command Rojo live sync server launcher
    ├── build-place.ps1                # Builds standalone build.rbxlx place snapshot
    └── blender/                       # Blender Python starter generator (validation deferred to Stage 4 R-010)
```

---

## 3. Quick Start for Developers (First Time Here?)

1. **Set up Roblox Studio & Rojo Sync:** Follow **[docs/DEVELOPMENT_SETUP.md](./docs/DEVELOPMENT_SETUP.md)** step-by-step to open a Baseplate in Studio, connect Rojo (`.\tools\start-rojo.ps1`), and run `Play (F5)` to verify the skeleton scripts initialize cleanly.
2. **Read Coding Rules Before Writing Code:** Review **[docs/CODING_STANDARDS.md](./docs/CODING_STANDARDS.md)** (`--!strict`, `Init()`/`Start()`, single state writer, Rojo ownership boundaries).
3. **Track Next Implementation Tasks:** Check **[docs/AGENT_TASKS.md](./docs/AGENT_TASKS.md)**—the next prioritized tasks are **`S1-01`** (Shared Config & Bounded Math) and **`S1-02`** (Idempotent Greybox Map Generator).
