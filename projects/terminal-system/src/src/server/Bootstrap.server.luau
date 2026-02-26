local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Services = script.Parent:WaitForChild("Services")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local StartupValidator = require(Services:WaitForChild("StartupValidator"))
local TerminalCaptureService = require(Services:WaitForChild("TerminalCaptureService"))
local TerminalInteractionService = require(Services:WaitForChild("TerminalInteractionService"))
local TerminalRegistry = require(Services:WaitForChild("TerminalRegistry"))

local function testPrint(message: string)
	if Config.Diagnostics.P2TestPrints then
		print(message)
	end
end

local validation = StartupValidator.ValidateTerminalsAndConfig()

if not validation.ok then
	for _, err in ipairs(validation.errors) do
		warn(string.format("[TerminalStartup] %s", err))
	end
	testPrint(string.format("[P2_SUMMARY] step=bootstrap valid=0 terminals=%d errors=%d", validation.terminalCount, #validation.errors))
	return
end

TerminalRegistry.Init()
TerminalInteractionService.Start()
TerminalCaptureService.Start()

task.delay(3, function()
	testPrint("========== START READ HERE ==========")
end)

testPrint(string.format("[P2_SUMMARY] step=bootstrap valid=1 terminals=%d errors=0", validation.terminalCount))
