# Multi-Agent Collaboration Rules (`AGENT_RULES.md`)

> **Last Updated:** November 15, 2026  
> **Applies To:** Gemini (Antigravity), ChatGPT (Technical Director), and the Human Project Lead

---

## 1. Agent Roles & Responsibilities

| Agent | Role Title | Core Responsibilities |
| :--- | :--- | :--- |
| **Gemini (Antigravity)** | **Primary Research, Design & Implementation Agent** | • Conduct live market & trend research.<br>• Draft and update game design, technical architecture, and Blender automation scripts.<br>• Implement modular Luau source code (`src/`) according to approved specs.<br>• Maintain `AGENT_TASKS.md` status updates. |
| **ChatGPT** | **Independent Technical Director & Reviewer** | • Independently audit research methodology, trend conclusions, and concept selection.<br>• Challenge weak assumptions, math imbalances, or scope creep.<br>• Review Luau architecture for security flaws, race conditions, DataStore edge cases, and mobile performance bottlenecks.<br>• Record formal critiques in `docs/AGENT_REVIEWS.md` and propose/approve decisions in `docs/DECISIONS.md`. |
| **Human Project Lead** | **Product Owner & Final Decision Maker** | • Approve major direction changes and resolve ties between Gemini and ChatGPT.<br>• Run playtests in Roblox Studio and manage GitHub / Roblox publishing credentials. |

---

## 2. File Ownership & Concurrency Protocol

To prevent merge conflicts and accidental overwrites when both agents interact with the repository:

1. **Avoid Simultaneous Edits to the Same File:**
   - **Gemini Primary Files:** `src/**`, `tools/**`, `docs/MARKET_RESEARCH.md`, `docs/TREND_ANALYSIS.md`, `docs/GAME_CONCEPTS.md`, `docs/GAME_DESIGN.md`, `docs/TECHNICAL_ARCHITECTURE.md`, `docs/DEVELOPMENT_ROADMAP.md`, `docs/ART_DIRECTION.md`, `docs/MONETIZATION.md`, `docs/AGENT_TASKS.md`.
   - **ChatGPT Primary Files:** `docs/AGENT_REVIEWS.md` (primary review log) and the Reviewer Response sections of `docs/DECISIONS.md`.
2. **Never Overwrite Without Reviewing:**
   - Before modifying any file, each agent **must read the latest committed version** of that file and check `docs/DECISIONS.md` and `docs/AGENT_REVIEWS.md`.
   - If ChatGPT wants to propose changes to `GAME_DESIGN.md` or `TECHNICAL_ARCHITECTURE.md`, ChatGPT should either:
     - Log the specific required changes in `docs/AGENT_REVIEWS.md` and `docs/DECISIONS.md` for Gemini to integrate, **OR**
     - Submit changes via a dedicated branch / Pull Request (e.g., `review/chatgpt-phase0-audit`).
3. **Branching & Pull Request Standard:**
   - `main` represents the current agreed-upon baseline.
   - Substantial code or design changes must use descriptive feature/review branches:
     - `feat/phase1-plot-core` (Gemini implementation branches)
     - `fix/datastore-session-lock` (Bugfix branches)
     - `review/chatgpt-<topic>` (ChatGPT technical review / architecture refinement branches)

---

## 3. Decision & Disagreement Resolution Workflow

Whenever a major architectural or design question arises:
1. **Log an ADR (Architecture/Design Decision Record)** in [`docs/DECISIONS.md`](./DECISIONS.md) with status `PROPOSED (Awaiting ChatGPT Review)`.
2. **ChatGPT Evaluates the Proposal:** ChatGPT challenges assumptions, evaluates edge cases, and marks the decision as `APPROVED`, `APPROVED WITH MODIFICATIONS`, or `COUNTER-PROPOSED`.
3. **Escalate Only Unresolved Trade-offs to Human Lead:** If both agents agree on a technical best practice (e.g., server-side rate limiting), adopt it immediately. If a trade-off affects creative vision (e.g., switching from Concept #1 to Concept #2 or #3), highlight the choice clearly for the Human Project Lead.

---

## 4. Luau Code Quality Standards (For Phase 1+ Implementation)

All Luau scripts committed to `src/` must adhere to:
- `--!strict` type checking header at line 1 of every `.luau` file.
- Zero magic numbers inside service logic (all constants must live in `src/Shared/Config/` or `src/Shared/Constants.luau`).
- Explicit server-side validation (`typeof`, `NaN` check, range check, rate-limit check) on the first line of every `OnServerEvent` and `OnServerInvoke` handler.
- Clear beginner-friendly docstrings at the top of each module explaining **what it does**, **how it connects to other modules**, and **how to test it in Roblox Studio**.
