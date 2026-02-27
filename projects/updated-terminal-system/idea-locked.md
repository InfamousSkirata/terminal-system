# UpdatedTerminal System — Idea Locked (v1.3+)

## Overall Purpose
Create planet-local, persistent terminals that drive readable PvP objectives and provide meaningful strategic advantages without item power creep.

Primary goals:
- Repeatable PvP conflict around clear control points.
- Advantage via spawn access + wage multiplier hooks.
- Scales from low-pop to high-pop servers.
- Prevents degenerate states (stalled progress, spam starts, runaway scaling).
- Persists across server shutdowns and server changes.

## Player-Facing Behavior
- Players on `TGE`, `TRA`, or `THC` can contest terminals.
- Capture flow is two-stage: neutralize owner (`100 -> 0`), then capture from neutral (`0 -> 100`).
- Only one faction progresses at a time: strict lead required (`+1` over second place).
- Terminal contest runs in time windows, can enter overtime, then locks for cooldown.
- Ownership changes impact spawn availability (field terminals only) and wage bonus hooks.

## UI Requirements
- Always-visible overhead label: `[ Terminal ]`.
- Ownership visuals:
- Owned: faction logo + faction color light.
- Neutral: grey light + no logo.
- Progress bar shown only during `CaptureWindowActive` or `Overtime`.
- Owned-state bar shows owner control depletion/regen.
- Neutral-state bar shows active contender fill color.
- Tie/no contender: bar freezes except regen/decay automation.
- Recommended messages:
- `Terminal contested: <TerminalName>`
- `Terminal neutralized: <TerminalName>`
- `Terminal captured by <Faction>: <TerminalName>`
- Optional lockout message when cooldown starts.

## Core Mechanics
1. Terminal types:
- `Base`: starts owned, capturable, never spawn-enabled.
- `Field`: starts neutral (or persisted owner), capturable, spawn-enabled for owner.

2. Capture window lifecycle:
- Start only from `Idle`, by non-civilian faction player interaction.
- Dynamic duration by planet-server population:
- `<=20: 8m`, `21-39: 10m`, `40-49: 12m`, `>=50: 14m`.
- After resolution, terminal enters fixed `30m` cooldown.

3. Active contender resolution:
- Count eligible players in 40-stud radius by faction.
- Active contender exists only on strict lead (`leading >= second + 1`).
- Tie for first => no active contender.

4. Single-contender progress model:
- Owned terminal:
- Owner contender => regen toward `100`.
- Enemy contender => neutralize toward `0`.
- At `0` => becomes `Neutral`.
- Neutral terminal:
- Active contender => fill toward `100`.
- None/tie/empty => decay toward `0`.
- At `100` => owned by contender faction.

5. Speed scaling:
- `N = min(activeContenderCount, 10)`.
- `M = 0.35 + 0.65*(N/10)`.
- `ActualTime = BaseTime / M`.
- Base capture time (`0->100`) at cap: `120s`.
- Base neutralize time (`100->0`) at cap: `156s` (`1.3x`).

6. Regen/decay anti-stall:
- Owned + empty zone => regen toward `100` at baseline `N=1` speed.
- Owned + tie => freeze (no owner-favor regen on tie).
- Neutral + no contender => decay toward `0` at baseline `N=1` speed.

7. Overtime:
- Timer hits `0` with contender => enter overtime.
- Continue while strict lead is maintained.
- End immediately on tie/loss of lead, capture completion, or overtime cap hit.
- Overtime safety cap: `8m` (recommended and adopted).

8. Cooldown lockout:
- Fixed `30m` after capture window/overtime resolution.
- No new window start during cooldown.

## Instances & Scope
- Multiple terminals can exist and run independently.
- Persistence scope is per `PlanetId + TerminalId`.
- Runtime is server-authoritative; clients only render UI and send interaction requests.

## Spawn Integration
- Spawn allowed only when all are true:
- Terminal type `Field`.
- Owner matches player faction.
- Terminal planet matches player current planet/server.
- No spawn cooldown in v1.
- Ownership/neutral changes must update spawn options immediately.
- Base terminals never appear in spawn options.

## Wage Integration
- Terminals contribute as external wage multiplier input.
- Global ownership bonus (all planets): `+1%` per owned terminal.
- Terminal contribution soft-cap: `+10%` total.
- Recompute trigger events:
- ownership changed,
- became neutral,
- captured from neutral,
- startup state load.

## Persistence Model
- Key: `PlanetId + TerminalId`.
- Required saved fields:
- `OwnerFaction`, `TerminalType`.
- Recommended saved fields:
- `ProgressValue`, `CooldownRemainingSeconds`, `LastUpdatedTimestamp`.
- Mid-capture shutdown behavior:
- On restart, load ownership.
- Do not resume capture window.
- Restore cooldown remaining if saved; otherwise start idle.
- Save frequency:
- immediate on ownership change,
- on cooldown start/end,
- optional periodic autosave.

## Security Constraints
- Capture eligibility and progression are fully server-calculated.
- Client cannot author ownership/progress/window transitions.
- All integration events originate from server state changes.

## Anti-Abuse / Edge Rules
- Start spam blocked by phase+cooldown gating and first-valid start wins.
- No half-capture forever due to neutral decay and owned empty-zone regen.
- No runaway speed due to contender cap at `10`.
- Overtime ends instantly if strict lead is lost.
- Timer boundary ordering is deterministic: apply progress threshold state updates before overtime/cooldown decision at boundary tick.

## Required Runtime Data
- `TerminalId`, `PlanetId`, `TerminalType`, `OwnerFaction`.
- `Phase` (`Idle`, `CaptureWindowActive`, `Overtime`, `Cooldown`).
- `CaptureWindowEndTime`, `CooldownEndTime`.
- `Progress` (`0..100`), optional `LastActiveContender`.
- `ZoneRadius=40` and visual config references.

## Required Integration Events
- `CaptureWindowStarted(terminalId, durationSeconds)`
- `OwnershipChanged(terminalId, oldOwner, newOwner)`
- `BecameNeutral(terminalId)`
- `CooldownStarted(terminalId, cooldownSeconds)`
- `CooldownEnded(terminalId)`
- `OvertimeStarted(terminalId)`
- `OvertimeEnded(terminalId)`
- `ProgressUpdated(terminalId, progressValue, activeContenderOrNone)`

Subscribers:
- Spawn system
- Wage system
- UI system
- Persistence system

## Testable Success Conditions
- Capture start: valid faction interaction in `Idle` starts exactly one window; civilians cannot.
- Active contender: only strict-lead faction changes progress; tie freezes as specified.
- Two-stage model: owned terminal must reach `0` before neutral capture can complete.
- Speed scaling: measured progression aligns with formula and `N<=10` cap.
- Regen/decay: owned empty zone regens; neutral no-contender decays.
- Overtime: starts only with contender at timer end and terminates correctly on tie/loss/cap/capture.
- Cooldown: no new window can start during 30-minute lock.
- Spawn integration: only eligible faction sees field terminal spawn immediately after ownership changes.
- Wage hook: multiplier recompute is triggered on all specified ownership transitions and startup load.
- Persistence: ownership survives restart; active capture windows do not resume.

## Locked Tuning Values
- Zone radius: `40` studs.
- Strict lead rule: `+1` above second place.
- Speed cap: `10` active contenders.
- Capture base time: `120s` at cap.
- Neutralize base time: `156s` at cap.
- Window duration: `8/10/12/14` minutes by population bracket.
- Overtime cap: `8m`.
- Cooldown: `30m`.
- Wage bonus: `+1%` per owned terminal, capped at `+10%`.
