--!strict
--[[
	Module: GreyboxBuilder
	Purpose: Idempotently creates, preserves, and strictly validates the Stage 3 six-plot + Central Observatory Hub
	         Starfall Ranch greybox map inside Workspace.StarfallGreyboxRoot.
	Connections: Called on server Init via GreyboxBuilder.EnsureExists(workspace) and manually via
	             tools/studio/GenerateGreyboxMap.luau.
	How to Test in Studio: Press Play (F5) or run tools/studio/GenerateGreyboxMap.luau in Command Bar.
]]

local CollectionService = game:GetService("CollectionService")

local Shared = script.Parent.Parent
local Constants = require(Shared:WaitForChild("Constants"))
local Types = require(Shared:WaitForChild("Types"))
local ConfigFolder = Shared:WaitForChild("Config")
local UpgradeConfig = require(ConfigFolder:WaitForChild("UpgradeConfig"))
local FormatUtil = require(script.Parent:WaitForChild("FormatUtil"))

export type GenerateOptions = {
	ConfirmReplace: boolean?,
	Parent: Instance?,
}

local PALETTE = {
	MeadowMint = Color3.fromRGB(95, 215, 145),
	AstralViolet = Color3.fromRGB(205, 115, 255),
	LilacStone = Color3.fromRGB(120, 105, 155),
	CraterFloor = Color3.fromRGB(85, 75, 115),
	PlazaStone = Color3.fromRGB(72, 68, 98),
	PromenadeStone = Color3.fromRGB(88, 84, 118),
	CreamWood = Color3.fromRGB(245, 235, 220),
	OrbitalCyan = Color3.fromRGB(65, 210, 255),
	StarlightGold = Color3.fromRGB(255, 205, 45),
	EmberCoral = Color3.fromRGB(255, 130, 75),
	FrostIce = Color3.fromRGB(130, 195, 240),
	LockedSlate = Color3.fromRGB(140, 145, 165),
	PenGrass = Color3.fromRGB(115, 228, 160),
	DarkSlate = Color3.fromRGB(45, 42, 62),
	TextCream = Color3.fromRGB(245, 240, 232),
}

local GreyboxBuilder = {}

local function isOwnedGreyboxFolder(instance: Instance?): boolean
	return instance ~= nil
		and instance:IsA("Folder")
		and CollectionService:HasTag(instance, Constants.TAG_GREYBOX_ROOT)
end

local function failAt(path: string, reason: string): (boolean, string)
	return false, string.format("%s: %s", path, reason)
end

local function createPart(props: {
	Name: string,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3,
	Material: Enum.Material?,
	Shape: Enum.PartType?,
	Transparency: number?,
	CanCollide: boolean?,
	Parent: Instance,
}): Part
	local part = Instance.new("Part")
	part.Name = props.Name
	part.Size = props.Size
	part.CFrame = props.CFrame
	part.Color = props.Color
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.Shape = props.Shape or Enum.PartType.Block
	part.Transparency = props.Transparency or 0
	part.Anchored = true
	part.CanCollide = if props.CanCollide ~= nil then props.CanCollide else true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = props.Parent
	return part
end

local function attachLabel(
	adornee: BasePart,
	name: string,
	text: string,
	studsOffset: Vector3,
	accentColor: Color3?,
	size: UDim2?,
	maxDistance: number?
): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = size or UDim2.fromOffset(130, 28)
	gui.StudsOffset = studsOffset
	gui.AlwaysOnTop = false
	gui.MaxDistance = maxDistance or 24
	gui.Adornee = adornee
	gui.Parent = adornee

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(26, 24, 42)
	label.BackgroundTransparency = 0.2
	label.TextColor3 = accentColor or Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.Parent = gui

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.PaddingTop = UDim.new(0, 3)
	padding.PaddingBottom = UDim.new(0, 3)
	padding.Parent = label

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	return gui
end

local PLOT_ORIGINS: { [number]: Vector3 } = {
	[1] = Vector3.new(-98, 0.5, -88),
	[2] = Vector3.new(-98, 0.5, 0),
	[3] = Vector3.new(-98, 0.5, 88),
	[4] = Vector3.new(98, 0.5, -88),
	[5] = Vector3.new(98, 0.5, 0),
	[6] = Vector3.new(98, 0.5, 88),
}

local BRIDGE_SPECS: { { PlotId: number, Position: Vector3 } } = {
	{ PlotId = 1, Position = Vector3.new(-61, 0.5, -88) },
	{ PlotId = 2, Position = Vector3.new(-61, 0.5, 0) },
	{ PlotId = 3, Position = Vector3.new(-61, 0.5, 88) },
	{ PlotId = 4, Position = Vector3.new(61, 0.5, -88) },
	{ PlotId = 5, Position = Vector3.new(61, 0.5, 0) },
	{ PlotId = 6, Position = Vector3.new(61, 0.5, 88) },
}

local STARTER_NODE_SPECS: { { PlotId: number, Position: Vector3 } } = {
	{ PlotId = 1, Position = Vector3.new(-54, 1.0, -88) },
	{ PlotId = 2, Position = Vector3.new(-50, 1.0, 0) },
	{ PlotId = 3, Position = Vector3.new(-54, 1.0, 88) },
	{ PlotId = 4, Position = Vector3.new(54, 1.0, -88) },
	{ PlotId = 5, Position = Vector3.new(50, 1.0, 0) },
	{ PlotId = 6, Position = Vector3.new(54, 1.0, 88) },
}

local CRATER_NODE_SPECS: { { Index: number, Name: string, Position: Vector3, Region: string, Color: Color3 } } = {
	{ Index = 1, Name = "MeteorNode_1", Position = Vector3.new(-20, 1.0, 92), Region = "EmberBasin", Color = PALETTE.EmberCoral },
	{ Index = 2, Name = "MeteorNode_2", Position = Vector3.new(0, 1.0, 122), Region = "EmberBasin", Color = PALETTE.EmberCoral },
	{ Index = 3, Name = "MeteorNode_3", Position = Vector3.new(20, 1.0, 92), Region = "EmberBasin", Color = PALETTE.EmberCoral },
	{ Index = 4, Name = "MeteorNode_4", Position = Vector3.new(-22, 2.25, -94), Region = "FrostRidge", Color = PALETTE.OrbitalCyan },
	{ Index = 5, Name = "MeteorNode_5", Position = Vector3.new(0, 2.25, -124), Region = "FrostRidge", Color = PALETTE.OrbitalCyan },
	{ Index = 6, Name = "MeteorNode_6", Position = Vector3.new(22, 2.25, -94), Region = "FrostRidge", Color = PALETTE.OrbitalCyan },
	{ Index = 7, Name = "MeteorNode_7", Position = Vector3.new(0, 1.0, 82), Region = "EmberBasin", Color = PALETTE.EmberCoral },
	{ Index = 8, Name = "MeteorNode_8", Position = Vector3.new(0, 2.25, -84), Region = "FrostRidge", Color = PALETTE.OrbitalCyan },
}

local PEN_SLOT_SPECS = {
	{ SlotId = "Pen_1", Offset = Vector3.new(18, 0.95, -9), Unlocked = true, Label = "Pen #1" },
	{ SlotId = "Pen_2", Offset = Vector3.new(30, 0.95, -9), Unlocked = false, Label = "Pen #2" },
	{ SlotId = "Pen_3", Offset = Vector3.new(18, 0.95, 2), Unlocked = false, Label = "Pen #3" },
	{ SlotId = "Pen_4", Offset = Vector3.new(30, 0.95, 2), Unlocked = false, Label = "Pen #4" },
	{ SlotId = "Pen_5", Offset = Vector3.new(18, 0.95, 13), Unlocked = false, Label = "Pen #5" },
}

