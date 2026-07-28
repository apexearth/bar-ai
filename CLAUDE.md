# bar-ai — working notes for Claude

AI development for **Beyond All Reason** (BAR), the RTS on the **Recoil** engine
(a fork of Spring RTS). This repo is the source of truth for a custom AI; the
live game install is a deploy target.

Everything below was verified on this machine on 2026-07-27 unless marked
otherwise. Re-verify paths before relying on them — engine versions change.

## Local layout

| What | Path |
|---|---|
| Launcher install | `C:\Users\apexe\AppData\Local\Programs\Beyond-All-Reason` |
| Spring data / write dir | `…\Beyond-All-Reason\data` |
| Active engine | `…\data\engine\recoil_2026.06.12` (from `launcher_cfg.json` → `config.json`) |
| Game (dev checkout) | `…\data\games\BAR.sdd` — git clone of `beyond-all-reason/Beyond-All-Reason`, on branch `apex` |
| Engine-side AIs | `…\data\engine\<ver>\AI\Skirmish\{BARb,CircuitAI,NullAI}\<version>\` |
| Game-side AI config | `BAR.sdd\luarules\configs\BARb\<version>\{config,script}` |

`tools/bar_env.py` resolves all of this at runtime. Never hardcode these paths in
new code — import `bar_env` instead. Override with `BAR_ROOT` / `BAR_DATA` /
`BAR_ENGINE` / `BAR_GAME_SDD` env vars.

**The BAR.sdd checkout is stale** — its `origin/master` ref is from 2025-11-28.
`git fetch` in it before comparing against upstream.

## The three layers you can work at

BAR's shipped AI, **BARb** ("BARbarIAn"), *is* CircuitAI: `rlcevg/CircuitAI`
branch `barbarian`, vendored into `beyond-all-reason/RecoilEngine` as the
submodule `AI/Skirmish/BARb`, compiled into `SkirmishAI.dll` and shipped inside
the engine archive.

1. **JSON config** — `config/*.json`. Build ratios, income tiers, unit roles,
   response tables. No build step. Where the existing `apex` work lives.
2. **AngelScript** — `script/**/*.as`. Real decision logic: `AiMakeTask`,
   `AiMakeDefence`, `AiMain`, and a per-30-frame `AiUpdate` hook, over
   `ai`, `aiEconomyMgr`, `aiMilitaryMgr`, `aiFactoryMgr`, `aiBuilderMgr`,
   `aiEnemyMgr`, `aiTerrainMgr`. ~405 bindings. No build step.
3. **C++** — CircuitAI's core. New task types, new map analysis, new bindings.
   Needs a cross-compile toolchain; see `docs/06-building-the-dll.md`.

Layers 1 and 2 both live in the **game archive** and are hot-swappable. Prefer
them. Reach for C++ only when you need a mechanism that doesn't exist yet.

## Two orthogonal axes — do not confuse them

- **AI version** → a separate entry in the lobby AI list.
  `AI/Skirmish/BARb/<version>/` (engine side, needs `SkirmishAI.dll`) **and**
  `luarules/configs/BARb/<version>/` (game side). `AIInfo.lua`'s `version` value
  must equal the folder name.
- **profile** → a difficulty/playstyle within one version, chosen by the
  `profile` AI option declared in that version's `AIOptions.lua`.
  `config/<profile>/*.json` + `script/<profile>/*.as`.

Config lookup falls back: `config/<profile>/x.json` → `config/x.json`.
Confirmed at runtime in an infolog:
`Load script: LuaRules\Configs\BARb\apex\script\hard_aggressive\init.as`

Corresponding C++ (CircuitAI `util/FileSystem.h`):
`"LuaRules/Configs/" + shortName + "/" + version + "/" + subdir + "/"`,
gated on the `game_config` AI option (default **true**).

## This repo

```
ai/<variant>/engine-side/   AIInfo.lua, AIOptions.lua        -> engine AI/Skirmish/BARb/<variant>/
ai/<variant>/game-side/     config/*.json, script/**/*.as    -> BAR.sdd/luarules/configs/BARb/<variant>/
reference/barb-stable/      pristine BARb stable, for diffing (do not edit)
game-patches/               patches + dev gadgets applied to BAR.sdd
tools/                      python harness (see below)
docs/                       the reference material
matches/                    harness output, gitignored
vendor/                     upstream clones, gitignored
```

Deploy derives the engine-side folder from the engine's own `BARb/stable` on
every run, so the bundled `SkirmishAI.dll` always matches the installed engine.
This is what makes the variant survive BAR engine updates — the previous
hand-copied approach broke on each one (the `apex` variant existed only in
`recoil_2025.06.11` and had been dead ever since).

## Commands

```bash
python tools/bar_env.py                      # show resolved paths
python tools/deploy_ai.py status             # what is deployed, and is it in sync
python tools/deploy_ai.py deploy apex        # repo -> live install
python tools/deploy_ai.py pull apex          # live install -> repo (after in-place edits)
python tools/deploy_ai.py gadgets            # install dev gadgets into BAR.sdd
python tools/deploy_ai.py patches            # apply game-patches/*.patch to BAR.sdd

