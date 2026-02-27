local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local StartupValidator = {}

export type ValidationResult = {
	ok: boolean,
	errors: { string },
	terminalCount: number,
}

local VALID_TERMINAL_TYPES = {
	Base = true,
	Field = true,
}

local VALID_OWNERS = {
	Neutral = true,
	TGE = true,
	TRA = true,
	THC = true,
}

local function requireStringAttribute(instance: Instance, attributeName: string, errors: { string }): string?
	local value = instance:GetAttribute(attributeName)
	if typeof(value) == "string" and value ~= "" then
		return value
	end

	table.insert(errors, string.format("%s: missing %s string", instance.Name, attributeName))
	return nil
end

local function validateConfig(errors: { string })
	if Config.Terminal.ZoneRadius <= 0 then
		table.insert(errors, "Config.Terminal.ZoneRadius must be > 0")
	end
	if Config.Terminal.TickSeconds <= 0 then
		table.insert(errors, "Config.Terminal.TickSeconds must be > 0")
	end
	if Config.Terminal.CaptureBaseSeconds <= 0 or Config.Terminal.NeutralizeBaseSeconds <= 0 then
		table.insert(errors, "CaptureBaseSeconds and NeutralizeBaseSeconds must be > 0")
	end
	if Config.Terminal.SpeedCapPlayers < 1 then
		table.insert(errors, "Config.Terminal.SpeedCapPlayers must be >= 1")
	end
	if Config.Terminal.SpeedMinMultiplier <= 0 or Config.Terminal.SpeedMinMultiplier > 1 then
		table.insert(errors, "Config.Terminal.SpeedMinMultiplier must be in (0,1]")
	end
	if Config.Terminal.RegenDecayVirtualCount < 1 then
		table.insert(errors, "Config.Terminal.RegenDecayVirtualCount must be >= 1")
	end
	if Config.Terminal.StartPhase ~= "Idle" then
		table.insert(errors, "Config.Terminal.StartPhase must be Idle in Pass 2+")
	end
	if Config.Terminal.OvertimeCapSeconds <= 0 then
		table.insert(errors, "Config.Terminal.OvertimeCapSeconds must be > 0")
	end
	if Config.Terminal.CooldownSeconds <= 0 then
		table.insert(errors, "Config.Terminal.CooldownSeconds must be > 0")
	end
	if Config.Terminal.InteractionDistance <= 0 then
		table.insert(errors, "Config.Terminal.InteractionDistance must be > 0")
	end
	if Config.Terminal.InteractionHoldSeconds <= 0 then
		table.insert(errors, "Config.Terminal.InteractionHoldSeconds must be > 0")
	end
	local bands = Config.Terminal.CaptureWindowSecondsByPopulation
	if typeof(bands) ~= "table" or #bands == 0 then
		table.insert(errors, "Config.Terminal.CaptureWindowSecondsByPopulation must be non-empty")
	else
		for i, band in ipairs(bands) do
			if typeof(band) ~= "table" or typeof(band.maxPlayers) ~= "number" or typeof(band.seconds) ~= "number" then
				table.insert(errors, string.format("CaptureWindowSecondsByPopulation[%d] invalid", i))
			elseif band.seconds <= 0 then
				table.insert(errors, string.format("CaptureWindowSecondsByPopulation[%d].seconds must be > 0", i))
			end
		end
	if Config.Persistence.Enabled then
		if typeof(Config.Persistence.DataStoreName) ~= "string" or Config.Persistence.DataStoreName == "" then
			table.insert(errors, "Config.Persistence.DataStoreName must be non-empty when persistence is enabled")
		end
		if Config.Persistence.SaveCooldownRemaining ~= true and Config.Persistence.SaveCooldownRemaining ~= false then
			table.insert(errors, "Config.Persistence.SaveCooldownRemaining must be boolean")
		end
		if Config.Persistence.SaveProgress ~= true and Config.Persistence.SaveProgress ~= false then
			table.insert(errors, "Config.Persistence.SaveProgress must be boolean")
		end
	end
	end
end

function StartupValidator.ValidateTerminals(): ValidationResult
	local errors = {}
	local tagged = CollectionService:GetTagged("Terminal")

	if #tagged == 0 then
		table.insert(errors, "No terminals tagged 'Terminal' found.")
	end

	validateConfig(errors)

	local seenKeys = {}

	for _, terminal in ipairs(tagged) do
		if not terminal:IsA("BasePart") then
			table.insert(errors, string.format("%s: tagged Terminal must be BasePart", terminal.Name))
			continue
		end

		local terminalId = requireStringAttribute(terminal, "TerminalId", errors)
		local planetId = requireStringAttribute(terminal, "PlanetId", errors)
		local terminalType = requireStringAttribute(terminal, "TerminalType", errors)
		local initialOwner = requireStringAttribute(terminal, "InitialOwner", errors)

		if terminalType and not VALID_TERMINAL_TYPES[terminalType] then
			table.insert(errors, string.format("%s: TerminalType must be Base or Field", terminal.Name))
		end

		if initialOwner and not VALID_OWNERS[initialOwner] then
			table.insert(errors, string.format("%s: InitialOwner invalid", terminal.Name))
		end

		if terminalId and planetId then
			local key = string.format("%s.%s", planetId, terminalId)
			if seenKeys[key] then
				table.insert(errors, string.format("Duplicate terminal key %s", key))
			else
				seenKeys[key] = true
			end
		end
	end

	return {
		ok = #errors == 0,
		errors = errors,
		terminalCount = #tagged,
	}
end

return StartupValidator
