# Serve setting C: --unit-contact vs force-level orders in fights (Mac, 20 games)

**Purpose:** in a fight a strong player orders each unit several times a second. With --unit-contact, units within 600
of a visible enemy army unit follow the unit heads every step instead of their force's order. Same model both sides
(enemy1). **Settings:** Red Comet Remake 1.8 1v1, both +50, speed 4, 40-min cap, no exploration, seeds 241-260, sides
swapped by seed parity, Armada t0 / Cortex t1. X = base + --unit-contact, Y = base (--forces --learned --rally --arc
--fbias -0.19). Ladder: the Mac's runtime/armynet/h2h-fgC.log.

**Result: base 13 (5 decided + 8 at cap), unit-contact 7 (4 decided + 3 at cap).** Decided games 5-4; the edge is
from capped games on standing metal.

| per side, paired | base | unit-contact | base ahead |
|---|---|---|---|
| trade 8 / 12 / 20 / 30 | 2.45 / 1.00 / 0.65 / 0.67 | 2.18 / 1.01 / 0.75 / 0.61 | 12, 9, 10, 13 of 20 |
| army 20 / 30 | 22,897 / 60,908 | 23,860 / 61,460 | 9/20, 11/20 |
| buildings killed 20 / 30 | 6,883 / 21,170 | 5,853 / 22,510 | 11/20, 9/20 |
| army in their half 5-15 / 15-25 | 0.19 / 0.20 | 0.22 / 0.19 | 6/20, 11/19 |

**Verdict:** no gain; it leans worse (7 of 20 overall). The unit heads as trained do not reproduce players' fight
micro. Not adopted.
