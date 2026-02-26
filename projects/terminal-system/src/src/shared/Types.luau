export type Faction = "TGE" | "TRA" | "THC"
export type OwnerFaction = "Neutral" | Faction
export type TerminalType = "Base" | "Field"
export type TerminalPhase = "Idle" | "CaptureWindowActive" | "Overtime" | "Cooldown"

export type TerminalState = {
	terminalId: string,
	planetId: string,
	terminalType: TerminalType,
	ownerFaction: OwnerFaction,
	phase: TerminalPhase,
	progress: number,
	zoneRadius: number,
	activeContender: Faction?,
	neutralProgressFaction: Faction?,
	terminalPart: BasePart,

	captureWindowEndTime: number?,
	captureWindowDurationSeconds: number?,
	overtimeStartedAt: number?,
	cooldownEndTime: number?,
	lastStartUserId: number?,
}

return {}
