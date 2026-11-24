# Starfall Ranch gameplay and launch plan

## The pitch

**Chase falling stars, hatch what’s inside, and raise a ranch that helps you find the next rare critter.** A player starts with one free meteor and a simple decision about where to spend their Coins. A returning player can hunt a species, raise a favorite, work toward a tool or habitat, help at a public meteor fall, send a critter squad on an expedition, or pursue a heavyweight mutation. A stronger ranch earns Coins faster. Spend those Coins on gear that improves hatch odds, speeds up field travel, or helps critters win tougher expeditions. The next upgrade and the next hunt give each other a purpose.

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
| First 90 seconds | Follow the starter beacon, crack an Ember meteor, take the pod to the incubator, place the guaranteed Star-Slime, and see Coins start flowing. | The Crater shows the next meteor and the ranch shows two clear first purchases. Future sessions resume from the saved starter completion and inventory. |
| Minutes 2–5 | Choose between opening a second pen, saving for a better Cracker, or taking a short Observatory contract. Walk back to the Crater for a known target. | A displayed Frost reward, a visible tool unlock, or a named missing species gives the second rescue a purpose. |
| Minutes 5–15 | Reach a different pocket of the Crater, try its crack pattern, set a named lure, and decide whether to feed, sell, or display a new critter. | The next habitat or Astral tool stays visible after the initial pads are bought. |
| Later sessions | Expand the ranch, finish field contracts, assemble a wanted collection, change the scanner’s featured critter, visit ranches, and hunt Astral. | A specific next unlock, a collection gap, a weight record, a mutation, or the Secret Eclipse Dragon. |

Those times are tuning targets. Keep the starter interaction mobile-friendly, show the largest imminent reward or goal in the HUD, and put the rest of the choices on the ranch board and in the Field Guide.

## Systems that create choices

- **Meteor fields and cracking.** Build one connected map with the home Crater, Frost Ridge, and Astral Shelf. Use five meteor families across those fields. Reuse the existing claim, crack, and hatch pipeline, with readable effects and crack timing patterns for each family. Good timing shortens the crack. A missed timing action still allows normal completion with the same reward pool. Provide touch, keyboard, gamepad, and reduced-motion inputs.
- **Crackers and Observatory.** The starting tool handles Ember. The first Coin upgrade opens Frost and Verdant. The second opens Storm and Astral after the appropriate ranch milestone. Show costs, access requirements, and tool models at the workbench. The equipped Cracker's model is visible during the crack. [Tool art brief](./ART_DIRECTION.md#launch-tool-models) Target 8–12 short Observatory contracts at launch across exploration, rescues, ranch upgrades, and collection. The Observatory uses one selected discovered critter to highlight its meteor family on the scanner. The scanner changes visibility, leaving hatch odds intact.
- **Feeding, lures, and ranch spending.** Keep one Coin currency. Permanent tool tiers, habitat pens, bag space, and incubators give players visible progression goals. Capped feeding raises a favorite critter's income. Named lures and optional potion brewing provide repeatable purchases. A lure makes the meteor family predictable while its pod keeps that family's published pool. Preview the price and family, and charge when the server can assign an eligible encounter. Duplicates can be income upgrades, sellable stock, or personal records.
- **Public meteor falls.** Standard wild spawns reward the first eligible player to claim. A periodic large Astral fall announces its location and lets multiple players contribute to cracking it. The server grants at most one personal pod per qualified player per fall, with the same hatch and bag-capacity rules as other encounters. Keep a regular earnable Astral route available so the Secret chase works solo and around any schedule.
- **Collection and progression.** Target **108 distinct earnable species** for public launch, with the roster split below. Gear tiers open access to new pools. Species base income, weight, and one mutation make specimens meaningfully different. Keep feeding additive against base income, and tune with per-critter and ranch caps. The Field Guide records discovered species and best weight. The Critter Index in the Observatory shows collection progress and pays one-time rewards. Players can sell duplicates while keeping their records. Each ranch has one featured display.
- **Eclipse Dragon.** Show an Astral clue and silhouette early. Keep the dragon and its finishes in the standard earnable Astral pool with fixed per-pod odds. Exclude Eclipse Dragon from paid luck and Premium Meteor pools. Hatch speed can affect attempts per hour, so include it in the release balance test. Lock outcomes server-side once per pod and preserve them across relog or purchase retries.

