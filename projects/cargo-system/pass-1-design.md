# Pass 1 Design: Bare Bones Cargo Loop — Cargo System

**Feature pass:** 1 of 6
**Based on:** feature-passes.md, idea-locked.md
**Existing code:** None (fresh project scaffold only)
**Critic Status:** APPROVED
**Date:** 2026-02-24

---

## What This Pass Adds

Pass 1 ships a minimal, server-authoritative loop:
- Buy cargo at seller prompt (credits deducted, max-5 enforced)
- Carry exactly one crate at a time
- Drop crate so it welds to nearby surface for ship-safe transport
- Re-pickup own dropped crate
- Sell carried crate at its assigned normal buyer for `SellPrice`
- Prevent resell using consumed `CargoId` registry

Out of scope for Pass 1: theft by non-owner, black market rules, permit gating, cross-server persistence, full custom UI.

---

## File Changes

### New Files
| File | Location | Purpose |
|------|----------|---------|
| `Config.luau` | `src/shared/` | Tunables for limits, interaction distances, wallet defaults, diagnostics flag |
| `Types.luau` | `src/shared/` | Shared type contracts for cargo records, seller/buyer defs, and result enums |
| `Remotes.luau` | `src/shared/` | Creates/finds `ReplicatedStorage/Remotes/Cargo/RequestDropCarried` |
| `Bootstrap.server.luau` | `src/server/` | Composition root: init validators, services, remotes, prompts |
| `Diagnostics.luau` | `src/server/Services/` | Counters + structured reason-code logging |
| `StartupValidator.luau` | `src/server/Services/` | Validates required tagged seller/buyer workspace contracts |
| `EconomyService.luau` | `src/server/Services/` | Server wallet authority (read/add/spend), with player attributes backing |
| `IdService.luau` | `src/server/Services/` | Generates unique `CargoId` strings for this server session |
| `CargoRegistry.luau` | `src/server/Services/` | Tracks live cargo metadata, cargo instance mapping, and sold ids |
| `CargoFactory.luau` | `src/server/Services/` | Creates cargo crate model/parts and applies authoritative attributes |
| `CargoCarryService.luau` | `src/server/Services/` | Handles carry attach, drop weld, and owner-only pickup in Pass 1 |
| `CargoTradingService.luau` | `src/server/Services/` | Purchase + normal sale validation and state transitions |
| `InteractionService.luau` | `src/server/Services/` | Adds/handles ProximityPrompts for seller/buyer/cargo pickup |
| `Sellers.luau` | `src/server/Data/` | Static seller definitions for Pass 1 |
| `Buyers.luau` | `src/server/Data/` | Static normal buyer definitions for Pass 1 |
| `CargoClient.client.luau` | `src/client/` | Local keybind for drop request and carry animation trigger stub |

### Modified Files
| File | What's Changing | Why |
|------|----------------|-----|
| `default.project.json` | No changes required | Existing mapping already supports server/client/shared paths |

---

## New/Modified APIs

