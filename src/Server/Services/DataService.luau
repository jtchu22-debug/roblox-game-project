--!strict
--[[
	Service: DataService
	Purpose: Manages authoritative Stage 3 ProfileStore player persistence (Loading -> Ready -> Closing),
	         environment-aware Live vs. Mock store resolution, explicit DataStoreState == "Access" enforcement
	         on live paths, schema reconciliation & legacy migration, guaranteed final Coin settlement before
	         session teardown, OnAfterSave write confirmation, BindToClose flush, offline MaturesAt
	         preservation, and strictly scoped OwnerStateDTO delivery.
	Connections: Wraps vendored Server.Libs.ProfileStore; binds NetworkService.BindSnapshotHandler;
	             exposes OnBeforeSave / OnPlayerReady / OnPlayerClosing for EconomyService, PlotService,
	             and MeteorService; retains BeginMockSession helpers for unit self-test suites.
	How to Test in Studio: Press Play (F5) and inspect [DataService] logs and 10 self-test suites in Output.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Types = require(Shared:WaitForChild("Types"))
local CritterConfig = require(Shared:WaitForChild("Config"):WaitForChild("CritterConfig"))

local ServerRoot = script.Parent.Parent
local LibsFolder = ServerRoot:WaitForChild("Libs")
local ProfileStore = require(LibsFolder:WaitForChild("ProfileStore"))

local ServicesFolder = script.Parent
local NetworkService = require(ServicesFolder:WaitForChild("NetworkService"))

export type SessionStatus = "Loading" | "Ready" | "Closing"
export type PersistenceBackendMode = "LiveProfileStore" | "MockProfileStore"
export type SmokeTestPhase = "RoundTrip" | "Write" | "Verify"

type SignalConnectionLike = {
	Disconnect: (self: any) -> (),
}

type SignalLike = {
	Connect: (self: any, listener: (...any) -> ()) -> SignalConnectionLike,
}

type ProfileHandleLike = {
	Data: any,
	UserIds: { number },
	OnSave: SignalLike,
	OnLastSave: SignalLike,
	OnAfterSave: SignalLike,
	OnFinalSaveResult: SignalLike,
	OnSessionEnd: SignalLike,
	IsActive: (self: any) -> boolean,
	Reconcile: (self: any) -> (),
	EndSession: (self: any) -> (),
	AddUserId: (self: any, userId: number) -> (),
	Save: (self: any) -> (),
}

type ProfileStoreLike = {
	Name: string,
	StartSessionAsync: (self: any, profileKey: string, params: { Cancel: (() -> boolean)?, Steal: boolean? }?) -> ProfileHandleLike?,
	RemoveAsync: ((self: any, profileKey: string) -> boolean)?,
}

export type StartSessionOptions = {
	Store: any?,
	NowClock: number?,
	OnKick: ((reason: string) -> ())?,
}

type PlayerSession = {
	UserId: number,
	StoreName: string,
	ProfileKey: string,
	Player: Player?,
	Status: SessionStatus,
	Profile: Types.PlayerProfileData?,
	ProfileHandle: ProfileHandleLike?,
	DataInitialized: boolean,
	FinalSettled: boolean,
	FinalSaveStarted: boolean,
	FinalReleaseQueued: boolean,
	FinalSaveTargetRevision: number,
	FinalSaveExpectedCoins: number?,
	FinalWriteConfirmed: boolean,
	FinalWriteAttemptFinished: boolean,
	InitiatedByLocalEnd: boolean,
	ClosingNotified: boolean,
	SessionEndedHandled: boolean,
	PendingSnapshotRequest: boolean,
	OnSaveConn: SignalConnectionLike?,
	OnLastSaveConn: SignalConnectionLike?,
	OnFinalSaveResultConn: SignalConnectionLike?,
	OnSessionEndConn: SignalConnectionLike?,
	KickCallback: ((reason: string) -> ())?,
}

local PROFILE_TEMPLATE: Types.PlayerProfileData = {
	SchemaVersion = Constants.SCHEMA_VERSION,
	Coins = 0,
	PendingFraction = 0,
	LastAccrualTimestamp = 0,
	Revision = 1,
	Items = {},
	Slots = {},
	Upgrades = {},
	DiscoveredSpecies = {},
}

local LOAD_FAILED_KICK_MESSAGE = "Unable to load your Starfall Ranch save right now. Please rejoin in a moment."
local SESSION_ENDED_KICK_MESSAGE = "Your Starfall Ranch session ended on this server (loaded elsewhere or server closing). Please rejoin."
local SHUTTING_DOWN_KICK_MESSAGE = "This Starfall Ranch server is restarting. Please rejoin in a moment."

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

local INCUBATOR_SLOT_ORDER: { [string]: boolean } = table.freeze({
	Incubator_1 = true,
	Incubator_2 = true,
})

local PEN_SLOT_UPGRADE_MAP: { [string]: string } = table.freeze({
	Pen_2 = "PenSlot_2",
	Pen_3 = "PenSlot_3",
	Pen_4 = "PenSlot_4",
})

local DataService = {
	Name = "DataService",
}

local sessions: { [number]: PlayerSession } = {}
local closingHandlesByUserId: { [number]: ProfileHandleLike } = {}
local lastClosingSessionsByUserId: { [number]: PlayerSession } = {}
local pendingEarlySnapshots: { [number]: boolean } = {}
local readyCallbacks: { (player: Player, profile: Types.PlayerProfileData) -> () } = {}
local closingCallbacks: { (player: Player) -> () } = {}
local beforeSaveCallbacks: { (player: Player?, profile: Types.PlayerProfileData) -> () } = {}
local snapshotRequestedCallbacks: { (player: Player) -> () } = {}

local activeStore: ProfileStoreLike? = nil
local resolvedBackendMode: PersistenceBackendMode = "MockProfileStore"
local resolvedStoreName = Constants.DATASTORE_NAME_DEV
local isShuttingDown = false
local bindToCloseRegistered = false
local onErrorConn: SignalConnectionLike? = nil
local playerAddedConn: RBXScriptConnection? = nil
local playerRemovingConn: RBXScriptConnection? = nil

local function isFiniteNumber(val: unknown): boolean
	return typeof(val) == "number" and val == val and math.abs(val) ~= math.huge
end

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

local function disconnectSignalSafe(conn: SignalConnectionLike?): ()
	if conn ~= nil then
		conn:Disconnect()
	end
end

local function disconnectNonAfterSaveSignals(session: PlayerSession): ()
	disconnectSignalSafe(session.OnSaveConn)
	session.OnSaveConn = nil
	disconnectSignalSafe(session.OnLastSaveConn)
	session.OnLastSaveConn = nil
	disconnectSignalSafe(session.OnSessionEndConn)
	session.OnSessionEndConn = nil
end

local function disconnectAllHandleSignals(session: PlayerSession): ()
	disconnectNonAfterSaveSignals(session)
	disconnectSignalSafe(session.OnFinalSaveResultConn)
	session.OnFinalSaveResultConn = nil
end

local function kickSessionOwner(player: Player?, customKick: ((reason: string) -> ())?, reason: string): ()
	if customKick ~= nil then
		local ok, err = pcall(customKick, reason)
		if not ok then
			warn("[DataService] Custom kick callback error: " .. tostring(err))
		end
	elseif player ~= nil and player.Parent ~= nil then
		player:Kick(reason)
	end
end

local function notifyClosingOnce(session: PlayerSession): ()
	if session.ClosingNotified then
		return
	end
	session.ClosingNotified = true
	local ownerPlayer = session.Player
	if ownerPlayer == nil then
		return
	end
	for _, cb in ipairs(closingCallbacks) do
		local ok, err = pcall(cb, ownerPlayer)
		if not ok then
			warn("[DataService] OnPlayerClosing callback error: " .. tostring(err))
		end
	end
end

local function runBeforeSaveHooks(session: PlayerSession, profileData: Types.PlayerProfileData, markFinal: boolean): ()
	if not session.DataInitialized or session.FinalSettled then
		return
	end
	if markFinal then
		session.FinalSettled = true
	end
	local ownerPlayer = session.Player
	local snapshot = table.clone(beforeSaveCallbacks)
	for _, cb in ipairs(snapshot) do
		local okCb, errCb = pcall(cb, ownerPlayer, profileData)
		if not okCb then
			warn("[DataService] OnBeforeSave callback error: " .. tostring(errCb))
		end
	end
end

local function deliverInitialSnapshotToPlayer(player: Player, session: PlayerSession): ()
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

function DataService.ResolvePersistenceBackend(
	isStudio: boolean,
	placeId: number,
	useMockStore: boolean,
	allowedPrototypePlaceId: number
): (PersistenceBackendMode, string, string)
	if not isStudio then
		if useMockStore and allowedPrototypePlaceId > 0 and placeId == allowedPrototypePlaceId then
			return "MockProfileStore", Constants.DATASTORE_NAME_DEV, "DesignatedPrototypePlace"
		end
		-- Never silently fall back to MockStore or blank profiles on live published servers.
		return "LiveProfileStore", Constants.DATASTORE_NAME_LIVE, "PublishedLiveDataStore"
	end

	if useMockStore then
		return "MockProfileStore", Constants.DATASTORE_NAME_DEV, "StudioExplicitMockFlag"
	end
	if placeId == 0 then
		return "MockProfileStore", Constants.DATASTORE_NAME_DEV, "StudioUnpublishedLocalPlace"
	end
	return "LiveProfileStore", Constants.DATASTORE_NAME_DEV, "StudioPublishedDevStore"
end

function DataService.ValidateLiveDataStoreState(mode: PersistenceBackendMode, dataStoreState: string): (boolean, string)
	if mode == "MockProfileStore" then
		return true, "ExplicitMockMode"
	end
	if dataStoreState == "Access" then
		return true, "DataStoreAccessVerified"
	elseif dataStoreState == "NoAccess" then
		return false, "Roblox API services disabled (enable Studio Access to API Services in Game Settings -> Security)"
	elseif dataStoreState == "NoInternet" then
		return false, "No internet connection for DataStore access (DataStoreState=NoInternet)"
	end
	return false, string.format("DataStoreState did not reach Access in time (state=%s)", tostring(dataStoreState))
end

function DataService.ReconcileAndMigrateProfileData(rawData: any, nowClock: number): Types.PlayerProfileData
	assert(typeof(rawData) == "table", "Profile.Data must be a table")
	local data = rawData :: { [string]: any }

	data.SchemaVersion = Constants.SCHEMA_VERSION

	local coinsNum = tonumber(data.Coins)
	if coinsNum == nil or not isFiniteNumber(coinsNum) then
		coinsNum = 0
	end
	data.Coins = math.clamp(math.floor(coinsNum :: number), 0, Constants.MAX_COINS)

	local pendingNum = tonumber(data.PendingFraction)
	if pendingNum == nil or not isFiniteNumber(pendingNum) or (pendingNum :: number) < 0 or (pendingNum :: number) >= 1 then
		pendingNum = 0
	end
	data.PendingFraction = pendingNum :: number

	-- Stage 3 policy: zero offline Coin payout; reset accrual baseline to current login clock.
	local safeClock = if isFiniteNumber(nowClock) and nowClock >= 0 then nowClock else workspace:GetServerTimeNow()
	data.LastAccrualTimestamp = safeClock

	local revisionNum = tonumber(data.Revision)
	if revisionNum == nil or not isFiniteNumber(revisionNum) or (revisionNum :: number) < 1 then
		revisionNum = 1
	else
		revisionNum = math.floor(revisionNum :: number)
	end
	data.Revision = revisionNum :: number

	local cleanUpgrades: { [string]: boolean } = {}
	if typeof(data.Upgrades) == "table" then
		for k, v in pairs(data.Upgrades :: { [any]: any }) do
			if typeof(k) == "string" and v == true then
				cleanUpgrades[k] = true
			end
		end
	end
	data.Upgrades = cleanUpgrades

	local cleanDiscovered: { [Types.SpeciesId]: boolean } = {}
	if typeof(data.DiscoveredSpecies) == "table" then
		for k, v in pairs(data.DiscoveredSpecies :: { [any]: any }) do
			if typeof(k) == "string" and (CritterConfig.ById :: { [string]: any })[k] ~= nil and v == true then
				cleanDiscovered[k :: Types.SpeciesId] = true
			end
		end
	end

	local cleanItems: { [string]: Types.CritterItemRecord } = {}
	local cleanSlots: { [string]: string } = {}
	local sortedKeys: { string } = {}
	if typeof(data.Items) == "table" then
		for k in pairs(data.Items :: { [any]: any }) do
			if typeof(k) == "string" and #k > 0 then
				table.insert(sortedKeys, k)
			end
		end
	end
	table.sort(sortedKeys)

	for _, itemKey in ipairs(sortedKeys) do
		local rawItem = (data.Items :: { [string]: any })[itemKey]
		if typeof(rawItem) == "table" then
			local speciesId = rawItem.SpeciesId
			local state = rawItem.State
			local speciesDef = if typeof(speciesId) == "string" then (CritterConfig.ById :: { [string]: any })[speciesId] else nil
			if speciesDef ~= nil and typeof(state) == "string" and VALID_STATES[state] then
				local variant: Types.VariantId = if typeof(rawItem.Variant) == "string" and VALID_VARIANTS[rawItem.Variant]
					then rawItem.Variant :: Types.VariantId
					else "Normal"
				local createdNum = tonumber(rawItem.CreatedAt)
				local createdAt = if createdNum ~= nil and isFiniteNumber(createdNum) and (createdNum :: number) >= 0
					then math.floor(createdNum :: number)
					else math.floor(safeClock)
				local feedNum = tonumber(rawItem.FeedLevel)
				local feedLevel = if feedNum ~= nil and isFiniteNumber(feedNum)
					then math.clamp(math.floor(feedNum :: number), 0, Constants.MAX_CRITTER_FEED_LEVEL)
					else 0

				local assignedSlot: string? = if typeof(rawItem.AssignedSlot) == "string" then rawItem.AssignedSlot else nil
				local plantedAt: number? = if isFiniteNumber(rawItem.PlantedAt) and rawItem.PlantedAt >= 0 then rawItem.PlantedAt else nil
				local maturesAt: number? = if isFiniteNumber(rawItem.MaturesAt) and rawItem.MaturesAt >= 0 then rawItem.MaturesAt else nil
				local finalState: Types.ItemState = state :: Types.ItemState

				if finalState == "Incubating" then
					local slotUnlocked = assignedSlot == "Incubator_1"
						or (assignedSlot == "Incubator_2" and cleanUpgrades["Incubator_2"] == true)
					if assignedSlot ~= nil and INCUBATOR_SLOT_ORDER[assignedSlot] and slotUnlocked and cleanSlots[assignedSlot] == nil then
						-- Preserve persisted MaturesAt intact so offline incubation completes on rejoin.
						local basePlanted = if plantedAt ~= nil then plantedAt else math.floor(safeClock)
						plantedAt = basePlanted
						if maturesAt == nil then
							maturesAt = basePlanted + (speciesDef.HatchSeconds :: number)
						end
						cleanSlots[assignedSlot] = itemKey
					else
						finalState = "PodInBag"
						assignedSlot = nil
						plantedAt = nil
						maturesAt = nil
					end
				elseif finalState == "InPen" then
					local reqUpgrade = if assignedSlot ~= nil then PEN_SLOT_UPGRADE_MAP[assignedSlot] else nil
					local penValid = assignedSlot == "Pen_1"
						or (reqUpgrade ~= nil and cleanUpgrades[reqUpgrade] == true)
					if assignedSlot ~= nil and penValid and cleanSlots[assignedSlot] == nil then
						cleanSlots[assignedSlot] = itemKey
						plantedAt = nil
						maturesAt = nil
						cleanDiscovered[speciesId :: Types.SpeciesId] = true
					else
						finalState = "HatchedInBag"
						assignedSlot = nil
						plantedAt = nil
						maturesAt = nil
						cleanDiscovered[speciesId :: Types.SpeciesId] = true
					end
				elseif finalState == "HatchedInBag" then
					assignedSlot = nil
					plantedAt = nil
					maturesAt = nil
					cleanDiscovered[speciesId :: Types.SpeciesId] = true
				else
					-- PodInBag
					assignedSlot = nil
					plantedAt = nil
					maturesAt = nil
				end

				cleanItems[itemKey] = {
					UID = itemKey,
					SpeciesId = speciesId :: Types.SpeciesId,
					Variant = variant,
					State = finalState,
					AssignedSlot = assignedSlot,
					PlantedAt = plantedAt,
					MaturesAt = maturesAt,
					CreatedAt = createdAt,
					FeedLevel = feedLevel,
				}
			end
		end
	end

	data.Items = cleanItems
	data.Slots = cleanSlots
	data.DiscoveredSpecies = cleanDiscovered

	return data :: Types.PlayerProfileData
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

function DataService.GetPersistenceInfo(): (PersistenceBackendMode, string, string)
	return resolvedBackendMode, resolvedStoreName, ProfileStore.DataStoreState
end

function DataService.CreateIsolatedMockStoreForTest(label: string): any
	local sanitized = string.gsub(label, "[^%w_]", "")
	if #sanitized == 0 then
		sanitized = "Mock"
	end
	local prefix = "SR_" .. string.sub(sanitized, 1, 12) .. "_"
	local storeName = prefix .. string.sub(HttpService:GenerateGUID(false), 1, 12)
	return ProfileStore.New(storeName, PROFILE_TEMPLATE).Mock
end

function DataService.ClearTestTrackingForUserIds(userIds: { number }): ()
	for _, userId in ipairs(userIds) do
		sessions[userId] = nil
		closingHandlesByUserId[userId] = nil
		lastClosingSessionsByUserId[userId] = nil
		pendingEarlySnapshots[userId] = nil
	end
end

function DataService.IsUserFinalSaveConfirmed(userId: number): boolean
	local closingSession = lastClosingSessionsByUserId[userId]
	return closingSession ~= nil and closingSession.FinalWriteConfirmed == true
end

function DataService.WaitForUserFinalSave(userId: number, timeoutSeconds: number?): boolean
	local closingSession = lastClosingSessionsByUserId[userId]
	if closingSession == nil then
		return false
	end
	local timeout = if timeoutSeconds ~= nil then math.max(0, timeoutSeconds) else 5
	local deadline = os.clock() + timeout
	local pendingHandle = closingHandlesByUserId[userId]
	while os.clock() < deadline do
		local handleReleased = pendingHandle == nil or not pendingHandle:IsActive()
		if handleReleased and (closingSession.FinalWriteConfirmed or closingSession.FinalWriteAttemptFinished) then
			return closingSession.FinalWriteConfirmed
		end
		task.wait()
	end
	local handleReleased = pendingHandle == nil or not pendingHandle:IsActive()
	return closingSession.FinalWriteConfirmed and handleReleased
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

function DataService.OnBeforeSave(callback: (player: Player?, profile: Types.PlayerProfileData) -> ()): { Disconnect: () -> () }
	table.insert(beforeSaveCallbacks, callback)
	local disconnected = false
	return {
		Disconnect = function()
			if disconnected then
				return
			end
			disconnected = true
			local idx = table.find(beforeSaveCallbacks, callback)
			if idx ~= nil then
				table.remove(beforeSaveCallbacks, idx)
			end
		end,
	}
end

function DataService.OnSnapshotDelivered(callback: (player: Player) -> ()): ()
	table.insert(snapshotRequestedCallbacks, callback)
end

function DataService.StartProfileSessionForUserId(
	userId: number,
	player: Player?,
	options: StartSessionOptions?
): (boolean, string)
	local customKick = if options ~= nil then options.OnKick else nil
	if isShuttingDown then
		kickSessionOwner(player, customKick, SHUTTING_DOWN_KICK_MESSAGE)
		return false, "ServerShuttingDown"
	end

	if player ~= nil and player.Parent ~= Players then
		return false, "PlayerNotInGame"
	end

	local existing = sessions[userId]
	if existing ~= nil then
		return false, "SessionAlreadyExists"
	end

	local usingDefaultStore = options == nil or options.Store == nil
	if usingDefaultStore and resolvedBackendMode == "LiveProfileStore" and ProfileStore.DataStoreState ~= "Access" then
		kickSessionOwner(player, customKick, LOAD_FAILED_KICK_MESSAGE)
		return false, "DataStoreAccessUnavailable"
	end

	local targetStore = (if options ~= nil and options.Store ~= nil then options.Store else activeStore) :: ProfileStoreLike?
	if targetStore == nil then
		kickSessionOwner(player, customKick, LOAD_FAILED_KICK_MESSAGE)
		return false, "StoreNotInitialized"
	end

	local hadEarlySnapshot = pendingEarlySnapshots[userId] == true
	pendingEarlySnapshots[userId] = nil

	local profileKey = Constants.PROFILE_KEY_PREFIX .. tostring(userId)
	local session: PlayerSession = {
		UserId = userId,
		StoreName = targetStore.Name,
		ProfileKey = profileKey,
		Player = player,
		Status = "Loading",
		Profile = nil,
		ProfileHandle = nil,
		DataInitialized = false,
		FinalSettled = false,
		FinalSaveStarted = false,
		FinalReleaseQueued = false,
		FinalSaveTargetRevision = 0,
		FinalSaveExpectedCoins = nil,
		FinalWriteConfirmed = false,
		FinalWriteAttemptFinished = false,
		InitiatedByLocalEnd = false,
		ClosingNotified = false,
		SessionEndedHandled = false,
		PendingSnapshotRequest = hadEarlySnapshot,
		OnSaveConn = nil,
		OnLastSaveConn = nil,
		OnFinalSaveResultConn = nil,
		OnSessionEndConn = nil,
		KickCallback = customKick,
	}
	sessions[userId] = session

	local function shouldCancel(): boolean
		if isShuttingDown or session.Status == "Closing" or sessions[userId] ~= session then
			return true
		end
		if player ~= nil and player.Parent ~= Players then
			return true
		end
		return false
	end

	-- Wait briefly if a previous ProfileHandle on this server is still releasing or confirming its final write.
	local prevHandle = closingHandlesByUserId[userId]
	local prevClosingSession = lastClosingSessionsByUserId[userId]
	if prevHandle ~= nil or (prevClosingSession ~= nil and prevClosingSession.FinalSaveStarted and not prevClosingSession.FinalWriteConfirmed) then
		local waitDeadline = os.clock() + 5
		while os.clock() < waitDeadline and not shouldCancel() do
			local handleDone = prevHandle == nil or not prevHandle:IsActive()
			local writeDone = prevClosingSession == nil or not prevClosingSession.FinalSaveStarted or prevClosingSession.FinalWriteConfirmed
			if handleDone and writeDone then
				break
			end
			task.wait()
		end
		local handleDone = prevHandle == nil or not prevHandle:IsActive()
		if handleDone and closingHandlesByUserId[userId] == prevHandle then
			closingHandlesByUserId[userId] = nil
		end
		if shouldCancel() then
			if sessions[userId] == session then
				sessions[userId] = nil
			end
			return false, "CancelledDuringLoad"
		end
	end

	local profileKey = Constants.PROFILE_KEY_PREFIX .. tostring(userId)
	local okLoad, handleOrErr = pcall(function()
		return targetStore:StartSessionAsync(profileKey, {
			Cancel = shouldCancel,
		})
	end)

	local profileHandle: ProfileHandleLike? = if okLoad then handleOrErr :: ProfileHandleLike? else nil
	if not okLoad then
		warn(string.format("[DataService] StartSessionAsync error for key %s: %s", profileKey, tostring(handleOrErr)))
	end

	if shouldCancel() then
		if profileHandle ~= nil and profileHandle:IsActive() then
			closingHandlesByUserId[userId] = profileHandle
			pcall(function()
				profileHandle:EndSession()
			end)
		end
		if sessions[userId] == session then
			sessions[userId] = nil
		end
		return false, "CancelledDuringLoad"
	end

	if profileHandle == nil then
		if sessions[userId] == session then
			sessions[userId] = nil
		end
		-- Fail closed: NEVER fabricate a blank profile when persistence load fails.
		kickSessionOwner(player, customKick, LOAD_FAILED_KICK_MESSAGE)
		return false, "LoadFailed"
	end

	profileHandle:AddUserId(userId)
	profileHandle:Reconcile()

	local loginClock = if options ~= nil and options.NowClock ~= nil
		then options.NowClock
		else workspace:GetServerTimeNow()
	local migratedProfile = DataService.ReconcileAndMigrateProfileData(profileHandle.Data, loginClock)

	session.ProfileHandle = profileHandle
	session.Profile = migratedProfile
	session.DataInitialized = true

	-- Connect per-operation OnFinalSaveResult BEFORE OnSave/OnLastSave/OnSessionEnd so release write outcomes are never missed.
	session.OnFinalSaveResultConn = profileHandle.OnFinalSaveResult:Connect(function(committed: boolean, _reason: string, savedData: any)
		if session.FinalReleaseQueued then
			local savedRev = if typeof(savedData) == "table" then tonumber(savedData.Revision) else nil
			local savedCoins = if typeof(savedData) == "table" then tonumber(savedData.Coins) else nil
			local targetRev = session.FinalSaveTargetRevision
			local expectedCoins = session.FinalSaveExpectedCoins
			local coinsMatch = expectedCoins == nil or (savedCoins ~= nil and savedCoins == expectedCoins)
			if committed == true and savedRev ~= nil and targetRev > 0 and (savedRev :: number) == targetRev and coinsMatch then
				session.FinalWriteConfirmed = true
			end
			session.FinalWriteAttemptFinished = true
			if closingHandlesByUserId[userId] == profileHandle then
				closingHandlesByUserId[userId] = nil
			end
			disconnectSignalSafe(session.OnFinalSaveResultConn)
			session.OnFinalSaveResultConn = nil
		end
	end)

	session.OnSaveConn = profileHandle.OnSave:Connect(function()
		if session.Status == "Ready" and session.Profile ~= nil and not session.FinalSettled then
			runBeforeSaveHooks(session, session.Profile, false)
		end
	end)

	-- Fires right before UpdateAsync on manual EndSession, external lock theft/force-load, or ProfileStore shutdown.
	session.OnLastSaveConn = profileHandle.OnLastSave:Connect(function(_reason: string)
		session.Status = "Closing"
		if sessions[userId] == session then
			sessions[userId] = nil
		end
		session.FinalSaveStarted = true
		session.FinalReleaseQueued = true
		closingHandlesByUserId[userId] = profileHandle
		lastClosingSessionsByUserId[userId] = session

		local authProfile = session.Profile
		if authProfile ~= nil then
			runBeforeSaveHooks(session, authProfile, true)
			if session.FinalSaveTargetRevision == 0 then
				authProfile.Revision += 1
				session.FinalSaveTargetRevision = authProfile.Revision
				session.FinalSaveExpectedCoins = authProfile.Coins
			end
		end

		disconnectSignalSafe(session.OnSaveConn)
		session.OnSaveConn = nil
		disconnectSignalSafe(session.OnLastSaveConn)
		session.OnLastSaveConn = nil
	end)

	-- Fires on external lock theft / shutdown / passive expiry.
	session.OnSessionEndConn = profileHandle.OnSessionEnd:Connect(function()
		if session.InitiatedByLocalEnd or session.SessionEndedHandled then
			return
		end
		session.SessionEndedHandled = true
		session.Status = "Closing"
		if sessions[userId] == session then
			sessions[userId] = nil
		end

		disconnectNonAfterSaveSignals(session)
		if not session.FinalSaveStarted then
			disconnectSignalSafe(session.OnFinalSaveResultConn)
			session.OnFinalSaveResultConn = nil
		end

		notifyClosingOnce(session)

		local activePlayer = session.Player
		local stillInServer = activePlayer ~= nil and activePlayer.Parent == Players
		local kickCb = session.KickCallback
		session.Profile = nil
		session.ProfileHandle = nil
		session.Player = nil
		session.KickCallback = nil

		if stillInServer or kickCb ~= nil then
			kickSessionOwner(activePlayer, kickCb, SESSION_ENDED_KICK_MESSAGE)
		end
	end)

	if shouldCancel() or not profileHandle:IsActive() then
		disconnectAllHandleSignals(session)
		if sessions[userId] == session then
			sessions[userId] = nil
		end
		session.Status = "Closing"
		session.Profile = nil
		session.ProfileHandle = nil
		session.Player = nil
		session.KickCallback = nil
		if profileHandle:IsActive() then
			closingHandlesByUserId[userId] = profileHandle
			pcall(function()
				profileHandle:EndSession()
			end)
		end
		return false, "CancelledDuringLoad"
	end

	session.Status = "Ready"

	if player ~= nil then
		for _, cb in ipairs(readyCallbacks) do
			local okCb, errCb = pcall(cb, player, migratedProfile)
			if not okCb then
				warn("[DataService] OnPlayerReady callback error: " .. tostring(errCb))
			end
		end

		-- Check session remained Ready after admission checks (e.g., server-full plot rejection).
		if sessions[userId] == session and session.Status == "Ready" and player.Parent == Players then
			deliverInitialSnapshotToPlayer(player, session)
		end
	end

	return true, "Ready"
end

function DataService.EndSession(userId: number, player: Player?): ()
	pendingEarlySnapshots[userId] = nil
	local session = sessions[userId]
	if session == nil then
		return
	end
	if player ~= nil and session.Player ~= nil and session.Player ~= player then
		return
	end

	session.InitiatedByLocalEnd = true
	session.SessionEndedHandled = true
	session.Status = "Closing"
	if sessions[userId] == session then
		sessions[userId] = nil
	end

	local profileData = session.Profile
	local handle = session.ProfileHandle

	-- 1. Notify gameplay listeners so no further actions modify this profile.
	notifyClosingOnce(session)

	-- 2. Settle final Coins ONCE from the authoritative profile BEFORE tearing down handle state or releasing lock.
	if profileData ~= nil and session.DataInitialized then
		runBeforeSaveHooks(session, profileData, true)
		if handle ~= nil and session.FinalSaveTargetRevision == 0 then
			profileData.Revision += 1
			session.FinalSaveTargetRevision = profileData.Revision
			session.FinalSaveExpectedCoins = profileData.Coins
		end
	end

	-- 3. Keep OnSave/OnLastSave/OnFinalSaveResult connected so handle:EndSession() transitions cleanly through final release tracking;
	--    disconnect only OnSessionEnd because InitiatedByLocalEnd handles teardown here.
	disconnectSignalSafe(session.OnSessionEndConn)
	session.OnSessionEndConn = nil

	session.Profile = nil
	session.ProfileHandle = nil
	session.Player = nil
	session.KickCallback = nil
	lastClosingSessionsByUserId[userId] = session

	if handle ~= nil and handle:IsActive() then
		session.FinalSaveStarted = true
		closingHandlesByUserId[userId] = handle
		local okEnd, errEnd = pcall(function()
			handle:EndSession()
		end)
		if not okEnd then
			warn("[DataService] Profile:EndSession error: " .. tostring(errEnd))
			disconnectAllHandleSignals(session)
			session.FinalWriteConfirmed = false
			session.FinalWriteAttemptFinished = true
		elseif not session.FinalReleaseQueued then
			disconnectAllHandleSignals(session)
			session.FinalWriteConfirmed = false
			session.FinalWriteAttemptFinished = true
		end
	else
		-- Never assume an inactive handle was safely saved unless a prior OnLastSave+OnAfterSave already confirmed it.
		if not session.FinalReleaseQueued then
			disconnectAllHandleSignals(session)
			session.FinalWriteConfirmed = false
			session.FinalWriteAttemptFinished = true
		end
	end
end

function DataService.FlushActiveProfileSessions(timeoutSeconds: number?): boolean
	local timeout = if timeoutSeconds ~= nil then timeoutSeconds else Constants.SHUTDOWN_FLUSH_TIMEOUT_SECONDS
	local activeUserIds: { number } = {}
	local trackedEntries: { { UserId: number, Session: PlayerSession, Handle: ProfileHandleLike? } } = {}

	for userId, session in pairs(sessions) do
		table.insert(activeUserIds, userId)
		if session.ProfileHandle ~= nil then
			table.insert(trackedEntries, {
				UserId = userId,
				Session = session,
				Handle = session.ProfileHandle,
			})
		end
	end

	for _, userId in ipairs(activeUserIds) do
		DataService.EndSession(userId, nil)
	end

	-- Wait for any in-progress OnLastSave release writes without re-including previously finished failed/stale sessions.
	for userId, closingSession in pairs(lastClosingSessionsByUserId) do
		if closingSession.FinalSaveStarted and not closingSession.FinalWriteAttemptFinished then
			local alreadyTracked = false
			for _, entry in ipairs(trackedEntries) do
				if entry.Session == closingSession then
					alreadyTracked = true
					break
				end
			end
			if not alreadyTracked then
				table.insert(trackedEntries, {
					UserId = userId,
					Session = closingSession,
					Handle = closingHandlesByUserId[userId],
				})
			end
		end
	end

	local deadline = os.clock() + math.max(0, timeout)
	while os.clock() < deadline do
		local allDone = true
		for _, entry in ipairs(trackedEntries) do
			local handle = entry.Handle
			local handleReleased = handle == nil or not handle:IsActive()
			if not handleReleased or (not entry.Session.FinalWriteConfirmed and not entry.Session.FinalWriteAttemptFinished) then
				allDone = false
				break
			end
		end
		if allDone then
			break
		end
		task.wait()
	end

	local allConfirmed = true
	for _, entry in ipairs(trackedEntries) do
		local handle = entry.Handle
		local handleReleased = handle == nil or not handle:IsActive()
		if not entry.Session.FinalWriteConfirmed or not handleReleased then
			allConfirmed = false
		elseif handle ~= nil and closingHandlesByUserId[entry.UserId] == handle then
			closingHandlesByUserId[entry.UserId] = nil
		end
	end
	return allConfirmed
end

function DataService.BeginMockSession(userId: number, player: Player?): PlayerSession
	local existing = sessions[userId]
	if existing ~= nil then
		DataService.EndSession(userId, nil)
	end

	local hadEarlySnapshot = pendingEarlySnapshots[userId] == true
	pendingEarlySnapshots[userId] = nil

	local session: PlayerSession = {
		UserId = userId,
		StoreName = "MockHelper",
		ProfileKey = Constants.PROFILE_KEY_PREFIX .. tostring(userId),
		Player = player,
		Status = "Loading",
		Profile = nil,
		ProfileHandle = nil,
		DataInitialized = false,
		FinalSettled = false,
		FinalSaveStarted = false,
		FinalReleaseQueued = false,
		FinalSaveTargetRevision = 0,
		FinalSaveExpectedCoins = nil,
		FinalWriteConfirmed = false,
		FinalWriteAttemptFinished = false,
		InitiatedByLocalEnd = false,
		ClosingNotified = false,
		SessionEndedHandled = false,
		PendingSnapshotRequest = hadEarlySnapshot,
		OnSaveConn = nil,
		OnLastSaveConn = nil,
		OnFinalSaveResultConn = nil,
		OnSessionEndConn = nil,
		KickCallback = nil,
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
	session.DataInitialized = true
	session.Status = "Ready"

	local player = session.Player
	if player ~= nil then
		for _, cb in ipairs(readyCallbacks) do
			local ok, err = pcall(cb, player, profile)
			if not ok then
				warn("[DataService] OnPlayerReady callback error: " .. tostring(err))
			end
		end

		if session.PendingSnapshotRequest and sessions[userId] == session and session.Status == "Ready" then
			deliverInitialSnapshotToPlayer(player, session)
		end
	end

	return true
end

function DataService.EndMockSession(userId: number, player: Player?): ()
	DataService.EndSession(userId, player)
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
			deliverInitialSnapshotToPlayer(player, session)
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

function DataService.RunLiveDevDataStoreSmokeTest(phase: SmokeTestPhase?, testUserId: number?): (boolean, string)
	local runPhase: SmokeTestPhase = if phase ~= nil then phase else "RoundTrip"
	local uid = if testUserId ~= nil then testUserId else -919999
	local waitDeadline = os.clock() + Constants.DATASTORE_READY_WAIT_SECONDS
	while ProfileStore.DataStoreState == "NotReady" and os.clock() < waitDeadline do
		task.wait(0.05)
	end
	if ProfileStore.DataStoreState ~= "Access" then
		return false, string.format("Live DataStore unavailable (DataStoreState=%s, PlaceId=%d, GameId=%d)", ProfileStore.DataStoreState, game.PlaceId, game.GameId)
	end

	local smokeStoreName = Constants.DATASTORE_NAME_DEV .. "_Smoke"
	local smokeStore = (ProfileStore.New(smokeStoreName, PROFILE_TEMPLATE) :: any) :: ProfileStoreLike
	local key = Constants.PROFILE_KEY_PREFIX .. tostring(uid)
	local t0 = math.floor(workspace:GetServerTimeNow())

	if runPhase == "RoundTrip" or runPhase == "Write" then
		if smokeStore.RemoveAsync ~= nil then
			pcall(function()
				(smokeStore.RemoveAsync :: any)(smokeStore, key)
			end)
		end

		local joinOk, joinReason = DataService.StartProfileSessionForUserId(uid, nil, {
			Store = smokeStore,
			NowClock = t0,
		})
		if not joinOk then
			return false, "Smoke test Write initial load failed: " .. joinReason
		end

		local prof = DataService.GetProfileByUserId(uid) :: Types.PlayerProfileData
		prof.Coins = 300
		prof.LastAccrualTimestamp = t0 - 10 -- Verify OnEnd final settlement adds >=10s pen earnings.
		prof.Upgrades["Incubator_1"] = true
		prof.DiscoveredSpecies["CinderPup"] = true
		prof.Items["smoke-pen"] = {
			UID = "smoke-pen",
			SpeciesId = "CinderPup",
			Variant = "Normal",
			State = "InPen",
			AssignedSlot = "Pen_1",
			PlantedAt = nil,
			MaturesAt = nil,
			CreatedAt = t0,
			FeedLevel = 1,
		}
		prof.Slots["Pen_1"] = "smoke-pen"
		prof.Items["smoke-pod"] = {
			UID = "smoke-pod",
			SpeciesId = "FrostBeetle",
			Variant = "Normal",
			State = "Incubating",
			AssignedSlot = "Incubator_1",
			PlantedAt = t0,
			MaturesAt = t0 + 45,
			CreatedAt = t0,
			FeedLevel = 0,
		}
		prof.Slots["Incubator_1"] = "smoke-pod"

		DataService.EndSession(uid)
		local savedOk = DataService.WaitForUserFinalSave(uid, 10)
		if not savedOk then
			return false, "Live DataStore final write was not confirmed after release"
		end

		if runPhase == "Write" then
			return true, string.format(
				"Write phase confirmed (%s, Version=%s, PlaceId=%d, GameId=%d, Key=%s, PlantedAt=%d, MaturesAt=%d). Restart Play/Server and run Verify phase.",
				smokeStoreName,
				Constants.GAME_VERSION,
				game.PlaceId,
				game.GameId,
				key,
				t0,
				t0 + 45
			)
		end
	end

	local reopenOk, reopenReason = DataService.StartProfileSessionForUserId(uid, nil, {
		Store = smokeStore,
		NowClock = t0 + 10,
	})
	if not reopenOk then
		return false, "Smoke test Verify load failed: " .. reopenReason
	end

	local reloaded = DataService.GetProfileByUserId(uid) :: Types.PlayerProfileData
	local savedCoins = reloaded.Coins
	local critter = reloaded.Items["smoke-pen"]
	local pod = reloaded.Items["smoke-pod"]
	local coinsOk = savedCoins > 300
	local critterOk = critter ~= nil and critter.SpeciesId == "CinderPup" and critter.FeedLevel == 1 and reloaded.Slots["Pen_1"] == "smoke-pen"
	local podOk = pod ~= nil
		and pod.State == "Incubating"
		and pod.PlantedAt ~= nil
		and pod.MaturesAt == ((pod.PlantedAt :: number) + 45)
		and reloaded.Slots["Incubator_1"] == "smoke-pod"
	local podMaturesAt = if pod ~= nil and pod.MaturesAt ~= nil then pod.MaturesAt else -1

	DataService.EndSession(uid)
	DataService.WaitForUserFinalSave(uid, 10)
	if smokeStore.RemoveAsync ~= nil then
		pcall(function()
			(smokeStore.RemoveAsync :: any)(smokeStore, key)
		end)
	end

	if not (coinsOk and critterOk and podOk) then
		return false, string.format("Smoke verify mismatch (coinsOk=%s Coins=%d critterOk=%s podOk=%s)", tostring(coinsOk), savedCoins, tostring(critterOk), tostring(podOk))
	end
	return true, string.format(
		"Live Dev DataStore %s verified (%s, Version=%s, PlaceId=%d, GameId=%d, SettledCoins=%d, Critter=CinderPup, MaturesAt=%d)",
		runPhase,
		smokeStoreName,
		Constants.GAME_VERSION,
		game.PlaceId,
		game.GameId,
		savedCoins,
		podMaturesAt
	)
end

local function onPlayerAdded(player: Player): ()
	if player.Parent ~= Players then
		return
	end
	task.spawn(function()
		DataService.StartProfileSessionForUserId(player.UserId, player)
	end)
end

local function onPlayerRemoving(player: Player): ()
	DataService.EndSession(player.UserId, player)
end

function DataService.Init(self: typeof(DataService)): ()
	local mode, storeName, reason = DataService.ResolvePersistenceBackend(
		RunService:IsStudio(),
		game.PlaceId,
		Constants.USE_MOCK_STORE,
		Constants.ALLOW_PUBLISHED_PROTOTYPE_PLACE_ID
	)
	resolvedBackendMode = mode
	resolvedStoreName = storeName

	local baseStore = ProfileStore.New(storeName, PROFILE_TEMPLATE)

	if mode == "LiveProfileStore" then
		local deadline = os.clock() + Constants.DATASTORE_READY_WAIT_SECONDS
		while ProfileStore.DataStoreState == "NotReady" and os.clock() < deadline do
			task.wait(0.05)
		end
		local dsOk, dsReason = DataService.ValidateLiveDataStoreState(mode, ProfileStore.DataStoreState)
		if not dsOk then
			activeStore = nil
			error(string.format("[DataService] Refusing LiveProfileStore on %s without API access: %s", storeName, dsReason))
		end
		activeStore = baseStore :: ProfileStoreLike
	else
		activeStore = baseStore.Mock :: ProfileStoreLike
	end

	if onErrorConn == nil then
		onErrorConn = ProfileStore.OnError:Connect(function(message: string, errStoreName: string, profileKey: string)
			warn(string.format("[DataService][ProfileStore] Error (%s / %s): %s", tostring(errStoreName), tostring(profileKey), tostring(message)))
		end)
	end

	if not bindToCloseRegistered then
		bindToCloseRegistered = true
		game:BindToClose(function()
			isShuttingDown = true
			local flushTimeout = if RunService:IsStudio() then 0.5 else Constants.SHUTDOWN_FLUSH_TIMEOUT_SECONDS
			DataService.FlushActiveProfileSessions(flushTimeout)
		end)
	end

	print(string.format(
		"[DataService] Initialized Stage 3 ProfileStore backend (Mode=%s, Store=%s, Reason=%s, DataStoreState=%s).",
		mode,
		storeName,
		reason,
		ProfileStore.DataStoreState
	))
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

local function waitForHandleRelease(handle: ProfileHandleLike, timeoutSeconds: number): ()
	local deadline = os.clock() + timeoutSeconds
	while handle:IsActive() and os.clock() < deadline do
		task.wait()
	end
end

function DataService.RunSelfTest(): number
	local passed = 0

	-- 1. Environment guard, persistence backend resolution, and strict Live DataStoreState validation
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

	local liveMode, liveStore, liveReason = DataService.ResolvePersistenceBackend(false, 999999, false, 0)
	assert(liveMode == "LiveProfileStore" and liveStore == Constants.DATASTORE_NAME_LIVE and liveReason == "PublishedLiveDataStore", "Published server uses LiveProfileStore")
	local localStudioMode, localStudioStore, localStudioReason = DataService.ResolvePersistenceBackend(true, 0, false, 0)
	assert(localStudioMode == "MockProfileStore" and localStudioStore == Constants.DATASTORE_NAME_DEV and localStudioReason == "StudioUnpublishedLocalPlace", "Unpublished Studio uses MockProfileStore safely")
	local pubStudioMode, pubStudioStore, pubStudioReason = DataService.ResolvePersistenceBackend(true, 777777, false, 0)
	assert(pubStudioMode == "LiveProfileStore" and pubStudioStore == Constants.DATASTORE_NAME_DEV and pubStudioReason == "StudioPublishedDevStore", "Published Studio uses isolated StudioDev store")

	assert((DataService.ValidateLiveDataStoreState("LiveProfileStore", "Access")), "LiveProfileStore allowed when DataStoreState=Access")
	assert(not DataService.ValidateLiveDataStoreState("LiveProfileStore", "NoAccess"), "LiveProfileStore rejects NoAccess instead of silent mock fallback")
	assert(not DataService.ValidateLiveDataStoreState("LiveProfileStore", "NoInternet"), "LiveProfileStore rejects NoInternet")
	assert(not DataService.ValidateLiveDataStoreState("LiveProfileStore", "NotReady"), "LiveProfileStore rejects NotReady")
	assert((DataService.ValidateLiveDataStoreState("MockProfileStore", "NoAccess")), "Explicit MockProfileStore permitted when local Studio has NoAccess")
	passed += 1

	local userA = -910001
	local userB = -910002

	DataService.EndSession(userA)
	DataService.EndSession(userB)

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

	-- 4. Verify leave clears session/readiness and mock helper rejoin starts clean
	DataService.EndMockSession(userA)
	assert(not DataService.IsUserIdReady(userA), "Readiness must clear on leave")
	assert(DataService.GetProfileByUserId(userA) == nil, "Profile must clear on leave")
	assert(DataService.HandleSnapshotRequestForUserId(userA, nil) == "IgnoredNoSession", "Removed session ignores snapshots")

	DataService.BeginMockSession(userA, nil)
	assert(DataService.CompleteMockSession(userA, 2000), "Rejoin session must initialize")
	local rejoinedA = DataService.GetProfileByUserId(userA) :: Types.PlayerProfileData
	assert(rejoinedA.Coins == 0 and next(rejoinedA.Items) == nil, "Mock helper rejoin starts clean")

	DataService.EndMockSession(userA)
	DataService.EndMockSession(userB)
	passed += 1

	-- 5. ProfileStore.Mock Round-Trip: Join -> Mutate -> EndSession (confirmed OnAfterSave) -> Rejoin preserves full state & MaturesAt
	local isolatedStoreName = "SR_Test_" .. string.sub(HttpService:GenerateGUID(false), 1, 12)
	local testBaseStore = ProfileStore.New(isolatedStoreName, PROFILE_TEMPLATE)
	local testMockStore = testBaseStore.Mock
	local userP = -910051
	local tBase = math.floor(workspace:GetServerTimeNow())
	local tFutureGuard = tBase + 60
	DataService.EndSession(userP)

	local joinOk, joinReason = DataService.StartProfileSessionForUserId(userP, nil, {
		Store = testMockStore,
		NowClock = tFutureGuard,
	})
	assert(joinOk and joinReason == "Ready" and DataService.IsUserIdReady(userP), "ProfileStore.Mock initial join must succeed")

	local pPersist = DataService.GetProfileByUserId(userP) :: Types.PlayerProfileData
	pPersist.Coins = 420
	pPersist.Revision = 5
	pPersist.Upgrades["PenSlot_2"] = true
	pPersist.Upgrades["FrostCracker"] = true
	pPersist.DiscoveredSpecies["StarSlime"] = true
	pPersist.DiscoveredSpecies["CinderPup"] = true
	pPersist.Items["pod-bag"] = {
		UID = "pod-bag",
		SpeciesId = "StarSlime",
		Variant = "Normal",
		State = "PodInBag",
		AssignedSlot = nil,
		PlantedAt = nil,
		MaturesAt = nil,
		CreatedAt = tBase - 5,
		FeedLevel = 0,
	}
	pPersist.Items["pod-inc"] = {
		UID = "pod-inc",
		SpeciesId = "FrostBeetle",
		Variant = "Normal",
		State = "Incubating",
		AssignedSlot = "Incubator_1",
		PlantedAt = tBase,
		MaturesAt = tBase + 45,
		CreatedAt = tBase - 2,
		FeedLevel = 0,
	}
	pPersist.Slots["Incubator_1"] = "pod-inc"
	pPersist.Items["pen-critter"] = {
		UID = "pen-critter",
		SpeciesId = "CinderPup",
		Variant = "Radiant",
		State = "InPen",
		AssignedSlot = "Pen_2",
		PlantedAt = nil,
		MaturesAt = nil,
		CreatedAt = tBase - 10,
		FeedLevel = 1,
	}
	pPersist.Slots["Pen_2"] = "pen-critter"

	DataService.EndSession(userP)
	assert(not DataService.IsUserIdReady(userP), "Session not ready after EndSession")
	assert(DataService.WaitForUserFinalSave(userP, 2), "Final OnAfterSave must confirm write after EndSession")

	local rejoinClock = tBase + 44
	local rejoinOk = DataService.StartProfileSessionForUserId(userP, nil, {
		Store = testMockStore,
		NowClock = rejoinClock,
	})
	assert(rejoinOk and DataService.IsUserIdReady(userP), "Rejoin after EndSession must succeed")
	local reloaded = DataService.GetProfileByUserId(userP) :: Types.PlayerProfileData
	assert(reloaded.Coins == 420 and reloaded.Revision == 6, "Coins & Revision (+1 on EndSession) must persist across rejoin")
	assert(reloaded.LastAccrualTimestamp == rejoinClock, "Stage 3 login resets LastAccrualTimestamp with zero offline coins")
	assert(reloaded.Upgrades["PenSlot_2"] == true and reloaded.Upgrades["FrostCracker"] == true, "Upgrades persist")
	assert(reloaded.DiscoveredSpecies["StarSlime"] == true and reloaded.DiscoveredSpecies["CinderPup"] == true, "DiscoveredSpecies persist")
	assert(reloaded.Items["pod-inc"] ~= nil and reloaded.Items["pod-inc"].MaturesAt == (tBase + 45), "Offline MaturesAt must survive rejoin intact")
	assert(reloaded.Items["pen-critter"] ~= nil and reloaded.Items["pen-critter"].FeedLevel == 1 and reloaded.Items["pen-critter"].Variant == "Radiant", "Pen critter variant & FeedLevel persist")
	assert(reloaded.Slots["Incubator_1"] == "pod-inc" and reloaded.Slots["Pen_2"] == "pen-critter", "Slots persist across rejoin")

	DataService.EndSession(userP)
	assert(DataService.WaitForUserFinalSave(userP, 2), "Second EndSession final write confirmed")
	passed += 1

	-- 6. Forced load failure: clean kick & zero silent blank overwrite of existing save
	local failKickCount = 0
	local failKickReason = ""
	local failingStore = {
		Name = isolatedStoreName .. "_Fail",
		StartSessionAsync = function(_self: any, _key: string, _params: any)
			return nil
		end,
	}
	local failOk, failReason = DataService.StartProfileSessionForUserId(userP, nil, {
		Store = failingStore,
		NowClock = tFutureGuard,
		OnKick = function(msg: string)
			failKickCount += 1
			failKickReason = msg
		end,
	})
	assert(not failOk and failReason == "LoadFailed", "Nil StartSessionAsync must fail closed with LoadFailed")
	assert(failKickCount == 1 and failKickReason == LOAD_FAILED_KICK_MESSAGE, "Load failure must trigger clean player kick")
	assert(not DataService.IsUserIdReady(userP) and DataService.GetProfileByUserId(userP) == nil, "Failed load must not mark session Ready or blank profile")

	local failAfterThrowCount = 0
	local throwingStore = {
		Name = isolatedStoreName .. "_Throw",
		StartSessionAsync = function(_self: any, _key: string, _params: any)
			error("Simulated DataStore 503 outage")
		end,
	}
	local throwOk, throwReason = DataService.StartProfileSessionForUserId(userP, nil, {
		Store = throwingStore,
		NowClock = tFutureGuard,
		OnKick = function(_msg: string)
			failAfterThrowCount += 1
		end,
	})
	assert(not throwOk and throwReason == "LoadFailed" and failAfterThrowCount == 1, "Throwing StartSessionAsync must fail closed and kick cleanly")

	local verifyAfterFailOk = DataService.StartProfileSessionForUserId(userP, nil, {
		Store = testMockStore,
		NowClock = tFutureGuard,
	})
	assert(verifyAfterFailOk, "Existing save must still load after earlier StartSessionAsync failure")
	local preservedProfile = DataService.GetProfileByUserId(userP) :: Types.PlayerProfileData
	assert(preservedProfile.Coins == 420 and preservedProfile.Items["pod-inc"] ~= nil, "Failed load must NEVER overwrite existing saved Coins or Items")
	passed += 1

	-- 7. Dual-server lock theft (OnSessionEnd fires while online -> clears readiness & kicks cleanly)
	local theftKickCount = 0
	local userTheft = -910052
	DataService.EndSession(userTheft)
	local theftJoinOk = DataService.StartProfileSessionForUserId(userTheft, nil, {
		Store = testMockStore,
		NowClock = tFutureGuard,
		OnKick = function(_msg: string)
			theftKickCount += 1
		end,
	})
	assert(theftJoinOk and DataService.IsUserIdReady(userTheft), "Theft test session ready")
	local stolenSession = sessions[userTheft]
	local stolenHandle = if stolenSession ~= nil then stolenSession.ProfileHandle else nil
	assert(stolenHandle ~= nil, "Theft test handle present")
	local activeStolenHandle = stolenHandle :: ProfileHandleLike
	activeStolenHandle:EndSession()
	waitForHandleRelease(activeStolenHandle, 2)
	task.wait()
	assert(not DataService.IsUserIdReady(userTheft) and DataService.GetProfileByUserId(userTheft) == nil, "Lock loss clears readiness immediately")
	assert(theftKickCount == 1, "Lock loss (OnSessionEnd) triggers clean kick")
	assert(DataService.WaitForUserFinalSave(userTheft, 2), "External/last save path confirms final write")
	passed += 1

	-- 8. BindToClose / FlushActiveProfileSessions confirms final writes & saves multiple profiles
	local userFlush1 = userP
	local userFlush2 = -910053
	DataService.EndSession(userFlush2)
	local pFlush1 = DataService.GetProfileByUserId(userFlush1) :: Types.PlayerProfileData
	pFlush1.Coins = 777
	pFlush1.LastAccrualTimestamp = tFutureGuard
	assert(DataService.StartProfileSessionForUserId(userFlush2, nil, {
		Store = testMockStore,
		NowClock = tFutureGuard,
	}), "Flush test user 2 starts")
	local pFlush2 = DataService.GetProfileByUserId(userFlush2) :: Types.PlayerProfileData
	pFlush2.Coins = 888

	local flushedAll = DataService.FlushActiveProfileSessions(2)
	assert(flushedAll, "FlushActiveProfileSessions must wait for OnAfterSave write confirmation")
	assert(not DataService.IsUserIdReady(userFlush1) and not DataService.IsUserIdReady(userFlush2), "Flush clears all active session readiness")
	assert(DataService.WaitForUserFinalSave(userFlush1, 0.5) and DataService.WaitForUserFinalSave(userFlush2, 0.5), "Final write flags confirmed")

	assert(DataService.StartProfileSessionForUserId(userFlush1, nil, { Store = testMockStore, NowClock = tFutureGuard }), "Reload flushed user 1")
	assert(DataService.StartProfileSessionForUserId(userFlush2, nil, { Store = testMockStore, NowClock = tFutureGuard }), "Reload flushed user 2")
	assert((DataService.GetProfileByUserId(userFlush1) :: Types.PlayerProfileData).Coins == 777, "Shutdown flush preserved user 1 Coins=777")
	assert((DataService.GetProfileByUserId(userFlush2) :: Types.PlayerProfileData).Coins == 888, "Shutdown flush preserved user 2 Coins=888")
	assert(DataService.FlushActiveProfileSessions(2), "Cleanup flush confirmed")
	passed += 1

	-- 9. Legacy schema migration, corruption hardening & offline MaturesAt preservation (zero offline Coins)
	local legacyRaw: { [string]: any } = {
		SchemaVersion = 0,
		Coins = 9_999_999_999,
		PendingFraction = -0.5,
		LastAccrualTimestamp = 100,
		Revision = 0,
		Slots = {
			Pen_2 = "ghost-missing",
			Incubator_1 = "legacy-inc",
		},
		Items = {
			["legacy-inc"] = {
				UID = "legacy-inc",
				SpeciesId = "NebulaFox",
				Variant = "Normal",
				State = "Incubating",
				AssignedSlot = "Incubator_1",
				PlantedAt = 2000,
				MaturesAt = 2045,
				CreatedAt = 1990,
			},
			["legacy-hatched"] = {
				UID = "legacy-hatched",
				SpeciesId = "CometOwl",
				Variant = "Radiant",
				State = "HatchedInBag",
				CreatedAt = 1500,
			},
			["locked-pen"] = {
				UID = "locked-pen",
				SpeciesId = "StarSlime",
				Variant = "Normal",
				State = "InPen",
				AssignedSlot = "Pen_3",
				CreatedAt = 1400,
			},
			["bad-species"] = {
				UID = "bad-species",
				SpeciesId = "RemovedBogusCritter",
				State = "PodInBag",
				CreatedAt = 1200,
			},
		},
	}

	local migrated = DataService.ReconcileAndMigrateProfileData(legacyRaw, 2044)
	assert(migrated.SchemaVersion == Constants.SCHEMA_VERSION, "Legacy SchemaVersion updated")
	assert(migrated.Coins == Constants.MAX_COINS, "Out-of-range Coins clamped cleanly")
	assert(migrated.PendingFraction == 0 and migrated.Revision == 1, "Invalid fraction/revision repaired")
	assert(migrated.LastAccrualTimestamp == 2044, "Login resets LastAccrualTimestamp with zero offline payout")
	assert(migrated.Slots["Pen_2"] == nil, "Dangling slot pointer stripped")
	assert(migrated.Items["legacy-inc"] ~= nil and migrated.Items["legacy-inc"].MaturesAt == 2045, "Offline MaturesAt timestamp preserved during migration")
	assert(migrated.Items["legacy-inc"].FeedLevel == 0, "Legacy omitted FeedLevel defaulted to 0")
	assert(migrated.DiscoveredSpecies["CometOwl"] == true and migrated.DiscoveredSpecies["StarSlime"] == true, "DiscoveredSpecies backfilled from legacy critters")
	assert(migrated.Items["locked-pen"] ~= nil and migrated.Items["locked-pen"].State == "HatchedInBag" and migrated.Items["locked-pen"].AssignedSlot == nil, "Locked pen item safely demoted to bag")
	assert(migrated.Items["bad-species"] == nil, "Unknown species entry removed safely during migration")
	passed += 1

	-- 10. Verify OnBeforeSave runs once after closing gameplay and BEFORE ProfileStore writes on BOTH EndSession and FlushActiveProfileSessions
	local userHook = -910054
	DataService.EndSession(userHook)
	local hookCalls = 0
	local readinessAtHook = true
	local hookConn = DataService.OnBeforeSave(function(_p: Player?, prof: Types.PlayerProfileData)
		if prof.Revision >= 9001 then
			hookCalls += 1
			readinessAtHook = DataService.IsUserIdReady(userHook)
			prof.Coins += 55
		end
	end)

	assert(DataService.StartProfileSessionForUserId(userHook, nil, { Store = testMockStore, NowClock = 3000 }), "Suite 10 join 1")
	local profHook1 = DataService.GetProfileByUserId(userHook) :: Types.PlayerProfileData
	profHook1.Revision = 9001
	profHook1.Coins = 100

	DataService.EndSession(userHook)
	assert(hookCalls == 1, "EndSession must run OnBeforeSave exactly once before final save")
	assert(not readinessAtHook, "Session must already be closed to gameplay when final OnBeforeSave settles")
	assert(DataService.WaitForUserFinalSave(userHook, 2), "OnAfterSave must confirm EndSession final write")

	assert(DataService.StartProfileSessionForUserId(userHook, nil, { Store = testMockStore, NowClock = 3010 }), "Suite 10 rejoin after EndSession")
	local profHook2 = DataService.GetProfileByUserId(userHook) :: Types.PlayerProfileData
	assert(profHook2.Coins == 155, "EndSession persisted OnBeforeSave mutation (+55)")

	hookCalls = 0
	assert(DataService.FlushActiveProfileSessions(2), "FlushActiveProfileSessions must run final OnBeforeSave and confirm write")
	assert(hookCalls == 1, "Shutdown flush must run OnBeforeSave exactly once")

	assert(DataService.StartProfileSessionForUserId(userHook, nil, { Store = testMockStore, NowClock = 3020 }), "Suite 10 rejoin after Flush")
	local profHook3 = DataService.GetProfileByUserId(userHook) :: Types.PlayerProfileData
	assert(profHook3.Coins == 210, "Shutdown flush persisted OnBeforeSave mutation (+55 -> 210)")

	hookConn:Disconnect()
	DataService.FlushActiveProfileSessions(2)
	passed += 1

	-- 11. Review #018 #1 Regression: Per-operation OnFinalSaveResult confirmation (autosave overlap, inactive handle, newer-owner equal/higher rev, and force-load)
	local function createFakeAsyncStore(storeLabel: string)
		local makeSignal = function()
			local listeners: { (...any) -> () } = {}
			return {
				Connect = function(_self: any, fn: (...any) -> ())
					table.insert(listeners, fn)
					return {
						Disconnect = function()
							local idx = table.find(listeners, fn)
							if idx ~= nil then
								table.remove(listeners, idx)
							end
						end,
					}
				end,
				Fire = function(_self: any, ...: any)
					local copy = table.clone(listeners)
					for _, fn in ipairs(copy) do
						fn(...)
					end
				end,
			}
		end

		local controller = {
			CurrentHandle = nil :: any,
			IsActiveFlag = true,
			SaveSig = makeSignal(),
			LastSaveSig = makeSignal(),
			AfterSaveSig = makeSignal(),
			FinalResultSig = makeSignal(),
			EndSig = makeSignal(),
		}

		local fakeStore = {
			Name = storeLabel,
			StartSessionAsync = function(_self: any, _key: string, _params: any)
				controller.IsActiveFlag = true
				local handle = {
					Data = DataService.CreateDefaultProfile(workspace:GetServerTimeNow()),
					UserIds = {},
					OnSave = controller.SaveSig,
					OnLastSave = controller.LastSaveSig,
					OnAfterSave = controller.AfterSaveSig,
					OnFinalSaveResult = controller.FinalResultSig,
					OnSessionEnd = controller.EndSig,
					IsActive = function()
						return controller.IsActiveFlag
					end,
					Reconcile = function() end,
					AddUserId = function(selfHandle: any, id: number)
						table.insert(selfHandle.UserIds, id)
					end,
					Save = function()
						controller.SaveSig:Fire()
					end,
					EndSession = function()
						controller.SaveSig:Fire()
						controller.LastSaveSig:Fire("Manual")
						controller.IsActiveFlag = false
						controller.EndSig:Fire()
						-- Deliberately withhold OnFinalSaveResult until test fires it explicitly!
					end,
				}
				controller.CurrentHandle = handle
				return handle
			end,
		}
		return fakeStore, controller
	end

	-- 11a: In-flight ordinary autosave completing AFTER EndSession must NOT confirm final write early
	local fakeStore11, ctrl11 = createFakeAsyncStore("SR_Fake_11a")
	local uRace = -910055
	assert(DataService.StartProfileSessionForUserId(uRace, nil, { Store = fakeStore11 }), "Suite 11a join")
	local pRace = DataService.GetProfileByUserId(uRace) :: Types.PlayerProfileData
	pRace.Revision = 10

	ctrl11.CurrentHandle:Save()
	DataService.EndSession(uRace)
	assert(not DataService.IsUserFinalSaveConfirmed(uRace), "Final write must NOT be confirmed immediately on EndSession")

	-- Ordinary autosave emits OnAfterSave carrying mutated Revision table; only OnFinalSaveResult may confirm!
	ctrl11.AfterSaveSig:Fire(ctrl11.CurrentHandle.Data)
	assert(not DataService.IsUserFinalSaveConfirmed(uRace), "Ordinary autosave OnAfterSave MUST NOT confirm pending final write")
	assert(not DataService.WaitForUserFinalSave(uRace, 0.05), "WaitForUserFinalSave stays false before OnFinalSaveResult")

	ctrl11.FinalResultSig:Fire(true, "Manual", ctrl11.CurrentHandle.Data)
	assert(DataService.IsUserFinalSaveConfirmed(uRace), "Committed OnFinalSaveResult confirms final write")
	assert(DataService.WaitForUserFinalSave(uRace, 0.2), "WaitForUserFinalSave succeeds after committed OnFinalSaveResult")

	-- 11b: Inactive handle at EndSession (no OnLastSave release path) must fail closed
	local fakeStore11b, ctrl11b = createFakeAsyncStore("SR_Fake_11b")
	local uInactive = -910056
	assert(DataService.StartProfileSessionForUserId(uInactive, nil, { Store = fakeStore11b }), "Suite 11b join")
	ctrl11b.IsActiveFlag = false
	DataService.EndSession(uInactive)
	assert(not DataService.IsUserFinalSaveConfirmed(uInactive), "Inactive handle without release MUST NOT report confirmed")
	assert(not DataService.WaitForUserFinalSave(uInactive, 0.05), "WaitForUserFinalSave returns false when inactive unsaved")

	-- 11c: REAL ProfileStore.Mock newer-owner ownership loss with EQUAL and HIGHER stored revisions must NOT confirm!
	local userMockStoreMap = (ProfileStore :: any).Test().UserMockStore[isolatedStoreName]
	assert(typeof(userMockStoreMap) == "table", "ProfileStore.Test().UserMockStore exposes isolated test store")

	local uLostEqual = -910057
	assert(DataService.StartProfileSessionForUserId(uLostEqual, nil, { Store = testMockStore, NowClock = tFutureGuard }), "Suite 11c equal-rev join")
	local pLostEq = DataService.GetProfileByUserId(uLostEqual) :: Types.PlayerProfileData
	pLostEq.Revision = 20
	pLostEq.Coins = 111
	local mockEntryEq = userMockStoreMap[Constants.PROFILE_KEY_PREFIX .. tostring(uLostEqual)]
	mockEntryEq.Data.MetaData.ActiveSession = { 999999, "OtherServerJob", "other-uid-eq" }
	mockEntryEq.Data.MetaData.SessionLoadCount += 1
	mockEntryEq.Data.Data.Revision = 21 -- Equal to close target!
	mockEntryEq.Data.Data.Coins = 111
	DataService.EndSession(uLostEqual)
	assert(not DataService.WaitForUserFinalSave(uLostEqual, 2), "Ownership loss with EQUAL newer Revision must return false")
	assert(not DataService.IsUserFinalSaveConfirmed(uLostEqual), "Ownership loss with EQUAL newer Revision must stay unconfirmed")

	local uLostHigher = -910060
	assert(DataService.StartProfileSessionForUserId(uLostHigher, nil, { Store = testMockStore, NowClock = tFutureGuard }), "Suite 11c higher-rev join")
	local pLostHigh = DataService.GetProfileByUserId(uLostHigher) :: Types.PlayerProfileData
	pLostHigh.Revision = 20
	pLostHigh.Coins = 222
	local mockEntryHigh = userMockStoreMap[Constants.PROFILE_KEY_PREFIX .. tostring(uLostHigher)]
	mockEntryHigh.Data.MetaData.ActiveSession = { 999999, "OtherServerJob", "other-uid-high" }
	mockEntryHigh.Data.MetaData.SessionLoadCount += 1
	mockEntryHigh.Data.Data.Revision = 500 -- Strictly HIGHER newer owner Revision!
	mockEntryHigh.Data.Data.Coins = 9999
	DataService.EndSession(uLostHigher)
	assert(not DataService.WaitForUserFinalSave(uLostHigher, 2), "Ownership loss with HIGHER newer Revision must return false")
	assert(not DataService.IsUserFinalSaveConfirmed(uLostHigher), "Ownership loss with HIGHER newer Revision must stay unconfirmed")

	-- 11d: REAL ProfileStore.Mock Force-Load path (ordinary Save hits ForceLoadSession -> external release without ordinary OnAfterSave)
	local uForceLoad = -910059
	local forceKickCount = 0
	local forceHookConn = DataService.OnBeforeSave(function(_p: Player?, prof: Types.PlayerProfileData)
		if prof.Revision == 700 and prof.Coins == 100 then
			prof.Coins += 55
		end
	end)
	assert(DataService.StartProfileSessionForUserId(uForceLoad, nil, {
		Store = testMockStore,
		NowClock = tFutureGuard,
		OnKick = function(_msg: string)
			forceKickCount += 1
		end,
	}), "Suite 11d force-load join")
	local pForce = DataService.GetProfileByUserId(uForceLoad) :: Types.PlayerProfileData
	pForce.Revision = 700
	pForce.Coins = 100
	local forceSession = sessions[uForceLoad]
	local forceHandle = if forceSession ~= nil then forceSession.ProfileHandle else nil
	assert(forceHandle ~= nil, "Force-load handle present")

	local mockEntryForce = userMockStoreMap[Constants.PROFILE_KEY_PREFIX .. tostring(uForceLoad)]
	mockEntryForce.Data.MetaData.ForceLoadSession = { 888888, "ForceLoadServerJob" }

	local activeForceHandle = forceHandle :: ProfileHandleLike
	activeForceHandle:Save() -- Triggers async autosave -> ProfileStore lines 854-857 SaveProfileAsync(..., true, false, "External") + break
	local forceDeadline = os.clock() + 2
	while DataService.IsUserIdReady(uForceLoad) and os.clock() < forceDeadline do
		task.wait()
	end
	assert(DataService.WaitForUserFinalSave(uForceLoad, 2), "Force-load release confirms final write via OnFinalSaveResult")
	assert(DataService.IsUserFinalSaveConfirmed(uForceLoad), "Force-load final write marked confirmed")
	assert(not DataService.IsUserIdReady(uForceLoad), "Force-load cleared session readiness")
	assert(forceKickCount == 1, "Force-load triggered clean player kick")
	assert(mockEntryForce.Data.Data.Coins == 155 and mockEntryForce.Data.Data.Revision == 701, "Force-load settled +55 Coins and Revision 701 to store")
	forceHookConn:Disconnect()

	-- 11e: Verify earlier unconfirmed lost-lock sessions NEVER poison subsequent healthy shutdown flushes
	local uHealthyAfter = -910058
	assert(DataService.StartProfileSessionForUserId(uHealthyAfter, nil, { Store = testMockStore, NowClock = tFutureGuard }), "Healthy flush session after lost-lock tests starts")
	assert(DataService.FlushActiveProfileSessions(2), "Healthy shutdown flush must succeed after earlier unconfirmed sessions")

	DataService.ClearTestTrackingForUserIds({
		userA,
		userB,
		userP,
		userTheft,
		userFlush2,
		userHook,
		uRace,
		uInactive,
		uLostEqual,
		uLostHigher,
		uForceLoad,
		uHealthyAfter,
	})
	passed += 1

	return passed
end

return DataService
