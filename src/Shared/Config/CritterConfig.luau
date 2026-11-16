--!strict
--[[
	Module: CritterConfig
	Purpose: Declarative, deeply frozen registry of the 3 Stage 1 Cosmic Critter species.
	Connections: Read by EconomyMath, EconomyService, UIController, and PlotVisualController.
	How to Test in Studio: Press Play (F5) to run SharedSelfTest verifying species values and immutability.
]]

local Shared = script.Parent.Parent
local Types = require(Shared:WaitForChild("Types"))

local byId: { [Types.SpeciesId]: Types.SpeciesDefinition } = {
	StarSlime = table.freeze({
		Id = "StarSlime",
		DisplayName = "Star-Slime",
		HatchSeconds = 15,
		CoinsPerSecond = 2,
		SellPrice = 40,
		BodyColor = Color3.fromRGB(95, 225, 165),
		AccentColor = Color3.fromRGB(255, 225, 95),
		DisplayScale = Vector3.new(2.6, 2.2, 2.6),
		Description = "A bouncy cosmic jelly critter that hatches fast and glows softly.",
	}),
	NebulaFox = table.freeze({
		Id = "NebulaFox",
		DisplayName = "Nebula Fox",
		HatchSeconds = 35,
		CoinsPerSecond = 4,
		SellPrice = 95,
		BodyColor = Color3.fromRGB(165, 115, 255),
		AccentColor = Color3.fromRGB(95, 220, 255),
		DisplayScale = Vector3.new(2.8, 2.8, 3.2),
		Description = "A quick sky-tailed fox with star-dusted ears.",
	}),
	SolarGolem = table.freeze({
		Id = "SolarGolem",
		DisplayName = "Solar Golem",
		HatchSeconds = 60,
		CoinsPerSecond = 7,
		SellPrice = 180,
		BodyColor = Color3.fromRGB(255, 175, 65),
		AccentColor = Color3.fromRGB(255, 240, 145),
		DisplayScale = Vector3.new(3.8, 4.2, 3.4),
		Description = "A chunky golden guardian powered by warm starlight.",
	}),
}

local orderedIds: { Types.SpeciesId } = table.freeze({
	"StarSlime",
	"NebulaFox",
	"SolarGolem",
})

local CritterConfig = {
	OrderedIds = orderedIds,
	ById = table.freeze(byId),
}

return table.freeze(CritterConfig)
