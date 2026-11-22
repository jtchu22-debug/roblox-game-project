--!strict
--[[
	Controller: CrackController
	Purpose: Manages meteor rescue prompts, server-nonce Start -> Finish execution, the forgiving
	         Tap/Hold + optional Gold-Zone Quick-Burst feel bar, Reduced Motion effects, and
	         MeteorLifecycle ClaimReleased/Despawn cancellation.
	Connections: Requires SoundController and UIController; invoked by InputController; communicates with
	             RequestStartCrack, RequestFinishCrack, and MeteorLifecycle.
	How to Test in Studio: Press Play (F5), rescue Starter/Wild meteors (wait 1.2s OR hit E/Space/Tap in Gold Zone).
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ControllersFolder = script.Parent
local SoundController = require(ControllersFolder:WaitForChild("SoundController"))
local UIController = require(ControllersFolder:WaitForChild("UIController"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Types = require(Shared:WaitForChild("Types"))
local CritterConfig = require(Shared:WaitForChild("Config"):WaitForChild("CritterConfig"))
local MeteorConfig = require(Shared:WaitForChild("Config"):WaitForChild("MeteorConfig"))
local UpgradeConfig = require(Shared:WaitForChild("Config"):WaitForChild("UpgradeConfig"))

type CrackMode = "Standard" | "FrostFracture" | "AstralPulse"

local FRIENDLY_ERROR_MESSAGES: { [string]: string } = {
	BagFull = "Bag full! Place or sell a critter first.",
	NotStarterOwner = "That Starter Meteor belongs to another player's Ranch!",
	NotLureOwner = "That Frost Meteor belongs to another player's Frost Lure!",
	MeteorAlreadyClaimed = "Another player is rescuing that Meteor!",
	OutOfRange = "Move closer to the station or Meteor!",
	AlreadyCracking = "Already rescuing a Meteor!",
	CharacterUnavailable = "Wait until your character respawns!",
	ClaimExpired = "Rescue timed out — try again!",
	ToolRequired = "Locked! Buy the required Cracker upgrade first!",
	AlreadyHasActiveLure = "Your Frost Lure is already waiting on North Ridge!",
	LureCooldown = "Lure cooling down — wait a few seconds.",
	NoFreeMeteorNode = "North Ridge is full! Crack a Ridge meteor first.",
	InsufficientCoins = string.format("Need %d Coins for a Frost Lure!", Constants.FROST_LURE_COST),
	LureUnavailable = "Frost Lure unavailable right now.",
}

local PALETTE = {
	PanelDark = Color3.fromRGB(24, 22, 38),
	TrackDark = Color3.fromRGB(46, 42, 72),
	TextCream = Color3.fromRGB(245, 240, 232),
	OrbitalCyan = Color3.fromRGB(65, 210, 255),
	StarlightGold = Color3.fromRGB(255, 205, 45),
	AstralViolet = Color3.fromRGB(205, 115, 255),
}

local CrackController = {
	Name = "CrackController",
}

local isCracking = false
local activeFinishSent = false
local activeCrackUID: string? = nil
local activeAttemptNonce: string? = nil
local activeCrackToken = 0
local activeStartClock = 0
local activePhaseStartClock = 0
local activeCrackMode: CrackMode = "Standard"
local activeBeat = 1
local activeUsedBeat1Burst = false
local activeMeteorPos: Vector3? = nil
local activeMeteorTrait: Types.MeteorTraitId? = nil
local activeIsStarter = false

local claimedByMeteorUID: { [string]: number? } = {}
local currentInputMode: UIController.InputMode = "Keyboard"

local startCrackFn: RemoteFunction? = nil
local finishCrackFn: RemoteFunction? = nil
local lifecycleConn: RBXScriptConnection? = nil
local renderConn: RBXScriptConnection? = nil

local feelFrame: Frame? = nil
local feelTitleLabel: TextLabel? = nil
local feelFillBar: Frame? = nil
local feelSweetZone: Frame? = nil
local feelActionButton: TextButton? = nil
local feelStroke: UIStroke? = nil

local function formatReasonMessage(reason: string, requiredUpgradeId: unknown?): string
	if reason == "ToolRequired" and typeof(requiredUpgradeId) == "string" then
		local def = (UpgradeConfig.ById :: { [string]: Types.UpgradeDefinition })[requiredUpgradeId]
		if def ~= nil then
			if def.StationZone == "Hub" then
				return string.format("Locked! Buy %s (%d Coins) at the Hub Tool Workbench!", def.DisplayName, def.Cost)
			end
			return string.format("Locked! Buy %s (%d Coins) on your Ranch Board!", def.DisplayName, def.Cost)
		end
	end
	return FRIENDLY_ERROR_MESSAGES[reason] or ("Could not rescue Meteor: " .. reason)
end

local function findMeteorModelFromPrompt(prompt: ProximityPrompt): Model?
	local current: Instance? = prompt.Parent
	while current ~= nil do
		if current:IsA("Model") and CollectionService:HasTag(current, Constants.TAG_ACTIVE_METEOR) then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function updateFeelButtonPromptText(inSweetSpot: boolean): ()
	local btn = feelActionButton
	if btn == nil then
		return
	end

	if SoundController.IsReducedMotion() then
		btn.Text = if activeCrackMode == "AstralPulse"
			then "Astral Core stabilizing safely..."
			elseif activeCrackMode == "FrostFracture" then "Frost seam fracturing safely..."
			else "Auto-cracking safely..."
		btn.BackgroundColor3 = PALETTE.TrackDark
		btn.TextColor3 = PALETTE.TextCream
		return
	end

	local actionKey = if currentInputMode == "Touch"
		then "TAP HERE"
		elseif currentInputMode == "Gamepad" then "Press X"
		else "Press E / Space"

	if inSweetSpot then
		btn.Text = string.format("NOW! %s for Quick Burst!", actionKey)
		btn.BackgroundColor3 = PALETTE.StarlightGold
		btn.TextColor3 = PALETTE.PanelDark
	else
		btn.Text = string.format("%s inside Gold Zone for Quick Burst (or wait)", actionKey)
		btn.BackgroundColor3 = PALETTE.TrackDark
		btn.TextColor3 = PALETTE.TextCream
	end
end

local function hideFeelUI(): ()
	if feelFrame ~= nil then
		feelFrame.Visible = false
	end
	if feelFillBar ~= nil then
		feelFillBar.Size = UDim2.fromScale(0, 1)
	end
end

local function cancelLocalCrack(meteorUID: string, showNotice: boolean): ()
	if activeCrackUID == meteorUID then
		activeCrackUID = nil
		activeAttemptNonce = nil
		isCracking = false
		activeFinishSent = false
		activeCrackMode = "Standard"
		activeBeat = 1
		activeUsedBeat1Burst = false
		activeCrackToken += 1
		hideFeelUI()
		if showNotice then
			UIController.ShowToast("Meteor rescue cancelled.", "Info")
		end
	end
end

local function spawnBurstEffect(pos: Vector3?, color: Color3, particleCount: number?): ()
	if pos == nil or SoundController.IsReducedMotion() then
		return
	end

	local parentFolder = workspace:FindFirstChild("StarfallClientVisuals") or workspace
	local emitterPart = Instance.new("Part")
	emitterPart.Name = "CrackBurstVFX"
	emitterPart.Size = Vector3.new(0.5, 0.5, 0.5)
	emitterPart.Position = pos + Vector3.new(0, 1.5, 0)
	emitterPart.Anchored = true
	emitterPart.CanCollide = false
	emitterPart.CanQuery = false
	emitterPart.CanTouch = false
	emitterPart.Transparency = 1
	emitterPart.Parent = parentFolder

	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new(color, Color3.fromRGB(255, 255, 255))
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.65),
		NumberSequenceKeypoint.new(1, 0),
	})
	particles.Lifetime = NumberRange.new(0.35, 0.55)
	particles.Speed = NumberRange.new(10, 18)
	particles.SpreadAngle = Vector2.new(80, 80)
	particles.Rate = 0
	particles.Enabled = false
	particles.Parent = emitterPart

	particles:Emit(particleCount or 14)
	Debris:AddItem(emitterPart, 0.8)
end

local function spawnArrivalStreak(pos: Vector3?, color: Color3): ()
	if pos == nil or SoundController.IsReducedMotion() then
		return
	end

	local parentFolder = workspace:FindFirstChild("StarfallClientVisuals") or workspace
	local streak = Instance.new("Part")
	streak.Name = "MeteorArrivalStreak"
	streak.Size = Vector3.new(1.4, 24, 1.4)
	streak.Color = color
	streak.Material = Enum.Material.Neon
	streak.Transparency = 0.25
	streak.Anchored = true
	streak.CanCollide = false
	streak.CanQuery = false
	streak.CanTouch = false
	streak.CFrame = CFrame.new(pos + Vector3.new(14, 52, 8)) * CFrame.Angles(math.rad(15), 0, math.rad(-14))
	streak.Parent = parentFolder

	local landTween = TweenService:Create(
		streak,
		TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = CFrame.new(pos + Vector3.new(0, 12, 0)), Transparency = 0.9 }
	)
	landTween:Play()
	Debris:AddItem(streak, 0.65)
	spawnBurstEffect(pos, color, 18)
