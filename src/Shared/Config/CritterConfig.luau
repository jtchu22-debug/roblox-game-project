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
		Rarity = "Common",
		HatchSeconds = 15,
		CoinsPerSecond = 2,
		SellPrice = 40,
		BodyColor = Color3.fromRGB(95, 225, 165),
		AccentColor = Color3.fromRGB(255, 225, 95),
		DisplayScale = Vector3.new(2.6, 2.2, 2.6),
		FieldClue = "Ember Meteors (South Basin)",
		Description = "A bouncy cosmic jelly critter that hatches fast and glows softly.",
	}),
	CinderPup = table.freeze({
		Id = "CinderPup",
		DisplayName = "Cinder Pup",
		Rarity = "Uncommon",
		HatchSeconds = 25,
		CoinsPerSecond = 3,
		SellPrice = 65,
		BodyColor = Color3.fromRGB(255, 125, 85),
		AccentColor = Color3.fromRGB(255, 215, 90),
		DisplayScale = Vector3.new(2.7, 2.4, 3.0),
		FieldClue = "Ember Meteors (South Basin)",
		Description = "An eager ember-eared pup with a warm comet tail.",
	}),
	FrostBeetle = table.freeze({
		Id = "FrostBeetle",
		DisplayName = "Frost Beetle",
		Rarity = "Uncommon",
		HatchSeconds = 35,
		CoinsPerSecond = 4,
		SellPrice = 90,
		BodyColor = Color3.fromRGB(85, 205, 245),
		AccentColor = Color3.fromRGB(185, 245, 255),
		DisplayScale = Vector3.new(2.9, 2.1, 3.2),
		FieldClue = "North Frost Ridge (Needs Frost Cracker)",
		Description = "An armored crystal beetle that chills the air around it.",
	}),
	NebulaFox = table.freeze({
		Id = "NebulaFox",
		DisplayName = "Nebula Fox",
		Rarity = "Rare",
		HatchSeconds = 45,
		CoinsPerSecond = 7,
		SellPrice = 150,
		BodyColor = Color3.fromRGB(165, 115, 255),
		AccentColor = Color3.fromRGB(95, 220, 255),
		DisplayScale = Vector3.new(2.8, 2.8, 3.2),
		FieldClue = "Rare on North Frost Ridge or Astral Falls",
		Description = "A quick sky-tailed fox with star-dusted ears.",
	}),
	SolarGolem = table.freeze({
		Id = "SolarGolem",
		DisplayName = "Solar Golem",
		Rarity = "Epic",
		HatchSeconds = 60,
		CoinsPerSecond = 11,
		SellPrice = 240,
		BodyColor = Color3.fromRGB(255, 175, 65),
		AccentColor = Color3.fromRGB(255, 240, 145),
		DisplayScale = Vector3.new(3.8, 4.2, 3.4),
		FieldClue = "Timed Astral Falls (Needs Astral Cracker)",
		Description = "A chunky golden guardian powered by warm starlight.",
	}),
	CometOwl = table.freeze({
		Id = "CometOwl",
		DisplayName = "Comet Owl",
		Rarity = "Legendary",
		HatchSeconds = 75,
		CoinsPerSecond = 18,
		SellPrice = 400,
		BodyColor = Color3.fromRGB(105, 85, 210),
		AccentColor = Color3.fromRGB(255, 215, 85),
		DisplayScale = Vector3.new(3.2, 3.6, 3.0),
		FieldClue = "Ultra-rare from timed Astral Falls (10%)",
		Description = "A midnight stargazer with sweeping comet wings.",
	}),
}

local orderedIds: { Types.SpeciesId } = table.freeze({
	"StarSlime",
	"CinderPup",
	"FrostBeetle",
	"NebulaFox",
	"SolarGolem",
	"CometOwl",
})

local CritterConfig = {
	OrderedIds = orderedIds,
	ById = table.freeze(byId),
}

return table.freeze(CritterConfig)
