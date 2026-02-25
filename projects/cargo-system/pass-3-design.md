# Pass 3 Design: Permit Gating + Seller/Buyer UX — Cargo System

**Feature pass:** 3 of 6  
**Based on:** feature-passes.md, idea-locked.md  
**Code baseline:** Pass 1 + Pass 2 implemented and studio-validated  
**Date:** 2026-02-25

---

## What This Pass Adds

Pass 3 adds permit-gated buying and lightweight in-game seller/buyer UI while preserving existing server authority:
- Permit definitions and persistent per-player permit ownership.
- Seller purchase flow blocked when required permit is missing.
- Permit purchase flow with credit deduction.
- Seller UI: product list + quantity selector + slot-cap guard.
- Buyer UI: expected payout preview + confirm sell + clear rejection messages.
- Optional route hint in seller UI payload (destination buyer id).

Out of scope for Pass 3: cross-server cargo persistence/permits (Pass 4), exploit hardening pass (Pass 5), performance tuning (final pass).

---

## File Changes

### New Files
- `src/shared/UiTypes.luau`  
  Purpose: typed payload contracts for seller/buyer UI snapshots.
- `src/server/Data/Permits.luau`  
  Purpose: permit definitions (`PermitId`, display name, category, price).
- `src/server/Services/PermitService.luau`  
  Purpose: server authority for permit ownership + purchase + persistence.
- `src/server/Services/TradeUiService.luau`  
  Purpose: builds seller/buyer UI payloads and validates request-level intents.
- `src/client/CargoTradeUi.client.luau`  
  Purpose: minimal ScreenGui for seller and buyer interactions.

### Modified Files
- `src/shared/Types.luau`  
  Add permit and UI-related type shapes for seller definitions.
- `src/shared/Remotes.luau`  
  Add remotes for opening UI and submitting UI actions.
- `src/shared/Config.luau`  
  Add UI tunables and permit persistence key/version.
- `src/server/Data/Sellers.luau`  
  Add `RequiredPermitId` support on seller definitions.
- `src/server/Services/CargoTradingService.luau`  
  Add permit checks and quantity-based purchase path used by UI.
- `src/server/Services/InteractionService.luau`  
  Seller/buyer prompts open UI instead of immediately buying/selling.
- `src/server/Services/StartupValidator.luau`  
  Validate configured seller permit ids exist in permit data.
- `src/server/Bootstrap.server.luau`  
  Initialize permit + UI services and bind new remotes.
- `src/client/CargoClient.client.luau`  
  Keep drop key behavior; coexist with new UI script.

---

## Data Structures

### `shared/Types.luau` additions
```lua
export type PermitCategory = "Planet" | "Tier" | "Legality"

export type PermitDefinition = {
    PermitId: string,
    DisplayName: string,
    Category: PermitCategory,
    Price: number,
}

export type SellerDefinition = {
    SellerId: string,
    RequiredPermitId: string?,
    Cargo: { [string]: SellerCargoDefinition },
}
```

### `shared/UiTypes.luau`
```lua
export type SellerUiProduct = {
    CargoType: string,
    PurchasePrice: number,
    SellPrice: number,
    DestinationBuyerId: string,
}

export type SellerUiState = {
    SellerId: string,
    Products: { SellerUiProduct },
    OwnedCount: number,
    SlotsRemaining: number,
    RequiredPermitId: string?,
    MissingPermit: boolean,
    PermitPrice: number?,
}

export type BuyerUiState = {
    BuyerId: string,
    HasCarriedCargo: boolean,
    ExpectedPayout: number,
    ExpectedReason: string?,
}
```

---

## New/Modified APIs

### `server/Services/PermitService.luau` (new)
```lua
function PermitService.init(): ()
function PermitService.playerHasPermit(player: Player, permitId: string): boolean
function PermitService.getOwnedPermitIds(player: Player): { [string]: boolean }
function PermitService.tryPurchasePermit(player: Player, permitId: string): (boolean, string?)
```

Notes:
- Persistence via DataStore key `cargo_permits_v1:<userId>` (pcall guarded).
- In-memory cache per player for runtime reads.

