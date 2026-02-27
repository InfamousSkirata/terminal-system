local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Types"))

local TerminalEventsService = require(script.Parent:WaitForChild("TerminalEventsService"))

local TerminalSpawnService = {}

local spawnByFactionPlanet: { [string]: { [string]: { BasePart } } } = {}

local function getBucket(faction: Types.Faction, planetId: string): { BasePart }
	spawnByFactionPlanet[faction] = spawnByFactionPlanet[faction] or {}
	spawnByFactionPlanet[faction][planetId] = spawnByFactionPlanet[faction][planetId] or {}
	return spawnByFactionPlanet[faction][planetId]
end

local function rebuild(states: { [string]: Types.TerminalState })
	spawnByFactionPlanet = {}
	for _, state in pairs(states) do
		if state.terminalType ~= "Field" then
			continue
		end
		if state.ownerFaction == "Neutral" then
			continue
		end
		local bucket = getBucket(state.ownerFaction :: Types.Faction, state.planetId)
		table.insert(bucket, state.terminalPart)
	end
end

local function emitAll()
	for faction, byPlanet in pairs(spawnByFactionPlanet) do
		for planetId, terminals in pairs(byPlanet) do
			TerminalEventsService.Emit("SpawnOptionsChanged", {
				faction = faction,
				planetId = planetId,
				terminals = terminals,
			})
		end
	end
end

function TerminalSpawnService.Init(states: { [string]: Types.TerminalState })
	rebuild(states)
	emitAll()
end

function TerminalSpawnService.OnOwnershipChanged(state: Types.TerminalState, oldOwner: Types.OwnerFaction, newOwner: Types.OwnerFaction)
	if state.terminalType ~= "Field" then
		return
	end

	if oldOwner ~= "Neutral" then
		local bucket = getBucket(oldOwner :: Types.Faction, state.planetId)
		for i = #bucket, 1, -1 do
			if bucket[i] == state.terminalPart then
				table.remove(bucket, i)
				break
			end
		end
		TerminalEventsService.Emit("SpawnOptionsChanged", {
			faction = oldOwner,
			planetId = state.planetId,
			terminals = bucket,
		})
	end

	if newOwner ~= "Neutral" then
		local bucket = getBucket(newOwner :: Types.Faction, state.planetId)
		local exists = false
		for _, part in ipairs(bucket) do
			if part == state.terminalPart then
				exists = true
				break
			end
		end
		if not exists then
			table.insert(bucket, state.terminalPart)
		end
		TerminalEventsService.Emit("SpawnOptionsChanged", {
			faction = newOwner,
			planetId = state.planetId,
			terminals = bucket,
		})
	end
end

function TerminalSpawnService.OnBecameNeutral(state: Types.TerminalState, oldOwner: Types.OwnerFaction)
	if state.terminalType ~= "Field" then
		return
	end
	if oldOwner == "Neutral" then
		return
	end

	local bucket = getBucket(oldOwner :: Types.Faction, state.planetId)
	for i = #bucket, 1, -1 do
		if bucket[i] == state.terminalPart then
			table.remove(bucket, i)
			break
		end
	end
	TerminalEventsService.Emit("SpawnOptionsChanged", {
		faction = oldOwner,
		planetId = state.planetId,
		terminals = bucket,
	})
end

function TerminalSpawnService.GetSpawnTerminals(faction: Types.Faction, planetId: string): { BasePart }
	local byPlanet = spawnByFactionPlanet[faction]
	if not byPlanet then
		return {}
	end
	return byPlanet[planetId] or {}
end

return TerminalSpawnService
