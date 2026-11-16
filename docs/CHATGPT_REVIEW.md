# Independent Phase 0 review — Starfall Ranch

**Reviewer:** ChatGPT, independent technical director  
**Review date:** 2026-11-15 (project/client date)  
**Baseline:** main @ c5c5b1791f8eb38303d899d771aca3c23860e050  
**Verdict: CHANGES REQUIRED — concept conditionally recommended for a narrowly scoped prototype; production implementation remains blocked pending human sign-off.**

## 1. Executive assessment

Gemini produced an unusually organized planning package for a first Roblox project. Its strongest decisions are the no-theft premise, visible collection/plot progression, Part-first art, server-owned economy, typed modules and client-only non-authoritative pet visuals. Those should survive revision.

However, "95/100," "very easy," guaranteed retention, 60 FPS and safe monetization are not established facts. The proposed launch builds a farm, pet simulator, timing game, shop, mutation simulator, offline vault, fusion system, rebirth system, social network, boss event and monetization platform simultaneously. The risk is not merely code volume; it is combinatorial state interactions, economy balance, asset throughput and playtesting.

**Recommendation:** Starfall Ranch, simplified to one cosmic-critter pipeline and a differentiating rescue/meteor-finding loop. Give it a short prototype gate rather than committing to the complete design. Relic Raiders is the strongest backup if the collection loop tests as boring; Potion Pop is the strongest alternative for social creativity. No game code until the owner approves a revised spec.

Scope of audit: README, all 12 docs (MARKET_RESEARCH, TREND_ANALYSIS, GAME_CONCEPTS, GAME_DESIGN, TECHNICAL_ARCHITECTURE, DEVELOPMENT_ROADMAP, ART_DIRECTION, MONETIZATION, AGENT_RULES, AGENT_TASKS, AGENT_REVIEWS, DECISIONS), Rojo mapping, src/README and Blender generator. This is a design and static review; no Luau implementation exists and I did not run Studio, Blender, user playtests or internal analytics.

## 2. Research quality: directionally useful, not yet decision-grade

### Independent checks

These are MY independent public-source observations, not a repetition of Gemini's claims. Third-party CCU trackers are sampled and can disagree; collection times, peaks and rolling windows differ. They report simultaneous players, not distinct users, cohorts, revenue, causality or retention. Rounded values below are for comparison, not synchronized live measurements. Sources accessed around the review date (UTC may already be Nov 16).

| Experience | Independent evidence | Implication |
|---|---|---|
| Steal An Egg | Rolimon's records 14.29M all-time sampled peak (Sep 19 2026); game created July 25 2026. RoStats week Nov 9, partial 6/7 days: 774,556 average players, 6.89M peak, -12.3% vs prior week. [1][2][6] | Extremely relevant NOW, despite cooling week. Gemini's 1M+ understates its scale and late-2025 dating is wrong for this particular place. Description explicitly includes stealing eggs from pets, hatching, training speed and stealing from players. It is not just Steal a Brainrot with a different model. |
| Throw Food For Animals | RoStats same partial week: 256,882 average players, +53.2%, 2.47M peak; Rolimon's table samples ~2.43M record and creation Sep 18 2026. [2][6] | Strong current momentum for legible training/use skill/collect loop; study it separately rather than treating all collection games as weather farms. |
| Grow a Garden | Rolimon's records 22.38M all-time sampled peak Aug 23 2025; past 30 days ~107K peak, past 24h 24.4K peak. [3] AP reported 21.6M in late June 2025 from Roblox [4]. | Historical success is real; Gemini's June peak is roughly plausible but not the highest recorded. Much lower recent scale means cloning its 2025 recipe is especially risky. Exact Aug 14 2026 figure not independently established here. |
| Fisch | Rolimon's ~1.274M Oct 18 2025 historical peak and ~511K recent 30-day peak; RoStats partial week avg 62,107. [5][6] | Gemini's headline numbers match approximately. Strong comparator for tactile harvesting and collection, not proof of an individual mechanic's effect. |
| Break and Steal an Egg | Rolimon's ~1.31M tracked peak; RoStats partial week ~84,722 average (-28%). Its description advertises breaking eggs, escaping guards, base income and speed/pickaxe upgrades. [6][7] | Directly overlooked competitor: the crack-carry-hatch/collect-income pitch already exists nearby, so novelty cannot rest on cracking and pens alone. |
| Fish It! | Rolimon's records ~2.72M peak Dec 7 2025; RoStats partial week ~63K average. It explicitly lists simpler clicking interaction and exploration. [6][8] | Important counterexample to simplistic claims that clicking or automation necessarily fails. Also direct competition for aquarium idea. |
| Shovel It! | Rolimon's records ~2,374 peak March 22 2026; snapshot only 1 active player, despite weather, mutations, same collection cues and high like ratio. [9] | Useful negative/control example: combining fashionable mechanics does not guarantee sustainable demand. |
| Brookhaven, Murder Mystery 2, Blox Fruits, Adopt Me, RIVALS, 99 Nights | All above Fisch on the partial weekly chart; 99 Nights ~131K average; Brookhaven ~334K average. [6] | Social identity, creativity, mastery, discovery, roleplay, teamwork and repeatable skill challenges matter beyond RNG. |

