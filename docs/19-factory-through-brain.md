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

---

# Review, 2026-08-12: what the code actually does

Everything in this section was measured on this machine today, on
`Comet Catcher`, `--per-side 4`, `--sides Cortex,Cortex`, seed 8, against
`BARb:stable:hard`, with `HEAD` deployed. The runs are named. Two temporary
instruments were added to get it: a per-line `depth:` field on the `facqueue
lines=` log, and `facCount` / `facQueued` in `dev_stats_export.lua`, which reads
the real build queue with `Spring.GetFactoryCommands` — synced, and therefore
independent of anything the AI believes.

## The headline: THE BENCHMARK IS MEASURING A DIFFERENT AI

Same build, same map, same seed, same eight players, 8 game minutes. The only
difference is the harness's sim-speed cap.

| | apex t0-t3 | stock t4-t7 |
|---|---|---|
| **default speed (~37x)** commander idle | 59-81% | 21-39% |
| **default speed** mexes | 1-4 | 3-6 |
| **`--speed 3`** commander idle | **3-4%** (t1 53%) | 4% |
| **`--speed 3`** mexes | 5-10 | 9-12 |
| **`--speed 3`** `armyReal` | 3260-4475 | 2850-5240 |

Runs: `matches/20260812-073250-*` (default) and `matches/20260812-074239-*`
(`--speed 3`). At default speed apex fields **no combat unit at all** in twelve
minutes — `armyReal` 2700 is the commander on its own — and builds 20-28 T1
constructors against stock's 6-15. At `--speed 3` the same code fields a normal
army and its commanders match stock's idle time to within a percentage point.

**Both AIs degrade at max sim speed; apex degrades far more**, because apex
issues many more orders per tick and, uniquely, *reads engine state back* to
decide the next one. See bug 1 for why that is fatal. Everything the benchmark
has said about facqueue is therefore about the harness.

The real, speed-independent problems left after that are: team 1's commander
(bug 4, still 53% idle at `--speed 3` against 3-4% for the other three), and a
composition that is narrow rather than absent — at 8 minutes the driven lines had
built `corthud` and `corcrash` and no raider or skirmisher at all (bug 2).

## Bug 1 — the queue read is correct but LATE, and the throttle has no memory

`CountQueued` is **not** broken. `LogFacQueues` reads it as 33, 31, 29 while the
synced gadget reads 33, 31, 29 on the same factory. The earlier "logs `queued 0`
while the factory visibly holds several orders" was an artefact of the log line
being printed only on the branch where the read was below the threshold.

What is really happening is worse, and it is visible per tick
(`matches/20260812-073700-*`, one line per `AiUpdate`):

```
[1.1m t3] fqtick #29815 depth=0 orders=11
[1.2m t3] fqtick #29815 depth=0 orders=17
...                                              45 consecutive ticks
[1.7m t3] fqtick #29815 depth=0 orders=50
[1.8m t3] fqtick #29815 depth=56 orders=56    <-- all 56 land at once
```

**An AI order is not applied when it is issued.** `CAICallback::GiveOrder`
(`rts/ExternalAI/AICallback.cpp:369`) does not touch the unit — it calls
`clientNet->Send(CBaseNetProtocol::Get().SendAICommand(...))`. The command is
applied when that message is consumed. At the benchmark's default speed cap the
simulation runs about 37x realtime and consumption falls **~45 sim-seconds**
behind. For 45 ticks `FillQuota` reads an empty queue, so `apex_fac_ahead` (2)
never binds, and it issues one more order every tick.

It is not a fixed engine constant — it is proportional to sim speed. The same
build at `--speed 3` (`matches/20260812-074005-*`) reads `queued=9` at 2 min and
`queued=2` at 4 min, against `queued=52-58` and `orders=56` at max speed. Stock
BARb sits at `queued=0-3` throughout, in both.

Three consequences, all of which matter:

