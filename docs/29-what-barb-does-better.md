# 29 — What BARb does better

*Written 2026-09-07, read-only audit. apexearth: "You know our concepts, what we
tried to do.... look at barb ai, it is kicking our pathetic asses. take notes."
and "we stand around worthlessly going in circles never accomplishing anything,
we never make it to enemy bases."*

Stock reference is `vendor/circuitai/src/circuit/` — verified as the clean
upstream. `vendor/engine/AI/Skirmish/BARb/src/circuit/` is NOT stock; it is our
deployed copy (its `AttackTask.cpp` quotes apexearth), and it matches
`cpp/src/circuit/` to within 6 lines. Stock's shipped script layer is
`vendor/bar/luarules/configs/BARb/stable/script/hard/`.

Every claim below carries a file:line. Statements of the form "stock does X, we
do Y" are facts. Anything labelled **HYPOTHESIS** is a causal claim I have not
measured, with the test named.

---

## 1. The delta surface

| | stock | ours | ratio |
|---|---|---|---|
| `task/fighter/` C++ | 5,037 lines | 9,933 | 2.0x |
| `SquadTask.cpp` | 488 | 1,896 | 3.9x |
| `AttackTask.cpp` | 430 | 1,573 | 3.7x |
| `DefendTask.cpp` | 412 | 1,221 | 3.0x |
| `FighterTask.cpp` | 226 | 805 | 3.6x |
| `RaidTask.cpp` | 453 | 752 | 1.7x |
| whole AngelScript layer | **562 lines** | **45,207 lines** | 80x |
| `manager/military*` script | **56 lines** (`military.as`) | 7,570 | 135x |
| tunables read in combat C++ | **0** | 108 distinct names | — |

Stock's entire military script is 56 lines and its `AiMakeTask` is one
statement: `return aiMilitaryMgr.DefaultMakeTask(unit);`
(`vendor/bar/luarules/configs/BARb/stable/script/hard/manager/military.as:7-10`).

Largest C++ diffs overall (lines changed vs stock): `CircuitAI.cpp` 1790,
`SquadTask.cpp` 1472, `InitScript.cpp` 1468, `MilitaryManager.cpp` 1280,
`AttackTask.cpp` 1211, `EconomyManager.cpp` 1167, `DefendTask.cpp` 809.

None of the combat gates listed below has an A/B recorded in
`docs/27-tunable-rationale.md` — the only combat entry there is
`apex_standoff_s` (line 176).

---

## 2. Ranked: what is most likely costing us games

### #1 — `check = MELEE` kills stock's promotion bootstrap. The army can never leave.

**This is a silent no-op of the exact class `docs/25-silent-failures.md`
describes, and it explains "we never make it to enemy bases" on its own.**

Stock, `vendor/circuitai/src/circuit/task/fighter/DefendTask.cpp:107-118`:

```cpp
if (updCount % 32 == 1) {
    CMilitaryManager* militaryMgr = static_cast<CMilitaryManager*>(manager);
    if ((attackPower >= maxPower) || !militaryMgr->GetTasks(check).empty()) {
        IFighterTask* task = militaryMgr->Enqueue(TaskF::Common(promote));
        ... assign every unit ...
```

Stock creates its defence pools with the **two-argument** form
(`vendor/circuitai/src/circuit/module/MilitaryManager.cpp:1697` and `:1711`):
`Enqueue(TaskF::Defend(FightType::ATTACK, power))`. That form sets
`check = _SIZE_` (`cpp/src/circuit/module/MilitaryManager.h:53-60`), and
`Enqueue` then constructs the task with **check = promote = ATTACK**
(`vendor/circuitai/src/circuit/module/MilitaryManager.cpp:615-620`).

So in stock the second clause reads `!GetTasks(ATTACK).empty()`. The moment one
pool clears the bar and creates the first ATTACK task, **every other defence
pool promotes on its next 32nd update** and merges into it via
`ISquadTask::GetMergeTask`. One pool clearing the bar bootstraps the whole army.

