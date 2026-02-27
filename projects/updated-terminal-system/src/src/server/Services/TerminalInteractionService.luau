local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local TerminalCaptureService = require(script.Parent:WaitForChild("TerminalCaptureService"))
local TerminalRegistry = require(script.Parent:WaitForChild("TerminalRegistry"))

local TerminalInteractionService = {}

local promptConnections: { RBXScriptConnection } = {}

local function shouldPromptBeEnabled(terminalPart: BasePart): boolean
	local phase = terminalPart:GetAttribute("TerminalPhase")
	return phase == "Idle"
end

local function findAnyPrompt(terminalPart: BasePart): ProximityPrompt?
	local direct = terminalPart:FindFirstChild("TerminalPrompt")
	if direct and direct:IsA("ProximityPrompt") then
		return direct
	end

	for _, descendant in ipairs(terminalPart:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			return descendant
		end
	end
	return nil
end

local function configurePrompt(prompt: ProximityPrompt, terminalPart: BasePart)
	prompt.Name = "TerminalPrompt"
	prompt.ActionText = "Start Contest"
	prompt.ObjectText = "Terminal"
	prompt.MaxActivationDistance = Config.Terminal.InteractionDistance
	prompt.HoldDuration = Config.Terminal.InteractionHoldSeconds
	prompt.RequiresLineOfSight = false
	prompt.Enabled = shouldPromptBeEnabled(terminalPart)
end

local function ensurePrompt(terminalPart: BasePart): ProximityPrompt
	local prompt = findAnyPrompt(terminalPart)
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = terminalPart
	end

	configurePrompt(prompt, terminalPart)

	for _, descendant in ipairs(terminalPart:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") and descendant ~= prompt then
			descendant.Enabled = false
		end
	end

	return prompt
end

local function bindPromptState(prompt: ProximityPrompt, terminalPart: BasePart)
	prompt.Enabled = shouldPromptBeEnabled(terminalPart)
	local connection = terminalPart:GetAttributeChangedSignal("TerminalPhase"):Connect(function()
		prompt.Enabled = shouldPromptBeEnabled(terminalPart)
	end)
	table.insert(promptConnections, connection)
end

function TerminalInteractionService.Start()
	for key, state in pairs(TerminalRegistry.GetAll()) do
		local prompt = ensurePrompt(state.terminalPart)
		bindPromptState(prompt, state.terminalPart)
		local connection = prompt.Triggered:Connect(function(player)
			local ok = TerminalCaptureService.TryStartCapture(player, key)
			if ok then
				prompt.Enabled = false
			else
				prompt.Enabled = shouldPromptBeEnabled(state.terminalPart)
			end
		end)
		table.insert(promptConnections, connection)
	end
end

function TerminalInteractionService.Stop()
	for _, connection in ipairs(promptConnections) do
		connection:Disconnect()
	end
	table.clear(promptConnections)
end

return TerminalInteractionService
