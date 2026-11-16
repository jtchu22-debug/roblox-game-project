# Beginner Development Setup & Workflow Guide (`DEVELOPMENT_SETUP.md`)

> **Last Updated:** November 15, 2026  
> **Project:** *Starfall Ranch* (`C:\Users\Justin\.gemini\antigravity\scratch\roblox-game-project`)  
> **Written For:** Beginner developers working with Roblox Studio, Rojo, Git/GitHub, and AI coding agents.

---

## 1. What Is Already Installed vs. What You Need to Do

### Already Installed & Verified on Your PC
| Tool | Status | Location / Notes |
| :--- | :---: | :--- |
| **Roblox Studio** | Installed | `C:\Users\Justin\AppData\Local\Roblox\Versions\...\RobloxStudioBeta.exe` |
| **Git (`2.56.0`)** | Installed | `C:\Users\Justin\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\git\cmd\git.exe` |
| **Rojo CLI (`v7.4.4`)** | Installed | `tools/bin/rojo.exe` inside this repository (gitignored) + pinned in `aftman.toml` / `rokit.toml` |
| **Rojo Studio Plugin** | Installed | `C:\Users\Justin\AppData\Local\Roblox\Plugins\RojoManagedPlugin.rbxm` |
| **Project Sync Helper Scripts** | Ready | [`tools/start-rojo.ps1`](../tools/start-rojo.ps1) and [`tools/build-place.ps1`](../tools/build-place.ps1) |

### One-Time Manual Roblox Studio Setup (2 Minutes)
1. **Open Roblox Studio** from your Start Menu / Desktop and sign in to your Roblox account.
2. Open a fresh **Baseplate** template (`New -> All Templates -> Baseplate`).
3. Turn on the 4 essential developer panels from the top **View** tab (click each so it stays pinned open):
   - **Explorer** (shows the hierarchy of folders and scripts in your game)
   - **Properties** (shows size, color, and settings of whatever you click in Explorer)
   - **Output** (prints messages and errors from our scripts—where we verify tests!)
   - **Command Bar** (a 1-line box at the bottom used later in Stage 1 to generate the greybox map)
   - *(Optional helpful panel)* **Script Analysis** (shows `--!strict` type errors immediately)
4. Click the **Plugins** tab at the top of Studio and confirm you see the **Rojo** icon.
5. Save this Baseplate file on your computer (for example, `File -> Save to File As... -> C:\Users\Justin\Documents\ROBLOX\StarfallRanch_Dev.rbxl`).
   - *Tip:* Save it outside `src/` (or name it `build.rbxl` inside the repo, which `.gitignore` automatically ignores) so you never accidentally commit a large binary `.rbxl` file to Git.

---

## 2. How to Synchronize Code Between This Repository and Roblox Studio (Rojo)

Think of **Rojo** as a live bridge: Gemini edits `.luau` text files inside `src/` on your hard drive, and Rojo pushes those files straight into Roblox Studio in real time.

### Step-by-Step Live Sync Workflow
1. **Start the Rojo Sync Server on your PC:**  
   Open PowerShell in `C:\Users\Justin\.gemini\antigravity\scratch\roblox-game-project` and run:
   ```powershell
   .\tools\start-rojo.ps1
   ```
   You should see Rojo listening on port `34872`. Leave this terminal window open while working.
2. **Connect Roblox Studio to Rojo:**  
   In your open `StarfallRanch_Dev.rbxl` Baseplate in Roblox Studio:
   - Go to **Plugins** $\rightarrow$ click **Rojo**.
   - In the Rojo popup panel, verify the address is `localhost` and port `34872`, then click **Connect**.
3. **Verify the Sync Worked in Explorer:**  
   Look at the **Explorer** window in Studio:
   - `ReplicatedStorage` now contains **`Shared`** (`Constants`, `Types`, `Config`, `Util`).
   - `ServerScriptService` now contains **`Server`** (`ServerInit`, `Services`).
   - `StarterPlayer -> StarterPlayerScripts` now contains **`Client`** (`ClientInit`, `Controllers`).

