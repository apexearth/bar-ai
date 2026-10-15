# bar-ai

A workbench for building a custom AI for **Beyond All Reason**.

The shipped AI, **BARb** ("BARbarIAn"), is [CircuitAI](https://github.com/rlcevg/CircuitAI)
on its `barbarian` branch: a C++ skirmish AI driven by JSON config and AngelScript, vendored
into the Recoil engine. This repo's variant is **Apex**, changed at all three levels:

| Level | Where | Build step | What you can change |
|---|---|---|---|
| **JSON config** | `ai/Unstable/game-side/config/` | none | unit roles, threat, retreat and quota knobs |
| **AngelScript** | `ai/Unstable/game-side/script/` | none | every build and production decision, army use, the nets |
| **C++** | `cpp/` (mirrored from `vendor/`) | Docker | fight tasks, maps, placement, new script bindings |

## Quick start

```bash
python tools/bar_env.py             # confirm it found your BAR install
python tools/deploy_ai.py status    # what's deployed
python tools/deploy_ai.py deploy Unstable
```

Then launch BAR normally; the variant shows up in the lobby AI list as **Apex**.

To benchmark it against stock BARb without opening the game:

```bash
python tools/deploy_ai.py gadgets   # one-time: installs the autoquit/result gadgets
python tools/run_match.py --a Apex:Unstable:standard --b BARb:stable:hard \
    --map "Comet Catcher" --minutes 60 --seed 1 --speed 20
python tools/run_tournament.py --a Apex:Unstable:standard --b BARb:stable:hard \
    --maps "Comet Catcher,Supreme Isthmus" --games 10 --speed 20
python tools/run_tournament.py --report
```

## Layout

```
ai/Unstable/        the AI variant -- source of truth, deployed into the live install
cpp/                the C++ source of the DLL
reference/          pristine BARb stable, for diffing (read-only)
game-patches/       changes to shared BAR files + dev gadgets
tools/              deploy, headless match harness, analysis (Python 3.13, stdlib only)
docs/               five documents, below
matches/ tournaments/ runtime/ vendor/   output and upstream clones (gitignored)
```

## Docs

- `docs/doctrine.md`: how the AI should play (the owner's directives only).
- `docs/how-it-works.md`: how the AI decides, part by part.
- `docs/working.md`: how to work in this repo: commands, testing, building, releasing.
- `docs/traps.md`: silent failure modes, each with its check.
- `docs/tunables.md`: why a default is what it is.

`ISSUES.md` is what is wrong now, `USER-FEEDBACK.md` the owner's open asks, `TODO.md` his named
plays not yet built. `CLAUDE.md` is the index for Claude sessions.

Python tools import `tools/bar_env.py` to locate the BAR install; nothing hardcodes paths.
`ai/Unstable/` is authoritative: if you edit configs inside `BAR.sdd` while iterating in-game,
run `python tools/deploy_ai.py pull Unstable` before the next deploy.
