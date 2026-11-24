--!strict
--[[
	Service: AnalyticsService (S5-01)
	Purpose: Server-authoritative anonymous AnalyticsService instrumentation for the 6-step
	         onboarding funnel (Spawn -> FirstMeteor -> FirstHatch -> FirstPen -> FirstUpgrade -> SecondRescue)
	         with persisted cross-reconnect deduplication, plus Coin economy source/sink logging
	         with batched PenAccrual reporting and zero PII.
	Connections: Requires Constants, Types, DataService; called by PlotService, MeteorService,
	             EconomyService, and initialized/started by ServerInit.
	How to Test in Studio: Press Play (F5) and inspect [StarfallRanch][SelfTest] PASS: All 4 AnalyticsService test suites passed
	                       and inspect AnalyticsService.GetRecentStudioEvents().
]]

local RobloxAnalyticsService = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Types = require(Shared:WaitForChild("Types"))

local ServicesFolder = script.Parent
local DataService = require(ServicesFolder:WaitForChild("DataService"))

export type TelemetryEventRecord = {
	Kind: "OnboardingFunnel" | "Economy",
	UserId: number,
	Step: number?,
	StepName: Types.OnboardingFunnelStep?,
	FlowType: Enum.AnalyticsEconomyFlowType?,
	CurrencyType: string?,
	Amount: number?,
	EndingBalance: number?,
	TransactionType: string?,
	ItemSku: string?,
}

type PendingAccrualEntry = {
	Amount: number,
	FirstBufferedAt: number,
	LastEndingBalance: number,
}

local CURRENCY_COINS = "Coins"
local ACCRUAL_FLUSH_MIN_COINS = 25
local ACCRUAL_FLUSH_INTERVAL_SECONDS = 30
local MAX_STUDIO_RECENT_EVENTS = 64

local FUNNEL_STEP_NUMBERS: { [Types.OnboardingFunnelStep]: number } = table.freeze({
	Spawn = 1,
	FirstMeteor = 2,
	FirstHatch = 3,
	FirstPen = 4,
	FirstUpgrade = 5,
	SecondRescue = 6,
})

local AnalyticsService = {
	Name = "AnalyticsService",
}

local pendingAccrualByUserId: { [number]: PendingAccrualEntry } = {}
local recentStudioEvents: { TelemetryEventRecord } = {}
local testEventSink: ((event: TelemetryEventRecord) -> ())? = nil
local closingHookRegistered = false

local function isFiniteNonNegative(value: unknown): boolean
	return typeof(value) == "number" and value == value and math.abs(value) ~= math.huge and value >= 0
end

local function isFinitePositive(value: unknown): boolean
	return typeof(value) == "number" and value == value and math.abs(value) ~= math.huge and value > 0
end

local function isRealLivePlayer(player: Player?): boolean
	return player ~= nil and typeof(player) == "Instance" and player:IsA("Player") and player.UserId > 0
end

local function recordStudioEvent(event: TelemetryEventRecord): ()
	table.insert(recentStudioEvents, event)
	if #recentStudioEvents > MAX_STUDIO_RECENT_EVENTS then
		table.remove(recentStudioEvents, 1)
	end
	if testEventSink ~= nil then
		testEventSink(event)
	end
end

local function emitOnboardingStep(
	player: Player?,
	userId: number,
	profile: Types.PlayerProfileData,
	stepName: Types.OnboardingFunnelStep
): boolean
	if profile.OnboardingFunnelSteps == nil then
		profile.OnboardingFunnelSteps = {}
	end
	if profile.OnboardingFunnelSteps[stepName] == true then
		return false
	end

	local stepNum = FUNNEL_STEP_NUMBERS[stepName]
	if stepNum == nil then
		return false
	end

	profile.OnboardingFunnelSteps[stepName] = true

	if isRealLivePlayer(player) then
		local ok, err = pcall(function()
			RobloxAnalyticsService:LogOnboardingFunnelStepEvent(player :: Player, stepNum, stepName)
		end)
		if not ok then
			warn(string.format("[AnalyticsService] LogOnboardingFunnelStepEvent(%s) failed: %s", stepName, tostring(err)))
		end
	end

	recordStudioEvent({
		Kind = "OnboardingFunnel",
		UserId = userId,
		Step = stepNum,
		StepName = stepName,
	})
	return true
