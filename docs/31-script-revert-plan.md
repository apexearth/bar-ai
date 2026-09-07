# 31 — Reverting the fight logic: what happens to the script layer

*Planning only, written 2026-09-07. Nothing was changed, built, deployed or run
to produce it.*

apexearth: *"biggest issue is the fight logic, our army is retarded. It is
completely dysfunctional. The brain stuff, wants, building, thats all working
'well enough' to keep. Even nuke logic, air raid logic, these things are doing
well."* and *"some actionscript delves into wanting to control fight logic, so
we may have to remove those."*

This file answers the second sentence. `docs/29-what-barb-does-better.md` is the
C++ side of the same decision. `docs/24-how-units-fight.md` still governs where
it disagrees with anything here.

---

## 0. The scoping ruling this whole plan depends on

"Revert to stock" is not one thing. Three different depths give three different
answers, and only one of them is survivable.

| depth | what it means | consequence |
|---|---|---|
| **A, election and tasks** | `cpp/src/circuit/task/fighter/*` and the fight half of `module/MilitaryManager.cpp` go back to stock. The script's `AiMakeTask` goes back to `return aiMilitaryMgr.DefaultMakeTask(unit)` | the plan below. Two script bindings break, both fixable |
| **B, plus `script/MilitaryScript.cpp`** | the four apex bindings on `CMilitaryManager` are deregistered | adds `GetBaseDefRange`/`SetBaseDefRange` to the break list. Those methods exist in stock's header. Only the registration is ours |
| **C, plus `script/InitScript.cpp`** | the whole binding set reverts, 159 apex-added registrations | **the entire AI dies.** About 180 script call sites in the *builder and economy* layer break: `.IsDead()` ×29, `.buildDef` ×86, `.GetBuildPos()` ×29, `.GetBuildType()` ×16, `.GetUnits()` ×18, `.GetFightType()` ×9, `.RemoveUnit()` ×4, plus `GetTunable`, `PublishTeamValue`, `ReadTeamValue`, every `Cmd*`, every `CCircuitDef` getter. Nukes and air die with it |

**Depth A is the only one that leaves "the brain stuff, wants, building" alive.**
`InitScript.cpp` and `CircuitAI.h` are plumbing, not fight logic, and must be
excluded from the revert by name. Everything below assumes depth A.

---

## 1. BREAKS: script that will not compile after the revert

Per **S3** (`docs/25-silent-failures.md`) a script compile error disables the
whole variant *silently*. The game still runs, the AI plays near-stock, and the
match reports a normal-looking result. So this is the list that can destroy a
measurement without anyone noticing. It is short, which is the good news.

### 1.1 Hard breaks at depth A, two call sites

| call site | binding | stock has the method? | fix |
|---|---|---|---|
| `manager/military/guardposts.as:459` | `aiMilitaryMgr.ClearGuardPosts()` | **no**, apex-only, `cpp/src/circuit/module/MilitaryManager.h:197` | delete with the file |
| `manager/military/guardposts.as:651` | `aiMilitaryMgr.SetGuardPost(unit, pos, reach)` | **no**, apex-only, `MilitaryManager.cpp:1791` / `.h:196` | delete with the file |

Both belong to the guard-post system. Its only consumer is
`CDefendTask::LeashPosts` (`cpp/src/circuit/task/fighter/DefendTask.cpp:950`,
`:1059`, `:1182`), which sits inside the reverted file, so script and C++ leave
together. There is nothing to preserve.

### 1.2 Extra breaks if the revert reaches `MilitaryScript.cpp` (depth B)

| call site | binding | note |
|---|---|---|
| `manager/frontline.as:504` | `aiMilitaryMgr.SetBaseDefRange(float)` | stock's `MilitaryManager.h:212` has the method. Only the AngelScript registration is apex |
| `manager/frontline.as:518` | `aiMilitaryMgr.GetBaseDefRange()` | same, `MilitaryManager.h:213` |

Keeping four lines of `MilitaryScript.cpp`, the two `RegisterObjectMethod`
calls, avoids this entirely. `DefaultMakeSensors` is registered but **never
called from script**. It appears only in a comment at `defenceline.as:323`, so
it can be deregistered freely.

