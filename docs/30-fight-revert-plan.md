# 30 — Fight revert plan (C++ layer)

*Written 2026-09-07, read-only audit. No file was edited, built or deployed.*

apexearth: *"I'm inclined to just want to revert almost all our fight logic back
to barb... It is terribly tempermental to change."* and *"the brain stuff, wants,
building, thats all working 'well enough' to keep. Even nuke logic, air raid
logic, these things are doing well."*

This plan covers **only** `cpp/`. AngelScript is a separate plan.

---

## 0. The reference tree is wrong, and that changes everything

`docs/29-what-barb-does-better.md` diffs us against
`vendor/circuitai/src/circuit/`. That tree is clean upstream, but it is a
**different, newer upstream than our fork base**, and its files will not compile
in our tree:

| | `vendor/circuitai` | our fork base | ours |
|---|---|---|---|
| geometry namespace | `geom::is_valid` | `utils::is_valid` | `utils::is_valid` |
| `util/ExtAS.h` | present | absent | absent |
| `THREAT_BASE` | removed | `0.f` | `0.f` |
| `terrainMgr->GetRandomMovePosition` | present | absent | absent |

**The correct revert baseline is commit `0ef36267` in the BARb build tree**
(`vendor/engine/AI/Skirmish/BARb`, `git merge-base apex/barbarian HEAD`). Revert
with `git checkout 0ef36267 -- src/circuit/<file>`, never by copying from
`vendor/circuitai`.

Diffing against the correct baseline also shrinks the apparent delta: e.g.
`MilitaryScript.cpp` is 7 lines of apex change, not 27; `ScoutTask.cpp` 28, not
37; `ThreatMap.h` 14, not 19. Some of what docs/29 attributes to us is upstream
drift.

### The real apex change surface (vs `0ef36267`, changed lines)

```
1440 task/fighter/SquadTask.cpp      579 task/fighter/FighterTask.cpp
1237 module/MilitaryManager.cpp      547 unit/CircuitUnit.cpp
1194 task/fighter/AttackTask.cpp     399 task/RetreatTask.cpp
 864 task/fighter/DefendTask.cpp     349 unit/enemy/EnemyManager.cpp
 338 task/fighter/RaidTask.cpp       230 task/UnitTask.cpp
 181 unit/CircuitUnit.h              172 task/fighter/BombTask.cpp
 147 task/fighter/AntiAirTask.cpp    129 task/fighter/SquadTask.h
 100 module/MilitaryManager.h         95 map/InfluenceMap.cpp
  58 task/fighter/FighterTask.h       56 task/fighter/AntiHeavyTask.cpp
  54 task/fighter/SupportTask.cpp     51 task/fighter/DefendTask.h
  50 unit/enemy/EnemyManager.h        42 task/fighter/AttackTask.h
  39 task/fighter/ArtilleryTask.cpp   35 map/ThreatMap.cpp
  33 task/UnitTask.h                  31 map/InfluenceMap.h
  28 task/fighter/ScoutTask.cpp       14 map/ThreatMap.h
   7 task/fighter/RaidTask.h           7 script/MilitaryScript.cpp
   2 task/fighter/RallyTask.cpp        0 task/fighter/GuardTask.cpp
```

### One correction to docs/29 worth knowing before deciding

**Stock already has range rows and arc placement.** `ISquadTask::Attack` in the
baseline keys `rangeUnits` by weapon range, walks the rows, and spreads each row
on an arc around the target at `RANGE_MOD` (0.8) of its range. Reverting
`SquadTask.cpp` does **not** turn the army into a ball, and it does not put long
guns in front. What it removes is everything layered on top: kiting, the orbiting
standoff ring, wrap, focus-fire/set-target, formation slots, cohesion derating,
the goal-hold, and the squad retreat vote.

---

## 1. Bucket table

**REVERT** = pure fight logic, back to `0ef36267`.
**KEEP-AIR / KEEP-NUKE** = he says these work.
**KEEP-INFRA** = the economy/brain/script layer or a crash fix depends on it.
**UNSURE** = needs his ruling (§5).

### `task/fighter/`

