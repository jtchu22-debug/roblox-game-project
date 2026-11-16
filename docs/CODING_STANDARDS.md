# Luau Coding Conventions & Documentation Standards (`CODING_STANDARDS.md`)

> **Last Updated:** November 15, 2026  
> **Applies To:** All `.luau` scripts in `src/` and Studio tooling scripts in `tools/`  
> **Goal:** Keep code beginner-readable, AI-friendly, type-safe, and strictly server-authoritative.

---

## 1. Rojo File Naming & Instance Mapping

Because our repository uses **Rojo (`default.project.json`)** as the canonical source of truth, file extensions determine what Roblox Studio creates:

| File Suffix | Roblox Instance Created | Where Allowed |
| :--- | :--- | :--- |
| `*.server.luau` | `Script` (runs on Server) | Only `src/Server/ServerInit.server.luau` |
| `*.client.luau` | `LocalScript` (runs on each Client) | Only `src/Client/ClientInit.client.luau` |
| `*.luau` | `ModuleScript` (reusable library/service/controller) | `src/Shared/`, `src/Server/Services/`, `src/Client/Controllers/` |

> **Rule:** Never add extra `.server.luau` or `.client.luau` entry-point scripts inside subfolders. All gameplay code runs through the single deterministic startup loop in `ServerInit.server.luau` and `ClientInit.client.luau`.

---

## 2. Mandatory `--!strict` Typing & `Types.luau`

1. **Line 1 of every `.luau` file MUST be `--!strict`.** This enables Roblox Studio's Script Analysis tab to catch typos, wrong argument types, and `nil` bugs before you even hit Play.
2. **Shared Types Live in `src/Shared/Types.luau`:** Any data structure sent between Server and Client (items, DTOs, config schemas) must be exported from `Types.luau` rather than redefined ad-hoc in multiple scripts.
3. **Avoid `any`:** Prefer exact types (`SpeciesId`, `PlayerProfileData`, `OwnerStateDTO`) or `unknown` paired with explicit runtime validation (`ValidationUtil.luau`).

---

## 3. Two-Phase Service & Controller Lifecycle (`Init` $\rightarrow$ `Start`)

Every Server Service (`src/Server/Services/`) and Client Controller (`src/Client/Controllers/`) follows the same clean lifecycle contract:

```luau
local ExampleService = {
	Name = "ExampleService",
}

-- Phase 1: Synchronous setup ONLY (create folders, remotes, internal tables).
-- Do NOT yield or call methods on other Services here—they may not be initialized yet!
function ExampleService.Init(self: typeof(ExampleService)): ()
end

-- Phase 2: Safe to connect events, start loops, and call other Services.
function ExampleService.Start(self: typeof(ExampleService)): ()
end

return ExampleService
```

- **`ServerInit.server.luau` order:** `NetworkService` $\rightarrow$ `DataService` $\rightarrow$ `EconomyService` $\rightarrow$ `PlotService` $\rightarrow$ `MeteorService` (first all `:Init()`, then all `:Start()`).
- **`ClientInit.client.luau` order:** `SoundController` $\rightarrow$ `UIController` $\rightarrow$ `PlotVisualController` $\rightarrow$ `CrackController` $\rightarrow$ `InputController` (first all `:Init()`, then all `:Start()`, followed by requesting the initial snapshot so no server packet is missed).

---

## 4. Mandatory Module Docstring Header Standard

Every new `.luau` module must start with a plain-English header block right below `--!strict` so both human beginners and AI reviewers immediately understand its role:

```luau
--!strict
--[[
	Service / Controller / Module: <ExactName>
	Purpose: <1-2 sentences describing what this module owns.>
	Connections: <Which other modules/remotes/services it talks to.>
	How to Test in Studio: <Concrete Play (F5) or Local Server verification step.>
]]
```

---

## 5. Naming & Style Conventions

| Construct | Convention | Example |
| :--- | :--- | :--- |
| Files, Services, Controllers, Types | `PascalCase` | `EconomyService.luau`, `CritterItemRecord` |
| Constant scalar keys inside `Constants.luau` | `UPPER_SNAKE_CASE` | `MAX_BAG_CAPACITY`, `USE_MOCK_STORE` |
| Local variables, parameters, table fields (config/DTO) | `camelCase` (locals) / `PascalCase` (DTO keys) | `local elapsedSeconds = 5`, `item.SpeciesId` |
| Intentionally unused parameters | Prefix with `_` | `function foo(_player: Player)` |
| Module table creation | Table literal + explicit `Name` | `local MyService = { Name = "MyService" }` |

- **No Magic Numbers:** All costs, capacities, distances, and timers belong in `src/Shared/Constants.luau` or `src/Shared/Config/*.luau`.
- **Single Source of State:** Only `EconomyService` mutates `Items`, `Slots`, `Coins`, and `Upgrades` inside a player's active profile. Other services call `EconomyService` methods rather than editing `Profile.Items` directly.

---

## 6. Server-Authority & Validation Rules

1. **Zero Client Trust:** Never read currency amounts, rewards, or timing bonuses from client payloads.
2. **Validate Every Remote Boundary:** Use `ValidationUtil.IsFiniteInteger` and `ValidationUtil.IsBoundedString` on inbound parameters to reject `NaN`, `±math.huge`, negative numbers, and malformed strings before processing.
3. **Non-Yielding Transitions:** Never call `task.wait()` or yielding async APIs between checking a player's inventory/coin balance and committing the updated state.

---

## 7. Rojo-Managed vs. Studio-Managed Object Ownership

To prevent Rojo from deleting your 3D map or lighting when syncing:

- **Rojo-Managed (Edited in Git/VS Code/Antigravity ONLY):**
  - `ReplicatedStorage.Shared` (`src/Shared`)
  - `ServerScriptService.Server` (`src/Server`)
  - `StarterPlayer.StarterPlayerScripts.Client` (`src/Client`)
- **Studio-Managed (Preserved by Rojo because `default.project.json` does NOT claim them):**
  - `Workspace` (Crater, Plots, `Baseplate`, `SpawnLocation` — built in Stage 1 via an idempotent tagged generator under `Workspace.StarfallGreyboxRoot`)
  - `Lighting`, `SoundService`, `ReplicatedStorage.Assets`

> **Golden Rule:** Never edit `ReplicatedStorage.Shared`, `ServerScriptService.Server`, or `StarterPlayer.StarterPlayerScripts.Client` directly inside Roblox Studio while Rojo is syncing—any manual edits inside Studio to Rojo-managed folders will be overwritten by the files on disk!
