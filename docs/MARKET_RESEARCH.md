# Roblox Market Research Report (2025–2026 — Post-Audit Revision)

> **Last Updated:** November 15, 2026 (Revised per Phase 0 Technical Director Audit)  
> **Research Baseline Date:** November 15–16, 2026  
> **Author:** Gemini (Primary Research Agent)  
> **Auditor:** ChatGPT (Independent Technical Director)  
> **Evidence Policy:** This document strictly separates **(A) Verifiable Public Telemetry**, **(B) Unverified / Pending Firsthand Walkthrough Items**, and **(C) Testable Product Hypotheses**. No private developer revenue, private retention percentages, or unverified causal claims are asserted as fact.

---

## 1. Executive Summary & Audit Corrections

Our initial research identified a clear shift in recent Roblox chart leaders away from static, pure-button tycoons toward **tactile harvesting loops, physical collectible showcases, and varied world progression**. However, our Phase 0 independent audit (`docs/CHATGPT_REVIEW.md`) identified several critical corrections required before committing to a game design:

1. **Avoid Overclaiming Discovery Penalties:** There is **no** algorithmic penalty against clicker games and **no** 28-day waiting lock before new experiences enter Home recommendations.
2. **Account for Direct Nearby Competitors & Negative Controls:** Earlier research missed **Break and Steal an Egg** (which already pairs cracking/carrying eggs with base passive income), **Fish It!** (a counterexample showing simple click + explore mechanics still retain massive players), and **Shovel It!** (a negative control showing that merely stacking weather + mutations does not guarantee retention).
3. **Beware Cloning Peak-and-Cool Phenomena:** *Grow a Garden*'s historic 2025 peak (~22.38M sampled) cooled dramatically by late 2026 (~24.4K 24h peak). Copying a cooled 2025 weather-farm template without a fresh, active core choice risks launching into a saturated fade.
4. **Separate Telemetry from Hypotheses:** Ideas such as *"offline growth increases D7 return"* or *"gifting boosts D1 retention"* are **testable hypotheses**, not guaranteed outcomes. We will test them directly with instrumented playtests in Stage 2 and Stage 5.

---

## 2. Verified Public Telemetry & Competitive Landscape (Snapshot: Nov 15–16, 2026)

> **Methodological Caveat:** Third-party CCU trackers (`Rolimon's`, `RoStats`) are sampled snapshots, not exact official Roblox totals. Peak CCU measures simultaneous players at a spike (often during an update/admin event), whereas weekly averages measure sustained baseline play. Note that **RoStats Week Nov 9, 2026 (`2026-w46`) reflects a partial 6/7-day window** at the time of retrieval and must not be treated as a complete 7-day average or equated directly against another game's all-time peak.

### 2.1 Primary Benchmark Experiences, Rivals & Negative Controls

