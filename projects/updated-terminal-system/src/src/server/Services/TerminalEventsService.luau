local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local TerminalEventsService = {}

local folder: Folder? = nil
local events: { [string]: BindableEvent } = {}

local EVENT_NAMES = {
	"CaptureWindowStarted",
	"OwnershipChanged",
	"BecameNeutral",
	"CooldownStarted",
	"CooldownEnded",
	"OvertimeStarted",
	"OvertimeEnded",
	"ProgressUpdated",
	"SpawnOptionsChanged",
	"WageBonusChanged",
}

local function ensureFolder(): Folder
	if folder and folder.Parent then
		return folder
	end

	local existing = ReplicatedStorage:FindFirstChild("TerminalEvents")
	if existing and existing:IsA("Folder") then
		folder = existing
		return folder
	end

	local created = Instance.new("Folder")
	created.Name = "TerminalEvents"
	created.Parent = ReplicatedStorage
	folder = created
	return created
end

function TerminalEventsService.Init()
	local root = ensureFolder()
	for _, name in ipairs(EVENT_NAMES) do
		local existing = root:FindFirstChild(name)
		if existing and existing:IsA("BindableEvent") then
			events[name] = existing
		else
			local ev = Instance.new("BindableEvent")
			ev.Name = name
			ev.Parent = root
			events[name] = ev
		end
	end
end

function TerminalEventsService.GetEvent(eventName: string): BindableEvent
	return events[eventName]
end

function TerminalEventsService.Emit(eventName: string, payload: any)
	local ev = events[eventName]
	if not ev then
		return
	end
	ev:Fire(payload)
end

return TerminalEventsService
