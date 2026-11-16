--!strict
--[[
	Module: CritterConfig
	Purpose: Declarative registry of Cosmic Critter species (Stage 1 skeleton stub).
	Connections: Populated during Stage 1 task S1-01; read by EconomyService, UI, and PlotVisualController.
	How to Test in Studio: Require from Command Bar or Play mode and confirm table freezes cleanly.
]]

local Shared = script.Parent.Parent
local Types = require(Shared.Types)

local CritterConfig: { [Types.SpeciesId]: Types.SpeciesDefinition } = {}

-- Stage 1 (S1-01) will populate StarSlime, NebulaFox, and SolarGolem entries per docs/GAME_DESIGN.md.

return table.freeze(CritterConfig)
