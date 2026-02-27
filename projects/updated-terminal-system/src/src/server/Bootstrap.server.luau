local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Services = script.Parent:WaitForChild("Services")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local StartupValidator = require(Services:WaitForChild("StartupValidator"))
local TerminalRegistry = require(Services:WaitForChild("TerminalRegistry"))
local TerminalAudioService = require(Services:WaitForChild("TerminalAudioService"))
local TerminalCaptureService = require(Services:WaitForChild("TerminalCaptureService"))
local TerminalInteractionService = require(Services:WaitForChild("TerminalInteractionService"))

local validation = StartupValidator.ValidateTerminals()

if not validation.ok then
	for _, err in ipairs(validation.errors) do
		warn(string.format("[TerminalStartup] %s", err))
	end
	return
end

TerminalRegistry.Init()
TerminalAudioService.Init(TerminalRegistry.GetAll())
TerminalCaptureService.Start()
TerminalInteractionService.Start()
