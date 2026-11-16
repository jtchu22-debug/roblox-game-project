--!strict
--[[
	Module: GreyboxBuilder
	Purpose: Idempotently creates and validates the tagged Stage 1 Starfall Ranch greybox map in Workspace.
	Connections: Called on server Init by PlotService.EnsureExists(workspace) and manually via tools/studio/GenerateGreyboxMap.luau.
	How to Test in Studio: Press Play (F5) to auto-generate StarfallGreyboxRoot or run tools/studio/GenerateGreyboxMap.luau in Command Bar.
]]

local CollectionService = game:GetService("CollectionService")

local Shared = script.Parent.Parent
local Constants = require(Shared:WaitForChild("Constants"))
local ConfigFolder = Shared:WaitForChild("Config")
local UpgradeConfig = require(ConfigFolder:WaitForChild("UpgradeConfig"))
local FormatUtil = require(script.Parent:WaitForChild("FormatUtil"))

export type GenerateOptions = {
	ConfirmReplace: boolean?,
	Parent: Instance?,
}

local PALETTE = {
	MeadowMint = Color3.fromRGB(95, 215, 145),
	LilacStone = Color3.fromRGB(120, 105, 155),
	CraterFloor = Color3.fromRGB(85, 75, 115),
	CreamWood = Color3.fromRGB(245, 235, 220),
	OrbitalCyan = Color3.fromRGB(65, 210, 255),
	StarlightGold = Color3.fromRGB(255, 205, 45),
	LockedSlate = Color3.fromRGB(140, 145, 165),
	PenGrass = Color3.fromRGB(115, 228, 160),
	DarkSlate = Color3.fromRGB(45, 42, 62),
}

local GreyboxBuilder = {}

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

local function attachLabel(adornee: BasePart, name: string, text: string, studsOffset: Vector3, accentColor: Color3?): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = UDim2.fromOffset(180, 44)
	gui.StudsOffset = studsOffset
	gui.AlwaysOnTop = false
	gui.MaxDistance = 90
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
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = label

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	return gui
end

