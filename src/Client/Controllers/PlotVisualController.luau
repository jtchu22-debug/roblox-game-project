--!strict
--[[
	Controller: PlotVisualController
	Purpose: Receives PublicPlotDTO snapshots from SyncPublicPlots, reconciles client-side blocky
	         Cosmic Critter & Star-Pod visuals on each plot, and runs a single centralized Heartbeat
	         animation loop that honors the SoundController Reduced Motion toggle.
	Connections: Requires SoundController, Constants, Types, and CritterConfig; exposes plot/station lookups to UIController.
	How to Test in Studio: Press Play (F5), incubate/place critters, and verify animated blocky models + Reduced Motion snap.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ControllersFolder = script.Parent
local SoundController = require(ControllersFolder:WaitForChild("SoundController"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Types = require(Shared:WaitForChild("Types"))
local CritterConfig = require(Shared:WaitForChild("Config"):WaitForChild("CritterConfig"))

type PartOffset = {
	Part: BasePart,
	Offset: CFrame,
}

type VisualEntry = {
	Key: string,
	Kind: "Critter" | "Pod",
	Signature: string,
	Model: Model,
	BaseCFrame: CFrame,
	Parts: { PartOffset },
	HopSpeed: number,
	HopHeight: number,
	Phase: number,
	MaturesAt: number?,
	CoreParts: { BasePart }?,
	WasMature: boolean,
}

local VISUALS_FOLDER_NAME = "StarfallClientVisuals"

local COLOR_EYE = Color3.fromRGB(22, 20, 34)
local COLOR_RADIANT_GOLD = Color3.fromRGB(255, 205, 45)
local COLOR_POD_INCUBATING = Color3.fromRGB(65, 210, 255)
local COLOR_CREAM = Color3.fromRGB(245, 240, 232)

local PlotVisualController = {
	Name = "PlotVisualController",
}

local latestPlots: { [number]: Types.PublicPlotDTO } = {}
local latestPlotsRevision = -1
local syncConn: RBXScriptConnection? = nil
local heartbeatConn: RBXScriptConnection? = nil
local visualsFolder: Folder? = nil
local activeVisuals: { [string]: VisualEntry } = {}
local publicPlotsListeners: { (plots: { [number]: Types.PublicPlotDTO }) -> () } = {}
local wasReducedMotion = false

local function getGreyboxPlotModel(plotId: number): Model?
	local root = workspace:FindFirstChild(Constants.GREYBOX_ROOT_NAME)
	if root == nil then
		return nil
	end
	local plotsFolder = root:FindFirstChild("Plots")
	if plotsFolder == nil then
		return nil
	end
	local plotModel = plotsFolder:FindFirstChild("Plot_" .. tostring(plotId))
	if plotModel ~= nil and plotModel:IsA("Model") then
		return plotModel
	end
	return nil
end

local function resolveStationPartOnPlot(plotModel: Model, stationKind: string, targetId: string): BasePart?
	if stationKind == "Incubator" then
		local folder = plotModel:FindFirstChild("Incubators")
		local pad = if folder ~= nil then folder:FindFirstChild(targetId) else nil
		return if pad ~= nil and pad:IsA("BasePart") then pad else nil
	elseif stationKind == "Pen" then
		local pen = plotModel:FindFirstChild("HabitatPen")
		local penSlots = if pen ~= nil then pen:FindFirstChild("PenSlots") else nil
		local pad = if penSlots ~= nil then penSlots:FindFirstChild(targetId) else nil
		return if pad ~= nil and pad:IsA("BasePart") then pad else nil
	elseif stationKind == "SellStand" then
		local stand = plotModel:FindFirstChild("SellStand")
		return if stand ~= nil and stand:IsA("BasePart") then stand else nil
	elseif stationKind == "UpgradePad" then
		local board = plotModel:FindFirstChild("UpgradeBoard")
		local pad = if board ~= nil then board:FindFirstChild("UpgradePad_" .. targetId) else nil
		return if pad ~= nil and pad:IsA("BasePart") then pad else nil
	end
	return nil
end

local function createVisualPart(
	parent: Model,
	partsList: { PartOffset },
	baseCFrame: CFrame,
	offset: CFrame,
	props: {
		Name: string,
		Size: Vector3,
		Color: Color3,
		Material: Enum.Material?,
		Shape: Enum.PartType?,
		Transparency: number?,
		IsWedge: boolean?,
		CastShadow: boolean?,
	}
): BasePart
	local part: BasePart
	if props.IsWedge then
		part = Instance.new("WedgePart")
	else
		local regular = Instance.new("Part")
		if props.Shape ~= nil then
			regular.Shape = props.Shape
		end
		part = regular
	end

	part.Name = props.Name
	part.Size = props.Size
	part.Color = props.Color
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.Transparency = props.Transparency or 0
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = if props.CastShadow ~= nil then props.CastShadow else false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = baseCFrame * offset
	part.Parent = parent

	table.insert(partsList, {
		Part = part,
		Offset = offset,
	})
	return part
end

local function attachRadiantHalo(
	model: Model,
	partsList: { PartOffset },
	baseCFrame: CFrame,
	yOffset: number,
	diameter: number
): ()
	createVisualPart(model, partsList, baseCFrame, CFrame.new(0, yOffset, 0) * CFrame.Angles(0, 0, math.rad(90)), {
		Name = "RadiantHalo",
		Size = Vector3.new(0.24, diameter, diameter),
		Color = COLOR_RADIANT_GOLD,
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Cylinder,
		Transparency = 0.15,
	})
end

local function buildCritterVisual(
	key: string,
	speciesId: Types.SpeciesId,
	variant: Types.VariantId,
	feedLevel: number,
	pad: BasePart,
	horizontalRotation: CFrame,
	phaseSeed: number
): VisualEntry?
	local folder = visualsFolder
	local def = CritterConfig.ById[speciesId]
	if folder == nil or def == nil then
		return nil
	end

	local fed = feedLevel >= 1
	local scaleMult = if fed then 1.15 else 1.0
	local accentColor = if fed then COLOR_RADIANT_GOLD else def.AccentColor
	local bodyScale = def.DisplayScale * scaleMult
	local padTopY = pad.Position.Y + pad.Size.X * 0.5
	local basePos = Vector3.new(pad.Position.X, padTopY + bodyScale.Y * 0.5, pad.Position.Z)
	local baseCFrame = CFrame.new(basePos) * horizontalRotation

	local model = Instance.new("Model")
	model.Name = string.format("%s_%s", key, speciesId)
	local partsList: { PartOffset } = {}

	local haloHeight = bodyScale.Y * 0.5 + 1.15 * scaleMult
	local haloDiameter = math.max(bodyScale.X, bodyScale.Z) * 0.85

	if speciesId == "StarSlime" then
		-- 6 parts (+1 Radiant halo = 7 <= 8 budget)
		local body = createVisualPart(model, partsList, baseCFrame, CFrame.new(), {
			Name = "Body",
			Size = bodyScale,
			Color = def.BodyColor,
			CastShadow = true,
		})
		model.PrimaryPart = body

		for _, xSign in ipairs({ -1, 1 }) do
			createVisualPart(model, partsList, baseCFrame, CFrame.new(xSign * 0.55 * scaleMult, 0.2 * scaleMult, -bodyScale.Z * 0.48), {
				Name = if xSign < 0 then "LeftEye" else "RightEye",
				Size = Vector3.new(0.36, 0.44, 0.22) * scaleMult,
				Color = COLOR_EYE,
				Shape = Enum.PartType.Ball,
			})
			createVisualPart(model, partsList, baseCFrame, CFrame.new(xSign * (bodyScale.X * 0.48), -0.35 * scaleMult, 0), {
				Name = if xSign < 0 then "LeftNub" else "RightNub",
				Size = Vector3.new(0.6, 0.7, 0.8) * scaleMult,
				Color = def.BodyColor,
			})
		end

		createVisualPart(model, partsList, baseCFrame, CFrame.new(0, bodyScale.Y * 0.5 + 0.22 * scaleMult, 0) * CFrame.Angles(0, math.rad(45), 0), {
			Name = "StarCrest",
			Size = Vector3.new(0.85, 0.45, 0.85) * scaleMult,
			Color = accentColor,
			Material = Enum.Material.Neon,
		})
		haloHeight = bodyScale.Y * 0.5 + 1.0 * scaleMult
	elseif speciesId == "NebulaFox" then
		-- 7 parts (+1 Radiant halo = 8 <= 8 budget)
		local torsoScale = Vector3.new(bodyScale.X * 0.8, bodyScale.Y * 0.7, bodyScale.Z * 0.95)
		local body = createVisualPart(model, partsList, baseCFrame, CFrame.new(), {
			Name = "Body",
			Size = torsoScale,
			Color = def.BodyColor,
			CastShadow = true,
		})
		model.PrimaryPart = body

		createVisualPart(model, partsList, baseCFrame, CFrame.new(0, 0.05 * scaleMult, -torsoScale.Z * 0.56), {
			Name = "Snout",
			Size = Vector3.new(1.0, 0.7, 0.65) * scaleMult,
			Color = COLOR_CREAM,
		})
		for _, xSign in ipairs({ -1, 1 }) do
			createVisualPart(model, partsList, baseCFrame, CFrame.new(xSign * 0.55 * scaleMult, 0.35 * scaleMult, -torsoScale.Z * 0.48), {
				Name = if xSign < 0 then "LeftEye" else "RightEye",
				Size = Vector3.new(0.34, 0.38, 0.22) * scaleMult,
				Color = COLOR_EYE,
			})
			createVisualPart(model, partsList, baseCFrame, CFrame.new(xSign * 0.65 * scaleMult, torsoScale.Y * 0.5 + 0.48 * scaleMult, -0.5 * scaleMult), {
				Name = if xSign < 0 then "LeftEar" else "RightEar",
				Size = Vector3.new(0.55, 1.0, 0.65) * scaleMult,
				Color = accentColor,
				Material = Enum.Material.Neon,
				IsWedge = true,
			})
		end
		createVisualPart(model, partsList, baseCFrame, CFrame.new(0, 0.55 * scaleMult, torsoScale.Z * 0.58) * CFrame.Angles(math.rad(-35), 0, 0), {
			Name = "Tail",
			Size = Vector3.new(0.85, 0.85, 1.7) * scaleMult,
			Color = accentColor,
			Material = Enum.Material.Neon,
		})
		haloHeight = torsoScale.Y * 0.5 + 1.55 * scaleMult
	else
		-- SolarGolem: 7 parts (+1 Radiant halo = 8 <= 8 budget)
		local body = createVisualPart(model, partsList, baseCFrame, CFrame.new(), {
			Name = "Body",
			Size = bodyScale,
			Color = def.BodyColor,
			CastShadow = true,
		})
		model.PrimaryPart = body

		createVisualPart(model, partsList, baseCFrame, CFrame.new(0, -0.1 * scaleMult, -bodyScale.Z * 0.46), {
			Name = "SolarCore",
			Size = Vector3.new(1.3, 1.3, 0.35) * scaleMult,
			Color = accentColor,
			Material = Enum.Material.Neon,
		})
		for _, xSign in ipairs({ -1, 1 }) do
			createVisualPart(model, partsList, baseCFrame, CFrame.new(xSign * 0.72 * scaleMult, 0.95 * scaleMult, -bodyScale.Z * 0.48), {
				Name = if xSign < 0 then "LeftEye" else "RightEye",
				Size = Vector3.new(0.45, 0.35, 0.22) * scaleMult,
				Color = COLOR_EYE,
			})
			createVisualPart(model, partsList, baseCFrame, CFrame.new(xSign * (bodyScale.X * 0.6), -0.15 * scaleMult, 0), {
				Name = if xSign < 0 then "LeftArm" else "RightArm",
				Size = Vector3.new(0.95, 2.4, 1.0) * scaleMult,
				Color = def.BodyColor,
			})
		end
		createVisualPart(model, partsList, baseCFrame, CFrame.new(0, bodyScale.Y * 0.5 + 0.3 * scaleMult, 0), {
			Name = "CrownCap",
			Size = Vector3.new(2.1, 0.55, 2.0) * scaleMult,
			Color = accentColor,
			Material = Enum.Material.Neon,
		})
		haloHeight = bodyScale.Y * 0.5 + 1.15 * scaleMult
	end

	if variant == "Radiant" then
		attachRadiantHalo(model, partsList, baseCFrame, haloHeight, haloDiameter)
	end

	model.Parent = folder
	local baseHop = if speciesId == "SolarGolem" then 0.45 else 0.75
	return {
		Key = key,
		Kind = "Critter",
		Signature = string.format("%s:%s:%d", speciesId, variant, feedLevel),
		Model = model,
		BaseCFrame = baseCFrame,
		Parts = partsList,
		HopSpeed = if speciesId == "StarSlime" then 4.2 elseif speciesId == "NebulaFox" then 5.0 else 3.1,
		HopHeight = baseHop + (if fed then 0.15 else 0),
		Phase = phaseSeed,
		MaturesAt = nil,
		CoreParts = nil,
		WasMature = false,
	}
end

local function buildPodVisual(
	key: string,
	maturesAt: number,
	pad: BasePart,
	horizontalRotation: CFrame,
	phaseSeed: number
): VisualEntry?
	local folder = visualsFolder
	if folder == nil then
		return nil
	end

	local padTopY = pad.Position.Y + pad.Size.X * 0.5
	local baseCFrame = CFrame.new(pad.Position.X, padTopY + 1.55, pad.Position.Z) * horizontalRotation

	local model = Instance.new("Model")
	model.Name = key .. "_Pod"
	local partsList: { PartOffset } = {}

	local initialMature = workspace:GetServerTimeNow() >= maturesAt
	local initialColor = if initialMature then COLOR_RADIANT_GOLD else COLOR_POD_INCUBATING

	local shell = createVisualPart(model, partsList, baseCFrame, CFrame.new(), {
		Name = "PodShell",
		Size = Vector3.new(2.5, 2.9, 2.5),
		Color = initialColor,
		Material = Enum.Material.Glass,
		Shape = Enum.PartType.Ball,
		Transparency = 0.42,
	})
	model.PrimaryPart = shell

	local core = createVisualPart(model, partsList, baseCFrame, CFrame.Angles(0.5, 0.5, 0), {
		Name = "PodCore",
		Size = Vector3.new(1.2, 1.2, 1.2),
		Color = initialColor,
		Material = Enum.Material.Neon,
	})

	model.Parent = folder
	return {
		Key = key,
		Kind = "Pod",
		Signature = tostring(maturesAt),
		Model = model,
		BaseCFrame = baseCFrame,
		Parts = partsList,
		HopSpeed = 2.6,
		HopHeight = 0.25,
		Phase = phaseSeed,
		MaturesAt = maturesAt,
		CoreParts = { shell, core },
		WasMature = initialMature,
	}
end

local function applyEntryCFrame(entry: VisualEntry, targetCFrame: CFrame): ()
	for _, sub in ipairs(entry.Parts) do
		sub.Part.CFrame = targetCFrame * sub.Offset
	end
end

local function destroyVisualEntry(key: string): ()
	local existing = activeVisuals[key]
	if existing ~= nil then
		existing.Model:Destroy()
		activeVisuals[key] = nil
	end
end

local function reconcilePlotVisuals(): ()
	if visualsFolder == nil then
		return
	end

	local desiredKeys: { [string]: boolean } = {}

	for plotId, dto in pairs(latestPlots) do
		if dto.OwnerUserId ~= 0 then
			local plotModel = getGreyboxPlotModel(plotId)
			if plotModel ~= nil then
				local primary = plotModel.PrimaryPart
				local horizontalRotation = if primary ~= nil then primary.CFrame.Rotation else CFrame.new()

				for slotId, penVisual in pairs(dto.ActivePenVisuals) do
					local key = string.format("P%d_%s", plotId, slotId)
					desiredKeys[key] = true
					local feedLevel = penVisual.FeedLevel or 0
					local signature = string.format("%s:%s:%d", penVisual.SpeciesId, penVisual.Variant, feedLevel)
					local current = activeVisuals[key]
					if current == nil or current.Signature ~= signature then
						destroyVisualEntry(key)
						local pad = resolveStationPartOnPlot(plotModel, "Pen", slotId)
						if pad ~= nil then
							local phaseSeed = plotId * 1.7 + (#slotId * 0.9)
							local created = buildCritterVisual(
								key,
								penVisual.SpeciesId,
								penVisual.Variant,
								feedLevel,
								pad,
								horizontalRotation,
								phaseSeed
							)
							if created ~= nil then
								activeVisuals[key] = created
							end
						end
					end
				end

				for slotId, incVisual in pairs(dto.IncubatorVisuals) do
					local key = string.format("P%d_%s", plotId, slotId)
					desiredKeys[key] = true
					local signature = tostring(incVisual.MaturesAt)
					local current = activeVisuals[key]
					if current == nil or current.Signature ~= signature then
						destroyVisualEntry(key)
						local pad = resolveStationPartOnPlot(plotModel, "Incubator", slotId)
						if pad ~= nil then
							local phaseSeed = plotId * 1.3 + (#slotId * 0.6)
							local created = buildPodVisual(
								key,
								incVisual.MaturesAt,
								pad,
								horizontalRotation,
								phaseSeed
							)
							if created ~= nil then
								activeVisuals[key] = created
							end
						end
					end
				end
			end
		end
	end

	for key in pairs(activeVisuals) do
		if not desiredKeys[key] then
			destroyVisualEntry(key)
		end
	end
end

local function stepVisualAnimations(): ()
	local reducedMotion = SoundController.IsReducedMotion()
	local nowClock = workspace:GetServerTimeNow()

	if reducedMotion then
		if not wasReducedMotion then
			for _, entry in pairs(activeVisuals) do
				applyEntryCFrame(entry, entry.BaseCFrame)
			end
		end
		wasReducedMotion = true
	else
		wasReducedMotion = false
	end

	for _, entry in pairs(activeVisuals) do
		if entry.Kind == "Pod" and entry.MaturesAt ~= nil and entry.CoreParts ~= nil then
			local mature = nowClock >= entry.MaturesAt
			if mature ~= entry.WasMature then
				entry.WasMature = mature
				local nextColor = if mature then COLOR_RADIANT_GOLD else COLOR_POD_INCUBATING
				for _, part in ipairs(entry.CoreParts) do
					part.Color = nextColor
				end
			end
		end

		if not reducedMotion then
			if entry.Kind == "Critter" then
				local hopY = math.abs(math.sin(nowClock * entry.HopSpeed + entry.Phase)) * entry.HopHeight
				local yaw = math.sin(nowClock * 1.4 + entry.Phase) * 0.14
				local nextCFrame = entry.BaseCFrame * CFrame.new(0, hopY, 0) * CFrame.Angles(0, yaw, 0)
				applyEntryCFrame(entry, nextCFrame)
			else
				local hoverY = math.sin(nowClock * entry.HopSpeed + entry.Phase) * entry.HopHeight
				local spin = nowClock * 0.9 + entry.Phase
				local nextCFrame = entry.BaseCFrame * CFrame.new(0, hoverY, 0) * CFrame.Angles(0, spin, 0)
				applyEntryCFrame(entry, nextCFrame)
			end
		end
	end
end

local function notifyPublicPlotsListeners(): ()
	for _, cb in ipairs(publicPlotsListeners) do
		local ok, err = pcall(cb, latestPlots)
		if not ok then
			warn("[PlotVisualController] PublicPlots listener error: " .. tostring(err))
		end
	end
end

function PlotVisualController.Init(self: typeof(PlotVisualController)): ()
	local existing = workspace:FindFirstChild(VISUALS_FOLDER_NAME)
	local folder: Folder
	if existing ~= nil and existing:IsA("Folder") then
		existing:ClearAllChildren()
		folder = existing
	else
		if existing ~= nil then
			existing:Destroy()
		end
		folder = Instance.new("Folder")
		folder.Name = VISUALS_FOLDER_NAME
		folder.Archivable = false
		folder.Parent = workspace
	end
	visualsFolder = folder
	activeVisuals = {}
end

function PlotVisualController.Start(self: typeof(PlotVisualController)): ()
	local remotes = ReplicatedStorage:WaitForChild(Constants.REMOTES_FOLDER_NAME)
	local syncPlotsEvent = remotes:WaitForChild(Constants.REMOTE_NAMES.SyncPublicPlots) :: RemoteEvent

	if syncConn == nil then
		syncConn = syncPlotsEvent.OnClientEvent:Connect(function(plotsList: { Types.PublicPlotDTO }, revision: number)
			if typeof(plotsList) ~= "table" or typeof(revision) ~= "number" then
				return
			end
			if latestPlotsRevision ~= -1 and revision <= latestPlotsRevision then
				return
			end

			latestPlotsRevision = revision
			local nextMap: { [number]: Types.PublicPlotDTO } = {}
			local occupiedCount = 0
			for _, dto in ipairs(plotsList) do
				if typeof(dto) == "table" and typeof(dto.PlotId) == "number" then
					nextMap[dto.PlotId] = dto
					if dto.OwnerUserId ~= 0 then
						occupiedCount += 1
					end
				end
			end
			latestPlots = nextMap

			print(string.format(
				"[PlotVisualController] Synced public plots (Revision %d, %d/%d occupied).",
				revision,
				occupiedCount,
				#plotsList
			))

			reconcilePlotVisuals()
			notifyPublicPlotsListeners()
		end)
	end

	if heartbeatConn == nil then
		heartbeatConn = RunService.Heartbeat:Connect(stepVisualAnimations)
	end
end

function PlotVisualController.GetPublicPlots(): { [number]: Types.PublicPlotDTO }
	return latestPlots
end

function PlotVisualController.GetLatestRevision(): number
	return latestPlotsRevision
end

function PlotVisualController.GetPlotIdForUserId(userId: number): number?
	for plotId, dto in pairs(latestPlots) do
		if dto.OwnerUserId == userId then
			return plotId
		end
	end
	return nil
end

function PlotVisualController.GetStationPartForUserId(userId: number, stationKind: string, targetId: string): BasePart?
	local plotId = PlotVisualController.GetPlotIdForUserId(userId)
	if plotId == nil then
		return nil
	end
	local plotModel = getGreyboxPlotModel(plotId)
	if plotModel == nil then
		return nil
	end
	return resolveStationPartOnPlot(plotModel, stationKind, targetId)
end

function PlotVisualController.OnPublicPlotsChanged(callback: (plots: { [number]: Types.PublicPlotDTO }) -> ()): ()
	table.insert(publicPlotsListeners, callback)
	if latestPlotsRevision ~= -1 then
		local ok, err = pcall(callback, latestPlots)
		if not ok then
			warn("[PlotVisualController] Initial PublicPlots callback error: " .. tostring(err))
		end
	end
end

return PlotVisualController
