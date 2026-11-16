# Starfall Ranch (`roblox-game-project`)

> **Project Status:** Phase 0 Audit Integrated — Awaiting Human Lead Sign-Off (`R-007`) Before Stage 1 Vertical Slice  
> **Last Updated:** November 15, 2026  
> **Primary Research & Implementation Agent:** Gemini (Antigravity)  
> **Independent Technical Director & Reviewer:** ChatGPT  

---

## 1. Project Overview

This repository houses the market research, game design documentation, technical architecture, and forthcoming Luau source code for **Starfall Ranch**, an original non-griefing Roblox Meteor Rescue & Creature Habitat Tycoon designed for younger audiences (ages 8–14) with a bright, low-poly stylized aesthetic.

Following Phase 0 market research and an independent Technical Director audit (`docs/CHATGPT_REVIEW.md`), the launch roadmap was intentionally **narrowed into a strict gated vertical-slice plan**: prove that our core 5-minute **Active Meteor Rescue Choice $\rightarrow$ Incubation $\rightarrow$ Keep-vs-Sell $\rightarrow$ Ranch Upgrade** loop is genuinely fun in an uncoached playtest *before* scaling persistence, custom Blender meshes, or optional pure cosmetics.

### Narrowed Prototype & MVP Loop (*Starfall Ranch*)
- **Active Crater Choice:** Falling meteors leave distinct trails and shapes in a shared, non-griefing Crater (**Ember**, **Frost**, **Astral**), letting players choose between fast common hatches and slower high-value pods.
- **Unified Critter Pipeline:** Rescued meteors yield **Star-Pods** that incubate on your Ranch Pad (supporting absolute-timestamp offline incubation in Stage 3+) and hatch into blocky **Cosmic Critters** (*Star-Slime*, *Nebula Fox*, *Solar Golem*).
- **Keep vs. Sell Decision:** Place hatched critters inside your Habitat Pen for steady bounded integer `Coins/sec` (`2 / 4 / 7 Coins/s`) or sell duplicates at your Ranch Gate for instant coins toward visible Ranch upgrades.

---

## 2. Repository Structure

```text
roblox-game-project/
├── README.md                          # Project overview, current gate status, and navigation guide
├── default.project.json               # Rojo configuration mapping src/ to Roblox Studio (activated in R-008)
├── .gitignore                         # Ignore rules for Roblox Studio (.rbxlx.lock), OS, and build artifacts
├── docs/
│   ├── MARKET_RESEARCH.md             # Verified 2025–2026 CCU snapshots, overlooked rivals, negative controls & hypotheses
│   ├── TREND_ANALYSIS.md              # Post-audit disposition of 8 Roblox design trends (Prototype vs. Deferred)
│   ├── GAME_CONCEPTS.md               # 12 original concepts, qualitative E/P/S/D/F/X audit & Top 3 selection
│   ├── GAME_DESIGN.md                 # Narrowed Prototype & MVP spec, bounded integer economy & 5-min simulation
│   ├── TECHNICAL_ARCHITECTURE.md      # Single-item-map schema, nonce claim protocol, DTOs & ProfileStore lifecycle
│   ├── DEVELOPMENT_ROADMAP.md         # 5-stage gated roadmap (Mock Vertical Slice -> Playtest -> Alpha -> Launch)
│   ├── ART_DIRECTION.md               # Low-poly style guide, accessibility, scale/instance budgets & Blender caveats
│   ├── MONETIZATION.md                # Child-safe policy (Creator Rewards, zero paid random items, cosmetics-only post-stability)
│   ├── CHATGPT_REVIEW.md              # Full independent Phase 0 Technical Director audit report
│   ├── AGENT_RULES.md                 # Multi-agent collaboration protocol between Gemini and ChatGPT
│   ├── AGENT_TASKS.md                 # Actionable task board and current execution gates (R-001 through R-010)
│   ├── AGENT_REVIEWS.md               # Structured review log and audit trail
│   └── DECISIONS.md                   # Architecture & Design Decision Records (ADR-001 to ADR-007)
├── src/                               # Placeholder README until R-007 sign-off authorizes Stage 1 (R-008)
└── tools/
    └── blender/                       # Blender Python starter generator (validation deferred to R-010 after Stage 2 fun gate)
```

---

## 3. Documentation Reading Order (For Human Lead Sign-Off `R-007`)

1. **[docs/CHATGPT_REVIEW.md](./docs/CHATGPT_REVIEW.md)** — ChatGPT's independent Phase 0 audit and rationale for scope narrowing.
2. **[docs/DECISIONS.md](./docs/DECISIONS.md)** — Review **ADR-001 through ADR-007** and their resolved post-audit positions.
3. **[docs/GAME_DESIGN.md](./docs/GAME_DESIGN.md)** & **[docs/DEVELOPMENT_ROADMAP.md](./docs/DEVELOPMENT_ROADMAP.md)** — Verify the narrowed 3-species, 1-currency, 5-stage gated prototype plan.
4. **[docs/TECHNICAL_ARCHITECTURE.md](./docs/TECHNICAL_ARCHITECTURE.md)** & **[docs/MONETIZATION.md](./docs/MONETIZATION.md)** — Verify the single-item-map schema, nonce security model, and child-safe Creator Rewards / cosmetics-only policy.
5. **[docs/MARKET_RESEARCH.md](./docs/MARKET_RESEARCH.md)**, **[docs/TREND_ANALYSIS.md](./docs/TREND_ANALYSIS.md)**, **[docs/GAME_CONCEPTS.md](./docs/GAME_CONCEPTS.md)**, and **[docs/ART_DIRECTION.md](./docs/ART_DIRECTION.md)** — Supporting evidence and asset budgets.

---

## 4. Multi-Agent Collaboration Workflow & Current Gate

Governed by **[docs/AGENT_RULES.md](./docs/AGENT_RULES.md)**:
- **Gemini (Antigravity):** Primary Researcher, Game Designer, and Implementation Agent.
- **ChatGPT:** Independent Technical Director, Systems Auditor, and Design Critic.
- **Human Project Lead:** Product Owner and Final Gate Approver.

**Current Gate (`R-007`):** `R-001` through `R-006` documentation revisions are complete. **No Luau gameplay code (`src/`) will be written until the Human Lead explicitly approves the revised `Starfall Ranch` prototype direction and authorizes Stage 1 (`R-008`).**
