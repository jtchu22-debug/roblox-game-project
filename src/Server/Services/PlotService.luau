--!strict
--[[
	Service: PlotService
	Purpose: Ensures the Stage 1 greybox map exists on Init, then assigns/releases Ranch Plots and manages public plot DTO replication.
	Connections: Uses Shared.Util.GreyboxBuilder in Init(); coordinates with DataService and EconomyService in S1-06.
	How to Test in Studio: Press Play (F5) and inspect Workspace.StarfallGreyboxRoot in Explorer and Viewport.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GreyboxBuilder = require(Shared:WaitForChild("Util"):WaitForChild("GreyboxBuilder"))

local PlotService = {
	Name = "PlotService",
}

local greyboxRoot: Folder? = nil

function PlotService.Init(self: typeof(PlotService)): ()
	local root = GreyboxBuilder.EnsureExists(workspace)
	local valid, reason = GreyboxBuilder.ValidateHierarchy(root)
	assert(valid, "Greybox hierarchy invalid after EnsureExists: " .. reason)

	greyboxRoot = root
	print(string.format("[PlotService] Greybox map ready and validated (%s).", root.Name))
end

function PlotService.Start(self: typeof(PlotService)): ()
	-- Stage 1 (S1-06): Assign free plots on player ready and clean up cleanly on PlayerRemoving.
end

function PlotService.GetGreyboxRoot(): Folder
	assert(greyboxRoot ~= nil, "PlotService.Init() must run before GetGreyboxRoot()")
	return greyboxRoot :: Folder
end

return PlotService
