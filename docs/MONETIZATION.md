# Ethical & Child-Safe Monetization Plan (Post-Audit Revision)

> **Last Updated:** November 15, 2026 (Revised per Phase 0 Technical Director Audit — `R-005`)  
> **Author:** Gemini (Primary Game Designer)  
> **Auditor:** ChatGPT (Independent Technical Director)  
> **Core Principle:** Let children enjoy the complete game without spending a single Robux. Monetization is **completely disabled in Stages 1–3** and, if introduced after product stability and compliance review, is limited strictly to **transparent, fixed-price cosmetics**.

---

## 1. Policy Corrections & Strict Guardrails (`R-005`)

Following our Phase 0 Technical Director audit and review of Roblox's [Paid Random Items Policy](https://create.roblox.com/docs/production/monetization/paid-random-items) and [Creator Rewards](https://create.roblox.com/docs/creator-rewards) documentation:

1. **Creator Rewards Replaced Engagement-Based Payouts (EBP):**  
   Roblox retired Engagement-Based Payouts and Creator Affiliate programs on **July 24, 2025**, replacing them with **Creator Rewards** (centered on **Daily Engagement** and **Audience Expansion** for qualifying experiences). We do **not** assume or promise passive Premium playtime payouts or guaranteed revenue.
2. **NO Indirect Paid Random Mechanics:**  
   Even if a shop item is deterministic, selling **convertible currency bundles** (`Starter Bundle: 2,500 Coins`) that buy randomized pods, or selling **luck/probability boosters** (`Weather Beacons` boosting random rarity rolls), constitutes or borders on indirect paid-random mechanics under Roblox policy. **All paid currency packs, paid luck boosts, and paid weather/mutation items are permanently removed.**
3. **NO Paid Gameplay Advantages:**  
   Extra Habitat Pen slots, faster movement hoverboards, 24h storage/vault boosts, and auto-crack drones create meaningful economic progression advantages over non-paying children. **All progression upgrades must be 100% earnable through gameplay only.**
4. **NO Social Spending Pressure or Dark Patterns:**  
   No server-wide chat/banner announcements celebrating who spent Robux, no pop-up purchase prompts during gameplay, no false scarcity countdowns, and no punishing streak losses.

---

## 2. Staged Monetization Rollout

| Stage | Monetization Status | Rationale |
| :--- | :---: | :--- |
| **Stages 1–2 (Prototype & Discovery Playtest)** | **ZERO Monetization** | Prove the core 5-minute Meteor Rescue & Ranch loop is genuinely fun on its own. |
| **Stage 3 (Persistence Alpha)** | **ZERO Monetization** | Focus 100% on DataStore stability, session locking, offline incubation, and exploit testing. |
| **Stages 4–5 (Private Polish & Testing)** | **ZERO Monetization** | Validate the game in private builds. Review proposed launch cosmetics after stability soak tests and Roblox policy checks. |
| **Stage 6 (First Public Release)** | **ZERO or Fixed Cosmetics Only (Post-Review)** | Activate only offerings signed off by the Human Lead and Technical Director after stability and compliance verification. |

---

## 3. Approved Future Monetization Scope (Pure Cosmetics Only — Post-Stability)

Any monetization enabled for the Stage 6 public release or later must satisfy **all four rules**:
- **Fixed, upfront Robux price** (no bundles masking unit cost, no escalating packs).
- **Zero gameplay stats, speed, income, luck, or slot advantages.**
- **100% deterministic preview** (the player sees the exact 3D decoration or trail before clicking buy).
- **Parent/child respectful:** No pop-ups; accessible only via an optional `[🎨 Cosmetics]` tab.

### Eligible Candidate Categories
1. **Ranch Visual Themes (GamePass):** Purely aesthetic fence, ground-tint, and ranch arch skins (e.g., *Pastel Candy Ranch*, *Starlight Observatory Trim*).
2. **Avatar Cosmetic Accessories / Trails (GamePass):** Purely visual cosmic star-dust trail or handheld lantern cosmetic (zero walkspeed or jump changes).

---

## 4. Technical Durability Contract for Future Purchases (`ProcessReceipt`)

While GamePasses use simple `MarketplaceService:UserOwnsGamePassAsync` ownership checks (retried gracefully on transient API errors), **if** any Developer Product were ever approved in the distant future, implementation must satisfy Roblox's [Player Data and Purchasing](https://create.roblox.com/docs/cloud-services/data-stores/player-data-purchasing) and [`MarketplaceService.ProcessReceipt`](https://create.roblox.com/docs/reference/engine/classes/MarketplaceService) standards:

1. **Strict Validation:** Verify `ProductId` exists in an allowlisted server-only table, verify `Player` is in the server, and verify `DataService:IsReady(player)` is `true` (if not loaded yet, return `Enum.ProductPurchaseDecision.NotProcessedYet` so Roblox safely retries).
2. **Atomic Durable Entitlement & Ledger:** Grant the entitlement **and** record the durable `PurchaseId` inside the **same `ProfileStore` profile mutation**, then flush/confirm persistence **before** returning `Enum.ProductPurchaseDecision.PurchaseGranted`.
3. **No Naive Eviction Ring Buffers:** A fixed ring buffer (e.g., last 20 receipts) can evict an older unprocessed receipt ID and accidentally grant an item twice if Roblox retries. Any receipt deduplication ledger must either use durable permanent keys for one-time entitlements or an explicit verified retention window backed by a separate receipt-store check—**never** claim "zero-loss guaranteed" without crash/disconnect verification tests.
