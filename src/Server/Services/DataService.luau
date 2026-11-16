--!strict
--[[
	Service: DataService
	Purpose: Manages Stage 1 MockStore player profile lifecycle (Loading -> Ready -> Closing), readiness checks,
	         and strictly scoped single-player OwnerStateDTO snapshot delivery.
	Connections: Binds NetworkService.BindSnapshotHandler; enforces IsReady(player) boundary for EconomyService,
	             PlotService, and MeteorService. Stage 3 swaps MockStore cleanly to pinned ProfileStore.
	How to Test in Studio: Press Play (F5) and 2-Player Local Server; verify DataService self-tests pass
	                       and each client prints Synced OwnerStateDTO in Output.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Types = require(Shared:WaitForChild("Types"))

local ServicesFolder = script.Parent
local NetworkService = require(ServicesFolder:WaitForChild("NetworkService"))

export type SessionStatus = "Loading" | "Ready" | "Closing"

type PlayerSession = {
	UserId: number,
	Player: Player?,
	Status: SessionStatus,
	Profile: Types.PlayerProfileData?,
	PendingSnapshotRequest: boolean,
}

local DataService = {
	Name = "DataService",
}

local sessions: { [number]: PlayerSession } = {}
local pendingEarlySnapshots: { [number]: boolean } = {}
local readyCallbacks: { (player: Player, profile: Types.PlayerProfileData) -> () } = {}
local closingCallbacks: { (player: Player) -> () } = {}
local playerAddedConn: RBXScriptConnection? = nil
local playerRemovingConn: RBXScriptConnection? = nil
local mockSessionCounter = 0

local function cloneCritterRecord(src: Types.CritterItemRecord): Types.CritterItemRecord
	return {
		UID = src.UID,
		SpeciesId = src.SpeciesId,
		Variant = src.Variant,
		State = src.State,
		AssignedSlot = src.AssignedSlot,
		PlantedAt = src.PlantedAt,
		MaturesAt = src.MaturesAt,
		CreatedAt = src.CreatedAt,
	}
end

local function cloneStringMap(src: { [string]: string }): { [string]: string }
	local out: { [string]: string } = {}
	for k, v in pairs(src) do
		out[k] = v
	end
	return out
end

local function cloneBoolMap(src: { [string]: boolean }): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for k, v in pairs(src) do
		out[k] = v
	end
	return out
end

local function cloneDiscoveredMap(src: { [Types.SpeciesId]: boolean }): { [Types.SpeciesId]: boolean }
	local out: { [Types.SpeciesId]: boolean } = {}
	for k, v in pairs(src) do
		out[k] = v
	end
	return out
end

function DataService.CreateDefaultProfile(nowEpoch: number?): Types.PlayerProfileData
	local epoch = if nowEpoch ~= nil then math.floor(nowEpoch) else os.time()
	return {
		SchemaVersion = Constants.SCHEMA_VERSION,
		Coins = 0,
		PendingFraction = 0,
		LastAccrualTimestamp = epoch,
		Revision = 1,
		Items = {},
		Slots = {},
		Upgrades = {},
		DiscoveredSpecies = {},
	}
end

function DataService.ReconcileProfile(raw: any, nowEpoch: number?): Types.PlayerProfileData
	local fresh = DataService.CreateDefaultProfile(nowEpoch)
	if typeof(raw) ~= "table" then
		return fresh
	end

	if typeof(raw.SchemaVersion) == "number" and raw.SchemaVersion >= 1 then
		fresh.SchemaVersion = math.floor(raw.SchemaVersion)
	end
	if typeof(raw.Coins) == "number" and raw.Coins == raw.Coins and math.abs(raw.Coins) ~= math.huge then
		fresh.Coins = math.clamp(math.floor(raw.Coins), 0, Constants.MAX_COINS)
	end
	if typeof(raw.PendingFraction) == "number" and raw.PendingFraction == raw.PendingFraction then
		if raw.PendingFraction >= 0 and raw.PendingFraction < 1 then
			fresh.PendingFraction = raw.PendingFraction
		end
	end
	if typeof(raw.LastAccrualTimestamp) == "number" and raw.LastAccrualTimestamp == raw.LastAccrualTimestamp then
		fresh.LastAccrualTimestamp = math.max(0, math.floor(raw.LastAccrualTimestamp))
	end
	if typeof(raw.Revision) == "number" and raw.Revision >= 1 then
		fresh.Revision = math.floor(raw.Revision)
	end

	if typeof(raw.Items) == "table" then
		for uid, rec in pairs(raw.Items) do
			if typeof(uid) == "string" and typeof(rec) == "table" and typeof(rec.UID) == "string" then
				fresh.Items[uid] = cloneCritterRecord(rec :: Types.CritterItemRecord)
			end
		end
	end
	if typeof(raw.Slots) == "table" then
		for slotId, itemUid in pairs(raw.Slots) do
			if typeof(slotId) == "string" and typeof(itemUid) == "string" then
				fresh.Slots[slotId] = itemUid
			end
		end
	end
	if typeof(raw.Upgrades) == "table" then
		for upgradeId, unlocked in pairs(raw.Upgrades) do
			if typeof(upgradeId) == "string" and typeof(unlocked) == "boolean" then
				fresh.Upgrades[upgradeId] = unlocked
			end
		end
	end
	if typeof(raw.DiscoveredSpecies) == "table" then
		for speciesId, discovered in pairs(raw.DiscoveredSpecies) do
			if typeof(speciesId) == "string" and typeof(discovered) == "boolean" then
				fresh.DiscoveredSpecies[speciesId :: Types.SpeciesId] = discovered
			end
		end
	end

	return fresh
end

function DataService.BuildOwnerStateDTO(profile: Types.PlayerProfileData): Types.OwnerStateDTO
	local copiedItems: { [string]: Types.CritterItemRecord } = {}
	for uid, rec in pairs(profile.Items) do
		copiedItems[uid] = cloneCritterRecord(rec)
	end

	return {
		Revision = profile.Revision,
		Coins = profile.Coins,
		BagCap = Constants.MAX_BAG_CAPACITY,
		Items = copiedItems,
		Slots = cloneStringMap(profile.Slots),
		Upgrades = cloneBoolMap(profile.Upgrades),
		DiscoveredSpecies = cloneDiscoveredMap(profile.DiscoveredSpecies),
	}
end

function DataService.IsUserIdReady(userId: number): boolean
	local session = sessions[userId]
	return session ~= nil and session.Status == "Ready" and session.Profile ~= nil
end

function DataService.IsReady(player: Player): boolean
	local session = sessions[player.UserId]
	return session ~= nil
		and session.Player == player
		and session.Status == "Ready"
		and session.Profile ~= nil
end

function DataService.GetProfileByUserId(userId: number): Types.PlayerProfileData?
	local session = sessions[userId]
	if session ~= nil and session.Status == "Ready" then
		return session.Profile
	end
	return nil
end

function DataService.GetProfile(player: Player): Types.PlayerProfileData?
	local session = sessions[player.UserId]
	if session ~= nil and session.Player == player and session.Status == "Ready" then
		return session.Profile
	end
	return nil
end

function DataService.SendOwnerStateSnapshot(player: Player): boolean
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false
	end
	local dto = DataService.BuildOwnerStateDTO(profile)
	NetworkService.SendOwnerState(player, dto)
	return true
end

function DataService.BeginMockSession(userId: number, player: Player?): PlayerSession
	local existing = sessions[userId]
	if existing ~= nil then
		existing.Status = "Closing"
		sessions[userId] = nil
	end

	local hadEarlySnapshot = pendingEarlySnapshots[userId] == true
	pendingEarlySnapshots[userId] = nil

	local session: PlayerSession = {
		UserId = userId,
		Player = player,
		Status = "Loading",
		Profile = nil,
		PendingSnapshotRequest = hadEarlySnapshot,
	}
	sessions[userId] = session
	return session
end

function DataService.CompleteMockSession(userId: number, nowEpoch: number?): boolean
	local session = sessions[userId]
	if session == nil or session.Status ~= "Loading" then
		return false
	end
	if session.Player ~= nil and session.Player.Parent ~= Players then
		sessions[userId] = nil
		return false
	end

	local profile = DataService.CreateDefaultProfile(nowEpoch)
	session.Profile = profile
	session.Status = "Ready"
	mockSessionCounter += 1

	local player = session.Player
	if player ~= nil then
		for _, cb in ipairs(readyCallbacks) do
			local ok, err = pcall(cb, player, profile)
			if not ok then
				warn("[DataService] OnPlayerReady callback error: " .. tostring(err))
			end
		end

		if session.PendingSnapshotRequest then
			session.PendingSnapshotRequest = false
			DataService.SendOwnerStateSnapshot(player)
		end
	end

	return true
end

function DataService.EndMockSession(userId: number, player: Player?): ()
	pendingEarlySnapshots[userId] = nil
	local session = sessions[userId]
	if session == nil then
		return
	end
	if player ~= nil and session.Player ~= nil and session.Player ~= player then
		return
	end

	session.Status = "Closing"
	local ownerPlayer = session.Player
	if ownerPlayer ~= nil then
		for _, cb in ipairs(closingCallbacks) do
			local ok, err = pcall(cb, ownerPlayer)
			if not ok then
				warn("[DataService] OnPlayerClosing callback error: " .. tostring(err))
			end
		end
	end

	session.Profile = nil
	session.Player = nil
	sessions[userId] = nil
end

function DataService.HandleSnapshotRequestForUserId(userId: number, player: Player?): string
	local session = sessions[userId]
	if session == nil then
		if player ~= nil and player.Parent == Players then
			pendingEarlySnapshots[userId] = true
			return "QueuedEarly"
		end
		return "IgnoredNoSession"
	end

	if session.Status == "Loading" then
		session.PendingSnapshotRequest = true
		return "QueuedLoading"
	elseif session.Status == "Ready" then
		if player ~= nil and session.Player == player then
			DataService.SendOwnerStateSnapshot(player)
			return "Delivered"
		elseif player == nil then
			return "DeliveredMock"
		end
	end

	return "IgnoredClosing"
end

function DataService.OnPlayerReady(callback: (player: Player, profile: Types.PlayerProfileData) -> ()): ()
	table.insert(readyCallbacks, callback)
	-- Also invoke immediately for any players already Ready.
	for _, session in pairs(sessions) do
		if session.Status == "Ready" and session.Player ~= nil and session.Profile ~= nil then
			local ok, err = pcall(callback, session.Player, session.Profile)
			if not ok then
				warn("[DataService] Late OnPlayerReady error: " .. tostring(err))
			end
		end
	end
end

function DataService.OnPlayerClosing(callback: (player: Player) -> ()): ()
	table.insert(closingCallbacks, callback)
end

local function onPlayerAdded(player: Player): ()
	if player.Parent ~= Players then
		return
	end
	DataService.BeginMockSession(player.UserId, player)
	-- Stage 1 MockStore completes synchronously after the Loading phase so readiness boundaries remain explicit.
	DataService.CompleteMockSession(player.UserId)
end

local function onPlayerRemoving(player: Player): ()
	DataService.EndMockSession(player.UserId, player)
end

function DataService.Init(self: typeof(DataService)): ()
	assert(
		Constants.USE_MOCK_STORE == true,
		"[DataService] Stage 1 DataService requires USE_MOCK_STORE == true; never fall back to mock profiles in live mode."
	)
	print("[DataService] Initialized in Stage 1 MockStore mode (in-memory session profiles).")
end

function DataService.Start(self: typeof(DataService)): ()
	NetworkService.BindSnapshotHandler(function(player: Player)
		DataService.HandleSnapshotRequestForUserId(player.UserId, player)
	end)

	if playerRemovingConn == nil then
		playerRemovingConn = Players.PlayerRemoving:Connect(onPlayerRemoving)
	end

	if playerAddedConn == nil then
		playerAddedConn = Players.PlayerAdded:Connect(onPlayerAdded)
	end

	-- Initialize any players already present before DataService:Start() connected PlayerAdded.
	for _, existingPlayer in ipairs(Players:GetPlayers()) do
		if sessions[existingPlayer.UserId] == nil then
			onPlayerAdded(existingPlayer)
		end
	end
end

function DataService.RunSelfTest(): number
	local passed = 0
	local userA = -910001
	local userB = -910002

	DataService.EndMockSession(userA)
	DataService.EndMockSession(userB)

	-- 1. Enforce Loading -> Ready -> Closing readiness boundaries and independent profile state
	DataService.BeginMockSession(userA, nil)
	assert(not DataService.IsUserIdReady(userA), "Profile must NOT be ready while Loading")
	assert(DataService.GetProfileByUserId(userA) == nil, "GetProfileByUserId must return nil while Loading")

	-- Request snapshot before readiness -> queued cleanly
	local queueState = DataService.HandleSnapshotRequestForUserId(userA, nil)
	assert(queueState == "QueuedLoading", "Pre-ready snapshot request must queue while Loading")

	assert(DataService.CompleteMockSession(userA, 1000), "CompleteMockSession should succeed")
	assert(DataService.IsUserIdReady(userA), "Profile must be ready after completion")

	DataService.BeginMockSession(userB, nil)
	assert(DataService.CompleteMockSession(userB, 1000), "Second player session should complete")

	local profileA = DataService.GetProfileByUserId(userA) :: Types.PlayerProfileData
	local profileB = DataService.GetProfileByUserId(userB) :: Types.PlayerProfileData
	assert(profileA ~= nil and profileB ~= nil and profileA ~= profileB, "Each player needs distinct profile table")

	-- Mutating player A's profile tables must never leak to player B
	profileA.Coins = 250
	profileA.Upgrades["PenSlot_2"] = true
	profileA.Items["uid-1"] = {
		UID = "uid-1",
		SpeciesId = "StarSlime",
		Variant = "Normal",
		State = "PodInBag",
		AssignedSlot = nil,
		PlantedAt = nil,
		MaturesAt = nil,
		CreatedAt = 1000,
	}
	assert(profileB.Coins == 0 and profileB.Upgrades["PenSlot_2"] == nil and profileB.Items["uid-1"] == nil, "Player B state must stay isolated")
	passed += 1

	-- 2. Verify OwnerStateDTO whitelisting and deep-copy isolation
	local dtoA = DataService.BuildOwnerStateDTO(profileA)
	assert(dtoA.Coins == 250 and dtoA.BagCap == Constants.MAX_BAG_CAPACITY, "DTO exposes owner fields")
	assert((dtoA :: any).SchemaVersion == nil, "DTO must strip SchemaVersion")
	assert((dtoA :: any).PendingFraction == nil, "DTO must strip PendingFraction")
	assert((dtoA :: any).LastAccrualTimestamp == nil, "DTO must strip LastAccrualTimestamp")

	dtoA.Coins = 999999
	dtoA.Upgrades["PenSlot_3"] = true
	assert(profileA.Coins == 250 and profileA.Upgrades["PenSlot_3"] == nil, "Mutating DTO copy must not affect server profile")
	passed += 1

	-- 3. Verify leave clears session/readiness and rejoin starts fresh mock state
	DataService.EndMockSession(userA)
	assert(not DataService.IsUserIdReady(userA), "Readiness must clear on leave")
	assert(DataService.GetProfileByUserId(userA) == nil, "Profile must clear on leave")
	assert(DataService.HandleSnapshotRequestForUserId(userA, nil) == "IgnoredNoSession", "Removed session ignores snapshots")

	DataService.BeginMockSession(userA, nil)
	assert(DataService.CompleteMockSession(userA, 2000), "Rejoin session must initialize")
	local rejoinedA = DataService.GetProfileByUserId(userA) :: Types.PlayerProfileData
	assert(rejoinedA.Coins == 0 and next(rejoinedA.Items) == nil, "MockStore rejoin starts clean")

	DataService.EndMockSession(userA)
	DataService.EndMockSession(userB)
	passed += 1

	return passed
end

return DataService
