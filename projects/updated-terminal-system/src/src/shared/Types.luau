export type Faction = "TGE" | "TRA" | "THC"
export type OwnerFaction = "Neutral" | Faction
export type TerminalType = "Base" | "Field"
export type TerminalPhase = "Idle" | "CaptureWindowActive" | "Overtime" | "Cooldown"

export type TerminalState = {
	key: string,
	terminalId: string,
	planetId: string,
	terminalType: TerminalType,
	ownerFaction: OwnerFaction,
	phase: TerminalPhase,
	progress: number,
	zoneRadius: number,
	activeContender: Faction?,
	captureWindowDurationSeconds: number?,
	captureWindowEndTime: number?,
	overtimeStartedAt: number?,
	cooldownEndTime: number?,
	terminalPart: BasePart,
}

return {}
