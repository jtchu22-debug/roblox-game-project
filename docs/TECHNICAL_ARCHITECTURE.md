# Technical Architecture & Engineering Plan (Post-Audit Revision)

> **Last Updated:** November 15, 2026 (Revised per Phase 0 Technical Director Audit — `R-004`)  
> **Author:** Gemini (Primary Implementation Planner)  
> **Auditor:** ChatGPT (Independent Technical Director)  
> **Target Stack:** Roblox Studio, Luau (`--!strict`), pinned Rojo (`default.project.json`), pinned `ProfileStore` (Stage 3+)  

---

## 1. Architectural Philosophy & Core Invariants

1. **100% Server-Authoritative State & Economy:** The client never determines currency amounts, species rolls, cooldowns, or timers. Client remotes only send intent requests with bounded primitives.
2. **One Authority Per Entity (Single Item Map):** Every Pod/Critter exists in **one** authoritative `Items` table inside the player's session state, keyed by an immutable server UUID (`ItemUID`). A Critter cannot exist in two places at once (no separate `PlantedBeds` vs `Inventory` vs `ActivePenCritters` duplication).
3. **Non-Yielding State Transitions:** All inventory, slot, upgrade, and meteor-claim transitions mutate server memory atomically **without yielding** between validation and state commit.
4. **Stage-Appropriate Persistence:** Stages 1–2 run on an explicit `MockStore` adapter to validate fun and concurrency fast. Stage 3+ switches cleanly to pinned **`ProfileStore`** (`MadStudioRoblox/ProfileStore`)—never a custom handmade lock, and **never** falling back to a blank live profile on a DataStore read failure.
5. **Lightweight Client-Only Critter Visuals:** Server stores zero `Humanoid` or `Model` physics for critters. The server replicates a minimal `PublicPlotDTO`; clients render anchored, non-colliding low-poly models (budgeted at $\le 30$ critters server-wide) driven by one centralized client manager.

---

## 2. Project Hierarchy (`default.project.json`)

> *Status (Updated 2026-11-15):* Following `R-007` Human Lead approval, the `src/` ModuleScript skeleton (`S1-00`) has been initialized and Rojo smoke-tested (`build.rbxlx`). Unmanaged 3D workspace templates and assets inside `.rbxl` live outside Rojo-managed code folders or are recreated idempotently by the tagged greybox generator (`S1-02`).

```text
src/
├── Shared/                              # -> ReplicatedStorage.Shared (Public static definitions)
│   ├── Types.luau                       # Strict Luau DTO, Item, Plot, and Config types
│   ├── Constants.luau                   # Bounded caps (MAX_BAG=10, MAX_PLOTS=2..6, COIN_CAP)
│   ├── Config/
│   │   ├── CritterConfig.luau           # 3 prototype species, expanding to 24 with Stage 6
│   │   ├── MeteorConfig.luau            # 3 Meteor Traits (Ember, Frost, Astral) & drop weights
│   │   └── UpgradeConfig.luau           # 3 Prototype Upgrades + Stage 3 alpha expansions
│   └── Util/
│       ├── EconomyMath.luau             # Bounded integer settlement with sub-second remainder
│       ├── FormatUtil.luau              # Safe integer formatting & timer strings
│       └── ValidationUtil.luau          # Finite number, integer, enum, and dense-array guards
│
├── Server/                              # -> ServerScriptService.Server (Authoritative game logic)
│   ├── ServerInit.server.luau           # Ordered startup, readiness gates, shutdown handling
│   ├── Libs/
│   │   └── ProfileStore/                # Pinned upstream MadStudioRoblox/ProfileStore + MIT LICENSE (Stage 3)
│   └── Services/
│       ├── NetworkService.luau          # Remote creation, schema validation, per-player token-bucket limits
│       ├── DataService.luau             # MockStore (Stages 1–2) / ProfileStore adapter (Stage 3+), reconciliation
│       ├── EconomyService.luau          # Single state writer: bag, incubation, pen placement, sell, upgrades, accrual
│       ├── PlotService.luau             # Plot allocation, idempotent slot nodes, release & cleanup
│       └── MeteorService.luau           # Crater spawning, Nonce claim lifecycle, server-verified cracking
│
└── Client/                              # -> StarterPlayer.StarterPlayerScripts.Client
    ├── ClientInit.client.luau           # Subscribes listeners, then requests initial state snapshot
    └── Controllers/
        ├── InputController.luau         # ProximityPrompt hooks + Touch/Keyboard/Gamepad bindings
        ├── CrackController.luau         # Visual tap/optional feel ring + local feedback (no economy power)
        ├── PlotVisualController.luau    # Centralized single-loop hopping critter visuals & revision cleanup
        ├── UIController.luau            # Mobile-safe HUD, Bag/Keep-Sell UI, Upgrade prompts, Settings
        └── SoundController.luau         # Accessible audio chimes with Mute & Reduced-Motion support
```

