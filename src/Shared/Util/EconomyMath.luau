--!strict
--[[
	Module: EconomyMath
	Purpose: Pure, deterministic integer coin settlement, pen rate summation, and weighted meteor rolling.
	Connections: Called exclusively on Server by EconomyService and MeteorService; formatting helpers pair with UI.
	How to Test in Studio: Press Play (F5) to run SharedSelfTest automatically and verify all assertions pass.
]]

local Shared = script.Parent.Parent
local Constants = require(Shared:WaitForChild("Constants"))
local Types = require(Shared:WaitForChild("Types"))
local ConfigFolder = Shared:WaitForChild("Config")
local CritterConfig = require(ConfigFolder:WaitForChild("CritterConfig"))
local MeteorConfig = require(ConfigFolder:WaitForChild("MeteorConfig"))

local FLOAT_EPSILON = 1e-9

local EconomyMath = {}

local function isFinite(value: number): boolean
	return typeof(value) == "number" and value == value and math.abs(value) ~= math.huge
end

function EconomyMath.GetCritterCoinsPerSecond(speciesId: Types.SpeciesId, variant: Types.VariantId): number
	local species = CritterConfig.ById[speciesId]
	assert(species ~= nil, string.format("Unknown SpeciesId: %s", tostring(speciesId)))

	local bonus = if variant == "Radiant" then Constants.RADIANT_BONUS_COINS_PER_SEC else 0
	return species.CoinsPerSecond + bonus
end

function EconomyMath.GetCritterSellPrice(speciesId: Types.SpeciesId, variant: Types.VariantId): number
	local species = CritterConfig.ById[speciesId]
	assert(species ~= nil, string.format("Unknown SpeciesId: %s", tostring(speciesId)))

	local bonus = if variant == "Radiant" then Constants.RADIANT_BONUS_SELL_COINS else 0
	return species.SellPrice + bonus
end

function EconomyMath.CalculateActivePenRate(items: { [string]: Types.CritterItemRecord }): number
	local totalRate = 0
	for _, record in pairs(items) do
		if record.State == "InPen" and record.AssignedSlot ~= nil then
			totalRate += EconomyMath.GetCritterCoinsPerSecond(record.SpeciesId, record.Variant)
		end
	end
	return totalRate
end

function EconomyMath.SettleElapsedCoins(
	currentCoins: number,
	pendingFraction: number,
	coinsPerSecond: number,
	elapsedSeconds: number,
	coinCap: number
): (number, number)
	local safeCap = if isFinite(coinCap) and coinCap >= 0 then math.floor(coinCap) else Constants.MAX_COINS
	local safeCoins = if isFinite(currentCoins) and currentCoins > 0 then math.floor(currentCoins) else 0
	safeCoins = math.min(safeCoins, safeCap)

	local safeFraction = if isFinite(pendingFraction) and pendingFraction > 0 and pendingFraction < 1
		then pendingFraction
		else 0

	if safeCoins >= safeCap then
		return safeCap, 0
	end

	if not isFinite(coinsPerSecond) or coinsPerSecond <= 0 then
		return safeCoins, safeFraction
	end
	if not isFinite(elapsedSeconds) or elapsedSeconds <= 0 then
		return safeCoins, safeFraction
	end

	local totalEarned = safeFraction + (coinsPerSecond * elapsedSeconds)
	if not isFinite(totalEarned) then
		return safeCap, 0
	end

	local wholeCoins = math.floor(totalEarned + FLOAT_EPSILON)
	local nextFraction = math.max(0, totalEarned - wholeCoins)
	if nextFraction >= 1 then
		nextFraction = 0
	end

	local nextCoins = safeCoins + wholeCoins
	if nextCoins >= safeCap then
		return safeCap, 0
	end

	return nextCoins, nextFraction
end

function EconomyMath.RollSpeciesForMeteorTrait(traitId: Types.MeteorTraitId, rng: Random): Types.SpeciesId
	local trait = MeteorConfig.ById[traitId]
	assert(trait ~= nil, string.format("Unknown MeteorTraitId: %s", tostring(traitId)))

	local totalWeight = 0
	for _, speciesId in ipairs(CritterConfig.OrderedIds) do
		local weight = trait.DropWeights[speciesId] or 0
		if weight > 0 then
			totalWeight += weight
		end
	end
	assert(totalWeight > 0, string.format("MeteorTrait %s has zero total drop weight", tostring(traitId)))

	local roll = rng:NextNumber() * totalWeight
	local cumulative = 0
	local lastEligible: Types.SpeciesId = CritterConfig.OrderedIds[1]

	for _, speciesId in ipairs(CritterConfig.OrderedIds) do
		local weight = trait.DropWeights[speciesId] or 0
		if weight > 0 then
			lastEligible = speciesId
			cumulative += weight
			if roll <= cumulative then
				return speciesId
			end
		end
	end

	return lastEligible
end

function EconomyMath.RollVariant(rng: Random): Types.VariantId
	if rng:NextNumber() < Constants.RADIANT_HATCH_CHANCE then
		return "Radiant"
	end
	return "Normal"
end

return EconomyMath
