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
local ConfigFolder = Shared:WaitForChild("Config")
local CritterConfig = require(ConfigFolder:WaitForChild("CritterConfig"))
local UpgradeConfig = require(ConfigFolder:WaitForChild("UpgradeConfig"))

type PartOffset = {
	Part: BasePart,
	Offset: CFrame,
}

type VisualEntry = {
	Key: string,
	PlotId: number,
	OwnerUserId: number,
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
	RadiantEmitters: { ParticleEmitter }?,
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
local lastOwnerByPlotId: { [number]: number } = {}
local lastPlotRevisionByPlotId: { [number]: number } = {}
local syncConn: RBXScriptConnection? = nil
local heartbeatConn: RBXScriptConnection? = nil
local visualsFolder: Folder? = nil
local activeVisuals: { [string]: VisualEntry } = {}
local publicPlotsListeners: { (plots: { [number]: Types.PublicPlotDTO }) -> () } = {}
local wasReducedMotion = false
local suppressSyncLog = false

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

local function resolveHubStationPart(stationKind: string, targetId: string): BasePart?
	local root = workspace:FindFirstChild(Constants.GREYBOX_ROOT_NAME)
	if root == nil then
		return nil
	end
	local hub = root:FindFirstChild("CentralHub")
	if hub == nil then
		return nil
	end
	if stationKind == "LureStand" then
		local kiosk = hub:FindFirstChild("FrostLureKiosk")
		local lure = if kiosk ~= nil then kiosk:FindFirstChild("LureStand") else nil
		return if lure ~= nil and lure:IsA("BasePart") then lure else nil
	elseif stationKind == "UpgradePad" then
		local workbench = hub:FindFirstChild("ToolWorkbench")
		local pad = if workbench ~= nil then workbench:FindFirstChild("UpgradePad_" .. targetId) else nil
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

local function attachRadiantSparkles(hostPart: BasePart, reducedMotion: boolean): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "RadiantSparkles"
	emitter.Color = ColorSequence.new(COLOR_RADIANT_GOLD, Color3.fromRGB(255, 255, 255))
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.28),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Lifetime = NumberRange.new(0.6, 1.0)
	emitter.Rate = 4
	emitter.Speed = NumberRange.new(0.8, 1.6)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.Enabled = not reducedMotion
	emitter.Parent = hostPart
	return emitter
end

local function measureModelWorldYBounds(model: Model): (number, number)
	local minY = math.huge
	local maxY = -math.huge
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			local half = desc.Size * 0.5
			local cf = desc.CFrame
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local wy = cf:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)).Y
						minY = math.min(minY, wy)
						maxY = math.max(maxY, wy)
					end
				end
			end
		end
	end
	if minY == math.huge then
		return 0, 0
	end
	return minY, maxY
end

local function computeCritterHopProfile(speciesId: Types.SpeciesId, fed: boolean): (number, number)
	local hopSpeed = if speciesId == "StarSlime" or speciesId == "CinderPup"
		then 4.3
		elseif speciesId == "NebulaFox" or speciesId == "CometOwl" then 4.9
		else 3.2
	local baseHop = if speciesId == "SolarGolem" then 0.45 else 0.75
	return hopSpeed, baseHop + (if fed then 0.15 else 0)
end