### `server/Services/TradeUiService.luau` (new)
```lua
function TradeUiService.getSellerUiState(player: Player, sellerId: string): UiTypes.SellerUiState?
function TradeUiService.getBuyerUiState(player: Player, buyerId: string): UiTypes.BuyerUiState?
```

### `server/Services/CargoTradingService.luau` (modified)
```lua
function CargoTradingService.tryPurchase(player: Player, sellerId: string, cargoType: string, quantity: number): (boolean, string?)
-- Existing signature kept; now enforces permit if seller requires it.

function CargoTradingService.trySellCarriedToBuyer(player: Player, buyerId: string): (boolean, string?)
-- Existing signature kept.

function CargoTradingService.previewSellToBuyer(player: Player, buyerId: string): (number, string?)
-- New helper for Buyer UI expected payout/reason.
```

### `shared/Remotes.luau` additions
```lua
export type CargoRemotes = {
    RequestDropCarried: RemoteEvent,
    OpenSellerUi: RemoteEvent,          -- server->client payload SellerUiState
    OpenBuyerUi: RemoteEvent,           -- server->client payload BuyerUiState
    RequestPurchaseCargo: RemoteFunction, -- client->server (sellerId,cargoType,quantity)
    RequestBuyPermit: RemoteFunction,     -- client->server (permitId)
    RequestSellAtBuyer: RemoteFunction,   -- client->server (buyerId)
    NotifyTradeMessage: RemoteEvent,      -- server->client (code,text)
}
```

---

## Config Additions

`shared/Config.luau`:
```lua
Permit = {
    DataStoreKeyPrefix = "cargo_permits_v1",
}

UI = {
    SellerMaxRows = 8,
    QuantityMin = 1,
    QuantityMaxPerAction = 5,
}
```

---

## Data Flow

### Behavior: Seller Prompt -> UI -> Purchase
1. Player triggers seller `CargoSellerPrompt`.
2. `InteractionService` resolves `SellerId` and calls `TradeUiService.getSellerUiState`.
3. Server fires `OpenSellerUi` with product list, slots remaining, and permit status.
4. Client chooses cargo type + quantity and invokes `RequestPurchaseCargo`.
5. Server validates:
   - seller/cargo exists
   - quantity range
   - slot remaining
   - permit requirement satisfied (`PermitService.playerHasPermit`)
   - funds available
6. On success, existing crate spawn path runs for `quantity`.
7. On failure, return reason code and `NotifyTradeMessage` to UI.

### Behavior: Permit Purchase
1. If seller payload has `MissingPermit=true`, UI shows permit purchase button.
2. Client invokes `RequestBuyPermit(permitId)`.
3. Server validates permit id and spends credits through `EconomyService.trySpend`.
4. On success, permit id is granted and saved; seller UI can be reopened and purchase retried.

### Behavior: Buyer Prompt -> UI -> Sell
1. Buyer prompt opens UI via `OpenBuyerUi` with `ExpectedPayout` and rejection reason preview.
2. Client confirms and invokes `RequestSellAtBuyer(buyerId)`.
3. Server executes `trySellCarriedToBuyer`; returns reason/payout.
4. UI shows success payout or exact reject reason.

---

## Integration Pass (against real current code)

### Existing modules reused without signature breaks
- `EconomyService.trySpend/addCredits/getCredits` unchanged.
- `CargoTradingService.tryPurchase` signature unchanged; behavior extended for permits.
- `InteractionService` still owns prompt wiring; only callback targets change.
- `CargoCarryService` remains source of carried crate truth for buyer preview/sell.

### New cross-boundary flows
- `InteractionService -> TradeUiService.getSellerUiState/getBuyerUiState`: table payload only, no side effects.
- `Client UI -> CargoTradingService.tryPurchase`: existing validated transaction path.
- `Client UI -> PermitService.tryPurchasePermit`: new permit transaction path, economy-authoritative.
- `Client UI -> CargoTradingService.trySellCarriedToBuyer`: existing sell authority path.