| file | bucket | notes |
|---|---|---|
| `SquadTask.cpp/.h` | **REVERT** (with 4 carve-outs) | see §1.1 |
| `AttackTask.cpp/.h` | **REVERT** whole | nothing outside fighter reads it |
| `DefendTask.cpp/.h` | **REVERT** whole | costs `apex: leash` telemetry and the `post` order tag — §3 |
| `FighterTask.cpp/.h` | **REVERT** (with 2 carve-outs) | see §1.2 |
| `RaidTask.cpp/.h` | **REVERT** | `CanAssignTo` is already byte-identical to stock; raids are starved in AngelScript, not here |
| `AntiAirTask.cpp` | **KEEP-AIR** | AA massing hold, mixed-type AA squads, 4000-elmo join radius, crash-safe seed position |
| `BombTask.cpp` | **KEEP-AIR** | bomb-target de-confliction, energy-stream pricing, nanoframe pricing |
| `AntiHeavyTask.cpp` | **KEEP-INFRA** | 56 lines, almost all crash guards (`GetTravelAct()` null, seed position) |
| `ArtilleryTask.cpp` | **KEEP-INFRA** | crash guards + `CmdAttack`; one small revert candidate (roam fallback) |
| `ScoutTask.cpp` | **KEEP-INFRA** | crash guards + `OrdSrc::SCOUT` tag |
| `SupportTask.cpp` | **UNSURE** | `ESCORT_PER_SQUAD = 2` is his number, paired with `brain/facqueue.as` |
| `RallyTask.cpp` | **KEEP** (telemetry) | 2 lines: one `OrdSrc::RALLY` tag |
| `GuardTask.cpp` | untouched | 0 lines |

#### 1.1 `SquadTask` carve-outs — do not delete these symbols

| symbol | read by |
|---|---|
| `GetHealthScale()` | `AntiAirTask.cpp`, `AntiHeavyTask.cpp` (both KEEP), plus Attack/Defend/Raid |
| `GetSpreadRadius()` | `unit/action/SupportAction.cpp` (escort standoff) |
| `LinePos()` | `unit/action/SupportAction.cpp` |
| `IsChargeDef()` | `AttackTask.cpp` (goes away with it, but check) |

`AntiAirTask` and `AntiHeavyTask` are KEEP files that call `GetHealthScale()`.
Reverting `SquadTask.cpp` without keeping it is a **C++ compile error** — loud,
not silent, which is the good failure mode. Keep the three accessors as a small
appendix on the reverted `ISquadTask`.

#### 1.2 `FighterTask` carve-outs — do not delete these symbols

| symbol | read by | why it must live |
|---|---|---|
| `IFighterTask::RoamPos()` | `AntiAirTask`, `AntiHeavyTask`, `ArtilleryTask`, `BombTask`, `RaidTask` | four of five are KEEP files |
| `IFighterTask::FightTypeName(int)` | `module/MilitaryManager.cpp` (stale-task crash log), `unit/action/TravelAction.cpp` | bounds-checked name for a value recovered from the task registry |

Everything else in `FighterTask` — `KeepRange`, `DodgeFire`, `CounterBattery`,
`SafeStandoff`, `LeadPos`, `AttackEnemy`, `MarkCoward`/`IsCoward`,
`TrySquadRetreat`, `IsDiveCommit`, the retreat-source counters — is REVERT.

Note `cowards` itself is **stock**; only the accessors are ours.

### `module/MilitaryManager.{cpp,h}` — the dangerous file

This is one file holding four unrelated things. **Never revert it wholesale.**

