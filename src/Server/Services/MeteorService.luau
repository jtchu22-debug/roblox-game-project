--!strict
--[[
	Service: MeteorService
	Purpose: Manages Crater Meteor spawning (separate Starter vs. Wild pools), server-issued AttemptNonce
	         claim protocol, proximity/bag/readiness validation, and claim lifecycle cleanup.
	Connections: Uses GreyboxBuilder anchors, DataService, EconomyService, PlotService, and NetworkService.
	How to Test in Studio: Press Play (F5), walk into CentralCrater, press E / tap on Meteors to rescue Star-Pods!
]]

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Types = require(Shared:WaitForChild("Types"))
local ConfigFolder = Shared:WaitForChild("Config")
local MeteorConfig = require(ConfigFolder:WaitForChild("MeteorConfig"))
local EconomyMath = require(Shared:WaitForChild("Util"):WaitForChild("EconomyMath"))

local ServicesFolder = script.Parent
local AnalyticsService = require(ServicesFolder:WaitForChild("AnalyticsService"))
local DataService = require(ServicesFolder:WaitForChild("DataService"))
local EconomyService = require(ServicesFolder:WaitForChild("EconomyService"))
local NetworkService = require(ServicesFolder:WaitForChild("NetworkService"))
local PlotService = require(ServicesFolder:WaitForChild("PlotService"))

export type ActiveMeteor = {
	UID: string,
	Trait: Types.MeteorTraitId,
	NodeName: string,
	Position: Vector3,
	IsStarter: boolean,
	OwnerUserId: number?,
	PlotId: number?,
	LuredByUserId: number?,
	LuredOwnerName: string?,
	ClaimedByUserId: number?,
	SpawnedAt: number,
	Model: Model?,
}

export type ActiveClaim = {
	UserId: number,
	MeteorUID: string,
	AttemptNonce: string,
	StartedAt: number,
	Deadline: number,
}

export type PendingAstralFall = {
	NodeName: string,
	Position: Vector3,
	LandAt: number,
}

local WILD_TRAIT_WEIGHTS: { { Trait: Types.MeteorTraitId, Weight: number } } = table.freeze({
	table.freeze({ Trait = "Ember" :: Types.MeteorTraitId, Weight = 72 }),
	table.freeze({ Trait = "Frost" :: Types.MeteorTraitId, Weight = 28 }),
})

local EMBER_BASIN_NODES: { [string]: boolean } = table.freeze({
	MeteorNode_1 = true,
	MeteorNode_2 = true,
	MeteorNode_3 = true,
	MeteorNode_7 = true,
})

local FROST_ASTRAL_RIDGE_NODES: { [string]: boolean } = table.freeze({
	MeteorNode_4 = true,
	MeteorNode_5 = true,
	MeteorNode_6 = true,
	MeteorNode_8 = true,
})

local MeteorService = {
	Name = "MeteorService",
}

local serverRng = Random.new()
local wildNodes: { BasePart } = {}
local starterNodesByPlotId: { [number]: BasePart } = {}
local activeMeteorsFolder: Folder? = nil

local activeMeteors: { [string]: ActiveMeteor } = {}
local wildNodeOccupied: { [string]: string } = {}
local wildNodeCooldownUntil: { [string]: number } = {}
local starterByPlotId: { [number]: string } = {}
local luredMeteorByUserId: { [number]: string } = {}
local lastLureClockByUserId: { [number]: number } = {}
local activeClaimsByUserId: { [number]: ActiveClaim } = {}
local activeAstralUID: string? = nil
local pendingAstralFall: PendingAstralFall? = nil
local nextAstralFallAt = 0
local characterConnsByUserId: { [number]: { RBXScriptConnection } } = {}
local activeHumanoidConnsByUserId: { [number]: { RBXScriptConnection } } = {}
local lifecycleObserver: ((payload: { [string]: any }) -> ())? = nil
local beforeNavigateRegistered = false
local watcherRunning = false

local function publishMeteorLifecycle(payload: { [string]: any }): ()
	if lifecycleObserver ~= nil then
		lifecycleObserver(payload)
	end
	NetworkService.BroadcastMeteorLifecycle(payload)
end

local function isFiniteVector3(v: Vector3): boolean
	return v.X == v.X
		and math.abs(v.X) ~= math.huge
		and v.Y == v.Y
		and math.abs(v.Y) ~= math.huge
		and v.Z == v.Z
		and math.abs(v.Z) ~= math.huge
end

local function isFiniteClock(value: number): boolean
	return typeof(value) == "number" and value == value and math.abs(value) ~= math.huge and value >= 0
end

local function setMeteorPromptEnabled(meteor: ActiveMeteor, enabled: boolean): ()
	local model = meteor.Model
	if model == nil then
		return
	end
	local primary = model.PrimaryPart
	local prompt = if primary then primary:FindFirstChild("RescuePrompt") else nil
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = enabled
	end
end

local function measureMeteorWorldYBounds(model: Model, excludeBeacons: boolean?): (number, number)
	local minY = math.huge
	local maxY = -math.huge
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			if excludeBeacons and (desc.Name == "AstralBeacon" or desc.Name == "LureBeacon") then
				continue
			end
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

local function tryCloneMeteorTemplate(meteor: ActiveMeteor, traitDef: Types.MeteorTraitDefinition, yawRad: number): (Model?, BasePart?)
	local templatesRoot = ReplicatedStorage:FindFirstChild(Constants.ASSET_TEMPLATES_FOLDER_NAME)
	local meteorsFolder = if templatesRoot ~= nil then templatesRoot:FindFirstChild("Meteors") else nil
	local template = if meteorsFolder ~= nil then meteorsFolder:FindFirstChild(meteor.Trait) else nil
	if template == nil or not template:IsA("Model") then
		return nil, nil
	end

	local tmplBody = template:FindFirstChild("RockBody")
	if tmplBody == nil or not tmplBody:IsA("BasePart") then
		return nil, nil
	end

	local clone = template:Clone()
	local rockBody: BasePart? = nil
	local toStrip: { Instance } = {}
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("SurfaceAppearance") or desc:IsA("LuaSourceContainer") then
			table.insert(toStrip, desc)
		elseif desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
			desc.CanQuery = false
			desc.CanTouch = false
			if desc.Name == "RockBody" then
				rockBody = desc
				desc.Material = Enum.Material.SmoothPlastic
				desc.Color = traitDef.RockColor
				desc.CastShadow = true
			elseif desc.Name == "CoreShards" then
				desc.Material = Enum.Material.Neon
				desc.Color = traitDef.CoreColor
				desc.CastShadow = false
			elseif desc.Name == "TraitCrest" then
				desc.Material = Enum.Material.Neon
				desc.Color = traitDef.TrailColor
				desc.CastShadow = false
			else
				desc.Material = Enum.Material.SmoothPlastic
				desc.Color = traitDef.RockColor
				desc.CastShadow = false
			end
		end
	end
	for _, item in ipairs(toStrip) do
		item:Destroy()
	end
	if rockBody == nil then
		clone:Destroy()
		return nil, nil
	end

	clone.PrimaryPart = rockBody
	local targetCf = CFrame.new(meteor.Position) * CFrame.Angles(0, yawRad, 0)
	clone:PivotTo(targetCf)
	local minY = measureMeteorWorldYBounds(clone)
	if math.abs(minY - meteor.Position.Y) > 1e-4 then
		clone:PivotTo(targetCf * CFrame.new(0, meteor.Position.Y - minY, 0))
	end
	return clone, rockBody
end

