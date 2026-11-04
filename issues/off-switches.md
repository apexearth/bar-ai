# Switches nobody plays (2026-11-03, cleanup 11-04)

A switch at 0 in `tunables.as` (and in the release) that is not a lobby option runs in no game anyone plays.
11-04 deleted 38 of them first, script side, keeping the off path (smoke game on lane-slim: compiled and played); each
one's measurement is in that commit message. Kept on purpose: diagnostics and training (ETA_LOG, PERF,
CATALOG_DUMP, NN_RECORD, VERBOSE, FORECAST_LOG, PN_EXPLORE, PN_RULE_CENTRE, DRAW_*, PING), test aids (UNIT_LIMIT
for `--restrict-mex`, DEF_OFF), the lobby option PERSONA, and LAB_BEST / ARMY_ONE_CURRENCY, which steps 3-4 of
`todo/one-pricing-scale.md` use.

**11-04, second pass:** COM_HOME (comhome.as is now just ComHomeLathe, which the effigy rush reads), the C++ ONE_ARMY (AttackTask follow/stage), KEEP_ROUTE (TravelAction) and FLUSH_KIN (BuilderTask flush rank), 14 policy.as knobs nothing called, and lava.as, which nothing included. Constants the AI reads directly, not through GetTunable (RAID_MIN_EARLY, SCREEN_MAX, T2_ARMY_FLOOR, AISLE_GROW, ECO_TARGET_BASE_8), are used and stay.

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