| what | bucket | why |
|---|---|---|
| `DefaultMakeDefence` / `DefaultMakeSensors` / `MakeBaseDefence` stubbed to `return;` | **KEEP-INFRA** | the 2026-08-22 "the DLL originates no economy/build decisions" strip. Reverting restores engine-side tower **and sensor** placement that would compete with the script Brain's placement — an economy regression, not a fight one |
| `MakeSensors()` extraction | **KEEP-INFRA** | support for the above |
| stale-task registry guards in the attacker idle / damaged / destroyed handlers | **KEEP-INFRA** | crash fix (`IsTaskStale`, `CIRCUIT_TASK_REGISTRY`) |
| `guardTasks` erase-before-abort, and erase-by-value in `DequeueTask` | **KEEP-INFRA** | two separate use-after-free fixes, both with the mechanism written down |
| `PushUpdate(task)` for `updateTasks.push_back` | **KEEP-INFRA** | scheduler plumbing |
| scheduler job names `"milIdle"/"milUpd"/"milDef"/"milRaid"/"wdog"` | **KEEP-INFRA** | `frametime.py` reads them |
| `cdef.SetIsJammer(...)` in the def loop | **KEEP-INFRA** | the script's jammer wants read it |
| `SRoleInfo::SVsInfo` explicit constructor | **KEEP-INFRA** | compiler compat |
| `NoteBombTarget` / `LastBombFrame` | **KEEP-AIR** | `BombTask.cpp` |
| `NoteSuperTarget` / `IsRecentSuperTarget` | **KEEP-NUKE** | `task/static/SuperTask.cpp` — stops N silos firing N warheads into one crater |
| `IsCommCloakWanted` / `UpdateCommCloak` / `commCloakStallTicks` | **KEEP-INFRA** | commander; also read by `task/RetreatTask.cpp` |
| `SetGuardPost` / `ClearGuardPosts` / `GetGuardPost` | **KEEP-INFRA** (see §2) | bound into AngelScript |
| `GetDefenceStand`, `IsStrongpoint`, `fencePos`, and the DEFEND-enqueue position override | **REVERT** | |
| `GetGuardAnchor` (both), `GuardSpotScore`, `FillDefencePos`, guard-flip telemetry | **REVERT** | |
| front-first insertion in `FillFrontPos` / `FillAttackSafePos` / `FillStaticSafePos` | **REVERT** | |
| `UpdateDefenceTasks` per-pool hot-spot anchoring | **REVERT** | |
| **the ARMY SPLIT block** (`apex_army_split`) | **REVERT** | ON by default and **not in the gadget** — §4 |
| `DispatchRaids` + `raidTrack` | **REVERT** | already inert: `apex_intercept` defaults 0 |
| `GetFrontierPos` + the forward-placement override in `UpdateDefence` | **REVERT** | but it is a *placement* rule, not a fight rule — check with the AngelScript plan |
| `apex_attack_share` cap in `DefaultMakeTask` | **REVERT** | docs/29 shows it is overwritten within 5 s by `SetMaxPower` — inert |
| `apex_raid_first` in `DefaultMakeTask` RAID branch | **UNSURE** | §5 |

### `map/ThreatMap.*`, `map/InfluenceMap.*`

**KEEP-INFRA, entirely. There is no fight logic in either.** The whole delta is:
perf counters (`perfCells`, `perfPaints`, `perfApplyUs`, relaxed atomics),
scheduler job names, one copy elision in the decloak loop, `final` removal, and
moving the LuaRules **widget** visualisation out of `#ifdef DEBUG_VIS` so
`~widraw` works in a shipped build. Touching them buys nothing and costs
`frametime.py`.

### `unit/CircuitUnit.{cpp,h}`

**KEEP-INFRA / KEEP-TELEMETRY, entirely.** This file is the instrument the
revert will be judged with (§3). It holds `OrdKind`/`OrdSrc`/`NoteOrder`/
`OrdSrcName`/`OrdSrcPrio`, the `apex: ord` trace, travel-goal progress
(`SetTravelGoal`/`NoteGoalDist`), the act ring and `GetActTrace` (bound to
AngelScript, used by `deaths.py`), the `Wake` enum, `CmdAttack`/`SniperHoldPos`,
the D-gun hold, and the `ClearAct` shadow that fixed a heap-corrupting UAF.

The one thing that becomes vestigial is `InFormation()` / `SetFormSlot` — nothing
sets a slot once `SquadTask` reverts. Leaving it costs nothing (the slot defaults
to 0 with an invalid direction and the funnel passes the point through). Delete
it later if at all.

### `unit/enemy/EnemyManager.{cpp,h}`

**KEEP-INFRA, entirely.** `GetEnemyCostFresh` (19 AngelScript call sites),
`GetEnemyGroup*` (11+), `GetEnemyStructPos`/`GetEnemyStructCost`,
`GetEnemyAirCostNear`, `GetEnemyMaxMobileCostM`, `PurgeStaleGhosts`, the fresh
bucket and its `SetFreshSeconds`. Removing any of these is an **AngelScript
compile failure**, which per `docs/25` S3 means the variant plays near-stock
while still writing a normal-looking result.

### `task/UnitTask.{cpp,h}`

**KEEP-INFRA.** Task liveness registry (`Probe`, `SLiveness`, `TypeName`,
`NoteSubtype`) and `IntentPing`. Reverting fighter `.cpp` files removes the
`NoteSubtype` calls in their constructors — the registry then reports a task's
type but not its fight subtype. Still compiles; worth re-adding one line per
reverted constructor.

