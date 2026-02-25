# Pipeline Overview

This is a cyclic development pipeline for Roblox game systems using one AI model:
- **Codex CLI (GPT 5.3):** Architect, builder, critic, and debugger

The human user has minimal Luau/Roblox scripting knowledge. The AI carries the technical burden. The user orchestrates, tests in Roblox Studio, and tunes config values.

## Structure

**Idea → Roadmap → [Design → Build → Prove] × N → Ship**

### One-time stages
- **Idea** — define what the system does. All features, mechanics, edge cases, UI. Lock it.
- **Roadmap** — divide features into ordered passes. Pass 1 is bare bones. Optimizations are last.

### Per-pass cycle (repeat for each feature pass)
- **Design** — Codex architects this pass against real tested code from previous passes. Integration pass traces data across modules. Golden test scenarios defined.
- **Build** — Codex implements from its own design doc. Tests each step via MCP during the initial build loop and matches results against pass/fail conditions. Mechanical failures get 1 self-fix attempt. Behavioral failures get up to 3 diagnosis-and-fix attempts before asking the user for help.
- **Prove** — The user runs golden tests in Studio (this pass + all previous = regression check) and reports results. Codex cleans up AI build prints, writes a build delta, commits, pushes, and moves to the next pass's design.

### Ship
When all passes are proven. Final critic review on the full codebase.

## Why It's Cyclic

Building the entire system from one massive architecture (waterfall) fails because the architecture is designed against specs, not against working code. By the time you build module 10, modules 1-9 behave differently than the spec predicted. Bugs compound and become irreversible.

The cyclic approach designs each pass against real, tested code from previous passes. Each pass is small enough to prove correct before moving on. If something breaks, the blast radius is one pass, not the whole system.

## Key Concepts

- **Architecture-as-contract:** Codex always builds from a validated design doc, not from vibes or verbal instructions.
- **Build deltas:** After each pass, Codex documents what actually changed vs what was designed. These inform the next pass's design.
- **Golden tests:** Specific test scenarios with exact expected outcomes. They accumulate across passes and serve as regression tests.
- **Diagnostics module:** Built-in logging (lifecycle reason codes, health counters, per-entity trails). Makes debugging evidence-based instead of speculative.
- **Startup validators:** Check workspace contracts at server start, fail loud if something's wrong.
- **Config extraction:** Every tunable value in a config file. User adjusts these directly without AI tokens.
- **Test Packet:** Each design doc includes a Test Packet — AI build prints, exact pass/fail conditions, and MCP procedure. Pattern-match against these during testing.
- **MCP testing (gated):** Codex connects to Roblox Studio through the `robloxstudio-mcp` server. MCP testing is allowed during the initial build loop. After that, MCP is locked — the user tests in Studio and only re-enables MCP by explicitly saying "test it" or reporting an error.
- **AI build prints:** Temporary, structured print statements (`[TAG] key=value`) specified in the Test Packet. Removed after each pass is proven.
- **Critic reviews are periodic, NOT per-pass.** Full critic review on the entire codebase every 3-5 passes.

## File Layout

```
codex-instructions.md           # Codex's rules (re-read every session)
ACTION-MAP.md                   # Human user's workflow reference
pipeline/
├── overview.md                 # This file (read once)
├── idea.md                     # Idea stage instructions
├── roadmap.md                  # Roadmap stage instructions
├── design.md                   # Design step instructions (per pass)
├── build.md                    # Build step instructions (per pass)
├── prove.md                    # Prove step instructions (per pass)
├── checklists/
│   └── critic-checklist.md     # Critic review rubric
└── templates/                  # Templates for project files
projects/<name>/
├── state.md                    # Current position + build deltas
├── idea-locked.md              # Locked idea
├── feature-passes.md           # Ordered pass roadmap
├── pass-N-design.md            # Design doc per pass
├── golden-tests.md             # Accumulating test scenarios
├── build-notes.md              # Final ship output
└── src/                        # The codebase
```
