--!strict
--[[
	Module: FormatUtil
	Purpose: Formatting helpers for integer currency strings and countdown timers (Stage 1 skeleton stub).
	Connections: Used by Client UIController and World BillboardGuis.
	How to Test in Studio: Call FormatUtil.FormatCoins(1250) in Command Bar during Stage 1.
]]

local FormatUtil = {}

function FormatUtil.FormatCoins(amount: number): string
	-- Stage 1 (S1-01): Implement readable formatting (e.g. 1250 -> "1,250").
	return tostring(math.floor(amount))
end

function FormatUtil.FormatTimer(secondsRemaining: number): string
	-- Stage 1 (S1-01): Implement "MM:SS" countdown formatting.
	local clamped = math.max(0, math.floor(secondsRemaining))
	return string.format("%02d:%02d", math.floor(clamped / 60), clamped % 60)
end

return FormatUtil
