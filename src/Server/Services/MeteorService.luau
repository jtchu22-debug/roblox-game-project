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
	table.freeze({ Trait = "Ember" :: Types.MeteorTraitId, Weight = 45 }),
	table.freeze({ Trait = "Frost" :: Types.MeteorTraitId, Weight = 30 }),
	table.freeze({ Trait = "Astral" :: Types.MeteorTraitId, Weight = 25 }),
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
local activeHumanoidConnsByUserId: { [number]: { RBXScriptConnection } } = {}
local lifecycleObserver: ((payload: { [string]: any }) -> ())? = nil
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

local function createMeteorModel(meteor: ActiveMeteor): Model?
	local folder = activeMeteorsFolder
	if folder == nil then
		return nil
	end

	local traitDef = MeteorConfig.ById[meteor.Trait]
	local isWildAstral = meteor.Trait == "Astral" and not meteor.IsStarter
	local model = Instance.new("Model")
	model.Name = (if meteor.IsStarter then "StarterMeteor_" else "WildMeteor_") .. string.sub(meteor.UID, 1, 8)
	model:SetAttribute("MeteorUID", meteor.UID)
	model:SetAttribute("Trait", meteor.Trait)
	model:SetAttribute("IsStarter", meteor.IsStarter)
	model:SetAttribute("OwnerUserId", meteor.OwnerUserId or 0)
	CollectionService:AddTag(model, Constants.TAG_ACTIVE_METEOR)

	local basePos = meteor.Position + Vector3.new(0, if isWildAstral then 2.4 else 1.8, 0)
	local body = Instance.new("Part")
	body.Name = "RockBody"
	body.Size = if isWildAstral then Vector3.new(5.2, 4.4, 5.2) else Vector3.new(3.8, 3.2, 3.8)
	body.CFrame = CFrame.new(basePos) * CFrame.Angles(0, math.rad(((string.byte(meteor.UID, 1) or 0) * 37) % 360), 0)
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
	core.Size = if isWildAstral then Vector3.new(2.4, 5.4, 2.4) else Vector3.new(1.8, 3.8, 1.8)
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
		ring.Size = if isWildAstral then Vector3.new(0.45, 7.8, 7.8) else Vector3.new(0.35, 6.2, 6.2)
		ring.CFrame = body.CFrame * CFrame.new(0, 0.6, 0) * CFrame.Angles(0.25, 0, math.rad(90))
		ring.Color = traitDef.TrailColor
		ring.Material = Enum.Material.Neon
		ring.Transparency = 0.25
		ring.Anchored = true
		ring.CanCollide = false
		ring.Parent = model

		if isWildAstral then
			local beacon = Instance.new("Part")
			beacon.Name = "AstralBeacon"
			beacon.Size = Vector3.new(1.1, 32, 1.1)
			beacon.CFrame = body.CFrame * CFrame.new(0, 17, 0)
			beacon.Color = traitDef.CoreColor
			beacon.Material = Enum.Material.Neon
			beacon.Transparency = 0.62
			beacon.Anchored = true
			beacon.CanCollide = false
			beacon.CanQuery = false
			beacon.CanTouch = false
			beacon.Parent = model
		end
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "MeteorLabel"
	gui.Size = if isWildAstral then UDim2.fromOffset(230, 52) else UDim2.fromOffset(190, 44)
	gui.StudsOffset = if isWildAstral then Vector3.new(0, 5.6, 0) else Vector3.new(0, 4.2, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = if isWildAstral then 140 else 95
	gui.Adornee = body
	gui.Parent = body

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(24, 22, 38)
	label.BackgroundTransparency = 0.2
	label.TextColor3 = if isWildAstral then traitDef.CoreColor else traitDef.TrailColor
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = if meteor.IsStarter
		then "STARTER METEOR"
		elseif isWildAstral then "[ASTRAL - RARE]\nStar Cracker (Solar Golem!)"
		else string.format("[%s] Meteor", traitDef.IconText)
	label.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RescuePrompt"
	prompt.ObjectText = if meteor.IsStarter
		then "Starter Meteor"
		elseif isWildAstral then "Astral Meteor (Needs Star Cracker)"
		else traitDef.DisplayName
	prompt.ActionText = if isWildAstral then "Break Astral Core" else "Rescue Star-Pod"
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
	local uid = HttpService:GenerateGUID(false)
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
	if meteor.IsStarter and meteor.OwnerUserId ~= userId then
		return { Ok = false, Reason = "NotStarterOwner" }
	end

	-- Enforce required Tool upgrade BEFORE claiming so locked players cannot reserve a shared Astral meteor.
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

function MeteorService.HandlePlotReleased(plotId: number, userId: number): ()
	local starterUid = starterByPlotId[plotId]
	if starterUid ~= nil then
		removeMeteorInternal(starterUid)
		publishMeteorLifecycle({
			Action = "Despawn",
			MeteorUID = starterUid,
		})
	end

	MeteorService.ReleaseClaimForUserId(userId)
	disconnectCharacterListeners(userId)
	starterClaimedByUserId[userId] = nil
end

function MeteorService.HandlePlayerClosing(userId: number): ()
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

local function populateWildMeteorsUpToCap(nowClock: number): ()
	local activeWildAstral = 0
	for _, meteor in pairs(activeMeteors) do
		if not meteor.IsStarter and meteor.Trait == "Astral" then
			activeWildAstral += 1
		end
	end

	while MeteorService.GetActiveWildMeteorCount() < Constants.MAX_ACTIVE_WILD_METEORS do
		local spawned = false
		for _, node in ipairs(wildNodes) do
			local nodeName = node.Name
			local cooldownUntil = wildNodeCooldownUntil[nodeName] or 0
			if wildNodeOccupied[nodeName] == nil and nowClock >= cooldownUntil then
				local traitOverride: Types.MeteorTraitId? = if activeWildAstral == 0 then "Astral" else nil
				local ok, _, meteor = MeteorService.SpawnWildMeteorAtNode(nodeName, traitOverride, nowClock)
				if ok and meteor ~= nil then
					if meteor.Trait == "Astral" then
						activeWildAstral += 1
					end
					publishMeteorLifecycle({
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
				MeteorService.SweepActiveClaims(nowClock)
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
		assert(countBagItems(p1) == p1BagBeforeStarter + 1, "Starter rescue grants exactly 1 pod")
		assert(activeMeteors[starterObj.UID] == nil, "Starter meteor despawned after grant")
		assert(countEvents("Despawn", starterObj.UID) == 1 and countEvents("ClaimReleased", starterObj.UID) == 0, "Starter completion emits single Despawn and zero ClaimReleased")
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

		-- 3. Invalid/out-of-range start, OutOfRange & BagFull finish release meteor + emit ClaimReleased + recover prompt
		local wOk2, _, wild2 = MeteorService.SpawnWildMeteorAtNode("MeteorNode_2", "Frost", 5010)
		assert(wOk2 and wild2 ~= nil, "Wild meteor 2 spawns")
		local wildObj2 = wild2 :: ActiveMeteor
		table.insert(createdMeteorUIDs, wildObj2.UID)

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
		for i = 1, Constants.MAX_BAG_CAPACITY do
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
		starterClaimedByUserId[u1] = nil
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
		starterClaimedByUserId[u2] = nil
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
	end)

	lifecycleObserver = nil
	for _, uid in ipairs(createdMeteorUIDs) do
		removeMeteorInternal(uid)
	end
	wildNodeCooldownUntil = {}
	activeClaimsByUserId[u1] = nil
	activeClaimsByUserId[u2] = nil
	activeClaimsByUserId[uUnassigned] = nil
	starterClaimedByUserId[u1] = nil
	starterClaimedByUserId[u2] = nil
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