### 1.3 Everything else the script calls on the military manager is stock API

Verified against `vendor/circuitai/src/circuit/`. None of these break.

- `TaskF::Common(...)`, `TaskF::Guard(vip)`, `TaskF::Defend(promote, power)`,
  `TaskF::Defend(check, promote, power)`. **All four are stock**
  (`vendor/circuitai/.../MilitaryManager.h`), the three-argument overload
  included.
- `Task::FightType::*` is a pure AngelScript enum in
  `ai/Unstable/game-side/script/task.as`, not a binding. Stock ships the same
  enum.
- `aiMilitaryMgr.DefaultMakeTask`, `Enqueue`, `EnqueueRetreat`,
  `DefaultMakeDefence`, `GetGuardTaskNum`, `armyCost`,
  `quota.{scout, attack, raid.min, raid.avg}`. All stock.
- `IUnitTask@` handles held in arrays (`gSquads`, `gAskTask`). Stock refcounts
  `IUnitTask` too, `vendor/.../task/UnitTask.h:36`, CRTP `IRefCounter<IUnitTask>`.
- The `Military::AiMakeDefence` and `AiIsAirValid` hook signatures are stock's own.

### 1.4 The dangerous middle: compiles, but still steers the stock fighter

This bucket is worse than BREAKS for measurement, because nothing errors. These
script writes reach through **stock bindings** into **stock** fight code, so
after the revert they keep changing the army's behaviour while looking like they
were removed.

| write | site | what stock reads it with |
|---|---|---|
| `aiMilitaryMgr.quota.attack = …` | `massing.as:485`, `posture.as:167, 669, 690, 700, 738, 750` | `minAttackers`, the promote bar in `DefaultMakeTask` (`vendor/.../MilitaryManager.cpp:1697, 1711`) and in `SetMaxPower` |
| `aiMilitaryMgr.quota.raid.min = …` | `posture.as:54` | `raid.min`, the raid pool's bar (`:1682`) |
| `cdef.SetRetreat(…)` | `posture.as:360, 363`; `army.as:1399`; `catalog.as:238`; `air/update.as` ×7 | the retreat threshold in `IFighterTask::OnUnitDamaged` |
| `aiMilitaryMgr.SetBaseDefRange(…)` | `frontline.as:504` | stock `DefendTask`, `RaidTask` and `BuilderTask` all read `GetBaseDefRange()` |

**A revert that deletes `MakeTaskInner` but leaves `MassWant()` writing
`quota.attack` has not reverted the fight logic.** It has reverted the routing
and kept the bar. That is the exact shape of change `CLAUDE.md` warns about: the
instrument will say the election is stock, and the army will still not leave.

### 1.5 Writes that go inert, dead rather than broken

These are `CCircuitAI` setters. They survive at depth A, but their only consumers
sit inside `task/fighter/`, so after the revert they write to nothing.

| write | site | sole consumer, all reverted |
|---|---|---|
| `ai.SetEngageBoost(f)` | `posture.as:162, 187` | `AttackTask.cpp:180`, `TradeScaledMargin` |
| `ai.SetCommitted(bool)` | `posture.as:165, 196` | `AttackTask.cpp:443`, `FighterTask.cpp:324`, `SquadTask.cpp:277` |
| `ai.SetFrontPos(pos)` | `posture.as:619, 629` | `FighterTask.cpp:152` (`RoamPos`), `DefendTask.cpp:127, 171, 336`, `RetreatTask.cpp:216`, `MilitaryManager.cpp:1104, 1246, 1310` |

`SetFrontPos` deserves a second look. `MilitaryManager`'s three readers are in
the *defence-placement* half of that file, and `RetreatTask.cpp:216` is not a
fighter task. If those survive the revert, `SetFrontPos` stays live and
`posture.as`'s lane computation has to stay with it.

---

## 2. The air and nuke couplings, the highest-risk part

### 2.1 Nukes are essentially uncoupled. Safe.

