--!strict
--[[
	Controller: SoundController
	Purpose: Plays lightweight UI, meteor crack, and hatch sound effects while honoring Mute and Reduced Motion accessibility settings.
	Connections: Called by CrackController, PlotVisualController, and UIController.
	How to Test in Studio: Press Play (F5) and verify toggling Mute immediately silences playback.
]]

local SoundController = {
	Name = "SoundController",
}

local isMuted = false
local isReducedMotion = false

function SoundController.Init(self: typeof(SoundController)): ()
	-- Stage 1 (S1-08): Preload approved sound instances inside SoundService.
end

function SoundController.Start(self: typeof(SoundController)): ()
	-- Stage 1 (S1-08): Connect accessibility setting state changes.
end

function SoundController.IsMuted(): boolean
	return isMuted
end

function SoundController.IsReducedMotion(): boolean
	return isReducedMotion
end

return SoundController
