--!strict
--[[
	Module: Constants
	Purpose: Authoritative structural and balance bounds shared across Client and Server.
	Connections: Imported by Server Services and Shared Util modules to avoid magic numbers.
	How to Test in Studio: Verify values are frozen at runtime so no script mutates shared constants.
]]

local Constants = {
	GAME_VERSION = "0.1.1-s1-01",
	USE_MOCK_STORE = true,
	RUN_SELF_TESTS = true,
	SCHEMA_VERSION = 1,

	-- Plot & Server Capacity Bounds
	MAX_PLOTS_PROTOTYPE = 2,
	MAX_PLOTS_ALPHA = 6,
	STARTER_PEN_SLOTS = 1,
	STARTER_INCUBATOR_SLOTS = 1,

	-- Inventory & Economy Safety Caps
	MAX_BAG_CAPACITY = 10,
	MAX_COINS = 1_000_000_000,
	RADIANT_HATCH_CHANCE = 0.10,
	RADIANT_BONUS_COINS_PER_SEC = 0,
	RADIANT_BONUS_SELL_COINS = 0,

	-- Networking & Security Bounds
	REMOTES_FOLDER_NAME = "Remotes",
	MAX_CRACK_START_DISTANCE = 18,
	MAX_CRACK_FINISH_DISTANCE = 22,
	CRACK_CLAIM_TIMEOUT_SECONDS = 6.0,
	MIN_CRACK_DURATION_SECONDS = 0.4,
	MAX_STRING_ID_LENGTH = 40,
}

return table.freeze(Constants)
