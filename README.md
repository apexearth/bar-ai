# bar-ai

A workbench for building custom AI for **Beyond All Reason**.

The shipped AI, **BARb** ("BARbarIAn"), is [CircuitAI](https://github.com/rlcevg/CircuitAI)
on its `barbarian` branch — a C++ skirmish AI driven by JSON config and
AngelScript, vendored into the Recoil engine. You can modify it at three levels
without touching the other two:

| Level | Where | Build step | What you can change |
|---|---|---|---|
| **JSON config** | `ai/<variant>/game-side/config/` | none | build ratios, income tiers, unit roles, responses |
| **AngelScript** | `ai/<variant>/game-side/script/` | none | task selection, defence logic, per-tick custom logic |
| **C++** | CircuitAI source | cross-compile | new task types, map analysis, new script bindings |

The first two live inside the game archive and are hot-swappable. Start there.

## Quick start

```bash
python tools/bar_env.py             # confirm it found your BAR install
python tools/deploy_ai.py status    # what's deployed
python tools/deploy_ai.py deploy Unstable
```

Then launch BAR normally — the variant shows up in the lobby AI list as
**Apex**.

To benchmark it against stock BARb without opening the game:

```bash
python tools/deploy_ai.py gadgets   # one-time: installs the autoquit/result gadget
python tools/run_match.py --a Apex:Unstable:standard --b BARb:stable:hard \
    --map "Comet Catcher" --minutes 60 --seed 1
```

A full match takes well under a minute of wall time. For statistics:

```bash
python tools/run_tournament.py --a Apex:Unstable:standard --b BARb:stable:hard \
    --maps "Comet Catcher,Supreme Isthmus" --games 10
python tools/run_tournament.py --report
```

## Layout

```
ai/Unstable/        the AI variant — source of truth, deployed into the live install
reference/          pristine BARb stable, for diffing (read-only)
game-patches/       changes to shared BAR files + dev gadgets
tools/              deploy + headless match harness (Python 3.13, stdlib only)
docs/               reference material
matches/            single-match output (gitignored)
tournaments/        batch output (gitignored)
vendor/             upstream clones (gitignored)
```

Each variant is a distinct **shortName**, not a version of `BARb` — see docs/03
for why a version-only variant silently plays as stock in multiplayer. The live
variant is `Apex` / version
`Unstable` / profile `standard`; `python tools/deploy_ai.py status` prints the
current specs.

## Docs

**[docs/README.md](docs/README.md) is the index** — one line per doc saying what
question it answers. Pick one from there rather than reading the set.

Beyond `docs/`: **`docs/23-the-plan.md`** is what the AI is trying to do, in two
paragraphs, and is the thing to read first; **`ISSUES.md`** is the live list of
what is wrong; **`USER-FEEDBACK.md`** is the standing brief of what's actually
wanted; **`TODO.md`** is the sketchbook of named plays and unbuilt behaviours;
**`changes/CHANGES.md`** is frozen at 2026-08-28 and is history only — what changed and
what was measured lives in the commit message now; **`CLAUDE.md`** is the working guide, including the
silent failure modes worth knowing before trusting a result.

## Conventions

Python tools import `tools/bar_env.py` to locate the BAR install; nothing
hardcodes paths. `ai/<variant>/` is authoritative — if you edit configs directly
inside `BAR.sdd` while iterating in-game, run `python tools/deploy_ai.py pull
<variant>` before the next deploy or the changes are lost.
