--!strict
--[[
	Service: AnalyticsService (S5-01)
	Purpose: Server-authoritative anonymous AnalyticsService instrumentation for the 6-step
	         onboarding funnel (Spawn -> FirstMeteor -> FirstHatch -> FirstPen -> FirstUpgrade -> SecondRescue)
	         using contiguous-prefix flushing, Fresh vs. Legacy cohort separation, and retryable
	         platform submission tracking, plus Coin economy source/sink logging with batched PenAccrual.
	Connections: Requires Constants, Types, DataService; called by PlotService, MeteorService,
	             EconomyService, and initialized/started by ServerInit.
	How to Test in Studio: Press Play (F5) and inspect [StarfallRanch][SelfTest] PASS: All 6 AnalyticsService test suites passed
	                       and run the private published-server smoke check on PlaceId 106917003014718.
]]

local RobloxAnalyticsService = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Types = require(Shared:WaitForChild("Types"))

local ServicesFolder = script.Parent
local DataService = require(ServicesFolder:WaitForChild("DataService"))

export type DeliveryMode = "PlatformSubmitted" | "StudioCapture" | "PlatformFailed"

export type TelemetryEventRecord = {
	Kind: "OnboardingFunnel" | "Economy",
	DeliveryMode: DeliveryMode,
	UserId: number,
	Cohort: Types.OnboardingFunnelCohort?,
	Step: number?,
	StepName: Types.OnboardingFunnelStep?,
	FlowType: Enum.AnalyticsEconomyFlowType?,
	CurrencyType: string?,
	Amount: number?,
	EndingBalance: number?,
	TransactionType: string?,
	ItemSku: string?,
}

