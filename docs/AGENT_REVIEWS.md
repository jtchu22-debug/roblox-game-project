# Independent Technical Director Review Log (`AGENT_REVIEWS.md`)

> **Last Updated:** November 15, 2026  
> **Primary Reviewer:** ChatGPT (Independent Technical Director)  
> **Purpose:** Provide a structured, critical audit trail where ChatGPT challenges assumptions, verifies research, critiques game concepts, and audits technical feasibility before implementation begins.

---

## Instructions for ChatGPT (Technical Director)

Welcome to the repository! As the independent **Technical Director & Reviewer**, your mandate is **not** to rubber-stamp Gemini's proposals. Please be rigorous, critical, and practical.

When reviewing this Phase 0 package, please evaluate and document your findings below across these 7 areas:

1. **Market Research & Algorithm Audit (`MARKET_RESEARCH.md`):**
   - Are there any blind spots in how the 2025–2026 Roblox market or the 28-day Recommended For You (RFY) algorithm is analyzed?
   - Do you agree with the assessment of why classic clicker simulators fail to retain mobile players?
2. **Trend Analysis Audit (`TREND_ANALYSIS.md`):**
   - Which of the 8 identified trends are strongest for a beginner team, and which carry hidden execution traps?
3. **Concept Ranking & Finalist Critique (`GAME_CONCEPTS.md`):**
   - Audit the 12 concepts and the Top 3 finalists:
     - **#1: *Starfall Ranch: Critter & Crystal Tycoon*** (95/100)
     - **#2: *Potion Pop! Alchemy & Cauldron Tycoon*** (91/100)
     - **#3: *Relic Raiders: Vault & Museum Tycoon*** (90/100)
   - Do you agree with **Concept #1 (*Starfall Ranch*)** as the recommended primary game, or do you believe **#2 (*Potion Pop!*)**, **#3 (*Relic Raiders*)**, or another concept offers a higher probability of success?
4. **Game Design & Economy Math Critique (`GAME_DESIGN.md`):**
   - Stress-test the **Value & Mutation Formula**:
     $$\text{Value} = \text{BaseValue} \times \left(\frac{\text{WeightKg}}{\text{BaseWeightKg}}\right)^{1.25} \times \text{TierFusionMult} \times \left(1 + \sum_{i} (\text{MutationMult}_i - 1)\right)$$
   - Does additive mutation stacking (`1 + sum(Mult - 1)`) strike the right balance between excitement and inflation control, or should specific weather/innate categories multiply against each other?
   - Is the **MVP Scope (Bucket 1)** genuinely achievable for a beginner developer, or should anything in Bucket 1 be pushed to Bucket 2 (Post-Launch)?
5. **Technical Architecture & Security Audit (`TECHNICAL_ARCHITECTURE.md`):**
   - Audit the `PlayerProfileData` schema, `RemoteEvent`/`RemoteFunction` payload contracts, and offline timestamp calculation.
   - Identify any missing exploit edge cases, race conditions (e.g., during Proximity Gifting, Rebirth resets, or Supply Ship window rollovers), or mobile memory bottlenecks.
6. **Roadmap & Beginner Onboarding Audit (`DEVELOPMENT_ROADMAP.md` & `ART_DIRECTION.md`):**
   - Will a beginner developer get stuck transitioning from code to Roblox Studio 3D hierarchy setup? *(See ADR-006 in `DECISIONS.md` regarding a Studio Command-Bar Map Generator script).*
7. **Open Decisions Sign-Off (`DECISIONS.md`):**
   - Record your position on **ADR-001 through ADR-007** in `docs/DECISIONS.md`.

---

## Review Log

### Review #001 — Phase 0 Research, Concept & Architecture Audit
- **Reviewer:** ChatGPT (Independent Technical Director)
- **Status:** `PENDING REVIEW`
- **Date:** *(To be filled by ChatGPT)*

#### 1. Executive Verdict
*(ChatGPT: State `APPROVED`, `APPROVED WITH MODIFICATIONS`, or `CHANGES REQUIRED`)*

#### 2. Concept Selection Critique (*Starfall Ranch* vs. *Potion Pop!* vs. *Relic Raiders*)
*(ChatGPT: Record your evaluation of the Top 3 concepts here)*

#### 3. Economy Math & MVP Scope Findings
*(ChatGPT: Record what should be cut, simplified, or re-tuned in the MVP)*

#### 4. Technical Architecture & Security Findings
*(ChatGPT: List specific architectural improvements or edge cases to fix before Phase 1 coding)*

#### 5. Action Items for Gemini (Phase 1 Pre-Requisites)
- [ ] *(ChatGPT to populate actionable items)*



---

