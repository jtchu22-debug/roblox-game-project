# Stage 3 (`S3-04`) Persistence Failure-Injection & 6-Player Verification (`v0.3.6-s3-04-verification`)

> **Build Version:** `v0.3.6-s3-04-verification` (`src/Shared/Constants.luau`)
> **Target Published Test Place:** `Bioniccat4000's Place: 11222026_1` (`placeId: 106917003014718`, `universeId: 10778558732`, Roblox Open Cloud `serverSize: 6`)
> **Primary Suites:** `src/Server/Services/Stage3VerificationSuite.luau`, `tools/studio/RunS304LivePersistenceCheck.luau`

---

## 1. Automated Startup Verification (`55/55` Self-Test Suites PASS)

Verified in clean Play Solo boots on both the unpublished local place (`StarfallRanch_Dev.rbxl`, `MockProfileStore`) and the published 6-player test place (`106917003014718`, `Mode=LiveProfileStore`, `Store=StarfallRanch_StudioDev_v1`, `DataStoreState=Access`), with `0` script errors (plus the 3 pre-existing non-blocking `ContentId: rbxassetid://203785492` SoundController catalog asset warnings):

| Module / Suite | Count | Coverage Summary |
| :--- | :---: | :--- |
| `SharedSelfTest` | `6` | Config immutability, bounded economy math, string/nonce bounds, greybox contract |
| `NetworkService` | `3` | 9 remotes, hostile inbound fuzzing, token-bucket rate limiting & `RequestNavigate` ack |
| `DataService` | `12` | Env & `DataStoreState` guards, isolation, `ProfileStore.Mock` round-trip, load fail kick, lock theft, `BindToClose` flush, migration, `OnBeforeSave`, `OnFinalSaveResult` ownership, **Suite 12 (`S3-04`): yielding load early-leave cancellation & `< 1.0s` fast rejoin after unconfirmed ownership loss** |
| `EconomyService` | `9` | Lifecycle invariants, duplicate rejection, reserve-bag deadlock guards, fractional accrual, authorizer fail-closed, offline `MaturesAt`, leave/shutdown Coin flush, `BagCap_20` & `PenSlot_5` |
| `PlotService` | `4` | 6-plot allocation & `7th` `NoFreePlot`, Ranch + Hub station proximity/ownership, late-join 6-plot DTO & reuse revision, Hub/Ranch navigation target resolution |
| `MeteorService` | `5` | Starter scoping, wild race & nonce hijack, Ridge Frost Lure isolation & timed Astral Fall cadence, abandonment/death/leave cleanup, **Suite 5 (`S3-04`): personal Lured Frost disconnect single-`Despawn`, simultaneous wild claim release, saturated Ridge non-eviction by `TriggerAstralFallNow`** |
| `Stage1VerificationSuite` | `5` | Remote fuzzing + bucket matrix, 2P meteor adversarial, cross-plot/inventory guards, bag cap deadlock, 5-minute full progression pacing sim |
| `Stage3VerificationSuite` (`S3-04`) | `6` | See Section 3 below |
| `UIController` (Client) | `2` | Responsive HUD (`>= 320px` + `667x375`), Bag scroll/focus preservation, `RequestNavigate` server ack & `2.0s` cooldown |
| `PlotVisualController` (Client) | `3` | 6-plot late-join visuals & stale revision guard, plot reuse destruction, **Suite 3 (`S3-04`): full 6-plot × 5-pen (`30` critters + `12` pods) `<= 8`-part budget & reuse/release cleanup** |
| **Total Self-Test Suites** | **`55`** | **55 / 55 PASS** |

---

## 2. Audit Fixes Landed Before `S3-04` Sign-Off

1. **`DataService.luau` — Eliminated 5-Second Rejoin Stall After Ownership Loss:**
   In `StartProfileSessionForUserId`, waiting for a previous closing handle now checks `prevClosingSession.FinalWriteAttemptFinished` so a finished-but-unconfirmed lost-lock close never stalls a clean rejoin for `5s` (`DataService` Suite `12b` asserts `< 1.0s`).
