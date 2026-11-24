--!strict
--[[
	Tool: RunS404StarterPersistenceCheck (Studio Server Command Bar Script)
	Purpose: Verifies S4-04 live Roblox DataStore starter meteor persistence across reload:
	         completed user does not respawn or duplicate-grant StarSlime, while another eligible
	         user still receives a working starter meteor spawn and crack.
	Usage:
	  1. Open the published 6-player dev place (PlaceId > 0) with "Enable Studio Access to API Services" = ON.
	  2. Start Play Solo (F5) or Run (F8) and execute with PHASE = "Write" in the Server Command Bar.
	  3. Stop, start a BRAND-NEW server session (F5 / F8), set PHASE = "Verify", and execute again.
	     (Or set PHASE = "RoundTrip" for a single-session check.)
]]

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

assert(RunService:IsRunning() and RunService:IsServer(), "Run this script from the Server Command Bar during Run (F8) or Play Solo (F5).")

local PHASE: "Write" | "Verify" | "RoundTrip" = "RoundTrip"

local ServerFolder = ServerScriptService:WaitForChild("Server")
local Stage3VerificationSuite = require(ServerFolder:WaitForChild("Services"):WaitForChild("Stage3VerificationSuite"))

local ok, message = Stage3VerificationSuite.RunS404StarterPersistenceCheck(PHASE)
if ok then
	print("[S404StarterPersistenceCheck] PASS: " .. message)
else
	error("[S404StarterPersistenceCheck] FAIL: " .. message)
end
