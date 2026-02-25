# Project State

**Stage:** Pass 5 Build
**Status:** in-progress
**Pipeline Version:** v3
**Last Updated:** 2026-02-25

## Resume Notes
Pass 4 continuity foundation is stable in Studio tests. Pass 5 hardening has started with server-side transaction locks to reduce race/replay outcomes under prompt spam.

### Pass 4 Build Delta
**Built as designed (foundation):**
- Added `CargoPersistenceService` with DataStore-backed owned-cargo load/save.
- Restores owned cargo on join (up to global max 5) and reconstructs physical crates.
- Persists owned cargo periodically and on major transitions (buy/sell/drop/disconnect).
- Global cap continuity now uses restored ownership state in `CargoRegistry.countOwnedBy`.

**Current limitations:**
- This is persistence foundation, not full teleport handoff contracts yet.
- DataStore availability in Studio depends on API access settings.

### Pass 5 Build Delta
**Built so far:**
- Added per-player trade mutex in `CargoTradingService` to reject overlapping buy/sell requests (`TRADE_REJECT_BUSY`).
- Added per-cargo sell mutex to prevent concurrent sell processing on the same cargo id (`SELL_REJECT_BUSY`).
- Wrapped transaction scopes in protected execution with deterministic lock release.

**Goal of this slice:**
- Prevent double-processing from rapid prompt spam and overlapping remote execution windows.

### Final Optimization Delta
**Built so far:**
- Removed noisy per-drop follow debug spam logs.
- Added restore-path diagnostics counters (`restore_drop_ship_attach`, `restore_drop_path_attach`, `restore_drop_world_attach`, `restore_drop_near_player`, `restore_owned_near_player`).
- Moved cargo drop/stack tuning constants into `Config.Cargo.DropTuning` for Studio-side balancing without code edits.

### Pass 2 Build Delta
**Built as designed:**
- Non-owner pickup now works for dropped cargo and permanently sets `IsStolen=true`.
- Normal buyers reject stolen cargo with `SELL_REJECT_STOLEN`.
- Black market buyer support added (`BuyerType="BlackMarket"`), with payout locked to `PurchasePrice`.
- Buyer prompt wiring/validation now supports both `CargoBuyer` and `BlackMarketBuyer` tags.

**Deviations from design:**
- Added guard `BUY_REJECT_ALREADY_CARRYING` so players cannot purchase while already carrying cargo.
- Added carry UX behavior: seller prompt hides locally while carrying cargo and reappears when not carrying.
- Drop orientation now follows player look direction projected onto the drop surface.
- Added dependent-cargo re-settle when picking up a supporting crate to prevent "double carry" and floating stacks.

**New runtime contracts:**
- Black market rig can be tagged `BlackMarketBuyer` with `BuyerId="BlackMarketA"` to receive sell prompts.
- `Players.<Player>.IsCarryingCargo` is authoritative carry-state attribute used by client prompt visibility logic.
- Pass 2-specific diagnostics now include `[P2_TEST]` for stolen pickup and black market/stolen sale outcomes.

**Non-blocking follow-ups:**
- Rename legacy `[P1_TEST]`/`[P1_SUMMARY]` diagnostics to pass-neutral tags in a future cleanup pass.

### Pass 3 Design Delta
**Planned for build:**
- Permit definitions + persistent ownership service.
- Permit-gated seller purchase checks.
- Seller UI (product + quantity + permit prompt) and buyer UI (payout preview + confirm).
- Additional trade remotes and validator checks for permit references.

**Design constraints:**
- Keep server authority for all money/cargo/permit state transitions.
- Keep current carry/drop/sell physics behavior intact.

### Pass 3 Build Delta
**Built as designed:**
- Added permit data + `PermitService` with DataStore-backed ownership load/save and purchase flow.
- Added permit UI remotes and server handler (`OpenPermitUi`, `RequestBuyPermit`).
- Seller and buyer interactions remain prompt-driven for purchase/sell actions.
- `CargoTradingService` now enforces seller `RequiredPermitId` and exposes `previewSellToBuyer`.
- Added client `CargoTradeUi.client.luau` permit popup (price + purchase button + close X).
- Startup validator now verifies seller permit references against permit data.

**Deviations from design:**
- Deferred full seller/buyer UI flows; implemented prompt-first UX with permit popup only.
- Kept existing `[P1_TEST]/[P2_TEST]` diagnostics and added targeted `[P3_TEST]` events rather than introducing a full new summary counter set.