### `task/RetreatTask.cpp`

Mixed.

| what | bucket |
|---|---|
| commander cloak affordability via `IsCommCloakWanted` | **KEEP-INFRA** (commander) |
| `GetTravelAct()` null guards, `CPathInfo` allocation | **KEEP-INFRA** (crash) |
| haven threat re-check (`GetEnemyInflAt(endPos) >= INFL_EPS` → base) | **UNSURE** — §5 |
| `GetRallyPos` / `GetRearHaven` | **REVERT** |
| heal-post (`apex_retreat_behind`) | **REVERT** — already inert, default 0 |

### `script/MilitaryScript.cpp`

7 lines, 5 added registrations. See §2.

### `script/InitScript.cpp`

**DO NOT REVERT.** 1,061 changed lines, and essentially all of it is the
economy/brain binding surface (`GetTunable`, `PublishTeamValue`, wreck/rez
positions, choke points, `CCircuitDef` accessors, `CSetupManager`). The
fight-relevant registrations point at `CircuitAI.cpp` and `CEnemyManager`, both
of which stay.

### `CircuitAI.{cpp,h}`

Not in the revert set, but named here because the fight files are its only
readers for several members — see §2.2.

---

## 2. The binding surface

### 2.1 Registrations that break outright

| binding | implemented in | breaks if… |
|---|---|---|
| `CMilitaryManager::SetGuardPost(CCircuitUnit@, AIFloat3, float)` | `MilitaryManager.{cpp,h}` (apex) | reverting `MilitaryManager.h` → **C++ compile error** in `MilitaryScript.cpp`. Reverting `MilitaryScript.cpp` while `military/guardposts.as` still calls it → **AngelScript compile error** → S3 silent near-stock variant |
| `CMilitaryManager::ClearGuardPosts()` | same | same |
| `CMilitaryManager::DefaultMakeSensors(int, AIFloat3)` | same | C++ compile error only — no AngelScript caller found (0 hits) |
| `CMilitaryManager::GetBaseDefRange()` / `SetBaseDefRange(float)` | **baseline** — not ours | safe. Only the *registration* is ours |
| `CCircuitUnit::GetActTrace()` | `CircuitUnit.h` (KEEP) | safe |
| `IUnitTask::GetFightType()` | `InitScript.cpp` shim over stock `IFighterTask::GetFightType` | safe |
| `IUnitTask::GetUnits/RemoveUnit/Abort/Done` | `UnitTask`/`TaskModule` (KEEP) | safe |
| every `CEnemyManager::GetEnemyGroup*`, `GetEnemyCostFresh`, `freshMobileThreat`, `SetFreshSeconds`, `GetEnemyStruct*` | `EnemyManager` (KEEP) | safe **provided EnemyManager is not reverted** |
| every `CCircuitAI::*` fight binding (`SetFrontPos`, `SetEngageBoost`, `SetCommitted`, `GetAttackHotspot`, `GetAllyInflAt`/`GetEnemyInflAt`/`GetNetInflAt`, `GetUnitThreatAt`, `EnemyReachSlack`, choke points) | `CircuitAI.cpp` (KEEP) | safe |

**Verdict: exactly three registrations are at risk, all in
`script/MilitaryScript.cpp`, and the rule is simple — do not revert
`MilitaryScript.cpp`, and keep `SetGuardPost`/`ClearGuardPosts`/
`DefaultMakeSensors` on `CMilitaryManager` even after the fight revert.** Keeping
a setter whose reader is gone is cheap; deleting it is either a build failure or
an S3.

### 2.2 The bigger risk: bindings that go SILENT, not broken

These compile fine and stop doing anything. This is the class `docs/25` calls the
only real bug in this repo.

| the script keeps calling | the C++ readers | after the revert |
|---|---|---|
| `ai.SetFrontPos(pos)` — `military/posture.as` | `FighterTask::RoamPos`, `DefendTask` (×3), `MilitaryManager::FillFrontPos`/`FillAttackSafePos`/`FillStaticSafePos`, `RetreatTask` | only `RetreatTask` survives. The front line the script computes every tick stops steering anything |
| `ai.SetEngageBoost(f)` — killing blow / posture | `AttackTask::TradeScaledMargin` only | **no readers left.** Killing blow becomes decorative |
| `ai.SetCommitted(bool)` | `AttackTask:443`, `FighterTask:324`, `SquadTask:277` | **no readers left** |
| `aiMilitaryMgr.SetGuardPost(...)` — `military/guardposts.as` | `DefendTask::FallbackPosts`/`LeashPosts` only | **no readers left** |
| `aiMilitaryMgr.SetBaseDefRange(f)` — `SetupManager` | `DefendTask`, `RaidTask`, `SuperTask`, `BuilderTask` | partially survives (Super/Builder) |

