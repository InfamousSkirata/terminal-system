# Pass 1 Design: Bare Bones Contest Loop — Terminal System

**Feature pass:** 1 of 6
**Based on:** feature-passes.md, idea-locked.md
**Existing code:** none (greenfield pass)
**Critic Status:** APPROVED
**Date:** 2026-02-25

---

## What This Pass Adds
This pass delivers the minimum end-to-end terminal contest loop on server authority:
- Terminal runtime state per terminal (id/type/owner/phase/progress/zone radius).
- In-zone faction counting (alive-only) and strict-lead active contender resolution.
- Two-stage shared bar logic:
  - Owned terminal: enemy contender neutralizes 100 -> 0.
  - Neutral terminal: contender captures 0 -> 100.
- Ownership transitions and world visual ownership state updates.

This pass intentionally does not implement capture-window start interaction, cooldown, overtime, persistence, spawn integration, wage integration, or player-facing UI screens. Those are later passes.

---

## File Changes

### New Files
| File | Location | Purpose |
|------|----------|---------|
| `Config.luau` | `src/src/shared` | Tunables for Pass 1 loop (zone radius, tick, speed constants, debug flags). |
| `Types.luau` | `src/src/shared` | Shared type aliases/enums for terminal owner/type/phase and runtime state. |
| `Diagnostics.luau` | `src/src/server/Services` | Structured logging and lightweight counters for pass verification. |
| `StartupValidator.luau` | `src/src/server/Services` | Verifies required terminal workspace contracts before startup. |
| `TerminalRegistry.luau` | `src/src/server/Services` | Discovers tagged terminal instances and owns server-side terminal state table. |
| `TerminalCaptureService.luau` | `src/src/server/Services` | Tick loop for contender resolution, progress updates, transitions. |
| `Bootstrap.server.luau` | `src/src/server` | Startup composition: validate -> registry init -> capture service start. |

### Modified Files
| File | What's Changing | Why |
|------|----------------|-----|
| none | n/a | First implementation pass. |

---

## Workspace Contracts (Pass 1)
Each terminal is a `BasePart` tagged with `Terminal` and must have attributes:
- `TerminalId: string` (unique on planet)
- `PlanetId: string`
- `TerminalType: string` (`Base` or `Field`)
- `InitialOwner: string` (`TGE` / `TRA` / `THC` / `Neutral`)

Pass 1 runtime assumptions:
- All discovered terminals start in `CaptureWindowActive` phase at boot for testability.
- This temporary simplification is removed in Pass 2 when interaction-driven windows are added.

---

## New/Modified APIs

```lua
-- src/src/server/Services/StartupValidator.luau
export type ValidationResult = {
    ok: boolean,
    errors: {string},
    terminalCount: number,
}

function StartupValidator.ValidateTerminals(): ValidationResult
-- Scans tagged terminals and validates required attributes and values.
```

```lua
-- src/src/server/Services/TerminalRegistry.luau
local TerminalRegistry = {}

export type TerminalState = {
    terminalId: string,
    planetId: string,
    terminalType: "Base" | "Field",
    ownerFaction: "Neutral" | "TGE" | "TRA" | "THC",
    phase: "Idle" | "CaptureWindowActive",
    progress: number,
    zoneRadius: number,
    activeContender: "TGE" | "TRA" | "THC"?,
    terminalPart: BasePart,
}

function TerminalRegistry.Init(): nil
function TerminalRegistry.GetAll(): {[string]: TerminalState}
function TerminalRegistry.GetById(terminalId: string): TerminalState?
function TerminalRegistry.SetOwner(terminalId: string, newOwner: "Neutral" | "TGE" | "TRA" | "THC"): nil
function TerminalRegistry.SetProgress(terminalId: string, progress: number): nil
function TerminalRegistry.SetActiveContender(terminalId: string, contender: "TGE" | "TRA" | "THC"?): nil
function TerminalRegistry.ApplyOwnershipVisual(terminalId: string): nil
```

```lua
-- src/src/server/Services/TerminalCaptureService.luau
local TerminalCaptureService = {}

export type TeamCounts = {
    TGE: number,
    TRA: number,
    THC: number,
}

function TerminalCaptureService.Start(): nil
function TerminalCaptureService.Stop(): nil

-- Internal API (typed locals)
-- computeTeamCounts(state: TerminalState): TeamCounts
-- resolveActiveContender(counts: TeamCounts): "TGE" | "TRA" | "THC"?
-- computeSpeedMultiplier(activeCount: number): number
-- computeDeltaPerTick(baseTimeSeconds: number, multiplier: number, tickSeconds: number): number
-- advanceOwnedState(state: TerminalState, contender: "TGE" | "TRA" | "THC"): nil
-- advanceNeutralState(state: TerminalState, contender: "TGE" | "TRA" | "THC"?): nil
```

