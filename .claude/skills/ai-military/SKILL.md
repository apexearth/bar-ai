---
name: ai-military
description: How the army fights — massing pools, stance, supers, raids; the C++ fight classes are stock since 2026-09-07 (docs/30)
---

# The military — who commands the army

Script layer: `manager/military/` (shim `military.as` — include order is
load-bearing, globals in `state.as`). C++ layer: `vendor/engine/.../task/
fighter/` (mirrored in `cpp/`, see the cpp-dll skill).

## Ownership

| Decision | Owner | File |
|---|---|---|
| Which units mass vs stay stock | `WantsMassing` role filter (AA/scout/arty/super excluded; raiders mass post-T2; riots fall through when escort tasks exist) | `military/hooks.as` |
| Hold home vs march | the DEFEND→ATTACK promote pool; MELEE-promote = a hold. Since 2026-09-13 a hold is a STATE: `HoldReason()` (base attacked / contested / raided / conservative stance) says whether, `HoldNeedM()` (enemy metal within `BASE_DANGER_DIST` of home; the stance case their massed army) says how much -- past it new units go to attack -- and `ReleaseHold()` hands every held pool stock's exit (`aiMilitaryMgr.ReleaseHoldPools()`, C++ `CDefendTask::SetPromote`) the moment no reason remains. Before that a unit elected in a 45-s raid alarm stood at home for the rest of the game. `apex: hold` census | `massing.as`, hooks.as + C++ DefendTask |
| Enemy stance read | `UpdateStance` (AGGRESSIVE/PASSIVE/UNKNOWN, split thresholds, 30s dwell) → budget lean via `StanceShareMult` | `military/stance.as` |
| Retreat/leash | `OutgunnedHere` odds trigger, DEFEND leash on forward fraction | `military/withdraw.as` |
| Supers | `SuperGuardTask` holds; released by the team push window, or when held supers > 40% of army value (then held tasks are ABORTED so they re-elect) | `military/superguard.as` |
| Answer to a building of ours killed on our ground | `NoteRaidOn` (death hook) → nearest spare escorts / DEFEND members / held raid packs / attack-squad units within `PostReach`, 1.2× the armed foe metal there or nobody, on a RAID task with `SetRaidGoal` at the spot; ends clear / 45 s. `apex: raid-answer`, `raid-answer-stat` | `military/raidanswer.as` |
| Their army on our ground, out of the raid answer's reach | the hunt's intercept: every 2 s `InterceptTarget` (biggest uncovered ground group nearer our home than `FoeAnchor`); a new one is decided at once with rule HUNT unless `small` (< 1/8 attack metal) or `outweighed` (1.2× vs attack + home pools + guns). HUNT = AttackTask focus: stage between it and home, go when gathered power beats it, end gone / left / 180 s. `apex: intercept`, `hunt start ... ic=1` | `military/nnhunt.as` |
| Raid targets/roam | C++ CRaidTask: idle roam → nearest enemy-influenced mex spot; FindTarget still has no distance bias (open item) | C++ RaidTask.cpp |
| Idle squad roam | C++ `IFighterTask::RoamPos` — front-anchored scatter (`apex_roam_front`), NOT the uniform-random pick whose mean is map center | C++ FighterTask.cpp |
| Standoff/kite in squads | rows + kite; SIEGE-attr rows fear proximity (back off at 0.9 range, reopen to full) | C++ SquadTask.cpp |
| Front position | posture publishes the lane via `ai.SetFrontPos` — consumed by C++ roam | `military/posture.as` |

## How much army — and why it is an ECONOMY quantity

`market/army.as`. Read this before touching anything that feeds it.

```
EconAssetsM = gAssetsM - gProtM - gBPM                    (census.as)
ArmyTarget  = EconAssetsM * guard_rate
            + max(seenEnemy, (EconAssetsM + ArmyValue) * enemy_prior) * match_ratio
ArmyValue   = sum of MOBILE, non-builder, power>1 units
```

