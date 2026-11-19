--!strict
--[[
	Controller: SoundController
	Purpose: Plays client UI, meteor crack, hatch, sell, and upgrade sound effects via SoundService
	         and manages global Mute Sound and Reduced Motion accessibility settings.
	Connections: Required by PlotVisualController, UIController, CrackController, and InputController.
	How to Test in Studio: Press Play (F5), open Settings (⚙), and toggle Mute Sound or Reduced Motion.
]]

local SoundService = game:GetService("SoundService")

export type SoundCue =
	"Click"
	| "CrackStart"
	| "CrackChime"
	| "CrackSuccess"
	| "Hatch"
	| "Upgrade"
	| "Sell"
	| "Error"

type CuePreset = {
	SoundId: string,
	Volume: number,
	PlaybackSpeed: number,
}

local DEFAULT_SFX_VOLUME = 0.8

local CUE_PRESETS: { [SoundCue]: CuePreset } = {
	Click = {
		SoundId = "rbxasset://sounds/volume_slider.ogg",
		Volume = 0.35,
		PlaybackSpeed = 1.15,
	},
	CrackStart = {
		SoundId = "rbxasset://sounds/action_jump.mp3",
		Volume = 0.45,
		PlaybackSpeed = 1.25,
	},
	CrackChime = {
		SoundId = "rbxasset://sounds/action_get_up.mp3",
		Volume = 0.55,
		PlaybackSpeed = 1.55,
	},
	CrackSuccess = {
		SoundId = "rbxasset://sounds/action_get_up.mp3",
		Volume = 0.5,
		PlaybackSpeed = 1.2,
	},
	Hatch = {
		SoundId = "rbxasset://sounds/impact_water.mp3",
		Volume = 0.55,
		PlaybackSpeed = 1.45,
	},
	Upgrade = {
		SoundId = "rbxasset://sounds/action_get_up.mp3",
		Volume = 0.6,
		PlaybackSpeed = 1.35,
	},
	Sell = {
		SoundId = "rbxasset://sounds/volume_slider.ogg",
		Volume = 0.5,
		PlaybackSpeed = 1.4,
	},
	Error = {
		SoundId = "rbxasset://sounds/action_footsteps_plastic.mp3",
		Volume = 0.45,
		PlaybackSpeed = 0.75,
	},
}

local SoundController = {
	Name = "SoundController",
}

local isMuted = false
local isReducedMotion = false
local sfxGroup: SoundGroup? = nil
local cueSounds: { [SoundCue]: Sound } = {}
local settingsListeners: { (muted: boolean, reducedMotion: boolean) -> () } = {}

local function notifySettingsListeners(): ()
	for _, cb in ipairs(settingsListeners) do
		local ok, err = pcall(cb, isMuted, isReducedMotion)
		if not ok then
			warn("[SoundController] Settings listener error: " .. tostring(err))
		end
	end
end

local function applyMuteToSoundGroup(): ()
	local group = sfxGroup
	if group ~= nil then
		group.Volume = if isMuted then 0 else DEFAULT_SFX_VOLUME
	end
	if isMuted then
		for _, sound in pairs(cueSounds) do
			if sound.IsPlaying then
				sound:Stop()
			end
		end
		local customFolder = SoundService:FindFirstChild("StarfallSfx")
		if customFolder ~= nil then
			for _, child in ipairs(customFolder:GetChildren()) do
				if child:IsA("Sound") and child.IsPlaying then
					child:Stop()
				end
			end
		end
	end
end

local function ensureCueSound(folder: Folder, cue: SoundCue, preset: CuePreset, group: SoundGroup): Sound
	local existing = folder:FindFirstChild(cue)
	local sound: Sound
	if existing ~= nil and existing:IsA("Sound") then
		sound = existing
	else
		if existing ~= nil then
			existing:Destroy()
		end
		sound = Instance.new("Sound")
		sound.Name = cue
		sound.Parent = folder
	end

	sound.SoundId = preset.SoundId
	sound.Volume = preset.Volume
	sound.PlaybackSpeed = preset.PlaybackSpeed
	sound.SoundGroup = group
	return sound
end

function SoundController.Init(self: typeof(SoundController)): ()
	local existingGroup = SoundService:FindFirstChild("StarfallSfxGroup")
	local group: SoundGroup
	if existingGroup ~= nil and existingGroup:IsA("SoundGroup") then
		group = existingGroup
	else
		if existingGroup ~= nil then
			existingGroup:Destroy()
		end
		group = Instance.new("SoundGroup")
		group.Name = "StarfallSfxGroup"
		group.Parent = SoundService
	end
	sfxGroup = group

	local existingFolder = group:FindFirstChild("StarfallSfxGenerated")
	local generatedFolder: Folder
	if existingFolder ~= nil and existingFolder:IsA("Folder") then
		generatedFolder = existingFolder
	else
		if existingFolder ~= nil then
			existingFolder:Destroy()
		end
		generatedFolder = Instance.new("Folder")
		generatedFolder.Name = "StarfallSfxGenerated"
		generatedFolder.Parent = group
	end

	for cue, preset in pairs(CUE_PRESETS) do
		cueSounds[cue] = ensureCueSound(generatedFolder, cue, preset, group)
	end

	applyMuteToSoundGroup()
end

function SoundController.Start(self: typeof(SoundController)): ()
	applyMuteToSoundGroup()
	notifySettingsListeners()
end

function SoundController.IsMuted(): boolean
	return isMuted
end

function SoundController.SetMuted(muted: boolean): ()
	if isMuted == muted then
		return
	end
	isMuted = muted
	applyMuteToSoundGroup()
	notifySettingsListeners()
end

function SoundController.ToggleMuted(): boolean
	SoundController.SetMuted(not isMuted)
	return isMuted
end

function SoundController.IsReducedMotion(): boolean
	return isReducedMotion
end

function SoundController.SetReducedMotion(reduced: boolean): ()
	if isReducedMotion == reduced then
		return
	end
	isReducedMotion = reduced
	notifySettingsListeners()
end

function SoundController.ToggleReducedMotion(): boolean
	SoundController.SetReducedMotion(not isReducedMotion)
	return isReducedMotion
end

function SoundController.OnSettingsChanged(callback: (muted: boolean, reducedMotion: boolean) -> ()): ()
	table.insert(settingsListeners, callback)
	local ok, err = pcall(callback, isMuted, isReducedMotion)
	if not ok then
		warn("[SoundController] Initial settings callback error: " .. tostring(err))
	end
end

function SoundController.Play(cue: SoundCue): ()
	if isMuted then
		return
	end

	local overrideFolder = SoundService:FindFirstChild("StarfallSfx")
	local overrideSound = if overrideFolder ~= nil then overrideFolder:FindFirstChild(cue) else nil
	if overrideSound ~= nil and overrideSound:IsA("Sound") then
		if sfxGroup ~= nil then
			overrideSound.SoundGroup = sfxGroup
		end
		overrideSound.TimePosition = 0
		overrideSound:Play()
		return
	end

	local sound = cueSounds[cue]
	if sound ~= nil then
		sound.TimePosition = 0
		sound:Play()
	end
end

return SoundController
