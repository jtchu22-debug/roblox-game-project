--!strict
--[[
	Script: ServerInit
	Purpose: Single authoritative server entry point. Runs optional self-tests, then initializes and starts all Server Services.
	Connections: Lives at ServerScriptService.Server.ServerInit via Rojo (default.project.json).
	How to Test in Studio: Press Play (F5) and look for "[StarfallRanch][SelfTest] PASS" and "[StarfallRanch][Server] ... initialized" in Output.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Types = require(Shared:WaitForChild("Types"))
local SharedSelfTest = require(Shared:WaitForChild("Util"):WaitForChild("SharedSelfTest"))

if Constants.RUN_SELF_TESTS then
	local passedCount = SharedSelfTest.RunAll()
	print(string.format("[StarfallRanch][SelfTest] PASS: All %d S1-01 shared unit test suites passed.", passedCount))
end

local ServicesFolder = script.Parent:WaitForChild("Services")

local serviceOrder: { Types.Service } = {
	require(ServicesFolder:WaitForChild("NetworkService")) :: Types.Service,
	require(ServicesFolder:WaitForChild("DataService")) :: Types.Service,
	require(ServicesFolder:WaitForChild("EconomyService")) :: Types.Service,
	require(ServicesFolder:WaitForChild("PlotService")) :: Types.Service,
	require(ServicesFolder:WaitForChild("MeteorService")) :: Types.Service,
}

for _, service in ipairs(serviceOrder) do
	service:Init()
end

for _, service in ipairs(serviceOrder) do
	service:Start()
end

print(string.format("[StarfallRanch][Server] v%s skeleton initialized (%d services).", Constants.GAME_VERSION, #serviceOrder))
