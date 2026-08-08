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
| Game (harness) | `…\data\games\BAR.sdd` — git clone of `beyond-all-reason/Beyond-All-Reason`, branch `apex`, pinned 2025-11-28 |
| Game (reference) | `vendor/bar` — the same repo at upstream `master`, for looking things up |
| Engine-side AIs | `…\data\engine\<ver>\AI\Skirmish\{BARb,BARbApex,CircuitAI,NullAI}\<version>\` |
| Game-side AI config | `BAR.sdd\luarules\configs\<shortName>\<version>\{config,script}` |

`tools/bar_env.py` resolves all of this at runtime. Never hardcode these paths in
new code — import `bar_env` instead. Override with `BAR_ROOT` / `BAR_DATA` /
`BAR_ENGINE` / `BAR_GAME_SDD` env vars.

**There are two game trees and they are different versions.** `BAR.sdd` is
pinned at 2025-11-28 and is what every match runs against — it is also the only
one the dev gadgets can live in, and those gadgets produce *all* telemetry
(`aaT1`, `metalProduced`, `top`, and the game-over winner). `vendor/bar` tracks
upstream `master`. Never answer a unit question by picking one: run
`tools/unitdef.py`, which reads both and shouts when they disagree —
`legadvshipyard` exists upstream and not in the game we test, and `corasy` costs
3100 here against 2800 upstream.

**The game itself does not use `BAR.sdd`.** Chobby plays the rapid-downloaded
`.sdp` packages in `data/packages`/`data/pool`; `BAR.sdd` is an extra entry the
engine picks up by scanning `data/games/`, used only by this harness. That is
why it sat eight months stale without anyone noticing, and why deleting it would
cost the telemetry rather than break the game.

**Read `docs/10-bar-game-concepts.md` before diagnosing anything.** Reasoning
about this AI from telemetry without the game model has repeatedly produced
confident nonsense — T3 treated as affordable at 40 metal/s, a broken run
reported as a "scaling" property, a D-gun's effect on our own buildings not
understood. The economic thresholds there are real numbers from someone who
plays the game.

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

## Three axes — do not confuse them

- **shortName** → the AI's identity. **This is the only one multiplayer keeps.**
  `AI/Skirmish/<shortName>/<version>/`. Ours is `BARbApex`, so the harness spec
  is `BARbApex:apex`, not `BARb:apex`.
- **AI version** → a variant within one shortName.
  `AIInfo.lua`'s `version` value must equal the folder name.
- **profile** → a difficulty/playstyle within one version, chosen by the
  `profile` AI option declared in that version's `AIOptions.lua`.
  `config/<profile>/*.json` + `script/<profile>/*.as`.
  **`apex` ships exactly one: `hard_aggressive`.** The stock easy/medium/hard/
  rush trees were deleted — they carried none of this AI's work, so every change
  either had to be made four more times or silently did not exist there. Do not
  add a profile back without a reason that is not "difficulty".

**A variant must never be just a version of `BARb`.** The lobby protocol's
`ADDBOT` carries a single `aiLib` field and no version — Chobby's `AddAi` sends
`concat("ADDBOT", aiName, battleStatus, teamColor, aiLib)` and `_OnAddBot` sets
only `status.aiLib`. So a hosted game's start script has **`Version` empty**, and
`AILibraryManager::FittingSkirmishAIKeys` filters on version only "if one is
specified i.e. non-empty"; `ResolveSkirmishAIKey` then takes the highest by
`VersionCompare`, and `"apex" < "stable"`. A version-only variant therefore loads
**stock BARb in every multiplayer game**, with no error anywhere. Single-player
is not affected: `interface_skirmish.lua` writes the script locally and does pass
`Version = data.aiVersion`, which is why this only ever showed up when hosting.

Reproduce it locally with `run_match.py --drop-ai-version`, which omits `Version`
from every `[AI]` block exactly as a hosted game does.

Config lookup falls back: `config/<profile>/x.json` → `config/x.json`.
Confirmed at runtime in an infolog:
`Load script: LuaRules\Configs\BARbApex\apex\script\hard_aggressive\init.as`

Corresponding C++ (CircuitAI `util/FileSystem.h`):
`"LuaRules/Configs/" + shortName + "/" + version + "/" + subdir + "/"`,
gated on the `game_config` AI option (default **true**).

## This repo

```
ai/<variant>/engine-side/   AIInfo.lua, AIOptions.lua        -> engine AI/Skirmish/<shortName>/<variant>/
ai/<variant>/game-side/     config/*.json, script/**/*.as    -> BAR.sdd/luarules/configs/<shortName>/<variant>/
reference/barb-stable/      pristine BARb stable, for diffing (do not edit)
game-patches/               patches + dev gadgets applied to BAR.sdd
tools/                      python harness (see below)
docs/                       the reference material
matches/                    harness output, gitignored
vendor/                     upstream clones (circuitai, engine, bar), gitignored
```

Deploy derives the engine-side folder from the engine's own `BARb/stable` on
every run, so the bundled `SkirmishAI.dll` always matches the installed engine.
This is what makes the variant survive BAR engine updates — the previous
hand-copied approach broke on each one (the `apex` variant existed only in
`recoil_2025.06.11` and had been dead ever since).

See **`CHANGES.md`** for everything this AI does differently from stock BARb,
which layer each change lives in, and how well each is actually measured.

**Read `USER-FEEDBACK.md` before starting work.** It is the standing brief of
what apexearth actually wants, in one place, with the still-unresolved items
marked. Several entries there have been raised three or four times without being
fixed — base sprawl and never reclaiming old buildings, army not being positioned
on the front line, naval players going idle. Re-reading it costs a minute; being
told the same thing again costs his session. `CHANGES.md` says what was done,
`USER-FEEDBACK.md` says what was asked for.

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

python tools/unitdef.py corasy --builders    # cost, display name, who can build it
python tools/unitdef.py legsy --builds       # what it builds
python tools/unitdef.py "advanced ship"      # search display names
python tools/unitdef.py --trees              # both game trees and their dates

python tools/run_match.py --a BARbApex:apex:hard_aggressive --b BARb:stable:hard \
    --map "Comet Catcher" --minutes 60 --seed 1
python tools/run_match.py --a BARbApex:apex:hard_aggressive --b BARb:stable:hard \
    --map "Comet Catcher" --per-side 8 --watch   # windowed, real time, watchable

python tools/review.py <run> --control <run>  # THE way to judge a run; see below
python tools/check.py                        # pre-deploy: bad JSON, dead unit names
python tools/trace_flow.py <match-or-run-dir> # did the pooling strategy actually work
python tools/run_tournament.py --a BARbApex:apex:hard_aggressive --b BARb:stable:hard \
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
  shows them uncurated. Any profile you want selectable must be declared in your
  own `AIOptions.lua`; `ai/apex/engine-side/AIOptions.lua` declares the single
  `hard_aggressive` entry.
- Engine dirs are wiped on BAR update. Re-run `deploy_ai.py deploy` afterwards.

## Failure modes that are SILENT — check for these before believing a result

Every one of these has produced a confident, wrong conclusion in this repo. They
share a shape: the thing didn't work, and nothing said so.

- **In multiplayer the engine silently runs stock BARb unless the variant has its
  own shortName.** The lobby drops the AI version, and empty-version resolution
  picks the highest by `VersionCompare` — `stable` beats `apex`. Nothing logs a
  problem; the AI simply plays like stock. See "Three axes" above, and test with
  `run_match.py --drop-ai-version`.
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
- **`ai.GetBuilderThreatAt(pos)` will crash on an off-map position, and reads
  zero almost everywhere anyway.** `CThreatMap::GetBuilderThreatAt` bounds-checks
  with an `assert` — compiled out in release — then indexes `surfThreat`
  unchecked. Sampling a ring of radius 1500 around a base near the map edge read
  off-map memory and killed the engine at frame 3 (0xc0000005). **Guard every
  position with `Builder::OnMap()`** — `AiTerrainWidth()`/`AiTerrainHeight()`
  are bound, and `OnMap` already exists for exactly this. Even so,
  the value is 3% nonzero across ten games, which is why the old commander
  retreat never fired — do not build a trigger on it.
- **Never answer a unit question from a filename search.** Use
  `tools/unitdef.py`. A `glob legasy.lua` returning nothing was read as "Legion
  has no advanced shipyard" and written into a code comment as fact; Legion's
  advanced shipyard is `corasy`, which `legnavyconship`/`legcs`/`legch` list in
  `buildoptions`. Unit defs sit in arbitrary faction subdirectories, display
  names live in `language/en/units.json`, and what a faction can *build* is
  neither — it is the buildoptions of its constructors. One search answers none
  of those three questions.
- **"This unit does not exist" is always a claim about ONE tree.** `BAR.sdd` is
  pinned at 2025-11-28 and `vendor/bar` tracks master, so absence in one proves
  nothing about the other — `legadvshipyard` is upstream-only. `tools/unitdef.py`
  reads both and labels every answer with its source; a unit found only upstream
  gets a loud "do not use it in AI code", because the AI runs against the pinned
  tree.
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

**This section's conclusion holds only at benchmark scale. It does not hold in
the games this AI is actually hosted in — re-check the income before applying
it.**

At benchmark scale: apexdef produces ~110,000 metal across a 45-minute 4v4 —
about 40 metal/second for the whole team. Against that, T3 is two or three units
a game, and that is what gets fielded. Stock BARb fields none.

**Stock fielding none is also benchmark-only.** In a +40% 40-minute 4v4, stock
BARb put **146,850 metal** into T3 on one side, 126,150 of it on a single player.
If a game runs long enough on a bonused economy, stock out-T3s us by default —
which is what losing to "loads of T3" looks like from the inside.

But the numbers above were partly wrong and the scale was unrepresentative. Real
costs, read from the unit defs 2026-07-30: **corgant 8400, corshiva 1550,
corcat 4900, armbanth 13500, corjugg 20000, corkorg 29000** — a Korgoth is 29k,
not the ~11,000 previously claimed here. And hosted games run with a resource
bonus (+40% is normal online) and go long: a player was observed live at **398
metal/second**, where a gantry is 21 seconds of income and a Shiva is 4.

So "the economy cannot pay for T3" is a statement about a 40 m/s benchmark, not
about BAR. Before treating "no T3" as affordable-but-broken *or* as unaffordable,
read the actual income. Above ~250 m/s the affordability argument inverts
completely, which is why `T3Worthwhile()` drops its vetoes there.

## "The path fires" is not evidence that the change is good

Firing proves a change is *wired up*. It says nothing about what it **displaced**,
and in this AI almost everything worth adding displaces something.

Measured 2026-08-01, four 8-game tournaments, same map, seeds, settings and DLL:

| | session start | after twelve changes |
|---|---|---|
| head to head | 2-2 | **0-8** |
| metal produced | 140,940 | **32,648** |
| mex upgrades | 11 | **2** |
| army share | 18.3% | 4.1% |

Twelve changes went in over one session. **Every one was confirmed firing** — that
was the acceptance test — and each looked reasonable alone: dig-in towers when a
constructor keeps getting shot, flak when the enemy flies, a converter when
energy is wasted, the next fusion before it is needed. Together they cut metal
production by 4.3x, because every one of them spends **constructor time**, and
constructor time is the economy. They all run ahead of `DefaultMakeTask`, which
is where mex upgrades live, so the AI answered every threat and never grew.

Tuning the constants afterwards moved metal 39,233 -> 32,648, i.e. the wrong way.
The problem was never the constants.

So:

- **Judge a behaviour change on composition, not on its log line.**
  `python tools/composition.py <tournament>` reports where the metal actually
  went. `mex upgrades 2 vs 8` is the same answer in every game; who won 8 games
  is a coin flip.
- **One behaviour change at a time**, with composition after each. A batch tells
  you the batch is bad and nothing about which member.
- **Separate rules that SPEND from fixes that STOP something.** Removing a
  deadlock, a stampede or a tower built permanently switched off costs no build
  power and is near-free to re-apply. A new rule that enqueues work is never
  free, however cheap the unit.
- **Watching a replay tells you a behaviour looks smart. It cannot tell you what
  it cost.** The dig-in fortresses looked excellent on screen and were among the
  most expensive things here.

See `docs/12-build-phases.md` for the BUILD_PHASE design that addresses this
directly: a single sense of what the AI is buying right now, that individual
rules defer to instead of each firing whenever its own condition happens to hold.

## apexearth is faster than the benchmark — ask him first

His standing requests live in `USER-FEEDBACK.md`; this section is only about
the workflow.

A watched game returns useful feedback in about **five minutes**. A tournament
with a matched control takes **twenty to thirty**, and on the standard benchmark
it frequently cannot answer the question at all: per-team income there is
4-9 metal/s against 12-41 in a hosted game, so anything gated on income never
fires, and win rate has swung 60% -> 10% on an unchanged AI.

So the default order is:

1. **Deploy and hand him a windowed run** (`--watch --speed 5`). Do this FIRST,
   before any measuring, so he is watching while other work continues.
2. Act on what he reports. Every diagnosis that has actually landed this project
   came from him watching: "two v six battles", "Commando as the first unit out
   of the T2 lab", "cons at the front making mexes", "that's a 4v4 map".
3. Use a tournament to **confirm** a mechanism he has already identified, or to
   catch a regression. Not to go looking for one.

Corollary: never leave him idle while a control runs. Launch the watch run, then
do the slow measuring alongside it.

## Judging a run — do these, in this order

`python tools/review.py <run> --control <run>` runs all of this and withholds a
verdict when a gate fails. Prefer it to doing the steps by hand; the steps are
listed because each one is here for a reason.

Every item is here because skipping it produced a confident wrong answer.

1. **Did it actually run?** `grep -ciE "\.as \([0-9]+, [0-9]+\) : ERR"` over the
   infolog, and confirm the variant loaded. A compile error disables the variant
   and the match still reports a normal result.
2. **Run a control.** Deploy unmodified HEAD, run the *same* games, compare. On
   2026-08-02 a change was blamed for a 0-7 tournament; the control lost too, and
   the collapse turned out to predate it by weeks. Never attribute an effect
   without the baseline in hand.
3. **Compare equal samples.** 8 games against a 5-game control is not a
   comparison. Wait for both to finish.
4. **Standing counters are not end-state.** Constructors, army and `mCon` go to
   ZERO when a team dies, so the last sample of a lost game is a corpse.
   `composition.py` now reports these as PEAK and prints how many player-games
   ended wiped out — read that line. Cumulative counters (metal, kills, losses)
   are fine at the end. Reading end-state as the story once produced "apex builds
   1 constructor to stock's 10" when apex actually held MORE constructors all
   game; the diagnosis was backwards for an hour.
5. **Cross-check the timeline before believing a total.**
   `analyze_stats.py <run>` samples every 2 game-minutes. Totals hide when
   something happened, and "when" is usually the finding — the same run showed
   both AIs level to minute 4 and separating at minute 6.
6. **A grep that returns nothing means the pattern is stale until proven
   otherwise.** Log formats drift. `"sent .* metal to lead"` returned zero and
   was reported as "slinging never fired" when 269,000 metal had moved; the
   message had lost the word "metal" and was rate-limited 1-in-40. Confirm the
   pattern matches something before concluding it is absent.
7. **Check the configuration is legitimate.** Comet Catcher is a 4v4 map
   (16x12); dozens of runs were done on it at 8v8, which starves every player and
   invalidates the economy. Match player count to map size, and note that
   `IsSmallTeam()` (< 6 per side) takes different code paths entirely.
8. **Benchmark economics are not hosted economics.** Per-team metal income at
   7 min: hosted games 12-41/s, this benchmark 4-9/s. Behaviours gated on income
   (the air assassin needs 40/s) never fire here at all. If a change targets
   something seen in a hosted game, confirm the benchmark can even reproduce the
   condition before trusting a null result.

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

### Comments — write far fewer than feels natural here

The long "tried X, measured Y, reverted" blocks already in `factory.as` are
load-bearing: they stop a failed experiment being retried. That is not licence
to add more of them. Three rules, each from a real mistake:

- **Never state a cause you did not measure.** A spacing fix was annotated "that
  is how a cap of 6 produced 15-20 constructors" — the cap holding at ≤6 had
  been measured; the claim about the overshoot never was. If it was reasoning,
  say so or leave it out. Wrong comments are worse than none.
- **Don't inline the commit message.** What was tried, what it scored, why it
  was reverted goes in `CHANGES.md`. A comment earns its place by explaining a
  mechanism that is not visible in the code — a NOCOUNT handle, a jsoncpp
  parsing quirk, an engine gate that returns before the check you are reading.
- **Change the code, change the comment.** A declaration still read "cleared on
  a handover" after the clearing was removed. Re-read every comment attached to
  a line you touch.
- **Never write a finding into a comment. Findings go in `CHANGES.md`.** A
  comment saying "Legion has legsy but no advanced shipyard" was written from a
  single failed `glob legasy.lua`. It was false — Legion builds `corasy`, listed
  in `legnavyconship`/`legcs`/`legch` buildoptions — and it sat in the code
  asserting the opposite as fact. This is the recurring failure: a conclusion
  drawn once, frozen in a comment, and then believed by the next reader
  (including the next session) long after it stopped being true. Measurements,
  unit costs, timings, "X never happens", "Y does not exist" are all findings.
  They belong in `CHANGES.md`, where they are dated and sit next to the run that
  produced them, or in nothing at all.

  What may stay in a comment is a **mechanism you can see in the code being
  read** — an engine gate that returns early, an index that is shared between
  two files, a parser quirk. Not evidence for a decision; the reason a line
  cannot be deleted.

  Corollary: **absence is the least reliable finding of all.** Not finding a
  file, a unit or a call proves the search failed, not that the thing is
  missing. Never record "does not exist" anywhere on one search — check who
  builds it, who references it, and the game's own name tables first.

Default to none. Three lines is a lot; ten needs a reason.

## If contributing upstream

Split by layer: game-side configs → `beyond-all-reason/Beyond-All-Reason`
(`luarules/configs/BARb/`); C++ or AngelScript-binding changes →
`rlcevg/CircuitAI` branch `barbarian`.

BAR's `AI_POLICY.md` requires **explicit disclosure of AI-assisted code in the
PR**, and human verification of it. Undisclosed use gets the PR closed. This
applies to work done in this repo with Claude.