2. **`MeteorService.luau` — Eliminated Redundant `ClaimReleased` on Personal Lured Frost Disconnect:**
   Removed the premature `MeteorService.ReleaseClaimForUserId(userId)` inside `despawnLuredMeteorForUserId` because `removeMeteorInternal(luredUid)` already clears an active claim on that lured meteor (`MeteorService` Suite `5a`/`5b` verify a single `Despawn` on personal lured disconnect and intact `ClaimReleased` on shared wild meteors). Also made `PlotService.OnBeforeNavigate` registration idempotent in both `MeteorService:Init()` and `MeteorService:Start()`.
3. **`Stage3VerificationSuite.luau` — Separate Command-Bar Cache Hook Initialization:**
   `RunLiveApiPersistenceCheck` calls idempotent `EconomyService:Init()` so running from Studio Command Bar / `execute_luau` registers `EconomyService`'s `OnBeforeSave` final Coin settlement hook on that module cache.

---

## 3. `Stage3VerificationSuite` (`6/6` Suites PASS)

1. **Suite 1 — 6-Player `ProfileStore.Mock` Admission, 7th-Player `NoFreePlot` Save Preservation & Reuse:** Opens `u1..u6` on isolated `ProfileStore.Mock`, assigns `Plot_1..Plot_6` + starter nodes, admits `u7` (pre-saved with `615 Coins`, `Pen_1 = NebulaFox`, `Incubator_1 = CinderPup`), asserts `NoFreePlot` ends `u7` session cleanly (`WaitForUserFinalSave == true`) without data loss, releases `Plot_3`, then admits `u7` onto `Plot_3` with incremented `PlotRevision` and intact `615 Coins` + critters + timer.
2. **Suite 2 — Persistence Failure-Injection & 6-Player Concurrent `BindToClose` Flush:** Tests both `nil` and throwing `StartSessionAsync` fail-closed kicks without blank overwrite, external `ForceLoadSession` lock theft on `u2` while online (`OnKick` + final Coin settlement + `< 1.0s` rejoin), and concurrent `FlushActiveProfileSessions(4)` across all 6 active players followed by reload verification of settled Coins, Revisions, `BagCap_20`, `PenSlot_5`, `FeedLevel`, `Radiant`, and incubating `MaturesAt`.
3. **Suite 3 — Offline `MaturesAt` Clock Boundaries (`-1s`, `0s`, `+12h`) & Zero Offline Coin Payout:** Verifies `0` offline Coins accrued on login, `NotMature` at `t0 + 44` (`-1s`), exact `NebulaFox` hatch at `t0 + 45` while `Incubator_2` remains `NotMature`, and `+12h` reload (`0` extra Coins + `SolarGolem` hatch + valid invariants).
4. **Suite 4 — 6-Player Cross-Plot & Hub Station Authorization Matrix:** Asserts own-plot and Hub station authorization across `Plot_1..Plot_6`, rejects all `30` cross-plot pairs with `OutOfRange`, blocks Ranch-to-Hub and Hub-to-Ranch range spoofs, and blocks unassigned `u7` (`NoAssignedPlot`).
5. **Suite 5 — 6-Player Crater Race, `AttemptNonce` Hijack, Navigation Claim Cancel & Lure Saturation:** Rejects all `30` cross-owner starter attempts (`NotStarterOwner`), tests 6-player wild `Astral` claim race + nonce hijack rejection, verifies `PlotService.ExecuteNavigationForUserId(..., "Hub", ...)` cancels active meteor claim via `OnBeforeNavigate`, and tests 4-player North Ridge Frost Lure saturation + `u1` disconnect recovery for `u5`.
6. **Suite 6 — 6-Player Independent Rate Buckets & 30-Critter `PublicPlotDTO` Audit:** Saturates all 6 inbound remotes on `u1` (and rejects hostile payloads) while confirming `u2..u6` keep full independent token buckets, then audits `BuildAllPublicPlotDTOs()` across 6 occupied plots × 5 pens (`30` active critters, zero private fields leaked).

---