### Example session

A player has enough Coins for either a second pen or the Frost Cracker. They buy the tool after seeing a Nebula Fox clue in the Field Guide, crack a Frost meteor and hatch a Heavy fox. They keep it for income and assign it to highlight Frost signatures later. With more Coins they can feed the fox, buy a lure to hunt another Frost specimen, or save for the Astral tool. When a server announces an Astral fall, they see the next goal and what they need to join it.

## Ranch plots, central hub, and navigation

The launch setting is **Starfall Valley**, a bright cosmic ranch valley with a copper-domed Observatory, terraced ranches, and a signed trail from the Ember Basin to Frost Ridge and Astral Shelf. See the [world art brief and concept image](./WORLD_ART_DIRECTION.md) for the terrain, sky, landmarks, and first environment slice.

The owner’s two Anime Dice screenshots are a reference for open space, clear destinations, and readable plots. The first shows a generous main aisle between display areas. The second shows an open central plaza with shops and activities on its edges. Use Starfall Ranch’s cosmic ranch theme, original icons, and its own signs and map composition.

| Area | Starfall Ranch layout | Greybox acceptance check |
| --- | --- | --- |
| **Player ranches** | Give each of the six plots a broad, unobstructed path from its gate. Group incubators on one side and pens with places for future expansion on the other. Leave room around each station for two avatars to pass and for the mobile camera to turn. Keep the home route and income-generating critters visible from the gate. | Start around **76 × 68 studs** per plot and a **14–18 stud** central aisle. Adjust after walking the map at standard movement speed on desktop and touch. Walking straight through the plot should keep station prompts off the main aisle wherever possible. |
| **Central hub** | Build an open plaza around the **Observatory** as the main landmark. Put the Coin-funded **Tool Workbench**, **Frost Lure kiosk**, and **Contracts board** along its edges. Put the **Critter Index** inside the Observatory near its entrance, clear of the main walkway and vendor queues. Keep ranch incubators, pens, and selling nearby at home. Give each hub station a clear place to stand and one obvious interaction. | From each plot gate, players can see the Observatory or a sign pointing to it. From the plaza center, they can find the two meteor routes and the way home. Use current station logic and prices during the layout pass. Any move of a purchase prompt to the hub must preserve server ownership, distance, and purchase checks. |
| **Meteor grounds** | Lead from the open plaza into a wider Crater with signed paths to **Ember Basin**, **Frost Ridge**, and room for the planned **Astral Shelf**. Keep the shop plaza and the active landing areas visually separate. Reserve an open landing area with a clear approach so a player can spot and follow the Astral event from the hub. | Walk both opening routes without crossing a shop queue or hitting overlapping prompts. Check that an incoming meteor and its landing cue remain visible from an approach path, with a steady cue in Reduced Motion. |
| **HUD and navigation** | Use a small set of readable destination controls in Starfall’s illustrated style. **Hub** and **Ranch** guide players to their destinations. **Shop** opens the optional shop when it is available. Keep **Coins and income**, **Bag**, and the **Field Guide** easy to reach. Show the active world action only when relevant, with generous touch targets. | Keep the center of the screen open for the avatar and meteor cues. Verify 320px portrait and 667×375 landscape, including Bag, prompts, and both navigation destinations. Keep touch controls clear of Roblox’s built-in controls. |

A workable starting map has three ranches on each side of the shared plaza, Ember Basin to the south and Frost Ridge to the north. Connect the routes through the plaza and place the future Astral area beyond the Ridge if sightlines work. Treat these dimensions and positions as greybox starting points. Preserve the short starter route from ranch spawn to the guaranteed meteor and back.

