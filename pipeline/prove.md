# Prove (per pass)

## What You're Doing

Confirming that this feature pass works correctly and hasn't broken anything from previous passes. Once proven, this pass becomes locked foundation for future passes.

## Process

### Step 1: User Runs Golden Tests

The **user** runs golden tests in Studio — not you via MCP. You provide the checklist, the user plays and reports back.

Give the user a clear checklist from `projects/<name>/golden-tests.md`:
- This pass's golden tests (new functionality works)
- All previous passes' golden tests (no regressions)
- For each test: what to set up, what to do, what to look for

The user plays, observes, and reports results. **Only use MCP if the user explicitly says to.**

### Step 2: User Diagnostics Health Check

Tell the user to enable DEBUG_MODE and play for a few minutes. They check:
- Active entity counts: stable, or drifting?
- Spawn/destroy rates: balanced?
- Failure/reject counts: any unexpected failures?
- Per-entity trails: do they show the expected lifecycle?
- Any new warning or error messages?

The user reports what they see. You fix if needed.

### Step 3: Regression Check

The user verifies that behaviors from previous passes still work correctly. If a regression is found: **blocking issue.** Fix it before this pass can be locked.

### Step 4: Clean Up AI Build Prints

Remove all temporary AI build prints:
- All `[TAG] key=value` print statements
- All `START READ HERE` / `END READ HERE` markers
- All `[SUMMARY]` print lines
- All test probe scripts

**Keep** permanent diagnostics (`DEBUG_MODE`-gated logging, lifecycle reason codes, health counters).

**Do NOT run a verification playtest after cleanup.**

### Step 5: Build Delta + Commit

**Write the build delta** to `state.md`:

```
### Pass N Build Delta
**Built as designed:**
- [what matched the design doc]

**Deviations from design:**
- [what changed and why]

**New runtime contracts:**
- [new contracts, config values, or behaviors not in the original design]

**Non-blocking follow-ups:**
- [anything noticed but deferred]
```

**Commit and push:**
```
git add -A && git commit -m "pass N complete: [pass name]" && git push origin main
```

### Step 6: Lock This Pass

- Update `state.md` with build deltas and next pass info
- The code on disk is now **proven foundation** for the next pass
- Tell the user: **"Pass N complete. Ready to design pass N+1 when you are."**

## Exit Criteria

- [ ] All golden tests pass (this pass + all previous)
- [ ] Diagnostics health check clean
- [ ] No regressions on previous pass behavior
- [ ] AI build prints removed
- [ ] Build delta documented in state.md
- [ ] Code committed and pushed
- [ ] state.md updated for next pass

## Periodic Full Critic Review

Every 3-5 passes, run a full critic review on the entire codebase. This catches accumulated drift, tech debt, and patterns going stale.

## Rules

- **Don't skip regression tests.** Each pass builds on proven code.
- **Don't move on with a known regression.** Fix it in this cycle.
- **Config tuning is still free.** No cycle needed for config tweaks.
- **Build deltas are mandatory.** You can't design the next pass accurately without knowing what you actually built.

## If This Is The Last Pass → Ship

When all feature passes are proven:
1. Run all golden tests one final time
2. Run full critic review on the complete codebase
3. Write `projects/<name>/build-notes.md`
4. Final commit and push
5. Update `state.md`: Stage → Complete
6. System is done