---

## 3. Single Authoritative Schema & Entity Lifecycle (`R-004`)

### 3.1 Valid Item Lifecycle State Machine

```text
[Cracked Meteor] -> "PodInBag" -> "Incubating" -> "HatchedInBag" -> "InPen"
                                                        |               |
                                                        +-----> [SOLD (Removed Permanently)]
```

**Enforced Invariants (Checked in Unit Tests & Server Transitions):**
1. Every `ItemUID` in `Profile.Items` has **one** valid `State` (`"PodInBag" | "Incubating" | "HatchedInBag" | "InPen"`).
2. If `State == "Incubating"` or `"InPen"`, `AssignedSlot` points to **exactly one** slot ID (`"Incubator_1"`, `"Pen_1"`, etc.), and `Slots[AssignedSlot] == ItemUID`.
3. Every slot ID holds **at most one** `ItemUID`.
4. Only `State == "PodInBag"` can move to an open Incubator; only `State == "Incubating"` with `os.time() >= MaturesAt` can hatch to `"HatchedInBag"`; only `"HatchedInBag"` can move to an open Pen slot or be sold; `"InPen"` items **cannot** be sold directly (must be removed to Bag first, preventing accidental sale of active critters).
5. `BagCount` (`PodInBag + HatchedInBag`) $\le$ `MaxBagCapacity`. Inventory capacity is checked **before** consuming any meteor claim or hatching.
6. All currencies and counts are finite integers (`0 <= Coins <= 1_000_000_000`); no `Instance` objects, functions, or sparse mixed tables inside persisted data.

### 3.2 Persisted Profile Schema (`SchemaVersion = 1`)

```luau
--!strict
export type ItemState = "PodInBag" | "Incubating" | "HatchedInBag" | "InPen"
export type SpeciesId = "StarSlime" | "NebulaFox" | "SolarGolem"
export type VariantId = "Normal" | "Radiant"

export type CritterItemRecord = {
	UID: string,                  -- Immutable server GUID
	SpeciesId: SpeciesId,
	Variant: VariantId,           -- Assigned atomically on hatch on server
	State: ItemState,
	AssignedSlot: string?,        -- e.g. "Incubator_1" or "Pen_1" when active
	PlantedAt: number?,           -- Server os.time() when incubation started
	MaturesAt: number?,           -- Absolute server os.time() when ready to hatch
	CreatedAt: number,
}

export type PlayerProfileData = {
	SchemaVersion: number,
	Coins: number,                -- Integer Coins >= 0
	PendingFraction: number,      -- Carried fractional coin remainder (< 1.0)
	LastAccrualTimestamp: number, -- Server epoch used for deterministic online settlement
	Revision: number,             -- Monotonic state revision for client sync
	Items: { [string]: CritterItemRecord },
	Slots: { [string]: string },  -- SlotId -> ItemUID (e.g. ["Incubator_1"] = uid)
	Upgrades: { [string]: boolean },
	DiscoveredSpecies: { [SpeciesId]: boolean }, -- Stage 4 simple checklist (no stats)
}
```

### 3.3 Whitelisted DTO Replication (Private vs. Public)
- **`OwnerStateDTO` (Sent only to owning player via `SyncOwnerState`):** Contains `{ Revision, Coins, BagCap, Items, Slots, Upgrades, DiscoveredSpecies }`. Never sends internal server nonces, anti-abuse flags, or external telemetry IDs.
- **`PublicPlotDTO` (Broadcast cleanly for all 6 plots via `SyncPublicPlots`):** Contains `{ PlotId, OwnerUserId, OwnerDisplayName, PlotRevision, UnlockedUpgrades, ActivePenVisuals = { [SlotId]: { SpeciesId, Variant } }, IncubatorVisuals = { [SlotId]: { MaturesAt } } }`.
- **Late-Join & Resync:** Client connects listeners first, then fires `RequestInitialSnapshot`. Out-of-order revisions trigger a rate-limited resync request.

