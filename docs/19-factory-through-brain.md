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