Do not present RoStats' incomplete weekly report as a full week or compare a tracker peak against another game's average as if equal. A proper next research pass must add timestamped links, place IDs, week averages/peak windows, launch/update dates, sample cadence, and clear separation of observations, causal hypotheses and unverified claims. Validate the remaining exact Dead Rails, Dandy's World, Restaurant Tycoon 3, The Forge, Ride A Pet, Ultimate Mining Tycoon, legacy ranges and player-device breakdown before citing them as verified. The vague aggregator claims and combined cohorts are not a substitute for a reproducible evidence table. Do not claim we verified private revenue or D7/D28 cohorts.

### Roblox discovery

Official Discovery and FAQ [10][11] corroborate the first-session metrics and D1, D2–7, D8–28 behavior windows; play-through, first-play bounce, days played and playtime are key, with co-play, qualified sessions and spend metrics secondary. Gemini is right about the separation of ad-acquired users from ranking signals of organic Home-acquired users. However:
- No one metric is the sole ranking factor; play days are not demonstrably "#1." Play days in a window are not D7/D28 retention percentages.
- Benchmarks help creators diagnose, but do not directly set ranking. There is no genre-tag penalty or fixed category cutoff for clickers; no 28-day waiting requirement. New experiences can be tested early, and moving windows allow recovery.
- Claiming fixed session uplift (8 to 25 min), gifting sky-high D1 retention, organic short-form CAC of zero, or offline growth directly maximizing RFY is unsupported. Treat as testable hypotheses.
- Claims that 70%+ of young players are mobile and precise 70/20/10 device split are unsupported in this package. Design mobile-first regardless, measure actual devices.
- Reddit/YouTube/TikTok sentiment section lacks traceable examples, dates, sample selection or demographics; add anonymized themes with links, both praise/criticism, and acknowledge creator and selection bias. Never infer all children behave alike.

### Better research design (Gemini deliverable)

Collect 12–20 games spanning winners, mid-tier, recent failed clones and evergreen experiences; include new rivals above and 2–3 comparable newer cozy games. Document 5-minute firsthand gameplay walkthroughs, onboarding actions to first reward, second goal, active/passive loop, actual social interaction, accessibility, update cadence, and whether novelty is a mechanic or theme. Record 7/30-day average and update peaks from consistent tracker and snapshot timestamps. Separate correlation from plausible motivations, include counterexamples, and label hypotheses to test in OUR instrumented prototype. No extrapolation from private retention stats.

## 3. Market opportunity and eight trends

The strongest opportunity is not "another Grow a Garden with pets." It is a child-friendly, immediately understandable **go out and rescue/find cool creatures, improve a visible home, and share the discovery** loop. Kids should have a reason to keep playing when a shop timer is irrelevant and even when common drops occur. Emphasize agency, mastery, curiosity, ownership, expression, cooperation and competence; rarity and income are supporting rewards.

| Gemini trend | Independent disposition |
|---|---|
| 1. Size/mutation stacking | Keep ONE visible cosmetic variant, not a giant multiplicative economy. Test silhouette and collecting delight. |
| 2. Synchronized weather/shop | Defer both clocks. A common meteor field should always be available. Later test one optional weather event with no missable exclusive rewards. |
| 3. Offline progression | Keep offline incubation (simple absolute timestamps). Defer passive offline money or cap conservatively; avoid requiring check-ins or punishments. No offline random re-roll. |
| 4. Micro-skill | High priority. Test immediately; forgiving standard tap is full progression, no repetitive compulsory 1.5s bar 100x. Skill should improve feel, not huge economic bonus. |
| 5. Hold-to-flex/gifting | Keep inspectable ranch displays (capped visuals); defer transfer, likes rewards, gifting and friend economic buffs. Co-play should be fun even without existing friends. |
| 6. Bestiary/fusion | Simple discovered species checklist later; no stat stacking milestones or fusion until duplicates and capacity choices are understood. |
| 7. Automation/rebirth | Visible permanent upgrades early. Avoid reset/rebirth until a satisfying 20–30 minute progression arc exists; automation must not replace the most fun action. |
| 8. Viral spectacle | Use honest thumbnail and delightful hatch with reduced-motion option. No large-scale screen flash, pressure broadcasts, free acquisition promises, or social spending pressure. |

A short visual game title and thumbnail should communicate the verb and reward (e.g. "Catch Star Critters!" — test naming, not a committed title), rather than six abstract systems. Avoid confusing "Steal" branding if no players' items are stolen. Show a meteor and an adorable creature being rescued, not a collage of currencies.

## 4. Independent concept evaluation (all twelve)

These grades are **design judgments**, not market probabilities. Assess entry fun/readability (E), sustained choices/progression (P), positive social play (S), distinctiveness vs competition (D), beginner delivery (F), and extensibility/fair monetization (X). H/M/L mean high/medium/low relative promise; for F, H means most feasible. Younger players and mobile accessibility are embedded in E and S. Actual effort depends heavily on scope; all original specs are more complex than their difficulty scores imply.

