--!strict
--[[
	Tool: VerifyS403SoakPreflight (Read-Only Studio Command-Bar / Audit Helper)
	Purpose: Verifies pre-publish readiness for S4-03 on StarfallRanch_Dev.rbxl or the private
	         published playtest place (106917003014718): Constants build flags, Greybox map contract,
	         all 6 v2 Critter templates, and all 3 angular Meteor templates under ReplicatedStorage.AssetTemplates.
	Usage: Paste and run in Studio Command Bar (pure read-only; mutates nothing).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local CritterConfig = require(Shared:WaitForChild("Config"):WaitForChild("CritterConfig"))
local MeteorConfig = require(Shared:WaitForChild("Config"):WaitForChild("MeteorConfig"))
local GreyboxBuilder = require(Shared:WaitForChild("Util"):WaitForChild("GreyboxBuilder"))

local EXPECTED_CRITTER_MESHES = { "Accent", "Body", "Eyes", "Secondary" }
local EXPECTED_METEOR_MESHES = { "CoreShards", "RockBody", "TraitCrest" }

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

local function inspectTemplateModel(
	folder: Instance?,
	assetName: string,
	expectedMeshes: { string },
	expectedPrimary: string,
	checkEyesForward: boolean,
	maxHeight: number?
): (boolean, string)
	if folder == nil then
		return false, string.format("FAIL %-11s | Missing parent folder", assetName)
	end
	local model = folder:FindFirstChild(assetName)
	if model == nil or not model:IsA("Model") then
		return false, string.format("FAIL %-11s | Missing Model template in %s", assetName, folder:GetFullName())
	end

	local children = model:GetChildren()
	if #children ~= #expectedMeshes then
		return false, string.format("FAIL %-11s | Expected %d MeshParts, found %d", assetName, #expectedMeshes, #children)
	end

	local meshMap: { [string]: MeshPart } = {}
	for _, child in ipairs(children) do
		if not child:IsA("MeshPart") then
			return false, string.format("FAIL %-11s | Non-MeshPart child %s (%s)", assetName, child.Name, child.ClassName)
		end
		if child.DoubleSided ~= false then
			return false, string.format("FAIL %-11s | %s.DoubleSided is true", assetName, child.Name)
		end
		if not (child.Anchored and not child.CanCollide and not child.CanQuery and not child.CanTouch) then
			return false, string.format("FAIL %-11s | %s anchor/collision/query flags invalid", assetName, child.Name)
		end
		if child:FindFirstChildOfClass("SurfaceAppearance") ~= nil then
			return false, string.format("FAIL %-11s | %s still contains SurfaceAppearance", assetName, child.Name)
		end
		meshMap[child.Name] = child
	end

	for _, meshName in ipairs(expectedMeshes) do
		if meshMap[meshName] == nil then
			return false, string.format("FAIL %-11s | Missing MeshPart '%s'", assetName, meshName)
		end
	end

	if model.PrimaryPart == nil or model.PrimaryPart.Name ~= expectedPrimary then
		return false, string.format("FAIL %-11s | PrimaryPart must be '%s'", assetName, expectedPrimary)
	end

	local _, bbox = model:GetBoundingBox()
	if maxHeight ~= nil and bbox.Y > maxHeight then
		return false, string.format("FAIL %-11s | Height %.3f exceeds %.1f studs", assetName, bbox.Y, maxHeight)
	end

	local minY = measureMinWorldY(model)
	local pivotDelta = math.abs(model:GetPivot().Position.Y - minY)
	if pivotDelta > 0.01 then
		return false, string.format("FAIL %-11s | PivotDeltaY %.4f > 0.01", assetName, pivotDelta)
	end

	local extra = ""
	if checkEyesForward then
		local eyesLocalZ = model:GetPivot():PointToObjectSpace(meshMap["Eyes"].Position).Z
		if eyesLocalZ >= 0 then
			return false, string.format("FAIL %-11s | Eyes localZ %.4f >= 0 (must face -Z)", assetName, eyesLocalZ)
		end
		extra = string.format(" | EyesZ=%.4f", eyesLocalZ)
	end

	return true, string.format(
		"PASS %-11s | Parts=%d | Size=(%.3f x %.3f x %.3f) | PivotDelta=%.4f%s",
		assetName,
		#children,
		bbox.X,
		bbox.Y,
		bbox.Z,
		pivotDelta,
		extra
	)
end

local lines: { string } = {}
local function logLine(line: string): ()
	table.insert(lines, line)
	print("[VerifyS403SoakPreflight] " .. line)
end

logLine("=== S4-03 Soak Preflight Report (Read-Only) ===")
logLine(string.format(
	"Build: GAME_VERSION=%s | USE_MOCK_STORE=%s | PlaceId=%d | GameId=%d | MaxPlayers=%d",
	tostring(Constants.GAME_VERSION),
	tostring(Constants.USE_MOCK_STORE),
	game.PlaceId,
	game.GameId,
	Players.MaxPlayers
))

if Constants.USE_MOCK_STORE then
	logLine("FAIL USE_MOCK_STORE must be false before publishing S4-03 soak build")
end
if game.PlaceId == 0 then
	logLine("NOTE Unpublished local place (PlaceId=0) — publish to private test place (106917003014718) before device soak")
end
if Players.MaxPlayers ~= Constants.MAX_PLOTS_ALPHA then
	logLine(string.format(
		"NOTE Players.MaxPlayers=%d (set Game Settings -> Places -> Max Players = %d before 6-player soak if publishing)",
		Players.MaxPlayers,
		Constants.MAX_PLOTS_ALPHA
	))
end

local greyboxRoot = workspace:FindFirstChild(Constants.GREYBOX_ROOT_NAME)
local greyboxOk = false
if greyboxRoot == nil then
	logLine("FAIL Greybox: Missing Workspace." .. Constants.GREYBOX_ROOT_NAME)
else
	local valid, reason = GreyboxBuilder.ValidateHierarchy(greyboxRoot)
	greyboxOk = valid
	if valid then
		logLine("PASS Greybox: ValidateHierarchy passed (" .. greyboxRoot:GetFullName() .. ")")
	else
		logLine("FAIL Greybox: " .. reason)
	end
end

local templatesRoot = ReplicatedStorage:FindFirstChild(Constants.ASSET_TEMPLATES_FOLDER_NAME)
local crittersFolder = if templatesRoot ~= nil then templatesRoot:FindFirstChild("Critters") else nil
local meteorsFolder = if templatesRoot ~= nil then templatesRoot:FindFirstChild("Meteors") else nil

local critterPass = 0
for _, speciesId in ipairs(CritterConfig.OrderedIds) do
	local ok, msg = inspectTemplateModel(
		crittersFolder,
		speciesId,
		EXPECTED_CRITTER_MESHES,
		"Body",
		true,
		Constants.MAX_CRITTER_DISPLAY_HEIGHT
	)
	if ok then
		critterPass += 1
	end
	logLine(msg)
end

local meteorPass = 0
for _, traitId in ipairs(MeteorConfig.OrderedIds) do
	local ok, msg = inspectTemplateModel(
		meteorsFolder,
		traitId,
		EXPECTED_METEOR_MESHES,
		"RockBody",
		false,
		Constants.MAX_CRITTER_DISPLAY_HEIGHT
	)
	if ok then
		meteorPass += 1
	end
	logLine(msg)
end

local allAssetsReady = greyboxOk
	and not Constants.USE_MOCK_STORE
	and critterPass == #CritterConfig.OrderedIds
	and meteorPass == #MeteorConfig.OrderedIds

local status = if allAssetsReady
	then (if game.PlaceId == 0 then "ASSETS_READY_FOR_PUBLISH" else "READY_FOR_SOAK")
	else "BLOCKED_MISSING_ASSETS"

logLine(string.format(
	"SUMMARY: Status=%s | Greybox=%s | Critters=%d/%d | Meteors=%d/%d",
	status,
	if greyboxOk then "PASS" else "FAIL",
	critterPass,
	#CritterConfig.OrderedIds,
	meteorPass,
	#MeteorConfig.OrderedIds
))

return table.concat(lines, "\n")
