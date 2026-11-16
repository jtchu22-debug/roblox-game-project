# Ethical & Child-Safe Monetization Strategy

> **Last Updated:** November 15, 2026  
> **Author:** Gemini (Primary Game Designer & Research Lead)  
> **Reviewer:** ChatGPT (Independent Technical Director)  
> **Core Principle:** *"Respect the Player, Reward the Server."* Every purchase in *Starfall Ranch* must be 100% transparent, non-predatory, age-appropriate for children (8–14), and compliant with global Roblox policies (UK/EU/AU/US children's privacy & anti-gambling regulations).

---

## 1. Strict Ethical Guardrails (What We Will NEVER Do)

In our market research (`MARKET_RESEARCH.md`), we observed that heavily criticized simulators (*Pets GO*, *Pet Simulator 99*) rely on high-friction dark patterns that hurt brand trust and risk regulatory enforcement. We explicitly forbid the following in *Starfall Ranch*:

1. **NO Paid Random Loot Boxes / Paid Gacha Eggs:** Players can **never** spend Robux on a random roll, mystery egg, or blind box. All Geodes and Star-Pods are earned through gameplay or bought with free in-game Starlight Coins.
2. **NO "Forever Packs" or Escalating Hidden Price Chains:** We will never hide a high-cost item behind a chain of escalating Robux purchases. Every item shows its exact, final price and contents upfront.
3. **NO Screen-Blocking Pop-up Prompts:** We will never trigger `MarketplaceService:PromptPurchase` unexpectedly while a player is walking or clicking in the middle of gameplay (which tricks kids on mobile into accidental clicks). Prompts only open when the player intentionally taps a clearly labeled `[🛒 Shop]` button.
4. **NO Paywalls on Core Content:** Every single Critter species, Crystal type, Mutation, Bestiary milestone, and Rebirth tier is 100% achievable by a Free-to-Play (F2P) player.

---

## 2. Permanent GamePasses (Convenience, Storage & Customization)

GamePasses are one-time purchases priced in the impulse-friendly **79 to 399 Robux** range for younger players:

| GamePass Name | Price (Robux) | Exact Benefit Provided | Why It Is Fair & Desirable |
| :--- | :---: | :--- | :--- |
| **Auto-Crack Helper Drone** | **149 R$** | Spawns a personal Mini-Drone that follows you in the Crater and automatically hits a standard Green Crack on nearby wild meteors. *(Note: F2P players also unlock a plot-bound Auto-Crack Turret at Rebirth 3).* | Saves thumb fatigue for relaxed players, while active F2P players who hit the manual Gold Critical zone still get higher (`1.35x`) weight rolls! |
| **Extra Ranch Habitat (+3 Critter Slots)** | **249 R$** | Increases your active Critter Pen capacity by `+3 slots` (e.g., from 4 $\rightarrow$ 7 at start, scaling to 13 at max Rebirth). | Lets collectors see more of their favorite mutated critters hopping around their ranch at once. |
| **Deep Vault & Backpack (2x Storage)** | **99 R$** | Doubles Inventory capacity (`150` $\rightarrow$ `300` items) and increases the Offline Drone Vault cap from `12 hours` $\rightarrow$ `24 hours`. | Pure quality-of-life convenience for completionists who hoard every mutation variant. |
| **Starlight Hoverboard & VIP Trail** | **79 R$** | Grants a toggleable sci-fi Hoverboard (`+25%` movement speed between Plaza and Crater) plus a cosmic star trail and gold `[⭐ VIP]` chat tag. | Affordable cosmetic/mobility pass that looks cool in the central hub without breaking economy math. |
| **Cosmic Architect Pack (Cosmetic Themes)** | **199 R$** | Unlocks 3 customizable visual themes for your Ranch fences, soil beds, and arch (*Candy Nebula*, *Cyber Neon*, *Crystal Palace*). | 100% cosmetic self-expression inspired by *Restaurant Tycoon 3* and *Brookhaven*. |

---

## 3. Repeatable Developer Products (Communal & Time-Saver Boosts)

The highest-converting, highest-goodwill Developer Products in 2025–2026 hits (*Fisch*'s Aurora Totems, *Grow a Garden*'s Weather/Sprinkler boosts) are **Communal Server Boosts**—where one player's small purchase benefits **all 6 players in the server** and celebrates the buyer as a hero!

| Developer Product | Price (Robux) | Exact Benefit Provided | Social & Retention Impact |
| :--- | :---: | :--- | :--- |
| **Summon Cosmic Weather Beacon** | **49 R$** | Immediately triggers a 3-minute **Solar Flare**, **Frost Nebula**, or **Ion Storm** across the entire server, with a banner: `🌟 [BuyerName] activated an Ion Storm Beacon for the whole server!` | Creates massive server gratitude (`"TYSM!!"`) in chat, zero P2W resentment, and high repeat purchases during party play. |
| **Supernova Eclipse Beacon (Server Event)** | **149 R$** | Summons the ultra-vibrant 3-minute **Supernova Eclipse** (`3x` server-wide Prismatic & Void mutation odds) + drops 3 bonus Mythic Meteors in the Crater for everyone. | High-spectacle social event that content creators and friend groups love triggering together. |
| **Instant Orbital Growth Surge (Personal)** | **29 R$** | Instantly advances all currently planted Geodes and Incubating Pods on the buyer's plot by **60 minutes** of growth time. | Transparent, low-cost time-saver for impatient players who just planted a slow-growing Epic pod. |
| **Starter Rancher Bundle (One-Time Limit)** | **49 R$** | Grants `2,500 Starlight Coins`, `1x Guaranteed Golden Star-Slime`, and `2x Solar Sprinklers` (Strictly limited to 1 purchase per account). | High-value entry point for converting first-time spenders (improves the algorithm's *Spend Days* signal). |

---

## 4. Roblox Engagement-Based Payouts (Premium & Playtime Revenue)

A substantial share of Roblox developer revenue comes passively from **Roblox Engagement-Based Payouts** (rewarding games based on the share of time spent by Roblox Premium subscribers and verified active users).

Our core design naturally maximizes Engagement Payouts without requiring scummy traps:
1. **Synchronized 5-Minute Supply Ship & 6-Minute Weather Cycles:** Encourages natural 20–35 minute play sessions.
2. **Co-Op Mega-Geode Every 15 Minutes:** Keeps friends in the server together.
3. **Calm, Cozy Ranch Management:** Players genuinely enjoy hanging out on their customized floating ranch showing off giant critters and chatting with friends.

---

## 5. Technical Safeguards for Purchases (`MonetizationService.luau`)

To guarantee zero lost Robux for players:
- `MarketplaceService.ProcessReceipt` will **never** return `Enum.ProductPurchaseDecision.PurchaseGranted` until the player's profile is loaded and the `PurchaseId` is written into a ring-buffer array (`Data.ProcessedReceipts`) inside their DataStore profile.
- If a server crashes mid-purchase before saving, Roblox automatically re-invokes `ProcessReceipt` on the next server join, ensuring 100% reliable fulfillment.
