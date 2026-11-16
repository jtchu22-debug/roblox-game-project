# Technical Architecture & Engineering Plan

> **Last Updated:** November 15, 2026  
> **Author:** Gemini (Primary Implementation Planner)  
> **Reviewer:** ChatGPT (Independent Technical Director)  
> **Target Stack:** Roblox Studio, Luau (`--!strict`), Rojo 7.x (`default.project.json`), `DataStoreService`  

---

## 1. Architectural Philosophy

Because the human developer is a **beginner in Luau** and development is **AI-assisted (Gemini + ChatGPT)**, the codebase must follow four non-negotiable engineering rules:

1. **100% Server-Authoritative Economy & State:** The client *never* tells the server how much money it earned, what mutation rolled, or whether a timer finished. The client only sends **intent requests** (e.g., `"AttemptCrackMeteor"`, `"RequestPlantGeode"`, `"RequestBuySupplyItem"`), and the server validates cooldowns, distances, prices, and timestamps.
2. **Data-Driven Configuration (`src/Shared/Config`):** All Critter stats, Crystal growth times, Mutation multipliers, Weather weights, and Upgrade costs live in pure declarative Luau tables inside `ReplicatedStorage.Shared.Config`. Adding a new critter or tuning balance never requires editing core service logic.
3. **Single-Script Entry Point Pattern (Modular Services & Controllers):** Instead of scattering dozens of loose `Script` instances inside `Workspace` parts (which causes race conditions and makes Git/AI collaboration impossible), we use **one server bootstrap script** (`ServerInit.server.luau`) and **one client bootstrap script** (`ClientInit.client.luau`) that require organized `ModuleScript`s.
4. **Zero Server-Side Humanoid Physics for Pets/Critters:** Spawning 60 Roblox `Humanoid` models for ranch critters destroys server frame time and mobile battery. On the server, an active Critter is **purely a Luau table**. The client renders lightweight anchored `Model`s and animates their hopping via `TweenService` / `RunService.RenderStepped`.

---

## 2. Roblox Studio & Rojo Project Hierarchy

Our repository maps directly into Roblox Studio via `default.project.json`:

```text
src/
├── Shared/                              # -> ReplicatedStorage.Shared
│   ├── Types.luau                       # Exported Luau type definitions (--!strict)
│   ├── Constants.luau                   # Game-wide constants (Max Offline Hours, Plot Count)
│   ├── Config/
│   │   ├── CritterConfig.luau           # 8 MVP Critter definitions (BaseCoinsPerSec, GrowthTime, Rarity)
│   │   ├── CrystalConfig.luau           # 6 MVP Crystal Geode definitions (BaseValue, GrowthTime, StockOdds)
│   │   ├── MutationConfig.luau          # 8 MVP Mutations (Multiplier, WeatherSource, Color, Material)
│   │   ├── WeatherConfig.luau           # 5 MVP Cosmic Weather events (Duration, Odds, Skybox, MutationChance)
│   │   └── UpgradeConfig.luau           # Plot pad upgrades & Rebirth requirements
│   └── Util/
│       ├── EconomyMath.luau             # Pure deterministic functions for item value & offline earnings
│       ├── FormatUtil.luau              # Number formatting (1,250 -> "1.25K", timer strings "04:12")
│       └── WeightRoller.luau            # Deterministic weighted RNG table selector
│
├── Server/                              # -> ServerScriptService.Server
│   ├── ServerInit.server.luau           # Ordered initialization of all Server Services
│   └── Services/
│       ├── DataService.luau             # DataStore load/save, session-locking, auto-save loop, offline calc
│       ├── PlotService.luau             # Plot assignment, Soil Beds, Incubator Pads, Habitat Pens, Upgrades
│       ├── MeteorService.luau           # Crater meteor spawning, Critical Crack validation, Mega-Geode boss
│       ├── WeatherService.luau          # 6-min global weather cycle, mutation application ticks, Beacons
│       ├── SupplyShipService.luau       # Synchronized 5-min shop seed (`math.floor(os.time() / 300)`) & purchases
│       ├── InventoryService.luau        # Item UUID management, Selling, Star-Fuser 5-to-1, Proximity Gifting
│       └── MonetizationService.luau     # MarketplaceService ProcessReceipt & GamePass ownership caching
│
└── Client/                              # -> StarterPlayer.StarterPlayerScripts.Client
    ├── ClientInit.client.luau           # Ordered initialization of all Client Controllers
    └── Controllers/
        ├── InputController.luau         # ProximityPrompts, mobile tap targets, Hotbar equipping
        ├── CrackMinigameController.luau # 1.5s Critical Crack timing bar UI & camera feedback
        ├── PlotVisualController.luau    # Renders growing crystals, hopping critters, and floating coin popups
        ├── WeatherVisualController.luau # Smooth Lighting/Skybox tweens, rain/solar particle emitters
        ├── UIController.luau            # Top HUD, Supply Ship Shop, Cosmic Bestiary, Offline Welcome Card
        └── SoundController.luau         # Pitch-ascending combo chimes, weather sirens, UI clicks
```

