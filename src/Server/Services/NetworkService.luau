--!strict
--[[
	Service: NetworkService
	Purpose: Creates ReplicatedStorage.Remotes, validates all inbound client payloads, enforces per-player
	         per-remote token-bucket rate limits, and routes authorized calls to registered server handlers.
	Connections: Initialized first by ServerInit; handlers registered by DataService, EconomyService, PlotService, and MeteorService.
	How to Test in Studio: Press Play (F5) to run NetworkService.RunSelfTest() and inspect ReplicatedStorage.Remotes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Types = require(Shared:WaitForChild("Types"))
local ValidationUtil = require(Shared:WaitForChild("Util"):WaitForChild("ValidationUtil"))

export type RemoteResult = {
	Ok: boolean,
	Reason: string?,
	[string]: any,
}

type RateBucketConfig = {
	Capacity: number,
	RefillPerSecond: number,
}

type PlayerBucket = {
	Tokens: number,
	LastRefill: number,
}

local REMOTE_NAMES = Constants.REMOTE_NAMES

local RATE_LIMIT_CONFIGS: { [string]: RateBucketConfig } = table.freeze({
	[REMOTE_NAMES.RequestInitialSnapshot] = table.freeze({ Capacity = 2, RefillPerSecond = 1 / 3 }),
	[REMOTE_NAMES.RequestStartCrack] = table.freeze({ Capacity = 4, RefillPerSecond = 4 }),
	[REMOTE_NAMES.RequestFinishCrack] = table.freeze({ Capacity = 4, RefillPerSecond = 4 }),
	[REMOTE_NAMES.RequestPlotAction] = table.freeze({ Capacity = 8, RefillPerSecond = 8 }),
	[REMOTE_NAMES.RequestBuyUpgrade] = table.freeze({ Capacity = 3, RefillPerSecond = 3 }),
})

local ACTIONS_REQUIRING_ITEM_UID: { [string]: boolean } = table.freeze({
	StartIncubate = true,
	PlaceInPen = true,
})

local NetworkService = {
	Name = "NetworkService",
}

local remotesFolder: Folder? = nil
local remoteEvents: { [string]: RemoteEvent } = {}
local remoteFunctions: { [string]: RemoteFunction } = {}
local rateBuckets: { [number]: { [string]: PlayerBucket } } = {}

local snapshotHandler: ((player: Player) -> ())? = nil
local plotActionHandler: ((player: Player, action: Types.PlotAction, targetSlotOrUID: string, itemUID: string?) -> ())? = nil
local startCrackHandler: ((player: Player, meteorUID: string) -> RemoteResult)? = nil
local finishCrackHandler: ((player: Player, meteorUID: string, attemptNonce: string) -> RemoteResult)? = nil
local buyUpgradeHandler: ((player: Player, upgradeId: Types.UpgradeId) -> RemoteResult)? = nil
local playerRemovingConn: RBXScriptConnection? = nil

local function ensureRemoteEvent(folder: Folder, name: string): RemoteEvent
	local existing = folder:FindFirstChild(name)
	if existing ~= nil then
		assert(existing:IsA("RemoteEvent"), string.format("Remote '%s' exists but is %s instead of RemoteEvent", name, existing.ClassName))
		return existing
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

local function ensureRemoteFunction(folder: Folder, name: string): RemoteFunction
	local existing = folder:FindFirstChild(name)
	if existing ~= nil then
		assert(existing:IsA("RemoteFunction"), string.format("Remote '%s' exists but is %s instead of RemoteFunction", name, existing.ClassName))
		return existing
	end
	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = folder
	return remote
end

function NetworkService.CheckAndConsumeRateLimit(userId: number, remoteName: string, nowClock: number?): boolean
	local cfg = RATE_LIMIT_CONFIGS[remoteName]
	if cfg == nil then
		return false
	end

	local now = if nowClock ~= nil then nowClock else os.clock()
	local userBuckets = rateBuckets[userId]
	if userBuckets == nil then
		userBuckets = {}
		rateBuckets[userId] = userBuckets
	end

	local bucket = userBuckets[remoteName]
	if bucket == nil then
		bucket = {
			Tokens = cfg.Capacity,
			LastRefill = now,
		}
		userBuckets[remoteName] = bucket
	else
		local elapsed = math.max(0, now - bucket.LastRefill)
		bucket.Tokens = math.min(cfg.Capacity, bucket.Tokens + elapsed * cfg.RefillPerSecond)
		bucket.LastRefill = now
	end

	if bucket.Tokens >= 1 then
		bucket.Tokens -= 1
		return true
	end

	return false
end

function NetworkService.ClearPlayerBuckets(userId: number): ()
	rateBuckets[userId] = nil
end

function NetworkService.ValidateInboundPayload(remoteName: string, ...: unknown): (boolean, string)
	local argc = select("#", ...)
	local arg1, arg2, arg3 = ...

	if remoteName == REMOTE_NAMES.RequestInitialSnapshot then
		if argc ~= 0 then
			return false, "Expected 0 arguments"
		end
		return true, "Ok"
	elseif remoteName == REMOTE_NAMES.RequestStartCrack then
		if argc ~= 1 then
			return false, "Expected 1 argument"
		end
		if not ValidationUtil.IsBoundedString(arg1, Constants.MAX_STRING_ID_LENGTH) then
			return false, "Invalid meteorUID"
		end
		return true, "Ok"
	elseif remoteName == REMOTE_NAMES.RequestFinishCrack then
		if argc ~= 2 then
			return false, "Expected 2 arguments"
		end
		if not ValidationUtil.IsBoundedString(arg1, Constants.MAX_STRING_ID_LENGTH) then
			return false, "Invalid meteorUID"
		end
		if not ValidationUtil.IsBoundedString(arg2, Constants.MAX_STRING_ID_LENGTH) then
			return false, "Invalid attemptNonce"
		end
		return true, "Ok"
	elseif remoteName == REMOTE_NAMES.RequestBuyUpgrade then
		if argc ~= 1 then
			return false, "Expected 1 argument"
		end
		if not ValidationUtil.IsValidUpgradeId(arg1) then
			return false, "Invalid upgradeId"
		end
		return true, "Ok"
	elseif remoteName == REMOTE_NAMES.RequestPlotAction then
		if argc < 2 or argc > 3 then
			return false, "Expected 2 or 3 arguments"
		end
		if not ValidationUtil.IsValidPlotAction(arg1) then
			return false, "Invalid plot action"
		end
		if not ValidationUtil.IsBoundedString(arg2, Constants.MAX_STRING_ID_LENGTH) then
			return false, "Invalid targetSlotOrUID"
		end
		local actionName = arg1 :: string
		if ACTIONS_REQUIRING_ITEM_UID[actionName] then
			if not ValidationUtil.IsBoundedString(arg3, Constants.MAX_STRING_ID_LENGTH) then
				return false, "Action requires bounded itemUID"
			end
		else
			if arg3 ~= nil then
				return false, "Unexpected itemUID for action"
			end
		end
		return true, "Ok"
	end

	return false, "Unknown remote"
end

local function processInvokeRequest(
	userId: number,
	remoteName: string,
	handlerFn: ((...any) -> RemoteResult)?,
	playerArg: Player?,
	...: unknown
): RemoteResult
	-- Always charge the token bucket before validating payload so spam fails cleanly.
	if not NetworkService.CheckAndConsumeRateLimit(userId, remoteName) then
		return { Ok = false, Reason = "RateLimited" }
	end

	local valid, _reason = NetworkService.ValidateInboundPayload(remoteName, ...)
	if not valid then
		return { Ok = false, Reason = "InvalidPayload" }
	end

	if handlerFn == nil or playerArg == nil then
		return { Ok = false, Reason = "ServiceUnavailable" }
	end

	local ok, result = pcall(handlerFn, playerArg, ...)
	if not ok then
		warn(string.format("[NetworkService] Handler error in %s: %s", remoteName, tostring(result)))
		return { Ok = false, Reason = "InternalError" }
	end

	return result
end

function NetworkService.Init(self: typeof(NetworkService)): ()
	local existing = ReplicatedStorage:FindFirstChild(Constants.REMOTES_FOLDER_NAME)
	local folder: Folder
	if existing ~= nil then
		assert(existing:IsA("Folder"), "ReplicatedStorage.Remotes must be a Folder")
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = Constants.REMOTES_FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	remotesFolder = folder

	-- Outbound events (Server -> Client)
	for _, name in ipairs({
		REMOTE_NAMES.SyncOwnerState,
		REMOTE_NAMES.SyncPublicPlots,
		REMOTE_NAMES.MeteorLifecycle,
	}) do
		remoteEvents[name] = ensureRemoteEvent(folder, name)
	end

	-- Inbound events (Client -> Server)
	for _, name in ipairs({
		REMOTE_NAMES.RequestInitialSnapshot,
		REMOTE_NAMES.RequestPlotAction,
	}) do
		remoteEvents[name] = ensureRemoteEvent(folder, name)
	end

	-- Inbound functions (Client -> Server)
	for _, name in ipairs({
		REMOTE_NAMES.RequestStartCrack,
		REMOTE_NAMES.RequestFinishCrack,
		REMOTE_NAMES.RequestBuyUpgrade,
	}) do
		remoteFunctions[name] = ensureRemoteFunction(folder, name)
	end
end

function NetworkService.Start(self: typeof(NetworkService)): ()
	if playerRemovingConn == nil then
		playerRemovingConn = Players.PlayerRemoving:Connect(function(player: Player)
			NetworkService.ClearPlayerBuckets(player.UserId)
		end)
	end

	remoteEvents[REMOTE_NAMES.RequestInitialSnapshot].OnServerEvent:Connect(function(player: Player, ...: any)
		if not NetworkService.CheckAndConsumeRateLimit(player.UserId, REMOTE_NAMES.RequestInitialSnapshot) then
			return
		end
		local valid = NetworkService.ValidateInboundPayload(REMOTE_NAMES.RequestInitialSnapshot, ...)
		if not valid or snapshotHandler == nil then
			return
		end
		local ok, err = pcall(snapshotHandler, player)
		if not ok then
			warn("[NetworkService] RequestInitialSnapshot error: " .. tostring(err))
		end
	end)

	remoteEvents[REMOTE_NAMES.RequestPlotAction].OnServerEvent:Connect(function(player: Player, ...: any)
		if not NetworkService.CheckAndConsumeRateLimit(player.UserId, REMOTE_NAMES.RequestPlotAction) then
			return
		end
		local valid = NetworkService.ValidateInboundPayload(REMOTE_NAMES.RequestPlotAction, ...)
		if not valid or plotActionHandler == nil then
			return
		end
		local action, targetSlotOrUID, itemUID = ...
		local ok, err = pcall(
			plotActionHandler,
			player,
			action :: Types.PlotAction,
			targetSlotOrUID :: string,
			itemUID :: string?
		)
		if not ok then
			warn("[NetworkService] RequestPlotAction error: " .. tostring(err))
		end
	end)

	remoteFunctions[REMOTE_NAMES.RequestStartCrack].OnServerInvoke = function(player: Player, ...: any): RemoteResult
		return processInvokeRequest(player.UserId, REMOTE_NAMES.RequestStartCrack, startCrackHandler :: any, player, ...)
	end

	remoteFunctions[REMOTE_NAMES.RequestFinishCrack].OnServerInvoke = function(player: Player, ...: any): RemoteResult
		return processInvokeRequest(player.UserId, REMOTE_NAMES.RequestFinishCrack, finishCrackHandler :: any, player, ...)
	end

	remoteFunctions[REMOTE_NAMES.RequestBuyUpgrade].OnServerInvoke = function(player: Player, ...: any): RemoteResult
		return processInvokeRequest(player.UserId, REMOTE_NAMES.RequestBuyUpgrade, buyUpgradeHandler :: any, player, ...)
	end
end

function NetworkService.BindSnapshotHandler(handler: (player: Player) -> ()): ()
	assert(snapshotHandler == nil, "Snapshot handler already registered")
	snapshotHandler = handler
end

function NetworkService.BindPlotActionHandler(
	handler: (player: Player, action: Types.PlotAction, targetSlotOrUID: string, itemUID: string?) -> ()
): ()
	assert(plotActionHandler == nil, "PlotAction handler already registered")
	plotActionHandler = handler
end

function NetworkService.BindStartCrackHandler(handler: (player: Player, meteorUID: string) -> RemoteResult): ()
	assert(startCrackHandler == nil, "StartCrack handler already registered")
	startCrackHandler = handler
end

function NetworkService.BindFinishCrackHandler(
	handler: (player: Player, meteorUID: string, attemptNonce: string) -> RemoteResult
): ()
	assert(finishCrackHandler == nil, "FinishCrack handler already registered")
	finishCrackHandler = handler
end

function NetworkService.BindBuyUpgradeHandler(handler: (player: Player, upgradeId: Types.UpgradeId) -> RemoteResult): ()
	assert(buyUpgradeHandler == nil, "BuyUpgrade handler already registered")
	buyUpgradeHandler = handler
end

function NetworkService.SendOwnerState(player: Player, dto: Types.OwnerStateDTO): ()
	local remote = remoteEvents[REMOTE_NAMES.SyncOwnerState]
	if remote then
		remote:FireClient(player, dto)
	end
end

function NetworkService.BroadcastPublicPlots(plots: { Types.PublicPlotDTO }, revision: number): ()
	local remote = remoteEvents[REMOTE_NAMES.SyncPublicPlots]
	if remote then
		remote:FireAllClients(plots, revision)
	end
end

function NetworkService.SendPublicPlotsToPlayer(player: Player, plots: { Types.PublicPlotDTO }, revision: number): ()
	local remote = remoteEvents[REMOTE_NAMES.SyncPublicPlots]
	if remote then
		remote:FireClient(player, plots, revision)
	end
end

function NetworkService.BroadcastMeteorLifecycle(payload: { [string]: any }): ()
	local remote = remoteEvents[REMOTE_NAMES.MeteorLifecycle]
	if remote then
		remote:FireAllClients(payload)
	end
end

function NetworkService.SendMeteorLifecycleToPlayer(player: Player, payload: { [string]: any }): ()
	local remote = remoteEvents[REMOTE_NAMES.MeteorLifecycle]
	if remote then
		remote:FireClient(player, payload)
	end
end

function NetworkService.GetRemotesFolder(): Folder
	assert(remotesFolder ~= nil, "NetworkService.Init() must run before GetRemotesFolder()")
	return remotesFolder :: Folder
end

function NetworkService.RunSelfTest(): number
	local passed = 0

	-- 1. Verify all 8 remote instances exist with exact classes
	local folder = NetworkService.GetRemotesFolder()
	for _, evName in ipairs({
		REMOTE_NAMES.SyncOwnerState,
		REMOTE_NAMES.SyncPublicPlots,
		REMOTE_NAMES.MeteorLifecycle,
		REMOTE_NAMES.RequestInitialSnapshot,
		REMOTE_NAMES.RequestPlotAction,
	}) do
		local inst = folder:FindFirstChild(evName)
		assert(inst ~= nil and inst:IsA("RemoteEvent"), "Missing RemoteEvent: " .. evName)
	end
	for _, fnName in ipairs({
		REMOTE_NAMES.RequestStartCrack,
		REMOTE_NAMES.RequestFinishCrack,
		REMOTE_NAMES.RequestBuyUpgrade,
	}) do
		local inst = folder:FindFirstChild(fnName)
		assert(inst ~= nil and inst:IsA("RemoteFunction"), "Missing RemoteFunction: " .. fnName)
	end
	passed += 1

	-- 2. Verify strict inbound payload validation across valid & hostile shapes
	assert(NetworkService.ValidateInboundPayload(REMOTE_NAMES.RequestInitialSnapshot), "0-arg snapshot valid")
	assert(not NetworkService.ValidateInboundPayload(REMOTE_NAMES.RequestInitialSnapshot, "extra"), "Extra snapshot arg rejected")

	assert(NetworkService.ValidateInboundPayload(REMOTE_NAMES.RequestStartCrack, "meteor-1"), "Valid meteorUID accepted")
	assert(not NetworkService.ValidateInboundPayload(REMOTE_NAMES.RequestStartCrack, 0 / 0), "NaN meteorUID rejected")
	assert(not NetworkService.ValidateInboundPayload(REMOTE_NAMES.RequestStartCrack, string.rep("x", 41)), "Oversized meteorUID rejected")

	assert(NetworkService.ValidateInboundPayload(REMOTE_NAMES.RequestFinishCrack, "meteor-1", "nonce-123"), "Valid finish args accepted")
	assert(not NetworkService.ValidateInboundPayload(REMOTE_NAMES.RequestFinishCrack, "meteor-1", "nonce-123", 0.5), "Extra ClientDelta arg rejected")

	assert(NetworkService.ValidateInboundPayload(REMOTE_NAMES.RequestBuyUpgrade, "PenSlot_2"), "Valid upgradeId accepted")
	assert(not NetworkService.ValidateInboundPayload(REMOTE_NAMES.RequestBuyUpgrade, "Rebirth_1"), "Unknown upgradeId rejected")

	assert(NetworkService.ValidateInboundPayload(REMOTE_NAMES.RequestPlotAction, "StartIncubate", "Incubator_1", "item-uid-1"), "StartIncubate valid")
	assert(not NetworkService.ValidateInboundPayload(REMOTE_NAMES.RequestPlotAction, "StartIncubate", "Incubator_1"), "StartIncubate missing itemUID rejected")
	assert(NetworkService.ValidateInboundPayload(REMOTE_NAMES.RequestPlotAction, "Hatch", "Incubator_1"), "Hatch valid")
	assert(not NetworkService.ValidateInboundPayload(REMOTE_NAMES.RequestPlotAction, "Hatch", "Incubator_1", "extra-uid"), "Hatch extra itemUID rejected")
	assert(not NetworkService.ValidateInboundPayload(REMOTE_NAMES.RequestPlotAction, "GiftItem", "Slot_1", "uid"), "Removed GiftItem action rejected")
	passed += 1

	-- 3. Verify token-bucket rate limiting charges invalid calls, refills on time, and cleans up
	local testUserId = -999001
	NetworkService.ClearPlayerBuckets(testUserId)
	local t0 = 100.0
	for i = 1, 3 do
		assert(NetworkService.CheckAndConsumeRateLimit(testUserId, REMOTE_NAMES.RequestBuyUpgrade, t0), "Burst token " .. tostring(i))
	end
	assert(not NetworkService.CheckAndConsumeRateLimit(testUserId, REMOTE_NAMES.RequestBuyUpgrade, t0), "4th call in same instant must rate-limit")
	assert(NetworkService.CheckAndConsumeRateLimit(testUserId, REMOTE_NAMES.RequestBuyUpgrade, t0 + 1.0), "Token must refill after 1s")

	-- Also verify invalid payload through processInvokeRequest consumes token and safely rejects
	NetworkService.ClearPlayerBuckets(testUserId)
	for _ = 1, 3 do
		local badRes = processInvokeRequest(testUserId, REMOTE_NAMES.RequestBuyUpgrade, nil, nil, "BadUpgrade")
		assert(not badRes.Ok and badRes.Reason == "InvalidPayload", "Bad payload must return InvalidPayload")
	end
	local throttledRes = processInvokeRequest(testUserId, REMOTE_NAMES.RequestBuyUpgrade, nil, nil, "PenSlot_2")
	assert(not throttledRes.Ok and throttledRes.Reason == "RateLimited", "Prior bad requests must drain bucket")

	NetworkService.ClearPlayerBuckets(testUserId)
	local unavailableRes = processInvokeRequest(testUserId, REMOTE_NAMES.RequestBuyUpgrade, nil, nil, "PenSlot_2")
	assert(not unavailableRes.Ok and unavailableRes.Reason == "ServiceUnavailable", "Unbound handler returns ServiceUnavailable")
	NetworkService.ClearPlayerBuckets(testUserId)
	passed += 1

	return passed
end

return NetworkService