**Every one of these must be paired with the AngelScript plan.** Either the
script stops computing them, or a `deadcheck.py` pass will read "the rule fires"
forever while nothing downstream listens. Hand this table to the AngelScript
agent.

---

## 3. Telemetry that must survive the revert

`tools/behave.py` is how the revert gets judged. It reads three things.

| instrument | emitted at | survives? |
|---|---|---|
| `apex: ord t=… src=… kind=… to=… jump=… gap=…` | `unit/CircuitUnit.cpp:487`, gated on `apex_order_trace` | **yes** — `CircuitUnit.cpp` is KEEP |
| `apex: squadsize own n=… \| enemy n=…` | `CircuitAI.cpp:982` | **yes** — `CircuitAI.cpp` is KEEP |
| `apex: fightcensus tasks/units/metal …` | AngelScript, `military/fightcensus.as:75` | **AngelScript plan's problem, not ours** |

The catch is **attribution, not the trace**. `behave.py` partitions orders into
`STAND = {post, ring, regroup, patrol, rally, standoff, retreat}` and
`FIGHT = {engage, attack, combat, sniper}` using the `OrdSrc` tag at the call
site. Those tags are per-call-site arguments in the files being reverted:

```
DefendTask.cpp 5   AntiAirTask.cpp 3   AttackTask.cpp 2   FighterTask.cpp 2
RaidTask.cpp   1   ScoutTask.cpp   1   RallyTask.cpp  1   SupportTask.cpp 2
ArtilleryTask.cpp 1  AntiHeavyTask.cpp 2  RetreatTask.cpp 2  UnitTask.cpp 1
FightAction.cpp 4   MoveAction.cpp 4    SupportAction.cpp 1  BuilderManager.cpp 1
```

Reverting `DefendTask.cpp` deletes the only `post` tags; reverting `AttackTask`,
`FighterTask` and `RaidTask` deletes `engage`/`standoff`/`dodge` tags. Stock calls
`CmdMoveTo(pos, opts, timeout)` with no `src`, which lands in `OrdSrc::OTHER` —
so after a naive revert **the STAND/FIGHT split collapses into `other` and
`behave.py` stops being able to answer the question the revert was run to
answer.**

**Requirement: every reverted file gets its `OrdSrc` argument re-added at each
`CmdMoveTo` / `CmdFightTo` / `CmdAttack` call site before the arm is measured.**
The reverted stock call sites are few (stock `SquadTask::Attack` and
`AttackTask::Update` are ~430–490 lines each). Budget one pass per file.

Also lost, and worth deciding on explicitly:

- `apex: leash …` (`DefendTask.cpp:1075`) — dies with `LeashPosts`. It measures a
  behaviour that will no longer exist, so losing it is correct, but note that
  `game-audit`/`dashboard` entries keyed on it go stale.
- `apex: guardflip` / `apex: guardsum` (`MilitaryManager.cpp`) — same, dies with
  the per-pool anchoring it measures.
- `IUnitTask::NoteSubtype` calls in reverted fighter constructors — re-add one
  line each so the stale-task crash log keeps naming fight subtypes.

---

## 4. Order of operations

Rules 2 and 4 of `docs/26-working-rules.md` apply throughout: one behaviour per
step, judged on `composition.py` + `behave.py`, and two seeds are an anecdote.

### Step 0 — before anything: claim a lane

`python tools/lane.py init fightrevert`. Another session shares this build tree
and deploy target (`docs/28-parallel-sessions.md`). A shared-tree edit was
destroyed 2026-09-07.

### Step 1 — turn the fight layer OFF with modoptions. No rebuild. **Do this first.**

108 distinct `apex_*` tunables are read in the fight C++, and **103 of them are
already published in `game-patches/gadgets/dev_tunables.lua`** (501 names total).
Most apex fight behaviours default to `1.f` and can be switched off from the
launcher.

