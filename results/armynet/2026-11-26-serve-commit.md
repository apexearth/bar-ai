# Serve setting B: --commit 0.8 vs the random band draw (Mac, 20 games)

**Purpose:** no zigzag. Without --commit the server draws back / hold / forward at random by the model's mass each
decision, so a force can flip bands. With --commit 0.8 a force keeps its order while its destination rates at least
0.8 of the best place (3x3 cells each); otherwise it goes to the best place itself. Same model both sides (enemy1).
**Settings:** Red Comet Remake 1.8 1v1, both +50, speed 4, 40-min cap, no exploration, seeds 221-240, sides swapped by
seed parity, Armada t0 / Cortex t1. X = base + --commit 0.8, Y = base (--forces --learned --rally --arc --fbias -0.19).
Ladder: the Mac's runtime/armynet/h2h-fgB.log.

**Result: 10 - 10** (base 5 decided + 5 at cap; commit 7 decided + 3 at cap).

| per side, paired | base | commit | base ahead |
|---|---|---|---|
| trade 8 / 12 / 16 / 20 / 30 | 2.56 / 1.03 / 0.70 / 0.69 / 0.65 | 1.78 / 0.94 / 0.84 / 0.69 / 0.62 | 11, 11, 7, 10, 9 of 20 |
| army 20 / 30 | 23,862 / 63,231 | 24,539 / 60,580 | 9/20, 10/20 |
| buildings killed 20 / 30 | 6,245 / 20,076 | 5,890 / 23,468 | 11/20, 9/20 |
| army in their half 5-15 / 15-25 | 0.18 / 0.20 | 0.20 / 0.20 | 9/20, 8/20 |

**Verdict:** no measurable difference at 20 games; commit wins 2 more decided games and kills more buildings late.
It removes the zigzag he dislikes at no measured cost.
