# Golden Tests: Terminal System

Tests accumulate across passes. Every prove step runs ALL tests, not just the current pass's.

---

## Pass 1 Tests

### Test: Enemy Neutralizes Owned Base Terminal
- **Added in:** Pass 1
- **Setup:** Base terminal owned by THC at progress 100. In-zone counts forced/observed as TGE=2, TRA=0, THC=0.
- **Action:** Run capture loop continuously until transition occurs.
- **Expected:** Progress reaches 0 and owner changes to Neutral.
- **Pass condition:** Diagnostics summary reports `neutralizations>=1` and no errors.

### Test: Neutral Field Captured by Single Contender
- **Added in:** Pass 1
- **Setup:** Field terminal neutral at progress 0. In-zone counts forced/observed as TRA=3, others 0.
- **Action:** Run capture loop continuously until terminal capture occurs.
- **Expected:** Progress reaches 100 and owner changes to TRA.
- **Pass condition:** Diagnostics summary reports `captures>=1` and no errors.

### Test: Tie Freezes Progress
- **Added in:** Pass 1
- **Setup:** Neutral terminal seeded at progress 40. In-zone tie maintained (TGE=2, TRA=2, THC=0).
- **Action:** Maintain tie for 20 seconds.
- **Expected:** Active contender remains None and progress remains effectively unchanged.
- **Pass condition:** Summary reports `tie_freeze_ok=1` with drift <= 1.0 progress point.

---
