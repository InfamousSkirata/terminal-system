# Codex Instructions

**You are the architect AND the builder.** You design passes, build them, and prove them correct. One AI does the full cycle.

If this is your first conversation on this project, read `pipeline/overview.md` once for context.

## The Cycle

```
Idea → Roadmap → [Design → Build → Prove] × N → Ship
```

You handle every step. The user orchestrates, tests in Studio, and tunes config values. They have minimal Luau/Roblox scripting knowledge — you carry the technical burden.

---

## One-Time Stages

### Idea
When user says "starting idea": follow `pipeline/idea.md`, write to `projects/<name>/idea-locked.md`

### Roadmap
When user says "build the roadmap": follow `pipeline/roadmap.md`, write to `projects/<name>/feature-passes.md`

These happen once per project before the pass cycle begins.

---

## Starting a Pass

Every pass has three phases: **Design → Build → Prove.** Do them in order. Don't skip ahead.

### Phase 1: Design This Pass

Follow `pipeline/design.md`. Your job:

1. Read `projects/<name>/state.md` — find which pass is next, read build deltas from previous passes
2. Read `projects/<name>/feature-passes.md` — what this pass includes
3. Read the actual code in `projects/<name>/src/` — this is your source of truth. NOT previous design docs. The code is reality.
4. Read build deltas in state.md — design against what actually exists, not what you planned
5. Follow the full design process in `pipeline/design.md` (integration pass, golden tests, test packet, etc.)
6. Write the design to `projects/<name>/pass-N-design.md`
7. Update `projects/<name>/state.md` and `projects/<name>/golden-tests.md`
8. Tell the user: **"Pass N design is ready. Review it, then tell me to build."**

**Your design must be specific enough to build from without guessing** — exact file names, function signatures, data structures, integration points. You're writing it for yourself, but write it like someone else will read it. Future-you in a new session needs this to be unambiguous.

### Phase 2: Build This Pass

Follow `pipeline/build.md`. Your job:

1. **Run preflight check** (verify Rojo serving, MCP connected, spot-check sync)
2. Build what the design doc specifies, one step at a time
3. Checkpoint before testing: `git add -A && git commit -m "checkpoint: pass N step [name] pre-test"`
4. Test each step via MCP (see testing procedure below)
5. After each step passes automated tests → ask user for visual check
6. When all steps pass → tell user all steps are built, ready for golden tests

### Phase 3: Prove This Pass

Follow `pipeline/prove.md`. Your job:

1. Give the user a golden test checklist (this pass + all previous passes)
2. User runs tests in Studio and reports results
3. Fix any issues found
4. Clean up all AI build prints
5. Write build delta to state.md
6. Commit and push
7. Tell the user: **"Pass N complete. Ready to design pass N+1 when you are."**

---

## MCP — When and How to Use It

You have access to Roblox Studio via the `robloxstudio-mcp` server. **MCP is expensive and slow. Use it deliberately, not reflexively.**

### MCP has exactly two valid uses:

**1. Workspace manipulation** — creating/editing physical objects in Studio (Parts, Models, properties, attributes, tags). Use MCP tools like `create_object`, `set_property`, `set_attribute`, etc. when the design doc requires workspace setup. This is always allowed.

**2. Post-build playtesting** — verifying that a significant chunk of newly built code actually works. This means you've just finished building one or more complete build steps and need confirmation before moving on.

### MCP is NOT for:

- **Smoke tests.** Don't playtest "just to make sure things still work." If you didn't change anything, don't test.
- **Verification after cleanup.** Don't playtest after removing build prints or doing the wrap-up protocol.
- **Checking if Rojo synced.** Do one spot-check at preflight, then trust it.
- **Exploring the hierarchy.** Don't call `get_project_structure` or `get_children` to browse. You wrote the code — you know what's there. If you need to verify, use `get_script_source` on a specific file.
- **Double-checking.** If the test passed and the user confirmed visual check, it's done. Move on.

### When playtesting IS allowed:

- **After completing a build step** (or multiple related steps built together). This is the initial build verification.
- **After applying a bug fix.** You changed code, you need to verify.
- **When the user explicitly says to test.**

### When playtesting is NOT allowed:

- After a step already passed + user confirmed visual check. MCP is locked.
- During the Prove phase (user runs golden tests, not you).
- After wrap-up cleanup.
- "Just to be safe" — never.

### Batch builds, then test once

Don't test after every 10 lines. Build a complete logical unit (a full module, or a full build step from the design doc), then test. If the design doc has 3 independent modules in one step, build all 3, then test once.

### Playtest procedure (when allowed):

0. **Clear stale session:** Call `stop_playtest` once.
1. **Checkpoint:** `git add -A && git commit -m "checkpoint: pass N step [name] pre-test"`
2. **Test:** `start_playtest` → wait for `========== START READ HERE ==========` marker → `get_playtest_output` once → `stop_playtest`
3. **Match output against the Test Packet's pass/fail conditions.** Pattern-match only.
4. **If pass:** Tell the user it's ready for their visual check.
5. **If fail — classify:**
   - **Mechanical** (syntax error, missing require, typo, nil on code you just wrote): Fix one thing, retest. Max 1 attempt.
   - **Behavioral** (logic mismatch, contract violation, wrong data flow): Diagnose the root cause, write a fix, retest. Max 3 fix attempts before asking the user for help.

**No-regression rule:** If your fix breaks something previously passing, revert it immediately.

### MCP Efficiency Rules

- **Never call `get_project_structure` on broad roots** (`game`, `Workspace`, `ReplicatedStorage`) with depth > 2. Query specific paths only.
- **Playtest log budget: max 2 retrievals per test.** `get_playtest_output` is cumulative — each call returns ALL logs. Don't poll repeatedly.
- **Keep `Config.DiagnosticsEnabled = false`** during automated testing. Only pass-specific `[PN_TEST]` prints.
- **If logs exceed ~200 lines, reduce logging** before continuing.
- **All code lives in the repo.** Never edit Studio scripts directly — Rojo syncs repo → Studio.
- **Summarize findings.** Don't paste full raw log dumps. Report pass/fail + 1-2 supporting lines.

---

## Test Harnesses

When a pass needs runtime verification beyond simple print-matching, the design doc may specify a **test harness** — a temporary script that drives specific test scenarios.

### Rules for test harnesses:

- **Test harnesses live in the repo.** Create them as files in `src/` so they sync via Rojo. Never create Studio-only scripts.
- **They are temporary.** Like AI build prints, they get removed during wrap-up. They do not ship.
- **They are specified in the design doc's Test Packet.** Don't invent harnesses that aren't in the design.
- **They are simple.** A harness spawns a scenario, waits, checks results, prints pass/fail. It does not contain game logic.
- **Name them clearly.** `PassN_Test.luau` or similar. Put them in `src/server/TestHarness/` so they're easy to find and clean up.
- **They run once per playtest.** A harness should trigger after a delay, run its checks, print results, and stop. Not loop forever.

### When NOT to use a harness:

- If the test is just "does it print the right summary line" — AI build prints handle that.
- If the test requires visual judgment (looks right, feels right) — that's the user's job.
- If you're testing something you can verify from logs alone.

---

## Roblox Engine Gotchas

These are real engine behaviors that will burn you if you don't know about them:

- **PrimaryPart.CFrame cascades to anchored children.** When you set `model.PrimaryPart.CFrame` on a Model with anchored children, Roblox repositions ALL anchored children relative to PrimaryPart — overriding any per-part CFrame writes. Fix: reparent parts that need independent CFrame control to a separate Folder in Workspace (outside the Model hierarchy).

- **Client CFrame writes on server-anchored parts** are local-only and get overridden by the PrimaryPart cascade above. Moving parts out of the Model is the only reliable fix.

- **`execute_luau` during playtest reads the Edit DataModel**, NOT the runtime DataModel. You cannot inspect live game state via `execute_luau` while a playtest is running. Use AI build prints and `get_playtest_output` instead.

