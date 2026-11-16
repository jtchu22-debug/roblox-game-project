--!strict
--[[
	Controller: CrackController
	Purpose: Handles Crater Meteor ProximityPrompt triggers, executes the server-nonce Start -> Finish crack
	         flow, and tracks MeteorLifecycle remote updates for Stage 1 client feel.
	Connections: Invokes RequestStartCrack and RequestFinishCrack; listens to MeteorLifecycle.
	How to Test in Studio: Press Play (F5), walk into CentralCrater, and press E / Tap on a Meteor!
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))

local CrackController = {
	Name = "CrackController",
}

local isCracking = false
local promptConn: RBXScriptConnection? = nil
local lifecycleConn: RBXScriptConnection? = nil

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

function CrackController.Init(self: typeof(CrackController)): ()
	-- Lightweight visual progress bar UI arrives in S1-08.
end

function CrackController.Start(self: typeof(CrackController)): ()
	local remotes = ReplicatedStorage:WaitForChild(Constants.REMOTES_FOLDER_NAME)
	local startCrackFn = remotes:WaitForChild(Constants.REMOTE_NAMES.RequestStartCrack) :: RemoteFunction
	local finishCrackFn = remotes:WaitForChild(Constants.REMOTE_NAMES.RequestFinishCrack) :: RemoteFunction
	local meteorLifecycleEvent = remotes:WaitForChild(Constants.REMOTE_NAMES.MeteorLifecycle) :: RemoteEvent

	if lifecycleConn == nil then
		lifecycleConn = meteorLifecycleEvent.OnClientEvent:Connect(function(_payload: { [string]: any })
			-- Tracked cleanly for S1-08 trail/particle feedback.
		end)
	end

	if promptConn == nil then
		promptConn = ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, playerWhoTriggered: Player)
			if playerWhoTriggered ~= Players.LocalPlayer then
				return
			end
			if isCracking then
				return
			end

			local meteorModel = findMeteorModelFromPrompt(prompt)
			if meteorModel == nil then
				return
			end

			local meteorUID = meteorModel:GetAttribute("MeteorUID")
			if typeof(meteorUID) ~= "string" then
				return
			end

			isCracking = true
			task.spawn(function()
				local okStart, startRes = pcall(function()
					return startCrackFn:InvokeServer(meteorUID)
				end)
				if not okStart or typeof(startRes) ~= "table" or not startRes.Ok then
					local reason = if typeof(startRes) == "table" and startRes.Reason then tostring(startRes.Reason) else "Failed"
					warn("[CrackController] Could not start meteor rescue: " .. reason)
					isCracking = false
					return
				end

				-- Minimal tactile delay respecting server MIN_CRACK_DURATION_SECONDS (0.4s); S1-08 adds visual bar.
				task.wait(0.45)

				local okFinish, finishRes = pcall(function()
					return finishCrackFn:InvokeServer(meteorUID, startRes.AttemptNonce)
				end)
				if okFinish and typeof(finishRes) == "table" and finishRes.Ok then
					print(string.format("[CrackController] Rescued Star-Pod: %s!", tostring(finishRes.SpeciesId)))
				else
					local reason = if typeof(finishRes) == "table" and finishRes.Reason then tostring(finishRes.Reason) else "Failed"
					warn("[CrackController] Could not finish meteor rescue: " .. reason)
				end

				isCracking = false
			end)
		end)
	end
end

return CrackController
