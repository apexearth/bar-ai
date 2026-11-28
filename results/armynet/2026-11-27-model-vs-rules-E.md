# Army model vs our rules army: E1 / E2 / E3 (serve-only), A as the baseline

Plan: `todo/armynet-objectives.md`, the Fable session's E (11-27). Setup as
[A](2026-11-27-model-vs-rules-A-B.md): enemy1 model-010000 with his online flags vs our rules army, Red Comet 1v1
+50, A's six seeds and sides, same faction both sides, replays built and read with `tools/armynet/objectives_army.py
--mvr-log ... --side model|rules`. Serve-only changes (no retraining):
- **E1** `--cluster-fight`: a move order aimed within reach (range + 200) of a known enemy cluster (2,000 metal of
  remembered buildings within 800, from the model's own input) or the presumed base goes out as a fight order.
- **E2** E1 + `--force-idle`: a force standing still with no order, or at the place it was sent, decides every step
  (no click roll); where the forced answer goes is logged (same spot within 300 / deeper / sideways / back).
- **E3** E2 + `--hybrid-cluster`: a ground unit with a living enemy building in sight within reach at a known cluster
  is released to the AI's own attack (the existing release line) until no building is in view, then returns to the
  model, which must answer (E2). Serve-only, no C++.

## Results (model side)

| | won | lost | at the cap |
|---|---|---|---|
| A | 1 | 5 | - |
| E1 | 1 | 4 | 1 (behind) |
| E2 | 2 | 4 (two commander deaths at 9 and 10 min) | - |
| E3 | **3** | 3 | - |

## The tables (model / rules side, same games)

| at a live enemy cluster | A model | A rules | E1 model | E1 rules | E2 model | E2 rules | E3 model | E3 rules |
|---|---|---|---|---|---|---|---|---|
| **building metal killed per 1,000 army metal-min** | 405 | 1,253 | 361 | 923 | **1,157** | 655 | **999** | 824 |
| standing order move / attack / fight | .80 / .17 / .00 | .41 / .39 / .13 | .12 / .62 / .11 | .43 / .41 / .12 | .15 / .65 / .16 | .40 / .45 / .12 | .26 / .56 / .15 | .42 / .38 / .15 |
| orders per unit-minute there | 42.2 | 25.8 | 12.0 | 24.7 | 15.2 | 25.3 | 19.1 | 22.9 |
| enemy building in weapon range | .556 | .516 | .540 | .579 | .535 | .489 | .488 | .614 |
| share of metal-time at a live cluster | .140 | .139 | .215 | .184 | .141 | .175 | .168 | .136 |
| stints cleared / left / died | .13 / .27 / .42 | .42 / .27 / .30 | .14 / .13 / .58 | .30 / .33 / .36 | .21 / .19 / .60 | .32 / .24 / .42 | .29 / .17 / .48 | .22 / .36 / .42 |
| **after clearing: none** | .635 | .503 | .620 | .428 | .602 | .423 | **.564** | .474 |
| after clearing: deeper / sideways / back | .14 / .23 / .00 | .16 / .06 / .28 | .28 / .02 / .08 | .20 / .13 / .25 | .18 / .17 / .05 | .36 / .20 / .02 | .17 / .08 / .18 | .20 / .13 / .20 |

| whole game | A model | E1 model | E2 model | E3 model |
|---|---|---|---|---|
| idle at its target | .227 | .177 | .198 | .239 |
| ordered at a cluster or base | .212 | .294 | .353 | .353 |
| in their half, units 5-15 / 15-25 min | .258 / .326 | .218 / .192 | .249 / .208 | .286 / .335 |
| at a known cluster / of it ghosts | .256 / .452 | .305 / .295 | .386 / .636 | .379 / .557 |
| funnel arrived | .567 | .687 | .650 | .674 |

**E2's forced answers** (all six games, 4,027): deeper .46, same spot .40, back .12, sideways .02. Where the model
must answer, it goes on more often than it stays: it holds an opinion about going on that the click roll was hiding.
E1 turned 1,489 of 7,527 moves into fights at a cluster (.20); E2 2,094 of 11,135.

## Read

E3's forced answers (5,616): deeper .54, same .32, back .11, sideways .03; 4,504 unit-steps released at a cluster.

1. **The kind alone does not kill (E1).** Fight orders at a cluster switch the kind (attack .62) but cut the
   re-deciding to 12 orders per unit-minute, and the kill rate stays where A had it (361 vs 405): the 11-24
   fightnear result again.
2. **The forced decision is what pays (E2, E3).** With a force made to answer when it stands at its target, the
   kill rate at a live cluster reaches the rules army's (E2 1,157, E3 999; their rules sides 655, 824; A's 1,253).
   The model then goes deeper about half the time it is asked (E2 .46, E3 .54) and back about one time in nine:
   it has an opinion about going on, which the click roll hid. Step 3 does not have to supply it from nothing.
3. **Releasing to the AI's own attack (E3) adds results, not kill rate:** E3 won 3 of 6 (E2 2, A 1), stood further
   forward than E2 (units in their half .29 / .34 at 5-15 / 15-25 min vs .25 / .21), and had the lowest "no order
   after clearing" of the model arms, .564. Still above Fable's "well under .6" for the rules army's .47.
4. Results are six games each: 1 -> 1 -> 2 -> 3 is a direction, not a measurement (a 12-of-20 bar passes an
   identical model one time in four). The continuous measures above are the reading.
5. C (the model retrained with the memory fix, serve with it on, no E flags) on the same seeds: kill rate at a live
   cluster 1,326 (rules side 1,028), none after clearing .359, but units in their half .24 at 5-15 min; 2 of 6.
   The control (same code, no fix) is playing; the C page follows when it is read.

## Added 11-27 (the Fable session's two asks): the trade at a cluster, and what "none" is made of

At a live cluster, our army metal lost (units that died during a stint there) per enemy building metal killed there;
and each "none after clearing" sorted as: an order to where the unit already stands (same; in E2/E3 this includes
the forced answer "same spot"), standing within reach of a remembered cluster with nothing alive (ghost), an order
within 30 s (window), dead within 30 s, else idle. Metal-weighted; the counts are small (15-96 stints per column).

| | lost per killed at a live cluster | none = same / ghost / window / idle / dead (count) |
|---|---|---|
| A model | 1.85 | .60 / .22 / .02 / 0 / .16 (15) |
| A rules | 0.46 | .78 / .18 / 0 / 0 / .04 (96) |
| E1 model | 2.29 | .44 / .43 / 0 / 0 / .13 (20) |
| E1 rules | 0.58 | .82 / .14 / 0 / 0 / .04 (87) |
| E2 model | **0.83** | **.86** / .09 / 0 / 0 / .05 (42) |
| E2 rules | 0.97 | .83 / .10 / 0 / 0 / .07 (36) |
| E3 model | **0.71** | **.90** / .04 / 0 / 0 / .06 (40) |
| E3 rules | 1.00 | .60 / .32 / 0 / 0 / .08 (55) |
| C model (memory fix, no E flags) | 1.16 | .62 / .20 / .01 / 0 / .16 (25) |
| C rules | 0.67 | .73 / .21 / 0 / .004 / .06 (51) |

- **The forced push trades better, it does not just die deeper:** lost per killed falls from 1.85 (A) to 0.83 (E2)
  and 0.71 (E3), under the rules sides of those games (0.97, 1.00). More stints end in deaths, but each building
  costs less.
- **"None" after clearing is not ghosts in E2/E3:** it is the model answering "stay here" (.86, .90; the forced
  answer was "same spot" .32-.40 of the time). Ghost-held is .09 / .04. In A and E1 (no forced decision) ghosts are
  a fifth to two fifths of it. C keeps ghosts at .20 even with the memory fix: the fix forgets what was seen dying,
  not what died unseen.
- So the "none" target is better read as two numbers: idle with no decision (0 in every arm with a forced decision)
  and a decision to stay (a choice the model makes; whether it is a good one is the next question).

<!-- meta {"topic": "armynet", "date": "2026-11-27", "title": "Army model vs our rules army: E1 fight at clusters / E2 + forced decision / E3 + release to the AI attack", "games": 18, "W": 6, "L": 11, "w": 0, "l": 1, "verdict": "Model side counted (E1 1-4 +1 cap behind, E2 2-4, E3 3-3; A was 1-5). Live-cluster kill rate A 405, E1 361, E2 1,157, E3 999 (rules sides 655-1,253). The kind alone does not pay; the forced decision does. Forced answers go deeper .46-.54, back .11-.12. None after clearing best in E3, .564."} -->
