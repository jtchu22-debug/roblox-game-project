--!strict
--[[
	Module: SharedSelfTest
	Purpose: Automated deterministic unit tests verifying S1-01 config integrity, bounded integer math, formatting, and validation guards.
	Connections: Executed on Server startup by ServerInit when Constants.RUN_SELF_TESTS is true.
	How to Test in Studio: Press Play (F5) and look for "[StarfallRanch][SelfTest] PASS" in the Output window.
]]

local Shared = script.Parent.Parent
local Constants = require(Shared:WaitForChild("Constants"))
local Types = require(Shared:WaitForChild("Types"))
local ConfigFolder = Shared:WaitForChild("Config")
local CritterConfig = require(ConfigFolder:WaitForChild("CritterConfig"))
local MeteorConfig = require(ConfigFolder:WaitForChild("MeteorConfig"))
local UpgradeConfig = require(ConfigFolder:WaitForChild("UpgradeConfig"))

local UtilFolder = script.Parent
local EconomyMath = require(UtilFolder:WaitForChild("EconomyMath"))
local FormatUtil = require(UtilFolder:WaitForChild("FormatUtil"))
local ValidationUtil = require(UtilFolder:WaitForChild("ValidationUtil"))

local SharedSelfTest = {}

local function runTest(name: string, fn: () -> ()): ()
	local ok, err = pcall(fn)
	if not ok then
		error(string.format("[StarfallRanch][SelfTest] FAIL in '%s': %s", name, tostring(err)))
	end
end

