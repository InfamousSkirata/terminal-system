local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type OwnerFaction = Types.OwnerFaction
type Faction = Types.Faction
type TerminalPhase = Types.TerminalPhase
type TerminalState = Types.TerminalState

local TerminalRegistry = {}

local stateByKey: { [string]: TerminalState } = {}

local OWNER_COLORS: { [OwnerFaction]: Color3 } = {
	Neutral = Color3.fromRGB(120, 120, 120),
	TGE = Color3.fromRGB(255, 120, 120),
	TRA = Color3.fromRGB(120, 255, 120),
	THC = Color3.fromRGB(120, 160, 255),
}

local function updatePromptEnabled(state: TerminalState)
	local prompt = state.terminalPart:FindFirstChild("TerminalInteractPrompt")
	if not prompt or not prompt:IsA("ProximityPrompt") then
		return
	end

	local enabled = state.phase == "Idle" and (state.cooldownEndTime == nil or os.clock() >= state.cooldownEndTime)
	prompt.Enabled = enabled
end

function TerminalRegistry.BuildKey(planetId: string, terminalId: string): string
	return string.format("%s.%s", planetId, terminalId)
end

function TerminalRegistry.Init()
	table.clear(stateByKey)

	for _, terminal in ipairs(CollectionService:GetTagged("Terminal")) do
		if not terminal:IsA("BasePart") then
			continue
		end

		local terminalId = terminal:GetAttribute("TerminalId") :: string
		local planetId = terminal:GetAttribute("PlanetId") :: string
		local terminalType = terminal:GetAttribute("TerminalType") :: Types.TerminalType
		local initialOwner = terminal:GetAttribute("InitialOwner") :: OwnerFaction

		local progress = if initialOwner == "Neutral" then 0 else 100
		local key = TerminalRegistry.BuildKey(planetId, terminalId)

		stateByKey[key] = {
			terminalId = terminalId,
			planetId = planetId,
			terminalType = terminalType,
			ownerFaction = initialOwner,
			phase = "Idle",
			progress = progress,
			zoneRadius = Config.Terminal.ZoneRadius,
			activeContender = nil,
			neutralProgressFaction = nil,
			terminalPart = terminal,
			captureWindowEndTime = nil,
			captureWindowDurationSeconds = nil,
			overtimeStartedAt = nil,
			cooldownEndTime = nil,
			lastStartUserId = nil,
		}

		terminal:SetAttribute("OwnerFaction", initialOwner)
		terminal:SetAttribute("TerminalPhase", "Idle")
		terminal:SetAttribute("TerminalProgress", progress)
		terminal:SetAttribute("CaptureWindowEndTime", nil)
		terminal:SetAttribute("CooldownEndTime", nil)
		TerminalRegistry.ApplyOwnershipVisual(key)
		updatePromptEnabled(stateByKey[key])
	end
end

function TerminalRegistry.GetAll(): { [string]: TerminalState }
	return stateByKey
end

function TerminalRegistry.GetByKey(terminalKey: string): TerminalState?
	return stateByKey[terminalKey]
end

function TerminalRegistry.SetOwner(terminalKey: string, newOwner: OwnerFaction)
	local state = TerminalRegistry.GetByKey(terminalKey)
	if not state then
		return
	end

	state.ownerFaction = newOwner
	if newOwner ~= "Neutral" then
		state.neutralProgressFaction = nil
		state.terminalPart:SetAttribute("NeutralProgressFaction", nil)
	end

	state.terminalPart:SetAttribute("OwnerFaction", newOwner)
	TerminalRegistry.ApplyOwnershipVisual(terminalKey)
end

function TerminalRegistry.SetProgress(terminalKey: string, progress: number)
	local state = TerminalRegistry.GetByKey(terminalKey)
	if not state then
		return
	end

	local clamped = math.clamp(progress, 0, 100)
	state.progress = clamped
	state.terminalPart:SetAttribute("TerminalProgress", clamped)
end

function TerminalRegistry.SetActiveContender(terminalKey: string, contender: Faction?)
	local state = TerminalRegistry.GetByKey(terminalKey)
	if not state then
		return
	end

	state.activeContender = contender
	state.terminalPart:SetAttribute("ActiveContender", contender)
