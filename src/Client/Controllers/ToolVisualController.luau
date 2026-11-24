--!strict
--[[
	Controller: ToolVisualController
	Purpose: Manages Observatory Tool Workbench locked/owned Cracker previews and held Cracker
	         models during meteor cracks (including R15/R6 grip attachment, first/third-person
	         visibility, Reduced Motion support, and cancel/death/respawn cleanup).
	Connections: Requires SoundController, UIController, Constants, Types, ToolConfig, UpgradeConfig.
	             Invoked by CrackController during meteor rescue interactions.
	How to Test in Studio: Press Play (F5) for automated self-tests, inspect ToolWorkbench in CentralHub,
	                       and crack Starter/Ember/Frost/Astral meteors in first- and third-person.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ControllersFolder = script.Parent
local SoundController = require(ControllersFolder:WaitForChild("SoundController"))
local UIController = require(ControllersFolder:WaitForChild("UIController"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Types = require(Shared:WaitForChild("Types"))
local ConfigFolder = Shared:WaitForChild("Config")
local ToolConfig = require(ConfigFolder:WaitForChild("ToolConfig"))
local UpgradeConfig = require(ConfigFolder:WaitForChild("UpgradeConfig"))

type BuildOptions = {
	Owned: boolean?,
	Anchored: boolean?,
	CastShadow: boolean?,
}

type WorkbenchEntry = {
	ToolId: Types.CrackerToolId,
	Owned: boolean,
	AssetSource: string,
	PartCount: number,
	BaseCFrame: CFrame,
	Pedestal: Part,
	ToolModel: Model,
	StatusLabel: TextLabel,
}

local VISUALS_FOLDER_NAME = "StarfallClientVisuals"
local WORKBENCH_FOLDER_NAME = "StarfallWorkbenchDisplays"
local HELD_MODEL_NAME = "StarfallHeldCracker"
local HELD_MOTOR_NAME = "StarfallCrackerGripMotor"

local LOCKED_BODY_COLOR = Color3.fromRGB(82, 86, 108)
local LOCKED_ACCENT_COLOR = Color3.fromRGB(110, 118, 142)
local LOCKED_TRANSPARENCY = 0.48

local PALETTE = {
	PanelDark = Color3.fromRGB(24, 22, 38),
	TextCream = Color3.fromRGB(245, 240, 232),
	TextMuted = Color3.fromRGB(178, 182, 204),
	MeadowMint = Color3.fromRGB(95, 215, 145),
	StarlightGold = Color3.fromRGB(255, 205, 45),
	PedestalDark = Color3.fromRGB(34, 32, 52),
	PedestalOwnedTrim = Color3.fromRGB(85, 195, 185),
	PedestalLockedTrim = Color3.fromRGB(72, 74, 96),
}

local ToolVisualController = {
	Name = "ToolVisualController",
}

local workbenchDisplays: { [Types.CrackerToolId]: WorkbenchEntry } = {}
local workbenchFolder: Folder? = nil
local workbenchHeartbeatConn: RBXScriptConnection? = nil
local ownerStateConnBound = false
local wasReducedMotion = false

local equipToken = 0
local activeHeldModel: Model? = nil
local activeHeldMotor: Motor6D? = nil
local activeHeldToolId: Types.CrackerToolId? = nil
local activeHeldParts: { BasePart } = {}
local heldRenderConn: RBXScriptConnection? = nil
local swingPulseUntil = 0
local swingPulseStart = 0

local charRemovingConn: RBXScriptConnection? = nil
local charAddedConn: RBXScriptConnection? = nil
local humanoidDiedConn: RBXScriptConnection? = nil

local function getVisualsRoot(): Folder
	local existing = workspace:FindFirstChild(VISUALS_FOLDER_NAME)
	if existing ~= nil and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = VISUALS_FOLDER_NAME
	folder.Parent = workspace
	return folder
end

local function makeProceduralPart(
	parent: Model,
	name: string,
	size: Vector3,
	offset: CFrame,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	if shape ~= nil then
		part.Shape = shape
	end
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = offset
	part.Parent = parent
	return part
end

local function buildProceduralCracker(toolId: Types.CrackerToolId): Model
	local model = Instance.new("Model")
	model.Name = toolId

	-- Coordinate convention matches Blender FBX output in Roblox space:
	-- Grip centered at (0,0,0), Handle extends along +Y, striking Head faces -Z.
	local grip = makeProceduralPart(model, "Grip", Vector3.new(0.28, 0.92, 0.28), CFrame.new(0, 0, 0), Enum.PartType.Cylinder)
	grip.CFrame = CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.rad(90))
	grip.Size = Vector3.new(0.92, 0.28, 0.28)

	local handle = makeProceduralPart(model, "Handle", Vector3.new(1.12, 0.22, 0.22), CFrame.new(0, 0.98, 0) * CFrame.Angles(0, 0, math.rad(90)), Enum.PartType.Cylinder)
	local band = makeProceduralPart(model, "Band", Vector3.new(0.28, 0.34, 0.34), CFrame.new(0, 1.58, 0) * CFrame.Angles(0, 0, math.rad(90)), Enum.PartType.Cylinder)

	if toolId == "FrostCracker" then
		local head = makeProceduralPart(model, "Head", Vector3.new(0.44, 0.44, 0.96), CFrame.new(0, 2.00, -0.22), nil)
		local accent = makeProceduralPart(model, "Accent", Vector3.new(0.20, 0.28, 0.62), CFrame.new(0, 2.00, -0.44), nil)
		accent.Size = Vector3.new(0.20, 0.28, 0.62)
		local _ = head
	elseif toolId == "AstralCracker" then
		local head = makeProceduralPart(model, "Head", Vector3.new(0.24, 0.96, 0.96), CFrame.new(0, 2.18, -0.06) * CFrame.Angles(0, math.rad(90), 0), Enum.PartType.Cylinder)
		local accent = makeProceduralPart(model, "Accent", Vector3.new(0.36, 0.36, 0.36), CFrame.new(0, 2.18, -0.06), Enum.PartType.Ball)
		local _ = head
		local _2 = accent
	else
		local head = makeProceduralPart(model, "Head", Vector3.new(1.12, 0.64, 0.64), CFrame.new(0, 2.04, -0.04) * CFrame.Angles(0, math.rad(90), 0), Enum.PartType.Cylinder)
		local accent = makeProceduralPart(model, "Accent", Vector3.new(0.68, 0.24, 0.34), CFrame.new(0, 2.04, -0.04), nil)
		local _ = head
		local _2 = accent
	end

	model.PrimaryPart = grip
	return model
end

local function applyCrackerStyling(model: Model, toolId: Types.CrackerToolId, options: BuildOptions?): ()
	local def = ToolConfig.ById[toolId]
	assert(def ~= nil, "Unknown CrackerToolId: " .. tostring(toolId))

	local owned = if options ~= nil and options.Owned ~= nil then options.Owned else true
	local anchored = if options ~= nil and options.Anchored ~= nil then options.Anchored else true
	local castShadow = if options ~= nil and options.CastShadow ~= nil then options.CastShadow else owned

	local toStrip: { Instance } = {}
	local partCount = 0
	local gripPart: BasePart? = nil

	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("SurfaceAppearance") or desc:IsA("LuaSourceContainer") then
			table.insert(toStrip, desc)
		elseif desc:IsA("BasePart") then
			partCount += 1
			desc.Anchored = anchored
			desc.CanCollide = false
			desc.CanQuery = false
			desc.CanTouch = false
			desc.Massless = not anchored
			desc.Transparency = if owned then 0 else LOCKED_TRANSPARENCY

			if desc.Name == "Grip" then
				gripPart = desc
				desc.Color = if owned then def.GripColor else LOCKED_BODY_COLOR
				desc.Material = Enum.Material.SmoothPlastic
				desc.CastShadow = castShadow and owned
			elseif desc.Name == "Handle" then
				desc.Color = if owned then def.HandleColor else LOCKED_BODY_COLOR
				desc.Material = if owned then def.HandleMaterial else Enum.Material.SmoothPlastic
				desc.CastShadow = castShadow and owned
			elseif desc.Name == "Band" then
				desc.Color = if owned then def.BandColor else LOCKED_BODY_COLOR
				desc.Material = if owned then def.BandMaterial else Enum.Material.SmoothPlastic
				desc.CastShadow = castShadow and owned
			elseif desc.Name == "Head" then
				desc.Color = if owned then def.HeadColor else LOCKED_BODY_COLOR
				desc.Material = if owned then def.HeadMaterial else Enum.Material.SmoothPlastic
				desc.CastShadow = castShadow and owned
			elseif desc.Name == "Accent" then
				desc.Color = if owned then def.AccentColor else LOCKED_ACCENT_COLOR
				desc.Material = if owned then def.AccentMaterial else Enum.Material.SmoothPlastic
				desc.CastShadow = false
			else
				desc.Color = if owned then def.HandleColor else LOCKED_BODY_COLOR
				desc.Material = Enum.Material.SmoothPlastic
				desc.CastShadow = false
			end
		end
	end

	for _, item in ipairs(toStrip) do
		item:Destroy()
	end

	assert(partCount <= ToolConfig.MAX_TOOL_PARTS, string.format("%s exceeds %d BasePart budget (%d)", toolId, ToolConfig.MAX_TOOL_PARTS, partCount))
	if gripPart ~= nil then
		model.PrimaryPart = gripPart
	end
end

local function isValidCrackerTemplate(template: Instance?): (boolean, string?)
	if template == nil or not template:IsA("Model") then
		return false, "template is not a Model"
	end

	local gripPart = template:FindFirstChild("Grip", true)
	if gripPart == nil or not gripPart:IsA("BasePart") then
		return false, "missing Grip BasePart"
	end

	local partCount = 0
	for _, desc in ipairs(template:GetDescendants()) do
		if desc:IsA("BasePart") then
			partCount += 1
		end
	end
	if partCount == 0 or partCount > ToolConfig.MAX_TOOL_PARTS then
		return false, string.format("part count %d outside 1..%d", partCount, ToolConfig.MAX_TOOL_PARTS)
	end

	return true, nil
end

function ToolVisualController.BuildCrackerModel(toolId: Types.CrackerToolId, options: BuildOptions?): (Model, string, number)
	local templatesRoot = ReplicatedStorage:FindFirstChild(Constants.ASSET_TEMPLATES_FOLDER_NAME)
	local toolsFolder = if templatesRoot ~= nil then templatesRoot:FindFirstChild("Tools") else nil
	local template = if toolsFolder ~= nil then toolsFolder:FindFirstChild(toolId) else nil

	local model: Model
	local sourceTag: string
	if template ~= nil then
		local okTemplate, badReason = isValidCrackerTemplate(template)
		if okTemplate then
			model = (template :: Model):Clone()
			model.Name = toolId
			sourceTag = "MeshTemplate"
		else
			warn(string.format(
				"[ToolVisualController] Rejected malformed tool template '%s': %s. Using procedural fallback.",
				toolId,
				tostring(badReason)
			))
			model = buildProceduralCracker(toolId)
			sourceTag = "ProceduralFallback"
		end
	else
		model = buildProceduralCracker(toolId)
		sourceTag = "ProceduralFallback"
	end

	applyCrackerStyling(model, toolId, options)

	local partCount = 0
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			partCount += 1
		end
	end

	model:SetAttribute("CrackerToolId", toolId)
	model:SetAttribute("AssetSource", sourceTag)
	return model, sourceTag, partCount
end

local function findWorkbenchCounterTop(): BasePart?
	local root = workspace:FindFirstChild(Constants.GREYBOX_ROOT_NAME)
	if root == nil then
		return nil
	end
	local hub = root:FindFirstChild("CentralHub")
	local workbench = if hub ~= nil then hub:FindFirstChild("ToolWorkbench") else nil
	local counter = if workbench ~= nil then workbench:FindFirstChild("BenchCounter") else nil
	local benchTop = if counter ~= nil then counter:FindFirstChild("BenchTop") else nil
	if benchTop ~= nil and benchTop:IsA("BasePart") then
		return benchTop
	end
	return nil
end

local function formatWorkbenchStatusText(toolId: Types.CrackerToolId, owned: boolean): (string, Color3)
	local def = ToolConfig.ById[toolId]
	local shortName = if toolId == "StarterCracker"
		then "STARTER"
		elseif toolId == "FrostCracker" then "FROST"
		else "ASTRAL"
	if owned then
		return string.format("%s • OWNED", shortName), PALETTE.MeadowMint
	end
	local upgradeDef = if def.RequiredUpgradeId ~= nil then UpgradeConfig.ById[def.RequiredUpgradeId] else nil
	local costText = if upgradeDef ~= nil then string.format(" (%dc)", upgradeDef.Cost) else ""
	return string.format("%s • LOCKED%s", shortName, costText), PALETTE.TextMuted
end

local function createWorkbenchDisplayEntry(
	parentFolder: Folder,
	benchTop: BasePart,
	toolId: Types.CrackerToolId,
	owned: boolean
): WorkbenchEntry
	local def = ToolConfig.ById[toolId]
	local benchTopY = benchTop.Position.Y + benchTop.Size.Y * 0.5
	local displayX = benchTop.Position.X + 0.35

	local pedestal = Instance.new("Part")
	pedestal.Name = toolId .. "_Pedestal"
	pedestal.Shape = Enum.PartType.Cylinder
	pedestal.Size = Vector3.new(0.28, 2.2, 2.2)
	pedestal.CFrame = CFrame.new(displayX, benchTopY + 0.14, def.WorkbenchZ) * CFrame.Angles(0, 0, math.rad(90))
	pedestal.Color = if owned then PALETTE.PedestalOwnedTrim else PALETTE.PedestalLockedTrim
	pedestal.Material = Enum.Material.SmoothPlastic
	pedestal.Anchored = true
	pedestal.CanCollide = false
	pedestal.CanQuery = false
	pedestal.CanTouch = false
	pedestal.Parent = parentFolder

	local baseCFrame = CFrame.new(displayX, benchTopY + 0.92, def.WorkbenchZ)
		* CFrame.Angles(0, math.rad(-55), 0)
		* CFrame.Angles(math.rad(14), 0, 0)

	local toolModel, sourceTag, partCount = ToolVisualController.BuildCrackerModel(toolId, {
		Owned = owned,
		Anchored = true,
		CastShadow = owned,
	})
	toolModel.Name = toolId .. "_WorkbenchPreview"
	toolModel:PivotTo(baseCFrame)
	toolModel.Parent = parentFolder

	local billboard = Instance.new("BillboardGui")
	billboard.Name = toolId .. "_StatusGui"
	billboard.Adornee = pedestal
	billboard.Size = UDim2.fromOffset(146, 26)
	billboard.StudsOffsetWorldSpace = Vector3.new(0.85, 0.55, 0)
	billboard.MaxDistance = 42
	billboard.AlwaysOnTop = false
	billboard.Parent = pedestal

	local pill = Instance.new("TextLabel")
	pill.Name = "StatusLabel"
	pill.Size = UDim2.fromScale(1, 1)
	pill.BackgroundColor3 = PALETTE.PanelDark
	pill.BackgroundTransparency = 0.12
	pill.Font = Enum.Font.GothamBold
	pill.TextSize = 11
	local statusText, statusColor = formatWorkbenchStatusText(toolId, owned)
	pill.Text = statusText
	pill.TextColor3 = statusColor
	pill.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = pill

	local stroke = Instance.new("UIStroke")
	stroke.Color = if owned then PALETTE.MeadowMint else PALETTE.PedestalLockedTrim
	stroke.Thickness = 1.5
	stroke.Parent = pill

	return {
		ToolId = toolId,
		Owned = owned,
		AssetSource = sourceTag,
		PartCount = partCount,
		BaseCFrame = baseCFrame,
		Pedestal = pedestal,
		ToolModel = toolModel,
		StatusLabel = pill,
	}
end

function ToolVisualController.ReconcileWorkbenchDisplays(upgrades: { [string]: boolean }?): ()
	local benchTop = findWorkbenchCounterTop()
	if benchTop == nil then
		return
	end

	local root = getVisualsRoot()
	if workbenchFolder == nil or workbenchFolder.Parent ~= root then
		local existing = root:FindFirstChild(WORKBENCH_FOLDER_NAME)
		if existing ~= nil and existing:IsA("Folder") then
			workbenchFolder = existing
		else
			local created = Instance.new("Folder")
			created.Name = WORKBENCH_FOLDER_NAME
			created.Parent = root
			workbenchFolder = created
		end
	end
	local folder = workbenchFolder :: Folder

	for _, toolId in ipairs(ToolConfig.OrderedIds) do
		local owned = ToolConfig.IsToolOwned(toolId, upgrades)
		local entry = workbenchDisplays[toolId]
		if entry == nil or entry.ToolModel.Parent == nil or entry.Pedestal.Parent == nil then
			if entry ~= nil then
				if entry.ToolModel.Parent ~= nil then
					entry.ToolModel:Destroy()
				end
				if entry.Pedestal.Parent ~= nil then
					entry.Pedestal:Destroy()
				end
			end
			workbenchDisplays[toolId] = createWorkbenchDisplayEntry(folder, benchTop, toolId, owned)
		elseif entry.Owned ~= owned then
			entry.Owned = owned
			applyCrackerStyling(entry.ToolModel, toolId, {
				Owned = owned,
				Anchored = true,
				CastShadow = owned,
			})
			entry.Pedestal.Color = if owned then PALETTE.PedestalOwnedTrim else PALETTE.PedestalLockedTrim
			local statusText, statusColor = formatWorkbenchStatusText(toolId, owned)
			entry.StatusLabel.Text = statusText
			entry.StatusLabel.TextColor3 = statusColor
			local stroke = entry.StatusLabel:FindFirstChildOfClass("UIStroke")
			if stroke ~= nil then
				stroke.Color = if owned then PALETTE.MeadowMint else PALETTE.PedestalLockedTrim
			end
			if not owned or SoundController.IsReducedMotion() then
				entry.ToolModel:PivotTo(entry.BaseCFrame)
			end
		end
	end
end

local function stepWorkbenchDisplays(): ()
	local reduced = SoundController.IsReducedMotion()
	local now = os.clock()
	for idx, toolId in ipairs(ToolConfig.OrderedIds) do
		local entry = workbenchDisplays[toolId]
		if entry ~= nil and entry.ToolModel.Parent ~= nil then
			if reduced or not entry.Owned then
				if (reduced and not wasReducedMotion) or not entry.Owned then
					entry.ToolModel:PivotTo(entry.BaseCFrame)
				end
			else
				local bobY = math.sin(now * 2.1 + idx * 1.1) * 0.12
				local yaw = math.sin(now * 1.2 + idx * 0.9) * 0.22
				entry.ToolModel:PivotTo(entry.BaseCFrame * CFrame.new(0, bobY, 0) * CFrame.Angles(0, yaw, 0))
			end
		end
	end
	wasReducedMotion = reduced
end

local function resolveCharacterHand(character: Model): (BasePart?, CFrame)
	local rightHand = character:FindFirstChild("RightHand")
	if rightHand ~= nil and rightHand:IsA("BasePart") then
		local gripAtt = rightHand:FindFirstChild("RightGripAttachment")
		local gripCf = if gripAtt ~= nil and gripAtt:IsA("Attachment")
			then gripAtt.CFrame
			else CFrame.new(0, -0.15, 0)
		return rightHand, gripCf
	end

	local rightArm = character:FindFirstChild("Right Arm")
	if rightArm ~= nil and rightArm:IsA("BasePart") then
		local gripAtt = rightArm:FindFirstChild("RightGripAttachment")
		local gripCf = if gripAtt ~= nil and gripAtt:IsA("Attachment")
			then gripAtt.CFrame
			else CFrame.new(0, -1.0, 0)
		return rightArm, gripCf
	end

	return nil, CFrame.new()
end

function ToolVisualController.ClearHeldCracker(_reason: string?, targetCharacter: Model?): ()
	equipToken += 1
	if heldRenderConn ~= nil then
		heldRenderConn:Disconnect()
		heldRenderConn = nil
	end
	if activeHeldMotor ~= nil then
		activeHeldMotor:Destroy()
		activeHeldMotor = nil
	end
	if activeHeldModel ~= nil then
		activeHeldModel:Destroy()
		activeHeldModel = nil
	end
	activeHeldToolId = nil
	table.clear(activeHeldParts)
	swingPulseUntil = 0

	local chars: { Model } = {}
	if targetCharacter ~= nil then
		table.insert(chars, targetCharacter)
	end
	local lp = Players.LocalPlayer
	if lp ~= nil and lp.Character ~= nil and lp.Character ~= targetCharacter then
		table.insert(chars, lp.Character)
	end

	for _, char in ipairs(chars) do
		local strayModel = char:FindFirstChild(HELD_MODEL_NAME)
		if strayModel ~= nil then
			strayModel:Destroy()
		end
		for _, desc in ipairs(char:GetDescendants()) do
			if desc:IsA("Motor6D") and desc.Name == HELD_MOTOR_NAME then
				desc:Destroy()
			end
		end
	end
end

function ToolVisualController.PulseCrackSwing(_intensity: number?): ()
	local now = os.clock()
	swingPulseStart = now
	swingPulseUntil = now + 0.24
end

function ToolVisualController.EquipHeldCracker(toolId: Types.CrackerToolId, customCharacter: Model?): boolean
	local lp = Players.LocalPlayer
	local character = customCharacter or (if lp ~= nil then lp.Character else nil)
	if character == nil then
		return false
	end

	local handPart, handGripCf = resolveCharacterHand(character)
	if handPart == nil then
		return false
	end

	ToolVisualController.ClearHeldCracker("Reequip", character)
	local myToken = equipToken

	local model = ToolVisualController.BuildCrackerModel(toolId, {
		Owned = true,
		Anchored = false,
		CastShadow = true,
	})
	model.Name = HELD_MODEL_NAME

	local gripPart = model.PrimaryPart or model:FindFirstChild("Grip")
	if gripPart == nil or not gripPart:IsA("BasePart") then
		model:Destroy()
		return false
	end

	local partsList: { BasePart } = {}
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = false
			desc.Massless = true
			desc.CanCollide = false
			desc.CanQuery = false
			desc.CanTouch = false
			desc.LocalTransparencyModifier = 0
			table.insert(partsList, desc)
			if desc ~= gripPart then
				local weld = Instance.new("WeldConstraint")
				weld.Name = "GripWeld_" .. desc.Name
				weld.Part0 = gripPart
				weld.Part1 = desc
				weld.Parent = desc
			end
		end
	end

	model:PivotTo(handPart.CFrame * handGripCf * ToolConfig.HELD_GRIP_OFFSET)
	model.Parent = character

	local motor = Instance.new("Motor6D")
	motor.Name = HELD_MOTOR_NAME
	motor.Part0 = handPart
	motor.Part1 = gripPart
	motor.C0 = handGripCf * ToolConfig.HELD_GRIP_OFFSET
	motor.C1 = CFrame.new()
	motor.Parent = handPart

	if myToken ~= equipToken then
		motor:Destroy()
		model:Destroy()
		return false
	end

	activeHeldModel = model
	activeHeldMotor = motor
	activeHeldToolId = toolId
	activeHeldParts = partsList

	local equipClock = os.clock()
	heldRenderConn = RunService.RenderStepped:Connect(function()
		if myToken ~= equipToken or activeHeldMotor == nil or activeHeldModel == nil or activeHeldModel.Parent == nil then
			if heldRenderConn ~= nil then
				heldRenderConn:Disconnect()
				heldRenderConn = nil
			end
			return
		end

		for _, part in ipairs(activeHeldParts) do
			if part.Parent ~= nil then
				part.LocalTransparencyModifier = 0
			end
		end

		local now = os.clock()
		local reduced = SoundController.IsReducedMotion()
		local swingAngle = 0
		if not reduced then
			if now < swingPulseUntil then
				local alpha = math.clamp((now - swingPulseStart) / 0.24, 0, 1)
				swingAngle = math.sin(alpha * math.pi) * math.rad(42)
			else
				swingAngle = math.sin((now - equipClock) * 7.5) * math.rad(16)
			end
		end

		local fpOffset = CFrame.new()
		local cam = workspace.CurrentCamera
		local head = character:FindFirstChild("Head")
		if cam ~= nil and head ~= nil and head:IsA("BasePart") then
			local camDist = (cam.CFrame.Position - head.Position).Magnitude
			if camDist < 1.8 then
				-- Pull held Cracker cleanly into the lower-right first-person view
				fpOffset = CFrame.new(-0.35, -0.55, 0.72) * CFrame.Angles(math.rad(-22), math.rad(18), 0)
			end
		end

		activeHeldMotor.C1 = fpOffset * CFrame.Angles(swingAngle, 0, 0)
	end)

	return true
end

function ToolVisualController.GetActiveHeldToolId(): Types.CrackerToolId?
	return activeHeldToolId
end

function ToolVisualController.IsHeldRenderActive(): boolean
	return heldRenderConn ~= nil
end

function ToolVisualController.GetWorkbenchDisplaySummary(): { [string]: { Owned: boolean, AssetSource: string, PartCount: number } }
	local summary: { [string]: { Owned: boolean, AssetSource: string, PartCount: number } } = {}
	for toolId, entry in pairs(workbenchDisplays) do
		summary[toolId] = {
			Owned = entry.Owned,
			AssetSource = entry.AssetSource,
			PartCount = entry.PartCount,
		}
	end
	return summary
end

local function bindCharacterCleanup(character: Model): ()
	if humanoidDiedConn ~= nil then
		humanoidDiedConn:Disconnect()
		humanoidDiedConn = nil
	end
	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum ~= nil then
		humanoidDiedConn = hum.Died:Connect(function()
			ToolVisualController.ClearHeldCracker("HumanoidDied", character)
		end)
	end
end

function ToolVisualController.Init(self: typeof(ToolVisualController)): ()
	-- Visuals attach in Start() after Greybox & UIController initialize.
end

function ToolVisualController.Start(self: typeof(ToolVisualController)): ()
	local initialState = UIController.GetLatestOwnerState()
	ToolVisualController.ReconcileWorkbenchDisplays(if initialState ~= nil then initialState.Upgrades else nil)

	if not ownerStateConnBound then
		ownerStateConnBound = true
		UIController.OnOwnerStateChanged(function(dto: Types.OwnerStateDTO)
			ToolVisualController.ReconcileWorkbenchDisplays(dto.Upgrades)
		end)
	end

	if workbenchHeartbeatConn == nil then
		workbenchHeartbeatConn = RunService.Heartbeat:Connect(stepWorkbenchDisplays)
	end

	local lp = Players.LocalPlayer
	if lp ~= nil then
		if lp.Character ~= nil then
			bindCharacterCleanup(lp.Character)
		end
		if charAddedConn == nil then
			charAddedConn = lp.CharacterAdded:Connect(function(char: Model)
				bindCharacterCleanup(char)
			end)
		end
		if charRemovingConn == nil then
			charRemovingConn = lp.CharacterRemoving:Connect(function(char: Model)
				ToolVisualController.ClearHeldCracker("CharacterRemoving", char)
			end)
		end
	end
end

function ToolVisualController.RunSelfTest(): number
	local passed = 0

	-- Suite 1: Workbench displays build all 3 Crackers (<= 8 parts) and reconcile locked/owned states
	ToolVisualController.ReconcileWorkbenchDisplays({})
	local summary0 = ToolVisualController.GetWorkbenchDisplaySummary()
	assert(summary0.StarterCracker ~= nil and summary0.StarterCracker.Owned == true, "StarterCracker Workbench preview owned by default")
	assert(summary0.FrostCracker ~= nil and summary0.FrostCracker.Owned == false, "FrostCracker Workbench preview locked initially")
	assert(summary0.AstralCracker ~= nil and summary0.AstralCracker.Owned == false, "AstralCracker Workbench preview locked initially")
	for _, toolId in ipairs(ToolConfig.OrderedIds) do
		assert(summary0[toolId].PartCount <= ToolConfig.MAX_TOOL_PARTS, toolId .. " exceeds 8 parts")
	end

	ToolVisualController.ReconcileWorkbenchDisplays({ FrostCracker = true, StarCracker = true })
	local summary1 = ToolVisualController.GetWorkbenchDisplaySummary()
	assert(summary1.FrostCracker.Owned == true and summary1.AstralCracker.Owned == true, "Workbench previews transition to Owned live")
	passed += 1

	-- Suite 2: Held Cracker equips onto mock R15 character with Motor6D, Massless, CanCollide=false, LocalTransparencyModifier=0
	local mockChar = Instance.new("Model")
	mockChar.Name = "_MockCrackerChar"
	local mockHead = Instance.new("Part")
	mockHead.Name = "Head"
	mockHead.Parent = mockChar
	local mockHand = Instance.new("Part")
	mockHand.Name = "RightHand"
	mockHand.Parent = mockChar
	local gripAtt = Instance.new("Attachment")
	gripAtt.Name = "RightGripAttachment"
	gripAtt.Parent = mockHand
	mockChar.Parent = workspace

	local equipped = ToolVisualController.EquipHeldCracker("StarterCracker", mockChar)
	assert(equipped == true and ToolVisualController.GetActiveHeldToolId() == "StarterCracker", "StarterCracker equips cleanly")
	assert(ToolVisualController.IsHeldRenderActive() == true, "Held RenderStepped active while equipped")
	local heldModel = mockChar:FindFirstChild(HELD_MODEL_NAME)
	assert(heldModel ~= nil and heldModel:IsA("Model"), "StarfallHeldCracker mounted under character")
	assert(mockHand:FindFirstChild(HELD_MOTOR_NAME) ~= nil, "Motor6D grip mounted on RightHand")
	for _, desc in ipairs((heldModel :: Model):GetDescendants()) do
		if desc:IsA("BasePart") then
			assert(desc.Massless == true and desc.CanCollide == false and desc.LocalTransparencyModifier == 0, "Held tool part flags valid")
		end
	end
	passed += 1

	-- Suite 3: Cleanup leaves zero stray models/motors and disconnects RenderStepped
	ToolVisualController.ClearHeldCracker("SelfTestCleanup", mockChar)
	assert(ToolVisualController.GetActiveHeldToolId() == nil, "Active held tool cleared")
	assert(ToolVisualController.IsHeldRenderActive() == false, "Held RenderStepped disconnected on cleanup")
	assert(mockChar:FindFirstChild(HELD_MODEL_NAME) == nil, "Held model destroyed on cleanup")
	assert(mockHand:FindFirstChild(HELD_MOTOR_NAME) == nil, "Grip Motor6D destroyed on cleanup")
	mockChar:Destroy()

	ToolVisualController.ReconcileWorkbenchDisplays({})
	passed += 1

	-- Suite 4: Malformed optional tool template falls back cleanly without interrupting startup
	local templatesRoot = ReplicatedStorage:FindFirstChild(Constants.ASSET_TEMPLATES_FOLDER_NAME)
	local createdRoot = false
	if templatesRoot == nil then
		local r = Instance.new("Folder")
		r.Name = Constants.ASSET_TEMPLATES_FOLDER_NAME
		r.Parent = ReplicatedStorage
		templatesRoot = r
		createdRoot = true
	end
	local toolsFolder = (templatesRoot :: Instance):FindFirstChild("Tools")
	local createdTools = false
	if toolsFolder == nil then
		local t = Instance.new("Folder")
		t.Name = "Tools"
		t.Parent = templatesRoot
		toolsFolder = t
		createdTools = true
	end

	local origStarter = (toolsFolder :: Instance):FindFirstChild("StarterCracker")
	if origStarter ~= nil then
		origStarter.Parent = nil
	end

	local badModel = Instance.new("Model")
	badModel.Name = "StarterCracker"
	local badGripFolder = Instance.new("Folder")
	badGripFolder.Name = "Grip"
	badGripFolder.Parent = badModel
	for idx = 1, ToolConfig.MAX_TOOL_PARTS + 1 do
		local p = Instance.new("Part")
		p.Name = "Extra_" .. tostring(idx)
		p.Parent = badModel
	end
	badModel.Parent = toolsFolder

	local okMalformed, malformedErr = pcall(function()
		local fallbackModel, sourceTag, partCount = ToolVisualController.BuildCrackerModel("StarterCracker", { Owned = true })
		assert(sourceTag == "ProceduralFallback", "Malformed template must fall back to ProceduralFallback")
		assert(partCount <= ToolConfig.MAX_TOOL_PARTS, "Fallback model must respect part budget")
		fallbackModel:Destroy()
		ToolVisualController.ReconcileWorkbenchDisplays({})
	end)

	badModel:Destroy()
	if origStarter ~= nil then
		origStarter.Parent = toolsFolder
	end
	if createdTools and toolsFolder ~= nil then
		toolsFolder:Destroy()
	end
	if createdRoot and templatesRoot ~= nil then
		templatesRoot:Destroy()
	end
	assert(okMalformed, "Malformed tool template regression failed: " .. tostring(malformedErr))
	passed += 1

	return passed
end

return ToolVisualController