function SharedSelfTest.RunAll(): number
	local passedCount = 0

	runTest("Configs_Integrity_And_Immutability", function()
		assert(#CritterConfig.OrderedIds == 3, "Expected 3 Critter species")
		assert(#MeteorConfig.OrderedIds == 3, "Expected 3 Meteor traits")
		assert(#UpgradeConfig.OrderedIds == 3, "Expected 3 Ranch upgrades")

		for _, speciesId in ipairs(CritterConfig.OrderedIds) do
			local def = CritterConfig.ById[speciesId]
			assert(def ~= nil, "Missing species definition")
			assert(def.HatchSeconds > 0 and def.HatchSeconds % 1 == 0, "HatchSeconds must be positive integer")
			assert(def.CoinsPerSecond > 0 and def.CoinsPerSecond % 1 == 0, "CoinsPerSecond must be positive integer")
			assert(def.SellPrice > 0 and def.SellPrice % 1 == 0, "SellPrice must be positive integer")
		end

		for _, traitId in ipairs(MeteorConfig.OrderedIds) do
			local trait = MeteorConfig.ById[traitId]
			assert(trait ~= nil, "Missing meteor trait")
			local sum = 0
			for _, speciesId in ipairs(CritterConfig.OrderedIds) do
				sum += (trait.DropWeights[speciesId] or 0)
			end
			assert(sum == 100, "DropWeights should sum to 100")
		end

		local mutateOk = pcall(function()
			(Constants :: any).MAX_COINS = 999
		end)
		assert(not mutateOk, "Constants must be frozen")

		local mutateConfigOk = pcall(function()
			(CritterConfig.ById.StarSlime :: any).CoinsPerSecond = 999
		end)
		assert(not mutateConfigOk, "CritterConfig entries must be deeply frozen")
	end)
	passedCount += 1

	runTest("EconomyMath_Exact_And_Fractional_Settlement", function()
		-- 2 Coins/s for 60s must equal exactly 120 Coins and 0 remainder
		local coins, frac = EconomyMath.SettleElapsedCoins(0, 0, 2, 60, Constants.MAX_COINS)
		assert(coins == 120 and frac == 0, string.format("Expected 120/0, got %d/%f", coins, frac))

		-- 10 steps of 0.3s at 2 Coins/s must accumulate without floating-point drift loss
		local stepCoins, stepFrac = 0, 0
		for _ = 1, 10 do
			stepCoins, stepFrac = EconomyMath.SettleElapsedCoins(stepCoins, stepFrac, 2, 0.3, Constants.MAX_COINS)
		end
		assert(stepCoins == 6 and stepFrac == 0, string.format("Expected 6/0 after 3s, got %d/%f", stepCoins, stepFrac))

		-- Negative, NaN, and Inf elapsed time must never subtract or corrupt coins
		local negCoins, negFrac = EconomyMath.SettleElapsedCoins(50, 0.5, 2, -10, Constants.MAX_COINS)
		assert(negCoins == 50 and negFrac == 0.5, "Negative dt must be ignored")

		local nanCoins, nanFrac = EconomyMath.SettleElapsedCoins(50, 0.5, 2, 0 / 0, Constants.MAX_COINS)
		assert(nanCoins == 50 and nanFrac == 0.5, "NaN dt must be ignored")

		-- Cap clamping zeroes pending remainder
		local capCoins, capFrac = EconomyMath.SettleElapsedCoins(Constants.MAX_COINS - 1, 0.4, 10, 5, Constants.MAX_COINS)
		assert(capCoins == Constants.MAX_COINS and capFrac == 0, "Coins must clamp cleanly at MAX_COINS")
	end)
	passedCount += 1

	runTest("EconomyMath_ActivePenRate_And_DeterministicRolls", function()
		local items: { [string]: Types.CritterItemRecord } = {
			a = {
				UID = "a",
				SpeciesId = "StarSlime",
				Variant = "Normal",
				State = "InPen",
				AssignedSlot = "Pen_1",
				PlantedAt = nil,
				MaturesAt = nil,
				CreatedAt = 0,
			},
			b = {
				UID = "b",
				SpeciesId = "NebulaFox",
				Variant = "Radiant",
				State = "InPen",
				AssignedSlot = "Pen_2",
				PlantedAt = nil,
				MaturesAt = nil,
				CreatedAt = 0,
			},
			c = {
				UID = "c",
				SpeciesId = "SolarGolem",
				Variant = "Normal",
				State = "HatchedInBag", -- Not in pen!
				AssignedSlot = nil,
				PlantedAt = nil,
				MaturesAt = nil,
				CreatedAt = 0,
			},
			d = {
				UID = "d",
				SpeciesId = "SolarGolem",
				Variant = "Normal",
				State = "PodInBag", -- Not hatched!
				AssignedSlot = nil,
				PlantedAt = nil,
				MaturesAt = nil,
				CreatedAt = 0,
			},
		}

		local rate = EconomyMath.CalculateActivePenRate(items)
		assert(rate == 6, string.format("Expected active pen rate 6, got %d", rate))

		-- Verify Ember never drops SolarGolem and Astral never drops StarSlime
		local rng = Random.new(12345)
		for _ = 1, 25 do
			local emberDrop = EconomyMath.RollSpeciesForMeteorTrait("Ember", rng)
			assert(emberDrop == "StarSlime" or emberDrop == "NebulaFox", "Unexpected Ember drop")

			local astralDrop = EconomyMath.RollSpeciesForMeteorTrait("Astral", rng)
			assert(astralDrop == "NebulaFox" or astralDrop == "SolarGolem", "Unexpected Astral drop")
		end
	end)
	passedCount += 1

	runTest("FormatUtil_Formatting_And_Safety", function()
		assert(FormatUtil.FormatCoins(0) == "0", "0 coins format")
		assert(FormatUtil.FormatCoins(1250) == "1,250", "1,250 coins format")
		assert(FormatUtil.FormatCoins(1000000) == "1,000,000", "1,000,000 coins format")
		assert(FormatUtil.FormatCoins(-42) == "0", "Negative coins clamp to 0")
		assert(FormatUtil.FormatCoins(0 / 0) == "0", "NaN coins format safely to 0")
		assert(FormatUtil.FormatTimer(65) == "01:05", "65s timer")
		assert(FormatUtil.FormatTimer(-5) == "00:00", "Negative timer clamps to 00:00")
		assert(FormatUtil.FormatRate(7) == "+7 Coins/s", "Rate string format")
	end)
	passedCount += 1

	runTest("ValidationUtil_Rejects_Invalid_Payloads", function()
		assert(ValidationUtil.IsFiniteInteger(42), "42 is finite int")
		assert(not ValidationUtil.IsFiniteInteger(0 / 0), "NaN rejected")
		assert(not ValidationUtil.IsFiniteInteger(math.huge), "+inf rejected")
		assert(not ValidationUtil.IsFiniteInteger(-math.huge), "-inf rejected")
		assert(not ValidationUtil.IsFiniteInteger(1.5), "Float rejected")
		assert(not ValidationUtil.IsNonNegativeInteger(-1), "Negative int rejected")
		assert(ValidationUtil.IsBoundedString("PenSlot_2", Constants.MAX_STRING_ID_LENGTH), "Valid string accepted")
		assert(not ValidationUtil.IsBoundedString("", Constants.MAX_STRING_ID_LENGTH), "Empty string rejected")
		assert(not ValidationUtil.IsBoundedString(string.rep("a", 41), Constants.MAX_STRING_ID_LENGTH), "Oversized string rejected")
		assert(not ValidationUtil.IsBoundedString(123, Constants.MAX_STRING_ID_LENGTH), "Non-string rejected")

		assert(ValidationUtil.IsValidSpeciesId("StarSlime"), "Valid species accepted")
		assert(not ValidationUtil.IsValidSpeciesId("Dragon"), "Invalid species rejected")
		assert(ValidationUtil.IsValidMeteorTraitId("Astral"), "Valid meteor trait accepted")
		assert(not ValidationUtil.IsValidMeteorTraitId("Gold"), "Invalid meteor trait rejected")
		assert(ValidationUtil.IsValidUpgradeId("PenSlot_2"), "Valid upgrade accepted")
		assert(not ValidationUtil.IsValidUpgradeId("Rebirth_1"), "Invalid upgrade rejected")
		assert(ValidationUtil.IsValidPlotAction("PlaceInPen"), "Valid action accepted")
		assert(not ValidationUtil.IsValidPlotAction("GiftItem"), "Cut gifting action rejected")
	end)
	passedCount += 1

	return passedCount
end

return SharedSelfTest