| Concept | E | P | S | D | F | X | Decision/reason |
|---|---|---|---|---|---|---|---|
| 1 Starfall Ranch | H | H | M | M | H* | H | Lead, ONLY one critter pipeline. Cute ownership + active search; high clone risk, repetition. Safe visits and cosmetic habitats. |
| 2 Potion Pop | H | H | H | H | M | H | Serious runner-up. Funny usable potions are intrinsically social, recipes offer agency; recipe UI and avatar-effect cleanup/consent are real work. Single cauldron and 3 recipes could make a compelling later prototype. |
| 3 Relic Raiders | H | H | H | H | M/L | H | Strongest action backup. Actual risk/route decisions are engaging; avoid losing earned items and long lobby waits. Mobile trap readability, movement, content design and anti-teleport are expensive. |
| 4 Abyssal Aquarium | H | H | M | M/L | M | H | Attractive browsing/display; Fisch and Fish It! plus aquarium comparison already established; tank rendering/animation and underwater camera burden. |
| 5 Mega-Magnet Scrapyard | H | M | H | H | L | H | Strong tactile toy and mech milestone; replicated physics/ownership and object contention are risky. Simplify via logical attachment and local visual motion if reconsidered. |
| 6 Blocky Blacksmith | M | H | H | M | L | H | Visible craft-to-hero use is better than sale alone; combat/path, DPS tuning and animations multiply workload. Avoid paid combat power. |
| 7 Gachapon Toy Factory | H | M | M | M | H* | H | Easy shape factory; potential favorite for creative arrangement, but blind-box-only gameplay gets repetitive and monetization needs no random paid linkage. Use chosen toy recipes. |
| 8 Boba & Critter Café | H | H | H | M | M/L | H | Creative expression and visiting make strong cozy alternative; simplify guests to visual traffic, not queues/navigation; menu and decoration pipeline pricey. |
| 9 Sky-Train Express | H | H | H | H | L | H | Exciting moving world and natural cooperative roles; technical risk from moving platforms, replication and platform accessibility. Save for experienced team. |
| 10 Marble Plinko | H | L/M | M | M | M | L | Satisfying toy, but jackpot framing and chance-based payout unsuitable for this child-first monetization strategy. If ever revisit, use a non-wager marble construction puzzle. |
| 11 Piñata Fortress | H | H | H | M/H | L | H | Strong play/strategy loop, but multiple defense waves, targeting, co-op credit and balancing are a project of their own. |
| 12 Fossil Park | H | H | M/H | H | M | H | Close fourth: intuitive dino collecting, satisfying digging and museum customization; asset/sculpting burden higher than cube critters, excavation replay must be tested. |

*Feasibility assumes drastic simplification, not Gemini's original feature list. No score should be treated as measured retention, children’s preferences, or predicted success. Gemini’s rubric double-counts trend alignment/retention/clip-ability and favors feature quantity; difficulty omits integration, balancing, testing, content production and support. Its claim a new species takes 10 minutes ignores visual, balancing, registry, UI, audio, device, save migration and regression costs.

### Top 3 & decision

**Starfall Ranch** leads for a beginner because stationary plots, collectible state, low-poly assets and a simple repeatable input have fewer engine risks. But the proposed timing gauge by itself is a weak USP and Break and Steal an Egg makes a simple crack/base collection clone less defensible. Counter-propose an active **meteor rescue choice**: scan visible meteor trails, choose a nearby meteor type/risk/reward, crack to reveal a pod, bring it home, hatch and decide whether to keep for income or sell. No forced player-to-player race or loss; personal claim opportunities or fair replenishment. One visible choice (meteor color/location/trait) is essential. Test whether players chase another meteor without being told; if they merely wait for passive coins, pivot.

**Potion Pop** may outperform on differentiation if kids enjoy making funny effects. Test two benign, reversible effects for self/consenting participants and known recipes, no forced transformations. **Relic Raiders** offers more inherent decisions than a timing gauge; if Starfall's prototype fails, test a single safe timed vault with guaranteed first reward, short sessions and choice of deeper paths. Do not merge all three into launch. Human owner chooses final direction after revised concept review; no approval of original feature list.

## 5. Proposed product spec and economy challenge

### Prototype (NOT public launch)

- One compact flat/shared crater; 2 prototype plots (scale to 6 after multiplayer proof), each with 1–2 incubation spaces and 3 habitat slots. Max players ultimately equal plot capacity; always allocate a plot or handle full state gracefully.
- One earnable currency, three identifiable critter species (Slime, Fox, Golem), two visible meteor choices, basic tap with optional forgiving timing reward. A guaranteed starter critter; deterministic tutorial intro, not misleading "rare" event.
- First rescue instantly available, one hatch in ~10–15s. Hatch → place in pen → earn coins → buy a visible habitat expansion or tool upgrade. Upgrade within 2 minutes as a hypothesis. A small sell vs keep choice, one additional upgrade, no cash pickup physics.
- Server in-memory data with explicit test mode; no paid purchases, no persistent writes yet. Soft feel: cute animation/audio, lightweight readable UI. Other players can visit/inspect and collect their own meteors without blocking someone else's. No mandatory tutorial modal.
- One action prompt, currency, incubator progress, next upgrade goal. Touch/gamepad/keyboard; no reliance on color alone. No forced bloom/flash/shake. Mobile safe areas; test contrast and readability.
- A complete five-minute loop before building a second system. Repeat in a 15-minute unguided playtest.

