# Starfall Ranch Monetization Plan

> **Last Updated:** November 15, 2026 (Stage 6 launch revision)  
> **Author:** Gemini (Primary Game Designer)  
> **Auditor:** ChatGPT (Independent Technical Director)  
> **Core Principle:** Ship the full earnable collection and an optional shop with paid gameplay advantages, consumable purchases, and cosmetics at the first public release.

---

## 1. Launch Shop Guardrails

- Keep all 12 core critters, the Eclipse Dragon, and the standard ranch upgrades earnable through gameplay. Preview deterministic products and their exact benefits, duration, and Robux price in the optional shop.
- Treat Premium Meteors and paid luck as paid randomness. For eligible users, show every final outcome and its numerical odds before purchase, and show updated odds while a modifier is active. Use `PolicyService:GetPolicyInfoForPlayerAsync()` and `ArePaidRandomItemsRestricted` to restrict paid-random access per player. Keep the earnable game and fixed eligible offers accessible. [Roblox paid-random items guidelines](https://create.roblox.com/docs/production/monetization/paid-random-items)
- Preserve the earned Eclipse Dragon chase. Use one base Secret check when a normal Astral pod's species is selected, then apply paid luck only to the remaining non-Secret outcomes. Premium Meteors exclude the Eclipse Dragon. Faster incubation can increase attempts per hour.
- Keep purchases opt-in through the shop. Avoid unsolicited prompts, false scarcity, penalizing streaks, and announcements celebrating spending. [Roblox guidance on younger audiences](https://en.help.roblox.com/hc/en-us/articles/47965190783892-Promoting-Items-to-Younger-Audiences)
- Treat Creator Rewards as a separate program. [Creator Rewards](https://create.roblox.com/docs/creator-rewards)

---

## 2. Staged Monetization Rollout

| Stage | Monetization | Release requirement |
| :--- | :--- | :--- |
| **Stages 1–5** | No public sales | Build and verify the free baseline in Studio or invite-only builds. |
| **Stage 6 private release candidate** | Complete shop and test purchases | Configure passes and products, tune prices and progression, and verify entitlements, receipts, offline payouts, and per-player eligibility. |
| **Stage 6 first public release** | Gameplay passes, Developer Products, and cosmetics on day one | Open the content-complete build and its verified shop together. Complete purchase and policy checks in private testing. |

---

## 3. Day-One Game Passes and Purchases

Use one-time Roblox passes for permanent entitlements and Developer Products for repeatable purchases. [Passes](https://create.roblox.com/docs/production/monetization/passes) · [Developer Products](https://create.roblox.com/docs/production/monetization/developer-products)

| Offer | Type | Launch design | Roblox reference |
| :--- | :--- | :--- | :--- |
| **Lucky Hatch** | Pass | Permanently improve non-Secret drop odds in regular meteor pools. Show the effective odds to the player. | [Pet Simulator 99 passes](https://www.obbydesk.com/games/pet-simulator-99/passes) |
| **Fast Incubation** | Pass | Shorten incubation by a fixed percentage for newly planted pods. Preserve the per-pod drop odds. | [Bubble Gum Simulator INFINITY Fast Hatch](https://www.rolimons.com/gamepass/1111985110) |
| **2× Offline Coins** | Pass | Double the capped offline Coin payout available to all players. Use the same time cap for both groups and enforce an absolute payout cap. Offline incubation remains available to everyone. | [Trade Tower pass](https://www.rolimons.com/gamepass/30527155) |
| **Ranch VIP** | Pass | Bundle a ranch theme, trail, and visible gameplay benefit. Use two additional bag slots as the starting balance proposal and apply the resulting cap to bag reservations and the HUD. | [Adopt Me! VIP](https://upliftgames.zendesk.com/hc/en-us/articles/39204397059604-Adopt-Me-FAQ) · [Pet Simulator 99 VIP](https://rblxdb.com/games/minigames-pet-simulator-99-3317771874) |
| **Premium Meteor** | Developer Product | Grant an eligible buyer one Premium Meteor reward roll from a disclosed, server-owned pool. Put bonus critters outside the 12-species earnable checklist when an outcome is shop-exclusive. | [Pet Simulator X Exclusive Egg](https://www.biggames.io/post/pet-simulator-x-secret-cat-update) |
| **Instant Hatch** | Developer Product | Grant one stored incubation completion credit. Redeem it on a player-owned incubating pod to finish its timer. Keep the credit if the pod is unavailable or capacity blocks completion, and use the normal hatch validation. | [Bubble Gum Simulator INFINITY Fast Hatch](https://www.rolimons.com/gamepass/1111985110) |
| **Guaranteed Shop Companion** | Pass for a one-time unlock | Sell an exact, previewable companion with a stated income rate. Keep it outside the core collection checklist, with stats within the earnable range. | [Adopt Me! Rose Dragon](https://www.playadopt.me/news/valentines-heartbreak-notes) |
| **Fixed-price cosmetics** | Pass for a one-time unlock | Offer previewable ranch themes, trails, and accessories with their exact appearance shown before buying. | [Adopt Me! premium items and VIP](https://upliftgames.zendesk.com/hc/en-us/articles/39204397059604-Adopt-Me-FAQ) |

Set Robux prices, odds, incubation reductions, and offline caps against the private release candidate. Compare first hatch, first upgrade, hatches per hour, and return-session economy between the free baseline and paid offers. Check combined perks and keep currency payouts bounded.

---

## 4. Purchase Delivery and Receipt Durability (`ProcessReceipt`)

Resolve Game Pass ownership on the server with `MarketplaceService:UserOwnsGamePassAsync` and handle transient lookup errors. Stage 6 Developer Products must satisfy Roblox's [Player Data and Purchasing](https://create.roblox.com/docs/cloud-services/data-stores/player-data-purchasing) and [`MarketplaceService.ProcessReceipt`](https://create.roblox.com/docs/reference/engine/classes/MarketplaceService) standards:

1. **Strict Validation:** Verify `ProductId` exists in an allowlisted server-only table, verify `Player` is in the server, and verify `DataService:IsReady(player)` is `true` (if not loaded yet, return `Enum.ProductPurchaseDecision.NotProcessedYet` so Roblox safely retries).
2. **Atomic Durable Entitlement & Ledger:** Grant the entitlement **and** record the durable `PurchaseId` inside the **same `ProfileStore` profile mutation**, then flush/confirm persistence **before** returning `Enum.ProductPurchaseDecision.PurchaseGranted`.
3. **No Naive Eviction Ring Buffers:** A fixed ring buffer (e.g., last 20 receipts) can evict an older unprocessed receipt ID and accidentally grant an item twice if Roblox retries. Any receipt deduplication ledger must either use durable permanent keys for one-time entitlements or an explicit verified retention window backed by a separate receipt-store check—**never** claim "zero-loss guaranteed" without crash/disconnect verification tests.

4. **Durable delivery at capacity:** Persist paid items or credits before acknowledging a receipt. Deliver them through a stored entitlement when the bag or target is unavailable. Verify replay, disconnect, rejoin, save failure, and capacity cases before going live.
5. **Offline settlement:** Use the saved pen rate and a trusted server timestamp to calculate capped offline earnings. Commit the credited Coins and the interval checkpoint together before exposing the balance. Test rejoin, cap boundaries, and duplicate settlement.