Ours (`ai/Unstable/game-side/script/standard/manager/military/hooks.as:267-268`):

```angelscript
return NoteElect("mass.attack", aiMilitaryMgr.Enqueue(TaskF::Defend(Task::FightType::MELEE,
        Task::FightType::ATTACK, aiMilitaryMgr.quota.attack)));
```

That is the **three-argument** form, so `check = MELEE`
(`cpp/src/circuit/module/MilitaryManager.h:62-70`), and
`cpp/src/circuit/task/fighter/DefendTask.cpp:201` evaluates
`!militaryMgr->GetTasks(FightType::MELEE).empty()`.

**Nothing in this codebase ever creates a task of `FightType::MELEE`.** The
enum member exists (`cpp/src/circuit/task/fighter/FighterTask.h:44`) and the only
other occurrence in the entire C++ tree is the name string at
`cpp/src/circuit/task/fighter/FighterTask.cpp:128`. The script's own comment at
`hooks.as:236-238` says so explicitly — "nothing in CircuitAI ever enqueues a
MELEE task" — and uses that fact deliberately for the *hold* branch at
`hooks.as:264-265`. The attack branch two lines below inherited the same
`MELEE` in the `check` slot, where it is not a feature.

Therefore `GetTasks(MELEE)` is **always empty**, `mayReinforce` at
`DefendTask.cpp:201-202` is **always false**, and the only surviving path out of
defence is `attackPower >= maxPower` for one pool acting alone.

What that bar is: `cpp/src/circuit/module/MilitaryManager.cpp:1612-1629` rewrites
it every 5 seconds for every ATTACK-promoting pool to
`max(minAttackers, GetPreMaxGroupThreat())` — the enemy's second-largest group's
influence (`cpp/src/circuit/unit/enemy/EnemyManager.h:124`), with `minAttackers`
= 8 from config (`MilitaryManager.cpp:431`). This overwrite is inherited from
stock (`vendor/circuitai/.../MilitaryManager.cpp:1397`) and is harmless there
*because stock has the bootstrap*.

Two consequences worth naming separately, because both are fixes that were
written and are inert:

- The `apex_attack_share` cap added in `DefaultMakeTask`
  (`cpp/src/circuit/module/MilitaryManager.cpp`, DEFEND case, `:2476-2481`) —
  whose own comment says it exists because "the AI created ZERO attack tasks in
  twenty minutes" — is **overwritten within 5 seconds** by `SetMaxPower` at
  line 1629, which applies no such cap. It is also only reachable through the
  `stock` fallthrough at `hooks.as:271`, which most line army never takes.
- The whole `MassWant()` machinery (`manager/military/massing.as:204-285`, eight
  tunables) writes `quota.attack`, which becomes the constructor argument — and
  is likewise overwritten by line 1629 for every pool that could actually
  attack. It survives only on MELEE-promoting pools, which never attack anyway.

This matches the census already in the repo: `docs/24-how-units-fight.md:665-668`
— "218 of 240 census samples had NO attack task in existence at all", 42% of
pools held one or two units, 3% ever reached their bar.

**What to try:** at `hooks.as:267`, pass `Task::FightType::ATTACK` as the
`check` argument (or use the two-argument `TaskF::Defend(ATTACK, quota.attack)`
so it matches stock exactly). One token. Measure attack-task count per game
before and after; the census line already exists.

---

### #2 — Three election branches produce units that can never attack, and they run first.

Stock's election is one line: `DefaultMakeTask`
(`vendor/bar/.../hard/manager/military.as:9`), which maps role to fight type and
sends nearly everything to a promotable defence pool
(`vendor/circuitai/.../MilitaryManager.cpp:1636-1717`).

Ours is `MakeTaskInner`
(`ai/Unstable/game-side/script/standard/manager/military/hooks.as:110-271`), and
the order matters because it is first-match:

