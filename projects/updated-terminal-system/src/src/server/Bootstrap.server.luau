local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Services = script.Parent:WaitForChild("Services")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local StartupValidator = require(Services:WaitForChild("StartupValidator"))
local TerminalRegistry = require(Services:WaitForChild("TerminalRegistry"))
local TerminalEventsService = require(Services:WaitForChild("TerminalEventsService"))
local TerminalSpawnService = require(Services:WaitForChild("TerminalSpawnService"))
local TerminalWageService = require(Services:WaitForChild("TerminalWageService"))
local TerminalPersistenceService = require(Services:WaitForChild("TerminalPersistenceService"))
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

TerminalEventsService.Init()
TerminalPersistenceService.Init()
local overrides = TerminalPersistenceService.LoadAll()
TerminalRegistry.Init(overrides)
TerminalSpawnService.Init(TerminalRegistry.GetAll())
TerminalWageService.Init(TerminalRegistry.GetAll())
TerminalAudioService.Init(TerminalRegistry.GetAll())
TerminalCaptureService.Start()
TerminalInteractionService.Start()
TerminalPersistenceService.BindToClose(TerminalRegistry.GetAll())
