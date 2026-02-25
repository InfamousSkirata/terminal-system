# System Idea: Cargo System

## Overall Purpose
Create a physical cargo trading loop where players buy crates, transport them, and sell them at assigned buyers for profit. The system also supports theft, black market liquidation, permit-gated sellers, and cross-planet delivery continuity.

## Player-Facing Behavior
- Player interacts with Cargo Seller NPC/terminal.
- Seller shows cargo products and quantity selection.
- Player can buy cargo up to a global per-player cap of 5 owned crates.
- Purchased cargo spawns as physical crates with fixed route metadata (origin + one destination buyer).
- Player carries cargo in-hand with carry animation.
- Player can drop cargo in world.
- Dropped cargo sticks/welds to touched surface (including ship floors) for transport stability.
- Any player can pick up dropped cargo.
- If non-owner picks up cargo, cargo becomes permanently stolen.
- Player sells cargo at buyers:
  - Normal buyer: only accepts matching destination route.
  - Black market buyer: accepts broad cargo rules and pays purchase price only.

## UI Requirements
- Seller interaction UI:
  - Product list (cargo type, purchase price, sell price/destination indicator).
  - Quantity selector constrained by remaining cargo slots (max 5 total).
  - Clear error for slot cap reached.
- Permit prompt UI:
  - If seller requires permit and player lacks it, show buy permit prompt with price.
  - Success/failure credit feedback.
- Buyer interaction UI:
  - Sell prompt when valid cargo is in context.
  - Expected payout shown before confirmation.
  - Rejection reason text (wrong destination, stolen not accepted, already sold, invalid cargo).
- Optional route hint:
  - Destination buyer + planet in cargo tooltip/inspect panel.

## Core Mechanics
1. Purchasing Cargo
- Server validates credits, permit requirements, and remaining cargo slots.
- Purchase deducts credits and spawns crate(s) with authoritative metadata.
- Each crate gets a unique CargoId and one assigned destination buyer.

2. Carry / Drop Loop
- Carry state toggles when player picks up or drops cargo.
- Carry animation plays while carrying.
- Drop action places cargo at valid nearby location.
- Cargo is physically attached/welded to target surface to prevent drift during transport.

3. Metadata & Authority
- Server owns cargo metadata and sale truth.
- Required metadata:
  - CargoId
  - CargoType
  - OriginSellerId
  - DestinationBuyerId
  - PurchasePrice
  - SellPrice
  - OriginalOwnerUserId
  - CurrentHolderUserId (optional)
  - IsStolen
  - PlanetOfOrigin/PlanetTag (optional)
  - Status (Owned/Dropped/InTransit/Sold)

4. Selling Rules
- Normal buyer accepts only cargo where `DestinationBuyerId` matches buyer.
- Black market accepts broad cargo and pays exactly `PurchasePrice`.
- Sale consumes cargo and records CargoId as sold/consumed to prevent resale/duplication.

5. Permit Gating
- Sellers can require permit IDs.
- Permit purchase deducts credits and permanently grants permit to player.
- Multiple permit categories supported (planet, tier, legality).

6. Theft Rules
- Dropped cargo can be picked up by others.
- If non-owner picks up cargo, `IsStolen = true` permanently.
- Recommended: normal buyers reject stolen cargo; black market is theft outlet.

7. Cross-Planet / Cross-Server Continuity
- Cargo retains identity + metadata across teleport/server transitions.
- Destination may be local or remote planet/server.
- 5-cargo ownership limit applies globally across servers.

## Instances & Scope
- Cargo entities: per crate, many concurrent per server.
- Ownership and permit state: per player, persistent.
- Sold CargoId history: persistent (or durable anti-dupe strategy) for server-trust sale validation.
- Cross-server persistence required for owned cargo continuity.

## Edge Cases & Abuse Scenarios
- Buy spam at cargo cap boundary (must hard-stop at 5 total).
- Attempted client-side price/destination tampering.
- Double-sell race on same CargoId.
- Selling far from buyer (must require proximity check).
- Disconnect while carrying cargo.
- Disconnect while cargo is dropped on moving ship.
- Cross-server transfer duplication attempts.
- Replaying stale client sell requests.

## Integration with Existing Systems
- Economy/Credits: purchase, permit purchase, and sale flows.
- Inventory/carry handling: player carried item slot/state.
- Animation/character state: carry animation.
- Vehicle/ship physics: drop-to-surface weld/stick behavior.
- Travel/teleport: owned cargo persistence and reconstruction.
- UI prompt system for seller/buyer/permit interactions.
- Optional future integration with crime/reputation/wanted.

## Security Concerns
- Server-authoritative validation for all buy/sell/permit/cargo state transitions.
- Client cannot set or mutate cargo value, destination, stolen state, or sale validity.
- Unique CargoId + consumed/sold registry required to block duplication/resale exploits.
- All seller/buyer interaction checks require server-side proximity and validity checks.

## Performance Concerns
- Potentially high count of physical welded cargo on ships and in hubs.
- Frequent interaction prompts near clustered sellers/buyers.
- Cross-server persistence I/O cost for cargo + permits.
- Need bounded metadata writes and anti-spam interaction throttling.

## Testable Success Conditions
1. Purchase limit: Player owning 5 cargo cannot buy additional crates from any seller.
2. Purchase integrity: Successful purchase deducts credits and creates crates with complete metadata.
3. Route lock: Normal buyer accepts only crates with matching `DestinationBuyerId`.
4. Profit rule: Normal sale pays `SellPrice`, and `SellPrice > PurchasePrice` for configured profitable routes.
5. Black market rule: Black market sale pays exactly `PurchasePrice`.
6. Theft flagging: Non-owner pickup permanently sets `IsStolen = true`.
7. Theft routing: With recommended rule enabled, normal buyers reject stolen cargo.
8. Physical stability: Dropped cargo remains attached/stable on moving ship floors.
9. Anti-dupe: Sold cargo cannot be sold again using same CargoId.
10. Permit gate: Permit-locked seller blocks purchase until permit is bought.
11. Permit persistence: Purchased permits remain available across rejoin/server change.
12. Cross-server cargo continuity: Owned cargo remains valid with same metadata after planet travel.
13. Global cap continuity: Cross-server ownership still enforces max 5 cargo total.
14. Disconnect policy (v1): Cargo follows owner session-owned list and restores consistently without dupes.

## Open Questions / Locked Choices for v1
- Locked recommendation: normal buyers reject stolen cargo.
- Locked recommendation: black market payout equals `PurchasePrice`.
- Locked recommendation: disconnect handling uses owner session-owned cargo list restoration policy.
- Future (not v1): dynamic taxes, faction/reputation pricing modifiers, combat/sprint restrictions while carrying.
