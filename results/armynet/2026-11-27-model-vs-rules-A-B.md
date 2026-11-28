# Army model vs our rules army, paired: A (baseline) and B (memory fix, serve only)

Plan: `todo/armynet-objectives.md`, the Fable session's A-D (11-27). Read with `tools/armynet/objectives_army.py
--mvr-log <run log> --side model|rules` (definitions in its docstring and on
[the step-2 page](2026-11-27-step2-army-instrument.md)); the contract check "army idle on dead enemy ground" from the
infologs.

**Games:** `tools/armynet/model_vs_rules.sh`. Red Comet 1v1, both +50, 40-min cap, speed 4, the same faction on both
sides (Armada seeds 1, 4, 5; Cortex 2, 3, 6), both seats our AI v0.5.22 game-side (lanes armynet, rel521), one with
the army model (enemy1 model-010000, his online flags `--forces --learned --rally --arc --fbias -0.19`), the other
with our rules army; the model side by seed parity. Replays built into `runtime/armynet/own-games/mvr-a`, `mvr-b`.
- **A:** the model as played (matches/mvr-mvr-a-s1..6; run log runtime/armynet/mvr-mvr-a.log). Seed 2's server
  started during the data.py edits; replayed as mvr-a2 (the model lost it).
- **B:** the same with `BARAI_ABSENT=1` on serve only (data.absence_marks: a remembered enemy building is forgotten
  once one of our units had its spot within 0.7 x sight after its last sighting with nothing there). The model was
  trained without it, so B's inputs differ from training (asked for: how much of the gap is the defect).

## Results

| | model won | rules won |
|---|---|---|
| A | 1 (s2; 0 with the replay of s2) | 5 (6) |
| B | 2 (won s1, ahead at the cap s6) | 4 |

## The tables (model side / rules side, same games)

| A | model | rules |
|---|---|---|
| idle at its target | .227 | .247 |
| ordered at a cluster or base | .212 | .265 |
| in their half, units 5-15 / 15-25 min | .258 / .326 | .369 / .469 |
| in their half, metal, whole game | .379 | .492 |
| at a known cluster / of it ghosts | .256 / .452 | .400 / .652 |
| **building metal killed per 1,000 army metal-min at a live cluster** | **405** | **1,253** |
| there: an enemy building in weapon range | .556 | .516 |
| **there: standing order move / attack / fight / none** | **.798 / .174 / .003 / .025** | .410 / .386 / .131 / .073 |
| in weapon range under a move order | .50 | .57 |
| stints at a live cluster cleared / left / died / open | .125 / .268 / .424 / .183 | .420 / .270 / .299 / .011 |
| after clearing: deeper / sideways / back / none | .135 / .230 / .000 / .635 | .156 / .058 / .283 / .503 |
| funnel arrived / stood short (median elmos) | .567 / 775 | .594 / 992 |
| flips per unit-minute | .257 | .294 |
| contract: army idle on dead enemy ground (mean of seats) | .020 | .048 |

| B (fix on, serve only) | model | rules |
|---|---|---|
| idle at its target | .265 | .248 |
| ordered at a cluster or base | .338 | .299 |
| in their half, units 5-15 / 15-25 min | .225 / .226 | .238 / .347 |
| in their half, metal, whole game | .444 | .327 |
| at a known cluster / of it ghosts | .434 / .738 | .390 / .571 |
| **building metal killed per 1,000 army metal-min at a live cluster** | **304** | **885** |
| there: an enemy building in weapon range | .534 | .588 |
| **there: standing order move / attack / fight / none** | **.634 / .291 / .002 / .072** | .449 / .432 / .074 / .046 |
| stints at a live cluster cleared / left / died / open | .125 / .361 / .378 / .136 | .253 / .274 / .434 / .040 |
| after clearing: deeper / sideways / back / none | .086 / .027 / .121 / **.766** | .303 / .103 / .161 / .433 |
| funnel arrived / stood short (median elmos) | .513 / 760 | .663 / 1,098 |
| flips per unit-minute | .178 | .244 |

Seed 2 of A replayed (its server started during the edits): the model lost it (the original was the model's only A
win, a 27.6-min game that carries much of A's late model metal-time). With the replay in place of the original, the
model's A column moves a long way (their half 5-15 .166, at a known cluster .045, live-cluster kill rate 392): six
games are too few for the whole-game shares; the live-cluster kill rate and order kinds are steadier (405 / 392
either way, the rules army 1,253 / 1,200).

## Read

A: against the rules army the model stands less forward (units in their half .26 vs .37 at 5-15 min), and at a
live enemy cluster it kills buildings at a third of the rules army's rate (405 vs 1,253) while just as often in
weapon range (.556 vs .516). The difference is the order it stands under there: **move .80 vs .41, attack .17 vs
.39**. A unit under a move order walks on rather than stopping to shoot buildings. Fable's (D) suspicion, confirmed
in kind rather than distance (in range under a move order: .50, so not mainly "stops short"). The players' order
kinds at a live cluster are not read yet (next run of the players column).
Ghosts are not the model's main problem against the rules army: .452 of its cluster time vs the rules army's .652 (the
rules army clears more, so more of its cluster time is on ground it already cleared).

B: the memory fix on serve alone does not close the gap; if anything the model reads a little worse (kill rate 304
vs 405, ghosts .738 vs .452, no order after clearing .766 vs .635), all within what six different games can move.
It is a distribution shift (the model never trained on the cleaner memory), so B does not judge the fix itself; C
(trained with it) does. The order-kind gap is the same in B (move .63 vs .45, attack .29 vs .43). Results: B model
2 of 6 (won s1, ahead at the 40-min cap in s6), A 1 of 6 (0 of 6 with seed 2's replay).

**What the two runs say about the gap:** the defect is real but not the main reason the model loses to the rules army.
The main measured reason is what it does at a live enemy cluster: move orders where the rules army attacks, and a
third of the kill rate. That points at step 3 (an objective with a kind: kill this cluster) more than at memory.
<!-- meta {"topic": "armynet", "date": "2026-11-27", "title": "Army model vs our rules army, paired: A baseline, B memory fix on serve", "games": 12, "W": 2, "L": 9, "w": 1, "l": 0, "verdict": "Model side counted. At a live enemy cluster the model kills buildings at a third of the rules army's rate (A 405 vs 1,253 per 1k army metal-min), standing under move orders (.80 vs .41; attack .17 vs .39). The memory fix on serve alone (B) does not close it (304 vs 885). Points at step 3."} -->
