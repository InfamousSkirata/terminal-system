local Config = {
	Terminal = {
		ZoneRadius = 40,
		TickSeconds = 0.5,
		CaptureBaseSeconds = 120,
		NeutralizeBaseSeconds = 156,
		CaptureWindowSecondsByPopulation = {
			{ maxPlayers = 20, seconds = 8 * 60 },
			{ maxPlayers = 39, seconds = 10 * 60 },
			{ maxPlayers = 49, seconds = 12 * 60 },
			{ maxPlayers = 999, seconds = 14 * 60 },
		},
		OvertimeCapSeconds = 8 * 60,
		CooldownSeconds = 30 * 60,
		InteractionDistance = 12,
		SpeedCapPlayers = 10,
		SpeedMinMultiplier = 0.35,
		RegenDecayVirtualCount = 1,
		StartPhase = "Idle",
	},
	Teams = {
		Factions = { "TGE", "TRA", "THC" },
		Civilian = "Civilian",
	},
	Diagnostics = {
		Pass1TestPrints = true,
		Pass2TestPrints = true,
		SummaryIntervalSeconds = 5,
		Pass1HarnessEnabled = false,
		Pass2HarnessEnabled = false,
		UseForcedTeamCounts = false,
	},
}

return Config