| order | branch | file:line | result |
|---|---|---|---|
| 1 | `Air::HoldsUnit` | hooks.as:124-125 | `return null` — no task, no orders at all |
| 2 | `Factory::HoldsLateFighter` | hooks.as:126-127 | `return null` |
| 3 | bomber | hooks.as:134-136 | BOMB |
| 4 | raid pull | hooks.as:139-144 | raid pack |
| 5 | **escort** | hooks.as:152-159 | `TaskF::Guard(vip)` — a GUARD task never attacks |
| 6 | **cover** | hooks.as:166-173 | `TaskF::Defend(MELEE, MELEE, ...)` — never promotes, never raids |
| 7 | fodder | hooks.as:174-203 | solo `CScoutTask` |
| 8 | charger | hooks.as:210-221 | solo ATTACK, pinned home if base contested |
| 9 | superguard | hooks.as:225-226 | RALLY hold |
| 10 | **massing hold** | hooks.as:260-266 | `TaskF::Defend(MELEE, MELEE, ...)` — permanent |
| 11 | massing attack | hooks.as:267-268 | the pool whose bootstrap #1 killed |
| 12 | stock | hooks.as:271 | `DefaultMakeTask` |

Branches 5, 6 and 10 each yield a unit that can never take an attack task, and
they are evaluated **before** the massing pool. Branch 10 fires whenever any of
`Builder::BaseUnderAttack()` (`manager/builder/sitesafety.as:503`, enemy centroid
within 2200 of home), `BaseContested()`
(`manager/military/territory/enemy.as:128-133`, net influence at home < 0),
`BaseRaided()` (`manager/military/basedefence.as:260-266`, within 45 s of any
raid) or `ConservativeStance()` (`manager/military/massing.as:176-202`, six
sub-tests) is true.

Stock has no equivalent of 5, 6, 10 or 11. Its GUARD equivalent exists but is
only consulted *after* the raid/defend pool is offered
(`vendor/circuitai/.../MilitaryManager.cpp:1666-1697`).

apexearth, 2026-09-07: *"I didn't see us raid a single time. Everyone is too
busy escorting or guarding structures."* — that is branches 5 and 6 read off the
screen.

**HYPOTHESIS:** branches 5, 6 and 10 absorb the majority of line army. **Test:**
the `NoteElect` tag is already stamped on every election. Count
`escort` / `cover` / `mass.hold` / `mass.attack` per game from the infolog; no
code change needed.

**What to try:** move the escort and cover branches *below* the massing block,
so a unit is offered the fighting pool first and takes guard duty only when no
pool wants it — which is stock's ordering.

---

### #3 — We demand a 1.35x edge to start a fight; stock demands 1.0. And we run the test twice.

Stock, `vendor/circuitai/src/circuit/task/fighter/AttackTask.cpp:270-274` — one
test, no margin:

```cpp
if (((maxPower <= group.influence * scale) && (inflMap->GetInfluenceAt(group.pos) < INFL_SAFE))
    || !terrainMgr->CanMobileReachAt(area, group.pos, highestRange))
{
    continue;
}
```

Ours, `cpp/src/circuit/task/fighter/AttackTask.cpp:1011-1016`:

```cpp
const bool groupWeak = !isJuggernaut
        && (maxPower + groupAlly <= group.influence * scale * groupMargin) && !isHome;
if (groupWeak && !inTheirBase) { ++skippedWeak; continue; }
```

`groupMargin` is `TradeScaledMargin()` (`AttackTask.cpp:165-181`) =
`ENGAGE_MARGIN (1.35) * clamp(1/tradeRatio, 0.90, 1.00) * engageBoost`, so
1.215–1.35 in normal play.

Then we run a **second, stricter odds test that stock does not have at all**, per
candidate enemy, at `AttackTask.cpp:1251-1260`:

```cpp
if (!isJuggernaut && !isDive
    && (localInfl > .0f) && (allyPower < localInfl * nearMargin) && !isHome) {
    ++skippedWeak; ... continue;
}
```

where `localInfl` sums the influence of *every* enemy group within
`NEARBY_ENEMY_DIST` (800) of the target (`AttackTask.cpp:1176-1182`), and
`nearMargin` is the same 1.35-based margin.

