# Stage 2 (`S2-01`) Uncoached Discovery Playtest Kit

> **Applies To:** `v0.2.4-s2c-astral-fall` (`Stage 2C: Timed Astral Fall Event, Crater Routes & Mobile Declutter`, allowlisted for private `PlaceId 137485500524067`)  
> **Goal:** Observe **5–10 consenting testers** play *Starfall Ranch* uncoached for 5–15 minutes to decide whether to **Go** to Stage 3 (`ProfileStore` + 6 plots), **Iterate** on onboarding/Crater feel, or **Pivot** before writing persistence or Blender art.  
> **Privacy Rule:** Collect **zero personal data** (no real names, Roblox usernames, UserIds, emails, or ages). Use anonymous tester codes `T-01` through `T-10`.

---

## 1. Private Playtest Setup Checklist (Choose Option A or Option B)

### Option A: Private Published Roblox Test Place *(Recommended for Mobile & Desktop Testers)*
> **Why:** Stage 1–2 deliberately use in-memory `MockStore`. As a safety check (`DataService.CanUseMockStoreInEnvironment`), published Roblox servers block `MockStore` unless `Constants.ALLOW_PUBLISHED_PROTOTYPE_PLACE_ID` matches that exact private `PlaceId`. Also, both `ServerInit` and `ClientInit` gate `RUN_SELF_TESTS` behind `RunService:IsStudio()`, so playtesters on live private servers will not see self-test flashes on spawn.

1. **Confirm Studio passes first:** Open the place in Roblox Studio (`rojo serve` synced) and verify Play Solo (`F5`) prints **33/33 `PASS` suites** (`31` Server/Shared + `2` Client) with `0` script errors.
2. **Publish as a Private Place:** In Studio, choose **File -> Publish to Roblox As...** -> create a **new private experience** (do **not** publish publicly).
3. **Copy your numeric `PlaceId`:** From Creator Dashboard / Game Settings -> Basic Info / URL, copy the Place ID number (e.g., `1234567890`).
4. **Lock server capacity to `2` Players:** In Roblox Studio **Game Settings -> Places** (or Creator Dashboard -> Places -> Configure), set **Maximum Player Count = `2`**.
   - *Important:* Stage 1–2 intentionally have `MAX_PLOTS_PROTOTYPE = 2` (`Plot_1` and `Plot_2`). Leaving Max Players higher than `2` will cause player #3 to be kicked with `NoFreePlot`!