### Private alpha after prototype passes

One coherent entity lifecycle: inventory pod → incubating pod → hatched critter → stored OR active habitat → sold (terminal). Preserve identity; no duplicate ownership. One modest fixed visual variant at hatch, short deterministic absolute growth timestamps; reliable profile saving and offline incubation only. Add species checklist (no multipliers), cosmetic display options, 3–5 visible permanent upgrades, fair replenishment, short optional co-op activity if proven fun. No full farming lane. Duplicates should have clear value.

### Public MVP scope after private alpha

6 plots if tests support; ~3–5 critters, one or two simple cosmetic variants, two habitat sizes, at most one optional communal event after core loop passes. Mobile polish, reliable saving, no exploitation blockers, onboarding funnel telemetry and honest packaging. Offline growth not an obligation; never punish missing a day. No separate StarGems, no paid progression, no streaks/time-play rewards, no stock scarcity, no player gifting/trading, no rebirths, fusion, five weathers, NPC AI, boss, multiple worlds, huge models or six upgrade trees. Later add feature only with owner approval, specific need, budget and tests. Monetization after stability and policy review, not before.

### First-session contract (targets, not observed data)

0–15s: see your ranch, meteor and a clear single action. 15–45s: crack/reveal and hatch first critter, place in pen. 45–120s: earn and spend on useful visible upgrade. 2–5 min: choose another meteor/creature and compare habitat options; meet another player if present. 5–15 min: progress toward a personally chosen critter or decoration. Next day: optional mature pod/new goal, not a streak loss or artificial scarcity.

### Economy math

GDD §4.2 and ADR-003 disagree: one sums all bonuses while the latter multiplies innate and weather groups. The GDD's "480x" example with stated 3x weight, 3.5x fusion, 25x and 15x mutations is actually 3^1.25 × 3.5 × (25+15−1) ≈ **539x**; the table uses 30x Prismatic, which would make it ~608x if 15x were valid. Golden tutorial 2x vs table 8x, weight/Colossal double-count risk, Supernova not consistently in tables. ADR's 8×(1+3+9)=104x is arithmetically right but still drastic. Neither bounds income.

Weather probability mismatches: GDD 35% per cycle but roadmap rolls every 20 seconds for 120 seconds (six rolls). If independent, 1−0.65^6≈92.5%, not 35%. Clearly specify once per event, each eligible item, exclusions, eligibility cutoff and persisted event ID if ever implemented. Offline simulation must not reroll matured slots or give better odds than returning normally.

5 coins/s tutorial × 43,200s × 35% = 75,600 offline coins **from one starter**, versus a 25-coin first upgrade. Massive imbalance. Five identical 1x creatures fused into 3.5x is a loss of total uncapped output, but gains output per slot; state this as a capacity tradeoff, never immediate universal upgrade. Rebirth reset definitions conflict (3 vs 5), and permanent buffs compound with pen slots and rare multipliers. Do not use resets as sole inflation control.

Counter-propose base integer income and fixed sell prices per species (sample tuning only: 2, 4, 7 coins/sec, first upgrade target 60–90 seconds under measured starter earnings). Use a modest skill benefit or cosmetic outcome, never client-awarded bonuses. One unique cosmetic variant or constrained multiplier ≤1.5x if needed; firm bound on coins, weight, inventory, active slots and server income. No exponent or stacked stats MVP. Decide whether selling sacrifices future income, avoid accidentally selling active/favorited item. Accrue at elapsed server time, settle before rate changes, floor once using bounded arithmetic/remainder. When active income accrues at 2/s for 60s, expect exactly 120 coins absent other changes. Cap integer totals well below floating-point precision limits. Build a spreadsheet or pure test simulator of starter/average/lucky/highest output, income vs prices, sale/keep choice, returning after 1h/12h, capacity and time to milestones. Do not promise exact balance before playtest.

## 6. Technical architecture critique

Good: clear service ownership, strict types, bootstrap scripts, server-only state/economy, config tables, proximity & rate checks, public visual replication, no humanoid pets. Official Roblox guidance supports validation across the client/server boundary and session locking [12][13]. Do not treat strict Luau types as runtime validation. Missing Network module/contract, state transitions, startup readiness, error handling and tests are launch blockers.

### P0 — correctness/security

