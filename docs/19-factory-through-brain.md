# Factory production through Brain — our own standing queue

**Goal, in apexearth's words:** *"Can we try \*not\* using the original CircuitAI
method to make units and instead use our method? (this is what i've been asking
for the entire time btw)"* and *"I want to watch a game with it all working
through brain, and not the old pathway."*

The deliverable is a **watchable game** where every unit a factory builds was
ordered by Brain as a standing queue, not handed out one `CRecruitTask` at a
time.

Everything below was read from source on 2026-08-11 and is cited by file:line so
the next session does not re-derive it.

---

## Why the old pathway cannot simply be "topped up"

`CFactoryManager::Enqueue` (`FactoryManager.cpp:815`) is three lines: `new
CRecruitTask`, `push_back`, `TaskAdded`. One task per unit.

**The blocker:** `CRecruitTask::Finish()` (`task/static/RecruitTask.cpp:108`)
calls `Cancel()`, and `Cancel()` (`:124`) walks the factory's engine command
queue, collects every negative (build) cmdId, and issues
`CmdRemove(params, ALT|CONTROL)`.

So a standing queue **cannot survive its own first completion** under the task
scheme — the task that produced unit #1 wipes orders #2..#N. Repeat does not
save it either: the engine re-appends a finished order to the back of the queue,
and that `CmdRemove` takes all build commands with it.

This is why `CmdRepeat` was bound by this repo, commented for exactly this
purpose — *"A factory told to repeat re-queues what it finishes, so a spam lab
keeps producing instead of waiting to be handed each unit as a separate task"* —
and then never called from anywhere. The intent was right; the mechanism
underneath cancels it.

**Consequence for the design: a factory is either ours or CircuitAI's, never
both.** No blending. The switch is per factory.

---

## What is already committed

| Commit | What |
|---|---|
| `5a25502` | Queue throttle. `Factory::gQTask` mirrors the pending recruit list from the `AiTaskAdded`/`AiTaskRemoved` hooks (which were empty stubs); `Factory::AiMakeTask` declines when full. Deployed and verified. |
| `4ef7bbb` | `CmdBuildUnit(CCircuitDef@, int count, bool replace)` binding in `cpp/src/circuit/script/InitScript.cpp`. **Registered, called by nothing. The DLL has NOT been rebuilt.** |
| `c640fc5` | `Builder::RearOfBase(dist)` in `manager/builder/sitesafety.as`. Helper only, unwired. |

Also live and useful: the `FacWon(name, task)` census in
`manager/factory/maketask.as` + `rules_recruit.as`, and the bp/scout/fire spend
counters in `manager/brain/mix.as`.

---

## The bound surface (verified — do not assume anything else exists)

`CFactoryManager` in `vendor/circuitai/src/circuit/script/FactoryScript.cpp`
binds **only**: `DefaultGetFactoryToBuild`, `DefaultMakeTask`, `Enqueue`
(recruit + serv), `GetRoleDef`, `GetFactoryCount`, `isAssistRequired`,
`buildpowerRatio`, `responseWeight`, and the tier-weight/importance setters.

**Not bound:** `CanEnqueueTask`, `GetTasks`. That is why every script-side
`Enqueue` is blind and why `gQTask` had to be rebuilt from the hooks.

`CCircuitUnit` bindings that are **ours**, added in `cpp/src/circuit/script/
InitScript.cpp`: `CmdMoveTo`, `CmdRepeat`, `GetHealthPercent`, and now
`CmdBuildUnit`. Stock adds `GetPos`, the attribute calls, `SetFireState`,
`SetMoveState`, `SelfDestruct`, `GetRulesParam`, and the `task` property.

`IUnitTask` exposes `GetType`, `GetUnits`, `Abort`, `Done` — and in the running
DLL `GetBuildType`, `GetBuildPos`, `buildDef`, `target` resolve on `IUnitTask`
directly. **`cast<IBuilderTask@>(...)` does NOT compile** — it fails with
`Identifier 'IBuilderTask' is not a data type`. Call the methods on the
`IUnitTask@` param, as `manager/builder/events.as` does.

---

## Step 1 — Rebuild the DLL

Docker 29.6.2 is installed. `docs/06-building-the-dll.md` says the build works
on this machine and has been run many times; follow it exactly.

Gate: the rebuilt `SkirmishAI.dll` must land where `deploy_ai.py` picks it up
(deploy reports *"SkirmishAI.dll (local build)"*). If deploy does not say that,
stop — the game will silently run stock BARb.

---

## Step 2 — Wire Brain to own the factory

