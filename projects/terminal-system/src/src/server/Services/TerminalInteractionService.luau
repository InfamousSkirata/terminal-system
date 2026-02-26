local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local TerminalRegistry = require(script.Parent:WaitForChild("TerminalRegistry"))

type TerminalState = Types.TerminalState

local TerminalInteractionService = {}

local promptConnections: { RBXScriptConnection } = {}
local windowsStarted = 0
local rejects = 0
local durationBucketOk = true

local function testPrint(message: string)
	if Config.Diagnostics.P2TestPrints then
		print(message)
	end
end

local function emitStartSummary()
	testPrint(string.format(
		"[P2_SUMMARY] step=start windows_started=%d rejects=%d duration_bucket_ok=%d errors=0",
		windowsStarted,
		rejects,
		if durationBucketOk then 1 else 0
	))
end

local function clearConnections()
	for _, conn in ipairs(promptConnections) do
		conn:Disconnect()
	end
	table.clear(promptConnections)
end

local function computeWindowDurationSeconds(playerCount: number): number
	if playerCount <= 20 then
		return Config.Terminal.CaptureWindowSecondsLowPop
	elseif playerCount <= 39 then
		return Config.Terminal.CaptureWindowSecondsMidPop
	elseif playerCount <= 49 then
		return Config.Terminal.CaptureWindowSecondsHighPop
	end
	return Config.Terminal.CaptureWindowSecondsMaxPop
end

local function isPlayerAlive(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function canPlayerStartWindow(player: Player, state: TerminalState): (boolean, string?)
	if player.Team == nil then
		return false, "missing-team"
	end

	local teamName = player.Team.Name
	if teamName == Config.Teams.Civilian then
		return false, "civilian"
	end

	local validFaction = false
	for _, faction in ipairs(Config.Teams.Factions) do
		if teamName == faction then
			validFaction = true
			break
		end
	end
	if not validFaction then
		return false, "invalid-team"
	end

	if not isPlayerAlive(player) then
		return false, "dead"
	end

	if state.phase ~= "Idle" then
		return false, "not-idle"
	end

	if state.cooldownEndTime and os.clock() < state.cooldownEndTime then
		return false, "cooldown"
	end

	return true, nil
end

local function ensurePrompt(state: TerminalState): ProximityPrompt
	local existing = state.terminalPart:FindFirstChild("TerminalInteractPrompt")
	if existing and existing:IsA("ProximityPrompt") then
		return existing
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TerminalInteractPrompt"
	prompt.ActionText = "Contest"
	prompt.ObjectText = "Terminal"
	prompt.HoldDuration = Config.Terminal.PromptHoldSeconds
	prompt.MaxActivationDistance = Config.Terminal.PromptMaxDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = state.terminalPart
	return prompt
end

local function onPromptTriggered(player: Player, terminalKey: string)
	local state = TerminalRegistry.GetByKey(terminalKey)
	if not state then
		return
	end

	local ok, reason = canPlayerStartWindow(player, state)
	if not ok then
		rejects += 1
		testPrint(string.format(
			"[P2_TEST] start_request terminal=%s team=%s phase=%s accepted=0 reason=%s",
			state.terminalId,
			if player.Team then player.Team.Name else "None",
			state.phase,
			reason or "rejected"
		))
		emitStartSummary()
		return
	end

	local playerCount = #Players:GetPlayers()
	local durationSeconds = computeWindowDurationSeconds(playerCount)
	local accepted = TerminalRegistry.TryStartCaptureWindow(terminalKey, durationSeconds, player.UserId)
	if not accepted then
		rejects += 1
		testPrint(string.format(
			"[P2_TEST] start_request terminal=%s team=%s phase=%s accepted=0 reason=race-reject",
			state.terminalId,
			if player.Team then player.Team.Name else "None",
			state.phase
		))
		emitStartSummary()
		return
	end

	windowsStarted += 1
	local validDuration = durationSeconds == Config.Terminal.CaptureWindowSecondsLowPop
		or durationSeconds == Config.Terminal.CaptureWindowSecondsMidPop
		or durationSeconds == Config.Terminal.CaptureWindowSecondsHighPop
		or durationSeconds == Config.Terminal.CaptureWindowSecondsMaxPop
	durationBucketOk = durationBucketOk and validDuration

	testPrint(string.format(
		"[P2_TEST] start_request terminal=%s team=%s phase=%s accepted=1 reason=ok",
		state.terminalId,
		if player.Team then player.Team.Name else "None",
		state.phase
	))
	testPrint(string.format(
		"[P2_TEST] window_started terminal=%s duration=%d pop=%d",
		state.terminalId,
		durationSeconds,
		playerCount
	))
	emitStartSummary()
end

function TerminalInteractionService.Start()
	clearConnections()
	windowsStarted = 0
	rejects = 0
	durationBucketOk = true

	for terminalKey, state in pairs(TerminalRegistry.GetAll()) do
		local prompt = ensurePrompt(state)
		local connection = prompt.Triggered:Connect(function(player)
			onPromptTriggered(player, terminalKey)
		end)
		table.insert(promptConnections, connection)
	end
end

function TerminalInteractionService.Stop()
	clearConnections()
end

return TerminalInteractionService