end

local function spawnIncomingAstralFall(pos: Vector3?, duration: number): ()
	if pos == nil then
		return
	end

	local parentFolder = workspace:FindFirstChild("StarfallClientVisuals") or workspace
	local totalLifetime = math.max(0.5, duration) + 0.4

	local targetRing = Instance.new("Part")
	targetRing.Name = "AstralTargetRing"
	targetRing.Shape = Enum.PartType.Cylinder
	targetRing.Size = Vector3.new(0.35, 11, 11)
	targetRing.CFrame = CFrame.new(pos + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.rad(90))
	targetRing.Color = PALETTE.AstralViolet
	targetRing.Material = Enum.Material.Neon
	targetRing.Transparency = 0.28
	targetRing.Anchored = true
	targetRing.CanCollide = false
	targetRing.CanQuery = false
	targetRing.CanTouch = false
	targetRing.Parent = parentFolder
	Debris:AddItem(targetRing, totalLifetime)

	local shaft = Instance.new("Part")
	shaft.Name = "AstralWarningShaft"
	shaft.Size = Vector3.new(0.85, 90, 0.85)
	shaft.CFrame = CFrame.new(pos + Vector3.new(0, 45, 0))
	shaft.Color = PALETTE.AstralViolet
	shaft.Material = Enum.Material.Neon
	shaft.Transparency = 0.65
	shaft.Anchored = true
	shaft.CanCollide = false
	shaft.CanQuery = false
	shaft.CanTouch = false
	shaft.Parent = parentFolder
	Debris:AddItem(shaft, totalLifetime)

	if not SoundController.IsReducedMotion() then
		local orb = Instance.new("Part")
		orb.Name = "AstralFallingOrb"
		orb.Shape = Enum.PartType.Ball
		orb.Size = Vector3.new(4.2, 4.2, 4.2)
		orb.CFrame = CFrame.new(pos + Vector3.new(-36, 100, -22))
		orb.Color = PALETTE.StarlightGold
		orb.Material = Enum.Material.Neon
		orb.Transparency = 0.1
		orb.Anchored = true
		orb.CanCollide = false
		orb.CanQuery = false
		orb.CanTouch = false
		orb.Parent = parentFolder

		local descentTween = TweenService:Create(
			orb,
			TweenInfo.new(math.max(0.25, duration), Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ CFrame = CFrame.new(pos + Vector3.new(0, 2.4, 0)) }
		)
		descentTween:Play()
		Debris:AddItem(orb, math.max(0.25, duration) + 0.2)
	end
