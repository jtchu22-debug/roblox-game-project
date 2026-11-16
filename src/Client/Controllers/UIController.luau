--!strict
--[[
	Controller: UIController
	Purpose: Manages mobile-safe HUD (Coins, Bag count, Keep-vs-Sell panel, Upgrade prompts, Mute/Reduced Motion settings).
	Connections: Reads OwnerStateDTO from SyncOwnerState and formats numbers via Shared.Util.FormatUtil.
	How to Test in Studio: Preview in Studio Device Emulator (iPhone SE, iPad, 1080p) verifying zero overlap with thumb zones.
]]

local UIController = {
	Name = "UIController",
}

function UIController.Init(self: typeof(UIController)): ()
	-- Stage 1 (S1-08): Create Safe-Area aware ScreenGui containers.
end

function UIController.Start(self: typeof(UIController)): ()
	-- Stage 1 (S1-08): Subscribe to SyncOwnerState and bind button actions.
end

return UIController
