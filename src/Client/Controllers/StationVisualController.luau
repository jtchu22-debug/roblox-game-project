--!strict
--[[
	Controller: StationVisualController
	Purpose: Replaces greybox station placeholders across all 6 ranches (Incubators, SellStand,
	         HabitatPen) and CentralHub ToolWorkbench with S6-ART-02 modeled templates while
	         preserving authoritative interaction anchors, ProximityPrompts, ToolVisualController
	         displays, and per-plot Locked/Idle/Incubating/Ready states from PublicPlotDTO.
	Connections: Requires SoundController, PlotVisualController, Constants, Types.
	How to Test in Studio: Press Play (F5) for automated self-tests, inspect all 6 ranches &
	                       CentralHub ToolWorkbench, and verify two-player Incubator state isolation.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ControllersFolder = script.Parent
local PlotVisualController = require(ControllersFolder:WaitForChild("PlotVisualController"))
local SoundController = require(ControllersFolder:WaitForChild("SoundController"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Types = require(Shared:WaitForChild("Types"))

export type IncubatorVisualState = "Locked" | "Idle" | "Incubating" | "Ready"

type IncubatorEntry = {
	PlotId: number,
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
local PLOT_COUNT = 6

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
local incubatorEntriesByPlot: { [number]: { [string]: IncubatorEntry } } = {}
local sellStandModelsByPlot: { [number]: Model } = {}
local habitatPenModelsByPlot: { [number]: Model } = {}
local workbenchModel: Model? = nil
local listenersBound = false
local heartbeatConn: RBXScriptConnection? = nil
local lastPlots: { [number]: Types.PublicPlotDTO } = {}

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
	serverNow: number
): IncubatorVisualState
	-- Authoritative per-plot state MUST come strictly from that plot's PublicPlotDTO,
	-- never from the viewing player's local OwnerStateDTO.
	local isOccupied = plotDto ~= nil and plotDto.OwnerUserId > 0
	if slotId ~= "Incubator_1" then
		local unlocked = isOccupied and plotDto ~= nil and plotDto.UnlockedUpgrades["Incubator_2"] == true
		if not unlocked then
			return "Locked"
		end
	end

	if isOccupied and plotDto ~= nil then
		local incVis = plotDto.IncubatorVisuals[slotId]
		if incVis ~= nil then
			if serverNow >= incVis.MaturesAt then
				return "Ready"
			end
			return "Incubating"
		end
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

local function prepareStaticStationParts(model: Model): { BasePart }
	local parts: { BasePart } = {}
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
			desc.CanQuery = false
			desc.CanTouch = false
			table.insert(parts, desc)
		end
	end
	return parts
end

local function resolvePlotRotation(plotModel: Model): CFrame
	local pen = plotModel:FindFirstChild("HabitatPen")
	local penFloor = if pen ~= nil then pen:FindFirstChild("PenFloor") else nil
	if penFloor ~= nil and penFloor:IsA("BasePart") then
		return penFloor.CFrame - penFloor.CFrame.Position
	end
	local spawnPart = plotModel:FindFirstChild("SpawnPoint")
	if spawnPart ~= nil and spawnPart:IsA("BasePart") then
		return spawnPart.CFrame - spawnPart.CFrame.Position
	end
	return CFrame.new()
end

local function mountPlotStations(plotId: number, plotModel: Model): ()
	local folder = getStationFolder()
	local plotRot = resolvePlotRotation(plotModel)

	-- 1. Incubators (Incubator_1 & Incubator_2)
	local incubators = plotModel:FindFirstChild("Incubators")
	if incubators ~= nil then
		local plotEntries = incubatorEntriesByPlot[plotId]
		if plotEntries == nil then
			plotEntries = {}
			incubatorEntriesByPlot[plotId] = plotEntries
		end
		for _, slotId in ipairs({ "Incubator_1", "Incubator_2" }) do
			local pad = incubators:FindFirstChild(slotId)
			if pad ~= nil and pad:IsA("BasePart") then
				local existing = plotEntries[slotId]
				if existing == nil or existing.Model.Parent == nil then
					local cloned = findStationTemplate({ "Incubator", "Incubator_Prototype" }, "Base")
					if cloned ~= nil then
						cloned.Name = string.format("Plot%d_%s_Model", plotId, slotId)
						local statusRing = cloned:FindFirstChild("StatusRing", true)
						local canopy = cloned:FindFirstChild("Canopy", true)
						local basePart = cloned:FindFirstChild("Base", true)
						if statusRing ~= nil and statusRing:IsA("BasePart")
							and canopy ~= nil and canopy:IsA("BasePart")
							and basePart ~= nil and basePart:IsA("BasePart")
						then
							cloned.PrimaryPart = basePart
							local baseParts = prepareStaticStationParts(cloned)
							local padTopY = pad.Position.Y + pad.Size.X * 0.5
							cloned:PivotTo(CFrame.new(pad.Position.X, padTopY, pad.Position.Z) * plotRot * CFrame.Angles(0, -math.pi * 0.5, 0))
							cloned.Parent = folder
							pad.LocalTransparencyModifier = 1
							pad:SetAttribute("ModeledIncubatorPodYOffset", INCUBATOR_POD_Y_OFFSET)

							local labelGui = pad:FindFirstChild("SlotLabel")
							if labelGui ~= nil and labelGui:IsA("BillboardGui") then
								labelGui.StudsOffsetWorldSpace = Vector3.new(0, 6.1, 0)
							end

							local entry: IncubatorEntry = {
								PlotId = plotId,
								SlotId = slotId,
								Pad = pad,
								Model = cloned,
								StatusRing = statusRing,
								Canopy = canopy,
								BaseParts = baseParts,
								CurrentState = "Idle",
							}
							applyIncubatorVisualState(entry, if slotId == "Incubator_1" then "Idle" else "Locked")
							plotEntries[slotId] = entry
						else
							cloned:Destroy()
						end
					end
				end
			end
		end
	end

	-- 2. SellStand
	local sellStand = plotModel:FindFirstChild("SellStand")
	if sellStand ~= nil and sellStand:IsA("BasePart") then
		local existingSell = sellStandModelsByPlot[plotId]
		if existingSell == nil or existingSell.Parent == nil then
			local cloned = findStationTemplate({ "SellStand", "SellStand_Prototype" }, "TimberBase")
			if cloned ~= nil then
				local timberBase = cloned:FindFirstChild("TimberBase", true)
				if timberBase ~= nil and timberBase:IsA("BasePart") then
					cloned.PrimaryPart = timberBase
					prepareStaticStationParts(cloned)
					local bottomY = sellStand.Position.Y - sellStand.Size.Y * 0.5
					cloned.Name = string.format("Plot%d_SellStand_Model", plotId)
					cloned:PivotTo(CFrame.new(sellStand.Position.X, bottomY, sellStand.Position.Z) * plotRot)
					cloned.Parent = folder
					sellStand.LocalTransparencyModifier = 1
					local sellTop = sellStand:FindFirstChild("SellTop")
					if sellTop ~= nil and sellTop:IsA("BasePart") then
						sellTop.LocalTransparencyModifier = 1
					end
					local sellLabel = sellStand:FindFirstChild("SellLabel")
					if sellLabel ~= nil and sellLabel:IsA("BillboardGui") then
						sellLabel.StudsOffsetWorldSpace = Vector3.new(0, 4.6, 0)
					end
					sellStandModelsByPlot[plotId] = cloned
				else
					cloned:Destroy()
				end
			end
		end
	end

	-- 3. HabitatPen perimeter & feeding trough
	local penModel = plotModel:FindFirstChild("HabitatPen")
	local penFloor = if penModel ~= nil then penModel:FindFirstChild("PenFloor") else nil
	if penModel ~= nil and penFloor ~= nil and penFloor:IsA("BasePart") then
		local existingPen = habitatPenModelsByPlot[plotId]
		if existingPen == nil or existingPen.Parent == nil then
			local cloned = findStationTemplate({ "HabitatPen", "HabitatPen_Prototype" }, "TimberPosts")
			if cloned ~= nil then
				local posts = cloned:FindFirstChild("TimberPosts", true)
				if posts ~= nil and posts:IsA("BasePart") then
					cloned.PrimaryPart = posts
					prepareStaticStationParts(cloned)
					local floorTopY = penFloor.Position.Y + penFloor.Size.Y * 0.5
					cloned.Name = string.format("Plot%d_HabitatPen_Model", plotId)
					cloned:PivotTo(CFrame.new(penFloor.Position.X, floorTopY, penFloor.Position.Z) * plotRot)
					cloned.Parent = folder
					for _, child in ipairs(penModel:GetChildren()) do
						if child:IsA("BasePart") and string.sub(child.Name, 1, 6) == "Fence_" then
							child.LocalTransparencyModifier = 1
						end
					end
					habitatPenModelsByPlot[plotId] = cloned
				else
					cloned:Destroy()
				end
			end
		end
	end
end

local function mountAllRanches(): ()
	local root = workspace:FindFirstChild(Constants.GREYBOX_ROOT_NAME)
	local plots = if root ~= nil then root:FindFirstChild("Plots") else nil
	if plots == nil then
		return
	end
	for plotId = 1, PLOT_COUNT do
		local plotModel = plots:FindFirstChild("Plot_" .. tostring(plotId))
		if plotModel ~= nil and plotModel:IsA("Model") then
			mountPlotStations(plotId, plotModel)
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
	prepareStaticStationParts(cloned)

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

function StationVisualController.ReconcileAllPlots(
	plotsById: { [number]: Types.PublicPlotDTO }?,
	nowOverride: number?
): ()
	local serverNow = nowOverride or workspace:GetServerTimeNow()
	for plotId = 1, PLOT_COUNT do
		local plotDto = if plotsById ~= nil then plotsById[plotId] else nil
		local plotEntries = incubatorEntriesByPlot[plotId]
		if plotEntries ~= nil then
			for _, slotId in ipairs({ "Incubator_1", "Incubator_2" }) do
				local entry = plotEntries[slotId]
				if entry ~= nil and entry.Model.Parent ~= nil then
					local nextState = StationVisualController.ResolveIncubatorState(slotId, plotDto, serverNow)
					if entry.CurrentState ~= nextState then
						applyIncubatorVisualState(entry, nextState)
					end
				end
			end
		end
	end
end

function StationVisualController.GetStatusSummary(): { [string]: any }
	local incCount = 0
	local plotStates: { [number]: { [string]: string } } = {}
	for plotId, entries in pairs(incubatorEntriesByPlot) do
		plotStates[plotId] = {}
		for slotId, entry in pairs(entries) do
			if entry.Model.Parent ~= nil then
				incCount += 1
				plotStates[plotId][slotId] = entry.CurrentState
			end
		end
	end
	local sellCount = 0
	for _, m in pairs(sellStandModelsByPlot) do
		if m.Parent ~= nil then
			sellCount += 1
		end
	end
	local penCount = 0
	for _, m in pairs(habitatPenModelsByPlot) do
		if m.Parent ~= nil then
			penCount += 1
		end
	end
	return {
		IncubatorCount = incCount,
		SellStandCount = sellCount,
		HabitatPenCount = penCount,
		WorkbenchMounted = workbenchModel ~= nil and workbenchModel.Parent ~= nil,
		PlotStates = plotStates,
	}
end

function StationVisualController.Init(self: typeof(StationVisualController)): ()
	-- Stations mount in Start() after Greybox & PlotVisualController initialize.
end

function StationVisualController.Start(self: typeof(StationVisualController)): ()
	mountAllRanches()
	mountToolWorkbench()

	StationVisualController.ReconcileAllPlots(lastPlots)

	if not listenersBound then
		listenersBound = true
		PlotVisualController.OnPublicPlotsChanged(function(plots: { [number]: Types.PublicPlotDTO })
			lastPlots = plots
			StationVisualController.ReconcileAllPlots(lastPlots)
		end)
	end

	if heartbeatConn == nil then
		local accum = 0
		heartbeatConn = RunService.Heartbeat:Connect(function(dt: number)
			accum += dt
			if accum >= 0.5 then
				accum = 0
				StationVisualController.ReconcileAllPlots(lastPlots)
			end
			local _ = SoundController.IsReducedMotion()
		end)
	end
end

function StationVisualController.RunSelfTest(): number
	local passed = 0

	-- Suite 1: Basic Incubator state resolution (Locked, Idle, Incubating, Ready)
	assert(StationVisualController.ResolveIncubatorState("Incubator_1", nil, 100) == "Idle", "Incubator_1 starts Idle")
	assert(StationVisualController.ResolveIncubatorState("Incubator_2", nil, 100) == "Locked", "Incubator_2 starts Locked")
	local singlePlot: Types.PublicPlotDTO = {
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
	assert(StationVisualController.ResolveIncubatorState("Incubator_2", singlePlot, 100) == "Idle", "Incubator_2 Idle when plot unlocked")
	assert(StationVisualController.ResolveIncubatorState("Incubator_1", singlePlot, 120) == "Incubating", "Incubator_1 Incubating before MaturesAt")
	assert(StationVisualController.ResolveIncubatorState("Incubator_1", singlePlot, 150) == "Ready", "Incubator_1 Ready at MaturesAt")
	passed += 1

	-- Suite 2 (Review #040): Two-player ownership isolation & plot reassignment
	local plot1OwnerA: Types.PublicPlotDTO = {
		PlotId = 1,
		OwnerUserId = 101,
		OwnerDisplayName = "PlayerA",
		PlotRevision = 1,
		UnlockedUpgrades = {},
		ActivePenVisuals = {},
		IncubatorVisuals = {},
	}
	local plot2OwnerB: Types.PublicPlotDTO = {
		PlotId = 2,
		OwnerUserId = 202,
		OwnerDisplayName = "PlayerB",
		PlotRevision = 4,
		UnlockedUpgrades = { Incubator_2 = true },
		ActivePenVisuals = {},
		IncubatorVisuals = {
			Incubator_1 = { MaturesAt = 200 },
		},
	}
	-- Even when viewing Plot 1 as Player B (who has Incubator_2 unlocked), Plot 1's Incubator_2 stays Locked.
	assert(StationVisualController.ResolveIncubatorState("Incubator_2", plot1OwnerA, 150) == "Locked", "Plot 1 Incubator_2 must stay Locked for Player B visitor")
	assert(StationVisualController.ResolveIncubatorState("Incubator_2", plot2OwnerB, 150) == "Idle", "Plot 2 Incubator_2 Idle for Player B")
	assert(StationVisualController.ResolveIncubatorState("Incubator_1", plot2OwnerB, 150) == "Incubating", "Plot 2 Incubator_1 Incubating")
	assert(StationVisualController.ResolveIncubatorState("Incubator_1", plot2OwnerB, 200) == "Ready", "Plot 2 Incubator_1 Ready")
	-- Plot release / reassignment resets Incubator_2 to Locked and Incubator_1 to Idle
	local plot2Released: Types.PublicPlotDTO = {
		PlotId = 2,
		OwnerUserId = 0,
		OwnerDisplayName = "",
		PlotRevision = 5,
		UnlockedUpgrades = {},
		ActivePenVisuals = {},
		IncubatorVisuals = {},
	}
	assert(StationVisualController.ResolveIncubatorState("Incubator_2", plot2Released, 250) == "Locked", "Released plot resets Incubator_2 to Locked")
	assert(StationVisualController.ResolveIncubatorState("Incubator_1", plot2Released, 250) == "Idle", "Released plot resets Incubator_1 to Idle")
	passed += 1

	-- Suite 3: Invalid/non-archivable station template validation rejects cleanly without throwing
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
