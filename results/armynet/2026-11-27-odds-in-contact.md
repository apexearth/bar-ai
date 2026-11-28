# Fighting outgunned: his G2 watch game, and the sets, model and rules side

His G2 watch game (11-27, `matches/watch-g2`: Comet Catcher 1v1, both +50, Armada, speed 10; G2 as `play_online.py`
defaults on team 0 against our rules army) ended at 29.5 min with the rules army winning. His read while watching:
our army went in even when it was outgunned and did not preserve itself. This page measures that, with no new
games beyond his.

`tools/armynet/objectives_army.py` now prints two "odds" lines (ground truth from the replay):
- **In contact**: an armed enemy unit within our unit's weapon range + 200.
- **Odds**: our armed metal within 1,000 of the unit against theirs within 1,000; **outgunned** under 1 / 1.5,
  **ahead** over 1.5, else **even**.
- **Order there**: toward (its target 100+ closer to their armed units' centre near it), away (100+ farther), or hold
  (no order, or neither).
- **Lost by odds**: a unit that dies within 20 s of its last contact counts at that contact's odds.

## The tables

| | in contact (of metal-time) | outgunned / even / ahead (of contact) | outgunned: toward / hold / away | ahead: toward / hold / away | **our army metal lost outgunned / even / ahead** |
|---|---|---|---|---|---|
| **his watch game, G2 model** | .441 | .15 / .16 / .69 | .13 / .51 / .36 | .21 / .45 / .34 | **.47** / .29 / .24 |
| his watch game, rules | .159 | .05 / .08 / .87 | .05 / .56 / .39 | .13 / .63 / .24 | .23 / .21 / .56 |
| A-12 model (vs rules) | .361 | .14 / .16 / .70 | .16 / .65 / .19 | .20 / .57 / .23 | **.44** / .21 / .35 |
| A-12 rules | .239 | .05 / .10 / .85 | .12 / .69 / .19 | .25 / .56 / .19 | .24 / .27 / .50 |
| G1 model (vs rules) | .413 | .08 / .09 / .83 | .22 / .53 / .24 | .21 / .59 / .20 | .36 / .20 / .44 |
| G1 rules | .261 | .10 / .12 / .78 | .13 / .55 / .32 | .24 / .57 / .19 | .34 / .21 / .45 |
| G2 model (vs rules) | .358 | .07 / .13 / .80 | **.23** / .61 / .17 | .37 / .38 / .25 | .33 / .25 / .41 |
| G2 rules | .334 | .10 / .15 / .75 | .16 / .65 / .20 | .23 / .56 / .22 | .32 / .23 / .45 |
| H2: G2 (vs enemy1) | .294 | .15 / .14 / .71 | **.36** / .51 / .13 | .31 / .51 / .18 | .35 / .22 / .42 |
| H2: enemy1 played | .419 | .05 / .08 / .88 | .17 / .57 / .26 | .24 / .59 / .17 | .21 / .23 / .56 |

## Read

1. **His read holds for his game:** the model lost 47% of its army metal in fights where it was outgunned, twice
   the rules army's 23%, and it was in contact for 44% of its metal-time against the rules army's 16%. The rules
   army takes its fights ahead (.87 of its contact time).
2. **Across the sets it is the same for the played model (A-12: .44 vs .24).** G2 brings the outgunned share of
   losses down to the rules army's level against the rules army (.33 vs .32), but **G2 goes toward the enemy while
   outgunned more often** than anyone: .23 against the rules army (rules .16) and .36 head-to-head (enemy1 .17).
   The forced decision makes it go on, deeper, whether or not the odds are with it.
3. When outgunned, every model arm pulls away less often than it holds (.13-.24 away); in his game it was .36.
4. **A contract check now carries it** (`tools/contract.py` "army lost outgunned": the same share from the infolog's
   30-s army snapshots of both sides; the gadget snapshots every AI team). On these games, model / rules: his game
   .54 / .18, A seeds 1-6 .46 / .24, A seeds 7-12 .41 / .25, G2 vs rules .43 / .30, H2 G2 .30 / enemy1 .33.
   Coarser than the replay measure, same direction. (Corrected the same day: the first reading split the snapshot
   line on spaces, its units are comma-separated, so it saw one unit per snapshot.)
5. **What it points at:** the odds are not weighed when a force is asked. The queued `--force-fire` arm (V1) asks a
   force the moment a member is hurt and logs its answer against force metal / enemy metal near it: it shows whether
   the model has an opinion about pulling back when outgunned. If it has none, "pull back when outgunned" joins the
   objectives labelled from rules-army episodes (roadmap step 3).

<!-- meta {"topic": "armynet", "date": "2026-11-27", "title": "Fighting outgunned: his G2 watch game, and the sets, model and rules side", "games": 1, "W": 0, "L": 1, "w": 0, "l": 0, "verdict": "His G2 watch game, lost at 29.5 min. Army metal lost while outgunned: model .47 vs rules .23 (A-12 .44 vs .24; G2 vs rules .33 vs .32). G2 goes toward the enemy while outgunned .23 (rules .16), .36 head-to-head (enemy1 .17). In contact .44 of metal-time vs .16."} -->
