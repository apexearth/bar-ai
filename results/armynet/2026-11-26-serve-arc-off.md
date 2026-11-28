# Serve setting A: arc off vs on (Mac, 20 games)

**Purpose:** in a fight, where to stand should be the model's choice; `--arc` moves armed units onto range arcs facing
the enemy after the model picks the place. Same model on both sides (enemy1 model-010000), only the flag differs.
**Settings:** Red Comet Remake 1.8 1v1, both +50, speed 4, 40-min cap, no exploration, seeds 201-220, sides swapped by
seed parity. X = --forces --learned --rally --fbias -0.19 (no arc), Y = the same + --arc. Mac v0.5.21 + aa + one-con +
lobby-hands, 4 lanes. Ladder: the Mac's runtime/armynet/h2h-fgA.log. A capped game goes to the side with more
standing metal at the cap.

**Result: arc on 11 (7 decided + 4 at cap), arc off 9 (7 decided + 2 at cap).**

| per side, paired | arc on | arc off | arc on ahead |
|---|---|---|---|
| trade 12 / 20 / 30 | 0.85 / 0.78 / 0.67 | 1.04 / 0.65 / 0.64 | 8/20, 11/20, 12/20 |
| army at 20 | 22,498 | 24,496 | 7/20 |
| buildings killed 20 / 30 | 5,986 / 23,158 | 5,412 / 19,612 | 12/20, 15/20 |
| army in their half 5-15 / 15-25 | 0.15 / 0.19 | 0.23 / 0.21 | 6/20, 10/20 |

**Verdict:** no measurable difference at 20 games. Arc off stands forward more early and keeps a slightly bigger army;
arc on kills more buildings late (15 of 20). Neither changes the result; the default is unchanged until he decides.
