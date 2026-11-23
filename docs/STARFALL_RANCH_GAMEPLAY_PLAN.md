# Starfall Ranch gameplay and launch plan

## The pitch

**Chase falling stars, hatch what’s inside, and raise a ranch that helps you find the next rare critter.** A player starts with one free meteor and a simple decision about where to spend their Coins. A returning player can hunt a species, raise a favorite, work toward a tool or habitat, help at a public meteor fall, or pursue a heavyweight mutation. Every path runs through the same rescue, hatch, and ranch loop.

The signature feature is the connection between a player’s ranch and their next expedition. An assigned critter can highlight one meteor family on the Observatory scanner, and a Coin-funded lure can target a known family. What players keep on the ranch shapes what they can hunt. A bright sky streak, a clear landing marker, and a distinct crack interaction give them a reason to leave the ranch when something special lands.

## What to borrow from each reference

| Reference | Design lesson | Starfall Ranch version | Source |
| --- | --- | --- | --- |
| Pet Simulator 99 | A visible collection and gear progression make the next unlock easy to understand. | The Field Guide shows species, habitats, and clues. The workbench previews what each Cracker upgrade opens. | [Game](https://www.roblox.com/games/8737899170/Pet-Simulator-99) · [BIG Games area index](https://db.biggames.io/wiki/areas) |
| Bee Swarm Simulator | Quests give familiar actions new goals and guide players toward new areas. | Observatory contracts direct players to rescue different families, raise selected critters, or chart a new field. Rewards are Coins or visible progression unlocks. | [Game](https://www.roblox.com/games/1537690962/Bee-Swarm-Simulator) |
| Steal An Egg | A rescued collectible hatches into a visible source of income. Size and mutation keep duplicates interesting. | Claim wild meteors, hatch their pods, then place, feed, or sell critters. The pen and Field Guide show rarity, weight, mutation, and Coins per second. | [Game listing and description](https://www.rolimons.com/game/107778070777162) |
| Throw Food For Animals | The type of lure and the reach of your gear influence what you can find. | Spend earned Coins on a lure for a named meteor family and use a better Cracker to reach its harder deposits. | [Game description](https://op.gg/roblox/games/10766972131) |
| Fish It! | A short catch interaction can support a large collection chase. | Keep the first crack quick. Give rare hatches readable reveals and show which critters and records are still missing. | [Game](https://www.roblox.com/games/121864768012064/Fish-It) |
| Fisch | Exploration and a readable skill check make the hunt feel different by location. | Ember, Frost, and Astral fields have distinct crack patterns and drop pools. Show the field, tool, and conditions that help find a species. | [Game](https://www.roblox.com/games/16732694052/Fisch) |
| Grow a Garden | Returning to a growing plot creates a reason to check in, and unusual specimens are worth showing. | Pods finish incubating offline, pens accumulate capped offline Coins, and visitors can inspect a featured critter’s weight and mutation. | [Game](https://www.roblox.com/games/126884695634066/Grow-a-Garden) |
| Steal a Brainrot | A valuable spawn creates a social moment, and an income-producing collection makes progress visible. | Broadcast incoming meteor falls. Players can race to unclaimed wild meteors or cooperate on one large fall with individual rewards. Owned critters stay with their ranchers. | [Game](https://www.roblox.com/games/109983668079237/Steal-a-Brainrot) |
| Slime RNG | Rare reveals and world unlocks give collectors goals at different horizons. | Use a visible rarity ladder and a long-term Astral Secret chase. The rolls happen through expeditions and hatches. | [Game description and listing](https://www.rolimons.com/game/92416421522960) |

## The player’s first session and beyond

| When | What the player does | Reason to continue |
| --- | --- | --- |
| First 90 seconds | Follow the starter beacon, crack an Ember meteor, take the pod to the incubator, place the guaranteed Star-Slime, and see Coins start flowing. | The Crater shows the next meteor and the ranch shows two clear first purchases. |
| Minutes 2–5 | Choose between opening a second pen, saving for a better Cracker, or taking a short Observatory contract. Walk back to the Crater for a known target. | A displayed Frost reward, a visible tool unlock, or a named missing species gives the second rescue a purpose. |
| Minutes 5–15 | Reach a different pocket of the Crater, try its crack pattern, set a named lure, and decide whether to feed, sell, or display a new critter. | The next habitat or Astral tool stays visible after the initial pads are bought. |
| Later sessions | Expand the ranch, finish field contracts, assemble a wanted collection, change the scanner’s featured critter, visit ranches, and hunt Astral. | A specific next unlock, a collection gap, a weight record, a mutation, or the Secret Eclipse Dragon. |

Those times are tuning targets. Keep the starter interaction mobile-friendly, show the largest imminent reward or goal in the HUD, and put the rest of the choices on the ranch board and in the Field Guide.

## Systems that create choices

- **Meteor fields and cracking.** Build one connected map with the home Crater, Frost Ridge, and Astral Shelf. Reuse the existing meteor, claim, and hatch pipeline. Ember has the familiar quick crack, Frost exposes two fracture points in sequence, and Astral has a short pulse with a generous action window. Each gets a readable silhouette, icon, and sound or static cue. Good timing shortens the crack. A missed timing action still allows normal completion with the same reward pool. Provide touch, keyboard, gamepad, and reduced-motion inputs. Fields can support distinct families and overlapping drop pools.
- **Crackers and Observatory.** The starting tool handles Ember. The first Coin upgrade opens Frost. The second opens Astral after the appropriate ranch milestone. The workbench shows costs and access requirements before payment. Target 8–12 short Observatory contracts at launch across exploration, rescues, ranch upgrades and collection milestones. The Observatory uses one selected discovered critter to highlight its meteor family on the scanner. The scanner changes visibility, so its benefit is independent of drop odds and paid luck.
- **Feeding, lures, and ranch spending.** Launch with one currency and four uses for it. Permanent tools open new hunts, pens and incubators improve throughput, capped feeding makes a favorite critter more valuable, and a single-use lure targets a named meteor family. A lure makes the family predictable while its pod still uses the normal published pool. Preview price and family, and charge only when an eligible encounter can be assigned. Feeding grants a small bounded bonus, previewed on the critter card. Duplicates can be income upgrades, sellable stock, or personal records.
- **Public meteor falls.** Standard wild spawns reward the first eligible player to claim. A periodic large Astral fall announces its location and lets multiple players contribute to cracking it. The server grants at most one personal pod per qualified player per fall, with the same hatch and bag-capacity rules as other encounters. Keep a regular earnable Astral route available so the Secret chase works solo and around any schedule.
- **Collection and progression.** Use the [Stage 6 roster proposal](https://github.com/jtchu22-debug/roblox-game-project/pull/9) of **24 earnable species**. Common 5, Uncommon 5, Rare 4, Epic 4, Legendary 3, Mythic 2, and Secret 1. Keep Ember, Frost, and Astral as meteor families and the seven rarities on critters. A tier of gear changes which pools players can access. Species base income, weight, and one mutation make specimens meaningfully different. Keep feeding additive against base income, and tune with per-critter and ranch caps. The Field Guide records discovered species and best weight, so players can choose to sell a duplicate while keeping their record. Give every species a recognizable original Blender model and put one featured critter on display at each ranch.
- **Eclipse Dragon.** Show an Astral clue and silhouette early. Make the dragon earnable from standard Astral pods at the same per-pod Secret odds for eligible players at the same progression stage. Keep the Secret check outside paid luck and Premium Meteor pools. Hatch speed can affect attempts per hour, so include it in the release balance test. Lock outcomes server-side once per pod and preserve them across relog or purchase retries.

### Example session

A player has enough Coins for either a second pen or the Frost Cracker. They buy the tool after seeing a Nebula Fox clue in the Field Guide, crack a Frost meteor and hatch a Heavy fox. They keep it for income and assign it to highlight Frost signatures later. With more Coins they can feed the fox, buy a lure to hunt another Frost specimen, or save for the Astral tool. When a server announces an Astral fall, they see the next goal and what they need to join it.

## Ranch plots, central hub, and navigation

The owner’s two Anime Dice screenshots are a reference for open space, clear destinations, and readable plots. The first shows a generous main aisle between display areas. The second shows an open central plaza with shops and activities on its edges. Use Starfall Ranch’s cosmic ranch theme, original icons, and its own signs and map composition.

| Area | Starfall Ranch layout | Greybox acceptance check |
| --- | --- | --- |
| **Player ranches** | Give each of the six plots a broad, unobstructed path from its gate. Group incubators on one side and pens with places for future expansion on the other. Leave room around each station for two avatars to pass and for the mobile camera to turn. Keep the home route and income-generating critters visible from the gate. | Start around **76 × 68 studs** per plot and a **14–18 stud** central aisle. Adjust after walking the map at standard movement speed on desktop and touch. Walking straight through the plot should keep station prompts off the main aisle wherever possible. |
| **Central hub** | Build an open plaza around the **Observatory** as the main landmark. Put the Coin-funded **Tool Workbench**, **Frost Lure kiosk**, and **Contracts board** along its edges, with room for future traders or event stalls. Keep ranch incubators, pens, and selling nearby at home. Give each hub station a clear place to stand and one obvious interaction. | From each plot gate, players can see the Observatory or a sign pointing to it. From the plaza center, they can find the two meteor routes and the way home. Use current station logic and prices during the layout pass. Any move of a purchase prompt to the hub must preserve server ownership, distance, and purchase checks. |
| **Meteor grounds** | Lead from the open plaza into a wider Crater with signed paths to **Ember Basin**, **Frost Ridge**, and room for the planned **Astral Shelf**. Keep the shop plaza and the active landing areas visually separate. Reserve an open landing area with a clear approach so a player can spot and follow the Astral event from the hub. | Walk both opening routes without crossing a shop queue or hitting overlapping prompts. Check that an incoming meteor and its landing cue remain visible from an approach path, with a steady cue in Reduced Motion. |
| **HUD and navigation** | Use a small set of readable destination controls in Starfall’s illustrated style. **Hub** and **Ranch** guide players to their destinations. **Shop** opens the optional shop when it is available. Keep **Coins and income**, **Bag**, and the **Field Guide** easy to reach. Show the active world action only when relevant, with generous touch targets. | Keep the center of the screen open for the avatar and meteor cues. Verify 320px portrait and 667×375 landscape, including Bag, prompts, and both navigation destinations. Keep touch controls clear of Roblox’s built-in controls. |

A workable starting map has three ranches on each side of the shared plaza, Ember Basin to the south and Frost Ridge to the north. Connect the routes through the plaza and place the future Astral area beyond the Ridge if sightlines work. Treat these dimensions and positions as greybox starting points. Preserve the short starter route from ranch spawn to the guaranteed meteor and back.

**Stage 3** uses the roomier plot footprint and hub paths when the six-plot map is greyboxed. Represent hub destinations with signs or simple stalls and test the starter loop, plot assignment, routes, and prompt readability. **Stages 4–5** refine the visual design, mobile HUD, station interactions, and meteor-event visibility. **Stage 6** completes the Observatory contracts and scanner, the shared meteor experience, and the public shop described below.

## Hatch odds and Observatory leaderboards

Add this during Stage 6 alongside the expanded roster, before the public launch. The Observatory gets two global boards. The Field Guide and critter cards show the same odds and income labels so players can see what each board measures.

| Board | What counts |
| --- | --- |
| **Rarest Hatch** | Highest lifetime rarity among the player's eligible species-and-finish hatches. Show the critter, its finish, meteor pool, and `1 in N` hatch odds. Keep the record if the critter is sold. Use standard earnable pod rolls at published, unboosted odds. Exclude premium, boosted-odds, granted, and legacy critters without a verifiable roll record. |
| **Ranch Coins/s** | Combined steady Coins per second from the player's currently placed critters, including weight, mutation, and feeding. A player's latest saved lineup stands while offline. Update after a lineup or income change and publish on a bounded refresh interval. Exclude one-time rewards and offline payouts. |

### Rarity and finishes

- Each standard meteor pool publishes a species probability as `1 in N` (label rounded display values as approximate). Keep Common through Secret as readable species tiers. A species available from multiple pools shows its odds by pool in the Field Guide, and each eligible hatch is ranked using the pool it actually came from.
- Roll one finish after the species. Start tuning at **89% Standard, 10% Gold, and 1% Rainbow**. Gold is one-tenth as likely as the species by itself, and Rainbow is one-hundredth as likely. A species with **1 in 500** pool odds is **about 1 in 562 Standard**, **1 in 5,000 Gold**, and **1 in 50,000 Rainbow**. These are proposed tuning values. Gold and Rainbow are collectible finishes with no direct Coins/s bonus in this baseline.
- The server determines the record using the unrounded joint probability of the species and finish. Save the original odds and pool revision so future balancing changes leave existing records intact. Display the leading record on the board and keep numerical ordering independent of display rounding.

### Weight, size, and mutations

- Use **1.0 kg = 1.0× base income**. Each **0.1 kg** adds or subtracts **10 percentage points** from that multiplier. Start testing with **0.8–1.5 kg** in 0.1 kg steps. At a base rate of **100 Coins/s**, a **0.8 kg** critter earns **80**, a **1.2 kg** critter earns **120**, and a **1.5 kg** critter earns **150** before other bonuses. Let displayed size follow weight within the pen and device performance budgets, with no separate size bonus.
- A hatch can independently roll one rare mutation. Also test an earnable natural mutation path through ranch play after hatching. Use Radiant as the starting mutation and preserve the existing Radiant appearance and earned value in migration. Mutation raises Coins/s and has no effect on the Rarest Hatch record. Balance mutation and weight together against ranch income caps and show the final rate on the card.
- Settle accrual at the old rate before a placement, feed, or mutation changes it. Reuse the server economy rate for pens, offline settlement, cards, and the Coins/s board. Freeze the species, finish, weight, and initial mutation outcome once per pod and persist it across rejoin and retry. Existing critters default to 1.0 kg and Standard finish while preserving existing progression. Keep the opening loop accessible before introducing the boards or income modifiers to new players.
- Before public launch, verify the pool and finish math, rate bounds, legacy saves, rejoin and duplicate-reward handling, and both boards across servers. Check that selling a record critter preserves the rarity entry, while moving a producer out of a pen lowers the income entry. Verify that changing weight or mutation leaves the rarity entry intact.

## Day-one shop and economy

Ship the verified shop alongside the full launch build. The launch lineup from [PR #9](https://github.com/jtchu22-debug/roblox-game-project/pull/9) includes gameplay passes for faster incubation, 2× capped offline Coins, Ranch VIP with extra bag room, and eligible non-Secret paid luck. Include Instant Hatch credits, a guaranteed Robux companion, cosmetics, and an eligible Premium Meteor product. Keep the advertised searchable Field Guide focused on the 24 earnable critters. Put exclusive shop companions in a separate guide category.

Keep hunt-lure Coins earnable through play. Price exclusive guaranteed pets inside the earnable income range and test the combined effects of all paid perks on the strongest allowed ranch. Show the exact benefit of fixed perks. Premium Meteors and paid odds modifiers require per-player eligibility and all applicable numerical outcomes before purchase, with effective odds updated when a boost is active. Keep deterministic offers and regular play available to players restricted from paid RNG. [Roblox paid random items policy](https://create.roblox.com/docs/production/monetization/paid-random-items)

## Build order and sign-off

| Milestone | Deliverable | Exit check |
| --- | --- | --- |
| **Stage 2B — Expanded playable loop** | Stay on MockStore. Use the existing Crater with two distinct paths, two purchasable Cracker tiers, a distinct Astral arrival and crack, one named Frost lure, one capped feeding upgrade, and 2–3 new critters for 5–6 total. Show one follow-up goal after the first ranch pads. | Play through roughly 10–15 minutes of purposeful progression before inviting live testers. Run 3–5 new uncoached testers and log anonymous outcomes. |
| **Stage 3 — Persistence and multiplayer** | Persist the tool, ranch, critter and collection state. Support offline hatching, migrate old/default state, and verify larger servers. | Rejoin, overlapping sessions, server failures, inventory capacity and meteor claim cleanup behave consistently. |
| **Stages 4–5 — Art pipeline and private baseline** | Validate a Blender import end to end, build representative assets and the Field Guide, and test field readability, input and multiplayer performance. Prototype one public fall on a private server. | Clean mobile and desktop runs, working accessibility, and stable claims and per-player rewards. |
| **Stage 6 — Content-complete private candidate, then public launch** | Ship-ready 24-species roster, three exploration fields, Field Guide and records, Observatory contracts and scanner, Rarest Hatch and Ranch Coins/s leaderboards, collectible finishes, weight and mutations, public meteor falls, tool and ranch progression, feeding, lures, capped offline Coins, and the day-one shop. | Privately verify the whole build, including all species’ earnable paths, leaderboard odds and cross-server updates, mobile play, save and offline recovery, late-game balance, and real purchase delivery and eligibility. Open publicly with those systems complete. |

### Stage 2B decision

Preserve the existing R-009 benchmarks. Record first reward against a 45-second median, hatch and pen against 80% within 90 seconds, and voluntary repeat rescue against 70% within five minutes. Report actual counts and elapsed times. Over the rest of the session, record whether players voluntarily chase the special meteor, choose between spending paths, and name their next goal without coaching. Watch whether they initiate that next action when time permits.

Advance if the opening remains legible and most testers show a reason to hunt or spend after the original upgrades. If players reach the new encounter and still describe the hunt as interchangeable, revisit the pivot decision before completing the roster. [Round 1 observations](./S2_01_PLAYTEST_KIT.md#5-recorded-stage-2-playtest-summary--round-1-v021-s2-playtest-live-2026-11-18) · [Review #012](./AGENT_REVIEWS.md#review-012--stage-2-round-1-decision)

### Implementation notes for Gemini

Keep players’ Coins, unlocks, lure entitlements, claims, drops and payouts under server authority. Reuse the current economy writer for spending, and use the shared configs to define fields, encounter rules, species and progression costs. Keep join/retry behavior consistent for the same reward. Settle offline earnings from saved pen rates and a server timestamp with a durable checkpoint. Deliver developer products through durable, idempotent receipts and verify player eligibility when offering and redeeming paid random items.

Keep the broad live-service ideas, such as additional maps, global trading, and reset-based rebirth, in the post-launch backlog. Launch depth comes from the expedition choices, ranch investment, collection chase and social falls above.