```lua
-- shared/Remotes.luau
export type CargoRemotes = {
    RequestDropCarried: RemoteEvent,
}

function Remotes.getCargoRemotes(): CargoRemotes
-- Creates/fetches folders/events under ReplicatedStorage and returns typed handles.


-- server/Services/EconomyService.luau
function EconomyService.init(): ()
function EconomyService.getCredits(player: Player): number
function EconomyService.trySpend(player: Player, amount: number): (boolean, string?)
function EconomyService.addCredits(player: Player, amount: number): ()
-- Server authority over credits; no client-set values.


-- server/Services/IdService.luau
function IdService.nextCargoId(): string
-- Format: "cargo_<jobId>_<counter>_<unixMs>".


-- server/Services/CargoRegistry.luau
export type CargoRecord = Types.CargoRecord

function CargoRegistry.register(instance: Model, record: CargoRecord): ()
function CargoRegistry.getByInstance(instance: Instance): CargoRecord?
function CargoRegistry.getInstanceById(cargoId: string): Model?
function CargoRegistry.markSold(cargoId: string): ()
function CargoRegistry.isSold(cargoId: string): boolean
function CargoRegistry.countOwnedBy(userId: number): number
function CargoRegistry.destroyCargo(cargoId: string): ()
-- Owns authoritative in-memory lifecycle for Pass 1.


-- server/Services/CargoFactory.luau
function CargoFactory.createCargo(record: Types.CargoRecord): Model
-- Builds crate model and writes authoritative attributes onto model.


-- server/Services/CargoCarryService.luau
function CargoCarryService.tryPickUp(player: Player, cargoModel: Model): (boolean, string?)
function CargoCarryService.tryDropCarried(player: Player): (boolean, string?)
function CargoCarryService.getCarriedCargo(player: Player): Model?
-- Pass 1 pickup rule: only OriginalOwnerUserId may pick up.


-- server/Services/CargoTradingService.luau
function CargoTradingService.tryPurchase(player: Player, sellerId: string, cargoType: string, quantity: number): (boolean, string?)
function CargoTradingService.trySellCarriedToBuyer(player: Player, buyerId: string): (boolean, string?)
-- Handles all buy/sell validation and money movement.


-- server/Services/InteractionService.luau
function InteractionService.init(): ()
-- Wires prompts for sellers, buyers, and cargo pickup.


-- server/Services/StartupValidator.luau
function StartupValidator.validateOrError(): ()
-- Hard-fails startup on missing workspace contracts.
```

---

## New Data Structures

```lua
-- shared/Types.luau
export type CargoStatus = "Owned" | "Dropped" | "InTransit" | "Sold"

export type CargoRecord = {
    CargoId: string,
    CargoType: string,
    OriginSellerId: string,
    DestinationBuyerId: string,
    PurchasePrice: number,
    SellPrice: number,
    OriginalOwnerUserId: number,
    CurrentHolderUserId: number?,
    IsStolen: boolean,
    PlanetTag: string?,
    Status: CargoStatus,
}

export type SellerCargoDefinition = {
    CargoType: string,
    PurchasePrice: number,
    SellPrice: number,
    DestinationBuyerId: string,
}

export type SellerDefinition = {
    SellerId: string,
    Cargo: { [string]: SellerCargoDefinition },
}

export type BuyerDefinition = {
    BuyerId: string,
    BuyerType: "Normal",
}
```

Cargo model attributes mirrored from `CargoRecord` (except optionals when nil):
- `CargoId`, `CargoType`, `OriginSellerId`, `DestinationBuyerId`, `PurchasePrice`, `SellPrice`, `OriginalOwnerUserId`, `CurrentHolderUserId`, `IsStolen`, `Status`

---

## New Config Values

```lua
-- shared/Config.luau
return {
    DiagnosticsEnabled = false,

    Cargo = {
        MaxOwnedPerPlayer = 5,           -- Hard cap in Pass 1. Range: 1-20.
        CarryOffset = CFrame.new(0, 0, -2.5), -- Position of crate relative to HumanoidRootPart.
        DropRayDistance = 14,            -- Max downward search distance for valid surface.
        MaxInteractDistance = 14,        -- Distance validation for seller/buyer/cargo pickup.
        PickupPromptDistance = 10,
        SellerPromptDistance = 10,
        BuyerPromptDistance = 10,
    },

    Economy = {
        StartingCredits = 1500,          -- Applied when player has no Credits attribute.
    },

    Input = {
        DropKey = Enum.KeyCode.G,        -- Client drop request key.
    },
}
```

---

## Data Flow for New Behaviors

