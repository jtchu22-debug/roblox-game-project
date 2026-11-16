--!strict
--[[
	Tool: GenerateGreyboxMap (Studio Command Bar Script)
	Purpose: Safely creates Workspace.StarfallGreyboxRoot in an isolated Roblox Studio test place.
	Usage (In Studio Command Bar):
	  1. Ensure Rojo is connected so ReplicatedStorage.Shared exists.
	  2. Paste and run this script (with ConfirmReplace = false for first run).
	  3. To intentionally rebuild StarfallGreyboxRoot later, set ConfirmReplace = true below.
	Safety: Never touches Baseplate, Terrain, Camera, or unrelated Studio objects outside StarfallGreyboxRoot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GreyboxBuilder = require(Shared:WaitForChild("Util"):WaitForChild("GreyboxBuilder"))

-- Change to `true` ONLY when you intentionally want to replace an existing StarfallGreyboxRoot.
local CONFIRM_REPLACE = false

local created, status, root = GreyboxBuilder.Generate({
	ConfirmReplace = CONFIRM_REPLACE,
	Parent = workspace,
})

if created and root then
	print("[GenerateGreyboxMap] Created StarfallGreyboxRoot successfully (" .. status .. ").")
elseif status == "ExistingPresent" then
	warn("[GenerateGreyboxMap] StarfallGreyboxRoot already exists! Set CONFIRM_REPLACE = true if you want to rebuild it.")
else
	warn("[GenerateGreyboxMap] Stopped: " .. status)
end
