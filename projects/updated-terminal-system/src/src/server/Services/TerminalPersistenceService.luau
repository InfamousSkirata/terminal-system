local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local TerminalPersistenceService = {}

export type LoadMap = { [string]: Types.TerminalPersistLoad }

local dataStore: GlobalDataStore? = nil
local mockStore: { [string]: Types.TerminalPersistRecord } = {}

local function getStore(): GlobalDataStore?
	if not Config.Persistence.Enabled then
		return nil
	end

	if Config.Persistence.UseMockInStudio and RunService:IsStudio() then
		return nil
	end

	if dataStore == nil then
		dataStore = DataStoreService:GetDataStore(Config.Persistence.DataStoreName)
	end

	return dataStore
end

local function nowWallTime(): number
	return os.time()
end

local function getTerminalKeys(): { [string]: { terminalType: Types.TerminalType } }
	local keys = {}
	for _, terminal in ipairs(CollectionService:GetTagged("Terminal")) do
		if not terminal:IsA("BasePart") then
			continue
		end
		local terminalId = terminal:GetAttribute("TerminalId")
		local planetId = terminal:GetAttribute("PlanetId")
		local terminalType = terminal:GetAttribute("TerminalType") :: Types.TerminalType
		if typeof(terminalId) ~= "string" or typeof(planetId) ~= "string" then
			continue
		end
		local key = string.format("%s.%s", planetId, terminalId)
		keys[key] = {
			terminalType = terminalType,
		}
	end
	return keys
end

function TerminalPersistenceService.Init()
	dataStore = nil
	end

local function loadRecord(key: string): Types.TerminalPersistRecord?
	if Config.Persistence.UseMockInStudio and RunService:IsStudio() then
		return mockStore[key]
	end

	local store = getStore()
	if not store then
		return nil
	end

	local ok, result = pcall(function()
		return store:GetAsync(key)
	end)
	if not ok then
				return nil
	end

	if result ~= nil then
			end
	return result
end

function TerminalPersistenceService.LoadAll(): LoadMap
	local overrides: LoadMap = {}
	if not Config.Persistence.Enabled then
		return overrides
	end

	local keys = getTerminalKeys()
	local count = 0
	for _ in pairs(keys) do
		count += 1
	end
		for key, info in pairs(keys) do
		local record = loadRecord(key)
		if record == nil then
			continue
		end

		local remaining = nil
		if Config.Persistence.SaveCooldownRemaining and typeof(record.cooldownRemainingSeconds) == "number" then
			local elapsed = nowWallTime() - record.savedAt
			remaining = math.max(0, record.cooldownRemainingSeconds - elapsed)
		end

		local phase: Types.TerminalPhase = "Idle"
		if remaining ~= nil and remaining > 0 then
			phase = "Cooldown"
		end

		overrides[key] = {
			ownerFaction = record.ownerFaction,
			progress = record.progress,
			phase = phase,
			cooldownRemainingSeconds = remaining,
		}
	end

	return overrides
end

local function computeCooldownRemaining(state: Types.TerminalState): number?
	if not Config.Persistence.SaveCooldownRemaining then
		return nil
	end

	if state.phase ~= "Cooldown" then
		return 0
	end

	if state.cooldownEndTime == nil then
		return 0
	end

	local remaining = state.cooldownEndTime - os.clock()
	if remaining <= 0 then
		return 0
	end

	return remaining
end

function TerminalPersistenceService.SaveTerminal(state: Types.TerminalState, reason: string)
	if not Config.Persistence.Enabled then
		return
	end
	
	local record: Types.TerminalPersistRecord = {
		ownerFaction = state.ownerFaction,
		terminalType = state.terminalType,
		progress = if Config.Persistence.SaveProgress then state.progress else nil,
		cooldownRemainingSeconds = computeCooldownRemaining(state),
		savedAt = nowWallTime(),
	}

	if Config.Persistence.UseMockInStudio and RunService:IsStudio() then
		mockStore[state.key] = record
		return
	end

	local store = getStore()
	if not store then
		return
	end

	local ok, err = pcall(function()
		store:SetAsync(state.key, record)
	end)
	if ok then
			else
			end
end

function TerminalPersistenceService.SaveAll(states: { [string]: Types.TerminalState })
	if not Config.Persistence.Enabled then
		return
	end

	for _, state in pairs(states) do
		TerminalPersistenceService.SaveTerminal(state, "shutdown")
	end
end

function TerminalPersistenceService.BindToClose(states: { [string]: Types.TerminalState })
	if not Config.Persistence.Enabled then
		return
	end

	game:BindToClose(function()
		TerminalPersistenceService.SaveAll(states)
		task.wait(1)
	end)
end

function TerminalPersistenceService.__debug_adjust_saved_at(key: string, secondsAgo: number)
	if not (Config.Persistence.UseMockInStudio and RunService:IsStudio()) then
		return
	end
	local record = mockStore[key]
	if not record then
		return
	end
	record.savedAt = os.time() - secondsAgo
end

return TerminalPersistenceService
