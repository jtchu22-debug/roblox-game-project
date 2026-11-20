--!strict
--[[
	Service: PlotService
	Purpose: Validates or creates the greybox map on Init, assigns/releases unique Ranch Plots per player,
	         enforces server-side plot ownership and station proximity authorization for both prompts and remotes,
	         and replicates whitelisted PublicPlotDTO snapshots.
	Connections: Coordinates with GreyboxBuilder, NetworkService, DataService, and EconomyService.
	How to Test in Studio: Press Play (F5) and test 2-Player Local Server to verify unique plot spawns,
	                       prompt interactivity, cross-plot rejection, and clean leave release.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Types = require(Shared:WaitForChild("Types"))
local ConfigFolder = Shared:WaitForChild("Config")
local CritterConfig = require(ConfigFolder:WaitForChild("CritterConfig"))
local UpgradeConfig = require(ConfigFolder:WaitForChild("UpgradeConfig"))
local UtilFolder = Shared:WaitForChild("Util")
local EconomyMath = require(UtilFolder:WaitForChild("EconomyMath"))
local FormatUtil = require(UtilFolder:WaitForChild("FormatUtil"))
local GreyboxBuilder = require(UtilFolder:WaitForChild("GreyboxBuilder"))

local ServicesFolder = script.Parent
local DataService = require(ServicesFolder:WaitForChild("DataService"))
local EconomyService = require(ServicesFolder:WaitForChild("EconomyService"))
local NetworkService = require(ServicesFolder:WaitForChild("NetworkService"))

type PlotAssignment = {
	PlotId: number,
	UserId: number,
	DisplayName: string,
	Player: Player?,
	Profile: Types.PlayerProfileData,
	CharacterAddedConn: RBXScriptConnection?,
}

type PlotPromptSet = {
	Incubators: { [string]: ProximityPrompt },
	Pens: { [string]: ProximityPrompt },
	SellStand: ProximityPrompt?,
	LureStand: ProximityPrompt?,
	Upgrades: { [string]: ProximityPrompt },
}

local PALETTE = {
	OrbitalCyan = Color3.fromRGB(65, 210, 255),
	StarlightGold = Color3.fromRGB(255, 205, 45),
	LockedSlate = Color3.fromRGB(140, 145, 165),
	MeadowMint = Color3.fromRGB(95, 215, 145),
	AstralViolet = Color3.fromRGB(205, 115, 255),
}

local PlotService = {
	Name = "PlotService",
}

local greyboxRoot: Folder? = nil
local plotModelsById: { [number]: Model } = {}
local plotPromptsById: { [number]: PlotPromptSet } = {}
local assignmentsByPlotId: { [number]: PlotAssignment } = {}
local plotIdByUserId: { [number]: number } = {}
local plotRevisionByPlotId: { [number]: number } = {}
local incubatorMatureNotified: { [number]: { [string]: boolean } } = {}
local plotAssignedCallbacks: { (plotId: number, userId: number) -> () } = {}
local plotReleasedCallbacks: { (plotId: number, userId: number) -> () } = {}
local globalPlotsRevision = 0
local incubatorWatcherRunning = false

local function isFiniteVector3(v: Vector3): boolean
	return v.X == v.X
		and math.abs(v.X) ~= math.huge
		and v.Y == v.Y
		and math.abs(v.Y) ~= math.huge
		and v.Z == v.Z
		and math.abs(v.Z) ~= math.huge
end

local function getPlotModel(plotId: number): Model?
	return plotModelsById[plotId]
end

local function setPartLabelState(part: BasePart, guiName: string, text: string, visible: boolean): ()
	local gui = part:FindFirstChild(guiName)
	if gui and gui:IsA("BillboardGui") then
		gui.Enabled = visible
		local lbl = gui:FindFirstChild("Label")
		if lbl and lbl:IsA("TextLabel") then
			lbl.Text = text
		end
	end
end

local function setPartLabelText(part: BasePart, guiName: string, text: string): ()
	setPartLabelState(part, guiName, text, true)
end

local function createPromptOnPart(parentPart: BasePart, promptName: string, objectText: string, actionText: string): ProximityPrompt
	local existing = parentPart:FindFirstChild(promptName)
	if existing and existing:IsA("ProximityPrompt") then
		existing.MaxActivationDistance = Constants.PROMPT_ACTIVATION_DISTANCE
		return existing
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = promptName
	prompt.ObjectText = objectText
	prompt.ActionText = actionText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Constants.PROMPT_ACTIVATION_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = parentPart
	return prompt
end

local function selectDeterministicPodInBag(profile: Types.PlayerProfileData): string?
	local candidates: { Types.CritterItemRecord } = {}
	for _, item in pairs(profile.Items) do
		if item.State == "PodInBag" then
			table.insert(candidates, item)
		end
	end
	if #candidates == 0 then
		return nil
	end
	table.sort(candidates, function(a, b)
		if a.CreatedAt ~= b.CreatedAt then
			return a.CreatedAt < b.CreatedAt
		end
		return a.UID < b.UID
	end)
	return candidates[1].UID
end

local function selectDeterministicHatchedCritter(profile: Types.PlayerProfileData, preferHighestRate: boolean): string?
	local candidates: { Types.CritterItemRecord } = {}
	for _, item in pairs(profile.Items) do
		if item.State == "HatchedInBag" then
			table.insert(candidates, item)
		end
	end
	if #candidates == 0 then
		return nil
	end
	table.sort(candidates, function(a, b)
		local rateA = CritterConfig.ById[a.SpeciesId].CoinsPerSecond
		local rateB = CritterConfig.ById[b.SpeciesId].CoinsPerSecond
		if rateA ~= rateB then
			if preferHighestRate then
				return rateA > rateB
			else
				return rateA < rateB
			end
		end
		if a.CreatedAt ~= b.CreatedAt then
			return a.CreatedAt < b.CreatedAt
		end
		return a.UID < b.UID
	end)
	return candidates[1].UID
end

function PlotService.ResolveStationAnchor(plotId: number, stationKind: string, targetId: string): BasePart?
	local plotModel = getPlotModel(plotId)
	if plotModel == nil then
		return nil
	end

	if stationKind == "Incubator" then
		local incubators = plotModel:FindFirstChild("Incubators")
		local pad = if incubators then incubators:FindFirstChild(targetId) else nil
		return if pad and pad:IsA("BasePart") then pad else nil
	elseif stationKind == "Pen" then
		local pen = plotModel:FindFirstChild("HabitatPen")
		local penSlots = if pen then pen:FindFirstChild("PenSlots") else nil
		local pad = if penSlots then penSlots:FindFirstChild(targetId) else nil
		return if pad and pad:IsA("BasePart") then pad else nil
	elseif stationKind == "SellStand" then
		local stand = plotModel:FindFirstChild("SellStand")
		return if stand and stand:IsA("BasePart") then stand else nil
	elseif stationKind == "LureStand" then
		local lure = plotModel:FindFirstChild("LureStand")
		return if lure and lure:IsA("BasePart") then lure else nil
	elseif stationKind == "UpgradePad" then
		local board = plotModel:FindFirstChild("UpgradeBoard")
		local pad = if board then board:FindFirstChild("UpgradePad_" .. targetId) else nil
		return if pad and pad:IsA("BasePart") then pad else nil
	end

	return nil
end

function PlotService.AuthorizeStationAtPosition(
	userId: number,
	worldPos: Vector3,
	stationKind: string,
	targetId: string
): (boolean, string)
	local plotId = plotIdByUserId[userId]
	if plotId == nil then
		return false, "NoAssignedPlot"
	end

	local anchor = PlotService.ResolveStationAnchor(plotId, stationKind, targetId)
	if anchor == nil then
		return false, "InvalidStationAnchor"
	end

	if not isFiniteVector3(worldPos) then
		return false, "OutOfRange"
	end

	local distance = (worldPos - anchor.Position).Magnitude
	if distance ~= distance
		or math.abs(distance) == math.huge
		or distance < 0
		or distance > Constants.MAX_STATION_INTERACT_DISTANCE
	then
		return false, "OutOfRange"
	end

	return true, "Authorized"
end

function PlotService.AuthorizePlayerStation(player: Player, stationKind: string, targetId: string): (boolean, string)
	local character = player.Character
	if character == nil then
		return false, "CharacterUnavailable"
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoid.Health <= 0 or rootPart == nil or not rootPart:IsA("BasePart") then
		return false, "CharacterUnavailable"
	end

	return PlotService.AuthorizeStationAtPosition(player.UserId, rootPart.Position, stationKind, targetId)
end

function PlotService.BuildPublicPlotDTO(plotId: number): Types.PublicPlotDTO
	local assignment = assignmentsByPlotId[plotId]
	local rev = plotRevisionByPlotId[plotId] or 1

	local unlockedUpgrades: { [string]: boolean } = {}
	local activePenVisuals: { [string]: Types.PublicPenVisual } = {}
	local incubatorVisuals: { [string]: Types.PublicIncubatorVisual } = {}

	if assignment ~= nil then
		local profile = assignment.Profile
		for upgradeId, isOwned in pairs(profile.Upgrades) do
			if isOwned == true then
				unlockedUpgrades[upgradeId] = true
			end
		end
		for slotId, itemUID in pairs(profile.Slots) do
			local item = profile.Items[itemUID]
			if item ~= nil then
				if item.State == "InPen" then
					activePenVisuals[slotId] = {
						SpeciesId = item.SpeciesId,
						Variant = item.Variant,
						FeedLevel = item.FeedLevel or 0,
					}
				elseif item.State == "Incubating" and item.MaturesAt ~= nil then
					incubatorVisuals[slotId] = {
						MaturesAt = item.MaturesAt,
					}
				end
			end
		end
	end

	return {
		PlotId = plotId,
		OwnerUserId = if assignment then assignment.UserId else 0,
		OwnerDisplayName = if assignment then assignment.DisplayName else "",
		PlotRevision = rev,
		UnlockedUpgrades = unlockedUpgrades,
		ActivePenVisuals = activePenVisuals,
		IncubatorVisuals = incubatorVisuals,
	}
end

function PlotService.BuildAllPublicPlotDTOs(): { Types.PublicPlotDTO }
	local list: { Types.PublicPlotDTO } = {}
	for plotId = 1, Constants.MAX_PLOTS_PROTOTYPE do
		table.insert(list, PlotService.BuildPublicPlotDTO(plotId))
	end
	return list
end

function PlotService.RefreshPlotWorldState(plotId: number): ()
	local plotModel = getPlotModel(plotId)
	local prompts = plotPromptsById[plotId]
	if plotModel == nil or prompts == nil then
		return
	end

	local assignment = assignmentsByPlotId[plotId]
	local nowClock = workspace:GetServerTimeNow()
	incubatorMatureNotified[plotId] = {}

	-- Update Arch Header & Neon Trim
	local arch = plotModel:FindFirstChild("RanchArch")
	if arch then
		local header = arch:FindFirstChild("Header")
		if header and header:IsA("BasePart") then
			local signText = if assignment
				then string.format("%s's Ranch", assignment.DisplayName)
				else string.format("Ranch Plot %d (Open)", plotId)
			setPartLabelText(header, "OwnerSign", signText)
		end
		local trim = arch:FindFirstChild("ArchNeonTrim")
		if trim and trim:IsA("BasePart") then
			if assignment == nil then
				trim.Color = PALETTE.LockedSlate
			elseif assignment.Profile.Upgrades["PenSlot_4"] == true then
				trim.Color = PALETTE.StarlightGold
			elseif assignment.Profile.Upgrades["PenSlot_3"] == true then
				trim.Color = PALETTE.AstralViolet
			else
				trim.Color = PALETTE.OrbitalCyan
			end
		end
	end

	local hasPodInBag = false
	local hasHatchedInBag = false
	local hasFrostCracker = false
	if assignment ~= nil then
		hasFrostCracker = assignment.Profile.Upgrades["FrostCracker"] == true
		for _, item in pairs(assignment.Profile.Items) do
			if item.State == "PodInBag" then
				hasPodInBag = true
			elseif item.State == "HatchedInBag" then
				hasHatchedInBag = true
			end
		end
	end

	-- Update SellStand Prompt & Label (visible only when holding hatched critter)
	local sellAnchor = PlotService.ResolveStationAnchor(plotId, "SellStand", "SellStand")
	if prompts.SellStand ~= nil then
		prompts.SellStand.Enabled = hasHatchedInBag
		prompts.SellStand.ActionText = "Sell"
		prompts.SellStand.ObjectText = "Critter"
	end
	if sellAnchor ~= nil then
		setPartLabelState(sellAnchor, "SellLabel", "Sell", hasHatchedInBag)
	end

	-- Update LureStand Prompt & Label (visible only once FrostCracker is owned)
	local lureAnchor = PlotService.ResolveStationAnchor(plotId, "LureStand", "LureStand")
	if prompts.LureStand ~= nil and lureAnchor ~= nil then
		if hasFrostCracker then
			prompts.LureStand.Enabled = true
			prompts.LureStand.ActionText = string.format("Lure %d", Constants.FROST_LURE_COST)
			prompts.LureStand.ObjectText = "Frost"
			lureAnchor.Color = Color3.fromRGB(45, 42, 62)
			setPartLabelState(lureAnchor, "LureLabel", string.format("Frost Lure • %d", Constants.FROST_LURE_COST), true)
		else
			prompts.LureStand.Enabled = false
			lureAnchor.Color = if assignment == nil then Color3.fromRGB(45, 42, 62) else PALETTE.LockedSlate
			setPartLabelState(lureAnchor, "LureLabel", "Frost Lure", false)
		end
	end

	-- Update Incubators
	for idx, slotId in ipairs({ "Incubator_1", "Incubator_2" }) do
		local anchor = PlotService.ResolveStationAnchor(plotId, "Incubator", slotId)
		local prompt = prompts.Incubators[slotId]
		if anchor and prompt then
			if assignment == nil then
				local defaultUnlocked = idx == 1
				prompt.Enabled = false
				anchor.Color = if defaultUnlocked then PALETTE.OrbitalCyan else PALETTE.LockedSlate
				anchor.Material = if defaultUnlocked then Enum.Material.Neon else Enum.Material.SmoothPlastic
				anchor.Transparency = if defaultUnlocked then 0.1 else 0.45
				setPartLabelState(anchor, "SlotLabel", string.format("Incubator #%d", idx), false)
			else
				local profile = assignment.Profile
				local unlocked = EconomyService.IsUnlockedIncubatorSlot(profile, slotId)
				if not unlocked then
					prompt.Enabled = false
					anchor.Color = PALETTE.LockedSlate
					anchor.Material = Enum.Material.SmoothPlastic
					anchor.Transparency = 0.45
					setPartLabelState(anchor, "SlotLabel", string.format("Incubator #%d", idx), false)
				else
					local occupantUID = profile.Slots[slotId]
					local occupant = if occupantUID then profile.Items[occupantUID] else nil
					if occupant == nil then
						prompt.Enabled = hasPodInBag
						prompt.ActionText = "Incubate"
						prompt.ObjectText = string.format("Incubator #%d", idx)
						anchor.Color = PALETTE.OrbitalCyan
						anchor.Material = Enum.Material.Neon
						anchor.Transparency = 0.1
						setPartLabelState(anchor, "SlotLabel", string.format("Incubator #%d", idx), hasPodInBag)
					else
						local mature = occupant.MaturesAt ~= nil and nowClock >= occupant.MaturesAt
						local speciesName = CritterConfig.ById[occupant.SpeciesId].DisplayName
						if mature then
							incubatorMatureNotified[plotId][slotId] = true
							prompt.Enabled = true
							prompt.ActionText = "Hatch!"
							prompt.ObjectText = speciesName
							anchor.Color = PALETTE.StarlightGold
							anchor.Material = Enum.Material.Neon
							anchor.Transparency = 0
							setPartLabelState(anchor, "SlotLabel", "HATCH!", true)
						else
							prompt.Enabled = false
							anchor.Color = PALETTE.OrbitalCyan
							anchor.Material = Enum.Material.Neon
							anchor.Transparency = 0.1
							local remaining = math.max(1, math.ceil((occupant.MaturesAt :: number) - nowClock))
							setPartLabelState(anchor, "SlotLabel", string.format("%s • %ds", speciesName, remaining), true)
						end
					end
				end
			end
		end
	end

	-- Update Pen Slots
	for idx, slotId in ipairs({ "Pen_1", "Pen_2", "Pen_3", "Pen_4" }) do
		local anchor = PlotService.ResolveStationAnchor(plotId, "Pen", slotId)
		local prompt = prompts.Pens[slotId]
		if anchor and prompt then
			if assignment == nil then
				local defaultUnlocked = idx == 1
				prompt.Enabled = false
				anchor.Color = if defaultUnlocked then PALETTE.StarlightGold else PALETTE.LockedSlate
				anchor.Transparency = if defaultUnlocked then 0.15 else 0.5
				setPartLabelState(anchor, "SlotLabel", string.format("Pen #%d", idx), false)
			else
				local profile = assignment.Profile
				local unlocked = EconomyService.IsUnlockedPenSlot(profile, slotId)
				if not unlocked then
					prompt.Enabled = false
					anchor.Color = PALETTE.LockedSlate
					anchor.Transparency = 0.5
					setPartLabelState(anchor, "SlotLabel", string.format("Pen #%d", idx), false)
				else
					local occupantUID = profile.Slots[slotId]
					local occupant = if occupantUID then profile.Items[occupantUID] else nil
					if occupant == nil then
						prompt.Enabled = hasHatchedInBag
						prompt.ActionText = "Place"
						prompt.ObjectText = string.format("Pen #%d", idx)
						anchor.Color = PALETTE.StarlightGold
						anchor.Transparency = 0.15
						setPartLabelState(anchor, "SlotLabel", string.format("Pen #%d", idx), hasHatchedInBag)
					else
						local def = CritterConfig.ById[occupant.SpeciesId]
						local effRate = EconomyMath.GetCritterCoinsPerSecond(occupant.SpeciesId, occupant.Variant, occupant.FeedLevel)
						local feedStar = if (occupant.FeedLevel or 0) >= 1 then " ★" else ""
						prompt.Enabled = true
						prompt.ActionText = "Pick Up"
						prompt.ObjectText = def.DisplayName
						anchor.Color = def.BodyColor
						anchor.Transparency = 0.05
						setPartLabelState(anchor, "SlotLabel", string.format("%s%s +%d/s", def.DisplayName, feedStar, effRate), true)
					end
				end
			end
		end
	end

	-- Update Upgrade Pads (only show labels/prompts for currently buyable next-step upgrades)
	for _, upgradeId in ipairs(UpgradeConfig.OrderedIds) do
		local def = UpgradeConfig.ById[upgradeId]
		local anchor = PlotService.ResolveStationAnchor(plotId, "UpgradePad", upgradeId)
		local prompt = prompts.Upgrades[upgradeId]
		if anchor and prompt then
			local unownedColor = if def.Id == "FrostCracker"
				then PALETTE.OrbitalCyan
				elseif def.Id == "StarCracker" then PALETTE.AstralViolet
				elseif def.Id == "PenSlot_4" then PALETTE.StarlightGold
				else PALETTE.MeadowMint
			local ownedColor = if def.SlotCategory == "Tool" then PALETTE.StarlightGold else PALETTE.OrbitalCyan
			local prereqId = def.RequiresUpgradeId
			local prereqMet = prereqId == nil
				or (assignment ~= nil and assignment.Profile.Upgrades[prereqId] == true)
			if assignment == nil then
				prompt.Enabled = false
				anchor.Color = unownedColor
				anchor.Transparency = 0
				setPartLabelState(anchor, "UpgradeLabel", def.DisplayName, false)
			elseif assignment.Profile.Upgrades[upgradeId] == true then
				prompt.Enabled = false
				anchor.Color = ownedColor
				anchor.Transparency = 0.35
				setPartLabelState(anchor, "UpgradeLabel", def.DisplayName, false)
			elseif not prereqMet and prereqId ~= nil then
				prompt.Enabled = false
				anchor.Color = PALETTE.LockedSlate
				anchor.Transparency = 0.35
				setPartLabelState(anchor, "UpgradeLabel", def.DisplayName, false)
			else
				prompt.Enabled = true
				prompt.ActionText = string.format("Buy %s", FormatUtil.FormatCoins(def.Cost))
				prompt.ObjectText = def.DisplayName
				anchor.Color = unownedColor
				anchor.Transparency = 0
				setPartLabelState(
					anchor,
					"UpgradeLabel",
					string.format("%s • %s", def.DisplayName, FormatUtil.FormatCoins(def.Cost)),
					true
				)
			end
		end
	end
end

local function broadcastAllPublicPlots(): ()
	globalPlotsRevision += 1
	NetworkService.BroadcastPublicPlots(PlotService.BuildAllPublicPlotDTOs(), globalPlotsRevision)
end

local function moveCharacterToPlot(player: Player, plotId: number, character: Model): ()
	local plotModel = getPlotModel(plotId)
	local spawnLoc = if plotModel then plotModel:FindFirstChild("SpawnPoint") else nil
	if spawnLoc and spawnLoc:IsA("SpawnLocation") then
		character:PivotTo(spawnLoc.CFrame + Vector3.new(0, 3, 0))
	end
end

function PlotService.AssignPlotForUserId(
	userId: number,
	displayName: string,
	profile: Types.PlayerProfileData,
	player: Player?
): (boolean, string, number?)
	local existingPlotId = plotIdByUserId[userId]
	if existingPlotId ~= nil then
		return true, "AlreadyAssigned", existingPlotId
	end

	local chosenPlotId: number? = nil
	for plotId = 1, Constants.MAX_PLOTS_PROTOTYPE do
		if assignmentsByPlotId[plotId] == nil then
			chosenPlotId = plotId
			break
		end
	end

	if chosenPlotId == nil then
		return false, "NoFreePlot", nil
	end

	local assignedPlotId = chosenPlotId :: number
	local charConn: RBXScriptConnection? = nil

	if player ~= nil then
		local plotModel = getPlotModel(assignedPlotId)
		local spawnLoc = if plotModel then plotModel:FindFirstChild("SpawnPoint") else nil
		if spawnLoc and spawnLoc:IsA("SpawnLocation") then
			spawnLoc.Enabled = true
			player.RespawnLocation = spawnLoc
		end

		if player.Character ~= nil then
			moveCharacterToPlot(player, assignedPlotId, player.Character)
		end
		charConn = player.CharacterAdded:Connect(function(newChar: Model)
			task.defer(function()
				if plotIdByUserId[userId] == assignedPlotId then
					moveCharacterToPlot(player, assignedPlotId, newChar)
				end
			end)
		end)
	end

	assignmentsByPlotId[assignedPlotId] = {
		PlotId = assignedPlotId,
		UserId = userId,
		DisplayName = displayName,
		Player = player,
		Profile = profile,
		CharacterAddedConn = charConn,
	}
	plotIdByUserId[userId] = assignedPlotId
	plotRevisionByPlotId[assignedPlotId] = (plotRevisionByPlotId[assignedPlotId] or 0) + 1

	PlotService.RefreshPlotWorldState(assignedPlotId)
	for _, cb in ipairs(plotAssignedCallbacks) do
		local ok, err = pcall(cb, assignedPlotId, userId)
		if not ok then
			warn("[PlotService] OnPlotAssigned callback error: " .. tostring(err))
		end
	end
	return true, "Assigned", assignedPlotId
end

function PlotService.HandlePlayerReadyAdmission(
	userId: number,
	displayName: string,
	profile: Types.PlayerProfileData,
	player: Player?
): (boolean, string, number?)
	local ok, reason, plotId = PlotService.AssignPlotForUserId(userId, displayName, profile, player)
	if not ok then
		-- Never leave an excess player Ready without a Ranch; close session and reject cleanly.
		DataService.EndMockSession(userId, player)
		if player ~= nil and player.Parent ~= nil then
			player:Kick("This prototype server is full (max 2 ranches). Please join another server.")
		end
		return false, reason, nil
	end
	return true, reason, plotId
end

function PlotService.ReleasePlotForUserId(userId: number): number?
	local plotId = plotIdByUserId[userId]
	if plotId == nil then
		return nil
	end

	local assignment = assignmentsByPlotId[plotId]
	if assignment ~= nil then
		if assignment.CharacterAddedConn ~= nil then
			assignment.CharacterAddedConn:Disconnect()
			assignment.CharacterAddedConn = nil
		end
		if assignment.Player ~= nil then
			assignment.Player.RespawnLocation = nil
		end
	end

	local plotModel = getPlotModel(plotId)
	local spawnLoc = if plotModel then plotModel:FindFirstChild("SpawnPoint") else nil
	if spawnLoc and spawnLoc:IsA("SpawnLocation") then
		spawnLoc.Enabled = false
	end

	assignmentsByPlotId[plotId] = nil
	plotIdByUserId[userId] = nil
	plotRevisionByPlotId[plotId] = (plotRevisionByPlotId[plotId] or 0) + 1

	PlotService.RefreshPlotWorldState(plotId)
	for _, cb in ipairs(plotReleasedCallbacks) do
		local ok, err = pcall(cb, plotId, userId)
		if not ok then
			warn("[PlotService] OnPlotReleased callback error: " .. tostring(err))
		end
	end
	return plotId
end

function PlotService.OnPlotAssigned(callback: (plotId: number, userId: number) -> ()): ()
	table.insert(plotAssignedCallbacks, callback)
	for plotId, assignment in pairs(assignmentsByPlotId) do
		local ok, err = pcall(callback, plotId, assignment.UserId)
		if not ok then
			warn("[PlotService] Late OnPlotAssigned callback error: " .. tostring(err))
		end
	end
end

function PlotService.OnPlotReleased(callback: (plotId: number, userId: number) -> ()): ()
	table.insert(plotReleasedCallbacks, callback)
end

function PlotService.GetAssignedPlotId(userId: number): number?
	return plotIdByUserId[userId]
end

local function wirePlotPrompts(plotId: number): ()
	local prompts: PlotPromptSet = {
		Incubators = {},
		Pens = {},
		SellStand = nil,
		LureStand = nil,
		Upgrades = {},
	}

	-- Incubator Prompts
	for idx, slotId in ipairs({ "Incubator_1", "Incubator_2" }) do
		local anchor = PlotService.ResolveStationAnchor(plotId, "Incubator", slotId)
		assert(anchor ~= nil, "Missing Incubator anchor: " .. slotId)
		local prompt = createPromptOnPart(anchor, "IncubatorPrompt", string.format("Incubator #%d", idx), "Incubate Pod")
		prompt.Triggered:Connect(function(triggeringPlayer: Player)
			local owner = assignmentsByPlotId[plotId]
			if owner == nil or owner.UserId ~= triggeringPlayer.UserId then
				return
			end
			local profile = DataService.GetProfile(triggeringPlayer)
			if profile == nil then
				return
			end
			if profile.Slots[slotId] == nil then
				local podUid = selectDeterministicPodInBag(profile)
				if podUid ~= nil then
					EconomyService.HandlePlotAction(triggeringPlayer, "StartIncubate", slotId, podUid)
				end
			else
				EconomyService.HandlePlotAction(triggeringPlayer, "Hatch", slotId, nil)
			end
		end)
		prompts.Incubators[slotId] = prompt
	end

	-- Pen Prompts
	for idx, slotId in ipairs({ "Pen_1", "Pen_2", "Pen_3", "Pen_4" }) do
		local anchor = PlotService.ResolveStationAnchor(plotId, "Pen", slotId)
		assert(anchor ~= nil, "Missing Pen anchor: " .. slotId)
		local prompt = createPromptOnPart(anchor, "PenPrompt", string.format("Pen Slot #%d", idx), "Place Critter")
		prompt.Triggered:Connect(function(triggeringPlayer: Player)
			local owner = assignmentsByPlotId[plotId]
			if owner == nil or owner.UserId ~= triggeringPlayer.UserId then
				return
			end
			local profile = DataService.GetProfile(triggeringPlayer)
			if profile == nil then
				return
			end
			if profile.Slots[slotId] == nil then
				local critterUid = selectDeterministicHatchedCritter(profile, true)
				if critterUid ~= nil then
					EconomyService.HandlePlotAction(triggeringPlayer, "PlaceInPen", slotId, critterUid)
				end
			else
				EconomyService.HandlePlotAction(triggeringPlayer, "RemoveFromPen", slotId, nil)
			end
		end)
		prompts.Pens[slotId] = prompt
	end

	-- SellStand Prompt
	local sellAnchor = PlotService.ResolveStationAnchor(plotId, "SellStand", "SellStand")
	assert(sellAnchor ~= nil, "Missing SellStand anchor")
	local sellPrompt = createPromptOnPart(sellAnchor, "SellPrompt", "Ranch Gate Stand", "Sell Hatched Critter")
	sellPrompt.Triggered:Connect(function(triggeringPlayer: Player)
		local owner = assignmentsByPlotId[plotId]
		if owner == nil or owner.UserId ~= triggeringPlayer.UserId then
			return
		end
		local profile = DataService.GetProfile(triggeringPlayer)
		if profile == nil then
			return
		end
		local critterUid = selectDeterministicHatchedCritter(profile, false)
		if critterUid ~= nil then
			EconomyService.HandlePlotAction(triggeringPlayer, "SellCritter", critterUid, nil)
		end
	end)
	prompts.SellStand = sellPrompt

	-- LureStand Prompt
	local lureAnchor = PlotService.ResolveStationAnchor(plotId, "LureStand", "LureStand")
	assert(lureAnchor ~= nil, "Missing LureStand anchor")
	local lurePrompt = createPromptOnPart(
		lureAnchor,
		"LurePrompt",
		"Frost Lure Beacon",
		string.format("Summon Frost (%d Coins)", Constants.FROST_LURE_COST)
	)
	lurePrompt.Triggered:Connect(function(triggeringPlayer: Player)
		local owner = assignmentsByPlotId[plotId]
		if owner == nil or owner.UserId ~= triggeringPlayer.UserId then
			return
		end
		EconomyService.HandlePlotAction(triggeringPlayer, "UseFrostLure", "LureStand", nil)
	end)
	prompts.LureStand = lurePrompt

	-- Upgrade Pad Prompts
	for _, upgradeId in ipairs(UpgradeConfig.OrderedIds) do
		local def = UpgradeConfig.ById[upgradeId]
		local padAnchor = PlotService.ResolveStationAnchor(plotId, "UpgradePad", upgradeId)
		assert(padAnchor ~= nil, "Missing UpgradePad anchor: " .. upgradeId)
		local upgPrompt = createPromptOnPart(
			padAnchor,
			"UpgradePrompt",
			def.DisplayName,
			string.format("Buy (%s Coins)", FormatUtil.FormatCoins(def.Cost))
		)
		upgPrompt.Triggered:Connect(function(triggeringPlayer: Player)
			local owner = assignmentsByPlotId[plotId]
			if owner == nil or owner.UserId ~= triggeringPlayer.UserId then
				return
			end
			EconomyService.HandleBuyUpgrade(triggeringPlayer, upgradeId)
		end)
		prompts.Upgrades[upgradeId] = upgPrompt
	end

	plotPromptsById[plotId] = prompts
end

function PlotService.Init(self: typeof(PlotService)): ()
	local ok, status, root = GreyboxBuilder.EnsureExists(workspace)
	if not ok or root == nil then
		error(string.format("[PlotService] Greybox startup aborted (existing Studio content preserved): %s", status))
	end

	greyboxRoot = root
	local plotsFolder = root:FindFirstChild("Plots") :: Folder
	for plotId = 1, Constants.MAX_PLOTS_PROTOTYPE do
		local plotModel = plotsFolder:FindFirstChild("Plot_" .. tostring(plotId)) :: Model
		plotModelsById[plotId] = plotModel
		plotRevisionByPlotId[plotId] = 1
		wirePlotPrompts(plotId)
		PlotService.RefreshPlotWorldState(plotId)
	end

	print(string.format("[PlotService] Greybox map ready (%s: %s, %d plots wired).", status, root.Name, Constants.MAX_PLOTS_PROTOTYPE))
end

function PlotService.Start(self: typeof(PlotService)): ()
	EconomyService.SetStationAuthorizer(PlotService.AuthorizePlayerStation)

	EconomyService.OnPlotStateChanged(function(player: Player)
		local plotId = plotIdByUserId[player.UserId]
		if plotId ~= nil then
			plotRevisionByPlotId[plotId] = (plotRevisionByPlotId[plotId] or 0) + 1
			PlotService.RefreshPlotWorldState(plotId)
			broadcastAllPublicPlots()
		end
	end)

	DataService.OnPlayerReady(function(player: Player, profile: Types.PlayerProfileData)
		local ok, reason = PlotService.HandlePlayerReadyAdmission(player.UserId, player.DisplayName, profile, player)
		if not ok then
			warn(string.format("[PlotService] Rejected excess player %s: %s", player.Name, reason))
		else
			broadcastAllPublicPlots()
		end
	end)

	DataService.OnPlayerClosing(function(player: Player)
		if PlotService.ReleasePlotForUserId(player.UserId) ~= nil then
			broadcastAllPublicPlots()
		end
	end)

	DataService.OnSnapshotDelivered(function(player: Player)
		NetworkService.SendPublicPlotsToPlayer(player, PlotService.BuildAllPublicPlotDTOs(), globalPlotsRevision)
	end)

	-- Refresh Incubator world countdown labels every second while active and flip to HATCH at maturity
	if not incubatorWatcherRunning then
		incubatorWatcherRunning = true
		task.spawn(function()
			while incubatorWatcherRunning do
				task.wait(1)
				local nowClock = workspace:GetServerTimeNow()
				for plotId, assignment in pairs(assignmentsByPlotId) do
					local profile = assignment.Profile
					local needsRefresh = false
					for _, slotId in ipairs({ "Incubator_1", "Incubator_2" }) do
						local uid = profile.Slots[slotId]
						local item = if uid then profile.Items[uid] else nil
						if item and item.State == "Incubating" and item.MaturesAt ~= nil then
							if nowClock < item.MaturesAt or not (incubatorMatureNotified[plotId] and incubatorMatureNotified[plotId][slotId]) then
								needsRefresh = true
							end
						end
					end
					if needsRefresh then
						PlotService.RefreshPlotWorldState(plotId)
					end
				end
			end
		end)
	end
end

function PlotService.GetGreyboxRoot(): Folder
	assert(greyboxRoot ~= nil, "PlotService.Init() must run before GetGreyboxRoot()")
	return greyboxRoot :: Folder
end

function PlotService.RunSelfTest(): number
	local passed = 0
	local u1 = -920001
	local u2 = -920002
	local u3 = -920003

	PlotService.ReleasePlotForUserId(u1)
	PlotService.ReleasePlotForUserId(u2)
	PlotService.ReleasePlotForUserId(u3)

	local p1 = DataService.CreateDefaultProfile(1000)
	local p2 = DataService.CreateDefaultProfile(1000)
	local p3 = DataService.CreateDefaultProfile(1000)

	-- 1. Unique plot assignment for 2 players & graceful NoFreePlot for 3rd
	local ok1, _, plot1Id = PlotService.AssignPlotForUserId(u1, "TesterOne", p1, nil)
	local ok2, _, plot2Id = PlotService.AssignPlotForUserId(u2, "TesterTwo", p2, nil)
	assert(ok1 and ok2 and plot1Id == 1 and plot2Id == 2, "First two players receive Plot_1 and Plot_2")

	local ok3, reason3, plot3Id = PlotService.AssignPlotForUserId(u3, "TesterThree", p3, nil)
	assert(not ok3 and reason3 == "NoFreePlot" and plot3Id == nil, "3rd player rejected cleanly when prototype plots full")
	passed += 1

	-- 2. Server-side station proximity & ownership authorization
	local inc1Anchor = PlotService.ResolveStationAnchor(1, "Incubator", "Incubator_1") :: BasePart
	local inc2OtherAnchor = PlotService.ResolveStationAnchor(2, "Incubator", "Incubator_1") :: BasePart
	local sell1Anchor = PlotService.ResolveStationAnchor(1, "SellStand", "SellStand") :: BasePart
	local lure1Anchor = PlotService.ResolveStationAnchor(1, "LureStand", "LureStand") :: BasePart
	local pen4Anchor = PlotService.ResolveStationAnchor(1, "Pen", "Pen_4") :: BasePart
	local upg1Anchor = PlotService.ResolveStationAnchor(1, "UpgradePad", "PenSlot_2") :: BasePart

	-- Owner standing next to their own Plot_1 anchors succeeds
	assert((PlotService.AuthorizeStationAtPosition(u1, inc1Anchor.Position, "Incubator", "Incubator_1")), "Owner near own Incubator_1 authorized")
	assert((PlotService.AuthorizeStationAtPosition(u1, sell1Anchor.Position, "SellStand", "SellStand")), "Owner near own SellStand authorized")
	assert((PlotService.AuthorizeStationAtPosition(u1, lure1Anchor.Position, "LureStand", "LureStand")), "Owner near own LureStand authorized")
	assert((PlotService.AuthorizeStationAtPosition(u1, pen4Anchor.Position, "Pen", "Pen_4")), "Owner near own Pen_4 authorized")
	assert((PlotService.AuthorizeStationAtPosition(u1, upg1Anchor.Position, "UpgradePad", "PenSlot_2")), "Owner near own UpgradePad authorized")

	-- Owner standing on Plot_2 trying to access Plot_1's Incubator_1 rejected
	local crossOk, crossReason = PlotService.AuthorizeStationAtPosition(u1, inc2OtherAnchor.Position, "Incubator", "Incubator_1")
	assert(not crossOk and crossReason == "OutOfRange", "Standing at neighbor plot rejected as OutOfRange")

	-- Standing in center of Crater (> 18 studs away) rejected
	local farOk, farReason = PlotService.AuthorizeStationAtPosition(u1, Vector3.new(0, 2, 0), "SellStand", "SellStand")
	assert(not farOk and farReason == "OutOfRange", "Crater distance rejected for ranch station")

	-- Unassigned player & non-finite coordinates rejected (Review #007)
	local unOk, unReason = PlotService.AuthorizeStationAtPosition(u3, inc1Anchor.Position, "Incubator", "Incubator_1")
	assert(not unOk and unReason == "NoAssignedPlot", "Unassigned player rejected")
	local nanOk, nanReason = PlotService.AuthorizeStationAtPosition(u1, Vector3.new(0 / 0, 0, 0), "Incubator", "Incubator_1")
	assert(not nanOk and nanReason == "OutOfRange", "NaN coordinate must be rejected")
	local infOk, infReason = PlotService.AuthorizeStationAtPosition(u1, Vector3.new(math.huge, 0, 0), "Incubator", "Incubator_1")
	assert(not infOk and infReason == "OutOfRange", "Infinite coordinate must be rejected")

	-- Explicit NoFreePlot admission cleanup terminates excess Ready session
	DataService.BeginMockSession(u3, nil)
	assert(DataService.CompleteMockSession(u3, 1000) and DataService.IsUserIdReady(u3), "u3 ready before admission check")
	local admOk, admReason = PlotService.HandlePlayerReadyAdmission(u3, "TesterThree", p3, nil)
	assert(not admOk and admReason == "NoFreePlot", "Admission rejects 3rd user with NoFreePlot")
	assert(not DataService.IsUserIdReady(u3), "Rejected 3rd user session must be ended cleanly")
	passed += 1

	-- 3. PublicPlotDTO projection & release revision increments
	p1.Upgrades["PenSlot_2"] = true
	p1.Items["vis-critter"] = {
		UID = "vis-critter",
		SpeciesId = "NebulaFox",
		Variant = "Radiant",
		State = "InPen",
		AssignedSlot = "Pen_1",
		PlantedAt = nil,
		MaturesAt = nil,
		CreatedAt = 1000,
	}
	p1.Slots["Pen_1"] = "vis-critter"

	local revBeforeRelease = plotRevisionByPlotId[1]
	local dto1 = PlotService.BuildPublicPlotDTO(1)
	assert(dto1.OwnerUserId == u1 and dto1.OwnerDisplayName == "TesterOne", "Public DTO includes owner info")
	assert(dto1.ActivePenVisuals["Pen_1"] ~= nil and dto1.ActivePenVisuals["Pen_1"].SpeciesId == "NebulaFox", "Public DTO exposes active pen visual")
	assert((dto1 :: any).Coins == nil and (dto1 :: any).Items == nil, "Public DTO strips private Coins and Items")

	local releasedPlot = PlotService.ReleasePlotForUserId(u1)
	assert(releasedPlot == 1 and PlotService.GetAssignedPlotId(u1) == nil, "Leave releases Plot_1")
	assert(plotRevisionByPlotId[1] > revBeforeRelease, "PlotRevision increments on release")
	local dtoReleased = PlotService.BuildPublicPlotDTO(1)
	assert(dtoReleased.OwnerUserId == 0 and next(dtoReleased.ActivePenVisuals) == nil, "Released plot DTO resets cleanly")

	-- Plot_1 can now be assigned to u3
	local okReassign, _, reassignedId = PlotService.AssignPlotForUserId(u3, "TesterThree", p3, nil)
	assert(okReassign and reassignedId == 1, "Released Plot_1 reused cleanly")

	PlotService.ReleasePlotForUserId(u2)
	PlotService.ReleasePlotForUserId(u3)
	passed += 1

	return passed
end

return PlotService
