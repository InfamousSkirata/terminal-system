local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local Diagnostics = require(script.Parent:WaitForChild("Diagnostics"))
local TerminalRegistry = require(script.Parent:WaitForChild("TerminalRegistry"))
local TerminalAudioService = require(script.Parent:WaitForChild("TerminalAudioService"))
local TerminalPersistenceService = require(script.Parent:WaitForChild("TerminalPersistenceService"))
local TerminalEventsService = require(script.Parent:WaitForChild("TerminalEventsService"))
local TerminalSpawnService = require(script.Parent:WaitForChild("TerminalSpawnService"))
local TerminalWageService = require(script.Parent:WaitForChild("TerminalWageService"))

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
local lastProgressEmit: { [string]: number } = {}

local function nowSeconds(): number
	return os.clock()
end

local function emitProgress(state: TerminalState)
	local nowTs = nowSeconds()
	local last = lastProgressEmit[state.key] or 0
	if nowTs - last < 1 then
		return
	end
	lastProgressEmit[state.key] = nowTs
	TerminalEventsService.Emit("ProgressUpdated", TerminalRegistry.BuildEventPayload(state))
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
	if Config.Diagnostics.UseForcedTeamCounts == true then
		local forcedTGE = state.terminalPart:GetAttribute("P1_ForceTGE")
		local forcedTRA = state.terminalPart:GetAttribute("P1_ForceTRA")
		local forcedTHC = state.terminalPart:GetAttribute("P1_ForceTHC")

		if typeof(forcedTGE) == "number" and typeof(forcedTRA) == "number" and typeof(forcedTHC) == "number" then
			return {
				TGE = math.max(0, math.floor(forcedTGE + 0.5)),
				TRA = math.max(0, math.floor(forcedTRA + 0.5)),
				THC = math.max(0, math.floor(forcedTHC + 0.5)),
			}
		end
	end

	local counts: TeamCounts = {
		TGE = 0,
		TRA = 0,
		THC = 0,
	}

	for _, player in ipairs(Players:GetPlayers()) do
		if not isEligible(player) then
			continue
		end

		local character = player.Character
		if not character then
			continue
		end

		local root = character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			continue
		end

		local distance = (root.Position - state.terminalPart.Position).Magnitude
		if distance <= state.zoneRadius then
			counts[player.Team.Name :: Faction] += 1
		end
	end

	return counts
end

local function resolveActiveContender(counts: TeamCounts): Faction?
	local rows = {
		{ faction = "TGE" :: Faction, count = counts.TGE },
		{ faction = "TRA" :: Faction, count = counts.TRA },
		{ faction = "THC" :: Faction, count = counts.THC },
	}

	table.sort(rows, function(a, b)
		return a.count > b.count
	end)

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

local function totalInZone(counts: TeamCounts): number
	return counts.TGE + counts.TRA + counts.THC
end

local function computeSpeedMultiplier(activeCount: number): number
	local capped = math.min(activeCount, Config.Terminal.SpeedCapPlayers)
	local normalized = capped / Config.Terminal.SpeedCapPlayers
	return Config.Terminal.SpeedMinMultiplier + ((1 - Config.Terminal.SpeedMinMultiplier) * normalized)
end

local function computeDelta(baseSeconds: number, activeCount: number, tickSeconds: number): number
	local multiplier = computeSpeedMultiplier(activeCount)
	local ratePerSecond = (100 * multiplier) / baseSeconds
	return ratePerSecond * tickSeconds
end