## 4. Two-Session Live API-Backed Persistence Output (`106917003014718`)

Executed via `Stage3VerificationSuite.RunLiveApiPersistenceCheck` across **two separate Play Solo server sessions** against `StarfallRanch_StudioDev_v1_Smoke` (`PlaceId=106917003014718`, `GameId=10778558732`, `Mode=LiveProfileStore`, `DataStoreState=Access`, both sessions passed all `55/55` startup suites with `0` script errors):

- **Session 1 (`Write` + 2-profile concurrent `FlushActiveProfileSessions(10)`):**
  `[S304LivePersistenceCheck] PASS: Write phase confirmed (StarfallRanch_StudioDev_v1_Smoke, Version=0.3.6-s3-04-verification, PlaceId=106917003014718, GameId=10778558732, KeyA=Player_-919901, SettledCoinsA=439, RevA=3, KeyB=Player_-919902, SettledCoinsB=627, RevB=3, PlantedAt=1795389892, MaturesAtA=1795389937, MaturesAtB=1795389907).`
- **Fresh Session 2 (`Verify` + `MaturesAt` hatch boundary checks + cleanup):**
  `[S304LivePersistenceCheck] PASS: Live Dev DataStore S3-04 Verify verified (StarfallRanch_StudioDev_v1_Smoke, Version=0.3.6-s3-04-verification, PlaceId=106917003014718, GameId=10778558732, SettledCoinsA=439, RevA=3, SettledCoinsB=627, RevB=3, BagCap_20=true, PenSlot_5=true, Pen1A=CinderPup(FeedLevel=1), Pen5A=NebulaFox(Radiant), Pen1B=SolarGolem, PlantedAtA=1795389892, MaturesAtA=1795389937, MaturesAtB=1795389907, EarlyHatchReason=NotMature, Late12hHatch=FrostBeetle).`

Exact cross-session match confirmed:
- Player A (`Player_-919901`): `SettledCoinsA = 439 == 439`, `RevA = 3 == 3`, `BagCap_20 = true`, `PenSlot_5 = true`, `Pen_1 = CinderPup (FeedLevel=1)`, `Pen_5 = NebulaFox (Radiant)`, `Incubator_1 = FrostBeetle` (`PlantedAt = 1795389892`, `MaturesAt = 1795389937`), `-1s` hatch = `NotMature`, `+12h` hatch = `FrostBeetle`, `0` offline Coins accrued.
- Player B (`Player_-919902`): `SettledCoinsB = 627 == 627`, `RevB = 3 == 3`, `Pen_1 = SolarGolem`, `Incubator_1 = StarSlime` (`MaturesAt = 1795389907`).

---

## 5. Manual 6-Client Live Server Verification Checklist

*(Studio MCP automation runs 1-client Play Solo sessions and server/client unit + integration suites against all 6 plots and simulated 6–7 player states; live multi-client runtime tests below are for optional Human Lead / multi-device verification in Studio **Local Server (6 Players)** or a private published server on `106917003014718` (`serverSize: 6`).)*

- [ ] **6 Unique Plots & 7th Excess Rejection:** Join with 6 clients -> `Plot_1..Plot_6` assign cleanly (`PlotVisualController` shows `6/6 occupied`); 7th joiner (Studio 7-player Local Server) receives clean `NoFreePlot` kick without affecting `Plot_1..Plot_6`.
- [ ] **Mid-Crack Navigation Cancellation Across 2+ Clients:** Player 1 starts cracking a wild meteor and presses `Hub` HUD button mid-crack -> claim releases cleanly so Player 2 can immediately claim and crack the same meteor.
- [ ] **4-Player North Ridge Frost Lure Saturation:** Players 1–4 summon 4 personal Frost Lures on North Ridge while Player 5 tries -> Player 5 keeps their 75 Coins until Player 1 rescues or leaves.
- [ ] **Late Join & Plot Reuse Visual Purge:** Player 3 places critters/pods, leaves, and Player 7 joins onto `Plot_3` -> all clients show fresh `Plot_3` with zero leftover critter/pod models from Player 3.