end

local function emitEconomyEvent(
	player: Player?,
	userId: number,
	flowType: Enum.AnalyticsEconomyFlowType,
	amount: number,
	endingBalance: number,
	transactionType: string,
	itemSku: string
): boolean
	if not isFinitePositive(amount) or not isFiniteNonNegative(endingBalance) then
		return false
	end
	if typeof(transactionType) ~= "string" or #transactionType == 0 or typeof(itemSku) ~= "string" or #itemSku == 0 then
		return false
	end

	local cleanAmount = math.floor(amount)
	if cleanAmount <= 0 then
		return false
	end
	local cleanEnding = math.clamp(math.floor(endingBalance), 0, Constants.MAX_COINS)

	if isRealLivePlayer(player) then
		local ok, err = pcall(function()
			RobloxAnalyticsService:LogEconomyEvent(
				player :: Player,
				flowType,
				CURRENCY_COINS,
				cleanAmount,
				cleanEnding,
				transactionType,
				itemSku
			)
		end)
		if not ok then
			warn(string.format("[AnalyticsService] LogEconomyEvent(%s/%s) failed: %s", flowType.Name, itemSku, tostring(err)))
		end
	end

	recordStudioEvent({
		Kind = "Economy",
		UserId = userId,
		FlowType = flowType,
		CurrencyType = CURRENCY_COINS,
		Amount = cleanAmount,
		EndingBalance = cleanEnding,
		TransactionType = transactionType,
		ItemSku = itemSku,
	})
	return true
end

function AnalyticsService.RecordSpawn(player: Player?, userId: number, profile: Types.PlayerProfileData): boolean
	return emitOnboardingStep(player, userId, profile, "Spawn")
end

function AnalyticsService.RecordMeteorRescue(
	player: Player?,
	userId: number,
	profile: Types.PlayerProfileData,
	_isStarter: boolean,
	_trait: Types.MeteorTraitId,
	_speciesId: Types.SpeciesId
): (boolean, Types.OnboardingFunnelStep?)
	if profile.OnboardingFunnelSteps == nil then
		profile.OnboardingFunnelSteps = {}
	end
	if profile.OnboardingFunnelSteps["FirstMeteor"] ~= true then
		local recorded = emitOnboardingStep(player, userId, profile, "FirstMeteor")
		return recorded, if recorded then "FirstMeteor" else nil
	end
	if profile.OnboardingFunnelSteps["SecondRescue"] ~= true then
		local recorded = emitOnboardingStep(player, userId, profile, "SecondRescue")
		return recorded, if recorded then "SecondRescue" else nil
	end
	return false, nil
end

function AnalyticsService.RecordFirstHatch(
	player: Player?,
	userId: number,
	profile: Types.PlayerProfileData,
	_speciesId: Types.SpeciesId?
): boolean
	return emitOnboardingStep(player, userId, profile, "FirstHatch")
end

function AnalyticsService.RecordFirstPen(
	player: Player?,
	userId: number,
	profile: Types.PlayerProfileData,
	_slotId: string?
): boolean
	return emitOnboardingStep(player, userId, profile, "FirstPen")
end

function AnalyticsService.RecordFirstUpgrade(
	player: Player?,
	userId: number,
	profile: Types.PlayerProfileData,
	_upgradeId: Types.UpgradeId?
): boolean
	return emitOnboardingStep(player, userId, profile, "FirstUpgrade")
end

function AnalyticsService.FlushPendingAccrual(player: Player?, userId: number, endingBalance: number?): boolean
	local pending = pendingAccrualByUserId[userId]
	if pending == nil or pending.Amount <= 0 then
		pendingAccrualByUserId[userId] = nil
		return false
	end

	local amountToFlush = pending.Amount
	local finalBalance = if isFiniteNonNegative(endingBalance)
		then endingBalance :: number
		else pending.LastEndingBalance
	pendingAccrualByUserId[userId] = nil

	return emitEconomyEvent(
		player,
		userId,
		Enum.AnalyticsEconomyFlowType.Source,
		amountToFlush,
		finalBalance,
		Enum.AnalyticsEconomyTransactionType.Gameplay.Name,
		"PenAccrual"
	)