local function buildCentralCrater(root: Folder): ()
	local craterModel = Instance.new("Model")
	craterModel.Name = "CentralCrater"
	craterModel.Parent = root

	local floor = createPart({
		Name = "CraterFloor",
		Size = Vector3.new(1, 90, 90),
		CFrame = CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = PALETTE.CraterFloor,
		Material = Enum.Material.SmoothPlastic,
		Shape = Enum.PartType.Cylinder,
		Parent = craterModel,
	})
	craterModel.PrimaryPart = floor

	createPart({
		Name = "CenterBeaconRing",
		Size = Vector3.new(0.4, 14, 14),
		CFrame = CFrame.new(0, 0.9, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = PALETTE.OrbitalCyan,
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
		Parent = craterModel,
	})

	-- Rim stones spaced around the crater perimeter (leaving clear bridge openings on -X and +X)
	local rimFolder = Instance.new("Folder")
	rimFolder.Name = "RimStones"
	rimFolder.Parent = craterModel

	local rimAnglesDeg = { 35, 65, 115, 145, 215, 245, 295, 325 }
	for i, deg in ipairs(rimAnglesDeg) do
		local rad = math.rad(deg)
		local pos = Vector3.new(math.cos(rad) * 43, 2.2, math.sin(rad) * 43)
		createPart({
			Name = "RimStone_" .. tostring(i),
			Size = Vector3.new(7, 3.6, 5),
			CFrame = CFrame.lookAt(pos, Vector3.new(0, 2.2, 0)),
			Color = PALETTE.LilacStone,
			Parent = rimFolder,
		})
	end

	-- Bridges connecting Crater edge (|X| = 45) to Plot_1 (-50) and Plot_2 (+50)
	local bridgesFolder = Instance.new("Folder")
	bridgesFolder.Name = "Bridges"
	bridgesFolder.Parent = craterModel

	for i, xCenter in ipairs({ -47.5, 47.5 }) do
		createPart({
			Name = "Bridge_Plot_" .. tostring(i),
			Size = Vector3.new(8, 0.8, 12),
			CFrame = CFrame.new(xCenter, 0.5, 0),
			Color = PALETTE.CreamWood,
			Parent = bridgesFolder,
		})
	end

	-- 6 wild Meteor Spawn Nodes inside Crater
	local spawnNodes = Instance.new("Folder")
	spawnNodes.Name = "MeteorSpawnNodes"
	spawnNodes.Parent = craterModel

	for i = 1, 6 do
		local angle = math.rad((i - 1) * 60 + 30)
		local nodePos = Vector3.new(math.cos(angle) * 22, 1.0, math.sin(angle) * 22)
		local node = createPart({
			Name = "MeteorNode_" .. tostring(i),
			Size = Vector3.new(3, 0.25, 3),
			CFrame = CFrame.new(nodePos),
			Color = PALETTE.LilacStone,
			Material = Enum.Material.Neon,
			Transparency = 0.65,
			CanCollide = false,
			Parent = spawnNodes,
		})
		node:SetAttribute("NodeIndex", i)
		CollectionService:AddTag(node, Constants.TAG_METEOR_NODE)
	end

	-- 2 Starter Meteor Nodes directly in each plot's front gate sightline
	local starterNodes = Instance.new("Folder")
	starterNodes.Name = "StarterMeteorNodes"
	starterNodes.Parent = craterModel

	local starterPositions = {
		[1] = Vector3.new(-35, 1.0, 0),
		[2] = Vector3.new(35, 1.0, 0),
	}
	for plotId, pos in pairs(starterPositions) do
		local sNode = createPart({
			Name = "StarterNode_Plot_" .. tostring(plotId),
			Size = Vector3.new(3.5, 0.25, 3.5),
			CFrame = CFrame.new(pos),
			Color = PALETTE.StarlightGold,
			Material = Enum.Material.Neon,
			Transparency = 0.5,
			CanCollide = false,
			Parent = starterNodes,
		})
		sNode:SetAttribute("PlotId", plotId)
		sNode:SetAttribute("IsStarterNode", true)
	end
end

local function buildPlot(plotsFolder: Folder, plotId: number, origin: Vector3): Model
	local plotModel = Instance.new("Model")
	plotModel.Name = "Plot_" .. tostring(plotId)
	plotModel:SetAttribute("PlotId", plotId)
	plotModel.Parent = plotsFolder
	CollectionService:AddTag(plotModel, Constants.TAG_PLOT)

	-- Forward (-Z) looks directly toward the Central Crater at (0, 0.5, 0)
	local plotFrame = CFrame.lookAt(origin, Vector3.new(0, origin.Y, 0))

	local plotBase = createPart({
		Name = "PlotBase",
		Size = Vector3.new(50, 1, 50),
		CFrame = plotFrame,
		Color = PALETTE.MeadowMint,
		Parent = plotModel,
	})
	plotModel.PrimaryPart = plotBase

	-- Player SpawnPoint inside the front gate facing the Crater
	local spawnPart = Instance.new("SpawnLocation")
	spawnPart.Name = "SpawnPoint"
	spawnPart.Size = Vector3.new(6, 0.4, 6)
	spawnPart.CFrame = plotFrame * CFrame.new(0, 0.7, -15)
	spawnPart.Color = PALETTE.OrbitalCyan
	spawnPart.Material = Enum.Material.SmoothPlastic
	spawnPart.Anchored = true
	spawnPart.CanCollide = false
	spawnPart.Transparency = 0.4
	spawnPart.Enabled = false -- Assigned dynamically by PlotService
	spawnPart.Duration = 0
	spawnPart.Parent = plotModel

	-- Front Gate Arch
	local archModel = Instance.new("Model")
	archModel.Name = "RanchArch"
	archModel.Parent = plotModel

	createPart({
		Name = "LeftPillar",
		Size = Vector3.new(2, 10, 2),
		CFrame = plotFrame * CFrame.new(-7, 5.5, -23),
		Color = PALETTE.CreamWood,
		Parent = archModel,
	})
	createPart({
		Name = "RightPillar",
		Size = Vector3.new(2, 10, 2),
		CFrame = plotFrame * CFrame.new(7, 5.5, -23),
		Color = PALETTE.CreamWood,
		Parent = archModel,
	})
	local header = createPart({
		Name = "Header",
		Size = Vector3.new(17, 2, 2.4),
		CFrame = plotFrame * CFrame.new(0, 11.2, -23),
		Color = PALETTE.CreamWood,
		Parent = archModel,
	})
	createPart({
		Name = "ArchNeonTrim",
		Size = Vector3.new(15, 0.5, 2.6),
		CFrame = plotFrame * CFrame.new(0, 10.3, -23),
		Color = PALETTE.LockedSlate,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = archModel,
	})
	attachLabel(header, "OwnerSign", string.format("Ranch Plot %d (Open)", plotId), Vector3.new(0, 2.8, 0), PALETTE.StarlightGold)

	-- Gate Sell Stand
	local sellStand = createPart({
		Name = "SellStand",
		Size = Vector3.new(6, 3.2, 4),
		CFrame = plotFrame * CFrame.new(15, 2.1, -18),
		Color = PALETTE.DarkSlate,
		Parent = plotModel,
	})
	createPart({
		Name = "SellTop",
		Size = Vector3.new(6.2, 0.4, 4.2),
		CFrame = plotFrame * CFrame.new(15, 3.9, -18),
		Color = PALETTE.StarlightGold,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = sellStand,
	})
	sellStand:SetAttribute("PlotId", plotId)
	CollectionService:AddTag(sellStand, Constants.TAG_SELL_STAND)
	attachLabel(sellStand, "SellLabel", "Sell Critters", Vector3.new(0, 3.4, 0), PALETTE.StarlightGold)

	-- Incubator Pads (Left Wing)
	local incubatorsFolder = Instance.new("Folder")
	incubatorsFolder.Name = "Incubators"
	incubatorsFolder.Parent = plotModel

	local incubatorSpecs = {
		{ SlotId = "Incubator_1", LocalZ = -5, Unlocked = true, Label = "Incubator #1" },
		{ SlotId = "Incubator_2", LocalZ = 7, Unlocked = false, Label = "Incubator #2 (Locked)" },
	}
	for _, spec in ipairs(incubatorSpecs) do
		local pad = createPart({
			Name = spec.SlotId,
			Size = Vector3.new(0.8, 7, 7),
			CFrame = (plotFrame * CFrame.new(-15, 0.9, spec.LocalZ)) * CFrame.Angles(0, 0, math.rad(90)),
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

	-- Habitat Pen (Right/Center Wing)
	local penModel = Instance.new("Model")
	penModel.Name = "HabitatPen"
	penModel.Parent = plotModel

	createPart({
		Name = "PenFloor",
		Size = Vector3.new(22, 0.3, 20),
		CFrame = plotFrame * CFrame.new(8, 0.65, 5),
		Color = PALETTE.PenGrass,
		Parent = penModel,
	})

	-- Low pen fence rails (leaving a clean front doorway)
	local fenceSegments = {
		{ Size = Vector3.new(22, 2.2, 0.8), Offset = Vector3.new(8, 1.6, 15) }, -- Back fence
		{ Size = Vector3.new(0.8, 2.2, 20), Offset = Vector3.new(-3, 1.6, 5) }, -- Left fence
		{ Size = Vector3.new(0.8, 2.2, 20), Offset = Vector3.new(19, 1.6, 5) }, -- Right fence
		{ Size = Vector3.new(7, 2.2, 0.8), Offset = Vector3.new(0.5, 1.6, -5) }, -- Front left post
		{ Size = Vector3.new(7, 2.2, 0.8), Offset = Vector3.new(15.5, 1.6, -5) }, -- Front right post
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

	local penSpecs = {
		{ SlotId = "Pen_1", Offset = Vector3.new(8, 0.95, 2), Unlocked = true, Label = "Pen Slot #1" },
		{ SlotId = "Pen_2", Offset = Vector3.new(2, 0.95, 10), Unlocked = false, Label = "Pen Slot #2 (Locked)" },
		{ SlotId = "Pen_3", Offset = Vector3.new(14, 0.95, 10), Unlocked = false, Label = "Pen Slot #3 (Locked)" },
	}
	for _, spec in ipairs(penSpecs) do
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
	end

	-- Upgrade Pads (Back Deck)
	local upgradeBoard = Instance.new("Folder")
	upgradeBoard.Name = "UpgradeBoard"
	upgradeBoard.Parent = plotModel

	for _, upgradeId in ipairs(UpgradeConfig.OrderedIds) do
		local def = UpgradeConfig.ById[upgradeId]
		local localX = -18 + (def.Order - 1) * 8
		local pad = createPart({
			Name = "UpgradePad_" .. def.Id,
			Size = Vector3.new(0.6, 5.5, 5.5),
			CFrame = (plotFrame * CFrame.new(localX, 0.9, 19)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = PALETTE.MeadowMint,
			Material = Enum.Material.Neon,
			Shape = Enum.PartType.Cylinder,
			CanCollide = false,
			Parent = upgradeBoard,
		})
		pad:SetAttribute("PlotId", plotId)
		pad:SetAttribute("UpgradeId", def.Id)
		CollectionService:AddTag(pad, Constants.TAG_UPGRADE_PAD)
		attachLabel(
			pad,
			"UpgradeLabel",
			string.format("%s (%s Coins)", def.DisplayName, FormatUtil.FormatCoins(def.Cost)),
			Vector3.new(0, 2.8, 0),
			PALETTE.MeadowMint
		)
	end

	return plotModel
end

function GreyboxBuilder.ValidateHierarchy(root: Instance?): (boolean, string)
	if root == nil or not root:IsA("Folder") then
		return false, "Missing StarfallGreyboxRoot Folder"
	end
	if not CollectionService:HasTag(root, Constants.TAG_GREYBOX_ROOT) then
		return false, "Root missing StarfallGreyboxRoot tag"
	end

	local crater = root:FindFirstChild("CentralCrater")
	if crater == nil then
		return false, "Missing CentralCrater"
	end

	local meteorNodes = crater:FindFirstChild("MeteorSpawnNodes")
	if meteorNodes == nil then
		return false, "Missing MeteorSpawnNodes"
	end
	for i = 1, 6 do
		local node = meteorNodes:FindFirstChild("MeteorNode_" .. tostring(i))
		if node == nil or not CollectionService:HasTag(node, Constants.TAG_METEOR_NODE) then
			return false, "Missing or untagged MeteorNode_" .. tostring(i)
		end
	end

	local starterNodes = crater:FindFirstChild("StarterMeteorNodes")
	if starterNodes == nil then
		return false, "Missing StarterMeteorNodes"
	end

	local plotsFolder = root:FindFirstChild("Plots")
	if plotsFolder == nil then
		return false, "Missing Plots folder"
	end

	for plotId = 1, Constants.MAX_PLOTS_PROTOTYPE do
		local plot = plotsFolder:FindFirstChild("Plot_" .. tostring(plotId))
		if plot == nil or not plot:IsA("Model") or not CollectionService:HasTag(plot, Constants.TAG_PLOT) then
			return false, "Missing or untagged Plot_" .. tostring(plotId)
		end
		if starterNodes:FindFirstChild("StarterNode_Plot_" .. tostring(plotId)) == nil then
			return false, "Missing StarterNode_Plot_" .. tostring(plotId)
		end
		for _, req in ipairs({ "PlotBase", "SpawnPoint", "RanchArch", "SellStand", "Incubators", "HabitatPen", "UpgradeBoard" }) do
			if plot:FindFirstChild(req) == nil then
				return false, string.format("Plot_%d missing %s", plotId, req)
			end
		end

		local incubators = plot:FindFirstChild("Incubators") :: Instance
		for _, slotId in ipairs({ "Incubator_1", "Incubator_2" }) do
			local slot = incubators:FindFirstChild(slotId)
			if slot == nil or not CollectionService:HasTag(slot, Constants.TAG_INCUBATOR_SLOT) then
				return false, string.format("Plot_%d missing %s", plotId, slotId)
			end
		end

		local penSlots = (plot:FindFirstChild("HabitatPen") :: Instance):FindFirstChild("PenSlots")
		if penSlots == nil then
			return false, string.format("Plot_%d missing PenSlots", plotId)
		end
		for _, slotId in ipairs({ "Pen_1", "Pen_2", "Pen_3" }) do
			local slot = penSlots:FindFirstChild(slotId)
			if slot == nil or not CollectionService:HasTag(slot, Constants.TAG_PEN_SLOT) then
				return false, string.format("Plot_%d missing %s", plotId, slotId)
			end
		end

		local upgradeBoard = plot:FindFirstChild("UpgradeBoard") :: Instance
		for _, upgradeId in ipairs(UpgradeConfig.OrderedIds) do
			local pad = upgradeBoard:FindFirstChild("UpgradePad_" .. upgradeId)
			if pad == nil or not CollectionService:HasTag(pad, Constants.TAG_UPGRADE_PAD) then
				return false, string.format("Plot_%d missing UpgradePad_%s", plotId, upgradeId)
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
		if not confirmReplace then
			local existingFolder = if existing:IsA("Folder") then existing else nil
			return false, "ExistingPresent", existingFolder
		end
		-- Only remove our own tagged root; never touch Baseplate or unrelated user Studio assets.
		existing:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = Constants.GREYBOX_ROOT_NAME
	root:SetAttribute("GreyboxVersion", Constants.GREYBOX_VERSION)
	CollectionService:AddTag(root, Constants.TAG_GREYBOX_ROOT)
	root.Parent = targetParent

	buildCentralCrater(root)

	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = root

	local plotOrigins = {
		[1] = Vector3.new(-75, 0.5, 0),
		[2] = Vector3.new(75, 0.5, 0),
	}
	for plotId = 1, Constants.MAX_PLOTS_PROTOTYPE do
		buildPlot(plotsFolder, plotId, plotOrigins[plotId])
	end

	local valid, reason = GreyboxBuilder.ValidateHierarchy(root)
	assert(valid, "Generated greybox map failed self-validation: " .. reason)

	return true, "Created", root
end

function GreyboxBuilder.EnsureExists(parent: Instance?): Folder
	local targetParent: Instance = parent or workspace
	local existing = targetParent:FindFirstChild(Constants.GREYBOX_ROOT_NAME)
	if existing ~= nil and existing:IsA("Folder") then
		local valid, reason = GreyboxBuilder.ValidateHierarchy(existing)
		if valid then
			return existing
		end
		warn("[GreyboxBuilder] Existing greybox map invalid (" .. reason .. "); rebuilding root.")
		local ok, status, rebuilt = GreyboxBuilder.Generate({ ConfirmReplace = true, Parent = targetParent })
		assert(ok and rebuilt ~= nil, "Failed rebuilding greybox map: " .. status)
		return rebuilt :: Folder
	end

	local ok, status, created = GreyboxBuilder.Generate({ ConfirmReplace = false, Parent = targetParent })
	assert(ok and created ~= nil, "Failed creating greybox map: " .. status)
	return created :: Folder
end

return GreyboxBuilder