**LAW 1 — anything in the target's basis that cannot appear in `ArmyValue` is a
positive feedback loop.** Defence (`gProtM`) and standing lathe (`gBPM`) are
subtracted for exactly that reason: both are answers to demand, neither is
wealth that invites an attack, and neither can ever count as army. A new
structure class that answers demand must be subtracted here too.

Growing the ECONOMY raising the target is the intended coupling — a richer base
needs a bigger army. Growing the ANSWER raising it is the bug.

> The four laws behind this section, and the couplings it shares with the
> economy and tech, are in the **`ai-couplings`** skill. Load that before
> adding any gate, target, prior or role rule.

## The army gap has three suppliers, not one

`gap = ArmyTarget - ArmyValue`. Three things close it, and they are amplifiers
of each other, not alternatives:

| Supplier | What it raises | Where the gap is read |
|---|---|---|
| build power (nano, cons) | rate metal converts to units | `ProposeNano` army branch |
| static defence | `DefenceTarget` (`brain/market/protect_target.as`) — added 2026-08-26; before that defence had NO target and ran to 175% of eco | the defence gain |
| tech (T2/T3) | combat value per metal | `want_tech` `funded` |
| economy (mex, energy) | metal/s there is to convert | `ArmyGapStream` (want_mex), as a COST |

**LAW 2 — every demand term that buys a supplier must subtract the supply
already standing**, or the demand never closes. `NeediestLine` and
`UnservedLineSpend` subtract `nanosNear * NANO_ABSORB` (17.5 m/s a turret);
the army branch subtracted nothing and bought the same turret forever.

**LAW 3 — `funded` runs opposite to tech's job.** `want_tech` discounts the tech
want by `ArmyValue/ArmyTarget`, so a short army forbids the one thing that
raises combat value per metal. It is a real COST heuristic (do not tech before
you can crew it), but it means anything inflating `ArmyTarget` also vetoes the
tech that would close it. Counterweights already there: the out-teched floor
(`GetEnemyMaxMobileCostM`) and the `EcoQuiet` exemption.

### The cycle that was live until 2026-08-25

> nano built → `gAssetsM` ↑ → `ArmyTarget` ↑ → `funded` ↓ → no T2 →
> army stays weak → gap stays open → another nano

Measured: 30 turrets, 6,300 of 16,905 metal (37% of everything built) on lathe,
T2 reached in 3 of 8 games. After Law 2 in the army branch and Law 1 in the
basis: nano metal median 3,045 → 1,155, metal built median 13,210 → 17,708,
T2 in 5 of 8.

### Telling a healthy loop from a vicious one

Safe when the thing bought is subtracted from the demand that bought it —
`BPGap()` subtracts `BPCapacity()`, so arriving hands close the gap. Vicious
when the purchase lands in the demand's own BASIS instead. Check every new term
against that one question.

## Sensors that lie

- Threat map reads ~0 almost everywhere (3% nonzero) — never build a trigger
  on `GetBuilderThreatAt`; guard every position with `OnMap()` (crash).
- `GetEnemyCost`/`FreshMassingThreat` accumulate on EnemyEnterLOS — silence
  reads "safe" exactly when blind (gSeenPeak guards exist for this).
- Retreating units contribute 0 power (`GetHealthScale`, C++).

## Log lines

`apex: stance -> ...` · `apex: army census fN ...` ·
`apex: <super> holds the defence line` / `releasing N held super task(s)` ·
`apex: porc ON/OFF`

## Tunables

`apex_stance*` · `apex_withdraw_odds` ·
`apex_super_self_frac` (0.4) · `apex_roam_front/apex_roam_r` ·
`apex_siege_fear_frac` · `apex_raid_mexline` · `apex_raid_pack`

## Open items (as of 2026-08-21)

The 0-6 roam regression is unattributed (front-anchored roam vs serial
advsol); the universal one-shot-fear rule (any unit kites anything that
one-shots it and is slower) is scoped but unbuilt — see ISSUES.md.
