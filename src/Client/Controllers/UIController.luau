--!strict
--[[
	Controller: UIController
	Purpose: Receives OwnerStateDTO snapshots from SyncOwnerState and manages the Safe-Area responsive HUD,
	         non-blocking contextual guidance, toasts, Keep-vs-Sell Bag drawer (preserving Gamepad focus &
	         scroll across Coin ticks), and Accessibility Settings.
	Connections: Requires SoundController and PlotVisualController; communicates with RequestPlotAction and RequestBuyUpgrade.
	How to Test in Studio: Press Play (F5), check HUD layout across 320px+ viewports, press Bag (B / Y), verify
	                       focus & scroll survive passive Coin updates, and test Keep-vs-Sell & Settings toggles.
]]

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local ControllersFolder = script.Parent
local SoundController = require(ControllersFolder:WaitForChild("SoundController"))
local PlotVisualController = require(ControllersFolder:WaitForChild("PlotVisualController"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Types = require(Shared:WaitForChild("Types"))
local ConfigFolder = Shared:WaitForChild("Config")
local CritterConfig = require(ConfigFolder:WaitForChild("CritterConfig"))
local MeteorConfig = require(ConfigFolder:WaitForChild("MeteorConfig"))
local UpgradeConfig = require(ConfigFolder:WaitForChild("UpgradeConfig"))
local EconomyMath = require(Shared:WaitForChild("Util"):WaitForChild("EconomyMath"))
local FormatUtil = require(Shared:WaitForChild("Util"):WaitForChild("FormatUtil"))

export type InputMode = "Touch" | "Keyboard" | "Gamepad"
export type ToastKind = "Info" | "Success" | "Warn"

export type TopHudLayout = {
	Stacked: boolean,
	ResourceX: number,
	ResourceY: number,
	ResourceWidth: number,
	ResourceHeight: number,
	ActionsX: number,
	ActionsY: number,
	ActionsWidth: number,
	ActionsHeight: number,
	ToastY: number,
	SettingsX: number,
	SettingsY: number,
	SettingsWidth: number,
}

export type DrawerLayout = {
	X: number,
	Y: number,
	Width: number,
	Height: number,
}

type TimerBinding = {
	Label: TextLabel,
	MaturesAt: number,
	DisplayName: string,
	WasMature: boolean,
}

local WIDE_TOP_HUD_MIN_WIDTH = 560
local ACTION_TRAY_WIDTH = 288
local SETTINGS_DRAWER_HEIGHT = 272

local PALETTE = {
	PanelDark = Color3.fromRGB(24, 22, 38),
	CardDark = Color3.fromRGB(36, 33, 56),
	BorderSoft = Color3.fromRGB(78, 72, 114),
	TextCream = Color3.fromRGB(245, 240, 232),
	TextMuted = Color3.fromRGB(185, 180, 205),
	OrbitalCyan = Color3.fromRGB(65, 210, 255),
	StarlightGold = Color3.fromRGB(255, 205, 45),
	MeadowMint = Color3.fromRGB(95, 215, 145),
	AstralViolet = Color3.fromRGB(205, 115, 255),
	EmberCoral = Color3.fromRGB(255, 120, 80),
	DangerRed = Color3.fromRGB(220, 72, 72),
}

local UIController = {
	Name = "UIController",
}

local latestOwnerState: Types.OwnerStateDTO? = nil
local stateChangedCallbacks: { (dto: Types.OwnerStateDTO) -> () } = {}
local syncConn: RBXScriptConnection? = nil
local sizeChangedConn: RBXScriptConnection? = nil
local layoutChangedConn: RBXScriptConnection? = nil
local guideLayoutChangedConn: RBXScriptConnection? = nil
local plotActionRemote: RemoteEvent? = nil
local buyUpgradeRemote: RemoteFunction? = nil
local navigateRemote: RemoteFunction? = nil
local navigateDispatcher: ((target: Types.NavigationTarget, customInvoker: ((Types.NavigationTarget) -> any)?) -> boolean)? = nil

local hudGui: ScreenGui? = nil
local resourceBarFrame: Frame? = nil
local actionRowFrame: Frame? = nil
local coinsLabel: TextLabel? = nil
local rateLabel: TextLabel? = nil
local bagLabel: TextLabel? = nil
local hubButton: TextButton? = nil
local ranchButton: TextButton? = nil
local bagButton: TextButton? = nil
local guideButton: TextButton? = nil
local settingsButton: TextButton? = nil
local toastLabel: TextLabel? = nil
local hintBarFrame: Frame? = nil
local hintLabel: TextLabel? = nil

local bagDrawer: Frame? = nil
local bagCapacityLabel: TextLabel? = nil
local bagScrollFrame: ScrollingFrame? = nil
local bagScrollLayout: UIListLayout? = nil
local bagCloseButton: TextButton? = nil
local firstBagSelectable: GuiObject? = nil
local bagButtonsByKey: { [string]: GuiObject } = {}
local upgradeBuyButtons: { [Types.UpgradeId]: TextButton } = {}
local feedButtonsBySlot: { [string]: TextButton } = {}
local frostLureButton: TextButton? = nil
local lastFocusedBagKey: string? = nil
local lastBagStructureSignature: string? = nil
local bagRebuildCount = 0
local bagRestoreToken = 0
local bagRestoreInFlight = false

local guideDrawer: Frame? = nil
local guideProgressLabel: TextLabel? = nil
local guideProgressFill: Frame? = nil
local guideScrollFrame: ScrollingFrame? = nil
local guideScrollLayout: UIListLayout? = nil
local guideCloseButton: TextButton? = nil
local firstGuideSelectable: GuiObject? = nil
local guideButtonsByKey: { [string]: GuiObject } = {}
local lastFocusedGuideKey: string? = nil
local lastGuideStructureSignature: string? = nil
local guideRebuildCount = 0
local guideRestoreToken = 0
local guideRestoreInFlight = false

local settingsDrawer: Frame? = nil
local muteToggleButton: TextButton? = nil
local motionToggleButton: TextButton? = nil
local perfToggleButton: TextButton? = nil
local controlsHintLabel: TextLabel? = nil

local perfOverlayFrame: Frame? = nil
local perfLine1Label: TextLabel? = nil
local perfLine2Label: TextLabel? = nil
local perfRenderConn: RBXScriptConnection? = nil
local perfOverlayEnabled = false
local perfStartClock = 0
local perfWindowFrames = 0
local perfWindowDt = 0
local perfTotalFrames = 0
local perfTotalDt = 0
local perfMinFps = math.huge
local perfLastLogMinute = -1
local perfBaselineMemMb = 0

local bagOpen = false
local guideOpen = false
local settingsOpen = false
local currentInputMode: InputMode = "Keyboard"
local toastToken = 0
local pendingSellConfirmUID: string? = nil
local pendingSellConfirmExpiresAt = 0
local pendingUpgradeBuy = false
local pendingNavigate = false
local lastNavRequestClock = -Constants.NAVIGATE_CLIENT_COOLDOWN_SECONDS
local activeTimerBindings: { TimerBinding } = {}
local timerLoopStarted = false

local function addCorner(inst: GuiObject, radiusPx: number): ()
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radiusPx)
	corner.Parent = inst
end

local function addStroke(inst: GuiObject, color: Color3, thickness: number): ()
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = inst
end

local function makeTextButton(
	parent: Instance,
	name: string,
	text: string,
	bgColor: Color3,
	textColor: Color3,
	size: UDim2,
	textSize: number?
): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Size = size
	btn.BackgroundColor3 = bgColor
	btn.TextColor3 = textColor
	btn.Text = text
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = textSize or 15
	btn.AutoButtonColor = true
	btn.Selectable = true
	btn.BorderSizePixel = 0
	addCorner(btn, 10)
	btn.Parent = parent
	return btn
end

local function trapGamepadFocus(frame: Frame): ()
	frame.SelectionGroup = true
	frame.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	frame.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	frame.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	frame.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
end

function UIController.ComputeTopHudLayout(safeWidth: number): TopHudLayout
	local width = if typeof(safeWidth) == "number" and safeWidth == safeWidth and safeWidth > 0 then safeWidth else 320

	if width >= WIDE_TOP_HUD_MIN_WIDTH then
		local actWidth = ACTION_TRAY_WIDTH
		local resWidth = math.clamp(width - 28 - actWidth, 180, 380)
		local settingsWidth = 278
		return {
			Stacked = false,
			ResourceX = 10,
			ResourceY = 8,
			ResourceWidth = resWidth,
			ResourceHeight = 42,
			ActionsX = width - 10 - actWidth,
			ActionsY = 8,
			ActionsWidth = actWidth,
			ActionsHeight = 44,
			ToastY = 58,
			SettingsX = width - 10 - settingsWidth,
			SettingsY = 58,
			SettingsWidth = settingsWidth,
		}
	end

	local resWidth = math.max(200, width - 16)
	local actWidth = math.min(ACTION_TRAY_WIDTH, math.max(138, width - 16))
	local settingsWidth = math.clamp(width - 16, 220, 278)
	return {
		Stacked = true,
		ResourceX = math.floor((width - resWidth) * 0.5),
		ResourceY = 8,
		ResourceWidth = resWidth,
		ResourceHeight = 40,
		ActionsX = width - 8 - actWidth,
		ActionsY = 54,
		ActionsWidth = actWidth,
		ActionsHeight = 44,
		ToastY = 104,
		SettingsX = width - 8 - settingsWidth,
		SettingsY = 104,
		SettingsWidth = settingsWidth,
	}
end

function UIController.ComputeDrawerLayout(safeWidth: number, safeHeight: number): DrawerLayout
	local w = if typeof(safeWidth) == "number" and safeWidth == safeWidth and safeWidth > 0 then safeWidth else 320
	local h = if typeof(safeHeight) == "number" and safeHeight == safeHeight and safeHeight > 0 then safeHeight else 568
	local topLayout = UIController.ComputeTopHudLayout(w)
	local topClear = math.max(topLayout.ResourceY + topLayout.ResourceHeight, topLayout.ActionsY + topLayout.ActionsHeight) + 6
	local availH = math.max(180, h - topClear - 10)
	local drawerW = math.clamp(math.floor(w * 0.94), math.min(280, w - 12), 600)
	local drawerH = math.clamp(math.floor(h * 0.72), math.min(210, availH), math.min(520, availH))
	local drawerX = math.floor((w - drawerW) * 0.5)
	local drawerY = math.clamp(math.floor((h - drawerH) * 0.5), topClear, math.max(topClear, h - drawerH - 6))
	return {
		X = drawerX,
		Y = drawerY,
		Width = drawerW,
		Height = drawerH,
	}
end

local function applyResponsiveTopLayout(): ()
	local screenGui = hudGui
	if screenGui == nil then
		return
	end

	local rawWidth = screenGui.AbsoluteSize.X
	local rawHeight = screenGui.AbsoluteSize.Y
	local safeWidth = if rawWidth > 0 then rawWidth else 320
	local safeHeight = if rawHeight > 0 then rawHeight else 568
	local layout = UIController.ComputeTopHudLayout(safeWidth)
	local dLayout = UIController.ComputeDrawerLayout(safeWidth, safeHeight)

	if resourceBarFrame ~= nil then
		resourceBarFrame.AnchorPoint = Vector2.new(0, 0)
		resourceBarFrame.Position = UDim2.fromOffset(layout.ResourceX, layout.ResourceY)
		resourceBarFrame.Size = UDim2.fromOffset(layout.ResourceWidth, layout.ResourceHeight)
	end
	if actionRowFrame ~= nil then
		actionRowFrame.AnchorPoint = Vector2.new(0, 0)
		actionRowFrame.Position = UDim2.fromOffset(layout.ActionsX, layout.ActionsY)
		actionRowFrame.Size = UDim2.fromOffset(layout.ActionsWidth, layout.ActionsHeight)
	end
	if toastLabel ~= nil then
		toastLabel.Position = UDim2.new(0.5, 0, 0, layout.ToastY)
	end
	if perfOverlayFrame ~= nil then
		local perfWidth = math.min(296, safeWidth - 20)
		perfOverlayFrame.AnchorPoint = Vector2.new(0, 0)
		perfOverlayFrame.Position = UDim2.fromOffset(10, layout.ToastY)
		perfOverlayFrame.Size = UDim2.fromOffset(perfWidth, 44)
	end
	if bagDrawer ~= nil then
		bagDrawer.AnchorPoint = Vector2.new(0, 0)
		bagDrawer.Position = UDim2.fromOffset(dLayout.X, dLayout.Y)
		bagDrawer.Size = UDim2.fromOffset(dLayout.Width, dLayout.Height)
	end
	if guideDrawer ~= nil then
		guideDrawer.AnchorPoint = Vector2.new(0, 0)
		guideDrawer.Position = UDim2.fromOffset(dLayout.X, dLayout.Y)
		guideDrawer.Size = UDim2.fromOffset(dLayout.Width, dLayout.Height)
	end
	if settingsDrawer ~= nil then
		settingsDrawer.AnchorPoint = Vector2.new(0, 0)
		settingsDrawer.Position = UDim2.fromOffset(layout.SettingsX, layout.SettingsY)
		settingsDrawer.Size = UDim2.fromOffset(layout.SettingsWidth, SETTINGS_DRAWER_HEIGHT)
	end
end

function UIController.ComputeGuideStructureSignature(dto: Types.OwnerStateDTO): string
	local radiantBySpecies: { [Types.SpeciesId]: boolean } = {}
	for _, item in pairs(dto.Items) do
		if item.Variant == "Radiant" then
			radiantBySpecies[item.SpeciesId] = true
		end
	end
	local parts: { string } = {}
	for _, speciesId in ipairs(CritterConfig.OrderedIds) do
		local discFlag = if dto.DiscoveredSpecies[speciesId] == true then "1" else "0"
		local radFlag = if radiantBySpecies[speciesId] == true then "1" else "0"
		table.insert(parts, string.format("%s:%s:%s", speciesId, discFlag, radFlag))
	end
	return table.concat(parts, ";")
end

function UIController.ComputeBagStructureSignature(dto: Types.OwnerStateDTO, pendingSellUID: string?): string
	local itemKeys: { string } = {}
	for uid in pairs(dto.Items) do
		table.insert(itemKeys, uid)
	end
	table.sort(itemKeys)

	local parts: { string } = {
		string.format("cap:%d|res:%d|sell:%s", dto.BagCap, dto.ReservedBagSlots or 0, pendingSellUID or ""),
	}

	for _, upgradeId in ipairs(UpgradeConfig.OrderedIds) do
		table.insert(parts, string.format("u:%s=%s", upgradeId, if dto.Upgrades[upgradeId] == true then "1" else "0"))
	end

	for _, speciesId in ipairs(CritterConfig.OrderedIds) do
		table.insert(
			parts,
			string.format("d:%s=%s", speciesId, if dto.DiscoveredSpecies[speciesId] == true then "1" else "0")
		)
	end

	for _, uid in ipairs(itemKeys) do
		local item = dto.Items[uid]
		table.insert(
			parts,
			string.format(
				"i:%s|%s|%s|%s|%s|%s|%s",
				item.UID,
				item.SpeciesId,
				item.Variant,
				item.State,
				item.AssignedSlot or "",
				tostring(item.MaturesAt or 0),
				tostring(item.FeedLevel or 0)
			)
		)
	end

	return table.concat(parts, ";")
end

local function countBagAndIncome(dto: Types.OwnerStateDTO): (number, number, number, number)
	local bagCount = 0
	local totalRate = 0
	local penCount = 0
	local incubatingCount = 0
	for _, item in pairs(dto.Items) do
		if item.State == "PodInBag" or item.State == "HatchedInBag" then
			bagCount += 1
		elseif item.State == "Incubating" then
			incubatingCount += 1
		elseif item.State == "InPen" then
			penCount += 1
			totalRate += EconomyMath.GetCritterCoinsPerSecond(item.SpeciesId, item.Variant, item.FeedLevel)
		end
	end
	return bagCount, incubatingCount, penCount, totalRate
end

local function findEmptyUnlockedIncubator(dto: Types.OwnerStateDTO): string?
	if dto.Slots["Incubator_1"] == nil then
		return "Incubator_1"
	end
	if dto.Upgrades["Incubator_2"] == true and dto.Slots["Incubator_2"] == nil then
		return "Incubator_2"
	end
	return nil
end

local function findEmptyUnlockedPen(dto: Types.OwnerStateDTO): string?
	if dto.Slots["Pen_1"] == nil then
		return "Pen_1"
	end
	if dto.Upgrades["PenSlot_2"] == true and dto.Slots["Pen_2"] == nil then
		return "Pen_2"
	end
	if dto.Upgrades["PenSlot_3"] == true and dto.Slots["Pen_3"] == nil then
		return "Pen_3"
	end
	if dto.Upgrades["PenSlot_4"] == true and dto.Slots["Pen_4"] == nil then
		return "Pen_4"
	end
	if dto.Upgrades["PenSlot_5"] == true and dto.Slots["Pen_5"] == nil then
		return "Pen_5"
	end
	return nil
end

local function isWithinStationRange(stationKind: string, targetId: string): (boolean, string)
	local player = Players.LocalPlayer
	if player == nil then
		return false, "PlayerUnavailable"
	end
	local char = player.Character
	local humanoid = if char ~= nil then char:FindFirstChildOfClass("Humanoid") else nil
	local rootPart = if char ~= nil then char:FindFirstChild("HumanoidRootPart") else nil
	if humanoid == nil or humanoid.Health <= 0 or rootPart == nil or not rootPart:IsA("BasePart") then
		return false, "CharacterUnavailable"
	end

	local anchor = PlotVisualController.GetStationPartForUserId(player.UserId, stationKind, targetId)
	if anchor == nil then
		return false, "MissingStation"
	end

	local dist = (rootPart.Position - anchor.Position).Magnitude
	if dist ~= dist or dist > Constants.MAX_STATION_INTERACT_DISTANCE then
		return false, "OutOfRange"
	end
	return true, "Ok"
end

function UIController.ShowToast(message: string, kind: ToastKind?): ()
	local label = toastLabel
	if label == nil then
		return
	end

	toastToken += 1
	local myToken = toastToken
	local resolvedKind: ToastKind = kind or "Info"
	if resolvedKind == "Success" then
		label.BackgroundColor3 = Color3.fromRGB(28, 72, 54)
		label.TextColor3 = PALETTE.MeadowMint
	elseif resolvedKind == "Warn" then
		label.BackgroundColor3 = Color3.fromRGB(82, 42, 34)
		label.TextColor3 = PALETTE.StarlightGold
	else
		label.BackgroundColor3 = PALETTE.PanelDark
		label.TextColor3 = PALETTE.OrbitalCyan
	end

	label.Text = message
	label.Visible = true

	task.delay(2.8, function()
		if toastToken == myToken and toastLabel ~= nil then
			toastLabel.Visible = false
		end
	end)
end

local function updateActionButtonsText(): ()
	local btn = bagButton
	if btn ~= nil then
		local count = 0
		if latestOwnerState ~= nil then
			local bCount = countBagAndIncome(latestOwnerState)
			count = bCount
		end
		btn.Text = string.format("Bag (%d)", count)
	end
	if settingsButton ~= nil then
		settingsButton.Text = "⚙"
	end

	if controlsHintLabel ~= nil then
		if currentInputMode == "Touch" then
			controlsHintLabel.Text = "Touch: Tap Meteors, Prompts, Bag & Guide buttons"
		elseif currentInputMode == "Gamepad" then
			controlsHintLabel.Text = "Gamepad: X Rescue | Y Bag | L1 Guide | B Close Drawer"
		else
			controlsHintLabel.Text = "Keyboard: E Interact / Space Burst | B Bag | G Guide"
		end
	end
end

local function readPerfStatsSnapshot(): (number, number, number, number)
	local okTotal, rawTotal = pcall(function()
		return Stats:GetTotalMemoryUsageMb()
	end)
	local totalMem = if okTotal and typeof(rawTotal) == "number" then rawTotal else 0

	local okLua, rawLua = pcall(function()
		return Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.LuaHeap)
	end)
	local luaMem = if okLua and typeof(rawLua) == "number" then rawLua else 0

	local visualsFolder = workspace:FindFirstChild("StarfallClientVisuals")
	local visCount = if visualsFolder ~= nil then #visualsFolder:GetChildren() else 0
	local metCount = #CollectionService:GetTagged(Constants.TAG_ACTIVE_METEOR)

	return totalMem, luaMem, visCount, metCount