- **The throttle is unsound in principle, not just here.** It compares a target
  against a number that is stale by an unbounded amount, and it keeps no record
  of what it has already sent. Any lag — high sim speed, a loaded host, network
  latency in a hosted game — turns "keep two orders ahead" into "issue one order
  per tick forever". The fix is not a bigger read; it is to count what we issued
  and treat the queue read as a delayed confirmation of it
  (`outstanding = max(issued - confirmed, 0)`), which is the one thing the
  removed "wipe detector" got right and implemented wrongly.
- **The line's own comment is wrong.** `facqueue.as` says BAR's widget "reads the
  queue with `Spring.GetFactoryCommands` … CCircuitUnit::CountQueued is that same
  read". It is not the same read. The widget runs inside the game, where its
  order is applied immediately; an AI's order is not.
- **Every headless facqueue measurement in this document is invalid**, including
  the "army 0 / 2700 / 150 / 0" table above. The benchmark runs at the speed that
  triggers the pathology; a watched game does not. Any A/B on factory production
  has to be run at a speed where `facQueued` for apex stays in the same range as
  stock, or it is measuring the harness.

## Bug 2 — the quota is 20,000 units wide, so the tie-break picks the winner

Instrumented dump of one line's whole quota, one tick after takeover:

```
quota: corck=0/3 cornecro=0/3 corak=0/20296 corthud=0/7032
       corstorm=0/1754 corcrash=0/2915
```

`SlotsPerLine()` is `(GetUnitMax() - buildings) / lines`, and `GetUnitMax()`
returns `unitHandler.MaxUnits()` — **engine-wide, 32000 here**, as the appendix's
mechanism 6 already says. So every combat target is thousands and every combat
ratio prints `0.00`.

The part that was not spotted: `FillQuota` breaks ties with `ratio < worst`,
strictly. When several types read `have/want == 0`, **the first one in `defs`
wins — and `QuotaFor` inserts the constructor first**, then the scout, then the
combat roles. So while counts are zero the answer is always the constructor.

On its own this would self-correct after three constructors (`ConsWantedFor`
gives `want=3`). Compounded with bug 1 it does not: `have = def.count +
CountQueued(def)`, and during the 45-tick window **both terms are zero**, so the
constructor floor of 3 never registers as met and ~50 constructors are committed
before the queue read catches up. A T1 bot lab drains that queue at roughly one
unit per 25 seconds, so those 45 seconds of ordering are ~20 minutes of
production — which is exactly the 12-minute result above.

At `--speed 3`, where the throttle works, this stops being fatal but does not go
away: at 4 minutes the line had built only `corck:480 cornecro:130`, and at 8
minutes only `corthud` and `corcrash` — **no raider and no skirmisher on any of
the three driven bot lines**, while stock fielded gators, raiders, levellers and
wolverines. The mix table is raider-heavy on purpose; the quota is not
delivering it. Fixing the speed artefact alone does not fix the composition.

## Bug 3 — `Brain::Decide` enqueues on every call, and it is called far more often than once per decision

`IBuilderTask::Reevaluate` (`task/builder/BuilderTask.cpp:447`) ends with:

```cpp
HideAssignee(unit);
IUnitTask* task = manager->MakeTask(unit);   // <-- OUR AiMakeTask
ShowAssignee(unit);
if (task != nullptr && (task->GetType() != BUILDER
        || static_cast<IBuilderTask*>(task)->GetBuildType() != buildType)) {
    manager->AssignTask(unit, task);
    return false;
}
return true;
```

So `Builder::AiMakeTask` runs **every task update for every builder that is not
yet in build range** — it is a re-election, not a request for new work. Any rule
that calls `Enqueue` before returning therefore enqueues once per update, and
every enqueue after the first is an orphan: if the new task has the same
`buildType` as the one the unit is already on, `Reevaluate` keeps the old
assignment and simply leaves the new task in the pool with no worker.

`Brain::Decide`'s `fence`, `mex` and `mexup` branches all enqueue-then-return.
Measured on team 1 (`matches/20260812-073250-*`):

```
[1.9m t1] front-aim built=0 never=1  picked=0/8  (idle=0 dropped=1) pending=8
[2.9m t1] front-aim built=0 never=7  picked=0/15 (idle=0 dropped=7) pending=8
```

