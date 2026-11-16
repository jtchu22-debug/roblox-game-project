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
| **Stage 4–5 (Polish & Soft Launch)** | **ZERO or Fixed Cosmetics Only (Post-Review)** | Monetization can only activate *after* stability soak tests pass, privacy/policy checks are verified, and the Human Lead + Technical Director sign off. |

---

## 3. Approved Future Monetization Scope (Pure Cosmetics Only — Post-Stability)

If and when monetization is enabled after Stage 5 stability and compliance verification, every offering must satisfy **all four rules**:
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

---

## 5. Pay-to-Win (P2W) and Paid Convenience Benchmarks

These are reference models for a future monetization decision. The approved rollout in Sections 2–3 permits fixed-price cosmetics after stability and compliance review. A paid gameplay perk requires an explicit change to that decision.

| Mechanic | Roblox example | Starfall Ranch proposal and trade-off |
| :--- | :--- | :--- |
| **Boosted hatch luck** | *Pet Simulator 99* lists Ultra Lucky and Huge Hunter passes. [Pass listings](https://www.obbydesk.com/games/pet-simulator-99/passes) | **Defer.** A luck pass could tilt normal hatch odds toward Rare and Epic. Keep the Eclipse Dragon's Astral drop odds the same for every player so the Secret remains an earned chase. Any paid luck would require dynamic odds disclosure and per-user eligibility checks. |
| **Faster incubation** | *Bubble Gum Simulator INFINITY* lists Fast Hatch, which speeds up egg hatching. [Pass listing](https://www.rolimons.com/gamepass/1111985110) | **First gameplay perk to evaluate.** Test a modest, fixed reduction in incubation duration while keeping the same per-hatch drop weights. Compare hatches per hour and time to ranch upgrades. Faster incubation can still improve the chance of finding a rare critter in a session by allowing more attempts. |
| **Robux-only meteors or pets** | *Pet Simulator X* sold Exclusive Eggs with multiple possible pets. *Adopt Me!* listed its exact Rose Dragon for a fixed Robux price. [Exclusive Egg update](https://www.biggames.io/post/pet-simulator-x-secret-cat-update) · [Rose Dragon update](https://www.playadopt.me/news/valentines-heartbreak-notes) | **Prefer a direct cosmetic offer.** Preview an exact companion skin or meteor appearance and sell it for a fixed price with zero stat or reward changes. A Robux-only meteor that rolls a pet is a paid-random product. Keep the earnable collection complete through regular meteors. |
| **2× offline earnings** | *Trade Tower* listed a pass doubling offline earnings. [Pass listing](https://www.rolimons.com/gamepass/30527155) | **Defer.** Starfall Ranch plans offline incubation and zero offline Coins. This pass would require a new offline income system. If the team revisits it, model both free and paid caps and measure how much returning players can skip in the active loop. |
| **VIP** | *Adopt Me!* offers a VIP hangout. *Pet Simulator 99* lists VIP with both visual perks and economic rewards. [Uplift Games FAQ](https://upliftgames.zendesk.com/hc/en-us/articles/39204397059604-Adopt-Me-FAQ) · [Pass details](https://rblxdb.com/games/minigames-pet-simulator-99-3317771874) | **Best fit for the current plan.** A fixed-price Ranch VIP pass could bundle a themed ranch, a trail, and a previewable companion skin. A version that grants Coin multipliers, extra pens, or better meteor access would be a paid gameplay advantage. |

**Roblox paid-random rules.** A Robux purchase that grants a random outcome directly or indirectly, or improves the odds of an outcome, requires review under Roblox's paid-random policy. Disclose the outcomes and numerical odds before purchase where applicable, show the updated odds when modifiers are active, and apply per-player eligibility restrictions through `PolicyService`, including `ArePaidRandomItemsRestricted`. A fixed, previewable cosmetic uses a different purchase model. [Roblox paid-random guidelines](https://create.roblox.com/docs/production/monetization/paid-random-items) · [Promoting items to younger audiences](https://en.help.roblox.com/hc/en-us/articles/47965190783892-Promoting-Items-to-Younger-Audiences)

**Recommended order.** Start with cosmetic VIP and direct cosmetic sales after the existing stability review. If the team revisits paid progression, evaluate one perk at a time. Use the free baseline to compare first hatch, first upgrade, hatches per hour and Secret discovery before deciding whether to add a paid perk.
