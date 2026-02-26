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

## Pass 2 Tests

### Test: Window Start Gate + Dynamic Duration Buckets
- **Added in:** Pass 2
- **Setup:** Idle terminal, no cooldown. Validate starts across population bands (<=20, 21-39, 40-49, >=50).
- **Action:** Trigger interaction as faction player; also attempt invalid starts (civilian, during cooldown, while active).
- **Expected:** Exactly one valid start, invalid starts rejected, duration bucket selected correctly.
- **Pass condition:** `[P2_SUMMARY] step=start duration_bucket_ok=1` and `errors=0`.

### Test: Overtime Start and End on Lead Loss
- **Added in:** Pass 2
- **Setup:** Active window near end with active contender present.
- **Action:** Let timer hit zero (overtime starts), then remove strict lead (tie/empty).
- **Expected:** Overtime starts only at timeout with contender and ends immediately when lead is lost; cooldown starts.
- **Pass condition:** `[P2_SUMMARY] step=overtime overtime_started>=1 overtime_ended>=1 cooldown_started>=1 errors=0`.

### Test: Regen/Decay Matrix
- **Added in:** Pass 2
- **Setup:**
  - Owned terminal at partial progress with empty zone.
  - Owned terminal at partial progress with non-empty tie.
  - Neutral terminal at partial progress with no contender.
- **Action:** Run each condition for fixed duration.
- **Expected:** Owned-empty regens upward, owned-tie freezes, neutral-no-contender decays downward.
- **Pass condition:** `[P2_SUMMARY] step=regen_decay regen_ok=1 tie_freeze_ok=1 decay_ok=1 errors=0`.

---
