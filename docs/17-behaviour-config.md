# behaviour.json — what each knob actually does

Read from the C++ 2026-08-09, every entry traced from the parser to the line that
consumes it. The point of this file is that the config names do not say what they
do — `thr_mod.attack` is not "how aggressive", it is the *denominator* of a
self-confidence multiplier — and the same key is often read in two unrelated
places.

**Values are deliberately not tabulated here.** Every previous version of this
doc carried an `apex` vs `stable` value table and every one of them went stale
within weeks. Read the numbers out of
`ai/Unstable/game-side/config/standard/behaviour.json` and
`reference/barb-stable/`; read the *meaning* here.

## Dead: `response.json` and the `factory.json` weight tables

`response.json` is **empty** — a `{}` with a comment. The whole counter-composition
system (`response.<role>.{vs, ratio, importance, max_percent}`, `_weight_`,
`RoleProbability`) decides nothing, because the Brain's production market owns
composition and the facqueue suppresses the DLL's native recruit re-enqueues. The
same goes for `factory.json`'s `income_tier` ladders and per-tier weight rows
while a line is driven, which is always. See `docs/20-brain-overhaul.md` §6 and
the `ai-auction` skill.

If you are diagnosing "wrong units built", the answer is in
`Market::ConOrderFor` and the `apex: decide ... -> produce:` lines. It is not in
a JSON weight.

## quota.attack — parsed into `minAttackers`, used three ways

`MilitaryManager.cpp:368`, then:

1. `MilitaryManager.cpp:654` — `new CAttackTask(this, minAttackers, ...)`, where
   it becomes the task's `minPower`.
2. `AttackTask.cpp:311` — in `RemoveAssignee`: **when a squad's power drops below
   `minPower`, the task ABORTS.** So this is not only a departure size, it is the
   attrition floor at which an attack in progress dissolves and goes home.
3. `MilitaryManager.cpp:1594` —
   `dt->SetMaxPower(std::max(minAttackers, PreMaxGroupThreat))` on the defend
   pool: what the pool must reach before it promotes to an attack.

It is a **power** sum (`+= cdef->GetPower()`), not a unit count and not metal.

**`military/massing.as` overrides it upward at runtime.** `MassFloor()` sets the
promotion quota from a share of our OWN standing army cost
(`apex_mass_per_army`), with `apex_mass_floor` as a degenerate-case guard for an
army of nearly nothing. Any A/B of the config value has to account for that
override, or it changes nothing.

## quota.thr_mod.{attack,defence} — a divisor, not a multiplier

Both are `[min, max]` ranges. Per task the engine rolls a uniform value in that
range and the task's `powerMod` is `CONSTANT / mod`
(`MilitaryManager.cpp:645-655`):

| task | powerMod |
|---|---|
| SCOUT | `0.75 / mod` |
| RAID | `0.75 / mod` |
| ATTACK | `0.8 / mod` |
| BOMB | `2.0 / mod` |
| DEFEND | `1.0 / mod` (uses `thr_mod.defence`) |

`powerMod` then scales the squad's self-assessment when picking a target:
`maxPower = attackPower * powerMod * healthScale * cohesion`
(`AttackTask.cpp:594`).

**So a LOWER `thr_mod` makes the AI think it is stronger and engage more.**
Because it is a *range* rolled per task, a two-element form rolls a per-task
timidity die; a `[1.0, 1.0]` pins it.

## quota.thr_mod.{mobile,static,comm} — threat map weights

Read near `MilitaryManager.cpp:258` (`commMod`) and used to weight what goes into
the threat map. These are the "how much do we fear X" numbers — mobile units,
static defence, and an enemy commander respectively.

## quota.raid — `[min, avg]`

`MilitaryManager.cpp:365-367`. `raid.avg` is passed to `CRaidTask` as its group
size; `raid.min` is the pool size that promotes.

## quota.num_batch

`FactoryManager.cpp:335`. How many of the SAME unit a factory builds in a row
before re-choosing. Only relevant on a line the facqueue is not driving.

## quota.scout — `maxScouts`

`MilitaryManager.cpp:1888`: a scout-role unit only gets a SCOUT task while fewer
than `maxScouts` exist. This is the cap on simultaneous scouting.

## retreat.* — health fractions

`retreat.builder`, `retreat.fighter`, `retreat.shield`, as lists of health
fractions. **The list length changes the meaning**: a three-element form is a
band, a two-element form is read as a range and rolled per unit. This has caught
us before — see the "config format drift" memory. Match stock's arity unless you
mean to change the semantics.

## defence.*

`infl_rad`, `base_rad`, `comm_rad`, `escort` — radii the engine's own defence
placement uses. Our placement is in `manager/brain/market/protect_*.as`; see the
`ai-placement` skill.
