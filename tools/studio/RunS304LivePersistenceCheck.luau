--!strict
--[[
	Tool: RunS304LivePersistenceCheck (Studio Server Command Bar Script)
	Purpose: Verifies S3-04 multi-profile live Roblox DataStore persistence, BindToClose settlement flush,
	         BagCap_20 / PenSlot_5 / FeedLevel / Radiant fields, and offline MaturesAt hatch boundaries
	         on the isolated developer store ("StarfallRanch_StudioDev_v1_Smoke").
	Usage:
	  1. Open the published 6-player dev place (PlaceId > 0) with "Enable Studio Access to API Services" = ON.
	  2. Start Play Solo (F5) or Run (F8) and execute with PHASE = "Write" in the Server Command Bar.
	  3. Stop, start a BRAND-NEW server session (F5 / F8), set PHASE = "Verify", and execute again.
	     (Or set PHASE = "RoundTrip" for a single-session check.)
]]

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

assert(RunService:IsRunning() and RunService:IsServer(), "Run this script from the Server Command Bar during Run (F8) or Play Solo (F5).")

local PHASE: "Write" | "Verify" | "RoundTrip" = "Write"

local ServerFolder = ServerScriptService:WaitForChild("Server")
local Stage3VerificationSuite = require(ServerFolder:WaitForChild("Services"):WaitForChild("Stage3VerificationSuite"))

local ok, message = Stage3VerificationSuite.RunLiveApiPersistenceCheck(PHASE)
if ok then
	print("[S304LivePersistenceCheck] PASS: " .. message)
else
	error("[S304LivePersistenceCheck] FAIL: " .. message)
end