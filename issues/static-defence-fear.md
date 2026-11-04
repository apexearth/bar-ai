# Too afraid of static defences (2026-10-23)

A player's feedback via him, 10-22. Not the attack choice. Scenarios (tools/scenarios/tower_light, tower_heavy,
tower_line) all PASS on the stock army: 10 Centurions kill 3 LLTs or 2 HLTs and their mexes, 16 break a line of
8 LLT + 2 HLT, 0-3 lost. His hosted v0.3.5 games keep 50-74% of the army on ATTACK from minute 5 to 35. Stock
StockFindTarget still divides a distance by a squared distance (the fork bug AttackTask.cpp fixed for our path),
which shrinks a group's influence toward 0 away from base -- reckless, not afraid. Untested: the threat-aware
route walking around tower cover, and the retreat thresholds near towers. Needs what the player actually saw.