> **Note on 3D Assets (`ReplicatedStorage.Assets`):** Models built in Roblox Studio (or imported from Blender) are stored in a folder `ReplicatedStorage.Assets` (`Crystals/`, `Critters/`, `Meteors/`, `VFX/`) inside the `.rbxl` place file and referenced by `ModelId` string from `Config`.

---

## 3. Client / Server Responsibilities Matrix

| System | Server Responsibility (`ServerScriptService`) | Client Responsibility (`StarterPlayerScripts`) |
| :--- | :--- | :--- |
| **Meteor Cracking** | Spawns meteor ID + position; records `CrackStartTime`; validates when client sends `FinishCrack` that elapsed time matches the Green/Gold timing window; awards rolled item. | Displays 1.5s moving needle UI; plays hammer/laser swing animation, screen shake, and particle burst on completion. |
| **Plot Growth & Weather** | Tracks `PlantedAt` Unix timestamp; rolls mutations on active plot items when weather ticks; calculates offline progress on `PlayerAdded`. | Scales 3D crystal/pod model smoothly from `0.2x` to `1.0x` based on `(workspace:GetServerTimeNow() - PlantedAt) / Duration`; applies mutation materials/particles. |
| **Critter Habitat Pens** | Stores array of active Critter UUIDs in pen; computes exact `CoinsPerSecond` sum; adds accrued coins to plot vault. | Spawns low-poly Critter models inside the pen's bounding box; runs a lightweight client loop making them hop every 2–4 seconds and pop floating `+Coins` text. |
| **Supply Ship Shop** | Generates deterministic stock every 300 seconds using `Random.new(math.floor(os.time() / 300))`; tracks per-player stock purchases per 5-min window; deducts coins. | Displays countdown timer (`300 - (os.time() % 300)`); renders item cards and stock remaining counts. |

---

## 4. Networking Architecture (`RemoteEvents` & `RemoteFunctions`)

All remotes are created programmatically at startup inside `ReplicatedStorage.Remotes` by a small `Network` wrapper module so no manual Studio setup can go out of sync.

### Server-to-Client (`RemoteEvent:FireClient` / `FireAllClients`)
| Remote Name | Payload Schema | Purpose |
| :--- | :--- | :--- |
| `SyncPlayerData` | `PlayerProfileData` (full table on join, delta patch on update) | Keeps client UI, inventory, Bestiary, and currency in sync. |
| `OfflineReportReady` | `{ ElapsedSeconds: number, CoinsEarned: number, MaturedCount: number, NewMutations: number }` | Triggers the *"While You Were Away"* welcome modal on login. |
| `PlotStateUpdated` | `{ PlotId: number, OwnerUserId: number, Beds: {...}, Pens: {...}, Upgrades: {...} }` | Replicates plot visuals so all 6 players see each other's growing crystals and giant critters. |
| `WeatherChanged` | `{ WeatherId: string, EndsAtServerTime: number, TriggeredByPlayer: string? }` | Syncs skybox, ambient audio, and HUD timer across all clients. |
| `MeteorEvent` | `{ Action: "Spawn" \| "Cracked" \| "Despawn", MeteorUID: string, Tier: string, Position: Vector3 }` | Spawns/removes wild meteors in the central Crater. |
| `GlobalAnnouncement` | `{ Message: string, RarityColor: Color3, SoundId: string? }` | Broadcasts Mythic hatches, Supernova weather, and generous gifts. |