export type PlatformAnalyticsAdapter = {
	IsPublishedLiveServer: (() -> boolean)?,
	LogOnboardingFunnelStepEvent: (
		player: Player?,
		step: number,
		stepName: string,
		customFields: { [any]: any }?
	) -> (),
	LogEconomyEvent: (
		player: Player?,
		flowType: Enum.AnalyticsEconomyFlowType,
		currencyType: string,
		amount: number,
		endingBalance: number,
		transactionType: string,
		itemSku: string
	) -> (),
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

local FUNNEL_STEP_ORDER: { Types.OnboardingFunnelStep } = {
	"Spawn",
	"FirstMeteor",
	"FirstHatch",
	"FirstPen",
	"FirstUpgrade",
	"SecondRescue",
}

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
local studioCapturedStepsByUserId: { [number]: { [Types.OnboardingFunnelStep]: boolean } } = {}
local recentStudioEvents: { TelemetryEventRecord } = {}
local testEventSink: ((event: TelemetryEventRecord) -> ())? = nil
local customPlatformAdapter: PlatformAnalyticsAdapter? = nil
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

local function isPublishedLiveEnvironment(): boolean
	if customPlatformAdapter ~= nil and customPlatformAdapter.IsPublishedLiveServer ~= nil then
		return customPlatformAdapter.IsPublishedLiveServer()
	end
	return (not RunService:IsStudio()) and (game.PlaceId > 0)
end

local function recordTelemetryEvent(event: TelemetryEventRecord): ()
	table.insert(recentStudioEvents, event)
	if #recentStudioEvents > MAX_STUDIO_RECENT_EVENTS then
		table.remove(recentStudioEvents, 1)
	end
	if testEventSink ~= nil then
		testEventSink(event)
	end
end

local function ensureFunnelMaps(profile: Types.PlayerProfileData): ()
	if profile.OnboardingFunnelCohort ~= "Legacy" then
		profile.OnboardingFunnelCohort = "Fresh"
	end
	if profile.OnboardingFunnelAchieved == nil then
		profile.OnboardingFunnelAchieved = {}
	end
	if profile.OnboardingFunnelSubmitted == nil then
		profile.OnboardingFunnelSubmitted = {}
	end
end

-- Sends only the contiguous completed prefix of achieved steps in order (1..6)
-- so Roblox never auto-credits skipped intermediate steps when players progress out of order.
local function flushContiguousOnboardingPrefix(
	player: Player?,
	userId: number,
	profile: Types.PlayerProfileData
): number
	ensureFunnelMaps(profile)
	if profile.OnboardingFunnelCohort == "Legacy" then
		return 0
	end

	local isPublishedLive = isPublishedLiveEnvironment()
	local flushedCount = 0

	for stepIndex, stepName in ipairs(FUNNEL_STEP_ORDER) do
		if profile.OnboardingFunnelAchieved[stepName] ~= true then
			break
		end

		if isPublishedLive then
			if profile.OnboardingFunnelSubmitted[stepName] == true then
				continue
			end
			if customPlatformAdapter == nil and not isRealLivePlayer(player) then
				break
			end

			local customFields = {
				[Enum.AnalyticsCustomFieldKeys.CustomField01] = profile.OnboardingFunnelCohort,
			}
			local ok, err = pcall(function()
				if customPlatformAdapter ~= nil then
					customPlatformAdapter.LogOnboardingFunnelStepEvent(player, stepIndex, stepName, customFields)
				else
					RobloxAnalyticsService:LogOnboardingFunnelStepEvent(player :: Player, stepIndex, stepName, customFields)
				end
			end)

			if not ok then
				warn(string.format("[AnalyticsService] LogOnboardingFunnelStepEvent(%s) failed: %s", stepName, tostring(err)))
				recordTelemetryEvent({
					Kind = "OnboardingFunnel",
					DeliveryMode = "PlatformFailed",
					UserId = userId,
					Cohort = profile.OnboardingFunnelCohort,
					Step = stepIndex,
					StepName = stepName,
				})
				-- Stop at the failed step so subsequent steps stay ordered and this step remains retryable.
				break
			end

			profile.OnboardingFunnelSubmitted[stepName] = true
			if customPlatformAdapter == nil then
				print(string.format(
					"[AnalyticsService] Submitted OnboardingFunnel Step=%d (%s) Cohort=%s",
					stepIndex,
					stepName,
					profile.OnboardingFunnelCohort
				))
			end
			recordTelemetryEvent({
				Kind = "OnboardingFunnel",
				DeliveryMode = "PlatformSubmitted",
				UserId = userId,
				Cohort = profile.OnboardingFunnelCohort,
				Step = stepIndex,
				StepName = stepName,
			})
			flushedCount += 1
		else
			-- Studio capture must never mark OnboardingFunnelSubmitted, keeping live submission intact.
			local capturedMap = studioCapturedStepsByUserId[userId]
			if capturedMap == nil then
				capturedMap = {}
				studioCapturedStepsByUserId[userId] = capturedMap
			end
			if capturedMap[stepName] == true then
				continue
			end
			capturedMap[stepName] = true

			if customPlatformAdapter == nil and isRealLivePlayer(player) then
				local customFields = {
					[Enum.AnalyticsCustomFieldKeys.CustomField01] = profile.OnboardingFunnelCohort,
				}
				local ok, err = pcall(function()
					RobloxAnalyticsService:LogOnboardingFunnelStepEvent(player :: Player, stepIndex, stepName, customFields)
				end)
				if not ok then
					warn(string.format("[AnalyticsService] Studio LogOnboardingFunnelStepEvent(%s) failed: %s", stepName, tostring(err)))
				end
			end

			recordTelemetryEvent({
				Kind = "OnboardingFunnel",
				DeliveryMode = "StudioCapture",
				UserId = userId,
				Cohort = profile.OnboardingFunnelCohort,
				Step = stepIndex,
				StepName = stepName,
			})
			flushedCount += 1
		end
	end

	return flushedCount
end

local function recordAndFlushStep(
	player: Player?,
	userId: number,
	profile: Types.PlayerProfileData,
	stepName: Types.OnboardingFunnelStep
): boolean
	ensureFunnelMaps(profile)
	if FUNNEL_STEP_NUMBERS[stepName] == nil then
		return false
	end
	profile.OnboardingFunnelAchieved[stepName] = true
	return flushContiguousOnboardingPrefix(player, userId, profile) > 0
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
	local isPublishedLive = isPublishedLiveEnvironment()

	if isPublishedLive then
		if customPlatformAdapter == nil and not isRealLivePlayer(player) then
			return false
		end
		local ok, err = pcall(function()
			if customPlatformAdapter ~= nil then
				customPlatformAdapter.LogEconomyEvent(
					player,
					flowType,
					CURRENCY_COINS,
					cleanAmount,
					cleanEnding,
					transactionType,
					itemSku
				)
			else
				RobloxAnalyticsService:LogEconomyEvent(
					player :: Player,
					flowType,
					CURRENCY_COINS,
					cleanAmount,
					cleanEnding,
					transactionType,
					itemSku
				)
			end
		end)
		if not ok then
			warn(string.format("[AnalyticsService] LogEconomyEvent(%s/%s) failed: %s", flowType.Name, itemSku, tostring(err)))
			recordTelemetryEvent({
				Kind = "Economy",
				DeliveryMode = "PlatformFailed",
				UserId = userId,
				FlowType = flowType,
				CurrencyType = CURRENCY_COINS,
				Amount = cleanAmount,
				EndingBalance = cleanEnding,
				TransactionType = transactionType,
				ItemSku = itemSku,
			})
			return false
		end

		if customPlatformAdapter == nil then
			print(string.format(
				"[AnalyticsService] Submitted Economy %s %d Coins (Balance=%d, Tx=%s, Sku=%s)",
				flowType.Name,
				cleanAmount,
				cleanEnding,
				transactionType,
				itemSku
			))
		end
		recordTelemetryEvent({
			Kind = "Economy",
			DeliveryMode = "PlatformSubmitted",
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

	if customPlatformAdapter == nil and isRealLivePlayer(player) then
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
			warn(string.format("[AnalyticsService] Studio LogEconomyEvent(%s/%s) failed: %s", flowType.Name, itemSku, tostring(err)))
		end
	end

	recordTelemetryEvent({
		Kind = "Economy",
		DeliveryMode = "StudioCapture",
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
	return recordAndFlushStep(player, userId, profile, "Spawn")
end

function AnalyticsService.RecordMeteorRescue(
	player: Player?,
	userId: number,
	profile: Types.PlayerProfileData,
	_isStarter: boolean,
	_trait: Types.MeteorTraitId,
	_speciesId: Types.SpeciesId
): (boolean, Types.OnboardingFunnelStep?)
	ensureFunnelMaps(profile)
	if profile.OnboardingFunnelAchieved["FirstMeteor"] ~= true then
		local flushed = recordAndFlushStep(player, userId, profile, "FirstMeteor")
		return flushed, "FirstMeteor"
	end
	if profile.OnboardingFunnelAchieved["SecondRescue"] ~= true then
		local flushed = recordAndFlushStep(player, userId, profile, "SecondRescue")
		return flushed, "SecondRescue"
	end
	return false, nil
end

function AnalyticsService.RecordFirstHatch(
	player: Player?,
	userId: number,
	profile: Types.PlayerProfileData,
	_speciesId: Types.SpeciesId?
): boolean
	return recordAndFlushStep(player, userId, profile, "FirstHatch")
end

function AnalyticsService.RecordFirstPen(
	player: Player?,
	userId: number,
	profile: Types.PlayerProfileData,
	_slotId: string?
): boolean
	return recordAndFlushStep(player, userId, profile, "FirstPen")
end

function AnalyticsService.RecordFirstUpgrade(
	player: Player?,
	userId: number,
	profile: Types.PlayerProfileData,
	_upgradeId: Types.UpgradeId?
): boolean
	return recordAndFlushStep(player, userId, profile, "FirstUpgrade")
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
	studioCapturedStepsByUserId[userId] = nil
end

function AnalyticsService.ClearTrackingForUserId(userId: number): ()
	pendingAccrualByUserId[userId] = nil
	studioCapturedStepsByUserId[userId] = nil
end

function AnalyticsService.SetEventSinkForTest(sink: ((event: TelemetryEventRecord) -> ())?): ()
	testEventSink = sink
end

function AnalyticsService.SetPlatformAdapterForTest(adapter: PlatformAnalyticsAdapter?): ()
	customPlatformAdapter = adapter
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
	local prevAdapter = customPlatformAdapter

	local function resetCapture()
		captured = {}
	end

	local ok, err = pcall(function()
		AnalyticsService.SetEventSinkForTest(function(ev: TelemetryEventRecord)
			table.insert(captured, ev)
		end)

		local liveFunnelCalls: { { Step: number, StepName: string } } = {}
		local liveEconomyCalls: { { Flow: string, Amount: number, Balance: number, Sku: string } } = {}
		local failStepName: string? = nil
		local failEconomyOnce = false

		local publishedAdapter: PlatformAnalyticsAdapter = {
			IsPublishedLiveServer = function()
				return true
			end,
			LogOnboardingFunnelStepEvent = function(_player, step, stepName, _customFields)
				if failStepName ~= nil and stepName == failStepName then
					error("Simulated platform funnel outage for " .. stepName)
				end
				table.insert(liveFunnelCalls, { Step = step, StepName = stepName })
			end,
			LogEconomyEvent = function(_player, flowType, _currencyType, amount, endingBalance, _txType, itemSku)
				if failEconomyOnce then
					failEconomyOnce = false
					error("Simulated platform economy outage")
				end
				table.insert(liveEconomyCalls, {
					Flow = flowType.Name,
					Amount = amount,
					Balance = endingBalance,
					Sku = itemSku,
				})
			end,
		}

		-- 1. Sequential 6-step happy path (StudioCapture + PublishedLive PlatformSubmitted) & deduplication
		AnalyticsService.SetPlatformAdapterForTest(nil)
		local uStudio = -920001
		AnalyticsService.ClearTrackingForUserId(uStudio)
		local pStudio = DataService.CreateDefaultProfile(1000)
		resetCapture()

		assert(AnalyticsService.RecordSpawn(nil, uStudio, pStudio), "Studio Step 1 Spawn")
		assert(AnalyticsService.RecordMeteorRescue(nil, uStudio, pStudio, true, "Ember", "StarSlime"), "Studio Step 2 FirstMeteor")
		assert(AnalyticsService.RecordFirstHatch(nil, uStudio, pStudio, "StarSlime"), "Studio Step 3 FirstHatch")
		assert(AnalyticsService.RecordFirstPen(nil, uStudio, pStudio, "Pen_1"), "Studio Step 4 FirstPen")
		assert(AnalyticsService.RecordFirstUpgrade(nil, uStudio, pStudio, "PenSlot_2"), "Studio Step 5 FirstUpgrade")
		assert(AnalyticsService.RecordMeteorRescue(nil, uStudio, pStudio, false, "Ember", "CinderPup"), "Studio Step 6 SecondRescue")
		assert(#captured == 6, "Studio emits 6 sequential events")
		for idx, ev in ipairs(captured) do
			assert(ev.DeliveryMode == "StudioCapture" and ev.Step == idx and ev.Cohort == "Fresh", "StudioCapture leaves DeliveryMode=StudioCapture")
		end
		assert(next(pStudio.OnboardingFunnelSubmitted) == nil, "StudioCapture never marks OnboardingFunnelSubmitted")
		AnalyticsService.ClearTrackingForUserId(uStudio)

		AnalyticsService.SetPlatformAdapterForTest(publishedAdapter)
		liveFunnelCalls = {}
		local uPub = -920002
		local pPub = DataService.CreateDefaultProfile(1000)
		resetCapture()

		assert(AnalyticsService.RecordSpawn(nil, uPub, pPub), "Published Step 1 Spawn")
		assert(not AnalyticsService.RecordSpawn(nil, uPub, pPub), "Duplicate Spawn ignored")
		local m1Ok, m1Step = AnalyticsService.RecordMeteorRescue(nil, uPub, pPub, true, "Ember", "StarSlime")
		assert(m1Ok and m1Step == "FirstMeteor", "Published Step 2 FirstMeteor")
		assert(AnalyticsService.RecordFirstHatch(nil, uPub, pPub, "StarSlime"), "Published Step 3 FirstHatch")
		assert(AnalyticsService.RecordFirstPen(nil, uPub, pPub, "Pen_1"), "Published Step 4 FirstPen")
		assert(AnalyticsService.RecordFirstUpgrade(nil, uPub, pPub, "PenSlot_2"), "Published Step 5 FirstUpgrade")
		local m2Ok, m2Step = AnalyticsService.RecordMeteorRescue(nil, uPub, pPub, false, "Ember", "CinderPup")
		assert(m2Ok and m2Step == "SecondRescue", "Published Step 6 SecondRescue")
		local m3Ok, m3Step = AnalyticsService.RecordMeteorRescue(nil, uPub, pPub, false, "Frost", "FrostBeetle")
		assert(not m3Ok and m3Step == nil, "3rd rescue emits zero funnel events")

		assert(#captured == 6 and #liveFunnelCalls == 6, "Published submits 6 sequential events")
		for idx, ev in ipairs(captured) do
			assert(ev.DeliveryMode == "PlatformSubmitted" and ev.Step == idx, "Published marks PlatformSubmitted")
			assert(pPub.OnboardingFunnelSubmitted[ev.StepName :: Types.OnboardingFunnelStep] == true, "Submitted marked true after success")
		end
		passed += 1

		-- 2. Economy Sources & Sinks + live failure reporting
		local uEcon = -920003
		AnalyticsService.ClearTrackingForUserId(uEcon)
		liveEconomyCalls = {}
		resetCapture()

		assert(not AnalyticsService.RecordPenAccrual(nil, uEcon, 10, 10, 100), "10 Coins buffered below threshold")
		assert(#captured == 0, "Zero events before threshold")
		assert(AnalyticsService.RecordPenAccrual(nil, uEcon, 15, 25, 105), "25 Coins triggers batch flush")
		assert(#captured == 1 and captured[1].DeliveryMode == "PlatformSubmitted" and captured[1].ItemSku == "PenAccrual" and captured[1].Amount == 25, "Batch PenAccrual submitted")

		assert(not AnalyticsService.RecordPenAccrual(nil, uEcon, 4, 29, 200), "4 Coins buffered at t=200")
		assert(AnalyticsService.RecordPenAccrual(nil, uEcon, 4, 33, 230), "Interval >= 30s flushes 8 Coins")
		assert(#captured == 2 and captured[2].Amount == 8 and captured[2].EndingBalance == 33, "Interval accrual flush verified")

		assert(not AnalyticsService.RecordPenAccrual(nil, uEcon, 6, 39, 300), "Buffer 6 Coins before spend")
		assert(AnalyticsService.RecordCoinSink(nil, uEcon, 20, 19, Enum.AnalyticsEconomyTransactionType.Shop.Name, "Upgrade_PenSlot_2"), "Upgrade sink succeeds")
		assert(#captured == 4 and captured[3].ItemSku == "PenAccrual" and captured[3].EndingBalance == 39 and captured[4].ItemSku == "Upgrade_PenSlot_2" and captured[4].EndingBalance == 19, "Pre-spend flush + sink ordering verified")

		assert(AnalyticsService.RecordCoinSource(nil, uEcon, 40, 59, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "Sell_StarSlime"), "Sell source logged")
		assert(AnalyticsService.RecordCoinSink(nil, uEcon, 45, 14, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "Feed_NebulaFox"), "Feed sink logged")
		assert(AnalyticsService.RecordCoinSink(nil, uEcon, 75, 0, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "Lure_Frost"), "Lure sink logged")

		failEconomyOnce = true
		assert(not AnalyticsService.RecordCoinSource(nil, uEcon, 10, 10, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "Sell_StarSlime"), "Thrown live economy call returns false")
		assert(captured[#captured].DeliveryMode == "PlatformFailed", "Thrown economy call records PlatformFailed")

		AnalyticsService.ClearTrackingForUserId(uEcon)
		assert(pendingAccrualByUserId[uEcon] == nil, "ClearTrackingForUserId cleans pending accrual")
		passed += 1

		-- 3. Out-of-order regressions (Review #035 Finding #1): early 2nd rescue, out-of-order upgrade, Legacy cohort suppression
		local uEarly2 = -920004
		local pEarly2 = DataService.CreateDefaultProfile(2000)
		liveFunnelCalls = {}
		resetCapture()

		assert(AnalyticsService.RecordSpawn(nil, uEarly2, pEarly2), "Early2: Step 1 Spawn")
		assert(AnalyticsService.RecordMeteorRescue(nil, uEarly2, pEarly2, true, "Ember", "StarSlime"), "Early2: Step 2 FirstMeteor")
		local earlyResOk, earlyResName = AnalyticsService.RecordMeteorRescue(nil, uEarly2, pEarly2, false, "Ember", "CinderPup")
		assert(not earlyResOk and earlyResName == "SecondRescue", "Early2: 2nd rescue achieved early without flushing Step 6")
		assert(pEarly2.OnboardingFunnelAchieved["SecondRescue"] == true and pEarly2.OnboardingFunnelSubmitted["SecondRescue"] == nil, "Early2: SecondRescue marked Achieved but NOT Submitted")
		assert(#liveFunnelCalls == 2 and liveFunnelCalls[1].Step == 1 and liveFunnelCalls[2].Step == 2, "Early2: ONLY Steps 1..2 sent so Roblox never credits skipped steps")

		assert(AnalyticsService.RecordFirstHatch(nil, uEarly2, pEarly2, "StarSlime"), "Early2: Step 3 FirstHatch")
		assert(AnalyticsService.RecordFirstPen(nil, uEarly2, pEarly2, "Pen_1"), "Early2: Step 4 FirstPen")
		assert(AnalyticsService.RecordFirstUpgrade(nil, uEarly2, pEarly2, "PenSlot_2"), "Early2: Step 5 FirstUpgrade triggers Step 5 + held Step 6")
		assert(#liveFunnelCalls == 6, "All 6 steps submitted once prerequisites complete")
		for idx, call in ipairs(liveFunnelCalls) do
			assert(call.Step == idx, "Contiguous flush order step " .. tostring(idx))
		end

		-- Out-of-order upgrade before FirstPen
		local uOopUp = -920005
		local pOopUp = DataService.CreateDefaultProfile(2000)
		liveFunnelCalls = {}
		resetCapture()
		assert(AnalyticsService.RecordSpawn(nil, uOopUp, pOopUp), "OopUp: Spawn")
		assert(AnalyticsService.RecordMeteorRescue(nil, uOopUp, pOopUp, true, "Ember", "StarSlime"), "OopUp: FirstMeteor")
		assert(AnalyticsService.RecordFirstHatch(nil, uOopUp, pOopUp, "StarSlime"), "OopUp: FirstHatch")
		assert(not AnalyticsService.RecordFirstUpgrade(nil, uOopUp, pOopUp, "BagCap_20"), "OopUp: FirstUpgrade held before FirstPen")
		assert(#liveFunnelCalls == 3 and pOopUp.OnboardingFunnelAchieved["FirstUpgrade"] == true and pOopUp.OnboardingFunnelSubmitted["FirstUpgrade"] == nil, "OopUp: Upgrade held")
		assert(AnalyticsService.RecordFirstPen(nil, uOopUp, pOopUp, "Pen_1"), "OopUp: FirstPen flushes Step 4 then Step 5")
		assert(#liveFunnelCalls == 5 and liveFunnelCalls[4].Step == 4 and liveFunnelCalls[5].Step == 5, "OopUp: Step 4 -> Step 5 order preserved")

		-- Legacy cohort suppression: 0 funnel submissions, economy events still submit
		local uLegacy = -920006
		local pLegacy = DataService.ReconcileAndMigrateProfileData({
			SchemaVersion = 2,
			StarterMeteorCompleted = true,
			Coins = 100,
			Items = { ["leg1"] = { UID = "leg1", SpeciesId = "StarSlime", Variant = "Normal", State = "PodInBag", CreatedAt = 1000 } },
		}, 2000)
		liveFunnelCalls = {}
		resetCapture()
		assert(pLegacy.OnboardingFunnelCohort == "Legacy", "Prior-progress profile is Legacy cohort")
		assert(not AnalyticsService.RecordSpawn(nil, uLegacy, pLegacy), "Legacy cohort suppresses Spawn funnel")
		assert(not AnalyticsService.RecordFirstHatch(nil, uLegacy, pLegacy, "StarSlime"), "Legacy cohort suppresses FirstHatch funnel")
		assert(#liveFunnelCalls == 0, "Legacy cohort emits zero fresh-funnel steps")
		assert(AnalyticsService.RecordCoinSource(nil, uLegacy, 40, 140, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "Sell_StarSlime"), "Legacy cohort still logs Economy events")
		passed += 1

		-- 4. Failed platform submission & reconnect retry + Studio vs Published separation (Review #035 Finding #2)
		local retryStore = DataService.CreateIsolatedMockStoreForTest("S501Retry")
		local uRetry = -920007
		liveFunnelCalls = {}
		resetCapture()
		failStepName = "FirstMeteor"

		assert(DataService.StartProfileSessionForUserId(uRetry, nil, { Store = retryStore, NowClock = 3000 }), "Retry join 1")
		local pRetry1 = DataService.GetProfileByUserId(uRetry) :: Types.PlayerProfileData
		assert(AnalyticsService.RecordSpawn(nil, uRetry, pRetry1), "Retry join 1: Spawn succeeds")
		local rFailOk, rFailStep = AnalyticsService.RecordMeteorRescue(nil, uRetry, pRetry1, true, "Ember", "StarSlime")
		assert(not rFailOk and rFailStep == "FirstMeteor", "Retry join 1: Failed FirstMeteor returns flushed=false")
		assert(pRetry1.OnboardingFunnelAchieved["FirstMeteor"] == true and pRetry1.OnboardingFunnelSubmitted["FirstMeteor"] == nil, "Failed step marked Achieved but NOT Submitted")
		assert(captured[#captured].DeliveryMode == "PlatformFailed", "Failed call records DeliveryMode=PlatformFailed")
		assert(not AnalyticsService.RecordFirstHatch(nil, uRetry, pRetry1, "StarSlime"), "Step 3 blocked while Step 2 unsubmitted")
		assert(#liveFunnelCalls == 1 and pRetry1.OnboardingFunnelSubmitted["FirstHatch"] == nil, "Step 3 not submitted before Step 2")

		DataService.EndSession(uRetry)
		assert(DataService.WaitForUserFinalSave(uRetry, 2), "Save retry join 1")
		DataService.ClearTestTrackingForUserIds({ uRetry })

		-- Reconnect when platform recovers: Spawn skipped, Step 2 + Step 3 retried & submitted!
		failStepName = nil
		liveFunnelCalls = {}
		resetCapture()
		assert(DataService.StartProfileSessionForUserId(uRetry, nil, { Store = retryStore, NowClock = 3020 }), "Retry join 2")
		local pRetry2 = DataService.GetProfileByUserId(uRetry) :: Types.PlayerProfileData
		assert(AnalyticsService.RecordSpawn(nil, uRetry, pRetry2), "Retry join 2: RecordSpawn flushes pending Step 2 + Step 3")
		assert(#liveFunnelCalls == 2 and liveFunnelCalls[1].Step == 2 and liveFunnelCalls[2].Step == 3, "Retry join 2 submits Step 2 -> Step 3 in order")
		assert(pRetry2.OnboardingFunnelSubmitted["FirstMeteor"] == true and pRetry2.OnboardingFunnelSubmitted["FirstHatch"] == true, "Recovered steps marked Submitted")

		DataService.EndSession(uRetry)
		assert(DataService.WaitForUserFinalSave(uRetry, 2), "Save retry join 2")
		DataService.ClearTestTrackingForUserIds({ uRetry })

		-- 3rd join emits 0 duplicates
		liveFunnelCalls = {}
		resetCapture()
		assert(DataService.StartProfileSessionForUserId(uRetry, nil, { Store = retryStore, NowClock = 3040 }), "Retry join 3")
		local pRetry3 = DataService.GetProfileByUserId(uRetry) :: Types.PlayerProfileData
		assert(not AnalyticsService.RecordSpawn(nil, uRetry, pRetry3) and #liveFunnelCalls == 0, "Retry join 3 emits zero duplicates")
		DataService.EndSession(uRetry)
		assert(DataService.WaitForUserFinalSave(uRetry, 2), "Cleanup retry join 3")
		DataService.ClearTestTrackingForUserIds({ uRetry })

		-- Studio session does not block subsequent published submission
		local uStuToPub = -920008
		local pStuToPub = DataService.CreateDefaultProfile(4000)
		AnalyticsService.SetPlatformAdapterForTest(nil)
		assert(AnalyticsService.RecordSpawn(nil, uStuToPub, pStuToPub), "Studio captures Spawn")
		assert(pStuToPub.OnboardingFunnelSubmitted["Spawn"] == nil, "Studio leaves Submitted empty")
		AnalyticsService.SetPlatformAdapterForTest(publishedAdapter)
		liveFunnelCalls = {}
		assert(AnalyticsService.RecordSpawn(nil, uStuToPub, pStuToPub), "Published server still submits Spawn after Studio capture")
		assert(#liveFunnelCalls == 1 and pStuToPub.OnboardingFunnelSubmitted["Spawn"] == true, "Published server submits & marks Submitted")
		AnalyticsService.ClearTrackingForUserId(uStuToPub)
		passed += 1

		-- 5. Full ProfileStore.Mock reconnect deduplication under simulated published server
		local mockStore = DataService.CreateIsolatedMockStoreForTest("S501Funnel")
		local uReconn = -920009
		liveFunnelCalls = {}
		resetCapture()

		assert(DataService.StartProfileSessionForUserId(uReconn, nil, { Store = mockStore, NowClock = 1000 }), "Join 1")
		local pRec1 = DataService.GetProfileByUserId(uReconn) :: Types.PlayerProfileData
		assert(AnalyticsService.RecordSpawn(nil, uReconn, pRec1), "Join 1 records Spawn")
		assert(AnalyticsService.RecordMeteorRescue(nil, uReconn, pRec1, true, "Ember", "StarSlime"), "Join 1 records FirstMeteor")
		DataService.EndSession(uReconn)
		assert(DataService.WaitForUserFinalSave(uReconn, 2), "Save join 1")
		DataService.ClearTestTrackingForUserIds({ uReconn })

		resetCapture()
		assert(DataService.StartProfileSessionForUserId(uReconn, nil, { Store = mockStore, NowClock = 1020 }), "Join 2 (reconnect)")
		local pRec2 = DataService.GetProfileByUserId(uReconn) :: Types.PlayerProfileData
		assert(not AnalyticsService.RecordSpawn(nil, uReconn, pRec2), "Reconnect skips duplicate Spawn")
		assert(AnalyticsService.RecordFirstHatch(nil, uReconn, pRec2, "StarSlime"), "Join 2 FirstHatch")
		assert(AnalyticsService.RecordFirstPen(nil, uReconn, pRec2, "Pen_1"), "Join 2 FirstPen")
		assert(AnalyticsService.RecordFirstUpgrade(nil, uReconn, pRec2, "PenSlot_2"), "Join 2 FirstUpgrade")
		assert(AnalyticsService.RecordMeteorRescue(nil, uReconn, pRec2, false, "Ember", "CinderPup"), "Join 2 SecondRescue")
		assert(#liveFunnelCalls == 6, "All 6 steps submitted across reconnects")
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

		-- 6. Invalid/zero/negative/NaN guards & nil-player safety
		local uGuard = -920010
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
	AnalyticsService.SetPlatformAdapterForTest(prevAdapter)
	if not ok then
		error(err)
	end

	return passed
end

return AnalyticsService