end

local function spawnLureGuideBeam(targetPos: Vector3?): ()
	if targetPos == nil then
		return
	end
	local lp = Players.LocalPlayer
	local char = if lp ~= nil then lp.Character else nil
	local hrp = if char ~= nil then char:FindFirstChild("HumanoidRootPart") else nil
	if hrp == nil or not hrp:IsA("BasePart") then
		return
	end

	local parentFolder = workspace:FindFirstChild("StarfallClientVisuals") or workspace
	local targetAnchor = Instance.new("Part")
	targetAnchor.Name = "LureBeamTarget"
	targetAnchor.Size = Vector3.new(0.5, 0.5, 0.5)
	targetAnchor.Position = targetPos + Vector3.new(0, 3, 0)
	targetAnchor.Anchored = true
	targetAnchor.CanCollide = false
	targetAnchor.CanQuery = false
	targetAnchor.CanTouch = false
	targetAnchor.Transparency = 1
	targetAnchor.Parent = parentFolder

	local att0 = Instance.new("Attachment")
	att0.Name = "LureBeamStart"
	att0.Parent = hrp

	local att1 = Instance.new("Attachment")
	att1.Name = "LureBeamEnd"
	att1.Parent = targetAnchor

	local beam = Instance.new("Beam")
	beam.Name = "FrostLureGuideBeam"
	beam.Attachment0 = att0
	beam.Attachment1 = att1
	beam.Width0 = 0.55
	beam.Width1 = 0.85
	beam.FaceCamera = true
	beam.Color = ColorSequence.new(PALETTE.OrbitalCyan)
	beam.Transparency = NumberSequence.new(0.25)
	beam.Parent = targetAnchor

	Debris:AddItem(att0, 8)
	Debris:AddItem(targetAnchor, 8)
end

