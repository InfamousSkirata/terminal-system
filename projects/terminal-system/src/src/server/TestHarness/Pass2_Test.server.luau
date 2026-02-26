local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
if not Config.Diagnostics.P2TestPrints then
	return
end

local Services = script.Parent.Parent:WaitForChild("Services")
local TerminalRegistry = require(Services:WaitForChild("TerminalRegistry"))

local function firstTerminal()
	for key, state in pairs(TerminalRegistry.GetAll()) do
		return key, state
	end
	return nil, nil
end

local function forceCaptureWindow(terminalKey: string, state, durationSeconds: number)
	local nowTs = os.clock()
	state.phase = "CaptureWindowActive"
	state.captureWindowDurationSeconds = durationSeconds
	state.captureWindowEndTime = nowTs + durationSeconds
	state.overtimeStartedAt = nil
	state.cooldownEndTime = nil
	state.lastStartUserId = nil
	state.terminalPart:SetAttribute("TerminalPhase", state.phase)
	state.terminalPart:SetAttribute("CaptureWindowEndTime", state.captureWindowEndTime)
	state.terminalPart:SetAttribute("CooldownEndTime", nil)
end

task.delay(6, function()
	local terminalKey, state = firstTerminal()
	if not terminalKey or not state then
		return
	end

	TerminalRegistry.SetOwner(terminalKey, "Neutral")
	TerminalRegistry.SetProgress(terminalKey, 60)
	TerminalRegistry.SetNeutralProgressFaction(terminalKey, nil)
	forceCaptureWindow(terminalKey, state, 6)

	task.delay(18, function()
		TerminalRegistry.SetOwner(terminalKey, "THC")
		TerminalRegistry.SetProgress(terminalKey, 60)
		TerminalRegistry.SetNeutralProgressFaction(terminalKey, nil)
		forceCaptureWindow(terminalKey, state, 30)
	end)

	task.delay(26, function()
		TerminalRegistry.SetOwner(terminalKey, "Neutral")
		TerminalRegistry.SetProgress(terminalKey, 60)
		TerminalRegistry.SetNeutralProgressFaction(terminalKey, nil)
		forceCaptureWindow(terminalKey, state, 30)
	end)
end)
