# Feature Passes: UpdatedTerminal System

**Based on:** idea-locked.md
**Date:** 2026-02-26

---

## Pass 1: Bare Bones Contest Core
**What it includes:**
- Terminal runtime model and config-backed definitions for terminal identity and type (`Base`, `Field`).
- Core terminal state fields (`owner`, `phase`, `progress`, `zoneRadius`, timestamps/placeholders as needed).
- Zone presence counting for eligible factions (`TGE`, `TRA`, `THC`) within 40-stud radius (alive-only).
- Active contender selection with strict lead rule (`leading >= second + 1`), tie => no contender.
- Single-bar two-stage logic:
- Owned terminal: enemy contender neutralizes `100 -> 0`; owner contender regens toward `100`.
- Neutral terminal: contender captures `0 -> 100`; no contender decays toward `0`.
- Ownership transitions at thresholds:
- `0` while owned => becomes neutral.
- `100` while neutral => captured by active contender.
- Base vs Field behavior baseline:
- Base starts owned and is capturable.
- Field starts neutral and is capturable.

**After this pass, the system:**
- Supports complete ownership swings with one active contender at a time using the shared progress bar model.
- Runs the core conflict loop without timed windows/overtime/cooldown/persistence/integration layers yet.

---

## Pass 2: Capture Window Lifecycle and Timing
**Depends on:** Pass 1
**What it includes:**
- Interaction-based window start gate:
- Non-civilian faction players only.
- Start only in `Idle` and not in cooldown.
- First valid request wins.
- Dynamic capture window duration bands (`8m/10m/12m/14m`) by server population, duration locked at start.
- Progress speed formula and cap:
- `N = min(leadingCount, 10)`
- `M = 0.35 + 0.65*(N/10)`
- Capture base `120s`, neutralize base `156s`.
- Full overtime rules:
- Start at timer end only if contender exists.
- Continue only while strict lead is maintained.
- End on tie/loss, capture completion, or 8-minute cap.
- Cooldown lockout system:
- 30-minute cooldown after window/overtime resolution.
- No new capture start during cooldown.
- Deterministic timer-boundary handling for exact-threshold events.

**After this pass, the system:**
- Has the full match pacing loop: contest window, overtime final push, and anti-spam cooldown lockout.

---

## Pass 3: Persistence and Server-Restart Semantics
**Depends on:** Pass 1, 2
**What it includes:**
- Planet-terminal keyed persistence (`PlanetId + TerminalId`).
- Save/load contracts for ownership and lifecycle continuity:
- Required save: owner (and terminal identity linkage).
- Recommended save: progress, cooldown remaining, last updated timestamp.
- Save triggers:
- Ownership changes.
- Cooldown start/end.
- Startup load path.
- Shutdown/restart behavior:
- Active capture windows never resume after restart.
- Ownership restores from persistence.
- Cooldown restored if saved; otherwise terminal enters idle.

**After this pass, the system:**
- Maintains consistent terminal control across server shutdowns and re-entry without exploitable mid-capture resumes.

---

## Pass 4: Integration Contracts (Spawn + Wage + Events)
**Depends on:** Pass 1, 2, 3
**What it includes:**
- Server event emission surface:
- `CaptureWindowStarted`
- `OwnershipChanged`
- `BecameNeutral`
- `CooldownStarted` / `CooldownEnded`
- `OvertimeStarted` / `OvertimeEnded`
- `ProgressUpdated`
- Spawn system integration:
- Field-only spawn eligibility.
- Owner-faction and same-planet validation.
- Immediate spawn list updates on ownership/neutral changes.
- Base terminal hard exclusion from spawn options.
- Wage system hook integration:
- Trigger recompute on ownership transitions and startup load.
- Terminal contribution policy `+1%` per owned terminal with `+10%` cap.

**After this pass, the system:**
- Correctly drives downstream spawn and wage behavior from authoritative terminal state changes.

---

## Pass 5: World UI, Feedback, and Readability
**Depends on:** Pass 1, 2, 3, 4
**What it includes:**
- Overhead label `[ Terminal ]` on all terminals.
- Ownership world visuals:
- Owned => faction logo + faction color light.
- Neutral => grey + no logo.
- Progress UI visibility and color semantics:
- Visible only during capture window/overtime.
- Owned-state and neutral-state color rules implemented.
- Tie/no contender bar freeze behavior visualized correctly.
- Player messaging hooks for contested/neutralized/captured/cooldown moments.

**After this pass, the system:**
- Is understandable in live play with clear visual state, objective readability, and timely feedback.

---

## Final Pass: Optimization and Hardening
**Depends on:** All previous passes
**What it includes:**
- Performance tuning for per-terminal tick evaluation cadence and zone counting.
- Event/update throttling and deduping where behavior remains unchanged.
- Persistence write efficiency improvements while preserving critical transitions.
- Multi-terminal scalability validation under higher population.
- Final anti-abuse/edge-case hardening and config extraction for all tunables.

**After this pass, the system:**
- Preserves identical gameplay behavior with improved runtime performance, scalability, and production robustness.
