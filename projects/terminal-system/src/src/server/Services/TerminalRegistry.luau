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

local function terminalKey(planetId: string, terminalId: string): string
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
		local key = terminalKey(planetId, terminalId)

		stateByKey[key] = {
			terminalId = terminalId,
			planetId = planetId,
			terminalType = terminalType,
			ownerFaction = initialOwner,
			phase = Config.Terminal.StartPhase,
			progress = progress,
			zoneRadius = Config.Terminal.ZoneRadius,
			activeContender = nil,
			neutralProgressFaction = nil,
			terminalPart = terminal,
		}

		terminal:SetAttribute("OwnerFaction", initialOwner)
		terminal:SetAttribute("TerminalPhase", Config.Terminal.StartPhase)
		terminal:SetAttribute("TerminalProgress", progress)
		TerminalRegistry.ApplyOwnershipVisual(key)
	end
end

function TerminalRegistry.GetAll(): { [string]: TerminalState }
	return stateByKey
end

function TerminalRegistry.GetById(terminalId: string): TerminalState?
	if stateByKey[terminalId] then
		return stateByKey[terminalId]
	end

	for _, state in pairs(stateByKey) do
		if state.terminalId == terminalId then
			return state
		end
	end

	return nil
end

function TerminalRegistry.SetOwner(terminalId: string, newOwner: OwnerFaction)
	local state = TerminalRegistry.GetById(terminalId)
	if not state then
		return
	end

	state.ownerFaction = newOwner
	if newOwner ~= "Neutral" then
		state.neutralProgressFaction = nil
	end

	state.terminalPart:SetAttribute("OwnerFaction", newOwner)
	TerminalRegistry.ApplyOwnershipVisual(terminalId)
end

function TerminalRegistry.SetProgress(terminalId: string, progress: number)
	local state = TerminalRegistry.GetById(terminalId)
	if not state then
		return
	end

	local clamped = math.clamp(progress, 0, 100)
	state.progress = clamped
	state.terminalPart:SetAttribute("TerminalProgress", clamped)
end

function TerminalRegistry.SetActiveContender(terminalId: string, contender: Faction?)
	local state = TerminalRegistry.GetById(terminalId)
	if not state then
		return
	end

	state.activeContender = contender
	state.terminalPart:SetAttribute("ActiveContender", contender)
end

function TerminalRegistry.SetNeutralProgressFaction(terminalId: string, faction: Faction?)
	local state = TerminalRegistry.GetById(terminalId)
	if not state then
		return
	end

	state.neutralProgressFaction = faction
	state.terminalPart:SetAttribute("NeutralProgressFaction", faction)
end

function TerminalRegistry.ApplyOwnershipVisual(terminalId: string)
	local state = TerminalRegistry.GetById(terminalId)
	if not state then
		return
	end

	local color = OWNER_COLORS[state.ownerFaction] or OWNER_COLORS.Neutral
	state.terminalPart.Color = color
end

return TerminalRegistry
