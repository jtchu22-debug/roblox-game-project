--!strict
--[[
	Controller: InputController
	Purpose: Unifies Touch, Keyboard, and Gamepad input detection, makes ProximityPrompts clickable
	         for touch/mouse, routes meteor prompts with debounce to CrackController, shows friendly
	         station feedback hints, and handles B/ButtonY (Bag), ButtonB (Close), and Quick-Burst keys.
	Connections: Requires SoundController, UIController, PlotVisualController, and CrackController.
	How to Test in Studio: Press Play (F5), test Keyboard (E/Space/B), Device Emulator Touch taps, and Gamepad (X/Y/B).
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ControllersFolder = script.Parent
local SoundController = require(ControllersFolder:WaitForChild("SoundController"))
local PlotVisualController = require(ControllersFolder:WaitForChild("PlotVisualController"))
local UIController = require(ControllersFolder:WaitForChild("UIController"))
local CrackController = require(ControllersFolder:WaitForChild("CrackController"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Types = require(Shared:WaitForChild("Types"))
local UpgradeConfig = require(Shared:WaitForChild("Config"):WaitForChild("UpgradeConfig"))
local FormatUtil = require(Shared:WaitForChild("Util"):WaitForChild("FormatUtil"))

local RESCUE_PROMPT_DEBOUNCE_SECONDS = 0.25

local InputController = {
	Name = "InputController",
}

local currentInputMode: UIController.InputMode = "Keyboard"
local lastRescuePromptClock = 0

local promptShownConn: RBXScriptConnection? = nil
local promptTriggeredConn: RBXScriptConnection? = nil
local inputTypeConn: RBXScriptConnection? = nil
local inputBeganConn: RBXScriptConnection? = nil

local function classifyInputType(inputType: Enum.UserInputType): UIController.InputMode?
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif
		inputType == Enum.UserInputType.Gamepad1
		or inputType == Enum.UserInputType.Gamepad2
		or inputType == Enum.UserInputType.Gamepad3
		or inputType == Enum.UserInputType.Gamepad4
		or inputType == Enum.UserInputType.Gamepad5
		or inputType == Enum.UserInputType.Gamepad6
		or inputType == Enum.UserInputType.Gamepad7
		or inputType == Enum.UserInputType.Gamepad8
	then
		return "Gamepad"
	elseif
		inputType == Enum.UserInputType.Keyboard
		or inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseButton3
		or inputType == Enum.UserInputType.MouseWheel
		or inputType == Enum.UserInputType.MouseMovement
	then
		return "Keyboard"
	end
	return nil
end

local function applyInputMode(mode: UIController.InputMode): ()
	currentInputMode = mode
	UIController.SetInputMode(mode)
	CrackController.SetInputMode(mode)
end

local function detectInitialInputMode(): UIController.InputMode
	local lastKnown = classifyInputType(UserInputService:GetLastInputType())
	if lastKnown ~= nil then
		return lastKnown
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	end
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "Gamepad"
	end
	return "Keyboard"
end

local function findAncestorPlotId(inst: Instance): number?
	local current: Instance? = inst.Parent
	while current ~= nil do
		local plotAttr = current:GetAttribute("PlotId")
		if typeof(plotAttr) == "number" then
			return plotAttr
		end
		current = current.Parent
	end
	return nil
end

local function countBagStates(): (number, number)
	local dto = UIController.GetLatestOwnerState()
	if dto == nil then
		return 0, 0
	end
	local pods = 0
	local hatched = 0
	for _, item in pairs(dto.Items) do
		if item.State == "PodInBag" then
			pods += 1
		elseif item.State == "HatchedInBag" then
			hatched += 1
		end
	end
	return pods, hatched
end

local function handleRanchPromptFeedback(prompt: ProximityPrompt): ()
	local localPlayer = Players.LocalPlayer
	if localPlayer == nil then
		return
	end

	local promptPlotId = findAncestorPlotId(prompt)
	local myPlotId = PlotVisualController.GetPlotIdForUserId(localPlayer.UserId)
	if promptPlotId ~= nil and myPlotId ~= nil and promptPlotId ~= myPlotId then
		SoundController.Play("Error")
		UIController.ShowToast("That station belongs to another player's Ranch!", "Warn")
		return
	end

	local podsInBag, hatchedInBag = countBagStates()
	local dto = UIController.GetLatestOwnerState()

	if prompt.Name == "IncubatorPrompt" and prompt.ActionText == "Incubate" then
		if podsInBag == 0 then
			SoundController.Play("Error")
			UIController.ShowToast("No Star-Pods in your Bag!", "Warn")
			return
		end
	elseif prompt.Name == "PenPrompt" and prompt.ActionText == "Place" then
		if hatchedInBag == 0 then
			SoundController.Play("Error")
			UIController.ShowToast("Hatch a Star-Pod first!", "Warn")
			return
		end
	elseif prompt.Name == "SellPrompt" then
		if hatchedInBag == 0 then
			SoundController.Play("Error")
			UIController.ShowToast("No hatched Critters to sell!", "Warn")
			return
		end
	elseif prompt.Name == "LurePrompt" and dto ~= nil then
		local committed = 0
		for _, item in pairs(dto.Items) do
			if item.State ~= "InPen" then
				committed += 1
			end
		end
		if dto.Upgrades["FrostCracker"] ~= true then
			SoundController.Play("Error")
			UIController.ShowToast(string.format("Need Frost Cracker (%d Coins) first!", UpgradeConfig.ById.FrostCracker.Cost), "Warn")
			return
		elseif committed >= dto.BagCap then
			SoundController.Play("Error")
			UIController.ShowToast("Bag full! Sell or hatch before using a Lure.", "Warn")
			return
		elseif dto.Coins < Constants.FROST_LURE_COST then
			SoundController.Play("Error")
			UIController.ShowToast(string.format("Need %d Coins for a Frost Lure!", Constants.FROST_LURE_COST), "Warn")
			return
		end
	elseif prompt.Name == "UpgradePrompt" and dto ~= nil then
		local pad = prompt.Parent
		local upgradeAttr = if pad ~= nil then pad:GetAttribute("UpgradeId") else nil
		if typeof(upgradeAttr) == "string" then
			local upgradeDef = (UpgradeConfig.ById :: { [string]: Types.UpgradeDefinition })[upgradeAttr]
			if upgradeDef ~= nil then
				if dto.Upgrades[upgradeDef.Id] == true then
					SoundController.Play("Click")
					UIController.ShowToast("You already own " .. upgradeDef.DisplayName .. "!", "Info")
					return
				elseif upgradeDef.RequiresUpgradeId ~= nil and dto.Upgrades[upgradeDef.RequiresUpgradeId] ~= true then
					local prereq = UpgradeConfig.ById[upgradeDef.RequiresUpgradeId]
					SoundController.Play("Error")
					UIController.ShowToast(string.format("Requires %s first!", prereq.DisplayName), "Warn")
					return
				elseif dto.Coins < upgradeDef.Cost then
					SoundController.Play("Error")
					UIController.ShowToast(
						string.format("Need %s Coins for %s!", FormatUtil.FormatCoins(upgradeDef.Cost), upgradeDef.DisplayName),
						"Warn"
					)
					return
				end
			end
		end
	end

	SoundController.Play("Click")
end

function InputController.Init(self: typeof(InputController)): ()
	ProximityPromptService.Enabled = true
end

function InputController.Start(self: typeof(InputController)): ()
	applyInputMode(detectInitialInputMode())

	if inputTypeConn == nil then
		inputTypeConn = UserInputService.LastInputTypeChanged:Connect(function(newType: Enum.UserInputType)
			local classified = classifyInputType(newType)
			if classified ~= nil then
				applyInputMode(classified)
			end
		end)
	end

	if promptShownConn == nil then
		promptShownConn = ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
			prompt.ClickablePrompt = true
		end)
	end

	if promptTriggeredConn == nil then
		promptTriggeredConn = ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, playerWhoTriggered: Player)
			if playerWhoTriggered ~= Players.LocalPlayer then
				return
			end

			if prompt.Name == "RescuePrompt" then
				local now = os.clock()
				if (now - lastRescuePromptClock) < RESCUE_PROMPT_DEBOUNCE_SECONDS then
					return
				end
				lastRescuePromptClock = now
				CrackController.TryStartFromPrompt(prompt)
				return
			end

			if
				prompt.Name == "IncubatorPrompt"
				or prompt.Name == "PenPrompt"
				or prompt.Name == "SellPrompt"
				or prompt.Name == "LurePrompt"
				or prompt.Name == "UpgradePrompt"
			then
				handleRanchPromptFeedback(prompt)
			end
		end)
	end

	if inputBeganConn == nil then
		inputBeganConn = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
			local key = input.KeyCode

			if CrackController.IsCracking() then
				if key == Enum.KeyCode.E or key == Enum.KeyCode.Space or key == Enum.KeyCode.ButtonX then
					CrackController.TryTriggerSweetSpot()
					return
				end
			end

			if gameProcessed then
				return
			end

			if key == Enum.KeyCode.B or key == Enum.KeyCode.ButtonY then
				SoundController.Play("Click")
				UIController.ToggleBag()
			elseif key == Enum.KeyCode.G or key == Enum.KeyCode.ButtonL1 then
				SoundController.Play("Click")
				UIController.ToggleFieldGuide()
			elseif (key == Enum.KeyCode.Escape or key == Enum.KeyCode.ButtonB) and UIController.IsDrawerOpen() then
				SoundController.Play("Click")
				UIController.CloseDrawers()
			end
		end)
	end
end

function InputController.GetInputMode(): UIController.InputMode
	return currentInputMode
end

return InputController
