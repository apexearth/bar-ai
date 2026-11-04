# Switches nobody plays (2026-11-03, cleanup 11-04)

A switch at 0 in `tunables.as` (and in the release) that is not a lobby option runs in no game anyone plays.
11-04 deleted 38 of them, script side, keeping the off path (smoke game on lane-slim: compiled and played); each
one's measurement is in that commit message. Kept on purpose: diagnostics and training (ETA_LOG, PERF,
CATALOG_DUMP, NN_RECORD, VERBOSE, FORECAST_LOG, PN_EXPLORE, PN_RULE_CENTRE, DRAW_*, PING), test aids (UNIT_LIMIT
for `--restrict-mex`, DEF_OFF), the lobby option PERSONA, and LAB_BEST / ARMY_ONE_CURRENCY, which steps 3-4 of
`todo/one-pricing-scale.md` use.

**Still to delete, needs care:**
- `TUNE_COM_HOME` (comhome.as): its helpers are called by live commander code (comdecide, comrush, comship,
  smallhard, lift) without the switch, so only the switched parts can go.
- C++, needs a DLL build: `TUNE_ONE_ARMY` (AttackTask ArmyStep/FollowArmy/StageArmy, MilitaryManager board; also
  forced off under the stock army), `TUNE_KEEP_ROUTE` (TravelAction.cpp SetPath), `TUNE_FLUSH_KIN`
  (BuilderTask.cpp flush pass).
- Read by nothing at all (check.py dashboard section): T2_ENERGY, T2_ENERGY_REACTOR, CON_LOG_T1_A/B,
  CON_LOG_T2_A/B, ECO_TARGET_BASE_8, E_PER_METAL, GREED_CONS, RECLAIM_GEN_E, RECLAIM_PAD, AISLE_GROW,
  ENERGY_HEADROOM, FUSION_MIN_ENERGY, RAID_MIN_EARLY, RECLAIM_SOLAR_E, SCREEN_MAX, T2_ARMY_FLOOR.

**Built for one of his asks, never given a fair test (his call: test a short list, delete the rest and move
the ask back to `todo/`):** team massive air (TEAM_AIR), the rush as a play (STRIKE_PHASES, STRIKE_SCHEDULE,
DYN_MOD, PRODUCE_FOCUS, PRODUCE_NOCONS), plan by price (PLAN_FROM_PRICE), production answers their army
(COUNTER_MIX), squads gather before launch (GATHER, C++), no late joins (JOIN_ARRIVE), not lost to their commander
(COM_FIGHT, C++), kill their damage first (FOCUS_FIRE, C++), fusions and mohos first (T2_ECO), eco seat builds the
gantry (ECO_SEAT_T3), no gifts to a dead seat (GIFT_STAKE), a hand always on energy (ECO_HAND), upgrades first
(UPGRADE_FIRST), one decision per crew (CREW_ELECT), bolder commander (COM_BOLD), AFUS before Epic
(ENERGY_GROWTH_ARRIVE), land value (LAND_VALUE), air transports (LIFT_TURRETS, LIFT_HANDS), cannons on one area
(LRPC_FOCUS), fusion soon after T2 (T2_FUSION_PULL, waits on his ruling), siege (SIEGE, his ruling: off until the
siege squad works).
