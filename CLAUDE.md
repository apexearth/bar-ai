# bar-ai — working notes for Claude

AI development for **Beyond All Reason**, the RTS on the **Recoil** engine (a Spring fork). This
repo is the source of truth for a custom AI; the live game install is a deploy target.
`tools/bar_env.py` resolves every path at runtime; never hardcode one.

**This file is an index.** Five documents hold the rest, and each is authoritative over a summary
here:

| | |
|---|---|
| `docs/doctrine.md` | his directives only: goals, Do, Never, facts of the game |
| `docs/how-it-works.md` | what the AI is and how each part decides, current code only |
| `docs/working.md` | rules of work, commands, lanes, machine limits, testing, building, releasing |
| `docs/traps.md` | the S-numbered silent failures, one line each with its check |
| `docs/tunables.md` | why a default is what it is, keyed by `TUNE_` name |

## The one idea

Every decision answers: **what is the fastest path to the state we are trying to reach?** The AI
names a target and takes the move that makes it arrive soonest, with army and defence held at
their share of the economy we have built. Order, numbers and limits are OUTPUTS: a threshold,
build order or cap in this AI is a bug wearing a fix's clothing. Economy is energy, generators and
conversion as much as extractors (spots are fixed and few; conversion runs ~60 E per metal), and
his core tenet is: always be making economy. The nets decide; balances are theirs to discover.

## Rules that govern a session

- **Instrument first**; "the path fires" is not evidence; two seeds cannot resolve a change. If the instrument shows the decision did not move, say so.
- **Ask before inventing policy** (caps, exclusivity, switching a behaviour off, thresholds). Derive from the economy or ask him; a tunable is the last resort.
- **Price the cost before writing code an election calls**, and spread work across frames.
- **Write far fewer comments than feels natural**; findings go in the commit message or `ISSUES.md`.
- **Never author Python in a Bash heredoc**: `Write` a script, then run it.
- **Work directly**; an agent only when he asks or for a broad search.
- **Claim a lane** (`python tools/lane.py init <name>`) before building, deploying or running; `Apex:Unstable` is his slot.
- **Count every running engine** before launching one; his game sets the limit (`working.md`).
- Load the owning skill instead of reading the source tree; exclude `vendor/`, `matches/`, `changes/`, `reference/` from repo-wide searches.

## Before you do X, read Y

| About to… | Read first |
|---|---|
| judge any run | `review.py <run>` (gate 1 = compiled, ran, no crash); `bar-benchmark` skill |
| say why a game was won or lost | `story.py <match> --bucket 120`, then `minutes.py <match>` on a WIN and a LOSS; `mapframe.py` to see it |
| believe a match result | traps S3, S12, S15, S16, S17, S19, S29, S34 |
| run a sweep of a tunable | trap S8: deploy the gadget, not only the AI |
| launch or kill a run | `working.md` (lanes, machine limits, testing) |
| touch army / fighting | `doctrine.md`, then `ai-military`, `ai-army-composition`, `fight-analysis` |
| touch what gets built | `ai-auction`, `ai-eco-pricing`, `how-it-works.md` (market, factories) |
| touch where buildings land | `ai-placement`, `ai-risk-model` |
| touch builders / crews | `ai-builder-crew`; trap S14 (AiMakeTask re-elects) |
| count factories, tasks or in-flight builds | `async-sim-orders`; trap S13 |
| read a unit's cost or buildoptions | `tools/unitdef.py`; traps S10, S11 |
| add a gate, target, prior or role rule | `ai-couplings`, then "Ask before inventing policy" |
| add a tunable or a want kind | `dashboard-ui`; one line in `tunables.as`, the reasoning in `tunables.md` |
| change a default | `tunables.md` (several are measured-and-left-off) |
| write AngelScript | `how-it-works.md` (script API); traps S4, S5, S18; `as_scope.py` |
| touch C++ or build the DLL | `cpp-dll` skill; `python tools/build_dll.py` (S54) |
| build on an engine binding | traps S7, S9, S28 |
| create or rename a variant | trap S1 |
| fix a hitch or review performance | `ai-performance` skill; `frametime.py`, `hitch.py` (S31) |
| reason about the economy or T3 | `how-it-works.md` (the game), `eta-objective`, `value-paradigm` |
| work on nukes / air / the commander | `ai-nukes` · `ai-air` · `ai-commander` |
| work on the nets | `how-it-works.md` (the nets); `randsearch.py --status` |
| check a game against his complaints | `game-audit` skill |
| investigate a desync | `desync-check` skill |
| commit a change that touched comments | `python tools/comment_audit.py` |
| judge whether a rule does anything | `python tools/deadcheck.py <run>` |

## The four lists

- **Commit message**: what changed and what was measured.
- **`ISSUES.md`**: what is wrong now, with evidence. Its validation list on top is live.
- **`USER-FEEDBACK.md`**: his open asks. Read before starting work.
- **`TODO.md`**: his named plays and unbuilt behaviours, in his words.

An entry is deleted when it is built and measured. `changes/CHANGES.md` and `notes/` are frozen history.

## Layout

| | |
|---|---|
| live AI | `ai/Unstable/{engine-side,game-side}`, the only tree you edit |
| layers | JSON config, AngelScript (both hot-swappable by deploy), C++ in `cpp/` |
| shims | every `manager/<name>.as` `#include`s `manager/<name>/`; edit the parts |
| repo tree | `README.md` |
