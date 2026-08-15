# bar-ai — working notes for Claude

AI development for **Beyond All Reason** (BAR), the RTS on the **Recoil** engine
(a fork of Spring RTS). This repo is the source of truth for a custom AI; the
live game install is a deploy target.

Everything below was verified on this machine on 2026-08-09 unless marked
otherwise. Re-verify paths before relying on them — engine versions change.

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
  is `Apex:apex`, not `BARb:apex`. (It was `BARbApex` until 2026-08; nothing
  validates a shortName, so an old command silently produces
  `unknown skirmish AI` and a variant that scores zero on everything.)
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
`Load script: LuaRules\Configs\Apex\apex\script\hard_aggressive\init.as`

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

**The include order in a shim is load-bearing.** `CScriptBuilder` adds a section
before walking that section's own includes, depth-first in listed order, so the
shim's list is literally the order the compiler sees the declarations in.
Functions are visible module-wide regardless of file; globals, consts and types
are not, and must be declared before the line that reads them. Moving a function
between parts is free. Moving a global earlier than its declaration is a
`No matching symbol` that disables the whole variant.

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

See **`CHANGES.md`** for everything this AI does differently from stock BARb,
which layer each change lives in, and how well each is actually measured.

**`ISSUES.md` is the live list of what is wrong** — each entry with the
evidence for it and, where known, the mechanism in our own code. Add to it
rather than re-deriving the same complaint next session.

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

python tools/run_match.py --a Apex:apex:hard_aggressive --b BARb:stable:hard \
    --map "Comet Catcher" --minutes 60 --seed 1
python tools/run_match.py --a Apex:apex:hard_aggressive --b BARb:stable:hard \
    --map "Comet Catcher" --per-side 8 --watch   # windowed, real time, watchable

python tools/review.py <run> --control <run>  # THE way to judge a run; see below
python tools/check.py                        # pre-deploy: bad JSON, dead unit names
python tools/trace_flow.py <match-or-run-dir> # did the pooling strategy actually work
python tools/run_tournament.py --a Apex:apex:hard_aggressive --b BARb:stable:hard \
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
  `hard_aggressive` entry.
- Engine dirs are wiped on BAR update. Re-run `deploy_ai.py deploy` afterwards.

## The Brain drives the factories — factory.json is mostly NOT in the loop

With `apex_fac_queue_brain` on (the default), `brain/facqueue.as` takes every
factory line: it aborts recruit tasks, holds the line on a Wait task, and
issues build orders itself from `QuotaFor`. **While a line is driven,
`factory.json` tier tables and `response.json` decide nothing** except
through `GetRoleDef`'s per-role weighted draw. Days were spent tuning
factory.json weights to fix "only Hounds get built" (2026-08-14) when the
composition was actually decided by `QuotaFor`'s floor/ratio logic — traced
2026-08-15 via the `apex: facqueue ... quota:` log lines, which print each
line's per-def have/want and are the FIRST thing to read for any
"wrong units built" complaint. Attribute a composition problem to the
quota before touching any config table.

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

## Why "mass T3" does not happen: arithmetic, not plumbing

Gantry placement is fine — 79 requests across 20 games, median 23.9 min. Adding
gantry caretakers changed nothing (T3 3,725 → 3,488), so build power is not the
constraint either.

**This section's conclusion holds only at benchmark scale. It does not hold in
the games this AI is actually hosted in — re-check the income before applying
it.**

At benchmark scale: apexdef (the pre-merge variant, since folded into apex)
produces ~110,000 metal across a 45-minute 4v4 —
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

See `docs/18-brain.md` for the design that addresses this directly --
rules propose Wants and one arbiter ranks them, instead of the first rule in an
ordered list winning. `docs/17-behaviour-config.md` traces every behaviour.json
knob to the line that consumes it. `docs/12-build-phases.md` is the BUILD_PHASE
design that addresses this
directly: a single sense of what the AI is buying right now, that individual
rules defer to instead of each firing whenever its own condition happens to hold.

## Working as a fleet — delegate by default