`manager/brain/nukes.as`, 536 lines, drives silos entirely through `CmdStop`,
`CmdAttackGround`, `GetStockpile` and `GetTeamUnit`. It reads targets from
`aiEnemyMgr.GetEnemyGroupCount`/`GetEnemyGroupPos`, `ai.GetNetInflAt` and
`ai.ForgetEnemiesNear`. Its only reach into the military namespace is
`Military::ForwardFraction(p)` at `nukes.as:324`, which lives in
`manager/military/territory/holdings.as:254`, a territory reading rather than
fight control.

None of those bindings is in `task/fighter/` or the fight half of
`MilitaryManager`. **At depth A the nuke director needs nothing preserved beyond
`territory/`.** It is also why depth C would kill it: every one of those calls is
an apex `InitScript` binding.

One interaction already exists and the revert does not change it. A static nuke
silo falls through to `DefaultMakeTask`, then `SUPER`, then `CSuperTask`, and
`nukes.as` overrides that task's orders by re-issuing `CmdAttackGround` on a
tick. Stock behaves the same way. We deliberately did not register
`CSuperTask::SetTargetPos`, which stock does register. Leave it that way.

### 2.2 Air is directly coupled to the thing being reverted. This is the conflict.

`Military::MakeTaskInner`'s first three branches are the air doctrine.

```
hooks.as:124   if (Air::HoldsUnit(unit))            return null;   // mass before striking
hooks.as:126   if (Factory::HoldsLateFighter(unit)) return null;
hooks.as:134   if (Air::IsBomberDef(cdef.id))       return Enqueue(TaskF::Common(BOMB));
```

Stock's entire `AiMakeTask` is `return aiMilitaryMgr.DefaultMakeTask(unit)`
(`vendor/bar/luarules/configs/BARb/stable/script/hard/manager/military.as:7-10`).
It has no null return, so three things follow.

**"Mass air before attacking with air" dies.** `Air::HoldsUnit` returning `null`
is the only way this codebase can hold a plane. Nothing lands an aircraft from
AngelScript, since `CmdFindPad` and `CmdWait` are unregistered, so a unit with no
task is the only available form of "wait at home". Under stock every fighter and
bomber gets a task the frame it is built and flies off alone, which is the
failure `docs/24` names first under Air.

**The heavy bomber tier goes back into the ground push.** Our strike tier
(`armblade`, `corcrw`, `legfort`) carries role `heavy`, not `bomber`. Stock's
role map (`vendor/.../MilitaryManager.cpp:1640-1650`) has a BOMB entry for
`BOMBER` only, so `heavy` falls to the default branch,
`Enqueue(TaskF::Defend(ATTACK, power))`, the ground massing pool. The
economy-value target scoring in `CBombTask::FindTarget` is then never reached.
`hooks.as:128-133` records this regression having already happened once.

**Torpedo flyers fly at land armies with nothing to shoot.** `HoldsUnit`'s first
clause (`update.as:20-25`) holds a def with zero surf and zero air threat until
enemy subs are actually seen. The comment records 118 metal lost to this before
the hold existed.

What it takes to keep air working: `AiMakeTask` cannot be literally stock. The
minimum viable hook is four lines and carries no policy of its own.

```angelscript
IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
    if (Air::HoldsUnit(unit))            return null;
    if (Factory::HoldsLateFighter(unit)) return null;
    if (Air::IsBomberDef(int(unit.circuitDef.id)))
        return aiMilitaryMgr.Enqueue(TaskF::Common(Task::FightType::BOMB));
    return aiMilitaryMgr.DefaultMakeTask(unit);
}
```

Every ground branch goes: escort, cover, fodder, charger, superguard, mass.hold,
mass.attack. Three air branches stay. **This is a judgement call for apexearth,
not a decision to take silently.** See §5.

### 2.3 What else the air layer reads out of `Military::`

Air does not command ground units, but it senses through eight functions that
live in files otherwise slated for removal.

