# Pass 1 Design: Bare Bones Contest Core — UpdatedTerminal System

**Feature pass:** 1 of 6
**Based on:** feature-passes.md, idea-locked.md
**Existing code:** none (greenfield pass)
**Critic Status:** APPROVED
**Date:** 2026-02-26

---

## What This Pass Adds
This pass delivers the minimum server-authoritative terminal contest core:
- Runtime state for each terminal (`id/type/owner/phase/progress/zone`).
- In-zone eligible faction counting (`TGE`/`TRA`/`THC`, alive-only).
- Strict-lead active contender rule (`+1` over second place).
- Two-stage shared progress bar behavior:
- Owned terminal: enemy contender neutralizes `100 -> 0`; owner contender regens toward `100`.
- Neutral terminal: contender captures `0 -> 100`; no contender decays toward `0`.
- Ownership transitions with deterministic threshold clamps (`0` => neutral, `100` => captured).

Out of scope in Pass 1 by design:
- Interaction-driven capture-window starts.
- Capture-window duration bands, overtime, cooldown lockout.
- Persistence and restart restoration.
- Spawn/wage integrations and event contract surface.
- Full world UI/messaging polish.

---

## File Changes

### New Files
| File | Location | Purpose |
|------|----------|---------|
| `Config.luau` | `src/src/shared` | Pass 1 tunables (zone radius, tick interval, speed constants, diagnostics flag). |
| `Types.luau` | `src/src/shared` | Shared type aliases for faction/owner/type/phase/runtime state. |
| `StartupValidator.luau` | `src/src/server/Services` | Validates terminal workspace contracts before services start. |
| `Diagnostics.luau` | `src/src/server/Services` | Structured pass logging and counters for build-phase verification. |
| `TerminalRegistry.luau` | `src/src/server/Services` | Discovers terminals, owns runtime state table, applies owner/progress writes. |
| `TerminalCaptureService.luau` | `src/src/server/Services` | Tick loop for count -> contender -> progress -> transition flow. |
| `Bootstrap.server.luau` | `src/src/server` | Startup composition: validate -> registry init -> capture service start. |

### Modified Files
| File | What's Changing | Why |
|------|----------------|-----|
| none | n/a | Greenfield project and first implementation pass. |

---

## Workspace Contracts (Pass 1)
Terminal instances are `BasePart`s tagged with `Terminal` and must include attributes:
- `TerminalId: string`
- `PlanetId: string`
- `TerminalType: string` (`Base` or `Field`)
- `InitialOwner: string` (`Neutral`, `TGE`, `TRA`, `THC`)

Pass 1 startup simplification:
- Every terminal starts in `CaptureWindowActive` phase so the contest core can be validated without window-start logic.
- This is removed in Pass 2 when window lifecycle is introduced.

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
-- Reads CollectionService tag "Terminal", validates required attributes and values.
```

```lua
-- src/src/server/Services/TerminalRegistry.luau
export type TerminalState = {
    key: string, -- PlanetId.TerminalId
    terminalId: string,
    planetId: string,
    terminalType: "Base" | "Field",
    ownerFaction: "Neutral" | "TGE" | "TRA" | "THC",
    phase: "Idle" | "CaptureWindowActive",
    progress: number, -- 0..100
    zoneRadius: number,
    activeContender: "TGE" | "TRA" | "THC"?,
    terminalPart: BasePart,
}

function TerminalRegistry.Init(): nil
function TerminalRegistry.GetAll(): {[string]: TerminalState}
function TerminalRegistry.GetByKey(key: string): TerminalState?
function TerminalRegistry.SetOwner(key: string, newOwner: "Neutral" | "TGE" | "TRA" | "THC"): nil
function TerminalRegistry.SetProgress(key: string, value: number): nil
function TerminalRegistry.SetActiveContender(key: string, contender: "TGE" | "TRA" | "THC"?): nil
function TerminalRegistry.ApplyOwnershipVisual(key: string): nil
```

```lua
-- src/src/server/Services/TerminalCaptureService.luau
export type TeamCounts = {
    TGE: number,
    TRA: number,
    THC: number,
}

function TerminalCaptureService.Start(): nil
function TerminalCaptureService.Stop(): nil