local function configureFeelBeat(beat: number): ()
	if feelSweetZone ~= nil then
		if activeCrackMode == "FrostFracture" then
			local beatDuration = if beat == 1
				then Constants.FROST_BEAT1_END_SECONDS
				else (Constants.FROST_CRACK_DURATION_SECONDS - Constants.FROST_BEAT1_END_SECONDS)
			feelSweetZone.Position = UDim2.fromScale(Constants.FROST_BEAT_SWEET_START / beatDuration, 0)
			feelSweetZone.Size = UDim2.fromScale((Constants.FROST_BEAT_SWEET_END - Constants.FROST_BEAT_SWEET_START) / beatDuration, 1)
		elseif activeCrackMode == "AstralPulse" then
			local sStart = Constants.ASTRAL_PULSE_SWEET_START / Constants.ASTRAL_CRACK_DURATION_SECONDS
			local sEnd = Constants.ASTRAL_PULSE_SWEET_END / Constants.ASTRAL_CRACK_DURATION_SECONDS
			feelSweetZone.Position = UDim2.fromScale(sStart, 0)
			feelSweetZone.Size = UDim2.fromScale(sEnd - sStart, 1)
		else
			local sStart = Constants.CRACK_FEEL_WINDOW_START_SECONDS / Constants.CRACK_CLIENT_DURATION_SECONDS
			local sEnd = Constants.CRACK_FEEL_WINDOW_END_SECONDS / Constants.CRACK_CLIENT_DURATION_SECONDS
			feelSweetZone.Position = UDim2.fromScale(sStart, 0)
			feelSweetZone.Size = UDim2.fromScale(sEnd - sStart, 1)
		end
	end

	if feelTitleLabel ~= nil then
		if activeCrackMode == "FrostFracture" then
			feelTitleLabel.Text = if beat == 1
				then "FROST FRACTURE [1/2] — Tap Ice Seam #1!"
				else "FROST FRACTURE [2/2] — Split Ice Core!"
		elseif activeCrackMode == "AstralPulse" then
			feelTitleLabel.Text = "ASTRAL PULSE — Catch the Star Surge!"
		elseif activeIsStarter then
			feelTitleLabel.Text = "Rescuing STARTER METEOR..."
		else
			local traitDef = if activeMeteorTrait ~= nil then MeteorConfig.ById[activeMeteorTrait] else nil
			if traitDef ~= nil then
				feelTitleLabel.Text = string.format("Rescuing [%s] Meteor...", traitDef.IconText)
			else
				feelTitleLabel.Text = "Rescuing Meteor..."
			end
		end
	end
end

local function advanceFrostBeat(usedBurst: boolean): ()
	activeBeat = 2
	activePhaseStartClock = os.clock()
	activeUsedBeat1Burst = activeUsedBeat1Burst or usedBurst
	if feelFillBar ~= nil then
		feelFillBar.Size = UDim2.fromScale(0, 1)
	end
	configureFeelBeat(2)
	updateFeelButtonPromptText(false)
	SoundController.Play(if usedBurst then "CrackChime" else "CrackStart")
	spawnBurstEffect(activeMeteorPos, PALETTE.OrbitalCyan, 10)
end

local function submitFinishCrack(usedQuickBurst: boolean): ()
	if not isCracking or activeFinishSent or activeCrackUID == nil or activeAttemptNonce == nil then
		return
	end

	local finishFn = finishCrackFn
	if finishFn == nil then
		return
	end

	activeFinishSent = true
	local meteorUID = activeCrackUID :: string
	local attemptNonce = activeAttemptNonce :: string
	local myToken = activeCrackToken
	local meteorPos = activeMeteorPos
	local traitId = activeMeteorTrait
	local crackMode = activeCrackMode

	hideFeelUI()

	task.spawn(function()
		local okFinish, finishRes = pcall(function()
			return finishFn:InvokeServer(meteorUID, attemptNonce)
		end)

		if okFinish and typeof(finishRes) == "table" and finishRes.Ok then
			local rawSpecies = finishRes.SpeciesId
			local speciesId = tostring(rawSpecies)
			print(string.format("[CrackController] Rescued Star-Pod: %s!", speciesId))
			local speciesDef = if typeof(rawSpecies) == "string"
				then (CritterConfig.ById :: { [string]: Types.SpeciesDefinition })[rawSpecies]
				else nil
			local displayName = if speciesDef ~= nil then speciesDef.DisplayName else speciesId
			local traitDef = if traitId ~= nil
				then (MeteorConfig.ById :: { [string]: Types.MeteorTraitDefinition })[traitId]
				else nil
			local burstColor = if traitDef ~= nil then traitDef.TrailColor else PALETTE.StarlightGold

			SoundController.Play(if usedQuickBurst then "CrackChime" else "CrackSuccess")
			local bonusTag = if usedQuickBurst
				then (if crackMode == "AstralPulse"
					then " (Astral Surge!)"
					elseif crackMode == "FrostFracture" then " (Ice Split!)"
					else " (Quick Burst!)")
				else ""
			UIController.ShowToast(string.format("Rescued %s Pod!%s", displayName, bonusTag), "Success")
			spawnBurstEffect(meteorPos, burstColor, if crackMode == "AstralPulse" then 24 elseif crackMode == "FrostFracture" then 18 else 14)
		else
			local reason = if typeof(finishRes) == "table" and finishRes.Reason then tostring(finishRes.Reason) else "Failed"
			warn("[CrackController] Could not finish meteor rescue: " .. reason)
			if myToken == activeCrackToken then
				SoundController.Play("Error")
				UIController.ShowToast(formatReasonMessage(reason, if typeof(finishRes) == "table" then finishRes.RequiredUpgradeId else nil), "Warn")
			end
		end

		if myToken == activeCrackToken then
			isCracking = false
			activeFinishSent = false
			activeCrackUID = nil
			activeAttemptNonce = nil
			activeCrackMode = "Standard"
			activeBeat = 1
			activeUsedBeat1Burst = false
		end
	end)