And a third refusal at `AttackTask.cpp:1160-1163`: `(groupWeak || wornOut) &&
!isDive` → only unarmed fat economy qualifies.

The file's own comment history records this bar being walked down from 1.80 and
2.16 after apexearth said *"we are too cowardly"* — it was never taken to
stock's 1.0, and it is still applied twice.

**HYPOTHESIS:** the double odds test is why a squad that does leave still walks
in circles rather than committing. **Test:** `skippedWeak` and `bestRefused` are
already counted (`AttackTask.cpp:1014, 1253, 1257`); log the ratio of passes
refused at each of the three sites for one game, then A/B `ENGAGE_MARGIN` 1.35
vs 1.0 with the second test disabled.

---

### #4 — Defence pools cannot merge across anchors, so they never reach the bar.

Stock, `vendor/circuitai/src/circuit/task/fighter/SquadTask.cpp:189-196` — merge
is refused only for weaker candidates, unassignable ones, unreachable ground and
unsafe lines.

Ours adds an anchor filter, `cpp/src/circuit/task/fighter/SquadTask.cpp:388-389` (the flag) and `:414-418`
(the refusal):

```cpp
const bool isSplitAnchor = (fightType == FightType::DEFEND) && utils::is_valid(position);
const float anchorRadius = isSplitAnchor ? circuit->GetTunable("apex_hot_radius", 1000.f) : .0f;
...
if (isSplitAnchor && utils::is_valid(candidate->GetPosition())
    && (position.distance2D(candidate->GetPosition()) > anchorRadius))
{ ++rAnchor; continue; }
```

Two DEFEND pools anchored at different hot spots more than 1000 elmos apart can
never combine. `UpdateDefenceTasks`
(`cpp/src/circuit/module/MilitaryManager.cpp:1500-1630`) deliberately spreads
pools across distinct hot spots — heaviest pool picks first and subtracts its
power from that spot's demand — so the anchors are *designed* to be far apart.

`CDefendTask::CanAssignTo` (`cpp/src/circuit/task/fighter/DefendTask.cpp:70-73`)
additionally refuses any pool whose `GetPromote()` differs, so a MELEE-promoting
hold pool and an ATTACK-promoting pool can never merge either — and branch 10
above creates MELEE pools whenever home is contested.

Result: the army is partitioned into per-hot-spot, per-promote-type pools, each
capped at `maxPower` by `CanAssignTo`, each individually far below a bar set by
the enemy's second-largest blob.

apexearth, 2026-09-07: *"The enemy tends to come at us with one big blob of army
all together at the same time. Our army tends to be very spread out so we die to
them piece by piece."* Measured that game (`docs/24:826-833`): their peak group
32, ours 15; half of all pool passes were one or two units.

**What to try:** set `apex_hot_radius` very large (merge freely) for one A/B, and
separately make the hold branch use ATTACK as its promote type so pools stay
compatible.

---

### #5 — We issue a movement order per damage event. Stock issues none.

Stock, `vendor/circuitai/src/circuit/task/fighter/FighterTask.cpp:103-155`: on
damage, a healthy unit gets a repair request at most and **returns**. No move,
no reposition. Only a unit below its retreat threshold is given a `CRetreatTask`.

Ours, `cpp/src/circuit/task/fighter/FighterTask.cpp:301-306`, before any health
question:

```cpp
if (!KeepRange(unit, attacker)) {
    DodgeFire(unit, attacker);
}
CounterBattery(unit, attacker);
```

- `KeepRange` (`FighterTask.cpp:469-516`) issues `CmdMoveTo(...OrdSrc::STANDOFF)`
  at line 511, throttled by `apex_dodge_cd`, **default 1.0 second** (line 512).
- `DodgeFire` (`FighterTask.cpp:423-462`) issues `CmdMoveTo(...OrdSrc::DODGE)` at
  line 459, same 1-second cooldown (line 460).
- `CounterBattery` (`FighterTask.cpp:523-573`) issues a full attack order at line
  571, cooldown `apex_counter_cd` default 5 s.

