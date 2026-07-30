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
python tools/deploy_ai.py deploy apex
```

Then launch BAR normally — the variant shows up in the lobby AI list as
**BARbarIAn Apex**.

To benchmark it against stock BARb without opening the game:

```bash
python tools/deploy_ai.py gadgets   # one-time: installs the autoquit/result gadget
python tools/run_match.py --a BARbApex:apex:hard_aggressive --b BARb:stable:hard \
    --map "Comet Catcher" --minutes 60 --seed 1
```

A full match takes well under a minute of wall time. For statistics:

```bash
python tools/run_tournament.py --a BARbApex:apex:hard_aggressive --b BARb:stable:hard \
    --maps "Comet Catcher,Supreme Isthmus" --games 10
python tools/run_tournament.py --report
```

## Layout

```
ai/apex/            the AI variant — source of truth, deployed into the live install
reference/          pristine BARb stable, for diffing (read-only)
game-patches/       changes to shared BAR files + dev gadgets
tools/              deploy + headless match harness (Python 3.13, stdlib only)
docs/               reference material
matches/            harness output (gitignored)
vendor/             upstream clones (gitignored)
```

## Docs

| | |
|---|---|
| [01 — Local environment](docs/01-local-environment.md) | what's installed here, and the prior `apex` work |
| [02 — AI landscape](docs/02-ai-landscape.md) | every way to write AI for BAR, and which to pick |
| [03 — BARb architecture](docs/03-barb-architecture.md) | how config, script and DLL fit together |
| [04 — JSON config reference](docs/04-json-config-reference.md) | the config files, field by field |
| [05 — AngelScript API](docs/05-angelscript-api.md) | hooks, globals, and how to extend them |
| [06 — Building the DLL](docs/06-building-the-dll.md) | the C++ path, end to end |
| [07 — Headless testing](docs/07-headless-testing.md) | start scripts, speed, debugging, replays |
| [08 — ML and RL notes](docs/08-ml-and-rl.md) | what exists, what doesn't, what it would take |
| [09 — Resources](docs/09-resources.md) | every URL worth keeping |

## Conventions

Python tools import `tools/bar_env.py` to locate the BAR install; nothing
hardcodes paths. `ai/<variant>/` is authoritative — if you edit configs directly
inside `BAR.sdd` while iterating in-game, run `python tools/deploy_ai.py pull
<variant>` before the next deploy or the changes are lost.