| air uses | defined in | file's fate |
|---|---|---|
| `Military::gFencePos`, station spread | `hooks.as:508` | hooks.as is split, see §3 |
| `Military::AllyCount()` | `massing.as:122` | massing.as REMOVE |
| `Military::Outmassed()` | `massing.as:102` | massing.as REMOVE |
| `Military::TeamArmyCost()` | `killingblow.as:3` | killingblow.as REMOVE |
| `EnemyArmyCost`, `EnemyCostOf`, `EnemyAfloat`, `BaseContested`, `LosingGround` | `territory/enemy.as` | KEEP |
| `Military::AirThreatNow()` | `airthreat.as:62` | KEEP-AIR |
| `Air::ReleaseForPush()`, called BY `posture.as:152` | `air/update.as:175` | the caller is fight control |

The four in removed files are each under 15 lines and depend only on
`ai.GetTeamIds`, `ai.ReadTeamValue`, `aiMilitaryMgr.armyCost` and
`Market::StrRatio`. **Hoist them into a new `military/census.as` before deleting
their homes**, or the air layer stops compiling, which is the silent S3 failure
again.

`Air::ReleaseForPush()` is the coupling running the other way. The team-push
declaration in `posture.as:116-198` is what releases the air wing for a
coordinated strike, which is `docs/24`'s *"Coordinate air raids with the land
engagement."* Deleting `UpdateTeamPush` deletes the coordination. Air keeps
striking on its own timer. It just stops being simultaneous with the ground.

### 2.4 AA sizing is safe

`airthreat.as` and the AA block in `defenceline.as:331-383` size anti-air off
observed enemy air value and spend it through the economy, meaning build wants
and `CCircuitDef::maxThisUnit`, never through a fighter task. `AiMakeDefence`
(`defenceline.as:325`) is already a deliberate spend-nothing stub. Nothing here
touches the reverted code.

---

## 3. File-by-file classification

`manager/military/` is 7,565 lines across 22 files. It is not uniformly fight
control: only 7 of the 22 issue an order or enqueue a task at all.

### REMOVE, pure fight control

| file | lines | what it does |
|---|---|---|
| `massing.as` | 540 | `MassWant()` writing `quota.attack`, `ConservativeStance()`, the hold and commit gates. `docs/29 §4`: `SetMaxPower` overwrites it 5 s later for any pool that could attack, so it is **already largely inert**. Hoist `AllyCount` and `Outmassed` first |
| `posture.as` | 781 | the C++ fight writes (`SetEngageBoost`, `SetCommitted`, `SetFrontPos`, `quota.*`), team push, raid caution, turtle, corridor probe. Hoist `UpdateLanePos`/`LanePos` if `SetFrontPos`'s non-fighter readers survive |
| `withdraw.as` | 557 | issues `CmdMoveTo` to combat units and calls `t.Abort()`. The order-conflict source `docs/24:679-692` describes. `apex_fight_abort` is already 0 |
| `raid.as` | 318 | the raid director. Pulls units out of GUARD and DEFEND tasks by `RemoveUnit`, enqueues a RAID pack |
| `superguard.as` | 164 | holds T3 in a MELEE-promoting pool instead of stock's solo ATTACK |
| `guardposts.as` | 729 | the two hard breaks in §1.1. Posts DEFEND-pool members over assets |
| `killingblow.as` | 117 | the all-or-nothing T1 commit. Writes `apex_kill_quota` into `quota.attack`. Hoist `TeamArmyCost` first |
| `stance.as` | 139 | enemy stance to budget answer. Feeds the removed gates |
| `state.as` | 106 | reactive posture flags, consumed only by the removed gates |
| `roles.as` | 42 | massing constants |
| `gift.as` | 119 | already off, `TUNE_GIFT_ARMY = 0` at `tunables.as:1203` |
| `hooks.as`, the `MakeTaskInner` election and its census (roughly lines 110-300, `NoteElect`, `ElectCensus`, `NoteFightElection`) | ~250 | the 12-branch election |

Subtotal is about **3,860 lines**, roughly half the military tree.

### KEEP, the sensing that the economy and placement layers already depend on

