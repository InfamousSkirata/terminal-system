local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
if not Config.Diagnostics.P2TestPrints then
	return
end

local Services = script.Parent.Parent:WaitForChild("Services")
local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local TerminalInteractionService = require(Services:WaitForChild("TerminalInteractionService"))
local TerminalRegistry = require(Services:WaitForChild("TerminalRegistry"))

local function firstTerminal()
	for key, state in pairs(TerminalRegistry.GetAll()) do
		return key, state
	end
	return nil, nil
end

local function forceCaptureWindow(terminalKey: string, state, durationSeconds: number)
	local nowTs = os.clock()
	state.phase = "CaptureWindowActive"
	state.captureWindowDurationSeconds = durationSeconds
	state.captureWindowEndTime = nowTs + durationSeconds
	state.overtimeStartedAt = nil
	state.cooldownEndTime = nil
	state.lastStartUserId = nil
	state.terminalPart:SetAttribute("TerminalPhase", state.phase)
	state.terminalPart:SetAttribute("CaptureWindowEndTime", state.captureWindowEndTime)
	state.terminalPart:SetAttribute("CooldownEndTime", nil)
end

local function ensureTeams()
	for _, name in ipairs(Config.Teams.Factions) do
		if not Teams:FindFirstChild(name) then
			local team = Instance.new("Team")
			team.Name = name
			team.Parent = Teams
		end
	end
	if not Teams:FindFirstChild(Config.Teams.Civilian) then
		local team = Instance.new("Team")
		team.Name = Config.Teams.Civilian
		team.Parent = Teams
	end
end

local function movePlayerTo(player: Player, position: Vector3)
	local character = player.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.CFrame = CFrame.new(position)
	end
end

task.delay(6, function()
	ensureTeams()
	local player = Players:GetPlayers()[1]
	if not player then
		return
	end
	player.Team = Teams:FindFirstChild("TGE")

	local terminalKey, state = firstTerminal()
	if not terminalKey or not state then
		return
	end

	state.phase = "Idle"
	state.cooldownEndTime = nil
	state.terminalPart:SetAttribute("TerminalPhase", "Idle")
	state.terminalPart:SetAttribute("CooldownEndTime", nil)
	TerminalInteractionService.DebugTrigger(player, terminalKey)

	TerminalRegistry.SetOwner(terminalKey, "Neutral")
	TerminalRegistry.SetProgress(terminalKey, 60)
	TerminalRegistry.SetNeutralProgressFaction(terminalKey, nil)
	forceCaptureWindow(terminalKey, state, 6)

	movePlayerTo(player, state.terminalPart.Position + Vector3.new(0, 3, 0))
	task.delay(8, function()
		movePlayerTo(player, state.terminalPart.Position + Vector3.new(0, 3, 500))
	end)

	task.delay(18, function()
		TerminalRegistry.SetOwner(terminalKey, "THC")
		TerminalRegistry.SetProgress(terminalKey, 60)
		TerminalRegistry.SetNeutralProgressFaction(terminalKey, nil)
		forceCaptureWindow(terminalKey, state, 12)
		movePlayerTo(player, state.terminalPart.Position + Vector3.new(0, 3, 500))
	end)

	task.delay(30, function()
		TerminalRegistry.SetOwner(terminalKey, "Neutral")
		TerminalRegistry.SetProgress(terminalKey, 60)
		TerminalRegistry.SetNeutralProgressFaction(terminalKey, nil)
		forceCaptureWindow(terminalKey, state, 12)
		movePlayerTo(player, state.terminalPart.Position + Vector3.new(0, 3, 500))
	end)
end)
