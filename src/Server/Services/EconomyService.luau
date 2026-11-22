--!strict
--[[
	Service: EconomyService
	Purpose: Single authoritative state writer for player Items, Slots, Coins, Upgrades, fractional elapsed
	         coin settlement, reserved incubator hatch capacity, and Keep-vs-Sell transitions.
	Connections: Reads DataService ready profiles and Shared Config; binds NetworkService PlotAction/BuyUpgrade
	             handlers; notifies PlotService via OnPlotStateChanged when public plot visuals change.
	How to Test in Studio: Press Play (F5) to run EconomyService.RunSelfTest() and inspect Output.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Types = require(Shared:WaitForChild("Types"))
local ConfigFolder = Shared:WaitForChild("Config")
local CritterConfig = require(ConfigFolder:WaitForChild("CritterConfig"))
local UpgradeConfig = require(ConfigFolder:WaitForChild("UpgradeConfig"))
local EconomyMath = require(Shared:WaitForChild("Util"):WaitForChild("EconomyMath"))

local ServicesFolder = script.Parent
local DataService = require(ServicesFolder:WaitForChild("DataService"))
local NetworkService = require(ServicesFolder:WaitForChild("NetworkService"))

export type EconomyResult = {
	Ok: boolean,
	Reason: string?,
	ItemUID: string?,
	SpeciesId: Types.SpeciesId?,
	Variant: Types.VariantId?,
	CoinsEarned: number?,
}

local VALID_VARIANTS: { [string]: boolean } = table.freeze({
	Normal = true,
	Radiant = true,
})

local VALID_STATES: { [string]: boolean } = table.freeze({
	PodInBag = true,
	Incubating = true,
	HatchedInBag = true,
	InPen = true,
})

local INCUBATOR_SLOTS: { [string]: boolean } = table.freeze({
	Incubator_1 = true,
	Incubator_2 = true,
})

local PEN_SLOTS: { [string]: boolean } = table.freeze({
	Pen_1 = true,
	Pen_2 = true,
	Pen_3 = true,
	Pen_4 = true,
	Pen_5 = true,
})

local EconomyService = {
	Name = "EconomyService",
}

export type StationAuthorizer = (player: Player, stationKind: string, targetId: string) -> (boolean, string)
export type LureSpawner = (userId: number, displayName: string, trait: Types.MeteorTraitId, nowClock: number) -> (boolean, string)

local serverRng = Random.new()
local plotStateListeners: { (player: Player) -> () } = {}
local stationAuthorizer: StationAuthorizer? = nil
local lureSpawner: LureSpawner? = nil
local accrualRunning = false
local beforeSaveRegistered = false

local function notifyPlotChanged(player: Player): ()
	for _, cb in ipairs(plotStateListeners) do
		local ok, err = pcall(cb, player)
		if not ok then
			warn("[EconomyService] OnPlotStateChanged callback error: " .. tostring(err))
		end
	end
end

local function isFiniteInRange(value: number, minVal: number, maxVal: number): boolean
	return typeof(value) == "number"
		and value == value
		and math.abs(value) ~= math.huge
		and value >= minVal
		and value <= maxVal
end

local function isFiniteIntInRange(value: number, minVal: number, maxVal: number): boolean
	return isFiniteInRange(value, minVal, maxVal) and value % 1 == 0
end

function EconomyService.IsUnlockedIncubatorSlot(profile: Types.PlayerProfileData, slotId: string): boolean
	if slotId == "Incubator_1" then
		return true
	elseif slotId == "Incubator_2" then
		return profile.Upgrades["Incubator_2"] == true
	end
	return false
end

function EconomyService.IsUnlockedPenSlot(profile: Types.PlayerProfileData, slotId: string): boolean
	if slotId == "Pen_1" then
		return true
	elseif slotId == "Pen_2" then
		return profile.Upgrades["PenSlot_2"] == true
	elseif slotId == "Pen_3" then
		return profile.Upgrades["PenSlot_3"] == true
	elseif slotId == "Pen_4" then
		return profile.Upgrades["PenSlot_4"] == true
	elseif slotId == "Pen_5" then
		return profile.Upgrades["PenSlot_5"] == true
	end
	return false
end

function EconomyService.GetBagCapacity(profile: Types.PlayerProfileData): number
	if profile.Upgrades["BagCap_20"] == true then
		return Constants.MAX_BAG_CAPACITY_UPGRADED
	end
	return Constants.MAX_BAG_CAPACITY
end

function EconomyService.GetBagCount(profile: Types.PlayerProfileData): number
	local count = 0
	for _, item in pairs(profile.Items) do
		if item.State == "PodInBag" or item.State == "HatchedInBag" then
			count += 1
		end
	end
	return count
end

function EconomyService.GetOccupiedIncubatorCount(profile: Types.PlayerProfileData): number
	local count = 0
	for _, item in pairs(profile.Items) do
		if item.State == "Incubating" then
			count += 1
		end
	end
	return count
end

function EconomyService.GetCommittedBagCount(profile: Types.PlayerProfileData): number
	return EconomyService.GetBagCount(profile) + EconomyService.GetOccupiedIncubatorCount(profile)
end

function EconomyService.HasUnreservedBagSpace(profile: Types.PlayerProfileData): boolean
	return EconomyService.GetCommittedBagCount(profile) < EconomyService.GetBagCapacity(profile)
end

function EconomyService.ValidateProfileInvariants(profile: Types.PlayerProfileData): (boolean, string)
	if not isFiniteIntInRange(profile.Coins, 0, Constants.MAX_COINS) then
		return false, "Coins out of bounds"
	end
	if typeof(profile.PendingFraction) ~= "number"
		or profile.PendingFraction ~= profile.PendingFraction
		or profile.PendingFraction < 0
		or profile.PendingFraction >= 1
	then
		return false, "PendingFraction invalid"
	end
	if not isFiniteInRange(profile.LastAccrualTimestamp, 0, 10_000_000_000) then
		return false, "LastAccrualTimestamp invalid"
	end
	if not isFiniteIntInRange(profile.Revision, 1, 1_000_000_000) then
		return false, "Revision invalid"
	end

	local bagCount = 0
	local incubatingCount = 0
	for itemKey, item in pairs(profile.Items) do
		if item.UID ~= itemKey then
			return false, "Item UID key mismatch: " .. tostring(itemKey)
		end
		if (CritterConfig.ById :: { [string]: any })[item.SpeciesId] == nil then
			return false, "Invalid SpeciesId on " .. item.UID
		end
		if not VALID_VARIANTS[item.Variant] then
			return false, "Invalid Variant on " .. item.UID
		end
		if not VALID_STATES[item.State] then
			return false, "Invalid State on " .. item.UID
		end
		if item.FeedLevel ~= nil and not isFiniteIntInRange(item.FeedLevel, 0, Constants.MAX_CRITTER_FEED_LEVEL) then
			return false, "Invalid FeedLevel on " .. item.UID
		end

		if item.State == "PodInBag" or item.State == "HatchedInBag" then
			bagCount += 1
			if item.AssignedSlot ~= nil then
				return false, "Bag item must not have AssignedSlot: " .. item.UID
			end
		elseif item.State == "Incubating" then
			incubatingCount += 1
			local slotId = item.AssignedSlot
			if slotId == nil or not EconomyService.IsUnlockedIncubatorSlot(profile, slotId) then
				return false, "Incubating item in invalid/locked slot: " .. item.UID
			end
			if profile.Slots[slotId] ~= item.UID then
				return false, "Incubator slot mapping mismatch: " .. slotId
			end
		elseif item.State == "InPen" then
			local slotId = item.AssignedSlot
			if slotId == nil or not EconomyService.IsUnlockedPenSlot(profile, slotId) then
				return false, "Pen item in invalid/locked slot: " .. item.UID
			end
			if profile.Slots[slotId] ~= item.UID then
				return false, "Pen slot mapping mismatch: " .. slotId
			end
		end
	end

	local bagCap = EconomyService.GetBagCapacity(profile)
	if bagCount > bagCap then
		return false, "BagCount exceeds BagCapacity"
	end
	if (bagCount + incubatingCount) > bagCap then
		return false, "Committed bag + incubating slots exceed BagCapacity"
	end

	for slotId, itemUID in pairs(profile.Slots) do
		local item = profile.Items[itemUID]
		if item == nil then
			return false, "Slot references missing item: " .. slotId
		end
		if item.AssignedSlot ~= slotId then
			return false, "Bidirectional slot mismatch on: " .. slotId
		end
		if INCUBATOR_SLOTS[slotId] then
			if item.State ~= "Incubating" or not EconomyService.IsUnlockedIncubatorSlot(profile, slotId) then
				return false, "Invalid incubator occupant: " .. slotId
			end
		elseif PEN_SLOTS[slotId] then
			if item.State ~= "InPen" or not EconomyService.IsUnlockedPenSlot(profile, slotId) then
				return false, "Invalid pen occupant: " .. slotId
			end
		else
			return false, "Unknown slotId in profile.Slots: " .. slotId
		end
	end

	return true, "Valid"
end

function EconomyService.SettleProfileCoins(profile: Types.PlayerProfileData, nowClock: number): boolean
	if not isFiniteInRange(nowClock, 0, 10_000_000_000) then
		return false
	end

	local elapsed = nowClock - profile.LastAccrualTimestamp
	if elapsed <= 0 then
		return false
	end

	local rate = EconomyMath.CalculateActivePenRate(profile.Items)
	profile.LastAccrualTimestamp = nowClock

	if rate <= 0 then
		return false
	end

	local nextCoins, nextFraction = EconomyMath.SettleElapsedCoins(
		profile.Coins,
		profile.PendingFraction,
		rate,
		elapsed,
		Constants.MAX_COINS
	)

	local coinsChanged = nextCoins ~= profile.Coins
	profile.Coins = nextCoins
	profile.PendingFraction = nextFraction

	if coinsChanged then
		profile.Revision += 1
		return true
	end
	return false
end

function EconomyService.GrantPodToProfile(
	profile: Types.PlayerProfileData,
	speciesId: Types.SpeciesId,
	nowClock: number,
	customUid: string?
): EconomyResult
	if (CritterConfig.ById :: { [string]: any })[speciesId] == nil then
		return { Ok = false, Reason = "InvalidSpecies" }
	end
	-- Reserve hatch space for every occupied incubator so bag+incubators can never deadlock.
	if not EconomyService.HasUnreservedBagSpace(profile) then
		return { Ok = false, Reason = "BagFull" }
	end

	local uid = if customUid ~= nil then customUid else HttpService:GenerateGUID(false)
	if profile.Items[uid] ~= nil then
		return { Ok = false, Reason = "DuplicateUID" }
	end

	profile.Items[uid] = {
		UID = uid,
		SpeciesId = speciesId,
		Variant = "Normal",
		State = "PodInBag",
		AssignedSlot = nil,
		PlantedAt = nil,
		MaturesAt = nil,
		CreatedAt = math.floor(nowClock),
		FeedLevel = 0,
	}
	profile.Revision += 1

	return {
		Ok = true,
		ItemUID = uid,
		SpeciesId = speciesId,
	}
end

function EconomyService.StartIncubateOnProfile(
	profile: Types.PlayerProfileData,
	slotId: string,
	itemUID: string,
	nowClock: number
): EconomyResult
	if not INCUBATOR_SLOTS[slotId] then
		return { Ok = false, Reason = "InvalidSlot" }
	end
	if not EconomyService.IsUnlockedIncubatorSlot(profile, slotId) then
		return { Ok = false, Reason = "SlotLocked" }
	end
	if profile.Slots[slotId] ~= nil then
		return { Ok = false, Reason = "SlotOccupied" }
	end

	local item = profile.Items[itemUID]
	if item == nil then
		return { Ok = false, Reason = "ItemNotFound" }
	end
	if item.State ~= "PodInBag" or item.AssignedSlot ~= nil then
		return { Ok = false, Reason = "ItemNotPodInBag" }
	end

	local speciesDef = CritterConfig.ById[item.SpeciesId]
	local plantedAt = math.floor(nowClock)

	item.State = "Incubating"
	item.AssignedSlot = slotId
	item.PlantedAt = plantedAt
	item.MaturesAt = plantedAt + speciesDef.HatchSeconds
	profile.Slots[slotId] = itemUID
	profile.Revision += 1

	return { Ok = true, ItemUID = itemUID }
end

function EconomyService.HatchFromSlotOnProfile(
	profile: Types.PlayerProfileData,
	slotId: string,
	nowClock: number,
	customRng: Random?
): EconomyResult
	if not INCUBATOR_SLOTS[slotId] then
		return { Ok = false, Reason = "InvalidSlot" }
	end
	local itemUID = profile.Slots[slotId]
	if itemUID == nil then
		return { Ok = false, Reason = "SlotEmpty" }
	end

	local item = profile.Items[itemUID]
	if item == nil or item.State ~= "Incubating" or item.AssignedSlot ~= slotId then
		return { Ok = false, Reason = "InvalidIncubatorState" }
	end
	if item.MaturesAt == nil or nowClock < item.MaturesAt then
		return { Ok = false, Reason = "NotMature" }
	end
	if EconomyService.GetBagCount(profile) >= EconomyService.GetBagCapacity(profile) then
		return { Ok = false, Reason = "BagFull" }
	end

	local variant = EconomyMath.RollVariant(customRng or serverRng)
	item.Variant = variant
	item.State = "HatchedInBag"
	item.AssignedSlot = nil
	item.PlantedAt = nil
	item.MaturesAt = nil
	profile.Slots[slotId] = nil
	profile.DiscoveredSpecies[item.SpeciesId] = true
	profile.Revision += 1

	return {
		Ok = true,
		ItemUID = itemUID,
		SpeciesId = item.SpeciesId,
		Variant = variant,
	}
end

function EconomyService.PlaceInPenOnProfile(
	profile: Types.PlayerProfileData,
	slotId: string,
	itemUID: string,
	nowClock: number
): EconomyResult
	if not PEN_SLOTS[slotId] then
		return { Ok = false, Reason = "InvalidSlot" }
	end
	if not EconomyService.IsUnlockedPenSlot(profile, slotId) then
		return { Ok = false, Reason = "SlotLocked" }
	end
	if profile.Slots[slotId] ~= nil then
		return { Ok = false, Reason = "SlotOccupied" }
	end

	local item = profile.Items[itemUID]
	if item == nil then
		return { Ok = false, Reason = "ItemNotFound" }
	end
	if item.State ~= "HatchedInBag" or item.AssignedSlot ~= nil then
		return { Ok = false, Reason = "ItemNotHatchedInBag" }
	end

	-- Settle elapsed coins using fractional clock at the OLD pen rate before adding critter.
	EconomyService.SettleProfileCoins(profile, nowClock)

	item.State = "InPen"
	item.AssignedSlot = slotId
	profile.Slots[slotId] = itemUID
	profile.Revision += 1

	return { Ok = true, ItemUID = itemUID }
end

function EconomyService.RemoveFromPenOnProfile(
	profile: Types.PlayerProfileData,
	slotId: string,
	nowClock: number
): EconomyResult
	if not PEN_SLOTS[slotId] then
		return { Ok = false, Reason = "InvalidSlot" }
	end
	local itemUID = profile.Slots[slotId]
	if itemUID == nil then
		return { Ok = false, Reason = "SlotEmpty" }
	end

	local item = profile.Items[itemUID]
	if item == nil or item.State ~= "InPen" or item.AssignedSlot ~= slotId then
		return { Ok = false, Reason = "InvalidPenState" }
	end
	-- Shared capacity check respects bag spaces reserved for incubating pods.
	if not EconomyService.HasUnreservedBagSpace(profile) then
		return { Ok = false, Reason = "BagFull" }
	end

	-- Settle elapsed coins using fractional clock at the OLD pen rate before removing critter.
	EconomyService.SettleProfileCoins(profile, nowClock)

	item.State = "HatchedInBag"
	item.AssignedSlot = nil
	profile.Slots[slotId] = nil
	profile.Revision += 1

	return { Ok = true, ItemUID = itemUID }
end

function EconomyService.SellCritterOnProfile(
	profile: Types.PlayerProfileData,
	itemUID: string,
	_nowClock: number
): EconomyResult
	local item = profile.Items[itemUID]
	if item == nil then
		return { Ok = false, Reason = "ItemNotFound" }
	end
	if item.State == "InPen" then
		return { Ok = false, Reason = "MustRemoveFromPenFirst" }
	end
	if item.State ~= "HatchedInBag" or item.AssignedSlot ~= nil then
		return { Ok = false, Reason = "CannotSellUnhatched" }
	end

	local sellPrice = EconomyMath.GetCritterSellPrice(item.SpeciesId, item.Variant, item.FeedLevel)
	local previousCoins = profile.Coins
	local nextCoins = math.min(Constants.MAX_COINS, previousCoins + sellPrice)
	local actualCredited = nextCoins - previousCoins

	profile.Items[itemUID] = nil
	profile.Coins = nextCoins
	profile.Revision += 1

	return {
		Ok = true,
		ItemUID = itemUID,
		CoinsEarned = actualCredited,
	}
end

function EconomyService.BuyUpgradeOnProfile(
	profile: Types.PlayerProfileData,
	upgradeId: Types.UpgradeId,
	_nowClock: number
): EconomyResult
	local def = UpgradeConfig.ById[upgradeId]
	if def == nil then
		return { Ok = false, Reason = "InvalidUpgrade" }
	end
	if profile.Upgrades[upgradeId] == true then
		return { Ok = false, Reason = "AlreadyOwned" }
	end
	if def.RequiresUpgradeId ~= nil and profile.Upgrades[def.RequiresUpgradeId] ~= true then
		return { Ok = false, Reason = "PrerequisiteRequired" }
	end
	if profile.Coins < def.Cost then
		return { Ok = false, Reason = "InsufficientCoins" }
	end

	profile.Coins -= def.Cost
	profile.Upgrades[upgradeId] = true
	profile.Revision += 1

	return { Ok = true }
end

function EconomyService.HasUpgrade(profile: Types.PlayerProfileData, upgradeId: Types.UpgradeId): boolean
	return profile.Upgrades[upgradeId] == true
end

function EconomyService.FeedCritterInPenOnProfile(
	profile: Types.PlayerProfileData,
	slotId: string,
	nowClock: number
): EconomyResult
	if not PEN_SLOTS[slotId] then
		return { Ok = false, Reason = "InvalidSlot" }
	end
	if not EconomyService.IsUnlockedPenSlot(profile, slotId) then
		return { Ok = false, Reason = "SlotLocked" }
	end

	local itemUID = profile.Slots[slotId]
	if itemUID == nil then
		return { Ok = false, Reason = "SlotEmpty" }
	end

	local item = profile.Items[itemUID]
	if item == nil or item.State ~= "InPen" or item.AssignedSlot ~= slotId then
		return { Ok = false, Reason = "InvalidPenState" }
	end

	local currentFeed = item.FeedLevel or 0
	if currentFeed >= Constants.MAX_CRITTER_FEED_LEVEL then
		return { Ok = false, Reason = "AlreadyFed" }
	end
	if profile.Coins < Constants.CRITTER_FEED_COST then
		return { Ok = false, Reason = "InsufficientCoins" }
	end

	-- Settle elapsed coins at the OLD rate before boosting this critter's Coins/s.
	EconomyService.SettleProfileCoins(profile, nowClock)

	profile.Coins -= Constants.CRITTER_FEED_COST
	item.FeedLevel = currentFeed + 1
	profile.Revision += 1

	return {
		Ok = true,
		ItemUID = itemUID,
		SpeciesId = item.SpeciesId,
	}
end

function EconomyService.SetLureSpawner(spawner: LureSpawner?): ()
	lureSpawner = spawner
end

function EconomyService.UseFrostLureOnProfile(
	profile: Types.PlayerProfileData,
	userId: number,
	displayName: string,
	nowClock: number,
	customSpawner: LureSpawner?
): EconomyResult
	if profile.Upgrades["FrostCracker"] ~= true then
		return { Ok = false, Reason = "ToolRequired" }
	end
	if profile.Coins < Constants.FROST_LURE_COST then
		return { Ok = false, Reason = "InsufficientCoins" }
	end
	if EconomyService.GetCommittedBagCount(profile) >= EconomyService.GetBagCapacity(profile) then
		return { Ok = false, Reason = "BagFull" }
	end

	local activeSpawner = customSpawner or lureSpawner
	if activeSpawner == nil then
		return { Ok = false, Reason = "LureUnavailable" }
	end

	local spawnOk, spawnReason = activeSpawner(userId, displayName, "Frost", nowClock)
	if not spawnOk then
		return { Ok = false, Reason = spawnReason }
	end

	EconomyService.SettleProfileCoins(profile, nowClock)
	profile.Coins -= Constants.FROST_LURE_COST
	profile.Revision += 1

	return { Ok = true }
end

function EconomyService.NotifyPlotChangedForPlayer(player: Player): ()
	notifyPlotChanged(player)
end

function EconomyService.GrantPod(player: Player, speciesId: Types.SpeciesId): EconomyResult
	if not DataService.IsReady(player) then
		return { Ok = false, Reason = "ProfileNotReady" }
	end
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return { Ok = false, Reason = "ProfileNotReady" }
	end

	local res = EconomyService.GrantPodToProfile(profile, speciesId, workspace:GetServerTimeNow())
	if res.Ok then
		DataService.SendOwnerStateSnapshot(player)
		notifyPlotChanged(player)
	end
	return res
end

function EconomyService.CheckStationAuthorization(player: Player?, stationKind: string, targetId: string): (boolean, string)
	-- Deny by default if PlotService has not registered an authorizer.
	if stationAuthorizer == nil then
		return false, "AuthorizerUnavailable"
	end
	if player == nil then
		return false, "PlayerUnavailable"
	end
	return stationAuthorizer(player, stationKind, targetId)
end

function EconomyService.HandlePlotAction(
	player: Player,
	action: Types.PlotAction,
	targetSlotOrUID: string,
	itemUID: string?
): EconomyResult
	if not DataService.IsReady(player) then
		return { Ok = false, Reason = "ProfileNotReady" }
	end
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return { Ok = false, Reason = "ProfileNotReady" }
	end

	local stationKind: string
	local stationTargetId: string
	if action == "StartIncubate" or action == "Hatch" then
		stationKind = "Incubator"
		stationTargetId = targetSlotOrUID
	elseif action == "PlaceInPen" or action == "RemoveFromPen" or action == "FeedCritter" then
		stationKind = "Pen"
		stationTargetId = targetSlotOrUID
	elseif action == "SellCritter" then
		stationKind = "SellStand"
		stationTargetId = "SellStand"
	elseif action == "UseFrostLure" then
		stationKind = "LureStand"
		stationTargetId = "LureStand"
	else
		return { Ok = false, Reason = "InvalidAction" }
	end

	local authOk, authReason = EconomyService.CheckStationAuthorization(player, stationKind, stationTargetId)
	if not authOk then
		if action == "UseFrostLure" then
			NetworkService.SendMeteorLifecycleToPlayer(player, {
				Action = "LureFailed",
				Reason = authReason,
			})
		end
		return { Ok = false, Reason = authReason }
	end

	local nowClock = workspace:GetServerTimeNow()
	local res: EconomyResult
	local affectsPublicPlot = false
	local settledChanged = false

	if action == "StartIncubate" then
		res = EconomyService.StartIncubateOnProfile(profile, targetSlotOrUID, itemUID :: string, nowClock)
		affectsPublicPlot = true
	elseif action == "Hatch" then
		res = EconomyService.HatchFromSlotOnProfile(profile, targetSlotOrUID, nowClock)
		affectsPublicPlot = true
	elseif action == "PlaceInPen" then
		res = EconomyService.PlaceInPenOnProfile(profile, targetSlotOrUID, itemUID :: string, nowClock)
		affectsPublicPlot = true
	elseif action == "RemoveFromPen" then
		res = EconomyService.RemoveFromPenOnProfile(profile, targetSlotOrUID, nowClock)
		affectsPublicPlot = true
	elseif action == "FeedCritter" then
		settledChanged = EconomyService.SettleProfileCoins(profile, nowClock)
		res = EconomyService.FeedCritterInPenOnProfile(profile, targetSlotOrUID, nowClock)
		affectsPublicPlot = true
	elseif action == "UseFrostLure" then
		settledChanged = EconomyService.SettleProfileCoins(profile, nowClock)
		res = EconomyService.UseFrostLureOnProfile(profile, player.UserId, player.DisplayName, nowClock)
		if not res.Ok then
			NetworkService.SendMeteorLifecycleToPlayer(player, {
				Action = "LureFailed",
				Reason = res.Reason or "LureUnavailable",
			})
		end
	elseif action == "SellCritter" then
		res = EconomyService.SellCritterOnProfile(profile, targetSlotOrUID, nowClock)
		affectsPublicPlot = true
	else
		return { Ok = false, Reason = "InvalidAction" }
	end

	if res.Ok then
		DataService.SendOwnerStateSnapshot(player)
		if affectsPublicPlot then
			notifyPlotChanged(player)
		end
	elseif settledChanged then
		DataService.SendOwnerStateSnapshot(player)
	end
	return res
end

function EconomyService.HandleBuyUpgrade(player: Player, upgradeId: Types.UpgradeId): EconomyResult
	if not DataService.IsReady(player) then
		return { Ok = false, Reason = "ProfileNotReady" }
	end
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return { Ok = false, Reason = "ProfileNotReady" }
	end

	local authOk, authReason = EconomyService.CheckStationAuthorization(player, "UpgradePad", upgradeId)
	if not authOk then
		return { Ok = false, Reason = authReason }
	end

	local nowClock = workspace:GetServerTimeNow()
	local settledChanged = EconomyService.SettleProfileCoins(profile, nowClock)
	local res = EconomyService.BuyUpgradeOnProfile(profile, upgradeId, nowClock)

	if res.Ok then
		DataService.SendOwnerStateSnapshot(player)
		notifyPlotChanged(player)
	elseif settledChanged then
		DataService.SendOwnerStateSnapshot(player)
	end
	return res
end

function EconomyService.SetStationAuthorizer(authorizer: StationAuthorizer?): ()
	stationAuthorizer = authorizer
end

function EconomyService.OnPlotStateChanged(callback: (player: Player) -> ()): ()
	table.insert(plotStateListeners, callback)
end

local function ensureBeforeSaveRegistered(): ()
	if beforeSaveRegistered then
		return
	end
	beforeSaveRegistered = true
	DataService.OnBeforeSave(function(_player: Player?, profile: Types.PlayerProfileData)
		EconomyService.SettleProfileCoins(profile, workspace:GetServerTimeNow())
	end)
end

function EconomyService.Init(self: typeof(EconomyService)): ()
	ensureBeforeSaveRegistered()
end

function EconomyService.Start(self: typeof(EconomyService)): ()
	ensureBeforeSaveRegistered()

	NetworkService.BindPlotActionHandler(function(player: Player, action: Types.PlotAction, targetSlotOrUID: string, itemUID: string?)
		EconomyService.HandlePlotAction(player, action, targetSlotOrUID, itemUID)
	end)

	NetworkService.BindBuyUpgradeHandler(function(player: Player, upgradeId: Types.UpgradeId)
		return EconomyService.HandleBuyUpgrade(player, upgradeId)
	end)

	if not accrualRunning then
		accrualRunning = true
		task.spawn(function()
			while accrualRunning do
				task.wait(1)
				local nowClock = workspace:GetServerTimeNow()
				DataService.ForEachReadyPlayer(function(player: Player, profile: Types.PlayerProfileData)
					if EconomyService.SettleProfileCoins(profile, nowClock) then
						DataService.SendOwnerStateSnapshot(player)
					end
				end)
			end
		end)
	end
end

function EconomyService.RunSelfTest(): number
	local passed = 0
	local rng = Random.new(42)

	-- 1. Full happy-path lifecycle + invariant verification after every transition
	local profile = DataService.CreateDefaultProfile(1000)
	assert((EconomyService.ValidateProfileInvariants(profile)), "Default profile valid")

	local grantRes = EconomyService.GrantPodToProfile(profile, "StarSlime", 1000, "pod-1")
	assert(grantRes.Ok and EconomyService.GetBagCount(profile) == 1, "GrantPod creates PodInBag")
	assert((EconomyService.ValidateProfileInvariants(profile)), "Invariant valid after grant")

	local incRes = EconomyService.StartIncubateOnProfile(profile, "Incubator_1", "pod-1", 1005)
	assert(incRes.Ok and EconomyService.GetBagCount(profile) == 0 and EconomyService.GetOccupiedIncubatorCount(profile) == 1, "Incubate moves pod to reserved slot")
	assert(profile.Items["pod-1"].MaturesAt == 1020, "StarSlime matures in 15s")
	assert((EconomyService.ValidateProfileInvariants(profile)), "Invariant valid after start incubate")

	local hatchRes = EconomyService.HatchFromSlotOnProfile(profile, "Incubator_1", 1020, rng)
	assert(hatchRes.Ok and profile.Items["pod-1"].State == "HatchedInBag", "Hatch moves item to HatchedInBag")
	assert(profile.Slots["Incubator_1"] == nil and profile.DiscoveredSpecies["StarSlime"] == true, "Slot cleared & species discovered")
	assert((EconomyService.ValidateProfileInvariants(profile)), "Invariant valid after hatch")

	local penRes = EconomyService.PlaceInPenOnProfile(profile, "Pen_1", "pod-1", 1025)
	assert(penRes.Ok and profile.Items["pod-1"].State == "InPen" and profile.Slots["Pen_1"] == "pod-1", "PlaceInPen updates state/slot")
	assert((EconomyService.ValidateProfileInvariants(profile)), "Invariant valid after PlaceInPen")

	local settled = EconomyService.SettleProfileCoins(profile, 1055) -- 30s * 2/s = 60 Coins
	assert(settled and profile.Coins == 60, "30s at 2/s yields 60 Coins")
	assert((EconomyService.ValidateProfileInvariants(profile)), "Invariant valid after settle")

	local buyRes = EconomyService.BuyUpgradeOnProfile(profile, "PenSlot_2", 1055)
	assert(buyRes.Ok and profile.Coins == 0 and profile.Upgrades["PenSlot_2"] == true, "BuyUpgrade PenSlot_2 succeeds at 60 Coins")
	assert((EconomyService.ValidateProfileInvariants(profile)), "Invariant valid after BuyUpgrade")

	local remRes = EconomyService.RemoveFromPenOnProfile(profile, "Pen_1", 1060) -- +5s * 2/s = 10 Coins
	assert(remRes.Ok and profile.Coins == 10 and profile.Items["pod-1"].State == "HatchedInBag", "RemoveFromPen settles first & frees slot")
	assert((EconomyService.ValidateProfileInvariants(profile)), "Invariant valid after RemoveFromPen")

	local sellRes = EconomyService.SellCritterOnProfile(profile, "pod-1", 1061)
	assert(sellRes.Ok and sellRes.CoinsEarned == 40 and profile.Coins == 50 and profile.Items["pod-1"] == nil, "SellCritter adds 40 and removes item")
	assert((EconomyService.ValidateProfileInvariants(profile)), "Invariant valid after SellCritter")
	passed += 1

	-- 2. Failed operations MUST leave zero state changes (Revision, Coins, Items, Slots, Upgrades unchanged)
	local pFail = DataService.CreateDefaultProfile(2000)
	pFail.Coins = 59
	EconomyService.GrantPodToProfile(pFail, "StarSlime", 2000, "p-1")
	EconomyService.StartIncubateOnProfile(pFail, "Incubator_1", "p-1", 2000)

	local snapRev = pFail.Revision
	local snapCoins = pFail.Coins

	-- Premature hatch
	local earlyHatch = EconomyService.HatchFromSlotOnProfile(pFail, "Incubator_1", 2014, rng)
	assert(not earlyHatch.Ok and earlyHatch.Reason == "NotMature", "Premature hatch rejected")
	assert(pFail.Revision == snapRev and pFail.Items["p-1"].State == "Incubating", "Premature hatch makes zero state change")

	-- Locked slot & insufficient coins
	local lockedRes = EconomyService.StartIncubateOnProfile(pFail, "Incubator_2", "p-1", 2000)
	assert(not lockedRes.Ok and lockedRes.Reason == "SlotLocked", "Locked Incubator_2 rejected")
	local poorBuy = EconomyService.BuyUpgradeOnProfile(pFail, "PenSlot_2", 2000)
	assert(not poorBuy.Ok and poorBuy.Reason == "InsufficientCoins", "59 Coins < 60 cost rejected")
	assert(pFail.Coins == snapCoins and pFail.Revision == snapRev and pFail.Upgrades["PenSlot_2"] == nil, "Failed operations change zero state")

	-- Fill remaining unreserved bag capacity (9 + 1 incubating = 10 committed), verify overflow blocked
	for i = 1, Constants.MAX_BAG_CAPACITY - 1 do
		local g = EconomyService.GrantPodToProfile(pFail, "StarSlime", 2000, "fill-" .. tostring(i))
		assert(g.Ok, "Filling unreserved bag up to committed cap")
	end
	local revAtFull = pFail.Revision
	local overGrant = EconomyService.GrantPodToProfile(pFail, "StarSlime", 2000, "overflow")
	assert(not overGrant.Ok and overGrant.Reason == "BagFull" and pFail.Revision == revAtFull, "BagFull blocks GrantPod with zero changes")

	-- Selling unhatched pod rejected
	local sellPod = EconomyService.SellCritterOnProfile(pFail, "fill-1", 2020)
	assert(not sellPod.Ok and sellPod.Reason == "CannotSellUnhatched" and pFail.Revision == revAtFull, "Cannot sell PodInBag")

	-- Cap-clamped CoinsEarned on sale
	local pCap = DataService.CreateDefaultProfile(2500)
	pCap.Coins = Constants.MAX_COINS - 15
	pCap.Items["cap-1"] = {
		UID = "cap-1",
		SpeciesId = "StarSlime",
		Variant = "Normal",
		State = "HatchedInBag",
		AssignedSlot = nil,
		PlantedAt = nil,
		MaturesAt = nil,
		CreatedAt = 2500,
	}
	local capSell = EconomyService.SellCritterOnProfile(pCap, "cap-1", 2501)
	assert(capSell.Ok and capSell.CoinsEarned == 15 and pCap.Coins == Constants.MAX_COINS, "CoinsEarned reports actual credited delta at MAX_COINS")
	passed += 1

	-- 3. Duplicate transitions apply only once
	local pDup = DataService.CreateDefaultProfile(3000)
	pDup.Coins = 100
	EconomyService.GrantPodToProfile(pDup, "StarSlime", 3000, "dup-1")
	assert(EconomyService.StartIncubateOnProfile(pDup, "Incubator_1", "dup-1", 3000).Ok, "First incubate succeeds")
	local dupIncRev = pDup.Revision
	local dupInc = EconomyService.StartIncubateOnProfile(pDup, "Incubator_1", "dup-1", 3000)
	assert(not dupInc.Ok and pDup.Revision == dupIncRev, "Duplicate incubate fails cleanly")

	assert(EconomyService.HatchFromSlotOnProfile(pDup, "Incubator_1", 3015, rng).Ok, "First hatch succeeds")
	local dupHatchRev = pDup.Revision
	assert(not EconomyService.HatchFromSlotOnProfile(pDup, "Incubator_1", 3015, rng).Ok and pDup.Revision == dupHatchRev, "Duplicate hatch fails cleanly")

	assert(EconomyService.PlaceInPenOnProfile(pDup, "Pen_1", "dup-1", 3015).Ok, "First PlaceInPen succeeds")
	assert(not EconomyService.SellCritterOnProfile(pDup, "dup-1", 3015).Ok, "Active InPen critter cannot be sold directly")

	-- Stage 2B capped FeedCritter checks (insufficient coins, valid settle+feed, duplicate feed rejection, sell non-arbitrage)
	pDup.Coins = Constants.CRITTER_FEED_COST - 1
	local poorFeedRev = pDup.Revision
	local poorFeed = EconomyService.FeedCritterInPenOnProfile(pDup, "Pen_1", 3015)
	assert(
		not poorFeed.Ok and poorFeed.Reason == "InsufficientCoins" and pDup.Revision == poorFeedRev,
		"FeedCritter with insufficient coins makes zero state changes"
	)

	pDup.Coins = 100
	local feedOk = EconomyService.FeedCritterInPenOnProfile(pDup, "Pen_1", 3020) -- +5s * 2/s = 10 -> 110 - 45 = 65 Coins
	assert(feedOk.Ok and pDup.Coins == 65 and pDup.Items["dup-1"].FeedLevel == 1, "FeedCritter settles old rate then debits 45 and sets FeedLevel=1")
	assert(EconomyMath.CalculateActivePenRate(pDup.Items) == 4, "Fed StarSlime rate increases from 2/s to 4/s")
	local dupFeedRev = pDup.Revision
	local dupFeed = EconomyService.FeedCritterInPenOnProfile(pDup, "Pen_1", 3020)
	assert(
		not dupFeed.Ok and dupFeed.Reason == "AlreadyFed" and pDup.Coins == 65 and pDup.Revision == dupFeedRev,
		"Duplicate FeedCritter rejected at MAX_CRITTER_FEED_LEVEL=1"
	)

	pDup.Coins = 1500
	local prereqAstral = EconomyService.BuyUpgradeOnProfile(pDup, "StarCracker", 3020)
	assert(not prereqAstral.Ok and prereqAstral.Reason == "PrerequisiteRequired", "Astral Cracker requires FrostCracker")
	local prereqPen4 = EconomyService.BuyUpgradeOnProfile(pDup, "PenSlot_4", 3020)
	assert(not prereqPen4.Ok and prereqPen4.Reason == "PrerequisiteRequired", "PenSlot_4 requires PenSlot_3")

	local lureNoTool = EconomyService.UseFrostLureOnProfile(pDup, -9001, "DupTester", 3020, function()
		return true, "Spawned"
	end)
	assert(not lureNoTool.Ok and lureNoTool.Reason == "ToolRequired" and pDup.Coins == 1500, "Frost Lure blocked without FrostCracker with zero debit")

	assert(EconomyService.BuyUpgradeOnProfile(pDup, "FrostCracker", 3020).Ok, "Buy FrostCracker")
	local lureFailSpawn = EconomyService.UseFrostLureOnProfile(pDup, -9001, "DupTester", 3020, function()
		return false, "NoFreeMeteorNode"
	end)
	assert(not lureFailSpawn.Ok and lureFailSpawn.Reason == "NoFreeMeteorNode" and pDup.Coins == 1350, "Failing Frost Lure spawn charges zero Coins")

	local lureOk = EconomyService.UseFrostLureOnProfile(pDup, -9001, "DupTester", 3020, function()
		return true, "Spawned"
	end)
	assert(lureOk.Ok and pDup.Coins == 1275, "Successful Frost Lure charges exactly 75 Coins")

	pDup.Coins = 100
	assert(EconomyService.BuyUpgradeOnProfile(pDup, "PenSlot_2", 3020).Ok, "First BuyUpgrade succeeds")
	local dupBuyRev = pDup.Revision
	local dupBuy = EconomyService.BuyUpgradeOnProfile(pDup, "PenSlot_2", 3020)
	assert(not dupBuy.Ok and dupBuy.Reason == "AlreadyOwned" and pDup.Coins == 40 and pDup.Revision == dupBuyRev, "Duplicate BuyUpgrade charges once only")

	assert(EconomyService.RemoveFromPenOnProfile(pDup, "Pen_1", 3020).Ok, "Remove fed critter from pen succeeds")
	local fedSell = EconomyService.SellCritterOnProfile(pDup, "dup-1", 3020)
	assert(fedSell.Ok and fedSell.CoinsEarned == 60, "Fed StarSlime sells for 40 + 20 = 60 (< 45 feed cost, zero arbitrage)")
	local dupSellRev = pDup.Revision
	assert(not EconomyService.SellCritterOnProfile(pDup, "dup-1", 3020).Ok and pDup.Revision == dupSellRev, "Duplicate sell fails cleanly")
	passed += 1

	-- 4. Regression: Full unlocked incubators + full bag never deadlocks progression
	local pLock = DataService.CreateDefaultProfile(3500)
	pLock.Coins = 500
	assert(EconomyService.BuyUpgradeOnProfile(pLock, "Incubator_2", 3500).Ok, "Unlock Incubator_2")
	assert(EconomyService.GrantPodToProfile(pLock, "StarSlime", 3500, "inc-pod-1").Ok, "Grant pod 1")
	assert(EconomyService.GrantPodToProfile(pLock, "NebulaFox", 3500, "inc-pod-2").Ok, "Grant pod 2")
	assert(EconomyService.StartIncubateOnProfile(pLock, "Incubator_1", "inc-pod-1", 3500).Ok, "Incubate pod 1")
	assert(EconomyService.StartIncubateOnProfile(pLock, "Incubator_2", "inc-pod-2", 3500).Ok, "Incubate pod 2")

	-- Put an active critter in Pen_1 so we also verify RemoveFromPen respects reserved hatch capacity
	pLock.Items["pen-occupant"] = {
		UID = "pen-occupant",
		SpeciesId = "StarSlime",
		Variant = "Normal",
		State = "InPen",
		AssignedSlot = "Pen_1",
		PlantedAt = nil,
		MaturesAt = nil,
		CreatedAt = 3500,
	}
	pLock.Slots["Pen_1"] = "pen-occupant"

	for i = 1, Constants.MAX_BAG_CAPACITY - 2 do
		assert(EconomyService.GrantPodToProfile(pLock, "StarSlime", 3500, "bag-pod-" .. tostring(i)).Ok, "Fill remaining unreserved bag slot")
	end
	assert(EconomyService.GetBagCount(pLock) == 8 and EconomyService.GetOccupiedIncubatorCount(pLock) == 2, "8 in bag + 2 reserved incubating")
	assert(not EconomyService.GrantPodToProfile(pLock, "StarSlime", 3500, "extra-pod").Ok, "GrantPod blocked when 10 slots committed")
	assert(not EconomyService.RemoveFromPenOnProfile(pLock, "Pen_1", 3510).Ok, "RemoveFromPen blocked when 10 slots committed")

	-- Frost Lure must reject BagFull BEFORE invoking spawner or charging Coins
	pLock.Upgrades["FrostCracker"] = true
	pLock.Coins = 500
	local lureSpawnerCalls = 0
	local fullLure = EconomyService.UseFrostLureOnProfile(pLock, -9002, "FullBagTester", 3515, function()
		lureSpawnerCalls += 1
		return true, "Spawned"
	end)
	assert(not fullLure.Ok and fullLure.Reason == "BagFull" and lureSpawnerCalls == 0 and pLock.Coins == 500, "Full committed bag blocks Frost Lure before spawn/debit")

	-- Both incubating pods MUST still hatch cleanly at maturity
	local h1 = EconomyService.HatchFromSlotOnProfile(pLock, "Incubator_1", 3545, rng)
	local h2 = EconomyService.HatchFromSlotOnProfile(pLock, "Incubator_2", 3545, rng)
	assert(h1.Ok and h2.Ok, "Both occupied incubators must hatch cleanly despite full unreserved bag")
	assert(EconomyService.GetBagCount(pLock) == 10 and EconomyService.GetOccupiedIncubatorCount(pLock) == 0, "All 10 slots now in bag cleanly")
	assert(EconomyService.SellCritterOnProfile(pLock, "inc-pod-1", 3545).Ok, "Player can immediately sell hatched critter to recover bag space")
	assert((EconomyService.ValidateProfileInvariants(pLock)), "Invariants valid after full-bag hatch recovery")
	passed += 1

	-- 5. Regression: Sub-second fractional accrual across second boundary & rate changes
	local pSub = DataService.CreateDefaultProfile(10.8)
	pSub.Items["slime2"] = {
		UID = "slime2",
		SpeciesId = "StarSlime", -- 2/s
		Variant = "Normal",
		State = "HatchedInBag",
		AssignedSlot = nil,
		PlantedAt = nil,
		MaturesAt = nil,
		CreatedAt = 10,
	}
	pSub.Items["fox2"] = {
		UID = "fox2",
		SpeciesId = "NebulaFox", -- 7/s
		Variant = "Normal",
		State = "HatchedInBag",
		AssignedSlot = nil,
		PlantedAt = nil,
		MaturesAt = nil,
		CreatedAt = 10,
	}
	assert(EconomyService.PlaceInPenOnProfile(pSub, "Pen_1", "slime2", 10.8).Ok, "Place StarSlime at t=10.8")
	assert(EconomyService.RemoveFromPenOnProfile(pSub, "Pen_1", 11.1).Ok, "Remove StarSlime at t=11.1 (0.3s across boundary)")
	assert(pSub.Coins == 0 and math.abs(pSub.PendingFraction - 0.6) < 1e-6, "0.3s at 2/s across 11.0 boundary must carry 0.6 fraction with 0 Coins")

	assert(EconomyService.PlaceInPenOnProfile(pSub, "Pen_1", "fox2", 11.1).Ok, "Place NebulaFox at t=11.1")
	assert(EconomyService.SettleProfileCoins(pSub, 11.35), "0.25s at 7/s + 0.6 = 2.35 -> credits 2 Coins")
	assert(pSub.Coins == 2 and math.abs(pSub.PendingFraction - 0.35) < 1e-6, "Expected 2 Coins and 0.35 fraction after rate switch")
	assert((EconomyService.ValidateProfileInvariants(pSub)), "Invariant valid after sub-second fractional rate change")
	passed += 1

	-- 6. Missing authorizer denies by default (Review #007)
	local savedAuthorizer = stationAuthorizer
	EconomyService.SetStationAuthorizer(nil)
	local missingOk, missingReason = EconomyService.CheckStationAuthorization(nil, "UpgradePad", "PenSlot_2")
	assert(not missingOk and missingReason == "AuthorizerUnavailable", "Missing authorizer must deny by default")
	EconomyService.SetStationAuthorizer(function(_p, _k, _t)
		return false, "MockDenied"
	end)
	local mockDeniedOk, mockDeniedReason = EconomyService.CheckStationAuthorization(nil, "UpgradePad", "PenSlot_2")
	assert(not mockDeniedOk and mockDeniedReason == "PlayerUnavailable", "Nil player denied")
	EconomyService.SetStationAuthorizer(savedAuthorizer)
	passed += 1

	-- 7. Stage 3 offline MaturesAt boundary & zero-offline-coin settlement after login migration
	local offlineRaw: { [string]: any } = {
		SchemaVersion = 0,
		Coins = 50,
		PendingFraction = 0.25,
		LastAccrualTimestamp = 1000, -- 12h older than login clock
		Revision = 2,
		Slots = {
			Incubator_1 = "off-inc",
			Pen_1 = "off-pen",
		},
		Items = {
			["off-inc"] = {
				UID = "off-inc",
				SpeciesId = "NebulaFox",
				Variant = "Normal",
				State = "Incubating",
				AssignedSlot = "Incubator_1",
				PlantedAt = 1000,
				MaturesAt = 1045,
				CreatedAt = 990,
			},
			["off-pen"] = {
				UID = "off-pen",
				SpeciesId = "StarSlime",
				Variant = "Normal",
				State = "InPen",
				AssignedSlot = "Pen_1",
				CreatedAt = 900,
			},
		},
	}
	local tBeforeMature = 1044
	local migratedBefore = DataService.ReconcileAndMigrateProfileData(offlineRaw, tBeforeMature)
	assert((EconomyService.ValidateProfileInvariants(migratedBefore)), "Migrated offline profile passes invariants")
	assert(not EconomyService.SettleProfileCoins(migratedBefore, tBeforeMature), "Zero offline coins paid on login immediately after migration")
	assert(migratedBefore.Coins == 50, "Offline duration pays 0 extra coins in Stage 3")

	local earlyHatch = EconomyService.HatchFromSlotOnProfile(migratedBefore, "Incubator_1", 1044, rng)
	assert(not earlyHatch.Ok and earlyHatch.Reason == "NotMature", "1s before MaturesAt stays NotMature")

	local tTwelveHoursLater = 1045 + 12 * 3600
	local lateHatch = EconomyService.HatchFromSlotOnProfile(migratedBefore, "Incubator_1", tTwelveHoursLater, rng)
	assert(lateHatch.Ok and lateHatch.SpeciesId == "NebulaFox", "Pod incubated offline matures 12h later on first Hatch attempt")
	assert(migratedBefore.DiscoveredSpecies["NebulaFox"] == true, "Late offline hatch marks species discovered")
	assert((EconomyService.ValidateProfileInvariants(migratedBefore)), "Invariants valid after offline hatch")
	passed += 1

	-- 8. End-to-end ordinary leave AND shutdown flush with unaccrued pen earnings + confirmed reload
	local econStore = DataService.CreateIsolatedMockStoreForTest("EconLeave")
	local uEcon = -920088
	DataService.EndSession(uEcon)

	local joinNow = math.floor(workspace:GetServerTimeNow())
	local econJoinOk = DataService.StartProfileSessionForUserId(uEcon, nil, {
		Store = econStore,
		NowClock = joinNow,
	})
	assert(econJoinOk and DataService.IsUserIdReady(uEcon), "Suite 8 initial session ready")

	local pEcon1 = DataService.GetProfileByUserId(uEcon) :: Types.PlayerProfileData
	pEcon1.Coins = 100
	pEcon1.Items["econ-slime"] = {
		UID = "econ-slime",
		SpeciesId = "StarSlime", -- 2 Coins/s
		Variant = "Normal",
		State = "HatchedInBag",
		AssignedSlot = nil,
		PlantedAt = nil,
		MaturesAt = nil,
		CreatedAt = joinNow,
		FeedLevel = 0,
	}
	assert(EconomyService.PlaceInPenOnProfile(pEcon1, "Pen_1", "econ-slime", joinNow).Ok, "Place StarSlime in Pen_1")
	-- Simulate 10 seconds of unaccrued online pen time right before ordinary player leave.
	pEcon1.LastAccrualTimestamp = workspace:GetServerTimeNow() - 10

	DataService.EndSession(uEcon)
	assert(not DataService.IsUserIdReady(uEcon), "Leave closes session before save")
	assert(DataService.WaitForUserFinalSave(uEcon, 2), "Ordinary leave confirms OnAfterSave final write")

	local rejoinNow = workspace:GetServerTimeNow()
	assert(DataService.StartProfileSessionForUserId(uEcon, nil, {
		Store = econStore,
		NowClock = rejoinNow,
	}), "Suite 8 reload after ordinary leave")
	local pEcon2 = DataService.GetProfileByUserId(uEcon) :: Types.PlayerProfileData
	assert(pEcon2.Coins >= 120 and pEcon2.Coins <= 126, string.format("Leave must settle & persist >=20 unaccrued Coins (got %d)", pEcon2.Coins))

	-- Now verify Shutdown flush (FlushActiveProfileSessions) also settles final unaccrued Coins before writing.
	pEcon2.Coins = 200
	pEcon2.LastAccrualTimestamp = workspace:GetServerTimeNow() - 15
	assert(DataService.FlushActiveProfileSessions(2), "Shutdown flush confirms OnAfterSave")

	assert(DataService.StartProfileSessionForUserId(uEcon, nil, {
		Store = econStore,
		NowClock = workspace:GetServerTimeNow(),
	}), "Suite 8 reload after shutdown flush")
	local pEcon3 = DataService.GetProfileByUserId(uEcon) :: Types.PlayerProfileData
	assert(pEcon3.Coins >= 230 and pEcon3.Coins <= 238, string.format("Shutdown flush must settle & persist >=30 unaccrued Coins (got %d)", pEcon3.Coins))

	assert(DataService.FlushActiveProfileSessions(2), "Suite 8 cleanup flush")
	DataService.ClearTestTrackingForUserIds({ uEcon })
	passed += 1

	-- 9. Stage 3 upgrades: BagCap_20 (10 -> 20 capacity w/ reserved incubator hatch) & PenSlot_5 (Pen_5)
	local pStage3 = DataService.CreateDefaultProfile(4000)
	pStage3.Coins = 10000
	-- BagCap_20 requires Incubator_2; PenSlot_5 requires PenSlot_4
	local prereqBag = EconomyService.BuyUpgradeOnProfile(pStage3, "BagCap_20", 4000)
	assert(not prereqBag.Ok and prereqBag.Reason == "PrerequisiteRequired", "BagCap_20 requires Incubator_2")
	local prereqPen5 = EconomyService.BuyUpgradeOnProfile(pStage3, "PenSlot_5", 4000)
	assert(not prereqPen5.Ok and prereqPen5.Reason == "PrerequisiteRequired", "PenSlot_5 requires PenSlot_4")

	assert(EconomyService.BuyUpgradeOnProfile(pStage3, "Incubator_2", 4000).Ok, "Buy Incubator_2")
	assert(EconomyService.BuyUpgradeOnProfile(pStage3, "BagCap_20", 4000).Ok, "Buy BagCap_20 (1,200 Coins)")
	assert(EconomyService.GetBagCapacity(pStage3) == 20, "GetBagCapacity returns 20 after BagCap_20")

	assert(EconomyService.GrantPodToProfile(pStage3, "StarSlime", 4000, "b20-inc-1").Ok, "Grant b20-inc-1")
	assert(EconomyService.GrantPodToProfile(pStage3, "NebulaFox", 4000, "b20-inc-2").Ok, "Grant b20-inc-2")
	assert(EconomyService.StartIncubateOnProfile(pStage3, "Incubator_1", "b20-inc-1", 4000).Ok, "Start Incubator_1")
	assert(EconomyService.StartIncubateOnProfile(pStage3, "Incubator_2", "b20-inc-2", 4000).Ok, "Start Incubator_2")

	for i = 1, 18 do
		assert(EconomyService.GrantPodToProfile(pStage3, "StarSlime", 4000, "b20-bag-" .. tostring(i)).Ok, "Fill expanded bag slot " .. tostring(i))
	end
	assert(EconomyService.GetCommittedBagCount(pStage3) == 20, "18 bag + 2 incubating = 20 committed")
	local bag20Overflow = EconomyService.GrantPodToProfile(pStage3, "StarSlime", 4000, "b20-overflow")
	assert(not bag20Overflow.Ok and bag20Overflow.Reason == "BagFull", "21st committed slot rejected at BagCap 20")
	assert((EconomyService.ValidateProfileInvariants(pStage3)), "Invariants valid at BagCap 20")

	assert(EconomyService.HatchFromSlotOnProfile(pStage3, "Incubator_1", 4050, rng).Ok, "Incubator_1 hatches cleanly at full 20 cap")
	assert(EconomyService.HatchFromSlotOnProfile(pStage3, "Incubator_2", 4050, rng).Ok, "Incubator_2 hatches cleanly at full 20 cap")
	assert(EconomyService.GetBagCount(pStage3) == 20 and EconomyService.SellCritterOnProfile(pStage3, "b20-inc-1", 4050).Ok, "Sell 1 hatched critter from 20-cap bag")

	assert(EconomyService.BuyUpgradeOnProfile(pStage3, "PenSlot_2", 4050).Ok, "Buy PenSlot_2")
	assert(EconomyService.BuyUpgradeOnProfile(pStage3, "PenSlot_3", 4050).Ok, "Buy PenSlot_3")
	assert(EconomyService.BuyUpgradeOnProfile(pStage3, "PenSlot_4", 4050).Ok, "Buy PenSlot_4")
	assert(EconomyService.BuyUpgradeOnProfile(pStage3, "PenSlot_5", 4050).Ok, "Buy PenSlot_5 (3,600 Coins)")
	assert(EconomyService.IsUnlockedPenSlot(pStage3, "Pen_5"), "Pen_5 unlocked")
	assert(EconomyService.PlaceInPenOnProfile(pStage3, "Pen_5", "b20-inc-2", 4050).Ok, "Place critter in Pen_5")
	assert(EconomyMath.CalculateActivePenRate(pStage3.Items) == 7, "Pen_5 NebulaFox contributes +7 Coins/s")
	assert(EconomyService.RemoveFromPenOnProfile(pStage3, "Pen_5", 4052).Ok, "Remove critter from Pen_5 settles coins & returns to bag")
	assert((EconomyService.ValidateProfileInvariants(pStage3)), "Invariants valid after Pen_5 cycle")
	passed += 1

	return passed
end

return EconomyService
