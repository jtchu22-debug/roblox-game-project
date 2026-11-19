# Stage 2 (`S2-01`) Uncoached Discovery Playtest Kit

> **Applies To:** `v0.2.1-s2-playtest-live` (`Stage 2: Discovery Playtest Gate — R-009`, allowlisted for private `PlaceId 137485500524067`)  
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
- **Hold Status:** All `src/` edits are paused on `v0.2.1-s2-playtest-live` (`8ce1e25`) pending **ChatGPT's independent Stage 2 assessment** in [AGENT_REVIEWS.md](./AGENT_REVIEWS.md) and the Human Lead's final **Iterate vs. Pivot** call.