local function tryBuildCritterFromTemplate(
	folder: Folder,
	key: string,
	plotId: number,
	ownerUserId: number,
	speciesId: Types.SpeciesId,
	variant: Types.VariantId,
	feedLevel: number,
	pad: BasePart,
	horizontalRotation: CFrame,
	phaseSeed: number,
	def: Types.SpeciesDefinition
): VisualEntry?
	local templatesRoot = ReplicatedStorage:FindFirstChild(Constants.ASSET_TEMPLATES_FOLDER_NAME)
	local crittersFolder = if templatesRoot ~= nil then templatesRoot:FindFirstChild("Critters") else nil
	local template = if crittersFolder ~= nil then crittersFolder:FindFirstChild(speciesId) else nil
	if template == nil or not template:IsA("Model") then
		return nil
	end

	local templateBody = template:FindFirstChild("Body")
	if templateBody == nil or not templateBody:IsA("BasePart") then
		return nil
	end

	local templatePartCount = 0
	for _, desc in ipairs(template:GetDescendants()) do
		if desc:IsA("BasePart") then
			templatePartCount += 1
		end
	end
	if templatePartCount == 0 or templatePartCount > (Constants.MAX_CRITTER_PARTS - 1) then
		warn(string.format(
			"[PlotVisualController] Template %s has %d parts (budget max %d pre-halo); using blocky fallback.",
			template:GetFullName(),
			templatePartCount,
			Constants.MAX_CRITTER_PARTS - 1
		))
		return nil
	end

	local fed = feedLevel >= 1
	local scaleMult = if fed then Constants.FED_CRITTER_SCALE_MULTIPLIER else 1.0
	local accentColor = if fed then COLOR_RADIANT_GOLD else def.AccentColor
	local padTopY = pad.Position.Y + pad.Size.X * 0.5
	local baseCFrame = CFrame.new(pad.Position.X, padTopY, pad.Position.Z) * horizontalRotation

	local clone = template:Clone()
	clone.Name = string.format("%s_%s", key, speciesId)

	local bodyPart: BasePart? = nil
	local toStrip: { Instance } = {}
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("SurfaceAppearance") or desc:IsA("LuaSourceContainer") then
			table.insert(toStrip, desc)
		elseif desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
			desc.CanQuery = false
			desc.CanTouch = false
			if desc.Name == "Body" then
				bodyPart = desc
				desc.Material = Enum.Material.SmoothPlastic
				desc.Color = def.BodyColor
				desc.CastShadow = true
			elseif desc.Name == "Secondary" then
				desc.Material = Enum.Material.SmoothPlastic
				desc.Color = def.SecondaryColor
				desc.CastShadow = true
			elseif desc.Name == "Eyes" then
				desc.Material = Enum.Material.SmoothPlastic
				desc.Color = COLOR_EYE
				desc.CastShadow = false
			elseif desc.Name == "Accent" then
				desc.Material = Enum.Material.Neon
				desc.Color = accentColor
				desc.CastShadow = false
			else
				desc.Material = Enum.Material.SmoothPlastic
				desc.Color = def.BodyColor
				desc.CastShadow = false
			end
		end
	end
	for _, item in ipairs(toStrip) do
		item:Destroy()
	end
	if bodyPart == nil then
		clone:Destroy()
		return nil
	end
	clone.PrimaryPart = bodyPart

	local appliedScale = scaleMult
	clone:ScaleTo(appliedScale)
	local minY, maxY = measureModelWorldYBounds(clone)
	local haloClearance = if variant == "Radiant" then (0.55 * appliedScale + 0.12) else 0
	local rawHeight = math.max(0.1, maxY - minY)
	if (rawHeight + haloClearance) > Constants.MAX_CRITTER_DISPLAY_HEIGHT then
		local clampRatio = math.max(0.1, (Constants.MAX_CRITTER_DISPLAY_HEIGHT - haloClearance) / rawHeight)
		appliedScale = scaleMult * clampRatio
		clone:ScaleTo(appliedScale)
	end

	clone:PivotTo(baseCFrame)
	local curMinY = measureModelWorldYBounds(clone)
	if math.abs(curMinY - padTopY) > 1e-4 then
		clone:PivotTo(baseCFrame * CFrame.new(0, padTopY - curMinY, 0))
	end

	local partsList: { PartOffset } = {}
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("BasePart") then
			table.insert(partsList, {
				Part = desc,
				Offset = baseCFrame:ToObjectSpace(desc.CFrame),
			})
		end
	end

	local radiantEmitters: { ParticleEmitter }? = nil
	if variant == "Radiant" then
		local _, finalMaxY = measureModelWorldYBounds(clone)
		local _, finalBbox = clone:GetBoundingBox()
		local haloYOffset = (finalMaxY - padTopY) + 0.55 * appliedScale
		local haloDiameter = math.max(finalBbox.X, finalBbox.Z) * 0.85
		attachRadiantHalo(clone, partsList, baseCFrame, haloYOffset, haloDiameter)
		radiantEmitters = { attachRadiantSparkles(bodyPart, SoundController.IsReducedMotion()) }
	end

	clone.Parent = folder
	local hopSpeed, hopHeight = computeCritterHopProfile(speciesId, fed)
	return {
		Key = key,
		PlotId = plotId,
		OwnerUserId = ownerUserId,
		Kind = "Critter",
		Signature = string.format("%s:%s:%d:mesh", speciesId, variant, feedLevel),
		Model = clone,
		BaseCFrame = baseCFrame,
		Parts = partsList,
		HopSpeed = hopSpeed,
		HopHeight = hopHeight,
		Phase = phaseSeed,
		MaturesAt = nil,
		CoreParts = nil,
		RadiantEmitters = radiantEmitters,
		WasMature = false,
	}
end