### Behavior: Purchase Cargo
1. Player triggers seller `ProximityPrompt` on tagged seller model.
2. `InteractionService` resolves `SellerId` attribute, picks first configured cargo type for Pass 1 smoke flow.
3. `CargoTradingService.tryPurchase(player, sellerId, cargoType, quantity=1)` executes.
4. Service checks owned count from `CargoRegistry.countOwnedBy(userId)` and `MaxOwnedPerPlayer`.
5. Service validates seller/cargo definition from `Sellers.luau` and wallet spend via `EconomyService.trySpend`.
6. For each crate: `IdService.nextCargoId` creates id, `CargoFactory.createCargo` spawns model, `CargoRegistry.register` stores authoritative record.
7. `CargoCarryService.tryPickUp` auto-picks first spawned crate if player not carrying.
8. Diagnostics logs purchase result and counters.

### Behavior: Carry and Drop Weld
1. Carry state is server-owned in `CargoCarryService` (`carriedByUserId[userId] = cargoId`).
2. On pickup, service welds cargo primary part to player `HumanoidRootPart`; status set `InTransit`, `CurrentHolderUserId=userId`.
3. Client presses `DropKey`, fires `RequestDropCarried` remote.
4. Server validates sender identity and carry ownership; performs raycast from HRP downward/forward to find BasePart surface.
5. Server detaches carry weld, positions crate above hit point, creates weld from crate to hit BasePart.
6. Status set `Dropped`, `CurrentHolderUserId=nil`.
7. Any previous drop weld is cleaned before re-weld.

### Behavior: Sell at Normal Buyer
1. Player triggers buyer prompt on tagged buyer model (`BuyerId` attr).
2. `InteractionService` calls `CargoTradingService.trySellCarriedToBuyer`.
3. Service gets carried cargo from `CargoCarryService.getCarriedCargo`.
4. Service loads cargo record and rejects if sold or missing.
5. Service validates `DestinationBuyerId == buyerId` and buyer type is `Normal`.
6. Service pays `SellPrice` with `EconomyService.addCredits`, marks sold in registry, destroys cargo instance.
7. Summary diagnostics increments successful sales.

### Behavior: Owner-only Re-Pickup (Pass 1 scope boundary)
1. Dropped cargo has pickup prompt.
2. Player trigger calls `CargoCarryService.tryPickUp`.
3. Service validates `OriginalOwnerUserId == player.UserId`.
4. Non-owner is rejected (theft intentionally deferred to Pass 2).

---

## Integration Pass (against real code)

### Data Lifecycle Traces

**CargoRecord**
- **Created by:** `CargoTradingService.tryPurchase()` using seller config + generated id.
- **Passed via:** function argument into `CargoFactory.createCargo(record)` and `CargoRegistry.register(instance, record)`.
- **Received by:**
  - `CargoFactory.createCargo(record: Types.CargoRecord)`
  - `CargoRegistry.register(instance: Model, record: Types.CargoRecord)`
- **Stored in:**
  - `CargoRegistry.recordsById[cargoId]`
  - Model attributes for replication/inspection
- **Cleaned up by:** `CargoRegistry.destroyCargo(cargoId)` on sale.
- **Verified:** single owner module (`CargoRegistry`) controls source-of-truth and cleanup path.

**CarriedCargo Link**
- **Created by:** `CargoCarryService.tryPickUp` sets `carriedByUserId[userId]=cargoId`.
- **Passed via:** lookup inside `getCarriedCargo(player)`.
- **Received by:** `CargoTradingService.trySellCarriedToBuyer`.
- **Stored in:** in-memory map with user lifetime.
- **Cleaned up by:** drop, sale destroy, or `Players.PlayerRemoving` handler.
- **Verified:** no cross-player action path; userId key prevents player A acting on player B cargo.

**SoldCargo Guard**
- **Created by:** `CargoRegistry.markSold(cargoId)` on successful sale.
- **Passed via:** `CargoRegistry.isSold(cargoId)` checks before sale finalization.
- **Received by:** `CargoTradingService.trySellCarriedToBuyer`.
- **Stored in:** `soldById[cargoId]=true`.
- **Cleaned up by:** server shutdown (Pass 1 is in-server only).
- **Verified:** blocks same-session resell; cross-server durability deferred to Pass 4.

