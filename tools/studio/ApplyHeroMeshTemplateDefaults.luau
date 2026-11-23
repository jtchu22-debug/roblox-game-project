--!strict
--[[
	Tool: ApplyHeroMeshTemplateDefaults (Studio Command Bar / Plugin Helper)
	Purpose: Applies Starfall Ranch materials, colors, collision/query flags, PrimaryPart,
	         and budget checks (<= 8 BaseParts, <= 8.0 studs height, ground pivot) to imported
	         low-poly FBX models (`Critters` & `Meteors`) inside ReplicatedStorage or Workspace.
	Usage (In Studio Command Bar):
	  1. Import `.fbx` files from `tools/blender/exports/{critters,meteors}/` via File -> Import 3D
	     (keep Scale Unit: Studs, Single Mesh unchecked).
	  2. Move templates under `ReplicatedStorage.AssetTemplates.{Critters, Meteors}` (or leave in `Workspace`
	     to inspect in an isolated test place).
	  3. Paste and run this script in the Command Bar (safe & idempotent; never deletes models).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local COLOR_EYE = Color3.fromRGB(22, 20, 34)

type CritterPalette = {
	BodyColor: Color3,
	SecondaryColor: Color3?,
	AccentColor: Color3,
}

type MeteorPalette = {
	RockColor: Color3,
	CoreColor: Color3,
	TrailColor: Color3,
}

local SECONDARY_CRITTER_COLORS: { [string]: Color3 } = {
	StarSlime = Color3.fromRGB(42, 152, 116),
	CinderPup = Color3.fromRGB(245, 228, 204),
	FrostBeetle = Color3.fromRGB(42, 108, 170),
	NebulaFox = Color3.fromRGB(236, 228, 250),
	SolarGolem = Color3.fromRGB(168, 100, 44),
	CometOwl = Color3.fromRGB(228, 220, 246),
}

local function loadPalettes(): ({ [string]: CritterPalette }, { [string]: MeteorPalette })
	local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
	local configFolder = if sharedFolder ~= nil then sharedFolder:FindFirstChild("Config") else nil
	if configFolder ~= nil then
		local critterCfg = require(configFolder:WaitForChild("CritterConfig")) :: any
		local meteorCfg = require(configFolder:WaitForChild("MeteorConfig")) :: any
		local mergedCritters: { [string]: CritterPalette } = {}
		for speciesId, def in pairs(critterCfg.ById) do
			mergedCritters[speciesId] = {
				BodyColor = def.BodyColor,
				SecondaryColor = SECONDARY_CRITTER_COLORS[speciesId],
				AccentColor = def.AccentColor,
			}
		end
		return mergedCritters, meteorCfg.ById
	end

	warn("[ApplyHeroMeshTemplateDefaults] ReplicatedStorage.Shared not found; using standalone Studio preview palette.")
	local fallbackCritters: { [string]: CritterPalette } = {
		StarSlime = { BodyColor = Color3.fromRGB(95, 225, 165), SecondaryColor = SECONDARY_CRITTER_COLORS.StarSlime, AccentColor = Color3.fromRGB(255, 225, 95) },
		CinderPup = { BodyColor = Color3.fromRGB(255, 125, 85), SecondaryColor = SECONDARY_CRITTER_COLORS.CinderPup, AccentColor = Color3.fromRGB(255, 215, 90) },
		FrostBeetle = { BodyColor = Color3.fromRGB(85, 205, 245), SecondaryColor = SECONDARY_CRITTER_COLORS.FrostBeetle, AccentColor = Color3.fromRGB(185, 245, 255) },
		NebulaFox = { BodyColor = Color3.fromRGB(165, 115, 255), SecondaryColor = SECONDARY_CRITTER_COLORS.NebulaFox, AccentColor = Color3.fromRGB(95, 220, 255) },
		SolarGolem = { BodyColor = Color3.fromRGB(255, 175, 65), SecondaryColor = SECONDARY_CRITTER_COLORS.SolarGolem, AccentColor = Color3.fromRGB(255, 240, 145) },
		CometOwl = { BodyColor = Color3.fromRGB(105, 85, 210), SecondaryColor = SECONDARY_CRITTER_COLORS.CometOwl, AccentColor = Color3.fromRGB(255, 215, 85) },
	}
	local fallbackMeteors: { [string]: MeteorPalette } = {
		Ember = { RockColor = Color3.fromRGB(145, 85, 95), CoreColor = Color3.fromRGB(255, 145, 60), TrailColor = Color3.fromRGB(255, 130, 65) },
		Frost = { RockColor = Color3.fromRGB(95, 135, 185), CoreColor = Color3.fromRGB(125, 240, 255), TrailColor = Color3.fromRGB(85, 220, 255) },
		Astral = { RockColor = Color3.fromRGB(90, 75, 135), CoreColor = Color3.fromRGB(255, 210, 80), TrailColor = Color3.fromRGB(215, 110, 255) },
	}
	return fallbackCritters, fallbackMeteors
end

local function configurePartDefaults(part: BasePart, color: Color3, material: Enum.Material, castShadow: boolean): ()
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("SurfaceAppearance") then
			child:Destroy()
		end
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = castShadow
	part.Material = material
	part.Color = color
end

local function measureMinWorldY(model: Model): number
	local minY = math.huge
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			local half = desc.Size * 0.5
			local cf = desc.CFrame
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local wc = cf:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
						minY = math.min(minY, wc.Y)
					end
				end
			end
		end
	end
	return minY
end

local function applyToModel(model: Model, critterPal: CritterPalette?, meteorPal: MeteorPalette?): boolean
	local parts: { [string]: BasePart } = {}
	local basePartCount = 0
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			basePartCount += 1
			parts[desc.Name] = desc
		end
	end

	if critterPal ~= nil then
		local body = parts["Body"]
		local secondary = parts["Secondary"]
		local eyes = parts["Eyes"]
		local accent = parts["Accent"]
		assert(body and eyes and accent, string.format("%s missing expected Body/Eyes/Accent BaseParts", model:GetFullName()))
		configurePartDefaults(body, critterPal.BodyColor, Enum.Material.SmoothPlastic, true)
		if secondary ~= nil and critterPal.SecondaryColor ~= nil then
			configurePartDefaults(secondary, critterPal.SecondaryColor, Enum.Material.SmoothPlastic, true)
		end
		configurePartDefaults(eyes, COLOR_EYE, Enum.Material.SmoothPlastic, false)
		configurePartDefaults(accent, critterPal.AccentColor, Enum.Material.Neon, false)
		model.PrimaryPart = body
	elseif meteorPal ~= nil then
		local rock = parts["RockBody"]
		local core = parts["CoreShards"]
		local crest = parts["TraitCrest"]
		assert(rock and core and crest, string.format("%s missing expected RockBody/CoreShards/TraitCrest BaseParts", model:GetFullName()))
		configurePartDefaults(rock, meteorPal.RockColor, Enum.Material.SmoothPlastic, true)
		configurePartDefaults(core, meteorPal.CoreColor, Enum.Material.Neon, false)
		configurePartDefaults(crest, meteorPal.TrailColor, Enum.Material.Neon, false)
		model.PrimaryPart = rock
	else
		return false
	end

	assert(basePartCount <= 8, string.format("%s exceeds 8-BasePart budget (%d)", model:GetFullName(), basePartCount))
	local _, bboxSize = model:GetBoundingBox()
	assert(bboxSize.Y <= 8.0, string.format("%s height %.3f exceeds 8.0 stud budget", model:GetFullName(), bboxSize.Y))

	local minY = measureMinWorldY(model)
	local pivotDelta = math.abs(model:GetPivot().Position.Y - minY)
	assert(pivotDelta <= 0.05, string.format("%s ground pivot offset %.4f > 0.05", model:GetFullName(), pivotDelta))

	print(string.format(
		"[ApplyHeroMeshTemplateDefaults] Styled %s | Parts=%d/8 | Size=(%.3f, %.3f, %.3f) | PivotDeltaY=%.4f",
		model:GetFullName(),
		basePartCount,
		bboxSize.X,
		bboxSize.Y,
		bboxSize.Z,
		pivotDelta
	))
	return true
end

local critterPalettes, meteorPalettes = loadPalettes()
local containers: { Instance } = { workspace }
local assetTemplates = ReplicatedStorage:FindFirstChild("AssetTemplates")
if assetTemplates ~= nil then
	for _, folderName in ipairs({ "Critters", "Meteors" }) do
		local sub = assetTemplates:FindFirstChild(folderName)
		if sub ~= nil then
			table.insert(containers, sub)
		end
	end
end

local styledCount = 0
for _, container in ipairs(containers) do
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Model") then
			if applyToModel(child, critterPalettes[child.Name], meteorPalettes[child.Name]) then
				styledCount += 1
			end
		end
	end
end

print(string.format("[ApplyHeroMeshTemplateDefaults] Completed styling %d hero mesh model(s).", styledCount))
