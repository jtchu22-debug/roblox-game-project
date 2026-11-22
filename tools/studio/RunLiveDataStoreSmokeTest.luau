--!strict
--[[
	Tool: RunLiveDataStoreSmokeTest (Studio Server Command Bar Script)
	Purpose: Verifies real Roblox DataStore persistence on an isolated developer store
	         ("StarfallRanch_StudioDev_v1_Smoke") per Review #017.
	Usage:
	  1. Open the published dev place in Roblox Studio (PlaceId > 0) with "Enable Studio Access to API Services" = ON.
	  2. Run a fresh Server session (Play Solo F5 or Run F8) with PHASE = "Write" in the Server Command Bar.
	  3. Stop, start a BRAND-NEW Server session (F5 / F8), set PHASE = "Verify", and run again.
	     (Or set PHASE = "RoundTrip" for a single-session save/reopen check.)
]]

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

assert(RunService:IsRunning() and RunService:IsServer(), "Run this script from the Server Command Bar during Run (F8) or Play Solo (F5).")

local PHASE: "Write" | "Verify" | "RoundTrip" = "Write"

local ServerFolder = ServerScriptService:WaitForChild("Server")
local DataService = require(ServerFolder:WaitForChild("Services"):WaitForChild("DataService"))

local ok, message = DataService.RunLiveDevDataStoreSmokeTest(PHASE)
if ok then
	print("[LiveDataStoreSmokeTest] PASS: " .. message)
else
	error("[LiveDataStoreSmokeTest] FAIL: " .. message)
end
