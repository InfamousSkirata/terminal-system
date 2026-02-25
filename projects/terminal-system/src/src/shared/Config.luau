local Config = {
	Terminal = {
		ZoneRadius = 40,
		TickSeconds = 0.5,
		CaptureBaseSeconds = 120,
		NeutralizeBaseSeconds = 156,
		SpeedCapPlayers = 10,
		SpeedMinMultiplier = 0.35,
		StartPhase = "CaptureWindowActive", -- Pass 1 simplification; replaced in Pass 2.
	},
	Teams = {
		Factions = { "TGE", "TRA", "THC" },
		Civilian = "Civilian",
	},
	Diagnostics = {
		Enabled = false,
	},
}

return Config
