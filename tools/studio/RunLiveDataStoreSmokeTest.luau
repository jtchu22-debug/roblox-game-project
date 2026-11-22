--!strict
--[[
	Tool: RunLiveDataStoreSmokeTest (Studio Server Command Bar Script)
	Purpose: Verifies real Roblox DataStore persistence on an isolated developer store
	         ("StarfallRanch_StudioDev_v1_Smoke") per Review #016.
	Usage:
	  1. Open a published dev place in Roblox Studio with "Enable Studio Access to API Services" = ON.
	  2. Press Play (F5) or Run (F8), switch Command Bar / Studio context to Server, and run this script.
	  3. Confirm Output prints "[LiveDataStoreSmokeTest] PASS: ...".
]]

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

assert(RunService:IsRunning() and RunService:IsServer(), "Run this script from the Server Command Bar during Run (F8) or Play Solo (F5).")

local ServerFolder = ServerScriptService:WaitForChild("Server")
local DataService = require(ServerFolder:WaitForChild("Services"):WaitForChild("DataService"))

local ok, message = DataService.RunLiveDevDataStoreSmokeTest()
if ok then
	print("[LiveDataStoreSmokeTest] PASS: " .. message)
else
	error("[LiveDataStoreSmokeTest] FAIL: " .. message)
end
