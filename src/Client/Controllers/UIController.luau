--!strict
--[[
	Controller: UIController
	Purpose: Receives single-player OwnerStateDTO snapshots from SyncOwnerState and manages mobile-safe HUD state.
	Connections: Subscribes to ReplicatedStorage.Remotes.SyncOwnerState in Start(); notifies HUD listeners in S1-08.
	How to Test in Studio: Press Play (F5) and look for "[UIController] Synced OwnerStateDTO" in Output.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Types = require(Shared:WaitForChild("Types"))

local UIController = {
	Name = "UIController",
}

local latestOwnerState: Types.OwnerStateDTO? = nil
local stateChangedCallbacks: { (dto: Types.OwnerStateDTO) -> () } = {}
local syncConn: RBXScriptConnection? = nil

function UIController.Init(self: typeof(UIController)): ()
	-- Stage 1 (S1-08): Create Safe-Area aware ScreenGui containers.
end

function UIController.Start(self: typeof(UIController)): ()
	local remotes = ReplicatedStorage:WaitForChild(Constants.REMOTES_FOLDER_NAME)
	local syncEvent = remotes:WaitForChild(Constants.REMOTE_NAMES.SyncOwnerState) :: RemoteEvent

	if syncConn == nil then
		syncConn = syncEvent.OnClientEvent:Connect(function(dto: Types.OwnerStateDTO)
			if typeof(dto) ~= "table" or typeof(dto.Revision) ~= "number" then
				return
			end
			if latestOwnerState ~= nil and dto.Revision < latestOwnerState.Revision then
				return
			end
			latestOwnerState = dto
			print(string.format(
				"[UIController] Synced OwnerStateDTO (Revision %d, Coins %d, BagCap %d).",
				dto.Revision,
				dto.Coins,
				dto.BagCap
			))

			for _, cb in ipairs(stateChangedCallbacks) do
				local ok, err = pcall(cb, dto)
				if not ok then
					warn("[UIController] State listener error: " .. tostring(err))
				end
			end
		end)
	end
end

function UIController.GetLatestOwnerState(): Types.OwnerStateDTO?
	return latestOwnerState
end

function UIController.OnOwnerStateChanged(callback: (dto: Types.OwnerStateDTO) -> ()): ()
	table.insert(stateChangedCallbacks, callback)
	if latestOwnerState ~= nil then
		callback(latestOwnerState)
	end
end

return UIController
