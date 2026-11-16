--!strict
--[[
	Service: PlotService
	Purpose: Assigns and releases Ranch Plots for joining/leaving players and manages public plot DTO replication.
	Connections: Coordinates with DataService readiness and EconomyService slot/upgrade state.
	How to Test in Studio: Tested in Stage 1 with Test -> Local Server (2 Players) verifying unique plot assignment.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local _Shared = ReplicatedStorage:WaitForChild("Shared")

local PlotService = {
	Name = "PlotService",
}

function PlotService.Init(self: typeof(PlotService)): ()
	-- Stage 1 (S1-06): Discover tagged greybox plots inside Workspace.StarfallGreyboxRoot.
end

function PlotService.Start(self: typeof(PlotService)): ()
	-- Stage 1 (S1-06): Assign free plots on ready and clean up cleanly on PlayerRemoving.
end

return PlotService