| Experience | Place ID & Source Link | Launch / Tracker Milestones | Recent Telemetry Snapshot (Nov 2026) | Core Loop & Strategic Implication |
| :--- | :--- | :--- | :--- | :--- |
| **Steal An Egg** | `107778070777162`<br>[Rolimon's](https://www.rolimons.com/game/107778070777162) | Created **July 25, 2026**. All-time sampled peak: **~14.29M CCU** (Sep 19, 2026). | RoStats (`2026-w46`, 6/7 days): **~774,556 avg CCU**, ~6.89M peak (-12.3% WoW). | Explicitly combines training speed, stealing eggs from NPC guards/players, hatching, and base defense. Massive scale proves active risk/collection momentum—not merely a meme reskin. |
| **Throw Food For Animals** | [Rolimon's Table](https://www.rolimons.com/gametable)<br>[RoStats](https://rostats.io/charts/2026-w46) | Created **Sep 18, 2026**. Sampled record: **~2.43M–2.47M CCU**. | RoStats (`2026-w46`, 6/7 days): **~256,882 avg CCU**, ~2.47M peak (**+53.2% WoW**). | Strong active momentum built around a legible 3-step loop: train throw power $\rightarrow$ aim/throw down lane $\rightarrow$ collect animals into income pens. |
| **Break and Steal an Egg** *(Overlooked Rival)* | `114326934417838`<br>[Rolimon's](https://www.rolimons.com/game/114326934417838) | Tracked peak: **~1.31M CCU**. | RoStats (`2026-w46`, 6/7 days): **~84,722 avg CCU** (-28% WoW). | **Direct competitor warning:** Advertises breaking eggs, escaping guards, base income, and pickaxe/speed upgrades. Proves "crack + base income" alone is NOT novel—we need a distinct active choice! |
| **Fish It!** *(Counterexample)* | `121864768012064`<br>[Rolimon's](https://www.rolimons.com/game/121864768012064) | Tracked peak: **~2.72M CCU** (Dec 7, 2025). | RoStats (`2026-w46`, 6/7 days): **~63,000 avg CCU**. | **Counterexample:** Explicitly uses simpler clicking interaction + world exploration. Proves simple clicker mechanics do NOT fail automatically when pacing and discovery are well-executed. |
| **Fisch** | `16732694052`<br>[Rolimon's](https://www.rolimons.com/game/16732694052) | Tracked peak: **~1.274M CCU** (Oct 18, 2025). | 30-day peak **~511K CCU**; RoStats (`2026-w46`, 6/7 days): **~62,107 avg CCU**. | Active tension-reel skill check + Bestiary completion + communal server totems. Shows strong endurance via exploration and collection goals. |
| **Grow a Garden** | `126884695634066`<br>[Rolimon's](https://www.rolimons.com/game/126884695634066) / [AP News](https://apnews.com/article/2f5e4368448d57002d08b1b3d4a289ca) | AP reported **21.6M peak** (June 2025); Rolimon's sampled **22.38M peak** (Aug 23, 2025). | Past 30 days **~107K peak**; past 24h **~24.4K peak** (Nov 2026). | Historic viral milestone, but steep contraction from 2025 peaks proves cloning its passive weather-farm loop today carries high saturation risk. |
| **Shovel It!** *(Negative Control)* | `133832344745984`<br>[Rolimon's](https://www.rolimons.com/game/133832344745984) | Tracked peak: **~2,374 CCU** (March 22, 2026). | Snapshot: **1 active player** (despite weather, mutations, and high like ratio). | **Crucial Negative Control:** Demonstrates that assembling popular mechanics (weather + mutations + collection cues) guarantees neither product-market fit nor sustained players. |
| **Evergreen & Co-Op Leaders** *(Brookhaven, 99 Nights, Blox Fruits, Adopt Me!, MM2, RIVALS)* | [RoStats](https://rostats.io/charts/2026-w46) | Multi-year titans & 2025–2026 co-op/action staples. | RoStats (`2026-w46`, 6/7 days): *Brookhaven* **~334K avg**, *99 Nights* **~131K avg** (all above *Fisch*). | Proves long-term dominance is driven by social identity, roleplay, teamwork, and repeatable skill/world challenges—not RNG grinding alone. |

### 2.2 Secondary Comparators (Pending Place-ID Snapshot & 5-Minute Walkthrough Verification)
Before committing beyond our Stage 1 prototype, Gemini and the Human Lead will record 5-minute firsthand walkthroughs (onboarding steps to first reward, second goal, active/passive split, and update cadence) and exact Place ID snapshots for:
- *Dead Rails* (~1.47M–1.48M Apr 19, 2025 historical peak reported in initial pass)
- *Dandy's World*, *Restaurant Tycoon 3*, *The Forge*, *Ride A Pet*, *Ultimate Mining Tycoon*, and 2–3 mid-tier cozy/collection comparators.

---

## 3. Official Roblox Discovery & Recommendation Mechanics

Based strictly on official Roblox Creator Documentation ([Discovery Overview](https://create.roblox.com/docs/discovery) and [Discovery FAQ](https://create.roblox.com/docs/discovery-faq)):

1. **Evaluation Windows:** Roblox evaluates Home / Recommended For You (RFY) performance across early onboarding and rolling windows: **Day 1**, **Days 2–7**, and **Days 8–28**.
   - *Important Correction:* **Play Days per User** measures how many distinct days a user plays within a window—it is **not** identical to cohort D7/D28 retention percentages, and **no single metric is "#1"** in the ranking model.
2. **Core vs. Secondary Signals:**
   - **Primary Engagement Signals:** Play-Through Rate (PTR), First-Play Bounce Rate (leaving immediately after spawning), Playtime per User, and Play Days per User.
   - **Secondary Signals:** Qualified Play Sessions, Intentional Co-Play Days (friends joining friends), and Spend Days / Robux Spent per User.
3. **Organic vs. Paid Traffic Isolation:** Metrics generated via paid ads or external links do not directly inflate organic Home RFY retrieval scoring; the experience must retain organically acquired Home players.
4. **No Genre Penalties or 28-Day Lockouts:** Roblox does **not** penalize specific genre tags (such as "Clicker" or "Simulator") and does **not** force a 28-day wait before testing a new game. Moving windows allow experiences to improve and recover as onboarding/retention improve.

---

## 4. Community Sentiment & Bias Caveats

Community discussions on `r/roblox`, `r/robloxgamedev`, YouTube, and TikTok are useful for identifying **design friction patterns**, but suffer from heavy **selection and creator bias** (vocal PC teenagers/adults on Reddit do not represent every 8-to-12-year-old mobile player). We treat community feedback as **design hypotheses**, not universal laws:

- **Recurring Friction Themes to Avoid:**
  - *Cluttered Day-1 Spawn Screens:* Pop-ups blocking mobile screens before a player understands the first action.
  - *Punishing Base Theft for Younger Players:* Losing hard-earned items to high-level griefers drives immediate quit behavior for casual/younger cohorts (though high-stakes players enjoy *Steal An Egg*—meaning our target niche is specifically **positive, non-griefing collection**).
  - *Forced Overnight Device Idle:* Requiring PC auto-clicker macros alienates mobile/tablet users.
- **Device Assumption:** While exact platform demographics vary by title (and we do not assume a fixed `70/20/10` split without telemetry), we design **mobile-first** (clear tap targets, safe-area margins, restrained part counts) and measure actual device breakdowns once live analytics (`AnalyticsService`) are running.

---

## 5. Research-Backed Design Hypotheses (To Be Tested in Stages 1–2)

Rather than promising fixed uplifts, our prototype and alpha stages will directly test four concrete hypotheses:

1. **Hypothesis H1 (Active Choice Over Passive Waiting):** Giving players an active **Meteor Rescue Choice** (visibly scanning 2–3 falling meteor traits/locations in a shared crater) will cause $>70\%$ of uncoached testers to voluntarily initiate a second rescue within 5 minutes, rather than standing idle waiting for coins.
2. **Hypothesis H2 (Fast Legible Onboarding):** Putting a starter meteor directly along the sightline from the player's Ranch Plot—with zero pop-up modals—will allow $\ge 80\%$ of new testers to crack, hatch, and place their first Critter within 90 seconds.
3. **Hypothesis H3 (Keep-vs-Sell Agency):** Offering a clear integer decision (*Keep Critter in Pen for steady Coins/sec* vs. *Sell Critter for immediate Coins toward a visible Habitat Upgrade*) creates more engaging early-session decisions than automatic cash conversion.
4. **Hypothesis H4 (Low-Friction Offline Incubation):** Using absolute server timestamps (`MaturesAt`) for pod incubation (without offline passive money faucets or streak punishments) encourages voluntary next-day returns without inflating the economy.