end

local function buildFeelTimingUI(): ()
	local hud = UIController.GetHudScreenGui()
	if hud == nil or feelFrame ~= nil then
		return
	end

	local frame = Instance.new("Frame")
	frame.Name = "CrackFeelFrame"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -64)
	frame.Size = UDim2.new(0.92, 0, 0, 98)
	frame.BackgroundColor3 = PALETTE.PanelDark
	frame.BackgroundTransparency = 0.06
	frame.BorderSizePixel = 0
	frame.Visible = false
	local frameConstraint = Instance.new("UISizeConstraint")
	frameConstraint.MinSize = Vector2.new(260, 92)
	frameConstraint.MaxSize = Vector2.new(330, 102)
	frameConstraint.Parent = frame
	frame.Parent = hud

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = PALETTE.OrbitalCyan
	stroke.Thickness = 2
	stroke.Parent = frame
	feelStroke = stroke

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -20, 0, 22)
	title.Position = UDim2.fromOffset(10, 6)
	title.BackgroundTransparency = 1
	title.Text = "Rescuing Meteor..."
	title.TextColor3 = PALETTE.TextCream
	title.Font = Enum.Font.GothamBold
	title.TextSize = 14
	title.Parent = frame
	feelTitleLabel = title

	local track = Instance.new("Frame")
	track.Name = "ProgressTrack"
	track.Size = UDim2.new(1, -24, 0, 16)
	track.Position = UDim2.fromOffset(12, 32)
	track.BackgroundColor3 = PALETTE.TrackDark
	track.BorderSizePixel = 0
	track.Parent = frame

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 8)
	trackCorner.Parent = track

	local sweetStartFrac = Constants.CRACK_FEEL_WINDOW_START_SECONDS / Constants.CRACK_CLIENT_DURATION_SECONDS
	local sweetEndFrac = Constants.CRACK_FEEL_WINDOW_END_SECONDS / Constants.CRACK_CLIENT_DURATION_SECONDS

	local sweetZone = Instance.new("Frame")
	sweetZone.Name = "SweetSpotZone"
	sweetZone.Position = UDim2.fromScale(sweetStartFrac, 0)
	sweetZone.Size = UDim2.fromScale(sweetEndFrac - sweetStartFrac, 1)
	sweetZone.BackgroundColor3 = PALETTE.StarlightGold
	sweetZone.BackgroundTransparency = 0.4
	sweetZone.BorderSizePixel = 0
	sweetZone.ZIndex = 2
	sweetZone.Parent = track
	feelSweetZone = sweetZone

	local sweetStroke = Instance.new("UIStroke")
	sweetStroke.Color = PALETTE.StarlightGold
	sweetStroke.Thickness = 1.5
	sweetStroke.Parent = sweetZone

	local fill = Instance.new("Frame")
	fill.Name = "FillBar"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = PALETTE.OrbitalCyan
	fill.BorderSizePixel = 0
	fill.ZIndex = 3
	fill.Parent = track
	feelFillBar = fill

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 8)
	fillCorner.Parent = fill

	local actionBtn = Instance.new("TextButton")
	actionBtn.Name = "QuickBurstButton"
	actionBtn.Size = UDim2.new(1, -24, 0, 44)
	actionBtn.Position = UDim2.fromOffset(12, 50)
	actionBtn.BackgroundColor3 = PALETTE.TrackDark
	actionBtn.TextColor3 = PALETTE.TextCream
	actionBtn.Font = Enum.Font.GothamBold
	actionBtn.TextScaled = true
	actionBtn.AutoButtonColor = true
	actionBtn.Selectable = false
	actionBtn.BorderSizePixel = 0
	actionBtn.Parent = frame
	feelActionButton = actionBtn

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 10)
	btnCorner.Parent = actionBtn

	actionBtn.Activated:Connect(function()
		CrackController.TryTriggerSweetSpot()
	end)

	feelFrame = frame
