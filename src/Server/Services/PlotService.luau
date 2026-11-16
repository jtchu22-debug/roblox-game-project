--!strict
--[[
	Service: PlotService
	Purpose: Validates or creates the Stage 1 greybox map on Init (never destroying invalid/conflicting Studio content),
	         then assigns/releases Ranch Plots and manages public plot DTO replication in S1-06.
	Connections: Uses Shared.Util.GreyboxBuilder in Init(); coordinates with DataService and EconomyService in S1-06.
	How to Test in Studio: Press Play (F5) and inspect Workspace.StarfallGreyboxRoot in Explorer and Output.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GreyboxBuilder = require(Shared:WaitForChild("Util"):WaitForChild("GreyboxBuilder"))

local PlotService = {
	Name = "PlotService",
}

local greyboxRoot: Folder? = nil

function PlotService.Init(self: typeof(PlotService)): ()
	local ok, status, root = GreyboxBuilder.EnsureExists(workspace)
	if not ok or root == nil then
		error(string.format("[PlotService] Greybox startup aborted (existing Studio content preserved): %s", status))
	end

	greyboxRoot = root
	print(string.format("[PlotService] Greybox map ready (%s: %s).", status, root.Name))
end

function PlotService.Start(self: typeof(PlotService)): ()
	-- Stage 1 (S1-06): Assign free plots on player ready and clean up cleanly on PlayerRemoving.
end

function PlotService.GetGreyboxRoot(): Folder
	assert(greyboxRoot ~= nil, "PlotService.Init() must run before GetGreyboxRoot()")
	return greyboxRoot :: Folder
end

return PlotService
