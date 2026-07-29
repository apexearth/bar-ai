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

## Failure modes that are SILENT — check for these before believing a result

Every one of these has produced a confident, wrong conclusion in this repo. They
share a shape: the thing didn't work, and nothing said so.

- **An AngelScript compile error disables the whole variant, and the match still
  runs.** It plays as near-stock and reports a normal result. A 12-minute "the
  rush never fires" investigation was really a one-line syntax error. **Always**
  grep the infolog after a run:
  `grep -oiE "[a-z_]+\.as \([0-9]+, [0-9]+\) : ERR .{0,80}" infolog.txt`
- **AngelScript has no forward declarations.** `CCircuitDef@ Foo();` parses as a
  *global property* and yields `Name conflict`. The module sees all its own
  functions regardless of order — just call it. (Globals and types *do* need to
  be declared before use.)
- **Asking a unit to build something no constructor of ours can build is a
  no-op.** Forcing `coravp` while owning only a bot lab produced 33 dropped
  requests and zero errors. Constructor build options are per-unit: `corck`
  builds only `coralab`, `corcv` only `coravp`. Check the unit's `.lua` def.
- **`aiMilitaryMgr.quota.attack` caps units SENT to attack, not units BUILT.**
  Setting it to suppress army production does nothing; the factory keeps going.
- **Engine callbacks can be silently dead.** Every `Game_getTeamResource*` call
  returns -1 for all teams — including the AI's own — because
  `AI_TEAM_IDS` in `rts/ExternalAI/SSkirmishAICallbackImpl.cpp` is declared
  `= {{-1}}` and never assigned. Before building logic on a binding, log its
  raw return once and confirm it is real data. Route around via a synced gadget
  publishing a game rules param (`Game_getRulesParamFloat` is not gated); see
  `game-patches/gadgets/dev_team_income.lua`.
- **`str.replace` anchors that don't match do nothing, quietly.** This has eaten
  edits at least five times. Always `assert old in s` before replacing, and note
  that these Lua/AngelScript files are **tab-indented** — a space-indented anchor
  will never match.

- **Aggregate over the right unit.** The T2 rush was reported as "not firing"
  from a median first-T2 of 14.9 min. That was the median across ALL FOUR
  players, dominated by followers who tech late by design. The rusher's own time
  — `min(techStart)` per side — was 6.3 min, under 10 in 20 of 20 games. A team
  strategy that deliberately treats one player differently cannot be judged by a
  team-wide average.

## build_chain.json evaluates in ways the config does not suggest

Verified 2026-07-29 against `task/builder/BuildChain.cpp`, `BuilderTask.cpp`,
`module/BuilderManager.cpp`. Each of these broke a confident diagnosis.

- **A hub fires only when its exact parent unit FINISHES.** If the parent is
  never built, the child's condition is never evaluated — not false, *unrolled*.
  Jammer towers hung off `armanni`/`cordoom` and were never built once in a
  30-game sample; their `chance: 0.8` never rolled.
- **`porcupine.prevent` (1) means an ordinary cluster only ever gets
  `landDefenders[0]`.** `DefaultMakeDefence` walks
  `num = isPorc ? defenders.size() : preventCount`. Anything at a later
  porcupine index is unreachable outside a porc cluster.
- **Conditions cannot be combined.** `SBuildInfo::condition` is one enum; the
  parser takes `getMemberNames().front()` and jsoncpp sorts keys alphabetically,
  so `{"m_inc>": 10, "chance": 0.5}` silently becomes chance-only.
- **A condition is evaluated ONCE**, when the parent finishes, and never
  re-checked. It samples one moment. Nano gates of `m_inc>22..46` produced zero
  nanos because they were sampled at a 5.7-min T2 lab (income 10-15), not
  because the numbers were merely high.
- Vocabulary: `energy` is `!IsEnergyStalling() && IsEnergyFull()` = "we have
  plenty" — right for expensive-to-build or upkeep-heavy things (a jammer costs
  5200-19000 E to build), wrong for a fusion (storage is small early, so it
  fires far too soon). `wind` uses `IsEnergyStalling()` = "we need energy now".
  `m_inc>` tests METAL income only.

Upstream bugs found in the same pass, still present in `barb-stable`:
`legbombard` has no builder anywhere; `armfmd` is not a unit def (Armada's
anti-nuke is `armamd`); `armnanotct2`/`cornanotct2`/`legnanotct2` are buildable
by nobody; several porcupine entries carry `"on": false` and are built inert.

**Faction parity**: work done for Cortex has repeatedly been forgotten for
Armada and Legion, and terrain blocks are a second axis of the same trap — a
`land` ratio fix leaves `air` and `water` at stock values, so the change simply
does not exist on those maps.

## Why "mass T3" does not happen: arithmetic, not plumbing

Gantry placement is fine — 79 requests across 20 games, median 23.9 min. Adding
gantry caretakers changed nothing (T3 3,725 → 3,488), so build power is not the
constraint either.

**A Korgoth is ~11,000 metal. apexdef produces ~110,000 metal across a
45-minute 4v4 — about 40 metal/second for the whole team. One T3 unit is
therefore ~275 seconds of the entire team's income.** Two or three per game is
the arithmetic ceiling, and that is exactly what gets fielded. Stock BARb fields
none at all.

So a T3 win condition needs an economy several times larger than either AI
reaches. Before treating "no T3 mass" as a bug, check whether the economy could
pay for one. The alternatives are to grow the economy to afford it, or to accept
that at this scale the deciding force is massed T2.

## Harness discipline

- **Never edit a file a running tournament uses.** Editing `run_match.py`
  mid-run killed 17 matches with an `AttributeError`. The repo `ai/<variant>/`
  tree is safe to edit while running; deploying is what swaps live files.
- **Kill the waiter with the run.** Twice now, killing a tournament has left
  `until ...; sleep; done` shells polling forever for a file that will never be
  written. Stop the background task, not just the processes.
- **`pkill -f` silently does nothing on Windows.** Use
  `powershell -NoProfile -Command "Get-Process python,spring-headless -ErrorAction SilentlyContinue | Stop-Process -Force"`,
  then verify the count is zero.
- **Run Python with `-u` when redirecting to a log.** Without it the log stays
  empty for the whole run and looks exactly like a dead process.
- **Tournament output lands in `tournaments/<stamp>-<name>/`, not `matches/`.**
- **Never chain a deploy into a backgrounded run.** `deploy && run_tournament &`
  hides the deploy's failure: the run proceeds against a half-written AI folder
  and every match reports `FetchSkirmishAILibrary: unknown skirmish AI`, which
  shows up in telemetry as the variant scoring zero on everything. That reads
  exactly like a catastrophic regression and is not one. Deploy, verify, then
  launch.
- **Deploying while BAR is open fails with `WinError 5`** and leaves the AI
  folder half-written (`FetchSkirmishAILibrary: unknown skirmish AI`). Check for
  `spring.exe` / `Beyond-All-Reason.exe` first, and redeploy after closing.
- **`FixedRNGSeed` does not make runs reproducible.** The AI DLL is
  multithreaded: the same seed produced first-T2 at 5.2, 6.9, 9.1 and 9.8
  minutes. Never read a single-run delta as an effect.
- **Confirm the AI under test is actually the one running**, via
  `Load script: LuaRules\Configs\BARb\<variant>\...` in the infolog. A replay
  cannot tell you this — in a replay AIs are "remote", `AiLog` output does not
  appear at all, and `Spring.GetAIInfo` reports `SYNCED_NOSHORTNAME`.

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