So a unit under sustained fire is re-ordered roughly once per second by this
handler alone, on top of the squad's own destination election. The repo has
already measured the result (`docs/24:684-688`): 16 call sites issue movement,
~4,400 orders a minute over ~276 units, and "the standoff ring alone re-sent 367
of its 662 orders inside 3 seconds with 260 of them moving the goal more than
128 elmos."

apexearth: *"we stand around worthlessly going in circles never accomplishing
anything."* This is the mechanism that literally moves them in circles — and
`SquadTask.cpp:1635` adds a deliberate `ORBIT_RATE` precession on top of it.

**What to try:** `apex_standoff=0`, `apex_dodge=0`, `apex_counter_battery=0` as a
single A/B arm against the default. This is a three-modoption test that needs no
rebuild and directly answers "is the micro layer net negative".

---

### #6 — `CounterBattery` will charge an aircraft. It is the one target path with no air filter.

**Answer to "does stock let ground units target aircraft": no.** Stock applies
the same anti-air capability test in every target selector:

`vendor/circuitai/src/circuit/task/fighter/AttackTask.cpp:295`,
`DefendTask.cpp:273`, `RaidTask.cpp:321`, `ScoutTask.cpp:207`,
`module/MilitaryManager.cpp:1577`, `AntiHeavyTask.cpp:291`:

```cpp
|| (edef->IsAbleToFly() && !(IsInWater ? cdef->HasSubToAir() : cdef->HasSurfToAir()))  // notAA
```

We inherited all six and they are intact:
`cpp/src/circuit/task/fighter/AttackTask.cpp:1078`, `DefendTask.cpp:681`,
`RaidTask.cpp:501`, `ScoutTask.cpp:207`, `module/MilitaryManager.cpp:2298`,
`AntiHeavyTask.cpp:337`.

The apex-added target paths, audited one by one:

| path | file:line | air filter |
|---|---|---|
| squad focus-fire / set-target pool | `SquadTask.cpp:1550` | **present** — skips all flyers outright |
| `CDefendTask::LeashPosts` `canEngage` | `DefendTask.cpp:910-911` | **present** (added in the working tree, 2026-09-08; not in the last commit) |
| `CArtilleryTask::Execute` set-target | `ArtilleryTask.cpp:115-120` | n/a — `FindTarget` refuses all mobiles, same as stock |
| `IFighterTask::AttackEnemy` | `FighterTask.cpp:687` | callers pre-filter (`DefendTask.cpp:955`, `:980` via `canEngage`; `FighterTask.cpp:593` via task target) |
| **`IFighterTask::CounterBattery`** | **`FighterTask.cpp:523-573`** | **MISSING** |

`CounterBattery` filters the attacker on `IsMobile()` (line 536) — an aircraft is
mobile — and filters *our* unit on `IsAbleToFly()` (line 550), which is the
opposite question. It then calls `unit->Attack(attacker, false, ...)` at line
571, and `CCircuitUnit::Attack` (`cpp/src/circuit/unit/CircuitUnit.cpp:921`)
applies no capability test of its own — for a non-melee unit it queues a move
plus an attack.

So a ground riot/defend/rally unit strafed by any aircraft that outranges it is
ordered to walk at the aircraft. That is exactly *"Our targetting logic also sets
some units to attack enemy aircraft which they are ill-equipped to hit"*
(`docs/24:593`) and *"our AI also just trying to kill enemy air, so we stand
around worthlessly going in circles."*

`KeepRange` (`FighterTask.cpp:475-484`) also accepts an airborne attacker and
will back a ground unit away from a plane it could never have shot.

On the AngelScript side there is no per-unit weapon targeting at all, but four
*class* filters that should exclude AA units and do not — they let an AA bot be
bought and posted as ground cover, escort or raid body:
`hooks.as:166-173` (cover routing, runs before the `WantsMassing` AA exclusion at
`hooks.as:38-39`), `manager/military/guardposts.as:145-148` (`CoverUnitDef`),
`manager/military/raid.as:181-191` (`RaidWorthPulling`),
`manager/brain/market/guards.as:232-250` (`EscortWorthy`).