local function getCaptureWindowDurationSeconds(playerCount: number): number
	for _, band in ipairs(Config.Terminal.CaptureWindowSecondsByPopulation) do
		if playerCount <= band.maxPlayers then
			return band.seconds
		end
	end
	return Config.Terminal.CaptureWindowSecondsByPopulation[#Config.Terminal.CaptureWindowSecondsByPopulation].seconds
end

local function setPhaseIdle(key: string)
	TerminalRegistry.SetPhase(key, "Idle")
	TerminalRegistry.SetCaptureWindow(key, nil, nil)
	TerminalRegistry.SetOvertimeStart(key, nil)
	TerminalRegistry.SetCooldownEnd(key, nil)
	TerminalRegistry.SetActiveContender(key, nil)
	local state = TerminalRegistry.GetByKey(key)
	if state then
		TerminalAudioService.OnIdle(state)
	end
end

local function beginCaptureWindow(key: string, state: TerminalState, durationSeconds: number)
	local nowTs = nowSeconds()
	TerminalRegistry.SetPhase(key, "CaptureWindowActive")
	TerminalRegistry.SetCaptureWindow(key, durationSeconds, nowTs + durationSeconds)
	TerminalRegistry.SetOvertimeStart(key, nil)
	TerminalRegistry.SetCooldownEnd(key, nil)
	TerminalRegistry.SetActiveContender(key, nil)
	local updated = TerminalRegistry.GetByKey(key) or state
	local payload = TerminalRegistry.BuildEventPayload(updated)
	payload.durationSeconds = durationSeconds
	TerminalEventsService.Emit("CaptureWindowStarted", payload)
	TerminalAudioService.OnCaptureStart(state)
end

local function beginOvertime(key: string, state: TerminalState)
	local nowTs = nowSeconds()
	TerminalRegistry.SetPhase(key, "Overtime")
	TerminalRegistry.SetOvertimeStart(key, nowTs)
	local updated = TerminalRegistry.GetByKey(key) or state
	TerminalEventsService.Emit("OvertimeStarted", TerminalRegistry.BuildEventPayload(updated))
	TerminalAudioService.OnOvertime(state)
end

local function beginCooldown(key: string, state: TerminalState, reason: string)
	local nowTs = nowSeconds()
	local priorPhase = state.phase
	TerminalRegistry.SetPhase(key, "Cooldown")
	TerminalRegistry.SetCaptureWindow(key, nil, nil)
	TerminalRegistry.SetOvertimeStart(key, nil)
	TerminalRegistry.SetCooldownEnd(key, nowTs + Config.Terminal.CooldownSeconds)
	TerminalRegistry.SetActiveContender(key, nil)
	local updated = TerminalRegistry.GetByKey(key) or state
	local payload = TerminalRegistry.BuildEventPayload(updated)
	payload.reason = reason
	payload.cooldownSeconds = Config.Terminal.CooldownSeconds
	TerminalEventsService.Emit("CooldownStarted", payload)
	if priorPhase == "Overtime" then
		TerminalEventsService.Emit("OvertimeEnded", TerminalRegistry.BuildEventPayload(updated))
	end
	TerminalAudioService.OnCooldown(state, reason)
	TerminalPersistenceService.SaveTerminal(state, "cooldown_start")
end

local function advanceOwned(key: string, state: TerminalState, contender: Faction?, leaderCount: number, totalCount: number, tickSeconds: number)
	local before = state.progress

	if contender == nil then
		if totalCount == 0 then
			local regen = computeDelta(Config.Terminal.NeutralizeBaseSeconds, Config.Terminal.RegenDecayVirtualCount, tickSeconds)
			TerminalRegistry.SetProgress(key, state.progress + regen)
		end
		return
	end

	if contender == state.ownerFaction then
		local regen = computeDelta(Config.Terminal.NeutralizeBaseSeconds, leaderCount, tickSeconds)
		TerminalRegistry.SetProgress(key, state.progress + regen)
		return
	end

	local drain = computeDelta(Config.Terminal.NeutralizeBaseSeconds, leaderCount, tickSeconds)
	TerminalRegistry.SetProgress(key, state.progress - drain)

	if state.progress > 0 then
		return
	end

	local oldOwner = state.ownerFaction
	TerminalRegistry.SetProgress(key, 0)
	TerminalRegistry.SetOwner(key, "Neutral")
	TerminalEventsService.Emit("BecameNeutral", TerminalRegistry.BuildEventPayload(state))
	local updated = TerminalRegistry.GetByKey(key) or state
	local payload = TerminalRegistry.BuildEventPayload(updated)
	payload.oldOwner = oldOwner
	payload.newOwner = "Neutral"
	TerminalEventsService.Emit("OwnershipChanged", payload)
	TerminalSpawnService.OnBecameNeutral(state, oldOwner)
	TerminalWageService.OnBecameNeutral(state, oldOwner, TerminalRegistry.GetAll())
	TerminalPersistenceService.SaveTerminal(state, "owner_neutralized")
	Diagnostics.Increment("neutralizations", 1)
	Diagnostics.Log("transition", {
		key = state.key,
		from = oldOwner,
		to = "Neutral",
		reason = "neutralized",
	})

	if before < 0 then
		Diagnostics.Increment("errors", 1)
	end
end

local function advanceNeutral(key: string, state: TerminalState, contender: Faction?, leaderCount: number, tickSeconds: number): boolean
	if contender == nil then
		local decay = computeDelta(Config.Terminal.CaptureBaseSeconds, Config.Terminal.RegenDecayVirtualCount, tickSeconds)
		TerminalRegistry.SetProgress(key, state.progress - decay)
		return false
	end

	local rise = computeDelta(Config.Terminal.CaptureBaseSeconds, leaderCount, tickSeconds)
	TerminalRegistry.SetProgress(key, state.progress + rise)

	if state.progress < 100 then
		return false
	end

	TerminalRegistry.SetProgress(key, 100)
	TerminalRegistry.SetOwner(key, contender)
	local updated = TerminalRegistry.GetByKey(key) or state
	local payload = TerminalRegistry.BuildEventPayload(updated)
	payload.oldOwner = "Neutral"
	payload.newOwner = contender
	TerminalEventsService.Emit("OwnershipChanged", payload)
	TerminalSpawnService.OnOwnershipChanged(state, "Neutral", contender)
	TerminalWageService.OnOwnershipChanged(state, "Neutral", contender, TerminalRegistry.GetAll())
	TerminalPersistenceService.SaveTerminal(state, "owner_captured")
	Diagnostics.Increment("captures", 1)
	Diagnostics.Log("transition", {
		key = state.key,
		from = "Neutral",
		to = contender,
		reason = "captured",
	})
	return true
end

local function processActiveWindow(key: string, state: TerminalState, tickSeconds: number)
	local counts = computeTeamCounts(state)
	local contender = resolveActiveContender(counts)
	local previousContender = state.activeContender

	if previousContender ~= contender then
		Diagnostics.Increment("contender_changes", 1)
	end

	TerminalRegistry.SetActiveContender(key, contender)

	local before = state.progress
	local leaderCount = if contender == nil then 0 else counts[contender]
	local inZone = totalInZone(counts)
	local capturedThisTick = false

	if state.ownerFaction == "Neutral" then
		capturedThisTick = advanceNeutral(key, state, contender, leaderCount, tickSeconds)
	else
		advanceOwned(key, state, contender, leaderCount, inZone, tickSeconds)
	end

	if contender == nil and inZone > 0 and state.ownerFaction ~= "Neutral" then
		if math.abs(state.progress - before) > 0.001 then
			Diagnostics.SetCounter("tie_freeze_ok", 0)
		end
	end

	if capturedThisTick then
		beginCooldown(key, state, "captured")
		return
	end

	local nowTs = nowSeconds()

	if state.phase == "CaptureWindowActive" then
		local captureWindowEndTime = state.captureWindowEndTime
		if captureWindowEndTime and nowTs >= captureWindowEndTime then
			if contender ~= nil then
				beginOvertime(key, state)
			else
				beginCooldown(key, state, "window_timeout")
			end
		end
		return
	end

	if state.phase == "Overtime" then
		if contender == nil then
			beginCooldown(key, state, "overtime_lost_lead")
			return
		end

		local overtimeStartedAt = state.overtimeStartedAt
		if overtimeStartedAt and (nowTs - overtimeStartedAt) >= Config.Terminal.OvertimeCapSeconds then
			beginCooldown(key, state, "overtime_cap")
		end
	end
end

function TerminalCaptureService.TryStartCapture(player: Player, key: string): (boolean, string)
	local state = TerminalRegistry.GetByKey(key)
	if not state then
		return false, "missing_terminal"
	end

	if not isEligible(player) then
		return false, "ineligible_player"
	end

	if state.phase ~= "Idle" then
		return false, "phase_blocked"
	end

	local durationSeconds = getCaptureWindowDurationSeconds(#Players:GetPlayers())
	beginCaptureWindow(key, state, durationSeconds)
	return true, "ok"
end

function TerminalCaptureService.Start()
	if running then
		return
	end

	running = true
	elapsed = 0
	summaryElapsed = 0
	Diagnostics.ResetPassCounters()

	local all = TerminalRegistry.GetAll()
	local count = 0
	for _, _ in pairs(all) do
		count += 1
	end
	Diagnostics.SetCounter("terminals_loaded", count)

	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		summaryElapsed += dt

		if elapsed < Config.Terminal.TickSeconds then
			return
		end

		local tickSeconds = elapsed
		elapsed = 0

		for key, state in pairs(TerminalRegistry.GetAll()) do
			if state.phase == "Cooldown" then
				local cooldownEndTime = state.cooldownEndTime
				if cooldownEndTime and nowSeconds() >= cooldownEndTime then
					setPhaseIdle(key)
					TerminalPersistenceService.SaveTerminal(state, "cooldown_end")
				end
				continue
			end

			if state.phase == "CaptureWindowActive" or state.phase == "Overtime" then
				processActiveWindow(key, state, tickSeconds)
				continue
			end

			TerminalRegistry.SetActiveContender(key, nil)
		end
		Diagnostics.Increment("ticks_processed", 1)

		if summaryElapsed >= Config.Diagnostics.SummaryIntervalSeconds then
			summaryElapsed = 0
			Diagnostics.EmitPass1Summary("contender")
			Diagnostics.EmitPass1Summary("progress")
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
