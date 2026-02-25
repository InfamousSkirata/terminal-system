# Pipeline Action Map — What You Do

## Setup
```bash
cd ~/roblox-pipeline
bash pipeline/new-project.sh <system-name>
```

### MCP Prerequisites (one-time)
- **Codex CLI:** `robloxstudio-mcp` is configured in `~/.codex/config.toml`. Codex auto-launches it.
- **Roblox Studio:** Install the [boshyxd MCP plugin](https://create.roblox.com/store/asset/132985143757536). Enable "Allow HTTP Requests" in Game Settings > Security.

---

## Idea (You + Codex)

1. Open Codex CLI from your pipeline folder
2. Tell Codex: **"Read codex-instructions.md. Starting idea for <system-name>"**
3. Describe your idea, answer questions, push back if you disagree
4. When done: **"Lock it"**

**Done when:** `idea-locked.md` exists.

---

## Roadmap (Codex, mostly hands-off)

1. Tell Codex: **"Build the roadmap for <system-name>"**
2. Codex divides features into ordered passes
3. Review the passes — reprioritize if you want
4. Approve

**Done when:** `feature-passes.md` exists.

---

## Passes (repeat for each pass)

### Design (Codex)
1. Tell Codex: **"Design pass N for <system-name>"**
2. Codex reads existing code + build deltas, designs this pass, self-critiques
3. Review `pass-N-design.md` — ask questions if anything seems off
4. When happy: **"Build it"**

### Build (Codex — mostly hands-off)
1. **Make sure Roblox Studio is open** with the MCP plugin connected and Rojo serving
2. Codex builds step by step, testing automatically via MCP
3. You watch or do something else — Codex handles the build-test loop
4. **Codex asks you for a visual check** when automated tests pass. Play the game, check it looks/feels right.
5. If something looks wrong: tell Codex what you see
6. If Codex is stuck after 3 fix attempts: help troubleshoot or simplify the approach
7. When all tests pass and you're happy → **"Do the wrap-up protocol"**

### Prove (You test, Codex wraps up)
1. Codex gives you a golden test checklist
2. You play in Studio, run through the tests, report results
3. If issues: Codex fixes → you retest
4. When all pass: **"Do the wrap-up protocol"**
5. Codex cleans up, writes build delta, commits, pushes
6. Ready for the next pass: **"Design pass N+1"**

---

## The Flow

```
You tell Codex to design → Codex writes design doc
↓
You say "build it" → Codex builds + tests via MCP
↓
You do visual checks → Codex fixes if needed
↓
You run golden tests → Codex wraps up
↓
You say "design pass N+1" → (repeat)
```

One AI, one conversation flow. No copy-pasting between tools.

---

## Config Tuning (You, no AI needed)

At any point during testing:
1. Open Config.luau
2. Adjust values for anything that feels off
3. Re-test
4. **Exhaust config before going back to AI**

---

## Periodic Structural Review (every 3-5 passes)

1. Tell Codex: **"Full structural review for <system-name>"**
2. Codex runs critic on the entire codebase
3. Codex fixes issues
4. Continue with the next pass

---

## Ship

When all passes are proven:
1. Tell Codex: **"Ship <system-name>"**
2. Codex does final review, writes build-notes.md
3. Final commit and push
4. Done

---

## If Rate Limit Hits

- Stop. State is saved to state.md.
- When limit resets: **"Resuming pass N [design/build/prove] for <system-name>"**

---

## If Codex Is Stuck

- If Codex can't fix a bug after 3 attempts, it'll tell you
- Help troubleshoot: describe what you see in Studio, share error logs
- Consider simplifying the approach or deferring the feature

---

## The Pattern
```
Idea → Roadmap → [Design → Build → Prove] × N → Ship
```