**What to try:** add `if (aDef->IsAbleToFly() && !cdef->HasSurfToAir()) return;`
at the top of `CounterBattery` and the same to `KeepRange`; add a
`GetSurfThreat() > 0` test to the four AngelScript class filters.

---

### #7 — Attack pathing, flanking and assembly: three delays stock does not have.

All in `cpp/src/circuit/task/fighter/AttackTask.cpp::Update`, none in stock:

- **Attack-break abort** (line 443-454): if the task holds under
  `apex_attack_break` (0.4) of the power it ever held, `AbortTask`. Survivors
  re-pool at home — and, per #1, cannot leave again.
- **Assemble hold** (line 550-604): the squad stops for up to `apex_assemble_secs`
  (8 s) if stretched, *while approaching the enemy*. The instrument at line
  568-574 was added because the gate "fired zero times in four smoke games" — it
  is not known to do anything.
- **Flank via** (line 637-703): 35% of attacks (`apex_flank_pct`) walk to a
  perpendicular waypoint first, and 35% of those (`apex_flank_deep_pct`) route to
  the map edge. Stock walks at the target.

Stock's `Update` (`vendor/circuitai/.../AttackTask.cpp:119-217`) is: merge,
regroup, find target, engage if in range with LOS, else path to it.

**HYPOTHESIS:** these three together are why a squad that does form takes a long
time to arrive and often dissolves first. **Test:** `apex_flank_pct=0`,
`apex_assemble=0`, `apex_attack_break=0` as one arm.

---

### #8 — Stock's raid pipeline is intact in C++; ours is starved upstream.

`CRaidTask::CanAssignTo` is byte-identical to stock
(`cpp/src/circuit/task/fighter/RaidTask.cpp` vs
`vendor/circuitai/.../RaidTask.cpp`). The RAID branch of `DefaultMakeTask` is
improved over stock (`MilitaryManager.cpp`, `apex_raid_first` offers the raid
pool before guard duty). So the raid *machinery* is not the problem.

What starves it: `DefaultMakeTask` is only reached through the `stock`
fallthrough at `hooks.as:271`, and branches 5/6/7 above claim cheap fast units
first. `manager/military/raid.as` works around this by pulling bodies directly,
but only from GUARD and DEFEND tasks (`raid.as:273-281`), capped at 4 per pass
(`raid.as:266`), and refused entirely while the base is busy or cover is short
(`raid.as:170-175`). `ISSUES.md:860-928` already documents 13 raiders reaching
`Defend(RAID, raid.min)` in one game with **zero raids formed**, for the same
reason as #1: a fresh one-unit pool per unit, packs only via merge, a 2.5-power
Pawn against an 18-power bar.

`CMilitaryManager::DispatchRaids` (`MilitaryManager.cpp`) is a *defensive*
interceptor, not an offensive raid dispatcher, and is off by default
(`apex_intercept`, 0.f).

---

## 3. Counting the elaboration

A newly-built line unit, from birth to firing at something it chose.

**Stock — 6 decision points**, one of which has an unconditional escape:

1. `AiMakeTask` → `DefaultMakeTask` role map (`military.as:9`, `MilitaryManager.cpp:1636`)
2. Promote: `power >= maxPower` **OR any ATTACK task exists** (`DefendTask.cpp:109`)
3. `FindTarget` group odds, margin 1.0 (`AttackTask.cpp:270`)
4. `CanMobileReachAt` (`AttackTask.cpp:271`)
5. Engage: within range+slack AND `GetHitTest()` LOS (`AttackTask.cpp:182-186`)
6. `IsMustRegroup()` (`SquadTask.cpp:228`)

Plus 8 per-enemy capability filters (`AttackTask.cpp:283-317`) — those are "can
this weapon reach that target", not policy, and we kept them.

**Ours — roughly 50**, of which about 30 can independently stop the unit:

