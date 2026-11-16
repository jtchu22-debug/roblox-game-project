--!strict
--[[
	Module: Constants
	Purpose: Authoritative structural and balance bounds shared across Client and Server.
	Connections: Imported by Server Services and Shared Util modules to avoid magic numbers.
	How to Test in Studio: Verify values are frozen at runtime so no script mutates shared constants.
]]

local Constants = {
	GAME_VERSION = "0.1.0-skeleton",
	USE_MOCK_STORE = true,

	-- Plot & Server Capacity Bounds
	MAX_PLOTS_PROTOTYPE = 2,
	MAX_PLOTS_ALPHA = 6,

	-- Inventory & Economy Safety Caps
	MAX_BAG_CAPACITY = 10,
	MAX_COINS = 1_000_000_000,

	-- Networking & Security Bounds
	REMOTES_FOLDER_NAME = "Remotes",
	MAX_CRACK_START_DISTANCE = 18,
	MAX_CRACK_FINISH_DISTANCE = 22,
	CRACK_CLAIM_TIMEOUT_SECONDS = 6.0,
	MIN_CRACK_DURATION_SECONDS = 0.4,
	MAX_STRING_ID_LENGTH = 40,
}

return table.freeze(Constants)
