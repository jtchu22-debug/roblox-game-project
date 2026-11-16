--!strict
--[[
	Script: ServerInit
	Purpose: Single authoritative server entry point. Runs optional self-tests, initializes services, runs service self-tests, and starts services.
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
	print(string.format("[StarfallRanch][SelfTest] PASS: All %d Stage 1 shared unit test suites passed.", passedCount))
end

local ServicesFolder = script.Parent:WaitForChild("Services")
local NetworkService = require(ServicesFolder:WaitForChild("NetworkService"))
local DataService = require(ServicesFolder:WaitForChild("DataService"))
local EconomyService = require(ServicesFolder:WaitForChild("EconomyService"))
local PlotService = require(ServicesFolder:WaitForChild("PlotService"))

local serviceOrder: { Types.Service } = {
	NetworkService :: Types.Service,
	DataService :: Types.Service,
	EconomyService :: Types.Service,
	PlotService :: Types.Service,
	require(ServicesFolder:WaitForChild("MeteorService")) :: Types.Service,
}

for _, service in ipairs(serviceOrder) do
	service:Init()
end

if Constants.RUN_SELF_TESTS then
	local netPassed = NetworkService.RunSelfTest()
	print(string.format("[StarfallRanch][SelfTest] PASS: All %d NetworkService test suites passed.", netPassed))

	local dataPassed = DataService.RunSelfTest()
	print(string.format("[StarfallRanch][SelfTest] PASS: All %d DataService test suites passed.", dataPassed))

	local econPassed = EconomyService.RunSelfTest()
	print(string.format("[StarfallRanch][SelfTest] PASS: All %d EconomyService test suites passed.", econPassed))

	local plotPassed = PlotService.RunSelfTest()
	print(string.format("[StarfallRanch][SelfTest] PASS: All %d PlotService test suites passed.", plotPassed))
end

for _, service in ipairs(serviceOrder) do
	service:Start()
end

print(string.format("[StarfallRanch][Server] v%s server initialized (%d services).", Constants.GAME_VERSION, #serviceOrder))
