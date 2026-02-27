local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local TerminalAudioService = {}

local pendingCaptureLoop: { [string]: number } = {}

local function fadeIn(sound: Sound, targetVolume: number, duration: number)
	sound.Volume = 0
	local tween = TweenService:Create(sound, TweenInfo.new(duration), { Volume = targetVolume })
	tween:Play()
end

local function ensureSound(parent: Instance, name: string, soundId: string, looped: boolean, volume: number): Sound?
	if soundId == nil or soundId == "" then
		local existing = parent:FindFirstChild(name)
		if existing and existing:IsA("Sound") then
			existing:Stop()
			existing.SoundId = ""
		end
		return nil
	end

	local sound = parent:FindFirstChild(name)
	if sound and sound:IsA("Sound") then
		sound.SoundId = soundId
		sound.Looped = looped
		sound.Volume = volume
		return sound
	end

	local created = Instance.new("Sound")
	created.Name = name
	created.SoundId = soundId
	created.Looped = looped
	created.Volume = volume
	created.Parent = parent
	return created
end

local function configureLoopSound(sound: Sound?)
	if not sound then
		return
	end

	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = Config.Terminal.LoopMinDistance
	sound.RollOffMaxDistance = Config.Terminal.LoopMaxDistance
end

local function updateLoops(state: { terminalPart: BasePart, phase: string, key: string })
	local part = state.terminalPart
	local idleSound = ensureSound(part, "TerminalIdleLoop", Config.Terminal.IdleLoopSoundId, true, Config.Terminal.IdleLoopVolume)
	local captureSound = ensureSound(part, "TerminalCaptureLoop", Config.Terminal.CaptureLoopSoundId, true, Config.Terminal.CaptureLoopVolume)
	configureLoopSound(idleSound)
	configureLoopSound(captureSound)

	if state.phase == "Idle" then
		pendingCaptureLoop[state.key] = nil
		if captureSound then
			captureSound:Stop()
		end
		if idleSound and not idleSound.IsPlaying then
			idleSound:Play()
		end
		return
	end

	if state.phase == "CaptureWindowActive" or state.phase == "Overtime" then
		if idleSound then
			idleSound:Stop()
		end
		if captureSound and not captureSound.IsPlaying then
			if pendingCaptureLoop[state.key] == nil then
				local token = (pendingCaptureLoop[state.key] or 0) + 1
				pendingCaptureLoop[state.key] = token
				task.delay(0.25, function()
					if pendingCaptureLoop[state.key] ~= token then
						return
					end
					if state.phase == "CaptureWindowActive" or state.phase == "Overtime" then
						captureSound:Play()
						fadeIn(captureSound, Config.Terminal.CaptureLoopVolume, 0.6)
					end
				end)
			end
		end
		return
	end

	pendingCaptureLoop[state.key] = nil
	if idleSound then
		idleSound:Stop()
	end
	if captureSound then
		captureSound:Stop()
	end
end

local function playOneShot(state: { terminalPart: BasePart }, name: string, soundId: string)
	local sound = ensureSound(state.terminalPart, name, soundId, false, Config.Terminal.OneShotVolume)
	if sound then
		sound:Play()
	end
end

function TerminalAudioService.Init(states: { [string]: { terminalPart: BasePart, phase: string } })
	for _, state in pairs(states) do
		updateLoops(state)
	end
end

function TerminalAudioService.OnCaptureStart(state: { terminalPart: BasePart, phase: string })
	playOneShot(state, "TerminalCaptureStart", Config.Terminal.CaptureStartSoundId)
	updateLoops(state)
end

function TerminalAudioService.OnOvertime(state: { terminalPart: BasePart, phase: string })
	updateLoops(state)
end

function TerminalAudioService.OnCooldown(state: { terminalPart: BasePart, phase: string }, reason: string)
	if reason == "captured" then
		playOneShot(state, "TerminalCaptured", Config.Terminal.CaptureSuccessSoundId)
	else
		playOneShot(state, "TerminalCaptureFailed", Config.Terminal.CaptureFailedSoundId)
	end
	updateLoops(state)
end

function TerminalAudioService.OnIdle(state: { terminalPart: BasePart, phase: string })
	updateLoops(state)
end

return TerminalAudioService