```lua
-- src/src/server/Services/Diagnostics.luau
local Diagnostics = {}

function Diagnostics.Log(tag: string, fields: {[string]: any}?): nil
function Diagnostics.Increment(counterName: string, amount: number?): nil
function Diagnostics.GetCounter(counterName: string): number
function Diagnostics.ResetPassCounters(): nil
function Diagnostics.EmitPass1Summary(): nil
```

---

## New Data Structures

```lua
-- src/src/shared/Types.luau
export type Faction = "TGE" | "TRA" | "THC"
export type OwnerFaction = "Neutral" | Faction
export type TerminalType = "Base" | "Field"
export type TerminalPhase = "Idle" | "CaptureWindowActive"

export type TerminalState = {
    terminalId: string,
    planetId: string,
    terminalType: TerminalType,
    ownerFaction: OwnerFaction,
    phase: TerminalPhase,
    progress: number,
    zoneRadius: number,
    activeContender: Faction?,
    terminalPart: BasePart,
}
```

```lua
-- src/src/shared/Config.luau
return {
    Terminal = {
        ZoneRadius = 40,
        TickSeconds = 0.5,
        CaptureBaseSeconds = 120,
        NeutralizeBaseSeconds = 156,
        SpeedCapPlayers = 10,
        SpeedMinMultiplier = 0.35,
        StartPhase = "CaptureWindowActive", -- pass1 bootstrap simplification
    },
    Teams = {
        Factions = {"TGE", "TRA", "THC"},
        Civilian = "Civilian",
    },
    Diagnostics = {
        Pass1TestPrints = true,
    },
}
```

---

## Data Flow for New Behaviors

### Startup and State Bootstrap
1. `Bootstrap.server.luau` calls `StartupValidator.ValidateTerminals()`.
2. On success, `TerminalRegistry.Init()` discovers tagged terminals and creates `TerminalState` entries.
3. Registry initializes `progress`:
- Owned terminals start at `100`.
- Neutral terminals start at `0`.
4. Registry applies owner visuals immediately via `ApplyOwnershipVisual`.
5. `TerminalCaptureService.Start()` begins heartbeat loop.

### Active Contender Resolution
1. Capture service computes in-zone alive faction counts per terminal each tick.
2. Service resolves contender only if leader has strict +1 over second place.
3. Registry stores `activeContender` each tick for diagnostics.

### Progress and Ownership Transition
1. If owner is non-neutral and contender is enemy, decrement progress using neutralize speed.
2. If owner is non-neutral and contender is owner, increment toward 100 (defensive stabilization behavior already compatible with pass1 scope).
3. If terminal is neutral and contender exists, increment toward 100 using capture speed.
4. If owned progress reaches 0, transition owner to `Neutral` and clamp progress to `0`.
5. If neutral progress reaches 100, transition owner to contender and clamp progress to `100`.
6. Ownership transition triggers world visual refresh and diagnostics event.

---

## Integration Pass (against real code)

### Data Lifecycle Traces

**TerminalState**
- **Created by:** `TerminalRegistry.Init()` -> `TerminalState`
- **Passed via:** Registry table reference returned by `TerminalRegistry.GetAll()`
- **Received by:** `TerminalCaptureService.Start()` tick loop
- **Stored in:** `TerminalRegistry._stateById[terminalId]` for server lifetime
- **Cleaned up by:** not needed in pass1 (server-lifetime state)
- **Verified:** single owner module (`TerminalRegistry`) controls writes via setters

**ActiveContender**
- **Created by:** `resolveActiveContender(counts)` -> `Faction?`
- **Passed via:** `TerminalRegistry.SetActiveContender(terminalId, contender)`
- **Received by:** `TerminalRegistry` and diagnostics summary
- **Stored in:** `TerminalState.activeContender` (tick-overwritten)
- **Cleaned up by:** set to `nil` when no strict lead
- **Verified:** type restricted to faction union or nil

### API Composition Checks (new calls only)

| Caller | Callee | Args Match | Return Handled | Verified Against |
|--------|--------|-----------|----------------|-----------------|
| `Bootstrap.server` | `StartupValidator.ValidateTerminals()` | Yes | Yes (`ok` gate) | New API in this pass |
| `Bootstrap.server` | `TerminalRegistry.Init()` | Yes | n/a | New API in this pass |
| `Bootstrap.server` | `TerminalCaptureService.Start()` | Yes | n/a | New API in this pass |
| `TerminalCaptureService` | `TerminalRegistry.GetAll()` | Yes | Yes | New API in this pass |
| `TerminalCaptureService` | `TerminalRegistry.SetProgress/SetOwner/SetActiveContender()` | Yes | n/a | New API in this pass |