end

local function updatePerfReadout(fps: number, avgFps: number, minFps: number, frameMs: number, elapsedSec: number, emitLog: boolean): ()
	local totalMem, luaMem, visCount, metCount = readPerfStatsSnapshot()
	local deltaMem = totalMem - perfBaselineMemMb
	local deltaSign = if deltaMem >= 0 then "+" else ""
	local elapsedStr = FormatUtil.FormatTimer(math.floor(elapsedSec))

	if perfLine1Label ~= nil then
		if fps > 0 then
			perfLine1Label.Text = string.format(
				"FPS: %.0f (Avg %.0f / Min %.0f) | %.1fms | T+%s",
				fps,
				avgFps,
				minFps,
				frameMs,
				elapsedStr
			)
			perfLine1Label.TextColor3 = if fps >= 30
				then PALETTE.MeadowMint
				elseif fps >= 24 then PALETTE.StarlightGold
				else PALETTE.DangerRed
		else
			perfLine1Label.Text = string.format("FPS: sampling... | T+%s", elapsedStr)
			perfLine1Label.TextColor3 = PALETTE.OrbitalCyan
		end
	end

	if perfLine2Label ~= nil then
		perfLine2Label.Text = string.format("Mem: %.0fMB (%s%.0f) | Vis: %d | Met: %d", totalMem, deltaSign, deltaMem, visCount, metCount)
	end

	if emitLog then
		if fps > 0 then
			print(string.format(
				"[SoakTelemetry] Elapsed=%s | FPS=%.1f (Avg=%.1f Min=%.1f) | FrameMs=%.1f | TotalMemMB=%.1f | DeltaMemMB=%s%.1f | LuaHeapMB=%.1f | Visuals=%d | Meteors=%d",
				elapsedStr,
				fps,
				avgFps,
				minFps,
				frameMs,
				totalMem,
				deltaSign,
				deltaMem,
				luaMem,
				visCount,
				metCount
			))
		else
			print(string.format(
				"[SoakTelemetry] Elapsed=%s | BaselineTotalMemMB=%.1f | DeltaMemMB=+0.0 | LuaHeapMB=%.1f | Visuals=%d | Meteors=%d",
				elapsedStr,
				totalMem,
				luaMem,
				visCount,
				metCount
			))
		end
	end
end

local function updatePerfToggleButtonUI(): ()
	if perfToggleButton ~= nil then
		perfToggleButton.Text = if perfOverlayEnabled then "Soak Perf Stats: ON" else "Soak Perf Stats: OFF"
		perfToggleButton.BackgroundColor3 = if perfOverlayEnabled then PALETTE.OrbitalCyan else PALETTE.CardDark
		perfToggleButton.TextColor3 = if perfOverlayEnabled then PALETTE.PanelDark else PALETTE.TextCream
	end
end

local function setPerfOverlayEnabled(enabled: boolean): ()
	if perfRenderConn ~= nil then
		perfRenderConn:Disconnect()
		perfRenderConn = nil
	end

	perfOverlayEnabled = enabled
	updatePerfToggleButtonUI()

	if perfOverlayFrame ~= nil then
		perfOverlayFrame.Visible = enabled
	end

	if not enabled then
		return
	end

	perfStartClock = os.clock()
	perfWindowFrames = 0
	perfWindowDt = 0
	perfTotalFrames = 0
	perfTotalDt = 0
	perfMinFps = math.huge
	perfLastLogMinute = 0
	local baseTotal = readPerfStatsSnapshot()
	perfBaselineMemMb = baseTotal
	updatePerfReadout(0, 0, 0, 0, 0, true)

	perfRenderConn = RunService.RenderStepped:Connect(function(dt: number)
		if not perfOverlayEnabled then
			return
		end
		if typeof(dt) ~= "number" or dt ~= dt or dt <= 0 then
			return
		end

		perfWindowFrames += 1
		perfWindowDt += dt
		perfTotalFrames += 1
		perfTotalDt += dt

		if perfWindowDt >= 1.0 then
			local fps = perfWindowFrames / perfWindowDt
			local avgFps = perfTotalFrames / math.max(0.001, perfTotalDt)
			perfMinFps = math.min(perfMinFps, fps)
			local frameMs = (perfWindowDt / perfWindowFrames) * 1000
			local elapsed = math.max(0, os.clock() - perfStartClock)
			local minuteIdx = math.floor(elapsed / 60)
			local shouldLog = minuteIdx > perfLastLogMinute
			if shouldLog then
				perfLastLogMinute = minuteIdx
			end

			updatePerfReadout(fps, avgFps, perfMinFps, frameMs, elapsed, shouldLog)
			perfWindowFrames = 0
			perfWindowDt = 0
		end
	end)
end

local function updateSettingsTogglesUI(muted: boolean, reducedMotion: boolean): ()
	if muteToggleButton ~= nil then
		muteToggleButton.Text = if muted then "Mute Sound: ON" else "Mute Sound: OFF"
		muteToggleButton.BackgroundColor3 = if muted then PALETTE.EmberCoral else PALETTE.CardDark
		muteToggleButton.TextColor3 = if muted then PALETTE.PanelDark else PALETTE.TextCream
	end
	if motionToggleButton ~= nil then
		motionToggleButton.Text = if reducedMotion then "Reduced Motion: ON" else "Reduced Motion: OFF"
		motionToggleButton.BackgroundColor3 = if reducedMotion then PALETTE.OrbitalCyan else PALETTE.CardDark
		motionToggleButton.TextColor3 = if reducedMotion then PALETTE.PanelDark else PALETTE.TextCream
	end
	updatePerfToggleButtonUI()
end

local function updateContextualHint(): ()
	local label = hintLabel
	local bar = hintBarFrame
	if label == nil then
		return
	end

	local dto = latestOwnerState
	if dto == nil then
		label.Text = "Connecting to Ranch..."
		label.TextColor3 = PALETTE.StarlightGold
		if bar ~= nil then
			bar.Visible = true
		end
		return
	end

	local nowClock = workspace:GetServerTimeNow()
	local hasMatureIncubator = false
	local shortestRemaining = math.huge
	local hasPodInBag = false
	local hasHatchedInBag = false
	local activePenCount = 0

	for _, item in pairs(dto.Items) do
		if item.State == "Incubating" and item.MaturesAt ~= nil then
			local rem = item.MaturesAt - nowClock
			if rem <= 0 then
				hasMatureIncubator = true
			elseif rem < shortestRemaining then
				shortestRemaining = rem
			end
		elseif item.State == "PodInBag" then
			hasPodInBag = true
		elseif item.State == "HatchedInBag" then
			hasHatchedInBag = true
		elseif item.State == "InPen" then
			activePenCount += 1
		end
	end

	local freePen = findEmptyUnlockedPen(dto)
	local freeIncubator = findEmptyUnlockedIncubator(dto)

	if hasMatureIncubator then
		label.Text = "Hatch Ready at your Incubator!"
		label.TextColor3 = PALETTE.StarlightGold
		if bar ~= nil then
			bar.Visible = true
		end
	elseif activePenCount == 0 then
		if hasHatchedInBag and freePen ~= nil then
			label.Text = "Walk to Pen #1 to place your Critter!"
			label.TextColor3 = PALETTE.MeadowMint
		elseif hasPodInBag and freeIncubator ~= nil then
			label.Text = "Walk to Incubator #1 to hatch!"
			label.TextColor3 = PALETTE.OrbitalCyan
		elseif shortestRemaining < math.huge then
			label.Text = string.format("Hatching (%s) — crack Basin Meteors!", FormatUtil.FormatTimer(shortestRemaining))
			label.TextColor3 = PALETTE.TextCream
		else
			label.Text = "Rescue your glowing Starter Meteor!"
			label.TextColor3 = PALETTE.StarlightGold
		end
		if bar ~= nil then
			bar.Visible = true
		end
	else
		if bar ~= nil then
			bar.Visible = false
		end
	end
end

local function syncScrollCanvasSize(scroll: ScrollingFrame?, layout: UIListLayout?, minHeight: number?): ()
	if scroll == nil or layout == nil then
		return
	end
	local contentH = math.ceil(layout.AbsoluteContentSize.Y) + 16
	if minHeight ~= nil then
		contentH = math.max(contentH, minHeight)
	end
	scroll.CanvasSize = UDim2.fromOffset(0, contentH)
end

local function getMaxScrollY(scroll: ScrollingFrame?, layout: UIListLayout?): number
	if scroll == nil then
		return 0
	end
	local layoutH = if layout ~= nil then math.ceil(layout.AbsoluteContentSize.Y) + 16 else 0
	local canvasH = math.max(scroll.AbsoluteCanvasSize.Y, layoutH)
	return math.max(0, canvasH - scroll.AbsoluteWindowSize.Y)
end

local function syncBagCanvasSize(minHeight: number?): ()
	syncScrollCanvasSize(bagScrollFrame, bagScrollLayout, minHeight)
end

local function getMaxBagScrollY(): number
	return getMaxScrollY(bagScrollFrame, bagScrollLayout)
end

local function canSelectGuiObject(target: GuiObject?): boolean
	if target == nil then
		return false
	end
	if not GuiService.GuiNavigationEnabled then
		return false
	end
	local root = hudGui
	if root == nil or not root.Enabled or not target:IsDescendantOf(root) then
		return false
	end
	if not target.Selectable or not target.Visible then
		return false
	end

	local current: Instance? = target.Parent
	while current ~= nil and current ~= root do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		current = current.Parent
	end

	local absSize = target.AbsoluteSize
	if absSize.X <= 0 or absSize.Y <= 0 then
		return false
	end
	return true
end

local function safeSetSelectedObject(target: GuiObject?): boolean
	if target == nil then
		GuiService.SelectedObject = nil
		return true
	end
	if not canSelectGuiObject(target) then
		return false
	end
	GuiService.SelectedObject = target
	return GuiService.SelectedObject == target
end

local function resolveBagSelectionTarget(preferredKey: string?): GuiObject?
	if preferredKey ~= nil then
		if bagButtonsByKey[preferredKey] ~= nil then
			return bagButtonsByKey[preferredKey]
		end
		if preferredKey == "CloseBag" and bagCloseButton ~= nil then
			return bagCloseButton
		end
	end
	return firstBagSelectable or bagCloseButton
end

local function resolveGuideSelectionTarget(preferredKey: string?): GuiObject?
	if preferredKey ~= nil then
		if guideButtonsByKey[preferredKey] ~= nil then
			return guideButtonsByKey[preferredKey]
		end
		if preferredKey == "CloseGuide" and guideCloseButton ~= nil then
			return guideCloseButton
		end
	end
	return firstGuideSelectable or guideCloseButton
end

local rebuildBagContents: (preserveFocusAndScroll: boolean?) -> ()
local rebuildFieldGuideContents: (preserveFocusAndScroll: boolean?) -> ()

local function applyDrawerVisibility(preferredBagKey: string?, preferredGuideKey: string?): ()
	if bagDrawer ~= nil then
		bagDrawer.Visible = bagOpen
	end
	if guideDrawer ~= nil then
		guideDrawer.Visible = guideOpen
	end
	if settingsDrawer ~= nil then
		settingsDrawer.Visible = settingsOpen
	end

	if currentInputMode ~= "Gamepad" then
		return
	end

	if bagOpen then
		if not bagRestoreInFlight then
			local currentSelected = GuiService.SelectedObject
			local insideBag = currentSelected ~= nil and bagDrawer ~= nil and currentSelected:IsDescendantOf(bagDrawer)
			if preferredBagKey ~= nil or not insideBag then
				local target = resolveBagSelectionTarget(preferredBagKey or lastFocusedBagKey)
				safeSetSelectedObject(target)
			end
		end
	elseif guideOpen then
		if not guideRestoreInFlight then
			local currentSelected = GuiService.SelectedObject
			local insideGuide = currentSelected ~= nil and guideDrawer ~= nil and currentSelected:IsDescendantOf(guideDrawer)
			if preferredGuideKey ~= nil or not insideGuide then
				local target = resolveGuideSelectionTarget(preferredGuideKey or lastFocusedGuideKey)
				safeSetSelectedObject(target)
			end
		end
	elseif settingsOpen then
		local currentSelected = GuiService.SelectedObject
		local insideSettings = currentSelected ~= nil and settingsDrawer ~= nil and currentSelected:IsDescendantOf(settingsDrawer)
		if not insideSettings then
			if canSelectGuiObject(muteToggleButton) then
				safeSetSelectedObject(muteToggleButton)
			else
				task.spawn(function()
					RunService.RenderStepped:Wait()
					if settingsOpen and currentInputMode == "Gamepad" then
						safeSetSelectedObject(muteToggleButton)
					end
				end)
			end
		end
	else
		safeSetSelectedObject(nil)
	end
end