This is the cheapest, safest and most informative first move, and it satisfies
"instrument first": it answers *how much of the gap is the fight layer at all*
before a single line is deleted, and it is reversible in one launch argument.

Suggested arms, one at a time:

| arm | modoptions |
|---|---|
| A — per-damage micro off | `apex_standoff=0 apex_dodge=0 apex_counter_battery=0` |
| B — attack delays off | `apex_flank_pct=0 apex_assemble=0 apex_attack_break=0` |
| C — pool partitioning off | `apex_hot_radius=9000 apex_defend_post=0 apex_guard_posts=0` |
| D — squad shape off | `apex_wrap_arc=0 apex_kite_frac=0 apex_goal_hold=0 apex_squad_retreat=0` |
| E — everything above at once | the union |

**Trap (S8):** the gadget is deployed separately from the AI
(`deploy_ai.py gadgets`). An unpublished name runs the default with no error.
**Five fight tunables are NOT in the gadget and cannot be switched off this way:**

```
apex_army_split (default 1.f — ON), apex_split_cd, apex_split_hold,
apex_split_margin, apex_split_min_dist
```

So the army-split behaviour in `UpdateDefenceTasks` is live and unswitchable.
Either add the five names to the gadget (a one-line-per-name change, no rebuild
of the DLL) or accept that arm E does not include it.

If arm E lands at or near stock's result, **most of the C++ revert below is
unnecessary** and the plan collapses to deleting dead code at leisure. If arm E
does not close the gap, the problem is not the tunable-gated layer and the
structural reverts in steps 3–6 are justified. Either answer is worth more than
any single revert.

### Step 2 — bank the deletions that cost nothing

Two behaviours are already inert at their defaults, so removing them is a pure
code-size win with a guaranteed-zero behaviour delta. Do them together, in one
build, and confirm `behave.py` and `composition.py` are unchanged — that
confirmation is also a **check that the build pipeline is honest** before any
real revert rides on it.

- `CMilitaryManager::DispatchRaids` + `raidTrack` + `CDefendTask::Dispatch`/
  `IsDispatched`/`GetDispatchPos` (`apex_intercept` = 0)
- `RetreatTask` heal-post (`apex_retreat_behind` = 0)

### Step 3 — `FighterTask.cpp/.h`: the per-damage micro layer

Smallest structural revert (579 lines), highest measured churn, and the one
apexearth watched: *"we stand around worthlessly going in circles."* Removes
`KeepRange`, `DodgeFire`, `CounterBattery`, `SafeStandoff`, `LeadPos`,
`AttackEnemy`.

Keep `RoamPos` and `FightTypeName` (§1.2). Re-add `OrdSrc` tags (§3).
This step alone also closes docs/29 #6 — `CounterBattery` charging aircraft —
because the function is gone.

Measure against step 1 arm A. If arm A already moved the number, this step should
reproduce it; if it does not, the revert is doing something arm A did not, and
that is worth knowing before step 4.

### Step 4 — `AttackTask.cpp/.h`

1,194 lines. Engage margin, the double odds test, flank, assemble, attack-break,
risk escalation, ally aggregation. Self-contained: nothing outside `task/fighter/`
reads it. Compare against step 1 arm B.

### Step 5 — `SquadTask.cpp/.h`

1,440 lines, the largest. Keep the four accessors in §1.1 or the build fails.
Compare against arm D.

### Step 6 — `DefendTask.cpp/.h` + the MilitaryManager fight parts

Do these **together**, because they are one mechanism: `DefendTask` consumes the
anchors and posts that `UpdateDefenceTasks` and `GetGuardAnchor` produce.
Reverting one alone leaves the other running against nothing.

Surgical, not wholesale, for `MilitaryManager.cpp` — the KEEP rows in §1 are
interleaved with the REVERT rows in the same file. Extract the reverted functions
by hand against `0ef36267`; do not `git checkout` the file.

### Step 7 — `RaidTask.cpp/.h`

Last, because docs/29 #8 shows the raid machinery is fine and the starvation is
upstream in AngelScript. If the AngelScript plan restores stock's
`DefaultMakeTask` routing, this may want to stay as-is.

### Never

`ThreatMap.*`, `InfluenceMap.*`, `CircuitUnit.*`, `EnemyManager.*`,
`UnitTask.*`, `InitScript.cpp`, `MilitaryScript.cpp`, and the KEEP rows of
`MilitaryManager`.

