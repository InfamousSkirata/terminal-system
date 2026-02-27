local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
if not Config.Diagnostics.Pass2HarnessEnabled then
	return
end

local Services = script.Parent.Parent:WaitForChild("Services")
local TerminalCaptureService = require(Services:WaitForChild("TerminalCaptureService"))
local TerminalRegistry = require(Services:WaitForChild("TerminalRegistry"))

local function firstTerminal()
	for key, state in pairs(TerminalRegistry.GetAll()) do
		return key, state
	end
	return nil, nil
end

local function ensureTeam(name: string): Team
	local existing = Teams:FindFirstChild(name)
	if existing and existing:IsA("Team") then
		return existing
	end

	local team = Instance.new("Team")
	team.Name = name
	team.Parent = Teams
	return team
end

local function setForcedCounts(part: BasePart, tge: number, tra: number, thc: number)
	part:SetAttribute("P1_ForceTGE", tge)
	part:SetAttribute("P1_ForceTRA", tra)
	part:SetAttribute("P1_ForceTHC", thc)
end

local function clearForcedCounts(part: BasePart)
	part:SetAttribute("P1_ForceTGE", nil)
	part:SetAttribute("P1_ForceTRA", nil)
	part:SetAttribute("P1_ForceTHC", nil)
end

local function waitFor(predicate: () -> boolean, timeoutSeconds: number): boolean
	local deadline = os.clock() + timeoutSeconds
	while os.clock() < deadline do
		if predicate() then
			return true
		end
		task.wait(0.1)
	end
	return predicate()
end

task.delay(4, function()
	local terminalKey, terminalState = firstTerminal()
	if not terminalKey or not terminalState then
		print("[P2_HARNESS] pass=0 reason=no_terminals")
		return
	end

	local player = Players:GetPlayers()[1]
	if not player then
		print("[P2_HARNESS] pass=0 reason=no_player")
		return
	end

local teamFaction = ensureTeam("TGE")
local teamCivilian = ensureTeam(Config.Teams.Civilian)

local originalBands = Config.Terminal.CaptureWindowSecondsByPopulation
local originalOvertimeCap = Config.Terminal.OvertimeCapSeconds
local originalCooldown = Config.Terminal.CooldownSeconds

if Config.Diagnostics.Pass2HarnessOverrideDurations then
	Config.Terminal.CaptureWindowSecondsByPopulation = { { maxPlayers = 999, seconds = 3 } }
	Config.Terminal.OvertimeCapSeconds = 4
	Config.Terminal.CooldownSeconds = 3
end
Config.Diagnostics.UseForcedTeamCounts = true

	player.Team = teamCivilian
	local okIneligible, reasonIneligible = TerminalCaptureService.TryStartCapture(player, terminalKey)
	local ineligibleOk = (not okIneligible) and reasonIneligible == "ineligible_player"

	player.Team = teamFaction
	local okStart, reasonStart = TerminalCaptureService.TryStartCapture(player, terminalKey)
	local startedOk = okStart and reasonStart == "ok"

	local okBlocked, reasonBlocked = TerminalCaptureService.TryStartCapture(player, terminalKey)
	local blockedOk = (not okBlocked) and reasonBlocked == "phase_blocked"

	local part = terminalState.terminalPart
	setForcedCounts(part, 5, 0, 0)
	local overtimeOk = waitFor(function()
		return terminalState.phase == "Overtime"
	end, 10)

	setForcedCounts(part, 0, 0, 0)
	local cooldownOk = waitFor(function()
		return terminalState.phase == "Cooldown"
	end, 5)

	local idleOk = waitFor(function()
		return terminalState.phase == "Idle"
	end, 6)

	Config.Terminal.CaptureWindowSecondsByPopulation = originalBands
	Config.Terminal.OvertimeCapSeconds = originalOvertimeCap
	Config.Terminal.CooldownSeconds = originalCooldown
	Config.Diagnostics.UseForcedTeamCounts = false
	clearForcedCounts(part)

	local pass = ineligibleOk and startedOk and blockedOk and overtimeOk and cooldownOk and idleOk
	print(string.format(
		"[P2_HARNESS] pass=%d ineligible_ok=%d started_ok=%d blocked_ok=%d overtime_ok=%d cooldown_ok=%d idle_ok=%d",
		if pass then 1 else 0,
		if ineligibleOk then 1 else 0,
		if startedOk then 1 else 0,
		if blockedOk then 1 else 0,
		if overtimeOk then 1 else 0,
		if cooldownOk then 1 else 0,
		if idleOk then 1 else 0
	))
end)
