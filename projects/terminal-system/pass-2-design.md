# Pass 2 Design: Timing, Overtime, Cooldown, Regen/Decay — Terminal System

**Feature pass:** 2 of 6
**Based on:** feature-passes.md, idea-locked.md
**Existing code:** `Config.luau`, `Types.luau`, `StartupValidator.luau`, `TerminalRegistry.luau`, `TerminalCaptureService.luau`, `Bootstrap.server.luau`
**Critic Status:** APPROVED
**Date:** 2026-02-25

---

## What This Pass Adds
This pass converts the always-on Pass 1 loop into a real lifecycle:
- Interaction-driven capture window start (faction-only, idle-only, first valid request wins).
- Dynamic capture window durations by server population (locked at window start).
- Overtime entry/exit rules at timer boundary.
- 30-minute cooldown lockout after contest resolution.
- Regen/decay behavior for no-contender states.
- Deterministic timer-boundary transitions.

This pass intentionally does not add persistence, spawn/wage integration events, or player-facing UI widgets. Those remain in later passes.

---

## File Changes

### New Files
| File | Location | Purpose |
|------|----------|---------|
| `TerminalInteractionService.luau` | `src/src/server/Services` | Owns start-capture interaction flow via `ProximityPrompt` and validates initiators. |

### Modified Files
| File | What's Changing | Why |
|------|----------------|-----|
| `Config.luau` | Add pass-2 timing/overtime/cooldown and interaction config; remove `StartPhase` dependency. | Lifecycle is now runtime-driven, not hardcoded start-active. |
| `Types.luau` | Expand `TerminalPhase` (`Idle`, `CaptureWindowActive`, `Overtime`, `Cooldown`) and `TerminalState` timing fields. | Needed for explicit phase machine. |
| `TerminalRegistry.luau` | Initialize terminals in `Idle`; add phase/timer setters and `TryStartCaptureWindow` atomic gate. | Centralized state ownership + race-safe window start. |
| `TerminalCaptureService.luau` | Add phase machine, overtime/cooldown transitions, regen/decay logic, and timer checks. | Implements pass-2 gameplay behavior. |
| `StartupValidator.luau` | Validate new config constraints at startup (duration ordering, positive intervals). | Fail fast on misconfiguration. |
| `Bootstrap.server.luau` | Start `TerminalInteractionService` before capture loop; wire dependencies. | Needed to receive player start requests. |

---

## Workspace Contracts (Pass 2)
Existing required terminal attributes remain unchanged:
- `TerminalId`, `PlanetId`, `TerminalType`, `InitialOwner`

No new mandatory workspace authoring contracts are introduced in this pass.
Interaction prompt contract:
- `TerminalInteractionService` auto-creates/reuses a `ProximityPrompt` named `TerminalInteractPrompt` under each terminal part.
- This avoids manual prompt setup drift.

---

## New/Modified APIs

```lua
-- src/src/server/Services/TerminalInteractionService.luau
local TerminalInteractionService = {}

function TerminalInteractionService.Start(): nil
function TerminalInteractionService.Stop(): nil

-- Internal
-- ensurePrompt(state: TerminalState): ProximityPrompt
-- canPlayerStartWindow(player: Player, state: TerminalState): (boolean, string?)
-- onPromptTriggered(player: Player, terminalKey: string): nil
```

```lua
-- src/src/server/Services/TerminalRegistry.luau (modified)
local TerminalRegistry = {}

function TerminalRegistry.BuildKey(planetId: string, terminalId: string): string
function TerminalRegistry.GetAll(): {[string]: TerminalState}
function TerminalRegistry.GetByKey(terminalKey: string): TerminalState?

function TerminalRegistry.SetOwner(terminalKey: string, newOwner: OwnerFaction): nil
function TerminalRegistry.SetProgress(terminalKey: string, progress: number): nil
function TerminalRegistry.SetActiveContender(terminalKey: string, contender: Faction?): nil
function TerminalRegistry.SetNeutralProgressFaction(terminalKey: string, faction: Faction?): nil
function TerminalRegistry.SetPhase(terminalKey: string, phase: TerminalPhase): nil

function TerminalRegistry.TryStartCaptureWindow(terminalKey: string, durationSeconds: number, startedByUserId: number): boolean
function TerminalRegistry.StartOvertime(terminalKey: string, startedAt: number): nil
function TerminalRegistry.StartCooldown(terminalKey: string, durationSeconds: number): nil
function TerminalRegistry.ClearWindowTiming(terminalKey: string): nil
function TerminalRegistry.IsCooldownActive(terminalKey: string, nowTs: number): boolean
```

