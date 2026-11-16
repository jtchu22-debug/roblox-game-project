--!strict
--[[
	Module: UpgradeConfig
	Purpose: Declarative registry of permanent Ranch upgrades (Stage 1 skeleton stub).
	Connections: Populated during Stage 1 task S1-01; read by EconomyService, PlotService, and UIController.
	How to Test in Studio: Require from Command Bar or Play mode and confirm table freezes cleanly.
]]

local Shared = script.Parent.Parent
local Types = require(Shared.Types)

local UpgradeConfig: { [string]: Types.UpgradeDefinition } = {}

-- Stage 1 (S1-01) will populate PenSlot_2, Incubator_2, and PenSlot_3 per docs/GAME_DESIGN.md.

return table.freeze(UpgradeConfig)
