# Fewer fighters, more bombers since v0.5.10

His watch, 11-12: the enemy had loads of fighters, we made almost none, and our air was useless.

Measured (scratchpad `fightercensus.py`): metal per seat-game, ours vs v0.5.07 in the same 2v2 +50 gates.

| gate | ours: fighters / bombers | v0.5.07: fighters / bombers |
|---|---|---|
| arm510c (11-11 morning) | 4,741 / 6,843 | 4,994 / 5,592 |
| arm510m (v0.5.10 final) | 2,888 / 7,552 | 4,300 / 5,531 |
| armLN (v0.5.11) | 3,716 / 9,543 | 3,228 / 6,271 |
| cor510c (11-11 morning) | 3,954 / 3,945 | 3,945 / 4,435 |
| cor510k (v0.5.10 final) | 2,725 / 8,408 | 3,404 / 4,051 |
| corLN (v0.5.11) | 2,876 / 7,164 | 4,462 / 4,816 |

The morning build matched v0.5.07 on fighters, so the drop came during the 11-11 changes. Prime suspect: flyers taken
out of the ground-line math (army.as LineMeans/TrackLine, production.as line pull). Even v0.5.07's fighters are only
15-30% of the enemy's air metal. In one 35-minute mirror game we built 347 fighters and lost 327; air squads cannot
group, so the fighters trickle into a massed enemy.

Next: test the 11-11 air changes one at a time on fighter metal; price fighters by the bombers and gunships they save
while their fighters own the sky; add an air-superiority scenario.