```lua
-- src/src/server/Services/TerminalCaptureService.luau (modified)
local TerminalCaptureService = {}

function TerminalCaptureService.Start(): nil
function TerminalCaptureService.Stop(): nil

-- Internal
-- computeWindowDurationSeconds(playerCount: number): number
-- evaluateTerminalState(terminalKey: string, state: TerminalState, nowTs: number, tickSeconds: number): nil
-- applyOwnedRegenOrNeutralize(...): nil
-- applyNeutralCaptureOrDecay(...): nil
-- resolveWindowTimeout(...): nil
-- resolveOvertimeExit(...): nil
```

```lua
-- src/src/server/Bootstrap.server.luau (modified)
-- order:
-- 1) StartupValidator.ValidateTerminalsAndConfig()
-- 2) TerminalRegistry.Init()
-- 3) TerminalInteractionService.Start()
-- 4) TerminalCaptureService.Start()
```

---

## New Data Structures

```lua
-- src/src/shared/Types.luau (modified)
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
```

```lua
-- src/src/shared/Config.luau (additions)
Terminal = {
    TickSeconds = 0.5,
    ZoneRadius = 40,

    CaptureBaseSeconds = 120,
    NeutralizeBaseSeconds = 156,
    SpeedCapPlayers = 10,
    SpeedMinMultiplier = 0.35,

    CaptureWindowSecondsLowPop = 480,   -- <=20 players
    CaptureWindowSecondsMidPop = 600,   -- 21-39
    CaptureWindowSecondsHighPop = 720,  -- 40-49
    CaptureWindowSecondsMaxPop = 840,   -- >=50

    OvertimeMaxSeconds = 480,
    CooldownSeconds = 1800,

    RegenDecayVirtualCount = 1,
    PromptHoldSeconds = 0.5,
    PromptMaxDistance = 12,
}
```

---

## Data Flow for New Behaviors

### Capture Window Start
1. Player triggers terminal prompt (`TerminalInteractionService`).
2. Service validates faction team (`TGE/TRA/THC`), alive status, and terminal phase eligibility (`Idle` and not cooldown).
3. Service computes active server population and maps to duration bucket:
- `<=20 -> 480`
- `21-39 -> 600`
- `40-49 -> 720`
- `>=50 -> 840`
4. Service calls `TerminalRegistry.TryStartCaptureWindow(terminalKey, duration, userId)`.
5. If accepted, registry sets phase `CaptureWindowActive`, stores end timestamp, clears cooldown fields.

### Capture Window Tick + Timeout
1. `TerminalCaptureService` ticks each terminal every `TickSeconds`.
2. If phase is `CaptureWindowActive`, run contender + progress logic.
3. At `now >= captureWindowEndTime`:
- If active contender exists -> `StartOvertime`.
- If none -> `StartCooldown(CooldownSeconds)`.

### Overtime
1. Overtime uses identical progress rules to capture window.
2. Overtime exits immediately when:
- active contender becomes `nil` (tie/empty/lead loss), or
- terminal is captured, or
- `now >= overtimeStartedAt + OvertimeMaxSeconds`.
3. On overtime exit -> `StartCooldown(CooldownSeconds)`.

### Regen/Decay
Owned terminal:
- active contender == owner -> regen toward 100 using owner leader count.
- active contender is enemy -> neutralize toward 0 using enemy leader count.
- no active contender:
  - if zone empty -> regen at virtual `N=1`.
  - if tie (non-empty) -> freeze.

