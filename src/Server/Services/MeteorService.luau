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

local WILD_TRAIT_WEIGHTS: { { Trait: Types.MeteorTraitId, Weight: number } } = table.freeze({
	table.freeze({ Trait = "Ember" :: Types.MeteorTraitId, Weight = 50 }),
	table.freeze({ Trait = "Frost" :: Types.MeteorTraitId, Weight = 35 }),
	table.freeze({ Trait = "Astral" :: Types.MeteorTraitId, Weight = 15 }),
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
local starterClaimedByUserId: { [number]: boolean } = {}
local activeClaimsByUserId: { [number]: ActiveClaim } = {}
local characterConnsByUserId: { [number]: { RBXScriptConnection } } = {}
local watcherRunning = false

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

local function createMeteorModel(meteor: ActiveMeteor): Model?
	local folder = activeMeteorsFolder
	if folder == nil then
		return nil
	end

	local traitDef = MeteorConfig.ById[meteor.Trait]
	local model = Instance.new("Model")
	model.Name = (if meteor.IsStarter then "StarterMeteor_" else "WildMeteor_") .. string.sub(meteor.UID, 1, 8)
	model:SetAttribute("MeteorUID", meteor.UID)
	model:SetAttribute("Trait", meteor.Trait)
	model:SetAttribute("IsStarter", meteor.IsStarter)
	model:SetAttribute("OwnerUserId", meteor.OwnerUserId or 0)
	CollectionService:AddTag(model, Constants.TAG_ACTIVE_METEOR)

	local basePos = meteor.Position + Vector3.new(0, 1.8, 0)
	local body = Instance.new("Part")
	body.Name = "RockBody"
	body.Size = Vector3.new(3.8, 3.2, 3.8)
	body.CFrame = CFrame.new(basePos) * CFrame.Angles(0, math.rad((#meteor.UID * 37) % 360), 0)
	body.Color = traitDef.RockColor
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.Parent = model
	model.PrimaryPart = body

	local core = Instance.new("Part")
	core.Name = "CoreCrystal"
	core.Size = Vector3.new(1.8, 3.8, 1.8)
	core.CFrame = body.CFrame * CFrame.new(0, 0.7, 0) * CFrame.Angles(0.15, 0.4, -0.15)
	core.Color = traitDef.CoreColor
	core.Material = Enum.Material.Neon
	core.Anchored = true
	core.CanCollide = false
	core.Parent = model

	-- Color-independent shape silhouette for accessibility
	if traitDef.ShapeStyle == "FlameCrest" then
		for _, xOff in ipairs({ -1.1, 1.1 }) do
			local crest = Instance.new("WedgePart")
			crest.Name = "FlameHorn"
			crest.Size = Vector3.new(0.8, 2.2, 1.4)
			crest.CFrame = body.CFrame * CFrame.new(xOff, 1.8, 0) * CFrame.Angles(0, 0, if xOff < 0 then 0.25 else -0.25)
			crest.Color = traitDef.TrailColor
			crest.Material = Enum.Material.Neon
			crest.Anchored = true
			crest.CanCollide = false
			crest.Parent = model
		end
	elseif traitDef.ShapeStyle == "IceSpikes" then
		for i = 1, 3 do
			local ang = math.rad(i * 120)
			local spike = Instance.new("Part")
			spike.Name = "IceSpike_" .. tostring(i)
			spike.Size = Vector3.new(0.9, 2.8, 0.9)
			spike.CFrame = body.CFrame * CFrame.new(math.cos(ang) * 1.4, 1.6, math.sin(ang) * 1.4) * CFrame.Angles(math.sin(ang) * 0.4, 0, -math.cos(ang) * 0.4)
			spike.Color = traitDef.TrailColor
			spike.Material = Enum.Material.Neon
			spike.Anchored = true
			spike.CanCollide = false
			spike.Parent = model
		end
	else
		local ring = Instance.new("Part")
		ring.Name = "AstralRing"
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.35, 6.2, 6.2)
		ring.CFrame = body.CFrame * CFrame.new(0, 0.6, 0) * CFrame.Angles(0.25, 0, math.rad(90))
		ring.Color = traitDef.TrailColor
		ring.Material = Enum.Material.Neon
		ring.Transparency = 0.25
		ring.Anchored = true
		ring.CanCollide = false
		ring.Parent = model
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "MeteorLabel"
	gui.Size = UDim2.fromOffset(190, 44)
	gui.StudsOffset = Vector3.new(0, 4.2, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 95
	gui.Adornee = body
	gui.Parent = body

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(24, 22, 38)
	label.BackgroundTransparency = 0.2
	label.TextColor3 = traitDef.TrailColor
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = if meteor.IsStarter
		then "STARTER METEOR"
		else string.format("[%s] Meteor", traitDef.IconText)
	label.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RescuePrompt"
	prompt.ObjectText = if meteor.IsStarter then "Starter Meteor" else traitDef.DisplayName
	prompt.ActionText = "Rescue Star-Pod"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Constants.PROMPT_ACTIVATION_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Enabled = true
	prompt.Parent = body

	model.Parent = folder
	return model
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

local function removeMeteorInternal(meteorUID: string): ()
	local meteor = activeMeteors[meteorUID]
	if meteor == nil then
		return
	end

	if meteor.IsStarter and meteor.PlotId ~= nil then
		if starterByPlotId[meteor.PlotId] == meteorUID then
			starterByPlotId[meteor.PlotId] = nil
		end
	elseif not meteor.IsStarter then
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
	end
	return true
end

function MeteorService.SpawnStarterMeteorForPlot(plotId: number, ownerUserId: number, nowClock: number?): (boolean, string, ActiveMeteor?)
	if starterClaimedByUserId[ownerUserId] then
		return false, "StarterAlreadyClaimed", nil
	end
	if starterByPlotId[plotId] ~= nil then
		local existing = activeMeteors[starterByPlotId[plotId]]
		return true, "AlreadyPresent", existing
	end

	local node = starterNodesByPlotId[plotId]
	if node == nil then
		return false, "MissingStarterNode", nil
	end

	local uid = "starter-" .. HttpService:GenerateGUID(false)
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

function MeteorService.SpawnWildMeteorAtNode(nodeName: string, traitOverride: Types.MeteorTraitId?, nowClock: number?): (boolean, string, ActiveMeteor?)
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
	local uid = "wild-" .. HttpService:GenerateGUID(false)
	local meteor: ActiveMeteor = {
		UID = uid,
		Trait = trait,
		NodeName = nodeName,
		Position = targetNode.Position,
		IsStarter = false,
		OwnerUserId = nil,
		PlotId = nil,
		ClaimedByUserId = nil,
		SpawnedAt = nowClock or workspace:GetServerTimeNow(),
		Model = nil,
	}
	meteor.Model = createMeteorModel(meteor)
	activeMeteors[uid] = meteor
	wildNodeOccupied[nodeName] = uid

	return true, "Spawned", meteor
end

function MeteorService.GetActiveWildMeteorCount(): number
	local count = 0
	for _ in pairs(wildNodeOccupied) do
		count += 1
	end
	return count
end

function MeteorService.SweepExpiredClaims(nowClock: number): number
	local releasedCount = 0
	local toRelease: { number } = {}
	for userId, claim in pairs(activeClaimsByUserId) do
		if nowClock > claim.Deadline then
			table.insert(toRelease, userId)
		end
	end
	for _, userId in ipairs(toRelease) do
		if MeteorService.ReleaseClaimForUserId(userId) then
			releasedCount += 1
		end
	end
	return releasedCount
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
	if meteor.IsStarter and meteor.OwnerUserId ~= userId then
		return { Ok = false, Reason = "NotStarterOwner" }
	end
	if meteor.ClaimedByUserId ~= nil then
		return { Ok = false, Reason = "MeteorAlreadyClaimed" }
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

	if nowClock > claim.Deadline then
		MeteorService.ReleaseClaimForUserId(userId)
		return { Ok = false, Reason = "ClaimExpired" }
	end

	if (nowClock - claim.StartedAt) < Constants.MIN_CRACK_DURATION_SECONDS then
		return { Ok = false, Reason = "TooFast" }
	end

	if not isFiniteVector3(worldPos) then
		return { Ok = false, Reason = "OutOfRange" }
	end
	local distance = (worldPos - meteor.Position).Magnitude
	if distance ~= distance or math.abs(distance) == math.huge or distance > Constants.MAX_CRACK_FINISH_DISTANCE then
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

	local grantRes = EconomyService.GrantPodToProfile(profile, speciesId, nowClock)
	if not grantRes.Ok then
		MeteorService.ReleaseClaimForUserId(userId)
		return { Ok = false, Reason = grantRes.Reason or "GrantFailed" }
	end

	-- Pod grant succeeded; now atomically consume claim and despawn meteor.
	activeClaimsByUserId[userId] = nil
	if meteor.IsStarter then
		starterClaimedByUserId[userId] = true
	else
		wildNodeCooldownUntil[meteor.NodeName] = nowClock + Constants.WILD_METEOR_RESPAWN_SECONDS
	end

	removeMeteorInternal(meteorUID)

	return {
		Ok = true,
		MeteorUID = meteorUID,
		ItemUID = grantRes.ItemUID,
		SpeciesId = speciesId,
	}
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

local function handleStartCrackRequest(player: Player, meteorUID: string): NetworkService.RemoteResult
	local pos = getLiveCharacterPosition(player)
	if pos == nil then
		return { Ok = false, Reason = "CharacterUnavailable" }
	end
	local res = MeteorService.StartCrackAtPosition(player.UserId, pos, meteorUID, workspace:GetServerTimeNow())
	if res.Ok then
		NetworkService.BroadcastMeteorLifecycle({
			Action = "Claimed",
			MeteorUID = meteorUID,
			ClaimedBy = player.UserId,
		})
	end
	return res
end

local function handleFinishCrackRequest(player: Player, meteorUID: string, attemptNonce: string): NetworkService.RemoteResult
	local pos = getLiveCharacterPosition(player)
	if pos == nil then
		return { Ok = false, Reason = "CharacterUnavailable" }
	end
	local res = MeteorService.FinishCrackAtPosition(player.UserId, pos, meteorUID, attemptNonce, workspace:GetServerTimeNow())
	if res.Ok then
		DataService.SendOwnerStateSnapshot(player)
		NetworkService.BroadcastMeteorLifecycle({
			Action = "Despawn",
			MeteorUID = meteorUID,
		})
	elseif res.Reason == "BagFull" or res.Reason == "ClaimExpired" then
		NetworkService.BroadcastMeteorLifecycle({
			Action = "ClaimReleased",
			MeteorUID = meteorUID,
		})
	end
	return res
end

local function disconnectCharacterListeners(userId: number): ()
	local conns = characterConnsByUserId[userId]
	if conns ~= nil then
		for _, conn in ipairs(conns) do
			conn:Disconnect()
		end
		characterConnsByUserId[userId] = nil
	end
end

local function attachCharacterClaimCleanup(player: Player): ()
	local userId = player.UserId
	disconnectCharacterListeners(userId)

	local conns: { RBXScriptConnection } = {}
	local function bindHumanoid(char: Model)
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			table.insert(conns, hum.Died:Connect(function()
				if MeteorService.ReleaseClaimForUserId(userId) then
					-- Claim released cleanly on death
				end
			end))
		end
	end

	if player.Character ~= nil then
		bindHumanoid(player.Character)
	end
	table.insert(conns, player.CharacterAdded:Connect(function(newChar: Model)
		MeteorService.ReleaseClaimForUserId(userId)
		bindHumanoid(newChar)
	end))
	table.insert(conns, player.CharacterRemoving:Connect(function()
		MeteorService.ReleaseClaimForUserId(userId)
	end))

	characterConnsByUserId[userId] = conns
end

local function populateWildMeteorsUpToCap(nowClock: number): ()
	while MeteorService.GetActiveWildMeteorCount() < Constants.MAX_ACTIVE_WILD_METEORS do
		local spawned = false
		for _, node in ipairs(wildNodes) do
			local nodeName = node.Name
			local cooldownUntil = wildNodeCooldownUntil[nodeName] or 0
			if wildNodeOccupied[nodeName] == nil and nowClock >= cooldownUntil then
				local ok, _, meteor = MeteorService.SpawnWildMeteorAtNode(nodeName, nil, nowClock)
				if ok and meteor ~= nil then
					NetworkService.BroadcastMeteorLifecycle({
						Action = "Spawn",
						MeteorUID = meteor.UID,
						Trait = meteor.Trait,
						Position = meteor.Position,
					})
					spawned = true
					break
				end
			end
		end
		if not spawned then
			break
		end
	end
end

function MeteorService.Init(self: typeof(MeteorService)): ()
	local root = PlotService.GetGreyboxRoot()
	local crater = root:FindFirstChild("CentralCrater") :: Model

	wildNodes = {}
	local meteorSpawnFolder = crater:FindFirstChild("MeteorSpawnNodes") :: Folder
	for i = 1, 6 do
		local node = meteorSpawnFolder:FindFirstChild("MeteorNode_" .. tostring(i)) :: BasePart
		assert(node ~= nil and CollectionService:HasTag(node, Constants.TAG_METEOR_NODE), "Invalid MeteorNode_" .. tostring(i))
		table.insert(wildNodes, node)
	end

	starterNodesByPlotId = {}
	local starterFolder = crater:FindFirstChild("StarterMeteorNodes") :: Folder
	for plotId = 1, Constants.MAX_PLOTS_PROTOTYPE do
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

	print(string.format("[MeteorService] Discovered %d wild nodes and %d starter nodes.", #wildNodes, Constants.MAX_PLOTS_PROTOTYPE))
end

function MeteorService.Start(self: typeof(MeteorService)): ()
	NetworkService.BindStartCrackHandler(handleStartCrackRequest)
	NetworkService.BindFinishCrackHandler(handleFinishCrackRequest)

	PlotService.OnPlotAssigned(function(plotId: number, userId: number)
		local player = Players:GetPlayerByUserId(userId)
		if player ~= nil then
			attachCharacterClaimCleanup(player)
		end
		local ok, _, meteor = MeteorService.SpawnStarterMeteorForPlot(plotId, userId, workspace:GetServerTimeNow())
		if ok and meteor ~= nil then
			NetworkService.BroadcastMeteorLifecycle({
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
		MeteorService.ReleaseClaimForUserId(userId)
		disconnectCharacterListeners(userId)
		starterClaimedByUserId[userId] = nil
		local starterUid = starterByPlotId[plotId]
		if starterUid ~= nil then
			removeMeteorInternal(starterUid)
			NetworkService.BroadcastMeteorLifecycle({
				Action = "Despawn",
				MeteorUID = starterUid,
			})
		end
	end)

	DataService.OnPlayerClosing(function(player: Player)
		MeteorService.ReleaseClaimForUserId(player.UserId)
		disconnectCharacterListeners(player.UserId)
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
				ClaimedBy = meteor.ClaimedByUserId,
			})
		end
	end)

	-- Seed initial wild meteors in the Crater immediately
	populateWildMeteorsUpToCap(workspace:GetServerTimeNow())

	if not watcherRunning then
		watcherRunning = true
		task.spawn(function()
			while watcherRunning do
				task.wait(0.5)
				local nowClock = workspace:GetServerTimeNow()
				MeteorService.SweepExpiredClaims(nowClock)
				populateWildMeteorsUpToCap(nowClock)
			end
		end)
	end
end

function MeteorService.RunSelfTest(): number
	local passed = 0
	local rng = Random.new(99)
	local u1 = -930001
	local u2 = -930002
	local uUnassigned = -930003

	PlotService.ReleasePlotForUserId(u1)
	PlotService.ReleasePlotForUserId(u2)
	DataService.EndMockSession(u1)
	DataService.EndMockSession(u2)
	DataService.EndMockSession(uUnassigned)

	DataService.BeginMockSession(u1, nil)
	DataService.CompleteMockSession(u1, 5000)
	DataService.BeginMockSession(u2, nil)
	DataService.CompleteMockSession(u2, 5000)

	local p1 = DataService.GetProfileByUserId(u1) :: Types.PlayerProfileData
	local p2 = DataService.GetProfileByUserId(u2) :: Types.PlayerProfileData

	assert((PlotService.AssignPlotForUserId(u1, "MeteorTester1", p1, nil)), "Assign Plot 1")
	assert((PlotService.AssignPlotForUserId(u2, "MeteorTester2", p2, nil)), "Assign Plot 2")

	-- 1. Starter meteor scoping & guaranteed StarSlime drop
	local sOk, _, starter1 = MeteorService.SpawnStarterMeteorForPlot(1, u1, 5000)
	assert(sOk and starter1 ~= nil, "Starter meteor spawns for Plot 1")
	local starterObj = starter1 :: ActiveMeteor

	-- Player 2 cannot claim Player 1's starter meteor
	local crossStart = MeteorService.StartCrackAtPosition(u2, starterObj.Position, starterObj.UID, 5001)
	assert(not crossStart.Ok and crossStart.Reason == "NotStarterOwner", "Other player blocked from starter meteor")

	-- Unassigned user blocked even with Ready session
	DataService.BeginMockSession(uUnassigned, nil)
	DataService.CompleteMockSession(uUnassigned, 5000)
	local noPlotStart = MeteorService.StartCrackAtPosition(uUnassigned, starterObj.Position, starterObj.UID, 5001)
	assert(not noPlotStart.Ok and noPlotStart.Reason == "NoAssignedPlot", "Unassigned player blocked")
	DataService.EndMockSession(uUnassigned)

	-- Player 1 completes starter crack cleanly
	local p1Start = MeteorService.StartCrackAtPosition(u1, starterObj.Position, starterObj.UID, 5001)
	assert(p1Start.Ok and p1Start.AttemptNonce ~= nil, "Owner starts starter crack")
	local p1Finish = MeteorService.FinishCrackAtPosition(u1, starterObj.Position, starterObj.UID, p1Start.AttemptNonce :: string, 5002, rng)
	assert(p1Finish.Ok and p1Finish.SpeciesId == "StarSlime", "Starter meteor guarantees StarSlime")
	assert(activeMeteors[starterObj.UID] == nil, "Starter meteor despawned after grant")
	passed += 1

	-- 2. Simultaneous 2-player claim race, forged nonce, TooFast, and replay rejection
	local wOk, _, wild1 = MeteorService.SpawnWildMeteorAtNode("MeteorNode_1", "Astral", 5003)
	assert(wOk and wild1 ~= nil, "Wild meteor spawns on MeteorNode_1")
	local wildObj = wild1 :: ActiveMeteor

	local race1 = MeteorService.StartCrackAtPosition(u1, wildObj.Position, wildObj.UID, 5004)
	assert(race1.Ok and race1.AttemptNonce ~= nil, "Player 1 wins claim")
	local race2 = MeteorService.StartCrackAtPosition(u2, wildObj.Position, wildObj.UID, 5004)
	assert(not race2.Ok and race2.Reason == "MeteorAlreadyClaimed", "Player 2 blocked from claimed meteor")

	-- Forged nonce rejected
	local forged = MeteorService.FinishCrackAtPosition(u1, wildObj.Position, wildObj.UID, "forged-nonce", 5005, rng)
	assert(not forged.Ok and forged.Reason == "InvalidClaim", "Forged nonce rejected")

	-- Premature finish (< 0.4s) rejected without removing meteor
	local tooFast = MeteorService.FinishCrackAtPosition(u1, wildObj.Position, wildObj.UID, race1.AttemptNonce :: string, 5004.1, rng)
	assert(not tooFast.Ok and tooFast.Reason == "TooFast" and activeMeteors[wildObj.UID] ~= nil, "TooFast finish rejected and meteor preserved")

	-- Valid finish succeeds, and replay of same nonce fails
	local wildFinish = MeteorService.FinishCrackAtPosition(u1, wildObj.Position, wildObj.UID, race1.AttemptNonce :: string, 5005.0, rng)
	assert(wildFinish.Ok and activeMeteors[wildObj.UID] == nil, "Valid finish grants pod and despawns meteor")
	local replay = MeteorService.FinishCrackAtPosition(u1, wildObj.Position, wildObj.UID, race1.AttemptNonce :: string, 5005.2, rng)
	assert(not replay.Ok and replay.Reason == "InvalidClaim", "Nonce replay rejected")
	passed += 1

	-- 3. Non-finite/out-of-range, BagFull at finish preserving meteor, and claim timeout release
	local wOk2, _, wild2 = MeteorService.SpawnWildMeteorAtNode("MeteorNode_2", "Frost", 5010)
	assert(wOk2 and wild2 ~= nil, "Wild meteor 2 spawns")
	local wildObj2 = wild2 :: ActiveMeteor

	local nanStart = MeteorService.StartCrackAtPosition(u2, Vector3.new(0 / 0, 0, 0), wildObj2.UID, 5011)
	assert(not nanStart.Ok and nanStart.Reason == "OutOfRange", "NaN start pos rejected")
	local farStart = MeteorService.StartCrackAtPosition(u2, wildObj2.Position + Vector3.new(50, 0, 0), wildObj2.UID, 5011)
	assert(not farStart.Ok and farStart.Reason == "OutOfRange", "Out-of-range start rejected")

	-- Claim with 1 slot left, fill bag before finish -> finish must fail cleanly and preserve meteor!
	local c2 = MeteorService.StartCrackAtPosition(u2, wildObj2.Position, wildObj2.UID, 5011)
	assert(c2.Ok and c2.AttemptNonce ~= nil, "u2 claims wild2")
	for i = 1, Constants.MAX_BAG_CAPACITY do
		EconomyService.GrantPodToProfile(p2, "StarSlime", 5011, "fill-m-" .. tostring(i))
	end
	local bagFullFinish = MeteorService.FinishCrackAtPosition(u2, wildObj2.Position, wildObj2.UID, c2.AttemptNonce :: string, 5012, rng)
	assert(not bagFullFinish.Ok and bagFullFinish.Reason == "BagFull", "BagFull at finish rejected")
	assert(activeMeteors[wildObj2.UID] ~= nil and wildObj2.ClaimedByUserId == nil, "Meteor preserved & claim released on BagFull")

	-- Timeout sweep frees expired claim for another player
	local cExpire = MeteorService.StartCrackAtPosition(u1, wildObj2.Position, wildObj2.UID, 5015)
	assert(cExpire.Ok, "u1 claims wild2")
	assert(MeteorService.SweepExpiredClaims(5015 + Constants.CRACK_CLAIM_TIMEOUT_SECONDS + 1) == 1, "Expired claim swept cleanly")
	assert(wildObj2.ClaimedByUserId == nil, "Meteor unlocked after expiry")

	-- Clean up all test meteors, plots, and sessions
	removeMeteorInternal(wildObj2.UID)
	wildNodeCooldownUntil = {}
	starterClaimedByUserId[u1] = nil
	starterClaimedByUserId[u2] = nil
	PlotService.ReleasePlotForUserId(u1)
	PlotService.ReleasePlotForUserId(u2)
	DataService.EndMockSession(u1)
	DataService.EndMockSession(u2)
	passed += 1

	return passed
end

return MeteorService
