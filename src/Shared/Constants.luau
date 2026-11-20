--!strict
--[[
	Module: Constants
	Purpose: Authoritative structural, map-tag, remote-name, and balance bounds shared across Client and Server.
	Connections: Imported by Server Services and Shared Util modules to avoid magic numbers.
	How to Test in Studio: Verify values are frozen at runtime so no script mutates shared constants.
]]

local Constants = {
	GAME_VERSION = "0.2.4-s2c-astral-fall",
	USE_MOCK_STORE = true,
	ALLOW_PUBLISHED_PROTOTYPE_PLACE_ID = 137485500524067, -- Private Stage 2 test place (Bioniccat4000's Place: 11192026_1)
	RUN_SELF_TESTS = true, -- Executes only in Studio (RunService:IsStudio() guard in ServerInit/ClientInit)
	SCHEMA_VERSION = 1,

	-- Plot & Server Capacity Bounds
	MAX_PLOTS_PROTOTYPE = 2,
	MAX_PLOTS_ALPHA = 6,
	STARTER_PEN_SLOTS = 1,
	STARTER_INCUBATOR_SLOTS = 1,
	MAX_STATION_INTERACT_DISTANCE = 18,
	PROMPT_ACTIVATION_DISTANCE = 7.5,
	MAX_ACTIVE_WILD_METEORS = 4,
	WILD_METEOR_RESPAWN_SECONDS = 10,
	ASTRAL_FALL_FIRST_DELAY_SECONDS = 45,
	ASTRAL_FALL_INTERVAL_SECONDS = 75,
	ASTRAL_FALL_WARNING_SECONDS = 3.0,
	ASTRAL_METEOR_LIFETIME_SECONDS = 55,

	-- Greybox Map Identifiers & CollectionService Tags
	GREYBOX_ROOT_NAME = "StarfallGreyboxRoot",
	GREYBOX_VERSION = "1.0.0-s1-02",
	TAG_GREYBOX_ROOT = "StarfallGreyboxRoot",
	TAG_PLOT = "StarfallPlot",
	TAG_INCUBATOR_SLOT = "StarfallIncubatorSlot",
	TAG_PEN_SLOT = "StarfallPenSlot",
	TAG_UPGRADE_PAD = "StarfallUpgradePad",
	TAG_SELL_STAND = "StarfallSellStand",
	TAG_LURE_STAND = "StarfallLureStand",
	TAG_METEOR_NODE = "StarfallMeteorNode",
	TAG_ACTIVE_METEOR = "StarfallActiveMeteor",

	-- Inventory & Economy Safety Caps
	MAX_BAG_CAPACITY = 10,
	MAX_COINS = 1_000_000_000,
	RADIANT_HATCH_CHANCE = 0.10,
	RADIANT_BONUS_COINS_PER_SEC = 0,
	RADIANT_BONUS_SELL_COINS = 0,
	MAX_CRITTER_FEED_LEVEL = 1,
	CRITTER_FEED_COST = 45,
	CRITTER_FEED_BONUS_COINS_PER_SEC = 2,
	CRITTER_FEED_SELL_BONUS = 20, -- Strictly < CRITTER_FEED_COST so feeding-to-sell never profits
	FROST_LURE_COST = 75,
	FROST_LURE_COOLDOWN_SECONDS = 8,

	-- Networking & Security Bounds
	REMOTES_FOLDER_NAME = "Remotes",
	REMOTE_NAMES = table.freeze({
		SyncOwnerState = "SyncOwnerState",
		SyncPublicPlots = "SyncPublicPlots",
		MeteorLifecycle = "MeteorLifecycle",
		RequestInitialSnapshot = "RequestInitialSnapshot",
		RequestPlotAction = "RequestPlotAction",
		RequestStartCrack = "RequestStartCrack",
		RequestFinishCrack = "RequestFinishCrack",
		RequestBuyUpgrade = "RequestBuyUpgrade",
	}),
	MAX_CRACK_START_DISTANCE = 18,
	MAX_CRACK_FINISH_DISTANCE = 22,
	MAX_CRACK_ABANDON_DISTANCE = 28,
	CRACK_CLAIM_TIMEOUT_SECONDS = 6.0,
	MIN_CRACK_DURATION_SECONDS = 0.4,
	CRACK_CLIENT_DURATION_SECONDS = 1.2,
	CRACK_FEEL_WINDOW_START_SECONDS = 0.52,
	CRACK_FEEL_WINDOW_END_SECONDS = 0.96,
	FROST_CRACK_DURATION_SECONDS = 1.5,
	FROST_BEAT1_END_SECONDS = 0.75,
	FROST_BEAT_SWEET_START = 0.25,
	FROST_BEAT_SWEET_END = 0.62,
	ASTRAL_CRACK_DURATION_SECONDS = 1.9,
	ASTRAL_PULSE_SWEET_START = 0.85, -- > MIN_CRACK_DURATION_SECONDS for rhythmic pulse surge
	ASTRAL_PULSE_SWEET_END = 1.55,
	MAX_STRING_ID_LENGTH = 40,
}

return table.freeze(Constants)