Set 2026-08-12 by apexearth: the top-level session is an **organizer**. The
domain agents in `.claude/agents/` carry the detail; top-level context stays
slim so the loop stays fast.

**Investigation is parallel and read-only. Implementation is serial and
measured.** This is not a style preference. Twelve changes went in over one
session, every one confirmed firing, and together they cut metal production
4.3x — see "The path fires" above. A fleet of agents editing at once is that
failure mode industrialized. The serialization is what makes the parallelism
safe.

- **INVESTIGATE** — the default. Many agents at once, across different
  domains. They read, grep, and run tools; they return a diagnosis and a
  proposed patch. **They do not edit.**
- **IMPLEMENT** — one agent, one approved diagnosis, then a measurement before
  the next goes in.

**What an agent must return.** Top-level context is the scarce resource, so
the report is bounded and structured:

1. **VERDICT** — one line. What is wrong, or "no bug found". A clean bill of
   health is a real and useful answer; do not manufacture a finding.
2. **EVIDENCE** — the specific line, log excerpt or measurement, cited
   `file:line`. An absence needs the positive search that established it.
3. **PATCH** — the exact change, or "none proposed".
4. **COST** — what constructor time or build power this spends, and what it
   displaces. "None" is valid but must be argued, not assumed.
5. **CONFIDENCE** — and what observation would falsify it.

No file dumps, no narration of the search. The point of delegating is that the
organizer reads a conclusion, not a transcript.

**Every agent runs on Opus**, declared in its own frontmatter so it does not
silently follow the session model.

**Keep agents SHORT-LIVED. Do not build up long-running ones.** Continuing an
agent resumes it from its full transcript, so a fifth task costs the first four
again. Measured 2026-08-12: single agents reached 345k, 337k and 328k tokens,
and the 337k one was answering a question it could have taken fresh in a
fraction of that. apexearth: *"You're wasting a lot of tokens/usage by doing it
like this. Prefer to NOT have long running agents."*

So: **spawn a fresh agent per task by default.** Continue an existing one only
when the *unwritten* context genuinely matters — mid-implementation of a patch
it just designed, or a correction to work it has in its hands right now. Two or
three exchanges is the normal ceiling.

That only works if findings live in the repo rather than in transcripts, which
makes the next rule load-bearing rather than tidy:

**Write the finding down before the agent ends.** `CHANGES.md` for what changed
and what was measured, `ISSUES.md` for what is wrong and not yet fixed. A
finding left in a transcript is one you will pay to rediscover, and it forces
the long-running-agent pattern that costs the tokens. When several agents run
at once they will all decline to edit `CHANGES.md` to avoid colliding — so the
ORGANIZER writes it, not them. Ask each agent for the one paragraph it would
have written, and land them together.

Corollary for dispatch: put the distilled context in the PROMPT. A fresh agent
given the three facts it needs outperforms a stale one carrying three hundred.

**Never leave apexearth idle.** If he has said he is around, a windowed game
runs the entire time the fleet and the smoke runs do — launch it *first*, then
dispatch. Kill it and hand him a fresh one if a smoke run finishes early and
shows an obvious problem; watching a known-broken build wastes his session.

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
2. **Make it a tunable with the measured default**, and say in the commit what
   was measured. Then it is an experiment, not a decree.
3. **Ask.** One sentence: "should X be capped, or scale with income?" He answers
   these in seconds and the answer is usually "scale".

Not every choice needs a question -- fixing a null deref, wiring a rule that
already exists, following a stated preference. The trigger is: *am I deciding
what the AI is ALLOWED to do, rather than how to do what it was already meant to
do?* If yes, ask.

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
to add more of them. Four rules, each from a real mistake:

- **A code comment is not a session transcript.** apexearth, 2026-08-14, after
  a comment quoted his own complaint verbatim, listed a measured number, and
  narrated the fix history: "quit flooding our comments with events of our
  work, just state a concise 'why' and let that be it." One line: what this
  code does that looks wrong otherwise, and the reason. Not what was reported,
  not what was measured, not the session's timeline — those go in `CHANGES.md`
  (see the next rule) or nowhere.
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