python tools/unitsync.py maps comet          # resolve map display names
python tools/unitsync.py ais                 # what the engine sees

python tools/run_match.py --a BARb:apex:hard_aggressive --b BARb:stable:hard \
    --map "Comet Catcher" --minutes 60 --seed 1
python tools/run_tournament.py --a BARb:apex:hard_aggressive --b BARb:stable:hard \
    --maps "Comet Catcher" --games 10
python tools/run_tournament.py --report
```

Measured on this machine: a 27 game-minute match completes in ~44 s wall
(~37× realtime) with a warm archive cache; a cold cache adds ~35 s.

## Gotchas that cost time

- **`MinSpeed`, not `MaxSpeed`, is what speeds up a headless run.**
  `GameServer::UserSpeedChange` clamps the starting speed into
  `[MinSpeed, MaxSpeed]`, so raising only `MaxSpeed` changes nothing.
- **`GameType=Beyond All Reason $VERSION;`** — `$VERSION` is *literal*. CI
  substitutes it when packing for rapid; a raw `.sdd` checkout never does. That
  same string is also what flips BAR's internal dev mode on
  (`luarules/gadgets.lua` greps `Game.gameVersion` for it).
- **`FixedRNGSeed`**, not `RandomSeed`.
- **Map names in start scripts are display names** ("Comet Catcher Remake 1.8"),
  not filenames. Use `tools/unitsync.py` rather than guessing.
- **On Windows the AI binary is `SkirmishAI.dll`** — the `lib` prefix is Linux only.
- Delete `<writedir>/LuaUI/Config` between headless runs; stale widget config
  silently changes which widgets load. The harness does this.
- Custom AI versions are **not** in Chobby's `aiCustomData.lua`, so the lobby
  shows them uncurated. Declare your profiles in your own `AIOptions.lua`
  (that is why `ai/apex/engine-side/AIOptions.lua` un-comments them).
- Engine dirs are wiped on BAR update. Re-run `deploy_ai.py deploy` afterwards.

## Conventions

- Python 3.13, standard library only. No new dependencies without a reason.
- Tools import `bar_env`; they never hardcode install paths.
- Treat `reference/barb-stable/` as read-only — it's the diff baseline.
- Keep `ai/<variant>/` as the source of truth. If you edit configs directly
  inside `BAR.sdd` while iterating, run `deploy_ai.py pull <variant>` afterwards
  or the work will be lost on the next deploy.
- Line endings are LF (`.gitattributes`) so diffs against upstream stay readable.

## If contributing upstream

Split by layer: game-side configs → `beyond-all-reason/Beyond-All-Reason`
(`luarules/configs/BARb/`); C++ or AngelScript-binding changes →
`rlcevg/CircuitAI` branch `barbarian`.

BAR's `AI_POLICY.md` requires **explicit disclosure of AI-assisted code in the
PR**, and human verification of it. Undisclosed use gets the PR closed. This
applies to work done in this repo with Claude.
