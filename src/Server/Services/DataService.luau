--!strict
--[[
	Service: DataService
	Purpose: Manages Stage 1 MockStore player profile lifecycle (Loading -> Ready -> Closing), environment guards,
	         readiness checks, and strictly scoped single-player OwnerStateDTO snapshot delivery.
	Connections: Binds NetworkService.BindSnapshotHandler; enforces IsReady(player) boundary for EconomyService,
	             PlotService, and MeteorService. Stage 3 swaps MockStore cleanly to pinned ProfileStore.
	How to Test in Studio: Press Play (F5) and 2-Player Local Server; verify DataService self-tests pass
	                       and each client prints Synced OwnerStateDTO in Output.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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
local snapshotRequestedCallbacks: { (player: Player) -> () } = {}
local playerAddedConn: RBXScriptConnection? = nil
local playerRemovingConn: RBXScriptConnection? = nil

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
		FeedLevel = src.FeedLevel or 0,
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

function DataService.CanUseMockStoreInEnvironment(
	isStudio: boolean,
	placeId: number,
	useMockStore: boolean,
	allowedPrototypePlaceId: number
): (boolean, string)
	if not useMockStore then
		return false, "USE_MOCK_STORE is disabled"
	end
	if isStudio then
		return true, "StudioEnvironment"
	end
	if allowedPrototypePlaceId > 0 and placeId == allowedPrototypePlaceId then
		return true, "DesignatedPrototypePlace"
	end
	return false, string.format("MockStore blocked on published PlaceId %d", placeId)
end

function DataService.CreateDefaultProfile(nowClock: number?): Types.PlayerProfileData
	local clockTime = if nowClock ~= nil then nowClock else workspace:GetServerTimeNow()
	return {
		SchemaVersion = Constants.SCHEMA_VERSION,
		Coins = 0,
		PendingFraction = 0,
		LastAccrualTimestamp = clockTime,
		Revision = 1,
		Items = {},
		Slots = {},
		Upgrades = {},
		DiscoveredSpecies = {},
	}
end

function DataService.BuildOwnerStateDTO(profile: Types.PlayerProfileData): Types.OwnerStateDTO
	local copiedItems: { [string]: Types.CritterItemRecord } = {}
	local reservedSlots = 0
	for uid, rec in pairs(profile.Items) do
		copiedItems[uid] = cloneCritterRecord(rec)
		if rec.State == "Incubating" then
			reservedSlots += 1
		end
	end

	return {
		Revision = profile.Revision,
		Coins = profile.Coins,
		BagCap = Constants.MAX_BAG_CAPACITY,
		ReservedBagSlots = reservedSlots,
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

function DataService.ForEachReadyPlayer(callback: (player: Player, profile: Types.PlayerProfileData) -> ()): ()
	for _, session in pairs(sessions) do
		if session.Status == "Ready" and session.Player ~= nil and session.Profile ~= nil then
			callback(session.Player, session.Profile)
		end
	end
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

function DataService.OnSnapshotDelivered(callback: (player: Player) -> ()): ()
	table.insert(snapshotRequestedCallbacks, callback)
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
			if DataService.SendOwnerStateSnapshot(player) then
				for _, snapCb in ipairs(snapshotRequestedCallbacks) do
					local ok, err = pcall(snapCb, player)
					if not ok then
						warn("[DataService] OnSnapshotDelivered error: " .. tostring(err))
					end
				end
			end
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
			if DataService.SendOwnerStateSnapshot(player) then
				for _, snapCb in ipairs(snapshotRequestedCallbacks) do
					local ok, err = pcall(snapCb, player)
					if not ok then
						warn("[DataService] OnSnapshotDelivered error: " .. tostring(err))
					end
				end
			end
			return "Delivered"
		elseif player == nil then
			return "DeliveredMock"
		end
	end

	return "IgnoredClosing"
end

function DataService.OnPlayerReady(callback: (player: Player, profile: Types.PlayerProfileData) -> ()): ()
	table.insert(readyCallbacks, callback)
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
	DataService.CompleteMockSession(player.UserId)
end

local function onPlayerRemoving(player: Player): ()
	DataService.EndMockSession(player.UserId, player)
end

function DataService.Init(self: typeof(DataService)): ()
	local ok, reason = DataService.CanUseMockStoreInEnvironment(
		RunService:IsStudio(),
		game.PlaceId,
		Constants.USE_MOCK_STORE,
		Constants.ALLOW_PUBLISHED_PROTOTYPE_PLACE_ID
	)
	assert(ok, "[DataService] MockStore rejected by environment guard: " .. reason)
	print(string.format("[DataService] Initialized in Stage 1 MockStore mode (%s).", reason))
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

	for _, existingPlayer in ipairs(Players:GetPlayers()) do
		if sessions[existingPlayer.UserId] == nil then
			onPlayerAdded(existingPlayer)
		end
	end
end

function DataService.RunSelfTest(): number
	local passed = 0

	-- 1. Environment guard checks (never run MockStore on unauthorized published servers)
	local studioOk = DataService.CanUseMockStoreInEnvironment(true, 0, true, 0)
	assert(studioOk, "MockStore allowed in Studio")
	local pubBlocked = DataService.CanUseMockStoreInEnvironment(false, 999999, true, 0)
	assert(not pubBlocked, "MockStore blocked on published server without prototype PlaceId")
	local pubMismatch = DataService.CanUseMockStoreInEnvironment(false, 999999, true, 123456)
	assert(not pubMismatch, "MockStore blocked on mismatched published PlaceId")
	local pubAllowed = DataService.CanUseMockStoreInEnvironment(false, 123456, true, 123456)
	assert(pubAllowed, "MockStore allowed only on designated prototype PlaceId")
	local flagOff = DataService.CanUseMockStoreInEnvironment(true, 0, false, 0)
	assert(not flagOff, "MockStore disabled when USE_MOCK_STORE=false")
	passed += 1

	local userA = -910001
	local userB = -910002

	DataService.EndMockSession(userA)
	DataService.EndMockSession(userB)

	-- 2. Enforce Loading -> Ready -> Closing readiness boundaries and independent profile state
	DataService.BeginMockSession(userA, nil)
	assert(not DataService.IsUserIdReady(userA), "Profile must NOT be ready while Loading")
	assert(DataService.GetProfileByUserId(userA) == nil, "GetProfileByUserId must return nil while Loading")

	local queueState = DataService.HandleSnapshotRequestForUserId(userA, nil)
	assert(queueState == "QueuedLoading", "Pre-ready snapshot request must queue while Loading")

	assert(DataService.CompleteMockSession(userA, 1000), "CompleteMockSession should succeed")
	assert(DataService.IsUserIdReady(userA), "Profile must be ready after completion")

	DataService.BeginMockSession(userB, nil)
	assert(DataService.CompleteMockSession(userB, 1000), "Second player session should complete")

	local profileA = DataService.GetProfileByUserId(userA) :: Types.PlayerProfileData
	local profileB = DataService.GetProfileByUserId(userB) :: Types.PlayerProfileData
	assert(profileA ~= nil and profileB ~= nil and profileA ~= profileB, "Each player needs distinct profile table")

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

	-- 3. Verify OwnerStateDTO whitelisting and deep-copy isolation
	local dtoA = DataService.BuildOwnerStateDTO(profileA)
	assert(dtoA.Coins == 250 and dtoA.BagCap == Constants.MAX_BAG_CAPACITY and dtoA.ReservedBagSlots == 0, "DTO exposes owner fields")
	assert((dtoA :: any).SchemaVersion == nil, "DTO must strip SchemaVersion")
	assert((dtoA :: any).PendingFraction == nil, "DTO must strip PendingFraction")
	assert((dtoA :: any).LastAccrualTimestamp == nil, "DTO must strip LastAccrualTimestamp")

	dtoA.Coins = 999999
	dtoA.Upgrades["PenSlot_3"] = true
	assert(profileA.Coins == 250 and profileA.Upgrades["PenSlot_3"] == nil, "Mutating DTO copy must not affect server profile")
	passed += 1

	-- 4. Verify leave clears session/readiness and rejoin starts fresh mock state
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