---

## 4. Server-Authoritative Protocols & Remote Validation

### 4.1 Meteor Cracking Nonce & Claim Protocol
To eliminate replay exploits, double-claims, and latency-unfair client timers:
1. **Claim Start (`RequestStartCrack`):**
   - Server validates: `ProfileReady == true`, `CharacterAlive == true`, `(RootPos - MeteorPos).Magnitude <= 18`, `BagCount < BagCap`, player has no other active claim, and `Meteor.ClaimedBy == nil`.
   - Server sets `Meteor.ClaimedBy = player.UserId`, generates a cryptographic-grade random `AttemptNonce = HttpService:GenerateGUID(false)`, records `Meteor.Generation`, `StartedAt = os.clock()`, and `Deadline = os.clock() + 6.0`.
   - Returns `{ Ok = true, AttemptNonce = AttemptNonce, MeteorUID = MeteorUID }` (or safe failure reason).
2. **Claim Finish (`RequestFinishCrack`):**
   - Client sends `{ MeteorUID, AttemptNonce }` (**no `ClientDelta` parameter is trusted or used for economy**).
   - Server validates: `ProfileReady == true`, `CharacterAlive == true`, active claim exists matching `(player.UserId, MeteorUID, AttemptNonce)`, `os.clock() <= Deadline`, `os.clock() - StartedAt >= 0.4` (prevents instant frame-0 macro), `(RootPos - MeteorPos).Magnitude <= 22`, and `BagCount < BagCap`.
   - **Atomic Non-Yielding Commit:** Consumes `AttemptNonce`, deletes active meteor claim, creates 1 new `CritterItemRecord` (`State = "PodInBag"`) in `Profile.Items`, removes the meteor entity, and replicates updated `OwnerStateDTO`.
   - **Failure / Timeout Cleanup:** If the player disconnects, dies, moves >28 studs away, or exceeds `Deadline`, a server heartbeat sweeps expired claims and frees the meteor cleanly.

### 4.2 Complete Remote Contract & Rate Limits (MVP Scope)

| Remote | Direction | Arguments (Strictly Validated) | Token Bucket Limit |
| :--- | :---: | :--- | :---: |
| `RequestInitialSnapshot` | `C -> S` (`RemoteEvent`) | *(None)* — triggers snapshot once per ready session + resync cooldown | `1 / 3s` |
| `RequestStartCrack` | `C -> S` (`RemoteFunction`) | `(MeteorUID: string)` (`# <= 40`) | `4 / sec` |
| `RequestFinishCrack` | `C -> S` (`RemoteFunction`) | `(MeteorUID: string, AttemptNonce: string)` (`# <= 40`) | `4 / sec` |
| `RequestPlotAction` | `C -> S` (`RemoteEvent`) | `(Action: "StartIncubate" \| "Hatch" \| "PlaceInPen" \| "RemoveFromPen" \| "SellCritter", TargetSlotOrUID: string, ItemUID: string?)` | `8 / sec` |
| `RequestBuyUpgrade` | `C -> S` (`RemoteFunction`) | `(UpgradeId: string)` (allowlisted against `UpgradeConfig`) | `3 / sec` |
| `SyncOwnerState` | `S -> C` (`RemoteEvent`) | `OwnerStateDTO` | Server-driven |
| `SyncPublicPlots` | `S -> C` (`RemoteEvent`) | `{ PublicPlotDTO }` + `PlotRevision` | Server-driven |
| `MeteorLifecycle` | `S -> C` (`RemoteEvent`) | `{ Action: "Spawn" \| "Claimed" \| "ClaimReleased" \| "Despawn", MeteorUID, Trait?, Position?, ClaimedBy? }` | Server-driven |

*Note: Removed entirely from MVP: `RequestGiftItem`, `RequestFuseCritters`, `RequestLikePlot`, `WeatherChanged`, `OfflineReportReady`, and shop window remotes.*

