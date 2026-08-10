# behaviour.json / response.json — what each knob actually does

Read from the C++ 2026-08-09, every entry traced from the parser to the line that
consumes it. `apex` values are `config/hard_aggressive/`; `stable` is
`reference/barb-stable/game-side/config/hard_aggressive/`.

The point of this file is that the config names do not say what they do —
`thr_mod.attack` is not "how aggressive", it is the *denominator* of a
self-confidence multiplier — and the same key is often read in two unrelated
places.

## quota.attack — apex 60, stable 15, engine default 8

Parsed at `MilitaryManager.cpp:368` into `minAttackers`, and then used in **three**
different ways:

1. `MilitaryManager.cpp:654` — `new CAttackTask(this, minAttackers, ...)`, where
   it becomes the task's `minPower`.
2. `AttackTask.cpp:311` — in `RemoveAssignee`: **when a squad's power drops below
   `minPower`, the task ABORTS**. So this is not only a departure size, it is the
   attrition floor at which an attack in progress dissolves and goes home. At 60,
   a push that loses a third of itself stops being a push.
3. `MilitaryManager.cpp:1594` — `dt->SetMaxPower(std::max(minAttackers, PreMaxGroupThreat))`
   on the defend pool, which is what the pool must reach before it promotes to an
   attack.

**Careful: apex's own `MASS_FLOOR` overrides it upward.** `military/massing.as`
does `if (quota.attack < want) quota.attack = want` with `want = 30` by default,
so setting the config below 30 changes nothing unless `apex_mass_floor` moves
too. Any A/B of this number has to move both.

## quota.thr_mod.* — a divisor, not a multiplier

`thr_mod.attack` and `thr_mod.defence` are `[min, max]` ranges. Per task, the
engine rolls a uniform value in that range and the task's `powerMod` is
`CONSTANT / mod` (`MilitaryManager.cpp:645-655`):

| task | powerMod |
|---|---|
| SCOUT | `0.75 / mod` |
| RAID | `0.75 / mod` |
| ATTACK | `0.8 / mod` |
| BOMB | `2.0 / mod` |
| DEFEND | `1.0 / mod` (uses `thr_mod.defence`) |

`powerMod` then scales the squad's self-assessment when picking a target:
`maxPower = attackPower * powerMod * healthScale * cohesion` (`AttackTask.cpp:594`).

**So a LOWER `thr_mod` makes the AI think it is stronger and engage more.**

| | apex | stable | effect |
|---|---|---|---|
| `thr_mod.attack` | [0.6, 0.8] | [1.0, 1.0] | apex attack powerMod 1.00-1.33 vs stable 0.80 — **apex is already the bolder one here** |
| `thr_mod.defence` | [0.3, 0.5] | [1.0, 1.0] | apex defenders rate themselves 2.0-3.3x, stable 1.0x |

This matters for the "we are not aggressive" question: the self-confidence dial
is already turned past stock. The timidity is elsewhere.

## quota.thr_mod.{mobile,static,comm} — threat map weights

Read near `MilitaryManager.cpp:258` (`commMod`) and used to weight what goes into
the threat map. These are the "how much do we fear X" numbers.

| | apex | stable |
|---|---|---|
| `mobile` | 1.0 | 1.05 |
| `static` | 1.0 | **1.2** |
| `comm` | 0.003 | 0.05 |

apex **under**-weights static defence relative to stock, i.e. fears towers less,
and treats an enemy commander as almost harmless (0.003 against 0.05).

## quota.raid — apex [6, 150], stable [10, 65]

`raid.min` / `raid.avg` (`MilitaryManager.cpp:365-367`). `raid.avg` is passed to
`CRaidTask` as its group size. apex raids in smaller parties (6 vs 10) but allows
far larger ones (150 vs 65).

## quota.num_batch — apex 3, stable 5

`FactoryManager.cpp:335`. How many of the SAME unit a factory builds in a row
before re-choosing. Lower = a more mixed army, more re-evaluation; higher = fewer
decisions and more homogeneous batches.

## quota.scout — maxScouts

`MilitaryManager.cpp:1888`: a scout role unit only gets a SCOUT task while fewer
than `maxScouts` exist. This is the cap on simultaneous scouting, and it is the
first thing to look at for issue 3 in `ISSUES.md` (sight before a push).

## retreat.* — health fractions

`retreat.builder`, `retreat.fighter`, `retreat.shield`, as lists of health
fractions. apex `fighter [0.5, 1.0]` against stable `[0.5, 0.55, 1.0]`.

## response._weight_ — apex 0.1, stable(hard_aggressive) 30.0, engine default 0.5

`FactoryManager.cpp:707` into `reWeight`, consumed once, at line 1658:

    float prob = militaryMgr->RoleProbability(bd) * (probs[i] + reWeight);

where `probs[i]` is the unit's ratio for the current income tier and
`RoleProbability` (`MilitaryManager.cpp:1440`) is

    max over counter-roles of: enemyMetal / (roleCost + 1) * importance

gated by that role's `ratio` and `max_percent`. If `RoleProbability` is 0 the code
falls back to `prob = probs[i]` — **the response system can only boost a unit,
never suppress one below its configured ratio.**

`_weight_` is therefore a dial for how completely counter-picking overrides the
factory ratios:

- **0.1** — the boost stays proportional to the ratio you wrote; `factory.json`
  dominates.
- **30.0** — the ratio becomes noise next to it and whichever role counters the
  enemy takes over production.

apex is at 0.1 because commit `3f5c9cc` moved onto stock's **`hard`** tree, which
ships 0.1; `hard_aggressive` is the unmaintained copy that still has 30.0.

## response.<role>.{vs, ratio, importance, max_percent}

Per `RoleProbability` above: `vs` is the list of enemy roles this role counters,
`importance` scales the urgency per counter, `ratio` gates whether the enemy has
enough of that role to bother, and `max_percent` caps this role as a share of our
own army cost. apex cut every list to 3 entries and dropped `importance` from
15-100 down to 5-20, which flattens counter-picking further on top of the low
`_weight_`.
