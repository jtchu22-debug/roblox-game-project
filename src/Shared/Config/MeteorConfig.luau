--!strict
--[[
	Module: MeteorConfig
	Purpose: Declarative, deeply frozen registry of Crater Meteor traits (Ember, Frost, Astral).
	Connections: Read by EconomyMath, MeteorService, and CrackController for drop odds and visual cues.
	How to Test in Studio: Press Play (F5) to run SharedSelfTest verifying drop weights and immutability.
]]

local Shared = script.Parent.Parent
local Types = require(Shared:WaitForChild("Types"))

local byId: { [Types.MeteorTraitId]: Types.MeteorTraitDefinition } = {
	Ember = table.freeze({
		Id = "Ember",
		DisplayName = "Ember Meteor",
		TrailColor = Color3.fromRGB(255, 130, 65),
		RockColor = Color3.fromRGB(145, 85, 95),
		CoreColor = Color3.fromRGB(255, 145, 60),
		ShapeStyle = "FlameCrest",
		IconText = "EMBER",
		RequiredUpgradeId = nil,
		DropWeights = table.freeze({
			StarSlime = 75,
			CinderPup = 25,
			FrostBeetle = 0,
			NebulaFox = 0,
			SolarGolem = 0,
			CometOwl = 0,
		}),
	}),
	Frost = table.freeze({
		Id = "Frost",
		DisplayName = "Frost Meteor",
		TrailColor = Color3.fromRGB(85, 220, 255),
		RockColor = Color3.fromRGB(95, 135, 185),
		CoreColor = Color3.fromRGB(125, 240, 255),
		ShapeStyle = "IceSpikes",
		IconText = "FROST",
		RequiredUpgradeId = "FrostCracker",
		DropWeights = table.freeze({
			StarSlime = 0,
			CinderPup = 0,
			FrostBeetle = 75,
			NebulaFox = 25,
			SolarGolem = 0,
			CometOwl = 0,
		}),
	}),
	Astral = table.freeze({
		Id = "Astral",
		DisplayName = "Astral Meteor",
		TrailColor = Color3.fromRGB(215, 110, 255),
		RockColor = Color3.fromRGB(90, 75, 135),
		CoreColor = Color3.fromRGB(255, 210, 80),
		ShapeStyle = "StarRing",
		IconText = "ASTRAL",
		RequiredUpgradeId = "StarCracker",
		DropWeights = table.freeze({
			StarSlime = 0,
			CinderPup = 0,
			FrostBeetle = 0,
			NebulaFox = 40,
			SolarGolem = 50,
			CometOwl = 10,
		}),
	}),
}

local orderedIds: { Types.MeteorTraitId } = table.freeze({
	"Ember",
	"Frost",
	"Astral",
})

local MeteorConfig = {
	OrderedIds = orderedIds,
	ById = table.freeze(byId),
}

return table.freeze(MeteorConfig)
