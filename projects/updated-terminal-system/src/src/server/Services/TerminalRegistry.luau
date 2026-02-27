local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type OwnerFaction = Types.OwnerFaction
type Faction = Types.Faction
type TerminalState = Types.TerminalState

local TerminalRegistry = {}

local stateByKey: { [string]: TerminalState } = {}

local OWNER_COLORS: { [OwnerFaction]: Color3 } = {
	Neutral = Color3.fromRGB(120, 120, 120),
	TGE = Color3.fromRGB(255, 120, 120),
	TRA = Color3.fromRGB(120, 255, 120),
	THC = Color3.fromRGB(120, 160, 255),
}

function TerminalRegistry.BuildKey(planetId: string, terminalId: string): string
	return string.format("%s.%s", planetId, terminalId)
end

function TerminalRegistry.Init(overrides: { [string]: Types.TerminalPersistLoad }?)
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
		local override = if overrides then overrides[key] else nil

		if override then
			if override.ownerFaction then
				initialOwner = override.ownerFaction
			end
			if typeof(override.progress) == "number" then
				progress = math.clamp(override.progress, 0, 100)
			elseif initialOwner == "Neutral" then
				progress = 0
			else
				progress = 100
			end
		end

		local phase = Config.Terminal.StartPhase
		local cooldownEndTime: number? = nil
		if override then
			phase = override.phase
			if phase == "Cooldown" and typeof(override.cooldownRemainingSeconds) == "number" then
				cooldownEndTime = os.clock() + math.max(0, override.cooldownRemainingSeconds)
			end
		end

		stateByKey[key] = {
			key = key,
			terminalId = terminalId,
			planetId = planetId,
			terminalType = terminalType,
			ownerFaction = initialOwner,
			phase = phase,
			progress = progress,
			zoneRadius = Config.Terminal.ZoneRadius,
			activeContender = nil,
			captureWindowDurationSeconds = nil,
			captureWindowEndTime = nil,
			overtimeStartedAt = nil,
			cooldownEndTime = cooldownEndTime,
			terminalPart = terminal,
		}

		terminal:SetAttribute("OwnerFaction", initialOwner)
		terminal:SetAttribute("TerminalPhase", phase)
		terminal:SetAttribute("TerminalProgress", progress)
		terminal:SetAttribute("ActiveContender", nil)
		terminal:SetAttribute("CaptureWindowDurationSeconds", nil)
		terminal:SetAttribute("CaptureWindowEndTime", nil)
		terminal:SetAttribute("OvertimeStartedAt", nil)
		terminal:SetAttribute("CooldownEndTime", cooldownEndTime)
		TerminalRegistry.ApplyOwnershipVisual(key)
	end
end

function TerminalRegistry.GetAll(): { [string]: TerminalState }
	return stateByKey
end

function TerminalRegistry.GetByKey(key: string): TerminalState?
	return stateByKey[key]
end


function TerminalRegistry.BuildEventPayload(state: Types.TerminalState): Types.TerminalEventPayload
	return {
		key = state.key,
		terminalId = state.terminalId,
		planetId = state.planetId,
		terminalType = state.terminalType,
		ownerFaction = state.ownerFaction,
		phase = state.phase,
		progress = state.progress,
		activeContender = state.activeContender,
	}
end

function TerminalRegistry.SetOwner(key: string, newOwner: OwnerFaction)
	local state = stateByKey[key]
	if not state then
		return
	end

	state.ownerFaction = newOwner
	state.terminalPart:SetAttribute("OwnerFaction", newOwner)
	TerminalRegistry.ApplyOwnershipVisual(key)
end

function TerminalRegistry.SetProgress(key: string, value: number)
	local state = stateByKey[key]
	if not state then
		return
	end

	local clamped = math.clamp(value, 0, 100)
	state.progress = clamped
	state.terminalPart:SetAttribute("TerminalProgress", clamped)
end

function TerminalRegistry.SetActiveContender(key: string, contender: Faction?)
	local state = stateByKey[key]
	if not state then
		return
	end

	state.activeContender = contender
	state.terminalPart:SetAttribute("ActiveContender", contender)
end

function TerminalRegistry.SetPhase(key: string, phase: Types.TerminalPhase)
	local state = stateByKey[key]
	if not state then
		return
	end

	state.phase = phase
	state.terminalPart:SetAttribute("TerminalPhase", phase)
end

function TerminalRegistry.SetCaptureWindow(key: string, durationSeconds: number?, endTime: number?)
	local state = stateByKey[key]
	if not state then
		return
	end

	state.captureWindowDurationSeconds = durationSeconds
	state.captureWindowEndTime = endTime
	state.terminalPart:SetAttribute("CaptureWindowDurationSeconds", durationSeconds)
	state.terminalPart:SetAttribute("CaptureWindowEndTime", endTime)
end

function TerminalRegistry.SetOvertimeStart(key: string, overtimeStartedAt: number?)
	local state = stateByKey[key]
	if not state then
		return
	end

	state.overtimeStartedAt = overtimeStartedAt
	state.terminalPart:SetAttribute("OvertimeStartedAt", overtimeStartedAt)
end

function TerminalRegistry.SetCooldownEnd(key: string, cooldownEndTime: number?)
	local state = stateByKey[key]
	if not state then
		return
	end

	state.cooldownEndTime = cooldownEndTime
	state.terminalPart:SetAttribute("CooldownEndTime", cooldownEndTime)
end

function TerminalRegistry.ApplyOwnershipVisual(key: string)
	local state = stateByKey[key]
	if not state then
		return
	end

	local color = OWNER_COLORS[state.ownerFaction] or OWNER_COLORS.Neutral
	state.terminalPart.Color = color
end

return TerminalRegistry