### Review #001 — Independent Technical Director response (2026-11-15)
- **Status:** `CHANGES REQUIRED` — independent audit completed; revised design and human approval pending.
- **Baseline reviewed:** `c5c5b1791f8eb38303d899d771aca3c23860e050`
- **Full audit:** [CHATGPT_REVIEW.md](./CHATGPT_REVIEW.md).
- **Concept:** Starfall Ranch is recommended only as a narrowed, hypothesis-testing prototype, not approval of the current launch scope. Potion Pop and Relic Raiders remain viable alternatives.
- **Research:** Directionally credible, but unsupported causal claims and missing reproducible citations. Independent current snapshots confirm Steal An Egg and Throw Food For Animals momentum, Grow a Garden historic-vs-current decline, and neglected rivals including Break and Steal an Egg and Fish It!.
- **Economy:** Conflicting formulas, 539x example rather than 480x, probability repeated-roll mismatch, excessive offline faucet. Start with one bounded economy and critter lifecycle.
- **Security:** Good server authority and lightweight visuals; resolve attempt replay/double-claim, unsafe remote payloads, one-item/one-location invariant, private vs public replication, load/save failures, durable receipt dedup and asynchronous lifecycle. Gifting/trading deferred; two-key saves are not atomic.
- **Roadmap:** Prototype/observe fun before production persistence, full content and monetization. Run adversarial tests every milestone.
- **Monetization:** Correct obsolete payout program and remove indirect paid random rewards, probability boosts, progression advantage and social-spending pressure.
- **Actions:** See R-001 through R-010 in [AGENT_TASKS.md](./AGENT_TASKS.md) and individual ADR dispositions in [DECISIONS.md](./DECISIONS.md).
- **Gate:** T-011 complete on review branch; T-012 and human approval remain outstanding. Do not implement Phase 1 yet.

---

### Review #002 — S1-02 greybox generator (2026-11-15)

**Verdict — REJECT**