### Client-to-Server (`RemoteEvent:FireServer` / `RemoteFunction:InvokeServer`)
| Remote Name | Type | Arguments (Validated on Server) | Rate Limit |
| :--- | :---: | :--- | :---: |
| `RequestStartCrack` | `RemoteFunction` | `(MeteorUID: string)` $\rightarrow$ returns `{ Success: boolean, SeedTime: number }` | 3 calls / sec |
| `RequestFinishCrack` | `RemoteFunction` | `(MeteorUID: string, ClientDelta: number)` $\rightarrow$ returns `{ Zone: "Gold" \| "Green", RewardItem: ItemData }` | 3 calls / sec |
| `RequestPlotAction` | `RemoteEvent` | `(Action: "Plant" \| "Harvest" \| "PlaceCritter" \| "RemoveCritter" \| "CollectVault", SlotIndex: number, ItemUID: string?)` | 8 calls / sec |
| `RequestShopPurchase` | `RemoteFunction` | `(ShopType: "SupplyShip" \| "PlotUpgrade" \| "Rebirth", ItemId: string)` $\rightarrow$ returns `{ Success: boolean, Reason: string? }` | 4 calls / sec |
| `RequestSellItems` | `RemoteFunction` | `(Mode: "HeldItem" \| "AllUnlockedCrystals", ItemUID: string?)` $\rightarrow$ returns `{ CoinsEarned: number }` | 2 calls / sec |
| `RequestFuseCritters` | `RemoteFunction` | `(CritterUIDs: {string})` (must be array of 5 valid UIDs) | 1 call / sec |
| `RequestGiftItem` | `RemoteEvent` | `(TargetPlayer: Player, ItemUID: string)` | 1 call / 2 sec |
| `RequestLikePlot` | `RemoteEvent` | `(TargetPlotId: number)` | 1 call / 3 sec |

---

## 5. DataStore Schema & Offline Progression Math

### 5.1 Player Profile Schema (`DataService.luau`)
We use a clean, versioned schema (`SchemaVersion = 1`) backed by `DataStoreService` with **Session Locking** (preventing item duplication if a player rapidly hops servers) and a 60-second auto-save cycle plus `game:BindToClose` flush:

```luau
--!strict
export type MutationId = "Colossal" | "Wet" | "Solar" | "Frost" | "Shocked" | "Golden" | "Void" | "Prismatic"

export type InventoryItem = {
	UID: string,                   -- HttpService:GenerateGUID(false)
	Category: "Geode" | "Crystal" | "Pod" | "Critter",
	ItemId: string,                -- e.g., "StarSlime", "NebulaFox", "SunQuartz"
	WeightKg: number,              -- Rolled weight (e.g., 14.2)
	Mutations: { MutationId },     -- Array of applied mutations
	IsStarforged: boolean,         -- True if created via 5-to-1 Star-Fuser
	IsLocked: boolean,             -- Prevents accidental Bulk Sell / Fusion
	CreatedAt: number,
}

export type PlantedSlot = {
	SlotIndex: number,
	Category: "Geode" | "Pod",
	ItemId: string,
	WeightKg: number,
	Mutations: { MutationId },
	PlantedAt: number,             -- Unix timestamp (os.time())
	GrowthDuration: number,        -- Required seconds to mature
}

export type PlayerProfileData = {
	SchemaVersion: number,
	Coins: number,
	StarGems: number,
	Rebirths: number,
	LastSeenTimestamp: number,     -- Used for Offline Growth & Vault math
	TotalPlaytimeSeconds: number,
	LikesReceived: number,

	Inventory: { [string]: InventoryItem }, -- Keyed by UID (Max 150 base slots)
	PlantedBeds: { [number]: PlantedSlot }, -- Growing Crystal Geodes
	Incubators: { [number]: PlantedSlot },  -- Growing Critter Pods
	ActivePenCritters: { string },          -- Array of InventoryItem UIDs currently in Habitat Pen
	TrophyPedestalUID: string?,             -- Critter UID displayed at plot front gate

	UnlockedUpgrades: { [string]: number }, -- e.g., { SoilBeds = 2, PenSlots = 1, CollectorDrone = 1 }
	Bestiary: {
		[string]: {                         -- Keyed by ItemId
			DiscoveredCount: number,
			MaxWeightKg: number,
			MutationsFound: { [MutationId]: boolean },
		}
	},
	ShopPurchasesWindow: {
		WindowSeed: number,                 -- math.floor(os.time() / 300)
		Counts: { [string]: number },
	},
	GamePassesOwned: { [string]: boolean },
}
```

