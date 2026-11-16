--!strict
--[[
	Module: MeteorConfig
	Purpose: Declarative registry of Crater Meteor traits (Ember, Frost, Astral) (Stage 1 skeleton stub).
	Connections: Populated during Stage 1 task S1-01; read by MeteorService and CrackController.
	How to Test in Studio: Require from Command Bar or Play mode and confirm table freezes cleanly.
]]

local Shared = script.Parent.Parent
local Types = require(Shared.Types)

local MeteorConfig: { [Types.MeteorTraitId]: Types.MeteorTraitDefinition } = {}

-- Stage 1 (S1-01) will populate Ember, Frost, and Astral meteor definitions per docs/GAME_DESIGN.md.

return table.freeze(MeteorConfig)