New file `manager/brain/facqueue.as`, added to the `brain.as` shim. **Include
order is load-bearing**: globals and consts must be declared before the line
that reads them; functions may live anywhere.

The loop, run from `AiUpdate` (every 30 frames) — **not** from `AiMakeTask`:

1. For each factory Brain owns, ask the existing mix for the composition it
   wants. `Brain::NextForMix(fac)` already answers "what should this factory
   build next"; call it N times, or expose the ratio directly.
2. Lay the queue down: `fac.CmdBuildUnit(def, count, replace)` — first call with
   `replace = true` to clear whatever is there, subsequent defs with
   `replace = false` to append.
3. `fac.CmdRepeat(true)` so the factory loops the queue instead of idling.
4. Re-lay the queue only when the wanted composition has **materially** changed,
   not every tick. Relaying every tick is the same cumulative-append bug in a
   new costume.

**Keeping CircuitAI off the factory** is the other half. `Factory::AiMakeTask`
must, for a Brain-owned factory, return a `Wait` task —
`aiFactoryMgr.Enqueue(TaskS::Wait(false, timeout))` — so the manager considers
it busy and never assigns it a `CRecruitTask`. Use `stop = false`; `stop = true`
issues `CmdWait` and will pause the factory we are trying to run.

Do **not** return null: null leaves the unit in the idle task, and
`CIdleTask::Update` will come straight back asking again.

Do **not** return an already-registered task from `AiMakeTask`. That has crashed
the engine twice here — `0xC0000374` and `0xC0000005`.

---

## Step 3 — The unknown that decides whether this works

Units built outside a `CRecruitTask` finish with **no owning task** and land in
`CIdleTask`. Role assignment then has to come from `Military::AiMakeTask`.

That is the same path every unit takes once its task ends, so it should work —
but it is unverified, and if it does not, **the army comes out unassigned and
stands still**, which looks far worse than the bug being fixed.

Check it first, in the first run: count units finished vs units that acquire a
fight task. If they diverge, the fix is to route finished units into the
military hook explicitly rather than abandoning the approach.

---

## Step 4 — Verify before handing over a game

In this order. Every one of these has produced a confident wrong answer here.

1. `grep -ciE "\.as \([0-9]+, [0-9]+\) : ERR"` over the match `stdout.txt`.
   A compile error disables the whole variant **and the match still runs**,
   playing like stock. The `queue-full` change hit exactly this on its first
   deploy tonight.
2. Confirm the variant loaded: `Load script: LuaRules\Configs\Apex\apex\...`.
3. Confirm the new path is actually driving: log the queue lay-down and count
   it. `FacWon` should show the Brain-owned factories no longer answering
   through `mix` one unit at a time.
4. Only then hand over a windowed game.

---

## Harness configuration — both of these were wrong tonight

- **`--per-side 4`.** `ApexActive()` (`script/world.as:30`) returns **false with
  no allies**, so a 1v1 plays stock. A tournament run without `--per-side` was
  stock-vs-stock and its 3-3 result meant nothing.
- **`--sides Cortex,Cortex`.** The default alternates Armada/Cortex. Every run
  on 2026-08-11 was cross-faction and is confounded; `run_match.py --help` says
  same-faction is preferred for A/B. Re-baseline before trusting any comparison
  against tonight's numbers.

---

## Evidence this is the right target

From the watched game (30 min, 4v4, no winner):

```
mInc=496.1  mCur=20496  mStor=20500  isMetalFull=1  facs=3  queue=5
```

496 metal/second, bank at 20,496 against 20,500 of storage — **completely
full** — with five orders across three factories. Three factories fed one task
at a time cannot spend 496/s, and the `IsExcessed` gate is satisfied at that
income so `Wait` is not what is holding it. This is the case for the standing
queue.

The factory census (3,322 decisions, busiest AI per match, 6 games):

| winner | share |
|---|---|
| `assist` (nano turrets → `DefaultMakeTask`) | 74.2% |
| `mix` (`Brain::MixTask`) | 25.8% |
| every other rule | **0** |

`rez`, `bank-bp`, `rush-bp`, `defensive`, `losing-push`, `share-acon`,
`air-con`, `ecolead`, `default` all scored zero. **`Brain::MixTask` already
decides everything a factory builds** — the lower two-thirds of
`Factory::AiMakeTask` is unreachable. So routing production through Brain is not
a new authority; it is making explicit what is already true.

---

## Built and measured, 2026-08-12