| file | lines | who depends on it |
|---|---|---|
| `territory/enemy.as` | 154 | `EnemyCostOf` (army.as, worth.as, protect_senseprice.as, production.as, coverage.as), `EnemyArmyCost`, `BaseContested`, `LosingGround`, `EnemyAfloat`. Air and market both |
| `territory/holdings.as` | 301 | `ForwardFraction`, 37 call sites including `nukes.as:324`, `want_tech`, `sites`, `safety`, `protect_*`, `main.as` |
| `territory/front.as` | 577 | the front curve. `frontline.as`, placement, `want_nano` |
| `territory/frontspots.as` | 486 | front build spots. `protect_sense.as`, `protect_fill.as` |
| `airthreat.as` | 186 | KEEP-AIR. `AirThreatNow`, `AirSeenEver`, AA sizing |
| `basedefence.as` | 284 | jammer and porcupine demand, approach threat. `BaseRaided()` loses its consumer, the rest is build demand |
| `unblock.as` | 465 | units walled in by our own buildings. A stuck-unit fix that applies to builders too, and it runs ahead of the `ApexActive` gate at `main.as:113` |
| `intel.as` | 67 | telemetry on believed enemy strength |
| `defenceline.as` | 383 | the `AiMakeDefence` stub, AA sizing, ally-aid telemetry. **Must not be deleted.** A missing `AiMakeDefence` falls through to the native spender |
| `hooks.as`, the FENCE register: `gFenceId`, `gFencePos`, `gFenceDef`, `gFenceLostPos`, `FenceCountNear`, `FenceGunsNear`, `FenceGunMetalNear`, `OwnDefenceMetal`, `NearestFenceDist`, `FenceLostNear`, `AiUnitAdded/Removed` | ~200 | `want_nano.as`, `protect_*`, `air/station.as`, `coverage.as`. Nothing else in the AI records where our defences stand |
| `hooks.as`, the `gSquads` register and `EscortSquadCount` | ~90 | `production.as` support wants (radar, jammer), `builder/reclaim.as:164`, `guardposts.as`, `fightcensus.as` |
| `hooks.as`, `WantsMassing` and `IsFodder` | ~60 | `main.as:261, 343` loss accounting. Keep as predicates even with the election gone |
| `fightcensus.as` | 89 | the instrument that will measure this revert. Keep until the work is finished |
| `deathledger.as` | 266 | UNSURE. `NoteCombatLoss` is called from `main.as:263`, but its output `BleedCaution()` feeds only `SetEngageBoost`, which goes inert. Half telemetry, half dead |

### The market layer, the genuinely ambiguous files

**`market/army.as`, 1,735 lines, KEEP-ECON.** It answers how much army and which
roles, priced against enemy composition. It touches the fighter layer in exactly
one place, `army.as:1399` (`rdef.SetRetreat(rt)`), which is a per-def retreat
threshold rather than a command. `armyCost` at `:184` is read-only. Role shares
(`RoleTarget`, `RoleValue`, `RoleCommitted`) decide purchases, and stock's
`DefaultMakeTask` maps whatever we buy onto its own fight types, so composition
still steers the army under stock. That is the correct place for it. Nothing here
goes.

**`market/production.as`, 1,401 lines, KEEP-ECON with one dead branch.** Unit
selection is a purchase. But its escort branch (`EscortWorthy`) and cover branch
(`CoverNeedM`, `CoverUnitDef`) buy units for duties only the removed election
could assign. After the revert those purchases still happen and nothing posts or
escorts them, so it is metal bought for a job nobody hands out. The support
branch at `production.as:570` (radar, jammer) survives, because
`EscortSquadCount` reads `gSquads`, which is kept.

**`market/guards.as`, 484 lines, SPLIT.** `EscortNeeded`, `EscortWorthy`,
`EscortOrderFor` and `EscortGain` are escort pairing and pricing, and pairing is
a fight decision the removed election consumed. `GuardNote`, `GuardGone`,
`WorkerSeen`, `WorkerGone`, `EscortMetalOn` and `BPProtectedFrac` are the
worker-exposure census that `army.as`, `floor.as`, `execute.as`,
`protect_census.as` and `census.as` all read. Keep the census. The pairing goes
with the election that fed it. Note `docs/24:750-770`: he complained the escorts
were bad, not that escorting was wrong, so this belongs in his ruling rather than
a silent delete.

