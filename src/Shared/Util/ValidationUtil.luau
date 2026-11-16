--!strict
--[[
	Module: ValidationUtil
	Purpose: Pure type, finite-number, integer, and bounded-string guards for inbound payloads.
	Connections: Used by NetworkService on every client-to-server remote handler.
	How to Test in Studio: Unit-test NaN, +/-inf, negative floats, and oversized strings in Stage 1.
]]

local ValidationUtil = {}

function ValidationUtil.IsFiniteInteger(value: unknown): boolean
	if typeof(value) ~= "number" then
		return false
	end
	return value == value and math.abs(value) ~= math.huge and value % 1 == 0
end

function ValidationUtil.IsBoundedString(value: unknown, maxLength: number): boolean
	if typeof(value) ~= "string" then
		return false
	end
	return #value > 0 and #value <= maxLength
end

return ValidationUtil
