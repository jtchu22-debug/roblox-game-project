--!strict
--[[
	Service/Suite: Stage3VerificationSuite (S3-04)
	Purpose: Automated server-side Stage 3 persistence failure-injection and 6-player full-server
	         exploit verification suite, plus a live Roblox API two-session persistence helper.
	Connections: Requires NetworkService, DataService, EconomyService, PlotService, MeteorService, and Shared configs.
	How to Test in Studio: Press Play (F5) with Constants.RUN_SELF_TESTS = true and run RunS304LivePersistenceCheck.luau.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Types = require(Shared:WaitForChild("Types"))

local ServicesFolder = script.Parent
local NetworkService = require(ServicesFolder:WaitForChild("NetworkService"))
local DataService = require(ServicesFolder:WaitForChild("DataService"))
local EconomyService = require(ServicesFolder:WaitForChild("EconomyService"))
local PlotService = require(ServicesFolder:WaitForChild("PlotService"))
local MeteorService = require(ServicesFolder:WaitForChild("MeteorService"))

local Stage3VerificationSuite = {
	Name = "Stage3VerificationSuite",
}

local TEST_USERS = { -950001, -950002, -950003, -950004, -950005, -950006, -950007, -950008 }
local SPECIES_CYCLE: { Types.SpeciesId } = {
	"StarSlime",
	"CinderPup",
	"FrostBeetle",
	"CometOwl",
	"NebulaFox",
	"SolarGolem",
}
local ALL_PEN_SLOTS = { "Pen_1", "Pen_2", "Pen_3", "Pen_4", "Pen_5" }

local function assertInvariants(profile: Types.PlayerProfileData, label: string): ()
	local ok, reason = EconomyService.ValidateProfileInvariants(profile)
	assert(ok, string.format("Economy invariant broken (%s): %s", label, tostring(reason)))
end

local function cleanupAllTestUsers(): ()
	for _, uid in ipairs(TEST_USERS) do
		PlotService.ReleasePlotForUserId(uid)
		MeteorService.HandlePlayerClosing(uid)
		DataService.EndSession(uid)
		NetworkService.ClearPlayerBuckets(uid)
	end
	DataService.ClearTestTrackingForUserIds(TEST_USERS)
	MeteorService.ResetTestAstralAndCooldownState()
end

local function populateRichStage3Profile(profile: Types.PlayerProfileData, index: number, baseCoins: number, baseClock: number, matureAt: number): ()
	local speciesId = SPECIES_CYCLE[((index - 1) % #SPECIES_CYCLE) + 1]
	profile.Coins = baseCoins
	profile.Upgrades["Incubator_2"] = true
	profile.Upgrades["BagCap_20"] = true
	profile.Upgrades["PenSlot_2"] = true
	profile.Upgrades["PenSlot_3"] = true
	profile.Upgrades["PenSlot_4"] = true
	profile.Upgrades["PenSlot_5"] = true
	profile.DiscoveredSpecies[speciesId] = true

	local penUid = "s3-pen-" .. tostring(index)
	profile.Items[penUid] = {
		UID = penUid,
		SpeciesId = speciesId,
		Variant = if index % 2 == 0 then "Radiant" else "Normal",
		State = "InPen",
		AssignedSlot = "Pen_1",
		PlantedAt = nil,
		MaturesAt = nil,
		CreatedAt = math.floor(baseClock),
		FeedLevel = if index % 2 == 1 then 1 else 0,
	}
	profile.Slots["Pen_1"] = penUid

	local incUid = "s3-inc-" .. tostring(index)
	profile.Items[incUid] = {
		UID = incUid,
		SpeciesId = "NebulaFox",
		Variant = "Normal",
		State = "Incubating",
		AssignedSlot = "Incubator_1",
		PlantedAt = math.floor(baseClock),
		MaturesAt = matureAt,
		CreatedAt = math.floor(baseClock),
		FeedLevel = 0,
	}
	profile.Slots["Incubator_1"] = incUid
end

local function runSixPlayerAdmissionAndReuseSuite(): ()
	local mockStore = DataService.CreateIsolatedMockStoreForTest("S304_Admit")
	local tBase = math.floor(workspace:GetServerTimeNow())
	local tFutureGuard = tBase + 60
	local u7 = TEST_USERS[7]

	-- Pre-save u7 with Coins, Pen_1 critter, and incubating pod timer
	assert(DataService.StartProfileSessionForUserId(u7, nil, { Store = mockStore, NowClock = tFutureGuard }), "Pre-save u7 session opens")
	local p7Pre = DataService.GetProfileByUserId(u7) :: Types.PlayerProfileData
	p7Pre.Coins = 615
	p7Pre.DiscoveredSpecies["NebulaFox"] = true
	p7Pre.Items["u7-pen"] = {
		UID = "u7-pen",
		SpeciesId = "NebulaFox",
		Variant = "Normal",
		State = "InPen",
		AssignedSlot = "Pen_1",
		PlantedAt = nil,
		MaturesAt = nil,
		CreatedAt = tBase,
		FeedLevel = 0,
	}
	p7Pre.Slots["Pen_1"] = "u7-pen"
	p7Pre.Items["u7-inc"] = {
		UID = "u7-inc",
		SpeciesId = "CinderPup",
		Variant = "Normal",
		State = "Incubating",
		AssignedSlot = "Incubator_1",
		PlantedAt = tBase,
		MaturesAt = tBase + 45,
		CreatedAt = tBase,
		FeedLevel = 0,
	}
	p7Pre.Slots["Incubator_1"] = "u7-inc"
	p7Pre.LastAccrualTimestamp = tFutureGuard
	DataService.EndSession(u7)
	assert(DataService.WaitForUserFinalSave(u7, 2), "Pre-save u7 final write confirmed")

	-- Open 6 concurrent ProfileStore.Mock sessions and assign Plot_1..Plot_6
	for i = 1, Constants.MAX_PLOTS_ALPHA do
		local uid = TEST_USERS[i]
		assert(DataService.StartProfileSessionForUserId(uid, nil, { Store = mockStore, NowClock = tFutureGuard }), "Open mock session u" .. tostring(i))
		local prof = DataService.GetProfileByUserId(uid) :: Types.PlayerProfileData
		local admOk, _, plotId = PlotService.HandlePlayerReadyAdmission(uid, "S3_" .. tostring(i), prof, nil)
		assert(admOk and plotId == i, string.format("u%d must be admitted onto Plot_%d", i, i))
		local stOk, _, stMeteor = MeteorService.SpawnStarterMeteorForPlot(i, uid, tBase)
		assert(stOk and stMeteor ~= nil and (stMeteor :: MeteorService.ActiveMeteor).NodeName == ("StarterNode_Plot_" .. tostring(i)), "Starter node wired for Plot_" .. tostring(i))
	end

	-- 7th player loads save then hits full-server NoFreePlot: clean reject + confirmed release save
	assert(DataService.StartProfileSessionForUserId(u7, nil, { Store = mockStore, NowClock = tFutureGuard }), "u7 session loads before admission check")
	local p7Full = DataService.GetProfileByUserId(u7) :: Types.PlayerProfileData
	local p7CoinsBeforeEnd = p7Full.Coins
	p7Full.LastAccrualTimestamp = tFutureGuard
	local fullOk, fullReason, fullPlotId = PlotService.HandlePlayerReadyAdmission(u7, "S3_7", p7Full, nil)
	assert(not fullOk and fullReason == "NoFreePlot" and fullPlotId == nil, "7th player rejected with NoFreePlot")
	assert(not DataService.IsUserIdReady(u7), "Rejected 7th player session closed immediately")
	assert(DataService.WaitForUserFinalSave(u7, 2), "Rejected 7th player releases/confirms lock cleanly")

	-- Release Plot_3 (u3 leaves), verify PlotRevision increments and DTO clears
	local revBefore3 = PlotService.BuildPublicPlotDTO(3).PlotRevision
	local relPlot = PlotService.ReleasePlotForUserId(TEST_USERS[3])
	assert(relPlot == 3, "u3 leaves Plot_3")
	DataService.EndSession(TEST_USERS[3])
	assert(DataService.WaitForUserFinalSave(TEST_USERS[3], 2), "u3 final save confirmed")
	local dtoCleared3 = PlotService.BuildPublicPlotDTO(3)
	assert(dtoCleared3.OwnerUserId == 0 and dtoCleared3.PlotRevision > revBefore3 and next(dtoCleared3.ActivePenVisuals) == nil, "Plot_3 DTO resets and increments PlotRevision")

	-- Now u7 rejoins cleanly onto Plot_3 with all persisted state intact
	assert(DataService.StartProfileSessionForUserId(u7, nil, { Store = mockStore, NowClock = tFutureGuard }), "u7 rejoins cleanly after Plot_3 opens")
	local p7Rejoined = DataService.GetProfileByUserId(u7) :: Types.PlayerProfileData
	assert(p7Rejoined.Coins == p7CoinsBeforeEnd and p7CoinsBeforeEnd == 615, "7th player retains exact saved Coins across NoFreePlot kick")
	assert(p7Rejoined.Items["u7-pen"] ~= nil and p7Rejoined.Items["u7-pen"].SpeciesId == "NebulaFox" and p7Rejoined.Slots["Pen_1"] == "u7-pen", "7th player Pen_1 NebulaFox intact")
	assert(p7Rejoined.Items["u7-inc"] ~= nil and p7Rejoined.Items["u7-inc"].MaturesAt == tBase + 45, "7th player incubating pod MaturesAt intact")

	local reAdmitOk, _, rePlotId = PlotService.HandlePlayerReadyAdmission(u7, "S3_7", p7Rejoined, nil)
	assert(reAdmitOk and rePlotId == 3, "u7 reuses freed Plot_3 cleanly")
	local dtoReused3 = PlotService.BuildPublicPlotDTO(3)
	assert(dtoReused3.OwnerUserId == u7 and dtoReused3.PlotRevision > dtoCleared3.PlotRevision, "Reused Plot_3 increments PlotRevision cleanly")

	cleanupAllTestUsers()
end

local function runPersistenceFailureAndSixPlayerFlushSuite(): ()
	local mockStore, mockStoreName = DataService.CreateIsolatedMockStoreWithMapForTest("S304_FailFlush")
	local tNow = workspace:GetServerTimeNow()
	local tFloor = math.floor(tNow)
	local tFutureGuard = tFloor + 120

	-- Pre-save uFail (-950008) cleanly, then verify forced load failure (nil & throw) kicks cleanly without blank overwrite
	local uFail = TEST_USERS[8]
	assert(DataService.StartProfileSessionForUserId(uFail, nil, { Store = mockStore, NowClock = tFutureGuard }), "Save initial uFail profile")
	local pFailPre = DataService.GetProfileByUserId(uFail) :: Types.PlayerProfileData
	pFailPre.Coins = 411
	pFailPre.LastAccrualTimestamp = tFutureGuard
	DataService.EndSession(uFail)
	assert(DataService.WaitForUserFinalSave(uFail, 2), "uFail initial save confirmed")

	-- Open 6 concurrent players (u1..u6) with active force-load watcher on u2 and rich state on all 6
	local kickCounts: { [number]: number } = {}
	for i = 1, Constants.MAX_PLOTS_ALPHA do
		local uid = TEST_USERS[i]
		kickCounts[uid] = 0
		assert(
			DataService.StartProfileSessionForUserId(uid, nil, {
				Store = mockStore,
				NowClock = tNow,
				OnKick = function(_reason: string)
					kickCounts[uid] += 1
				end,
			}),
			"Suite 2 open session u" .. tostring(i)
		)
		local prof = DataService.GetProfileByUserId(uid) :: Types.PlayerProfileData
		populateRichStage3Profile(prof, i, 100 * i, tNow, tFloor + 120 + i)
		prof.LastAccrualTimestamp = tNow - 10
		assertInvariants(prof, "Suite 2 populate u" .. tostring(i))
	end

	-- Forced load failures while 6 players stay online
	local failKicks = 0
	local nilStore = {
		Name = "S304_NilLoad",
		StartSessionAsync = function()
			return nil
		end,
	}
	local okNil, reasonNil = DataService.StartProfileSessionForUserId(uFail, nil, {
		Store = nilStore,
		NowClock = tFutureGuard,
		OnKick = function()
			failKicks += 1
		end,
	})
	assert(not okNil and reasonNil == "LoadFailed" and failKicks == 1, "Nil StartSessionAsync fails closed & kicks cleanly")
	assert(not DataService.IsUserIdReady(uFail) and DataService.GetProfileByUserId(uFail) == nil, "Nil failure never marks Ready")

	local throwStore = {
		Name = "S304_ThrowLoad",
		StartSessionAsync = function()
			error("S304 Simulated DataStore 503")
		end,
	}
	local okThrow, reasonThrow = DataService.StartProfileSessionForUserId(uFail, nil, {
		Store = throwStore,
		NowClock = tFutureGuard,
		OnKick = function()
			failKicks += 1
		end,
	})
	assert(not okThrow and reasonThrow == "LoadFailed" and failKicks == 2, "Throwing StartSessionAsync fails closed & kicks cleanly")
	assert(DataService.StartProfileSessionForUserId(uFail, nil, { Store = mockStore, NowClock = tFutureGuard }), "uFail loads after DataStore outage recovery")
	assert((DataService.GetProfileByUserId(uFail) :: Types.PlayerProfileData).Coins == 411, "Forced load failures preserved uFail Coins=411")
	DataService.EndSession(uFail)
	assert(DataService.WaitForUserFinalSave(uFail, 2), "uFail cleanup save confirmed")

	-- External Force-Load lock theft on u2 while online: triggers OnPlayerClosing kick + final Coin settle + fast <1s rejoin
	local u2 = TEST_USERS[2]
	local u2InitialCoins = (DataService.GetProfileByUserId(u2) :: Types.PlayerProfileData).Coins
	local mockMap = DataService.GetUserMockStoreMapForTest(mockStoreName)
	local entry2 = mockMap[Constants.PROFILE_KEY_PREFIX .. tostring(u2)]
	assert(entry2 ~= nil, "mockMap holds active u2 entry")
	entry2.Data.MetaData.ForceLoadSession = { 888888, "RemoteForceLoadJob" }
	assert(DataService.TriggerTestProfileSave(u2), "Trigger autosave on u2 to detect ForceLoadSession")

	local forceDeadline = os.clock() + 3
	while DataService.IsUserIdReady(u2) and os.clock() < forceDeadline do
		task.wait()
	end
	assert(not DataService.IsUserIdReady(u2) and DataService.GetProfileByUserId(u2) == nil, "Force-Load clears u2 readiness")
	assert(kickCounts[u2] == 1, "Force-Load triggers clean kick on u2")
	assert(DataService.WaitForUserFinalSave(u2, 2), "Force-Load confirms final write on u2")
	local u2FinOk, _, u2SettledCoins = DataService.GetLastClosingFinalSaveInfo(u2)
	assert(u2FinOk and u2SettledCoins ~= nil and (u2SettledCoins :: number) > u2InitialCoins, "Force-Load settles unaccrued u2 Coins before releasing lock")

	local tRejoin2 = os.clock()
	assert(DataService.StartProfileSessionForUserId(u2, nil, { Store = mockStore, NowClock = workspace:GetServerTimeNow() }), "u2 rejoins cleanly after Force-Load release")
	assert((os.clock() - tRejoin2) < 1.0, "u2 rejoins without 5s stall after Force-Load release")
	local p2Rejoined = DataService.GetProfileByUserId(u2) :: Types.PlayerProfileData
	assert(p2Rejoined.Coins == u2SettledCoins, "u2 reload matches exact Force-Load settled Coins")
	p2Rejoined.LastAccrualTimestamp = workspace:GetServerTimeNow() - 10

	-- 6-player concurrent BindToClose shutdown flush: settles all 6, confirms all 6, and preserves exact state across reload
	local preFlushCoins: { [number]: number } = {}
	for i = 1, Constants.MAX_PLOTS_ALPHA do
		local uid = TEST_USERS[i]
		local p = DataService.GetProfileByUserId(uid) :: Types.PlayerProfileData
		preFlushCoins[uid] = p.Coins
		p.LastAccrualTimestamp = workspace:GetServerTimeNow() - 10
	end

	assert(DataService.FlushActiveProfileSessions(4), "6-player concurrent FlushActiveProfileSessions confirms all final writes")

	local expectedAfterFlush: { [number]: { Coins: number, Rev: number } } = {}
	for i = 1, Constants.MAX_PLOTS_ALPHA do
		local uid = TEST_USERS[i]
		assert(not DataService.IsUserIdReady(uid), "Flush clears session readiness for u" .. tostring(i))
		local finOk, finRev, finCoins = DataService.GetLastClosingFinalSaveInfo(uid)
		assert(finOk and finCoins ~= nil and (finCoins :: number) > preFlushCoins[uid], "u" .. tostring(i) .. " settled unaccrued Coins during flush")
		expectedAfterFlush[uid] = {
			Coins = finCoins :: number,
			Rev = finRev,
		}
	end

	for i = 1, Constants.MAX_PLOTS_ALPHA do
		local uid = TEST_USERS[i]
		assert(DataService.StartProfileSessionForUserId(uid, nil, { Store = mockStore, NowClock = tFutureGuard }), "Reload u" .. tostring(i) .. " after 6-player flush")
		local reloaded = DataService.GetProfileByUserId(uid) :: Types.PlayerProfileData
		local exp = expectedAfterFlush[uid]
		assert(reloaded.Coins == exp.Coins and reloaded.Revision == exp.Rev, "u" .. tostring(i) .. " exact Coins & Revision survived 6-player flush")
		assert(reloaded.Upgrades["BagCap_20"] == true and reloaded.Upgrades["PenSlot_5"] == true, "u" .. tostring(i) .. " upgrades preserved")
		assert(reloaded.Items["s3-pen-" .. tostring(i)] ~= nil and reloaded.Slots["Pen_1"] == ("s3-pen-" .. tostring(i)), "u" .. tostring(i) .. " Pen_1 critter preserved")
		assert(reloaded.Items["s3-inc-" .. tostring(i)] ~= nil and reloaded.Items["s3-inc-" .. tostring(i)].MaturesAt == (tFloor + 120 + i), "u" .. tostring(i) .. " MaturesAt timer preserved")
		assertInvariants(reloaded, "Suite 2 reloaded u" .. tostring(i))
	end

	cleanupAllTestUsers()
end

local function runOfflineMaturesBoundarySuite(rng: Random): ()
	local mockStore = DataService.CreateIsolatedMockStoreForTest("S304_Offline")
	local uid = TEST_USERS[1]
	local t0 = math.floor(workspace:GetServerTimeNow())
	local tFutureGuard = t0 + 120

	assert(DataService.StartProfileSessionForUserId(uid, nil, { Store = mockStore, NowClock = tFutureGuard }), "Offline test initial join")
	local prof = DataService.GetProfileByUserId(uid) :: Types.PlayerProfileData
	prof.Coins = 250
	prof.Upgrades["Incubator_2"] = true
	prof.DiscoveredSpecies["SolarGolem"] = true
	prof.Items["off-pen"] = {
		UID = "off-pen",
		SpeciesId = "SolarGolem",
		Variant = "Normal",
		State = "InPen",
		AssignedSlot = "Pen_1",
		PlantedAt = nil,
		MaturesAt = nil,
		CreatedAt = t0,
		FeedLevel = 0,
	}
	prof.Slots["Pen_1"] = "off-pen"
	prof.Items["off-inc-1"] = {
		UID = "off-inc-1",
		SpeciesId = "NebulaFox",
		Variant = "Normal",
		State = "Incubating",
		AssignedSlot = "Incubator_1",
		PlantedAt = t0,
		MaturesAt = t0 + 45,
		CreatedAt = t0,
		FeedLevel = 0,
	}
	prof.Slots["Incubator_1"] = "off-inc-1"
	prof.Items["off-inc-2"] = {
		UID = "off-inc-2",
		SpeciesId = "SolarGolem",
		Variant = "Normal",
		State = "Incubating",
		AssignedSlot = "Incubator_2",
		PlantedAt = t0,
		MaturesAt = t0 + 75,
		CreatedAt = t0,
		FeedLevel = 0,
	}
	prof.Slots["Incubator_2"] = "off-inc-2"
	prof.LastAccrualTimestamp = tFutureGuard
	assertInvariants(prof, "Suite 3 initial")

	DataService.EndSession(uid)
	assert(DataService.WaitForUserFinalSave(uid, 2), "Suite 3 first write confirmed")

	-- Rejoin at -1s (t0 + 44) -> zero offline Coins, Incubator_1 NotMature; at 0s (t0 + 45) -> Incubator_1 hatches, Incubator_2 NotMature
	assert(DataService.StartProfileSessionForUserId(uid, nil, { Store = mockStore, NowClock = t0 + 44 }), "Suite 3 rejoin at -1s")
	local pMinus1 = DataService.GetProfileByUserId(uid) :: Types.PlayerProfileData
	assert(pMinus1.Coins == 250, "Offline duration pays 0 extra Coins on login")
	assert(not EconomyService.SettleProfileCoins(pMinus1, t0 + 44), "Zero offline accrual immediately at login")

	local hMinus1 = EconomyService.HatchFromSlotOnProfile(pMinus1, "Incubator_1", t0 + 44, rng)
	assert(not hMinus1.Ok and hMinus1.Reason == "NotMature", "1s before MaturesAt stays NotMature across real rejoin")

	local hExact = EconomyService.HatchFromSlotOnProfile(pMinus1, "Incubator_1", t0 + 45, rng)
	assert(hExact.Ok and hExact.SpeciesId == "NebulaFox" and pMinus1.DiscoveredSpecies["NebulaFox"] == true, "Exact MaturesAt hatches NebulaFox")
	local hInc2Early = EconomyService.HatchFromSlotOnProfile(pMinus1, "Incubator_2", t0 + 45, rng)
	assert(not hInc2Early.Ok and hInc2Early.Reason == "NotMature", "Incubator_2 still NotMature at t0+45")

	pMinus1.LastAccrualTimestamp = tFutureGuard
	DataService.EndSession(uid)
	assert(DataService.WaitForUserFinalSave(uid, 2), "Suite 3 second write confirmed")

	-- Rejoin 12 hours later -> zero offline Coins + Incubator_2 matures cleanly
	local tTwelveHoursLater = t0 + 75 + 12 * 3600
	assert(DataService.StartProfileSessionForUserId(uid, nil, { Store = mockStore, NowClock = tTwelveHoursLater }), "Suite 3 rejoin +12h later")
	local pPlus12h = DataService.GetProfileByUserId(uid) :: Types.PlayerProfileData
	assert(pPlus12h.Coins == 250, "12-hour offline rejoin pays 0 offline Coins")
	local hInc2Late = EconomyService.HatchFromSlotOnProfile(pPlus12h, "Incubator_2", tTwelveHoursLater, rng)
	assert(hInc2Late.Ok and hInc2Late.SpeciesId == "SolarGolem", "Incubator_2 matures +12h later cleanly")
	assertInvariants(pPlus12h, "Suite 3 post-12h hatch")

	cleanupAllTestUsers()
end

local function runSixPlayerStationIsolationSuite(): ()
	for i = 1, Constants.MAX_PLOTS_ALPHA do
		local uid = TEST_USERS[i]
		DataService.BeginMockSession(uid, nil)
		DataService.CompleteMockSession(uid, 7000)
		local p = DataService.GetProfileByUserId(uid) :: Types.PlayerProfileData
		assert((PlotService.AssignPlotForUserId(uid, "Iso_" .. tostring(i), p, nil)), "Suite 4 assign Plot_" .. tostring(i))
	end

	local ownSpecs = {
		{ Kind = "Incubator", Target = "Incubator_1" },
		{ Kind = "Pen", Target = "Pen_1" },
		{ Kind = "Pen", Target = "Pen_5" },
		{ Kind = "SellStand", Target = "SellStand" },
		{ Kind = "UpgradePad", Target = "BagCap_20" },
		{ Kind = "UpgradePad", Target = "PenSlot_5" },
	}
	local hubSpecs = {
		{ Kind = "LureStand", Target = "LureStand" },
		{ Kind = "UpgradePad", Target = "FrostCracker" },
		{ Kind = "UpgradePad", Target = "StarCracker" },
	}
	local root = PlotService.GetGreyboxRoot()
	local hubArrival = ((root:FindFirstChild("CentralHub") :: Model):FindFirstChild("HubArrivalPad") :: BasePart)

	for i = 1, Constants.MAX_PLOTS_ALPHA do
		local uid = TEST_USERS[i]
		local ownIncAnchor = PlotService.ResolveStationAnchor(i, "Incubator", "Incubator_1") :: BasePart

		for _, spec in ipairs(ownSpecs) do
			local anchor = PlotService.ResolveStationAnchor(i, spec.Kind, spec.Target) :: BasePart
			assert((PlotService.AuthorizeStationAtPosition(uid, anchor.Position, spec.Kind, spec.Target)), "Owner authorized at own " .. spec.Target)
			local hubFromRanchOk, hubFromRanchReason = PlotService.AuthorizeStationAtPosition(uid, hubArrival.Position, spec.Kind, spec.Target)
			assert(not hubFromRanchOk and hubFromRanchReason == "OutOfRange", "Hub pos blocked for Ranch " .. spec.Target)
		end

		for _, hSpec in ipairs(hubSpecs) do
			local hAnchor = PlotService.ResolveHubStationAnchor(hSpec.Kind, hSpec.Target) :: BasePart
			assert((PlotService.AuthorizeStationAtPosition(uid, hAnchor.Position, hSpec.Kind, hSpec.Target)), "Owner authorized at Hub " .. hSpec.Target)
			local ranchToHubOk, ranchToHubReason = PlotService.AuthorizeStationAtPosition(uid, ownIncAnchor.Position, hSpec.Kind, hSpec.Target)
			assert(not ranchToHubOk and ranchToHubReason == "OutOfRange", "Ranch pos blocked for Hub " .. hSpec.Target)
		end

		-- All 30 cross-plot unauthorized checks
		for j = 1, Constants.MAX_PLOTS_ALPHA do
			if j ~= i then
				for _, targetSpec in ipairs({
					{ Kind = "Incubator", Target = "Incubator_1" },
					{ Kind = "Pen", Target = "Pen_1" },
					{ Kind = "SellStand", Target = "SellStand" },
					{ Kind = "UpgradePad", Target = "PenSlot_5" },
				}) do
					local otherAnchor = PlotService.ResolveStationAnchor(j, targetSpec.Kind, targetSpec.Target) :: BasePart
					local crossOk, crossReason = PlotService.AuthorizeStationAtPosition(uid, otherAnchor.Position, targetSpec.Kind, targetSpec.Target)
					assert(not crossOk and crossReason == "OutOfRange", string.format("u%d blocked from Plot_%d %s", i, j, targetSpec.Target))
				end
			end
		end
	end

	-- Unassigned u7 blocked everywhere
	local p1Inc = PlotService.ResolveStationAnchor(1, "Incubator", "Incubator_1") :: BasePart
	local hubLure = PlotService.ResolveHubStationAnchor("LureStand", "LureStand") :: BasePart
	local u7RanchOk, u7RanchReason = PlotService.AuthorizeStationAtPosition(TEST_USERS[7], p1Inc.Position, "Incubator", "Incubator_1")
	local u7HubOk, u7HubReason = PlotService.AuthorizeStationAtPosition(TEST_USERS[7], hubLure.Position, "LureStand", "LureStand")
	assert(not u7RanchOk and u7RanchReason == "NoAssignedPlot", "Unassigned u7 blocked at Ranch")
	assert(not u7HubOk and u7HubReason == "NoAssignedPlot", "Unassigned u7 blocked at Hub")

	cleanupAllTestUsers()
end

local function runSixPlayerCraterRaceNavAndLureSuite(rng: Random): ()
	for i = 1, Constants.MAX_PLOTS_ALPHA do
		local uid = TEST_USERS[i]
		DataService.BeginMockSession(uid, nil)
		DataService.CompleteMockSession(uid, 9000)
		local p = DataService.GetProfileByUserId(uid) :: Types.PlayerProfileData
		p.Upgrades["FrostCracker"] = true
		p.Upgrades["StarCracker"] = true
		p.Coins = 500
		assert((PlotService.AssignPlotForUserId(uid, "Race_" .. tostring(i), p, nil)), "Suite 5 assign Plot_" .. tostring(i))
	end

	-- 6-player starter isolation (all 30 cross-owner checks rejected)
	local starters: { MeteorService.ActiveMeteor } = {}
	for i = 1, Constants.MAX_PLOTS_ALPHA do
		local sOk, _, sRaw = MeteorService.SpawnStarterMeteorForPlot(i, TEST_USERS[i], 9001)
		assert(sOk and sRaw ~= nil, "Suite 5 spawn starter Plot_" .. tostring(i))
		starters[i] = sRaw :: MeteorService.ActiveMeteor
	end
	for i = 1, Constants.MAX_PLOTS_ALPHA do
		for j = 1, Constants.MAX_PLOTS_ALPHA do
			if j ~= i then
				local badStart = MeteorService.StartCrackAtPosition(TEST_USERS[i], starters[j].Position, starters[j].UID, 9002)
				assert(not badStart.Ok and badStart.Reason == "NotStarterOwner", string.format("u%d blocked from Plot_%d starter", i, j))
			end
		end
	end

	-- 6-player wild Astral claim race, AttemptNonce hijack defense, & navigation OnBeforeNavigate claim cancellation
	local wOk, _, wRaw = MeteorService.SpawnWildMeteorAtNode("MeteorNode_5", "Astral", 9005)
	assert(wOk and wRaw ~= nil, "Suite 5 wild Astral meteor spawns")
	local w1 = wRaw :: MeteorService.ActiveMeteor

	local s1 = MeteorService.StartCrackAtPosition(TEST_USERS[1], w1.Position, w1.UID, 9006)
	assert(s1.Ok and typeof(s1.AttemptNonce) == "string", "u1 claims wild Astral meteor")
	local u1Nonce = s1.AttemptNonce :: string

	for j = 2, Constants.MAX_PLOTS_ALPHA do
		local raceFail = MeteorService.StartCrackAtPosition(TEST_USERS[j], w1.Position, w1.UID, 9006)
		assert(not raceFail.Ok and raceFail.Reason == "MeteorAlreadyClaimed", "u" .. tostring(j) .. " blocked by u1 claim")
		local hijackFail = MeteorService.FinishCrackAtPosition(TEST_USERS[j], w1.Position, w1.UID, u1Nonce, 9007.5, rng)
		assert(not hijackFail.Ok and hijackFail.Reason == "InvalidClaim", "u" .. tostring(j) .. " cannot hijack u1 AttemptNonce")
	end
	assert(w1.ClaimedByUserId == TEST_USERS[1], "u1 claim remains intact after 5 hijack attempts")

	-- Navigation during active crack triggers OnBeforeNavigate claim cancellation and lets u2 win the meteor
	local navigatedCFrame: CFrame? = nil
	local navRes = PlotService.ExecuteNavigationForUserId(TEST_USERS[1], "Hub", function(destCFrame: CFrame)
		navigatedCFrame = destCFrame
	end)
	assert(navRes.Ok and navRes.Target == "Hub" and navigatedCFrame ~= nil and math.abs((navigatedCFrame :: CFrame).Position.X) < 10, "u1 navigation to Hub succeeds")
	assert(w1.ClaimedByUserId == nil, "Navigation cancels u1 mid-crack meteor claim via OnBeforeNavigate")
	local u1PostNavFin = MeteorService.FinishCrackAtPosition(TEST_USERS[1], w1.Position, w1.UID, u1Nonce, 9008, rng)
	assert(not u1PostNavFin.Ok and u1PostNavFin.Reason == "InvalidClaim", "Cancelled u1 nonce fails FinishCrack cleanly")

	local s2 = MeteorService.StartCrackAtPosition(TEST_USERS[2], w1.Position, w1.UID, 9008.2)
	assert(s2.Ok and typeof(s2.AttemptNonce) == "string", "u2 takes unlocked wild meteor after u1 navigated")
	assert(MeteorService.FinishCrackAtPosition(TEST_USERS[2], w1.Position, w1.UID, s2.AttemptNonce :: string, 9009.5, rng).Ok, "u2 finishes reclaimed wild meteor cleanly")

	-- 6-player Ridge Frost Lure saturation & disconnect recovery
	MeteorService.ResetTestAstralAndCooldownState()
	local function lureSpawnerWrapper(uid: number, dname: string, trait: Types.MeteorTraitId, clk: number): (boolean, string)
		local okSpawn, rsnSpawn = MeteorService.SpawnLuredMeteorForPlayer(uid, dname, trait, clk)
		return okSpawn, rsnSpawn
	end

	local lures: { MeteorService.ActiveMeteor } = {}
	for i = 1, 4 do
		local uid = TEST_USERS[i]
		local p = DataService.GetProfileByUserId(uid) :: Types.PlayerProfileData
		local lOk, _, lRaw = MeteorService.SpawnLuredMeteorForPlayer(uid, "Race_" .. tostring(i), "Frost", 9100)
		assert(lOk and lRaw ~= nil, "Lure #" .. tostring(i) .. " spawns on North Ridge")
		lures[i] = lRaw :: MeteorService.ActiveMeteor
		p.Coins -= Constants.FROST_LURE_COST
	end

	local p5 = DataService.GetProfileByUserId(TEST_USERS[5]) :: Types.PlayerProfileData
	local p5CoinsBefore = p5.Coins
	local fullRidgeLure = EconomyService.UseFrostLureOnProfile(p5, TEST_USERS[5], "Race_5", 9101, lureSpawnerWrapper)
	assert(not fullRidgeLure.Ok and fullRidgeLure.Reason == "NoFreeMeteorNode" and p5.Coins == p5CoinsBefore, "u5 rejected on saturated Ridge with 0 Coins debited")

	for j = 2, Constants.MAX_PLOTS_ALPHA do
		local stealRes = MeteorService.StartCrackAtPosition(TEST_USERS[j], lures[1].Position, lures[1].UID, 9101.2)
		assert(not stealRes.Ok and stealRes.Reason == "NotLureOwner", "u" .. tostring(j) .. " blocked from u1 personal Frost Lure")
	end

	-- u1 disconnects -> despawns u1's personal lure, freeing a Ridge slot for u5
	PlotService.ReleasePlotForUserId(TEST_USERS[1])
	MeteorService.HandlePlayerClosing(TEST_USERS[1])

	local u5LureSpawned: MeteorService.ActiveMeteor? = nil
	local u5Retry = EconomyService.UseFrostLureOnProfile(p5, TEST_USERS[5], "Race_5", 9102, function(uid: number, dname: string, trait: Types.MeteorTraitId, clk: number): (boolean, string)
		local okSpawn, rsnSpawn, mObj = MeteorService.SpawnLuredMeteorForPlayer(uid, dname, trait, clk)
		u5LureSpawned = mObj
		return okSpawn, rsnSpawn
	end)
	assert(u5Retry.Ok and u5LureSpawned ~= nil and p5.Coins == p5CoinsBefore - Constants.FROST_LURE_COST, "u5 spawns Frost Lure cleanly after u1 disconnect")
	local u5Lure = u5LureSpawned :: MeteorService.ActiveMeteor
	local u5Start = MeteorService.StartCrackAtPosition(TEST_USERS[5], u5Lure.Position, u5Lure.UID, 9103)
	assert(u5Start.Ok and typeof(u5Start.AttemptNonce) == "string", "u5 claims own Frost Lure")
	assert(MeteorService.FinishCrackAtPosition(TEST_USERS[5], u5Lure.Position, u5Lure.UID, u5Start.AttemptNonce :: string, 9104.5, rng).Ok, "u5 harvests own Frost Lure cleanly")

	cleanupAllTestUsers()
end

local function runSixPlayerRateAndPublicDtoAuditSuite(): ()
	local capacities: { { Remote: string, Cap: number } } = {
		{ Remote = Constants.REMOTE_NAMES.RequestInitialSnapshot, Cap = 2 },
		{ Remote = Constants.REMOTE_NAMES.RequestStartCrack, Cap = 4 },
		{ Remote = Constants.REMOTE_NAMES.RequestFinishCrack, Cap = 4 },
		{ Remote = Constants.REMOTE_NAMES.RequestPlotAction, Cap = 8 },
		{ Remote = Constants.REMOTE_NAMES.RequestBuyUpgrade, Cap = 3 },
		{ Remote = Constants.REMOTE_NAMES.RequestNavigate, Cap = 2 },
	}
	local t0 = 5000

	for i = 1, Constants.MAX_PLOTS_ALPHA do
		local uid = TEST_USERS[i]
		NetworkService.ClearPlayerBuckets(uid)
		DataService.BeginMockSession(uid, nil)
		DataService.CompleteMockSession(uid, 9500)
		local p = DataService.GetProfileByUserId(uid) :: Types.PlayerProfileData
		p.Coins = 12345
		p.Upgrades["PenSlot_2"] = true
		p.Upgrades["PenSlot_3"] = true
		p.Upgrades["PenSlot_4"] = true
		p.Upgrades["PenSlot_5"] = true
		for sIdx, slotId in ipairs(ALL_PEN_SLOTS) do
			local itemUid = string.format("dto-%d-%d", i, sIdx)
			p.Items[itemUid] = {
				UID = itemUid,
				SpeciesId = SPECIES_CYCLE[((i + sIdx) % #SPECIES_CYCLE) + 1],
				Variant = if (i + sIdx) % 2 == 0 then "Radiant" else "Normal",
				State = "InPen",
				AssignedSlot = slotId,
				PlantedAt = nil,
				MaturesAt = nil,
				CreatedAt = 9500,
				FeedLevel = (i + sIdx) % 2,
			}
			p.Slots[slotId] = itemUid
		end
		assert((PlotService.AssignPlotForUserId(uid, "Dto_" .. tostring(i), p, nil)), "Suite 6 assign Plot_" .. tostring(i))
	end

	-- u1 saturates all 6 inbound remotes (with hostile values rejected too); u2..u6 keep independent full bursts
	local u1 = TEST_USERS[1]
	assert(not NetworkService.ValidateInboundPayload(Constants.REMOTE_NAMES.RequestNavigate, "Moon"), "Hostile navigate target rejected")
	assert(not NetworkService.ValidateInboundPayload(Constants.REMOTE_NAMES.RequestBuyUpgrade, 0 / 0), "NaN upgradeId rejected")
	for _, entry in ipairs(capacities) do
		for _ = 1, entry.Cap do
			assert(NetworkService.CheckAndConsumeRateLimit(u1, entry.Remote, t0), "u1 consumes " .. entry.Remote)
		end
		assert(not NetworkService.CheckAndConsumeRateLimit(u1, entry.Remote, t0), "u1 saturated on " .. entry.Remote)
	end

	for i = 2, Constants.MAX_PLOTS_ALPHA do
		local uid = TEST_USERS[i]
		for _, entry in ipairs(capacities) do
			for b = 1, entry.Cap do
				assert(NetworkService.CheckAndConsumeRateLimit(uid, entry.Remote, t0), string.format("u%d independent bucket %s #%d", i, entry.Remote, b))
			end
			assert(not NetworkService.CheckAndConsumeRateLimit(uid, entry.Remote, t0), "u" .. tostring(i) .. " hits own limit after Cap")
		end
	end

	-- Audit full 6-plot PublicPlotDTO snapshot (30 active critters, zero private fields leaked)
	local allDtos = PlotService.BuildAllPublicPlotDTOs()
	assert(#allDtos == Constants.MAX_PLOTS_ALPHA, "Expected 6 PublicPlotDTO entries")
	local totalCritters = 0
	for plotId, dto in ipairs(allDtos) do
		assert(dto.PlotId == plotId and dto.OwnerUserId == TEST_USERS[plotId], "DTO PlotId/Owner matches")
		assert((dto :: any).Coins == nil, "DTO strips Coins")
		assert((dto :: any).Items == nil, "DTO strips Items")
		assert((dto :: any).PendingFraction == nil, "DTO strips PendingFraction")
		assert((dto :: any).LastAccrualTimestamp == nil, "DTO strips LastAccrualTimestamp")
		assert((dto :: any).SchemaVersion == nil, "DTO strips SchemaVersion")
		for _, slotId in ipairs(ALL_PEN_SLOTS) do
			assert(dto.ActivePenVisuals[slotId] ~= nil, string.format("Plot_%d exposes %s visual", plotId, slotId))
			totalCritters += 1
		end
	end
	assert(totalCritters == 30, "All 30 active pen critters exposed across 6 occupied plots")

	cleanupAllTestUsers()
end

function Stage3VerificationSuite.RunLiveApiPersistenceCheck(phase: DataService.SmokeTestPhase?, baseTestUserId: number?): (boolean, string)
	-- Ensure EconomyService's OnBeforeSave hook is registered even when invoked from a Command Bar require() cache.
	EconomyService:Init()

	local runPhase: DataService.SmokeTestPhase = if phase ~= nil then phase else "RoundTrip"
	local uA = if baseTestUserId ~= nil then baseTestUserId else -919901
	local uB = uA - 1

	local storeOk, liveStoreOrErr, storeName = DataService.GetLiveDevSmokeStore()
	if not storeOk then
		return false, tostring(liveStoreOrErr)
	end
	local smokeStore = liveStoreOrErr
	local keyA = Constants.PROFILE_KEY_PREFIX .. tostring(uA)
	local keyB = Constants.PROFILE_KEY_PREFIX .. tostring(uB)
	local t0 = math.floor(workspace:GetServerTimeNow())

	local writtenCoinsA = -1
	local writtenRevA = -1
	local writtenCoinsB = -1
	local writtenRevB = -1

	if runPhase == "RoundTrip" or runPhase == "Write" then
		DataService.EndSession(uA)
		DataService.EndSession(uB)
		DataService.ClearTestTrackingForUserIds({ uA, uB })

		if smokeStore.RemoveAsync ~= nil then
			local anyStore = smokeStore :: any
			pcall(function()
				anyStore:RemoveAsync(keyA)
				anyStore:RemoveAsync(keyB)
			end)
		end

		local joinOkA, joinReasonA = DataService.StartProfileSessionForUserId(uA, nil, {
			Store = smokeStore,
			NowClock = t0,
		})
		if not joinOkA then
			return false, "S304 Write initial load failed for uA: " .. joinReasonA
		end
		local joinOkB, joinReasonB = DataService.StartProfileSessionForUserId(uB, nil, {
			Store = smokeStore,
			NowClock = t0,
		})
		if not joinOkB then
			DataService.FlushActiveProfileSessions(5)
			return false, "S304 Write initial load failed for uB: " .. joinReasonB
		end

		local profA = DataService.GetProfileByUserId(uA) :: Types.PlayerProfileData
		profA.Coins = 300
		profA.LastAccrualTimestamp = t0 - 10
		profA.Upgrades["Incubator_2"] = true
		profA.Upgrades["BagCap_20"] = true
		profA.Upgrades["PenSlot_2"] = true
		profA.Upgrades["PenSlot_3"] = true
		profA.Upgrades["PenSlot_4"] = true
		profA.Upgrades["PenSlot_5"] = true
		profA.DiscoveredSpecies["CinderPup"] = true
		profA.DiscoveredSpecies["NebulaFox"] = true
		profA.Items["s304-pen1"] = {
			UID = "s304-pen1",
			SpeciesId = "CinderPup",
			Variant = "Normal",
			State = "InPen",
			AssignedSlot = "Pen_1",
			PlantedAt = nil,
			MaturesAt = nil,
			CreatedAt = t0,
			FeedLevel = 1,
		}
		profA.Slots["Pen_1"] = "s304-pen1"
		profA.Items["s304-pen5"] = {
			UID = "s304-pen5",
			SpeciesId = "NebulaFox",
			Variant = "Radiant",
			State = "InPen",
			AssignedSlot = "Pen_5",
			PlantedAt = nil,
			MaturesAt = nil,
			CreatedAt = t0,
			FeedLevel = 0,
		}
		profA.Slots["Pen_5"] = "s304-pen5"
		profA.Items["s304-incA"] = {
			UID = "s304-incA",
			SpeciesId = "FrostBeetle",
			Variant = "Normal",
			State = "Incubating",
			AssignedSlot = "Incubator_1",
			PlantedAt = t0,
			MaturesAt = t0 + 45,
			CreatedAt = t0,
			FeedLevel = 0,
		}
		profA.Slots["Incubator_1"] = "s304-incA"

		local profB = DataService.GetProfileByUserId(uB) :: Types.PlayerProfileData
		profB.Coins = 500
		profB.LastAccrualTimestamp = t0 - 10
		profB.DiscoveredSpecies["SolarGolem"] = true
		profB.Items["s304-penB"] = {
			UID = "s304-penB",
			SpeciesId = "SolarGolem",
			Variant = "Normal",
			State = "InPen",
			AssignedSlot = "Pen_1",
			PlantedAt = nil,
			MaturesAt = nil,
			CreatedAt = t0,
			FeedLevel = 0,
		}
		profB.Slots["Pen_1"] = "s304-penB"
		profB.Items["s304-incB"] = {
			UID = "s304-incB",
			SpeciesId = "StarSlime",
			Variant = "Normal",
			State = "Incubating",
			AssignedSlot = "Incubator_1",
			PlantedAt = t0,
			MaturesAt = t0 + 15,
			CreatedAt = t0,
			FeedLevel = 0,
		}
		profB.Slots["Incubator_1"] = "s304-incB"

		local flushed = DataService.FlushActiveProfileSessions(10)
		local finOkA, revA, coinsA = DataService.GetLastClosingFinalSaveInfo(uA)
		local finOkB, revB, coinsB = DataService.GetLastClosingFinalSaveInfo(uB)
		if not flushed or not finOkA or not finOkB or coinsA == nil or coinsB == nil then
			return false, string.format(
				"S304 Write flush did not confirm (flushed=%s okA=%s okB=%s)",
				tostring(flushed),
				tostring(finOkA),
				tostring(finOkB)
			)
		end
		if (coinsA :: number) <= 300 or (coinsB :: number) <= 500 then
			return false, string.format(
				"S304 Write settlement did not credit unaccrued pen earnings (coinsA=%d coinsB=%d)",
				coinsA :: number,
				coinsB :: number
			)
		end
		writtenCoinsA = coinsA :: number
		writtenRevA = revA
		writtenCoinsB = coinsB :: number
		writtenRevB = revB

		if runPhase == "Write" then
			DataService.ClearTestTrackingForUserIds({ uA, uB })
			return true, string.format(
				"Write phase confirmed (%s, Version=%s, PlaceId=%d, GameId=%d, KeyA=%s, SettledCoinsA=%d, RevA=%d, KeyB=%s, SettledCoinsB=%d, RevB=%d, PlantedAt=%d, MaturesAtA=%d, MaturesAtB=%d).",
				storeName,
				Constants.GAME_VERSION,
				game.PlaceId,
				game.GameId,
				keyA,
				writtenCoinsA,
				writtenRevA,
				keyB,
				writtenCoinsB,
				writtenRevB,
				t0,
				t0 + 45,
				t0 + 15
			)
		end
	end

	-- Verify phase: reopen both keys from live Roblox DataStore, validate state + hatch boundaries + cleanup
	local reopenNow = workspace:GetServerTimeNow()
	local verifyOkA, verifyReasonA = DataService.StartProfileSessionForUserId(uA, nil, {
		Store = smokeStore,
		NowClock = reopenNow,
	})
	if not verifyOkA then
		return false, "S304 Verify load failed for uA: " .. verifyReasonA
	end
	local verifyOkB, verifyReasonB = DataService.StartProfileSessionForUserId(uB, nil, {
		Store = smokeStore,
		NowClock = reopenNow,
	})
	if not verifyOkB then
		DataService.FlushActiveProfileSessions(5)
		return false, "S304 Verify load failed for uB: " .. verifyReasonB
	end

	local relA = DataService.GetProfileByUserId(uA) :: Types.PlayerProfileData
	local relB = DataService.GetProfileByUserId(uB) :: Types.PlayerProfileData

	local noOfflinePay = not EconomyService.SettleProfileCoins(relA, relA.LastAccrualTimestamp)
	local coinsOkA = if runPhase == "RoundTrip" then relA.Coins == writtenCoinsA else relA.Coins > 300
	local revOkA = if runPhase == "RoundTrip" then relA.Revision == writtenRevA else relA.Revision >= 2
	local coinsOkB = if runPhase == "RoundTrip" then relB.Coins == writtenCoinsB else relB.Coins > 500
	local revOkB = if runPhase == "RoundTrip" then relB.Revision == writtenRevB else relB.Revision >= 2

	local pen1A = relA.Items["s304-pen1"]
	local pen5A = relA.Items["s304-pen5"]
	local podA = relA.Items["s304-incA"]
	local pen1B = relB.Items["s304-penB"]
	local podB = relB.Items["s304-incB"]

	local stateOkA = relA.Upgrades["BagCap_20"] == true
		and relA.Upgrades["PenSlot_5"] == true
		and pen1A ~= nil and pen1A.SpeciesId == "CinderPup" and pen1A.FeedLevel == 1 and relA.Slots["Pen_1"] == "s304-pen1"
		and pen5A ~= nil and pen5A.SpeciesId == "NebulaFox" and pen5A.Variant == "Radiant" and relA.Slots["Pen_5"] == "s304-pen5"
		and podA ~= nil and podA.SpeciesId == "FrostBeetle" and podA.State == "Incubating" and podA.PlantedAt ~= nil and podA.MaturesAt == ((podA.PlantedAt :: number) + 45)
	local stateOkB = pen1B ~= nil and pen1B.SpeciesId == "SolarGolem" and relB.Slots["Pen_1"] == "s304-penB"
		and podB ~= nil and podB.SpeciesId == "StarSlime" and podB.State == "Incubating" and podB.PlantedAt ~= nil and podB.MaturesAt == ((podB.PlantedAt :: number) + 15)

	local plantedA = if podA ~= nil and podA.PlantedAt ~= nil then podA.PlantedAt else -1
	local maturesA = if podA ~= nil and podA.MaturesAt ~= nil then podA.MaturesAt else -1
	local maturesB = if podB ~= nil and podB.MaturesAt ~= nil then podB.MaturesAt else -1
	local verifiedCoinsA = relA.Coins
	local verifiedRevA = relA.Revision
	local verifiedCoinsB = relB.Coins
	local verifiedRevB = relB.Revision

	local earlyReason = "Skipped"
	local lateSpecies = "Skipped"
	local hatchBoundaryOk = false
	if stateOkA and podA ~= nil and podA.MaturesAt ~= nil then
		local rng = Random.new(7)
		local matureTime = podA.MaturesAt :: number
		local earlyRes = EconomyService.HatchFromSlotOnProfile(relA, "Incubator_1", matureTime - 1, rng)
		earlyReason = tostring(earlyRes.Reason)
		local lateRes = EconomyService.HatchFromSlotOnProfile(relA, "Incubator_1", matureTime + 12 * 3600, rng)
		lateSpecies = tostring(lateRes.SpeciesId)
		local invOk = EconomyService.ValidateProfileInvariants(relA)
		hatchBoundaryOk = (not earlyRes.Ok and earlyRes.Reason == "NotMature")
			and (lateRes.Ok and lateRes.SpeciesId == "FrostBeetle")
			and invOk
	end

	DataService.FlushActiveProfileSessions(10)
	if smokeStore.RemoveAsync ~= nil then
		local anyStore = smokeStore :: any
		pcall(function()
			anyStore:RemoveAsync(keyA)
			anyStore:RemoveAsync(keyB)
		end)
	end
	DataService.ClearTestTrackingForUserIds({ uA, uB })

	if not (noOfflinePay and coinsOkA and revOkA and coinsOkB and revOkB and stateOkA and stateOkB and hatchBoundaryOk) then
		return false, string.format(
			"S304 Verify mismatch (noOffline=%s coinsA=%s(%d) revA=%s(%d) coinsB=%s(%d) revB=%s(%d) stateA=%s stateB=%s hatch=%s[%s->%s])",
			tostring(noOfflinePay),
			tostring(coinsOkA),
			verifiedCoinsA,
			tostring(revOkA),
			verifiedRevA,
			tostring(coinsOkB),
			verifiedCoinsB,
			tostring(revOkB),
			verifiedRevB,
			tostring(stateOkA),
			tostring(stateOkB),
			tostring(hatchBoundaryOk),
			earlyReason,
			lateSpecies
		)
	end

	return true, string.format(
		"Live Dev DataStore S3-04 %s verified (%s, Version=%s, PlaceId=%d, GameId=%d, SettledCoinsA=%d, RevA=%d, SettledCoinsB=%d, RevB=%d, BagCap_20=true, PenSlot_5=true, Pen1A=CinderPup(FeedLevel=1), Pen5A=NebulaFox(Radiant), Pen1B=SolarGolem, PlantedAtA=%d, MaturesAtA=%d, MaturesAtB=%d, EarlyHatchReason=%s, Late12hHatch=%s).",
		runPhase,
		storeName,
		Constants.GAME_VERSION,
		game.PlaceId,
		game.GameId,
		verifiedCoinsA,
		verifiedRevA,
		verifiedCoinsB,
		verifiedRevB,
		plantedA,
		maturesA,
		maturesB,
		earlyReason,
		lateSpecies
	)
end

function Stage3VerificationSuite.RunS404StarterPersistenceCheck(phase: DataService.SmokeTestPhase?, baseTestUserId: number?): (boolean, string)
	EconomyService:Init()

	local runPhase: DataService.SmokeTestPhase = if phase ~= nil then phase else "RoundTrip"
	local uCompleted = if baseTestUserId ~= nil then baseTestUserId else -960401
	local uEligible = uCompleted - 1

	local storeOk, liveStoreOrErr, storeName = DataService.GetLiveDevSmokeStore()
	if not storeOk then
		return false, tostring(liveStoreOrErr)
	end
	local smokeStore = liveStoreOrErr
	local keyCompleted = Constants.PROFILE_KEY_PREFIX .. tostring(uCompleted)
	local keyEligible = Constants.PROFILE_KEY_PREFIX .. tostring(uEligible)
	local t0 = math.floor(workspace:GetServerTimeNow())

	local function cleanupUsers(removeKeys: boolean): ()
		for _, uid in ipairs({ uCompleted, uEligible }) do
			local pId = PlotService.GetAssignedPlotId(uid)
			if pId ~= nil then
				MeteorService.HandlePlotReleased(pId, uid)
				PlotService.ReleasePlotForUserId(uid)
			end
			DataService.EndSession(uid)
		end
		DataService.FlushActiveProfileSessions(5)
		if removeKeys and smokeStore.RemoveAsync ~= nil then
			local anyStore = smokeStore :: any
			pcall(function()
				anyStore:RemoveAsync(keyCompleted)
				anyStore:RemoveAsync(keyEligible)
			end)
		end
		DataService.ClearTestTrackingForUserIds({ uCompleted, uEligible })
	end

	local resultMsg = ""
	local ok, err = pcall(function()
		if runPhase == "RoundTrip" or runPhase == "Write" then
			cleanupUsers(true)

			local joinC, reasonC = DataService.StartProfileSessionForUserId(uCompleted, nil, { Store = smokeStore, NowClock = t0 })
			assert(joinC, "S404 Write load uCompleted failed: " .. tostring(reasonC))
			local joinE, reasonE = DataService.StartProfileSessionForUserId(uEligible, nil, { Store = smokeStore, NowClock = t0 })
			assert(joinE, "S404 Write load uEligible failed: " .. tostring(reasonE))

			local profC = DataService.GetProfileByUserId(uCompleted) :: Types.PlayerProfileData
			local profE = DataService.GetProfileByUserId(uEligible) :: Types.PlayerProfileData

			local okPlotC, reasonPlotC, plotC = PlotService.AssignPlotForUserId(uCompleted, "S404Completed", profC, nil)
			assert(okPlotC and plotC ~= nil, "S404 Write assign plot uCompleted failed: " .. tostring(reasonPlotC))
			local okPlotE, reasonPlotE, plotE = PlotService.AssignPlotForUserId(uEligible, "S404Eligible", profE, nil)
			assert(okPlotE and plotE ~= nil, "S404 Write assign plot uEligible failed: " .. tostring(reasonPlotE))

			local spC, reasonSpC, mC = MeteorService.SpawnStarterMeteorForPlot(plotC :: number, uCompleted, t0)
			assert(spC and mC ~= nil, "S404 Write spawn starter uCompleted failed: " .. tostring(reasonSpC))
			local stC = MeteorService.StartCrackAtPosition(uCompleted, mC.Position, mC.UID, t0 + 1)
			assert(stC.Ok and stC.AttemptNonce ~= nil, "S404 Write start starter uCompleted failed: " .. tostring(stC.Reason))
			local finC = MeteorService.FinishCrackAtPosition(uCompleted, mC.Position, mC.UID, stC.AttemptNonce :: string, t0 + 2, Random.new(404))
			assert(finC.Ok and finC.SpeciesId == "StarSlime", "S404 Write finish starter uCompleted failed: " .. tostring(finC.Reason))
			assert(profC.StarterMeteorCompleted == true, "S404 Write StarterMeteorCompleted must be true")

			local podCountWrite = 0
			for _ in pairs(profC.Items) do
				podCountWrite += 1
			end
			assert(podCountWrite == 1, "S404 Write granted exactly 1 StarSlime pod")

			local dupGrant = EconomyService.GrantStarterPodToProfile(profC, t0 + 3, "s404-live-dup")
			assert(not dupGrant.Ok and dupGrant.Reason == "StarterAlreadyCompleted", "S404 Write replay grant must be rejected")

			local spE, reasonSpE, mE = MeteorService.SpawnStarterMeteorForPlot(plotE :: number, uEligible, t0)
			assert(spE and mE ~= nil and profE.StarterMeteorCompleted == false, "S404 Write eligible player keeps starter available: " .. tostring(reasonSpE))

			for _, uid in ipairs({ uCompleted, uEligible }) do
				local pId = PlotService.GetAssignedPlotId(uid)
				if pId ~= nil then
					MeteorService.HandlePlotReleased(pId, uid)
					PlotService.ReleasePlotForUserId(uid)
				end
			end
			local flushed = DataService.FlushActiveProfileSessions(10)
			assert(flushed, "S404 Write flush failed")
			DataService.ClearTestTrackingForUserIds({ uCompleted, uEligible })

			if runPhase == "Write" then
				resultMsg = string.format(
					"Live Dev DataStore S4-04 Write complete (%s, Version=%s, PlaceId=%d, PlaceVersion=%d, GameId=%d, CompletedUser=%d, EligibleUser=%d).",
					storeName,
					Constants.GAME_VERSION,
					game.PlaceId,
					game.PlaceVersion,
					game.GameId,
					uCompleted,
					uEligible
				)
				return
			end
		end

		local relOkC, relReasonC = DataService.StartProfileSessionForUserId(uCompleted, nil, { Store = smokeStore, NowClock = t0 + 60 })
		assert(relOkC, "S404 Verify reload uCompleted failed: " .. tostring(relReasonC))
		local relOkE, relReasonE = DataService.StartProfileSessionForUserId(uEligible, nil, { Store = smokeStore, NowClock = t0 + 60 })
		assert(relOkE, "S404 Verify reload uEligible failed: " .. tostring(relReasonE))

		local relC = DataService.GetProfileByUserId(uCompleted) :: Types.PlayerProfileData
		local relE = DataService.GetProfileByUserId(uEligible) :: Types.PlayerProfileData
		assert(relC.SchemaVersion == Constants.SCHEMA_VERSION, "S404 Verify SchemaVersion == " .. tostring(Constants.SCHEMA_VERSION))
		assert(relC.StarterMeteorCompleted == true, "S404 Verify uCompleted retained StarterMeteorCompleted=true")

		local podCountVerify = 0
		local hasStarSlimePod = false
		for _, item in pairs(relC.Items) do
			podCountVerify += 1
			if item.SpeciesId == "StarSlime" and item.State == "PodInBag" then
				hasStarSlimePod = true
			end
		end
		assert(podCountVerify == 1 and hasStarSlimePod, "S404 Verify uCompleted restored exactly 1 StarSlime PodInBag")

		local okPlotC2, _, plotC2 = PlotService.AssignPlotForUserId(uCompleted, "S404Completed", relC, nil)
		assert(okPlotC2 and plotC2 ~= nil, "S404 Verify assign plot uCompleted")
		local spBlocked, spBlockedReason = MeteorService.SpawnStarterMeteorForPlot(plotC2 :: number, uCompleted, t0 + 60)
		assert(not spBlocked and spBlockedReason == "StarterAlreadyCompleted", "S404 Verify completed user skips starter respawn")

		local okPlotE2, _, plotE2 = PlotService.AssignPlotForUserId(uEligible, "S404Eligible", relE, nil)
		assert(okPlotE2 and plotE2 ~= nil, "S404 Verify assign plot uEligible")
		assert(relE.StarterMeteorCompleted == false, "S404 Verify uEligible retained StarterMeteorCompleted=false")
		local spEligible, reasonSpE2, mE2 = MeteorService.SpawnStarterMeteorForPlot(plotE2 :: number, uEligible, t0 + 60)
		assert(spEligible and mE2 ~= nil, "S404 Verify eligible user spawns starter: " .. tostring(reasonSpE2))
		local stE2 = MeteorService.StartCrackAtPosition(uEligible, mE2.Position, mE2.UID, t0 + 61)
		assert(stE2.Ok and stE2.AttemptNonce ~= nil, "S404 Verify eligible user starts crack")
		local finE2 = MeteorService.FinishCrackAtPosition(uEligible, mE2.Position, mE2.UID, stE2.AttemptNonce :: string, t0 + 62, Random.new(405))
		assert(finE2.Ok and finE2.SpeciesId == "StarSlime" and relE.StarterMeteorCompleted == true, "S404 Verify eligible user completes starter crack")

		resultMsg = string.format(
			"Live Dev DataStore S4-04 %s verified (%s, Version=%s, PlaceId=%d, PlaceVersion=%d, GameId=%d, SchemaVersion=%d, CompletedUser=%d[StarterMeteorCompleted=true, Pods=1, RespawnBlocked=true], EligibleUser=%d[SpawnedAndCompleted=true]).",
			runPhase,
			storeName,
			Constants.GAME_VERSION,
			game.PlaceId,
			game.PlaceVersion,
			game.GameId,
			relC.SchemaVersion,
			uCompleted,
			uEligible
		)
	end)

	cleanupUsers(runPhase ~= "Write")
	if not ok then
		return false, tostring(err)
	end
	return true, resultMsg
end

function Stage3VerificationSuite.RunSelfTest(): number
	local passed = 0
	local rng = Random.new(304)

	cleanupAllTestUsers()
	local ok, err = pcall(function()
		-- 1. 6-player ProfileStore.Mock admission, 7th-player NoFreePlot save preservation, & Plot reuse
		runSixPlayerAdmissionAndReuseSuite()
		passed += 1

		-- 2. Forced load failure, external Force-Load lock theft, & 6-player concurrent BindToClose flush
		runPersistenceFailureAndSixPlayerFlushSuite()
		passed += 1

		-- 3. Offline MaturesAt boundaries (-1s, 0s, +12h) & zero offline Coins across ProfileStore.Mock rejoin
		runOfflineMaturesBoundarySuite(rng)
		passed += 1

		-- 4. 6-player full-server cross-plot (30 pairs) & Hub station proximity/ownership authorization matrix
		runSixPlayerStationIsolationSuite()
		passed += 1

		-- 5. 6-player Crater race, AttemptNonce hijack, OnBeforeNavigate crack cancel & Ridge Frost Lure saturation
		runSixPlayerCraterRaceNavAndLureSuite(rng)
		passed += 1

		-- 6. 6-player independent rate-limit buckets, hostile payload rejection & 30-critter PublicPlotDTO privacy audit
		runSixPlayerRateAndPublicDtoAuditSuite()
		passed += 1
	end)

	cleanupAllTestUsers()
	if not ok then
		error(err)
	end

	return passed
end

return Stage3VerificationSuite