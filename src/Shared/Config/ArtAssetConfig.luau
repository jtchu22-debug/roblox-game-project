--!strict
--[[
	Module: ArtAssetConfig
	Purpose: Single reusable S6-ART-03 artwork mapping keyed by stable Nav, Species, Meteor,
	         Tool, and Upgrade IDs. Keeps ImageId="" (never broken placeholder IDs) until final
	         Roblox Creator Hub uploads, pairing every entry with editable SVG/model sources and
	         Observatory fallback medallion colors/glyphs.
	Connections: Read by UIController and SharedSelfTest.
	How to Test in Studio: Press Play (F5) to run SharedSelfTest ArtAssetConfig coverage suite.
]]

local Shared = script.Parent.Parent
local ConfigFolder = script.Parent
local CritterConfig = require(ConfigFolder:WaitForChild("CritterConfig"))
local MeteorConfig = require(ConfigFolder:WaitForChild("MeteorConfig"))
local ToolConfig = require(ConfigFolder:WaitForChild("ToolConfig"))
local UpgradeConfig = require(ConfigFolder:WaitForChild("UpgradeConfig"))
local Types = require(Shared:WaitForChild("Types"))

export type ArtEntry = {
	Id: string,
	Label: string,
	Glyph: string,
	ImageId: string,
	PrimaryColor: Color3,
	SecondaryColor: Color3?,
	AccentColor: Color3,
	SourcePath: string,
}

local navById: { [string]: ArtEntry } = table.freeze({
	Hub = table.freeze({
		Id = "Hub",
		Label = "Hub",
		Glyph = "✦",
		ImageId = "",
		PrimaryColor = Color3.fromRGB(205, 115, 255),
		AccentColor = Color3.fromRGB(255, 205, 45),
		SourcePath = "tools/art/icons/nav/Hub.svg",
	}),
	Ranch = table.freeze({
		Id = "Ranch",
		Label = "Ranch",
		Glyph = "⌂",
		ImageId = "",
		PrimaryColor = Color3.fromRGB(95, 215, 145),
		AccentColor = Color3.fromRGB(245, 235, 220),
		SourcePath = "tools/art/icons/nav/Ranch.svg",
	}),
	Bag = table.freeze({
		Id = "Bag",
		Label = "Bag",
		Glyph = "◈",
		ImageId = "",
		PrimaryColor = Color3.fromRGB(65, 210, 255),
		AccentColor = Color3.fromRGB(245, 235, 220),
		SourcePath = "tools/art/icons/nav/Bag.svg",
	}),
	Guide = table.freeze({
		Id = "Guide",
		Label = "Guide",
		Glyph = "☉",
		ImageId = "",
		PrimaryColor = Color3.fromRGB(255, 205, 45),
		AccentColor = Color3.fromRGB(210, 164, 82),
		SourcePath = "tools/art/icons/nav/Guide.svg",
	}),
	Shop = table.freeze({
		Id = "Shop",
		Label = "Shop",
		Glyph = "★",
		ImageId = "",
		PrimaryColor = Color3.fromRGB(210, 164, 82),
		AccentColor = Color3.fromRGB(85, 195, 185),
		SourcePath = "tools/art/icons/nav/Shop.svg",
	}),
	Settings = table.freeze({
		Id = "Settings",
		Label = "Settings",
		Glyph = "⚙",
		ImageId = "",
		PrimaryColor = Color3.fromRGB(165, 160, 192),
		AccentColor = Color3.fromRGB(245, 240, 232),
		SourcePath = "tools/art/icons/nav/Settings.svg",
	}),
})

local speciesGlyphs: { [Types.SpeciesId]: string } = {
	StarSlime = "●",
	CinderPup = "▲",
	FrostBeetle = "◆",
	NebulaFox = "◈",
	SolarGolem = "■",
	CometOwl = "✦",
}

local crittersMap: { [string]: ArtEntry } = {}
for _, speciesId in ipairs(CritterConfig.OrderedIds) do
	local def = CritterConfig.ById[speciesId]
	crittersMap[speciesId] = table.freeze({
		Id = speciesId,
		Label = def.DisplayName,
		Glyph = speciesGlyphs[speciesId] or "●",
		ImageId = "",
		PrimaryColor = def.BodyColor,
		SecondaryColor = def.SecondaryColor,
		AccentColor = def.AccentColor,
		SourcePath = "tools/blender/exports/critters/" .. speciesId .. ".fbx",
	})
end
local crittersById = table.freeze(crittersMap)

local meteorGlyphs: { [Types.MeteorTraitId]: string } = {
	Ember = "▲",
	Frost = "❄",
	Astral = "★",
}

local meteorsMap: { [string]: ArtEntry } = {}
for _, traitId in ipairs(MeteorConfig.OrderedIds) do
	local def = MeteorConfig.ById[traitId]
	meteorsMap[traitId] = table.freeze({
		Id = traitId,
		Label = def.DisplayName,
		Glyph = meteorGlyphs[traitId] or "✦",
		ImageId = "",
		PrimaryColor = def.RockColor,
		SecondaryColor = def.CoreColor,
		AccentColor = def.TrailColor,
		SourcePath = "tools/art/icons/meteors/" .. traitId .. ".svg",
	})
