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
local summaryElapsed = 0

local overtimeStartedCount = 0
local overtimeEndedCount = 0
local cooldownStartedCount = 0
local regenOk = false
local decayOk = false
local tieFreezeOk = true

local function testPrint(message: string)
	if Config.Diagnostics.P2TestPrints then
		print(message)
	end
end

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

local function totalContenders(counts: TeamCounts): number
	return counts.TGE + counts.TRA + counts.THC
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

local function applyProgressDelta(baseTimeSeconds: number, effectiveCount: number, tickSeconds: number): number
	local multiplier = computeSpeedMultiplier(effectiveCount)
	return computeDeltaPerTick(baseTimeSeconds, multiplier, tickSeconds)
end

local function emitSummaries()
	testPrint(string.format(
		"[P2_SUMMARY] step=overtime overtime_started=%d overtime_ended=%d cooldown_started=%d errors=0",
		overtimeStartedCount,
		overtimeEndedCount,
		cooldownStartedCount
	))
	testPrint(string.format(
		"[P2_SUMMARY] step=regen_decay regen_ok=%d decay_ok=%d tie_freeze_ok=%d errors=0",
		if regenOk then 1 else 0,
		if decayOk then 1 else 0,
		if tieFreezeOk then 1 else 0
	))
end

local function enterCooldown(terminalKey: string, reason: string)
	cooldownStartedCount += 1
	TerminalRegistry.StartCooldown(terminalKey, Config.Terminal.CooldownSeconds)
	local state = TerminalRegistry.GetByKey(terminalKey)
	if state then
		testPrint(string.format(
			"[P2_TEST] cooldown terminal=%s started=1 ends_in=%d reason=%s",
			state.terminalId,
			Config.Terminal.CooldownSeconds,
			reason
		))
	end
end

local function handleOwnedState(
	terminalKey: string,
	state: TerminalState,
	contender: Faction?,
	leaderCount: number,
	totalInZone: number,
	tickSeconds: number
)
	local before = state.progress
	if contender == nil then
		if totalInZone == 0 then
			local delta = applyProgressDelta(
				Config.Terminal.NeutralizeBaseSeconds,
				Config.Terminal.RegenDecayVirtualCount,
				tickSeconds
			)
			TerminalRegistry.SetProgress(terminalKey, state.progress + delta)
			if state.progress > before then
				regenOk = true
				testPrint(string.format("[P2_TEST] regen terminal=%s from=%.1f to=%.1f", state.terminalId, before, state.progress))
			end
		end
		return
	end

	if contender == state.ownerFaction then
		local delta = applyProgressDelta(Config.Terminal.NeutralizeBaseSeconds, leaderCount, tickSeconds)
		TerminalRegistry.SetProgress(terminalKey, state.progress + delta)
		if state.progress > before then
			regenOk = true
		end
		return
	end

	local delta = applyProgressDelta(Config.Terminal.NeutralizeBaseSeconds, leaderCount, tickSeconds)
	TerminalRegistry.SetProgress(terminalKey, state.progress - delta)
	if state.progress > 0 then
		return
	end

	TerminalRegistry.SetProgress(terminalKey, 0)
	TerminalRegistry.SetOwner(terminalKey, "Neutral")
	TerminalRegistry.SetNeutralProgressFaction(terminalKey, nil)
end

local function handleNeutralState(
	terminalKey: string,
	state: TerminalState,
	contender: Faction?,
	leaderCount: number,
	tickSeconds: number
): boolean
	local before = state.progress
	if contender == nil then
		local decay = applyProgressDelta(
			Config.Terminal.CaptureBaseSeconds,
			Config.Terminal.RegenDecayVirtualCount,
			tickSeconds
		)
		TerminalRegistry.SetProgress(terminalKey, state.progress - decay)
		if state.progress < before then
			decayOk = true
			testPrint(string.format("[P2_TEST] decay terminal=%s from=%.1f to=%.1f", state.terminalId, before, state.progress))
		end
		if state.progress <= 0 then
			TerminalRegistry.SetProgress(terminalKey, 0)
			TerminalRegistry.SetNeutralProgressFaction(terminalKey, nil)
		end
		return false
	end

	local delta = applyProgressDelta(Config.Terminal.CaptureBaseSeconds, leaderCount, tickSeconds)
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
		return false
	end

	TerminalRegistry.SetProgress(terminalKey, state.progress + delta)
	if state.progress < 100 then
		return false
	end

	TerminalRegistry.SetProgress(terminalKey, 100)
	TerminalRegistry.SetOwner(terminalKey, contender)
	TerminalRegistry.SetNeutralProgressFaction(terminalKey, nil)
	enterCooldown(terminalKey, "captured")
	return true
