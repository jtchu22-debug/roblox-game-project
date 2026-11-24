--!strict
--[[
	Module: ToolConfig
	Purpose: Declarative registry and helpers for the 3 Launch Cracker tools (Starter, Frost, Astral).
	Connections: Read by ToolVisualController, CrackController, ApplyHeroMeshTemplateDefaults, and SharedSelfTest.
	How to Test in Studio: Press Play (F5) to run SharedSelfTest verifying tool definitions and upgrade mapping.
]]

local Shared = script.Parent.Parent
local Types = require(Shared:WaitForChild("Types"))

local byId: { [Types.CrackerToolId]: Types.CrackerToolDefinition } = {
	StarterCracker = table.freeze({
		Id = "StarterCracker",
		DisplayName = "Starter Cracker",
		RequiredUpgradeId = nil,
		WorkbenchZ = -24,
		HandleColor = Color3.fromRGB(142, 92, 54),
		GripColor = Color3.fromRGB(96, 60, 38),
		BandColor = Color3.fromRGB(198, 128, 72),
		HeadColor = Color3.fromRGB(238, 228, 208),
		AccentColor = Color3.fromRGB(85, 195, 185),
		HandleMaterial = Enum.Material.SmoothPlastic,
		BandMaterial = Enum.Material.Metal,
		HeadMaterial = Enum.Material.SmoothPlastic,
		AccentMaterial = Enum.Material.Neon,
	}),
	FrostCracker = table.freeze({
		Id = "FrostCracker",
		DisplayName = "Frost Cracker",
		RequiredUpgradeId = "FrostCracker",
		WorkbenchZ = -16,
		HandleColor = Color3.fromRGB(185, 152, 92),
		GripColor = Color3.fromRGB(28, 42, 74),
		BandColor = Color3.fromRGB(224, 218, 206),
		HeadColor = Color3.fromRGB(78, 118, 168),
		AccentColor = Color3.fromRGB(95, 232, 255),
		HandleMaterial = Enum.Material.Metal,
		BandMaterial = Enum.Material.SmoothPlastic,
		HeadMaterial = Enum.Material.SmoothPlastic,
		AccentMaterial = Enum.Material.Neon,
	}),
	AstralCracker = table.freeze({
		Id = "AstralCracker",
		DisplayName = "Astral Cracker",
		RequiredUpgradeId = "StarCracker",
		WorkbenchZ = -32,
		HandleColor = Color3.fromRGB(205, 164, 78),
		GripColor = Color3.fromRGB(30, 26, 48),
		BandColor = Color3.fromRGB(235, 224, 202),
		HeadColor = Color3.fromRGB(215, 174, 82),
		AccentColor = Color3.fromRGB(196, 110, 255),
		HandleMaterial = Enum.Material.Metal,
		BandMaterial = Enum.Material.SmoothPlastic,
		HeadMaterial = Enum.Material.Metal,
		AccentMaterial = Enum.Material.Neon,
	}),
}

local orderedIds: { Types.CrackerToolId } = table.freeze({
	"StarterCracker",
	"FrostCracker",
	"AstralCracker",
})

local ToolConfig = {
	MAX_TOOL_PARTS = 8,
	MAX_TOOL_TRIANGLES = 400,
	MAX_TOOL_DIMENSION_STUDS = 4.0,
	HELD_GRIP_OFFSET = CFrame.Angles(math.rad(15), 0, 0),
	OrderedIds = orderedIds,
	ById = table.freeze(byId),
}

function ToolConfig.IsToolOwned(toolId: Types.CrackerToolId, upgrades: { [string]: boolean }?): boolean
	local def = byId[toolId]
	if def == nil then
		return false
	end
	if def.RequiredUpgradeId == nil then
		return true
	end
	return upgrades ~= nil and upgrades[def.RequiredUpgradeId] == true
end

function ToolConfig.ResolveHeldCrackerId(upgrades: { [string]: boolean }?): Types.CrackerToolId
	if upgrades ~= nil and upgrades["StarCracker"] == true then
		return "AstralCracker"
	elseif upgrades ~= nil and upgrades["FrostCracker"] == true then
		return "FrostCracker"
	end
	return "StarterCracker"
end

return table.freeze(ToolConfig)
