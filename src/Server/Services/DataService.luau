--!strict
--[[
	Service: DataService
	Purpose: Manages player session readiness and profile storage (MockStore in Stage 1-2; pinned ProfileStore in Stage 3+).
	Connections: Required by EconomyService, PlotService, and MeteorService to verify IsReady(player) before mutations.
	How to Test in Studio: Press Play (F5) and confirm DataService reports MockStore mode active in Output.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Types = require(Shared:WaitForChild("Types"))

local DataService = {
	Name = "DataService",
}

function DataService.Init(self: typeof(DataService)): ()
	if Constants.USE_MOCK_STORE then
		print("[DataService] Initialized in Stage 1 MockStore mode (in-memory session profiles).")
	end
end

function DataService.Start(self: typeof(DataService)): ()
	-- Stage 1 (S1-04): Wire Players.PlayerAdded / PlayerRemoving mock lifecycle.
	-- Stage 3: Swap MockStore adapter cleanly to pinned ProfileStore.
end

function DataService.IsReady(_player: Player): boolean
	-- Stage 1 (S1-04): Return true only after active profile session completes loading.
	return false
end

function DataService.GetProfile(_player: Player): Types.PlayerProfileData?
	-- Stage 1 (S1-04): Return active session profile table for server services only.
	return nil
end

return DataService