---

## 5. What reverting COSTS — complaints it re-opens

Each of these is a directive in `docs/24-how-units-fight.md` that stock does not
implement. He would rather know than be surprised.

| directive (docs/24) | implemented by | reverted at |
|---|---|---|
| *"Fight at about 90% of maximum attack range. Do not move any closer."* (his number) | `STANDOFF_RANGE_MOD 0.90` | step 5 → back to stock `RANGE_MOD 0.8` (80%, i.e. **closer in**, not further out) |
| *"Kite the enemy, often."* | `SquadTask` kite rows | step 5 — stock has no kiting at all |
| *"Almost always stay moving... circle around the enemies they are shooting."* | `ORBIT_RATE` precession | step 5 |
| *"A more powerful unit does not run from a longer-ranged weaker one"* (Thug vs Rocketeer) | `POWER_DOMINANCE_RATIO 1.15` | step 5 |
| *"Units that can be D-gunned together must spread out"* | `CHARGE_SPACING 360` | step 5 |
| *"best would be if the hurt guys just move towards the back of the pack"* | `COWARD_REAR_MOD` | step 5 |
| *"Use move orders plus set-target, not attack-this-unit"* / *"Concentrate fire on the lowest-HP enemies"* | `SquadTask` focus-fire pool | step 5 — but note this was **measured harmful in both shapes and already defaults off** (`apex_focus_finish` = 0) |
| *"back up before the enemy can fire back"* / *"being 10% out of the enemy's range is the moment to move"* | `KeepRange` | step 3 |
| *"Standoff moves must not walk a unit into a new threat"* | `SafeStandoff` | step 3 |
| *"Big T3 units... shoot the most valuable target within range and keep moving into the enemy base"* / juggernaut charge | `IsChargeDef` + charge doctrine in `AttackTask` | step 4 |
| *"Near the enemy base, dive straight in and target their economy"* | `diveCommit` | step 4 |
| *"we are too cowardly"* — the engage bar walked down from 2.16 → 1.80 → 1.35 | `ENGAGE_MARGIN` | step 4. **Stock's is 1.0** — this revert makes us *braver*, not more cowardly |
| *"After a raid on enemy mexes, go further and take out more"* | `CRaidTask::FindOnwardSpot` | step 7 |
| *"the enemy is attacking one of our frontline bases and our huge army isn't there"* | per-pool anchoring + army split | step 6 — this is the complaint the split was built for |
| *"If the base has enough defenses to handle what's attacking it then we don't need to send our army"* | standing-guns subtraction in the split | step 6 |
| *"our retreats are often ALL THE WAY BACK TO THE BASE"* / *"sometimes our retreat logic takes us into new threats"* | `RetreatTask` haven re-check + heal post | UNSURE / step 2 |
| *"Attach a maximum of 2 jammer and 2 radar to the squads"* (his number) | `ESCORT_PER_SQUAD` | UNSURE |

Three of these — the 90% standoff, the D-gun spacing, and "not afraid of longer-
ranged weaker units" — are numbers he stated himself, not inferences. They are the
likeliest things he will miss.

---

## 6. UNSURE — needs apexearth's ruling

Listed in §5 of the report, not restated here. The five items are:
`apex_raid_first` ordering, the escort cap of 2 radar / 2 jammer per squad, the
retreat haven threat re-check, the forward-placement rule for new ground turrets
(`GetFrontierPos`), and the `apex_siege_fight` gate shared across
Artillery/Scout/AntiHeavy/AntiAir.

## apexearth's rulings, 2026-09-08

Asked as plain-language questions during planning; these are decisions, not
suggestions, and they bound the revert.

| Question | Ruling |
|---|---|
| Raid pack offered before guard duty (his own 2026-09-07 request) | **Go back to stock.** Guard duty first, as stock. Accepts fewer raids. |
| The 2-jammer / 2-radar escort cap (his own request) | **Keep.** It is a build rule -- how many to make -- not fight micro. |
| Retreat destination re-check (his own request) | **Accept stock's version.** Nearest safe spot by distance, never revisited. |
| Forward placement of ground-shooting turrets | **Keep -- it is building logic**, and the building layer stays. Out of scope. |

The pattern to read from these: he reverts BEHAVIOURS freely, including ones he
asked for, and keeps BUILD RULES. When a change is ambiguous, ask which of the
two it is rather than whether it is good.
