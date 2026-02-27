local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local TerminalEventsService = require(script.Parent:WaitForChild("TerminalEventsService"))

local TerminalWageService = {}

local bonusByFaction: { [string]: number } = {}
local ownedByFaction: { [string]: number } = {}

local function reset()
	bonusByFaction = {}
	ownedByFaction = {}
	for _, faction in ipairs(Config.Teams.Factions) do
		bonusByFaction[faction] = 0
		ownedByFaction[faction] = 0
	end
end

local function computeBonus(count: number): number
	return math.min(count * Config.Terminal.WageBonusPerTerminal, Config.Terminal.WageBonusCap)
end

local function emitAll()
	for _, faction in ipairs(Config.Teams.Factions) do
		TerminalEventsService.Emit("WageBonusChanged", {
			faction = faction,
			ownedTerminals = ownedByFaction[faction] or 0,
			bonusPercent = bonusByFaction[faction] or 0,
		})
	end
end

function TerminalWageService.Init(states: { [string]: Types.TerminalState })
	reset()
	for _, state in pairs(states) do
		if state.ownerFaction ~= "Neutral" then
			ownedByFaction[state.ownerFaction] += 1
		end
	end
	for _, faction in ipairs(Config.Teams.Factions) do
		bonusByFaction[faction] = computeBonus(ownedByFaction[faction])
	end
	emitAll()
end

function TerminalWageService.Recompute(states: { [string]: Types.TerminalState })
	reset()
	for _, state in pairs(states) do
		if state.ownerFaction ~= "Neutral" then
			ownedByFaction[state.ownerFaction] += 1
		end
	end
	for _, faction in ipairs(Config.Teams.Factions) do
		bonusByFaction[faction] = computeBonus(ownedByFaction[faction])
	end
	emitAll()
end

function TerminalWageService.OnOwnershipChanged(state: Types.TerminalState, oldOwner: Types.OwnerFaction, newOwner: Types.OwnerFaction, allStates: { [string]: Types.TerminalState })
	TerminalWageService.Recompute(allStates)
end

function TerminalWageService.OnBecameNeutral(state: Types.TerminalState, oldOwner: Types.OwnerFaction, allStates: { [string]: Types.TerminalState })
	TerminalWageService.Recompute(allStates)
end

function TerminalWageService.GetBonus(faction: Types.Faction): number
	return bonusByFaction[faction] or 0
end

return TerminalWageService