1. **Cracking protocol:** RequestFinishCrack accepts ClientDelta; ignore it for reward. Server-issued unpredictable per-attempt nonce, meteor UID, owner, generation, start time, deadline; single active attempt per player; verify ready/loaded profile, alive character, distance at start AND finish, current claim, cooldown, expiry and capacity. Consume nonce and meteor claim, grant item once in one non-yielding state transition; release claim on timeout/respawn/leave, ensure reward before removing meteor. Two-player simultaneous finish, retry/replay, expired/forged tokens and meteor despawn tested. Clock-based exact gold window will penalize latency and is trivially scripted; server timing validates plausibility not human skill. Tolerate latency for standard reward, bounded cosmetic bonus or broad server-approved reward, no trusting mouse timing. Server checks replicated position but teleports remain possible (network ownership); use plausible traversal/state/rate constraints and reject impossible actions, don't ban solely for lag. ProximityPrompts are requests, not proof.
2. **Validate all inbound values:** enums allowlisted; strings bounded and IDs resolved in authoritative registry; finite numbers (NaN and ±inf), exact integral/bounded slots, matching action/argument shape; arrays dense and ≤ expected length with unique IDs; no arbitrary Instances or deep tables. Resolve player identity from Roblox-provided caller, target by actual current server ID. Per-player/per-action token buckets + global work cap, budget cleanup on leave, charge failed requests too; no expensive or yielding external calls in handlers. Return safe reasons, not internal errors. Validate ownership, current item state, capacity, plot, cost, proximity, cooldown, readiness server-side. Never rely on client cooldowns/UI. Use events for commands where practical with request ID + bounded acknowledgments; avoid waiting on client, safe error handling for RemoteFunction.
3. **One authority per entity:** InventoryItem and PlantedSlot currently duplicate fields, omit UID from planted state, ActivePenCritters references inventory. Schema needs single keyed Items map with immutable server UUID, species/state, optional slot and plantedAt/maturesAt; slot ownership relations keyed as serializable strings or dense arrays; no sparse numeric dictionaries/mixed tables, no Roblox Instance references, finite primitives only. Invariants: each UID has exactly one authoritative location; slot occupied by max one item; only stored item can place/sell; only active can accrue; no stale trophy ref; counts ≤ caps; currencies ≥0; no duplicate fusion UID, locked or active items cannot sell/fuse; each purchase/hatch atomic. Inventory full must reject BEFORE consumption. Clear all indices on sell/remove. Migration and reconciliation must validate and repair legacy/missing fields; don't replace valid loaded data with defaults. Schema currently omits OfflineVault balance, receipt ledger and settlement checkpoint despite referencing them; specify exact persisted fields and limits or remove features.
4. **Cross-player item transfers:** in-memory mutation of two tables in one no-yield thread plus session locks does NOT atomically persist two datastore keys. A crash after A saved but B not saved loses item; B saved but A not saved duplicates. Also receiver capacity, recipient confirmation, spam, gifting locked/active/paid items, disconnect and policy abuse. Remove gifting AND trading from MVP. Future transfer protocol needs persistent transaction ID/journal, escrow/reservation, idempotent reconciliation, locks/ordered per-profile writes, explicit receiver consent, atomicity/recovery tests at every crash boundary; policy checks and moderation. Never ship "trade next week" guarantee.
5. **Saving lifecycle:** prefer reviewed pinned ProfileStore [14] or Roblox official reference; not a handmade ~180-line lock. Vendor server-side only, preserve upstream license, document version/commit and update policy. Thin DataService adapter owns load/start session, reconcile schema, cancellation if player leaves, OnSessionEnd handling (stop accepting gameplay/kick with message), explicit profile readiness, mutation only during active session. Save/load with protected calls and sane bounded retry/backoff/jitter and budget awareness (respect library behavior, no duplicate competing loops). Prevent concurrent saves/out-of-order overwrites; autosave cadence staggered, immediate end-session on PlayerRemoving; shutdown stops new mutations, ends active sessions concurrently within BindToClose time budget. Mock data only explicit local/test configuration; NEVER fallback to new live profile on real load failure. Separate test place/store keys, avoid Studio touching production data. Verify existing data preserved, load fail, stale/reconnect lock, duplicate sessions, shutdown, autosave failure and abrupt process death. Initial mock tests cannot prove persistence. No money features until tests pass.
6. **Offline time and replay:** store last settled timestamp and state in same profile save; using LastSeen on logout only duplicates accrual since last autosave on crash. Clamp elapsed to non-negative bounded; use server wall clock for persisted epochs, monotonic clock for short durations. MatureAt absolute; process offline changes once on successful session, commit checkpoint and results together; welcome card is display not remint. Do not simulate unrelated weather or mature slots beyond eligibility. If income later introduced, settle online first and on every rate change, use checkpoint and bounded accrual; define crash loss window. Rejoin repeatedly should not overpay. Test future timestamp, 1s/12h/72h gaps, mature boundary, disconnect after apply/before durable save.
7. **Purchases (deferred):** no paid code before policy and stability. If eventually enabled, central server ProcessReceipt validates known product and user, loaded active profile, never trust prompt-finished, duplicate/parallel receipt and retry after disconnect; atomically save grant entitlement and purchase ID together; return PurchaseGranted only after verified durable grant, otherwise NotProcessedYet. Naive bounded ring buffer can evict old outstanding receipts and regrant. Use durable dedup or formally safe retention/reconciliation per receipt; document capacity. A transient weather event cannot be made retry-safe by just logging receipt—persist a consumable entitlement first, separately redeem after ready, never sell inaccessible effect. No claims of guaranteed zero loss. One-time permanent deterministic cosmetics via passes simpler; use Roblox ownership source and retry failures.