end

local function stepCrackFeelUI(): ()
	if not isCracking or activeFinishSent or activeAttemptNonce == nil then
		return
	end

	local now = os.clock()
	if activeCrackMode == "FrostFracture" then
		local phaseDuration = if activeBeat == 1
			then Constants.FROST_BEAT1_END_SECONDS
			else (Constants.FROST_CRACK_DURATION_SECONDS - Constants.FROST_BEAT1_END_SECONDS)
		local phaseElapsed = now - activePhaseStartClock
		local progress = math.clamp(phaseElapsed / phaseDuration, 0, 1)
		local inSweetSpot = not SoundController.IsReducedMotion()
			and phaseElapsed >= Constants.FROST_BEAT_SWEET_START
			and phaseElapsed <= Constants.FROST_BEAT_SWEET_END

		if feelFillBar ~= nil then
			feelFillBar.Size = UDim2.fromScale(progress, 1)
			feelFillBar.BackgroundColor3 = if inSweetSpot then PALETTE.StarlightGold else PALETTE.OrbitalCyan
		end
		if feelStroke ~= nil then
			feelStroke.Color = if inSweetSpot then PALETTE.StarlightGold else PALETTE.OrbitalCyan
		end
		updateFeelButtonPromptText(inSweetSpot)

		if phaseElapsed >= phaseDuration then
			if activeBeat == 1 then
				advanceFrostBeat(false)
			elseif (now - activeStartClock) >= (Constants.MIN_CRACK_DURATION_SECONDS + 0.05) then
				submitFinishCrack(activeUsedBeat1Burst)
			end
		end
		return
	elseif activeCrackMode == "AstralPulse" then
		local elapsed = now - activeStartClock
		local duration = Constants.ASTRAL_CRACK_DURATION_SECONDS
		local progress = math.clamp(elapsed / duration, 0, 1)
		local inSweetSpot = not SoundController.IsReducedMotion()
			and elapsed >= Constants.ASTRAL_PULSE_SWEET_START
			and elapsed <= Constants.ASTRAL_PULSE_SWEET_END

		if feelFillBar ~= nil then
			feelFillBar.Size = UDim2.fromScale(progress, 1)
			feelFillBar.BackgroundColor3 = if inSweetSpot then PALETTE.StarlightGold else PALETTE.AstralViolet
		end
		if feelStroke ~= nil then
			feelStroke.Color = if inSweetSpot then PALETTE.StarlightGold else PALETTE.AstralViolet
		end
		updateFeelButtonPromptText(inSweetSpot)

		if elapsed >= duration then
			submitFinishCrack(false)
		end
		return
	end

	local elapsed = now - activeStartClock
	local duration = Constants.CRACK_CLIENT_DURATION_SECONDS
	local progress = math.clamp(elapsed / duration, 0, 1)
	local inSweetSpot = not SoundController.IsReducedMotion()
		and elapsed >= Constants.CRACK_FEEL_WINDOW_START_SECONDS
		and elapsed <= Constants.CRACK_FEEL_WINDOW_END_SECONDS

	if feelFillBar ~= nil then
		feelFillBar.Size = UDim2.fromScale(progress, 1)
		feelFillBar.BackgroundColor3 = if inSweetSpot then PALETTE.StarlightGold else PALETTE.OrbitalCyan
	end
	if feelStroke ~= nil then
		feelStroke.Color = if inSweetSpot then PALETTE.StarlightGold else PALETTE.OrbitalCyan
	end
	updateFeelButtonPromptText(inSweetSpot)

	if elapsed >= duration then
		submitFinishCrack(false)
	end
end

function CrackController.Init(self: typeof(CrackController)): ()
	-- Timing Ring UI attaches inside Start() after UIController:Init() creates StarfallRanchHUD.
end

