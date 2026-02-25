# Design (per pass)

## What You're Doing

Designing the technical architecture for one feature pass. This design must be detailed enough to implement without guessing, and it must integrate cleanly with the existing tested code from previous passes.

## Input

- `projects/<name>/feature-passes.md` — which pass you're designing and what it includes
- `projects/<name>/idea-locked.md` — the full feature spec (for reference)
- `projects/<name>/state.md` — current state, including build deltas from previous passes
- **Previous passes' code on disk** — the existing tested codebase. This is your source of truth.
- **Build deltas in state.md** — what actually changed vs what was planned in previous passes

## Process

### Step 1: Read Existing Code + Build Deltas

If this is pass 2+, read the actual code from previous passes AND the build deltas in state.md. Understand:
- What modules exist and what their real APIs are
- What data structures are actually used
- How modules actually communicate
- What config values exist
- **What changed from previous designs** — build deltas tell you where reality diverged from the plan

Do NOT rely on previous design docs as the source of truth. The code + build deltas are what's real.

### Step 2: Design This Pass

Cover everything relevant to this pass:

- **New files:** Name, location (server/client/shared), purpose
- **Modified files:** What's changing and why
- **New data structures and types**
- **New or modified APIs:** Exact function signatures
- **New RemoteEvents** (if any)
- **Data flow** for new behaviors
- **New config values** (with comments, defaults, ranges)
- **Script communication:** How new modules connect to existing ones
- **Security boundaries** (if this pass adds client-facing features)
- **Performance considerations** (if relevant to this pass)

Keep it focused. Don't redesign what's already working — just design what's new or changing.

### Step 3: Integration Pass

For every new piece of data or function call that crosses a module boundary:

1. **Where is it created?** Which module, which function, what type?
2. **How is it passed?** Argument, return value, RemoteEvent, shared state?
3. **Who receives it?** Which module, which function — check against REAL CODE signatures
4. **Where is it stored?** What table, what lifetime?
5. **When is it cleaned up?**

For every call site where new code calls existing code (or vice versa):
- Do the argument types match the real function signature?
- Is the return value handled correctly?
- If the function can return nil, is that handled?

**This is the most important step.** Checking new code against real, tested code is fundamentally more reliable than checking specs against specs.

### Step 4: Design Golden Tests + Test Packet

**Golden tests.** Define 1-3 specific test scenarios for the new functionality:
- **Setup:** What workspace layout, what config overrides
- **Action:** What happens
- **Expected:** Specific observable result
- **Pass condition:** What to check (visual + diagnostics)

Also note: which previous passes' golden tests should be re-run as regression checks.

**Test Packet.** For each build step, specify everything needed to build and test:

- **AI build prints:** Which events to print, what data each print includes, where to place markers, what the summary line reports. These are temporary — removed after the pass is proven.
- **Pass/fail conditions:** Exact patterns to match in the summary output per build step. Example: `PASS if [P5_SUMMARY] errors=0 AND spawned>=1`.
- **MCP procedure:** Default is the standard procedure (stop → start → wait for marker → get_output → stop). Only specify deviations from default.
- **Expected summary format:** The exact `[PN_SUMMARY] key=value key=value` format.

### Step 5: Update Diagnostics & Validators (if needed)

- New lifecycle reason codes for new behaviors
- New health counters if relevant
- New startup validator checks for new workspace contracts

### Step 5b: Self-Critique This Design

Self-critique the design against `pipeline/checklists/critic-checklist.md`. Scan it against the checklist items for correctness, security, and performance issues. Fix any blocking issues before proceeding.

### Step 6: Lock This Pass's Design

- Write to `projects/<name>/pass-N-design.md`
- Add new golden tests to `projects/<name>/golden-tests.md`
- Update `projects/<name>/state.md`: Step → Build, Status → ready
- Tell the user: **"Pass N design is ready. Review it, then tell me to build."**

## Exit Criteria

- [ ] All new/modified modules specified with exact APIs
- [ ] Integration pass complete — every cross-boundary data flow traced against real code
- [ ] Golden tests defined for new functionality
- [ ] Test Packet complete — AI build prints, pass/fail conditions, expected summary format
- [ ] Regression tests identified from previous passes
- [ ] Diagnostics/validators updated if new behaviors or workspace contracts added
- [ ] Config values extracted for any new tunables
- [ ] Self-critique done (zero blocking issues)

## Rules

- **Design against real code, not specs.** If pass 1 is built, read pass 1's code.
- **Read build deltas.** They tell you what was actually built vs what was planned.
- **Don't redesign what works.** Don't refactor unless this pass requires changes.
- **Stay scoped.** Only design what this pass's features need.
- **Be specific.** Exact function signatures, exact data types, exact integration points.