All three steps are done: the DLL was rebuilt with `CmdBuildUnit` (it needed
`#include "AISCommands.h"` for `UNIT_COMMAND_OPTION_SHIFT_KEY`), `manager/brain/
facqueue.as` drives the line, and `Factory::AiMakeTask` keeps CircuitAI off it.
Verified in a 15-minute 4v4 Cortex mirror on Comet Catcher: zero AngelScript
errors, the variant loaded, four lines taken, `facqueue` the winning rule 97
times, and `mix` no longer answering for those factories.

What the run settled, against the questions below:

- **`count` is not multiplied engine-side.** Orders issued 28/17/26/29 per player
  against combat units registered 25/14/31/36. One order, one unit.
- **`Wait(false, ...)` holds the line.** No recruit task was assigned to a driven
  factory in the whole game, and the line kept producing.
- **Units built with no owning task do get roles.** `Military::AiMakeTask`
  requests ran 1.4x units registered -- an unassigned army re-asks on every idle
  update and would read far higher.
- **Assistants were unaffected**: `assist` still answers through
  `DefaultMakeTask`, which is the branch above ours.

The one thing that did NOT work first time: comparing the wanted plan to the laid
one as an ORDERED LIST re-laid every line every `FQ_RELAY_MIN`, because a single
slot moving between roles rewrites the list. 16 lay-downs per line, and a line
that consumes ~1.5 units per 20s never reached its queue's tail -- one unit at a
time again, wearing a queue. Comparing by composition, with a churn threshold
(`apex_fac_queue_churn`, 0.34), took it to 3 lay-downs per line.

Still not measured: what any of this does to the army. Composition against a
control is the next step.

## Unverified, must be measured not assumed

- **shift/ctrl multiplier.** apexearth: *"shift will add/remove 5 units, ctrl
  will add/remove 20."* If that multiplier is applied engine-side rather than by
  the UI, `count` orders become 5× the units. `CmdBuildUnit` appends with
  `SHIFT`. **First run must queue a known number and count what comes out.**
- Whether `Wait(false, ...)` reliably keeps `CFactoryManager` from assigning a
  recruit task to a held factory.
- Whether aborting/holding interacts badly with assistants: nano turrets
  register with the factory manager and are 74% of `AiMakeTask` traffic. They
  must keep reaching `DefaultMakeTask` → `CreateAssistTask`, or every turret on
  that player goes idle — a bug this repo has already shipped once.

---

## Queued behind this (do not batch — one change at a time, composition after each)

1. **T2 lab at the back of the base.** *"make sure we build the T2 lab in what is
   considered the back of our base."* Position is chosen engine-side:
   `UpdateFactoryTasks` enqueues `TaskB::Factory(priority, facDef, -RgtVector,
   representer)` and `FindBuildSite` picks. The only lever is to enqueue it
   ourselves with an explicit position, ahead of the engine — a `T2LabAtRear`
   rule guarded on the conditions `factory/choose.as:257` already uses
   (`MayPursueT2() && !gHaveT2 && RushReady()`), placing at
   `Builder::RearOfBase(...)`. It is a **redirect, not a new spend**, so it does
   not carry the displacement risk every new enqueue rule here carries. Verify
   with `[BARAI_POS]`: the lab's `FrontT` should come out negative.
2. **T2 defences hardly ever get built.** `HeavyDefenceFor` gates Rattlesnake
   (`armamb`/`cortoast`) at 50 m/s and Pulsar (`armanni`/`cordoom`) at 100 m/s;
   at 496 m/s both should be constant. Attribute before touching: count which
   rule places each defence and how many requests are dropped. These are
   advanced-constructor-only, and asking a unit to build something it cannot
   build is a **silent no-op** — the identical bug handed commanders a Pit Bull
   and produced zero errors.

---

# Appendix, 2026-08-12: what apexearth asked for, and where it actually stands

Written for a fresh reviewer. Everything below is either a **quote**, a **source
citation**, or a **measurement with the run it came from**. Where something is
unverified it says so. Several claims made earlier in this session were wrong and
are marked as such — do not trust them merely because they are written down.

## What he wants, in his words

- **Our method, not CircuitAI's.** *"Can we try \*not\* using the original
  CircuitAI method to make units and instead use our method? (this is what i've
  been asking for the entire time btw)"*
- **Quota mode.** *"'Quota Mode' — where you simply set a desired target quantity
  and the factory will make sure we build up to that quantity."* And: *"The way
  this works is it is a toggle. You toggle the factory to quota mode and then add
  the desired unit counts to it."*
- **The quota is per factory.** *"Remember each factory has it's own unique
  quota."*