Fifteen front-defence orders in under three minutes; **none was ever picked up by
a builder** ten seconds after being placed, and seven were aborted by the engine.
This is the leak, not a placement problem.

## Bug 4 — CORRECTED: the leak is real, but it is NOT why the commander stands around

The section as first written blamed commander idleness on the enqueue leak and on
wall-clock path-query latency. apexearth doubted it — *"Sounds like this only
matters much at very, very fast speeds. Are you sure it's the reason our
commander stands around all the time?"* — and he was right.

Attributed properly afterwards, with a `CmdQueueSize` binding added for the
purpose, sampling our own commander once per `AiUpdate` into four exclusive
buckets (`matches/20260812-083050-*`, `--speed 3`, 10 min, 4v4):

| | t0 | t1 | t2 | t3 |
|---|---|---|---|---|
| has a task AND an engine order — working | **91%** | **78%** | **96%** | **91%** |
| task but no order — waiting on a path query | 2% | 3% | 2% | 2% |
| no task at all — our pipeline declined | 4% | 7% | 3% | 5% |
| other task type (retreat, wait, combat) | 3% | 11% | 0% | 3% |

The synced gadget agrees from the other side: apex commanders idle **3-6%**,
stock **2-5%**. And at ten minutes apex matches stock on economy outright — mex
10-12 against 10-13, metal built 8.5k-11.5k against 9.5k-11.5k.

So: **path latency is 2-3% of commander time, not the complaint.** What it really
explains is the benchmark artefact — the identical code reads 59-81% idle at the
default speed cap because these wall-clock waits cover ~12x more sim frames
there. Keep the mechanism, drop the conclusion.

**Where the game is actually lost is after minute ten** and is not yet
attributed. The watched 24-minute game ended with apex at 10k-46k metal built
against stock's 59k-103k and two apex players dead, while the first ten minutes
were level. Measure the timeline; do not guess at this a third time.

The leak itself is still real and still worth fixing — 15 fence orders,
`picked=0/15` — it just is not what it was blamed for. What follows is the
evidence for the leak, which stands.

### The original evidence for the leak

Team 1, same run, from `expand-diag`:

```
[0.5m t1] pool[def=1 t13=2 ]  tasks=3  canEnq=1 mex=1 workers=1 mInc=4 mCur=990/1050 full=1
[2.0m t1] pool[def=1 t13=8 ]  tasks=9  canEnq=0 mex=1 workers=1 mInc=4 mCur=1040/1050 full=1
[3.5m t1] pool[energy=1 t13=37 t15=1] tasks=39 canEnq=0 ...
[4.0m t1] pool[fac=1 energy=1 t13=69 t15=1] tasks=72 canEnq=0 ...
```

- `mCur=1040/1050 full=1` from **30 seconds in and for the rest of the game**:
  storage capped, income 4/s, nothing being spent.
- `mex=1`, `workers=1`, `facs=0` until 4 minutes — no factory, so no second
  builder, so `t13` (MEX) piles to 69 with one worker.
- `commIdle` 201/241 samples at 2 min, against 10-36/241 for the other three
  apex players. The commander's engine command queue is **empty** 83% of the
  time — it is not walking, not building, not assisting. At `--speed 3` the other
  three apex commanders drop to 3-4% idle and team 1 was still 53% in one run —
  but on a later `--speed 3` run with the quota fixes in, team 1 sat at 6% idle
  and 12 mexes, level with the rest. So team 1's collapse is NOT a stable
  property of the start position; it is intermittent, and the runs that showed it
  also had the runaway factory queue. Re-measure before treating "green/red is
  broken" as a separate bug.

The sequence that starts it is in the log: `home tower corhllt` at frame 18 — the
very first builder decision of the game — then three `brain orders front defence
corhllt` at 0.4-0.6m, all at `fwd=-0.11` (behind the base; team 1 starts on the
border, so `HomeTower` picks the 260-metal heavy tower and `Front` puts the line
on top of the base). Each is enqueued, returned, and dropped again by
`Reevaluate`/`UpdatePath`, and the commander cycles instead of expanding.

