# Feature Passes: Cargo System

**Based on:** idea-locked.md
**Date:** 2026-02-24

---

## Pass 1: Bare Bones Cargo Loop
**What it includes:**
- Server-authoritative cargo purchase from seller with credits deduction.
- Max 5 owned cargo limit enforcement (single server baseline behavior).
- Physical crate spawn with required metadata (`CargoId`, type, prices, origin seller, destination buyer, owner, status).
- Carry + drop loop with in-hand carry state and basic carry animation hook.
- Drop-to-surface stick/weld behavior so cargo remains stable on moving ship floors.
- Normal buyer sale validation (`DestinationBuyerId` match) and payout at `SellPrice`.
- Anti-dupe sale consumption: sold `CargoId` cannot be sold again.
- Core interaction validation (proximity + valid cargo checks).

**After this pass, the system:**
Players can buy cargo, physically transport it, and complete a normal profitable delivery on the assigned route with server-validated anti-dupe protection.

---

## Pass 2: Theft + Black Market Rules
**Depends on:** Pass 1
**What it includes:**
- World pickup by any player for dropped cargo.
- Permanent `IsStolen = true` when non-owner picks up cargo.
- Black market buyer support that accepts cargo under configured rule set and pays exactly `PurchasePrice`.
- Recommended routing lock: normal buyers reject stolen cargo.
- Buyer rejection reason coverage for wrong destination / stolen / already sold / invalid.

**After this pass, the system:**
Cargo theft is possible, stolen cargo is routed to black market, and theft converts cargo value without creating profit beyond the original purchase cost.

---

## Pass 3: Permit Gating + Seller/Buyer UX
**Depends on:** Pass 1, 2
**What it includes:**
- Permit definitions and persistent per-player permit ownership.
- Permit-required sellers block cargo purchases without permit.
- Permit purchase prompt flow with credit deduction and grant.
- Multi-permit category support shape (planet/tier/legality mapping in data/config).
- Seller UI pass for product list + quantity selector constrained by remaining slots.
- Buyer UI pass for expected payout display + clear rejection messages.
- Optional cargo route hint display (destination buyer/planet label).

**After this pass, the system:**
Players can see clear buy/sell info in UI, unlock gated seller networks through permits, and trade within explicit access rules.

---

## Pass 4: Cross-Server Cargo Continuity
**Depends on:** Pass 1, 2, 3
**What it includes:**
- Persistent cargo ownership/state model for teleport/hyperspace travel.
- Cargo metadata continuity across server transitions (identity, values, route, stolen state).
- Global max-5 owned cargo enforcement across servers.
- Disconnect policy implementation for v1: cargo follows owner session-owned list and restores consistently without duplication.
- Permit persistence validation across rejoin/server changes.

**After this pass, the system:**
Players can transport valid cargo between planets/servers without losing route integrity, while ownership limits and anti-dupe constraints remain enforced globally.

---

## Pass 5: Hardening, Abuse Defenses, and Data Contracts
**Depends on:** Pass 1, 2, 3, 4
**What it includes:**
- Race-safe sale and purchase transaction guards for spam/concurrency.
- Replay/stale request protections for buy/sell remotes.
- Strong server-side immutability enforcement for client-visible cargo metadata.
- Expanded validation/error pathways for all edge cases identified in idea doc.
- Contract checks for integration points (economy, carry state, travel persistence).

**After this pass, the system:**
The cargo economy loop is production-safe against common exploit paths (double-sell, tampering, race abuse, stale requests) with explicit server contracts.

---

## Final Pass: Optimization
**Depends on:** All previous passes
**What it includes:**
- Performance tuning for high cargo density (physics load, weld strategy, cleanup cadence).
- Interaction/UI throttling for crowded hubs.
- Persistence I/O batching/caching where safe.
- Non-functional profiling and hotspot reductions without changing gameplay behavior.

**After this pass, the system:**
Keeps identical player-facing behavior with better runtime performance and scalability under heavier server load.
