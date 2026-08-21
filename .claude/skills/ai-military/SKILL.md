---
name: ai-military
description: How the army fights — massing pools, stance, killing blow, withdraw/leash, supers, raids, and the C++ squad movement layer
---

# The military — who commands the army

Script layer: `manager/military/` (shim `military.as` — include order is
load-bearing, globals in `state.as`). C++ layer: `vendor/engine/.../task/
fighter/` (mirrored in `cpp/`, see the cpp-dll skill).

## Ownership

| Decision | Owner | File |
|---|---|---|
| Which units mass vs stay stock | `WantsMassing` role filter (AA/scout/arty/super excluded; raiders mass post-T2; riots fall through when escort tasks exist) | `military/hooks.as` |
| Hold home vs march | the DEFEND→ATTACK promote pool; MELEE-promote = never converts (deliberate hold) | hooks.as + C++ DefendTask |
| Enemy stance read | `UpdateStance` (AGGRESSIVE/PASSIVE/UNKNOWN, split thresholds, 30s dwell) → budget lean via `StanceShareMult` | `military/stance.as` |
| All-in attack | killing blow (`OurArmyNow` vs `FoeMobileMassing`, hysteresis 1.2/0.5) + T1-commit variant | `military/killingblow.as` |
| Retreat/leash | `OutgunnedHere` odds trigger, DEFEND leash on forward fraction | `military/withdraw.as` |
| Supers | `SuperGuardTask` holds; released by killing blow, push window, or when held supers > 40% of army value (then held tasks are ABORTED so they re-elect) | `military/superguard.as` |
| Raid targets/roam | C++ CRaidTask: idle roam → nearest enemy-influenced mex spot; FindTarget still has no distance bias (open item) | C++ RaidTask.cpp |
| Idle squad roam | C++ `IFighterTask::RoamPos` — front-anchored scatter (`apex_roam_front`), NOT the uniform-random pick whose mean is map center | C++ FighterTask.cpp |
| Standoff/kite in squads | rows + kite; SIEGE-attr rows fear proximity (back off at 0.9 range, reopen to full) | C++ SquadTask.cpp |
| Front position | posture publishes the lane via `ai.SetFrontPos` — consumed by C++ roam | `military/posture.as` |

## Sensors that lie

- Threat map reads ~0 almost everywhere (3% nonzero) — never build a trigger
  on `GetBuilderThreatAt`; guard every position with `OnMap()` (crash).
- `GetEnemyCost`/`FreshMassingThreat` accumulate on EnemyEnterLOS — silence
  reads "safe" exactly when blind (gSeenPeak guards exist for this).
- Retreating units contribute 0 power (`GetHealthScale`, C++).

## Log lines

`apex: stance -> ...` · `apex: army census fN ...` · `apex: KILLING BLOW` ·
`apex: <super> holds the defence line` / `releasing N held super task(s)` ·
`apex: porc ON/OFF`

## Tunables

`apex_stance*` · `apex_withdraw_odds` · `apex_t1_push_edge/off` ·
`apex_super_self_frac` (0.4) · `apex_roam_front/apex_roam_r` ·
`apex_siege_fear_frac` · `apex_raid_mexline` · `apex_raid_pack`

## Open items (as of 2026-08-21)

The 0-6 roam regression is unattributed (front-anchored roam vs serial
advsol); the universal one-shot-fear rule (any unit kites anything that
one-shots it and is slower) is scoped but unbuilt — see ISSUES.md.