end

local function resolveWindowTimeout(terminalKey: string, state: TerminalState, contender: Faction?, nowTs: number)
	if not state.captureWindowEndTime or nowTs < state.captureWindowEndTime then
		return
	end

	testPrint(string.format(
		"[P2_TEST] timeout terminal=%s contender=%s phase_before=%s",
		state.terminalId,
		contender or "None",
		state.phase
	))

	if contender ~= nil then
		overtimeStartedCount += 1
		TerminalRegistry.StartOvertime(terminalKey, nowTs)
		testPrint(string.format("[P2_TEST] overtime terminal=%s started=1 ended=none", state.terminalId))
	else
		enterCooldown(terminalKey, "window-timeout-no-contender")
	end
end

local function resolveOvertimeExit(terminalKey: string, state: TerminalState, contender: Faction?, nowTs: number)
	if contender == nil then
		overtimeEndedCount += 1
		testPrint(string.format("[P2_TEST] overtime terminal=%s started=1 ended=lead-lost", state.terminalId))
		enterCooldown(terminalKey, "overtime-lead-lost")
		return
	end

	if state.overtimeStartedAt and nowTs >= (state.overtimeStartedAt + Config.Terminal.OvertimeMaxSeconds) then
		overtimeEndedCount += 1
		testPrint(string.format("[P2_TEST] overtime terminal=%s started=1 ended=cap-reached", state.terminalId))
		enterCooldown(terminalKey, "overtime-cap")
	end
end

local function processTerminal(terminalKey: string, state: TerminalState, nowTs: number, tickSeconds: number)
	if state.phase == "Cooldown" then
		if state.cooldownEndTime and nowTs >= state.cooldownEndTime then
			state.cooldownEndTime = nil
			state.terminalPart:SetAttribute("CooldownEndTime", nil)
			TerminalRegistry.SetPhase(terminalKey, "Idle")
		end
		return
	end

	if state.phase == "Idle" then
		TerminalRegistry.SetActiveContender(terminalKey, nil)
		return
	end

	local counts = computeTeamCounts(state)
	local contender = resolveActiveContender(counts)
	local leaderCount = if contender == nil then 0 else counts[contender]
	local totalInZone = totalContenders(counts)

	TerminalRegistry.SetActiveContender(terminalKey, contender)

	local previousProgress = state.progress
	if state.ownerFaction == "Neutral" then
		local captured = handleNeutralState(terminalKey, state, contender, leaderCount, tickSeconds)
		if captured then
			return
		end
	else
		handleOwnedState(terminalKey, state, contender, leaderCount, totalInZone, tickSeconds)
	end

	if contender == nil and totalInZone > 0 and state.ownerFaction ~= "Neutral" and math.abs(state.progress - previousProgress) > 0.001 then
		tieFreezeOk = false
		testPrint(string.format("[P2_TEST] tie_freeze terminal=%s from=%.1f to=%.1f", state.terminalId, previousProgress, state.progress))
	end

	if state.phase == "CaptureWindowActive" then
		resolveWindowTimeout(terminalKey, state, contender, nowTs)
	elseif state.phase == "Overtime" then
		resolveOvertimeExit(terminalKey, state, contender, nowTs)
	end
end

function TerminalCaptureService.Start()
	if running then
		return
	end

	running = true
	elapsed = 0
	summaryElapsed = 0
	overtimeStartedCount = 0
	overtimeEndedCount = 0
	cooldownStartedCount = 0
	regenOk = false
	decayOk = false
	tieFreezeOk = true

	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		summaryElapsed += dt

		if elapsed < Config.Terminal.TickSeconds then
			return
		end

		local tickSeconds = elapsed
		elapsed = 0
		local nowTs = os.clock()

		for terminalKey, state in pairs(TerminalRegistry.GetAll()) do
			processTerminal(terminalKey, state, nowTs, tickSeconds)
		end

		if summaryElapsed >= Config.Diagnostics.SummaryIntervalSeconds then
			summaryElapsed = 0
			emitSummaries()
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