*Election (11)* — hooks.as 124, 126, 134, 139, 152, 166, 174, 210, 225, 260, 267,
plus `WantsMassing`'s 6 sub-clauses (hooks.as 33-63) and `ConservativeStance`'s 6
(massing.as 178-201).

*Bar setting (6)* — `MassWant` (massing.as 204-285, 8 tunables), four posture
overrides (posture.as 166, 669, 698, 750), `SetMaxPower` overwrite
(MilitaryManager.cpp:1629) which discards all of the above.

*Pool growth (4)* — `CanAssignTo` power cap + promote-type match
(DefendTask.cpp:70), merge weaker-candidate, merge anchor radius, merge threat
line (SquadTask.cpp `CheckMergeTask`).

*Promotion (5)* — `onFront`, `noPromoteUntil`, `IsDispatched`, `guardShort`,
`mayReinforce` (DefendTask.cpp:190-203). Stock has **one** clause here.

*Withdraw layer (6)* — withdraw.as 209, 221, 246, 254, 257, 409, 421.

*Attack task (7)* — attack-break 443, `TryAllLowFallback` 459, regroup 466,
assemble 550, engage+LOS 528, flank 637, charge/ceiling 737 (AttackTask.cpp).

*Target selection (5 policy + 8 capability)* — overpowered 964, groupWeak 1011,
reach 1017, weak-or-worn 1160, localInfl 1251 (AttackTask.cpp).

*Per-damage-event (6)* — KeepRange 303, DodgeFire 304, CounterBattery 306,
coward mark 347, `TrySquadRetreat` 392, commit/dive waivers 324/335
(FighterTask.cpp).

Plus the order arbiter (`CCircuitUnit::OrdSrcPrio`, `CircuitUnit.cpp:406`,
gated on `apex_order_arbiter` default **0.f** at line 513 — off, and it refused
5,273 orders in a 20-minute game when on).

---

## 4. What stock does that we have effectively disabled

| stock behaviour | our disabling site | status |
|---|---|---|
| `!GetTasks(check).empty()` promotion bootstrap | `hooks.as:267` passes `check = MELEE`; `DefendTask.cpp:201` | **dead — always false** |
| `DefaultMakeDefence` (engine-side defence placement) | `manager/military/defenceline.as:325-328` is a no-op stub | intentional, but it also vetoes engine-placed AA |
| `DefaultMakeTask` for most army | `hooks.as:110-271` intercepts before the fallthrough at 271 | branches 5/6/10 never reach it |
| randomized per-pool `powerMod` (`1.0f / mod`, `MilitaryManager.cpp:617`) that gives some pools a low bar | our 3-arg path always uses `powerMod = 1.0` (`MilitaryManager.h:62-70`, `MilitaryManager.cpp:619`) | every pool now has the identical, high bar |
| `apex_attack_share` cap on the promote bar | `MilitaryManager.cpp:1629` overwrites it 5 s later | **inert** |
| `MassWant()` quota (8 tunables) | same overwrite | **inert for attack-capable pools** |
| assemble-before-contact gate | its own instrument (`AttackTask.cpp:568`) says it "fired zero times in four smoke games" | **unproven** |
| order arbiter | `apex_order_arbiter` default 0 | off |
| raid interceptor | `apex_intercept` default 0 | off |

---

## 5. Order of work

1. **`hooks.as:267` → `check = ATTACK`.** One token. Restores the mechanism by
   which stock's army leaves home at all. Everything else in this document is
   downstream of an army that never marches.
2. **A/B the micro layer off** (`apex_standoff=0 apex_dodge=0
   apex_counter_battery=0`). Three modoptions, no rebuild.
3. **Air filter in `CounterBattery` and `KeepRange`.** He watched this one.
4. **Reorder `MakeTaskInner`** so escort/cover are offered after the pool.
5. **A/B `ENGAGE_MARGIN` 1.35 → 1.0 with the `localInfl` test off.**
6. **A/B `apex_hot_radius` large** so defence pools merge.

Rules 2 and 4 of `docs/26-working-rules.md` apply to every one of these: one
change at a time, judged on `composition.py`, and two seeds are an anecdote.