### API Composition Checks (new calls only)

| Caller | Callee | Args Match | Return Handled | Verified Against |
|--------|--------|-----------|----------------|-----------------|
| `InteractionService.onSellerPrompt(player, sellerId)` | `CargoTradingService.tryPurchase(player, sellerId, cargoType, 1)` | Yes | Yes (`ok, reason`) | Pass 1 design signatures |
| `CargoTradingService.tryPurchase` | `EconomyService.trySpend(player, totalCost)` | Yes | Yes (abort on false) | Pass 1 design signatures |
| `CargoTradingService.tryPurchase` | `CargoRegistry.countOwnedBy(player.UserId)` | Yes | Yes (limit gate) | Pass 1 design signatures |
| `InteractionService.onBuyerPrompt` | `CargoTradingService.trySellCarriedToBuyer(player, buyerId)` | Yes | Yes (`ok, reason`) | Pass 1 design signatures |
| `CargoClient` | `Remotes.RequestDropCarried:FireServer()` | Yes (no payload) | Server sender-authoritative | Pass 1 design signatures |

No existing prior-pass code exists, so there are zero backward-compatibility signature conflicts.

---

## Diagnostics Updates

### New Reason Codes
- `BUY_OK` — purchase completed.
- `BUY_REJECT_LIMIT` — rejected for max-owned cap.
- `BUY_REJECT_FUNDS` — insufficient credits.
- `BUY_REJECT_CONFIG` — missing seller/cargo config.
- `PICKUP_OK` — cargo attached to player.
- `PICKUP_REJECT_OWNER` — non-owner tried pickup in Pass 1.
- `DROP_OK` — drop succeeded and welded.
- `DROP_REJECT_SURFACE` — no valid BasePart surface.
- `SELL_OK` — normal sale completed.
- `SELL_REJECT_DEST` — wrong buyer destination.
- `SELL_REJECT_NOCARGO` — player attempted sale without carried cargo.
- `SELL_REJECT_ALREADY_SOLD` — cargo id already consumed.

### New Health Counters
- `purchases_success`
- `purchases_rejected`
- `drops_success`
- `drops_rejected`
- `sales_success`
- `sales_rejected`
- `active_cargo_count`

---

## Startup Validator Updates

| Contract | Check | Error Message |
|----------|-------|---------------|
| Seller nodes exist | At least 1 tagged `CargoSeller` instance in Workspace | `Cargo startup failed: no CargoSeller-tagged instance found` |
| Buyer nodes exist | At least 1 tagged `CargoBuyer` instance in Workspace | `Cargo startup failed: no CargoBuyer-tagged instance found` |
| Seller attributes | Each seller has non-empty `SellerId` string attribute | `Cargo startup failed: CargoSeller missing SellerId` |
| Buyer attributes | Each buyer has non-empty `BuyerId` string attribute | `Cargo startup failed: CargoBuyer missing BuyerId` |
| Config sanity | `MaxOwnedPerPlayer >= 1`, prompt distances > 0 | `Cargo startup failed: invalid Config value` |

---

## Golden Tests for This Pass

### Test: Purchase Cap + Metadata Integrity
- **Setup:** 1 seller with valid `SellerId`, enough credits (>= 5 * purchase price), empty cargo ownership.
- **Action:** Trigger seller purchase prompt 6 times.
- **Expected:** First 5 purchases succeed, 6th is rejected for cap; all created crates have required attributes and unique `CargoId`.
- **Pass condition:** Visual: exactly 5 owned crates exist. Diagnostics: `BUY_OK=5` and one `BUY_REJECT_LIMIT`.

