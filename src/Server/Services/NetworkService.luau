--!strict
--[[
	Service: NetworkService
	Purpose: Creates ReplicatedStorage.Remotes, validates inbound payloads, and enforces per-player token-bucket rate limits.
	Connections: Initialized first by ServerInit; used by EconomyService, PlotService, and MeteorService.
	How to Test in Studio: Press Play (F5) and inspect ReplicatedStorage.Remotes in Explorer.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))

local NetworkService = {
	Name = "NetworkService",
}

local remotesFolder: Folder? = nil

function NetworkService.Init(self: typeof(NetworkService)): ()
	local existing = ReplicatedStorage:FindFirstChild(Constants.REMOTES_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		remotesFolder = existing
	else
		local folder = Instance.new("Folder")
		folder.Name = Constants.REMOTES_FOLDER_NAME
		folder.Parent = ReplicatedStorage
		remotesFolder = folder
	end
end

function NetworkService.Start(self: typeof(NetworkService)): ()
	-- Stage 1 (S1-03): Bind validated RemoteEvents/RemoteFunctions and token buckets.
end

function NetworkService.GetRemotesFolder(): Folder
	assert(remotesFolder ~= nil, "NetworkService.Init() must run before GetRemotesFolder()")
	return remotesFolder :: Folder
end

return NetworkService
