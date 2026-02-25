# Feature Passes: Terminal System

**Based on:** idea-locked.md
**Date:** 2026-02-25

---

## Pass 1: Bare Bones Contest Loop
**What it includes:**
- Terminal runtime model with required core fields (id/type/owner/phase/progress/zone radius).
- Capture zone detection and eligible player counting for TGE/TRA/THC (alive-only rule).
- Active contender resolution (strict +1 lead over second place).
- Two-stage progress behavior:
  - Owned terminals neutralize 100->0 when enemy is active contender.
  - Neutral terminals capture 0->100 by active contender.
- Single shared progress bar semantics in state model (no blending/multi-faction progress).
- Core ownership transitions and phase transitions for Idle/CaptureWindowActive.
- Terminal type behaviors:
  - Base terminal starts owned and is capturable but never spawn-enabled.
  - Field terminal starts neutral (default) and is capturable.

**After this pass, the system:**
- Supports end-to-end contesting and ownership swaps with one active contender at a time.
- Can run terminal fights without overtime/cooldown/persistence/integration layers yet.

---

## Pass 2: Timing, Overtime, Cooldown, Regen/Decay
**Depends on:** Pass 1
**What it includes:**
- Capture window start interaction rules (faction-only initiator, idle-only start, first valid request wins).
- Dynamic capture window duration bands (<=20, 21-39, 40-49, >=50), locked at window start.
- Full speed model implementation:
  - `N = min(leadingCount, 10)`
  - `M = 0.35 + 0.65*(N/10)`
  - capture `120/M`, neutralize `156/M`.
- Regen/decay rules:
  - Owned + empty zone => slow regen toward 100 (N=1 baseline).
  - Owned + tie non-empty => freeze.
  - Neutral + no contender => slow decay toward 0 (N=1 baseline).
- Overtime behavior and end conditions:
  - Start at timer end only if active contender exists.
  - End on strict lead loss, zone empty/tie, capture completion, or 8-minute cap.
- Cooldown lockout (30 minutes) after contest resolution.

**After this pass, the system:**
- Has the intended pacing/anti-stall/anti-spam lifecycle for live contests.
- Produces deterministic outcomes at timer boundaries and overtime transitions.

---

## Pass 3: Persistence and Restart Semantics
**Depends on:** Pass 1, 2
**What it includes:**
- Planet+terminal keyed persistence (`<PlanetId>.<TerminalId>`).
- Save/load fields:
  - Required: owner.
  - Recommended/runtime-supporting: progress, cooldown remaining, last-updated timestamp.
- Save triggers:
  - Ownership changes.
  - Cooldown start/end.
  - Server load restore path.
- Restart behavior:
  - Never resume in-progress capture windows.
  - Restore ownership and cooldown state; reset phase to Idle/Cooldown as appropriate.

**After this pass, the system:**
- Keeps terminal ownership outcomes consistent across server shutdowns and planet travel.

---

## Pass 4: Integration Contracts (Spawn, Wage, Events)
**Depends on:** Pass 1, 2, 3
**What it includes:**
- Server event/signal surface for:
  - CaptureWindowStarted
  - OwnershipChanged
  - BecameNeutral
  - CooldownStarted/CooldownEnded
  - OvertimeStarted/OvertimeEnded
  - ProgressUpdated
- Spawn integration rules:
  - Field-only spawn eligibility.
  - Owner faction and same-planet checks.
  - Immediate spawn-list updates on ownership/neutral changes.
- Wage integration hook:
  - Ownership transitions trigger recomputation.
  - Terminal contribution policy: +1% per owned terminal globally, capped at +10%.

**After this pass, the system:**
- Drives downstream game systems correctly when terminal state changes.

---

## Pass 5: World/UI Feedback and Messaging
**Depends on:** Pass 1, 2, 3, 4
**What it includes:**
- Overhead terminal label and ownership visuals (faction light/logo vs neutral grey/no-logo).
- Capture progress UI visibility rules (active window/overtime only).
- Correct bar coloring semantics for owned vs neutral states.
- Optional-but-recommended player messages for contested/neutralized/captured/cooldown events.
- UI behavior under tie/no-contender freeze and regen/decay outcomes.

**After this pass, the system:**
- Is readable and understandable to players in real time with clear world and HUD feedback.

---

## Final Pass: Optimization and Hardening
**Depends on:** All previous passes
**What it includes:**
- Performance tuning for zone checks and update cadence (0.25s-1.0s validation).
- Event/network update throttling where safe.
- Persistence write minimization without losing critical transitions.
- Scalability validation with multiple active terminals.
- Final anti-abuse validation and balancing hook polish (config extraction for tuning constants).

**After this pass, the system:**
- Preserves the same gameplay behavior with improved efficiency, scalability, and operational robustness.
