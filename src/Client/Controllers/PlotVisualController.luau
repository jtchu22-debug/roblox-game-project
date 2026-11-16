--!strict
--[[
	Controller: PlotVisualController
	Purpose: Receives PublicPlotDTO snapshots from SyncPublicPlots and tracks per-plot visual state & revisions.
	Connections: Subscribes to ReplicatedStorage.Remotes.SyncPublicPlots in Start(); drives hopping critter visuals in S1-08.
	How to Test in Studio: Press Play (F5) and verify "[PlotVisualController] Synced N public plots" in Output.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Types = require(Shared:WaitForChild("Types"))

local PlotVisualController = {
	Name = "PlotVisualController",
}

local latestPlots: { [number]: Types.PublicPlotDTO } = {}
local latestPlotsRevision = -1
local syncConn: RBXScriptConnection? = nil

function PlotVisualController.Init(self: typeof(PlotVisualController)): ()
	-- Stage 1 (S1-08): Initialize centralized visual container and critter model cache.
end

function PlotVisualController.Start(self: typeof(PlotVisualController)): ()
	local remotes = ReplicatedStorage:WaitForChild(Constants.REMOTES_FOLDER_NAME)
	local syncPlotsEvent = remotes:WaitForChild(Constants.REMOTE_NAMES.SyncPublicPlots) :: RemoteEvent

	if syncConn == nil then
		syncConn = syncPlotsEvent.OnClientEvent:Connect(function(plotsList: { Types.PublicPlotDTO }, revision: number)
			if typeof(plotsList) ~= "table" or typeof(revision) ~= "number" then
				return
			end
			if latestPlotsRevision ~= -1 and revision <= latestPlotsRevision then
				return
			end

			latestPlotsRevision = revision
			local nextMap: { [number]: Types.PublicPlotDTO } = {}
			local occupiedCount = 0
			for _, dto in ipairs(plotsList) do
				if typeof(dto) == "table" and typeof(dto.PlotId) == "number" then
					nextMap[dto.PlotId] = dto
					if dto.OwnerUserId ~= 0 then
						occupiedCount += 1
					end
				end
			end
			latestPlots = nextMap

			print(string.format(
				"[PlotVisualController] Synced public plots (Revision %d, %d/%d occupied).",
				revision,
				occupiedCount,
				#plotsList
			))
		end)
	end
end

function PlotVisualController.GetPublicPlots(): { [number]: Types.PublicPlotDTO }
	return latestPlots
end

function PlotVisualController.GetLatestRevision(): number
	return latestPlotsRevision
end

return PlotVisualController
