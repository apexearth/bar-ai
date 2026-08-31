# bar-ai — working notes for Claude

AI development for **Beyond All Reason** (BAR), the RTS on the **Recoil** engine
(a fork of Spring RTS). This repo is the source of truth for a custom AI; the
live game install is a deploy target.

Everything below was verified on this machine on 2026-08-09 unless marked
otherwise. Re-verify paths before relying on them — engine versions change.

Refer to `BAR-GUIDE.md` to learn about game mechanics.

## Local layout

| What | Path |
|---|---|
| Launcher install | `C:\Users\apexe\AppData\Local\Programs\Beyond-All-Reason` |
| Spring data / write dir | `…\Beyond-All-Reason\data` |
| Active engine | `…\data\engine\recoil_2026.07.04` (from `launcher_cfg.json` → `config.json`) |
| Game (harness) | `…\data\games\BAR.sdd` — git clone of `beyond-all-reason/Beyond-All-Reason`, branch `apex`, pinned 2025-11-28 |
| Game (reference) | `vendor/bar` — the same repo at upstream `master`, for looking things up |
| Engine-side AIs | `…\data\engine\<ver>\AI\Skirmish\{BARb,Apex,ApexCtl,ApexStk,CircuitAI,NullAI}\<version>\` |
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
  `AI/Skirmish/<shortName>/<version>/`. Ours is `Apex`, so the harness spec
  is `Apex:Unstable`, not `BARb:Unstable`. (It was `BARbApex` until 2026-08; nothing
  validates a shortName, so an old command silently produces
  `unknown skirmish AI` and a variant that scores zero on everything.)
- **AI version** → a variant within one shortName.
  `AIInfo.lua`'s `version` value must equal the folder name.
- **profile** → a difficulty/playstyle within one version, chosen by the
  `profile` AI option declared in that version's `AIOptions.lua`.
  `config/<profile>/*.json` + `script/<profile>/*.as`.
  **`Unstable` ships exactly one: `standard`.** The stock easy/medium/hard/
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
`Load script: LuaRules\Configs\Apex\Unstable\script\standard\init.as`

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

### How the AngelScript is laid out

Every `manager/<name>.as` is a SHIM: a table of contents that `#include`s the
real code from `manager/<name>/`. Edit the parts, not the shim — except to add a
part, which means adding a line to the shim.

**The include order in a shim is load-bearing, but narrowly.** `CScriptBuilder`
adds a section before walking that section's own includes, depth-first in listed
order, so the shim's list is the order the compiler sees declarations in. What
actually breaks is only a **global's INITIALIZER expression** reading a symbol
declared in a later file. AngelScript registers every type and global across all
sections before compiling any function, so functions, parameter types and
ordinary reads inside function bodies are order-independent — this tree proves
it and runs (`market/want_super.as` reads `Base::gAnchor` from a namespace
included four lines later). An earlier checker that enforced the stricter rule
produced 250 false positives here. `python tools/as_scope.py` reproduces the
real walk and reports the two failures that do bite: a global initializer
reading a later symbol, and a local read outside its declaring block.

Both `AiMakeTask`s are pipelines: `builder/maketask.as` and
`factory/maketask.as` are short ordered lists of named rules that live in the
sibling `rules_*.as`. A rule returns null to pass. **Where a new rule goes in
that list is the design decision** — see the 2026-08-01 composition finding
below.

`script/side.as` holds `SideDef3`/`SideName3`, outside every namespace, which is
how an Armada/Cortex/Legion triple gets resolved. Use it rather than writing
another `if (side == "cortex")` chain.

Files are kept under ~600 lines deliberately: above that, work degenerates into
grep-an-anchor-and-blind-replace, and a `str.replace` anchor that does not match
fails silently. That has eaten edits here at least five times.

**Component ownership lives in the `ai-*` skills** (apexearth 2026-08-21:
"make skills for our ai components so we understand whats in charge of
what"): `ai-economy`, `ai-build-arbitration`, `ai-factory-brain`,
`ai-military`, `ai-placement`, `ai-nukes`, `ai-commander`, `ai-air`. Each
answers: what owns which decision, the decision chain, the log lines that
expose it, and its tunables. Load the matching one BEFORE diagnosing a
domain — it is cheaper than rediscovering the chain from the code.

**A new tunable or mechanism is not finished until the dashboard shows it.**
`tools/dashboard.py` is apexearth's interface to this AI — he does not run
the CLI tools — so a knob that exists only in `tunables.as` is a knob he
cannot reach, and a modoption missing from `dev_tunables.lua` is silently
ignored in game. Load the **`dashboard-ui`** skill before adding one.
`check.py` runs `tools/dashboard_audit.py`, which reports any tunable the
guided view has never seen, any it names that no longer exists, and any it
offers that nothing reads.

**`CHANGES.md` is FROZEN (apexearth 2026-08-27: "stop putting changes in
CHANGES.md... you can instead look at git history").** What changed and what
was measured goes in the COMMIT MESSAGE, next to the diff it justifies; open
or unresolved findings go in `ISSUES.md`. The frozen file remains as history
for everything before 2026-08-28.

**`ISSUES.md` is the live list of what is wrong** — each entry with the
evidence for it and, where known, the mechanism in our own code. Add to it
rather than re-deriving the same complaint next session.

**Read `USER-FEEDBACK.md` before starting work.** It is the standing brief of
what apexearth actually wants, in one place, with the still-unresolved items
marked. Several entries there have been raised three or four times without being
fixed — base sprawl and never reclaiming old buildings, army not being positioned
on the front line, naval players going idle. Re-reading it costs a minute; being
told the same thing again costs his session. Git history says what was done,
`USER-FEEDBACK.md` says what was asked for.

## Commands

```bash
python tools/dashboard.py                    # local web UI: browse runs, launch, deploy, tunables
python tools/bar_env.py                      # show resolved paths
python tools/deploy_ai.py status             # what is deployed, and is it in sync
python tools/deploy_ai.py deploy Unstable    # repo -> live install
python tools/deploy_ai.py pull Unstable      # live install -> repo (after in-place edits)
python tools/deploy_ai.py gadgets            # install dev gadgets into BAR.sdd
python tools/deploy_ai.py patches            # apply game-patches/*.patch to BAR.sdd

python tools/unitsync.py maps comet          # resolve map display names
python tools/unitsync.py ais                 # what the engine sees

python tools/unitdef.py corasy --builders    # cost, display name, who can build it
python tools/unitdef.py legsy --builds       # what it builds
python tools/unitdef.py "advanced ship"      # search display names
python tools/unitdef.py --trees              # both game trees and their dates

python tools/run_match.py --a Apex:Unstable:standard --b BARb:stable:hard \
    --map "Comet Catcher" --minutes 60 --seed 1
python tools/run_match.py --a Apex:Unstable:standard --b BARb:stable:hard \
    --map "Comet Catcher" --per-side 8 --watch   # windowed, real time, watchable

python tools/review.py <run> --control <run>  # THE way to judge a run; see below
python tools/check.py                        # pre-deploy: bad JSON, dead unit names
python tools/trace_flow.py <match-or-run-dir> # did the pooling strategy actually work
python tools/run_tournament.py --a Apex:Unstable:standard --b BARb:stable:hard \
    --maps "Comet Catcher" --games 10
python tools/run_tournament.py --report

python tools/composition.py <tournament>     # where the metal actually went
python tools/tl.py tournaments/<run>         # paired timeline by game minute
python tools/fight1v1.py <run-dir>           # army trade efficiency, in metal
```

Batch output lands in `tournaments/<stamp>-<slug>/`, not `matches/`.

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
  `standard` entry.
- Engine dirs are wiped on BAR update. Re-run `deploy_ai.py deploy` afterwards.

## The Brain drives the factories — `factory.json` is mostly NOT in the loop

`Market::ConOrderFor` (`brain/market/production.as`) is the only path to what a
factory builds. While the Brain drives a line, `factory.json` tier tables and
`response.json` decide nothing. Days were spent tuning factory.json weights to
fix "only Hounds get built" when the composition was decided elsewhere entirely.
**Attribute a composition problem to the producing code before touching any
config table** — read `apex: decide ... -> produce:`, `apex: worth` and
`apex: lineclass`. Details: the `ai-factory-brain` skill.

## Failure modes that are SILENT — check for these before believing a result

Every one of these has produced a confident, wrong conclusion in this repo. They
share a shape: the thing didn't work, and nothing said so.

- **In multiplayer the engine silently runs stock BARb unless the variant has its
  own shortName.** The lobby drops the AI version, and empty-version resolution
  picks the highest by `VersionCompare` — `stable` beats `apex`. Nothing logs a
  problem; the AI simply plays like stock. See "Three axes" above, and test with
  `run_match.py --drop-ai-version`.
- **A plain 1v1 (no allies) used to silently run stock, on purpose — REMOVED
  2026-08-14.** `world.as`'s `ApexActive()` used to latch false whenever the
  AI's own ally team had no teammates (`mates.length() <= 1`), which caused
  `Builder::MakeTaskInner` and five other call sites to fall through to stock
  CircuitAI logic for the whole game — measured 2026-08-14 as zero `apex:` log
  lines over 4628 frames in a watched 1v1. apexearth judged that measurement
  stale against everything fixed since and had the gate removed outright:
  `ApexActive()` now unconditionally returns `true`, the `apex_solo_stock`
  tunable is gone, and apex runs its own logic in every game regardless of
  ally count. Confirm apex is running with `grep "apex:" infolog.txt`.
- **An AngelScript compile error disables the whole variant, and the match still
  runs.** It plays as near-stock and reports a normal result. A 12-minute "the
  rush never fires" investigation was really a one-line syntax error. **Always**
  grep the infolog after a run:
  `grep -oiE "\(?[0-9]+, [0-9]+\) : ERR|Fix compilation errors" infolog.txt`
  **Do NOT anchor the pattern on a filename.** AngelScript treats WARNINGS as
  errors, and that failure prints as ` (0, 0) : ERR : Warnings are treated as
  errors by the application` with no file — a filename-anchored grep reads a
  variant that never compiled as a clean run. Cost a full round of false
  "validated" reports 2026-08-20 (a `uint`/`int` compare in maketask.as).
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
  was measured returning -1 for all teams, including the AI's own. **The
  mechanism previously recorded here is wrong**: it said `AI_TEAM_IDS` in
  `rts/ExternalAI/SSkirmishAICallbackImpl.cpp` is "declared `= {{-1}}` and never
  assigned", but in `recoil_2026.07.04` it *is* assigned, at line 5535
  (`AI_TEAM_IDS[ai->GetSkirmishAIID()] = ai->GetTeamId()`), and the -1 comes out
  of `aiGetTeamResource`'s `AlliedTeams` gate. The observation has not been
  re-measured on this engine — treat both the reading and the explanation as
  unverified. Before building logic on a binding, log its raw return once and
  confirm it is real data. Route around via a synced gadget publishing a game
  rules param (`Game_getRulesParamFloat` is not gated); see
  `game-patches/gadgets/dev_team_income.lua`.
- **`ai.GetBuilderThreatAt(pos)` will crash on an off-map position, and reads
  zero almost everywhere anyway.** `CThreatMap::GetBuilderThreatAt` bounds-checks
  with an `assert` — compiled out in release — then indexes `surfThreat`
  unchecked. Sampling a ring of radius 1500 around a base near the map edge read
  off-map memory and killed the engine at frame 3 (0xc0000005). **Guard every
  position with `OnMap()`** (`script/world.as`) — `AiTerrainWidth()`/`AiTerrainHeight()`
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
- **A DUPLICATE `RegisterObjectMethod` kills the AI at init, and the match still
  reports a normal-looking failure.** Registering a binding that already exists
  returns `asALREADY_REGISTERED (-13)`, the `ASSERT` fires, and the AI never
  initialises — the engine runs to completion, `result.json` says
  `crashed: true` with an EMPTY stats array, and the only real evidence is one
  line in the infolog: `Failed in call to function 'RegisterObjectMethod'`. Grep
  `asALREADY_REGISTERED` before blaming logic. Measured 2026-08-12: `SetRetreat`
  was bound 14 lines below where a second copy was added, and the "surface
  listing" that said it was missing had been truncated with `head -30` — absence
  again, from an incomplete search.
- **An order we issue is NOT applied when we issue it, and reading the unit back
  in the same tick returns the state before it.** `CAICallback::GiveOrder`
  (`rts/ExternalAI/AICallback.cpp:369`) never touches the unit — it does
  `clientNet->Send(SendAICommand(...))`, and the command lands when that message
  is consumed. **The lag scales with sim speed**: measured 2026-08-12, a factory
  read `CountQueued == 0` for 45 consecutive `AiUpdate`s at the benchmark's
  default speed cap (~37x realtime) and then took all 56 queued orders in one
  tick; at `--speed 3` the same code read 2-9 throughout. Any loop of the form
  "read what the unit has, top it up" will issue one order per tick for the whole
  lag window. Keep a count of what was SENT and use the read only to confirm it.
  This is also a benchmark trap: a headless run at max speed can exercise a
  completely different code path from the game apexearth watches.
- **`AiMakeTask` is a RE-ELECTION, not a request for new work.**
  `IBuilderTask::Reevaluate` (`task/builder/BuilderTask.cpp:447`) calls
  `manager->MakeTask(unit)` on every task update for every builder not yet in
  build range, and only reassigns if the answer has a *different* build type. So
  any rule that `Enqueue`s before returning enqueues **once per update**, and
  every enqueue after the first is an orphan nobody will ever work. Measured:
  15 front-defence tasks in 3 minutes, `picked=0/15`. Return an existing task, or
  remember the one already placed for that builder.

- **A watch game's infolog reaches the match dir only at game END; mid-game
  reads of `matches/_engine*/infolog.txt` can be DAYS stale.** Analyzing a
  live game via the engine dir produced a full false diagnosis 2026-08-21 (a
  "dead facqueue" CRITICAL retracted hours later -- the log was from Aug 10).
  Check the file's mtime against the game being discussed before reading ONE
  line of it.

- **`result.json`'s `teams[].team` is the SPEC index ('a'=0, 'b'=1), not a game
  team.** In a per-side game spec b's players are teams N..2N-1, so anchoring a
  side split on `ally_of[teams[apex].team]` reads the ENEMY's side whenever Apex
  is spec b -- every side-swapped tournament game. This inverted a full 6-game
  tournament read 2026-08-21 into a false "we out-scale stock 2x" (the reported
  dominance was stock's own scaling); the corrected medians said the opposite.
  Each spec's players share the allyteam equal to its spec index -- anchor on
  that. `tools/scaling.py` does it right now; check any new tool against a
  side-swapped game before believing it.

- **Aggregate over the right unit.** The T2 rush was reported as "not firing"
  from a median first-T2 of 14.9 min. That was the median across ALL FOUR
  players, dominated by followers who tech late by design. The rusher's own time
  — `min(techStart)` per side — was 6.3 min, under 10 in 20 of 20 games. A team
  strategy that deliberately treats one player differently cannot be judged by a
  team-wide average.

## build_chain.json evaluates in ways the config does not suggest

See the `barb-tuning` skill for the full mechanics (hub firing, condition
evaluation, `prevent` semantics, `energy`/`wind` vocabulary) and the upstream
bugs found alongside them — verified 2026-07-29 against `BuildChain.cpp`,
`BuilderTask.cpp`, `BuilderManager.cpp`.

## T3 affordability is a statement about INCOME, not about the AI

Real costs, read from the unit defs: **corgant 8400, corshiva 1550, corcat 4900,
armbanth 13500, corjugg 20000, corkorg 29000**. At the 40 metal/s benchmark T3 is
two or three units a game; in a hosted +40% game a player was observed at **398
metal/second**, where a gantry is 21 seconds of income. Above ~250 m/s the
affordability argument inverts completely, which is why `T3Worthwhile()` drops
its vetoes there. **Read the actual income before calling T3 unaffordable or
broken** — and note that stock BARb out-T3s us by default on a bonused economy
(146,850 metal of T3 on one side of a +40% 40-minute 4v4).

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

See `docs/20-brain-overhaul.md` for the design that addresses this directly --
rules propose Wants and one arbiter ranks them, instead of the first rule in an
ordered list winning. `docs/17-behaviour-config.md` traces every behaviour.json
knob to the line that consumes it. `docs/21-simplification.md` and
`docs/22-macro-demand.md` are the 2026-08-30 findings: a price built from twelve
multiplicative terms cannot be steered by changing one of them, and a decision
asked of a single constructor cannot express what the base needs.

## Delegate only when asked, and keep agents short-lived

The fleet-of-agents workflow was tried and **measured worse**: single agents
reached 345k, 337k and 328k tokens and drove usage UP, because continuing an
agent replays its whole transcript. apexearth: *"You're wasting a lot of
tokens/usage by doing it like this. Prefer to NOT have long running agents."*

So: work directly by default. Spawn agents when he asks for them, or for
genuinely parallel work with **disjoint file ownership** — two agents editing
one file is a merge conflict you will pay for twice. Give each a fresh, bounded
task with the three facts it needs in the PROMPT; two or three exchanges is the
ceiling. Investigation can be parallel; implementation is serial and measured.

**Write the finding down before the agent ends** — commit message for what
changed and what was measured, `ISSUES.md` for what is wrong and not yet fixed.
A finding left in a transcript is one you will pay to rediscover.

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

## Judging a run

`python tools/review.py <run> --control <run>` runs the full checklist and
withholds a verdict when a gate fails — see the `bar-benchmark` skill for the
nine-step breakdown and why each step is there (every one exists because
skipping it produced a confident wrong answer at least once).

## Harness discipline

- **Never run two matches on one engine write-dir.** Both engines write the
  same `infolog.txt` and config tree; measured 2026-08-15, a watch game beside
  a long soak run broke the watch game's AI outright and filled the soak's log
  with interleaved binary garbage. `run_match.py` now pidfile-guards
  `matches/_engine` and auto-suffixes a busy dir, but a hand-launched engine
  bypasses that -- check `engine.pid` first.
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
- **Deploy in the foreground, then background the run.** Deploy → background
  run → keep coding is the sanctioned workflow (apexearth 2026-08-27: "It
  should be ok to deploy, run a background run to see how that change went,
  and continue to work on the code in the meantime"). The one rule inside it:
  the deploy's success must be VERIFIED before the run leans on it — a
  backgrounded `deploy && run &` hides a failed deploy, the run proceeds
  against a half-written AI folder, and `FetchSkirmishAILibrary: unknown
  skirmish AI` reads in telemetry as a catastrophic regression that is not
  one. Deploy and check the output (or `deploy_ai.py status`), THEN launch
  the run in the background.
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

## Ask before inventing policy

apexearth, after a hard cap of 4 was added to something he had twice said should
scale with the economy: *"damn you have me worried about whatever other bad ideas
you may randomly add. You should update claude.md so you ask more questions
before just making decisions like that."*

The failure is not being wrong once. It is deciding a POLICY question -- what the
AI is allowed to do -- as if it were an implementation detail, and burying the
answer in a constant. These are the ones that keep happening:

- **Hard caps and ceilings.** "At most 4 of these." He has now said twice that
  nothing should have a hard cap; everything scales with economy and progression.
  If something is being built too often, the fix is its VALUE relative to
  alternatives, not a number that forbids the eleventh one.
- **Exclusivity.** "Only the eco lead may build reactors", "only the tech lead
  may go T2". This one shipped for weeks and made a solo player never build a
  reactor at all. A role may change how OFTEN or how MUCH; it must not decide
  WHETHER.
- **Turning a behaviour off** to fix a symptom, rather than finding what starves
  it. Front-line nanos got defaulted off after one arm; he wanted them on and
  tuned.
- **Thresholds pulled out of the air.** A gate at "60 metal/s" is a claim about
  the game. Derive it, measure it, or ask -- and say which of the three it was.

What to do instead, in order of preference:

1. **Derive it from the economy** -- income, bank, what the thing costs, what it
   returns. That is the answer he gives every time he is asked.
2. **Ask.** One sentence: "should X be capped, or scale with income?" He answers
   these in seconds and the answer is usually "scale".
3. **A named constant**, with the derivation in the commit message.

**A TUNABLE IS THE LAST RESORT, NOT THE SAFE MIDDLE.** This list used to offer
"make it a tunable with the measured default" as option 2, and because it was
the cheapest of the three it was chosen almost every time. Measured 2026-08-30:
**404 tunables declared, 316 read at exactly one call site, and 360 never
overridden in a single recorded run.** They are not experiments; they are
constants wearing an experiment's clothing, and each costs four registration
sites (`tunables.as`, `dev_tunables.lua`, `dashboard_guide.py`, the audit
waiver) plus a line of apexearth's attention on the dashboard.

Create a tunable ONLY when you are going to sweep it in this session and will
report the sweep. Otherwise use a named constant. `python tools/dashboard_audit.py
--stale` lists every tunable never overridden in a run; that list is a cull
list, and folding one back into a constant is always a welcome change.

Not every choice needs a question -- fixing a null deref, wiring a rule that
already exists, following a stated preference. The trigger is: *am I deciding
what the AI is ALLOWED to do, rather than how to do what it was already meant to
do?* If yes, ask.

## Instrument first. This is the rule that matters most.

apexearth, 2026-08-30: *"I see it terribly often that you make changes which
have little or no effect."* He was right. Four changes went in that day and
every one failed to bite:

- a tier discount that scaled EVERY member of the tier equally, so it could
  never change which member was chosen;
- a jammer spacing fix built on a dead-binding theory, when the binding was
  alive (`GetJammerRadius=360`) -- counts rose on both seeds;
- a defence repricing that helped one seed and hurt the other;
- a serialization gate placed on a code path that carries no traffic
  (`moho-pass: 0` -- mex upgrades never reach the Requests chokepoint).

Each is the same mistake: **the code was changed before the path was proven to
carry the decision.** The one diagnosis that survived came from reading the
path first -- `apex: exec ... protect:armguard` plus `defplace ... wall=1
gain=0.00` found the real mechanism in a single step.

So, before changing a rule:

1. **Prove it executes.** Find the log line, or add a counter, that says this
   code ran in a real game. A gate nothing reaches is dead code.
2. **Prove it decides.** Show that its output is what selects the outcome, not
   one of eleven other multipliers. See `docs/21-simplification.md`.
3. **Then change it** -- and if the instrument shows the decision did not move,
   SAY SO. Shipping an inert edit is worse than shipping nothing, because it
   spends his review and hides the real cause.

### Three ways a measurement lies here, all of them paid for

- **A sampled log is not a census.** `defrank` is rate-limited per builder-def
  per 60s. It was read as a complete record and produced a wrong conclusion.
  Say in the log line whether it is a sample.
- **A metric that cannot distinguish the two states you care about is not
  evidence.** "Zero RAID fight-type elections across 11 matches" was used to
  prove we never raid. But stock enqueues raiders as `Defend(promote=RAID)` --
  fight type DEFEND -- and the promotion happens in C++ without passing through
  `AiMakeTask`, so the metric cannot separate the raid pool from the massing
  pool. It was evidence of nothing.
- **Two seeds cannot resolve a change.** Matched pairs disagreed in sign on the
  same change the same day. If you have two runs, you have an anecdote.

## Conventions

- Python 3.13, standard library only. No new dependencies without a reason.
- Tools import `bar_env`; they never hardcode install paths.
- Treat `reference/barb-stable/` as read-only — it's the diff baseline.
- Keep `ai/<variant>/` as the source of truth. If you edit configs directly
  inside `BAR.sdd` while iterating, run `deploy_ai.py pull <variant>` afterwards
  or the work will be lost on the next deploy.
- Line endings are LF (`.gitattributes`) so diffs against upstream stay readable
  -- but the WORKING TREE IS MIXED, and several `.as` files are CRLF. Three
  `str.replace` anchors failed silently on this in one session. Read the exact
  bytes before replacing, or use `tools/normalize_eol.py`.

### Comments — write far fewer than feels natural here

The long "tried X, measured Y, reverted" blocks already in `factory.as` are
load-bearing: they stop a failed experiment being retried. That is not licence
to add more of them. Four rules, each from a real mistake:

- **A code comment is not a session transcript.** apexearth, 2026-08-14, after
  a comment quoted his own complaint verbatim, listed a measured number, and
  narrated the fix history: "quit flooding our comments with events of our
  work, just state a concise 'why' and let that be it." One line: what this
  code does that looks wrong otherwise, and the reason. Not what was reported,
  not what was measured, not the session's timeline — those go in the commit
  message (see the next rule) or nowhere.
- **Never state a cause you did not measure.** A spacing fix was annotated "that
  is how a cap of 6 produced 15-20 constructors" — the cap holding at ≤6 had
  been measured; the claim about the overshoot never was. If it was reasoning,
  say so or leave it out. Wrong comments are worse than none.
- **Don't inline the commit message.** What was tried, what it scored, why it
  was reverted goes in the commit message. A comment earns its place by explaining a
  mechanism that is not visible in the code — a NOCOUNT handle, a jsoncpp
  parsing quirk, an engine gate that returns before the check you are reading.
- **Change the code, change the comment.** A declaration still read "cleared on
  a handover" after the clearing was removed. Re-read every comment attached to
  a line you touch.
- **Never write a finding into a comment. Findings go in the commit message
  or `ISSUES.md`.** A
  comment saying "Legion has legsy but no advanced shipyard" was written from a
  single failed `glob legasy.lua`. It was false — Legion builds `corasy`, listed
  in `legnavyconship`/`legcs`/`legch` buildoptions — and it sat in the code
  asserting the opposite as fact. This is the recurring failure: a conclusion
  drawn once, frozen in a comment, and then believed by the next reader
  (including the next session) long after it stopped being true. Measurements,
  unit costs, timings, "X never happens", "Y does not exist" are all findings.
  They belong in the commit message — dated, next to the diff — or in
  `ISSUES.md` while unresolved, or in nothing at all.

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