local function refreshUpgradeAffordabilityInPlace(dto: Types.OwnerStateDTO): ()
	for _, upgradeId in ipairs(UpgradeConfig.OrderedIds) do
		local btn = upgradeBuyButtons[upgradeId]
		if btn ~= nil then
			local def = UpgradeConfig.ById[upgradeId]
			local canAfford = dto.Coins >= def.Cost
			btn.BackgroundColor3 = if canAfford then PALETTE.MeadowMint else PALETTE.CardDark
			btn.TextColor3 = if canAfford then PALETTE.PanelDark else PALETTE.TextMuted
		end
	end

	local canFeed = dto.Coins >= Constants.CRITTER_FEED_COST
	for _, feedBtn in pairs(feedButtonsBySlot) do
		feedBtn.BackgroundColor3 = if canFeed then PALETTE.MeadowMint else PALETTE.CardDark
		feedBtn.TextColor3 = if canFeed then PALETTE.PanelDark else PALETTE.TextMuted
	end

	if frostLureButton ~= nil then
		local canLure = dto.Upgrades["FrostCracker"] == true and dto.Coins >= Constants.FROST_LURE_COST
		frostLureButton.BackgroundColor3 = if canLure then PALETTE.MeadowMint else PALETTE.CardDark
		frostLureButton.TextColor3 = if canLure then PALETTE.PanelDark else PALETTE.TextMuted
	end
end

local function createSectionHeader(parent: Instance, title: string, accent: Color3, layoutOrder: number): ()
	local header = Instance.new("TextLabel")
	header.Name = "Section_" .. title
	header.Size = UDim2.new(1, 0, 0, 26)
	header.BackgroundTransparency = 1
	header.Text = title
	header.TextColor3 = accent
	header.Font = Enum.Font.GothamBold
	header.TextSize = 14
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.LayoutOrder = layoutOrder
	header.Parent = parent
end

local function createEmptyNote(parent: Instance, text: string, layoutOrder: number): ()
	local note = Instance.new("TextLabel")
	note.Size = UDim2.new(1, 0, 0, 30)
	note.BackgroundColor3 = PALETTE.CardDark
	note.BackgroundTransparency = 0.4
	note.TextColor3 = PALETTE.TextMuted
	note.Text = text
	note.Font = Enum.Font.GothamMedium
	note.TextSize = 13
	note.LayoutOrder = layoutOrder
	addCorner(note, 8)
	note.Parent = parent
end

local function createRowCard(parent: Instance, swatchColor: Color3, layoutOrder: number): (Frame, TextLabel, TextLabel)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 62)
	row.BackgroundColor3 = PALETTE.CardDark
	row.BorderSizePixel = 0
	row.LayoutOrder = layoutOrder
	addCorner(row, 10)
	addStroke(row, PALETTE.BorderSoft, 1)
	row.Parent = parent

	local swatch = Instance.new("Frame")
	swatch.Size = UDim2.fromOffset(10, 44)
	swatch.Position = UDim2.new(0, 8, 0.5, -22)
	swatch.BackgroundColor3 = swatchColor
	swatch.BorderSizePixel = 0
	addCorner(swatch, 4)
	swatch.Parent = row

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -190, 0, 24)
	title.Position = UDim2.fromOffset(24, 7)
	title.BackgroundTransparency = 1
	title.TextColor3 = PALETTE.TextCream
	title.Font = Enum.Font.GothamBold
	title.TextSize = 14
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Parent = row

	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.new(1, -190, 0, 20)
	subtitle.Position = UDim2.fromOffset(24, 33)
	subtitle.BackgroundTransparency = 1
	subtitle.TextColor3 = PALETTE.TextMuted
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.TextSize = 12
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.TextTruncate = Enum.TextTruncate.AtEnd
	subtitle.Parent = row

	return row, title, subtitle
end