- **`.Touched` without debounce** fires dozens of times per contact. Always debounce.

- **`wait()` is deprecated.** Use `task.wait()`. Same for `spawn()` → `task.spawn()`, `delay()` → `task.delay()`.

---

## AI Build Prints

Add the temporary print statements **specified in the design doc's Test Packet.** Don't invent additional prints beyond what the Test Packet specifies.

- **Format:** `[PN_TEST] key=value` — pass-specific tag, one line per event, non-spammy
- **Markers:** Print `========== START READ HERE ==========` after a few seconds of startup
- **Summaries:** End each test window with `[PN_SUMMARY] key=value key=value`
- **Temporary.** Removed after the pass is proven. Not permanent diagnostics.

---

## Bug Fix Discipline

When a bug appears:

1. **Read diagnostics output first.** Evidence before action.
2. **If diagnostics don't cover this case, add logging first.**
3. **Then patch the code.** Smallest change that fixes the problem.
4. **One fix at a time.** Fix one bug, test, confirm. Then the next.
5. **Never mix bugfixes with feature additions or refactors.**
6. **Minimize blast radius.** Don't restructure surrounding code while fixing a bug.

If you're stuck after 3 attempts on the same bug, stop and tell the user what you've tried and what you think is happening. Let them decide next steps.

---

## Periodic Critic Review (every 3-5 passes)

When the user asks, or every 3-5 passes, run a full critic review on the entire codebase using `pipeline/checklists/critic-checklist.md`. This catches accumulated drift, tech debt, and contract looseness. Fix what you find before the next pass.

---

## Wrap-Up Protocol

When the user says **"do the wrap-up protocol"** (or anything similar), execute ALL of these in order:

### Step 1: Remove ALL testing artifacts

Search every file you touched this pass and remove:
- All `[PN_TEST]` print statements
- All `========== START READ HERE ==========` and `========== END READ HERE ==========` markers
- All `[PN_SUMMARY]` print lines
- All test probe scripts/modules
- Any `Config.DiagnosticsEnabled = true` you set — reset to `false`

**Keep:** Permanent diagnostics (`DEBUG_MODE`-gated logging, lifecycle reason codes, health counters).

**Do NOT run a verification playtest after cleanup.**

### Step 2: Write build delta to state.md

```
### Pass N Build Delta
**Built as designed:**
- [list what matched the design doc]

**Deviations from design:**
- [what changed and why]

**New runtime contracts:**
- [any new contracts, config values, or behaviors not in the original design]

**Non-blocking follow-ups:**
- [anything noticed but deferred]
```

### Step 3: Commit and push

```
git add -A && git commit -m "pass N complete: [name]" && git push origin main
```

### Step 4: Tell the user

```
Pass N complete. Ready to design pass N+1 when you are.
```

---

## Rules

- **Follow the design doc exactly during build.** Don't improvise, don't add things it doesn't specify.
- **Read code from disk before modifying.** Your memory drifts. The files are truth.
- **Design against real code, not specs.** The code + build deltas are truth.
- **One step at a time.** Don't build the next step until the current one passes testing.
- **File scope during build:** Only modify files listed in the current pass's design doc.
- **Stay scoped.** Only design what this pass needs. Don't anticipate future passes.
- **Be specific in designs.** Exact function signatures, exact data types, exact integration points.
- **Do not move on until bugs are fixed.** A broken module is a broken foundation.

## Code Standards

- Modern Luau (`task.wait()`, `--!strict` where practical)
- Server authority on sensitive operations, validate RemoteEvent args
- Use diagnostics module for lifecycle events, config for all tunables
- Clean up connections on player leave

## Rojo + MCP Coexistence

- **Rojo syncs code. MCP runs tests.** Different jobs.
- **Don't reconnect unnecessarily.** If both are working, leave them alone.
- **If sync looks wrong:** Spot-check (compare a repo symbol against `get_script_source`). If mismatch, ask user to verify Rojo.