Reviewed [`33db18c`](https://github.com/jtchu22-debug/roblox-game-project/commit/33db18c2f5966990ff2bd38f5203926dd7f46eb9), the S1-02 commit on `main`. This was a static review of the changed map builder, Studio tool, shared self-test, and server boot path against the approved S1-02 and ADR-006 requirements. Roblox Studio execution and viewport checks remain unverified.

The normal empty-place path constructs the tagged root, the central crater, two ranch plots, and the interaction anchors. The geometry joins the crater and both plots at their bridge entrances. The upgrade pads use the existing upgrade config, and server startup generates the map before the services start. A normal rerun preserves an existing valid map. The confirmed replacement and invalid-map startup paths fail the preservation requirement.

#### Required fixes

1. **High — Protect authored Studio objects during replacement.** `Generate` destroys any child with the root name when `ConfirmReplace` is true, even if it is an unrelated model or untagged folder. `EnsureExists` also silently enables replacement whenever a same-named folder fails validation. In Edit mode the command can remove the unrelated object's descendants from the authoring place. At runtime the auto-repair discards authored map edits in the current server, and a non-folder name collision aborts service startup with a generic error. Require the expected folder and ownership tag before any replacement. Have runtime startup reuse a valid root, generate on absence, and report a clear, non-mutating error on invalid or conflicting content. For explicit replacement, build and validate the candidate off-tree before swapping out the owned root. [Replacement and startup paths](https://github.com/jtchu22-debug/roblox-game-project/blob/33db18c2f5966990ff2bd38f5203926dd7f46eb9/src/Shared/Util/GreyboxBuilder.luau#L494-L551) · [Studio command](https://github.com/jtchu22-debug/roblox-game-project/blob/33db18c2f5966990ff2bd38f5203926dd7f46eb9/tools/studio/GenerateGreyboxMap.luau#L16-L29)
2. **Medium — Validate the map contract upcoming services will consume.** `ValidateHierarchy` accepts an untagged `SellStand`, a wrong-class `SpawnPoint`, and tagged anchors with incorrect or missing identifiers. A map saved through Studio can pass startup checks and then leave a plot without a discoverable sell stand or bind an anchor to the wrong slot. Check the classes, relevant tags and expected `PlotId`, `SlotId`, `UpgradeId`, `NodeIndex` and starter metadata before accepting a root. Return the offending path in the error. Discover within the validated root. The six wild nodes are tagged, while the two starter nodes are in a separate untagged folder. Keep those collections explicit in the S1-07 contract so wild selection preserves the guaranteed starter meteor. [Hierarchy checks](https://github.com/jtchu22-debug/roblox-game-project/blob/33db18c2f5966990ff2bd38f5203926dd7f46eb9/src/Shared/Util/GreyboxBuilder.luau#L415-L491) · [Wild and starter generation](https://github.com/jtchu22-debug/roblox-game-project/blob/33db18c2f5966990ff2bd38f5203926dd7f46eb9/src/Shared/Util/GreyboxBuilder.luau#L158-L203)

#### Verification

Extend the existing map suite to verify that a same-named untagged object and its descendants survive both entry points, a damaged owned root survives startup refusal, a valid owned root is reused, and a bad class, tag or ID fails validation. The current test's unrelated object is a differently named sibling, so it misses the overwrite bug. Then run the command in an isolated Studio place in Edit mode and use Play to verify a clean server startup and traversable bridges. [Existing self-test](https://github.com/jtchu22-debug/roblox-game-project/blob/33db18c2f5966990ff2bd38f5203926dd7f46eb9/src/Shared/Util/SharedSelfTest.luau#L189-L224) · [Startup sequence](https://github.com/jtchu22-debug/roblox-game-project/blob/33db18c2f5966990ff2bd38f5203926dd7f46eb9/src/Server/ServerInit.server.luau#L14-L37)

#### Security and remaining scope

The map builder runs from the server bootstrap and exposes no gameplay request handler. Currency, critter grants, and progression authority remain unverified because the relevant server services are stubs. Plot assignment and player-specific spawning belong to S1-06. Require server-owned plot, distance, readiness and progression checks when S1-03–S1-07 connect inputs to state changes. Studio anchors and their replicated metadata are discovery data. [Roblox client-server security guidance](https://create.roblox.com/docs/scripting/security/client-server-boundary)

**Optional —** Keep the two-plot layout and current module organization for Stage 1. Move plot origins into layout data when S3-03 introduces six plots. Limit the startup self-test to Studio or a deliberate test run before publishing a prototype.

**Handoff to Gemini —** Fix the two S1-02 findings and attach the focused Studio results before S1-06 and S1-07 rely on the map. S1-03 can proceed independently of the map fixes.

---

### Review #003 — S1-02 re-review and S1-03 gate (2026-11-15)

**Verdict — APPROVE. Start S1-04.** Reviewed [`326f596`](https://github.com/jtchu22-debug/roblox-game-project/commit/326f5960187afa16422e0bd8f465a1798fe296d9) on `main`.

- **S1-02 — Both Review #002 findings resolved.** Replacement requires an owned tagged folder and a validated off-tree candidate. Startup preserves conflicting objects and invalid owned roots, and reuses valid roots. The hierarchy checks enforce anchor classes, tags and IDs at named paths, with wild and starter nodes kept separate. Regression cases cover ownership, malformed map metadata and valid-root reuse. [Ownership and startup](https://github.com/jtchu22-debug/roblox-game-project/blob/326f5960187afa16422e0bd8f465a1798fe296d9/src/Shared/Util/GreyboxBuilder.luau#L651-L716) · [Map contract](https://github.com/jtchu22-debug/roblox-game-project/blob/326f5960187afa16422e0bd8f465a1798fe296d9/src/Shared/Util/GreyboxBuilder.luau#L415-L648) · [Regression tests](https://github.com/jtchu22-debug/roblox-game-project/blob/326f5960187afa16422e0bd8f465a1798fe296d9/src/Shared/Util/SharedSelfTest.luau#L189-L286)
- **S1-03 — Networking accepted.** The eight remote names, directions and classes match the architecture. Every inbound route uses Roblox's caller identity, charges a per-user, per-remote server bucket before validation, and rejects invalid shapes before dispatch. `PlayerRemoving` clears the buckets. The outbound API targets a single player for owner state and has separate public plot methods. The relevant gameplay handlers are still pending, so authorization of profile, coin, critter and claim changes remains for the milestones that implement them. [Remote setup](https://github.com/jtchu22-debug/roblox-game-project/blob/326f5960187afa16422e0bd8f465a1798fe296d9/src/Server/Services/NetworkService.luau#L219-L257) · [Dispatch and cleanup](https://github.com/jtchu22-debug/roblox-game-project/blob/326f5960187afa16422e0bd8f465a1798fe296d9/src/Server/Services/NetworkService.luau#L189-L217) · [Event and function bindings](https://github.com/jtchu22-debug/roblox-game-project/blob/326f5960187afa16422e0bd8f465a1798fe296d9/src/Server/Services/NetworkService.luau#L259-L312) · [Outbound routing](https://github.com/jtchu22-debug/roblox-game-project/blob/326f5960187afa16422e0bd8f465a1798fe296d9/src/Server/Services/NetworkService.luau#L343-L361)

#### Verification

- Independently built the exact Git commit with Rojo 7.4.4 and verified the Rojo sourcemap for the network service, greybox module, and server and client entry points.
- Cross-checked the [posted Studio Output](https://github.com/jtchu22-debug/roblox-game-project/pull/2#issuecomment-6906711016) against the local Studio log. Six shared and three network test suites passed. Studio reused the greybox, started both sides and returned `InvalidPayload` for an invalid upgrade and `ServiceUnavailable` for a valid upgrade with no gameplay handler. This review used the recorded Studio run. Manual Edit-mode rerun, bridge traversal and a two-client gameplay session remain unverified. The asset-type warning also appeared on earlier versions and did not stop startup.

#### Handoff to Gemini

Implement the Stage 1 in-memory profile lifecycle in S1-04. Create independent profile tables matching `Types.PlayerProfileData`, expose them only while ready, and clear the profile and readiness on leave. Verify two players start with independent state, existing players are initialized if present at startup, and leave/rejoin follows the mock lifecycle. Preserve the readiness boundary when handlers come online. The client startup comment still describes a future snapshot request. When the snapshot owner and client listeners are wired, ensure an initial request made before readiness has a delivery or retry path and that another client never receives the owner profile. [DataService milestone stub](https://github.com/jtchu22-debug/roblox-game-project/blob/326f5960187afa16422e0bd8f465a1798fe296d9/src/Server/Services/DataService.luau#L25-L38) · [Snapshot event](https://github.com/jtchu22-debug/roblox-game-project/blob/326f5960187afa16422e0bd8f465a1798fe296d9/src/Server/Services/NetworkService.luau#L266-L278) · [Client startup](https://github.com/jtchu22-debug/roblox-game-project/blob/326f5960187afa16422e0bd8f465a1798fe296d9/src/Client/ClientInit.client.luau#L25-L34)

---

### Review #004 — S1-04 and S1-05 gate

**Verdict — APPROVE WITH CHANGES. Gemini can start S1-05 in Studio.** Reviewed [`ca493bf`](https://github.com/jtchu22-debug/roblox-game-project/commit/ca493bf4015ac01e0daa96aca66503b804eb4dd7) on `main`.

- **Lifecycle and integration pass.** Players get fresh profile tables. Getters require a ready session and the production call path checks the Player instance. Shutdown of a mock player session clears its readiness and profile, and startup catches players already present. Owner state is copied into a dedicated DTO and targeted to the requesting player. The client attaches its listener before the initial request. [Profile creation](https://github.com/jtchu22-debug/roblox-game-project/blob/ca493bf4015ac01e0daa96aca66503b804eb4dd7/src/Server/Services/DataService.luau#L81-L94) · [Readiness and snapshot](https://github.com/jtchu22-debug/roblox-game-project/blob/ca493bf4015ac01e0daa96aca66503b804eb4dd7/src/Server/Services/DataService.luau#L152-L205) · [Lifecycle](https://github.com/jtchu22-debug/roblox-game-project/blob/ca493bf4015ac01e0daa96aca66503b804eb4dd7/src/Server/Services/DataService.luau#L229-L370) · [Client startup](https://github.com/jtchu22-debug/roblox-game-project/blob/ca493bf4015ac01e0daa96aca66503b804eb4dd7/src/Client/ClientInit.client.luau#L25-L36)
- **Medium — Guard mock profiles before publishing.** `DataService.Init` checks only `USE_MOCK_STORE`, which is checked in as true. A published server can therefore start with temporary profiles and reset progression on rejoin. This conflicts with the environment boundary in the architecture, but does not block local S1-05 development. Default to Studio-only and allow a deliberately designated private prototype place only if published prototype testing is needed. Keep production closed until the persistent adapter is implemented. [Startup guard](https://github.com/jtchu22-debug/roblox-game-project/blob/ca493bf4015ac01e0daa96aca66503b804eb4dd7/src/Server/Services/DataService.luau#L343-L349) · [Architecture](https://github.com/jtchu22-debug/roblox-game-project/blob/ca493bf4015ac01e0daa96aca66503b804eb4dd7/docs/TECHNICAL_ARCHITECTURE.md#L158-L160)
- **Low, deferred to persistence — `ReconcileProfile` is unused in mock mode.** It can accept malformed critter records, mismatched IDs and invalid slot references. Do not wire it into S1-05. Before Stage 3, validate the entire profile and item/slot consistency or replace it with the tested migration path. [Reconciler](https://github.com/jtchu22-debug/roblox-game-project/blob/ca493bf4015ac01e0daa96aca66503b804eb4dd7/src/Server/Services/DataService.luau#L96-L149)

#### Verification

Independently built the exact commit with Rojo 7.4.4. Reviewed the recorded Studio logs for both solo and two-client runs. All 12 suites passed and both local clients logged a revision 1 owner snapshot with 0 Coins and bag capacity 10. Profile isolation and reset on rejoin are covered by the in-process self-test. A real-client reconnect, forced pre-ready delivery, and a distinct-state test across the two clients were not independently exercised.

#### Handoff to Gemini

Begin S1-05 with EconomyService as the sole writer of coins, critter state, slots and upgrades. Read the ready profile for the Roblox-supplied player and keep each validation-to-commit transition free of yields. Test failed operations for zero state changes, duplicate transitions for single application, and elapsed settlement before pen rate changes. Keep lifecycle callbacks synchronous while they hold a session reference, or explicitly guard against stale-session work when async behavior is introduced.

---

### Review #005 — S1-05 economy and S1-06 gate

**Verdict — REJECT. Fix the two S1-05 blockers before moving to S1-06.** Reviewed [`d595e33`](https://github.com/jtchu22-debug/roblox-game-project/commit/d595e337430d3dfc9eb4dd1536b3adaaff104e26) on `main`.

The normal critter lifecycle keeps its item and slot records consistent, commits changes without yielding, and uses server-owned prices, species data, and the caller's ready profile. Duplicate sales and purchases cannot apply the same transaction twice. The S1-04 MockStore environment guard is also resolved. By default the mock adapter is Studio-only, with a deliberate place-ID override for a prototype.

#### Required changes

1. **High — A full bag can stop progression permanently.** Incubating frees a bag space, but the mature item needs that space again to hatch. With every unlocked incubator occupied and a bag full of unhatched pods, the player cannot hatch, incubate another pod, sell a pod, or place one in a pen. This can happen before the first critter earns any coins. Reserve hatch capacity for occupied incubators when accepting bag additions, or provide a free way to discard a pod. If reserving capacity, use one shared capacity check for pod grants and pen removals and surface reserved slots to the UI when it is wired. Add a regression that fills every unlocked incubator and the bag using normal actions and proves the player can still complete a hatch. [Grant and incubation](https://github.com/jtchu22-debug/roblox-game-project/blob/d595e337430d3dfc9eb4dd1536b3adaaff104e26/src/Server/Services/EconomyService.luau#L232-L304) · [Hatch capacity check](https://github.com/jtchu22-debug/roblox-game-project/blob/d595e337430d3dfc9eb4dd1536b3adaaff104e26/src/Server/Services/EconomyService.luau#L306-L339) · [Sell restrictions](https://github.com/jtchu22-debug/roblox-game-project/blob/d595e337430d3dfc9eb4dd1536b3adaaff104e26/src/Server/Services/EconomyService.luau#L416-L430)
2. **Medium — Whole-second timestamps misattribute pen income when the rate changes.** `os.time()` and `math.floor(nowEpoch)` discard the boundary fractions before the existing remainder math can use them. A critter placed at 10.8 and removed at 11.1 seconds pays two Coins at 2 Coins/s, although the interval should carry 0.6 Coins with zero whole Coins credited. Use one fractional server clock for session initialization, each settlement before a rate change or purchase, and the periodic accrual tick. Keep incubation deadlines on their existing epoch contract. Update the accrual timestamp invariant and test a rate change on both sides of a second boundary. [Settlement](https://github.com/jtchu22-debug/roblox-game-project/blob/d595e337430d3dfc9eb4dd1536b3adaaff104e26/src/Server/Services/EconomyService.luau#L199-L229) · [Callers](https://github.com/jtchu22-debug/roblox-game-project/blob/d595e337430d3dfc9eb4dd1536b3adaaff104e26/src/Server/Services/EconomyService.luau#L497-L578) · [Existing remainder math](https://github.com/jtchu22-debug/roblox-game-project/blob/d595e337430d3dfc9eb4dd1536b3adaaff104e26/src/Shared/Util/EconomyMath.luau#L50-L92) · [Roblox server clock](https://create.roblox.com/docs/reference/engine/classes/Workspace#GetServerTimeNow)

#### S1-06 integration

The existing economy handlers enforce profile readiness and logical slot state. They have no plot, station, or proximity authorization yet. When S1-06 wires prompts, resolve the caller's assigned plot and action-specific anchor on the server and check reachability before any player-triggered mutation. Route prompt and remote entry points through the same checks so UI visibility cannot stand in for authorization. Keep the economy transition synchronous. [Current gameplay entry points](https://github.com/jtchu22-debug/roblox-game-project/blob/d595e337430d3dfc9eb4dd1536b3adaaff104e26/src/Server/Services/EconomyService.luau#L483-L566) · [Roblox client-server security guidance](https://create.roblox.com/docs/scripting/security/client-server-boundary)

**Low, non-blocking —** At the currency cap `SellCritterOnProfile` reports nominal `CoinsEarned` even when the wallet receives less. Return the actual credited delta if the UI uses this value. [Sale result](https://github.com/jtchu22-debug/roblox-game-project/blob/d595e337430d3dfc9eb4dd1536b3adaaff104e26/src/Server/Services/EconomyService.luau#L432-L441)

#### Verification

Independently built the exact commit with Rojo 7.4.4. The recorded Studio run passed all 17 suites and delivered the initial owner snapshot. The economy tests run on constructed profiles and cover regular transitions, repeated actions, some bag-limit cases, and whole-second accrual. They do not cover recovery from a full bag and occupied incubators or fractional pen-rate boundaries. No independent end-to-end player economy run was performed.

Gemini, post the fix commit and focused regression results in this review for a gate recheck.

---

### Review #006 — S1-05 fixes and S1-06 approval

**Verdict — APPROVE. Gemini can start S1-06.** Reviewed [`25ea2bd`](https://github.com/jtchu22-debug/roblox-game-project/commit/25ea2bd7b11d46581459eadfecc6b47d30059ace) on `main`. Both blockers from Review #005 are resolved.

- **Hatch capacity.** Each incubating pod reserves one bag slot. New pod grants and pen removals check the same committed capacity, so neither can take a pending hatch's slot. Incubating and hatching transfer capacity without increasing its committed total. The new regression covers two occupied incubators, eight more pods in the bag, blocked pod grants and pen removals, both hatches, and a successful sale. The owner snapshot includes `ReservedBagSlots`. [Capacity](https://github.com/jtchu22-debug/roblox-game-project/blob/25ea2bd7b11d46581459eadfecc6b47d30059ace/src/Server/Services/EconomyService.luau#L107-L133) · [Regression](https://github.com/jtchu22-debug/roblox-game-project/blob/25ea2bd7b11d46581459eadfecc6b47d30059ace/src/Server/Services/EconomyService.luau#L739-L775) · [Owner snapshot](https://github.com/jtchu22-debug/roblox-game-project/blob/25ea2bd7b11d46581459eadfecc6b47d30059ace/src/Server/Services/DataService.luau#L114-L134)
- **Passive income.** Profile creation, player actions, and periodic settlement share the fractional server clock. Pen changes settle at the old rate. The regression checks zero whole Coins and a 0.6 remainder across the second boundary, then checks that the remainder carries forward at a new rate. The cap sale also reports the credited amount. [Settlement](https://github.com/jtchu22-debug/roblox-game-project/blob/25ea2bd7b11d46581459eadfecc6b47d30059ace/src/Server/Services/EconomyService.luau#L225-L258) · [Fractional regression](https://github.com/jtchu22-debug/roblox-game-project/blob/25ea2bd7b11d46581459eadfecc6b47d30059ace/src/Server/Services/EconomyService.luau#L776-L807) · [Capped sale](https://github.com/jtchu22-debug/roblox-game-project/blob/25ea2bd7b11d46581459eadfecc6b47d30059ace/src/Server/Services/EconomyService.luau#L463-L475)

Independently built the exact commit with Rojo 7.4.4 and cross-checked the recorded Studio run for v0.1.6. All 18 suites passed, including five EconomyService suites, and the initial owner snapshot arrived with the reservation field. A separate two-player economy playthrough was not performed.

**Handoff to Gemini.** Proceed with unique plot assignment, release on leave, public revisions, and prompt wiring. Validate the caller's assigned plot and distance to the action's anchor on the server for both prompts and remotes. For S1-07, use the committed-capacity helper before consuming a meteor claim. Update the design's Bag Full hint before it becomes player-facing copy. Starting incubation now reserves the pod's slot until hatch, and placing or selling a hatched critter frees capacity. [S1-06 task](https://github.com/jtchu22-debug/roblox-game-project/blob/25ea2bd7b11d46581459eadfecc6b47d30059ace/docs/AGENT_TASKS.md#L38) · [Existing bag hint](https://github.com/jtchu22-debug/roblox-game-project/blob/25ea2bd7b11d46581459eadfecc6b47d30059ace/docs/GAME_DESIGN.md#L102)

---

### Review #007 — S1-06 plot review and S1-07 gate

**Verdict — APPROVE WITH CHANGES. Gemini can start S1-07.** Reviewed [`1727aba`](https://github.com/jtchu22-debug/roblox-game-project/commit/1727aba22b117886135020ad73ac2332137ae386) on `main`. Land the two contained changes below before calling the combined slice ready for playtesting.

The intended two-player path assigns separate plots, clears assignment and visual state on leave, and advances public revisions on ownership and slot changes. Late joiners receive a full public snapshot. Public DTOs expose the approved visual fields while owner coins and inventory stay in the owner snapshot. Prompts check the triggering player against the plot owner, and both interaction routes run through the same server-side station authorizer once wired. [Allocation and release](https://github.com/jtchu22-debug/roblox-game-project/blob/1727aba22b117886135020ad73ac2332137ae386/src/Server/Services/PlotService.luau#L440-L530) · [Public projection](https://github.com/jtchu22-debug/roblox-game-project/blob/1727aba22b117886135020ad73ac2332137ae386/src/Server/Services/PlotService.luau#L209-L257) · [Lifecycle and snapshots](https://github.com/jtchu22-debug/roblox-game-project/blob/1727aba22b117886135020ad73ac2332137ae386/src/Server/Services/PlotService.luau#L659-L688)

#### Changes

1. **Medium — Deny actions when authorization cannot be established.** Both player-facing economy handlers skip station authorization if the callback is absent. In the normal startup order it is installed by `PlotService.Start`, but the handlers should deny by default when it is missing. The station distance check also only rejects values above the cap, so a non-finite magnitude can slip through the numeric predicate. Reject missing authorizers and require a finite in-range distance before mutation. Cover both denial paths in focused server-side tests. [Economy entry points](https://github.com/jtchu22-debug/roblox-game-project/blob/1727aba22b117886135020ad73ac2332137ae386/src/Server/Services/EconomyService.luau#L521-L605) · [Station check](https://github.com/jtchu22-debug/roblox-game-project/blob/1727aba22b117886135020ad73ac2332137ae386/src/Server/Services/PlotService.luau#L171-L206) · [Roblox boundary guidance](https://create.roblox.com/docs/scripting/security/client-server-boundary)
2. **Medium — A full server leaves a ready player with no ranch.** The third player reaches the ready callback, but `NoFreePlot` only logs a warning and release never retries the unassigned player. They can remain stuck when another player leaves. Confirm the prototype place's two-player limit and add a clear rejection when no plot can be allocated. S1-07 should require an active plot before assigning starter meteors or accepting rescue actions. [Assignment](https://github.com/jtchu22-debug/roblox-game-project/blob/1727aba22b117886135020ad73ac2332137ae386/src/Server/Services/PlotService.luau#L440-L461) · [Ready and closing handlers](https://github.com/jtchu22-debug/roblox-game-project/blob/1727aba22b117886135020ad73ac2332137ae386/src/Server/Services/PlotService.luau#L671-L684) · [Two-player design](https://github.com/jtchu22-debug/roblox-game-project/blob/1727aba22b117886135020ad73ac2332137ae386/docs/GAME_DESIGN.md#L25)

**Low, non-blocking.** The incubator label prints a seconds value, but its watcher refreshes only at maturity. Show a static incubating label or render a real countdown from `MaturesAt` when the UI milestone wires it. [Label](https://github.com/jtchu22-debug/roblox-game-project/blob/1727aba22b117886135020ad73ac2332137ae386/src/Server/Services/PlotService.luau#L331-L348) · [Watcher](https://github.com/jtchu22-debug/roblox-game-project/blob/1727aba22b117886135020ad73ac2332137ae386/src/Server/Services/PlotService.luau#L690-L712)

#### Verification and S1-07 handoff

Independently built the exact commit with Rojo 7.4.4. The recorded Studio run passed all 21 suites. The two-client logs show two occupied plots, then revisions releasing both to zero. A separate recorded check returned OutOfRange. I did not independently exercise live prompt activation or a third-player join.

Proceed with the server-owned meteor lifecycle. Use the assigned plot to scope the starter node, keep starter and wild spawn pools separate, and recheck readiness, range, and unreserved bag space at the grant boundary. Consume the claim and remove its meteor only after the pod grant succeeds. Carry the plot and character lifecycle into claim cleanup.

---

### Review #008 — S1-07 meteor review and S1-08 gate

**Verdict — REJECT. Hold S1-08 until the meteor request and lifecycle contract pass the Studio gate.** Reviewed [`27baf91`](https://github.com/jtchu22-debug/roblox-game-project/commit/27baf91a71d7d78416a46cad500cfd7fce9959b1) on `main`.

The S1-06 station authorization and full-plot admission follow-ups are addressed in code and covered by server self-tests. MeteorService separates wild and starter nodes, scopes the starter to its owner, checks the ready profile, active plot, rate-limited request, range and capacity at the appropriate boundaries, and commits the pod grant before consuming the claim. [Station guard](https://github.com/jtchu22-debug/roblox-game-project/blob/27baf91a71d7d78416a46cad500cfd7fce9959b1/src/Server/Services/EconomyService.luau#L521-L529) · [Plot admission](https://github.com/jtchu22-debug/roblox-game-project/blob/27baf91a71d7d78416a46cad500cfd7fce9959b1/src/Server/Services/PlotService.luau#L525-L541) · [Meteor grant](https://github.com/jtchu22-debug/roblox-game-project/blob/27baf91a71d7d78416a46cad500cfd7fce9959b1/src/Server/Services/MeteorService.luau#L493-L524)

#### Required changes

1. **High — Neither meteor can be rescued through the normal client route.** Starter IDs concatenate an eight-character prefix with an unbraced 36-character GUID (44 characters). Wild IDs concatenate a five-character prefix (41 characters). Both inbound crack requests reject any meteor ID longer than 40 characters. Studio logs from two rescue attempts show `InvalidPayload`, and the service's direct-call tests skip the rejecting layer. Use the unprefixed GUID as the remote ID. Starter and wild type already exist as server fields and model attributes. Keep the bound, test that generated starter and wild IDs pass both inbound validators, and verify one starter and one wild rescue through the actual Studio prompt. Check that each success grants exactly one pod and removes its meteor. [Starter ID](https://github.com/jtchu22-debug/roblox-game-project/blob/27baf91a71d7d78416a46cad500cfd7fce9959b1/src/Server/Services/MeteorService.luau#L271-L300) · [Wild ID](https://github.com/jtchu22-debug/roblox-game-project/blob/27baf91a71d7d78416a46cad500cfd7fce9959b1/src/Server/Services/MeteorService.luau#L305-L337) · [Remote validation](https://github.com/jtchu22-debug/roblox-game-project/blob/27baf91a71d7d78416a46cad500cfd7fce9959b1/src/Server/Services/NetworkService.luau#L136-L154) · [Client prompt bridge](https://github.com/jtchu22-debug/roblox-game-project/blob/27baf91a71d7d78416a46cad500cfd7fce9959b1/src/Client/Controllers/CrackController.luau#L62-L91) · [Roblox GUID format](https://create.roblox.com/docs/reference/engine/classes/HttpService#GenerateGUID)
2. **Medium — The claim cleanup stream omits releases that the UI will need.** The periodic sweep checks expiry only, so walking beyond the specified 28-stud abandonment range leaves the meteor reserved until timeout. Timeout sweeps, death, respawn, and leave clear server state and re-enable the prompt without publishing the release event. A client tracking `Claimed` events can retain stale ownership. Centralize release notification with the server state change while the meteor remains active, and have the sweep enforce abandonment and character validity in addition to expiry. Keep a single despawn update when a meteor is removed. Add focused tests for release on distance, timeout, respawn, and leave, including public state and prompt recovery. [Release helper](https://github.com/jtchu22-debug/roblox-game-project/blob/27baf91a71d7d78416a46cad500cfd7fce9959b1/src/Server/Services/MeteorService.luau#L256-L269) · [Sweep](https://github.com/jtchu22-debug/roblox-game-project/blob/27baf91a71d7d78416a46cad500cfd7fce9959b1/src/Server/Services/MeteorService.luau#L350-L363) · [Remote response path](https://github.com/jtchu22-debug/roblox-game-project/blob/27baf91a71d7d78416a46cad500cfd7fce9959b1/src/Server/Services/MeteorService.luau#L556-L574) · [Character hooks](https://github.com/jtchu22-debug/roblox-game-project/blob/27baf91a71d7d78416a46cad500cfd7fce9959b1/src/Server/Services/MeteorService.luau#L587-L615) · [Plot and session cleanup](https://github.com/jtchu22-debug/roblox-game-project/blob/27baf91a71d7d78416a46cad500cfd7fce9959b1/src/Server/Services/MeteorService.luau#L699-L716) · [Approved cleanup contract](https://github.com/jtchu22-debug/roblox-game-project/blob/27baf91a71d7d78416a46cad500cfd7fce9959b1/docs/TECHNICAL_ARCHITECTURE.md#L126-L130)

#### Verification

Independently built the exact commit with Rojo 7.4.4. The recorded Studio session passed 25 self-test suites, including all three MeteorService suites, and then logged two client rescue failures. No successful end-to-end rescue or two-client lifecycle run was verified for this revision.

Gemini, post the fix commit and the focused Studio results here before moving to S1-08 client and accessibility work.

---

### Review #009 — S1-07 fixes and S1-08 approval

**Verdict — APPROVE. Gemini can start S1-08.** Reviewed [`a834616`](https://github.com/jtchu22-debug/roblox-game-project/commit/a834616194a6ebc47724a4ef1973e37307c8e798) on `main`. Both Review #008 blockers are resolved.

- **Rescue path verified.** Starter and wild meteors use unprefixed GUIDs that fit both crack request validators. The Studio client log shows successful Star-Slime and Nebula Fox prompt rescues with owner-state updates. Automated regressions assert exactly one pod and meteor removal for each rescue. [Starter and wild IDs](https://github.com/jtchu22-debug/roblox-game-project/blob/a834616194a6ebc47724a4ef1973e37307c8e798/src/Server/Services/MeteorService.luau#L301-L351) · [Rescue regressions](https://github.com/jtchu22-debug/roblox-game-project/blob/a834616194a6ebc47724a4ef1973e37307c8e798/src/Server/Services/MeteorService.luau#L925-L1000)
- **Claim recovery verified at service level.** The sweep covers distance, expiry, and character availability. The cleanup tests cover respawn and leave, confirm the prompt reopens for retained meteors, and check a single release or despawn notification as appropriate. The client clears local crack state on release and despawn. [Release and sweep](https://github.com/jtchu22-debug/roblox-game-project/blob/a834616194a6ebc47724a4ef1973e37307c8e798/src/Server/Services/MeteorService.luau#L273-L430) · [Cleanup regressions](https://github.com/jtchu22-debug/roblox-game-project/blob/a834616194a6ebc47724a4ef1973e37307c8e798/src/Server/Services/MeteorService.luau#L1054-L1153) · [Client lifecycle](https://github.com/jtchu22-debug/roblox-game-project/blob/a834616194a6ebc47724a4ef1973e37307c8e798/src/Client/Controllers/CrackController.luau#L56-L85)

Independently built the exact commit with Rojo 7.4.4. The recorded Studio session ran version 0.1.9 and passed all 26 suites, including four MeteorService suites. The recorded live client run verifies both normal prompt rescues. Live two-client abandonment and respawn remain for the existing S1-09 multiplayer pass.

Proceed with the S1-08 input, HUD, crack feedback, and accessibility tasks against the Stage 1 roster and economy. The [Stage 6 launch plan](https://github.com/jtchu22-debug/roblox-game-project/pull/9) applies later.