> **Important Beginner Rule:** Whenever you edit code (or ask Gemini to edit code), edit the `.luau` files in the repository folder—**never** edit them inside Roblox Studio while Rojo is connected! Rojo automatically updates Studio the instant a file saves.

### Alternative: Inspecting a Clean Built Place (`build.rbxlx`)
If you ever want to build a standalone place snapshot from code only, run:
```powershell
.\tools\build-place.ps1
```
This generates `build.rbxlx` in the repo root. *(Note: `build.rbxlx` only contains the script folders from `default.project.json` and has no Baseplate floor yet, so use the **Baseplate + `start-rojo.ps1`** method above when testing gameplay!)*

---

## 3. How to Test Scripts in Roblox Studio

### Test A: Single-Player Skeleton / Script Test (`Play (F5)`)
1. Make sure Rojo is connected (green "Connected" status in Studio's Rojo panel).
2. Go to the **Home** or **Test** tab and click **Play** (or press `F5`).
3. Watch the **Output** window! Right now (with the Phase 1 skeleton), you should see three clean startup messages:
   - `[DataService] Initialized in Stage 1 MockStore mode (in-memory session profiles).`
   - `[StarfallRanch][Server] v0.1.0-skeleton initialized (5 services).`
   - `[StarfallRanch][Client] v0.1.0-skeleton initialized (5 controllers).`
4. In **Explorer**, expand `ReplicatedStorage` and confirm `Remotes` folder was created automatically by `NetworkService`.
5. Click **Stop** (`Shift + F5`).

### Test B: Two-Player Multiplayer Test (`Local Server`)
When we build Stage 1 plot claiming and meteor cracking, you will test two players at once:
1. Go to the **Test** tab in Roblox Studio.
2. In the **Clients and Servers** dropdown, select **2 Players** (next to `Local Server`).
3. Click **Start**. Studio opens **3 windows**: 1 Server window + Player 1 window + Player 2 window.
4. You can test moving Player 1 and Player 2 independently to verify they get separate Ranch Plots and cannot steal each other's meteors.
5. Click **Cleanup** in the Test tab when done to close all test windows at once.

### Test C: Mobile Layout Check (`Device Emulator`)
1. Go to the **Test** tab $\rightarrow$ click **Device** (the phone/tablet icon).
2. Select `iPhone 12` or `iPad Mini` from the top bar of the viewport to verify UI buttons fit comfortably without covering the mobile thumbstick or jump button.
3. *(Reminder from Audit)*: Device Emulator only tests **screen layout and touch input**, not real mobile FPS performance—real hardware tests come in Stage 4!

---

## 4. Plain-English Git & GitHub Guide for Beginners

Git tracks every change made by you, Gemini, and ChatGPT so you can always review changes or undo mistakes.

Because `git.exe` is installed inside your Antigravity runtime folder rather than Windows system `PATH`, run Git commands in PowerShell using this shortcut variable:

```powershell
$git = "C:\Users\Justin\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\git\cmd\git.exe"
Set-Location "C:\Users\Justin\.gemini\antigravity\scratch\roblox-game-project"
```

### Everyday Commands Cheat Sheet
| What You Want to Do | Exact PowerShell Command | Plain-English Meaning |
| :--- | :--- | :--- |
| **See what changed** | `& $git status` | Lists any files modified or added on your computer. |
| **Download updates from GitHub** | `& $git pull origin main` | Fetches and merges the latest work pushed by ChatGPT or another machine. |
| **Create a safe feature branch** | `& $git checkout -b feat/stage1-vertical-slice` | Switches off `main` onto a separate workspace branch for a new task (required by `AGENT_RULES.md` for substantial changes). |
| **Stage & save a snapshot** | `& $git add .`<br>`& $git commit -m "Describe your change"` | Packs your edits into a permanent, undoable checkpoint. |
| **Upload your snapshot to GitHub** | `& $git push -u origin HEAD` | Pushes your current branch up to `https://github.com/jtchu22-debug/roblox-game-project`. |
| **Check recent history** | `& $git log --oneline -n 10` | Shows the last 10 commits cleanly. |