-- internal typed locals
-- computeTeamCounts(state: TerminalState): TeamCounts
-- resolveActiveContender(counts: TeamCounts): "TGE" | "TRA" | "THC"?
-- computeSpeedMultiplier(activeCount: number): number
-- computeDelta(baseSeconds: number, multiplier: number, tickSeconds: number): number
-- advanceOwned(state: TerminalState, contender: "TGE" | "TRA" | "THC"?): nil
-- advanceNeutral(state: TerminalState, contender: "TGE" | "TRA" | "THC"?): nil
```

```lua
-- src/src/server/Services/Diagnostics.luau
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
    key: string,
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

---

## New Config Values

```lua
-- src/src/shared/Config.luau
return {
    Terminal = {
        ZoneRadius = 40, -- studs
        TickSeconds = 0.5, -- server update cadence
        CaptureBaseSeconds = 120, -- neutral 0->100 at M=1
        NeutralizeBaseSeconds = 156, -- owned 100->0 at M=1
        SpeedCapPlayers = 10,
        SpeedMinMultiplier = 0.35,
        StartPhase = "CaptureWindowActive", -- Pass 1 simplification
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

### Startup and Runtime State Bootstrap
1. `Bootstrap.server` calls `StartupValidator.ValidateTerminals()`.
2. On success, `TerminalRegistry.Init()` builds in-memory runtime states from tagged parts.
3. Registry seeds progress:
- Owned terminals start at `100`.
- Neutral terminals start at `0`.
4. Registry applies ownership visuals immediately.
5. `TerminalCaptureService.Start()` begins update ticks.

### Active Contender Resolution
1. On each tick, capture service computes in-zone alive faction counts.
2. Service resolves active contender only when strict lead exists.
3. Service writes contender to registry state and diagnostics when contender changes.

### Shared Progress and Ownership Transition
1. If terminal is owned:
- Owner contender => regen toward `100`.
- Enemy contender => neutralize toward `0`.
- No contender with empty zone => regen toward `100` using `N=1` baseline.
- No contender with non-empty tie => freeze.
2. If terminal is neutral:
- Active contender => capture toward `100`.
- No contender => decay toward `0` using `N=1` baseline.
3. Threshold transitions:
- Owned reaching `0` => owner becomes `Neutral`, progress clamped to `0`.
- Neutral reaching `100` => owner becomes contender faction, progress clamped to `100`.

---

## Integration Pass (against real code)

### Data Lifecycle Traces

**TerminalState**
- **Created by:** `TerminalRegistry.Init()` -> `TerminalState`
- **Passed via:** `TerminalRegistry.GetAll()` map references
- **Received by:** `TerminalCaptureService.Start()` tick loop
- **Stored in:** `TerminalRegistry._stateByKey[key]` for server lifetime
- **Cleaned up by:** not required in Pass 1 (server-lifetime state)
- **Verified:** state writes are centralized through `TerminalRegistry` setters

**ActiveContender**
- **Created by:** `resolveActiveContender(counts)` -> `Faction?`
- **Passed via:** `TerminalRegistry.SetActiveContender(key, contender)`
- **Received by:** registry state + diagnostics summary emitter
- **Stored in:** `TerminalState.activeContender` (tick-updated)
- **Cleaned up by:** set to `nil` when strict lead disappears
- **Verified:** union type prevents non-faction values

### API Composition Checks (new calls only)

| Caller | Callee | Args Match | Return Handled | Verified Against |
|--------|--------|-----------|----------------|-----------------|
| `Bootstrap.server` | `StartupValidator.ValidateTerminals()` | Yes | Yes (`ok` gate) | New API in this pass |
| `Bootstrap.server` | `TerminalRegistry.Init()` | Yes | n/a | New API in this pass |
| `Bootstrap.server` | `TerminalCaptureService.Start()` | Yes | n/a | New API in this pass |
| `TerminalCaptureService` | `TerminalRegistry.GetAll()` | Yes | Yes | New API in this pass |
| `TerminalCaptureService` | `TerminalRegistry.SetOwner/SetProgress/SetActiveContender()` | Yes | n/a | New API in this pass |

No legacy signature risk exists because this is the first pass.

---

## Diagnostics Updates

### New Reason Codes
- `P1_STARTUP_OK` — validator passed, services started.
- `P1_STARTUP_FAIL` — validator failed and startup was aborted.
- `P1_CONTENDER_CHANGED` — active contender changed.
- `P1_NEUTRALIZED` — owned terminal hit `0` and became neutral.
- `P1_CAPTURED` — neutral terminal hit `100` and changed owner.

### New Health Counters
- `terminals_loaded`
- `ticks_processed`
- `contender_changes`
- `neutralizations`
- `captures`
- `errors`

---

## Startup Validator Updates

| Contract | Check | Error Message |
|----------|-------|---------------|
| Tagged terminals exist | `CollectionService:GetTagged("Terminal")` count > 0 | `No terminals tagged 'Terminal' found.` |
| Terminal is BasePart | class derives from BasePart | `<name>: tagged Terminal must be BasePart` |
| `TerminalId` | non-empty string | `<name>: missing TerminalId string` |
| `PlanetId` | non-empty string | `<name>: missing PlanetId string` |
| `TerminalType` | in `Base/Field` | `<name>: TerminalType must be Base or Field` |
| `InitialOwner` | in `Neutral/TGE/TRA/THC` | `<name>: InitialOwner invalid` |
| Unique key | no duplicate `PlanetId.TerminalId` | `Duplicate terminal key <PlanetId.TerminalId>` |

---

## Golden Tests for This Pass

### Test: Enemy Neutralizes Owned Base Terminal
- **Setup:** One Base terminal with `InitialOwner=THC`; in-zone counts effectively `TGE=2, TRA=0, THC=0`.
- **Action:** Run loop until threshold transition.
- **Expected:** progress reaches `0` and owner changes `THC -> Neutral`.
- **Pass condition:** `[P1_SUMMARY] neutralizations>=1 captures=0 errors=0`.

### Test: Neutral Field Captured by Single Contender
- **Setup:** One Field terminal with `InitialOwner=Neutral`; in-zone counts effectively `TRA=3, TGE=0, THC=0`.
- **Action:** Run loop until capture transition.
- **Expected:** progress reaches `100` and owner changes `Neutral -> TRA`.
- **Pass condition:** `[P1_SUMMARY] captures>=1 errors=0`.

### Test: Tie Freezes Progress on Owned Terminal
- **Setup:** Owned terminal seeded at progress `60`; maintain non-empty tie `TGE=2, TRA=2, THC=0`.
- **Action:** Hold tie for 20 seconds.
- **Expected:** active contender remains none and progress remains effectively unchanged.
- **Pass condition:** `[P1_SUMMARY] tie_freeze_ok=1 errors=0` and drift <= `1.0`.

### Regression Tests
Re-run these golden tests from previous passes: none (Pass 1).

---

## Test Packet (Build Phase Contract)

### Build Step 1: Startup Validation and Registry Init
AI build prints (temporary):
- `[P1_TEST] startup terminals=<n> valid=<0|1>`
- `========== START READ HERE ==========`
- `[P1_SUMMARY] step=bootstrap valid=<0|1> terminals=<n> errors=<n>`

Pass/fail:
- PASS if `valid=1`, `terminals>=1`, and `errors=0`.

### Build Step 2: Contender Resolution
AI build prints:
- `[P1_TEST] contender key=<planet.term> tge=<n> tra=<n> thc=<n> winner=<team|None>` when winner changes.
- `[P1_SUMMARY] step=contender contender_changes=<n> errors=<n>`

Pass/fail:
- PASS if contender changes appear in setup and `errors=0`.

### Build Step 3: Progress + Transition Loop
AI build prints:
- `[P1_TEST] progress key=<planet.term> owner=<owner> contender=<team|None> value=<p>` (sparse sampling)
- `[P1_TEST] transition key=<planet.term> from=<owner> to=<owner> reason=<neutralized|captured>`
- `[P1_SUMMARY] step=progress neutralizations=<n> captures=<n> tie_freeze_ok=<0|1> errors=<n>`

Pass/fail:
- PASS if target transitions occur for test scenarios and `errors=0`.

MCP procedure:
- Default procedure (`stop -> start -> wait marker -> get output -> stop`).

---

## Critic Review Notes
Checklist result:
- Blocking: 0
- Flagged: 2
- `StartPhase = CaptureWindowActive` is a deliberate pass-1 simplification and must be replaced in Pass 2.
- Pass 1 visuals are state-correct but intentionally minimal; full visual/UI behavior is scheduled for Pass 5.
- Verdict: APPROVED for Pass 1 build.
