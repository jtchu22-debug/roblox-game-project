--!strict
--[[
	Service: EconomyService
	Purpose: Single authoritative state writer for player Items, Slots, Coins, Upgrades, and Keep-vs-Sell decisions.
	Connections: Reads DataService profiles and Shared Config tables; notifies PlotService and NetworkService of state updates.
	How to Test in Studio: Tested in Stage 1 via local playtests and unit tests on one-item/one-location invariants.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local _Shared = ReplicatedStorage:WaitForChild("Shared")

local EconomyService = {
	Name = "EconomyService",
}

function EconomyService.Init(self: typeof(EconomyService)): ()
	-- Stage 1 (S1-05): Prepare authoritative state transition handlers.
end

function EconomyService.Start(self: typeof(EconomyService)): ()
	-- Stage 1 (S1-05): Bind plot/shop remote requests and online coin accrual loop.
end

return EconomyService