### P1 — architecture and replication

- Start with one server bootstrap + DataService (mock adapter), PlotService, MeteorService, and possibly Economy/Inventory domain module (single state writer). Shared Types, basic Config, pure math. Do not prebuild seven service frameworks, wrappers with generic arbitrary remotes, or service-locator complexity. Explicit dependencies: data ready → allocate plot → send snapshot; handlers check readiness; client subscribes then requests snapshot so no lost event before listener. Mark server start failure visibly. Avoid circular requires; only server rolls RNG and commits. Shared static prices/species definitions are fine for presentation, but may be inspected and must be validated server-side. Put secret seeds, receipt IDs, server-owned tables and anti-abuse policy in server containers.
- SyncPlayerData full profile is overbroad (internal timestamps, receipt IDs, policy flags etc.). Create whitelisted owner DTO with coins/owned items/slots; other players receive only necessary public plot appearance. Full snapshot/version on join, revisions on deltas, detect missing/out-of-order revisions and request rate-limited resync. Late joins receive all existing plots and meteor states, then updates; cleanup on plot reuse with generation/revision so old animation/state doesn't leak. No per-frame income replication; send sparse changes and interpolate locally.
- Global shop seeded by public unix window isn't secret and doesn't ensure version-matched deterministic ordered iteration. If later added, sorted stock IDs, mirrored stock version, server-authoritative window ID from server clock and price; check requested window at transaction commit, reject stale UI and return current stock. Define per-player limits vs genuinely limited global stock; MVP should use always-available stock, not cross-server contention. Persist counters atomically with purchase; no yield between checks and mutation.
- Weather if reintroduced: finite duration, per-server event ID, explicit eligibility/mutation state, cap, event replacement/queue behavior and cooldown. Do not call MessagingService/MemoryStore for MVP unless actual cross-server feature requires it. No timer for every item: compare timestamps on demand and one bounded server tick.
- Plot lifecycle: free queue and capacity checked, PlayerAdded/PlayerRemoving and respawn handled, stale callbacks rejected; initialize/release exactly once. World objects define stable IDs/tags, not arbitrary name strings from client.
- Test lint/type errors, pure deterministic economy transitions and invariants, service integration 2/6 players, latency and exploit matrix every milestone. No live or public testing on a real-money economy before passing. Log useful diagnostics without personal data.

### Performance & scalability

Use logical anchored, non-colliding visual critters; server owns sanitized positions/states, visual clones not authoritative Tools. Limit max modeled critters to a measured budget: e.g. 6 plots × 5 active = 30 (initial target), ≤~8 stud display height, disable distant particles/shadows, no per-entity RenderStepped connections; use one client manager/tweens, cancel/destroy on unload/revision. Big scale changes camera, occlusion, collision and UI; never model 35-stud critters within 60-stud plots in MVP. Particle transparency/highlights and repeated per-frame ScaleTo can cost GPU even with few triangles. Throttle, avoid work for offscreen plots, pool only if metrics justify. StreamingEnabled if measured beneficial, handle missing map nodes. No guarantee 60FPS from Parts or emulation. Measure real low-end phone/tablet (sustained ≥30 FPS initial target, then optimize), full-server FPS/frame spikes/memory/network and 15–30min soak. Device emulator validates layout/input, not device performance. Define memory baseline and acceptable delta measured in a published test place rather than claiming arbitrary 400MB. 250-stud diameter with walk speed 16 implies 125/16≈7.8s to cross from edge to center, not a universal 4s; layout test.

## 7. Roadmap: replace feature-first plan with gates

Existing plan introduces full typed catalogs/DataStore before central action, defers first outsider feedback, art feel and adversarial testing too late, and mislabels phases. A solo beginner with AI should expect integration/debugging time and manual Studio work. No fixed launch date based on phases.

| Stage | Work | Exit criteria |
|---|---|---|
| 0 (now) | Correct research, choose narrower concept, lock scope, agree ADRs. | Human confirms concept and revised scope; commit baseline. No source code yet. |
| 1 foundation + vertical slice (indicative 1–2 weeks part-time) | Rojo smoke test, greybox, one server-authoritative find/crack/hatch/place/income/upgrade loop, mock profile. | Two players can independently play repeatedly; invalid requests, duplicate claims, respawn and capacity tests pass. Tiny feel/audio pass now. |
| 2 discovery playtest | Test 5–10 new consenting testers (ideally mix mobile/desktop; guardian permission for minors), no coaching, no personal data. | Most understand without help, ≥80% hatch in 90s as directional target, median first reward ≤45s; at least ~70% voluntarily initiate another rescue within 5min; qualitative reason to return beyond rewards. These are hypotheses/acceptance targets, not industry standards; small sample not statistical proof. Iterate or pivot if fails. |
| 3 persistence alpha (1–2+ weeks) | Pin library, profile schema and migrations, offline incubation, 3 species, 3 upgrades, 2–6 plots; repeated security checks. | Save/rejoin, overlapping sessions, lock loss, failure injection, crash/leave/shutdown, rejoin time, duplicate/capacity all pass. No silent fresh saves. Run full-server test. |
| 4 polish/private beta (1–3+ weeks) | Tighten feel, original low-poly hero assets, responsive UI, animations, checklist, optional non-economic social play; analytics and real device tests. | 15–30 min full-server soak and performance budget passes; no blockers; second playtest meets goals without artificial timers. |
| 5 controlled soft launch | Publish only approved scope, instrument funnel and retention cohorts; monetization only after product, policy and receipt checks. | Observe enough genuine new users/return cohorts, compare similar-game dashboards, investigate dropoff; decide iterate/continue/stop. Do not promise viral success. |