5. **Restrict Permissions:** Keep Experience visibility **Private** and grant Play access **only** to your explicit tester group/friends (never public Discovery).
6. **Enable MockStore for that exact `PlaceId`:** [Constants.luau](../src/Shared/Constants.luau#L12) is already configured with `ALLOW_PUBLISHED_PROTOTYPE_PLACE_ID = 137485500524067` for the private Stage 2 place (`Bioniccat4000's Place: 11192026_1`). Verify it matches your private `PlaceId`, rebuild (`powershell -ExecutionPolicy Bypass -File ".\tools\build-place.ps1"`), ensure Rojo is connected in Studio (**Plugins -> Rojo -> Connect**), and republish (**File -> Publish to Roblox (`Alt+P`)**) with **Maximum Player Count = `2`**.
7. **Run a 60-Second Live Smoke Test Before Inviting Testers:**
   - Join your private published experience from the Roblox app (not Studio).
   - Press **`F9`** -> **Server** log -> confirm `[DataService] Initialized in Stage 1 MockStore mode (DesignatedPrototypePlace).` and confirm `RUN_SELF_TESTS` does **not** run on the live server/client (zero flashing Bag rows on join).
   - Pick up/crack the glowing Starter Meteor once to verify normal spawn -> Starter rescue -> UI behavior.

### Option B: In-Person / Screen-Share Studio Session *(No Publishing Required)*
- Run Play Solo (`F5`) or **2-Player Local Server** directly inside Roblox Studio.
- Because `RunService:IsStudio()` is `true`, `MockStore` works immediately with `ALLOW_PUBLISHED_PROTOTYPE_PLACE_ID = 0`.
- Let each new tester start in a fresh Play session (so `MockStore` resets cleanly to `0 Coins`, `1` Starter Meteor, and `0` unlocked upgrades).

---

## 2. Consent, Zero-PII & Strict Zero-Coaching Protocol (`R-009`)

1. **Consent & Zero Personal Data:**
   - Recruit **5–10 testers** (ideally mixing **mobile/touch** and **desktop/gamepad** users).
   - Obtain clear voluntary consent before observing; obtain parent/guardian consent if any tester is a minor.
   - Do **not** record real names, Roblox usernames, `UserId`s, voices/video containing PII, emails, or birthdates anywhere in the repo. Track rows strictly by anonymous ID (`T-01`..`T-10`).
2. **Exact Verbatim Opening Prompt:**
   > *"You're trying an early prototype called Starfall Ranch for about 5 to 10 minutes. Everything resets when you leave, so nothing here is permanent. Please play however feels natural to you and think out loud as you go—tell me what you notice, what you expect to happen, or anything that feels confusing. I can't give hints while you play so we can see what the game teaches on its own."*
3. **Strict Zero-Coaching Rule:**
   - Do **not** point at buttons, explain controls, say "walk to the meteor", or explain "Bag", "Incubator", "Pen", "Quick Burst", or "Sell Stand".
   - If a tester asks *"What do I do?"*, reply warmly: **"Try whatever makes sense to you—I want to see what the game communicates first."**
   - Only intervene if a **hard crash or soft-lock bug** blocks all input; mark `Uncoached? = Bug-Blocked` and log the exact repro step so the metrics stay honest.

---

## 3. Ready-to-Fill Observation & Timing Sheet (`T-01`..`T-10`)

Start your stopwatch (`0:00`) the moment the player spawns and HUD finishes fading in:
- **First Reward (s):** Seconds from spawn until they finish cracking their first meteor (`Pod` enters Bag).
- **First Hatch & Pen (s):** Seconds from spawn until their first Critter finishes incubating and is placed in **Pen #1** (or deliberately sold—note which they chose!).
- **2nd+ Rescue <= 5m?:** Did they voluntarily initiate a **second or third** meteor rescue in the central Crater within 5 minutes (`Yes` / `No`)?

| Tester ID | Device / Input | Mode (`1P`/`2P`) | First Reward (`s`) | First Hatch & Pen (`s`) | 2nd+ Rescue `<= 5m`? | Upgrades Bought (`0–3`) | Uncoached? (`Yes`/`Bug-Blocked`) | Keep vs. Sell, Confusion Points & Verbatim Quotes |
| :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| `T-01` | | | | | | | | |
| `T-02` | | | | | | | | |
| `T-03` | | | | | | | | |
| `T-04` | | | | | | | | |
| `T-05` | | | | | | | | |
| `T-06` | | | | | | | | |
| `T-07` | | | | | | | | |
| `T-08` | | | | | | | | |
| `T-09` | | | | | | | | |
| `T-10` | | | | | | | | |

### Short 3-Question Post-Session Debrief *(Ask ONLY After 5–10 Min Ends)*
1. *"In your own words, what is the game about and how did you get stronger?"*
2. *"Which meteor or station felt best, and which part felt slow or confusing?"*
3. *"Would you come back tomorrow to fill more pens and discover new critters? Why or why not?"*

---

## 4. Stage 2 Decision Rollup (`Go / Iterate / Pivot` — `R-009`)

Once 5–10 uncoached runs are recorded above, fill in these observed directional summary metrics:

| Directional Target (`R-009`) | Stage 2 Benchmark | Observed Result | Pass? (`Yes`/`No`) |
| :--- | :--- | :--- | :---: |
| Completed Uncoached Sessions | `5–10` testers | Cohort-level summary reported (exact `N` not supplied) | `Unconfirmed` |
| **Median First Reward** | `<= 45s` | Not individually timed; all testers incubated `5+` eggs and bought all 3 upgrades within `2–3` min | `Inferred Fast (Untimed)` |
| **First Hatch & Pen <= 90s** | `>= 80%` of testers | Not individually timed; all testers incubated `5+` eggs within `2–3` min and found gameplay *"simple enough for a child to understand"* | `Inferred Pass (Untimed)` |
| **Voluntary 2nd+ Rescue <= 5m** | `>= 70%` of testers | All testers incubated `5+` eggs within `2–3` min | `Pass` |
| **Qualitative Engagement** | Testers understand loop uncoached, care about Ember/Frost/Astral choices, and show/visit ranches | **FAILED** — *"game is really easy to progress and lacks content"*; *"coins feel rather useless"* (only upgrades incubators/pen slots); *"All meteors felt the same, nothing was special or stood out"*; *"probably won't come back as there isn't much content"* | `Fail` |

### Decision Rule
- **GO -> Unlock Stage 3 (`S3-01`–`S3-04`):** Directional hypotheses hold (testers understand the loop uncoached, hit first rewards quickly, and actively return to the Crater rather than idling at Pens). Next step: vendor pinned `ProfileStore`, wire offline incubation (`MaturesAt`), and scale `2 -> 6` plots.
- **ITERATE (Targeted Loop/Onboarding Fix):** Testers enjoy critters/theme *but* repeatedly stall on UI legibility, Gold Crack timing clarity, Keep-vs-Sell discovery, or pacing—make one focused onboarding/pacing pass and re-test 3–5 fresh testers.
- **PIVOT -> Select Backup Concept (*Relic Raiders* / *Potion Pop!*):** Testers find the core meteor-crack -> ranch-keep loop flat even after understanding controls—pivot cleanly before investing weeks in `ProfileStore` or custom Blender assets (`R-006`).

### Recording the Decision
Share the filled Observation & Timing Sheet and Post-Session Debrief notes back in this conversation so **Gemini + ChatGPT** can analyze the results and ChatGPT can record the formal Stage 2 verdict (`GO` / `ITERATE` / `PIVOT`) in [AGENT_REVIEWS.md](./AGENT_REVIEWS.md).

---

## 5. Recorded Stage 2 Playtest Summary — Round 1 (`v0.2.1-s2-playtest-live`, 2026-11-18)

> **Data Completeness Note:** The Human Project Lead provided a qualitative & cohort-level summary of Round 1 live playtest feedback without an exact tester count (`N`) or per-tester timestamps (`T-01`..`T-10` remain blank above).

### 5.1 Human Lead Cohort Readout
- **Onboarding & Clarity (Positive):** Gameplay was reported as *"simple enough for a child to understand"* — all testers understood how to rescue meteors, incubate eggs/pods, and buy upgrades uncoached.
- **Progression Speed & Content Depth (Fail):** All testers bought **all upgrades** and incubated **`5+` eggs/pods within 2–3 minutes**. General consensus was that progression is far too easy and lacks content.
- **Coin Utility (Fail):** Coins felt *"rather useless"* once players unlocked the two extra Pen/Incubator upgrades because there is no other ongoing use for Coins.
- **Meteor Differentiation (Fail):** *"All meteors felt the same, nothing was special or stood out."*
- **Return Retention Intent (Fail):** Testers reported they *"probably won't come back as there isn't much content."*

### 5.2 Code-Level Diagnosis (Mapped to Round 1 Build `8ce1e25`)
1. **`530`-Coin Content Ceiling ([UpgradeConfig.luau](../src/Shared/Config/UpgradeConfig.luau#L13-L39)):** Total progression across all 3 upgrades (`PenSlot_2 = 60`, `Incubator_2 = 150`, `PenSlot_3 = 320`) equals only `530 Coins`. Selling `3` critters or idling briefly completes 100% of ranch upgrades within `2–3` minutes.
2. **Un-gated `Astral` Spawns ([MeteorService.luau](../src/Server/Services/MeteorService.luau#L49-L53)) & High Payouts ([CritterConfig.luau](../src/Shared/Config/CritterConfig.luau#L35-L45)):** `Astral` meteors (`15%` weight) spawn immediately from `t = 0` with no tool/progression gate and yield `SolarGolem` (`180 Coins` sell / `7 Coins/s`), accelerating testers through the `530`-Coin cap.
3. **Identical Meteor Interaction ([MeteorService.luau](../src/Server/Services/MeteorService.luau#L123-L145) & [CrackController.luau](../src/Client/Controllers/CrackController.luau#L88-L115)):** Ember, Frost, and Astral rocks sit at fixed Crater nodes and share the exact same single-tier `1.2s` crack bar — zero live meteor shower / sky-fall impact spectacle, zero tier-specific mechanics or special rare/event meteors, and zero meaningful gameplay difference between traits.
4. **No Ongoing Coin Sinks:** Zero tool/cracker upgrades, critter feeding/leveling sinks, meteor lures/scans, or deeper species goals (`3` total species; `Radiant` variant has `+0` stats).

### 5.3 Preliminary Gate Read & Handoff Status
- **Gemini Preliminary Gate Read:** **NO-GO for Stage 3 (`ProfileStore` & 6-Plot Alpha).** While Stage 1 UI/controls/clarity passed uncoached, Round 1 failed retention, progression depth, Coin utility, and core Crater excitement. Advancing to `ProfileStore` now would lock in a 3-minute loop that testers would not return to.
- **Decision Required Before Any `src/` Edits:** **ITERATE** (*Starfall Ranch* Stage 2B loop/depth pass, still on `MockStore`) vs. **PIVOT** to *Relic Raiders* or *Potion Pop!* ([GAME_CONCEPTS.md](./GAME_CONCEPTS.md)).
- **Human Lead's Preliminary Priority (if Iterating):** Add **New Coin Sinks** (Cracker/Pickaxe Tiers, Critter Level-Ups/Feeding, Meteor Lures) — paired with the Stage 2 findings on identical meteors and 2–3 min ceiling.
- **Hold Status:** Round 1 concluded with ChatGPT's Review #012 (`ITERATE` verdict) and Human Lead approval of the Stage 2B **Star Cracker + 2-Beat Astral Meteor + Capped Feed** pass (`v0.2.2-s2b-iterate`).

---

## 6. Stage 2B Round 2 Playtest Protocol (`v0.2.3-s2b-expanded`, 3–5 Fresh Testers)

### 6.1 What Changed for Round 2 (`Review #012` + [STARFALL_RANCH_GAMEPLAY_PLAN.md](./STARFALL_RANCH_GAMEPLAY_PLAN.md))
1. **6 Species & Field Guide (`Discovered: X / 6`):** *Ember* (*StarSlime* `2/s|40`, *CinderPup* `3/s|70`), *Frost* (*FrostBeetle* `5/s|110`, *NebulaFox* `8/s|175`), and *Astral* (*SolarGolem* `13/s|290`, *CometOwl* `20/s|450`) with Bag Field Guide clues for undiscovered species.
2. **2 Purchasable Cracker Tiers:** `FrostCracker` (`120 Coins`) unlocks Frost Ridge meteors & Frost Lures; `StarCracker` (`550 Coins`, requires `FrostCracker`) unlocks Astral meteors.
3. **2 Crater Regions & 3 Distinct Encounters:** Ember Basin (`1.2s` Standard Quick-Burst), Frost Ridge (`1.5s` 2-point sequential Fracture `[1/2] -> [2/2]`), and Astral Crater (`1.9s` Pulse Surge + sky-streak arrival beacon/toast), all accessible & `Reduced Motion`-safe.
4. **Ongoing Coin Sinks:** `Frost Lure` (`75 Coins`, personal `LuredByUserId` Frost meteor on Ridge — requires `FrostCracker`) on Ranch Gate `LureStand` & Bag UI, plus capped `Critter Feeding` (`45 Coins`, `+2 Coins/s`, `+20` sell bonus `< 45`, `1.15x` growth & gold `★`).
5. **10–15 Min Progression & Follow-up Goal:** `PenSlot_2 (60)` -> `FrostCracker (120)` -> `Incubator_2 (190)` -> `PenSlot_3 (360, req PenSlot_2)` -> `StarCracker (550, req FrostCracker)` -> `PenSlot_4 (1,150, req PenSlot_3, Gold Ranch Arch)`. Run a 10–15 min solo pre-check before inviting testers.

### 6.2 Round 2 Per-Tester Timing & Choice Log (`R2-01`..`R2-03`, `v0.2.3-s2b-expanded` / `1da9899`)
> **Data Completeness Note:** Individual timestamps (`First Reward`, `First Hatch & Pen`, `1P`/`2P` mode) and exact purchase orders were not individually timed in the cohort readout; fields below reflect only directly reported observations (`< 5 min` completion across all `N = 3` testers).

| Tester ID | Device / Input | Mode (`1P`/`2P`) | First Reward (`s`) | First Hatch & Pen (`s`) | Voluntary 2nd+ Rescue `<= 5m`? | Purchases Made (`Feed` / `FrostLure` / `Crackers` / `Pads`) | Discovered (`X/6`), Chased Frost/Astral & Named Next Goal |
| :---: | :--- | :---: | :---: | :---: | :---: | :--- | :--- |
| `R2-01` | PC | `Unconfirmed` | `Not individually timed (< 5m)` | `Not individually timed (< 5m)` | `Yes (< 5m)` | Completed all `6` upgrades (`2,430` total Coins) `< 5m` | `6/6` critters `< 5m`; recognized max upgrades + rarest critter goal; wanted harder rarity, lower spawn rates & more excitement |
| `R2-02` | PC | `Unconfirmed` | `Not individually timed (< 5m)` | `Not individually timed (< 5m)` | `Yes (< 5m)` | Completed all `6` upgrades (`2,430` total Coins) `< 5m` | `6/6` critters `< 5m`; recognized max upgrades + rarest critter goal; wanted harder rarity, lower spawn rates & more excitement |
| `R2-03` | Mobile (Touch) | `Unconfirmed` | `Not individually timed (< 5m)` | `Not individually timed (< 5m)` | `Yes (< 5m)` | Completed all `6` upgrades (`2,430` total Coins) `< 5m` | `6/6` critters `< 5m`; screen felt cluttered with text & push/interact buttons; wording made world feel small & cluttered |

### 6.3 Round 2 Rollup (`GO` vs. `PIVOT` — Review #012 / Awaiting Review #014)
- **Sample Count (`N / Denominator`):** `3 / 3–5` (`2` PC, `1` Mobile)
- **Median First Reward (`<= 45s`):** `Not individually timed` (all `3 / 3` testers progressed through all upgrades & critters in `< 5m`)
- **First Hatch & Pen (`<= 90s >= 80%`):** `Not individually timed` (all `3 / 3` testers hatched/collected all `6` species in `< 5m`)
- **Voluntary 2nd+ Rescue (`<= 5m >= 70%`):** `3 / 3 (100%)` — all testers repeatedly rescued meteors to complete all `6` critters & all `6` upgrades inside `5 min`
- **Clear Purpose / Next-Goal Clarity (Improved vs. Round 1):** **Positive** — testers understood that the goal is reaching max upgrades and chasing the rarest critter
- **Pacing, Rarity, Excitement & Mobile UX:** **FAIL / Blocker (`Stage 3` stays on hold)** — `< 5 min` completion for both upgrades and critters; rare meteors and pets feel too easy/common; lacks playful excitement (*Steal an Egg* / *Throw Food for Animals* energy); mobile screen and ranch world feel cramped and cluttered with text and interact prompts

### 6.4 Code-Level Diagnosis (Mapped to Build `1da9899`)
1. **Always-On Rare Spawns & Fast Respawn ([MeteorService.luau](../src/Server/Services/MeteorService.luau#L51-L55), [`#L938-L948`](../src/Server/Services/MeteorService.luau#L938-L948); [Constants.luau](../src/Shared/Constants.luau#L24)):** `populateWildMeteorsUpToCap` forces `>= 1` `Frost` and `>= 1` `Astral` meteor onto the map whenever the Crater populates, `WILD_TRAIT_WEIGHTS` rolls `Astral = 25%` / `Frost = 30%`, and wild nodes respawn every `WILD_METEOR_RESPAWN_SECONDS = 6`.
2. **High Rare-Critter Odds & Payout Compression ([MeteorConfig.luau](../src/Shared/Config/MeteorConfig.luau#L58-L65); [CritterConfig.luau](../src/Shared/Config/CritterConfig.luau#L52-L90)):** `Astral` meteors drop Legendary `CometOwl` at `30%` (`450 Coins` / `20/s`) and Epic `SolarGolem` at `55%` (`290 Coins` / `13/s`), while `Frost` drops `NebulaFox` at `45%` (`175 Coins` / `8/s`), compressing all `6` upgrades (`2,430` Coins total) and `6/6` Field Guide completion into `< 5` minutes.
3. **Mobile & World Text/Button Clutter ([GreyboxBuilder.luau](../src/Shared/Util/GreyboxBuilder.luau#L75-L100), [`#L215-L260`](../src/Shared/Util/GreyboxBuilder.luau#L215-L260); [PlotService.luau](../src/Server/Services/PlotService.luau#L94-L108); [Constants.luau](../src/Shared/Constants.luau#L22); [UIController.luau](../src/Client/Controllers/UIController.luau#L165-L235), [`#L1645-L1657`](../src/Client/Controllers/UIController.luau#L1645-L1657)):** Each plot spawns `15` `180x44` floating `BillboardGui` labels (`MaxDistance = 90`), `6` `UpgradePad_*` cylinders spaced only `7–8` studs apart (`PadOffsetX = -18, -10, -2, 6, 14, 21`) with `PROMPT_ACTIVATION_DISTANCE = 12` and `RequiresLineOfSight = false` (causing `3–4` stacked touch prompts simultaneously on phone screens), plus the stacked mobile top HUD and permanent full-width bottom `HintText` banner.
4. **Tactile Excitement / Toy-Factor Gap:** `FeedCritter` and `UseFrostLure` trigger from menu buttons or static `ProximityPrompt` taps rather than physical/playful world interactions (such as throwing food directly to critters in the pen or racing/carrying a contested rare Star-Egg drop before it expires).

### 6.5 Handoff Status
- **Stage 3 Status:** Remains **ON HOLD** (`MockStore` preserved; Round 2 + ChatGPT **Review #013 (`d9036b4`)** + **Review #014 (`c604289`)** drove Stage 2C `v0.2.4-s2c-astral-fall`).
- **ChatGPT Reviews #013–#014 (`d9036b4`, `c604289`):** Flagged missing spatial separation between the two Crater routes, Frost Lure `BagFull` pre-check / error feedback / landing visibility, always-on Astral availability/payout compression, and mobile text/prompt clutter — all addressed in **Section 7 / Stage 2C**.

---

## 7. Stage 2C Round 3 Playtest Protocol (`v0.2.4-s2c-astral-fall`, 3–5 Fresh Testers)

### 7.1 What Changed for Round 3 (Round 2 Feedback + Reviews #013 & #014)
1. **Astral Worth Chasing (`Astral Fall` Timed Event + Tuned Rarity/Payouts):** Removed automatic `Astral` refill (`0` on startup; wild spawns are Ember `72%` / Frost `28%` with `10s` node respawn). Every `75s` (first event `45s` after boot), a visible `3s` falling Astral meteor announces on North Frost Ridge and stays active for `55s`. `CometOwl` drop rate lowered to `10%` (`18/s | 400`); late-game payouts & upgrade costs tuned (`60 / 150 / 260 / 500 / 850 / 1,850`; `3,670` total upgrades) while preserving the `15s` starter `StarSlime` hatch.
2. **Two Marked Crater Routes & Decluttered Map / Mobile UI:** Split Crater into **South Ember Basin** (`MeteorNode_1..3`) and ramp-accessed **North Frost Ridge** (`MeteorNode_4..6`) with route markers; compacted world labels (`130x28`, `24` studs) shown contextually only when actionable; shrank prompt range (`12 -> 7.5` studs) and spaced upgrade pads into 2 rows (`>= 8` studs apart); enabled single-row phone HUD (`>= 360px` wide) and auto-hid `BottomHintBar` once a starter critter is placed in Pen #1.
3. **Frost Lure Completeness (`Review #013`):** Added server + client committed `BagFull` pre-check before spawning/charging (`75 Coins`), owner `LureFailed` error toasts for every failure mode, a visible cyan `LureBeacon` + `8s` guide beam showing where the Frost Lure landed strictly on North Frost Ridge. Keep the same `6` critters.

### 7.2 Round 3 Per-Tester Timing & Choice Log (`R3-01`..`R3-05`)
Observe **3–5 fresh, consenting, uncoached testers** across **mobile** and **desktop**:

| Tester ID | Device / Input | Mode (`1P`/`2P`) | First Reward (`s`) | First Hatch & Pen (`s`) | Chased Astral Fall / Used Frost Lure? | Readability on Mobile / Crater Routes Clear? | Maxed Upgrades / Critters Under 5m? & Reason to Return (`GO` vs. `PIVOT`) |
| :---: | :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| `R3-01` | | | | | | | |
| `R3-02` | | | | | | | |
| `R3-03` | | | | | | | |
| `R3-04` | | | | | | | |
| `R3-05` | | | | | | | |

### 7.3 Round 3 Gate (`GO -> Stage 3` vs. `PIVOT`)
- **Sample Count (`N / Denominator`):** `___ / 3–5`
- **Median First Reward (`<= 45s`) & First Hatch & Pen (`<= 90s >= 80%`):** `___s` / `___%`
- **Chased Timed Astral Fall + Mobile Readability:** `___ / N` noticed/chased the falling Astral meteor & found mobile prompts/routes clear
- **Decision Rule:** If fresh testers find and play the redesigned Astral encounter and still find the loop flat -> **PIVOT** (`Relic Raiders` / `Potion Pop!`). If they voluntarily chase Astral Fall, value rarer drops/pacing, and have a concrete reason to keep playing -> evaluate **GO -> Stage 3** (`ProfileStore` & `6` plots) in [AGENT_REVIEWS.md](./AGENT_REVIEWS.md).