- **Sizing, from the unit limit.** *"Take a look at your unit limit and divvy up
  your quota based on something reasonable. Let's say you have 100 buildings,
  2000 unit limit, you're in T1... then your split is on 1900 available units."*
  Then: *"Calculate how much total army you want, then fill up the quota to the
  ratio of those units that you want. (round up)"*
- **Tier shift.** *"Later when you get to T2 you reduce your target T1, removing
  some entirely, and now target to create T2 units... later on when T3 is on the
  field, adjust your T2 army accordingly."*
- **Advanced constructors first.** *"(force your advanced cons to build first by
  giving them an inserted queue mode order)"*
- **Add units individually, a few at a time.** *"queuing army 5 at a time is no
  good... just queue 2 or 3 of what you want"*, and *"If you add 5 then instead
  of spreading out our build we'll build 5 of one type and then 5 of the next,
  etc... that is not good, so individually adding them in the order desired is
  better."*
- **Never a standing queue that only grows.** *"With repeat being on the amount
  you've queued will never go down. So you just have factory #s that will
  perpetually keep going higher."*
- **Push forward, do not revert.** *"I hate it when you just want to 'revert' or
  'put the old pathway back on'. We're pushing forward!"*
- Standing rules from `CLAUDE.md` that bind this work: no hard caps, bound
  everything by economic power, ask before deciding policy.

## Mechanisms established from source (cite these, do not re-derive)

1. **A recruit task wipes the factory's queue.** `CRecruitTask::Finish()`
   (`task/static/RecruitTask.cpp:108`) calls `Cancel()`, which walks the
   factory's command queue and `CmdRemove`s every negative (build) cmdId. A
   factory is therefore ours or CircuitAI's, never both.
2. **SHIFT multiplies a factory build order by FIVE.**
   `CFactoryCAI::GetCountMultiplierFromOptions`
   (`rts/Sim/Units/CommandAI/FactoryCAI.cpp:150`): `if (opts & SHIFT_KEY)
   ret *= 5; if (opts & CONTROL_KEY) ret *= 20;`. apexearth identified this from
   watching; the engine source confirms it. **Never shift-append to a factory.**
   Use `CMD_INSERT`, which carries no multiplier — which is exactly why BAR's own
   quota widget uses it.
3. **BAR's Quota Mode cannot be turned on by an AI.**
   `luarules/gadgets/unit_factory_quota.lua` only stores a 0/1 flag on the
   factory's command description; it contains no production logic at all.
   `luaui/Widgets/unit_factory_quota.lua` does all the work, scopes everything to
   `unitTeam == myTeam`, and calls `widgetHandler:RemoveWidget()` when
   spectating. Both files are byte-identical in `BAR.sdd` and `vendor/bar`.
   Emulating it is the only route; sending `CMD_QUOTA_BUILD_TOGGLE` (id 23000)
   would light the icon and change nothing.
4. **What the widget actually does**, and what we copy: every 15 frames, pick the
   unit type with the lowest `count/quota` ratio (counting units *that factory*
   built which are still alive) and `CMD_INSERT` **one** order. It inserts at
   position 1 rather than 0 when the in-progress unit is more than 7.5% built or
   more than 500 metal in, so it never destroys work.
5. **Nothing else assigns tasks to a factory.** `ITaskModule::AssignTask` only
   ever comes from `MakeTask` (`module/TaskModule.cpp:70`), so a line held on a
   `Wait` task cannot be handed a recruit — but tasks assigned *before* takeover
   keep running.
6. **The unit-limit call we can safely use is the wrong one.**
   `skirmishAiCallback_Unit_getMax` returns `unitHandler.MaxUnits()` — engine
   wide, reads 32000 here. `Unit_getLimit` is per team but indexes `AI_TEAM_IDS`,
   the array declared `= {{-1}}` and never assigned (the same bug behind every
   `Game_getTeamResource*` returning -1). The safe per-team route is the start
   script's `[GAME] MaxUnits`, which is **not yet implemented**.

## What is implemented now

`manager/brain/facqueue.as`, plus two hooks in `factory/maketask.as`:
`Brain::DrivenFactory` answers a taken line before anything else, and
`Brain::FactoryQueueTask` takes new lines directly below `Air::MakeFactoryTask`
and **above** the queue-full branch.

C++ bindings added this session (`cpp/src/circuit/script/InitScript.cpp`, DLL
rebuilt each time): `CmdBuildUnit`, `CountQueued`, `CmdInsertBuild` (CMD_INSERT),
`GetUnitMax`, `GetTeamUnitCount(bool staticOnly)`.