local function buildCritterVisual(
	key: string,
	plotId: number,
	ownerUserId: number,
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

	local fromTemplate = tryBuildCritterFromTemplate(
		folder,
		key,
		plotId,
		ownerUserId,
		speciesId,
		variant,
		feedLevel,
		pad,
		horizontalRotation,
		phaseSeed,
		def
	)
	if fromTemplate ~= nil then
		return fromTemplate
	end

	local fed = feedLevel >= 1
	local scaleMult = if fed then Constants.FED_CRITTER_SCALE_MULTIPLIER else 1.0
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
	elseif speciesId == "CinderPup" then
		-- 7 parts (+1 Radiant halo = 8 <= 8 budget)
		local torsoScale = Vector3.new(bodyScale.X * 0.85, bodyScale.Y * 0.72, bodyScale.Z * 0.9)
		local body = createVisualPart(model, partsList, baseCFrame, CFrame.new(), {
			Name = "Body",
			Size = torsoScale,
			Color = def.BodyColor,
			CastShadow = true,
		})
		model.PrimaryPart = body

		createVisualPart(model, partsList, baseCFrame, CFrame.new(0, -0.05 * scaleMult, -torsoScale.Z * 0.54), {
			Name = "Snout",
			Size = Vector3.new(1.05, 0.72, 0.6) * scaleMult,
			Color = COLOR_CREAM,
		})
		for _, xSign in ipairs({ -1, 1 }) do
			createVisualPart(model, partsList, baseCFrame, CFrame.new(xSign * 0.55 * scaleMult, 0.32 * scaleMult, -torsoScale.Z * 0.48), {
				Name = if xSign < 0 then "LeftEye" else "RightEye",
				Size = Vector3.new(0.36, 0.4, 0.22) * scaleMult,
				Color = COLOR_EYE,
			})
			createVisualPart(model, partsList, baseCFrame, CFrame.new(xSign * 0.7 * scaleMult, torsoScale.Y * 0.5 + 0.35 * scaleMult, -0.25 * scaleMult), {
				Name = if xSign < 0 then "LeftEar" else "RightEar",
				Size = Vector3.new(0.45, 0.95, 0.65) * scaleMult,
				Color = accentColor,
				Material = Enum.Material.Neon,
				IsWedge = true,
			})
		end
		createVisualPart(model, partsList, baseCFrame, CFrame.new(0, 0.52 * scaleMult, torsoScale.Z * 0.54) * CFrame.Angles(math.rad(-25), 0, 0), {
			Name = "Tail",
			Size = Vector3.new(0.7, 0.9, 1.35) * scaleMult,
			Color = accentColor,
			Material = Enum.Material.Neon,
		})
		haloHeight = torsoScale.Y * 0.5 + 1.45 * scaleMult
	elseif speciesId == "FrostBeetle" then
		-- 7 parts (+1 Radiant halo = 8 <= 8 budget)
		local shellScale = Vector3.new(bodyScale.X, bodyScale.Y * 0.85, bodyScale.Z)
		local body = createVisualPart(model, partsList, baseCFrame, CFrame.new(), {
			Name = "Body",
			Size = shellScale,
			Color = def.BodyColor,
			CastShadow = true,
		})
		model.PrimaryPart = body

		createVisualPart(model, partsList, baseCFrame, CFrame.new(0, -0.15 * scaleMult, -shellScale.Z * 0.48), {
			Name = "HeadPlate",
			Size = Vector3.new(shellScale.X * 0.65, shellScale.Y * 0.55, 0.75) * scaleMult,
			Color = Color3.fromRGB(55, 115, 175),
		})
		for _, xSign in ipairs({ -1, 1 }) do
			createVisualPart(model, partsList, baseCFrame, CFrame.new(xSign * 0.5 * scaleMult, -0.05 * scaleMult, -shellScale.Z * 0.56), {
				Name = if xSign < 0 then "LeftEye" else "RightEye",
				Size = Vector3.new(0.32, 0.34, 0.22) * scaleMult,
				Color = COLOR_EYE,
			})
			createVisualPart(model, partsList, baseCFrame, CFrame.new(xSign * (shellScale.X * 0.54), -0.1 * scaleMult, 0.1 * scaleMult), {
				Name = if xSign < 0 then "LeftCrystal" else "RightCrystal",
				Size = Vector3.new(0.55, 0.65, 1.45) * scaleMult,
				Color = accentColor,
				Material = Enum.Material.Neon,
			})
		end
		createVisualPart(model, partsList, baseCFrame, CFrame.new(0, shellScale.Y * 0.45 + 0.45 * scaleMult, -shellScale.Z * 0.42) * CFrame.Angles(math.rad(25), 0, 0), {
			Name = "IceHorn",
			Size = Vector3.new(0.5, 1.3, 0.55) * scaleMult,
			Color = accentColor,
			Material = Enum.Material.Neon,
		})
		haloHeight = shellScale.Y * 0.5 + 1.35 * scaleMult
	elseif speciesId == "CometOwl" then
		-- 7 parts (+1 Radiant halo = 8 <= 8 budget)
		local body = createVisualPart(model, partsList, baseCFrame, CFrame.new(), {
			Name = "Body",
			Size = bodyScale,
			Color = def.BodyColor,
			CastShadow = true,
		})
		model.PrimaryPart = body

		createVisualPart(model, partsList, baseCFrame, CFrame.new(0, 0.15 * scaleMult, -bodyScale.Z * 0.52), {
			Name = "Beak",
			Size = Vector3.new(0.55, 0.45, 0.65) * scaleMult,
			Color = accentColor,
			Material = Enum.Material.Neon,
			IsWedge = true,
		})
		for _, xSign in ipairs({ -1, 1 }) do
			createVisualPart(model, partsList, baseCFrame, CFrame.new(xSign * 0.65 * scaleMult, 0.55 * scaleMult, -bodyScale.Z * 0.48), {
				Name = if xSign < 0 then "LeftEye" else "RightEye",
				Size = Vector3.new(0.45, 0.45, 0.22) * scaleMult,
				Color = COLOR_EYE,
				Shape = Enum.PartType.Ball,
			})
			createVisualPart(model, partsList, baseCFrame, CFrame.new(xSign * (bodyScale.X * 0.56), 0.05 * scaleMult, 0.15 * scaleMult) * CFrame.Angles(0, 0, xSign * math.rad(-18)), {
				Name = if xSign < 0 then "LeftWing" else "RightWing",
				Size = Vector3.new(0.65, 2.2, 1.9) * scaleMult,
				Color = accentColor,
				Material = Enum.Material.Neon,
			})
		end
		createVisualPart(model, partsList, baseCFrame, CFrame.new(0, bodyScale.Y * 0.5 + 0.35 * scaleMult, 0) * CFrame.Angles(0, math.rad(45), 0), {
			Name = "StarCrest",
			Size = Vector3.new(1.2, 0.55, 1.2) * scaleMult,
			Color = accentColor,
			Material = Enum.Material.Neon,
		})
		haloHeight = bodyScale.Y * 0.5 + 1.25 * scaleMult
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

	local radiantEmitters: { ParticleEmitter }? = nil
	if variant == "Radiant" then
		attachRadiantHalo(model, partsList, baseCFrame, haloHeight, haloDiameter)
		local bodyRef = model.PrimaryPart
		if bodyRef ~= nil then
			radiantEmitters = { attachRadiantSparkles(bodyRef, SoundController.IsReducedMotion()) }
		end
	end

	model.Parent = folder
	local hopSpeed, hopHeight = computeCritterHopProfile(speciesId, fed)
	return {
		Key = key,
		PlotId = plotId,
		OwnerUserId = ownerUserId,
		Kind = "Critter",
		Signature = string.format("%s:%s:%d:blocky", speciesId, variant, feedLevel),
		Model = model,
		BaseCFrame = baseCFrame,
		Parts = partsList,
		HopSpeed = hopSpeed,
		HopHeight = hopHeight,
		Phase = phaseSeed,
		MaturesAt = nil,
		CoreParts = nil,
		RadiantEmitters = radiantEmitters,
		WasMature = false,
	}
end

local function buildPodVisual(
	key: string,
	plotId: number,
	ownerUserId: number,
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
		PlotId = plotId,
		OwnerUserId = ownerUserId,
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

local function destroyVisualsForPlot(plotId: number): ()
	local toDestroy: { string } = {}
	for key, entry in pairs(activeVisuals) do
		if entry.PlotId == plotId then
			table.insert(toDestroy, key)
		end
	end
	for _, key in ipairs(toDestroy) do
		destroyVisualEntry(key)
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
					local hasMeshTemplate = false
					do
						local templatesRoot = ReplicatedStorage:FindFirstChild(Constants.ASSET_TEMPLATES_FOLDER_NAME)
						local crittersFolder = if templatesRoot ~= nil then templatesRoot:FindFirstChild("Critters") else nil
						local tmpl = if crittersFolder ~= nil then crittersFolder:FindFirstChild(penVisual.SpeciesId) else nil
						hasMeshTemplate = tmpl ~= nil and tmpl:IsA("Model")
					end
					local signature = string.format(
						"%s:%s:%d:%s",
						penVisual.SpeciesId,
						penVisual.Variant,
						feedLevel,
						if hasMeshTemplate then "mesh" else "blocky"
					)
					local current = activeVisuals[key]
					if current == nil or current.Signature ~= signature or current.OwnerUserId ~= dto.OwnerUserId then
						destroyVisualEntry(key)
						local pad = resolveStationPartOnPlot(plotModel, "Pen", slotId)
						if pad ~= nil then
							local phaseSeed = plotId * 1.7 + (#slotId * 0.9)
							local created = buildCritterVisual(
								key,
								plotId,
								dto.OwnerUserId,
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
					if current == nil or current.Signature ~= signature or current.OwnerUserId ~= dto.OwnerUserId then
						destroyVisualEntry(key)
						local pad = resolveStationPartOnPlot(plotModel, "Incubator", slotId)
						if pad ~= nil then
							local phaseSeed = plotId * 1.3 + (#slotId * 0.6)
							local created = buildPodVisual(
								key,
								plotId,
								dto.OwnerUserId,
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

	if reducedMotion ~= wasReducedMotion then
		for _, entry in pairs(activeVisuals) do
			if reducedMotion then
				applyEntryCFrame(entry, entry.BaseCFrame)
			end
			if entry.RadiantEmitters ~= nil then
				for _, emitter in ipairs(entry.RadiantEmitters) do
					emitter.Enabled = not reducedMotion
				end
			end
		end
		wasReducedMotion = reducedMotion
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
	latestPlots = {}
	latestPlotsRevision = -1
	lastOwnerByPlotId = {}
	lastPlotRevisionByPlotId = {}
end

function PlotVisualController.ApplyPublicPlotsSnapshot(plotsList: { Types.PublicPlotDTO }, revision: number): boolean
	if typeof(plotsList) ~= "table" or typeof(revision) ~= "number" then
		return false
	end
	if latestPlotsRevision ~= -1 and revision < latestPlotsRevision then
		return false
	end

	latestPlotsRevision = revision
	local nextMap: { [number]: Types.PublicPlotDTO } = {}
	local occupiedCount = 0

	for _, dto in ipairs(plotsList) do
		if typeof(dto) == "table" and typeof(dto.PlotId) == "number" then
			local plotId = dto.PlotId
			local incomingPlotRev = if typeof(dto.PlotRevision) == "number" then dto.PlotRevision else 1
			local prevPlotRev = lastPlotRevisionByPlotId[plotId] or 0

			if incomingPlotRev < prevPlotRev and latestPlots[plotId] ~= nil then
				local preserved = latestPlots[plotId]
				nextMap[plotId] = preserved
				if preserved.OwnerUserId ~= 0 then
					occupiedCount += 1
				end
			else
				local prevOwner = lastOwnerByPlotId[plotId]
				if prevOwner ~= nil and prevOwner ~= dto.OwnerUserId then
					destroyVisualsForPlot(plotId)
				end
				lastPlotRevisionByPlotId[plotId] = incomingPlotRev
				lastOwnerByPlotId[plotId] = dto.OwnerUserId
				nextMap[plotId] = dto
				if dto.OwnerUserId ~= 0 then
					occupiedCount += 1
				end
			end
		end
	end
	latestPlots = nextMap

	if not suppressSyncLog then
		print(string.format(
			"[PlotVisualController] Synced public plots (Revision %d, %d/%d occupied).",
			revision,
			occupiedCount,
			#plotsList
		))
	end

	reconcilePlotVisuals()
	notifyPublicPlotsListeners()
	return true
end

function PlotVisualController.Start(self: typeof(PlotVisualController)): ()
	local remotes = ReplicatedStorage:WaitForChild(Constants.REMOTES_FOLDER_NAME)
	local syncPlotsEvent = remotes:WaitForChild(Constants.REMOTE_NAMES.SyncPublicPlots) :: RemoteEvent

	if syncConn == nil then
		syncConn = syncPlotsEvent.OnClientEvent:Connect(function(plotsList: { Types.PublicPlotDTO }, revision: number)
			PlotVisualController.ApplyPublicPlotsSnapshot(plotsList, revision)
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
	local upgradeDef = if stationKind == "UpgradePad"
		then (UpgradeConfig.ById :: { [string]: Types.UpgradeDefinition })[targetId]
		else nil
	if stationKind == "LureStand" or (upgradeDef ~= nil and upgradeDef.StationZone == "Hub") then
		return resolveHubStationPart(stationKind, targetId)
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

function PlotVisualController.RunSelfTest(): number
	local passed = 0
	suppressSyncLog = true

	local testOk, testErr = pcall(function()
		local waitDeadline = os.clock() + 5
		while os.clock() < waitDeadline do
			local root = workspace:FindFirstChild(Constants.GREYBOX_ROOT_NAME)
			local plots = if root then root:FindFirstChild("Plots") else nil
			if plots and plots:FindFirstChild("Plot_6") then
				break
			end
			RunService.RenderStepped:Wait()
		end

		local function makeEmptyPlot(plotId: number, plotRev: number): Types.PublicPlotDTO
			return {
				PlotId = plotId,
				OwnerUserId = 0,
				OwnerDisplayName = "",
				PlotRevision = plotRev,
				UnlockedUpgrades = {},
				ActivePenVisuals = {},
				IncubatorVisuals = {},
			}
		end

		-- 1. Late-join 6-plot sync including Plot_6 Pen_5 visual + clean release destruction
		local snap1: { Types.PublicPlotDTO } = {
			{
				PlotId = 1,
				OwnerUserId = 101,
				OwnerDisplayName = "Alpha",
				PlotRevision = 2,
				UnlockedUpgrades = { PenSlot_5 = true },
				ActivePenVisuals = {
					Pen_1 = { SpeciesId = "StarSlime", Variant = "Normal", FeedLevel = 0 },
				},
				IncubatorVisuals = {},
			},
			makeEmptyPlot(2, 1),
			makeEmptyPlot(3, 1),
			makeEmptyPlot(4, 1),
			makeEmptyPlot(5, 1),
			{
				PlotId = 6,
				OwnerUserId = 606,
				OwnerDisplayName = "Sixth",
				PlotRevision = 3,
				UnlockedUpgrades = { PenSlot_5 = true },
				ActivePenVisuals = {
					Pen_5 = { SpeciesId = "NebulaFox", Variant = "Radiant", FeedLevel = 1 },
				},
				IncubatorVisuals = {},
			},
		}

		assert(PlotVisualController.ApplyPublicPlotsSnapshot(snap1, 1), "Apply 6-plot initial snapshot")
		local p1Entry = activeVisuals["P1_Pen_1"]
		local p6Entry = activeVisuals["P6_Pen_5"]
		assert(p1Entry ~= nil and p6Entry ~= nil, "Both Plot_1 and Plot_6 Pen_5 client models built")
		local p1OldModel = p1Entry.Model

		-- Reject strictly stale global revision without mutating active visuals
		assert(not PlotVisualController.ApplyPublicPlotsSnapshot({ makeEmptyPlot(1, 99) }, 0), "Strictly older global revision rejected")
		assert(activeVisuals["P1_Pen_1"] == p1Entry, "Stale global packet preserves Plot_1 visual")
		passed += 1

		-- 2. Direct plot reuse with identical species at higher PlotRevision destroys old model & builds fresh one
		local snapReuse: { Types.PublicPlotDTO } = {
			{
				PlotId = 1,
				OwnerUserId = 202,
				OwnerDisplayName = "Beta",
				PlotRevision = 4,
				UnlockedUpgrades = {},
				ActivePenVisuals = {
					Pen_1 = { SpeciesId = "StarSlime", Variant = "Normal", FeedLevel = 0 },
				},
				IncubatorVisuals = {},
			},
			makeEmptyPlot(2, 1),
			makeEmptyPlot(3, 1),
			makeEmptyPlot(4, 1),
			makeEmptyPlot(5, 1),
			makeEmptyPlot(6, 4),
		}

		assert(PlotVisualController.ApplyPublicPlotsSnapshot(snapReuse, 2), "Apply direct plot reuse snapshot")
		local p1ReusedEntry = activeVisuals["P1_Pen_1"]
		assert(p1ReusedEntry ~= nil and p1ReusedEntry.OwnerUserId == 202, "Reused Plot_1 assigned to new owner 202")
		assert(p1ReusedEntry.Model ~= p1OldModel and p1OldModel.Parent == nil, "Old owner's critter model destroyed cleanly on direct plot reuse")
		assert(activeVisuals["P6_Pen_5"] == nil, "Released Plot_6 visual removed cleanly")

		-- Stale PlotRevision inside newer global envelope must not roll back Plot_1
		local snapStalePlot: { Types.PublicPlotDTO } = {
			{
				PlotId = 1,
				OwnerUserId = 101,
				OwnerDisplayName = "AlphaStale",
				PlotRevision = 2,
				UnlockedUpgrades = {},
				ActivePenVisuals = {},
				IncubatorVisuals = {},
			},
		}
		assert(PlotVisualController.ApplyPublicPlotsSnapshot(snapStalePlot, 3), "Envelope accepted while guarding per-plot revision")
		assert(latestPlots[1].OwnerUserId == 202 and activeVisuals["P1_Pen_1"] ~= nil, "Lower PlotRevision must not roll back newer plot occupant")
		passed += 1

		-- 3. S3-04 Regression: Full 6-plot x 5-pen (30 critters + 12 pods) visual part budget & reuse purge
		local speciesCycle: { Types.SpeciesId } = {
			"StarSlime",
			"CinderPup",
			"FrostBeetle",
			"CometOwl",
			"NebulaFox",
			"SolarGolem",
		}
		local penSlotNames = { "Pen_1", "Pen_2", "Pen_3", "Pen_4", "Pen_5" }
		local snapFull: { Types.PublicPlotDTO } = {}
		for plotId = 1, Constants.MAX_PLOTS_ALPHA do
			local penVisuals: { [string]: Types.PublicPenVisual } = {}
			for sIdx, slotId in ipairs(penSlotNames) do
				local specIdx = ((plotId - 1) * 5 + sIdx - 1) % #speciesCycle + 1
				penVisuals[slotId] = {
					SpeciesId = speciesCycle[specIdx],
					Variant = if (plotId + sIdx) % 2 == 0 then "Radiant" else "Normal",
					FeedLevel = if (plotId + sIdx) % 3 == 0 then 1 else 0,
				}
			end
			table.insert(snapFull, {
				PlotId = plotId,
				OwnerUserId = 1000 + plotId,
				OwnerDisplayName = "Full_" .. tostring(plotId),
				PlotRevision = 10,
				UnlockedUpgrades = { PenSlot_5 = true, Incubator_2 = true },
				ActivePenVisuals = penVisuals,
				IncubatorVisuals = {
					Incubator_1 = { MaturesAt = 9999999999 },
					Incubator_2 = { MaturesAt = 9999999999 },
				},
			})
		end

		assert(PlotVisualController.ApplyPublicPlotsSnapshot(snapFull, 10), "Apply full 6-plot x 5-pen snapshot")
		local critterCount = 0
		local podCount = 0
		for _, entry in pairs(activeVisuals) do
			if entry.Kind == "Critter" then
				critterCount += 1
				local basePartCount = 0
				for _, desc in ipairs(entry.Model:GetDescendants()) do
					if desc:IsA("BasePart") then
						basePartCount += 1
					end
				end
				assert(
					basePartCount <= Constants.MAX_CRITTER_PARTS,
					string.format("Critter %s exceeded 8-part budget (%d parts)", entry.Key, basePartCount)
				)
				local _, bbSize = entry.Model:GetBoundingBox()
				assert(
					bbSize.Y <= Constants.MAX_CRITTER_DISPLAY_HEIGHT + 0.01,
					string.format("Critter %s height %.3f exceeded %.1f stud cap", entry.Key, bbSize.Y, Constants.MAX_CRITTER_DISPLAY_HEIGHT)
				)
			elseif entry.Kind == "Pod" then
				podCount += 1
			end
		end
		assert(critterCount == 30, string.format("Expected 30 active critters across 6 plots (got %d)", critterCount))
		assert(podCount == 12, string.format("Expected 12 active pods across 6 plots (got %d)", podCount))
		assert(
			visualsFolder ~= nil and #(visualsFolder :: Folder):GetChildren() == 42,
			"Expected 42 child models in StarfallClientVisuals"
		)

		local oldPlot3Models: { Model } = {}
		local oldPlot6Models: { Model } = {}
		for _, entry in pairs(activeVisuals) do
			if entry.PlotId == 3 then
				table.insert(oldPlot3Models, entry.Model)
			elseif entry.PlotId == 6 then
				table.insert(oldPlot6Models, entry.Model)
			end
		end
		assert(#oldPlot3Models == 7 and #oldPlot6Models == 7, "Plot_3 and Plot_6 each had 7 models before reuse/release")

		local snapReuse2 = table.clone(snapFull)
		snapReuse2[3] = {
			PlotId = 3,
			OwnerUserId = 2003,
			OwnerDisplayName = "Reused_3",
			PlotRevision = 12,
			UnlockedUpgrades = {},
			ActivePenVisuals = {
				Pen_1 = { SpeciesId = "StarSlime", Variant = "Normal", FeedLevel = 0 },
			},
			IncubatorVisuals = {},
		}
		snapReuse2[6] = makeEmptyPlot(6, 12)

		assert(PlotVisualController.ApplyPublicPlotsSnapshot(snapReuse2, 11), "Apply Plot_3 reuse and Plot_6 release")
		for _, m in ipairs(oldPlot3Models) do
			assert(m.Parent == nil, "Old Plot_3 model destroyed cleanly on owner change")
		end
		for _, m in ipairs(oldPlot6Models) do
			assert(m.Parent == nil, "Released Plot_6 model destroyed cleanly")
		end
		local remainingCount = 0
		for _ in pairs(activeVisuals) do
			remainingCount += 1
		end
		assert(remainingCount == 29, string.format("Expected 29 active visuals after release + reuse (got %d)", remainingCount))
		assert(
			visualsFolder ~= nil and #(visualsFolder :: Folder):GetChildren() == 29,
			"StarfallClientVisuals has zero leaked child models"
		)
		passed += 1

		-- 4. S4-02 Template Runtime Integration, Ground Contact, Radiant Sparkles, Reduced Motion & Height Reporting
		local createdTempRoot = false
		local createdTempCritters = false
		local createdTempMockStar = false
		local prevReduced = SoundController.IsReducedMotion()
		local testOk4, testErr4 = pcall(function()
			local root = ReplicatedStorage:FindFirstChild(Constants.ASSET_TEMPLATES_FOLDER_NAME)
			if root == nil then
				root = Instance.new("Folder")
				root.Name = Constants.ASSET_TEMPLATES_FOLDER_NAME
				root.Parent = ReplicatedStorage
				createdTempRoot = true
			end
			local cFolder = (root :: Instance):FindFirstChild("Critters")
			if cFolder == nil then
				cFolder = Instance.new("Folder")
				cFolder.Name = "Critters"
				cFolder.Parent = root
				createdTempCritters = true
			end

			local speciesToTest: { Types.SpeciesId } = {}
			for _, sid in ipairs(CritterConfig.OrderedIds) do
				local existing = (cFolder :: Instance):FindFirstChild(sid)
				if existing ~= nil and existing:IsA("Model") then
					table.insert(speciesToTest, sid)
				end
			end

			if #speciesToTest == 0 then
				local mock = Instance.new("Model")
				mock.Name = "StarSlime"
				local mSec = Instance.new("Part")
				mSec.Name = "Secondary"
				mSec.Size = Vector3.new(3.2, 0.6, 2.8)
				mSec.Position = Vector3.new(0, 0.3, 0)
				mSec.Parent = mock
				local mBody = Instance.new("Part")
				mBody.Name = "Body"
				mBody.Size = Vector3.new(2.8, 1.5, 2.5)
				mBody.Position = Vector3.new(0, 1.35, 0)
				mBody.Parent = mock
				local mEyes = Instance.new("Part")
				mEyes.Name = "Eyes"
				mEyes.Size = Vector3.new(1.4, 0.6, 0.3)
				mEyes.Position = Vector3.new(0, 1.1, -1.2)
				mEyes.Parent = mock
				local mAcc = Instance.new("Part")
				mAcc.Name = "Accent"
				mAcc.Size = Vector3.new(0.8, 0.8, 0.4)
				mAcc.Position = Vector3.new(0, 2.4, 0)
				mAcc.Parent = mock
				mock.PrimaryPart = mBody
				mock.Parent = cFolder
				createdTempMockStar = true
				table.insert(speciesToTest, "StarSlime")
			end

			local pad1 = resolveStationPartOnPlot(getGreyboxPlotModel(1) :: Model, "Pen", "Pen_1") :: BasePart
			local padTopY = pad1.Position.Y + pad1.Size.X * 0.5
			SoundController.SetReducedMotion(false)
			local seqRev = 20

			for _, sid in ipairs(speciesToTest) do
				seqRev += 1
				local snapTest: { Types.PublicPlotDTO } = {
					{
						PlotId = 1,
						OwnerUserId = 9001,
						OwnerDisplayName = "TemplateCheck",
						PlotRevision = seqRev,
						UnlockedUpgrades = { PenSlot_3 = true },
						ActivePenVisuals = {
							Pen_1 = { SpeciesId = sid, Variant = "Normal", FeedLevel = 0 },
							Pen_2 = { SpeciesId = sid, Variant = "Radiant", FeedLevel = 0 },
							Pen_3 = { SpeciesId = sid, Variant = "Radiant", FeedLevel = 1 },
						},
						IncubatorVisuals = {},
					},
					makeEmptyPlot(2, seqRev),
					makeEmptyPlot(3, seqRev),
					makeEmptyPlot(4, seqRev),
					makeEmptyPlot(5, seqRev),
					makeEmptyPlot(6, seqRev),
				}
				assert(PlotVisualController.ApplyPublicPlotsSnapshot(snapTest, seqRev), "Apply template test for " .. sid)

				local eNorm = activeVisuals["P1_Pen_1"]
				local eRad = activeVisuals["P1_Pen_2"]
				local eFed = activeVisuals["P1_Pen_3"]
				assert(eNorm ~= nil and eRad ~= nil and eFed ~= nil, "Built Normal, Radiant, and Fed Radiant visuals for " .. sid)

				local minNormY = measureModelWorldYBounds(eNorm.Model)
				assert(math.abs(minNormY - padTopY) <= 0.02, string.format("%s Normal grounded within 0.02 studs (delta=%.4f)", sid, minNormY - padTopY))
				local minFedY = measureModelWorldYBounds(eFed.Model)
				assert(math.abs(minFedY - padTopY) <= 0.02, string.format("%s Fed Radiant grounded within 0.02 studs (delta=%.4f)", sid, minFedY - padTopY))

				local _, sNorm = eNorm.Model:GetBoundingBox()
				local _, sRad = eRad.Model:GetBoundingBox()
				local _, sFed = eFed.Model:GetBoundingBox()
				assert(sNorm.Y <= Constants.MAX_CRITTER_DISPLAY_HEIGHT and sFed.Y <= Constants.MAX_CRITTER_DISPLAY_HEIGHT, sid .. " height <= 8.0")

				local bodyRad = eRad.Model:FindFirstChild("Body")
				local haloRad = eRad.Model:FindFirstChild("RadiantHalo")
				local sparkleRad = if bodyRad ~= nil then bodyRad:FindFirstChild("RadiantSparkles") else nil
				assert(haloRad ~= nil and sparkleRad ~= nil and sparkleRad:IsA("ParticleEmitter"), sid .. " Radiant has RadiantHalo & RadiantSparkles")
				assert((sparkleRad :: ParticleEmitter).Enabled == true, "RadiantSparkles enabled when Reduced Motion OFF")

				SoundController.SetReducedMotion(true)
				stepVisualAnimations()
				assert((sparkleRad :: ParticleEmitter).Enabled == false, "RadiantSparkles disabled cleanly when Reduced Motion ON")
				SoundController.SetReducedMotion(false)
				stepVisualAnimations()

				if not createdTempMockStar then
					print(string.format(
						"[PlotVisualController] Runtime Template Verified %-11s | NormalH=%.3f | Rad1xH=%.3f | FedRadH=%.3f",
						sid,
						sNorm.Y,
						sRad.Y,
						sFed.Y
					))
				end
			end
		end)

		SoundController.SetReducedMotion(prevReduced)
		if createdTempMockStar then
			local root = ReplicatedStorage:FindFirstChild(Constants.ASSET_TEMPLATES_FOLDER_NAME)
			local cFolder = if root ~= nil then root:FindFirstChild("Critters") else nil
			local mockStar = if cFolder ~= nil then cFolder:FindFirstChild("StarSlime") else nil
			if mockStar ~= nil then
				mockStar:Destroy()
			end
		end
		if createdTempCritters then
			local root = ReplicatedStorage:FindFirstChild(Constants.ASSET_TEMPLATES_FOLDER_NAME)
			local cFolder = if root ~= nil then root:FindFirstChild("Critters") else nil
			if cFolder ~= nil then
				cFolder:Destroy()
			end
		end
		if createdTempRoot then
			local root = ReplicatedStorage:FindFirstChild(Constants.ASSET_TEMPLATES_FOLDER_NAME)
			if root ~= nil then
				root:Destroy()
			end
		end
		assert(testOk4, tostring(testErr4))
		passed += 1
	end)

	suppressSyncLog = false
	for key in pairs(activeVisuals) do
		destroyVisualEntry(key)
	end
	if visualsFolder ~= nil then
		visualsFolder:ClearAllChildren()
	end
	latestPlots = {}
	latestPlotsRevision = -1
	lastOwnerByPlotId = {}
	lastPlotRevisionByPlotId = {}

	if not testOk then
		error(testErr)
	end

	return passed
end

return PlotVisualController
