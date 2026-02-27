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

export type TerminalPersistRecord = {
	ownerFaction: OwnerFaction,
	terminalType: TerminalType,
	progress: number?,
	cooldownRemainingSeconds: number?,
	savedAt: number,
}

export type TerminalPersistLoad = {
	ownerFaction: OwnerFaction,
	progress: number?,
	phase: TerminalPhase,
	cooldownRemainingSeconds: number?,
}

export type TerminalEventPayload = {
	key: string,
	terminalId: string,
	planetId: string,
	terminalType: TerminalType,
	ownerFaction: OwnerFaction,
	phase: TerminalPhase,
	progress: number,
	activeContender: Faction?,
}

export type OwnershipChangedPayload = TerminalEventPayload & {
	oldOwner: OwnerFaction,
	newOwner: OwnerFaction,
}

export type ProgressUpdatedPayload = TerminalEventPayload & {
	progress: number,
	activeContender: Faction?,
}

export type WageBonusPayload = {
	faction: Faction,
	ownedTerminals: number,
	bonusPercent: number,
}

return {}
