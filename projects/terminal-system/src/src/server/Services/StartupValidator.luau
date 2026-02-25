local CollectionService = game:GetService("CollectionService")

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

function StartupValidator.ValidateTerminals(): ValidationResult
	local errors = {}
	local tagged = CollectionService:GetTagged("Terminal")

	if #tagged == 0 then
		table.insert(errors, "No terminals tagged 'Terminal' found.")
	end

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

return StartupValidator
