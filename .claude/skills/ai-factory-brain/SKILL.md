---
name: ai-factory-brain
description: What gets BUILT from factories — the facqueue, quotas, con wants, plant choice, tech-lead election, and why factory.json is mostly not in the loop
---

# The factory brain — what comes out of the labs

## Ownership

| Decision | Owner | File |
|---|---|---|
| Every driven line's orders | `facqueue` (aborts recruit tasks, holds a Wait, issues builds from `QuotaFor`) | `manager/brain/facqueue.as` |
| Unit composition per line | `QuotaFor` floors + ratio draw (floors CHECKED first: cons, scouts, rezzers; then army by deficit ratio have/want) | same |
| Con counts | `Builder::ConsWantedFor` (income-log curve × greed × budget deferral) then the facqueue's Outmassed clamp (apexearth: "floor of 3 T1 cons; more only on surplus, never while outmassed") | `manager/builder/share.as`, facqueue |
| Which plant to build / switch | C++ FactoryToBuild + `PlantApproved` backstops (T1-commit, income cap `FactoryTypeCap`) | `manager/factory/choose.as`, `switch.as`, `builder/sitesafety.as` |
| T2 timing | `RushReady` (energy ≥ Policy::T2Energy 800, or 400 with a reactor) + `MayPursueT2`/`T2ArmyReady`; NO tech lead in 1v1 (his rule) | `manager/factory/techlead.as` |
| T1-commit (duels, small maps) | `T1Commit` with plateau/enemy-T2/income releases | techlead.as |
| Team roles (tech lead, eco lead) | `RefreshLead` election; eco lead holds the slot from frame 0 pre-designation | techlead.as, `mexhold.as` |
| Adv-con sharing | `ShareAdvCon` (lead keeps AdvConsWanted/2, gifts one per teammate) | `manager/builder/share.as` |

## The one thing to never forget

**While a line is driven, `factory.json` tier tables and `response.json`
decide nothing** except through GetRoleDef's per-role draw. Attribute any
"wrong units built" complaint to the QUOTA first: the `apex: facqueue ...
quota:` log lines print every line's per-def have/want. Days were lost tuning
factory.json weights for a composition the quota owned.

## Log lines

`apex: facqueue takes <plant>` (line adopted) · `... quota: corck=3/1 ...`
(the composition truth) · `apex: rush team=N LEAD/follower ...` (tech state)
· `apexphase: N -> M mInc=...` (build phase) · `apex: factory-diag ...
won:<census>` (which ladder rule wins factory elections)

## Tunables

`apex_fac_queue_brain` (master) · `apex_t1_core_min`/`apex_t2_core_min` ·
`apex_con_min` (3, his number) · `apex_quota_t1_after_t2` ·
`apex_t1_commit` family · Policy::T2Energy/T2EnergyReactor

## Traps

- A quota "floor" that isn't in the isFloor list competes in the ratio draw
  and loses to army wants of 700+ — floors must be floor-checked.
- Factories consume orders in bursts at high sim speed (the GiveOrder lag);
  count what was SENT.
- Only 2 quota lines in a whole game = the facqueue never took lines — check
  `facqueue takes` before anything else.
