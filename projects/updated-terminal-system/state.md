# Project State

**Stage:** Pass 4 Complete
**Status:** pass-4-complete
**Pipeline Version:** v3
**Last Updated:** 2026-02-27

## Resume Notes
Studio MCP reconnected and Pass 1 scripts were restored to Studio:
- `game.ReplicatedStorage`: `Config`, `Types`
- `game.ServerScriptService`: `Bootstrap`, `Services/*`

Completed:
1) Ran build-phase MCP checks per Test Packet (`stop -> start(run) -> wait -> output -> stop`).
2) Removed non-terminal workspace objects while preserving Baseplate, tagged terminals, spawn locations, and teams.

Added deterministic Pass 1 harness:
- `src/src/server/TestHarness/Pass1_Test.server.luau`
- Uses config-gated forced counts via terminal attributes (`P1_ForceTGE/TRA/THC`) in `TerminalCaptureService`.

Observed proof outputs from harness run:
- `[P1_SUMMARY] step=bootstrap valid=1 terminals=2 errors=0`
- `[P1_SUMMARY] step=contender terminals=2 contender_changes=3 errors=0`
- `[P1_SUMMARY] step=progress neutralizations=1 captures=1 tie_freeze_ok=1 errors=0`
- `[P1_HARNESS] pass=1 neutralized=1 captured=1 tie_drift=0.00 tie_ok=1 neutralizations=1 captures=1 tie_freeze_ok=1 errors=0`

Next step:
- Pass 3 design ready; build persistence + restart semantics.

Runtime defaults:
- `Pass1HarnessEnabled=false`
- `UseForcedTeamCounts=false`

Pass 2 implementation completed in source + Studio:
- `TerminalInteractionService` added (ProximityPrompt start gate).
- `TerminalCaptureService` now handles:
  - Idle/capture/overtime/cooldown phases,
  - dynamic window duration by population,
  - overtime start/end rules,
  - cooldown lockout and return to idle.
- `TerminalRegistry` expanded with phase timing fields and setters.
- `Config` updated with Pass 2 timing and interaction tunables.
- Terminal audio lifecycle added (idle/capture loops + capture start/success/fail one-shots).

Smoke check:
- Playtest booted with `[P1_SUMMARY] step=bootstrap valid=1 terminals=2 errors=0`
- No runtime errors observed in logs.

### Pass 2 Build Delta
**Built as designed:**
- Interaction-gated capture windows with hold-to-start prompts and prompt disable during non-idle phases.
- Dynamic window duration bands, overtime rules, and cooldown lockout behavior.
- TerminalRegistry phase timing fields and setters.

**Deviations from design:**
- Added terminal audio lifecycle (idle loop, capture loop, capture start/success/fail one-shots) with configurable volumes and ranges.
- Added loop fade-in for smoother capture start.

**New runtime contracts:**
- Terminal parts now host loop/oneshot Sound instances (`TerminalIdleLoop`, `TerminalCaptureLoop`, `TerminalCaptureStart`, `TerminalCaptured`, `TerminalCaptureFailed`).
- New Config fields for interaction sound/hold duration, loop volumes, and rolloff distances.

**Non-blocking follow-ups:**
- Add startup validation for `InteractionHoldSeconds` and audio config values.


### Pass 4 Build Delta
**Built as designed:**
- Event surface via TerminalEventsService (BindableEvents).
- Spawn eligibility tracking (field terminals only) and wage bonus recompute.
- Event emission on capture window/overtime/cooldown/ownership/progress changes.

**Deviations from design:**
- ProgressUpdated throttled at 1s per terminal (implemented inline in capture service).

**New runtime contracts:**
- ReplicatedStorage.TerminalEvents folder with BindableEvents.
- Spawn options change payload includes `faction`, `planetId`, `terminals`.
- Wage bonus payload includes `faction`, `ownedTerminals`, `bonusPercent`.

**Non-blocking follow-ups:**
- Consider gating ProgressUpdated by active window only (currently emits during active window/overtime).
