# System Idea: Terminal System

## Overall Purpose
Terminals are planet-local, persistent control points that create readable PvP objectives and recurring faction conflict. Ownership grants strategic advantages that are not item-based: faction-specific spawn access (field terminals only) and a global wage multiplier contribution. The system is designed to scale from low-population to high-population servers through dynamic capture-window durations and capped capture speed scaling.

Success criteria:
- Terminal fights happen repeatedly in normal play.
- Ownership changes are understandable from world/UI feedback.
- Full terminal flips occur inside intended match pressure windows.
- State persists reliably across server restarts and planet travel.

## Player-Facing Behavior
Players on faction teams (TGE, TRA, THC) can interact with an idle, non-cooldown terminal to begin a capture window. During an active window, factions contest a capture zone around the terminal. Only one faction can actively progress the bar at a time: the faction with strict local lead (+1 over second place).

Capture is two-stage:
- Owned terminal: neutralization from 100 to 0.
- Neutral terminal: capture from 0 to 100 by active contender.

The system supports dynamic swings:
- Defenders can regenerate owner control if they become active contender.
- Neutral progress decays when uncontested/tied.
- Progress can reverse when active contender changes.

At window end:
- If no active contender, contest ends and cooldown begins.
- If an active contender exists, overtime begins and continues while strict lead is maintained.
- Overtime ends on loss of strict lead, successful capture, or hard cap.

## UI Requirements
World/UI expectations:
- Overhead label always visible: `[ Terminal ]`.
- Ownership visuals:
  - Owned: faction color + logo.
  - Neutral: grey, no logo.
- Progress bar shown only during Capture Window Active or Overtime.
- Bar semantics:
  - Owned: owner control remaining (100 to 0 neutralization).
  - Neutral: active contender capture progress (0 to 100).
- Tie/no active contender: bar freezes except configured regen/decay rules.

Messaging (recommended, not mandatory):
- `Terminal contested: <TerminalName>`
- `Terminal neutralized: <TerminalName>`
- `Terminal captured by <Faction>: <TerminalName>`
- `Terminal secured; lockout active`

## Core Mechanics
1. Terminal types:
- Base Terminal: starts owned, capturable, never spawn-enabled.
- Field Terminal: starts neutral by default, capturable, spawn-enabled when owned.

2. Capture window start constraints:
- Initiator must be on TGE/TRA/THC (not Civilian).
- Terminal phase must be Idle and not in cooldown.
- First valid request wins if multiple interactions race.

3. Capture window duration by active planet-server population (locked at window start):
- <= 20 players: 8 min
- 21-39 players: 10 min
- 40-49 players: 12 min
- >= 50 players: 14 min

4. Active contender rule:
- Count eligible in-zone alive players per faction.
- Active contender exists only with strict lead (+1 above second place).
- Ties => no contender.

5. Progress speed model:
- Effective player count `N = min(leadingCount, 10)`.
- Multiplier `M = 0.35 + 0.65 * (N / 10)`.
- Capture time = `120 / M` seconds (neutral 0->100).
- Neutralize time = `156 / M` seconds (owned 100->0; 1.3x capture).

6. Regen/decay:
- Owned + empty zone: regen toward 100 at baseline N=1 speed.
- Owned + tie (non-empty): freeze.
- Neutral + no active contender (empty or tie): decay toward 0 at baseline N=1 speed.

7. Overtime:
- Starts if timer reaches 0 with active contender.
- Runs with normal progress rules.
- Ends immediately on strict lead loss, capture completion, or overtime hard cap (8 min).

8. Cooldown:
- 30-minute lockout after contest resolution.
- No new window starts during cooldown.
- Ownership state remains unchanged.
- Progress UI hidden.

## Instances & Scope
- Multiple terminals run concurrently and independently.
- Persistence scope: per planet, per terminal.
- Persistence key: `<PlanetId>.<TerminalId>`.
- Server-authoritative system; clients render and request interactions only.

## Edge Cases & Abuse Scenarios
- No infinite partial states:
  - Neutral decay and owned empty-zone regen prevent permanent partial progress.
- No capture spam:
  - Fixed 30-minute cooldown.
- No pure zerg instant win:
  - Speed capped at 10 effective contenders.
- End-of-timer boundaries are deterministic:
  - If 0%/100% is hit exactly at timeout, apply ownership update before overtime decision.
- Overtime abuse prevention:
  - Overtime ends immediately on tie/empty/lead loss.
  - Hard cap at 8 minutes.
- Mid-capture server shutdown:
  - Ownership persists; capture window does not resume.

## Integration with Existing Systems
Spawn system:
- Only field terminals can be spawn locations.
- Spawn allowed only when terminal owner matches player faction and terminal planet equals current server planet.
- Spawn options update immediately on ownership/neutral transitions.

Wage system (external hook):
- Terminals emit ownership changes for wage recomputation.
- Global wage bonus from total owned terminals across planets:
  - +1% per terminal, capped at +10% terminal contribution.

Persistence system:
- Save immediately on ownership changes and cooldown transitions.
- Optional periodic autosave.
- Restore ownership on server start; do not resume in-progress capture window.

UI systems:
- Subscribe to state/progress/overtime/cooldown events.
- Reflect ownership and contest state in world + HUD/map.

## Security Concerns
Must be server authoritative:
- Capture start validity.
- In-zone eligible player counting.
- Active contender resolution.
- Progress updates and phase transitions.
- Ownership changes.
- Cooldown/overtime timing.
- Spawn eligibility and wage trigger events.

Clients are untrusted for:
- Team counts, progress claims, ownership claims, timing claims.

## Performance Concerns
- Frequent zone counting across many terminals: requires bounded tick rate and efficient player-in-zone checks.
- Progress/UI update fan-out can spike network traffic if emitted too frequently.
- Persistence writes on high-frequency transitions should be event-driven and throttled where safe (without losing critical ownership changes).
- Recommended update tick: 0.25s to 1.0s, tuned after playtesting.

## Open Questions
- None blocking for roadmap stage.
- Future balancing knobs expected in config (timings, overtime cap, cooldown, speed curve constants).
