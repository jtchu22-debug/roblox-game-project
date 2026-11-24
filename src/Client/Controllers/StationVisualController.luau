--!strict
--[[
	Controller: StationVisualController
	Purpose: Replaces greybox station placeholders on Plot_1 Incubators and CentralHub ToolWorkbench
	         with S6-ART-02 modeled templates while preserving authoritative interaction anchors,
	         ProximityPrompts, ToolVisualController displays, and live Locked/Idle/Incubating/Ready states.
	Connections: Requires SoundController, UIController, PlotVisualController, Constants, Types.
	How to Test in Studio: Press Play (F5) for automated self-tests, inspect Plot_1 Incubators &
	                       CentralHub ToolWorkbench, and incubate/unlock slots to verify state changes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ControllersFolder = script.Parent
local PlotVisualController = require(ControllersFolder:WaitForChild("PlotVisualController"))
local SoundController = require(ControllersFolder:WaitForChild("SoundController"))
local UIController = require(ControllersFolder:WaitForChild("UIController"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Types = require(Shared:WaitForChild("Types"))

export type IncubatorVisualState = "Locked" | "Idle" | "Incubating" | "Ready"

type IncubatorEntry = {
	SlotId: string,
	Pad: BasePart,
	Model: Model,
	StatusRing: BasePart,
	Canopy: BasePart,
	BaseParts: { BasePart },
	CurrentState: IncubatorVisualState,
}

local STATION_FOLDER_NAME = "StarfallStationVisuals"
local MAX_STATION_PARTS = 8
local INCUBATOR_POD_Y_OFFSET = 2.95

local STATE_COLORS: { [IncubatorVisualState]: Color3 } = {
	Locked = Color3.fromRGB(82, 86, 108),
	Idle = Color3.fromRGB(85, 195, 185),
	Incubating = Color3.fromRGB(65, 210, 255),
	Ready = Color3.fromRGB(255, 205, 45),
}

local StationVisualController = {
	Name = "StationVisualController",
}

local stationFolder: Folder? = nil
local incubatorEntries: { [string]: IncubatorEntry } = {}
local workbenchModel: Model? = nil
local listenersBound = false
local heartbeatConn: RBXScriptConnection? = nil
local lastPlots: { [number]: Types.PublicPlotDTO } = {}
local lastOwnerState: Types.OwnerStateDTO? = nil

local function getStationFolder(): Folder
	if stationFolder ~= nil and stationFolder.Parent == workspace then
		return stationFolder
	end
	local existing = workspace:FindFirstChild(STATION_FOLDER_NAME)
	if existing ~= nil and existing:IsA("Folder") then
		stationFolder = existing
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = STATION_FOLDER_NAME
	folder.Parent = workspace
	stationFolder = folder
	return folder
end

local function isValidStationTemplate(template: Instance?, requiredPrimaryName: string): (boolean, string?)
	if template == nil or not template:IsA("Model") then
		return false, "template is not a Model"
	end
	if not template.Archivable then
		return false, "template is not Archivable"
	end
	local primary = template:FindFirstChild(requiredPrimaryName, true)
	if primary == nil or not primary:IsA("BasePart") then
		return false, "missing required BasePart " .. requiredPrimaryName
	end
	local partCount = 0
	for _, desc in ipairs(template:GetDescendants()) do
		if desc:IsA("BasePart") then
			partCount += 1
		end
	end
	if partCount == 0 or partCount > MAX_STATION_PARTS then
		return false, string.format("part count %d outside 1..%d", partCount, MAX_STATION_PARTS)
	end
	return true, nil
end

local function findStationTemplate(stationNames: { string }, requiredPrimaryName: string): Model?
	local templatesRoot = ReplicatedStorage:FindFirstChild(Constants.ASSET_TEMPLATES_FOLDER_NAME)
	if templatesRoot == nil then
		return nil
	end
	for _, folderName in ipairs({ "Stations", "Pilot" }) do
		local sub = templatesRoot:FindFirstChild(folderName)
		if sub ~= nil then
			for _, candidateName in ipairs(stationNames) do
				local tmpl = sub:FindFirstChild(candidateName)
				if tmpl ~= nil then
					local ok, reason = isValidStationTemplate(tmpl, requiredPrimaryName)
					if ok then
						local cloned = (tmpl :: Model):Clone()
						if cloned ~= nil then
							local okCloned, clonedReason = isValidStationTemplate(cloned, requiredPrimaryName)
							if okCloned then
								return cloned
							end
							cloned:Destroy()
							warn(string.format("[StationVisualController] Rejected cloned station '%s': %s", candidateName, tostring(clonedReason)))
						end
					else
						warn(string.format("[StationVisualController] Rejected station template '%s': %s", candidateName, tostring(reason)))
					end
				end
			end
		end
	end
	return nil
end

function StationVisualController.ResolveIncubatorState(
	slotId: string,
	plotDto: Types.PublicPlotDTO?,
	ownerDto: Types.OwnerStateDTO?,
	serverNow: number
): IncubatorVisualState
	local unlocked = slotId == "Incubator_1"
	if not unlocked then
		if plotDto ~= nil and plotDto.UnlockedUpgrades["Incubator_2"] == true then
			unlocked = true
		elseif ownerDto ~= nil and ownerDto.Upgrades["Incubator_2"] == true then
			unlocked = true
		end
	end
	if not unlocked then
		return "Locked"
	end

	local incVis = if plotDto ~= nil then plotDto.IncubatorVisuals[slotId] else nil
	if incVis ~= nil then
		if serverNow >= incVis.MaturesAt then
			return "Ready"
		end
		return "Incubating"
	end

	return "Idle"
end

local function applyIncubatorVisualState(entry: IncubatorEntry, state: IncubatorVisualState): ()
	entry.CurrentState = state
	local isLocked = state == "Locked"
	entry.StatusRing.Color = STATE_COLORS[state]
	entry.StatusRing.Material = if isLocked then Enum.Material.SmoothPlastic else Enum.Material.Neon
	entry.Canopy.Transparency = if isLocked then 0.84 else 0.65
	for _, part in ipairs(entry.BaseParts) do
		if part ~= entry.StatusRing and part ~= entry.Canopy then
			part.Transparency = if isLocked then 0.45 else 0
		end
	end
end

local function mountPlot1Incubators(): ()
	local root = workspace:FindFirstChild(Constants.GREYBOX_ROOT_NAME)
	local plots = if root ~= nil then root:FindFirstChild("Plots") else nil
	local plot1 = if plots ~= nil then plots:FindFirstChild("Plot_1") else nil
	local incubators = if plot1 ~= nil then plot1:FindFirstChild("Incubators") else nil
	if incubators == nil then
		return
	end

	local folder = getStationFolder()
	for _, slotId in ipairs({ "Incubator_1", "Incubator_2" }) do
		local pad = incubators:FindFirstChild(slotId)
		if pad ~= nil and pad:IsA("BasePart") then
			local existing = incubatorEntries[slotId]
			if existing == nil or existing.Model.Parent == nil then
				local cloned = findStationTemplate({ "Incubator", "Incubator_Prototype" }, "Base")
				if cloned ~= nil then
					cloned.Name = "Plot1_" .. slotId .. "_Model"
					local statusRing = cloned:FindFirstChild("StatusRing", true)
					local canopy = cloned:FindFirstChild("Canopy", true)
					local basePart = cloned:FindFirstChild("Base", true)
					if statusRing ~= nil and statusRing:IsA("BasePart")
						and canopy ~= nil and canopy:IsA("BasePart")
						and basePart ~= nil and basePart:IsA("BasePart")
					then
						cloned.PrimaryPart = basePart
						local baseParts: { BasePart } = {}
						for _, desc in ipairs(cloned:GetDescendants()) do
							if desc:IsA("BasePart") then
								desc.Anchored = true
								desc.CanCollide = false
								desc.CanQuery = false
								desc.CanTouch = false
								table.insert(baseParts, desc)
							end
						end
						local padTopY = pad.Position.Y + pad.Size.X * 0.5
						cloned:PivotTo(CFrame.new(pad.Position.X, padTopY, pad.Position.Z) * CFrame.Angles(0, -math.pi * 0.5, 0))
						cloned.Parent = folder
						pad.LocalTransparencyModifier = 1
						pad:SetAttribute("ModeledIncubatorPodYOffset", INCUBATOR_POD_Y_OFFSET)

						local labelGui = pad:FindFirstChild("SlotLabel")
						if labelGui ~= nil and labelGui:IsA("BillboardGui") then
							labelGui.StudsOffsetWorldSpace = Vector3.new(0, 6.1, 0)
						end

						local entry: IncubatorEntry = {
							SlotId = slotId,
							Pad = pad,
							Model = cloned,
							StatusRing = statusRing,
							Canopy = canopy,
							BaseParts = baseParts,
							CurrentState = "Idle",
						}
						applyIncubatorVisualState(entry, if slotId == "Incubator_1" then "Idle" else "Locked")
						incubatorEntries[slotId] = entry
					else
						cloned:Destroy()
					end
				end
			end
		end
	end
end

local function mountToolWorkbench(): ()
	if workbenchModel ~= nil and workbenchModel.Parent ~= nil then
		return
	end
	local root = workspace:FindFirstChild(Constants.GREYBOX_ROOT_NAME)
	local hub = if root ~= nil then root:FindFirstChild("CentralHub") else nil
	local bench = if hub ~= nil then hub:FindFirstChild("ToolWorkbench") else nil
	local counter = if bench ~= nil then bench:FindFirstChild("BenchCounter") else nil
	if counter == nil or not counter:IsA("BasePart") then
		return
	end

	local cloned = findStationTemplate({ "ToolWorkbench", "ToolWorkbench_Prototype" }, "TimberFrame")
	if cloned == nil then
		return
	end

	local timber = cloned:FindFirstChild("TimberFrame", true)
	if timber == nil or not timber:IsA("BasePart") then
		cloned:Destroy()
		return
	end
	cloned.PrimaryPart = timber
	for _, desc in ipairs(cloned:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
			desc.CanQuery = false
			desc.CanTouch = false
		end
	end

	-- Greybox BenchCounter bottom sits at Y=0.5 and BenchTop top sits at Y=4.1 (3.60 studs tall).
	local bottomY = counter.Position.Y - counter.Size.Y * 0.5
	cloned.Name = "CentralHub_ToolWorkbench_Model"
	cloned:PivotTo(CFrame.new(counter.Position.X, bottomY, counter.Position.Z) * CFrame.Angles(0, -math.pi * 0.5, 0))
	cloned.Parent = getStationFolder()

	counter.LocalTransparencyModifier = 1
	local benchTop = counter:FindFirstChild("BenchTop")
	if benchTop ~= nil and benchTop:IsA("BasePart") then
		benchTop.LocalTransparencyModifier = 1
	end
	workbenchModel = cloned
end

function StationVisualController.ReconcilePlot1Incubators(
	plotsById: { [number]: Types.PublicPlotDTO }?,
	ownerDto: Types.OwnerStateDTO?,
	nowOverride: number?
): ()
	local plot1Dto = if plotsById ~= nil then plotsById[1] else nil
	local serverNow = nowOverride or workspace:GetServerTimeNow()
	for _, slotId in ipairs({ "Incubator_1", "Incubator_2" }) do
		local entry = incubatorEntries[slotId]
		if entry ~= nil and entry.Model.Parent ~= nil then
			local nextState = StationVisualController.ResolveIncubatorState(slotId, plot1Dto, ownerDto, serverNow)
			if entry.CurrentState ~= nextState then
				applyIncubatorVisualState(entry, nextState)
			end
		end
	end
end

function StationVisualController.GetStatusSummary(): { [string]: any }
	local incStates: { [string]: string } = {}
	for slotId, entry in pairs(incubatorEntries) do
		incStates[slotId] = entry.CurrentState
	end
	return {
		Incubators = incStates,
		WorkbenchMounted = workbenchModel ~= nil and workbenchModel.Parent ~= nil,
	}
end

function StationVisualController.Init(self: typeof(StationVisualController)): ()
	-- Stations mount in Start() after Greybox & PlotVisualController initialize.
end

function StationVisualController.Start(self: typeof(StationVisualController)): ()
	mountPlot1Incubators()
	mountToolWorkbench()

	lastOwnerState = UIController.GetLatestOwnerState()
	StationVisualController.ReconcilePlot1Incubators(lastPlots, lastOwnerState)

	if not listenersBound then
		listenersBound = true
		UIController.OnOwnerStateChanged(function(dto: Types.OwnerStateDTO)
			lastOwnerState = dto
			StationVisualController.ReconcilePlot1Incubators(lastPlots, lastOwnerState)
		end)
		PlotVisualController.OnPublicPlotsChanged(function(plots: { [number]: Types.PublicPlotDTO })
			lastPlots = plots
			StationVisualController.ReconcilePlot1Incubators(lastPlots, lastOwnerState)
		end)
	end

	if heartbeatConn == nil then
		local accum = 0
		heartbeatConn = RunService.Heartbeat:Connect(function(dt: number)
			accum += dt
			if accum >= 0.5 then
				accum = 0
				StationVisualController.ReconcilePlot1Incubators(lastPlots, lastOwnerState)
			end
			local _ = SoundController.IsReducedMotion()
		end)
	end
end

function StationVisualController.RunSelfTest(): number
	local passed = 0

	-- Suite 1: Incubator state resolution covers Locked, Idle, Incubating, and Ready cleanly
	assert(StationVisualController.ResolveIncubatorState("Incubator_1", nil, nil, 100) == "Idle", "Incubator_1 starts Idle")
	assert(StationVisualController.ResolveIncubatorState("Incubator_2", nil, nil, 100) == "Locked", "Incubator_2 starts Locked")
	local mockPlot: Types.PublicPlotDTO = {
		PlotId = 1,
		OwnerUserId = 1,
		OwnerDisplayName = "Tester",
		PlotRevision = 2,
		UnlockedUpgrades = { Incubator_2 = true },
		ActivePenVisuals = {},
		IncubatorVisuals = {
			Incubator_1 = { MaturesAt = 150 },
		},
	}
	assert(StationVisualController.ResolveIncubatorState("Incubator_2", mockPlot, nil, 100) == "Idle", "Incubator_2 Idle when unlocked")
	assert(StationVisualController.ResolveIncubatorState("Incubator_1", mockPlot, nil, 120) == "Incubating", "Incubator_1 Incubating before MaturesAt")
	assert(StationVisualController.ResolveIncubatorState("Incubator_1", mockPlot, nil, 150) == "Ready", "Incubator_1 Ready at MaturesAt")
	passed += 1

	-- Suite 2: Invalid/non-archivable station template validation rejects cleanly without throwing
	local badModel = Instance.new("Model")
	badModel.Name = "_BadStationTest"
	local okBad1, _ = isValidStationTemplate(badModel, "Base")
	assert(okBad1 == false, "Station missing primary BasePart must fail validation")
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Parent = badModel
	badModel.Archivable = false
	local okBad2, _ = isValidStationTemplate(badModel, "Base")
	assert(okBad2 == false, "Non-archivable station must fail validation")
	badModel:Destroy()
	passed += 1

	return passed
end

return StationVisualController
