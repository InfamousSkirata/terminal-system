local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local TerminalRegistry = require(script.Parent:WaitForChild("TerminalRegistry"))

type Faction = Types.Faction
type TerminalState = Types.TerminalState

export type TeamCounts = {
	TGE: number,
	TRA: number,
	THC: number,
}

local TerminalCaptureService = {}

local running = false
local heartbeatConnection: RBXScriptConnection? = nil
local elapsed = 0

local function sortedFactionCounts(counts: TeamCounts): { { faction: Faction, count: number } }
	local rows = {
		{ faction = "TGE" :: Faction, count = counts.TGE },
		{ faction = "TRA" :: Faction, count = counts.TRA },
		{ faction = "THC" :: Faction, count = counts.THC },
	}

	table.sort(rows, function(a, b)
		return a.count > b.count
	end)

	return rows
end

local function isEligible(player: Player): boolean
	if player.Team == nil then
		return false
	end

	local teamName = player.Team.Name
	local isFaction = false
	for _, faction in ipairs(Config.Teams.Factions) do
		if teamName == faction then
			isFaction = true
			break
		end
	end
	if not isFaction then
		return false
	end

	local character = player.Character
	if not character then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and root:IsA("BasePart")
end

local function computeTeamCounts(state: TerminalState): TeamCounts
	local counts: TeamCounts = {
		TGE = 0,
		TRA = 0,
		THC = 0,
	}

	for _, player in ipairs(Players:GetPlayers()) do
		if not isEligible(player) then
			continue
		end

		local root = player.Character
		if not root then
			continue
		end

		local hrp = root:FindFirstChild("HumanoidRootPart")
		if not hrp or not hrp:IsA("BasePart") then
			continue
		end
		local distance = (hrp.Position - state.terminalPart.Position).Magnitude
		if distance <= state.zoneRadius then
			local teamName = player.Team.Name
			counts[teamName :: Faction] += 1
		end
	end

	return counts
end

local function resolveActiveContender(counts: TeamCounts): Faction?
	local rows = sortedFactionCounts(counts)
	local leader = rows[1]
	local second = rows[2]

	if leader.count <= 0 then
		return nil
	end

	if leader.count >= (second.count + 1) then
		return leader.faction
	end

	return nil
end

local function computeSpeedMultiplier(activeCount: number): number
	local capped = math.min(activeCount, Config.Terminal.SpeedCapPlayers)
	local normalized = capped / Config.Terminal.SpeedCapPlayers
	return Config.Terminal.SpeedMinMultiplier + ((1 - Config.Terminal.SpeedMinMultiplier) * normalized)
end

local function computeDeltaPerTick(baseTimeSeconds: number, multiplier: number, tickSeconds: number): number
	local ratePerSecond = (100 * multiplier) / baseTimeSeconds
	return ratePerSecond * tickSeconds
end

local function handleOwnedState(terminalKey: string, state: TerminalState, contender: Faction, leaderCount: number, tickSeconds: number)
	local multiplier = computeSpeedMultiplier(leaderCount)
	local delta = computeDeltaPerTick(Config.Terminal.NeutralizeBaseSeconds, multiplier, tickSeconds)

	if contender == state.ownerFaction then
		TerminalRegistry.SetProgress(terminalKey, state.progress + delta)
		return
	end

	TerminalRegistry.SetProgress(terminalKey, state.progress - delta)
	if state.progress > 0 then
		return
	end

	TerminalRegistry.SetProgress(terminalKey, 0)
	TerminalRegistry.SetOwner(terminalKey, "Neutral")
	TerminalRegistry.SetNeutralProgressFaction(terminalKey, nil)
end

local function handleNeutralState(terminalKey: string, state: TerminalState, contender: Faction?, leaderCount: number, tickSeconds: number)
	if contender == nil then
		return
	end

	local multiplier = computeSpeedMultiplier(leaderCount)
	local delta = computeDeltaPerTick(Config.Terminal.CaptureBaseSeconds, multiplier, tickSeconds)
	local currentFaction = state.neutralProgressFaction

	if currentFaction == nil then
		TerminalRegistry.SetNeutralProgressFaction(terminalKey, contender)
		currentFaction = contender
	end

	if currentFaction ~= contender then
		TerminalRegistry.SetProgress(terminalKey, state.progress - delta)
		if state.progress <= 0 then
			TerminalRegistry.SetProgress(terminalKey, 0)
			TerminalRegistry.SetNeutralProgressFaction(terminalKey, contender)
		end
		return
	end

	TerminalRegistry.SetProgress(terminalKey, state.progress + delta)
	if state.progress < 100 then
		return
	end

	TerminalRegistry.SetProgress(terminalKey, 100)
	TerminalRegistry.SetOwner(terminalKey, contender)
end

local function processTerminal(terminalKey: string, state: TerminalState, tickSeconds: number)
	if state.phase ~= "CaptureWindowActive" then
		return
	end

	local counts = computeTeamCounts(state)
	local contender = resolveActiveContender(counts)
	local leaderCount = if contender == nil then 0 else counts[contender]

	TerminalRegistry.SetActiveContender(terminalKey, contender)

	if state.ownerFaction == "Neutral" then
		handleNeutralState(terminalKey, state, contender, leaderCount, tickSeconds)
	else
		if contender ~= nil then
			handleOwnedState(terminalKey, state, contender, leaderCount, tickSeconds)
		end
	end
end

function TerminalCaptureService.Start()
	if running then
		return
	end

	running = true
	elapsed = 0

	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt

		if elapsed < Config.Terminal.TickSeconds then
			return
		end

		local tickSeconds = elapsed
		elapsed = 0

		for terminalKey, state in pairs(TerminalRegistry.GetAll()) do
			processTerminal(terminalKey, state, tickSeconds)
		end
	end)
end

function TerminalCaptureService.Stop()
	if not running then
		return
	end

	running = false
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
end

return TerminalCaptureService