Log anonymous onboarding steps with server-authoritative success (spawn → first meteor → first hatch → first placed → first upgrade → second rescue), time per step, failures, session length, D1/D7 and later D28 trends, reset errors and economy sources/sinks. Distinguish new/returning and organic/ad traffic; use official analytics when sample size supports it. Observe what children actually enjoy, not only how long they play. Test title/icon alternatives honestly. No spending targets for children.

## 8. Art, workflow and missing considerations

Part-first is right. Put one visually delightful critter and satisfying meteor feedback into the prototype, rather than waiting for full art sprint. Art direction palette strong; define unique silhouettes, color-independent icons, light/dark contrast, readable mobile labels, reduced motion & sound settings. Asset source/ownership, sound licenses, model origin/scale/pivot/attachments and importing into a clean test model should be documented.

Blender script was statically inspected, not executed: currently generates only 3 clusters, 2 meteors, 2 critters; not full catalog. create_meteor_geode ignores core_rgba and doesn't actually embed glowing shards; critter lacks visible eyes/tail attachment; exporter promised in ART_DIRECTION is absent (no FBX export call). Triangle budgets unverified especially bevel and UV spheres; material emission/color compatibility across Blender versions and Roblox importer uncertain. Generator deletes all objects in named collections on rerun: document dedicated generated scene, confirm replacement before production use, never run on valuable artist scene. Start with a single reviewed sample export/import and verify dimensions, normals, pivots, material segmentation and runtime recoloring. Later fix script separately; don't burn time now.

Rojo mapping points at missing src/Shared, src/Server, src/Client directories at baseline (empty directories not tracked). A clean clone cannot reliably build as written. First approved task: create actual mapped files/folders and smoke-test pinned Rojo version against isolated Studio place. Add README command paths, plugin connect/disconnect & test guidance; choose Rojo as canonical source and manual copy only educational fallback, not parallel workflow. Explicitly preserve unmanaged Studio objects; define which nodes are Rojo-managed and map assets/reference place artifact or reproducible generator in Git/LFS documented. Sync source changes before/after Studio editing; no asset API keys or credentials in public repo. Command-bar generator approved only in isolated test place; idempotent tagged generation root, unique IDs, dry-run/confirmation for destructive replacing, consistent hierarchy and asserts. No scripts fetched/executed from arbitrary sources. Use versioned build and branch/PR checklists with owner review.

Important missing considerations: settings/device-safe areas, gamepad navigation, respawn/reconnect, full server, disconnect at each action, abuse of social UI, text filtering and privacy (no freeform user text or external chat/Discord dependency for children), cosmetic licensing, experience maturity/publishing eligibility checks, reporting/blocking using Roblox features, moderation and support process, analytics cost/sample bias, and patch rollback/schema compatibility. No claim of blanket regional legal compliance. Set low-spec targets early. Limit flashing/screen effects and opt out.

## 9. Monetization policy correction and risks

Gemini's "no paid random loot" principle contradicts its concrete products. Roblox official policy [15] includes paid currency used to purchase random results and paid luck/probability modifiers. Starter bundle sells 2500 coins that buy random pods; paid beacons increase random mutation odds; several concepts sell luck. These could be indirect paid-random items even if the vendor price is fixed or the whole server benefits. Disclosing numerical odds and using per-player PolicyService restrictions would be needed if such systems were pursued; this review recommends avoiding them entirely, including any purchasable convertible currency used on randomized pods, and avoiding paid random-item trading. Do not infer universal child compliance. Extra income slots, 24h vault and speed confer meaningful advantage; earnability doesn't make them cosmetic or fair. Public spending announcements encourage social pressure. Remove from initial plan.

Roblox replaced Engagement-Based Payouts and Creator Affiliate programs with Creator Rewards on July 24 2025 [16][17]. Revise monetization document to current Daily Engagement/Audience Expansion rules, eligibility and authentic engagement; do not promise Premium time income or any revenue. No dark patterns, forced purchase UI, streak loss, false scarcity, social pressure or spend-driven design for children. Start later with fixed-price transparent purely cosmetic ranch themes/cosmetic accessories; all gameplay earnable. Let child enjoy game without payment. Price tests and compliance review later (no guaranteed revenue).