### Storage lifecycle
- Permit ownership:
  - Created/loaded in `PermitService.init` on `PlayerAdded`.
  - Updated on `tryPurchasePermit`.
  - Persisted on change and on `PlayerRemoving`.
  - Cached in-memory per server.

---

## Security Boundaries

- Client never sets cargo values/payout or permit ownership directly.
- All UI calls are intent-only; server re-derives authoritative data.
- Quantity clamped and validated server-side.
- Permit id validated against `Data/Permits.luau`; unknown ids rejected.
- Buyer preview is informative only; final sale still server-authoritative.

---

## Diagnostics & Validators Updates

### New reason codes
- `BUY_REJECT_PERMIT`
- `PERMIT_BUY_OK`
- `PERMIT_BUY_REJECT_FUNDS`
- `PERMIT_BUY_REJECT_OWNED`
- `PERMIT_BUY_REJECT_CONFIG`

### Startup validator additions
- Every `Sellers[sellerId].RequiredPermitId` must exist in `Permits` data.

---

## Golden Tests (Pass 3)

1. Permit Gate Blocks Purchase Until Permit Bought  
Setup: seller requires permit, player lacks permit.  
Action: open seller UI, attempt purchase, buy permit, purchase again.  
Expected: first attempt rejected with permit reason; permit purchase deducts exactly permit price; second purchase succeeds.

2. Seller UI Quantity + Slot Guard  
Setup: player owns 4 cargo, seller offers purchasable product.  
Action: request quantity 2 from UI.  
Expected: rejected by slot cap; quantity 1 succeeds.

3. Buyer UI Payout Preview + Result  
Setup: one normal cargo and one stolen cargo; black market buyer configured.  
Action: preview and confirm sell at normal and black market buyers.  
Expected: normal stolen preview shows reject reason, confirm fails with same reason; black market preview/confirm payout equals `PurchasePrice`.

Regression tests to rerun: all Pass 1 and Pass 2 golden tests.

---

## Test Packet (for build phase)

### Build step A: Permit service + permit-gated purchase
- Add temporary prints:
  - `[P3_TEST] event=permit_check seller=<id> permit=<id|none> has=<true|false>`
  - `[P3_TEST] event=permit_buy_result ok=<true|false> reason=<code> credits=<n>`
- Pass criteria:
  - permit-gated buy emits `BUY_REJECT_PERMIT`
  - successful permit buy emits `PERMIT_BUY_OK`
  - follow-up buy emits `BUY_OK`

### Build step B: Seller/buyer UI transport
- Add temporary prints:
  - `[P3_TEST] event=seller_ui_open seller=<id> products=<n> slots=<n> missingPermit=<true|false>`
  - `[P3_TEST] event=buyer_ui_open buyer=<id> payout=<n> reason=<code|none>`
- Pass criteria:
  - seller and buyer open events fire exactly once per prompt trigger.

### Build step C: Buyer confirm flow via UI
- Add temporary prints:
  - `[P3_TEST] event=ui_sell_result ok=<true|false> reason=<code> payout=<n>`
- Pass criteria:
  - stolen->normal yields `SELL_REJECT_STOLEN`
  - stolen->blackmarket yields `SELL_OK_BLACKMARKET` with purchase-price payout.

Expected summary format for temporary build logs:
`[P3_SUMMARY] permits_ok=<n> permits_reject=<n> ui_open_seller=<n> ui_open_buyer=<n> sells_ok=<n> sells_reject=<n> errors=<n>`

---

## Self-Critique (Checklist)

- Server authority maintained for money/permits/cargo state.
- New remotes are intent-level and validate all inputs server-side.
- No pass-4 persistence scope creep beyond permits.
- UI layer isolated from cargo core logic to limit regression blast radius.
- Main risk: DataStore throttling/errors in Studio/live; mitigated by pcall + in-memory fallback with explicit reject reasons when writes fail.

---

## Build Scope Lock

Build only files listed above for Pass 3. Keep cargo carry/drop/sell physics behavior unchanged unless required for UI/permit integration.