`HomeTower` compounds it: its "do we already have one" test is
`GetOwnUnitsOfDef(tower, gHomePos, HOME_TOWER_RADIUS)` — **standing units only,
not a pending task** — so while the tower is never finished it re-enqueues every
`HOME_TOWER_RETRY`. Logged four times on team 1 in five minutes.

This is not a facqueue regression. It reproduces at `--speed 3`, and t1 shows
`mex 1-3` in ten separate runs today.

## What was checked and is FINE — do not re-derive these

- **`CMD_INSERT` is used exactly as BAR's own quota widget uses it.** Widget:
  `GiveOrderToUnit(fac, CMD_INSERT, {pos, -unitDefID, ALT+INTERNAL}, ALT+CTRL)`.
  Ours: params `{front?0:1, -defId, ALT|INTERNAL}`, options `ALT|CTRL`. Byte for
  byte the same, and both halves are load-bearing —
  `CCommandAI::ExecuteInsert` (`CommandAI.cpp:1116`) routes the command into
  `facCAI->newUnitCommands` instead of the build queue **without** `CONTROL_KEY`,
  and treats param 0 as a command tag instead of a position **without**
  `ALT_KEY`.
- **No SHIFT multiplier on the insert path.** `CFactoryCAI::InsertBuildCommand`
  (`FactoryCAI.cpp:~300`) multiplies by `GetCountMultiplierFromOptions` of the
  **inserted** command's options, which are `ALT|INTERNAL` — neither SHIFT nor
  CONTROL, so the count is 1. The x5 only bites `CmdBuildUnit`, which is now
  called by nothing; its C++ comment still claims "`count` is NOT multiplied
  engine-side" and is wrong (corrected in the source alongside this review).
- **`Wait(false, …)` does hold the line.** No recruit task reached a driven
  factory in any run here, and the factory kept building from its own queue.
  `IWaitTask::Start` with `isStop=false` issues nothing at all
  (`task/common/WaitTask.cpp:44`).
- **Units built with no owning task do get adopted.**
  `CMilitaryManager::InitHandlers`' `attackerFinishedHandler`
  (`MilitaryManager.cpp:85`) runs `nilTask->RemoveAssignee; idleTask->AssignTo;
  army.insert` for any unit with no task. This is source, not inference.
- **The queue read reaches the right queue.**
  `Unit_getCurrentCommands` → `CAICallback::GetCurrentUnitCommands` →
  `unit->commandAI->commandQue`, which for a `CFactoryCAI` *is* the build queue.
  The wrapper (`WrappCurrentCommand::GetId`) returns the engine `CMD_*` code, so
  the `id < 0` filter is right.

## Corrections to what is written above this line

- *"`CountQueued` is suspect … If this read is wrong then the `apex_fac_ahead`
  limit never binds"* — half right for the wrong reason. The read is correct;
  it is **late**, by an amount proportional to sim speed. See bug 1.