| Risk | Severity | Response |
|---|---|---|
| Generic derivative concept, market cooling by launch | High | Test unique rescue choice, current competitor research and honest thumbnail before full build. |
| MVP scope/integration burnout | Critical | cut to one loop, milestone gates, weekly owner review. |
| Data loss/dupes | Critical | one-item state, session locks, failure tests; no transfers. |
| Currency inflation/boring idle loop | High | bounded simple economy; validate time-to-goal/keep-sell, remove offline coin faucet. |
| Cheating/race/network latency | High | server-owned lifecycle, nonce, proximity and validation, low-stakes skill bonus. |
| Child monetization compliance & pressure | Critical | no paid random interaction/currency/boost; no paid economy until independently reviewed. |
| Mobile frame/input overload | High | limited models, real-device budget, accessible inputs. |
| AI-generated integration regressions | High | one source of truth, tiny PRs, tests, pinned dependencies, owner rehearses Studio setup. |

## 10. ADR dispositions and tasks for Gemini

- ADR-001 **APPROVED WITH MODIFICATIONS / HUMAN APPROVAL REQUIRED:** keep Starfall as prototype candidate only, differentiated meteor rescue/choice. Explicit backup Relic Raiders / Potion Pop; revisit after test.
- ADR-002 **COUNTER-PROPOSED:** choose B, unified critter pipeline, no claimed percentage effort savings. Model, inventory, growth and economy one domain.
- ADR-003 **COUNTER-PROPOSED:** simple bounded integer economy, no weight exponent or stacked mutation/fusion initially. One cosmetic variation and explicit cap. Revisit only after balance evidence.
- ADR-004 **APPROVED WITH MODIFICATIONS:** pinned ProfileStore plus thin adapter, mock first, license, documented API and lifecycle tests; official reference alternative only if justified. No custom lock by default.
- ADR-005 **COUNTER-PROPOSED:** defer BOTH gifting and trading, no fixed post-launch date until durable transactions and policy tests.
- ADR-006 **APPROVED WITH MODIFICATIONS:** generator isolated, idempotent, names/tags validated, preserve unrelated assets. Smoke test after sign-off.
- ADR-007 **APPROVED WITH MODIFICATIONS:** Rojo canonical pinned setup, fix absent mapped dirs once implementation authorized, preserve Studio-managed assets, reproducible greybox, no parallel source edits.

Three next development/work items (not authorization to code):
1. Gemini revise MARKET_RESEARCH and TREND_ANALYSIS with reproducible sources, negative controls, recent competitors, remove unsupported algorithm/causality claims.
2. Gemini revise GAME_DESIGN, TECHNICAL_ARCHITECTURE, MONETIZATION and ROADMAP for one-pipeline prototype, bounded numbers, clear lifecycle and security/monetization cuts. Present updated scope, acceptance tests and open tradeoffs for human approval.
3. **After human approval only:** implement the minimal Rojo+greybox vertical slice on a feature branch with mock profile and adversarial 2-player tests. Observe first five-minute loop before real persistence, weather, additional content or purchases.

T-011 independent review complete on review branch; T-012 revision/human approval remains blocked. No implementation in this PR. Gemini owns integration of revisions; do not overwrite their original research with this audit. Human lead approves changes/merges and determines creative direction.

## References (retrieved around 2026-11-15/16; tracker stats dynamic)

[1] Rolimon's Steal An Egg: https://www.rolimons.com/game/107778070777162  
[2] Rolimon's sampled game table: https://www.rolimons.com/gametable  
[3] Rolimon's Grow a Garden: https://www.rolimons.com/game/126884695634066  
[4] Associated Press, historic 2025 peak (attributed to Roblox): https://apnews.com/article/2f5e4368448d57002d08b1b3d4a289ca  
[5] Rolimon's Fisch: https://www.rolimons.com/game/16732694052  
[6] RoStats week Nov 9 2026 (partial at retrieval): https://rostats.io/charts/2026-w46  
[7] Rolimon's Break and Steal an Egg: https://www.rolimons.com/game/114326934417838  
[8] Rolimon's Fish It!: https://www.rolimons.com/game/121864768012064  
[9] Rolimon's Shovel It!: https://www.rolimons.com/game/133832344745984  
[10] Roblox Discovery: https://create.roblox.com/docs/discovery  
[11] Roblox Discovery FAQ: https://create.roblox.com/docs/discovery-faq  
[12] Roblox securing client-server boundary: https://create.roblox.com/docs/scripting/security/client-server-boundary  
[13] Roblox player data and purchasing: https://create.roblox.com/docs/cloud-services/data-stores/player-data-purchasing  
[14] ProfileStore upstream: https://github.com/MadStudioRoblox/ProfileStore  
[15] Roblox paid random items: https://create.roblox.com/docs/production/monetization/paid-random-items  
[16] Roblox Creator Rewards: https://create.roblox.com/docs/creator-rewards  
[17] Roblox deprecated engagement-based payouts: https://create.roblox.com/docs/production/monetization/engagement-based-payouts  
[18] Roblox DataStore best practices: https://create.roblox.com/docs/cloud-services/data-stores/best-practices  
[19] Roblox MarketplaceService receipt reference: https://create.roblox.com/docs/reference/engine/classes/MarketplaceService  
[20] Roblox Analytics: https://create.roblox.com/docs/production/analytics  
