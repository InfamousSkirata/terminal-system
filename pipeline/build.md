# Build (per pass)

## What You're Doing

Building one feature pass from the design doc you wrote. The code integrates with existing tested code from previous passes.

## Your Leverage

- **Pass design doc** (`pass-N-design.md`) — the blueprint you wrote
- **Existing code on disk** — proven foundation from previous passes
- **Config file** — tunable values, try these before code changes
- **Diagnostics module** — read the output before guessing at problems
- **Golden tests** (`golden-tests.md`) — exact pass/fail criteria

## Preflight Check (before any testing)

Run this every time before your first `start_playtest` in a session:

1. **Verify Rojo is serving.** Ask the user to confirm Rojo server is running and Studio plugin is connected.
2. **Verify MCP is connected.** Call a lightweight MCP tool (e.g., `get_children` on a known path) and confirm it returns data.
3. **Spot-check sync.** Pick a known symbol from a file you just edited. Use `get_script_source` via MCP to read the same file in Studio. Confirm they match. If they don't — stop and tell the user.

## Build Process

### Step 1: Determine Build Order

Read your pass design doc. If this pass adds multiple modules or modifies multiple files, determine the order:
- Foundation pieces first (shared modules, config additions)
- Dependencies before dependents
- Independent modules can be built in the same step

### Step 2: Build Loop (repeat for each build step)

#### 2a. Build this step.
Write the code specified in the design doc for this step.

#### 2b. Checkpoint before testing.
`git add -A && git commit -m "checkpoint: pass N step [name] pre-test"`

#### 2c. Automated test (via MCP) — only after a complete build step.

**MCP playtesting is allowed here, and ONLY here.** Do not playtest at any other time unless the user explicitly asks. See `codex-instructions.md` for the full MCP discipline rules.

**Build the full step first, then test once.** Don't test after every few lines. If multiple independent modules are in the same step, build all of them, then run one playtest.

1. Call `stop_playtest` first to clear any stale session.
2. Call `start_playtest`
3. Wait for `========== START READ HERE ==========` marker
4. Call `get_playtest_output` ONE TIME — this is cumulative, only call once.
5. Call `stop_playtest`
6. **Match output against the Test Packet's pass/fail conditions.**

**Keep global diagnostics OFF.** Only pass-specific `[PN_TEST]` prints should be active.

**No-regression rule.** If a fix breaks something previously passing, revert immediately.

**After this step passes + user confirms visual check, MCP is locked.** No smoke tests. No "let me verify one more time." Done means done.

#### 2d. If automated tests fail:

**Mechanical failures** (syntax error, missing require, typo, nil on code you just wrote):
1. Fix one thing, retest. **Max 1 mechanical fix attempt.**
2. If still failing, treat as behavioral.

**Behavioral failures** (logic mismatch, contract violation, wrong data flow):
1. Read diagnostics output first.
2. Diagnose the root cause.
3. Write the smallest fix that addresses it.
4. Retest.
5. **Max 3 fix attempts.** If still failing, stop and tell the user what you've tried and what you think is happening.

#### 2e. If automated tests pass → user visual check.
Tell the user: **"Step [name] passes automated tests. Ready for your visual check in Studio."**

#### 2f. PASS → move to next step.

### Step 3: All Steps Built

When all modules for this pass are built and individual tests pass:
- Tell the user all steps are built and passing
- The user runs golden tests in Studio and reports results
- **Do NOT run MCP golden tests automatically.** The user decides.
- If issues found, fix them
- When everything passes → move to Prove

## AI Build Prints

Temporary print statements that exist ONLY during the build step so you can read what the code does at runtime. NOT the same as permanent diagnostics.

**Rules:**
- **Structured and tagged:** `[TAG] key=value` format. One line per event.
- **Non-spammy:** Print on events, not every frame.
- **Marker scripts:** Wait a few seconds then print `========== START READ HERE ==========`.
- **Summary prints:** `[SUMMARY] spawned=12 despawned=4 errors=0`
- **Temporary.** Removed after the pass is proven.

## Bug Fix Discipline

- **Do not move on until the bug is fixed.**
- **Minimize blast radius.** Don't restructure while fixing.
- **One fix at a time.** Fix, test, confirm. Then next.
- **Never mix bugfixes with feature additions.**
- **Instrument first.** Read diagnostics, add logging if needed, then patch.

## Change Discipline

Each interaction is ONE of:
- **Bugfix** — something doesn't work
- **Tuning** — values need adjusting
- **Design change** — behavior needs to work differently (update design doc first)

Never mix these.

## Codex Checkpoints

Tell the user at these moments:
- If unsure about a design decision during build
- If stuck on a bug after 3 fix attempts
- When all modules are built — for Prove step
