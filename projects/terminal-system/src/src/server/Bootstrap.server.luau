local Services = script.Parent:WaitForChild("Services")

local StartupValidator = require(Services:WaitForChild("StartupValidator"))
local TerminalCaptureService = require(Services:WaitForChild("TerminalCaptureService"))
local TerminalRegistry = require(Services:WaitForChild("TerminalRegistry"))

local validation = StartupValidator.ValidateTerminals()

if not validation.ok then
	for _, err in ipairs(validation.errors) do
		warn(string.format("[TerminalStartup] %s", err))
	end
	return
end

TerminalRegistry.Init()
TerminalCaptureService.Start()
