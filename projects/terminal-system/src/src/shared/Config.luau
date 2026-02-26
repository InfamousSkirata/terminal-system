local Config = {
	Terminal = {
		ZoneRadius = 40,
		TickSeconds = 0.5,
		CaptureBaseSeconds = 120,
		NeutralizeBaseSeconds = 156,
		SpeedCapPlayers = 10,
		SpeedMinMultiplier = 0.35,

		CaptureWindowSecondsLowPop = 480,
		CaptureWindowSecondsMidPop = 600,
		CaptureWindowSecondsHighPop = 720,
		CaptureWindowSecondsMaxPop = 840,

		OvertimeMaxSeconds = 480,
		CooldownSeconds = 1800,

		RegenDecayVirtualCount = 1,
		PromptHoldSeconds = 0.5,
		PromptMaxDistance = 12,
	},
	Teams = {
		Factions = { "TGE", "TRA", "THC" },
		Civilian = "Civilian",
	},
	Diagnostics = {
		P2TestPrints = true,
		SummaryIntervalSeconds = 5,
	},
}

return Config