Per tick, per driven line: compute the quota (constructors from
`Builder::ConsWantedFor`, scouts from the per-mex floor, combat roles from the
mix shares × slots × `TierShare`), then insert ONE order for whichever type has
the lowest `have/want`, while fewer than `apex_fac_ahead` (2) of our orders are
on the line. On takeover: abort the recruit tasks holding the line, re-issue the
opener, and insert an advanced constructor at the front if it is an advanced
plant.

## Known broken, in priority order

1. **Green (team 2) still behaves wrongly.** apexearth, repeatedly, most recently
   after the opener fix: *"green is still broken."* Unexplained. Log evidence so
   far: at 4 min green holds **67 pending MEX tasks with 5 mexes built**,
   `offers mex=156`, `idleJobs=18`. The mex pile is NOT new — matches from before
   this session show `t13=43` and `t13=63` at the 3-minute mark
   (`matches/20260812-033241-*`, `matches/20260812-045745-*`), so it is at most
   half the story. Those tasks come from CircuitAI's own
   `CEconomyManager::UpdateExpandTasks` (one per open spot, gated on
   `IsAllyOpenMexSpot`), not from our Brain — green logged exactly ONE
   `brain orders mex` in four minutes. **A control run of unmodified HEAD on the
   same seed has never been done. Do that before anything else.**
2. **`CountQueued` is suspect.** It logs `queued 0` / `queued 1` while the
   factory visibly holds several orders. `Unit_getCurrentCommands` returns
   `unit->commandAI->commandQue` (`rts/ExternalAI/AICallback.cpp:383`), while the
   widget deliberately uses `Spring.GetFactoryCommands`. If this read is wrong
   then the `apex_fac_ahead` limit never binds and the queue grows — which,
   together with the SHIFT ×5 bug (now fixed), is what apexearth was seeing.
   **Verify empirically: insert a known number, print the read.**
3. **Driving every factory silenced eleven rules.** `facqueue` now wins every
   factory decision, so `RezBotFloor`, `BankBuysBuildPower`, `LateRadarPlane`,
   `LateFighterScreen`, `EyesForTheGuns`, `RushBuildPower`,
   `DefensiveComposition`, `LosingArmyPush`, `ShareAdvancedCon`, `AirConMinimum`
   and `EcoLeadLine` never run. Mexes fell from stock's 12-27 to 3-18 and
   constructor counts with them — apexearth: *"you aren't making enough cons"*.
   Each of those rules is a quota in disguise and belongs in the table.
4. **Slot sizing does not bind.** See mechanism 6: the limit reads 32000, so
   `slots/line` comes out around 32000 and no combat quota is ever reached. The
   quota is currently pure shape, and the tier shift therefore has no real
   numbers behind it.

## Measurements, with their runs

Same map/seed/settings throughout (`Comet Catcher`, `--per-side 4`,
`--sides Cortex,Cortex`, seed 5 or 8, 22 min, vs `BARb:stable:hard`).

| | apex (t0-t3) | stock (t4-t7) |
|---|---|---|
| metal-share quota, seed 5 | army 0 / 2700 / 150 / 0 | 5455 / 6435 / 5595 / 6865 |
| slot quota, seed 5 | army 0 / 2700 / 2700 / 4585 | 4560 / 7725 / 5515 / 7385 |
| mexes, slot quota | 3-18 | 12-27 |

Factory spam, before and after moving adoption above the queue-full branch, same
seed: `queue=10 unstarted=10 facs=7` → `queue=0 unstarted=0 facs=1`.

## Claims made earlier this session that are WRONG

- *"`count` is not multiplied engine-side"* — **false**, and it was written into
  a commit message and a C++ comment before being caught. SHIFT multiplies by 5;
  see mechanism 2. The measurement behind the claim (orders issued vs units
  registered) was confounded by `CmdRepeat(true)` looping the queue.
- *"A recruit task already assigned to this factory will wipe our queue, and
  aborting them from `Factory::gQTask` fixes it"* — the abort ran and found
  nothing (`aborted 0`), because tasks created in C++ never reach the script task
  hooks. The real cause of that symptom was partial adoption (known broken #3),
  not leftover assignees.
- A "wipe detector" that cleared outstanding orders whenever an unexpected unit
  finished was a **feedback loop** (75 orders issued, 3 filled, 23 false alarms).
  It has been removed. Do not reintroduce event-based tracking of what is on a
  factory; read the queue instead.

## The order to work in

1. Control run of unmodified HEAD, same seed, and diff green's log against it.
   Nothing else is trustworthy until "is this ours?" is answered.
2. Verify `CountQueued` against a known number of inserted orders.
3. Read the per-team unit limit from the start script.
4. Fold the eleven silenced rules into the quota table as quota entries.
