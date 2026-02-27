# Golden Tests: UpdatedTerminal System

Tests accumulate across passes. Every prove step runs ALL tests, not just current-pass tests.

---

## Pass 1 Tests

### Test: Enemy Neutralizes Owned Base Terminal
- **Added in:** Pass 1
- **Setup:** Base terminal owned by THC at progress 100. In-zone counts forced/observed as `TGE=2, TRA=0, THC=0`.
- **Action:** Run contest loop continuously until ownership transition occurs.
- **Expected:** Progress reaches `0` and owner changes to `Neutral`.
- **Pass condition:** `[P1_SUMMARY] neutralizations>=1 captures=0 errors=0`.

### Test: Neutral Field Captured by Single Contender
- **Added in:** Pass 1
- **Setup:** Field terminal neutral at progress 0. In-zone counts forced/observed as `TRA=3, TGE=0, THC=0`.
- **Action:** Run contest loop continuously until capture transition occurs.
- **Expected:** Progress reaches `100` and owner changes to `TRA`.
- **Pass condition:** `[P1_SUMMARY] captures>=1 errors=0`.

### Test: Tie Freezes Progress on Owned Terminal
- **Added in:** Pass 1
- **Setup:** Owned terminal seeded to progress 60 with tie counts `TGE=2, TRA=2, THC=0`.
- **Action:** Hold tie for 20 seconds.
- **Expected:** No active contender and progress remains effectively unchanged.
- **Pass condition:** `[P1_SUMMARY] tie_freeze_ok=1 errors=0` with drift <= `1.0`.