end

function AnalyticsService.RecordPenAccrual(
	player: Player?,
	userId: number,
	earnedCoins: number,
	endingBalance: number,
	nowClock: number?
): boolean
	if not isFinitePositive(earnedCoins) or not isFiniteNonNegative(endingBalance) then
		return false
	end

	local cleanEarned = math.floor(earnedCoins)
	if cleanEarned <= 0 then
		return false
	end
	local cleanBalance = math.clamp(math.floor(endingBalance), 0, Constants.MAX_COINS)
	local clockVal = if nowClock ~= nil and isFiniteNonNegative(nowClock) then nowClock else os.clock()

	local entry = pendingAccrualByUserId[userId]
	if entry == nil then
		entry = {
			Amount = cleanEarned,
			FirstBufferedAt = clockVal,
			LastEndingBalance = cleanBalance,
		}
		pendingAccrualByUserId[userId] = entry
	else
		entry.Amount += cleanEarned
		entry.LastEndingBalance = cleanBalance
	end

	if entry.Amount >= ACCRUAL_FLUSH_MIN_COINS or (clockVal - entry.FirstBufferedAt) >= ACCRUAL_FLUSH_INTERVAL_SECONDS then
		return AnalyticsService.FlushPendingAccrual(player, userId, cleanBalance)
	end
	return false
end

function AnalyticsService.RecordCoinSource(
	player: Player?,
	userId: number,
	amount: number,
	endingBalance: number,
	transactionType: string,
	itemSku: string
): boolean
	if not isFinitePositive(amount) or not isFiniteNonNegative(endingBalance) then
		return false
	end
	local cleanAmount = math.floor(amount)
	if cleanAmount <= 0 then
		return false
	end
	local cleanEnding = math.clamp(math.floor(endingBalance), 0, Constants.MAX_COINS)

	-- Flush any buffered passive accrual at the pre-transaction balance so ledger balances stay monotonic.
	if pendingAccrualByUserId[userId] ~= nil then
		AnalyticsService.FlushPendingAccrual(player, userId, math.max(0, cleanEnding - cleanAmount))
	end

	return emitEconomyEvent(
		player,
		userId,
		Enum.AnalyticsEconomyFlowType.Source,
		cleanAmount,
		cleanEnding,
		transactionType,
		itemSku
	)
end

function AnalyticsService.RecordCoinSink(
	player: Player?,
	userId: number,
	amount: number,
	endingBalance: number,
	transactionType: string,
	itemSku: string
): boolean
	if not isFinitePositive(amount) or not isFiniteNonNegative(endingBalance) then
		return false
	end
	local cleanAmount = math.floor(amount)
	if cleanAmount <= 0 then
		return false
	end
	local cleanEnding = math.clamp(math.floor(endingBalance), 0, Constants.MAX_COINS)

	-- Flush any buffered passive accrual at the pre-spend balance before logging the sink.
	if pendingAccrualByUserId[userId] ~= nil then
		AnalyticsService.FlushPendingAccrual(player, userId, math.min(Constants.MAX_COINS, cleanEnding + cleanAmount))
	end

	return emitEconomyEvent(
		player,
		userId,
		Enum.AnalyticsEconomyFlowType.Sink,
		cleanAmount,
		cleanEnding,
		transactionType,
		itemSku
	)
end

function AnalyticsService.HandlePlayerClosing(player: Player): ()
	local userId = player.UserId
	local profile = DataService.GetProfileByUserId(userId)
	local fallbackBalance = if profile ~= nil then profile.Coins else nil
	AnalyticsService.FlushPendingAccrual(player, userId, fallbackBalance)
	pendingAccrualByUserId[userId] = nil
end

function AnalyticsService.ClearTrackingForUserId(userId: number): ()
	pendingAccrualByUserId[userId] = nil
end

