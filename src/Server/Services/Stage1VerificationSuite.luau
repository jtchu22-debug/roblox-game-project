--!strict
--[[
	Service/Suite: Stage1VerificationSuite (S1-09)
	Purpose: Automated server-side Stage 1 adversarial and 5-minute loop pacing verification suite.
	         Tests full inbound remote fuzzing + rate-limit saturation, 2-player meteor races & hijack/
	         abandonment/leave cleanup, cross-plot station isolation, upgrade spam, InPen sell protection,
	         bag-full deadlock guards, and a full 5-minute economy simulation with invariant checks.
	Connections: Requires NetworkService, DataService, EconomyService, PlotService, MeteorService, and Shared configs.
	How to Test in Studio: Press Play (F5) with Constants.RUN_SELF_TESTS = true and verify Output prints PASS.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Types = require(Shared:WaitForChild("Types"))
local CritterConfig = require(Shared:WaitForChild("Config"):WaitForChild("CritterConfig"))
local UpgradeConfig = require(Shared:WaitForChild("Config"):WaitForChild("UpgradeConfig"))
local EconomyMath = require(Shared:WaitForChild("Util"):WaitForChild("EconomyMath"))

local ServicesFolder = script.Parent
local NetworkService = require(ServicesFolder:WaitForChild("NetworkService"))
local DataService = require(ServicesFolder:WaitForChild("DataService"))
local EconomyService = require(ServicesFolder:WaitForChild("EconomyService"))
local PlotService = require(ServicesFolder:WaitForChild("PlotService"))
local MeteorService = require(ServicesFolder:WaitForChild("MeteorService"))

local Stage1VerificationSuite = {
	Name = "Stage1VerificationSuite",
}

local function assertInvariants(profile: Types.PlayerProfileData, contextLabel: string): ()
	local ok, reason = EconomyService.ValidateProfileInvariants(profile)
	assert(ok, string.format("Economy invariant broken (%s): %s", contextLabel, tostring(reason)))
end

local function findAnyItemInState(profile: Types.PlayerProfileData, targetState: Types.ItemState): Types.CritterItemRecord?
	for _, item in pairs(profile.Items) do
		if item.State == targetState then
			return item
		end
	end
	return nil
end

local function runRemoteFuzzAndRateMatrix(): ()
	local uFuzz = -940099
	NetworkService.ClearPlayerBuckets(uFuzz)

	local hostileValues: { unknown } = {
		0 / 0,
		math.huge,
		-math.huge,
		-1,
		"",
		string.rep("z", Constants.MAX_STRING_ID_LENGTH + 1),
		string.rep("k", 256),
		{},
		true,
		false,
		nil,
	}

	for _, bad in ipairs(hostileValues) do
		assert(not NetworkService.ValidateInboundPayload(Constants.REMOTE_NAMES.RequestStartCrack, bad), "StartCrack must reject hostile arg")
		assert(not NetworkService.ValidateInboundPayload(Constants.REMOTE_NAMES.RequestFinishCrack, bad, "nonce-1"), "FinishCrack must reject hostile meteorUID")
		assert(not NetworkService.ValidateInboundPayload(Constants.REMOTE_NAMES.RequestFinishCrack, "uid-1", bad), "FinishCrack must reject hostile nonce")
		assert(not NetworkService.ValidateInboundPayload(Constants.REMOTE_NAMES.RequestBuyUpgrade, bad), "BuyUpgrade must reject hostile upgradeId")
		assert(not NetworkService.ValidateInboundPayload(Constants.REMOTE_NAMES.RequestPlotAction, bad, "Pen_1"), "PlotAction must reject hostile action")
		assert(not NetworkService.ValidateInboundPayload(Constants.REMOTE_NAMES.RequestPlotAction, "StartIncubate", bad, "item-1"), "StartIncubate must reject hostile slot")
		assert(not NetworkService.ValidateInboundPayload(Constants.REMOTE_NAMES.RequestPlotAction, "StartIncubate", "Incubator_1", bad), "StartIncubate must reject hostile itemUID")
	end

	-- Extra argument rejection & deprecated action rejection
	assert(not NetworkService.ValidateInboundPayload(Constants.REMOTE_NAMES.RequestInitialSnapshot, nil), "Snapshot rejects nil arg")
	assert(not NetworkService.ValidateInboundPayload(Constants.REMOTE_NAMES.RequestStartCrack, "uid-1", "extra"), "StartCrack rejects extra arg")
	assert(not NetworkService.ValidateInboundPayload(Constants.REMOTE_NAMES.RequestFinishCrack, "uid-1", "nonce-1", 999), "FinishCrack rejects ClientDelta")
	assert(not NetworkService.ValidateInboundPayload(Constants.REMOTE_NAMES.RequestPlotAction, "SellCritter", "item-1", "extra"), "SellCritter rejects 3rd arg")
	assert(not NetworkService.ValidateInboundPayload(Constants.REMOTE_NAMES.RequestPlotAction, "RemoveFromPen", "Pen_1", "extra"), "RemoveFromPen rejects 3rd arg")
	assert(not NetworkService.ValidateInboundPayload(Constants.REMOTE_NAMES.RequestPlotAction, "FuseCritters", "Pen_1"), "Removed action rejected")

	-- Token bucket saturation and refill across all 5 inbound remotes
	local capacities: { { Remote: string, Cap: number } } = {
		{ Remote = Constants.REMOTE_NAMES.RequestInitialSnapshot, Cap = 2 },
		{ Remote = Constants.REMOTE_NAMES.RequestStartCrack, Cap = 4 },
		{ Remote = Constants.REMOTE_NAMES.RequestFinishCrack, Cap = 4 },
		{ Remote = Constants.REMOTE_NAMES.RequestPlotAction, Cap = 8 },
		{ Remote = Constants.REMOTE_NAMES.RequestBuyUpgrade, Cap = 3 },
	}
	local t0 = 1000
	for _, entry in ipairs(capacities) do
		for i = 1, entry.Cap do
			assert(
				NetworkService.CheckAndConsumeRateLimit(uFuzz, entry.Remote, t0),
				string.format("%s should allow burst %d/%d", entry.Remote, i, entry.Cap)
			)
		end
		assert(
			not NetworkService.CheckAndConsumeRateLimit(uFuzz, entry.Remote, t0),
			string.format("%s must reject burst + 1", entry.Remote)
		)
	end
	assert(NetworkService.CheckAndConsumeRateLimit(uFuzz, Constants.REMOTE_NAMES.RequestStartCrack, t0 + 1.0), "StartCrack bucket refills after 1s")
	assert(NetworkService.CheckAndConsumeRateLimit(uFuzz, Constants.REMOTE_NAMES.RequestInitialSnapshot, t0 + 3.0), "Snapshot bucket refills after 3s")

	NetworkService.ClearPlayerBuckets(uFuzz)
end

local function runTwoPlayerMeteorAdversarial(u1: number, u2: number, rng: Random): ()
	-- Race + cross-player AttemptNonce hijack + >28-stud abandon + recovery by p2
	local w1Ok, _, w1Raw = MeteorService.SpawnWildMeteorAtNode("MeteorNode_1", "Astral", 8000)
	assert(w1Ok and w1Raw ~= nil, "Wild meteor 1 spawns for 2P adversarial check")
	local w1 = w1Raw :: MeteorService.ActiveMeteor

	local p1 = DataService.GetProfileByUserId(u1) :: Types.PlayerProfileData
	local p2 = DataService.GetProfileByUserId(u2) :: Types.PlayerProfileData

	-- Locking check: u1 without StarCracker cannot claim Astral meteor w1
	local lockedStart = MeteorService.StartCrackAtPosition(u1, w1.Position, w1.UID, 8001)
	assert(not lockedStart.Ok and lockedStart.Reason == "ToolRequired" and w1.ClaimedByUserId == nil, "Locked player cannot claim Astral meteor")

	p1.Upgrades["StarCracker"] = true
	p2.Upgrades["StarCracker"] = true

	local s1 = MeteorService.StartCrackAtPosition(u1, w1.Position, w1.UID, 8001)
	assert(s1.Ok and typeof(s1.AttemptNonce) == "string", "u1 wins claim on w1")

	local s2Blocked = MeteorService.StartCrackAtPosition(u2, w1.Position, w1.UID, 8001)
	assert(not s2Blocked.Ok and s2Blocked.Reason == "MeteorAlreadyClaimed", "u2 blocked from u1-claimed meteor")

	local hijack = MeteorService.FinishCrackAtPosition(u2, w1.Position, w1.UID, s1.AttemptNonce :: string, 8002, rng)
	assert(not hijack.Ok and hijack.Reason == "InvalidClaim", "u2 cannot hijack u1 nonce")
	assert(w1.ClaimedByUserId == u1, "Hijack attempt leaves u1 claim intact")

	local swept = MeteorService.SweepActiveClaims(8002.5, function(uid: number): Vector3?
		if uid == u1 then
			return w1.Position + Vector3.new(Constants.MAX_CRACK_ABANDON_DISTANCE + 2, 0, 0)
		end
		return w1.Position
	end)
	assert(swept == 1 and w1.ClaimedByUserId == nil, "Abandoning >28 studs releases claim")

	local s2Take = MeteorService.StartCrackAtPosition(u2, w1.Position, w1.UID, 8003)
	assert(s2Take.Ok and typeof(s2Take.AttemptNonce) == "string", "u2 takes abandoned wild meteor")
	local f2 = MeteorService.FinishCrackAtPosition(u2, w1.Position, w1.UID, s2Take.AttemptNonce :: string, 8004, rng)
	assert(f2.Ok, "u2 finishes rescued wild meteor and despawns it cleanly")

	-- Leave cleanup: u1 holds starter + wild claim; leaving despawns starter and unlocks wild for u2
	local st1Ok, _, st1Raw = MeteorService.SpawnStarterMeteorForPlot(1, u1, 8010)
	assert(st1Ok and st1Raw ~= nil, "Plot 1 starter spawns")
	local w2Ok, _, w2Raw = MeteorService.SpawnWildMeteorAtNode("MeteorNode_2", "Frost", 8010)
	assert(w2Ok and w2Raw ~= nil, "Wild meteor 2 spawns")
	local w2 = w2Raw :: MeteorService.ActiveMeteor

	local s1Wild = MeteorService.StartCrackAtPosition(u1, w2.Position, w2.UID, 8011)
	assert(s1Wild.Ok, "u1 claims w2 before disconnecting")

	MeteorService.HandlePlotReleased(1, u1)
	MeteorService.HandlePlayerClosing(u1)

	assert(w2.ClaimedByUserId == nil, "Disconnect frees wild meteor claim for remaining player")
	local s2Reclaim = MeteorService.StartCrackAtPosition(u2, w2.Position, w2.UID, 8012)
	assert(s2Reclaim.Ok and typeof(s2Reclaim.AttemptNonce) == "string", "u2 reclaims unlocked wild meteor")
	local f2Wild = MeteorService.FinishCrackAtPosition(u2, w2.Position, w2.UID, s2Reclaim.AttemptNonce :: string, 8013, rng)
	assert(f2Wild.Ok, "u2 finishes reclaimed wild meteor cleanly")

	-- Reassign u1 back onto Plot 1 for subsequent tests
	PlotService.ReleasePlotForUserId(u1)
	local p1 = DataService.GetProfileByUserId(u1) :: Types.PlayerProfileData
	assert((PlotService.AssignPlotForUserId(u1, "S1Verify_1", p1, nil)), "Reassign Plot 1 to u1")
end

local function runCrossPlotAndInventoryGuards(u1: number, u2: number, rng: Random): ()
	local p1 = DataService.GetProfileByUserId(u1) :: Types.PlayerProfileData
	assertInvariants(p1, "before cross-plot checks")

	-- Cross-plot station isolation: u2 is on Plot 2 and cannot authorize against Plot 1 stations
	for _, spec in ipairs({
		{ Kind = "Incubator", Target = "Incubator_1" },
		{ Kind = "Pen", Target = "Pen_1" },
		{ Kind = "SellStand", Target = "SellStand" },
		{ Kind = "UpgradePad", Target = "PenSlot_2" },
	}) do
		local p1Anchor = PlotService.ResolveStationAnchor(1, spec.Kind, spec.Target)
		assert(p1Anchor ~= nil, "Plot 1 anchor exists: " .. spec.Kind)
		local crossOk, crossReason = PlotService.AuthorizeStationAtPosition(u2, (p1Anchor :: BasePart).Position, spec.Kind, spec.Target)
		assert(not crossOk and crossReason == "OutOfRange", "u2 blocked from Plot 1 station: " .. spec.Kind)
	end

	-- Rapid upgrade spam dedupes cleanly with single debit
	p1.Coins = 200
	local firstBuy = EconomyService.BuyUpgradeOnProfile(p1, "PenSlot_2", 8100)
	assert(firstBuy.Ok and p1.Coins == 140 and p1.Upgrades["PenSlot_2"] == true, "First upgrade debits exactly 60 Coins")
	for _ = 1, 5 do
		local spamBuy = EconomyService.BuyUpgradeOnProfile(p1, "PenSlot_2", 8100)
		assert(not spamBuy.Ok and spamBuy.Reason == "AlreadyOwned" and p1.Coins == 140, "Upgrade spam rejected with zero duplicate debit")
	end

	-- Cannot sell PodInBag, Incubating pod, or active InPen critter; HatchedInBag sells once cleanly
	local grant = EconomyService.GrantPodToProfile(p1, "StarSlime", 8100, "guard-item-1")
	assert(grant.Ok, "Grant test pod")
	local sellPod = EconomyService.SellCritterOnProfile(p1, "guard-item-1", 8100)
	assert(not sellPod.Ok and sellPod.Reason == "CannotSellUnhatched", "Cannot sell PodInBag")

	local inc = EconomyService.StartIncubateOnProfile(p1, "Incubator_1", "guard-item-1", 8100)
	assert(inc.Ok, "Incubate test pod")
	local sellInc = EconomyService.SellCritterOnProfile(p1, "guard-item-1", 8105)
	assert(not sellInc.Ok and sellInc.Reason == "CannotSellUnhatched", "Cannot sell Incubating pod")

	local hatch = EconomyService.HatchFromSlotOnProfile(p1, "Incubator_1", 8120, rng)
	assert(hatch.Ok, "Hatch test pod")
	local place = EconomyService.PlaceInPenOnProfile(p1, "Pen_1", "guard-item-1", 8121)
	assert(place.Ok, "Place test critter in Pen_1")

	local coinsBeforePenSell = p1.Coins
	local sellPen = EconomyService.SellCritterOnProfile(p1, "guard-item-1", 8122)
	assert(not sellPen.Ok and sellPen.Reason == "MustRemoveFromPenFirst" and p1.Coins == coinsBeforePenSell, "Protected InPen critter cannot be sold")

	assert((EconomyService.RemoveFromPenOnProfile(p1, "Pen_1", 8125).Ok), "Remove test critter from Pen_1")
	local sellValid = EconomyService.SellCritterOnProfile(p1, "guard-item-1", 8126)
	assert(sellValid.Ok and (sellValid.CoinsEarned :: number) >= 40, "Hatched critter sells cleanly once")
	local sellReplay = EconomyService.SellCritterOnProfile(p1, "guard-item-1", 8126)
	assert(not sellReplay.Ok and sellReplay.Reason == "ItemNotFound", "Sell replay rejected")
	assertInvariants(p1, "after cross-plot & sell checks")

	-- Reset u1 profile cleanly before capacity deadlock test
	p1.Items = {}
	p1.Slots = {}
	p1.Upgrades = {}
	p1.Coins = 0
	p1.PendingFraction = 0

	-- Bag + Incubator reserved capacity guard at Start and Finish boundaries
	local wOk, _, wCapRaw = MeteorService.SpawnWildMeteorAtNode("MeteorNode_4", "Ember", 8200)
	assert(wOk and wCapRaw ~= nil, "Wild meteor spawns for bag-full deadlock test")
	local wCap = wCapRaw :: MeteorService.ActiveMeteor

	assert((EconomyService.GrantPodToProfile(p1, "StarSlime", 8200, "inc-reserve-1").Ok), "Grant pod for incubator reservation")
	assert((EconomyService.StartIncubateOnProfile(p1, "Incubator_1", "inc-reserve-1", 8200).Ok), "Start incubator reserving 1 slot")
	for i = 1, Constants.MAX_BAG_CAPACITY - 1 do
		assert((EconomyService.GrantPodToProfile(p1, "StarSlime", 8200, "cap-slot-" .. tostring(i)).Ok), "Fill remaining bag slot " .. tostring(i))
	end
	assertInvariants(p1, "at 9 bag + 1 incubator = 10 committed slots")

	local fullStart = MeteorService.StartCrackAtPosition(u1, wCap.Position, wCap.UID, 8201)
	assert(not fullStart.Ok and fullStart.Reason == "BagFull" and wCap.ClaimedByUserId == nil, "10 committed slots block StartCrack before claiming meteor")

	-- Free 1 slot, claim meteor, refill slot before finish -> FinishCrack fails cleanly & frees meteor for u2
	p1.Items["cap-slot-1"] = nil
	local midStart = MeteorService.StartCrackAtPosition(u1, wCap.Position, wCap.UID, 8202)
	assert(midStart.Ok and typeof(midStart.AttemptNonce) == "string", "Start succeeds with 1 free committed slot")
	assert((EconomyService.GrantPodToProfile(p1, "StarSlime", 8202, "cap-slot-refill").Ok), "Fill last slot mid-crack")

	local midFinish = MeteorService.FinishCrackAtPosition(u1, wCap.Position, wCap.UID, midStart.AttemptNonce :: string, 8203, rng)
	assert(not midFinish.Ok and midFinish.Reason == "BagFull" and wCap.ClaimedByUserId == nil, "Finish rejects BagFull & frees meteor")

	local u2FinishCap = MeteorService.StartCrackAtPosition(u2, wCap.Position, wCap.UID, 8204)
	assert(u2FinishCap.Ok and typeof(u2FinishCap.AttemptNonce) == "string", "u2 can claim meteor after u1 BagFull release")
	assert((MeteorService.FinishCrackAtPosition(u2, wCap.Position, wCap.UID, u2FinishCap.AttemptNonce :: string, 8205, rng).Ok), "u2 harvests preserved meteor cleanly")
end

local function runFiveMinuteEconomyPacingCheck(rng: Random): ()
	local uSim = -940003
	MeteorService.HandlePlotReleased(1, uSim)
	PlotService.ReleasePlotForUserId(uSim)
	DataService.EndMockSession(uSim)

	local tStart = 10000
	DataService.BeginMockSession(uSim, nil)
	DataService.CompleteMockSession(uSim, tStart)
	local profile = DataService.GetProfileByUserId(uSim) :: Types.PlayerProfileData
	assert((PlotService.AssignPlotForUserId(uSim, "S1PacingSim", profile, nil)), "Assign Plot 1 for 5-min loop simulation")

	-- 0–25s: Rescue Starter Meteor -> Incubate (15s) -> Hatch -> Place StarSlime in Pen_1 (2 Coins/s)
	local sOk, _, starterRaw = MeteorService.SpawnStarterMeteorForPlot(1, uSim, tStart + 2)
	assert(sOk and starterRaw ~= nil, "Starter meteor spawns for 5-min pacing sim")
	local starter = starterRaw :: MeteorService.ActiveMeteor

	local sCrack = MeteorService.StartCrackAtPosition(uSim, starter.Position, starter.UID, tStart + 4)
	assert(sCrack.Ok and typeof(sCrack.AttemptNonce) == "string", "Sim player starts starter meteor")
	local sFin = MeteorService.FinishCrackAtPosition(uSim, starter.Position, starter.UID, sCrack.AttemptNonce :: string, tStart + 6, rng)
	assert(sFin.Ok and typeof(sFin.ItemUID) == "string" and sFin.SpeciesId == "StarSlime", "Starter yields StarSlime Pod")
	local firstPodUID = sFin.ItemUID :: string

	assert((EconomyService.StartIncubateOnProfile(profile, "Incubator_1", firstPodUID, tStart + 8).Ok), "Incubate starter StarSlime")
	local firstHatch = EconomyService.HatchFromSlotOnProfile(profile, "Incubator_1", tStart + 23, rng)
	assert(firstHatch.Ok, "Starter StarSlime hatches at +23s (<< 90s target)")
	assert((EconomyService.PlaceInPenOnProfile(profile, "Pen_1", firstPodUID, tStart + 24).Ok), "Place StarSlime in Pen_1 at +24s")
	assertInvariants(profile, "5m sim step 1 (Pen_1 active)")

	local nowClock = tStart + 25
	local boughtTimes: { [Types.UpgradeId]: number } = {}
	local nodeCycle = 0
	local fedPen1Once = false
	local preToolTraits: { Types.MeteorTraitId } = { "Ember", "Frost" }
	local postToolTraits: { Types.MeteorTraitId } = { "Astral", "Frost", "Astral" }

	for round = 1, 20 do
		local traitPool = if profile.Upgrades["StarCracker"] == true then postToolTraits else preToolTraits
		local trait = traitPool[((round - 1) % #traitPool) + 1]
		nodeCycle = ((nodeCycle) % 6) + 1
		local nodeName = "MeteorNode_" .. tostring(nodeCycle)

		local wOk, _, wRaw = MeteorService.SpawnWildMeteorAtNode(nodeName, trait, nowClock)
		assert(wOk and wRaw ~= nil, "Sim wild meteor spawns on " .. nodeName)
		local wObj = wRaw :: MeteorService.ActiveMeteor

		local wStart = MeteorService.StartCrackAtPosition(uSim, wObj.Position, wObj.UID, nowClock + 2)
		assert(wStart.Ok and typeof(wStart.AttemptNonce) == "string", "Sim starts wild rescue round " .. tostring(round))
		local wFin = MeteorService.FinishCrackAtPosition(uSim, wObj.Position, wObj.UID, wStart.AttemptNonce :: string, nowClock + 4, rng)
		assert(wFin.Ok and typeof(wFin.ItemUID) == "string", "Sim finishes wild rescue round " .. tostring(round))
		local podUID = wFin.ItemUID :: string
		local speciesDef = CritterConfig.ById[wFin.SpeciesId :: Types.SpeciesId]

		nowClock += 6
		assert((EconomyService.StartIncubateOnProfile(profile, "Incubator_1", podUID, nowClock).Ok), "Sim incubates round " .. tostring(round))
		nowClock += speciesDef.HatchSeconds
		assert((EconomyService.HatchFromSlotOnProfile(profile, "Incubator_1", nowClock, rng).Ok), "Sim hatches round " .. tostring(round))
		nowClock += 2

		-- Place into open unlocked Pen slot if available; otherwise sell at Ranch Gate
		local placed = false
		for _, penSlotId in ipairs({ "Pen_1", "Pen_2", "Pen_3" }) do
			if EconomyService.IsUnlockedPenSlot(profile, penSlotId) and profile.Slots[penSlotId] == nil then
				assert((EconomyService.PlaceInPenOnProfile(profile, penSlotId, podUID, nowClock).Ok), "Sim places critter in " .. penSlotId)
				placed = true
				break
			end
		end
		if not placed then
			EconomyService.SettleProfileCoins(profile, nowClock)
			assert((EconomyService.SellCritterOnProfile(profile, podUID, nowClock).Ok), "Sim sells surplus hatched critter")
		else
			EconomyService.SettleProfileCoins(profile, nowClock)
		end

		-- Buy visible upgrades in order as soon as affordable (PenSlot_2 -> StarCracker -> Incubator_2 -> PenSlot_3)
		for _, upgradeId in ipairs(UpgradeConfig.OrderedIds) do
			if profile.Upgrades[upgradeId] ~= true then
				local uDef = UpgradeConfig.ById[upgradeId]
				if profile.Coins >= uDef.Cost then
					local buyRes = EconomyService.BuyUpgradeOnProfile(profile, upgradeId, nowClock)
					assert(buyRes.Ok, "Sim buys upgrade " .. upgradeId)
					boughtTimes[upgradeId] = nowClock - tStart
				end
				-- Keep ordered progression realistic so PenSlot_2 precedes StarCracker precedes Incubator_2
				break
			end
		end

		-- Feed Pen_1 critter once StarCracker is unlocked (or once Pen_1 feed is affordable alongside upgrades)
		if not fedPen1Once and profile.Upgrades["PenSlot_2"] == true and profile.Coins >= Constants.CRITTER_FEED_COST then
			local feedRes = EconomyService.FeedCritterInPenOnProfile(profile, "Pen_1", nowClock)
			assert(feedRes.Ok, "Sim feeds Pen_1 critter once affordable")
			fedPen1Once = true
		end

		assertInvariants(profile, "5m sim round " .. tostring(round))

		local allBought = profile.Upgrades["PenSlot_2"] == true
			and profile.Upgrades["StarCracker"] == true
			and profile.Upgrades["Incubator_2"] == true
			and profile.Upgrades["PenSlot_3"] == true
		local allPensFilled = profile.Slots["Pen_1"] ~= nil
			and profile.Slots["Pen_2"] ~= nil
			and profile.Slots["Pen_3"] ~= nil
		if allBought and allPensFilled and fedPen1Once then
			break
		end
	end

	-- Verify paced progression milestones & exact fed Pen rate
	assert(boughtTimes["PenSlot_2"] ~= nil and boughtTimes["PenSlot_2"] <= 90, "PenSlot_2 (60 Coins) unlocked within 90s pacing target")
	assert(boughtTimes["StarCracker"] ~= nil and boughtTimes["StarCracker"] <= 240, "StarCracker (120 Coins) unlocked within 4m")
	assert(boughtTimes["Incubator_2"] ~= nil and boughtTimes["Incubator_2"] <= 360, "Incubator_2 (180 Coins) unlocked within 6m")
	assert(boughtTimes["PenSlot_3"] ~= nil and boughtTimes["PenSlot_3"] <= 540, "PenSlot_3 (360 Coins) unlocked within full Stage 2B loop")
	assert(fedPen1Once and profile.Items[profile.Slots["Pen_1"]].FeedLevel == 1, "Pen_1 critter fed to level 1")
	assert(profile.Slots["Pen_1"] ~= nil and profile.Slots["Pen_2"] ~= nil and profile.Slots["Pen_3"] ~= nil, "All 3 habitat pen slots filled")

	local expectedRate = 0
	for _, slotId in ipairs({ "Pen_1", "Pen_2", "Pen_3" }) do
		local uid = profile.Slots[slotId]
		local item = profile.Items[uid]
		expectedRate += EconomyMath.GetCritterCoinsPerSecond(item.SpeciesId, item.Variant, item.FeedLevel)
	end
	assert(EconomyMath.CalculateActivePenRate(profile.Items) == expectedRate and expectedRate >= 8, "3-slot active pen rate matches exact integer sum including feed bonus")
	assert(findAnyItemInState(profile, "Incubating") == nil, "No dangling incubator left at sim end")

	MeteorService.HandlePlotReleased(1, uSim)
	PlotService.ReleasePlotForUserId(uSim)
	DataService.EndMockSession(uSim)
end

function Stage1VerificationSuite.RunSelfTest(): number
	local passed = 0
	local rng = Random.new(2026)
	local u1 = -940001
	local u2 = -940002

	local testOk, testErr = pcall(function()
		-- 1. Complete remote payload fuzzing + rate-bucket saturation matrix
		runRemoteFuzzAndRateMatrix()
		passed += 1

		-- Set up clean 2-player mock environment
		MeteorService.HandlePlotReleased(1, u1)
		MeteorService.HandlePlotReleased(2, u2)
		PlotService.ReleasePlotForUserId(u1)
		PlotService.ReleasePlotForUserId(u2)
		DataService.EndMockSession(u1)
		DataService.EndMockSession(u2)

		DataService.BeginMockSession(u1, nil)
		DataService.CompleteMockSession(u1, 8000)
		DataService.BeginMockSession(u2, nil)
		DataService.CompleteMockSession(u2, 8000)
		local p1 = DataService.GetProfileByUserId(u1) :: Types.PlayerProfileData
		local p2 = DataService.GetProfileByUserId(u2) :: Types.PlayerProfileData
		assert((PlotService.AssignPlotForUserId(u1, "S1Verify_1", p1, nil)), "Assign u1 to Plot 1")
		assert((PlotService.AssignPlotForUserId(u2, "S1Verify_2", p2, nil)), "Assign u2 to Plot 2")

		-- 2. 2-player meteor race, nonce hijack, >28-stud abandon & disconnect recovery
		runTwoPlayerMeteorAdversarial(u1, u2, rng)
		passed += 1

		-- 3. Cross-plot station isolation, upgrade spam & protected InPen sell prevention
		-- 4. Bag + Incubator reserved capacity deadlock guard across Start/Finish crack boundaries
		runCrossPlotAndInventoryGuards(u1, u2, rng)
		passed += 2

		-- Clean up 2-player plots before 5-min Plot_1 pacing sim runs
		MeteorService.HandlePlotReleased(1, u1)
		MeteorService.HandlePlotReleased(2, u2)
		PlotService.ReleasePlotForUserId(u1)
		PlotService.ReleasePlotForUserId(u2)
		DataService.EndMockSession(u1)
		DataService.EndMockSession(u2)

		-- 5. Full deterministic 5-minute economy loop simulation
		runFiveMinuteEconomyPacingCheck(rng)
		passed += 1
	end)

	-- Guaranteed cleanup of test plots, meteors, sessions, and buckets
	MeteorService.HandlePlotReleased(1, u1)
	MeteorService.HandlePlotReleased(2, u2)
	MeteorService.HandlePlotReleased(1, -940003)
	PlotService.ReleasePlotForUserId(u1)
	PlotService.ReleasePlotForUserId(u2)
	PlotService.ReleasePlotForUserId(-940003)
	DataService.EndMockSession(u1)
	DataService.EndMockSession(u2)
	DataService.EndMockSession(-940003)
	NetworkService.ClearPlayerBuckets(u1)
	NetworkService.ClearPlayerBuckets(u2)
	NetworkService.ClearPlayerBuckets(-940003)

	if not testOk then
		error(testErr)
	end

	return passed
end

return Stage1VerificationSuite
