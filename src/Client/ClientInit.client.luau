--!strict
--[[
	Script: ClientInit
	Purpose: Single authoritative client entry point. Initializes controllers, starts listeners, and requests initial snapshot.
	Connections: Lives at StarterPlayer.StarterPlayerScripts.Client.ClientInit via Rojo (default.project.json).
	How to Test in Studio: Press Play (F5) and look for "[StarfallRanch][Client] ... initialized successfully." in Output.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Types = require(Shared:WaitForChild("Types"))

local ControllersFolder = script.Parent:WaitForChild("Controllers")

local controllerOrder: { Types.Controller } = {
	require(ControllersFolder:WaitForChild("SoundController")) :: Types.Controller,
	require(ControllersFolder:WaitForChild("UIController")) :: Types.Controller,
	require(ControllersFolder:WaitForChild("PlotVisualController")) :: Types.Controller,
	require(ControllersFolder:WaitForChild("CrackController")) :: Types.Controller,
	require(ControllersFolder:WaitForChild("InputController")) :: Types.Controller,
}

for _, controller in ipairs(controllerOrder) do
	controller:Init()
end

for _, controller in ipairs(controllerOrder) do
	controller:Start()
end

-- Stage 1 (S1-03): After listeners subscribe above, fire RequestInitialSnapshot here so no snapshot arrives before listeners bind.
print(string.format("[StarfallRanch][Client] v%s skeleton initialized (%d controllers).", Constants.GAME_VERSION, #controllerOrder))