### Test: Drop Weld Stability on Moving Surface
- **Setup:** Player carrying crate. A moving ship/floor BasePart exists.
- **Action:** Player drops cargo onto ship floor; move ship for 10 seconds.
- **Expected:** Cargo remains attached to ship floor and follows movement without sliding off.
- **Pass condition:** Visual: crate remains fixed relative to floor. Diagnostics: one `DROP_OK`, zero `DROP_REJECT_SURFACE`.

### Test: Route-Locked Sale + Anti-Dupe
- **Setup:** Carry cargo assigned to Buyer A; Buyer B also exists.
- **Action:** Attempt sale at Buyer B (wrong destination), then Buyer A, then repeat sale attempt on same cargo id.
- **Expected:** Buyer B rejects; Buyer A sale succeeds with `SellPrice` payout; second attempt fails because cargo is consumed/sold.
- **Pass condition:** Credits increase exactly by `SellPrice` once. Diagnostics include `SELL_REJECT_DEST`, `SELL_OK`, and `SELL_REJECT_ALREADY_SOLD`.

### Regression Tests
Re-run these golden tests from previous passes: None (Pass 1 baseline).

---

## Test Packet (Build Phase)

### Step 1: Purchase + Carry wiring
- **AI build prints:**
  - `========== START READ HERE ==========`
  - `[P1_TEST] event=buy_attempt seller=<id> cargoType=<type> qty=<n>`
  - `[P1_TEST] event=buy_result ok=<true|false> reason=<code> owned=<n> credits=<n>`
  - `[P1_TEST] event=pickup_result ok=<true|false> reason=<code> cargoId=<id>`
- **Expected summary format:**
  - `[P1_SUMMARY] step=purchase buys_ok=<n> buys_reject=<n> carried=<0|1> errors=<n>`
- **Pass/fail condition:** PASS if `buys_ok>=1`, `carried=1`, `errors=0`.

### Step 2: Drop weld behavior
- **AI build prints:**
  - `[P1_TEST] event=drop_attempt player=<name> cargoId=<id>`
  - `[P1_TEST] event=drop_result ok=<true|false> reason=<code> weldedTo=<partName|none>`
- **Expected summary format:**
  - `[P1_SUMMARY] step=drop drops_ok=<n> drops_reject=<n> errors=<n>`
- **Pass/fail condition:** PASS if `drops_ok>=1` and `errors=0`.

### Step 3: Sale route lock + anti-dupe
- **AI build prints:**
  - `[P1_TEST] event=sell_attempt buyer=<id> cargoId=<id>`
  - `[P1_TEST] event=sell_result ok=<true|false> reason=<code> payout=<n>`
- **Expected summary format:**
  - `[P1_SUMMARY] step=sell sell_ok=<n> sell_reject_dest=<n> sell_reject_sold=<n> credits_delta=<n> errors=<n>`
- **Pass/fail condition:** PASS if `sell_ok=1`, `sell_reject_dest>=1`, `sell_reject_sold>=1`, `credits_delta>0`, `errors=0`.

### MCP Procedure
Use standard MCP procedure for each step: `stop_playtest` -> `start_playtest` -> wait for start marker -> `get_playtest_output` once -> `stop_playtest`.

---

## Critic Review Notes

## Critic Review: Cargo System — Pass 1 Design

### Blocking Issues (must fix)
1. None.

### Flagged Items (note for later)
1. `soldById` durability is in-memory only in Pass 1; cross-server anti-dupe persistence is deferred to Pass 4.
2. Seller purchase uses a single default cargo option via prompt in Pass 1; full quantity/product UI is deferred to Pass 3.

### Passed
- Server authority is explicit for buy/drop/sell transitions.
- Remote surface is minimal (`drop` only) and sender-authoritative.
- Startup contracts and config sanity checks are defined.
- Cleanup ownership is explicit for cargo lifecycle and carry links.
- No deprecated APIs or frame-spam loops are required by this design.

### Regression Risk
- None for earlier passes (no previous pass code exists).

### Verdict: APPROVED / BLOCKED (0 blocking issues)
APPROVED.
