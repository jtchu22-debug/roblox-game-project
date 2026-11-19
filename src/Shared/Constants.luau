--!strict
--[[
	Module: Constants
	Purpose: Authoritative structural, map-tag, remote-name, and balance bounds shared across Client and Server.
	Connections: Imported by Server Services and Shared Util modules to avoid magic numbers.
	How to Test in Studio: Verify values are frozen at runtime so no script mutates shared constants.
]]

local Constants = {
	GAME_VERSION = "0.1.9-s1-07-fix",
	USE_MOCK_STORE = true,
	ALLOW_PUBLISHED_PROTOTYPE_PLACE_ID = 0,
	RUN_SELF_TESTS = true,
	SCHEMA_VERSION = 1,

	-- Plot & Server Capacity Bounds
	MAX_PLOTS_PROTOTYPE = 2,
	MAX_PLOTS_ALPHA = 6,
	STARTER_PEN_SLOTS = 1,
	STARTER_INCUBATOR_SLOTS = 1,
	MAX_STATION_INTERACT_DISTANCE = 18,
	PROMPT_ACTIVATION_DISTANCE = 12,
	MAX_ACTIVE_WILD_METEORS = 4,
	WILD_METEOR_RESPAWN_SECONDS = 6,

	-- Greybox Map Identifiers & CollectionService Tags
	GREYBOX_ROOT_NAME = "StarfallGreyboxRoot",
	GREYBOX_VERSION = "1.0.0-s1-02",
	TAG_GREYBOX_ROOT = "StarfallGreyboxRoot",
	TAG_PLOT = "StarfallPlot",
	TAG_INCUBATOR_SLOT = "StarfallIncubatorSlot",
	TAG_PEN_SLOT = "StarfallPenSlot",
	TAG_UPGRADE_PAD = "StarfallUpgradePad",
	TAG_SELL_STAND = "StarfallSellStand",
	TAG_METEOR_NODE = "StarfallMeteorNode",
	TAG_ACTIVE_METEOR = "StarfallActiveMeteor",

	-- Inventory & Economy Safety Caps
	MAX_BAG_CAPACITY = 10,
	MAX_COINS = 1_000_000_000,
	RADIANT_HATCH_CHANCE = 0.10,
	RADIANT_BONUS_COINS_PER_SEC = 0,
	RADIANT_BONUS_SELL_COINS = 0,

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
	MAX_STRING_ID_LENGTH = 40,
}

return table.freeze(Constants)
