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
	if Config.Terminal.TickSeconds <= 0 then
		table.insert(errors, "Config.Terminal.TickSeconds must be > 0")
	end
	if Config.Terminal.SpeedCapPlayers < 1 then
		table.insert(errors, "Config.Terminal.SpeedCapPlayers must be >= 1")
	end
	if Config.Terminal.SpeedMinMultiplier <= 0 or Config.Terminal.SpeedMinMultiplier > 1 then
		table.insert(errors, "Config.Terminal.SpeedMinMultiplier must be in (0,1]")
	end

	local positiveDurations = {
		Config.Terminal.CaptureBaseSeconds,
		Config.Terminal.NeutralizeBaseSeconds,
		Config.Terminal.CaptureWindowSecondsLowPop,
		Config.Terminal.CaptureWindowSecondsMidPop,
		Config.Terminal.CaptureWindowSecondsHighPop,
		Config.Terminal.CaptureWindowSecondsMaxPop,
		Config.Terminal.OvertimeMaxSeconds,
		Config.Terminal.CooldownSeconds,
	}

	for _, value in ipairs(positiveDurations) do
		if value <= 0 then
			table.insert(errors, "Capture/cooldown/overtime durations must be > 0")
			break
		end
	end

	if Config.Terminal.RegenDecayVirtualCount < 1 then
		table.insert(errors, "RegenDecayVirtualCount must be >= 1")
	end

	if Config.Terminal.PromptHoldSeconds < 0 then
		table.insert(errors, "PromptHoldSeconds must be >= 0")
	end
	if Config.Terminal.PromptMaxDistance <= 0 then
		table.insert(errors, "PromptMaxDistance must be > 0")
	end
end

function StartupValidator.ValidateTerminalsAndConfig(): ValidationResult
	local errors = {}
	local tagged = CollectionService:GetTagged("Terminal")

	if #tagged == 0 then
		table.insert(errors, "No terminals tagged 'Terminal' found.")
	end

	validateConfig(errors)

	local seenKeys = {}

	for _, terminal in ipairs(tagged) do
		if not terminal:IsA("BasePart") then
			table.insert(errors, string.format("%s: tagged Terminal must be a BasePart", terminal.Name))
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

function StartupValidator.ValidateTerminals(): ValidationResult
	return StartupValidator.ValidateTerminalsAndConfig()
end

return StartupValidator