rebuildBagContents = function(preserveFocusAndScroll: boolean?): ()
	local scroll = bagScrollFrame
	if scroll == nil then
		return
	end

	local preserve = preserveFocusAndScroll == true
	local savedCanvasPos = if preserve then scroll.CanvasPosition else Vector2.zero
	local prevCanvasHeight = if preserve then math.max(scroll.AbsoluteCanvasSize.Y, scroll.CanvasSize.Y.Offset, 1) else 0
	local preferredKey: string? = nil
	if preserve then
		local currentSelected = GuiService.SelectedObject
		if currentSelected ~= nil and bagDrawer ~= nil and currentSelected:IsDescendantOf(bagDrawer) then
			local attr = currentSelected:GetAttribute("BagActionKey")
			if typeof(attr) == "string" then
				preferredKey = attr
			end
		end
		if preferredKey == nil then
			preferredKey = lastFocusedBagKey
		end
	end

	bagRestoreToken += 1
	local myToken = bagRestoreToken
	bagRestoreInFlight = true

	-- Keep CanvasSize height and clear selection before destroying rows so Roblox does not
	-- synchronously clamp CanvasPosition or log invalid SelectedObject fallback jumps.
	local currentSelected = GuiService.SelectedObject
	if currentSelected ~= nil and currentSelected:IsDescendantOf(scroll) then
		GuiService.SelectedObject = nil
	end
	if preserve then
		scroll.CanvasSize = UDim2.fromOffset(0, prevCanvasHeight)
	end

	for _, child in ipairs(scroll:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	activeTimerBindings = {}
	bagButtonsByKey = {}
	upgradeBuyButtons = {}
	feedButtonsBySlot = {}
	frostLureButton = nil
	firstBagSelectable = nil

	local function registerBagButton(actionKey: string, btn: GuiObject): ()
		btn:SetAttribute("BagActionKey", actionKey)
		bagButtonsByKey[actionKey] = btn
		btn.SelectionGained:Connect(function()
			lastFocusedBagKey = actionKey
		end)
		if firstBagSelectable == nil then
			firstBagSelectable = btn
		end
	end

	local dto = latestOwnerState
	if dto == nil then
		createEmptyNote(scroll, "Loading Ranch Bag...", 1)
		lastBagStructureSignature = nil
		syncBagCanvasSize(nil)
		bagRestoreInFlight = false
		applyDrawerVisibility(nil)
		return
	end

	local bagCount, incubatingCount = countBagAndIncome(dto)
	local committed = bagCount + incubatingCount
	if bagCapacityLabel ~= nil then
		bagCapacityLabel.Text = string.format(
			"Bag: %d/%d committed (%d in Incubators)",
			committed,
			dto.BagCap,
			dto.ReservedBagSlots or incubatingCount
		)
	end

	local hatchedList: { Types.CritterItemRecord } = {}
	local podList: { Types.CritterItemRecord } = {}
	local incubatingList: { Types.CritterItemRecord } = {}
	local inPenList: { Types.CritterItemRecord } = {}

	for _, item in pairs(dto.Items) do
		if item.State == "HatchedInBag" then
			table.insert(hatchedList, item)
		elseif item.State == "PodInBag" then
			table.insert(podList, item)
		elseif item.State == "Incubating" then
			table.insert(incubatingList, item)
		elseif item.State == "InPen" then
			table.insert(inPenList, item)
		end
	end

	local function sortItems(list: { Types.CritterItemRecord }): ()
		table.sort(list, function(a: Types.CritterItemRecord, b: Types.CritterItemRecord): boolean
			local defA = CritterConfig.ById[a.SpeciesId]
			local defB = CritterConfig.ById[b.SpeciesId]
			if defA.CoinsPerSecond ~= defB.CoinsPerSecond then
				return defA.CoinsPerSecond > defB.CoinsPerSecond
			end
			if a.Variant ~= b.Variant then
				return a.Variant == "Radiant"
			end
			if a.CreatedAt ~= b.CreatedAt then
				return a.CreatedAt < b.CreatedAt
			end
			return a.UID < b.UID
		end)
	end

	sortItems(hatchedList)
	sortItems(podList)
	sortItems(incubatingList)
	sortItems(inPenList)

	local order = 1
	local nowClock = workspace:GetServerTimeNow()

	-- 1. Hatched Critters (Keep vs. Sell)
	createSectionHeader(scroll, string.format("Hatched Critters — Keep vs. Sell (%d)", #hatchedList), PALETTE.MeadowMint, order)
	order += 1
	if #hatchedList == 0 then
		createEmptyNote(scroll, "No hatched critters in your Bag. Hatch a Star-Pod first!", order)
		order += 1
	else
		for _, item in ipairs(hatchedList) do
			local def = CritterConfig.ById[item.SpeciesId]
			local row, title, subtitle = createRowCard(scroll, def.BodyColor, order)
			order += 1

			local variantTag = if item.Variant == "Radiant" then " [RADIANT]" else ""
			local fedTag = if (item.FeedLevel or 0) >= 1 then " ★" else ""
			local effRate = EconomyMath.GetCritterCoinsPerSecond(item.SpeciesId, item.Variant, item.FeedLevel)
			local effSell = EconomyMath.GetCritterSellPrice(item.SpeciesId, item.Variant, item.FeedLevel)
			title.Text = def.DisplayName .. variantTag .. fedTag
			subtitle.Text = string.format("Keep: +%d Coins/s  |  Sell: +%d Coins", effRate, effSell)

			local placeBtn = makeTextButton(row, "PlaceBtn", "Place", PALETTE.MeadowMint, PALETTE.PanelDark, UDim2.fromOffset(72, 44), 13)
			placeBtn.Position = UDim2.new(1, -166, 0.5, -22)
			registerBagButton("Place:" .. item.UID, placeBtn)
			placeBtn.Activated:Connect(function()
				local currentDto = latestOwnerState
				if currentDto == nil then
					return
				end
				local freePen = findEmptyUnlockedPen(currentDto)
				if freePen == nil then
					SoundController.Play("Error")
					UIController.ShowToast("All unlocked Pen slots are full! Buy Slot #2 or Sell extras.", "Warn")
					return
				end
				local okRange = isWithinStationRange("Pen", freePen)
				if not okRange then
					SoundController.Play("Error")
					UIController.ShowToast("Walk closer to your open Pen Slot (" .. freePen .. ") to place!", "Warn")
					return
				end
				SoundController.Play("Click")
				if plotActionRemote ~= nil then
					plotActionRemote:FireServer("PlaceInPen", freePen, item.UID)
				end
			end)

			local isArmed = pendingSellConfirmUID == item.UID and os.clock() <= pendingSellConfirmExpiresAt
			local sellText = if isArmed then "Confirm Sell?" else string.format("Sell +%d", effSell)
			local sellBg = if isArmed then PALETTE.DangerRed else PALETTE.StarlightGold
			local sellFg = if isArmed then PALETTE.TextCream else PALETTE.PanelDark
			local sellBtn = makeTextButton(row, "SellBtn", sellText, sellBg, sellFg, UDim2.fromOffset(84, 44), 12)
			sellBtn.Position = UDim2.new(1, -88, 0.5, -22)
			registerBagButton("Sell:" .. item.UID, sellBtn)
			sellBtn.Activated:Connect(function()
				local okRange = isWithinStationRange("SellStand", "SellStand")
				if not okRange then
					SoundController.Play("Error")
					UIController.ShowToast("Walk closer to your Ranch Gate Sell Stand to sell!", "Warn")
					return
				end
				if pendingSellConfirmUID == item.UID and os.clock() <= pendingSellConfirmExpiresAt then
					pendingSellConfirmUID = nil
					pendingSellConfirmExpiresAt = 0
					SoundController.Play("Click")
					if plotActionRemote ~= nil then
						plotActionRemote:FireServer("SellCritter", item.UID)
					end
				else
					pendingSellConfirmUID = item.UID
					pendingSellConfirmExpiresAt = os.clock() + 3.0
					lastFocusedBagKey = "Sell:" .. item.UID
					SoundController.Play("Click")
					rebuildBagContents(true)
					task.delay(3.1, function()
						if pendingSellConfirmUID == item.UID and os.clock() > pendingSellConfirmExpiresAt then
							pendingSellConfirmUID = nil
							if bagOpen then
								rebuildBagContents(true)
							end
						end
					end)
				end
			end)
		end
	end

	-- 2. Star-Pods in Bag
	createSectionHeader(scroll, string.format("Star-Pods in Bag (%d)", #podList), PALETTE.OrbitalCyan, order)
	order += 1
	if #podList == 0 then
		createEmptyNote(scroll, "No Star-Pods in Bag. Rescue Meteors in Central Crater!", order)
		order += 1
	else
		for _, item in ipairs(podList) do
			local def = CritterConfig.ById[item.SpeciesId]
			local row, title, subtitle = createRowCard(scroll, def.AccentColor, order)
			order += 1

			title.Text = def.DisplayName .. " Pod"
			subtitle.Text = string.format("Hatch: %ds  |  Earns +%d Coins/s", def.HatchSeconds, def.CoinsPerSecond)

			local incBtn = makeTextButton(row, "IncubateBtn", "Incubate", PALETTE.OrbitalCyan, PALETTE.PanelDark, UDim2.fromOffset(100, 44), 14)
			incBtn.Position = UDim2.new(1, -108, 0.5, -22)
			registerBagButton("Incubate:" .. item.UID, incBtn)
			incBtn.Activated:Connect(function()
				local currentDto = latestOwnerState
				if currentDto == nil then
					return
				end
				local freeInc = findEmptyUnlockedIncubator(currentDto)
				if freeInc == nil then
					SoundController.Play("Error")
					UIController.ShowToast("All unlocked Incubator pads are busy!", "Warn")
					return
				end
				local okRange = isWithinStationRange("Incubator", freeInc)
				if not okRange then
					SoundController.Play("Error")
					UIController.ShowToast("Walk closer to " .. freeInc .. " to incubate this Pod!", "Warn")
					return
				end
				SoundController.Play("Click")
				if plotActionRemote ~= nil then
					plotActionRemote:FireServer("StartIncubate", freeInc, item.UID)
				end
			end)
		end
	end

	-- 3. Active Incubators
	createSectionHeader(scroll, string.format("Active Incubators (%d)", #incubatingList), PALETTE.StarlightGold, order)
	order += 1
	if #incubatingList == 0 then
		createEmptyNote(scroll, "Incubator pads are empty right now.", order)
		order += 1
	else
		for _, item in ipairs(incubatingList) do
			local def = CritterConfig.ById[item.SpeciesId]
			local slotId = item.AssignedSlot or "Incubator_1"
			local maturesAt = item.MaturesAt or nowClock
			local remaining = maturesAt - nowClock
			local mature = remaining <= 0

			local row, title, subtitle = createRowCard(scroll, if mature then PALETTE.StarlightGold else PALETTE.OrbitalCyan, order)
			order += 1

			title.Text = string.format("%s — %s Pod", slotId, def.DisplayName)
			subtitle.Text = if mature then "READY TO HATCH!" else string.format("Hatching in %s", FormatUtil.FormatTimer(remaining))

			table.insert(activeTimerBindings, {
				Label = subtitle,
				MaturesAt = maturesAt,
				DisplayName = def.DisplayName,
				WasMature = mature,
			})

			local hatchBtn = makeTextButton(
				row,
				"HatchBtn",
				if mature then "Hatch!" else "Wait...",
				if mature then PALETTE.StarlightGold else PALETTE.CardDark,
				if mature then PALETTE.PanelDark else PALETTE.TextMuted,
				UDim2.fromOffset(100, 44),
				14
			)
			hatchBtn.Position = UDim2.new(1, -108, 0.5, -22)
			registerBagButton("Hatch:" .. slotId, hatchBtn)
			hatchBtn.Activated:Connect(function()
				if workspace:GetServerTimeNow() < maturesAt then
					SoundController.Play("Error")
					UIController.ShowToast("Still incubating! Wait until the timer finishes.", "Info")
					return
				end
				local okRange = isWithinStationRange("Incubator", slotId)
				if not okRange then
					SoundController.Play("Error")
					UIController.ShowToast("Walk closer to " .. slotId .. " to hatch your Critter!", "Warn")
					return
				end
				SoundController.Play("Click")
				if plotActionRemote ~= nil then
					plotActionRemote:FireServer("Hatch", slotId)
				end
			end)
		end
	end

	-- 4. Habitat Pen Critters (Protected — NO Sell Button)
	createSectionHeader(scroll, string.format("Habitat Pen Critters — Protected (%d)", #inPenList), PALETTE.StarlightGold, order)
	order += 1
	if #inPenList == 0 then
		createEmptyNote(scroll, "Your Habitat Pen is empty. Place a hatched Critter to earn Coins/s!", order)
		order += 1
	else
		for _, item in ipairs(inPenList) do
			local def = CritterConfig.ById[item.SpeciesId]
			local slotId = item.AssignedSlot or "Pen_1"
			local row, title, subtitle = createRowCard(scroll, def.BodyColor, order)
			order += 1

			local variantTag = if item.Variant == "Radiant" then " [RADIANT]" else ""
			local feedLevel = item.FeedLevel or 0
			local isFed = feedLevel >= Constants.MAX_CRITTER_FEED_LEVEL
			local effRate = EconomyMath.GetCritterCoinsPerSecond(item.SpeciesId, item.Variant, item.FeedLevel)
			title.Text = string.format("%s — %s%s%s", slotId, def.DisplayName, variantTag, if isFed then " ★" else "")
			subtitle.Text = string.format(
				"In Pen (Safe)  |  +%d Coins/s%s",
				effRate,
				if isFed then " (Star-Fed!)" else ""
			)

			if isFed then
				local fedTagBtn = makeTextButton(row, "FedTag", "Fed ★", PALETTE.PanelDark, PALETTE.StarlightGold, UDim2.fromOffset(84, 44), 13)
				fedTagBtn.Position = UDim2.new(1, -172, 0.5, -22)
				fedTagBtn.AutoButtonColor = false
				fedTagBtn.Selectable = false
			else
				local canFeed = dto.Coins >= Constants.CRITTER_FEED_COST
				local feedBtn = makeTextButton(
					row,
					"FeedBtn",
					string.format("Feed (%d)", Constants.CRITTER_FEED_COST),
					if canFeed then PALETTE.MeadowMint else PALETTE.CardDark,
					if canFeed then PALETTE.PanelDark else PALETTE.TextMuted,
					UDim2.fromOffset(84, 44),
					12
				)
				feedBtn.Position = UDim2.new(1, -172, 0.5, -22)
				feedButtonsBySlot[slotId] = feedBtn
				registerBagButton("Feed:" .. slotId, feedBtn)
				feedBtn.Activated:Connect(function()
					local currentDto = latestOwnerState
					if currentDto == nil then
						return
					end
					if currentDto.Coins < Constants.CRITTER_FEED_COST then
						SoundController.Play("Error")
						UIController.ShowToast(
							string.format(
								"Need %d Coins to Feed your Critter (+%d Coins/s)!",
								Constants.CRITTER_FEED_COST,
								Constants.CRITTER_FEED_BONUS_COINS_PER_SEC
							),
							"Warn"
						)
						return
					end
					local okRange = isWithinStationRange("Pen", slotId)
					if not okRange then
						SoundController.Play("Error")
						UIController.ShowToast("Walk closer to " .. slotId .. " to Feed this Critter!", "Warn")
						return
					end
					SoundController.Play("Click")
					if plotActionRemote ~= nil then
						plotActionRemote:FireServer("FeedCritter", slotId)
					end
				end)
			end

			local pickUpBtn = makeTextButton(row, "PickUpBtn", "Pick Up", PALETTE.CardDark, PALETTE.TextCream, UDim2.fromOffset(76, 44), 13)
			pickUpBtn.Position = UDim2.new(1, -84, 0.5, -22)
			addStroke(pickUpBtn, PALETTE.OrbitalCyan, 1)
			registerBagButton("PickUp:" .. slotId, pickUpBtn)
			pickUpBtn.Activated:Connect(function()
				local currentDto = latestOwnerState
				if currentDto == nil then
					return
				end
				local curBagCount, curIncCount = countBagAndIncome(currentDto)
				if (curBagCount + curIncCount) >= currentDto.BagCap then
					SoundController.Play("Error")
					UIController.ShowToast("Bag Full! Sell a hatched critter before picking up.", "Warn")
					return
				end
				local okRange = isWithinStationRange("Pen", slotId)
				if not okRange then
					SoundController.Play("Error")
					UIController.ShowToast("Walk closer to " .. slotId .. " to pick up this Critter!", "Warn")
					return
				end
				SoundController.Play("Click")
				if plotActionRemote ~= nil then
					plotActionRemote:FireServer("RemoveFromPen", slotId)
				end
			end)
		end
	end

	-- 5. Visible Ranch Upgrades
	createSectionHeader(scroll, "Ranch Upgrades", PALETTE.OrbitalCyan, order)
	order += 1
	for _, upgradeId in ipairs(UpgradeConfig.OrderedIds) do
		local def = UpgradeConfig.ById[upgradeId]
		local owned = dto.Upgrades[upgradeId] == true
		local prereqId = def.RequiresUpgradeId
		local prereqMet = true
		local prereqDef: Types.UpgradeDefinition? = nil
		if prereqId ~= nil then
			prereqMet = dto.Upgrades[prereqId] == true
			prereqDef = UpgradeConfig.ById[prereqId]
		end

		local unownedAccent = if upgradeId == "FrostCracker" or upgradeId == "BagCap_20"
			then PALETTE.OrbitalCyan
			elseif def.SlotCategory == "Tool" then PALETTE.AstralViolet
			elseif upgradeId == "PenSlot_4" or upgradeId == "PenSlot_5" then PALETTE.StarlightGold
			else PALETTE.MeadowMint
		local row, title, subtitle = createRowCard(
			scroll,
			if owned then PALETTE.OrbitalCyan elseif prereqMet then unownedAccent else PALETTE.BorderSoft,
			order
		)
		order += 1

		title.Text = def.DisplayName
		if not owned and not prereqMet and prereqDef ~= nil then
			subtitle.Text = string.format("%s (%s Coins  |  Needs %s)", def.Description, FormatUtil.FormatCoins(def.Cost), prereqDef.DisplayName)
		else
			subtitle.Text = string.format("%s (%s Coins)", def.Description, FormatUtil.FormatCoins(def.Cost))
		end

		if owned then
			local ownedBtn = makeTextButton(row, "OwnedTag", "Owned", PALETTE.PanelDark, PALETTE.OrbitalCyan, UDim2.fromOffset(100, 44), 14)
			ownedBtn.Position = UDim2.new(1, -108, 0.5, -22)
			ownedBtn.AutoButtonColor = false
			ownedBtn.Selectable = false
		elseif not prereqMet then
			local lockedBtn = makeTextButton(row, "LockedTag", "Locked", PALETTE.PanelDark, PALETTE.TextMuted, UDim2.fromOffset(100, 44), 13)
			lockedBtn.Position = UDim2.new(1, -108, 0.5, -22)
			lockedBtn.AutoButtonColor = false
			lockedBtn.Selectable = false
		else
			local canAfford = dto.Coins >= def.Cost
			local buyBtn = makeTextButton(
				row,
				"BuyBtn",
				string.format("Buy (%s)", FormatUtil.FormatCoins(def.Cost)),
				if canAfford then PALETTE.MeadowMint else PALETTE.CardDark,
				if canAfford then PALETTE.PanelDark else PALETTE.TextMuted,
				UDim2.fromOffset(100, 44),
				13
			)
			buyBtn.Position = UDim2.new(1, -108, 0.5, -22)
			upgradeBuyButtons[upgradeId] = buyBtn
			registerBagButton("Buy:" .. upgradeId, buyBtn)
			buyBtn.Activated:Connect(function()
				if pendingUpgradeBuy then
					return
				end
				local currentDto = latestOwnerState
				if currentDto == nil then
					return
				end
				if currentDto.Coins < def.Cost then
					SoundController.Play("Error")
					UIController.ShowToast(string.format("Need %s Coins for %s!", FormatUtil.FormatCoins(def.Cost), def.DisplayName), "Warn")
					return
				end
				local okRange = isWithinStationRange("UpgradePad", upgradeId)
				if not okRange then
					SoundController.Play("Error")
					if def.StationZone == "Hub" then
						UIController.ShowToast("Walk to the Hub Tool Workbench for " .. def.DisplayName .. "!", "Warn")
					else
						UIController.ShowToast("Walk closer to the " .. def.DisplayName .. " Upgrade Pad!", "Warn")
					end
					return
				end
				pendingUpgradeBuy = true
				SoundController.Play("Click")
				task.spawn(function()
					local fn = buyUpgradeRemote
					if fn ~= nil then
						local okCall, res = pcall(function()
							return fn:InvokeServer(upgradeId)
						end)
						if not okCall or typeof(res) ~= "table" or not res.Ok then
							SoundController.Play("Error")
							local reason = if typeof(res) == "table" and res.Reason then tostring(res.Reason) else "Failed"
							UIController.ShowToast("Upgrade failed: " .. reason, "Warn")
						end
					end
					pendingUpgradeBuy = false
				end)
			end)
		end
	end

	-- 5B. Crater Lures (Frost Cracker required)
	createSectionHeader(scroll, "Crater Lures", PALETTE.OrbitalCyan, order)
	order += 1
	do
		local hasFrostTool = dto.Upgrades["FrostCracker"] == true
		local lureRow, lureTitle, lureSubtitle = createRowCard(
			scroll,
			if hasFrostTool then PALETTE.OrbitalCyan else PALETTE.BorderSoft,
			order
		)
		order += 1
		lureTitle.Text = "Frost Lure Beacon"
		lureSubtitle.Text = string.format(
			"Summons your own Frost Meteor on the Ridge (%d Coins — requires Frost Cracker)",
			Constants.FROST_LURE_COST
		)

		if not hasFrostTool then
			local lockedTag = makeTextButton(lureRow, "LockedTag", "Locked", PALETTE.PanelDark, PALETTE.TextMuted, UDim2.fromOffset(100, 44), 13)
			lockedTag.Position = UDim2.new(1, -108, 0.5, -22)
			lockedTag.AutoButtonColor = false
			lockedTag.Selectable = false
		else
			local canAffordLure = dto.Coins >= Constants.FROST_LURE_COST
			local lureBtn = makeTextButton(
				lureRow,
				"LureBtn",
				string.format("Summon (%d)", Constants.FROST_LURE_COST),
				if canAffordLure then PALETTE.MeadowMint else PALETTE.CardDark,
				if canAffordLure then PALETTE.PanelDark else PALETTE.TextMuted,
				UDim2.fromOffset(100, 44),
				12
			)
			lureBtn.Position = UDim2.new(1, -108, 0.5, -22)
			frostLureButton = lureBtn
			registerBagButton("Lure:Frost", lureBtn)
			lureBtn.Activated:Connect(function()
				local currentDto = latestOwnerState
				if currentDto == nil then
					return
				end
				if currentDto.Upgrades["FrostCracker"] ~= true then
					SoundController.Play("Error")
					UIController.ShowToast(
						string.format("Unlock Frost Cracker (%d Coins) before using a Frost Lure!", UpgradeConfig.ById.FrostCracker.Cost),
						"Warn"
					)
					return
				end
				local curBagCount, curIncCount = countBagAndIncome(currentDto)
				if (curBagCount + curIncCount) >= currentDto.BagCap then
					SoundController.Play("Error")
					UIController.ShowToast("Bag full! Sell a critter before using a Frost Lure.", "Warn")
					return
				end
				if currentDto.Coins < Constants.FROST_LURE_COST then
					SoundController.Play("Error")
					UIController.ShowToast(string.format("Need %d Coins to summon a Frost Meteor!", Constants.FROST_LURE_COST), "Warn")
					return
				end
				local okRange = isWithinStationRange("LureStand", "LureStand")
				if not okRange then
					SoundController.Play("Error")
					UIController.ShowToast("Walk to the Frost Lure Kiosk in the Observatory Hub!", "Warn")
					return
				end
				SoundController.Play("Click")
				if plotActionRemote ~= nil then
					plotActionRemote:FireServer("UseFrostLure", "LureStand")
				end
			end)
		end
	end

	-- 6. Cosmic Field Guide
	local discoveredCount = 0
	for _, speciesId in ipairs(CritterConfig.OrderedIds) do
		if dto.DiscoveredSpecies[speciesId] == true then
			discoveredCount += 1
		end
	end
	createSectionHeader(
		scroll,
		string.format("Field Guide (Discovered: %d / %d)", discoveredCount, #CritterConfig.OrderedIds),
		PALETTE.StarlightGold,
		order
	)
	order += 1

	for _, speciesId in ipairs(CritterConfig.OrderedIds) do
		local def = CritterConfig.ById[speciesId]
		local discovered = dto.DiscoveredSpecies[speciesId] == true
		local row, title, subtitle = createRowCard(
			scroll,
			if discovered then def.BodyColor else PALETTE.BorderSoft,
			order
		)
		order += 1

		if discovered then
			title.Text = string.format("%s [%s]", def.DisplayName, def.Rarity)
			subtitle.Text = string.format(
				"+%d Coins/s  |  Sell %d  |  Hatch %ds",
				def.CoinsPerSecond,
				def.SellPrice,
				def.HatchSeconds
			)
			local foundTag = makeTextButton(row, "FoundTag", "Found", PALETTE.PanelDark, PALETTE.MeadowMint, UDim2.fromOffset(100, 44), 13)
			foundTag.Position = UDim2.new(1, -108, 0.5, -22)
			foundTag.AutoButtonColor = false
			foundTag.Selectable = false
		else
			title.Text = string.format("??? [%s]", def.Rarity)
			subtitle.Text = def.FieldClue
			local unknownTag = makeTextButton(row, "UnknownTag", "???", PALETTE.PanelDark, PALETTE.TextMuted, UDim2.fromOffset(100, 44), 13)
			unknownTag.Position = UDim2.new(1, -108, 0.5, -22)
			unknownTag.AutoButtonColor = false
			unknownTag.Selectable = false
		end
	end

	bagRebuildCount += 1
	lastBagStructureSignature = UIController.ComputeBagStructureSignature(dto, pendingSellConfirmUID)

	if bagDrawer ~= nil then
		bagDrawer.Visible = bagOpen
	end
	if guideDrawer ~= nil then
		guideDrawer.Visible = guideOpen
	end
	if settingsDrawer ~= nil then
		settingsDrawer.Visible = settingsOpen
	end

	task.spawn(function()
		RunService.RenderStepped:Wait()
		if myToken ~= bagRestoreToken then
			return
		end
		syncBagCanvasSize(nil)
		if bagScrollLayout ~= nil and bagScrollLayout.AbsoluteContentSize.Y == 0 and #scroll:GetChildren() > 1 then
			RunService.RenderStepped:Wait()
			if myToken ~= bagRestoreToken then
				return
			end
			syncBagCanvasSize(nil)
		end

		if not bagOpen then
			bagRestoreInFlight = false
			return
		end

		local maxScrollY = getMaxBagScrollY()
		if preserve then
			scroll.CanvasPosition = Vector2.new(savedCanvasPos.X, math.clamp(savedCanvasPos.Y, 0, maxScrollY))
		else
			scroll.CanvasPosition = Vector2.zero
		end

		if currentInputMode == "Gamepad" then
			local target = resolveBagSelectionTarget(if preserve then preferredKey else lastFocusedBagKey)
			safeSetSelectedObject(target)
			if preserve and target ~= nil then
				local winTop = scroll.AbsolutePosition.Y
				local winBottom = winTop + scroll.AbsoluteWindowSize.Y
				local targetTop = target.AbsolutePosition.Y
				local targetBottom = targetTop + target.AbsoluteSize.Y
				if targetTop >= winTop - 2 and targetBottom <= winBottom + 2 then
					scroll.CanvasPosition = Vector2.new(savedCanvasPos.X, math.clamp(savedCanvasPos.Y, 0, maxScrollY))
				end
			end
		end

		if myToken == bagRestoreToken then
			bagRestoreInFlight = false
		end
	end)
end

local function getTraitBadgeForSpecies(speciesId: Types.SpeciesId): string
	local traits: { string } = {}
	for _, traitId in ipairs(MeteorConfig.OrderedIds) do
		local tDef = MeteorConfig.ById[traitId]
		if tDef ~= nil and (tDef.DropWeights[speciesId] or 0) > 0 then
			table.insert(traits, tDef.IconText)
		end
	end
	if #traits == 0 then
		return "[CRATER]"
	end
	return "[" .. table.concat(traits, " / ") .. "]"
end

local function syncGuideCanvasSize(minHeight: number?): ()
	syncScrollCanvasSize(guideScrollFrame, guideScrollLayout, minHeight)
end

local function getMaxGuideScrollY(): number
	return getMaxScrollY(guideScrollFrame, guideScrollLayout)
end

rebuildFieldGuideContents = function(preserveFocusAndScroll: boolean?): ()
	local scroll = guideScrollFrame
	if scroll == nil then
		return
	end

	local preserve = preserveFocusAndScroll == true
	local savedCanvasPos = if preserve then scroll.CanvasPosition else Vector2.zero
	local prevCanvasHeight = if preserve then math.max(scroll.AbsoluteCanvasSize.Y, scroll.CanvasSize.Y.Offset, 1) else 0
	local preferredKey: string? = nil
	if preserve then
		local currentSelected = GuiService.SelectedObject
		if currentSelected ~= nil and guideDrawer ~= nil and currentSelected:IsDescendantOf(guideDrawer) then
			local attr = currentSelected:GetAttribute("GuideActionKey")
			if typeof(attr) == "string" then
				preferredKey = attr
			end
		end
		if preferredKey == nil then
			preferredKey = lastFocusedGuideKey
		end
	end

	guideRestoreToken += 1
	local myToken = guideRestoreToken
	guideRestoreInFlight = true

	local currentSelected = GuiService.SelectedObject
	if currentSelected ~= nil and currentSelected:IsDescendantOf(scroll) then
		GuiService.SelectedObject = nil
	end
	if preserve then
		scroll.CanvasSize = UDim2.fromOffset(0, prevCanvasHeight)
	end

	for _, child in ipairs(scroll:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	guideButtonsByKey = {}
	firstGuideSelectable = nil

	local function registerGuideButton(actionKey: string, btn: GuiObject): ()
		btn:SetAttribute("GuideActionKey", actionKey)
		guideButtonsByKey[actionKey] = btn
		btn.SelectionGained:Connect(function()
			lastFocusedGuideKey = actionKey
		end)
		if firstGuideSelectable == nil then
			firstGuideSelectable = btn
		end
	end

	local dto = latestOwnerState
	if dto == nil then
		createEmptyNote(scroll, "Loading Cosmic Field Guide...", 1)
		lastGuideStructureSignature = nil
		syncGuideCanvasSize(nil)
		guideRestoreInFlight = false
		applyDrawerVisibility(nil, nil)
		return
	end

	local radiantBySpecies: { [Types.SpeciesId]: boolean } = {}
	for _, item in pairs(dto.Items) do
		if item.Variant == "Radiant" then
			radiantBySpecies[item.SpeciesId] = true
		end
	end

	local discoveredCount = 0
	for _, speciesId in ipairs(CritterConfig.OrderedIds) do
		if dto.DiscoveredSpecies[speciesId] == true then
			discoveredCount += 1
		end
	end
	local totalSpecies = #CritterConfig.OrderedIds

	if guideProgressLabel ~= nil then
		guideProgressLabel.Text = string.format(
			"Discovered: %d / %d  •  Cosmetic Checklist (No Stat Bonuses)",
			discoveredCount,
			totalSpecies
		)
	end
	if guideProgressFill ~= nil then
		local ratio = if totalSpecies > 0 then math.clamp(discoveredCount / totalSpecies, 0, 1) else 0
		guideProgressFill.Size = UDim2.fromScale(ratio, 1)
	end

	local order = 1
	for _, speciesId in ipairs(CritterConfig.OrderedIds) do
		local def = CritterConfig.ById[speciesId]
		local discovered = dto.DiscoveredSpecies[speciesId] == true
		local hasRadiant = radiantBySpecies[speciesId] == true
		local traitBadge = getTraitBadgeForSpecies(speciesId)

		local card = Instance.new("TextButton")
		card.Name = "GuideCard_" .. speciesId
		card.Size = UDim2.new(1, 0, 0, 82)
		card.BackgroundColor3 = PALETTE.CardDark
		card.BorderSizePixel = 0
		card.Text = ""
		card.AutoButtonColor = false
		card.Selectable = true
		card.LayoutOrder = order
		order += 1
		addCorner(card, 10)
		addStroke(card, if discovered then def.BodyColor else PALETTE.BorderSoft, if hasRadiant then 1.8 else 1.2)
		card.Parent = scroll
		registerGuideButton("Species:" .. speciesId, card)

		local swatchHolder = Instance.new("Frame")
		swatchHolder.Size = UDim2.fromOffset(12, 62)
		swatchHolder.Position = UDim2.new(0, 8, 0.5, -31)
		swatchHolder.BackgroundColor3 = if discovered then def.BodyColor else Color3.fromRGB(40, 38, 56)
		swatchHolder.BorderSizePixel = 0
		addCorner(swatchHolder, 4)
		swatchHolder.Parent = card

		local swatchBottom = Instance.new("Frame")
		swatchBottom.Size = UDim2.new(1, 0, 0.42, 0)
		swatchBottom.Position = UDim2.fromScale(0, 0.58)
		swatchBottom.BackgroundColor3 = if discovered then def.SecondaryColor else Color3.fromRGB(28, 26, 40)
		swatchBottom.BorderSizePixel = 0
		addCorner(swatchBottom, 3)
		swatchBottom.Parent = swatchHolder

		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, -124, 0, 22)
		title.Position = UDim2.fromOffset(28, 8)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBold
		title.TextSize = 14
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextTruncate = Enum.TextTruncate.AtEnd
		title.TextColor3 = if discovered then PALETTE.TextCream else PALETTE.TextMuted
		title.Text = if discovered
			then (string.format("%s [%s]%s", def.DisplayName, def.Rarity, if hasRadiant then "  ★ Radiant" else ""))
			else string.format("??? [%s]", def.Rarity)
		title.Parent = card

		local details = Instance.new("TextLabel")
		details.Size = UDim2.new(1, -124, 0, 18)
		details.Position = UDim2.fromOffset(28, 32)
		details.BackgroundTransparency = 1
		details.Font = Enum.Font.GothamMedium
		details.TextSize = 12
		details.TextXAlignment = Enum.TextXAlignment.Left
		details.TextTruncate = Enum.TextTruncate.AtEnd
		details.TextColor3 = if discovered then PALETTE.MeadowMint else PALETTE.OrbitalCyan
		details.Text = if discovered
			then string.format("+%d/s  |  Sell %d  |  %ds  |  %s", def.CoinsPerSecond, def.SellPrice, def.HatchSeconds, traitBadge)
			else ("Clue: " .. def.FieldClue)
		details.Parent = card

		local subInfo = Instance.new("TextLabel")
		subInfo.Size = UDim2.new(1, -124, 0, 18)
		subInfo.Position = UDim2.fromOffset(28, 54)
		subInfo.BackgroundTransparency = 1
		subInfo.Font = Enum.Font.GothamMedium
		subInfo.TextSize = 11
		subInfo.TextXAlignment = Enum.TextXAlignment.Left
		subInfo.TextTruncate = Enum.TextTruncate.AtEnd
		subInfo.TextColor3 = PALETTE.TextMuted
		subInfo.Text = if discovered then def.Description else ("Source: " .. traitBadge .. " Meteors")
		subInfo.Parent = card

		local badge = Instance.new("TextLabel")
		badge.Size = UDim2.fromOffset(82, 34)
		badge.Position = UDim2.new(1, -92, 0.5, -17)
		badge.BackgroundColor3 = PALETTE.PanelDark
		badge.TextColor3 = if discovered then PALETTE.MeadowMint else PALETTE.TextMuted
		badge.Font = Enum.Font.GothamBold
		badge.TextSize = 12
		badge.Text = if discovered then "Found" else "Locked"
		addCorner(badge, 8)
		badge.Parent = card

		card.Activated:Connect(function()
			SoundController.Play("Click")
			if discovered then
				UIController.ShowToast(
					string.format("%s: %s%s", def.DisplayName, def.Description, if hasRadiant then " (Radiant seen!)" else ""),
					"Info"
				)
			else
				UIController.ShowToast(string.format("Clue (%s): %s %s", def.Rarity, def.FieldClue, traitBadge), "Info")
			end
		end)
	end

	createEmptyNote(scroll, "Radiant Variant (10% hatch): Purely cosmetic gold halo & sparkles — zero Coin/Sell multiplier.", order)

	guideRebuildCount += 1
	lastGuideStructureSignature = UIController.ComputeGuideStructureSignature(dto)

	if bagDrawer ~= nil then
		bagDrawer.Visible = bagOpen
	end
	if guideDrawer ~= nil then
		guideDrawer.Visible = guideOpen
	end
	if settingsDrawer ~= nil then
		settingsDrawer.Visible = settingsOpen
	end

	task.spawn(function()
		RunService.RenderStepped:Wait()
		if myToken ~= guideRestoreToken then
			return
		end
		syncGuideCanvasSize(nil)
		if guideScrollLayout ~= nil and guideScrollLayout.AbsoluteContentSize.Y == 0 and #scroll:GetChildren() > 1 then
			RunService.RenderStepped:Wait()
			if myToken ~= guideRestoreToken then
				return
			end
			syncGuideCanvasSize(nil)
		end

		if not guideOpen then
			guideRestoreInFlight = false
			return
		end

		local maxScrollY = getMaxGuideScrollY()
		if preserve then
			scroll.CanvasPosition = Vector2.new(savedCanvasPos.X, math.clamp(savedCanvasPos.Y, 0, maxScrollY))
		else
			scroll.CanvasPosition = Vector2.zero
		end

		if currentInputMode == "Gamepad" then
			local target = resolveGuideSelectionTarget(if preserve then preferredKey else lastFocusedGuideKey)
			safeSetSelectedObject(target)
			if preserve and target ~= nil then
				local winTop = scroll.AbsolutePosition.Y
				local winBottom = winTop + scroll.AbsoluteWindowSize.Y
				local targetTop = target.AbsolutePosition.Y
				local targetBottom = targetTop + target.AbsoluteSize.Y
				if targetTop >= winTop - 2 and targetBottom <= winBottom + 2 then
					scroll.CanvasPosition = Vector2.new(savedCanvasPos.X, math.clamp(savedCanvasPos.Y, 0, maxScrollY))
				end
			end
		end

		if myToken == guideRestoreToken then
			guideRestoreInFlight = false
		end
	end)
end

local function refreshAllHUD(dto: Types.OwnerStateDTO): ()
	local bagCount, incubatingCount, _, totalRate = countBagAndIncome(dto)
	local committed = bagCount + incubatingCount
	local isNarrow = hudGui ~= nil and hudGui.AbsoluteSize.X > 0 and hudGui.AbsoluteSize.X < 440

	if coinsLabel ~= nil then
		coinsLabel.Text = if isNarrow then FormatUtil.FormatCoins(dto.Coins) else (FormatUtil.FormatCoins(dto.Coins) .. " Coins")
	end
	if rateLabel ~= nil then
		rateLabel.Text = if isNarrow then string.format("+%d/s", totalRate) else FormatUtil.FormatRate(totalRate)
	end
	if bagLabel ~= nil then
		if isNarrow then
			bagLabel.Text = string.format("%d/%d", committed, dto.BagCap)
		elseif incubatingCount > 0 then
			bagLabel.Text = string.format("Bag: %d/%d (+%d Inc)", committed, dto.BagCap, incubatingCount)
		else
			bagLabel.Text = string.format("Bag: %d/%d", committed, dto.BagCap)
		end
		bagLabel.TextColor3 = if committed >= dto.BagCap then PALETTE.StarlightGold else PALETTE.TextCream
	end

	updateActionButtonsText()
	updateContextualHint()

	if bagOpen then
		local nextSig = UIController.ComputeBagStructureSignature(dto, pendingSellConfirmUID)
		if nextSig == lastBagStructureSignature then
			-- Coin-only update: keep existing rows, scroll position, and Gamepad selection untouched.
			refreshUpgradeAffordabilityInPlace(dto)
		else
			rebuildBagContents(true)
		end
	end

	if guideOpen then
		local nextGuideSig = UIController.ComputeGuideStructureSignature(dto)
		if nextGuideSig ~= lastGuideStructureSignature then
			rebuildFieldGuideContents(true)
		end
	end
end

local function handleAuthoritativeStateDiff(prevDto: Types.OwnerStateDTO?, nextDto: Types.OwnerStateDTO): ()
	if prevDto == nil then
		return
	end

	for uid, prevItem in pairs(prevDto.Items) do
		local nextItem = nextDto.Items[uid]
		if prevItem.State == "Incubating" and nextItem ~= nil and nextItem.State == "HatchedInBag" then
			local def = CritterConfig.ById[nextItem.SpeciesId]
			SoundController.Play("Hatch")
			local prefix = if nextItem.Variant == "Radiant" then "RADIANT " else ""
			UIController.ShowToast(string.format("Hatched %s%s!", prefix, def.DisplayName), "Success")
		elseif nextItem ~= nil and (nextItem.FeedLevel or 0) > (prevItem.FeedLevel or 0) then
			local def = CritterConfig.ById[nextItem.SpeciesId]
			SoundController.Play("Upgrade")
			UIController.ShowToast(
				string.format("Star-Fed %s! (+%d Coins/s bonus!)", def.DisplayName, Constants.CRITTER_FEED_BONUS_COINS_PER_SEC),
				"Success"
			)
		elseif prevItem.State == "HatchedInBag" and nextItem == nil and nextDto.Coins > prevDto.Coins then
			local def = CritterConfig.ById[prevItem.SpeciesId]
			local soldAmount = EconomyMath.GetCritterSellPrice(prevItem.SpeciesId, prevItem.Variant, prevItem.FeedLevel)
			SoundController.Play("Sell")
			UIController.ShowToast(string.format("Sold %s for +%s Coins!", def.DisplayName, FormatUtil.FormatCoins(soldAmount)), "Success")
		end
	end

	for _, speciesId in ipairs(CritterConfig.OrderedIds) do
		if prevDto.DiscoveredSpecies[speciesId] ~= true and nextDto.DiscoveredSpecies[speciesId] == true then
			local def = CritterConfig.ById[speciesId]
			local discTotal = 0
			for _, sid in ipairs(CritterConfig.OrderedIds) do
				if nextDto.DiscoveredSpecies[sid] == true then
					discTotal += 1
				end
			end
			UIController.ShowToast(
				string.format("NEW DISCOVERY: %s! (%d/%d in Field Guide)", def.DisplayName, discTotal, #CritterConfig.OrderedIds),
				"Success"
			)
		end
	end

	for _, upgradeId in ipairs(UpgradeConfig.OrderedIds) do
		if prevDto.Upgrades[upgradeId] ~= true and nextDto.Upgrades[upgradeId] == true then
			local def = UpgradeConfig.ById[upgradeId]
			SoundController.Play("Upgrade")
			if upgradeId == "FrostCracker" then
				UIController.ShowToast("Unlocked Frost Cracker! Crack Ridge Frost Meteors & use Hub Frost Lures!", "Success")
			elseif upgradeId == "StarCracker" then
				UIController.ShowToast("Unlocked Astral Cracker! Break Astral Pulse Meteors in the Crater!", "Success")
			elseif upgradeId == "PenSlot_4" then
				UIController.ShowToast("Unlocked Habitat Slot #4 & earned your Gold Ranch Arch!", "Success")
			elseif upgradeId == "BagCap_20" then
				UIController.ShowToast("Expanded Ranch Bag capacity from 10 to 20!", "Success")
			elseif upgradeId == "PenSlot_5" then
				UIController.ShowToast("Unlocked Habitat Slot #5! Place a 5th Critter in your Pen!", "Success")
			else
				UIController.ShowToast("Unlocked " .. def.DisplayName .. "!", "Success")
			end
		end
	end
end

function UIController.Init(self: typeof(UIController)): ()
	local player = Players.LocalPlayer
	if player == nil then
		return
	end
	local playerGui = player:WaitForChild("PlayerGui")

	local existing = playerGui:FindFirstChild("StarfallRanchHUD")
	if existing ~= nil then
		existing:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "StarfallRanchHUD"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui
	hudGui = screenGui

	-- Top Resource Bar (pixel-positioned by applyResponsiveTopLayout so narrow phones stack cleanly)
	local resBar = Instance.new("Frame")
	resBar.Name = "TopResourceBar"
	resBar.AnchorPoint = Vector2.new(0, 0)
	resBar.Position = UDim2.fromOffset(10, 8)
	resBar.Size = UDim2.fromOffset(300, 46)
	resBar.BackgroundColor3 = PALETTE.PanelDark
	resBar.BackgroundTransparency = 0.08
	resBar.BorderSizePixel = 0
	addCorner(resBar, 14)
	addStroke(resBar, PALETTE.BorderSoft, 1.5)
	resBar.Parent = screenGui
	resourceBarFrame = resBar

	local resLayout = Instance.new("UIListLayout")
	resLayout.FillDirection = Enum.FillDirection.Horizontal
	resLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	resLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	resLayout.Padding = UDim.new(0, 6)
	resLayout.Parent = resBar

	local cLabel = Instance.new("TextLabel")
	cLabel.Name = "CoinsLabel"
	cLabel.Size = UDim2.new(0.36, 0, 1, -8)
	cLabel.BackgroundTransparency = 1
	cLabel.Text = "0 Coins"
	cLabel.TextColor3 = PALETTE.StarlightGold
	cLabel.Font = Enum.Font.GothamBold
	cLabel.TextScaled = true
	cLabel.Parent = resBar
	coinsLabel = cLabel

	local rLabel = Instance.new("TextLabel")
	rLabel.Name = "RateLabel"
	rLabel.Size = UDim2.new(0.28, 0, 1, -12)
	rLabel.BackgroundColor3 = PALETTE.CardDark
	rLabel.Text = "+0 Coins/s"
	rLabel.TextColor3 = PALETTE.MeadowMint
	rLabel.Font = Enum.Font.GothamBold
	rLabel.TextScaled = true
	addCorner(rLabel, 8)
	rLabel.Parent = resBar
	rateLabel = rLabel

	local bLabel = Instance.new("TextLabel")
	bLabel.Name = "BagLabel"
	bLabel.Size = UDim2.new(0.28, 0, 1, -8)
	bLabel.BackgroundTransparency = 1
	bLabel.Text = "Bag: 0/10"
	bLabel.TextColor3 = PALETTE.TextCream
	bLabel.Font = Enum.Font.GothamBold
	bLabel.TextScaled = true
	bLabel.Parent = resBar
	bagLabel = bLabel

	-- Top-Right Action Buttons (>= 44px touch targets)
	local actionRow = Instance.new("Frame")
	actionRow.Name = "TopRightActions"
	actionRow.AnchorPoint = Vector2.new(0, 0)
	actionRow.Position = UDim2.fromOffset(124, 58)
	actionRow.Size = UDim2.fromOffset(ACTION_TRAY_WIDTH, 46)
	actionRow.BackgroundTransparency = 1
	actionRow.Parent = screenGui
	actionRowFrame = actionRow

	local actionLayout = Instance.new("UIListLayout")
	actionLayout.FillDirection = Enum.FillDirection.Horizontal
	actionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	actionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	actionLayout.Padding = UDim.new(0, 5)
	actionLayout.Parent = actionRow

	local function triggerNavigation(target: Types.NavigationTarget, customInvoker: ((Types.NavigationTarget) -> any)?): boolean
		if latestOwnerState == nil then
			SoundController.Play("Error")
			UIController.ShowToast("Wait until your Ranch finishes loading!", "Warn")
			return false
		end
		if pendingNavigate then
			return false
		end
		local now = os.clock()
		if (now - lastNavRequestClock) < Constants.NAVIGATE_CLIENT_COOLDOWN_SECONDS then
			SoundController.Play("Error")
			UIController.ShowToast("Travel cooling down — wait a moment!", "Warn")
			return false
		end

		UIController.CloseDrawers()
		pendingNavigate = true

		local function handleNavResult(okCall: boolean, res: any): ()
			pendingNavigate = false
			if okCall and typeof(res) == "table" and res.Ok == true then
				lastNavRequestClock = os.clock()
				SoundController.Play("Click")
				UIController.ShowToast(
					if target == "Hub" then "Arrived at Observatory Hub!" else "Returned to your Ranch!",
					"Success"
				)
				return
			end

			SoundController.Play("Error")
			local reason = if typeof(res) == "table" and res.Reason then tostring(res.Reason) else "Failed"
			if reason == "RateLimited" then
				lastNavRequestClock = os.clock()
				UIController.ShowToast("Travel cooling down — wait a moment!", "Warn")
			else
				UIController.ShowToast("Could not travel: " .. reason, "Warn")
			end
		end

		if customInvoker ~= nil then
			local okCall, res = pcall(customInvoker, target)
			handleNavResult(okCall, res)
			return true
		end

		local fn = navigateRemote
		if fn == nil then
			pendingNavigate = false
			SoundController.Play("Error")
			UIController.ShowToast("Travel unavailable right now!", "Warn")
			return false
		end

		task.spawn(function()
			local okCall, res = pcall(function()
				return fn:InvokeServer(target)
			end)
			handleNavResult(okCall, res)
		end)
		return true
	end
	navigateDispatcher = triggerNavigation

	local hubBtn = makeTextButton(actionRow, "HubButton", "Hub", PALETTE.AstralViolet, PALETTE.PanelDark, UDim2.fromOffset(46, 44), 12)
	hubBtn.LayoutOrder = 1
	hubBtn.Activated:Connect(function()
		triggerNavigation("Hub")
	end)
	hubButton = hubBtn

	local ranchBtn = makeTextButton(actionRow, "RanchButton", "Ranch", PALETTE.MeadowMint, PALETTE.PanelDark, UDim2.fromOffset(54, 44), 12)
	ranchBtn.LayoutOrder = 2
	ranchBtn.Activated:Connect(function()
		triggerNavigation("Ranch")
	end)
	ranchButton = ranchBtn

	local bagBtn = makeTextButton(actionRow, "BagButton", "Bag (0)", PALETTE.OrbitalCyan, PALETTE.PanelDark, UDim2.fromOffset(64, 44), 12)
	bagBtn.LayoutOrder = 3
	bagBtn.Activated:Connect(function()
		SoundController.Play("Click")
		UIController.ToggleBag()
	end)
	bagButton = bagBtn

	local guideBtn = makeTextButton(actionRow, "GuideButton", "Guide", PALETTE.StarlightGold, PALETTE.PanelDark, UDim2.fromOffset(60, 44), 12)
	guideBtn.LayoutOrder = 4
	guideBtn.Activated:Connect(function()
		SoundController.Play("Click")
		UIController.ToggleFieldGuide()
	end)
	guideButton = guideBtn

	local setBtn = makeTextButton(actionRow, "SettingsButton", "⚙", PALETTE.CardDark, PALETTE.TextCream, UDim2.fromOffset(44, 44), 18)
	setBtn.LayoutOrder = 5
	addStroke(setBtn, PALETTE.BorderSoft, 1.5)
	setBtn.Activated:Connect(function()
		SoundController.Play("Click")
		UIController.ToggleSettings()
	end)
	settingsButton = setBtn

	-- Upper-Center Toast Banner
	local toast = Instance.new("TextLabel")
	toast.Name = "ToastBanner"
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.Position = UDim2.new(0.5, 0, 0, 62)
	toast.Size = UDim2.new(0.86, 0, 0, 36)
	toast.BackgroundColor3 = PALETTE.PanelDark
	toast.BackgroundTransparency = 0.08
	toast.TextColor3 = PALETTE.OrbitalCyan
	toast.Text = ""
	toast.Font = Enum.Font.GothamBold
	toast.TextSize = 14
	toast.Visible = false
	addCorner(toast, 10)
	addStroke(toast, PALETTE.BorderSoft, 1)
	local toastConstraint = Instance.new("UISizeConstraint")
	toastConstraint.MinSize = Vector2.new(220, 34)
	toastConstraint.MaxSize = Vector2.new(460, 44)
	toastConstraint.Parent = toast
	toast.Parent = screenGui
	toastLabel = toast

	-- Bottom-Center Contextual Guidance Bar (shown during onboarding & Hatch Ready only)
	local hintFrame = Instance.new("Frame")
	hintFrame.Name = "BottomHintBar"
	hintFrame.AnchorPoint = Vector2.new(0.5, 1)
	hintFrame.Position = UDim2.new(0.5, 0, 1, -10)
	hintFrame.Size = UDim2.new(0.92, 0, 0, 38)
	hintFrame.BackgroundColor3 = PALETTE.PanelDark
	hintFrame.BackgroundTransparency = 0.14
	hintFrame.BorderSizePixel = 0
	addCorner(hintFrame, 12)
	addStroke(hintFrame, PALETTE.BorderSoft, 1)
	local hintConstraint = Instance.new("UISizeConstraint")
	hintConstraint.MinSize = Vector2.new(260, 36)
	hintConstraint.MaxSize = Vector2.new(580, 42)
	hintConstraint.Parent = hintFrame
	hintFrame.Parent = screenGui
	hintBarFrame = hintFrame

	local hLabel = Instance.new("TextLabel")
	hLabel.Name = "HintText"
	hLabel.Size = UDim2.new(1, -20, 1, 0)
	hLabel.Position = UDim2.fromOffset(10, 0)
	hLabel.BackgroundTransparency = 1
	hLabel.TextColor3 = PALETTE.StarlightGold
	hLabel.Font = Enum.Font.GothamBold
	hLabel.TextScaled = true
	hLabel.Text = "Connecting to your Starfall Ranch..."
	hLabel.Parent = hintFrame
	hintLabel = hLabel

	-- Bag & Keep-vs-Sell Drawer
	local drawer = Instance.new("Frame")
	drawer.Name = "BagDrawer"
	drawer.AnchorPoint = Vector2.new(0, 0)
	drawer.Position = UDim2.fromOffset(10, 104)
	drawer.Size = UDim2.fromOffset(300, 400)
	drawer.BackgroundColor3 = PALETTE.PanelDark
	drawer.BackgroundTransparency = 0.04
	drawer.BorderSizePixel = 0
	drawer.Visible = false
	addCorner(drawer, 16)
	addStroke(drawer, PALETTE.OrbitalCyan, 1.5)
	trapGamepadFocus(drawer)
	drawer.Parent = screenGui
	bagDrawer = drawer

	local drawerTitle = Instance.new("TextLabel")
	drawerTitle.Size = UDim2.new(1, -76, 0, 28)
	drawerTitle.Position = UDim2.fromOffset(16, 10)
	drawerTitle.BackgroundTransparency = 1
	drawerTitle.Text = "Ranch Bag & Keep-vs-Sell"
	drawerTitle.TextColor3 = PALETTE.TextCream
	drawerTitle.Font = Enum.Font.GothamBold
	drawerTitle.TextSize = 18
	drawerTitle.TextXAlignment = Enum.TextXAlignment.Left
	drawerTitle.Parent = drawer

	local capSub = Instance.new("TextLabel")
	capSub.Size = UDim2.new(1, -76, 0, 20)
	capSub.Position = UDim2.fromOffset(16, 38)
	capSub.BackgroundTransparency = 1
	capSub.Text = "Bag: 0/10 committed"
	capSub.TextColor3 = PALETTE.OrbitalCyan
	capSub.Font = Enum.Font.GothamMedium
	capSub.TextSize = 13
	capSub.TextXAlignment = Enum.TextXAlignment.Left
	capSub.Parent = drawer
	bagCapacityLabel = capSub

	local closeBagBtn = makeTextButton(drawer, "CloseBagBtn", "X", PALETTE.CardDark, PALETTE.TextCream, UDim2.fromOffset(44, 44), 16)
	closeBagBtn.AnchorPoint = Vector2.new(1, 0)
	closeBagBtn.Position = UDim2.new(1, -12, 0, 10)
	closeBagBtn:SetAttribute("BagActionKey", "CloseBag")
	closeBagBtn.SelectionGained:Connect(function()
		lastFocusedBagKey = "CloseBag"
	end)
	addStroke(closeBagBtn, PALETTE.BorderSoft, 1)
	closeBagBtn.Activated:Connect(function()
		SoundController.Play("Click")
		UIController.CloseDrawers()
	end)
	bagCloseButton = closeBagBtn

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "BagItemsScroll"
	scroll.Position = UDim2.fromOffset(12, 66)
	scroll.Size = UDim2.new(1, -24, 1, -78)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.None
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = PALETTE.OrbitalCyan
	scroll.Parent = drawer
	bagScrollFrame = scroll

	local scrollLayout = Instance.new("UIListLayout")
	scrollLayout.Padding = UDim.new(0, 8)
	scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
	scrollLayout.Parent = scroll
	bagScrollLayout = scrollLayout

	if layoutChangedConn ~= nil then
		layoutChangedConn:Disconnect()
	end
	layoutChangedConn = scrollLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		if not bagRestoreInFlight then
			syncBagCanvasSize(nil)
		end
	end)

	-- Dedicated Discovered Species Checklist ("Cosmic Field Guide") Drawer
	local gDrawer = Instance.new("Frame")
	gDrawer.Name = "FieldGuideDrawer"
	gDrawer.AnchorPoint = Vector2.new(0, 0)
	gDrawer.Position = UDim2.fromOffset(10, 104)
	gDrawer.Size = UDim2.fromOffset(300, 400)
	gDrawer.BackgroundColor3 = PALETTE.PanelDark
	gDrawer.BackgroundTransparency = 0.04
	gDrawer.BorderSizePixel = 0
	gDrawer.Visible = false
	addCorner(gDrawer, 16)
	addStroke(gDrawer, PALETTE.StarlightGold, 1.5)
	trapGamepadFocus(gDrawer)
	gDrawer.Parent = screenGui
	guideDrawer = gDrawer

	local gTitle = Instance.new("TextLabel")
	gTitle.Size = UDim2.new(1, -76, 0, 26)
	gTitle.Position = UDim2.fromOffset(16, 10)
	gTitle.BackgroundTransparency = 1
	gTitle.Text = "Cosmic Field Guide"
	gTitle.TextColor3 = PALETTE.StarlightGold
	gTitle.Font = Enum.Font.GothamBold
	gTitle.TextSize = 18
	gTitle.TextXAlignment = Enum.TextXAlignment.Left
	gTitle.Parent = gDrawer

	local gProgSub = Instance.new("TextLabel")
	gProgSub.Size = UDim2.new(1, -76, 0, 18)
	gProgSub.Position = UDim2.fromOffset(16, 36)
	gProgSub.BackgroundTransparency = 1
	gProgSub.Text = "Discovered: 0 / 6  •  Cosmetic Checklist"
	gProgSub.TextColor3 = PALETTE.TextCream
	gProgSub.Font = Enum.Font.GothamMedium
	gProgSub.TextSize = 12
	gProgSub.TextXAlignment = Enum.TextXAlignment.Left
	gProgSub.TextTruncate = Enum.TextTruncate.AtEnd
	gProgSub.Parent = gDrawer
	guideProgressLabel = gProgSub

	local gProgTrack = Instance.new("Frame")
	gProgTrack.Name = "GuideProgressTrack"
	gProgTrack.Size = UDim2.new(1, -32, 0, 8)
	gProgTrack.Position = UDim2.fromOffset(16, 58)
	gProgTrack.BackgroundColor3 = PALETTE.CardDark
	gProgTrack.BorderSizePixel = 0
	addCorner(gProgTrack, 4)
	gProgTrack.Parent = gDrawer

	local gProgFill = Instance.new("Frame")
	gProgFill.Name = "GuideProgressFill"
	gProgFill.Size = UDim2.fromScale(0, 1)
	gProgFill.BackgroundColor3 = PALETTE.StarlightGold
	gProgFill.BorderSizePixel = 0
	addCorner(gProgFill, 4)
	gProgFill.Parent = gProgTrack
	guideProgressFill = gProgFill

	local closeGuideBtn = makeTextButton(gDrawer, "CloseGuideBtn", "X", PALETTE.CardDark, PALETTE.TextCream, UDim2.fromOffset(44, 44), 16)
	closeGuideBtn.AnchorPoint = Vector2.new(1, 0)
	closeGuideBtn.Position = UDim2.new(1, -12, 0, 10)
	closeGuideBtn:SetAttribute("GuideActionKey", "CloseGuide")
	closeGuideBtn.SelectionGained:Connect(function()
		lastFocusedGuideKey = "CloseGuide"
	end)
	addStroke(closeGuideBtn, PALETTE.BorderSoft, 1)
	closeGuideBtn.Activated:Connect(function()
		SoundController.Play("Click")
		UIController.CloseDrawers()
	end)
	guideCloseButton = closeGuideBtn

	local gScroll = Instance.new("ScrollingFrame")
	gScroll.Name = "FieldGuideScroll"
	gScroll.Position = UDim2.fromOffset(12, 74)
	gScroll.Size = UDim2.new(1, -24, 1, -86)
	gScroll.BackgroundTransparency = 1
	gScroll.BorderSizePixel = 0
	gScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	gScroll.AutomaticCanvasSize = Enum.AutomaticSize.None
	gScroll.ScrollBarThickness = 6
	gScroll.ScrollBarImageColor3 = PALETTE.StarlightGold
	gScroll.Parent = gDrawer
	guideScrollFrame = gScroll

	local gScrollLayout = Instance.new("UIListLayout")
	gScrollLayout.Padding = UDim.new(0, 8)
	gScrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gScrollLayout.Parent = gScroll
	guideScrollLayout = gScrollLayout

	if guideLayoutChangedConn ~= nil then
		guideLayoutChangedConn:Disconnect()
	end
	guideLayoutChangedConn = gScrollLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		if not guideRestoreInFlight then
			syncGuideCanvasSize(nil)
		end
	end)

	-- Compact Opt-In Soak Perf Stats Overlay (zero RenderStepped overhead when OFF)
	local pOverlay = Instance.new("Frame")
	pOverlay.Name = "PerfOverlay"
	pOverlay.AnchorPoint = Vector2.new(0, 0)
	pOverlay.Position = UDim2.fromOffset(10, 58)
	pOverlay.Size = UDim2.fromOffset(296, 44)
	pOverlay.BackgroundColor3 = PALETTE.PanelDark
	pOverlay.BackgroundTransparency = 0.15
	pOverlay.BorderSizePixel = 0
	pOverlay.Active = false
	pOverlay.ZIndex = 1
	pOverlay.Visible = false
	addCorner(pOverlay, 10)
	addStroke(pOverlay, PALETTE.BorderSoft, 1)
	pOverlay.Parent = screenGui
	perfOverlayFrame = pOverlay

	local pLine1 = Instance.new("TextLabel")
	pLine1.Name = "Line1"
	pLine1.Position = UDim2.fromOffset(8, 3)
	pLine1.Size = UDim2.new(1, -16, 0, 18)
	pLine1.BackgroundTransparency = 1
	pLine1.TextColor3 = PALETTE.MeadowMint
	pLine1.Font = Enum.Font.GothamBold
	pLine1.TextSize = 11
	pLine1.TextXAlignment = Enum.TextXAlignment.Left
	pLine1.TextTruncate = Enum.TextTruncate.AtEnd
	pLine1.Active = false
	pLine1.Text = "FPS: sampling... | T+00:00"
	pLine1.Parent = pOverlay
	perfLine1Label = pLine1

	local pLine2 = Instance.new("TextLabel")
	pLine2.Name = "Line2"
	pLine2.Position = UDim2.fromOffset(8, 22)
	pLine2.Size = UDim2.new(1, -16, 0, 18)
	pLine2.BackgroundTransparency = 1
	pLine2.TextColor3 = PALETTE.TextCream
	pLine2.Font = Enum.Font.GothamMedium
	pLine2.TextSize = 11
	pLine2.TextXAlignment = Enum.TextXAlignment.Left
	pLine2.TextTruncate = Enum.TextTruncate.AtEnd
	pLine2.Active = false
	pLine2.Text = "Mem: --MB (Lua --MB) | Vis: 0 | Met: 0"
	pLine2.Parent = pOverlay
	perfLine2Label = pLine2

	-- Settings Popover
	local sDrawer = Instance.new("Frame")
	sDrawer.Name = "SettingsDrawer"
	sDrawer.AnchorPoint = Vector2.new(0, 0)
	sDrawer.Position = UDim2.fromOffset(34, 108)
	sDrawer.Size = UDim2.fromOffset(278, SETTINGS_DRAWER_HEIGHT)
	sDrawer.BackgroundColor3 = PALETTE.PanelDark
	sDrawer.BackgroundTransparency = 0.04
	sDrawer.BorderSizePixel = 0
	sDrawer.Visible = false
	addCorner(sDrawer, 14)
	addStroke(sDrawer, PALETTE.BorderSoft, 1.5)
	trapGamepadFocus(sDrawer)
	sDrawer.Parent = screenGui
	settingsDrawer = sDrawer

	local sTitle = Instance.new("TextLabel")
	sTitle.Size = UDim2.new(1, -64, 0, 28)
	sTitle.Position = UDim2.fromOffset(14, 12)
	sTitle.BackgroundTransparency = 1
	sTitle.Text = "Settings & Access"
	sTitle.TextColor3 = PALETTE.TextCream
	sTitle.Font = Enum.Font.GothamBold
	sTitle.TextSize = 16
	sTitle.TextXAlignment = Enum.TextXAlignment.Left
	sTitle.Parent = sDrawer

	local closeSettingsBtn = makeTextButton(sDrawer, "CloseSettingsBtn", "X", PALETTE.CardDark, PALETTE.TextCream, UDim2.fromOffset(44, 44), 15)
	closeSettingsBtn.AnchorPoint = Vector2.new(1, 0)
	closeSettingsBtn.Position = UDim2.new(1, -10, 0, 8)
	closeSettingsBtn.Activated:Connect(function()
		SoundController.Play("Click")
		UIController.CloseDrawers()
	end)

	local muteBtn = makeTextButton(sDrawer, "MuteToggleBtn", "Mute Sound: OFF", PALETTE.CardDark, PALETTE.TextCream, UDim2.new(1, -24, 0, 44), 14)
	muteBtn.Position = UDim2.fromOffset(12, 58)
	addStroke(muteBtn, PALETTE.BorderSoft, 1)
	muteBtn.Activated:Connect(function()
		local nowMuted = SoundController.ToggleMuted()
		if not nowMuted then
			SoundController.Play("Click")
		end
	end)
	muteToggleButton = muteBtn

	local motionBtn = makeTextButton(sDrawer, "MotionToggleBtn", "Reduced Motion: OFF", PALETTE.CardDark, PALETTE.TextCream, UDim2.new(1, -24, 0, 44), 14)
	motionBtn.Position = UDim2.fromOffset(12, 110)
	addStroke(motionBtn, PALETTE.BorderSoft, 1)
	motionBtn.Activated:Connect(function()
		SoundController.ToggleReducedMotion()
		SoundController.Play("Click")
	end)
	motionToggleButton = motionBtn

	local perfBtn = makeTextButton(sDrawer, "PerfToggleBtn", "Soak Perf Stats: OFF", PALETTE.CardDark, PALETTE.TextCream, UDim2.new(1, -24, 0, 44), 14)
	perfBtn.Position = UDim2.fromOffset(12, 162)
	addStroke(perfBtn, PALETTE.BorderSoft, 1)
	perfBtn.Activated:Connect(function()
		UIController.TogglePerfOverlay()
		SoundController.Play("Click")
	end)
	perfToggleButton = perfBtn

	local cHint = Instance.new("TextLabel")
	cHint.Name = "ControlsHint"
	cHint.Size = UDim2.new(1, -24, 0, 50)
	cHint.Position = UDim2.fromOffset(12, 212)
	cHint.BackgroundTransparency = 1
	cHint.TextColor3 = PALETTE.TextMuted
	cHint.Font = Enum.Font.GothamMedium
	cHint.TextSize = 12
	cHint.TextWrapped = true
	cHint.TextXAlignment = Enum.TextXAlignment.Left
	cHint.Parent = sDrawer
	controlsHintLabel = cHint

	SoundController.OnSettingsChanged(updateSettingsTogglesUI)
	updateActionButtonsText()
	applyResponsiveTopLayout()

	if sizeChangedConn ~= nil then
		sizeChangedConn:Disconnect()
	end
	sizeChangedConn = screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyResponsiveTopLayout)
end

function UIController.Start(self: typeof(UIController)): ()
	local remotes = ReplicatedStorage:WaitForChild(Constants.REMOTES_FOLDER_NAME)
	local syncEvent = remotes:WaitForChild(Constants.REMOTE_NAMES.SyncOwnerState) :: RemoteEvent
	plotActionRemote = remotes:WaitForChild(Constants.REMOTE_NAMES.RequestPlotAction) :: RemoteEvent
	buyUpgradeRemote = remotes:WaitForChild(Constants.REMOTE_NAMES.RequestBuyUpgrade) :: RemoteFunction
	navigateRemote = remotes:WaitForChild(Constants.REMOTE_NAMES.RequestNavigate) :: RemoteFunction

	if syncConn == nil then
		syncConn = syncEvent.OnClientEvent:Connect(function(dto: Types.OwnerStateDTO)
			if typeof(dto) ~= "table" or typeof(dto.Revision) ~= "number" then
				return
			end
			if latestOwnerState ~= nil and dto.Revision < latestOwnerState.Revision then
				return
			end

			local prevDto = latestOwnerState
			latestOwnerState = dto
			print(string.format(
				"[UIController] Synced OwnerStateDTO (Revision %d, Coins %d, BagCap %d, Reserved %d).",
				dto.Revision,
				dto.Coins,
				dto.BagCap,
				dto.ReservedBagSlots or 0
			))

			handleAuthoritativeStateDiff(prevDto, dto)
			refreshAllHUD(dto)

			for _, cb in ipairs(stateChangedCallbacks) do
				local ok, err = pcall(cb, dto)
				if not ok then
					warn("[UIController] State listener error: " .. tostring(err))
				end
			end
		end)
	end

	if not timerLoopStarted then
		timerLoopStarted = true
		task.spawn(function()
			while timerLoopStarted do
				task.wait(1)
				if latestOwnerState ~= nil then
					updateContextualHint()
					if bagOpen and #activeTimerBindings > 0 then
						local nowClock = workspace:GetServerTimeNow()
						local flippedMature = false
						for _, binding in ipairs(activeTimerBindings) do
							local rem = binding.MaturesAt - nowClock
							if rem <= 0 then
								if not binding.WasMature then
									flippedMature = true
									break
								end
								binding.Label.Text = "READY TO HATCH!"
							else
								binding.Label.Text = string.format("Hatching in %s", FormatUtil.FormatTimer(rem))
							end
						end
						if flippedMature then
							rebuildBagContents(true)
						end
					end
				end
			end
		end)
	end
end

function UIController.GetLatestOwnerState(): Types.OwnerStateDTO?
	return latestOwnerState
end

function UIController.OnOwnerStateChanged(callback: (dto: Types.OwnerStateDTO) -> ()): ()
	table.insert(stateChangedCallbacks, callback)
	if latestOwnerState ~= nil then
		callback(latestOwnerState)
	end
end

function UIController.GetHudScreenGui(): ScreenGui?
	return hudGui
end

function UIController.IsDrawerOpen(): boolean
	return bagOpen or guideOpen or settingsOpen
end

function UIController.IsFieldGuideOpen(): boolean
	return guideOpen
end

function UIController.IsPerfOverlayOpen(): boolean
	return perfOverlayEnabled
end

function UIController.TogglePerfOverlay(): boolean
	setPerfOverlayEnabled(not perfOverlayEnabled)
	return perfOverlayEnabled
end

function UIController.GetSelectedGamepadTarget(): GuiObject?
	if bagOpen then
		return resolveBagSelectionTarget(lastFocusedBagKey)
	elseif guideOpen then
		return resolveGuideSelectionTarget(lastFocusedGuideKey)
	elseif settingsOpen then
		return muteToggleButton
	end
	return nil
end

function UIController.ToggleBag(): boolean
	bagOpen = not bagOpen
	if bagOpen then
		guideOpen = false
		settingsOpen = false
		guideRestoreToken += 1
		guideRestoreInFlight = false
		lastFocusedGuideKey = nil
		rebuildBagContents(false)
	else
		bagRestoreToken += 1
		bagRestoreInFlight = false
		pendingSellConfirmUID = nil
		lastFocusedBagKey = nil
		applyDrawerVisibility(nil, nil)
	end
	return bagOpen
end

function UIController.ToggleFieldGuide(): boolean
	guideOpen = not guideOpen
	if guideOpen then
		bagOpen = false
		settingsOpen = false
		bagRestoreToken += 1
		bagRestoreInFlight = false
		pendingSellConfirmUID = nil
		lastFocusedBagKey = nil
		rebuildFieldGuideContents(false)
	else
		guideRestoreToken += 1
		guideRestoreInFlight = false
		lastFocusedGuideKey = nil
		applyDrawerVisibility(nil, nil)
	end
	return guideOpen
end

function UIController.ToggleSettings(): boolean
	settingsOpen = not settingsOpen
	if settingsOpen then
		bagOpen = false
		guideOpen = false
		bagRestoreToken += 1
		bagRestoreInFlight = false
		guideRestoreToken += 1
		guideRestoreInFlight = false
		pendingSellConfirmUID = nil
		lastFocusedBagKey = nil
		lastFocusedGuideKey = nil
	end
	applyDrawerVisibility(nil, nil)
	return settingsOpen
end

function UIController.CloseDrawers(): boolean
	local hadOpen = bagOpen or guideOpen or settingsOpen
	bagOpen = false
	guideOpen = false
	settingsOpen = false
	bagRestoreToken += 1
	bagRestoreInFlight = false
	guideRestoreToken += 1
	guideRestoreInFlight = false
	pendingSellConfirmUID = nil
	lastFocusedBagKey = nil
	lastFocusedGuideKey = nil
	applyDrawerVisibility(nil, nil)
	return hadOpen
end

function UIController.InvokeNavigationForTest(
	target: Types.NavigationTarget,
	customInvoker: (Types.NavigationTarget) -> any
): boolean
	if navigateDispatcher == nil then
		return false
	end
	return navigateDispatcher(target, customInvoker)
end

function UIController.SetInputMode(mode: InputMode): ()
	if currentInputMode == mode then
		return
	end
	currentInputMode = mode
	updateActionButtonsText()
	applyDrawerVisibility(nil)
end

function UIController.RunSelfTest(): number
	local passed = 0
	local scroll = bagScrollFrame :: ScrollingFrame
	local layoutRef = bagScrollLayout :: UIListLayout
	local gScroll = guideScrollFrame :: ScrollingFrame
	local savedMode = currentInputMode

	local function waitForBagSettled(): ()
		local frames = 0
		while bagRestoreInFlight and frames < 15 do
			RunService.RenderStepped:Wait()
			frames += 1
		end
		RunService.RenderStepped:Wait()
	end

	local function waitForGuideSettled(): ()
		local frames = 0
		while guideRestoreInFlight and frames < 15 do
			RunService.RenderStepped:Wait()
			frames += 1
		end
		RunService.RenderStepped:Wait()
	end

	local testOk, testErr = pcall(function()
		RunService.RenderStepped:Wait()

		-- 1. Narrow (320px portrait), landscape mobile (667x375) & desktop safe-width top HUD & drawer geometry invariants
		for _, w in ipairs({ 320, 360, 375, 440, 559, 560, 667, 1280 }) do
			local layout = UIController.ComputeTopHudLayout(w)
			assert(layout.Stacked == (w < WIDE_TOP_HUD_MIN_WIDTH), "Expected stacked layout only below 560px")
			assert(layout.ResourceX >= 0 and (layout.ResourceX + layout.ResourceWidth) <= w, "ResourceBar stays in bounds")
			assert(layout.ActionsX >= 0 and (layout.ActionsX + layout.ActionsWidth) <= w, "ActionTray stays in bounds")
			assert(layout.ActionsWidth >= ACTION_TRAY_WIDTH, "ActionTray fits Hub + Ranch + Bag + Guide + Settings")
			assert(layout.SettingsX >= 0 and (layout.SettingsX + layout.SettingsWidth) <= w, "SettingsDrawer stays in bounds")

			local xOverlap = layout.ResourceX < (layout.ActionsX + layout.ActionsWidth)
				and (layout.ResourceX + layout.ResourceWidth) > layout.ActionsX
			local yOverlap = layout.ResourceY < (layout.ActionsY + layout.ActionsHeight)
				and (layout.ResourceY + layout.ResourceHeight) > layout.ActionsY
			assert(not (xOverlap and yOverlap), "ResourceBar and ActionTray must never overlap at width " .. tostring(w))
			assert(layout.ToastY >= math.max(layout.ResourceY + layout.ResourceHeight, layout.ActionsY + layout.ActionsHeight), "Toast sits cleanly below top HUD")
		end
		for _, dims in ipairs({ { 320, 568 }, { 375, 667 }, { 667, 375 }, { 1280, 720 } }) do
			local topL = UIController.ComputeTopHudLayout(dims[1])
			local dL = UIController.ComputeDrawerLayout(dims[1], dims[2])
			local topBottom = math.max(topL.ResourceY + topL.ResourceHeight, topL.ActionsY + topL.ActionsHeight)
			assert(dL.X >= 0 and (dL.X + dL.Width) <= dims[1], "Drawer width stays inside Safe Area")
			assert(dL.Y >= topBottom and (dL.Y + dL.Height) <= dims[2], "Drawer clears Top HUD & stays inside Safe Area height")
			assert(dL.Height >= 180, "Drawer preserves usable scroll height on compact landscape screens")
			assert((topL.SettingsY + SETTINGS_DRAWER_HEIGHT) <= dims[2], "SettingsDrawer fits inside Safe Area height")
		end
		for _, navBtn in ipairs({ hubButton, ranchButton, bagButton, guideButton, settingsButton }) do
			assert(navBtn ~= nil and navBtn.AbsoluteSize.X >= 44 and navBtn.AbsoluteSize.Y >= 44, "All top HUD buttons maintain >= 44px touch target")
		end
		assert(
			bagDrawer ~= nil and bagDrawer.SelectionGroup == true
				and guideDrawer ~= nil and guideDrawer.SelectionGroup == true
				and settingsDrawer ~= nil and settingsDrawer.SelectionGroup == true,
			"Modal drawers enforce Gamepad SelectionGroup trapping"
		)
		passed += 1

		-- 2. Final rendered Bag scroll, Coin-only in-place update & post-layout structural rebuild
		local mockItems: { [string]: Types.CritterItemRecord } = {
			["h-1"] = {
				UID = "h-1",
				SpeciesId = "StarSlime",
				Variant = "Normal",
				State = "HatchedInBag",
				CreatedAt = 100,
			},
			["h-2"] = {
				UID = "h-2",
				SpeciesId = "NebulaFox",
				Variant = "Normal",
				State = "HatchedInBag",
				CreatedAt = 101,
			},
			["h-3"] = {
				UID = "h-3",
				SpeciesId = "SolarGolem",
				Variant = "Normal",
				State = "HatchedInBag",
				CreatedAt = 102,
			},
			["h-4"] = {
				UID = "h-4",
				SpeciesId = "StarSlime",
				Variant = "Radiant",
				State = "HatchedInBag",
				CreatedAt = 103,
			},
			["p-1"] = {
				UID = "p-1",
				SpeciesId = "StarSlime",
				Variant = "Normal",
				State = "PodInBag",
				CreatedAt = 104,
			},
			["p-2"] = {
				UID = "p-2",
				SpeciesId = "NebulaFox",
				Variant = "Normal",
				State = "PodInBag",
				CreatedAt = 105,
			},
			["p-3"] = {
				UID = "p-3",
				SpeciesId = "SolarGolem",
				Variant = "Normal",
				State = "PodInBag",
				CreatedAt = 106,
			},
			["pen-1"] = {
				UID = "pen-1",
				SpeciesId = "StarSlime",
				Variant = "Normal",
				State = "InPen",
				AssignedSlot = "Pen_1",
				CreatedAt = 99,
				FeedLevel = 0,
			},
		}
		local dto1: Types.OwnerStateDTO = {
			Revision = 1,
			Coins = 44,
			BagCap = Constants.MAX_BAG_CAPACITY,
			ReservedBagSlots = 0,
			Items = mockItems,
			Slots = { Pen_1 = "pen-1" },
			Upgrades = { FrostCracker = true },
			DiscoveredSpecies = { StarSlime = true, NebulaFox = true, SolarGolem = true },
		}
		local dto2: Types.OwnerStateDTO = {
			Revision = 2,
			Coins = 75,
			BagCap = Constants.MAX_BAG_CAPACITY,
			ReservedBagSlots = 0,
			Items = mockItems,
			Slots = { Pen_1 = "pen-1" },
			Upgrades = { FrostCracker = true },
			DiscoveredSpecies = { StarSlime = true, NebulaFox = true, SolarGolem = true },
		}

		currentInputMode = "Gamepad"
		bagOpen = true
		settingsOpen = false
		latestOwnerState = dto1

		rebuildBagContents(false)
		waitForBagSettled()
		assert(not bagRestoreInFlight, "Initial Bag restore must settle within bounded frames")
		assert(layoutRef.AbsoluteContentSize.Y > scroll.AbsoluteWindowSize.Y, "Rendered Bag list must overflow window height for scroll test")
		local maxScrollY = getMaxBagScrollY()
		assert(maxScrollY >= 40, "Rendered Bag must have >= 40px scrollable range")

		local rebuildsBefore = bagRebuildCount
		local feedBtnRef = feedButtonsBySlot["Pen_1"]
		local pen2BtnRef = upgradeBuyButtons["PenSlot_2"]
		local lureBtnRef = frostLureButton
		assert(feedBtnRef ~= nil, "Pen_1 Feed button rendered")
		assert(feedBtnRef.BackgroundColor3 == PALETTE.CardDark, "Pen_1 Feed starts unaffordable at 44 Coins")
		assert(pen2BtnRef ~= nil, "PenSlot_2 buy button rendered")
		assert(pen2BtnRef.BackgroundColor3 == PALETTE.CardDark, "PenSlot_2 starts unaffordable at 44 Coins")
		assert(lureBtnRef ~= nil, "Frost Lure summon button rendered")
		assert(lureBtnRef.BackgroundColor3 == PALETTE.CardDark, "Frost Lure starts unaffordable at 44 Coins")
		assert(scroll:FindFirstChild("Section_Field Guide (Discovered: 3 / 6)") ~= nil, "Field Guide header renders 3 / 6 discovered")

		local btnRelY = pen2BtnRef.AbsolutePosition.Y - scroll.AbsolutePosition.Y + scroll.CanvasPosition.Y
		local desiredScrollY = math.clamp(math.floor(btnRelY - scroll.AbsoluteWindowSize.Y * 0.5), 40, maxScrollY)
		scroll.CanvasPosition = Vector2.new(0, desiredScrollY)
		lastFocusedBagKey = "Buy:PenSlot_2"
		safeSetSelectedObject(pen2BtnRef)
		RunService.RenderStepped:Wait()

		local settledScrollY = scroll.CanvasPosition.Y
		assert(settledScrollY >= 35, "Bag scrolled to real non-zero rendered position")

		-- Coin-only update preserves rows, button instances, affordability colors, focus & scroll
		refreshAllHUD(dto2)
		RunService.RenderStepped:Wait()
		assert(bagRebuildCount == rebuildsBefore, "Coin-only update must not rebuild Bag rows")
		assert(feedButtonsBySlot["Pen_1"] == feedBtnRef, "Coin-only update preserves exact Feed button instance")
		assert(feedBtnRef.BackgroundColor3 == PALETTE.MeadowMint, "Coin-only update refreshes Feed affordability color in place")
		assert(upgradeBuyButtons["PenSlot_2"] == pen2BtnRef, "Coin-only update preserves exact Buy button instance")
		assert(pen2BtnRef.BackgroundColor3 == PALETTE.MeadowMint, "Coin-only update refreshes Buy affordability color in place")
		assert(frostLureButton == lureBtnRef, "Coin-only update preserves exact Frost Lure button instance")
		assert(lureBtnRef.BackgroundColor3 == PALETTE.MeadowMint, "Coin-only update refreshes Frost Lure affordability color in place")
		assert(math.abs(scroll.CanvasPosition.Y - settledScrollY) <= 1, "Coin-only update preserves rendered scroll position")
		assert(lastFocusedBagKey == "Buy:PenSlot_2", "Coin-only update preserves focused Bag action key")
		assert(hintBarFrame ~= nil and hintBarFrame.Visible == false, "BottomHintBar auto-hides after Pen #1 placed")

		-- Structural rebuild preserves lower-row focus & rendered scroll position after layout settles
		pendingSellConfirmUID = "h-2"
		pendingSellConfirmExpiresAt = os.clock() + 3
		lastFocusedBagKey = "Buy:PenSlot_2"
		rebuildBagContents(true)
		waitForBagSettled()

		assert(not bagRestoreInFlight, "Post-rebuild restore must finish settling")
		assert(bagRebuildCount == rebuildsBefore + 1, "Structural change rebuilds Bag rows")
		assert(math.abs(scroll.CanvasPosition.Y - settledScrollY) <= 1, "Structural rebuild restores final rendered scroll position")

		local rebuiltBuyBtn = upgradeBuyButtons["PenSlot_2"]
		assert(rebuiltBuyBtn ~= nil and resolveBagSelectionTarget("Buy:PenSlot_2") == rebuiltBuyBtn, "Structural rebuild preserves lower-row Buy target")
		if GuiService.GuiNavigationEnabled and canSelectGuiObject(rebuiltBuyBtn) then
			assert(GuiService.SelectedObject == rebuiltBuyBtn, "Gamepad selection stays on lower-row Buy button after structural rebuild")
		end

		local resolvedSell = resolveBagSelectionTarget("Sell:h-2")
		assert(resolvedSell ~= nil and resolvedSell ~= firstBagSelectable, "Confirm Sell button remains resolvable outside row 1")
		assert((resolvedSell :: TextButton).Text == "Confirm Sell?", "Focused button updated cleanly to Confirm Sell?")

		-- Verify BagCap_20 expands HUD & Bag header capacity label cleanly
		local dtoBag20: Types.OwnerStateDTO = {
			Revision = 3,
			Coins = 1500,
			BagCap = Constants.MAX_BAG_CAPACITY_UPGRADED,
			ReservedBagSlots = 0,
			Items = mockItems,
			Slots = { Pen_1 = "pen-1" },
			Upgrades = { FrostCracker = true, Incubator_2 = true, BagCap_20 = true },
			DiscoveredSpecies = { StarSlime = true, NebulaFox = true, SolarGolem = true },
		}
		latestOwnerState = dtoBag20
		refreshAllHUD(dtoBag20)
		waitForBagSettled()
		assert(bagCapacityLabel ~= nil and string.find(bagCapacityLabel.Text, "/20", 1, true) ~= nil, "Bag drawer shows /20 capacity after BagCap_20")
		assert(bagLabel ~= nil and string.find(bagLabel.Text, "/20", 1, true) ~= nil, "Top HUD BagLabel shows /20 capacity")

		-- Verify server-acknowledged navigation only confirms arrival on Ok=true and honors 2.0s client cooldown
		lastNavRequestClock = -Constants.NAVIGATE_CLIENT_COOLDOWN_SECONDS
		pendingNavigate = false
		assert(
			UIController.InvokeNavigationForTest("Hub", function()
				return { Ok = false, Reason = "RateLimited" }
			end),
			"Test navigation dispatches when cooldown expired"
		)
		assert(
			toastLabel ~= nil
				and toastLabel.Text == "Travel cooling down — wait a moment!"
				and string.find(toastLabel.Text, "Arrived", 1, true) == nil,
			"RateLimited RequestNavigate must not show arrival confirmation toast"
		)

		lastNavRequestClock = -Constants.NAVIGATE_CLIENT_COOLDOWN_SECONDS
		assert(
			UIController.InvokeNavigationForTest("Hub", function()
				return { Ok = true, Target = "Hub" }
			end),
			"Hub navigation dispatches when server acknowledges Ok"
		)
		assert(
			toastLabel ~= nil and toastLabel.Text == "Arrived at Observatory Hub!",
			"Successful RequestNavigate shows arrival confirmation"
		)
		assert(
			not UIController.InvokeNavigationForTest("Ranch", function()
				error("Client cooldown must prevent rapid re-invoke before 2s elapsed")
			end),
			"Client cooldown blocks rapid re-invoke within 2.0s"
		)
		passed += 1

		-- 3. S4-02 Dedicated Field Guide Checklist (cosmetic-only discovery tracking, Coin-tick stability, Gamepad/mutual exclusion)
		assert(UIController.ToggleFieldGuide() == true, "ToggleFieldGuide opens FieldGuideDrawer")
		waitForGuideSettled()
		assert(not bagOpen and not settingsOpen and guideDrawer ~= nil and guideDrawer.Visible, "FieldGuide opens mutually exclusively")
		assert(guideProgressLabel ~= nil and string.find(guideProgressLabel.Text, "3 / 6", 1, true) ~= nil, "FieldGuide displays 3 / 6 discovered")

		local guideRebuildsBefore = guideRebuildCount
		local slimeCard = gScroll:FindFirstChild("GuideCard_StarSlime")
		local owlCard = gScroll:FindFirstChild("GuideCard_CometOwl")
		assert(slimeCard ~= nil and owlCard ~= nil, "FieldGuide renders all species cards")
		local hasRadiantText = false
		for _, ch in ipairs(slimeCard:GetChildren()) do
			if ch:IsA("TextLabel") and string.find(ch.Text, "Radiant", 1, true) ~= nil then
				hasRadiantText = true
			end
		end
		assert(hasRadiantText, "FieldGuide highlights Radiant specimen seen for StarSlime")
		local owlUnknownText = false
		for _, ch in ipairs(owlCard:GetChildren()) do
			if ch:IsA("TextLabel") and string.find(ch.Text, "??? [Legendary]", 1, true) ~= nil then
				owlUnknownText = true
			end
		end
		assert(owlUnknownText, "Undiscovered CometOwl remains concealed behind clue card")

		-- Coin-only state change must not rebuild Field Guide cards
		local dtoCoinTick: Types.OwnerStateDTO = {
			Revision = 4,
			Coins = 2200,
			BagCap = Constants.MAX_BAG_CAPACITY_UPGRADED,
			ReservedBagSlots = 0,
			Items = mockItems,
			Slots = { Pen_1 = "pen-1" },
			Upgrades = { FrostCracker = true, Incubator_2 = true, BagCap_20 = true },
			DiscoveredSpecies = { StarSlime = true, NebulaFox = true, SolarGolem = true },
		}
		latestOwnerState = dtoCoinTick
		refreshAllHUD(dtoCoinTick)
		RunService.RenderStepped:Wait()
		assert(guideRebuildCount == guideRebuildsBefore, "Coin-only update must not rebuild Field Guide")

		-- New species discovery updates Field Guide cleanly to 4 / 6
		local dtoDiscoverOwl: Types.OwnerStateDTO = {
			Revision = 5,
			Coins = 2200,
			BagCap = Constants.MAX_BAG_CAPACITY_UPGRADED,
			ReservedBagSlots = 0,
			Items = mockItems,
			Slots = { Pen_1 = "pen-1" },
			Upgrades = { FrostCracker = true, Incubator_2 = true, BagCap_20 = true },
			DiscoveredSpecies = { StarSlime = true, NebulaFox = true, SolarGolem = true, CometOwl = true },
		}
		latestOwnerState = dtoDiscoverOwl
		refreshAllHUD(dtoDiscoverOwl)
		waitForGuideSettled()
		assert(guideRebuildCount == guideRebuildsBefore + 1, "New species discovery rebuilds Field Guide")
		assert(guideProgressLabel ~= nil and string.find(guideProgressLabel.Text, "4 / 6", 1, true) ~= nil, "FieldGuide updates cleanly to 4 / 6")
		local revealedOwlCard = gScroll:FindFirstChild("GuideCard_CometOwl")
		assert(revealedOwlCard ~= nil, "CometOwl card present after discovery")
		local owlRevealedTitle = false
		for _, ch in ipairs(revealedOwlCard:GetChildren()) do
			if ch:IsA("TextLabel") and string.find(ch.Text, "Comet Owl [Legendary]", 1, true) ~= nil then
				owlRevealedTitle = true
			end
		end
		assert(owlRevealedTitle, "Newly discovered CometOwl reveals title & stats in Field Guide")
		assert(UIController.CloseDrawers() == true and not UIController.IsDrawerOpen(), "CloseDrawers cleanly closes FieldGuideDrawer")

		-- S4-03 Soak Perf Stats overlay toggles cleanly with zero leftover RenderStepped listener when OFF
		assert(UIController.TogglePerfOverlay() == true and UIController.IsPerfOverlayOpen() == true, "TogglePerfOverlay opens Soak Perf Stats")
		assert(perfOverlayFrame ~= nil and perfOverlayFrame.Visible == true and perfRenderConn ~= nil, "PerfOverlay visible and sampling when ON")
		assert(perfLine2Label ~= nil and string.find(perfLine2Label.Text, "Vis:", 1, true) ~= nil and string.find(perfLine2Label.Text, "Met:", 1, true) ~= nil, "PerfOverlay Line2 renders Vis and Met counters")
		assert(perfToggleButton ~= nil and perfToggleButton.Text == "Soak Perf Stats: ON", "PerfToggleButton text updates to ON")
		assert(UIController.TogglePerfOverlay() == false and UIController.IsPerfOverlayOpen() == false, "TogglePerfOverlay closes cleanly")
		assert(perfOverlayFrame ~= nil and perfOverlayFrame.Visible == false and perfRenderConn == nil, "PerfOverlay disconnects RenderStepped cleanly when OFF")
		assert(perfToggleButton ~= nil and perfToggleButton.Text == "Soak Perf Stats: OFF", "PerfToggleButton text resets to OFF")
		passed += 1
	end)

	-- Restore pristine empty UI state before ClientInit starts live snapshot listener
	setPerfOverlayEnabled(false)
	bagRestoreToken += 1
	bagRestoreInFlight = false
	guideRestoreToken += 1
	guideRestoreInFlight = false
	currentInputMode = savedMode
	bagOpen = false
	guideOpen = false
	settingsOpen = false
	latestOwnerState = nil
	pendingSellConfirmUID = nil
	pendingSellConfirmExpiresAt = 0
	pendingNavigate = false
	lastNavRequestClock = -Constants.NAVIGATE_CLIENT_COOLDOWN_SECONDS
	toastToken += 1
	if toastLabel ~= nil then
		toastLabel.Visible = false
		toastLabel.Text = ""
	end
	lastBagStructureSignature = nil
	lastFocusedBagKey = nil
	bagRebuildCount = 0
	bagButtonsByKey = {}
	upgradeBuyButtons = {}
	feedButtonsBySlot = {}
	frostLureButton = nil
	activeTimerBindings = {}
	firstBagSelectable = nil
	lastGuideStructureSignature = nil
	lastFocusedGuideKey = nil
	guideRebuildCount = 0
	guideButtonsByKey = {}
	firstGuideSelectable = nil
	if bagCapacityLabel ~= nil then
		bagCapacityLabel.Text = "Bag: 0/10 committed"
	end
	if guideProgressLabel ~= nil then
		guideProgressLabel.Text = "Discovered: 0 / 6  •  Cosmetic Checklist"
	end
	if guideProgressFill ~= nil then
		guideProgressFill.Size = UDim2.fromScale(0, 1)
	end
	GuiService.SelectedObject = nil
	for _, child in ipairs(scroll:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	scroll.CanvasPosition = Vector2.zero
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.None
	for _, child in ipairs(gScroll:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	gScroll.CanvasPosition = Vector2.zero
	gScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	gScroll.AutomaticCanvasSize = Enum.AutomaticSize.None
	if coinsLabel ~= nil then
		coinsLabel.Text = "0 Coins"
	end
	if rateLabel ~= nil then
		rateLabel.Text = "+0 Coins/s"
	end
	if bagLabel ~= nil then
		bagLabel.Text = "Bag: 0/10"
		bagLabel.TextColor3 = PALETTE.TextCream
	end
	if hintBarFrame ~= nil then
		hintBarFrame.Visible = true
	end
	if hintLabel ~= nil then
		hintLabel.Text = "Connecting to your Starfall Ranch..."
		hintLabel.TextColor3 = PALETTE.StarlightGold
	end
	updateActionButtonsText()
	applyDrawerVisibility(nil, nil)
	applyResponsiveTopLayout()

	if not testOk then
		error(testErr)
	end

	return passed
end

return UIController