local function getUpgradePadColor(def: Types.UpgradeDefinition): Color3
	if def.Id == "FrostCracker" then
		return PALETTE.OrbitalCyan
	elseif def.Id == "StarCracker" then
		return PALETTE.AstralViolet
	elseif def.Id == "PenSlot_4" or def.Id == "PenSlot_5" then
		return PALETTE.StarlightGold
	elseif def.Id == "BagCap_20" then
		return PALETTE.OrbitalCyan
	end
	return PALETTE.MeadowMint
end

local function createHubLureStand(kioskModel: Model): Part
	local lureStand = createPart({
		Name = "LureStand",
		Size = Vector3.new(4, 3.2, 7),
		CFrame = CFrame.new(32, 2.1, -24),
		Color = PALETTE.DarkSlate,
		Parent = kioskModel,
	})
	createPart({
		Name = "LureTop",
		Size = Vector3.new(4.2, 0.4, 7.2),
		CFrame = CFrame.new(32, 3.9, -24),
		Color = PALETTE.OrbitalCyan,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = lureStand,
	})
	lureStand:SetAttribute("HubStation", true)
	CollectionService:AddTag(lureStand, Constants.TAG_LURE_STAND)
	CollectionService:AddTag(lureStand, Constants.TAG_HUB_STATION)
	attachLabel(
		lureStand,
		"LureLabel",
		string.format("Frost Lure • %d", Constants.FROST_LURE_COST),
		Vector3.new(0, 3.4, 0),
		PALETTE.OrbitalCyan,
		UDim2.fromOffset(150, 30),
		36
	)
	return lureStand
end

