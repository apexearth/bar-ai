# docs/ — what each file answers

Pick one. Do not read them all.

Everything here is dated and provisional. `CLAUDE.md` is the working guide, the
`.claude/skills/ai-*` skills own how the live AI actually decides things, and
`ISSUES.md` is what is currently wrong. **When a doc and the code disagree, the
code wins** — say so and fix the doc rather than reasoning from it. **When a doc
and [23 — The plan](23-the-plan.md) disagree about what the AI should be doing,
the plan wins** — a doc that still argues from a threshold, a build order or a
cap is describing an AI we are trying to stop being.

## Start here

| Doc | The question it answers |
|---|---|
| [23 — The plan](23-the-plan.md) | **What the AI is trying to do at all** — name a target state, take the fastest path to it, hold army and defence at their share of the economy. Two paragraphs. Read before anything else, including this table. |
| [24 — How units fight](24-how-units-fight.md) | **How the army is to fight**, in apexearth's own directives only: the no-turret five-minute test and its metrics, the scout-call-regroup-strike play, hunting with fast units, and the verified flanking-damage mechanic. Read before touching any C++ fighter task or `manager/military/`. |
| [10 — BAR game concepts](10-bar-game-concepts.md) | How does the game actually work — the two resources, the economic ladder and why its rungs are reached by exhausting the cheaper growth rather than by crossing an income, why the commander decides games. **Read before diagnosing anything.** |
| [21 — Simplification](21-simplification.md) | Why do changes here so often have no effect? Twelve multiplicative price terms, 404 tunables, and the instruments now in place to see which one carried a decision. |
| [22 — Macro demand](22-macro-demand.md) | The root architectural finding: every market proposer takes a constructor, so the AI never asks "what does the base need". The inversion, and how far it has landed. |
| [20 — Brain overhaul](20-brain-overhaul.md) | The 2026-08-22 mandate that killed all leaf build logic. Kept because it is the kill census `check.py` enforces, and the record of what was deliberately deleted. |

## Environment and mechanism

| Doc | The question it answers |
|---|---|
| [01 — Local environment](01-local-environment.md) | What is installed on this machine, where the engine and game trees are, and why `BAR.sdd` is not what the game plays. |
| [02 — AI landscape](02-ai-landscape.md) | Every way to put an AI into BAR (native C, CircuitAI, LuaAI), which are dead ends, and which to pick. |
| [03 — BARb architecture](03-barb-architecture.md) | How config, script and DLL fit together; shortName vs version vs profile, and why a version-only variant silently plays as stock in multiplayer. |
| [05 — AngelScript API](05-angelscript-api.md) | The hooks, globals and types available to script; what the bindings do and do not expose. |
| [06 — Building the DLL](06-building-the-dll.md) | The C++ path end to end — the Docker build loop, the artifact, and how deploy picks it up. |
| [19 — Factory engine mechanics](19-factory-engine-mechanics.md) | What the engine does underneath a factory order: why a recruit task wipes the queue, the SHIFT x5 trap, the bound surface, and why reads lag sends. |

## Configuration

| Doc | The question it answers |
|---|---|
| [04 — JSON config reference](04-json-config-reference.md) | Which JSON files still decide anything after the overhaul (mostly `behaviour.json`), and which are inert. |
| [17 — behaviour.json](17-behaviour-config.md) | What each `quota` / `retreat` / `defence` knob means, traced from the parser to the C++ line that consumes it. |
| [11 — Dead unit references](11-dead-unit-references.md) | Why a unit name can be real and still be a no-op, and which stock references do not resolve. |

## Method

| Doc | The question it answers |
|---|---|
| [25 — Silent failures](25-silent-failures.md) | The eighteen ways something here fails without saying so, keyed **S1–S18** by CLAUDE.md's router: the mechanism, the date it was measured, and the wrong conclusion it produced. Also the three findings that set the method — "the path fires" is not evidence, instrument first, and the frame budget. |
| [26 — Working rules](26-working-rules.md) | How to work in this repo: the policy line you must not cross alone (caps, exclusivity, thresholds, tunables), harness and Windows process traps, comment discipline, delegation, and apexearth's own workflow. |
| [27 — Tunable rationale](27-tunable-rationale.md) | Why each default is the number it is, keyed by `TUNE_` name: the measurement, the A/B that failed, the ruling. The long form that `tunables.as` used to carry inline; the file itself now runs one line per knob. |
| [07 — Headless testing](07-headless-testing.md) | How to drive the engine by hand — start script fields, speed, flags — and why ten games resolves nothing. |
| [16 — Big plays](16-big-plays.md) | Why the late game should produce moments; the silo/anti-nuke cadence arithmetic that sets the salvo size, and how to judge a "moment" when win rate cannot. |

## The outside world

Dated snapshots of other people's code. Nothing here describes our AI.

| Doc | The question it answers |
|---|---|
| [09 — Resources](09-resources.md) | Every URL worth keeping — repos, engine docs, tooling, the replay API. |
| [13 — Other AIs](13-other-ais.md) | `Felnious/Skirmish` read closely at commit `d765a46` (2026-08-08): what it is, what is worth stealing, what we already do better. |
| [14 — BAR AI landscape](14-bar-ai-landscape.md) | Who else is building BAR AI (2026-08-08), what the community believes about AI weaknesses, and what is not in the public record. |

## Deleted, so you do not go looking

- **08 — ML and RL** — a survey of an RL path never taken. The replay-API detail
  worth keeping moved into [09](09-resources.md).
- **12 — Build phases** — the BUILD_PHASE design. It shipped as
  `Factory::ComputePhase`, and the overhaul deleted `factory/phase.as`. Nothing
  in the live variant computes a build phase.
- **15 — Tunables** — a hand-maintained registry that went stale faster than it
  could be updated (20 of ~40 names had no reader). The live list is
  `game-patches/gadgets/dev_tunables.lua` + `tunables.as`, and
  `tools/dashboard_audit.py` (run by `check.py`) is what keeps them honest.
- **18 — The Brain** — the 2026-08-10 arbiter design. Every structure it
  described (`brain/mix.as`, `Score() = value/(1+have)/cost`, the `apex: brain
  picks` lines) was removed by the overhaul. See [20](20-brain-overhaul.md) for
  the history and the `ai-auction` skill for the live market.
- **19 — Factory through Brain** — an 859-line session log. Its verified engine
  mechanisms survive as [19 — Factory engine mechanics](19-factory-engine-mechanics.md).