end
local meteorsById = table.freeze(meteorsMap)

local toolsMap: { [string]: ArtEntry } = {}
for _, toolId in ipairs(ToolConfig.OrderedIds) do
	local def = ToolConfig.ById[toolId]
	toolsMap[toolId] = table.freeze({
		Id = toolId,
		Label = def.DisplayName,
		Glyph = if toolId == "AstralCracker" then "☽" elseif toolId == "FrostCracker" then "Ψ" else "⚒",
		ImageId = "",
		PrimaryColor = def.HeadColor,
		SecondaryColor = def.BandColor,
		AccentColor = def.AccentColor,
		SourcePath = "tools/art/icons/tools/" .. toolId .. ".svg",
	})
end
local toolsById = table.freeze(toolsMap)

local upgradesMap: { [string]: ArtEntry } = {}
for _, upgradeId in ipairs(UpgradeConfig.OrderedIds) do
	local def = UpgradeConfig.ById[upgradeId]
	local sourceSvg = if def.SlotCategory == "Pen"
		then "tools/art/icons/upgrades/PenSlot.svg"
		elseif def.SlotCategory == "Incubator" then "tools/art/icons/upgrades/Incubator.svg"
		elseif def.SlotCategory == "Bag" then "tools/art/icons/upgrades/BagCap.svg"
		elseif upgradeId == "StarCracker" then "tools/art/icons/tools/AstralCracker.svg"
		else "tools/art/icons/tools/FrostCracker.svg"
	local glyph = if def.SlotCategory == "Pen"
		then "⊞"
		elseif def.SlotCategory == "Incubator" then "◎"
		elseif def.SlotCategory == "Bag" then "◈"
		elseif upgradeId == "StarCracker" then "☽"
		else "Ψ"
	local accent = if upgradeId == "StarCracker"
		then Color3.fromRGB(205, 115, 255)
		elseif upgradeId == "FrostCracker" then Color3.fromRGB(65, 210, 255)
		else Color3.fromRGB(255, 205, 45)
	upgradesMap[upgradeId] = table.freeze({
		Id = upgradeId,
		Label = def.DisplayName,
		Glyph = glyph,
		ImageId = "",
		PrimaryColor = Color3.fromRGB(46, 42, 72),
		AccentColor = accent,
		SourcePath = sourceSvg,
	})
end
upgradesMap["FrostLure"] = table.freeze({
	Id = "FrostLure",
	Label = "Frost Lure",
	Glyph = "❄",
	ImageId = "",
	PrimaryColor = Color3.fromRGB(42, 108, 170),
	AccentColor = Color3.fromRGB(65, 210, 255),
	SourcePath = "tools/art/icons/upgrades/FrostLure.svg",
})
local upgradesById = table.freeze(upgradesMap)

local ArtAssetConfig = {
	Nav = navById,
	Critters = crittersById,
	Meteors = meteorsById,
	Tools = toolsById,
	Upgrades = upgradesById,
}

function ArtAssetConfig.GetNavArt(navId: string): ArtEntry?
	return navById[navId]
end

function ArtAssetConfig.GetSpeciesArt(speciesId: Types.SpeciesId): ArtEntry?
	return crittersById[speciesId]
end

function ArtAssetConfig.GetMeteorArt(traitId: Types.MeteorTraitId): ArtEntry?
	return meteorsById[traitId]
end

function ArtAssetConfig.GetToolArt(toolId: Types.CrackerToolId): ArtEntry?
	return toolsById[toolId]
end

function ArtAssetConfig.GetUpgradeArt(upgradeId: string): ArtEntry?
	return upgradesById[upgradeId]
end

function ArtAssetConfig.ValidateCatalogCoverage(): number
	local count = 0
	for _, navId in ipairs({ "Hub", "Ranch", "Bag", "Guide", "Shop", "Settings" }) do
		assert(navById[navId] ~= nil, "Missing Nav art: " .. navId)
		count += 1
	end
	for _, speciesId in ipairs(CritterConfig.OrderedIds) do
		assert(crittersById[speciesId] ~= nil, "Missing Species art: " .. speciesId)
		count += 1
	end
	for _, traitId in ipairs(MeteorConfig.OrderedIds) do
		assert(meteorsById[traitId] ~= nil, "Missing Meteor art: " .. traitId)
		count += 1
	end
	for _, toolId in ipairs(ToolConfig.OrderedIds) do
		assert(toolsById[toolId] ~= nil, "Missing Tool art: " .. toolId)
		count += 1
	end
	for _, upgradeId in ipairs(UpgradeConfig.OrderedIds) do
		assert(upgradesById[upgradeId] ~= nil, "Missing Upgrade art: " .. upgradeId)
		count += 1
	end
	assert(upgradesById["FrostLure"] ~= nil, "Missing FrostLure art")
	count += 1
	return count
end

return table.freeze(ArtAssetConfig)
