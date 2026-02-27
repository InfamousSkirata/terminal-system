local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
if not Config.Diagnostics.Pass4HarnessEnabled then
	return
end

local Services = script.Parent.Parent:WaitForChild("Services")
local TerminalEventsService = require(Services:WaitForChild("TerminalEventsService"))
local TerminalRegistry = require(Services:WaitForChild("TerminalRegistry"))

local function firstTerminal()
	for key, state in pairs(TerminalRegistry.GetAll()) do
		return key, state
	end
	return nil, nil
end

local function setForcedCounts(part: BasePart, tge: number, tra: number, thc: number)
	part:SetAttribute("P1_ForceTGE", tge)
	part:SetAttribute("P1_ForceTRA", tra)
	part:SetAttribute("P1_ForceTHC", thc)
end

local function clearForcedCounts(part: BasePart)
	part:SetAttribute("P1_ForceTGE", nil)
	part:SetAttribute("P1_ForceTRA", nil)
	part:SetAttribute("P1_ForceTHC", nil)
end

local function waitFor(predicate: () -> boolean, timeoutSeconds: number): boolean
	local deadline = os.clock() + timeoutSeconds
	while os.clock() < deadline do
		if predicate() then
			return true
		end
		task.wait(0.1)
	end
	return predicate()
end

task.delay(4, function()
	print("========== START READ HERE ==========")

	local key, state = firstTerminal()
	if not key or not state then
		print("[P4_SUMMARY] pass=0 errors=1 reason=no_terminals")
		return
	end

	local eventsToTrack = {
		OwnershipChanged = 0,
		BecameNeutral = 0,
		CooldownStarted = 0,
		CooldownEnded = 0,
		SpawnOptionsChanged = 0,
		WageBonusChanged = 0,
	}

	for name, _ in pairs(eventsToTrack) do
		TerminalEventsService.GetEvent(name).Event:Connect(function()
			eventsToTrack[name] += 1
		end)
	end

	local originalCapture = Config.Terminal.CaptureBaseSeconds
	local originalNeutralize = Config.Terminal.NeutralizeBaseSeconds
	local originalCooldown = Config.Terminal.CooldownSeconds
	Config.Terminal.CaptureBaseSeconds = 2
	Config.Terminal.NeutralizeBaseSeconds = 2
	Config.Terminal.CooldownSeconds = 2
	Config.Diagnostics.UseForcedTeamCounts = true

	TerminalRegistry.SetPhase(key, "CaptureWindowActive")
	TerminalRegistry.SetOwner(key, "THC")
	TerminalRegistry.SetProgress(key, 2)

	setForcedCounts(state.terminalPart, 5, 0, 0)
	local neutralized = waitFor(function()
		return state.ownerFaction == "Neutral"
	end, 5)

	setForcedCounts(state.terminalPart, 0, 5, 0)
	local captured = waitFor(function()
		return state.ownerFaction == "TRA"
	end, 5)

	local cooldownEnded = waitFor(function()
		return state.phase == "Idle"
	end, 5)

	Config.Terminal.CaptureBaseSeconds = originalCapture
	Config.Terminal.NeutralizeBaseSeconds = originalNeutralize
	Config.Terminal.CooldownSeconds = originalCooldown
	Config.Diagnostics.UseForcedTeamCounts = false
	clearForcedCounts(state.terminalPart)

	local errors = 0
	if not neutralized then errors += 1 end
	if not captured then errors += 1 end
	if not cooldownEnded then errors += 1 end
	for _, count in pairs(eventsToTrack) do
		if count <= 0 then
			errors += 1
		end
	end

	print(string.format("[P4_SUMMARY] pass=%d errors=%d", if errors == 0 then 1 else 0, errors))
end)