function CrackController.Start(self: typeof(CrackController)): ()
	local remotes = ReplicatedStorage:WaitForChild(Constants.REMOTES_FOLDER_NAME)
	startCrackFn = remotes:WaitForChild(Constants.REMOTE_NAMES.RequestStartCrack) :: RemoteFunction
	finishCrackFn = remotes:WaitForChild(Constants.REMOTE_NAMES.RequestFinishCrack) :: RemoteFunction
	local meteorLifecycleEvent = remotes:WaitForChild(Constants.REMOTE_NAMES.MeteorLifecycle) :: RemoteEvent

	buildFeelTimingUI()

	if lifecycleConn == nil then
		lifecycleConn = meteorLifecycleEvent.OnClientEvent:Connect(function(payload: { [string]: any })
			if typeof(payload) ~= "table" then
				return
			end
			local action = payload.Action
			if typeof(action) ~= "string" then
				return
			end

			if action == "AstralIncoming" then
				local pos = if typeof(payload.Position) == "Vector3" then payload.Position else nil
				local duration = if typeof(payload.Duration) == "number" then payload.Duration else Constants.ASTRAL_FALL_WARNING_SECONDS
				local dto = UIController.GetLatestOwnerState()
				local hasAstralTool = dto ~= nil and dto.Upgrades["StarCracker"] == true
				SoundController.Play("CrackChime")
				UIController.ShowToast(
					if hasAstralTool
						then "ASTRAL FALL on North Ridge! Chase it!"
						else "ASTRAL FALL on North Ridge! (Needs Astral Cracker)",
					"Info"
				)
				spawnIncomingAstralFall(pos, duration)
				return
			elseif action == "LureFailed" then
				local reason = if typeof(payload.Reason) == "string" then payload.Reason else "LureUnavailable"
				SoundController.Play("Error")
				UIController.ShowToast(formatReasonMessage(reason, nil), "Warn")
				return
			end

			local meteorUID = payload.MeteorUID
			if typeof(meteorUID) ~= "string" then
				return
			end

			if action == "Spawn" then
				if typeof(payload.ClaimedBy) == "number" then
					claimedByMeteorUID[meteorUID] = payload.ClaimedBy
				else
					claimedByMeteorUID[meteorUID] = nil
				end
				if payload.ArrivalEffect == true then
					local pos = if typeof(payload.Position) == "Vector3" then payload.Position else nil
					local lp = Players.LocalPlayer
					if payload.Trait == "Astral" then
						local dto = UIController.GetLatestOwnerState()
						local hasAstralTool = dto ~= nil and dto.Upgrades["StarCracker"] == true
						SoundController.Play("CrackChime")
						UIController.ShowToast(
							if hasAstralTool
								then "ASTRAL METEOR landed on North Ridge! Break it!"
								else "ASTRAL METEOR landed! (Needs Astral Cracker)",
							"Info"
						)
						spawnArrivalStreak(pos, PALETTE.AstralViolet)
					elseif typeof(payload.LuredBy) == "number" and lp ~= nil and payload.LuredBy == lp.UserId then
						SoundController.Play("CrackChime")
						UIController.ShowToast("Frost Lure landed on North Ridge! Follow the cyan beam!", "Success")
						spawnArrivalStreak(pos, PALETTE.OrbitalCyan)
						spawnLureGuideBeam(pos)
					end
				end
			elseif action == "Claimed" then
				if typeof(payload.ClaimedBy) == "number" then
					claimedByMeteorUID[meteorUID] = payload.ClaimedBy
				end
			elseif action == "ClaimReleased" then
				claimedByMeteorUID[meteorUID] = nil
				print(string.format("[CrackController] Meteor claim released: %s", string.sub(meteorUID, 1, 8)))
				cancelLocalCrack(meteorUID, true)
			elseif action == "Despawn" then
				claimedByMeteorUID[meteorUID] = nil
				cancelLocalCrack(meteorUID, false)
			end
		end)
	end

	if renderConn == nil then
		renderConn = RunService.RenderStepped:Connect(stepCrackFeelUI)
	end
end

function CrackController.IsCracking(): boolean
	return isCracking
end