- *"Nothing else assigns tasks to a factory. `ITaskModule::AssignTask` only ever
  comes from `MakeTask`"* — false as stated. `ITaskModule::AssignTask(unit,
  task)` (the two-argument form) is called from `IBuilderTask::Reevaluate`,
  `IBuilderTask::Finish`, `CRecruitTask::Finish` and `AssignPlayerTask`. The
  conclusion for *factories* happens to survive, but the sentence is what made
  bug 3 invisible on the builder side.
- *"tasks created in C++ never reach the script task hooks"* — not established.
  `ITaskModule::TaskAdded` unconditionally forwards to the script
  (`TaskModule.cpp:89`), and `CFactoryManager::Enqueue` calls it. The `aborted 0`
  observation that this was inferred from has a simpler explanation: at that
  point adoption was partial, so the tasks were on factories we had not taken.
  `AbortRecruitsOn` now routinely logs `aborted 10`.
- The appendix's mechanism 6 says `Unit_getLimit` "indexes `AI_TEAM_IDS`, the
  array declared `= {{-1}}` and never assigned". In `recoil_2026.07.04` that
  array **is** assigned, at `SSkirmishAICallbackImpl.cpp:5535`
  (`AI_TEAM_IDS[ai->GetSkirmishAIID()] = ai->GetTeamId()`). The observation that
  `Game_getTeamResource*` returns -1 has not been re-measured; the stated
  mechanism for it is wrong. Re-verify before relying on either.

## Caveat on every engine citation in this file

`vendor/engine` is at tag **2026.06.12** (commit `01b3161`, 2026-07-14); the
engine the matches actually run on is **2026.07.04**. The mechanisms cited here
— orders sent over the net, `ExecuteInsert`'s ALT/CONTROL routing, `FactoryCAI`'s
SHIFT multiplier, the worker-thread scheduler — are long-standing and were also
confirmed by measurement, so they hold. Exact line numbers and constants may not.
This is the likely reason `Unit_getLimit` reads **3938** rather than the 2000 the
`maxunits` modoption asks for: nothing in the 2026.06.12 source produces 3938 for
eight teams (`MAX_UNITS/9 = 3555`, `MAX_UNITS/8 = 4000`), so the running engine
derives it differently. Unresolved; test empirically by varying `--per-side` and
seeing how the number moves, not by reading this tree.

## The quota can only ever be a SHAPE at these numbers

Worth stating plainly because the tier-shift design depends on it. With a
per-player limit of ~2000-3900 and buildings subtracted, a combat role's target
comes out in the hundreds — 0.6 x 1900 is around 1100 raiders. No game reaches
that, so `have >= want` never fires for a combat role and the quota never bounds
production; it only ever answers "which role is furthest below its share".

The same arithmetic disarms the tier shift: `apex_quota_t1_after_t2` at 0.25 still
leaves a T1 target of ~475, far above anything held, so *"later when you get to T2
you reduce your target T1, removing some entirely"* has no effect. Making that
work needs the target to be bounded by what the economy sustains, with the unit
limit as a ceiling on top rather than as the target — which is a policy change,
and apexearth's instruction was explicitly to size it off the unit limit. Raise it
with him; do not quietly re-derive it.

## Why front-defence orders are aborted, and the one-line lever (NOT taken — policy)

`front-aim ... never=7 ... dropped=7` means the engine dequeued them, not that no
builder was free. The mechanism is `IBuilderTask::UpdatePath`
(`task/builder/BuilderTask.cpp:554`):

```cpp
if (canAutoAbort && (target == nullptr)
    && !terrainMgr->CanReachAtSafe(unit, endPos, range, cdef->GetPower()))
{
    manager->AbortTask(this);
    return;
}
```

A front position is by definition not "reachable at safe", so the task aborts as
soon as a builder is elected onto it and starts pathing. Note this is
**independent of priority** — `apex_front_now`, which raises fence orders to
`Priority::NOW` to get past `MakeBuilderTask`'s safety screen, does not touch
`canAutoAbort`, so raising priority alone cannot make a front tower get built.

`canAutoAbort` **is** writable from script: `InitScript.cpp:861` registers it as
a property on every builder task (`RegisterIBuilderTask`). So
`t.canAutoAbort = false` on a fence task, right after `Enqueue`, would stop the
abort.

**Not done, deliberately.** It is a policy question, not an implementation
detail: it sends constructors to ground the engine considers unsafe to reach, and
the likely cost is dead builders — the thing that starves everything else. Ask
apexearth whether front towers are worth builder losses before switching it on,
and if so make it a tunable with a measured default.

## Also found, not yet load-bearing

- **`AbortRecruitsOn` aborts every unstarted recruit task on the team**, not just
  those on the factory being taken (`facqueue.as`, the `on.length() == 0`
  branch), and `SweepDeadRecruits` repeats that every 5 s once every factory is
  driven. Deliberate, and commented as such, but it means taking one line can
  cancel another line's opener before that line is ever adopted.
- **`FillQuota` compares a per-line quota against a team-wide count.**
  `defs[i].count` is every unit of that def the AI owns, while `want` was divided
  by the number of lines. With N lines the effective target is 1/N of the
  intended total. Masked today because the targets are 20,000.
- **A full bank makes CircuitAI build factories without limit.**
  `CEconomyManager::UpdateFactoryTasks` (`EconomyManager.cpp:1530`) skips its
  income veto entirely when `facDef->GetCostM() <= GetMetalCur()`. Any player
  sitting at storage cap — which is every stalled apex player — therefore keeps
  requesting new factories. This is stock behaviour, but our stalls are what
  trigger it, and it is the mechanism behind "now at 40 m/s teal has 6 t1
  botlabs".
- **`limit=32000` is not the per-team limit.** Still true, still unfixed; the
  start script's `[GAME] MaxUnits` remains the route.

## The eleven silenced rules, and what each needs to become a quota entry

A driven line is answered by `Brain::FactoryQueueTask` and never reaches the
rules below it in `Factory::AiMakeTask`. Every one of them is a quota in disguise
— "keep N of this" — so each belongs in `QuotaFor` as an entry with its own gate.
Floors are checked top-down, first-short-wins; shares go through the ratio.

**Done** (2026-08-12):

| rule | as a quota entry |
|---|---|
| `RezBotFloor` | floor on the rez def, `min(wreckSeen / REZ_METAL_PER_BOT, REZ_FLOOR)`, bot lab only |
| `AirConMinimum` | floor of `AIR_CON_MIN` on the air plant's builder role |

**Remaining nine**, with the shape each needs:

| rule | shape | what it needs |
|---|---|---|
| `EyesForTheGuns` | floor | already covered by the scout floor; verify it fires once T2 guns stand, then delete the rule |
| `LateFighterScreen` | floor | fighter def, count from `Military::AirThreatSeen()`; air plant only |
| `LateRadarPlane` | floor of 1 | radar plane def, gated on the same lateness test the rule uses |
| `AirConMinimum` | done | — |
| `BankBuysBuildPower` | **share modifier** | not a count — it says "when the bank is full, buy more build power". Belongs as a multiplier on the constructor floor, which `QuotaFor` already does via `apex_con_full_mult`. Check it is equivalent, then delete |
| `RushBuildPower` | share modifier | same shape as above, gated on `RushReady()` |
| `ShareAdvancedCon` | floor | advanced constructor count for the team, not for us — needs a team-wide count, which `CCircuitDef::count` is not |
| `DefensiveComposition` | **share shift** | changes the mix toward riot/assault when behind; belongs in `gMix` as a counter weight, not as a floor |
| `LosingArmyPush` | share shift | same: it is a statement about the army mix, not a count |
| `EcoLeadLine` | **whole-line policy** | says "this line should be quiet". Belongs as a `TierShare`-style multiplier over the whole quota for that line, not as an entry |

The last four are the interesting ones: they are not floors at all, and folding
them in as floors would be the same category error that made the constructor win
every tie. Two are mix weights and two are line-level multipliers.

## The order to work in (revised)

0. **Re-baseline the harness.** Every conclusion in this file above the review
   line was drawn at the default speed cap, where apex's commanders idle 59-81%
   against stock's 21-39%. Decide what speed factory work is measured at, and
   gate on `facQueued` (now in `dev_stats_export.lua`) staying in stock's range.
1. **Make the throttle keep its own books.** Count issued orders, subtract what
   the queue read confirms, and never issue while `outstanding >= ahead`. That
   also makes the AI correct under a laggy host, which a hosted game is.
2. **Give the combat quota a real denominator**, or stop dividing by one: read
   `[GAME] MaxUnits` from the start script, or size the quota off army metal
   the economy can sustain. While every ratio is `0.00` the composition is
   decided by the order of a C++ array.
3. **Break the tie deliberately.** `ratio < worst` plus "constructor first in the
   array" is an accidental policy. Constructors and scouts are floors; they
   should be *checked* as floors, then the ratio should decide among combat roles
   only.
4. **Stop `AiMakeTask` enqueueing.** Every rule that calls `Enqueue` before
   returning leaks once per `Reevaluate`. Either return an existing task, or
   remember the one already placed for this builder.
5. Only then: fold the eleven silenced rules into the quota table, and re-run
   green.