### 4.3 Inbound Validation & Rate-Limit Rules (`NetworkService.luau`)
Every `OnServerEvent` and `OnServerInvoke` passes through a centralized validator:
- Reject any non-matching argument count or type before reading fields.
- Reject `NaN`, `±math.huge`, negative numbers, and non-integers where integers are expected.
- Resolve caller strictly from Roblox's first argument (`player`)—never accept a `UserId` or `PlotId` from client payloads.
- Charge the player's per-action token bucket **even on rejected/invalid calls**, and clean up buckets on `PlayerRemoving`.

---

## 5. Saving Lifecycle, Offline Safety & Testing Matrix

### 5.1 Saving Rules (`DataService.luau`)
1. **Explicit Readiness Gate:** Every gameplay remote handler checks `DataService:IsReady(player)` and rejects actions if a profile is still loading or closing.
2. **Stage 1–2 (`MockStore`):** Explicitly guarded by `Constants.USE_MOCK_STORE == true` inside Studio/prototype mode. Cannot be accidentally enabled in live production.
3. **Stage 3+ (`ProfileStore`):**
   - Vendor pinned `MadStudioRoblox/ProfileStore` with `LICENSE` preserved and version tag recorded in `src/Server/Libs/ProfileStore/VERSION.md`.
   - On `PlayerAdded`: `Store:StartSessionAsync("Player_" .. player.UserId, { Cancel = function() return player.Parent ~= Players end })`.
   - If `StartSessionAsync` returns `nil` (load failed or session lock unrecoverable): **kick the player cleanly with a polite retry message**—**NEVER** initialize a temporary blank live profile!
   - Listen to `Profile.OnSessionEnd`: immediately halt all gameplay mutations for that player and kick cleanly so stale sessions cannot mutate data.
   - Reconcile missing keys using `Profile:Reconcile()` plus explicit schema migration that preserves existing valid items/coins.
   - On `PlayerRemoving` and `game:BindToClose`: end sessions gracefully within the `BindToClose` shutdown window.
   - Use isolated DataStore scopes (`StarfallRanch_Alpha_v1` vs `StarfallRanch_Prod_v1`) so Studio tests never touch live player data.

### 5.2 Offline Incubation and Stage 6 Coin Settlement
- When a pod starts incubating, server records `MaturesAt = os.time() + SpeciesConfig.HatchSeconds`.
- On profile load, **only `MaturesAt`** is checked on demand when hatching (`os.time() >= Item.MaturesAt`).
- Through Stage 5, reset `LastAccrualTimestamp` on login with zero offline Coin payout.
- In Stage 6, compute offline Coins from the durable logout pen rate and elapsed server time within configured caps. Resolve the 2× pass server-side and commit the credited balance and settlement checkpoint in one durable update. Start online accrual from the new session timestamp. Verify a failed save or repeated join cannot consume or duplicate the same interval. [Purchase and settlement contract](./MONETIZATION.md#4-purchase-delivery-and-receipt-durability)

### 5.3 Mandatory Adversarial & Persistence Test Matrix (Every Milestone)
- **Stage 1 Tests:** 2-player simultaneous meteor finish race; expired/forged `AttemptNonce`; out-of-range finish; `NaN`/`nil`/wrong-type remote fuzzing; bag-full crack attempt; player leaving/respawning mid-crack; rapid plot upgrade spam.
- **Stage 3 Tests:** Join/save/rejoin preservation; forced `DataStore` load failure (verifies clean kick without overwriting data); overlapping dual-server session lock recovery; `OnSessionEnd` lock theft handling; server `BindToClose` shutdown save completion; clock boundary tests (`MaturesAt` 1s before vs. 12h after).

---

## 6. Stage 6 Critter Traits and Economy

- Extend the saved critter record with a server-rolled weight band and one optional income mutation. Migrate existing records to Normal weight and no income mutation. Keep the Radiant cosmetic field independent.
- Resolve progression and select the eligible meteor pool on the server. Derive the integer pen rate from the species config and saved traits using the [launch economy limits](./GAME_DESIGN.md#72-weight-and-income-mutations). Accrue at the old rate before a pen changes, then apply the capped new rate. Snapshot the same effective rate for offline settlement.
- Give the owner DTO the displayed kilograms, mutation, and effective Coins/s. Use capped cosmetic size and mutation visuals for public plot DTOs. Verify the migration, exact cap boundaries, paid and free pool eligibility, and reconnect settlement at the highest configured earn rates.
