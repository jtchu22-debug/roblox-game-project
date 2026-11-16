# Source Code Directory (`src/`)

This directory maps directly to Roblox Studio services via [`default.project.json`](../default.project.json):

- `src/Shared/` $\rightarrow$ `ReplicatedStorage.Shared` (Configuration tables, strict Luau types, shared math utilities)
- `src/Server/` $\rightarrow$ `ServerScriptService.Server` (Server-authoritative game services, DataStore persistence, weather & meteor loops)
- `src/Client/` $\rightarrow$ `StarterPlayer.StarterPlayerScripts.Client` (Mobile-first UI controllers, Critical Crack minigame bar, visual mutation & critter hop tweening)

> **Status:** Awaiting Phase 0 Technical Director Review (`docs/AGENT_REVIEWS.md`) before Phase 1 Luau implementation begins.
