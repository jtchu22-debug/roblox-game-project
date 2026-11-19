--!strict
--[[
	Module: ValidationUtil
	Purpose: Pure type, finite-number, integer, bounded-string, and enum guards for inbound payloads.
	Connections: Used by NetworkService and Server Services before mutating state.
	How to Test in Studio: Verified automatically by SharedSelfTest on Play (F5) including NaN/inf/bad-enum cases.
]]

local Shared = script.Parent.Parent
local ConfigFolder = Shared:WaitForChild("Config")
local CritterConfig = require(ConfigFolder:WaitForChild("CritterConfig"))
local MeteorConfig = require(ConfigFolder:WaitForChild("MeteorConfig"))
local UpgradeConfig = require(ConfigFolder:WaitForChild("UpgradeConfig"))

local VALID_PLOT_ACTIONS: { [string]: boolean } = table.freeze({
	StartIncubate = true,
	Hatch = true,
	PlaceInPen = true,
	RemoveFromPen = true,
	SellCritter = true,
	FeedCritter = true,
})

local ValidationUtil = {}

function ValidationUtil.IsFiniteNumber(value: unknown): boolean
	if typeof(value) ~= "number" then
		return false
	end
	return value == value and math.abs(value) ~= math.huge
end

function ValidationUtil.IsFiniteInteger(value: unknown): boolean
	if not ValidationUtil.IsFiniteNumber(value) then
		return false
	end
	return (value :: number) % 1 == 0
end

function ValidationUtil.IsNonNegativeInteger(value: unknown): boolean
	if not ValidationUtil.IsFiniteInteger(value) then
		return false
	end
	return (value :: number) >= 0
end

function ValidationUtil.IsBoundedString(value: unknown, maxLength: number): boolean
	if typeof(value) ~= "string" then
		return false
	end
	local str = value :: string
	return #str > 0 and #str <= maxLength
end

function ValidationUtil.IsValidSpeciesId(value: unknown): boolean
	if typeof(value) ~= "string" then
		return false
	end
	return (CritterConfig.ById :: { [string]: any })[value :: string] ~= nil
end

function ValidationUtil.IsValidMeteorTraitId(value: unknown): boolean
	if typeof(value) ~= "string" then
		return false
	end
	return (MeteorConfig.ById :: { [string]: any })[value :: string] ~= nil
end

function ValidationUtil.IsValidUpgradeId(value: unknown): boolean
	if typeof(value) ~= "string" then
		return false
	end
	return (UpgradeConfig.ById :: { [string]: any })[value :: string] ~= nil
end

function ValidationUtil.IsValidPlotAction(value: unknown): boolean
	if typeof(value) ~= "string" then
		return false
	end
	return VALID_PLOT_ACTIONS[value :: string] == true
end

return ValidationUtil