Neutral terminal:
- active contender present -> capture/reverse logic as in pass 1.
- no active contender -> decay toward 0 at virtual `N=1`.

### Capture Completion Policy
If terminal reaches full capture (`Neutral -> Faction`) during active window or overtime:
- transition owner immediately,
- end contest immediately,
- start cooldown immediately (recommended policy from idea spec).

---

## Integration Pass (against real code)

### Data Lifecycle Traces

**terminalKey**
- **Created by:** `TerminalRegistry.BuildKey(planetId, terminalId)` during init.
- **Passed via:** interaction callback closure + capture loop iteration key.
- **Received by:** registry setters (`SetOwner`, `SetPhase`, `TryStartCaptureWindow`, etc.).
- **Stored in:** dictionary key for `stateByKey`.
- **Cleaned up by:** server shutdown.
- **Verified:** removes ambiguous plain `TerminalId` lookup currently present in `GetById`.

**captureWindowEndTime / cooldownEndTime / overtimeStartedAt**
- **Created by:** `TryStartCaptureWindow`, `StartCooldown`, `StartOvertime`.
- **Passed via:** state table fields only (no network this pass).
- **Received by:** `TerminalCaptureService` phase evaluation.
- **Stored in:** `TerminalState` runtime fields.
- **Cleaned up by:** `ClearWindowTiming` + cooldown completion transition.
- **Verified:** timestamps are monotonic `os.clock()` values for server-local phase checks.

### API Composition Checks (new calls only)

| Caller | Callee | Args Match | Return Handled | Verified Against |
|--------|--------|-----------|----------------|-----------------|
| `Bootstrap.server` | `StartupValidator.ValidateTerminalsAndConfig()` | Yes | Yes (`ok` gate) | Modified validator API in this pass |
| `Bootstrap.server` | `TerminalInteractionService.Start()` | Yes | n/a | New service in this pass |
| `TerminalInteractionService` | `TerminalRegistry.TryStartCaptureWindow(key, duration, userId)` | Yes | Yes (bool gate) | New registry API |
| `TerminalCaptureService` | `TerminalRegistry.StartOvertime/StartCooldown/ClearWindowTiming()` | Yes | n/a | New registry API |
| `TerminalCaptureService` | `TerminalRegistry.SetPhase/SetProgress/SetOwner()` | Yes | n/a | Existing + modified registry APIs |

---

## Diagnostics Updates

### New Reason Codes
- `P2_WINDOW_STARTED` — capture window accepted.
- `P2_WINDOW_REJECTED` — start request rejected (invalid team/phase/cooldown).
- `P2_OVERTIME_STARTED` — timeout with active contender.
- `P2_OVERTIME_ENDED` — lead lost, capture, or cap reached.
- `P2_COOLDOWN_STARTED` — contest resolved and lockout applied.
- `P2_COOLDOWN_ENDED` — terminal returned to idle.

### New Health Counters
- `windows_started`
- `window_start_rejects`
- `overtimes_started`
- `overtimes_ended`
- `cooldowns_started`
- `cooldowns_ended`

Note: these are temporary build-test diagnostics in this pass and can remain minimal if not yet part of a permanent diagnostics module.

---

## Startup Validator Updates

| Contract | Check | Error Message |
|----------|-------|---------------|
| Tick interval | `TickSeconds > 0` | `Config.Terminal.TickSeconds must be > 0` |
| Speed cap | `SpeedCapPlayers >= 1` | `Config.Terminal.SpeedCapPlayers must be >= 1` |
| Speed min | `0 < SpeedMinMultiplier <= 1` | `Config.Terminal.SpeedMinMultiplier must be in (0,1]` |
| Duration ordering | all durations > 0 | `Capture/cooldown/overtime durations must be > 0` |
| Regen/decay virtual count | `RegenDecayVirtualCount >= 1` | `RegenDecayVirtualCount must be >= 1` |

---

## Golden Tests for This Pass