local function createMeteorModel(meteor: ActiveMeteor): Model?
	local folder = activeMeteorsFolder
	if folder == nil then
		return nil
	end

	local traitDef = MeteorConfig.ById[meteor.Trait]
	local isWildFrost = meteor.Trait == "Frost" and not meteor.IsStarter
	local isWildAstral = meteor.Trait == "Astral" and not meteor.IsStarter
	local isLured = meteor.LuredByUserId ~= nil
	local yawRad = math.rad(((string.byte(meteor.UID, 1) or 0) * 37) % 360)

	local model, body = tryCloneMeteorTemplate(meteor, traitDef, yawRad)
	if model == nil or body == nil then
		local fallbackModel = Instance.new("Model")
		local basePos = meteor.Position + Vector3.new(0, if isWildAstral then 2.4 else 1.8, 0)
		local rock = Instance.new("Part")
		rock.Name = "RockBody"
		rock.Size = if isWildAstral then Vector3.new(5.2, 4.4, 5.2) else Vector3.new(3.8, 3.2, 3.8)
		rock.CFrame = CFrame.new(basePos) * CFrame.Angles(0, yawRad, 0)
		rock.Color = traitDef.RockColor
		rock.Material = Enum.Material.SmoothPlastic
		rock.Anchored = true
		rock.CanCollide = false
		rock.TopSurface = Enum.SurfaceType.Smooth
		rock.BottomSurface = Enum.SurfaceType.Smooth
		rock.Parent = fallbackModel
		fallbackModel.PrimaryPart = rock

		local core = Instance.new("Part")
		core.Name = "CoreCrystal"
		core.Size = if isWildAstral then Vector3.new(2.4, 5.4, 2.4) else Vector3.new(1.8, 3.8, 1.8)
		core.CFrame = rock.CFrame * CFrame.new(0, 0.7, 0) * CFrame.Angles(0.15, 0.4, -0.15)
		core.Color = traitDef.CoreColor
		core.Material = Enum.Material.Neon
		core.Anchored = true
		core.CanCollide = false
		core.Parent = fallbackModel

		-- Color-independent shape silhouette for accessibility
		if traitDef.ShapeStyle == "FlameCrest" then
			for _, xOff in ipairs({ -1.1, 1.1 }) do
				local crest = Instance.new("WedgePart")
				crest.Name = "FlameHorn"
				crest.Size = Vector3.new(0.8, 2.2, 1.4)
				crest.CFrame = rock.CFrame * CFrame.new(xOff, 1.8, 0) * CFrame.Angles(0, 0, if xOff < 0 then 0.25 else -0.25)
				crest.Color = traitDef.TrailColor
				crest.Material = Enum.Material.Neon
				crest.Anchored = true
				crest.CanCollide = false
				crest.Parent = fallbackModel
			end
		elseif traitDef.ShapeStyle == "IceSpikes" then
			for i = 1, 3 do
				local ang = math.rad(i * 120)
				local spike = Instance.new("Part")
				spike.Name = "IceSpike_" .. tostring(i)
				spike.Size = Vector3.new(0.9, 2.8, 0.9)
				spike.CFrame = rock.CFrame * CFrame.new(math.cos(ang) * 1.4, 1.6, math.sin(ang) * 1.4) * CFrame.Angles(math.sin(ang) * 0.4, 0, -math.cos(ang) * 0.4)
				spike.Color = traitDef.TrailColor
				spike.Material = Enum.Material.Neon
				spike.Anchored = true
				spike.CanCollide = false
				spike.Parent = fallbackModel
			end
		else
			local ring = Instance.new("Part")
			ring.Name = "AstralRing"
			ring.Shape = Enum.PartType.Cylinder
			ring.Size = if isWildAstral then Vector3.new(0.45, 7.8, 7.8) else Vector3.new(0.35, 6.2, 6.2)
			ring.CFrame = rock.CFrame * CFrame.new(0, 0.6, 0) * CFrame.Angles(0.25, 0, math.rad(90))
			ring.Color = traitDef.TrailColor
			ring.Material = Enum.Material.Neon
			ring.Transparency = 0.25
			ring.Anchored = true
			ring.CanCollide = false
			ring.Parent = fallbackModel
		end

		model = fallbackModel
		body = rock
	end

	local meteorModel = model :: Model
	local primaryBody = body :: BasePart
	meteorModel.Name = (if meteor.IsStarter then "StarterMeteor_" elseif isLured then "LuredFrost_" else "WildMeteor_")
		.. string.sub(meteor.UID, 1, 8)
	meteorModel:SetAttribute("MeteorUID", meteor.UID)
	meteorModel:SetAttribute("Trait", meteor.Trait)
	meteorModel:SetAttribute("IsStarter", meteor.IsStarter)
	meteorModel:SetAttribute("OwnerUserId", meteor.OwnerUserId or 0)
	meteorModel:SetAttribute("LuredByUserId", meteor.LuredByUserId or 0)
	CollectionService:AddTag(meteorModel, Constants.TAG_ACTIVE_METEOR)

	if isWildAstral and meteorModel:FindFirstChild("AstralBeacon") == nil then
		local beacon = Instance.new("Part")
		beacon.Name = "AstralBeacon"
		beacon.Size = Vector3.new(1.1, 32, 1.1)
		beacon.CFrame = CFrame.new(meteor.Position + Vector3.new(0, 17, 0))
		beacon.Color = traitDef.CoreColor
		beacon.Material = Enum.Material.Neon
		beacon.Transparency = 0.62
		beacon.Anchored = true
		beacon.CanCollide = false
		beacon.CanQuery = false
		beacon.CanTouch = false
		beacon.Parent = meteorModel
	end

	if isLured and meteorModel:FindFirstChild("LureBeacon") == nil then
		local lureBeacon = Instance.new("Part")
		lureBeacon.Name = "LureBeacon"
		lureBeacon.Size = Vector3.new(0.85, 30, 0.85)
		lureBeacon.CFrame = CFrame.new(meteor.Position + Vector3.new(0, 16, 0))
		lureBeacon.Color = Color3.fromRGB(65, 210, 255)
		lureBeacon.Material = Enum.Material.Neon
		lureBeacon.Transparency = 0.52
		lureBeacon.Anchored = true
		lureBeacon.CanCollide = false
		lureBeacon.CanQuery = false
		lureBeacon.CanTouch = false
		lureBeacon.Parent = meteorModel
	end

	local _, bboxSize = meteorModel:GetBoundingBox()
	local labelOffsetY = math.max(if isWildAstral then 5.2 else 3.8, bboxSize.Y * 0.5 + 1.8)
	-- Keep beacon parts out of label height calculation by clamping reasonably
	if isWildAstral or isLured then
		labelOffsetY = if isWildAstral then 5.2 else 4.2
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "MeteorLabel"
	gui.Size = if meteor.IsStarter
		then UDim2.fromOffset(110, 26)
		elseif isWildAstral then UDim2.fromOffset(130, 30)
		elseif isLured then UDim2.fromOffset(148, 28)
		elseif isWildFrost then UDim2.fromOffset(100, 24)
		else UDim2.fromOffset(96, 24)
	gui.StudsOffset = Vector3.new(0, labelOffsetY, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = if meteor.IsStarter
		then 65
		elseif isWildAstral then 95
		elseif isLured then 95
		elseif isWildFrost then 42
		else 38
	gui.Adornee = primaryBody
	gui.Parent = primaryBody

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(24, 22, 38)
	label.BackgroundTransparency = 0.2
	label.TextColor3 = if isWildAstral then traitDef.CoreColor else traitDef.TrailColor
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = if meteor.IsStarter
		then "STARTER"
		elseif isWildAstral then "ASTRAL FALL"
		elseif isLured then "YOUR FROST LURE"
		elseif isWildFrost then "FROST"
		else "EMBER"
	label.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RescuePrompt"
	prompt.ObjectText = if meteor.IsStarter
		then "Starter"
		elseif isWildAstral then "Astral"
		elseif isLured then "Frost Lure"
		elseif isWildFrost then "Frost"
		else "Ember"
	prompt.ActionText = "Crack"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Constants.PROMPT_ACTIVATION_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Enabled = true
	prompt.Parent = primaryBody

	meteorModel.Parent = folder
	return meteorModel
end

local function rollWeightedWildTrait(rng: Random): Types.MeteorTraitId
	local total = 0
	for _, entry in ipairs(WILD_TRAIT_WEIGHTS) do
		total += entry.Weight
	end
	local roll = rng:NextNumber() * total
	local cumulative = 0
	for _, entry in ipairs(WILD_TRAIT_WEIGHTS) do
		cumulative += entry.Weight
		if roll <= cumulative then
			return entry.Trait
		end
	end
	return WILD_TRAIT_WEIGHTS[1].Trait
end

local function isNodeReservedForAstral(nodeName: string): boolean
	return pendingAstralFall ~= nil and pendingAstralFall.NodeName == nodeName
end

local function removeMeteorInternal(meteorUID: string): ()
	local meteor = activeMeteors[meteorUID]
	if meteor == nil then
		return
	end

	if activeAstralUID == meteorUID then
		activeAstralUID = nil
	end

	if meteor.ClaimedByUserId ~= nil then
		local claim = activeClaimsByUserId[meteor.ClaimedByUserId]
		if claim ~= nil and claim.MeteorUID == meteorUID then
			activeClaimsByUserId[meteor.ClaimedByUserId] = nil
		end
		meteor.ClaimedByUserId = nil
	end

	if meteor.IsStarter and meteor.PlotId ~= nil then
		if starterByPlotId[meteor.PlotId] == meteorUID then
			starterByPlotId[meteor.PlotId] = nil
		end
	elseif not meteor.IsStarter then
		if meteor.LuredByUserId ~= nil and luredMeteorByUserId[meteor.LuredByUserId] == meteorUID then
			luredMeteorByUserId[meteor.LuredByUserId] = nil
		end
		if wildNodeOccupied[meteor.NodeName] == meteorUID then
			wildNodeOccupied[meteor.NodeName] = nil
		end
	end

	if meteor.Model ~= nil then
		meteor.Model:Destroy()
		meteor.Model = nil
	end
	activeMeteors[meteorUID] = nil
end

function MeteorService.ReleaseClaimForUserId(userId: number): boolean
	local claim = activeClaimsByUserId[userId]
	if claim == nil then
		return false
	end

	activeClaimsByUserId[userId] = nil
	local meteor = activeMeteors[claim.MeteorUID]
	if meteor ~= nil and meteor.ClaimedByUserId == userId then
		meteor.ClaimedByUserId = nil
		setMeteorPromptEnabled(meteor, true)
		publishMeteorLifecycle({
			Action = "ClaimReleased",
			MeteorUID = meteor.UID,
		})
	end
	return true
end

function MeteorService.SpawnStarterMeteorForPlot(plotId: number, ownerUserId: number, nowClock: number?): (boolean, string, ActiveMeteor?)
	local profile = DataService.GetProfileByUserId(ownerUserId)
	if profile == nil then
		return false, "ProfileNotReady", nil
	end
	if profile.StarterMeteorCompleted == true then
		return false, "StarterAlreadyCompleted", nil
	end
	if starterByPlotId[plotId] ~= nil then
		local existing = activeMeteors[starterByPlotId[plotId]]
		if existing ~= nil and existing.OwnerUserId == ownerUserId then
			return true, "AlreadyPresent", existing
		end
		if existing ~= nil then
			removeMeteorInternal(existing.UID)
		else
			starterByPlotId[plotId] = nil
		end
	end

	local node = starterNodesByPlotId[plotId]
	if node == nil then
		return false, "MissingStarterNode", nil
	end

	local uid = HttpService:GenerateGUID(false)
	local meteor: ActiveMeteor = {
		UID = uid,
		Trait = "Ember",
		NodeName = node.Name,
		Position = node.Position,
		IsStarter = true,
		OwnerUserId = ownerUserId,
		PlotId = plotId,
		ClaimedByUserId = nil,
		SpawnedAt = nowClock or workspace:GetServerTimeNow(),
		Model = nil,
	}
	meteor.Model = createMeteorModel(meteor)
	activeMeteors[uid] = meteor
	starterByPlotId[plotId] = uid

	return true, "Spawned", meteor
end

function MeteorService.SpawnWildMeteorAtNode(
	nodeName: string,
	traitOverride: Types.MeteorTraitId?,
	nowClock: number?,
	luredByUserId: number?,
	luredOwnerName: string?
): (boolean, string, ActiveMeteor?)
	if wildNodeOccupied[nodeName] ~= nil then
		return false, "NodeOccupied", nil
	end

	local targetNode: BasePart? = nil
	for _, node in ipairs(wildNodes) do
		if node.Name == nodeName then
			targetNode = node
			break
		end
	end
	if targetNode == nil then
		return false, "UnknownWildNode", nil
	end

	local trait = traitOverride or rollWeightedWildTrait(serverRng)
	local uid = HttpService:GenerateGUID(false)
	local meteor: ActiveMeteor = {
		UID = uid,
		Trait = trait,
		NodeName = nodeName,
		Position = targetNode.Position,
		IsStarter = false,
		OwnerUserId = nil,
		PlotId = nil,
		LuredByUserId = luredByUserId,
		LuredOwnerName = luredOwnerName,
		ClaimedByUserId = nil,
		SpawnedAt = nowClock or workspace:GetServerTimeNow(),
		Model = nil,
	}
	meteor.Model = createMeteorModel(meteor)
	activeMeteors[uid] = meteor
	wildNodeOccupied[nodeName] = uid
	if trait == "Astral" then
		activeAstralUID = uid
	end
	if luredByUserId ~= nil then
		luredMeteorByUserId[luredByUserId] = uid
	end

	return true, "Spawned", meteor
end

function MeteorService.SpawnLuredMeteorForPlayer(
	userId: number,
	displayName: string,
	trait: Types.MeteorTraitId,
	nowClock: number?
): (boolean, string, ActiveMeteor?)
	local clock = nowClock or workspace:GetServerTimeNow()
	if luredMeteorByUserId[userId] ~= nil then
		return false, "AlreadyHasActiveLure", nil
	end
	local lastClock = lastLureClockByUserId[userId]
	if lastClock ~= nil and (clock - lastClock) < Constants.FROST_LURE_COOLDOWN_SECONDS then
		return false, "LureCooldown", nil
	end

	local selectedNodeName: string? = nil
	local preferredNodes = if trait == "Ember" then EMBER_BASIN_NODES else FROST_ASTRAL_RIDGE_NODES
	for _, node in ipairs(wildNodes) do
		local name = node.Name
		local cooldownUntil = wildNodeCooldownUntil[name] or 0
		if preferredNodes[name] and not isNodeReservedForAstral(name) and wildNodeOccupied[name] == nil and clock >= cooldownUntil then
			selectedNodeName = name
			break
		end
	end
	if selectedNodeName == nil then
		return false, "NoFreeMeteorNode", nil
	end

	local ok, reason, meteor = MeteorService.SpawnWildMeteorAtNode(selectedNodeName :: string, trait, clock, userId, displayName)
	if not ok or meteor == nil then
		return false, reason, nil
	end

	lastLureClockByUserId[userId] = clock
	publishMeteorLifecycle({
		Action = "Spawn",
		MeteorUID = meteor.UID,
		Trait = meteor.Trait,
		Position = meteor.Position,
		LuredBy = userId,
		LuredOwnerName = displayName,
		ArrivalEffect = true,
	})
	return true, "Spawned", meteor
end

function MeteorService.GetActiveWildMeteorCount(): number
	local count = 0
	for _, uid in pairs(wildNodeOccupied) do
		local m = activeMeteors[uid]
		if m ~= nil and m.LuredByUserId == nil then
			count += 1
		end
	end
	return count
end

local function getLiveCharacterPosition(player: Player): Vector3?
	local char = player.Character
	if char == nil then
		return nil
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local rootPart = char:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoid.Health <= 0 or rootPart == nil or not rootPart:IsA("BasePart") then
		return nil
	end
	return rootPart.Position
end

local function resolveLivePositionForUserId(userId: number): Vector3?
	local player = Players:GetPlayerByUserId(userId)
	if player == nil then
		return nil
	end
	return getLiveCharacterPosition(player)
end

function MeteorService.SweepActiveClaims(nowClock: number, resolvePositionFn: ((userId: number) -> Vector3?)?): number
	if not isFiniteClock(nowClock) then
		return 0
	end

	local posResolver = resolvePositionFn or resolveLivePositionForUserId
	local releasedCount = 0
	local toRelease: { number } = {}

	for userId, claim in pairs(activeClaimsByUserId) do
		local meteor = activeMeteors[claim.MeteorUID]
		if meteor == nil or meteor.ClaimedByUserId ~= userId then
			table.insert(toRelease, userId)
		elseif nowClock > claim.Deadline then
			table.insert(toRelease, userId)
		else
			local pos = posResolver(userId)
			if pos == nil or not isFiniteVector3(pos) then
				table.insert(toRelease, userId)
			else
				local distance = (pos - meteor.Position).Magnitude
				if distance ~= distance or math.abs(distance) == math.huge or distance > Constants.MAX_CRACK_ABANDON_DISTANCE then
					table.insert(toRelease, userId)
				end
			end
		end
	end

	for _, userId in ipairs(toRelease) do
		if MeteorService.ReleaseClaimForUserId(userId) then
			releasedCount += 1
		end
	end

	return releasedCount
end

function MeteorService.SweepExpiredClaims(nowClock: number, resolvePositionFn: ((userId: number) -> Vector3?)?): number
	return MeteorService.SweepActiveClaims(nowClock, resolvePositionFn)
end

function MeteorService.StartCrackAtPosition(
	userId: number,
	worldPos: Vector3,
	meteorUID: string,
	nowClock: number
): NetworkService.RemoteResult
	if not isFiniteClock(nowClock) then
		return { Ok = false, Reason = "InvalidClock" }
	end
	if not DataService.IsUserIdReady(userId) then
		return { Ok = false, Reason = "ProfileNotReady" }
	end
	if PlotService.GetAssignedPlotId(userId) == nil then
		return { Ok = false, Reason = "NoAssignedPlot" }
	end
	local profile = DataService.GetProfileByUserId(userId)
	if profile == nil then
		return { Ok = false, Reason = "ProfileNotReady" }
	end

	-- Sweep expired claims lazily so stale timers never block a valid attempt
	local existingClaim = activeClaimsByUserId[userId]
	if existingClaim ~= nil then
		if nowClock > existingClaim.Deadline then
			MeteorService.ReleaseClaimForUserId(userId)
		else
			return { Ok = false, Reason = "AlreadyCracking" }
		end
	end

	local meteor = activeMeteors[meteorUID]
	if meteor == nil then
		return { Ok = false, Reason = "MeteorNotFound" }
	end
	if meteor.IsStarter then
		if meteor.OwnerUserId ~= userId then
			return { Ok = false, Reason = "NotStarterOwner" }
		end
		if profile.StarterMeteorCompleted == true then
			return { Ok = false, Reason = "StarterAlreadyCompleted" }
		end
	end
	if meteor.IsStarter and profile.StarterMeteorCompleted == true then
		MeteorService.ReleaseClaimForUserId(userId)
		return { Ok = false, Reason = "StarterAlreadyCompleted" }
	end
	if meteor.LuredByUserId ~= nil and meteor.LuredByUserId ~= userId then
		return { Ok = false, Reason = "NotLureOwner" }
	end

	-- Enforce required Tool upgrade BEFORE claiming so locked players cannot reserve a shared meteor.
	local requiredUpgrade = MeteorConfig.ById[meteor.Trait].RequiredUpgradeId
	if not meteor.IsStarter and requiredUpgrade ~= nil and profile.Upgrades[requiredUpgrade] ~= true then
		return { Ok = false, Reason = "ToolRequired", RequiredUpgradeId = requiredUpgrade }
	end

	if meteor.ClaimedByUserId ~= nil then
		local holderUserId = meteor.ClaimedByUserId :: number
		local holderClaim = activeClaimsByUserId[holderUserId]
		if holderClaim == nil or holderClaim.MeteorUID ~= meteorUID then
			meteor.ClaimedByUserId = nil
			setMeteorPromptEnabled(meteor, true)
			publishMeteorLifecycle({
				Action = "ClaimReleased",
				MeteorUID = meteor.UID,
			})
		elseif nowClock > holderClaim.Deadline then
			MeteorService.ReleaseClaimForUserId(holderUserId)
		end

		if meteor.ClaimedByUserId ~= nil then
			return { Ok = false, Reason = "MeteorAlreadyClaimed" }
		end
	end

	if not isFiniteVector3(worldPos) then
		return { Ok = false, Reason = "OutOfRange" }
	end
	local distance = (worldPos - meteor.Position).Magnitude
	if distance ~= distance or math.abs(distance) == math.huge or distance > Constants.MAX_CRACK_START_DISTANCE then
		return { Ok = false, Reason = "OutOfRange" }
	end

	if not EconomyService.HasUnreservedBagSpace(profile) then
		return { Ok = false, Reason = "BagFull" }
	end

	local nonce = HttpService:GenerateGUID(false)
	meteor.ClaimedByUserId = userId
	setMeteorPromptEnabled(meteor, false)

	activeClaimsByUserId[userId] = {
		UserId = userId,
		MeteorUID = meteorUID,
		AttemptNonce = nonce,
		StartedAt = nowClock,
		Deadline = nowClock + Constants.CRACK_CLAIM_TIMEOUT_SECONDS,
	}

	publishMeteorLifecycle({
		Action = "Claimed",
		MeteorUID = meteorUID,
		ClaimedBy = userId,
	})

	return {
		Ok = true,
		MeteorUID = meteorUID,
		AttemptNonce = nonce,
		Trait = meteor.Trait,
		IsStarter = meteor.IsStarter,
	}
end

function MeteorService.FinishCrackAtPosition(
	userId: number,
	worldPos: Vector3,
	meteorUID: string,
	attemptNonce: string,
	nowClock: number,
	customRng: Random?
): NetworkService.RemoteResult
	if not isFiniteClock(nowClock) then
		return { Ok = false, Reason = "InvalidClock" }
	end
	if not DataService.IsUserIdReady(userId) then
		MeteorService.ReleaseClaimForUserId(userId)
		return { Ok = false, Reason = "ProfileNotReady" }
	end
	if PlotService.GetAssignedPlotId(userId) == nil then
		MeteorService.ReleaseClaimForUserId(userId)
		return { Ok = false, Reason = "NoAssignedPlot" }
	end
	local profile = DataService.GetProfileByUserId(userId)
	if profile == nil then
		MeteorService.ReleaseClaimForUserId(userId)
		return { Ok = false, Reason = "ProfileNotReady" }
	end

	local claim = activeClaimsByUserId[userId]
	if claim == nil or claim.MeteorUID ~= meteorUID or claim.AttemptNonce ~= attemptNonce then
		return { Ok = false, Reason = "InvalidClaim" }
	end

	local meteor = activeMeteors[meteorUID]
	if meteor == nil or meteor.ClaimedByUserId ~= userId then
		activeClaimsByUserId[userId] = nil
		return { Ok = false, Reason = "MeteorNotFound" }
	end
	if meteor.IsStarter and profile.StarterMeteorCompleted == true then
		MeteorService.ReleaseClaimForUserId(userId)
		return { Ok = false, Reason = "StarterAlreadyCompleted" }
	end
	if meteor.LuredByUserId ~= nil and meteor.LuredByUserId ~= userId then
		MeteorService.ReleaseClaimForUserId(userId)
		return { Ok = false, Reason = "NotLureOwner" }
	end

	local requiredUpgrade = MeteorConfig.ById[meteor.Trait].RequiredUpgradeId
	if not meteor.IsStarter and requiredUpgrade ~= nil and profile.Upgrades[requiredUpgrade] ~= true then
		MeteorService.ReleaseClaimForUserId(userId)
		return { Ok = false, Reason = "ToolRequired", RequiredUpgradeId = requiredUpgrade }
	end

	if nowClock > claim.Deadline then
		MeteorService.ReleaseClaimForUserId(userId)
		return { Ok = false, Reason = "ClaimExpired" }
	end

	if (nowClock - claim.StartedAt) < Constants.MIN_CRACK_DURATION_SECONDS then
		return { Ok = false, Reason = "TooFast" }
	end

	if not isFiniteVector3(worldPos) then
		MeteorService.ReleaseClaimForUserId(userId)
		return { Ok = false, Reason = "OutOfRange" }
	end
	local distance = (worldPos - meteor.Position).Magnitude
	if distance ~= distance or math.abs(distance) == math.huge or distance > Constants.MAX_CRACK_FINISH_DISTANCE then
		MeteorService.ReleaseClaimForUserId(userId)
		return { Ok = false, Reason = "OutOfRange" }
	end

	-- Recheck committed bag capacity and grant pod BEFORE removing meteor or consuming claim.
	if not EconomyService.HasUnreservedBagSpace(profile) then
		MeteorService.ReleaseClaimForUserId(userId)
		return { Ok = false, Reason = "BagFull" }
	end

	local speciesId: Types.SpeciesId = if meteor.IsStarter
		then "StarSlime"
		else EconomyMath.RollSpeciesForMeteorTrait(meteor.Trait, customRng or serverRng)

	local grantRes = if meteor.IsStarter
		then EconomyService.GrantStarterPodToProfile(profile, nowClock)
		else EconomyService.GrantPodToProfile(profile, speciesId, nowClock)
	if not grantRes.Ok then
		MeteorService.ReleaseClaimForUserId(userId)
		return { Ok = false, Reason = grantRes.Reason or "GrantFailed" }
	end

	-- Pod grant (and StarterMeteorCompleted for starter) succeeded; now atomically consume claim and despawn meteor.
	activeClaimsByUserId[userId] = nil
	if not meteor.IsStarter then
		wildNodeCooldownUntil[meteor.NodeName] = nowClock + Constants.WILD_METEOR_RESPAWN_SECONDS
	end

	removeMeteorInternal(meteorUID)
	AnalyticsService.RecordMeteorRescue(Players:GetPlayerByUserId(userId), userId, profile, meteor.IsStarter, meteor.Trait, speciesId)
	publishMeteorLifecycle({
		Action = "Despawn",
		MeteorUID = meteorUID,
	})

	return {
		Ok = true,
		MeteorUID = meteorUID,
		ItemUID = grantRes.ItemUID,
		SpeciesId = speciesId,
	}
end

local function handleStartCrackRequest(player: Player, meteorUID: string): NetworkService.RemoteResult
	local pos = getLiveCharacterPosition(player)
	if pos == nil then
		return { Ok = false, Reason = "CharacterUnavailable" }
	end
	return MeteorService.StartCrackAtPosition(player.UserId, pos, meteorUID, workspace:GetServerTimeNow())
end

local function handleFinishCrackRequest(player: Player, meteorUID: string, attemptNonce: string): NetworkService.RemoteResult
	local pos = getLiveCharacterPosition(player)
	if pos == nil then
		MeteorService.ReleaseClaimForUserId(player.UserId)
		return { Ok = false, Reason = "CharacterUnavailable" }
	end
	local res = MeteorService.FinishCrackAtPosition(player.UserId, pos, meteorUID, attemptNonce, workspace:GetServerTimeNow())
	if res.Ok then
		DataService.SendOwnerStateSnapshot(player)
		EconomyService.NotifyPlotChangedForPlayer(player)
	end
	return res
end

local function disconnectHumanoidListeners(userId: number): ()
	local conns = activeHumanoidConnsByUserId[userId]
	if conns ~= nil then
		for _, conn in ipairs(conns) do
			conn:Disconnect()
		end
		activeHumanoidConnsByUserId[userId] = nil
	end
end

local function disconnectCharacterListeners(userId: number): ()
	disconnectHumanoidListeners(userId)
	local conns = characterConnsByUserId[userId]
	if conns ~= nil then
		for _, conn in ipairs(conns) do
			conn:Disconnect()
		end
		characterConnsByUserId[userId] = nil
	end
end

function MeteorService.HandleCharacterLifecycleReset(userId: number): boolean
	return MeteorService.ReleaseClaimForUserId(userId)
end

local function despawnLuredMeteorForUserId(userId: number): ()
	local luredUid = luredMeteorByUserId[userId]
	if luredUid ~= nil then
		-- removeMeteorInternal clears any active claim on luredUid so leaving emits only a single Despawn.
		removeMeteorInternal(luredUid)
		luredMeteorByUserId[userId] = nil
		publishMeteorLifecycle({
			Action = "Despawn",
			MeteorUID = luredUid,
		})
	end
	lastLureClockByUserId[userId] = nil
end

function MeteorService.HandlePlotReleased(plotId: number, userId: number): ()
	local starterUid = starterByPlotId[plotId]
	if starterUid ~= nil then
		removeMeteorInternal(starterUid)
		publishMeteorLifecycle({
			Action = "Despawn",
			MeteorUID = starterUid,
		})
	end

	despawnLuredMeteorForUserId(userId)
	MeteorService.ReleaseClaimForUserId(userId)
	disconnectCharacterListeners(userId)
end

function MeteorService.HandlePlayerClosing(userId: number): ()
	despawnLuredMeteorForUserId(userId)
	MeteorService.ReleaseClaimForUserId(userId)
	disconnectCharacterListeners(userId)
end

local function attachCharacterClaimCleanup(player: Player): ()
	local userId = player.UserId
	disconnectCharacterListeners(userId)

	local charConns: { RBXScriptConnection } = {}
	local function bindHumanoidFromCharacter(char: Model)
		disconnectHumanoidListeners(userId)
		local humConns: { RBXScriptConnection } = {}
		local attachedHumanoid: Humanoid? = nil
		local childAddedConn: RBXScriptConnection? = nil

		local function attachToHumanoid(hum: Humanoid)
			if attachedHumanoid == hum then
				return
			end
			attachedHumanoid = hum
			if childAddedConn ~= nil then
				childAddedConn:Disconnect()
				childAddedConn = nil
			end
			table.insert(humConns, hum.Died:Connect(function()
				MeteorService.HandleCharacterLifecycleReset(userId)
			end))
		end

		local existingHum = char:FindFirstChildOfClass("Humanoid")
		if existingHum ~= nil then
			attachToHumanoid(existingHum)
		else
			local conn = char.ChildAdded:Connect(function(child: Instance)
				if child:IsA("Humanoid") then
					attachToHumanoid(child)
				end
			end)
			childAddedConn = conn
			table.insert(humConns, conn)
		end

		activeHumanoidConnsByUserId[userId] = humConns
	end

	if player.Character ~= nil then
		bindHumanoidFromCharacter(player.Character)
	end
	table.insert(charConns, player.CharacterAdded:Connect(function(newChar: Model)
		MeteorService.HandleCharacterLifecycleReset(userId)
		bindHumanoidFromCharacter(newChar)
	end))
	table.insert(charConns, player.CharacterRemoving:Connect(function()
		disconnectHumanoidListeners(userId)
		MeteorService.HandleCharacterLifecycleReset(userId)
	end))

	characterConnsByUserId[userId] = charConns
end

local function pickOpenNodeNameForTrait(trait: Types.MeteorTraitId, nowClock: number): string?
	local preferred = if trait == "Ember" then EMBER_BASIN_NODES else FROST_ASTRAL_RIDGE_NODES
	for _, node in ipairs(wildNodes) do
		local name = node.Name
		local cooldownUntil = wildNodeCooldownUntil[name] or 0
		if preferred[name] and not isNodeReservedForAstral(name) and wildNodeOccupied[name] == nil and nowClock >= cooldownUntil then
			return name
		end
	end
	return nil
end

function MeteorService.TriggerAstralFallNow(nowClock: number?): (boolean, string, PendingAstralFall?)
	local clock = nowClock or workspace:GetServerTimeNow()
	if pendingAstralFall ~= nil or (activeAstralUID ~= nil and activeMeteors[activeAstralUID] ~= nil) then
		return false, "AstralAlreadyActive", nil
	end

	local chosenNode: BasePart? = nil
	for _, node in ipairs(wildNodes) do
		local name = node.Name
		local cooldownUntil = wildNodeCooldownUntil[name] or 0
		if FROST_ASTRAL_RIDGE_NODES[name] and wildNodeOccupied[name] == nil and clock >= cooldownUntil then
			chosenNode = node
			break
		end
	end

	if chosenNode == nil then
		-- Evict the oldest unclaimed, un-lured wild meteor on North Ridge so scheduled Astral Falls can still arrive cleanly.
		local oldestEvictable: ActiveMeteor? = nil
		local oldestNode: BasePart? = nil
		for _, node in ipairs(wildNodes) do
			if FROST_ASTRAL_RIDGE_NODES[node.Name] then
				local occUid = wildNodeOccupied[node.Name]
				local occ = if occUid ~= nil then activeMeteors[occUid] else nil
				if occ ~= nil and not occ.IsStarter and occ.LuredByUserId == nil and occ.ClaimedByUserId == nil then
					if oldestEvictable == nil or occ.SpawnedAt < oldestEvictable.SpawnedAt then
						oldestEvictable = occ
						oldestNode = node
					end
				end
			end
		end
		if oldestEvictable ~= nil and oldestNode ~= nil then
			local evictUID = oldestEvictable.UID
			wildNodeCooldownUntil[oldestEvictable.NodeName] = nil
			removeMeteorInternal(evictUID)
			publishMeteorLifecycle({
				Action = "Despawn",
				MeteorUID = evictUID,
			})
			chosenNode = oldestNode
		end
	end

	if chosenNode == nil then
		nextAstralFallAt = clock + 5
		return false, "NoRidgeNodeAvailable", nil
	end

	wildNodeCooldownUntil[chosenNode.Name] = clock + Constants.ASTRAL_FALL_WARNING_SECONDS + 2
	-- Schedule the next fall against this fall's warning timestamp (75s fall-to-fall cadence).
	nextAstralFallAt = clock + Constants.ASTRAL_FALL_INTERVAL_SECONDS
	local incoming: PendingAstralFall = {
		NodeName = chosenNode.Name,
		Position = chosenNode.Position,
		LandAt = clock + Constants.ASTRAL_FALL_WARNING_SECONDS,
	}
	pendingAstralFall = incoming
	publishMeteorLifecycle({
		Action = "AstralIncoming",
		NodeName = incoming.NodeName,
		Position = incoming.Position,
		Duration = Constants.ASTRAL_FALL_WARNING_SECONDS,
	})
	return true, "Incoming", incoming
end

local function stepAstralFallEvent(nowClock: number): ()
	if pendingAstralFall ~= nil and nowClock >= pendingAstralFall.LandAt then
		local fall = pendingAstralFall
		pendingAstralFall = nil
		wildNodeCooldownUntil[fall.NodeName] = nil
		if wildNodeOccupied[fall.NodeName] == nil then
			local ok, _, meteor = MeteorService.SpawnWildMeteorAtNode(fall.NodeName, "Astral", nowClock)
			if ok and meteor ~= nil then
				publishMeteorLifecycle({
					Action = "Spawn",
					MeteorUID = meteor.UID,
					Trait = meteor.Trait,
					Position = meteor.Position,
					ArrivalEffect = true,
				})
			end
		end
	end

	if activeAstralUID ~= nil then
		local astralMeteor = activeMeteors[activeAstralUID]
		if astralMeteor == nil then
			activeAstralUID = nil
		elseif astralMeteor.ClaimedByUserId == nil and (nowClock - astralMeteor.SpawnedAt) >= Constants.ASTRAL_METEOR_LIFETIME_SECONDS then
			local expiredUID = astralMeteor.UID
			wildNodeCooldownUntil[astralMeteor.NodeName] = nowClock + Constants.WILD_METEOR_RESPAWN_SECONDS
			removeMeteorInternal(expiredUID)
			publishMeteorLifecycle({
				Action = "Despawn",
				MeteorUID = expiredUID,
			})
		end
	end

	if nextAstralFallAt > 0 and nowClock >= nextAstralFallAt and pendingAstralFall == nil and activeAstralUID == nil then
		MeteorService.TriggerAstralFallNow(nowClock)
	end
end

local function populateWildMeteorsUpToCap(nowClock: number): ()
	local activeEmber = 0
	local activeFrost = 0
	for _, meteor in pairs(activeMeteors) do
		if not meteor.IsStarter and meteor.LuredByUserId == nil then
			if meteor.Trait == "Ember" then
				activeEmber += 1
			elseif meteor.Trait == "Frost" then
				activeFrost += 1
			end
		end
	end

	local steps = 0
	while MeteorService.GetActiveWildMeteorCount() < Constants.MAX_ACTIVE_WILD_METEORS and steps < 8 do
		steps += 1
		local nextTrait: Types.MeteorTraitId
		if activeEmber < 2 then
			nextTrait = "Ember"
		elseif activeFrost < 1 then
			nextTrait = "Frost"
		else
			nextTrait = rollWeightedWildTrait(serverRng)
		end

		local nodeName = pickOpenNodeNameForTrait(nextTrait, nowClock)
		if nodeName == nil then
			nextTrait = if nextTrait == "Ember" then "Frost" else "Ember"
			nodeName = pickOpenNodeNameForTrait(nextTrait, nowClock)
		end
		if nodeName == nil then
			break
		end

		local ok, _, meteor = MeteorService.SpawnWildMeteorAtNode(nodeName, nextTrait, nowClock)
		if ok and meteor ~= nil then
			if meteor.Trait == "Ember" then
				activeEmber += 1
			elseif meteor.Trait == "Frost" then
				activeFrost += 1
			end
			publishMeteorLifecycle({
				Action = "Spawn",
				MeteorUID = meteor.UID,
				Trait = meteor.Trait,
				Position = meteor.Position,
				ArrivalEffect = false,
			})
		else
			break
		end
	end
end

local function ensureBeforeNavigateRegistered(): ()
	if beforeNavigateRegistered then
		return
	end
	beforeNavigateRegistered = true
	PlotService.OnBeforeNavigate(function(userId: number)
		MeteorService.ReleaseClaimForUserId(userId)
	end)
end

function MeteorService.ResetTestAstralAndCooldownState(): ()
	wildNodeCooldownUntil = {}
	pendingAstralFall = nil
	activeAstralUID = nil
	nextAstralFallAt = 0
end

function MeteorService.Init(self: typeof(MeteorService)): ()
	local root = PlotService.GetGreyboxRoot()
	local crater = root:FindFirstChild("CentralCrater") :: Model

	wildNodes = {}
	local meteorSpawnFolder = crater:FindFirstChild("MeteorSpawnNodes") :: Folder
	for i = 1, Constants.WILD_METEOR_NODE_COUNT do
		local node = meteorSpawnFolder:FindFirstChild("MeteorNode_" .. tostring(i)) :: BasePart
		assert(node ~= nil and CollectionService:HasTag(node, Constants.TAG_METEOR_NODE), "Invalid MeteorNode_" .. tostring(i))
		table.insert(wildNodes, node)
	end

	starterNodesByPlotId = {}
	local starterFolder = crater:FindFirstChild("StarterMeteorNodes") :: Folder
	for plotId = 1, Constants.MAX_PLOTS_ALPHA do
		local sNode = starterFolder:FindFirstChild("StarterNode_Plot_" .. tostring(plotId)) :: BasePart
		assert(sNode ~= nil and not CollectionService:HasTag(sNode, Constants.TAG_METEOR_NODE), "Invalid StarterNode_Plot_" .. tostring(plotId))
		starterNodesByPlotId[plotId] = sNode
	end

	local existingActive = root:FindFirstChild("ActiveMeteors")
	if existingActive and existingActive:IsA("Folder") then
		existingActive:ClearAllChildren()
		activeMeteorsFolder = existingActive
	else
		local folder = Instance.new("Folder")
		folder.Name = "ActiveMeteors"
		folder.Parent = root
		activeMeteorsFolder = folder
	end

	ensureBeforeNavigateRegistered()
	print(string.format("[MeteorService] Discovered %d wild nodes and %d starter nodes.", #wildNodes, Constants.MAX_PLOTS_ALPHA))
end

function MeteorService.Start(self: typeof(MeteorService)): ()
	NetworkService.BindStartCrackHandler(handleStartCrackRequest)
	NetworkService.BindFinishCrackHandler(handleFinishCrackRequest)
	EconomyService.SetLureSpawner(function(userId: number, displayName: string, trait: Types.MeteorTraitId, nowClock: number): (boolean, string)
		local ok, reason = MeteorService.SpawnLuredMeteorForPlayer(userId, displayName, trait, nowClock)
		return ok, reason
	end)

	ensureBeforeNavigateRegistered()

	PlotService.OnPlotAssigned(function(plotId: number, userId: number)
		local player = Players:GetPlayerByUserId(userId)
		if player ~= nil then
			attachCharacterClaimCleanup(player)
		end
		local ok, _, meteor = MeteorService.SpawnStarterMeteorForPlot(plotId, userId, workspace:GetServerTimeNow())
		if ok and meteor ~= nil then
			publishMeteorLifecycle({
				Action = "Spawn",
				MeteorUID = meteor.UID,
				Trait = meteor.Trait,
				Position = meteor.Position,
				IsStarter = true,
				OwnerUserId = userId,
			})
		end
	end)

	PlotService.OnPlotReleased(function(plotId: number, userId: number)
		MeteorService.HandlePlotReleased(plotId, userId)
	end)

	DataService.OnPlayerClosing(function(player: Player)
		MeteorService.HandlePlayerClosing(player.UserId)
	end)

	DataService.OnSnapshotDelivered(function(player: Player)
		for _, meteor in pairs(activeMeteors) do
			NetworkService.SendMeteorLifecycleToPlayer(player, {
				Action = "Spawn",
				MeteorUID = meteor.UID,
				Trait = meteor.Trait,
				Position = meteor.Position,
				IsStarter = meteor.IsStarter,
				OwnerUserId = meteor.OwnerUserId,
				LuredBy = meteor.LuredByUserId,
				LuredOwnerName = meteor.LuredOwnerName,
				ClaimedBy = meteor.ClaimedByUserId,
			})
		end
		if pendingAstralFall ~= nil then
			NetworkService.SendMeteorLifecycleToPlayer(player, {
				Action = "AstralIncoming",
				NodeName = pendingAstralFall.NodeName,
				Position = pendingAstralFall.Position,
				Duration = math.max(0.25, pendingAstralFall.LandAt - workspace:GetServerTimeNow()),
			})
		end
	end)

	-- Schedule first timed Astral Fall cleanly after startup, and seed wild Basin/Ridge meteors (no initial Astral)
	nextAstralFallAt = workspace:GetServerTimeNow() + Constants.ASTRAL_FALL_FIRST_DELAY_SECONDS
	populateWildMeteorsUpToCap(workspace:GetServerTimeNow())

	if not watcherRunning then
		watcherRunning = true
		task.spawn(function()
			while watcherRunning do
				task.wait(0.5)
				local nowClock = workspace:GetServerTimeNow()
				MeteorService.SweepActiveClaims(nowClock)
				stepAstralFallEvent(nowClock)
				populateWildMeteorsUpToCap(nowClock)
			end
		end)
	end
end

local function countBagItems(profile: Types.PlayerProfileData): number
	local count = 0
	for _, item in pairs(profile.Items) do
		if item.State == "PodInBag" or item.State == "HatchedInBag" then
			count += 1
		end
	end
	return count
end

local function isPromptEnabled(meteor: ActiveMeteor): boolean
	local model = meteor.Model
	local primary = if model ~= nil then model.PrimaryPart else nil
	local prompt = if primary ~= nil then primary:FindFirstChild("RescuePrompt") else nil
	return prompt ~= nil and prompt:IsA("ProximityPrompt") and prompt.Enabled
end

function MeteorService.RunSelfTest(): number
	local passed = 0
	local rng = Random.new(99)
	local u1 = -930001
	local u2 = -930002
	local uUnassigned = -930003
	local createdMeteorUIDs: { string } = {}
	local events: { { [string]: any } } = {}

	local function clearEvents(): ()
		events = {}
	end

	local function countEvents(action: string, meteorUID: string?): number
		local total = 0
		for _, ev in ipairs(events) do
			if ev.Action == action and (meteorUID == nil or ev.MeteorUID == meteorUID) then
				total += 1
			end
		end
		return total
	end

	PlotService.ReleasePlotForUserId(u1)
	PlotService.ReleasePlotForUserId(u2)
	DataService.EndMockSession(u1)
	DataService.EndMockSession(u2)
	DataService.EndMockSession(uUnassigned)

	local testOk, testErr = pcall(function()
		lifecycleObserver = function(payload: { [string]: any })
			table.insert(events, payload)
		end

		DataService.BeginMockSession(u1, nil)
		DataService.CompleteMockSession(u1, 5000)
		DataService.BeginMockSession(u2, nil)
		DataService.CompleteMockSession(u2, 5000)

		local p1 = DataService.GetProfileByUserId(u1) :: Types.PlayerProfileData
		local p2 = DataService.GetProfileByUserId(u2) :: Types.PlayerProfileData

		assert((PlotService.AssignPlotForUserId(u1, "MeteorTester1", p1, nil)), "Assign Plot 1")
		assert((PlotService.AssignPlotForUserId(u2, "MeteorTester2", p2, nil)), "Assign Plot 2")

		-- 1. Starter UID validation, plot scoping, guaranteed 1-pod StarSlime grant & single Despawn
		local sOk, _, starter1 = MeteorService.SpawnStarterMeteorForPlot(1, u1, 5000)
		assert(sOk and starter1 ~= nil, "Starter meteor spawns for Plot 1")
		local starterObj = starter1 :: ActiveMeteor
		table.insert(createdMeteorUIDs, starterObj.UID)

		assert(#starterObj.UID <= Constants.MAX_STRING_ID_LENGTH, "Starter MeteorUID stays within MAX_STRING_ID_LENGTH")
		local starterStartValid = NetworkService.ValidateInboundPayload(Constants.REMOTE_NAMES.RequestStartCrack, starterObj.UID)
		assert(starterStartValid, "Generated starter UID must pass RequestStartCrack validation")

		local crossStart = MeteorService.StartCrackAtPosition(u2, starterObj.Position, starterObj.UID, 5001)
		assert(not crossStart.Ok and crossStart.Reason == "NotStarterOwner", "Other player blocked from starter meteor")

		DataService.BeginMockSession(uUnassigned, nil)
		DataService.CompleteMockSession(uUnassigned, 5000)
		local noPlotStart = MeteorService.StartCrackAtPosition(uUnassigned, starterObj.Position, starterObj.UID, 5001)
		assert(not noPlotStart.Ok and noPlotStart.Reason == "NoAssignedPlot", "Unassigned player blocked")
		DataService.EndMockSession(uUnassigned)

		clearEvents()
		local p1BagBeforeStarter = countBagItems(p1)
		local p1Start = MeteorService.StartCrackAtPosition(u1, starterObj.Position, starterObj.UID, 5001)
		assert(p1Start.Ok and p1Start.AttemptNonce ~= nil, "Owner starts starter crack")
		local starterFinishValid = NetworkService.ValidateInboundPayload(
			Constants.REMOTE_NAMES.RequestFinishCrack,
			starterObj.UID,
			p1Start.AttemptNonce
		)
		assert(starterFinishValid, "Starter UID + AttemptNonce must pass RequestFinishCrack validation")
		assert(not isPromptEnabled(starterObj), "Starter prompt disabled while claimed")
		assert(countEvents("Claimed", starterObj.UID) == 1, "Starter start publishes Claimed event")

		local p1Finish = MeteorService.FinishCrackAtPosition(u1, starterObj.Position, starterObj.UID, p1Start.AttemptNonce :: string, 5002, rng)
		assert(p1Finish.Ok and p1Finish.SpeciesId == "StarSlime", "Starter meteor guarantees StarSlime")
		assert(p1.StarterMeteorCompleted == true, "Starter rescue marks profile.StarterMeteorCompleted=true")
		assert(countBagItems(p1) == p1BagBeforeStarter + 1, "Starter rescue grants exactly 1 pod")
		assert(activeMeteors[starterObj.UID] == nil, "Starter meteor despawned after grant")
		assert(countEvents("Despawn", starterObj.UID) == 1 and countEvents("ClaimReleased", starterObj.UID) == 0, "Starter completion emits single Despawn and zero ClaimReleased")

		local respawnBlockedOk, respawnBlockedReason = MeteorService.SpawnStarterMeteorForPlot(1, u1, 5002)
		assert(not respawnBlockedOk and respawnBlockedReason == "StarterAlreadyCompleted", "Completed profile blocks starter respawn")

		-- Verify Plot_6 starter node requires ready profile & spawns cleanly as part of 6-plot expansion
		local noProfOk, noProfReason = MeteorService.SpawnStarterMeteorForPlot(6, uUnassigned, 5002)
		assert(not noProfOk and noProfReason == "ProfileNotReady", "Unloaded profile blocks starter spawn")
		DataService.BeginMockSession(uUnassigned, nil)
		DataService.CompleteMockSession(uUnassigned, 5002)
		local s6Ok, _, starter6 = MeteorService.SpawnStarterMeteorForPlot(6, uUnassigned, 5002)
		assert(s6Ok and starter6 ~= nil and (starter6 :: ActiveMeteor).NodeName == "StarterNode_Plot_6", "Starter meteor spawns on Plot_6")
		removeMeteorInternal((starter6 :: ActiveMeteor).UID)
		DataService.EndMockSession(uUnassigned)
		passed += 1

		-- 2. Wild UID validation, 2-player race, forged nonce, TooFast, 1-pod grant & replay rejection
		local wOk, _, wild1 = MeteorService.SpawnWildMeteorAtNode("MeteorNode_1", "Astral", 5003)
		assert(wOk and wild1 ~= nil, "Wild meteor spawns on MeteorNode_1")
		local wildObj = wild1 :: ActiveMeteor
		table.insert(createdMeteorUIDs, wildObj.UID)

		assert(#wildObj.UID <= Constants.MAX_STRING_ID_LENGTH, "Wild MeteorUID stays within MAX_STRING_ID_LENGTH")
		local wildStartValid = NetworkService.ValidateInboundPayload(Constants.REMOTE_NAMES.RequestStartCrack, wildObj.UID)
		assert(wildStartValid, "Generated wild UID must pass RequestStartCrack validation")

		clearEvents()
		local lockedAstral = MeteorService.StartCrackAtPosition(u1, wildObj.Position, wildObj.UID, 5004)
		assert(
			not lockedAstral.Ok and lockedAstral.Reason == "ToolRequired" and wildObj.ClaimedByUserId == nil,
			"Player without StarCracker blocked from claiming Astral meteor"
		)
		assert(isPromptEnabled(wildObj), "Astral prompt stays enabled after ToolRequired rejection")
		assert(countEvents("Claimed", wildObj.UID) == 0, "Blocked Astral attempt emits zero Claimed events")

		p1.Upgrades["StarCracker"] = true
		p2.Upgrades["StarCracker"] = true

		local p1BagBeforeWild = countBagItems(p1)
		local race1 = MeteorService.StartCrackAtPosition(u1, wildObj.Position, wildObj.UID, 5004)
		assert(race1.Ok and race1.AttemptNonce ~= nil, "Player 1 wins claim")
		local wildFinishValid = NetworkService.ValidateInboundPayload(
			Constants.REMOTE_NAMES.RequestFinishCrack,
			wildObj.UID,
			race1.AttemptNonce
		)
		assert(wildFinishValid, "Wild UID + AttemptNonce must pass RequestFinishCrack validation")
		assert(not isPromptEnabled(wildObj), "Wild prompt disabled while claimed")

		local race2 = MeteorService.StartCrackAtPosition(u2, wildObj.Position, wildObj.UID, 5004)
		assert(not race2.Ok and race2.Reason == "MeteorAlreadyClaimed", "Player 2 blocked from claimed meteor")

		local forged = MeteorService.FinishCrackAtPosition(u1, wildObj.Position, wildObj.UID, "forged-nonce", 5005, rng)
		assert(not forged.Ok and forged.Reason == "InvalidClaim", "Forged nonce rejected")

		local tooFast = MeteorService.FinishCrackAtPosition(u1, wildObj.Position, wildObj.UID, race1.AttemptNonce :: string, 5004.1, rng)
		assert(not tooFast.Ok and tooFast.Reason == "TooFast" and activeMeteors[wildObj.UID] ~= nil, "TooFast finish rejected and meteor preserved")
		assert(not isPromptEnabled(wildObj), "Prompt remains disabled during valid crack after TooFast check")

		local wildFinish = MeteorService.FinishCrackAtPosition(u1, wildObj.Position, wildObj.UID, race1.AttemptNonce :: string, 5005.0, rng)
		assert(wildFinish.Ok and activeMeteors[wildObj.UID] == nil, "Valid finish grants pod and despawns meteor")
		assert(countBagItems(p1) == p1BagBeforeWild + 1, "Wild rescue grants exactly 1 pod")
		assert(
			countEvents("Claimed", wildObj.UID) == 1
				and countEvents("Despawn", wildObj.UID) == 1
				and countEvents("ClaimReleased", wildObj.UID) == 0,
			"Wild completion emits single Claimed and Despawn"
		)

		local replay = MeteorService.FinishCrackAtPosition(u1, wildObj.Position, wildObj.UID, race1.AttemptNonce :: string, 5005.2, rng)
		assert(not replay.Ok and replay.Reason == "InvalidClaim", "Nonce replay rejected")
		passed += 1

		-- 3. Frost pre-claim ToolRequired, OutOfRange, BagFull, strict Ridge Lure isolation & Timed Astral Fall
		local wOk2, _, wild2 = MeteorService.SpawnWildMeteorAtNode("MeteorNode_4", "Frost", 5010)
		assert(wOk2 and wild2 ~= nil, "Wild meteor 2 spawns on North Frost Ridge")
		local wildObj2 = wild2 :: ActiveMeteor
		table.insert(createdMeteorUIDs, wildObj2.UID)

		local lockedFrost = MeteorService.StartCrackAtPosition(u2, wildObj2.Position, wildObj2.UID, 5010.5)
		assert(
			not lockedFrost.Ok and lockedFrost.Reason == "ToolRequired" and wildObj2.ClaimedByUserId == nil,
			"Player without FrostCracker blocked from claiming Frost meteor"
		)
		p1.Upgrades["FrostCracker"] = true
		p2.Upgrades["FrostCracker"] = true

		-- Verify personal Frost Lure lands strictly on North Frost Ridge & never spills into Ember Basin when Ridge is full
		local lOk, _, luredMeteorRaw = MeteorService.SpawnLuredMeteorForPlayer(u1, "MeteorTester1", "Frost", 5010.8)
		assert(lOk and luredMeteorRaw ~= nil, "Frost Lure spawns personal Frost meteor")
		local luredObj = luredMeteorRaw :: ActiveMeteor
		assert(FROST_ASTRAL_RIDGE_NODES[luredObj.NodeName] == true, "Frost Lure spawns strictly on North Frost Ridge")
		assert(luredObj.Model ~= nil and luredObj.Model:FindFirstChild("LureBeacon") ~= nil, "Lured Frost meteor builds visible LureBeacon")
		table.insert(createdMeteorUIDs, luredObj.UID)
		local stealLure = MeteorService.StartCrackAtPosition(u2, luredObj.Position, luredObj.UID, 5010.9)
		assert(not stealLure.Ok and stealLure.Reason == "NotLureOwner", "Other player blocked from Lured Frost meteor")
		local dupOk, dupReason = MeteorService.SpawnLuredMeteorForPlayer(u1, "MeteorTester1", "Frost", 5010.9)
		assert(not dupOk and dupReason == "AlreadyHasActiveLure", "Second concurrent lure blocked")

		local tempRidgeUids: { string } = {}
		for nodeName in pairs(FROST_ASTRAL_RIDGE_NODES) do
			if wildNodeOccupied[nodeName] == nil then
				local fOk, _, fRaw = MeteorService.SpawnWildMeteorAtNode(nodeName, "Frost", 5010.85)
				assert(fOk and fRaw ~= nil, "Occupy Ridge node " .. nodeName)
				table.insert(tempRidgeUids, (fRaw :: ActiveMeteor).UID)
			end
		end
		local noBasinSpillOk, noBasinSpillReason = MeteorService.SpawnLuredMeteorForPlayer(u2, "MeteorTester2", "Frost", 5010.9)
		assert(not noBasinSpillOk and noBasinSpillReason == "NoFreeMeteorNode", "Full Ridge returns NoFreeMeteorNode without spilling into Ember Basin")
		for _, tmpUid in ipairs(tempRidgeUids) do
			removeMeteorInternal(tmpUid)
		end

		removeMeteorInternal(luredObj.UID)
		lastLureClockByUserId[u1] = nil

		-- Verify Timed Astral Fall: warning -> spawn on Ridge -> expiry -> exact 75s fall-to-fall next warning
		clearEvents()
		local tFallStart = 5010.95
		local afOk, _, afPending = MeteorService.TriggerAstralFallNow(tFallStart)
		assert(afOk and afPending ~= nil and FROST_ASTRAL_RIDGE_NODES[(afPending :: PendingAstralFall).NodeName] == true, "TriggerAstralFallNow announces North Ridge fall")
		assert(countEvents("AstralIncoming") == 1, "TriggerAstralFallNow broadcasts AstralIncoming")
		assert(math.abs(nextAstralFallAt - (tFallStart + Constants.ASTRAL_FALL_INTERVAL_SECONDS)) < 1e-6, "Astral Fall schedules next event against warning timestamp")
		stepAstralFallEvent(tFallStart + Constants.ASTRAL_FALL_WARNING_SECONDS + 0.1)
		assert(activeAstralUID ~= nil and activeMeteors[activeAstralUID] ~= nil, "Astral Fall spawns Astral meteor after warning")
		local spawnedAstral = activeMeteors[activeAstralUID :: string] :: ActiveMeteor
		assert(spawnedAstral.Trait == "Astral" and FROST_ASTRAL_RIDGE_NODES[spawnedAstral.NodeName] == true, "Spawned Astral sits on North Ridge")
		assert(spawnedAstral.Model ~= nil and spawnedAstral.Model:FindFirstChild("AstralBeacon") ~= nil, "Spawned Astral has visible AstralBeacon")
		clearEvents()
		stepAstralFallEvent(spawnedAstral.SpawnedAt + Constants.ASTRAL_METEOR_LIFETIME_SECONDS + 0.1)
		assert(activeMeteors[spawnedAstral.UID] == nil and countEvents("Despawn", spawnedAstral.UID) == 1, "Unclaimed Astral expires cleanly after lifetime")
		assert(math.abs(nextAstralFallAt - (tFallStart + Constants.ASTRAL_FALL_INTERVAL_SECONDS)) < 1e-6, "Expiry must NOT push next Astral Fall out to 133s")
		clearEvents()
		stepAstralFallEvent(tFallStart + Constants.ASTRAL_FALL_INTERVAL_SECONDS)
		assert(countEvents("AstralIncoming") == 1 and pendingAstralFall ~= nil, "Next Astral Fall fires on exact 75s fall-to-fall cadence")
		if pendingAstralFall ~= nil then
			wildNodeCooldownUntil[pendingAstralFall.NodeName] = nil
		end
		activeAstralUID = nil
		pendingAstralFall = nil
		nextAstralFallAt = 0

		local nanStart = MeteorService.StartCrackAtPosition(u2, Vector3.new(0 / 0, 0, 0), wildObj2.UID, 5011)
		assert(not nanStart.Ok and nanStart.Reason == "OutOfRange", "NaN start pos rejected")
		local farStart = MeteorService.StartCrackAtPosition(u2, wildObj2.Position + Vector3.new(50, 0, 0), wildObj2.UID, 5011)
		assert(not farStart.Ok and farStart.Reason == "OutOfRange", "Out-of-range start rejected")

		-- OutOfRange at finish releases claim, re-enables prompt, and broadcasts ClaimReleased
		local cFarFinish = MeteorService.StartCrackAtPosition(u2, wildObj2.Position, wildObj2.UID, 5011)
		assert(cFarFinish.Ok and cFarFinish.AttemptNonce ~= nil, "u2 claims wild2 before walking out of range")
		assert(not isPromptEnabled(wildObj2), "Prompt disabled after u2 claims wild2")
		clearEvents()
		local farFinish = MeteorService.FinishCrackAtPosition(
			u2,
			wildObj2.Position + Vector3.new(Constants.MAX_CRACK_FINISH_DISTANCE + 3, 0, 0),
			wildObj2.UID,
			cFarFinish.AttemptNonce :: string,
			5011.6,
			rng
		)
		assert(not farFinish.Ok and farFinish.Reason == "OutOfRange", "OutOfRange finish rejected")
		assert(activeMeteors[wildObj2.UID] ~= nil and wildObj2.ClaimedByUserId == nil, "Meteor preserved and unlocked on OutOfRange finish")
		assert(isPromptEnabled(wildObj2), "Prompt re-enabled on OutOfRange finish")
		assert(countEvents("ClaimReleased", wildObj2.UID) == 1 and countEvents("Despawn", wildObj2.UID) == 0, "OutOfRange finish emits ClaimReleased")

		-- Claim, fill bag before finish -> finish fails cleanly, releases claim, re-enables prompt
		local c2 = MeteorService.StartCrackAtPosition(u2, wildObj2.Position, wildObj2.UID, 5012)
		assert(c2.Ok and c2.AttemptNonce ~= nil, "u2 claims wild2 for BagFull check")
		for i = 1, EconomyService.GetBagCapacity(p2) do
			EconomyService.GrantPodToProfile(p2, "StarSlime", 5012, "fill-m-" .. tostring(i))
		end
		clearEvents()
		local bagFullFinish = MeteorService.FinishCrackAtPosition(u2, wildObj2.Position, wildObj2.UID, c2.AttemptNonce :: string, 5013, rng)
		assert(not bagFullFinish.Ok and bagFullFinish.Reason == "BagFull", "BagFull at finish rejected")
		assert(activeMeteors[wildObj2.UID] ~= nil and wildObj2.ClaimedByUserId == nil, "Meteor preserved & claim released on BagFull")
		assert(isPromptEnabled(wildObj2), "Prompt re-enabled on BagFull")
		assert(countEvents("ClaimReleased", wildObj2.UID) == 1 and countEvents("Despawn", wildObj2.UID) == 0, "BagFull emits ClaimReleased")
		p2.Items = {}
		passed += 1

		-- 4. Claim release lifecycle on distance (>28 studs), timeout, missing/dead char, respawn, and leave
		-- 4a. Distance abandonment
		local cDist = MeteorService.StartCrackAtPosition(u1, wildObj2.Position, wildObj2.UID, 5020)
		assert(cDist.Ok, "u1 claims wild2 for distance sweep test")
		assert(not isPromptEnabled(wildObj2), "Prompt disabled on u1 distance test claim")
		clearEvents()
		local sweptNear = MeteorService.SweepActiveClaims(5021, function(_userId: number): Vector3?
			return wildObj2.Position + Vector3.new(10, 0, 0)
		end)
		assert(sweptNear == 0 and wildObj2.ClaimedByUserId == u1 and not isPromptEnabled(wildObj2) and #events == 0, "Player within 28 studs retains claim")

		local sweptFar = MeteorService.SweepActiveClaims(5021.5, function(_userId: number): Vector3?
			return wildObj2.Position + Vector3.new(Constants.MAX_CRACK_ABANDON_DISTANCE + 0.5, 0, 0)
		end)
		assert(sweptFar == 1 and wildObj2.ClaimedByUserId == nil and isPromptEnabled(wildObj2), "Walk > 28 studs releases claim and re-enables prompt")
		assert(countEvents("ClaimReleased", wildObj2.UID) == 1, "Distance abandonment broadcasts ClaimReleased")

		local u2ClaimDist = MeteorService.StartCrackAtPosition(u2, wildObj2.Position, wildObj2.UID, 5022)
		assert(u2ClaimDist.Ok, "Another player can immediately reclaim after distance abandonment")
		assert(MeteorService.ReleaseClaimForUserId(u2), "Clean release after u2 reclaim")

		-- 4b. Timeout expiry
		local cExpire = MeteorService.StartCrackAtPosition(u1, wildObj2.Position, wildObj2.UID, 5030)
		assert(cExpire.Ok, "u1 claims wild2 for timeout test")
		clearEvents()
		local sweptTimeout = MeteorService.SweepActiveClaims(
			5030 + Constants.CRACK_CLAIM_TIMEOUT_SECONDS + 1,
			function(_userId: number): Vector3?
				return wildObj2.Position
			end
		)
		assert(sweptTimeout == 1 and wildObj2.ClaimedByUserId == nil and isPromptEnabled(wildObj2), "Expired claim swept cleanly and prompt re-enabled")
		assert(countEvents("ClaimReleased", wildObj2.UID) == 1, "Timeout expiry broadcasts ClaimReleased")

		-- 4c. Dead / missing character sweep
		local cDead = MeteorService.StartCrackAtPosition(u1, wildObj2.Position, wildObj2.UID, 5040)
		assert(cDead.Ok, "u1 claims wild2 for missing-character sweep")
		clearEvents()
		local sweptDead = MeteorService.SweepActiveClaims(5041, function(_userId: number): Vector3?
			return nil
		end)
		assert(sweptDead == 1 and wildObj2.ClaimedByUserId == nil and isPromptEnabled(wildObj2), "Unavailable character releases claim and re-enables prompt")
		assert(countEvents("ClaimReleased", wildObj2.UID) == 1, "Character unavailable sweep broadcasts ClaimReleased")

		-- 4d. Respawn / death hook
		local cRespawn = MeteorService.StartCrackAtPosition(u1, wildObj2.Position, wildObj2.UID, 5050)
		assert(cRespawn.Ok, "u1 claims wild2 for respawn hook test")
		clearEvents()
		assert(MeteorService.HandleCharacterLifecycleReset(u1), "Character reset handler releases active claim")
		assert(wildObj2.ClaimedByUserId == nil and isPromptEnabled(wildObj2), "Respawn/death reset unlocks meteor and re-enables prompt")
		assert(countEvents("ClaimReleased", wildObj2.UID) == 1, "Respawn/death reset broadcasts ClaimReleased")

		-- 4e. Leave while claiming wild meteor while Plot 1 has an unclaimed starter meteor
		p1.StarterMeteorCompleted = false
		local sLeaveOk, _, u1Starter = MeteorService.SpawnStarterMeteorForPlot(1, u1, 5060)
		assert(sLeaveOk and u1Starter ~= nil, "Unclaimed starter spawns for u1 leave test")
		local u1StarterObj = u1Starter :: ActiveMeteor
		table.insert(createdMeteorUIDs, u1StarterObj.UID)

		local cWildLeave = MeteorService.StartCrackAtPosition(u1, wildObj2.Position, wildObj2.UID, 5061)
		assert(cWildLeave.Ok and not isPromptEnabled(wildObj2), "u1 claims wild2 before leaving")
		clearEvents()
		MeteorService.HandlePlotReleased(1, u1)
		MeteorService.HandlePlayerClosing(u1)

		assert(activeMeteors[u1StarterObj.UID] == nil, "Plot 1 starter despawned on leave")
		assert(
			countEvents("Despawn", u1StarterObj.UID) == 1 and countEvents("ClaimReleased", u1StarterObj.UID) == 0,
			"Unclaimed starter emits single Despawn and no ClaimReleased"
		)
		assert(activeMeteors[wildObj2.UID] ~= nil and wildObj2.ClaimedByUserId == nil and isPromptEnabled(wildObj2), "Wild meteor released and prompt re-enabled on leave")
		assert(
			countEvents("ClaimReleased", wildObj2.UID) == 1 and countEvents("Despawn", wildObj2.UID) == 0,
			"Leave while claiming wild meteor emits ClaimReleased"
		)

		local u2ReclaimLeave = MeteorService.StartCrackAtPosition(u2, wildObj2.Position, wildObj2.UID, 5062)
		assert(u2ReclaimLeave.Ok, "Remaining player can claim wild meteor right after claimer leaves")
		assert(MeteorService.ReleaseClaimForUserId(u2), "Release u2 reclaim before Plot 2 leave test")

		-- 4f. Leave while claiming own starter meteor -> single Despawn and zero redundant ClaimReleased
		p2.StarterMeteorCompleted = false
		local s2LeaveOk, _, u2Starter = MeteorService.SpawnStarterMeteorForPlot(2, u2, 5070)
		assert(s2LeaveOk and u2Starter ~= nil, "Starter spawns for u2 own-starter leave test")
		local u2StarterObj = u2Starter :: ActiveMeteor
		table.insert(createdMeteorUIDs, u2StarterObj.UID)

		local cStarterLeave = MeteorService.StartCrackAtPosition(u2, u2StarterObj.Position, u2StarterObj.UID, 5071)
		assert(cStarterLeave.Ok and not isPromptEnabled(u2StarterObj), "u2 claims own starter before leaving")
		clearEvents()
		MeteorService.HandlePlotReleased(2, u2)
		MeteorService.HandlePlayerClosing(u2)

		assert(activeMeteors[u2StarterObj.UID] == nil, "Own starter despawned cleanly on leave")
		assert(
			countEvents("Despawn", u2StarterObj.UID) == 1 and countEvents("ClaimReleased") == 0,
			"Leaving while claiming own starter emits single Despawn and zero ClaimReleased"
		)
		assert(activeClaimsByUserId[u2] == nil, "Leaving claim entry cleared")
		passed += 1

		-- 5. S3-04 Regression: Lured Frost disconnect single-Despawn, wild claim preservation, and Ridge Astral saturation
		wildNodeCooldownUntil = {}
		pendingAstralFall = nil
		activeAstralUID = nil
		nextAstralFallAt = 0
		removeMeteorInternal(wildObj2.UID)

		DataService.BeginMockSession(u1, nil)
		DataService.CompleteMockSession(u1, 5100)
		DataService.BeginMockSession(u2, nil)
		DataService.CompleteMockSession(u2, 5100)
		local p1Lure = DataService.GetProfileByUserId(u1) :: Types.PlayerProfileData
		local p2Lure = DataService.GetProfileByUserId(u2) :: Types.PlayerProfileData
		p1Lure.Upgrades["FrostCracker"] = true
		p2Lure.Upgrades["FrostCracker"] = true
		assert((PlotService.AssignPlotForUserId(u1, "MeteorTester1", p1Lure, nil)), "Suite 5 assign u1 Plot 1")
		assert((PlotService.AssignPlotForUserId(u2, "MeteorTester2", p2Lure, nil)), "Suite 5 assign u2 Plot 2")
		lastLureClockByUserId[u1] = nil
		lastLureClockByUserId[u2] = nil

		-- 5a: Leaving while claiming own personal Lured Frost meteor emits single Despawn and zero ClaimReleased
		local l1Ok, _, l1Raw = MeteorService.SpawnLuredMeteorForPlayer(u1, "MeteorTester1", "Frost", 5105)
		assert(l1Ok and l1Raw ~= nil, "Suite 5a spawns lured Frost L1")
		local l1Obj = l1Raw :: ActiveMeteor
		table.insert(createdMeteorUIDs, l1Obj.UID)
		local l1Claim = MeteorService.StartCrackAtPosition(u1, l1Obj.Position, l1Obj.UID, 5106)
		assert(l1Claim.Ok, "u1 claims own L1")

		clearEvents()
		MeteorService.HandlePlotReleased(1, u1)
		MeteorService.HandlePlayerClosing(u1)
		assert(activeMeteors[l1Obj.UID] == nil, "Suite 5a L1 despawned on disconnect")
		assert(countEvents("Despawn", l1Obj.UID) == 1 and countEvents("ClaimReleased", l1Obj.UID) == 0, "Own lured disconnect emits single Despawn and zero ClaimReleased")
		assert(activeClaimsByUserId[u1] == nil and wildNodeOccupied[l1Obj.NodeName] == nil, "Suite 5a cleared claim & node occupancy")

		-- 5b: Leaving while holding unclaimed L2 + claimed wild meteor W3 despawns L2 AND unlocks W3 for u2
		PlotService.ReleasePlotForUserId(u1)
		DataService.EndMockSession(u1)
		DataService.BeginMockSession(u1, nil)
		DataService.CompleteMockSession(u1, 5120)
		local p1LureB = DataService.GetProfileByUserId(u1) :: Types.PlayerProfileData
		p1LureB.Upgrades["FrostCracker"] = true
		assert((PlotService.AssignPlotForUserId(u1, "MeteorTester1", p1LureB, nil)), "Suite 5b reassign u1 Plot 1")
		lastLureClockByUserId[u1] = nil
		wildNodeCooldownUntil = {}

		local l2Ok, _, l2Raw = MeteorService.SpawnLuredMeteorForPlayer(u1, "MeteorTester1", "Frost", 5120)
		assert(l2Ok and l2Raw ~= nil, "Suite 5b spawns unclaimed L2")
		local l2Obj = l2Raw :: ActiveMeteor
		table.insert(createdMeteorUIDs, l2Obj.UID)

		local w3Ok, _, w3Raw = MeteorService.SpawnWildMeteorAtNode("MeteorNode_1", "Ember", 5120)
		assert(w3Ok and w3Raw ~= nil, "Suite 5b spawns wild W3")
		local w3Obj = w3Raw :: ActiveMeteor
		table.insert(createdMeteorUIDs, w3Obj.UID)

		local w3Claim = MeteorService.StartCrackAtPosition(u1, w3Obj.Position, w3Obj.UID, 5121)
		assert(w3Claim.Ok, "u1 claims wild W3 while L2 sits unclaimed")
		clearEvents()
		MeteorService.HandlePlotReleased(1, u1)
		MeteorService.HandlePlayerClosing(u1)

		assert(activeMeteors[l2Obj.UID] == nil and countEvents("Despawn", l2Obj.UID) == 1, "Unclaimed L2 despawns cleanly on disconnect")
		assert(activeMeteors[w3Obj.UID] ~= nil and w3Obj.ClaimedByUserId == nil and isPromptEnabled(w3Obj), "Claimed wild W3 stays alive & unlocked on disconnect")
		assert(countEvents("ClaimReleased", w3Obj.UID) == 1, "Claimed wild W3 emits ClaimReleased on disconnect")
		assert(MeteorService.StartCrackAtPosition(u2, w3Obj.Position, w3Obj.UID, 5122).Ok, "u2 immediately reclaims unlocked wild W3")
		removeMeteorInternal(w3Obj.UID)

		-- 5c: Full North Ridge saturated by 4 paid Frost Lures rejects TriggerAstralFallNow without evicting lures, then recovers when 1 frees
		wildNodeCooldownUntil = {}
		local ridgeUsers = { -930011, -930012, -930013, -930014 }
		local ridgeLures: { ActiveMeteor } = {}
		for i, rUid in ipairs(ridgeUsers) do
			MeteorService.HandlePlayerClosing(rUid)
			local rOk, _, rRaw = MeteorService.SpawnLuredMeteorForPlayer(rUid, "Ridge_" .. tostring(i), "Frost", 5150)
			assert(rOk and rRaw ~= nil, "Suite 5c lure " .. tostring(i) .. " spawns on North Ridge")
			local rObj = rRaw :: ActiveMeteor
			table.insert(createdMeteorUIDs, rObj.UID)
			table.insert(ridgeLures, rObj)
		end

		local fullAfOk, fullAfReason = MeteorService.TriggerAstralFallNow(5200)
		assert(not fullAfOk and fullAfReason == "NoRidgeNodeAvailable", "Full Ridge lured meteors must NOT be evicted by Astral Fall")
		for i, rObj in ipairs(ridgeLures) do
			assert(activeMeteors[rObj.UID] ~= nil, "Paid lured meteor #" .. tostring(i) .. " preserved intact")
		end

		MeteorService.HandlePlayerClosing(ridgeUsers[1])
		local recoveredAfOk, recoveredAfReason = MeteorService.TriggerAstralFallNow(5206)
		assert(recoveredAfOk and recoveredAfReason == "Incoming", "Astral Fall recovers immediately once one Ridge node frees")
		for idx = 2, #ridgeUsers do
			MeteorService.HandlePlayerClosing(ridgeUsers[idx])
		end

		-- 5d: S4-02 / S4-03 Hero Meteor template clone, rescue prompt, ground & claim verification
		pendingAstralFall = nil
		activeAstralUID = nil
		wildNodeCooldownUntil = {}

		local prevStarCracker = p2Lure.Upgrades["StarCracker"]
		p2Lure.Upgrades["FrostCracker"] = true
		p2Lure.Upgrades["StarCracker"] = true

		local createdMRoot = false
		local createdMFold = false
		local createdMMock = false
		local mOk, mErr = pcall(function()
			local root = ReplicatedStorage:FindFirstChild(Constants.ASSET_TEMPLATES_FOLDER_NAME)
			if root == nil then
				root = Instance.new("Folder")
				root.Name = Constants.ASSET_TEMPLATES_FOLDER_NAME
				root.Parent = ReplicatedStorage
				createdMRoot = true
			end
			local mFold = (root :: Instance):FindFirstChild("Meteors")
			if mFold == nil then
				mFold = Instance.new("Folder")
				mFold.Name = "Meteors"
				mFold.Parent = root
				createdMFold = true
			end

			local traitSpecs: { { Trait: Types.MeteorTraitId, NodeName: string } } = {
				{ Trait = "Ember", NodeName = "MeteorNode_2" },
				{ Trait = "Frost", NodeName = "MeteorNode_4" },
				{ Trait = "Astral", NodeName = "MeteorNode_5" },
			}
			local specsToVerify: { { Trait: Types.MeteorTraitId, NodeName: string, IsMock: boolean } } = {}
			for _, spec in ipairs(traitSpecs) do
				local existingTmpl = (mFold :: Instance):FindFirstChild(spec.Trait)
				if existingTmpl ~= nil and existingTmpl:IsA("Model") then
					table.insert(specsToVerify, {
						Trait = spec.Trait,
						NodeName = spec.NodeName,
						IsMock = false,
					})
				end
			end

			if #specsToVerify == 0 then
				local tmpl = Instance.new("Model")
				tmpl.Name = "Ember"
				local rBody = Instance.new("Part")
				rBody.Name = "RockBody"
				rBody.Size = Vector3.new(3.6, 3.0, 3.6)
				rBody.Position = Vector3.new(0, 1.5, 0)
				rBody.Parent = tmpl
				local cShards = Instance.new("Part")
				cShards.Name = "CoreShards"
				cShards.Size = Vector3.new(1.5, 1.5, 1.5)
				cShards.Position = Vector3.new(0, 2.0, 0)
				cShards.Parent = tmpl
				local tCrest = Instance.new("Part")
				tCrest.Name = "TraitCrest"
				tCrest.Size = Vector3.new(0.8, 1.8, 0.8)
				tCrest.Position = Vector3.new(0, 3.0, 0)
				tCrest.Parent = tmpl
				tmpl.PrimaryPart = rBody
				tmpl.Parent = mFold
				createdMMock = true
				table.insert(specsToVerify, {
					Trait = "Ember",
					NodeName = "MeteorNode_2",
					IsMock = true,
				})
			end

			for idx, spec in ipairs(specsToVerify) do
				wildNodeCooldownUntil = {}
				local testClock = 5220 + idx * 10
				local tmplOk, _, tmplRaw = MeteorService.SpawnWildMeteorAtNode(spec.NodeName, spec.Trait, testClock)
				assert(tmplOk and tmplRaw ~= nil, "Template meteor spawns cleanly: " .. spec.Trait)
				local tmplMeteor = tmplRaw :: ActiveMeteor
				table.insert(createdMeteorUIDs, tmplMeteor.UID)
				local tmplModel = tmplMeteor.Model
				assert(tmplModel ~= nil and tmplModel.PrimaryPart ~= nil and tmplModel.PrimaryPart.Name == "RockBody", spec.Trait .. " PrimaryPart must be RockBody")
				assert(tmplModel:FindFirstChild("CoreShards") ~= nil and tmplModel:FindFirstChild("TraitCrest") ~= nil, spec.Trait .. " retains CoreShards & TraitCrest")

				local promptInst = tmplModel.PrimaryPart:FindFirstChild("RescuePrompt")
				assert(promptInst ~= nil and promptInst:IsA("ProximityPrompt") and promptInst.Enabled == true and promptInst.ActionText == "Crack", spec.Trait .. " RescuePrompt missing or disabled")
				assert(tmplModel.PrimaryPart:FindFirstChild("MeteorLabel") ~= nil, spec.Trait .. " MeteorLabel missing")
				assert(CollectionService:HasTag(tmplModel, Constants.TAG_ACTIVE_METEOR), spec.Trait .. " missing StarfallActiveMeteor tag")

				local rockMinY, rockMaxY = measureMeteorWorldYBounds(tmplModel, true)
				local minDeltaY = math.abs(rockMinY - tmplMeteor.Position.Y)
				local rockHeight = rockMaxY - rockMinY
				assert(minDeltaY <= 0.02, string.format("%s ground pivot offset %.4f > 0.02", spec.Trait, minDeltaY))
				assert(rockHeight <= Constants.MAX_CRITTER_DISPLAY_HEIGHT, string.format("%s height %.3f > %.1f", spec.Trait, rockHeight, Constants.MAX_CRITTER_DISPLAY_HEIGHT))

				local partCount = 0
				for _, d in ipairs(tmplModel:GetDescendants()) do
					if d:IsA("BasePart") then
						partCount += 1
					end
				end

				local claimRes = MeteorService.StartCrackAtPosition(u2, tmplMeteor.Position, tmplMeteor.UID, testClock + 1)
				assert(claimRes.Ok == true, spec.Trait .. " StartCrackAtPosition claim failed: " .. tostring(claimRes.Reason))
				MeteorService.ReleaseClaimForUserId(u2)
				removeMeteorInternal(tmplMeteor.UID)

				if spec.IsMock then
					print("[MeteorService] Runtime Template Verified Ember (mock fallback — import Ember/Frost/Astral into ReplicatedStorage.AssetTemplates.Meteors before S4-03 soak)")
				else
					print(string.format(
						"[MeteorService] Runtime Template Verified %-7s | Parts=%d | Height=%.3f | MinDeltaY=%.4f | PromptOk=true | ClaimOk=true",
						spec.Trait,
						partCount,
						rockHeight,
						minDeltaY
					))
				end
			end
		end)
		p2Lure.Upgrades["StarCracker"] = prevStarCracker
		if createdMMock then
			local root = ReplicatedStorage:FindFirstChild(Constants.ASSET_TEMPLATES_FOLDER_NAME)
			local mFold = if root ~= nil then root:FindFirstChild("Meteors") else nil
			local mockEmber = if mFold ~= nil then mFold:FindFirstChild("Ember") else nil
			if mockEmber ~= nil then
				mockEmber:Destroy()
			end
		end
		if createdMFold then
			local root = ReplicatedStorage:FindFirstChild(Constants.ASSET_TEMPLATES_FOLDER_NAME)
			local mFold = if root ~= nil then root:FindFirstChild("Meteors") else nil
			if mFold ~= nil then
				mFold:Destroy()
			end
		end
		if createdMRoot then
			local root = ReplicatedStorage:FindFirstChild(Constants.ASSET_TEMPLATES_FOLDER_NAME)
			if root ~= nil then
				root:Destroy()
			end
		end
		assert(mOk, tostring(mErr))
		passed += 1

		-- 6. S4-04 Starter meteor persistence lifecycle (mid-crack leave, full-bag, replay, rejoin same/fresh, hatch+sell, legacy, other eligible player)
		local s404Store, s404StoreName = DataService.CreateIsolatedMockStoreWithMapForTest("S404Starter")
		local s404Map = DataService.GetUserMockStoreMapForTest(s404StoreName)
		local uFresh = -930401
		local uLegacyDone = -930402
		local uLegacyAmbig = -930403
		local uOther = -930404
		local s404Users = { uFresh, uLegacyDone, uLegacyAmbig, uOther }

		local s6Ok, s6Err = pcall(function()
			local tS4 = 6000
			-- 6a. Fresh player joins & leaves mid-crack -> starter remains available on rejoin
			assert(DataService.StartProfileSessionForUserId(uFresh, nil, { Store = s404Store, NowClock = tS4 }), "S404 fresh join")
			local pFresh = DataService.GetProfileByUserId(uFresh) :: Types.PlayerProfileData
			assert(pFresh.StarterMeteorCompleted == false, "Fresh profile starts with StarterMeteorCompleted=false")
			local okPlotF, _, plotF = PlotService.AssignPlotForUserId(uFresh, "S404Fresh", pFresh, nil)
			assert(okPlotF and plotF ~= nil, "Assign plot for fresh player")
			local spOk1, _, mFresh1 = MeteorService.SpawnStarterMeteorForPlot(plotF :: number, uFresh, tS4)
			assert(spOk1 and mFresh1 ~= nil, "Starter spawns for fresh player")
			local stMid = MeteorService.StartCrackAtPosition(uFresh, (mFresh1 :: ActiveMeteor).Position, (mFresh1 :: ActiveMeteor).UID, tS4 + 1)
			assert(stMid.Ok, "Start crack before mid-crack disconnect")

			MeteorService.HandlePlotReleased(plotF :: number, uFresh)
			PlotService.ReleasePlotForUserId(uFresh)
			DataService.EndSession(uFresh)
			assert(DataService.WaitForUserFinalSave(uFresh, 2), "Save after mid-crack leave")

			assert(DataService.StartProfileSessionForUserId(uFresh, nil, { Store = s404Store, NowClock = tS4 + 5 }), "Rejoin after mid-crack leave")
			pFresh = DataService.GetProfileByUserId(uFresh) :: Types.PlayerProfileData
			assert(pFresh.StarterMeteorCompleted == false and countBagItems(pFresh) == 0, "Mid-crack leave preserves starter eligibility and grants 0 pods")
			local okPlotF2, _, plotF2 = PlotService.AssignPlotForUserId(uFresh, "S404Fresh", pFresh, nil)
			assert(okPlotF2 and plotF2 ~= nil, "Reassign plot after mid-crack leave")
			local spOk2, _, mFresh2 = MeteorService.SpawnStarterMeteorForPlot(plotF2 :: number, uFresh, tS4 + 5)
			assert(spOk2 and mFresh2 ~= nil, "Starter respawns after mid-crack leave")
			local mFreshObj = mFresh2 :: ActiveMeteor

			-- 6b. Full-bag failure at start and mid-crack keeps starter available
			local fillerUids: { string } = {}
			for i = 1, Constants.MAX_BAG_CAPACITY do
				local uid = "s404-fill-" .. tostring(i)
				assert(EconomyService.GrantPodToProfile(pFresh, "CinderPup", tS4 + 5, uid).Ok, "Fill bag slot " .. tostring(i))
				table.insert(fillerUids, uid)
			end
			local fullStart = MeteorService.StartCrackAtPosition(uFresh, mFreshObj.Position, mFreshObj.UID, tS4 + 6)
			assert(not fullStart.Ok and fullStart.Reason == "BagFull", "Full bag rejects starter crack start")

			pFresh.Items[fillerUids[Constants.MAX_BAG_CAPACITY]] = nil
			local okStartBeforeFill = MeteorService.StartCrackAtPosition(uFresh, mFreshObj.Position, mFreshObj.UID, tS4 + 7)
			assert(okStartBeforeFill.Ok and okStartBeforeFill.AttemptNonce ~= nil, "Starter crack starts with 9/10 bag")
			assert(EconomyService.GrantPodToProfile(pFresh, "CinderPup", tS4 + 7, fillerUids[Constants.MAX_BAG_CAPACITY]).Ok, "Refill 10th slot mid-crack")
			local fullFinish = MeteorService.FinishCrackAtPosition(uFresh, mFreshObj.Position, mFreshObj.UID, okStartBeforeFill.AttemptNonce :: string, tS4 + 8, rng)
			assert(not fullFinish.Ok and fullFinish.Reason == "BagFull", "Full bag mid-crack rejects starter finish")
			assert(pFresh.StarterMeteorCompleted == false and activeMeteors[mFreshObj.UID] ~= nil and isPromptEnabled(mFreshObj), "Full-bag finish leaves starter eligible and prompt re-enabled")

			-- 6c. Completion & repeated completion rejection
			for _, fUid in ipairs(fillerUids) do
				pFresh.Items[fUid] = nil
			end
			local okStartDone = MeteorService.StartCrackAtPosition(uFresh, mFreshObj.Position, mFreshObj.UID, tS4 + 9)
			assert(okStartDone.Ok and okStartDone.AttemptNonce ~= nil, "Starter crack starts with free bag")
			local okFinishDone = MeteorService.FinishCrackAtPosition(uFresh, mFreshObj.Position, mFreshObj.UID, okStartDone.AttemptNonce :: string, tS4 + 10, rng)
			assert(okFinishDone.Ok and okFinishDone.SpeciesId == "StarSlime" and okFinishDone.ItemUID ~= nil, "Starter crack succeeds")
			local starterItemUid = okFinishDone.ItemUID :: string
			assert(pFresh.StarterMeteorCompleted == true and countBagItems(pFresh) == 1, "Starter completion atomically sets flag and grants 1 pod")

			local replayFinish = MeteorService.FinishCrackAtPosition(uFresh, mFreshObj.Position, mFreshObj.UID, okStartDone.AttemptNonce :: string, tS4 + 11, rng)
			assert(not replayFinish.Ok, "Replayed FinishCrackAtPosition rejected")
			local repeatGrant = EconomyService.GrantStarterPodToProfile(pFresh, tS4 + 11, "s404-dup")
			assert(not repeatGrant.Ok and repeatGrant.Reason == "StarterAlreadyCompleted", "Repeat GrantStarterPodToProfile rejected")
			local respawnDoneOk, respawnDoneReason = MeteorService.SpawnStarterMeteorForPlot(plotF2 :: number, uFresh, tS4 + 11)
			assert(not respawnDoneOk and respawnDoneReason == "StarterAlreadyCompleted" and countBagItems(pFresh) == 1, "Completed starter never respawns or double-grants")

			-- 6d. Rejoin same server & simulated fresh server with unopened pod in bag
			MeteorService.HandlePlotReleased(plotF2 :: number, uFresh)
			PlotService.ReleasePlotForUserId(uFresh)
			DataService.EndSession(uFresh)
			assert(DataService.WaitForUserFinalSave(uFresh, 2), "Save with unopened starter pod")

			assert(DataService.StartProfileSessionForUserId(uFresh, nil, { Store = s404Store, NowClock = tS4 + 20 }), "Rejoin same server with unopened pod")
			pFresh = DataService.GetProfileByUserId(uFresh) :: Types.PlayerProfileData
			assert(pFresh.StarterMeteorCompleted == true and pFresh.Items[starterItemUid] ~= nil and pFresh.Items[starterItemUid].State == "PodInBag", "Unopened starter pod and completion persist on rejoin")
			local okPlotF3, _, plotF3 = PlotService.AssignPlotForUserId(uFresh, "S404Fresh", pFresh, nil)
			assert(okPlotF3 and plotF3 ~= nil, "Reassign plot on same-server rejoin")
			local spRejoinSame, spRejoinSameReason = MeteorService.SpawnStarterMeteorForPlot(plotF3 :: number, uFresh, tS4 + 20)
			assert(not spRejoinSame and spRejoinSameReason == "StarterAlreadyCompleted", "Same-server rejoin skips starter respawn")

			MeteorService.HandlePlotReleased(plotF3 :: number, uFresh)
			PlotService.ReleasePlotForUserId(uFresh)
			DataService.EndSession(uFresh)
			assert(DataService.WaitForUserFinalSave(uFresh, 2), "Save before fresh-server reload")
			DataService.ClearTestTrackingForUserIds({ uFresh })

			assert(DataService.StartProfileSessionForUserId(uFresh, nil, { Store = s404Store, NowClock = tS4 + 25 }), "Rejoin fresh server with unopened pod")
			pFresh = DataService.GetProfileByUserId(uFresh) :: Types.PlayerProfileData
			assert(pFresh.StarterMeteorCompleted == true and pFresh.Items[starterItemUid] ~= nil, "Fresh-server rejoin preserves unopened pod & completion")
			local okPlotF4, _, plotF4 = PlotService.AssignPlotForUserId(uFresh, "S404Fresh", pFresh, nil)
			assert(okPlotF4 and plotF4 ~= nil, "Assign plot on fresh-server rejoin")
			local spRejoinFresh, spRejoinFreshReason = MeteorService.SpawnStarterMeteorForPlot(plotF4 :: number, uFresh, tS4 + 25)
			assert(not spRejoinFresh and spRejoinFreshReason == "StarterAlreadyCompleted", "Fresh-server rejoin skips starter respawn")

			-- 6e. Hatch and sell StarSlime, then rejoin -> still completed & skips respawn
			local incRes = EconomyService.StartIncubateOnProfile(pFresh, "Incubator_1", starterItemUid, tS4 + 26)
			assert(incRes.Ok, "Incubate starter StarSlime pod")
			local matureAt = pFresh.Items[starterItemUid].MaturesAt :: number
			local hatchRes = EconomyService.HatchFromSlotOnProfile(pFresh, "Incubator_1", matureAt, rng)
			assert(hatchRes.Ok, "Hatch starter StarSlime pod")
			local sellRes = EconomyService.SellCritterOnProfile(pFresh, starterItemUid, matureAt + 1)
			assert(sellRes.Ok and pFresh.Items[starterItemUid] == nil and pFresh.Coins > 0, "Sell hatched starter StarSlime")

			MeteorService.HandlePlotReleased(plotF4 :: number, uFresh)
			PlotService.ReleasePlotForUserId(uFresh)
			DataService.EndSession(uFresh)
			assert(DataService.WaitForUserFinalSave(uFresh, 2), "Save after selling starter critter")
			DataService.ClearTestTrackingForUserIds({ uFresh })

			assert(DataService.StartProfileSessionForUserId(uFresh, nil, { Store = s404Store, NowClock = matureAt + 10 }), "Rejoin after selling starter critter")
			pFresh = DataService.GetProfileByUserId(uFresh) :: Types.PlayerProfileData
			assert(pFresh.StarterMeteorCompleted == true and pFresh.Coins > 0 and next(pFresh.Items) == nil, "Post-sell rejoin preserves Coins, 0 items, and StarterMeteorCompleted=true")
			local okPlotF5, _, plotF5 = PlotService.AssignPlotForUserId(uFresh, "S404Fresh", pFresh, nil)
			assert(okPlotF5 and plotF5 ~= nil, "Assign plot after selling critter")
			local spAfterSell, spAfterSellReason = MeteorService.SpawnStarterMeteorForPlot(plotF5 :: number, uFresh, matureAt + 10)
			assert(not spAfterSell and spAfterSellReason == "StarterAlreadyCompleted", "Post-sell rejoin skips starter respawn")

			-- 6f. Legacy profiles (completed with StarSlime evidence vs ambiguous without StarSlime)
			s404Map[Constants.PROFILE_KEY_PREFIX .. tostring(uLegacyDone)] = {
				Data = {
					Data = {
						SchemaVersion = 1,
						Coins = 30,
						Items = {
							["leg-pod"] = {
								UID = "leg-pod",
								SpeciesId = "StarSlime",
								Variant = "Normal",
								State = "PodInBag",
								CreatedAt = 1000,
							},
						},
						Slots = {},
						Upgrades = {},
						DiscoveredSpecies = {},
					},
					MetaData = { ProfileCreateTime = 1, SessionLoadCount = 1, LastUpdate = 1, MetaTags = {} },
					GlobalUpdates = { 0, {} },
				},
				CreatedTime = 1,
				UpdatedTime = 1,
				VersionId = 1,
				UserIds = {},
				MetaData = {},
			}
			s404Map[Constants.PROFILE_KEY_PREFIX .. tostring(uLegacyAmbig)] = {
				Data = {
					Data = {
						SchemaVersion = 1,
						Coins = 60,
						Items = {},
						Slots = {},
						Upgrades = {},
						DiscoveredSpecies = {},
					},
					MetaData = { ProfileCreateTime = 1, SessionLoadCount = 1, LastUpdate = 1, MetaTags = {} },
					GlobalUpdates = { 0, {} },
				},
				CreatedTime = 1,
				UpdatedTime = 1,
				VersionId = 1,
				UserIds = {},
				MetaData = {},
			}

			assert(DataService.StartProfileSessionForUserId(uLegacyDone, nil, { Store = s404Store, NowClock = tS4 + 30 }), "Load legacy done user")
			local pLegDone = DataService.GetProfileByUserId(uLegacyDone) :: Types.PlayerProfileData
			assert(pLegDone.StarterMeteorCompleted == true, "Legacy completed user skips starter")
			local okPlotLD, _, plotLD = PlotService.AssignPlotForUserId(uLegacyDone, "S404LegDone", pLegDone, nil)
			assert(okPlotLD and plotLD ~= nil, "Assign plot for legacy done user")
			local spLD, spLDReason = MeteorService.SpawnStarterMeteorForPlot(plotLD :: number, uLegacyDone, tS4 + 30)
			assert(not spLD and spLDReason == "StarterAlreadyCompleted", "Legacy completed user does not spawn starter")

			assert(DataService.StartProfileSessionForUserId(uLegacyAmbig, nil, { Store = s404Store, NowClock = tS4 + 30 }), "Load legacy ambiguous user")
			local pLegAmbig = DataService.GetProfileByUserId(uLegacyAmbig) :: Types.PlayerProfileData
			assert(pLegAmbig.StarterMeteorCompleted == false, "Ambiguous legacy user stays eligible")
			local okPlotLA, _, plotLA = PlotService.AssignPlotForUserId(uLegacyAmbig, "S404LegAmbig", pLegAmbig, nil)
			assert(okPlotLA and plotLA ~= nil, "Assign plot for legacy ambiguous user")
			local spLA, _, mLA = MeteorService.SpawnStarterMeteorForPlot(plotLA :: number, uLegacyAmbig, tS4 + 30)
			assert(spLA and mLA ~= nil, "Ambiguous legacy user spawns starter meteor")
			removeMeteorInternal((mLA :: ActiveMeteor).UID)

			-- 6g. Another eligible player on the same server still gets working starter spawn & crack
			assert(DataService.StartProfileSessionForUserId(uOther, nil, { Store = s404Store, NowClock = tS4 + 30 }), "Load other eligible player")
			local pOther = DataService.GetProfileByUserId(uOther) :: Types.PlayerProfileData
			local okPlotO, _, plotO = PlotService.AssignPlotForUserId(uOther, "S404Other", pOther, nil)
			assert(okPlotO and plotO ~= nil, "Assign plot for other eligible player")
			local spO, _, mO = MeteorService.SpawnStarterMeteorForPlot(plotO :: number, uOther, tS4 + 30)
			assert(spO and mO ~= nil, "Other eligible player spawns starter meteor")
			local stO = MeteorService.StartCrackAtPosition(uOther, (mO :: ActiveMeteor).Position, (mO :: ActiveMeteor).UID, tS4 + 31)
			assert(stO.Ok and stO.AttemptNonce ~= nil, "Other eligible player starts starter crack")
			local finO = MeteorService.FinishCrackAtPosition(uOther, (mO :: ActiveMeteor).Position, (mO :: ActiveMeteor).UID, stO.AttemptNonce :: string, tS4 + 32, rng)
			assert(finO.Ok and finO.SpeciesId == "StarSlime" and pOther.StarterMeteorCompleted == true, "Other eligible player finishes starter crack")
		end)

		for _, sUid in ipairs(s404Users) do
			local pId = PlotService.GetAssignedPlotId(sUid)
			if pId ~= nil then
				MeteorService.HandlePlotReleased(pId, sUid)
				PlotService.ReleasePlotForUserId(sUid)
			end
			DataService.EndSession(sUid)
		end
		DataService.ClearTestTrackingForUserIds(s404Users)
		assert(s6Ok, tostring(s6Err))
		passed += 1
	end)

	lifecycleObserver = nil
	activeAstralUID = nil
	pendingAstralFall = nil
	nextAstralFallAt = 0
	for _, uid in ipairs(createdMeteorUIDs) do
		removeMeteorInternal(uid)
	end
	wildNodeCooldownUntil = {}
	for _, rUid in ipairs({ -930011, -930012, -930013, -930014 }) do
		activeClaimsByUserId[rUid] = nil
		luredMeteorByUserId[rUid] = nil
		lastLureClockByUserId[rUid] = nil
	end
	activeClaimsByUserId[u1] = nil
	activeClaimsByUserId[u2] = nil
	activeClaimsByUserId[uUnassigned] = nil
	luredMeteorByUserId[u1] = nil
	luredMeteorByUserId[u2] = nil
	lastLureClockByUserId[u1] = nil
	lastLureClockByUserId[u2] = nil
	PlotService.ReleasePlotForUserId(u1)
	PlotService.ReleasePlotForUserId(u2)
	DataService.EndMockSession(u1)
	DataService.EndMockSession(u2)
	DataService.EndMockSession(uUnassigned)

	if not testOk then
		error(testErr)
	end

	return passed
end

return MeteorService