### 5.2 Server-Authoritative Offline Progression Calculation
When a player joins (`Players.PlayerAdded`) and their profile loads:
1. Compute `ElapsedOffline = math.clamp(os.time() - Data.LastSeenTimestamp, 0, MaxOfflineSeconds)` (where `MaxOfflineSeconds = 12 * 3600` by default).
2. **Plot Growth Advancement:** Because each `PlantedSlot` stores `PlantedAt` (a Unix timestamp), any Geode or Pod where `os.time() >= Slot.PlantedAt + Slot.GrowthDuration` is **already mature automatically** without needing a complex tick simulator!
3. **Offline Weather Mutation Roll:** For every full 15-minute block in `ElapsedOffline` (up to 48 blocks), the server runs a lightweight deterministic roll for unmatured slots to receive 1–2 weather mutations (*Wet*, *Solar*, or *Frost*), ensuring offline players wake up to mutated crops just like online players.
4. **Offline Critter Vault Earnings:**
   $$\text{OfflineCoins} = \text{ TotalPenCoinsPerSec} \times \text{ElapsedOffline} \times \text{OfflineEfficiencyRate}$$
   *(Where `OfflineEfficiencyRate` starts at `0.35` [35%] for starter ranches and scales to `0.75` [75%] once the player unlocks Collector Drones).*

---

## 6. Security & Exploit Prevention Checklist

Roblox simulators are frequent targets for client-side exploit scripts. Our architecture neutralizes common exploits by design:

| Exploit Vector | How Exploiters Attempt It | Our Server-Side Prevention |
| :--- | :--- | :--- |
| **Remote Spam / Auto-Crack Anywhere** | Firing `RequestStartCrack` & `RequestFinishCrack` for every meteor on the map from 500 studs away in 0.01 seconds. | 1. Server verifies `(PlayerCharacterRoot.Position - MeteorPosition).Magnitude <= 18` studs.<br>2. Server records `ServerStartTime = os.clock()` on `RequestStartCrack` and verifies `RequestFinishCrack` arrives within the exact valid timing window (`0.65s`–`0.95s` for Gold Zone). |
| **Negative Currency / NaN Injection** | Passing `-999999` or `0/0` (`NaN`) as a purchase count or item price. | Every remote argument undergoes strict `typeof()` validation, `arg == arg` (rejects `NaN`), and `math.floor(arg) > 0` checks. All prices are looked up exclusively from `Shared.Config` on the server. |
| **Item Duplication via Trading/Gifting** | Dropping/gifting an item and immediately leaving the server before `SetAsync` completes. | 1. Gifting mutates both players' in-memory server tables atomically in the same thread before yielding.<br>2. Session lock metadata prevents a new server from loading an outdated profile until the previous server releases the lock on `PlayerRemoving`. |
| **Plot Ownership Spoofing** | Firing `RequestPlotAction` for another player's `SlotIndex` or `ItemUID`. | `PlotService` resolves the caller's plot strictly via `PlotService:GetPlotByPlayer(player)`—the client cannot pass a `PlotId` parameter for mutations/harvests. |

---

## 7. Performance & Mobile Optimization Guidelines

1. **Client-Side Visual Culling & Animation Throttling:**
   - Hopping Critters in all 6 plots are animated by a single centralized `RunService.RenderStepped` loop in `PlotVisualController.luau`.
   - If a plot is more than **120 studs away** from `workspace.CurrentCamera`, its Critter hop updates throttle from 60 Hz down to **10 Hz**, and small particle emitters disable automatically.
2. **Part Count Budgets:**
   - Each Critter or Crystal model must use **$\le 12$ BaseParts/MeshParts** with `CastShadow = false` on small decorative attachments and `CanCollide = false`, `CanQuery = false`, `CanTouch = false` on all non-interactive visuals.
3. **Object Pooling for Coins & Meteors:**
   - Floating coin popups and crater meteors reuse a pre-allocated pool of 30 instances rather than calling `Instance.new()` / `:Destroy()` every second.
