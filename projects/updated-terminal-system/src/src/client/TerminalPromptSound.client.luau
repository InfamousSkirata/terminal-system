local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local function getSound(parent: Instance): Sound?
	local soundId = Config.Terminal.InteractionHoldSoundId
	if soundId == nil or soundId == "" then
		return nil
	end

	local existing = parent:FindFirstChild("TerminalPromptHoldSound")
	if existing and existing:IsA("Sound") then
		return existing
	end

	local sound = Instance.new("Sound")
	sound.Name = "TerminalPromptHoldSound"
	sound.SoundId = soundId
	sound.Volume = Config.Terminal.InteractionHoldSoundVolume
	sound.Looped = true
	sound.Parent = parent
	return sound
end

local function bindPrompt(prompt: ProximityPrompt)
	if prompt.Name ~= "TerminalPrompt" then
		return
	end

	local parent = prompt.Parent
	if not parent then
		return
	end

	local sound = getSound(parent)
	if not sound then
		return
	end

	prompt.PromptButtonHoldBegan:Connect(function()
		sound:Play()
	end)

	prompt.PromptButtonHoldEnded:Connect(function()
		sound:Stop()
	end)

	prompt.Triggered:Connect(function()
		sound:Stop()
	end)
end

ProximityPromptService.PromptShown:Connect(function(prompt)
	bindPrompt(prompt)
end)
