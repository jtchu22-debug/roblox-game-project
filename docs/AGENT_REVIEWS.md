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