### Test: Window Start Gate + Dynamic Duration Buckets
- **Setup:** Terminal idle and not cooling down; create players and teams to hit bucket boundaries (`<=20`, `21-39`, `40-49`, `>=50`).
- **Action:** Trigger prompt start once per population bucket.
- **Expected:** Window starts exactly once and selected duration matches configured bucket.
- **Pass condition:** `[P2_SUMMARY] window_start_ok=1 duration_bucket_ok=1 errors=0`.

### Test: Overtime Start and Immediate End on Lead Loss
- **Setup:** Active window near timeout with an active contender present.
- **Action:** Let timer hit zero (enters overtime), then force tie/empty state.
- **Expected:** Overtime starts, then ends immediately, then cooldown starts.
- **Pass condition:** `[P2_SUMMARY] overtime_started=1 overtime_ended=1 cooldown_started=1 errors=0`.

### Test: Regen/Decay Rules
- **Setup:**
  - Owned terminal at progress 60 with empty zone.
  - Owned terminal at progress 60 with non-empty tie.
  - Neutral terminal at progress 60 with no active contender.
- **Action:** Simulate each condition for fixed time window.
- **Expected:**
  - Owned empty -> progress increases.
  - Owned tie -> progress unchanged.
  - Neutral no contender -> progress decreases.
- **Pass condition:** `[P2_SUMMARY] regen_ok=1 tie_freeze_ok=1 decay_ok=1 errors=0`.

### Regression Tests
Re-run these golden tests from previous passes:
- `Enemy Neutralizes Owned Base Terminal`
- `Neutral Field Captured by Single Contender`
- `Tie Freezes Progress`

---

## Test Packet (Build Phase Contract)

### Build Step 1: Interaction Start + Duration Selection
AI build prints (temporary):
- `[P2_TEST] start_request terminal=<id> team=<team> phase=<phase> accepted=<0|1> reason=<text>`
- `[P2_TEST] window_started terminal=<id> duration=<sec> pop=<count>`
- `[P2_SUMMARY] step=start windows_started=<n> rejects=<n> duration_bucket_ok=<0|1> errors=<n>`

Pass/fail:
- PASS if at least one valid start is accepted, invalid starts are rejected, and bucket selection is correct.

### Build Step 2: Timeout -> Overtime/Cooldown State Machine
AI build prints (temporary):
- `[P2_TEST] timeout terminal=<id> contender=<team|None> phase_before=<phase>`
- `[P2_TEST] overtime terminal=<id> started=<0|1> ended=<reason|none>`
- `[P2_TEST] cooldown terminal=<id> started=<0|1> ends_in=<sec>`
- `[P2_SUMMARY] step=overtime overtime_started=<n> overtime_ended=<n> cooldown_started=<n> errors=<n>`

Pass/fail:
- PASS if overtime starts only when contender exists at timeout and cooldown starts on every contest resolution path.

### Build Step 3: Regen/Decay Behavior
AI build prints (temporary):
- `[P2_TEST] regen terminal=<id> from=<p> to=<p>`
- `[P2_TEST] decay terminal=<id> from=<p> to=<p>`
- `[P2_TEST] tie_freeze terminal=<id> from=<p> to=<p>`
- `[P2_SUMMARY] step=regen_decay regen_ok=<0|1> decay_ok=<0|1> tie_freeze_ok=<0|1> errors=<n>`

Pass/fail:
- PASS if owned-empty regens, neutral-no-contender decays, and owned tie freezes.

MCP procedure:
- Use standard procedure (stop -> start -> wait for marker -> get output -> stop).

Expected summary format:
- `[P2_SUMMARY] step=<name> key=value key=value ...`

---

## Critic Review Notes
Checklist result:
- Blocking: 0
- Flagged: 2
  - Flag: `TerminalRegistry.GetById` fallback lookup across all entries is ambiguous in multi-planet scenarios; pass 2 should replace active callsites with key-based APIs and deprecate fallback path.
  - Flag: prompt interaction can be spammed client-side; server gate is authoritative, but optional short per-player debounce can reduce noise.
- Verdict: APPROVED for Pass 2 build.
