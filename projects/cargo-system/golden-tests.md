# Golden Tests: Cargo System

Tests accumulate across passes. Every prove step runs ALL tests, not just the current pass's.

---

## Pass 1 Tests

### Test: Purchase Cap + Metadata Integrity
- **Added in:** Pass 1
- **Setup:** 1 seller with valid `SellerId`, enough credits (>= 5 * purchase price), empty cargo ownership.
- **Action:** Trigger seller purchase prompt 6 times.
- **Expected:** First 5 purchases succeed, 6th is rejected for cap; all created crates have required attributes and unique `CargoId`.
- **Pass condition:** Visual: exactly 5 owned crates exist. Diagnostics: `BUY_OK=5` and one `BUY_REJECT_LIMIT`.

### Test: Drop Weld Stability on Moving Surface
- **Added in:** Pass 1
- **Setup:** Player carrying crate. A moving ship/floor BasePart exists.
- **Action:** Player drops cargo onto ship floor; move ship for 10 seconds.
- **Expected:** Cargo remains attached to ship floor and follows movement without sliding off.
- **Pass condition:** Visual: crate remains fixed relative to floor. Diagnostics: one `DROP_OK`, zero `DROP_REJECT_SURFACE`.

### Test: Route-Locked Sale + Anti-Dupe
- **Added in:** Pass 1
- **Setup:** Carry cargo assigned to Buyer A; Buyer B also exists.
- **Action:** Attempt sale at Buyer B (wrong destination), then Buyer A, then repeat sale attempt on same cargo id.
- **Expected:** Buyer B rejects; Buyer A sale succeeds with `SellPrice` payout; second attempt fails because cargo is consumed/sold.
- **Pass condition:** Credits increase exactly by `SellPrice` once. Diagnostics include `SELL_REJECT_DEST`, `SELL_OK`, and `SELL_REJECT_ALREADY_SOLD`.

---

## Pass 2 Tests

### Test: Theft Flagging on Non-Owner Pickup
- **Added in:** Pass 2
- **Setup:** Player A buys and drops cargo. Player B stands nearby.
- **Action:** Player B picks up Player A's dropped cargo.
- **Expected:** Pickup succeeds and cargo is permanently marked stolen.
- **Pass condition:** Diagnostics include `[P2_TEST] event=pickup_stolen ...`; normal buyer later rejects the same cargo as stolen.

### Test: Normal Buyer Rejects Stolen Cargo
- **Added in:** Pass 2
- **Setup:** Carry a cargo crate where `IsStolen=true`.
- **Action:** Attempt to sell at normal buyers (`CoreBuyerA` or `CoreBuyerB`).
- **Expected:** Sale is rejected for stolen-state rule.
- **Pass condition:** Diagnostics include `[P2_TEST] ... SELL_REJECT_STOLEN` and summary shows `sell_reject_stolen` incrementing.

### Test: Black Market Payout Equals Purchase Price
- **Added in:** Pass 2
- **Setup:** Black market buyer exists with `BuyerId=BlackMarketA` and tag `BlackMarketBuyer` (or `CargoBuyer`). Carry stolen cargo.
- **Action:** Sell at `BlackMarketA`.
- **Expected:** Sale succeeds and payout equals `PurchasePrice` exactly (not `SellPrice`).
- **Pass condition:** Diagnostics include `[P2_TEST] event=sell_result ok=true reason=SELL_OK_BLACKMARKET payout=<purchasePrice>`.

---

## Pass 3 Tests

### Test: Permit Gate + Permit Purchase Flow
- **Added in:** Pass 3
- **Setup:** A seller has `RequiredPermitId`; player does not own that permit and has enough credits.
- **Action:** Attempt cargo purchase from seller UI, buy permit, then retry purchase.
- **Expected:** Initial buy is rejected for missing permit, permit purchase succeeds with correct credit deduction, retry purchase succeeds.
- **Pass condition:** Diagnostics include permit reject then permit buy success, followed by `BUY_OK`.

### Test: Seller Quantity Guard from UI
- **Added in:** Pass 3
- **Setup:** Player owns 4 cargo and opens seller UI.
- **Action:** Submit quantity 2, then quantity 1.
- **Expected:** Qty 2 rejected by slot limit; qty 1 succeeds.
- **Pass condition:** Exactly one limit reject and one successful purchase.

### Test: Buyer UI Preview + Confirm Consistency
- **Added in:** Pass 3
- **Setup:** Carry stolen cargo; normal and black market buyers exist.
- **Action:** Open buyer UI at each buyer, compare preview vs confirm result.
- **Expected:** Normal buyer preview indicates rejection and confirm rejects; black market preview payout equals purchase price and confirm pays that amount.
- **Pass condition:** Preview and final outcomes match for each buyer path.