function CrackController.TryTriggerSweetSpot(): boolean
	if not isCracking or activeFinishSent or activeAttemptNonce == nil then
		return false
	end
	if SoundController.IsReducedMotion() then
		return false
	end

	local now = os.clock()
	if activeCrackMode == "FrostFracture" then
		local phaseElapsed = now - activePhaseStartClock
		if phaseElapsed >= Constants.FROST_BEAT_SWEET_START and phaseElapsed <= Constants.FROST_BEAT_SWEET_END then
			if activeBeat == 1 then
				advanceFrostBeat(true)
				return true
			elseif (now - activeStartClock) >= (Constants.MIN_CRACK_DURATION_SECONDS + 0.05) then
				submitFinishCrack(true)
				return true
			end
		end
		return false
	elseif activeCrackMode == "AstralPulse" then
		local elapsed = now - activeStartClock
		if elapsed >= Constants.ASTRAL_PULSE_SWEET_START and elapsed <= Constants.ASTRAL_PULSE_SWEET_END then
			submitFinishCrack(true)
			return true
		end
		return false
	end

	local elapsed = now - activeStartClock
	if elapsed >= Constants.CRACK_FEEL_WINDOW_START_SECONDS and elapsed <= Constants.CRACK_FEEL_WINDOW_END_SECONDS then
		submitFinishCrack(true)
		return true
	end
	return false
end

function CrackController.TryStartFromPrompt(prompt: ProximityPrompt): boolean
	if isCracking or activeFinishSent then
		return false
	end

	local startFn = startCrackFn
	if startFn == nil then
		return false
	end

	local meteorModel = findMeteorModelFromPrompt(prompt)
	if meteorModel == nil then
		return false
	end

	local meteorUID = meteorModel:GetAttribute("MeteorUID")
	if typeof(meteorUID) ~= "string" then
		return false
	end

	local primary = meteorModel.PrimaryPart
	local meteorPosition = if primary ~= nil then primary.Position else nil

	isCracking = true
	activeFinishSent = false
	activeCrackUID = meteorUID
	activeAttemptNonce = nil
	activeCrackToken += 1
	local myToken = activeCrackToken

	task.spawn(function()
		local okStart, startRes = pcall(function()
			return startFn:InvokeServer(meteorUID)
		end)
		if not okStart or typeof(startRes) ~= "table" or not startRes.Ok then
			local reason = if typeof(startRes) == "table" and startRes.Reason then tostring(startRes.Reason) else "Failed"
			warn("[CrackController] Could not start meteor rescue: " .. reason)
			SoundController.Play("Error")
			UIController.ShowToast(formatReasonMessage(reason, if typeof(startRes) == "table" then startRes.RequiredUpgradeId else nil), "Warn")
			if myToken == activeCrackToken then
				isCracking = false
				activeCrackUID = nil
				activeAttemptNonce = nil
			end
			return
		end

		if myToken ~= activeCrackToken or activeCrackUID ~= meteorUID or typeof(startRes.AttemptNonce) ~= "string" then
			return
		end

		activeAttemptNonce = startRes.AttemptNonce
		activeStartClock = os.clock()
		activePhaseStartClock = activeStartClock
		activeMeteorPos = meteorPosition
		activeIsStarter = startRes.IsStarter == true
		activeMeteorTrait = startRes.Trait :: Types.MeteorTraitId?
		if not activeIsStarter and activeMeteorTrait == "Astral" then
			activeCrackMode = "AstralPulse"
		elseif not activeIsStarter and activeMeteorTrait == "Frost" then
			activeCrackMode = "FrostFracture"
		else
			activeCrackMode = "Standard"
		end
		activeBeat = 1
		activeUsedBeat1Burst = false

		configureFeelBeat(1)

		if feelFrame ~= nil then
			updateFeelButtonPromptText(false)
			if feelFillBar ~= nil then
				feelFillBar.Size = UDim2.fromScale(0, 1)
			end
			feelFrame.Visible = true
		end

		SoundController.Play("CrackStart")
	end)

	return true
end

function CrackController.SetInputMode(mode: UIController.InputMode): ()
	currentInputMode = mode
	if isCracking and not activeFinishSent and activeAttemptNonce ~= nil then
		local now = os.clock()
		local inSweet = false
		if not SoundController.IsReducedMotion() then
			if activeCrackMode == "FrostFracture" then
				local phaseElapsed = now - activePhaseStartClock
				inSweet = phaseElapsed >= Constants.FROST_BEAT_SWEET_START
					and phaseElapsed <= Constants.FROST_BEAT_SWEET_END
			elseif activeCrackMode == "AstralPulse" then
				local elapsed = now - activeStartClock
				inSweet = elapsed >= Constants.ASTRAL_PULSE_SWEET_START
					and elapsed <= Constants.ASTRAL_PULSE_SWEET_END
			else
				local elapsed = now - activeStartClock
				inSweet = elapsed >= Constants.CRACK_FEEL_WINDOW_START_SECONDS
					and elapsed <= Constants.CRACK_FEEL_WINDOW_END_SECONDS
			end
		end
		updateFeelButtonPromptText(inSweet)
	end
end

return CrackController
