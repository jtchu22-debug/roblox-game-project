--!strict
--[[
	Module: FormatUtil
	Purpose: Formatting helpers for integer currency strings, rates, and countdown timers.
	Connections: Used by Client UIController and World BillboardGuis.
	How to Test in Studio: Verified automatically by SharedSelfTest on Play (F5).
]]

local FormatUtil = {}

local function isFinite(value: number): boolean
	return typeof(value) == "number" and value == value and math.abs(value) ~= math.huge
end

function FormatUtil.FormatCoins(amount: number): string
	if not isFinite(amount) then
		return "0"
	end

	local clamped = math.max(0, math.floor(amount))
	local formatted = tostring(clamped)
	while true do
		local nextStr, count = string.gsub(formatted, "^(%d+)(%d%d%d)", "%1,%2")
		formatted = nextStr
		if count == 0 then
			break
		end
	end
	return formatted
end

function FormatUtil.FormatTimer(secondsRemaining: number): string
	if not isFinite(secondsRemaining) then
		return "00:00"
	end

	local clamped = math.max(0, math.floor(secondsRemaining))
	return string.format("%02d:%02d", math.floor(clamped / 60), clamped % 60)
end

function FormatUtil.FormatRate(coinsPerSecond: number): string
	return string.format("+%s Coins/s", FormatUtil.FormatCoins(coinsPerSecond))
end

return FormatUtil