end

function TerminalRegistry.SetNeutralProgressFaction(terminalKey: string, faction: Faction?)
	local state = TerminalRegistry.GetByKey(terminalKey)
	if not state then
		return
	end

	state.neutralProgressFaction = faction
	state.terminalPart:SetAttribute("NeutralProgressFaction", faction)
end

function TerminalRegistry.SetPhase(terminalKey: string, phase: TerminalPhase)
	local state = TerminalRegistry.GetByKey(terminalKey)
	if not state then
		return
	end

	state.phase = phase
	state.terminalPart:SetAttribute("TerminalPhase", phase)
	updatePromptEnabled(state)
end

function TerminalRegistry.ClearWindowTiming(terminalKey: string)
	local state = TerminalRegistry.GetByKey(terminalKey)
	if not state then
		return
	end

	state.captureWindowEndTime = nil
	state.captureWindowDurationSeconds = nil
	state.overtimeStartedAt = nil
	state.lastStartUserId = nil
	state.terminalPart:SetAttribute("CaptureWindowEndTime", nil)
end

function TerminalRegistry.TryStartCaptureWindow(terminalKey: string, durationSeconds: number, startedByUserId: number): boolean
	local state = TerminalRegistry.GetByKey(terminalKey)
	if not state then
		return false
	end

	local nowTs = os.clock()
	if state.phase ~= "Idle" then
		return false
	end
	if TerminalRegistry.IsCooldownActive(terminalKey, nowTs) then
		return false
	end

	state.phase = "CaptureWindowActive"
	state.captureWindowDurationSeconds = durationSeconds
	state.captureWindowEndTime = nowTs + durationSeconds
	state.overtimeStartedAt = nil
	state.lastStartUserId = startedByUserId
	state.cooldownEndTime = nil

	state.terminalPart:SetAttribute("TerminalPhase", state.phase)
	state.terminalPart:SetAttribute("CaptureWindowEndTime", state.captureWindowEndTime)
	state.terminalPart:SetAttribute("CooldownEndTime", nil)
	updatePromptEnabled(state)
	return true
end

function TerminalRegistry.StartOvertime(terminalKey: string, startedAt: number)
	local state = TerminalRegistry.GetByKey(terminalKey)
	if not state then
		return
	end

	state.phase = "Overtime"
	state.overtimeStartedAt = startedAt
	state.captureWindowEndTime = nil
	state.captureWindowDurationSeconds = nil
	state.terminalPart:SetAttribute("TerminalPhase", state.phase)
	state.terminalPart:SetAttribute("CaptureWindowEndTime", nil)
	updatePromptEnabled(state)
end

function TerminalRegistry.StartCooldown(terminalKey: string, durationSeconds: number)
	local state = TerminalRegistry.GetByKey(terminalKey)
	if not state then
		return
	end

	local nowTs = os.clock()
	state.phase = "Cooldown"
	state.cooldownEndTime = nowTs + durationSeconds
	state.captureWindowEndTime = nil
	state.captureWindowDurationSeconds = nil
	state.overtimeStartedAt = nil
	state.lastStartUserId = nil
	state.activeContender = nil
	state.terminalPart:SetAttribute("TerminalPhase", state.phase)
	state.terminalPart:SetAttribute("CooldownEndTime", state.cooldownEndTime)
	state.terminalPart:SetAttribute("CaptureWindowEndTime", nil)
	state.terminalPart:SetAttribute("ActiveContender", nil)
	updatePromptEnabled(state)
end

function TerminalRegistry.IsCooldownActive(terminalKey: string, nowTs: number): boolean
	local state = TerminalRegistry.GetByKey(terminalKey)
	if not state or not state.cooldownEndTime then
		return false
	end

	return nowTs < state.cooldownEndTime
end

function TerminalRegistry.ApplyOwnershipVisual(terminalKey: string)
	local state = TerminalRegistry.GetByKey(terminalKey)
	if not state then
		return
	end

	local color = OWNER_COLORS[state.ownerFaction] or OWNER_COLORS.Neutral
	state.terminalPart.Color = color
end

return TerminalRegistry
