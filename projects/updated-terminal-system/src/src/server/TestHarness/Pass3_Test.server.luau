local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
if not Config.Diagnostics.Pass3HarnessEnabled then
	return
end

local Services = script.Parent.Parent:WaitForChild("Services")
local TerminalPersistenceService = require(Services:WaitForChild("TerminalPersistenceService"))
local TerminalRegistry = require(Services:WaitForChild("TerminalRegistry"))

local function firstTerminal()
	for key, state in pairs(TerminalRegistry.GetAll()) do
		return key, state
	end
	return nil, nil
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

local function mockAdjustSavedAt(key: string, secondsAgo: number)
	TerminalPersistenceService.__debug_adjust_saved_at(key, secondsAgo)
end

local function logLoad(tag: string, key: string, data)
	print(string.format(
		"[P3_TEST] %s key=%s owner=%s progress=%s phase=%s remaining=%s",
		tag,
		key,
		data.ownerFaction,
		if data.progress == nil then "nil" else string.format("%.2f", data.progress),
		data.phase,
		if data.cooldownRemainingSeconds == nil then "nil" else string.format("%.2f", data.cooldownRemainingSeconds)
	))
end

task.delay(4, function()
	print("========== START READ HERE ==========")

	local key, state = firstTerminal()
	if not key or not state then
		print("[P3_SUMMARY] pass=0 errors=1 reason=no_terminals")
		return
	end

	state.ownerFaction = "TGE"
	state.progress = 42
	state.phase = "Cooldown"
	state.cooldownEndTime = os.clock() + 5

	TerminalPersistenceService.SaveTerminal(state, "test_save")

	local loaded = TerminalPersistenceService.LoadAll()
	local record = loaded[key]
	local errors = 0

	if not record then
		errors += 1
	else
		logLoad("load", key, record)
		if record.ownerFaction ~= "TGE" then
			errors += 1
		end
		if record.phase ~= "Cooldown" then
			errors += 1
		end
		if record.cooldownRemainingSeconds == nil or record.cooldownRemainingSeconds <= 0 then
			errors += 1
		end
	end

	mockAdjustSavedAt(key, 999)
	local loadedExpired = TerminalPersistenceService.LoadAll()
	local recordExpired = loadedExpired[key]
	if recordExpired then
		logLoad("load_expired", key, recordExpired)
		if recordExpired.phase ~= "Idle" then
			errors += 1
		end
	else
		errors += 1
	end

	print(string.format("[P3_SUMMARY] pass=%d errors=%d", if errors == 0 then 1 else 0, errors))
end)