No cross-pass signature mismatch risk exists because there are no prior implemented passes.

---

## Diagnostics Updates

### New Reason Codes
- `P1_STARTUP_OK` — startup validation passed and services began.
- `P1_STARTUP_FAIL` — startup validator detected contract errors; startup aborted.
- `P1_CONTENDER_CHANGED` — active contender changed for a terminal.
- `P1_NEUTRALIZED` — owned terminal reached 0 and became neutral.
- `P1_CAPTURED` — neutral terminal reached 100 and became owned.

### New Health Counters
- `terminals_loaded`
- `contender_changes`
- `neutralizations`
- `captures`
- `ticks_processed`

---

## Startup Validator Updates

| Contract | Check | Error Message |
|----------|-------|---------------|
| Tagged terminals exist | `CollectionService:GetTagged("Terminal")` count > 0 | `No terminals tagged 'Terminal' found.` |
| TerminalId attribute | non-empty string | `<name>: missing TerminalId string` |
| PlanetId attribute | non-empty string | `<name>: missing PlanetId string` |
| TerminalType attribute | in `Base/Field` | `<name>: TerminalType must be Base or Field` |
| InitialOwner attribute | in `Neutral/TGE/TRA/THC` | `<name>: InitialOwner invalid` |
| Unique terminal key | no duplicate `PlanetId.TerminalId` | `Duplicate terminal key <PlanetId.TerminalId>` |

---

## Golden Tests for This Pass

### Test: Enemy Neutralizes Owned Base Terminal
- **Setup:** One Base terminal with `InitialOwner=THC`; place 2 TGE players and 0 TRA/THC in zone.
- **Action:** Let simulation run uninterrupted.
- **Expected:** progress decreases from 100 to 0, owner changes `THC -> Neutral`.
- **Pass condition:** `[P1_SUMMARY] neutralizations>=1 captures=0` and neutralized terminal owner is `Neutral`.

### Test: Neutral Field Captured by Single Contender
- **Setup:** One Field terminal with `InitialOwner=Neutral`; place 3 TRA players, 0 others in zone.
- **Action:** let simulation run until terminal capture.
- **Expected:** progress increases from 0 to 100, owner changes `Neutral -> TRA`.
- **Pass condition:** `[P1_SUMMARY] captures>=1` and captured terminal owner `TRA`.

### Test: Tie Freezes Progress
- **Setup:** Neutral Field terminal at progress 40 (test seed), with 2 TGE and 2 TRA in zone.
- **Action:** hold tie state for 20 seconds.
- **Expected:** active contender is none; progress remains near 40 (no meaningful drift).
- **Pass condition:** summary reports `tie_freeze_ok=1` and absolute drift <= 1.0 progress point.

### Regression Tests
Re-run these golden tests from previous passes: none (Pass 1).

---

## Test Packet (Build Phase Contract)

### Build Step 1: Validation + Registry Bootstrap
AI build prints (temporary):
- `[P1_TEST] startup terminals=<n> valid=<0|1>`
- `========== START READ HERE ==========`
- `[P1_SUMMARY] step=bootstrap valid=<0|1> terminals=<n> errors=<n>`

Pass/fail:
- PASS if `valid=1`, `terminals>=1`, `errors=0`.

### Build Step 2: Contender Resolution Loop
AI build prints:
- `[P1_TEST] contender terminal=<id> tge=<n> tra=<n> thc=<n> winner=<team|None>` when contender changes.
- `[P1_SUMMARY] step=contender terminals=<n> contender_changes=<n> errors=<n>`

Pass/fail:
- PASS if contender changes occur in test setup and `errors=0`.

### Build Step 3: Two-Stage Progress + Ownership Transitions
AI build prints:
- `[P1_TEST] progress terminal=<id> owner=<owner> contender=<team|None> value=<p>` sampled sparsely.
- `[P1_TEST] transition terminal=<id> from=<owner> to=<owner> reason=<neutralized|captured>`
- `[P1_SUMMARY] step=progress neutralizations=<n> captures=<n> tie_freeze_ok=<0|1> errors=<n>`

Pass/fail:
- PASS if at least one intended transition occurs for each targeted scenario and `errors=0`.

MCP procedure:
- Use standard default procedure (stop -> start -> wait for marker -> get output -> stop).

---

## Critic Review Notes
Checklist result:
- Blocking: 0
- Flagged: 2
  - Flag: `StartPhase = CaptureWindowActive` is a temporary simplification; must be removed in Pass 2.
  - Flag: Ownership visuals are minimal in Pass 1 (state-correct but not production-polish); full UI pass planned in Pass 5.
- Verdict: APPROVED for Pass 1 build.