local function createPenSlotPad(
	penSlotsFolder: Folder,
	plotFrame: CFrame,
	plotId: number,
	spec: { SlotId: string, Offset: Vector3, Unlocked: boolean, Label: string }
): Part
	local slotPad = createPart({
		Name = spec.SlotId,
		Size = Vector3.new(0.4, 5, 5),
		CFrame = (plotFrame * CFrame.new(spec.Offset)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = if spec.Unlocked then PALETTE.StarlightGold else PALETTE.LockedSlate,
		Material = Enum.Material.SmoothPlastic,
		Shape = Enum.PartType.Cylinder,
		Transparency = if spec.Unlocked then 0.15 else 0.5,
		CanCollide = false,
		Parent = penSlotsFolder,
	})
	slotPad:SetAttribute("PlotId", plotId)
	slotPad:SetAttribute("SlotId", spec.SlotId)
	slotPad:SetAttribute("UnlockedByDefault", spec.Unlocked)
	CollectionService:AddTag(slotPad, Constants.TAG_PEN_SLOT)
	attachLabel(slotPad, "SlotLabel", spec.Label, Vector3.new(0, 2.4, 0), PALETTE.StarlightGold)
	return slotPad
end

local function createUpgradePad(
	parentFolder: Instance,
	originFrame: CFrame,
	plotId: number?,
	def: Types.UpgradeDefinition,
	isHubStation: boolean
): Part
	local baseColor = getUpgradePadColor(def)
	local pad = createPart({
		Name = "UpgradePad_" .. def.Id,
		Size = Vector3.new(0.6, 5.5, 5.5),
		CFrame = (originFrame * CFrame.new(def.PadOffsetX, 0.9, def.PadOffsetZ)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = baseColor,
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
		Parent = parentFolder,
	})
	if plotId ~= nil then
		pad:SetAttribute("PlotId", plotId)
	end
	if isHubStation then
		pad:SetAttribute("HubStation", true)
		CollectionService:AddTag(pad, Constants.TAG_HUB_STATION)
	end
	pad:SetAttribute("UpgradeId", def.Id)
	CollectionService:AddTag(pad, Constants.TAG_UPGRADE_PAD)
	attachLabel(
		pad,
		"UpgradeLabel",
		string.format("%s • %s", def.DisplayName, FormatUtil.FormatCoins(def.Cost)),
		Vector3.new(0, 2.6, 0),
		baseColor,
		UDim2.fromOffset(145, 28),
		if isHubStation then 36 else 24
	)
	return pad
end

local function buildCentralHub(root: Folder): ()
	local hubModel = Instance.new("Model")
	hubModel.Name = "CentralHub"
	hubModel.Parent = root

	local plazaFloor = createPart({
		Name = "PlazaFloor",
		Size = Vector3.new(108, 1, 108),
		CFrame = CFrame.new(0, 0.5, 0),
		Color = PALETTE.PlazaStone,
		Material = Enum.Material.SmoothPlastic,
		Parent = hubModel,
	})
	hubModel.PrimaryPart = plazaFloor

	-- Non-overlapping flush Promenades serving Plots 1..6 along West and East sides
	local promenades = Instance.new("Folder")
	promenades.Name = "Promenades"
	promenades.Parent = hubModel

	local promenadeSpecs = {
		{ Name = "WestPromenadeNorth", Size = Vector3.new(16, 1, 72), Pos = Vector3.new(-50, 0.5, -90) },
		{ Name = "WestPromenadeSouth", Size = Vector3.new(16, 1, 72), Pos = Vector3.new(-50, 0.5, 90) },
		{ Name = "WestPromenadeMid", Size = Vector3.new(4, 1, 108), Pos = Vector3.new(-56, 0.5, 0) },
		{ Name = "EastPromenadeNorth", Size = Vector3.new(16, 1, 72), Pos = Vector3.new(50, 0.5, -90) },
		{ Name = "EastPromenadeSouth", Size = Vector3.new(16, 1, 72), Pos = Vector3.new(50, 0.5, 90) },
		{ Name = "EastPromenadeMid", Size = Vector3.new(4, 1, 108), Pos = Vector3.new(56, 0.5, 0) },
	}
	for _, spec in ipairs(promenadeSpecs) do
		createPart({
			Name = spec.Name,
			Size = spec.Size,
			CFrame = CFrame.new(spec.Pos),
			Color = PALETTE.PromenadeStone,
			Parent = promenades,
		})
	end

	-- Arrival landing marker facing North toward Observatory
	createPart({
		Name = "HubArrivalPad",
		Size = Vector3.new(8, 0.2, 8),
		CFrame = CFrame.lookAt(Vector3.new(0, 1.05, 20), Vector3.new(0, 1.05, 0)),
		Color = PALETTE.OrbitalCyan,
		Material = Enum.Material.Neon,
		Transparency = 0.25,
		CanCollide = false,
		Parent = hubModel,
	})

	-- Observatory Landmark in Plaza center (visible from every Plot gate)
	local observatory = Instance.new("Model")
	observatory.Name = "Observatory"
	observatory.Parent = hubModel

	local plinth = createPart({
		Name = "ObservatoryPlinth",
		Size = Vector3.new(0.8, 18, 18),
		CFrame = CFrame.new(0, 1.4, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = PALETTE.CreamWood,
		Shape = Enum.PartType.Cylinder,
		Parent = observatory,
	})
	observatory.PrimaryPart = plinth

	createPart({
		Name = "ObservatoryRing",
		Size = Vector3.new(0.3, 22, 22),
		CFrame = CFrame.new(0, 1.15, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = PALETTE.OrbitalCyan,
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
		Parent = observatory,
	})
	createPart({
		Name = "ObservatoryTower",
		Size = Vector3.new(8, 11, 11),
		CFrame = CFrame.new(0, 5.8, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = PALETTE.DarkSlate,
		Shape = Enum.PartType.Cylinder,
		Parent = observatory,
	})
	local dome = createPart({
		Name = "ObservatoryDome",
		Size = Vector3.new(12, 12, 12),
		CFrame = CFrame.new(0, 12.2, 0),
		Color = PALETTE.AstralViolet,
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Ball,
		Transparency = 0.15,
		Parent = observatory,
	})
	createPart({
		Name = "TelescopeBarrel",
		Size = Vector3.new(2.2, 2.2, 12),
		CFrame = CFrame.new(0, 15.2, -4) * CFrame.Angles(math.rad(-25), 0, 0),
		Color = PALETTE.StarlightGold,
		Parent = observatory,
	})
	createPart({
		Name = "ObservatorySpire",
		Size = Vector3.new(0.9, 18, 0.9),
		CFrame = CFrame.new(0, 27, 0),
		Color = PALETTE.StarlightGold,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = observatory,
	})
	attachLabel(
		dome,
		"ObservatoryLabel",
		"OBSERVATORY HUB",
		Vector3.new(0, 11, 0),
		PALETTE.StarlightGold,
		UDim2.fromOffset(180, 36),
		160
	)

	-- Directional Plaza Signposts at main approaches
	local northSign = createPart({
		Name = "NorthRidgeSignpost",
		Size = Vector3.new(1.2, 4.5, 1.2),
		CFrame = CFrame.new(-15, 3.25, -48),
		Color = PALETTE.OrbitalCyan,
		Material = Enum.Material.Neon,
		Parent = hubModel,
	})
	attachLabel(
		northSign,
		"SignLabel",
		"NORTH: FROST RIDGE ->",
		Vector3.new(0, 3.0, 0),
		PALETTE.OrbitalCyan,
		UDim2.fromOffset(165, 30),
		70
	)
	local southSign = createPart({
		Name = "SouthEmberSignpost",
		Size = Vector3.new(1.2, 4.5, 1.2),
		CFrame = CFrame.new(-15, 3.25, 48),
		Color = PALETTE.EmberCoral,
		Material = Enum.Material.Neon,
		Parent = hubModel,
	})
	attachLabel(
		southSign,
		"SignLabel",
		"SOUTH: EMBER BASIN ->",
		Vector3.new(0, 3.0, 0),
		PALETTE.EmberCoral,
		UDim2.fromOffset(165, 30),
		70
	)

	-- Tool Workbench (West-North Plaza edge): FrostCracker & StarCracker pads
	local workbench = Instance.new("Model")
	workbench.Name = "ToolWorkbench"
	workbench.Parent = hubModel
	workbench:SetAttribute("HubStation", true)
	CollectionService:AddTag(workbench, Constants.TAG_HUB_STATION)

	local benchCounter = createPart({
		Name = "BenchCounter",
		Size = Vector3.new(4, 3.2, 22),
		CFrame = CFrame.new(-39, 2.1, -24),
		Color = PALETTE.DarkSlate,
		Parent = workbench,
	})
	createPart({
		Name = "BenchTop",
		Size = Vector3.new(4.2, 0.4, 22.2),
		CFrame = CFrame.new(-39, 3.9, -24),
		Color = PALETTE.AstralViolet,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = benchCounter,
	})
	attachLabel(
		benchCounter,
		"BenchLabel",
		"TOOL WORKBENCH",
		Vector3.new(0, 4.0, 0),
		PALETTE.StarlightGold,
		UDim2.fromOffset(160, 32),
		75
	)

	for _, upgradeId in ipairs(UpgradeConfig.OrderedIds) do
		local def = UpgradeConfig.ById[upgradeId]
		if def.StationZone == "Hub" then
			createUpgradePad(workbench, CFrame.new(), nil, def, true)
		end
	end

	-- Frost Lure Kiosk (East-North Plaza edge)
	local lureKiosk = Instance.new("Model")
	lureKiosk.Name = "FrostLureKiosk"
	lureKiosk.Parent = hubModel
	lureKiosk:SetAttribute("HubStation", true)
	CollectionService:AddTag(lureKiosk, Constants.TAG_HUB_STATION)

	local kioskCanopy = createPart({
		Name = "KioskBackdrop",
		Size = Vector3.new(3, 5.5, 11),
		CFrame = CFrame.new(39, 3.75, -24),
		Color = PALETTE.DarkSlate,
		Parent = lureKiosk,
	})
	attachLabel(
		kioskCanopy,
		"KioskLabel",
		"FROST LURE KIOSK",
		Vector3.new(0, 3.8, 0),
		PALETTE.OrbitalCyan,
		UDim2.fromOffset(160, 32),
		75
	)
	createHubLureStand(lureKiosk)

	-- Contracts Board Placeholder (West-South Plaza edge — Stage 4+ contracts)
	local contractsBoard = Instance.new("Model")
	contractsBoard.Name = "ContractsBoard"
	contractsBoard.Parent = hubModel
	contractsBoard:SetAttribute("HubStation", true)
	CollectionService:AddTag(contractsBoard, Constants.TAG_HUB_STATION)

	local boardPanel = createPart({
		Name = "BoardPanel",
		Size = Vector3.new(2, 6, 12),
		CFrame = CFrame.new(-39, 4.0, 24),
		Color = PALETTE.CreamWood,
		Parent = contractsBoard,
	})
	createPart({
		Name = "BoardTrim",
		Size = Vector3.new(2.2, 0.5, 12.2),
		CFrame = CFrame.new(-39, 7.1, 24),
		Color = PALETTE.StarlightGold,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = boardPanel,
	})
	attachLabel(
		boardPanel,
		"ContractsLabel",
		"CONTRACTS BOARD • Soon",
		Vector3.new(0, 4.2, 0),
		PALETTE.StarlightGold,
		UDim2.fromOffset(170, 32),
		65
	)

	-- Future Trader / Event Stall Alcove (East-South Plaza edge)
	local futureAlcove = Instance.new("Model")
	futureAlcove.Name = "FutureStallAlcove"
	futureAlcove.Parent = hubModel
	local alcovePad = createPart({
		Name = "AlcovePad",
		Size = Vector3.new(10, 0.2, 14),
		CFrame = CFrame.new(36, 1.1, 24),
		Color = PALETTE.LilacStone,
		CanCollide = false,
		Parent = futureAlcove,
	})
	attachLabel(
		alcovePad,
		"AlcoveLabel",
		"STAR TRADER STALL • Soon",
		Vector3.new(0, 3.2, 0),
		PALETTE.TextCream,
		UDim2.fromOffset(165, 30),
		55
	)
end

local function ensureCraterRouteLandmarks(craterModel: Model): ()
	local spawnNodes = craterModel:FindFirstChild("MeteorSpawnNodes")
	if spawnNodes ~= nil then
		for _, spec in ipairs(CRATER_NODE_SPECS) do
			local node = spawnNodes:FindFirstChild(spec.Name)
			if node ~= nil and node:IsA("BasePart") then
				node.CFrame = CFrame.new(spec.Position)
				node.Color = spec.Color
				node:SetAttribute("NodeIndex", spec.Index)
				node:SetAttribute("Region", spec.Region)
			end
		end
	end

	local existingLandmarks = craterModel:FindFirstChild("RouteLandmarks")
	if existingLandmarks ~= nil then
		return
	end

	local landmarks = Instance.new("Folder")
	landmarks.Name = "RouteLandmarks"
	landmarks.Parent = craterModel

	-- South Route: Approach bridge from Plaza + Ember Basin Floor Path
	createPart({
		Name = "EmberBasinApproach",
		Size = Vector3.new(24, 1, 14),
		CFrame = CFrame.new(0, 0.5, 61),
		Color = PALETTE.PromenadeStone,
		Parent = landmarks,
	})
	createPart({
		Name = "EmberBasinPath",
		Size = Vector3.new(12, 0.16, 44),
		CFrame = CFrame.new(0, 1.02, 92),
		Color = PALETTE.EmberCoral,
		Transparency = 0.35,
		CanCollide = false,
		Parent = landmarks,
	})
	local emberMarker = createPart({
		Name = "EmberRouteMarker",
		Size = Vector3.new(1.4, 4.5, 1.4),
		CFrame = CFrame.new(-10, 3.25, 66),
		Color = PALETTE.EmberCoral,
		Material = Enum.Material.Neon,
		Parent = landmarks,
	})
	attachLabel(
		emberMarker,
		"RouteLabel",
		"EMBER BASIN",
		Vector3.new(0, 3.0, 0),
		PALETTE.EmberCoral,
		UDim2.fromOffset(145, 30),
		70
	)

	-- North Route: Elevated icy Frost Ridge platform, Plaza ramp, West/East side ramps & Crystal Spires
	createPart({
		Name = "FrostRidgePlatform",
		Size = Vector3.new(84, 2, 80),
		CFrame = CFrame.new(0, 1.0, -108),
		Color = PALETTE.FrostIce,
		Parent = landmarks,
	})

	local ramp = Instance.new("WedgePart")
	ramp.Name = "FrostRidgeRamp"
	ramp.Size = Vector3.new(24, 1.0, 14)
	ramp.CFrame = CFrame.new(0, 1.5, -61) * CFrame.Angles(0, math.rad(180), 0)
	ramp.Color = PALETTE.OrbitalCyan
	ramp.Material = Enum.Material.SmoothPlastic
	ramp.Anchored = true
	ramp.CanCollide = true
	ramp.Parent = landmarks

	local westRamp = Instance.new("WedgePart")
	westRamp.Name = "FrostRidgeWestRamp"
	westRamp.Size = Vector3.new(14, 1.0, 6)
	westRamp.CFrame = CFrame.new(-45, 1.5, -88) * CFrame.Angles(0, math.rad(90), 0)
	westRamp.Color = PALETTE.OrbitalCyan
	westRamp.Material = Enum.Material.SmoothPlastic
	westRamp.Anchored = true
	westRamp.CanCollide = true
	westRamp.Parent = landmarks

	local eastRamp = Instance.new("WedgePart")
	eastRamp.Name = "FrostRidgeEastRamp"
	eastRamp.Size = Vector3.new(14, 1.0, 6)
	eastRamp.CFrame = CFrame.new(45, 1.5, -88) * CFrame.Angles(0, math.rad(-90), 0)
	eastRamp.Color = PALETTE.OrbitalCyan
	eastRamp.Material = Enum.Material.SmoothPlastic
	eastRamp.Anchored = true
	eastRamp.CanCollide = true
	eastRamp.Parent = landmarks

	for idx, xPos in ipairs({ -36, 36 }) do
		createPart({
			Name = "FrostSpire_" .. tostring(idx),
			Size = Vector3.new(2.6, 6.5, 2.6),
			CFrame = CFrame.new(xPos, 5.2, -108) * CFrame.Angles(0.08, math.rad(idx * 35), if xPos < 0 then -0.12 else 0.12),
			Color = PALETTE.OrbitalCyan,
			Material = Enum.Material.Neon,
			Transparency = 0.2,
			Parent = landmarks,
		})
	end

	local frostMarker = createPart({
		Name = "FrostRouteMarker",
		Size = Vector3.new(1.4, 4.5, 1.4),
		CFrame = CFrame.new(-14, 3.25, -66),
		Color = PALETTE.OrbitalCyan,
		Material = Enum.Material.Neon,
		Parent = landmarks,
	})
	attachLabel(
		frostMarker,
		"RouteLabel",
		"FROST RIDGE",
		Vector3.new(0, 3.0, 0),
		PALETTE.OrbitalCyan,
		UDim2.fromOffset(145, 30),
		75
	)

	-- Future Stage 6 Astral Shelf overlook north of Frost Ridge
	local astralShelf = createPart({
		Name = "AstralShelfReserve",
		Size = Vector3.new(46, 2, 24),
		CFrame = CFrame.new(0, 1.0, -162),
		Color = PALETTE.AstralViolet,
		Transparency = 0.35,
		Parent = landmarks,
	})
	attachLabel(
		astralShelf,
		"ShelfLabel",
		"ASTRAL SHELF • Future",
		Vector3.new(0, 3.5, 0),
		PALETTE.AstralViolet,
		UDim2.fromOffset(165, 30),
		85
	)
end

local function buildCentralCrater(root: Folder): ()
	local craterModel = Instance.new("Model")
	craterModel.Name = "CentralCrater"
	craterModel.Parent = root

	local floor = createPart({
		Name = "CraterFloor",
		Size = Vector3.new(84, 1, 80),
		CFrame = CFrame.new(0, 0.5, 108),
		Color = PALETTE.CraterFloor,
		Material = Enum.Material.SmoothPlastic,
		Parent = craterModel,
	})
	craterModel.PrimaryPart = floor

	local bridgesFolder = Instance.new("Folder")
	bridgesFolder.Name = "Bridges"
	bridgesFolder.Parent = craterModel

	for _, bridgeSpec in ipairs(BRIDGE_SPECS) do
		createPart({
			Name = "Bridge_Plot_" .. tostring(bridgeSpec.PlotId),
			Size = Vector3.new(6, 1, 20),
			CFrame = CFrame.new(bridgeSpec.Position),
			Color = PALETTE.CreamWood,
			Parent = bridgesFolder,
		})
	end

	-- 8 wild Meteor Spawn Nodes inside Meteor Grounds (EmberBasin 1..3 & 7, FrostRidge 4..6 & 8)
	local spawnNodes = Instance.new("Folder")
	spawnNodes.Name = "MeteorSpawnNodes"
	spawnNodes.Parent = craterModel

	for _, spec in ipairs(CRATER_NODE_SPECS) do
		local node = createPart({
			Name = spec.Name,
			Size = Vector3.new(3.2, 0.25, 3.2),
			CFrame = CFrame.new(spec.Position),
			Color = spec.Color,
			Material = Enum.Material.Neon,
			Transparency = 0.65,
			CanCollide = false,
			Parent = spawnNodes,
		})
		node:SetAttribute("NodeIndex", spec.Index)
		node:SetAttribute("Region", spec.Region)
		CollectionService:AddTag(node, Constants.TAG_METEOR_NODE)
	end

	ensureCraterRouteLandmarks(craterModel)

	-- 6 Starter Meteor Nodes right outside each plot gate (separate from wild TAG_METEOR_NODE pool)
	local starterNodes = Instance.new("Folder")
	starterNodes.Name = "StarterMeteorNodes"
	starterNodes.Parent = craterModel

	for _, starterSpec in ipairs(STARTER_NODE_SPECS) do
		local sNode = createPart({
			Name = "StarterNode_Plot_" .. tostring(starterSpec.PlotId),
			Size = Vector3.new(3.5, 0.25, 3.5),
			CFrame = CFrame.new(starterSpec.Position),
			Color = PALETTE.StarlightGold,
			Material = Enum.Material.Neon,
			Transparency = 0.5,
			CanCollide = false,
			Parent = starterNodes,
		})
		sNode:SetAttribute("PlotId", starterSpec.PlotId)
		sNode:SetAttribute("IsStarterNode", true)
	end
end

local function buildPlot(plotsFolder: Folder, plotId: number, origin: Vector3): Model
	local plotModel = Instance.new("Model")
	plotModel.Name = "Plot_" .. tostring(plotId)
	plotModel:SetAttribute("PlotId", plotId)
	plotModel.Parent = plotsFolder
	CollectionService:AddTag(plotModel, Constants.TAG_PLOT)

	-- -Z local faces toward central avenue/plaza at X = 0
	local plotFrame = CFrame.lookAt(origin, Vector3.new(0, origin.Y, origin.Z))

	local plotBase = createPart({
		Name = "PlotBase",
		Size = Vector3.new(76, 1, 68),
		CFrame = plotFrame,
		Color = PALETTE.MeadowMint,
		Parent = plotModel,
	})
	plotModel.PrimaryPart = plotBase

	-- 16-stud unobstructed central MainAisle from gate to upgrade deck
	createPart({
		Name = "MainAisle",
		Size = Vector3.new(16, 0.14, 54),
		CFrame = plotFrame * CFrame.new(0, 0.56, -7),
		Color = PALETTE.CreamWood,
		CanCollide = false,
		Parent = plotModel,
	})

	local spawnPart = Instance.new("SpawnLocation")
	spawnPart.Name = "SpawnPoint"
	spawnPart.Size = Vector3.new(6, 0.4, 6)
	spawnPart.CFrame = plotFrame * CFrame.new(0, 0.7, -24)
	spawnPart.Color = PALETTE.OrbitalCyan
	spawnPart.Material = Enum.Material.SmoothPlastic
	spawnPart.Anchored = true
	spawnPart.CanCollide = false
	spawnPart.Transparency = 0.4
	spawnPart.Enabled = false
	spawnPart.Duration = 0
	spawnPart.Parent = plotModel

	local archModel = Instance.new("Model")
	archModel.Name = "RanchArch"
	archModel.Parent = plotModel

	createPart({
		Name = "LeftPillar",
		Size = Vector3.new(2.4, 10, 2.4),
		CFrame = plotFrame * CFrame.new(-10, 5.5, -32),
		Color = PALETTE.CreamWood,
		Parent = archModel,
	})
	createPart({
		Name = "RightPillar",
		Size = Vector3.new(2.4, 10, 2.4),
		CFrame = plotFrame * CFrame.new(10, 5.5, -32),
		Color = PALETTE.CreamWood,
		Parent = archModel,
	})
	local header = createPart({
		Name = "Header",
		Size = Vector3.new(23, 2, 2.6),
		CFrame = plotFrame * CFrame.new(0, 11.2, -32),
		Color = PALETTE.CreamWood,
		Parent = archModel,
	})
	createPart({
		Name = "ArchNeonTrim",
		Size = Vector3.new(21, 0.5, 2.8),
		CFrame = plotFrame * CFrame.new(0, 10.3, -32),
		Color = PALETTE.LockedSlate,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = archModel,
	})
	attachLabel(
		header,
		"OwnerSign",
		string.format("Ranch Plot %d (Open)", plotId),
		Vector3.new(0, 2.8, 0),
		PALETTE.StarlightGold,
		UDim2.fromOffset(160, 34),
		65
	)

	-- Back Upgrade Deck holding Ranch Upgrade Pads away from main aisle
	createPart({
		Name = "UpgradeDeck",
		Size = Vector3.new(68, 0.25, 12),
		CFrame = plotFrame * CFrame.new(0, 0.62, 27),
		Color = PALETTE.PromenadeStone,
		Parent = plotModel,
	})

	-- SellStand near gate right wing (off 16-stud main aisle)
	local sellStand = createPart({
		Name = "SellStand",
		Size = Vector3.new(6, 3.2, 4),
		CFrame = plotFrame * CFrame.new(22, 2.1, -24),
		Color = PALETTE.DarkSlate,
		Parent = plotModel,
	})
	createPart({
		Name = "SellTop",
		Size = Vector3.new(6.2, 0.4, 4.2),
		CFrame = plotFrame * CFrame.new(22, 3.9, -24),
		Color = PALETTE.StarlightGold,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = sellStand,
	})
	sellStand:SetAttribute("PlotId", plotId)
	CollectionService:AddTag(sellStand, Constants.TAG_SELL_STAND)
	attachLabel(sellStand, "SellLabel", "Sell Critters", Vector3.new(0, 3.4, 0), PALETTE.StarlightGold)

	-- Left Wing: Incubators grouped off main aisle
	local incubatorsFolder = Instance.new("Folder")
	incubatorsFolder.Name = "Incubators"
	incubatorsFolder.Parent = plotModel

	local incubatorSpecs = {
		{ SlotId = "Incubator_1", LocalZ = -12, Unlocked = true, Label = "Incubator #1" },
		{ SlotId = "Incubator_2", LocalZ = 4, Unlocked = false, Label = "Incubator #2 (Locked)" },
	}
	for _, spec in ipairs(incubatorSpecs) do
		local pad = createPart({
			Name = spec.SlotId,
			Size = Vector3.new(0.8, 7, 7),
			CFrame = (plotFrame * CFrame.new(-23, 0.9, spec.LocalZ)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = if spec.Unlocked then PALETTE.OrbitalCyan else PALETTE.LockedSlate,
			Material = if spec.Unlocked then Enum.Material.Neon else Enum.Material.SmoothPlastic,
			Shape = Enum.PartType.Cylinder,
			Transparency = if spec.Unlocked then 0.1 else 0.45,
			Parent = incubatorsFolder,
		})
		pad:SetAttribute("PlotId", plotId)
		pad:SetAttribute("SlotId", spec.SlotId)
		pad:SetAttribute("UnlockedByDefault", spec.Unlocked)
		CollectionService:AddTag(pad, Constants.TAG_INCUBATOR_SLOT)
		attachLabel(pad, "SlotLabel", spec.Label, Vector3.new(0, 2.6, 0), PALETTE.OrbitalCyan)
	end

	-- Right Wing: Spacious Habitat Pen (Pen_1..Pen_5 + expansion alcove) visible from gate
	local penModel = Instance.new("Model")
	penModel.Name = "HabitatPen"
	penModel.Parent = plotModel

	createPart({
		Name = "PenFloor",
		Size = Vector3.new(26, 0.3, 34),
		CFrame = plotFrame * CFrame.new(24, 0.65, 2),
		Color = PALETTE.PenGrass,
		Parent = penModel,
	})

	local fenceSegments = {
		{ Size = Vector3.new(26, 2.2, 0.8), Offset = Vector3.new(24, 1.6, 19) },
		{ Size = Vector3.new(0.8, 2.2, 34), Offset = Vector3.new(37, 1.6, 2) },
		{ Size = Vector3.new(26, 2.2, 0.8), Offset = Vector3.new(24, 1.6, -15) },
		{ Size = Vector3.new(0.8, 2.2, 11), Offset = Vector3.new(11, 1.6, -9.5) },
		{ Size = Vector3.new(0.8, 2.2, 11), Offset = Vector3.new(11, 1.6, 13.5) },
	}
	for i, seg in ipairs(fenceSegments) do
		createPart({
			Name = "Fence_" .. tostring(i),
			Size = seg.Size,
			CFrame = plotFrame * CFrame.new(seg.Offset),
			Color = PALETTE.CreamWood,
			Parent = penModel,
		})
	end

	local penSlotsFolder = Instance.new("Folder")
	penSlotsFolder.Name = "PenSlots"
	penSlotsFolder.Parent = penModel

	for _, spec in ipairs(PEN_SLOT_SPECS) do
		createPenSlotPad(penSlotsFolder, plotFrame, plotId, spec)
	end

	-- Ranch UpgradeBoard (StationZone == "Ranch" upgrades only; tools live on Hub Tool Workbench)
	local upgradeBoard = Instance.new("Folder")
	upgradeBoard.Name = "UpgradeBoard"
	upgradeBoard.Parent = plotModel

	for _, upgradeId in ipairs(UpgradeConfig.OrderedIds) do
		local def = UpgradeConfig.ById[upgradeId]
		if def.StationZone == "Ranch" then
			createUpgradePad(upgradeBoard, plotFrame, plotId, def, false)
		end
	end

	return plotModel
end

function GreyboxBuilder.ValidateHierarchy(root: Instance?): (boolean, string)
	local rootPath = Constants.GREYBOX_ROOT_NAME
	if root == nil or not root:IsA("Folder") then
		return failAt(rootPath, "expected Folder")
	end
	if not CollectionService:HasTag(root, Constants.TAG_GREYBOX_ROOT) then
		return failAt(rootPath, "missing tag " .. Constants.TAG_GREYBOX_ROOT)
	end
	if root:GetAttribute("GreyboxVersion") ~= Constants.GREYBOX_VERSION then
		return failAt(rootPath, "GreyboxVersion attribute mismatch")
	end

	-- Central Hub contract
	local hubPath = rootPath .. "/CentralHub"
	local hub = root:FindFirstChild("CentralHub")
	if hub == nil or not hub:IsA("Model") then
		return failAt(hubPath, "expected Model")
	end
	local plazaFloor = hub:FindFirstChild("PlazaFloor")
	if plazaFloor == nil or not plazaFloor:IsA("BasePart") then
		return failAt(hubPath .. "/PlazaFloor", "expected BasePart")
	end
	if hub.PrimaryPart ~= plazaFloor then
		return failAt(hubPath, "PrimaryPart must be PlazaFloor")
	end
	local arrivalPad = hub:FindFirstChild("HubArrivalPad")
	if arrivalPad == nil or not arrivalPad:IsA("BasePart") then
		return failAt(hubPath .. "/HubArrivalPad", "expected BasePart")
	end
	local observatory = hub:FindFirstChild("Observatory")
	if observatory == nil or not observatory:IsA("Model") then
		return failAt(hubPath .. "/Observatory", "expected Model")
	end
	local workbenchPath = hubPath .. "/ToolWorkbench"
	local workbench = hub:FindFirstChild("ToolWorkbench")
	if workbench == nil or not workbench:IsA("Model") then
		return failAt(workbenchPath, "expected Model")
	end
	for _, upgradeId in ipairs(UpgradeConfig.OrderedIds) do
		local def = UpgradeConfig.ById[upgradeId]
		if def.StationZone == "Hub" then
			local padName = "UpgradePad_" .. upgradeId
			local padPath = workbenchPath .. "/" .. padName
			local pad = workbench:FindFirstChild(padName)
			if pad == nil or not pad:IsA("BasePart") then
				return failAt(padPath, "expected BasePart")
			end
			if not CollectionService:HasTag(pad, Constants.TAG_UPGRADE_PAD) then
				return failAt(padPath, "missing tag " .. Constants.TAG_UPGRADE_PAD)
			end
			if not CollectionService:HasTag(pad, Constants.TAG_HUB_STATION) then
				return failAt(padPath, "missing tag " .. Constants.TAG_HUB_STATION)
			end
			if pad:GetAttribute("UpgradeId") ~= upgradeId then
				return failAt(padPath, "UpgradeId must equal " .. upgradeId)
			end
			if pad:GetAttribute("HubStation") ~= true then
				return failAt(padPath, "HubStation attribute must equal true")
			end
		end
	end

	local kioskPath = hubPath .. "/FrostLureKiosk"
	local lureKiosk = hub:FindFirstChild("FrostLureKiosk")
	if lureKiosk == nil or not lureKiosk:IsA("Model") then
		return failAt(kioskPath, "expected Model")
	end
	local lureStandPath = kioskPath .. "/LureStand"
	local lureStand = lureKiosk:FindFirstChild("LureStand")
	if lureStand == nil or not lureStand:IsA("BasePart") then
		return failAt(lureStandPath, "expected BasePart")
	end
	if not CollectionService:HasTag(lureStand, Constants.TAG_LURE_STAND) then
		return failAt(lureStandPath, "missing tag " .. Constants.TAG_LURE_STAND)
	end
	if not CollectionService:HasTag(lureStand, Constants.TAG_HUB_STATION) then
		return failAt(lureStandPath, "missing tag " .. Constants.TAG_HUB_STATION)
	end
	if lureStand:GetAttribute("HubStation") ~= true then
		return failAt(lureStandPath, "HubStation attribute must equal true")
	end

	local contractsBoard = hub:FindFirstChild("ContractsBoard")
	if contractsBoard == nil or not contractsBoard:IsA("Model") then
		return failAt(hubPath .. "/ContractsBoard", "expected Model")
	end

	-- Central Crater (Meteor Grounds) contract
	local craterPath = rootPath .. "/CentralCrater"
	local crater = root:FindFirstChild("CentralCrater")
	if crater == nil or not crater:IsA("Model") then
		return failAt(craterPath, "expected Model")
	end

	local craterFloor = crater:FindFirstChild("CraterFloor")
	if craterFloor == nil or not craterFloor:IsA("BasePart") then
		return failAt(craterPath .. "/CraterFloor", "expected BasePart")
	end
	if crater.PrimaryPart ~= craterFloor then
		return failAt(craterPath, "PrimaryPart must be CraterFloor")
	end

	local landmarksPath = craterPath .. "/RouteLandmarks"
	local landmarks = crater:FindFirstChild("RouteLandmarks")
	if landmarks == nil or not landmarks:IsA("Folder") then
		return failAt(landmarksPath, "expected Folder")
	end
	for _, landmarkName in ipairs({ "EmberBasinPath", "FrostRidgePlatform", "FrostRidgeRamp" }) do
		if landmarks:FindFirstChild(landmarkName) == nil then
			return failAt(landmarksPath .. "/" .. landmarkName, "missing route landmark")
		end
	end

	local bridgesPath = craterPath .. "/Bridges"
	local bridges = crater:FindFirstChild("Bridges")
	if bridges == nil or not bridges:IsA("Folder") then
		return failAt(bridgesPath, "expected Folder")
	end
	for plotId = 1, Constants.MAX_PLOTS_ALPHA do
		local bridgeName = "Bridge_Plot_" .. tostring(plotId)
		local bridge = bridges:FindFirstChild(bridgeName)
		if bridge == nil or not bridge:IsA("BasePart") then
			return failAt(bridgesPath .. "/" .. bridgeName, "expected BasePart")
		end
	end

	local meteorNodesPath = craterPath .. "/MeteorSpawnNodes"
	local meteorNodes = crater:FindFirstChild("MeteorSpawnNodes")
	if meteorNodes == nil or not meteorNodes:IsA("Folder") then
		return failAt(meteorNodesPath, "expected Folder")
	end
	for i = 1, Constants.WILD_METEOR_NODE_COUNT do
		local nodeName = "MeteorNode_" .. tostring(i)
		local nodePath = meteorNodesPath .. "/" .. nodeName
		local node = meteorNodes:FindFirstChild(nodeName)
		if node == nil or not node:IsA("BasePart") then
			return failAt(nodePath, "expected BasePart")
		end
		if not CollectionService:HasTag(node, Constants.TAG_METEOR_NODE) then
			return failAt(nodePath, "missing tag " .. Constants.TAG_METEOR_NODE)
		end
		if node:GetAttribute("NodeIndex") ~= i then
			return failAt(nodePath, string.format("NodeIndex must equal %d", i))
		end
		if node:GetAttribute("IsStarterNode") == true then
			return failAt(nodePath, "wild meteor node must not have IsStarterNode=true")
		end
	end

	local starterNodesPath = craterPath .. "/StarterMeteorNodes"
	local starterNodes = crater:FindFirstChild("StarterMeteorNodes")
	if starterNodes == nil or not starterNodes:IsA("Folder") then
		return failAt(starterNodesPath, "expected Folder")
	end
	for plotId = 1, Constants.MAX_PLOTS_ALPHA do
		local sName = "StarterNode_Plot_" .. tostring(plotId)
		local sPath = starterNodesPath .. "/" .. sName
		local sNode = starterNodes:FindFirstChild(sName)
		if sNode == nil or not sNode:IsA("BasePart") then
			return failAt(sPath, "expected BasePart")
		end
		if CollectionService:HasTag(sNode, Constants.TAG_METEOR_NODE) then
			return failAt(sPath, "starter node must not carry wild tag " .. Constants.TAG_METEOR_NODE)
		end
		if sNode:GetAttribute("PlotId") ~= plotId then
			return failAt(sPath, string.format("PlotId must equal %d", plotId))
		end
		if sNode:GetAttribute("IsStarterNode") ~= true then
			return failAt(sPath, "IsStarterNode attribute must equal true")
		end
	end

	-- 6-Plot Ranch contract
	local plotsPath = rootPath .. "/Plots"
	local plotsFolder = root:FindFirstChild("Plots")
	if plotsFolder == nil or not plotsFolder:IsA("Folder") then
		return failAt(plotsPath, "expected Folder")
	end

	for plotId = 1, Constants.MAX_PLOTS_ALPHA do
		local plotName = "Plot_" .. tostring(plotId)
		local plotPath = plotsPath .. "/" .. plotName
		local plot = plotsFolder:FindFirstChild(plotName)
		if plot == nil or not plot:IsA("Model") then
			return failAt(plotPath, "expected Model")
		end
		if not CollectionService:HasTag(plot, Constants.TAG_PLOT) then
			return failAt(plotPath, "missing tag " .. Constants.TAG_PLOT)
		end
		if plot:GetAttribute("PlotId") ~= plotId then
			return failAt(plotPath, string.format("PlotId must equal %d", plotId))
		end

		local plotBase = plot:FindFirstChild("PlotBase")
		if plotBase == nil or not plotBase:IsA("BasePart") then
			return failAt(plotPath .. "/PlotBase", "expected BasePart")
		end
		if plot.PrimaryPart ~= plotBase then
			return failAt(plotPath, "PrimaryPart must be PlotBase")
		end

		local mainAisle = plot:FindFirstChild("MainAisle")
		if mainAisle == nil or not mainAisle:IsA("BasePart") then
			return failAt(plotPath .. "/MainAisle", "expected BasePart")
		end

		local spawnPoint = plot:FindFirstChild("SpawnPoint")
		if spawnPoint == nil or not spawnPoint:IsA("SpawnLocation") then
			return failAt(plotPath .. "/SpawnPoint", "expected SpawnLocation")
		end

		local archPath = plotPath .. "/RanchArch"
		local arch = plot:FindFirstChild("RanchArch")
		if arch == nil or not arch:IsA("Model") then
			return failAt(archPath, "expected Model")
		end
		local header = arch:FindFirstChild("Header")
		if header == nil or not header:IsA("BasePart") then
			return failAt(archPath .. "/Header", "expected BasePart")
		end
		local ownerSign = header:FindFirstChild("OwnerSign")
		if ownerSign == nil or not ownerSign:IsA("BillboardGui") then
			return failAt(archPath .. "/Header/OwnerSign", "expected BillboardGui")
		end
		local trim = arch:FindFirstChild("ArchNeonTrim")
		if trim == nil or not trim:IsA("BasePart") then
			return failAt(archPath .. "/ArchNeonTrim", "expected BasePart")
		end

		local sellPath = plotPath .. "/SellStand"
		local sellStand = plot:FindFirstChild("SellStand")
		if sellStand == nil or not sellStand:IsA("BasePart") then
			return failAt(sellPath, "expected BasePart")
		end
		if not CollectionService:HasTag(sellStand, Constants.TAG_SELL_STAND) then
			return failAt(sellPath, "missing tag " .. Constants.TAG_SELL_STAND)
		end
		if sellStand:GetAttribute("PlotId") ~= plotId then
			return failAt(sellPath, string.format("PlotId must equal %d", plotId))
		end

		local incubatorsPath = plotPath .. "/Incubators"
		local incubators = plot:FindFirstChild("Incubators")
		if incubators == nil or not incubators:IsA("Folder") then
			return failAt(incubatorsPath, "expected Folder")
		end
		for idx, slotId in ipairs({ "Incubator_1", "Incubator_2" }) do
			local slotPath = incubatorsPath .. "/" .. slotId
			local slot = incubators:FindFirstChild(slotId)
			if slot == nil or not slot:IsA("BasePart") then
				return failAt(slotPath, "expected BasePart")
			end
			if not CollectionService:HasTag(slot, Constants.TAG_INCUBATOR_SLOT) then
				return failAt(slotPath, "missing tag " .. Constants.TAG_INCUBATOR_SLOT)
			end
			if slot:GetAttribute("PlotId") ~= plotId then
				return failAt(slotPath, string.format("PlotId must equal %d", plotId))
			end
			if slot:GetAttribute("SlotId") ~= slotId then
				return failAt(slotPath, "SlotId must equal " .. slotId)
			end
			if slot:GetAttribute("UnlockedByDefault") ~= (idx == 1) then
				return failAt(slotPath, "UnlockedByDefault mismatch")
			end
		end

		local penPath = plotPath .. "/HabitatPen"
		local pen = plot:FindFirstChild("HabitatPen")
		if pen == nil or not pen:IsA("Model") then
			return failAt(penPath, "expected Model")
		end
		local penFloor = pen:FindFirstChild("PenFloor")
		if penFloor == nil or not penFloor:IsA("BasePart") then
			return failAt(penPath .. "/PenFloor", "expected BasePart")
		end
		local penSlotsPath = penPath .. "/PenSlots"
		local penSlots = pen:FindFirstChild("PenSlots")
		if penSlots == nil or not penSlots:IsA("Folder") then
			return failAt(penSlotsPath, "expected Folder")
		end
		for idx, slotId in ipairs({ "Pen_1", "Pen_2", "Pen_3", "Pen_4", "Pen_5" }) do
			local slotPath = penSlotsPath .. "/" .. slotId
			local slot = penSlots:FindFirstChild(slotId)
			if slot == nil or not slot:IsA("BasePart") then
				return failAt(slotPath, "expected BasePart")
			end
			if not CollectionService:HasTag(slot, Constants.TAG_PEN_SLOT) then
				return failAt(slotPath, "missing tag " .. Constants.TAG_PEN_SLOT)
			end
			if slot:GetAttribute("PlotId") ~= plotId then
				return failAt(slotPath, string.format("PlotId must equal %d", plotId))
			end
			if slot:GetAttribute("SlotId") ~= slotId then
				return failAt(slotPath, "SlotId must equal " .. slotId)
			end
			if slot:GetAttribute("UnlockedByDefault") ~= (idx == 1) then
				return failAt(slotPath, "UnlockedByDefault mismatch")
			end
		end

		local upgradeBoardPath = plotPath .. "/UpgradeBoard"
		local upgradeBoard = plot:FindFirstChild("UpgradeBoard")
		if upgradeBoard == nil or not upgradeBoard:IsA("Folder") then
			return failAt(upgradeBoardPath, "expected Folder")
		end
		for _, upgradeId in ipairs(UpgradeConfig.OrderedIds) do
			local def = UpgradeConfig.ById[upgradeId]
			if def.StationZone == "Ranch" then
				local padName = "UpgradePad_" .. upgradeId
				local padPath = upgradeBoardPath .. "/" .. padName
				local pad = upgradeBoard:FindFirstChild(padName)
				if pad == nil or not pad:IsA("BasePart") then
					return failAt(padPath, "expected BasePart")
				end
				if not CollectionService:HasTag(pad, Constants.TAG_UPGRADE_PAD) then
					return failAt(padPath, "missing tag " .. Constants.TAG_UPGRADE_PAD)
				end
				if pad:GetAttribute("PlotId") ~= plotId then
					return failAt(padPath, string.format("PlotId must equal %d", plotId))
				end
				if pad:GetAttribute("UpgradeId") ~= upgradeId then
					return failAt(padPath, "UpgradeId must equal " .. upgradeId)
				end
			end
		end
	end

	return true, "Valid"
end

function GreyboxBuilder.Generate(options: GenerateOptions?): (boolean, string, Folder?)
	local opts = options or {}
	local targetParent: Instance = opts.Parent or workspace
	local confirmReplace = opts.ConfirmReplace == true

	local existing = targetParent:FindFirstChild(Constants.GREYBOX_ROOT_NAME)
	if existing ~= nil then
		if not isOwnedGreyboxFolder(existing) then
			-- Never destroy an untagged folder or non-Folder Studio object sharing this name.
			return false, "UnownedCollision: " .. existing:GetFullName(), nil
		end
		if not confirmReplace then
			return false, "ExistingPresent", existing :: Folder
		end
	end

	-- Build and validate the entire candidate off-tree before replacing the existing owned root.
	local candidateRoot = Instance.new("Folder")
	candidateRoot.Name = Constants.GREYBOX_ROOT_NAME
	candidateRoot:SetAttribute("GreyboxVersion", Constants.GREYBOX_VERSION)
	CollectionService:AddTag(candidateRoot, Constants.TAG_GREYBOX_ROOT)

	buildCentralHub(candidateRoot)
	buildCentralCrater(candidateRoot)

	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = candidateRoot

	for plotId = 1, Constants.MAX_PLOTS_ALPHA do
		buildPlot(plotsFolder, plotId, PLOT_ORIGINS[plotId])
	end

	local valid, reason = GreyboxBuilder.ValidateHierarchy(candidateRoot)
	if not valid then
		candidateRoot:Destroy()
		return false, "CandidateValidationFailed: " .. reason, nil
	end

	if existing ~= nil then
		existing:Destroy()
	end
	candidateRoot.Parent = targetParent

	return true, "Created", candidateRoot
end

function GreyboxBuilder.EnsureCurrentVersionDetails(root: Folder): number
	local added = 0

	local crater = root:FindFirstChild("CentralCrater")
	if crater ~= nil and crater:IsA("Model") then
		ensureCraterRouteLandmarks(crater)
	end

	local hub = root:FindFirstChild("CentralHub")
	if hub ~= nil and hub:IsA("Model") then
		local workbench = hub:FindFirstChild("ToolWorkbench")
		if workbench ~= nil and workbench:IsA("Model") then
			for _, upgradeId in ipairs(UpgradeConfig.OrderedIds) do
				local def = UpgradeConfig.ById[upgradeId]
				if def.StationZone == "Hub" then
					local padName = "UpgradePad_" .. def.Id
					if workbench:FindFirstChild(padName) == nil then
						createUpgradePad(workbench, CFrame.new(), nil, def, true)
						added += 1
					end
				end
			end
		end
		local lureKiosk = hub:FindFirstChild("FrostLureKiosk")
		if lureKiosk ~= nil and lureKiosk:IsA("Model") and lureKiosk:FindFirstChild("LureStand") == nil then
			createHubLureStand(lureKiosk)
			added += 1
		end
	end

	local plotsFolder = root:FindFirstChild("Plots")
	if plotsFolder == nil or not plotsFolder:IsA("Folder") then
		return added
	end

	for plotId = 1, Constants.MAX_PLOTS_ALPHA do
		local plotModel = plotsFolder:FindFirstChild("Plot_" .. tostring(plotId))
		if plotModel ~= nil and plotModel:IsA("Model") then
			local plotBase = plotModel:FindFirstChild("PlotBase")
			if plotBase ~= nil and plotBase:IsA("BasePart") then
				local pen = plotModel:FindFirstChild("HabitatPen")
				local penSlots = if pen then pen:FindFirstChild("PenSlots") else nil
				if penSlots ~= nil and penSlots:IsA("Folder") then
					for _, spec in ipairs(PEN_SLOT_SPECS) do
						if penSlots:FindFirstChild(spec.SlotId) == nil then
							createPenSlotPad(penSlots, plotBase.CFrame, plotId, spec)
							added += 1
						end
					end
				end

				local upgradeBoard = plotModel:FindFirstChild("UpgradeBoard")
				if upgradeBoard ~= nil and upgradeBoard:IsA("Folder") then
					for _, upgradeId in ipairs(UpgradeConfig.OrderedIds) do
						local def = UpgradeConfig.ById[upgradeId]
						if def.StationZone == "Ranch" then
							local padName = "UpgradePad_" .. def.Id
							if upgradeBoard:FindFirstChild(padName) == nil then
								createUpgradePad(upgradeBoard, plotBase.CFrame, plotId, def, false)
								added += 1
							end
						end
					end
				end
			end
		end
	end

	return added
end

GreyboxBuilder.EnsureMissingUpgradePads = GreyboxBuilder.EnsureCurrentVersionDetails
GreyboxBuilder.EnsureStage2CLayout = GreyboxBuilder.EnsureCurrentVersionDetails

function GreyboxBuilder.EnsureExists(parent: Instance?): (boolean, string, Folder?)
	local targetParent: Instance = parent or workspace
	local existing = targetParent:FindFirstChild(Constants.GREYBOX_ROOT_NAME)
	if existing ~= nil then
		if not isOwnedGreyboxFolder(existing) then
			return false, "ConflictingUnownedRoot: " .. existing:GetFullName(), nil
		end
		if existing:GetAttribute("GreyboxVersion") == Constants.GREYBOX_VERSION then
			GreyboxBuilder.EnsureCurrentVersionDetails(existing :: Folder)
		end
		local valid, reason = GreyboxBuilder.ValidateHierarchy(existing)
		if valid then
			return true, "ReusedExisting", existing :: Folder
		end
		-- Preserve invalid or prior-version authored root untouched rather than silently destroying Studio edits.
		return false, "InvalidExistingRoot: " .. reason, existing :: Folder
	end

	return GreyboxBuilder.Generate({ ConfirmReplace = false, Parent = targetParent })
end

return GreyboxBuilder