function AnalyticsService.SetEventSinkForTest(sink: ((event: TelemetryEventRecord) -> ())?): ()
	testEventSink = sink
end

function AnalyticsService.GetRecentStudioEvents(): { TelemetryEventRecord }
	local copy: { TelemetryEventRecord } = {}
	for _, ev in ipairs(recentStudioEvents) do
		table.insert(copy, table.clone(ev))
	end
	return copy
end

function AnalyticsService.Init(self: typeof(AnalyticsService)): ()
	if closingHookRegistered then
		return
	end
	closingHookRegistered = true
	DataService.OnPlayerClosing(function(player: Player)
		AnalyticsService.HandlePlayerClosing(player)
	end)
end

function AnalyticsService.Start(self: typeof(AnalyticsService)): ()
	-- Lifecycle hooks are registered in Init and invoked directly by PlotService, MeteorService, and EconomyService.
end

function AnalyticsService.RunSelfTest(): number
	local passed = 0
	local captured: { TelemetryEventRecord } = {}
	local prevSink = testEventSink

	local function resetCapture()
		captured = {}
	end

	local ok, err = pcall(function()
		AnalyticsService.SetEventSinkForTest(function(ev: TelemetryEventRecord)
			table.insert(captured, ev)
		end)

		-- 1. Sequential 6-step onboarding funnel + zero duplicates on retries/repeats
		local uFunnel = -920001
		local pFunnel = DataService.CreateDefaultProfile(1000)
		resetCapture()

		assert(AnalyticsService.RecordSpawn(nil, uFunnel, pFunnel), "Step 1 Spawn recorded")
		assert(not AnalyticsService.RecordSpawn(nil, uFunnel, pFunnel), "Duplicate Spawn ignored")

		local m1Ok, m1Step = AnalyticsService.RecordMeteorRescue(nil, uFunnel, pFunnel, true, "Ember", "StarSlime")
		assert(m1Ok and m1Step == "FirstMeteor", "Step 2 FirstMeteor recorded")

		assert(AnalyticsService.RecordFirstHatch(nil, uFunnel, pFunnel, "StarSlime"), "Step 3 FirstHatch recorded")
		assert(not AnalyticsService.RecordFirstHatch(nil, uFunnel, pFunnel, "StarSlime"), "Duplicate FirstHatch ignored")

		assert(AnalyticsService.RecordFirstPen(nil, uFunnel, pFunnel, "Pen_1"), "Step 4 FirstPen recorded")
		assert(not AnalyticsService.RecordFirstPen(nil, uFunnel, pFunnel, "Pen_2"), "Duplicate FirstPen ignored")

		assert(AnalyticsService.RecordFirstUpgrade(nil, uFunnel, pFunnel, "PenSlot_2"), "Step 5 FirstUpgrade recorded")
		assert(not AnalyticsService.RecordFirstUpgrade(nil, uFunnel, pFunnel, "FrostCracker"), "Duplicate FirstUpgrade ignored")

		local m2Ok, m2Step = AnalyticsService.RecordMeteorRescue(nil, uFunnel, pFunnel, false, "Ember", "CinderPup")
		assert(m2Ok and m2Step == "SecondRescue", "Step 6 SecondRescue recorded")

		local m3Ok, m3Step = AnalyticsService.RecordMeteorRescue(nil, uFunnel, pFunnel, false, "Frost", "FrostBeetle")
		assert(not m3Ok and m3Step == nil, "3rd rescue emits zero funnel events")

		local expectedSteps = {
			{ Step = 1, Name = "Spawn" },
			{ Step = 2, Name = "FirstMeteor" },
			{ Step = 3, Name = "FirstHatch" },
			{ Step = 4, Name = "FirstPen" },
			{ Step = 5, Name = "FirstUpgrade" },
			{ Step = 6, Name = "SecondRescue" },
		}
		assert(#captured == #expectedSteps, "Exactly 6 onboarding events emitted")
		for idx, exp in ipairs(expectedSteps) do
			local ev = captured[idx]
			assert(ev.Kind == "OnboardingFunnel" and ev.Step == exp.Step and ev.StepName == exp.Name, "Ordered funnel step " .. exp.Name)
		end
		passed += 1

		-- 2. Economy Sources & Sinks (PenAccrual batching, pre-spend flush, Sell, Upgrade, Feed, Lure, cleanup)
		local uEcon = -920002
		AnalyticsService.ClearTrackingForUserId(uEcon)
		resetCapture()

		-- Buffered below 25 Coins & < 30s does not flush immediately
		assert(not AnalyticsService.RecordPenAccrual(nil, uEcon, 10, 10, 100), "10 Coins buffered below threshold")
		assert(#captured == 0, "Zero events before accrual threshold/interval")

		-- Reaching >= 25 Coins flushes one PenAccrual Source
		assert(AnalyticsService.RecordPenAccrual(nil, uEcon, 15, 25, 105), "25 Coins triggers batch flush")
		assert(#captured == 1 and captured[1].ItemSku == "PenAccrual" and captured[1].Amount == 25 and captured[1].EndingBalance == 25, "PenAccrual batch flush verified")

		-- Interval >= 30s flushes smaller accrual
		assert(not AnalyticsService.RecordPenAccrual(nil, uEcon, 4, 29, 200), "4 Coins buffered at t=200")
		assert(AnalyticsService.RecordPenAccrual(nil, uEcon, 4, 33, 230), "Interval >= 30s flushes 8 Coins")
		assert(#captured == 2 and captured[2].Amount == 8 and captured[2].EndingBalance == 33, "Interval accrual flush verified")

		-- Pre-spend flush ordering: buffer 6 Coins (33 -> 39), then spend 20 (39 -> 19)
		assert(not AnalyticsService.RecordPenAccrual(nil, uEcon, 6, 39, 300), "Buffer 6 Coins before spend")
		assert(AnalyticsService.RecordCoinSink(nil, uEcon, 20, 19, Enum.AnalyticsEconomyTransactionType.Shop.Name, "Upgrade_PenSlot_2"), "Upgrade sink succeeds")
		assert(#captured == 4, "Pre-spend flush + sink emitted 2 events")
		assert(captured[3].ItemSku == "PenAccrual" and captured[3].Amount == 6 and captured[3].EndingBalance == 39, "Pre-spend flush reports 39 balance")
		assert(
			captured[4].FlowType == Enum.AnalyticsEconomyFlowType.Sink
				and captured[4].TransactionType == Enum.AnalyticsEconomyTransactionType.Shop.Name
				and captured[4].ItemSku == "Upgrade_PenSlot_2"
				and captured[4].Amount == 20
				and captured[4].EndingBalance == 19,
			"Upgrade sink reports 19 ending balance"
		)

		-- Sell Source, Feed Sink, Lure Sink, and explicit disconnect flush
		assert(AnalyticsService.RecordCoinSource(nil, uEcon, 40, 59, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "Sell_StarSlime"), "Sell source logged")
		assert(AnalyticsService.RecordCoinSink(nil, uEcon, 45, 14, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "Feed_NebulaFox"), "Feed sink logged")
		assert(AnalyticsService.RecordCoinSink(nil, uEcon, 75, 0, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "Lure_Frost"), "Lure sink logged")
		assert(not AnalyticsService.RecordPenAccrual(nil, uEcon, 5, 5, 400), "Buffer 5 Coins before disconnect")
		assert(AnalyticsService.FlushPendingAccrual(nil, uEcon, 5), "Disconnect flush emits remaining 5 Coins")
		AnalyticsService.ClearTrackingForUserId(uEcon)
		assert(pendingAccrualByUserId[uEcon] == nil, "ClearTrackingForUserId removes pending entry without leaking")
		passed += 1

		-- 3. ProfileStore.Mock reconnect deduplication
		local mockStore = DataService.CreateIsolatedMockStoreForTest("S501Funnel")
		local uReconn = -920003
		resetCapture()

		assert(DataService.StartProfileSessionForUserId(uReconn, nil, { Store = mockStore, NowClock = 1000 }), "Join 1")
		local pRec1 = DataService.GetProfileByUserId(uReconn) :: Types.PlayerProfileData
		assert(AnalyticsService.RecordSpawn(nil, uReconn, pRec1), "Join 1 records Spawn")
		local recM1, recM1Name = AnalyticsService.RecordMeteorRescue(nil, uReconn, pRec1, true, "Ember", "StarSlime")
		assert(recM1 and recM1Name == "FirstMeteor", "Join 1 records FirstMeteor")
		DataService.EndSession(uReconn)
		assert(DataService.WaitForUserFinalSave(uReconn, 2), "Save join 1")
		DataService.ClearTestTrackingForUserIds({ uReconn })

		resetCapture()
		assert(DataService.StartProfileSessionForUserId(uReconn, nil, { Store = mockStore, NowClock = 1020 }), "Join 2 (reconnect)")
		local pRec2 = DataService.GetProfileByUserId(uReconn) :: Types.PlayerProfileData
		assert(not AnalyticsService.RecordSpawn(nil, uReconn, pRec2), "Reconnect skips duplicate Spawn")
		local recM2, recM2Name = AnalyticsService.RecordMeteorRescue(nil, uReconn, pRec2, false, "Ember", "CinderPup")
		assert(recM2 and recM2Name == "SecondRescue", "Reconnect records SecondRescue once")
		assert(#captured == 1 and captured[1].StepName == "SecondRescue", "Only SecondRescue fired on reconnect")
		DataService.EndSession(uReconn)
		assert(DataService.WaitForUserFinalSave(uReconn, 2), "Save join 2")
		DataService.ClearTestTrackingForUserIds({ uReconn })

		resetCapture()
		assert(DataService.StartProfileSessionForUserId(uReconn, nil, { Store = mockStore, NowClock = 1040 }), "Join 3")
		local pRec3 = DataService.GetProfileByUserId(uReconn) :: Types.PlayerProfileData
		assert(not AnalyticsService.RecordSpawn(nil, uReconn, pRec3), "Join 3 skips Spawn")
		local recM3 = AnalyticsService.RecordMeteorRescue(nil, uReconn, pRec3, false, "Frost", "FrostBeetle")
		assert(not recM3 and #captured == 0, "Join 3 3rd rescue emits 0 funnel events")
		DataService.EndSession(uReconn)
		assert(DataService.WaitForUserFinalSave(uReconn, 2), "Cleanup join 3")
		DataService.ClearTestTrackingForUserIds({ uReconn })
		AnalyticsService.ClearTrackingForUserId(uReconn)
		passed += 1

		-- 4. Invalid/zero/negative/NaN guards & nil-player safety
		local uGuard = -920004
		resetCapture()
		assert(not AnalyticsService.RecordPenAccrual(nil, uGuard, 0, 10, 500), "Zero accrual rejected")
		assert(not AnalyticsService.RecordPenAccrual(nil, uGuard, -5, 10, 500), "Negative accrual rejected")
		assert(not AnalyticsService.RecordPenAccrual(nil, uGuard, 0 / 0, 10, 500), "NaN accrual rejected")
		assert(not AnalyticsService.RecordCoinSource(nil, uGuard, 0, 10, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "Sell_StarSlime"), "Zero source rejected")
		assert(not AnalyticsService.RecordCoinSink(nil, uGuard, -10, 10, Enum.AnalyticsEconomyTransactionType.Shop.Name, "Upgrade_PenSlot_2"), "Negative sink rejected")
		assert(not AnalyticsService.RecordCoinSink(nil, uGuard, 10, -1, Enum.AnalyticsEconomyTransactionType.Shop.Name, "Upgrade_PenSlot_2"), "Negative endingBalance rejected")
		assert(not AnalyticsService.RecordCoinSource(nil, uGuard, 10, 20, "", "Sell_StarSlime"), "Empty transactionType rejected")
		assert(#captured == 0, "Invalid inputs emit zero telemetry events")
		AnalyticsService.ClearTrackingForUserId(uGuard)
		passed += 1
	end)

	AnalyticsService.SetEventSinkForTest(prevSink)
	if not ok then
		error(err)
	end

	return passed
end

return AnalyticsService