**`market/safety.as`, 333 lines, KEEP but flagged.** `CommanderSafety` is called
from the builder election at `decide.as:734`, not the military one, and issues
`CmdMoveTo` at `:191` and `:318`. It survives the revert untouched. But the
commander is a standing complaint (`docs/24:511, 519`, "totally braindead",
"chases enemies into the sunset") and it is fight-shaped code. UNSURE, his call
whether the commander is in scope.

**`market/coverage.as` and `protect_*.as`, KEEP-ECON.** They price defence
structures. Their `Military::` reads are all sensing: `FoeReach`, `EnemyCostOf`,
`OurArmyNow`, `UnitCoverAt`, `OpenFraction`. `UnitCoverAt` lives in
`guardposts.as` and must be hoisted with the census functions.

---

## 4. Already dead. Remove these first, they are free

Confirmed by reading the defaults in `tunables.as` and the sites they gate. None
of these can change a measurement, so they can go in one commit with no A/B.

| what | evidence |
|---|---|
| `gift.as`, the whole file | `TUNE_GIFT_ARMY = 0` (`tunables.as:1203`), single gate at `gift.as:82` |
| the fight-abort arm, `withdraw.as:477-490` | `TUNE_FIGHT_ABORT = 0` (`:416`), measured worse and reverted to opt-in |
| the raider-massing branch, `hooks.as:52` | `TUNE_RAIDER_MASSING = 0` (`:1740`). Raiders never enter the pool |
| the spam-scout branch for raiders, `hooks.as:195` | `TUNE_SPAM_RAIDERS = 0` (`:1744`) |
| the cost bar in `ApplyRetreatPosture`, `posture.as:345` | `TUNE_RETREAT_COST_SECS = 0` (`:286`). Only the `gRaiderSuicidal` clause still fires |
| `MassWant()`'s eight tunables writing `quota.attack` | `SetMaxPower` overwrites it (`MilitaryManager.cpp:1629`) within 5 s for every attack-promoting pool. `docs/29 §4` |
| the `apex_attack_share` cap | same overwrite. `docs/29 §4` calls it inert |
| the assemble-before-contact gate | its own instrument at `AttackTask.cpp:568` reports it fired zero times in four games |
| the order arbiter | `apex_order_arbiter` default 0 |
| the raid interceptor | `apex_intercept` default 0 |

Two more are often assumed dead and are not. `quota.attack` writes from
`posture.as` still land on stock's `minAttackers` (§1.4). And the `check = MELEE`
bug from `docs/29 §1` has **already been fixed** in the working tree:
`hooks.as:287` now passes `ATTACK, ATTACK`. Do not fix it again and credit the
revert with the result.

---

## 5. Order of operations

Each step is one behaviour, independently buildable and independently
measurable, in increasing risk. Judge every one on `tools/composition.py` and
`tools/review.py`, one change at a time. Two seeds are an anecdote (`CLAUDE.md`).

Before step 1 and after every step, `python tools/check.py` must pass and the
infolog must show the script compiled. A silent S3 failure here would make every
arm below look like a win.

