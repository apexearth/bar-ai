# Factory production — the engine mechanisms underneath it

What the engine and CircuitAI actually do when a factory is told to build
something. Read from source 2026-08-11/12 and cited by file:line so it is not
re-derived. The *policy* built on top of this — who decides what a line makes —
lives in the `ai-factory-brain` skill, not here; this file is only the physics.

**Citation caveat.** `vendor/engine` is at tag **2026.06.12** (commit `01b3161`);
matches run on **2026.07.04**. The mechanisms below are long-standing and were
confirmed by measurement as well as by reading, so they hold. Exact line numbers
and constants may not.

## 1. A recruit task wipes the factory's queue

`CRecruitTask::Finish()` (`task/static/RecruitTask.cpp:108`) calls `Cancel()`,
which walks the factory's engine command queue, collects every negative (build)
cmdId and issues `CmdRemove(params, ALT|CONTROL)`.

So a standing queue **cannot survive its own first completion** under the task
scheme: the task that produced unit #1 wipes orders #2..#N. `CmdRepeat` does not
save it — the engine re-appends a finished order to the back of the queue and
that same `CmdRemove` takes every build command with it.

**Consequence: a factory line is ours or CircuitAI's, never both.** No blending;
the switch is per factory. This is why `facqueue` aborts recruit tasks on a line
it adopts rather than co-existing with them.

## 2. SHIFT multiplies a factory build order by FIVE

`CFactoryCAI::GetCountMultiplierFromOptions`
(`rts/Sim/Units/CommandAI/FactoryCAI.cpp:150`):
`if (opts & SHIFT_KEY) ret *= 5; if (opts & CONTROL_KEY) ret *= 20;`

**Never shift-append to a factory.** Use `CMD_INSERT`, which carries no
multiplier — which is exactly why BAR's own quota widget uses it.

## 3. BAR's Quota Mode cannot be turned on by an AI

`luarules/gadgets/unit_factory_quota.lua` only stores a 0/1 flag on the factory's
command description; it contains no production logic at all.
`luaui/Widgets/unit_factory_quota.lua` does all the work, scopes everything to
`unitTeam == myTeam`, and removes itself when spectating. Both files are
byte-identical in `BAR.sdd` and `vendor/bar`. Sending `CMD_QUOTA_BUILD_TOGGLE`
(id 23000) would light the icon and change nothing; emulating the widget is the
only route.

What the widget does, and what is worth copying: every 15 frames, pick the unit
type with the lowest `count/quota` ratio (counting units *that factory* built
which are still alive) and `CMD_INSERT` **one** order. It inserts at position 1
rather than 0 when the in-progress unit is more than 7.5% built or more than 500
metal in, so it never destroys work.

## 4. The bound surface — do not assume anything else exists

`CFactoryManager` in `vendor/circuitai/src/circuit/script/FactoryScript.cpp`
binds **only**: `DefaultGetFactoryToBuild`, `DefaultMakeTask`, `Enqueue`
(recruit + serv), `GetRoleDef`, `GetFactoryCount`, `isAssistRequired`,
`buildpowerRatio`, `responseWeight`, and the tier-weight/importance setters.

**Not bound:** `CanEnqueueTask`, `GetTasks`. That is why every script-side
`Enqueue` is blind and why the sent-order ledger has to be kept in script.

`CCircuitUnit` bindings added by this repo (`cpp/src/circuit/script/InitScript.cpp`):
`CmdMoveTo`, `CmdRepeat`, `GetHealthPercent`, `CmdBuildUnit`. Stock adds
`GetPos`, the attribute calls, `SetFireState`, `SetMoveState`, `SelfDestruct`,
`GetRulesParam`, and the `task` property.

`IUnitTask` exposes `GetType`, `GetUnits`, `Abort`, `Done` — and in the running
DLL `GetBuildType`, `GetBuildPos`, `buildDef` and `target` resolve on
`IUnitTask` directly. **`cast<IBuilderTask@>(...)` does NOT compile** — it fails
with `Identifier 'IBuilderTask' is not a data type`. Call the methods on the
`IUnitTask@` parameter, as `manager/builder/events.as` does.

## 5. Who may assign a task to a unit

`ITaskModule::AssignTask(unit, task)` (the two-argument form) is called from
`IBuilderTask::Reevaluate`, `IBuilderTask::Finish`, `CRecruitTask::Finish` and
`AssignPlayerTask` — **not** only from `MakeTask`. For *factories* the practical
conclusion still holds (a line held on a `Wait` task cannot be handed a recruit,
though tasks assigned before takeover keep running), but the general statement is
false, and believing it hid a re-election bug on the builder side for a session.

`ITaskModule::TaskAdded` unconditionally forwards to the script
(`TaskModule.cpp:89`), and `CFactoryManager::Enqueue` calls it — so tasks created
in C++ **do** reach the script task hooks.

## 6. The unit limit callbacks

`skirmishAiCallback_Unit_getMax` returns `unitHandler.MaxUnits()` — engine-wide,
reads 32000 here. `Unit_getLimit` is per team and reads 3938 on this machine,
which nothing in the 2026.06.12 source produces for eight teams
(`MAX_UNITS/9 = 3555`, `MAX_UNITS/8 = 4000`); the running engine derives it
differently. Unresolved — establish it by varying `--per-side` and watching the
number move, not by reading the vendored tree.

The older note here claimed `Unit_getLimit` indexes an `AI_TEAM_IDS` array
"declared `= {{-1}}` and never assigned". **That is wrong**: in
`recoil_2026.07.04` it is assigned at `SSkirmishAICallbackImpl.cpp:5535`
(`AI_TEAM_IDS[ai->GetSkirmishAIID()] = ai->GetTeamId()`). The separate
observation that `Game_getTeamResource*` returns -1 has not been re-measured on
this engine; treat both the reading and its explanation as unverified.

## 7. Orders lag the tick that sends them

`CAICallback::GiveOrder` (`rts/ExternalAI/AICallback.cpp:369`) never touches the
unit — it sends a net message, and the command lands when that message is
consumed. **The lag scales with sim speed.** Measured 2026-08-12: at the
benchmark's default speed cap (~37x realtime) a factory read `CountQueued == 0`
for 45 consecutive updates and then took all 56 queued orders in one tick; at
`--speed 3` the same code read 2-9 throughout.

Any loop of the form "read what the unit has, top it up" issues one order per
tick for the whole lag window. Keep a count of what was SENT and use the read
only to confirm it. This is also a benchmark trap: a headless run at max speed
exercises a different code path from the game apexearth watches.

See the `async-sim-orders` skill for the full treatment.
