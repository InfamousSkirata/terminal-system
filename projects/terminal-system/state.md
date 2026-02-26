# Project State

**Stage:** Pass 2 Build
**Status:** testing-needed
**Pipeline Version:** v3
**Last Updated:** 2026-02-25

## Resume Notes
Pass 2 implementation completed in `src/src/server` and `src/src/shared`.
Next: run MCP playtest checks for start gating, overtime/cooldown transitions, and regen/decay summaries; then proceed to Prove.

### Pass 1 Build Delta
**Built as designed:**
- Added shared config/types modules for terminal tuning and typed runtime state.
- Added startup validator for terminal workspace contracts and duplicate key detection.
- Added terminal registry with per-terminal runtime state, attribute sync, and basic ownership visuals.
- Added server capture loop with strict-lead contender resolution and two-stage neutralize/capture behavior.
- Added bootstrap composition script to validate terminals and start services.

**Deviations from design:**
- Runtime state keying was tightened to use full `PlanetId.TerminalId` keys in capture-service write paths to avoid cross-planet `TerminalId` collisions.
- Temporary Pass 1 test-print instrumentation was added during build verification and fully removed during wrap-up.

**New runtime contracts:**
- Terminals must be tagged `Terminal` and be `BasePart` instances.
- Required attributes per terminal: `TerminalId`, `PlanetId`, `TerminalType` (`Base`/`Field`), `InitialOwner` (`Neutral`/`TGE`/`TRA`/`THC`).
- Server writes runtime attributes: `OwnerFaction`, `TerminalPhase`, `TerminalProgress`, `ActiveContender`, `NeutralProgressFaction`.

**Non-blocking follow-ups:**
- `StartPhase = "CaptureWindowActive"` is a deliberate Pass 1 simplification and must be replaced by interaction-driven window lifecycle in Pass 2.
- Ownership visuals are intentionally minimal; full world/UI requirements remain scheduled for Pass 5.
