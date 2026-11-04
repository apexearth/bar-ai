# Silent bugs from the 2026-10-08 code review (unfixed)

Five read-only reviewers, each finding checked against the 2v2 vs BARb batch (tournaments/20261008-054849-nn-barbtrain)
and the Comet 1v1s (20261008-204630). Line numbers are as of 2d9d4fd0; re-check each against the code before fixing.

- **First constructor up to 5 min late** (production.as ~2459, budget.as 178/191). `armyBehind` reads 0/target when a
  commander building finishes before the lab's first order (factory spend excluded), so the YIELD con floor yields.
  13 of 32 1v1 seats got their first con at f=1918-9249 after 1-9 combat units.
- **Join-fight STAY marches the squad to the enemy box** (AttackTask.cpp 745-751 -> 250 MarchEnemyBox). 67 of 98 STAYs
  (comet) were fights <1500 from home; the next line is `atkbox` 41/78 times.
- **Commander net off since 10-05** (nntrain.py ~1226 learn_head, nnlog.as 690). The head adopted lane keys ending
  `evade`; Unstable logs 29 own fields, so every game is skipped as "older" and NnHeadScore refuses silently.
- **Raid net GO strips cover and hold pools** (nnraid.as 271-285); the cover/hold ledgers (hooks.as 96, massing.as 427)
  drop a unit only on death, so they read full. Cover blocked 251 of 564 seat-minutes (1v1).
- **Held pool promotes under MELEE and poisons every later hold** (DefendTask.cpp 116-125, MilitaryManager.cpp
  686/750/811): MELEE falls to default (rally) and is filed under MELEE but removed under RALLY.
- **Supers never released** (superguard.as 110-118): 0 "releasing" lines in 21 games with 228 holds; Legion supers
  are keyed by cost and never count.
- **Siege ring backs out of the unit's own range** (SquadTask.cpp 553-608).
- **Constructors flee only when hit** (BuilderManager.cpp 1649 reflex covers rezzers only): 6,549 of 7,993 2v2 con
  deaths came after a con-retreat, 4,805 of them within 10 s.
- **Unit counts read as metal (S28)**: coverage.as 715 ThreatAt, guards.as 149/201 WorkerEnemyM -> EscortOwedM,
  raid.as 268 RaidPackNeed.
- **PickSpot ignores the con-death mark the let-go honours** (want_mex.as 855 vs sitesafety.as 345, maketask.as
  303-321): 898 of 6,405 let-gos re-sent to the same ground within 30 s.
- Suspected: generators skipped team-wide once any hand can build fusion (want_reclaim.as 483-490, want_energy.as
  154); the opening budget reads economy overspent (budget.as 178-185; a radar/tower beat a mex 42 times in the
  first 4 min).
- Smaller: raid decision acts on a 1-5 s old unit snapshot (nnraid.as ~655); stall hoist on a raw pull spike
  (guards.as 927); factory-floor EMA polluted by placeholder values (decide.as 2569); exposure cached at the con's
  position 30 s (army.as 107-136); GetAllyBuilds engine call per allied unit (InitScript.cpp).