**Stage 3** uses the roomier plot footprint and hub paths when the six-plot map is greyboxed. Represent hub destinations with signs or simple stalls and test the starter loop, plot assignment, routes, and prompt readability. **Stages 4–5** refine the visual design, mobile HUD, station interactions, and meteor-event visibility. **Stage 6** completes the Observatory contracts and scanner, the shared meteor experience, the [ranch and hub station models](./ART_DIRECTION.md#launch-station-models), and the public shop described below.

## Launch roster and rarity tiers

Stage 6 targets **108 distinct earnable species** across five meteor families and three fields. The [launch roster](./CRITTER_ROSTER.md) contains every name, stable ID, primary meteor, and art cue. Its first 24 species form the private production batch. Complete the full roster before public launch.

| Species tier | Launch target |
| --- | ---: |
| Common | 24 |
| Uncommon | 22 |
| Rare | 20 |
| Epic | 16 |
| Legendary | 12 |
| Mythic | 8 |
| Secret | 6 |
| **Total** | **108** |

**Secret** is the highest species tier. **Astral** is a meteor family and field that can yield multiple tiers. Gold, Rainbow, mutations, and weight variations belong to existing species. Shop-exclusive companions sit outside the earnable roster.

Reuse rigs, materials, and model components where practical. Give each species a recognizable name, silhouette or identifying feature, and a Field Guide card with its source and odds. Validate the first batch from model import through hatch, pen, save, and mobile display before producing the remaining batches. Give each family some exclusive species and overlap the lower tiers. Spread hunts across the fields so stronger tools open new collection goals while earlier areas still have targets worth returning for.

## Critter Index

Build a signed **Critter Index** exhibit inside the Observatory. Show **Found X / 108**, a separate **Core collection X / 102**, five meteor family tabs, discovered cards, undiscovered silhouettes, the next reward, and a clear claim button. Give each card a primary family, all eligible meteor pools, tier, base odds, and personal best weight. Use lightweight thumbnails and load the active page on demand on mobile. The existing portable Field Guide opens the same discovery records for checking what to hunt. Collect milestone rewards at the exhibit.

Count each species once when the server confirms the player's first hatch through an earnable route. Any finish qualifies. Mutations, duplicates, and weight records live on the species card. Selling a critter preserves the discovery. Shop exclusives can appear in the separate shop collection. They sit outside the 108-species count. A hatch through an earned luck potion can count toward the Index while retaining its existing rarity leaderboard rules.

### Collection rewards

Pet Simulator 99 rewards discoveries with redeemable collection tokens. Pet Catchers uses discovery counts for currency and elixirs. Bubble Gum Simulator INFINITY rewards completed egg collections with items and has separate completion rewards. Starfall Ranch combines visible species milestones with family checklists and direct grants through its existing potions, lures, and cosmetics. [BIG Games update notes](https://www.biggames.io/post/pet-simulator-99-update-5) · [Pet Catchers Index](https://petcatchers.fandom.com/wiki/Index) · [Bubble Gum Simulator INFINITY Index](https://bgs-infinity.fandom.com/wiki/Index)

| Discovery milestone | One-time reward |
| --- | --- |
| 6 species | 1 Coin Boost Potion |
| 18 species | 2 Ember Lures |
| 36 species | 2 Field Luck Potions and 2 Coin Boost Potions |
| 60 species | **Ranch Naturalist** display title |
| 90 species | **Constellation** ranch display pedestal skin |
| All 102 Common through Mythic species | **Star Atlas** ranch trophy |
| All 108 species | **Starfall Archivist** display title and an Index completion seal |

Complete all Common through Mythic species on a family page to claim one lure for that meteor family. File each species under its primary family so overlapping pools cannot advance two pages with the same critter. The top gameplay milestone and the family rewards avoid Secret requirements. Full completion is cosmetic and counts any Eclipse Dragon finish, including Standard. Rewards grant no permanent odds bonus, and reward lures use the usual family pool.

Use the saved discovery record as the source of truth. Backfill supported discoveries from existing pre-Shop profiles. Validate exhibit proximity, milestone eligibility, and the claimed milestone ID on the server. Persist the reward and claim marker together. If the reward cannot be granted, leave it claimable. Test that repeat requests, reconnects, and duplicate hatches cannot double-pay or remove an earned claim. Include mobile completion and reward checks in the launch candidate.

## Meteor families and spawn pacing

| Meteor family | Where to find it | Launch role |
| --- | --- | --- |
| Ember | Home Crater | Most frequent. Guaranteed first rescue and steady early collection. |
| Frost | Frost Ridge | Frequent after the first tool upgrade. Supports reliable early ranch upgrades. |
| Verdant | Home Crater and Frost Ridge pockets | Mid-game branch with its own collection and regular opportunities after the first tool upgrade. |
| Storm | Frost Ridge and Astral Shelf | Uncommon, clearly announced encounters with a distinct pool. |
| Astral | Astral Shelf | Least frequent ordinary family, with a predictable solo route and a separate public group fall. |

Lower the ordinary spawn frequency of Storm and Astral while preserving predictable opportunities at each tool tier. Reserve regular spawn opportunities for the early families so adding new pools preserves starter pacing. Count time to an eligible claim in both solo and six-player runs, including contested spawns. Tune by observed attempts per hour and use teasers or countdowns to make rare encounters legible. Keep standard Astral available between group falls.

Show spawn availability separately from hatch chance. The Field Guide and Rarest Hatch board report the outcome chance per pod from its pool. A scarce meteor reduces attempts per hour. Its spawn rate does not enter the displayed hatch odds.

## Critter Expeditions and earnable potions

After placing the first critter, unlock a short solo PvE expedition at the Observatory. Let players send up to three owned, hatched critters against corrupted meteor creatures. Use one shared auto-battle format with **Guard**, **Striker**, and **Support** roles and one optional player-activated ability. Start with three difficulty tiers drawn from the same format. Make the basic tier clearable with ordinary early critters and add stronger rewards at higher tiers. Equipped critters can keep producing ranch income. Use species combat stats and roles for squad choices, and keep weight and income mutations out of combat power at launch.

- **Earn free potions.** Guarantee a basic potion choice on the first expedition clear and reward brewing materials on repeat clears. Let players trade materials plus earned Coins for a chosen potion at the Observatory. Introductory rewards and expedition access cost no Coins or Robux. Solo play can earn every launch potion type.
- **Field Luck Potion.** Temporarily improves selected Rare through Mythic odds in eligible standard pools. Preserve exact Secret and finish probabilities. Apply the potion at the server's pod outcome roll and show effective odds before that roll. Apply the existing rarity board eligibility rule for boosted-odds hatches and show when a potion would make a roll ineligible. Keep the standard Astral pool outside the launch potion's effect so the Eclipse Dragon chase stays eligible.
- **Coin Boost Potion.** Prototype **+25% online ranch income for 15 minutes**. Keep offline income and the permanent Coins/s leaderboard on the base lineup calculation. Show the temporary payout bonus separately and keep one active buff of each type. Use server timestamps and settle accrual when an income buff starts or expires.
- **Balance Coin spending.** Tools, slots, and feeding should offer clear permanent gains at each tier. Lures and brewing compete for surplus Coins after the next upgrade is affordable. Test a typical early, mid-game, and late-game session with and without potions to keep ordinary progression viable and brewing attractive.
- **Validate the loop privately.** Prototype one expedition and both potions with the first roster batch before expanding to all three tiers. Verify owned squad and unlock checks, one grant per completion, potion expiry and reconnect behavior, loot odds, and actual mobile play. Keep encounters, rewards, and potion timing server-authoritative.

## Hatch odds and leaderboards

Add this during Stage 6 alongside the expanded roster, before the public launch. The Observatory gets two global boards. The Field Guide and critter cards show the same odds and income labels they use.

| Board | What counts |
| --- | --- |
| **Rarest Hatch** | Highest lifetime rarity among the player's eligible species-and-finish hatches. Show the critter, its finish, meteor pool, and `1 in N` hatch odds. Keep the record if the critter is sold. Use standard earnable pod rolls at published, unboosted odds. Exclude premium, boosted-odds, granted, and legacy critters without a verifiable roll record. |
| **Ranch Coins/s** | Combined steady Coins per second from the player's currently placed critters, including weight, mutation, and feeding. A player's latest saved lineup stands while offline. Update after a lineup or income change and publish on a bounded refresh interval. Exclude temporary potion boosts, one-time rewards, and offline payouts. |

### Roblox PlayerList

- Mirror both stats in Roblox's built-in PlayerList **Here** view using server-set `leaderstats`. Show **Coins/s** as the first numeric column and **Rarest Hatch** as a compact odds label such as `1 in 1B`. Show a dash until the first eligible record. Read both from the same server data as the Observatory boards.
- Roblox currently offers one active persistent PlayerList leaderboard per experience through its Friends and Global beta. If available for Starfall Ranch and verified in private testing, register **Coins/s** using the same ordered score store as the Observatory income board. The Observatory shows both global tables and includes the critter name, finish, and meteor pool for rarity records. [Roblox Creator Hub leaderboard documentation](https://create.roblox.com/docs/players/leaderboards)

### Rarity and finishes

- Each standard meteor pool publishes a species probability as `1 in N` (label rounded display values as approximate). Keep Common through Secret as readable species tiers. A species available from multiple pools shows its odds by pool in the Field Guide, and each eligible hatch is ranked using the pool it actually came from.
- Roll one finish after the species. Start tuning at **89% Standard, 10% Gold, and 1% Rainbow**. Gold is one-tenth as likely as the species by itself, and Rainbow is one-hundredth as likely. A species with **1 in 500** pool odds is **about 1 in 562 Standard**, **1 in 5,000 Gold**, and **1 in 50,000 Rainbow**. These are proposed tuning values. Gold and Rainbow are collectible finishes with no direct Coins/s bonus in this baseline.
- The rarest launch outcome is **Rainbow Eclipse Dragon**. Start tuning Eclipse Dragon at **1 in 10,000,000** per eligible standard Astral pod, with **1% Rainbow** conditional on the species. That gives **1 in 1,000,000,000** per eligible pod. Keep other Secrets at materially higher odds and check time-to-hatch against observed attempts per hour. The apex hatch is a prestige goal. Keep progression, powerful ranch income, and ordinary collection milestones achievable without it. Track any full Secret collection as an optional completion record.
- The server determines the record using the unrounded joint probability of the species and finish. Save the original odds and pool revision so future balancing changes leave existing records intact. Display the leading record on the board and keep numerical ordering independent of display rounding.

### Weight, size, and mutations

- Use **1.0 kg = 1.0× base income**. Each **0.1 kg** adds or subtracts **10 percentage points** from that multiplier. Start testing with **0.8–1.5 kg** in 0.1 kg steps. At a base rate of **100 Coins/s**, a **0.8 kg** critter earns **80**, a **1.2 kg** critter earns **120**, and a **1.5 kg** critter earns **150** before other bonuses. Let displayed size follow weight within the pen and device performance budgets, with no separate size bonus.
- A hatch can independently roll one rare mutation. Also test an earnable natural mutation path through ranch play after hatching. Use Radiant as the starting mutation and preserve the existing Radiant appearance and earned value in migration. Mutation raises Coins/s and has no effect on the Rarest Hatch record. Balance mutation and weight together against ranch income caps and show the final rate on the card.
- Settle accrual at the old rate before a placement, feed, or mutation changes it. Reuse the server economy rate for pens, offline settlement, cards, and the Coins/s board. Freeze the species, finish, weight, and initial mutation outcome once per pod and persist it across rejoin and retry. Existing critters default to 1.0 kg and Standard finish while preserving existing progression. Keep the opening loop accessible before introducing the boards or income modifiers to new players.
- Before public launch, verify the pool and finish math, rate bounds, legacy saves, rejoin and duplicate-reward handling, and both boards across servers. Check that selling a record critter preserves the rarity entry, while moving a producer out of a pen lowers the income entry. Verify that changing weight or mutation leaves the rarity entry intact.

## Day-one shop and economy

The [Observatory Gear Shop](./OBSERVATORY_GEAR_SHOP.md) is the main Coin sink for the launch progression loop. Players earn through placed critters and spend on Star Lens hatch luck, Trail Boots travel speed, or Bond Charm PvE damage. Five fixed price tiers scale against ordinary ranch earnings as players move into rarer pools. The Coin catalog has its own cards, progression, and visual gear. At Astral progression, the earned-Coin [prestige garage](./OBSERVATORY_GEAR_SHOP.md#prestige-garage) adds three rides and two suits as high-price showcase goals.

Ship the verified shop alongside the full launch build. The launch lineup from [PR #9](https://github.com/jtchu22-debug/roblox-game-project/pull/9) includes gameplay passes for faster incubation, 2× capped offline Coins, Ranch VIP with extra bag room, and eligible non-Secret paid luck. Include Instant Hatch credits, a guaranteed Robux companion, cosmetics, and an eligible Premium Meteor product. Keep the advertised searchable Field Guide focused on the 108 earnable species. Put exclusive shop companions in a separate guide category.

Keep hunt-lure Coins earnable through play. Price exclusive guaranteed pets inside the earnable income range and test the combined effects of all paid perks on the strongest allowed ranch. Show the exact benefit of fixed perks. Premium Meteors and paid odds modifiers require per-player eligibility and all applicable numerical outcomes before purchase, with effective odds updated when a boost is active. Keep deterministic offers and regular play available to players restricted from paid RNG. [Roblox paid random items policy](https://create.roblox.com/docs/production/monetization/paid-random-items)

## Build order and sign-off

| Milestone | Deliverable | Exit check |
| --- | --- | --- |
| **Stage 2B — Expanded playable loop** | Stay on MockStore. Use the existing Crater with two distinct paths, two purchasable Cracker tiers, a distinct Astral arrival and crack, one named Frost lure, one capped feeding upgrade, and 2–3 new critters for 5–6 total. Show one follow-up goal after the first ranch pads. | Play through roughly 10–15 minutes of purposeful progression before inviting live testers. Run 3–5 new uncoached testers and log anonymous outcomes. |
| **Stage 3 — Persistence and multiplayer** | Persist the tool, ranch, critter and collection state. Support offline hatching, migrate old/default state, and verify larger servers. | Rejoin, overlapping sessions, server failures, inventory capacity and meteor claim cleanup behave consistently. |
| **Stages 4–5 — Art pipeline and private baseline** | Validate a Blender import end to end, build representative assets and the Field Guide, and test field readability, input and multiplayer performance. Prototype one public fall on a private server. | Clean mobile and desktop runs, working accessibility, and stable claims and per-player rewards. Review the first Observatory, ranch, and Ember environment slice privately. |
| **Stage 6 — Content-complete private candidate, then public launch** | Ship-ready roster of 108 earnable species, the finished Starfall Valley landscape with five meteor families across three fields, Critter Expeditions and earnable potions, Critter Index exhibit with collection milestones, portable Field Guide and records, finished station models, [unique item and interface artwork](./ART_DIRECTION.md#launch-item-and-interface-artwork), Observatory contracts and scanner, Rarest Hatch and Ranch Coins/s leaderboards, collectible finishes, weight and mutations, public meteor falls, modeled Crackers, the Observatory Gear Shop, tool and ranch progression, feeding, lures, capped offline Coins, and the day-one shop. | Privately verify the whole build, including all species’ earnable paths, catalog artwork coverage, station prompts and readable mobile screens, Index milestones and claim durability, meteor cadence, expedition rewards and temporary boosts, leaderboard odds, PlayerList display, and cross-server updates, mobile play, save and offline recovery, Gear Shop progression and late-game balance, and real purchase delivery and eligibility. Open publicly with those systems complete. |

### Stage 2B decision

Preserve the existing R-009 benchmarks. Record first reward against a 45-second median, hatch and pen against 80% within 90 seconds, and voluntary repeat rescue against 70% within five minutes. Report actual counts and elapsed times. Over the rest of the session, record whether players voluntarily chase the special meteor, choose between spending paths, and name their next goal without coaching. Watch whether they initiate that next action when time permits.

Advance if the opening remains legible and most testers show a reason to hunt or spend after the original upgrades. If players reach the new encounter and still describe the hunt as interchangeable, revisit the pivot decision before completing the roster. [Round 1 observations](./S2_01_PLAYTEST_KIT.md#5-recorded-stage-2-playtest-summary--round-1-v021-s2-playtest-live-2026-11-18) · [Review #012](./AGENT_REVIEWS.md#review-012--stage-2-round-1-decision)

### Implementation notes for Gemini

Keep players’ Coins, unlocks, lure entitlements, claims, drops, expedition rewards, potion timing and payouts under server authority. Reuse the current economy writer for spending, and use the shared configs to define fields, encounter rules, species and progression costs. Keep join/retry behavior consistent for the same reward. Settle offline earnings from saved pen rates and a server timestamp with a durable checkpoint. Deliver developer products through durable, idempotent receipts and verify player eligibility when offering and redeeming paid random items.

Keep the broad live-service ideas, such as additional maps, global trading, and reset-based rebirth, in the post-launch backlog. Launch depth comes from the expedition choices, ranch investment, collection chase and social falls above.
