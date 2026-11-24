--!strict
--[[
	Script: ClientInit
	Purpose: Single authoritative client entry point. Initializes controllers, starts listeners, and requests initial snapshot.
	Connections: Lives at StarterPlayer.StarterPlayerScripts.Client.ClientInit via Rojo (default.project.json).
	How to Test in Studio: Press Play (F5) and look for "[StarfallRanch][Client] ... initialized" and "[UIController] Synced OwnerStateDTO" in Output.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Types = require(Shared:WaitForChild("Types"))

local ControllersFolder = script.Parent:WaitForChild("Controllers")

local controllerOrder: { Types.Controller } = {
	require(ControllersFolder:WaitForChild("SoundController")) :: Types.Controller,
	require(ControllersFolder:WaitForChild("UIController")) :: Types.Controller,
	require(ControllersFolder:WaitForChild("PlotVisualController")) :: Types.Controller,
	require(ControllersFolder:WaitForChild("ToolVisualController")) :: Types.Controller,
	require(ControllersFolder:WaitForChild("CrackController")) :: Types.Controller,
	require(ControllersFolder:WaitForChild("InputController")) :: Types.Controller,
}

for _, controller in ipairs(controllerOrder) do
	controller:Init()
end

if Constants.RUN_SELF_TESTS and RunService:IsStudio() then
	local UIController = require(ControllersFolder:WaitForChild("UIController"))
	local okUiTest, uiPassedOrErr = pcall(UIController.RunSelfTest)
	if okUiTest then
		print(string.format("[StarfallRanch][SelfTest] PASS: All %d UIController client test suites passed.", uiPassedOrErr :: number))
	else
		warn("[StarfallRanch][SelfTest] FAIL: UIController self-test error: " .. tostring(uiPassedOrErr))
	end

	local PlotVisualController = require(ControllersFolder:WaitForChild("PlotVisualController"))
	local okVisTest, visPassedOrErr = pcall(PlotVisualController.RunSelfTest)
	if okVisTest then
		print(string.format("[StarfallRanch][SelfTest] PASS: All %d PlotVisualController client test suites passed.", visPassedOrErr :: number))
	else
		warn("[StarfallRanch][SelfTest] FAIL: PlotVisualController self-test error: " .. tostring(visPassedOrErr))
	end

	local ToolVisualController = require(ControllersFolder:WaitForChild("ToolVisualController"))
	local okToolTest, toolPassedOrErr = pcall(ToolVisualController.RunSelfTest)
	if okToolTest then
		print(string.format("[StarfallRanch][SelfTest] PASS: All %d ToolVisualController client test suites passed.", toolPassedOrErr :: number))
	else
		warn("[StarfallRanch][SelfTest] FAIL: ToolVisualController self-test error: " .. tostring(toolPassedOrErr))
	end
end

for _, controller in ipairs(controllerOrder) do
	controller:Start()
end

-- Request initial snapshot ONLY after all controllers above have subscribed their listeners.
local remotes = ReplicatedStorage:WaitForChild(Constants.REMOTES_FOLDER_NAME)
local requestSnapshot = remotes:WaitForChild(Constants.REMOTE_NAMES.RequestInitialSnapshot) :: RemoteEvent
requestSnapshot:FireServer()

print(string.format("[StarfallRanch][Client] v%s client controllers initialized (%d controllers).", Constants.GAME_VERSION, #controllerOrder))