| # | step | risk | how it is measured |
|---|---|---|---|
| **0** | Delete the §4 dead code. No behaviour change is possible | none | `check.py` compiles, `deadcheck.py` loses those rules |
| **1** | Hoist the shared census into a new `military/census.as`: `AllyCount`, `Outmassed`, `TeamArmyCost` from massing and killingblow, `UnitCoverAt` from guardposts. Pure move, no logic change | none | `check.py`, a smoke game logs identically |
| **2** | Stop writing the fight bars. Remove every `aiMilitaryMgr.quota.*` write (`massing.as:485`, `posture.as:54, 167, 669, 690, 700, 738, 750`) and let stock's `minAttackers` and `raid.min` config values stand. **This is the single change most likely to move the army**, because it is the bar `docs/24:665-673` says moves the wrong way | medium | attack-task count per game from `fightcensus.as`, then `composition.py` |
| **3** | Reduce `AiMakeTask` to the air hook (§2.2, four lines). Deletes 9 of the 12 election branches at once. Keep `WantsMassing` and `IsFodder` as predicates for `main.as` | high, the big one | the `apex: elect` census disappears, `fightcensus` attack/raid/defend split, head-to-head against the current build |
| **4** | Delete `guardposts.as`, the only step that touches a binding (§1.1), and the escort and cover pairing in `guards.as`. Nothing assigns those duties after step 3, so this only removes the purchases and the dead posting pass | low after 3 | metal share in `composition.py` moves from cover and escort into line army |
| **5** | Delete `withdraw.as`, the per-unit `CmdMoveTo` recall layer. `docs/24:679-692` says order survival is why movement fixes read inert, so this is testable on its own with `apex_order_trace=1` and `tools/orders.py` | medium | orders per minute per unit, then `deaths.py` |
| **6** | Delete `raid.as` and `superguard.as`. Stock's raid pipeline is byte-identical to ours (`docs/29 §8`) and is starved only by the election, which step 3 removed, so this should be a no-op or an improvement | low | raid-task count, `fight1v1.py` |
| **7** | Delete `posture.as`, `massing.as`, `killingblow.as`, `stance.as`, `state.as`, `roles.as`. By here they have no consumers left. Check `SetFrontPos` first: if `MilitaryManager`'s defence-placement readers survive the C++ revert, `UpdateLanePos` must be hoisted rather than deleted | medium | placement telemetry, `trace.py --filter=defplace`, must not move |
| **8** | Re-run `battery.py` and a full `run_tournament.py` against the pre-revert build and against stock BARb | | the answer to whether this was worth it |

Steps 3 and 7 are the two that can silently break the air layer. Run
`grep -rn "Military::" manager/air/ manager/brain/nukes.as` after each and
confirm every symbol still resolves.

---

## 6. Questions only apexearth can answer

Ordered with the air conflict first, because that is where his two instructions
pull against each other.

1. **Air needs a hook the stock AI does not have.** Right now new aircraft are
   told to wait at home and do nothing until we have enough of them to strike
   together. That is the "mass air before attacking" rule. Stock BARb has no way
   to say that: every plane it builds is sent out the moment it is finished, one
   at a time. If we go fully stock on how units are handed their jobs, air
   massing stops working. Do we keep a small exception just for aircraft, or
   accept that air goes back to flying out one by one for now?

2. **Same question for the big bombers.** Our heavy bombers are labelled "heavy",
   not "bomber", in the game's own data. Stock only sends things labelled
   "bomber" on bombing runs, so under stock our heavies would join the ground
   army and go fight tanks instead of bombing the enemy base. Keep the one line
   that says "these are bombers", or let them fight on the ground?

3. **Air and ground currently attack together on purpose.** When we declare a
   push, the same code releases the air wing so both hit at once. That code is
   part of what is being removed. Is a coordinated air-and-ground strike worth
   keeping a piece of the old system for, or should air just strike on its own
   schedule?

4. **Escorts for constructors.** We currently pick a cheap fast unit and glue it
   to a constructor. You said the escorts we picked were bad, rascals instead of
   incisors, not that escorting was wrong. Stock has no escort system at all. Do
   constructors go unescorted from now on, or is this worth rebuilding later on
   top of stock?

5. **Units standing guard on buildings.** We spread units across our mexes and
   generators so each building has somebody near it. You asked for this, then
   said the guards "dry hump our most valuable mex" and did not answer the main
   base. Stock does none of this. Its units all pool up and defend as a group.
   Removing it is the cleanest cut in the whole plan. Confirm we lose the
   per-building guards entirely?

6. **The commander's flee logic.** The code that decides when the commander runs
   from danger is separate from the army logic and would survive this revert
   untouched. You have called the commander braindead several times. Do you want
   it in scope, or left alone this round so we only change one thing?

7. **How much army to build.** Everything about how much army and which kinds
   stays. That is the wants and building you said works. But one number it
   currently sets, how big a group has to be before it goes and attacks, is a
   fight decision that we write into the stock system. If we stop writing it,
   stock uses its own value. Step 2 of the plan stops writing it. Confirm that is
   what you want, or should we keep controlling the group size?

8. **Turrets.** Where defensive towers get built is decided by our code, and we
   deliberately switched off the stock version of that. It is not army logic and
   the plan keeps it. Confirm turret placement is out of scope for this revert.
