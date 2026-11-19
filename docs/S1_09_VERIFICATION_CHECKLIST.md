# Stage 1 (`S1-09`) Verification Checklist & Test Script

> **Applies To:** `v0.1.11-s1-09` (`S1-08` Review #010 UI Fixes + `S1-09` Final Gate Before Stage 2)  
> **Instructions:** Run each section below inside Roblox Studio (synced via Rojo `v7.4.4`) and report observed results so they can be recorded in `docs/AGENT_REVIEWS.md`.

---

## 1. Automated Startup Verification (Solo Play `F5`)

- [ ] **Rojo Sync & Startup (`ServerInit` + `ClientInit`):**
  - Open **View -> Output** and press **Play (`F5`)**.
  - Confirm **31 Server/Shared suites PASS** (including `All 5 Stage1VerificationSuite test suites passed.`).
  - Confirm **2 Client suites PASS** (`All 2 UIController client test suites passed.`).
  - Total expected `PASS` suites on boot: **33** with zero errors or script analysis warnings.

---

## 2. Review #010 UI Regression Checks

### 2A. Narrow Phone Safe Width (`>= 320px`) — Zero Overlap
- [ ] Switch to **Test -> Device Emulator** and choose a narrow phone resolution (or test custom narrow width down to `320px` safe width in portrait AND a standard phone landscape width like `iPhone` / `667x375`).
- [ ] Verify the Top Resource Bar (`Coins | +Coins/s | Bag`) stacks cleanly **above** the Action Tray (`Bag | Settings`) when `< 440px` wide, and sits **side-by-side** with spacing when `>= 440px` wide.
- [ ] Verify `Coins`, `Bag`, `Settings`, contextual bottom hint, and the **Crack Feel Bar** (`CrackFeelFrame`) never overlap or clip off-screen.
- [ ] Verify **Toast** banners and **Settings** popover open directly beneath the stacked action tray without covering `Coins`.

### 2B. Gamepad Focus & Scroll Preservation Across Passive Coin Ticks
- [ ] Place at least 1 hatched Critter in **Pen #1** so Coins tick up every 1 second.
- [ ] Press **`B`** (or **`ButtonY`** on a Gamepad) to open **Ranch Bag & Keep-vs-Sell**.
- [ ] Scroll down to **Ranch Upgrades** (`PenSlot_2`) or a lower critter row and highlight a lower button (using Gamepad D-Pad, or test with Gamepad mode active).
- [ ] Wait **5+ seconds** while Coins increase (`+2/s` ticks firing `SyncOwnerState`):
  - Confirm the Bag list does **not** snap back to scroll `Y = 0`.
  - Confirm the highlighted/selected button on the lower row does **not** jump back to the first row.
  - When Coins cross `60`, confirm `Buy (60)` turns Meadow Mint **green in place**.
- [ ] Tap **`Sell`** once to switch to **`Confirm Sell?`**: confirm focus stays on that exact `Confirm Sell?` button instead of jumping to row 1.

---

## 3. Accessibility & Input Mode Checks
- [ ] **Mute Sound:** Open `Settings` -> toggle **`Mute Sound: ON`** -> verify all UI clicks, crack SFX, chimes, and hatches silence immediately. Toggle **OFF** and confirm audio returns.
- [ ] **Reduced Motion:** Toggle **`Reduced Motion: ON`** -> verify all animated critters/pods in pens freeze motionless immediately, crack feel bar shows `Auto-cracking safely...`, and finishing a meteor skips particle bursts. Toggle **OFF** and confirm critters hop again.
- [ ] **Touch / Keyboard / Gamepad:**
  - Keyboard: `E` / `Space` hits Gold Quick-Burst; `B` toggles Bag.
  - Touch Emulator: Tapping world prompts starts rescue; tapping Gold Zone button triggers Quick Burst; `Bag` / `Settings` / `Place` / `Sell` tap cleanly (`>= 44px` hit targets).
  - Gamepad *(if connected)*: `X` rescues & triggers Gold Quick-Burst; `Y` toggles Bag; D-Pad moves across rows cleanly across Coin ticks; `B` closes drawers cleanly.

---

## 4. Live 2-Player Studio Local Server Verification
*(Run via **Test -> Clients and Servers -> Local Server -> 2 Players -> Start**)*

- [ ] **Unique Plot Assignment:** Player 1 spawns at `Plot_1` (`Player1's Ranch`); Player 2 spawns at `Plot_2` (`Player2's Ranch`). No plot collisions.
- [ ] **Starter Privacy:** Player 2 cannot claim Player 1's `STARTER METEOR`; Player 1 rescues Starter Meteor cleanly (`StarSlime`).
- [ ] **Simultaneous Crater Race:** Both players walk to the same Wild Meteor and trigger `E`: only 1 claims it (`Prompt` disables cleanly for the other player).
- [ ] **Abandonment (> 28 studs) & Respawn Recovery:** Player 1 claims a wild meteor and sprints `> 28` studs away OR resets character (`Esc -> R`) during the `1.2s` bar:
  - Client receives `ClaimReleased`, cancels crack bar cleanly, grants `0` pods, and **Player 2 (or Player 1)** can immediately see the `Rescue Star-Pod` prompt and claim it!
- [ ] **Leave Cleanup:** Have Player 1 claim a wild meteor in Crater and close Client 1's window:
  - Player 1's Ranch Plot resets cleanly to `Open`.
  - Player 1's claimed Wild Meteor immediately unlocks so Player 2 can claim & rescue it.
- [ ] **Station Isolation:** Player 2 walking onto Player 1's Ranch gets friendly rejection / server blocks station actions on another player's plot.

---

## 5. Full 5-Minute Prototype Loop Timing Check (Solo Play `F5`)
Record approximate wall-clock times from spawn (`0:00`):
- [ ] **Starter Rescue & Hatch:** Starter Meteor rescued -> Pod incubated (`15s`) -> Hatched -> Placed in `Pen_1` (`<= 90s`).
- [ ] **Upgrade #1 (`PenSlot_2` — `60 Coins`):** Bought cleanly via green Pad or Bag (`~50–90s`).
- [ ] **Upgrade #2 (`Incubator_2` — `150 Coins`):** Bought cleanly (`~2:00–3:15`).
- [ ] **Upgrade #3 (`PenSlot_3` — `320 Coins`) + Full 3-Slot Pen:** Bought cleanly within ~5 minutes (`<= 5:30`), Arch neon trim turns **Starlight Gold**, passive income runs smoothly (`6–21 Coins/s`).
