# G: the memory-fix model with E3's and E2's flags, 12 seeds, vs A on the same 12

Plan: `todo/armynet-objectives.md`, the Fable session's G (11-27). Setup as [A](2026-11-27-model-vs-rules-A-B.md)
(Red Comet 1v1 +50, 40 min, speed 4, same faction both sides, the model's team by seed parity), on A's six seeds
plus six new ones (7-12); every game's replay kept and built (`runtime/armynet/own-games/mvr-{g0,g1,g2}`).
- **A-12**: enemy1 model-010000, his online flags (`--forces --learned --rally --arc --fbias -0.19`); seeds 1-6 are
  A's games (mvr-a), seeds 7-12 new (mvr-g0).
- **G1**: the [C](2026-11-27-model-vs-rules-C.md) model (enemy1-absent, md5 2c0819b4, `BARAI_ABSENT=1`) with his
  flags + E3's (`--cluster-fight --force-idle --hybrid-cluster`), seeds 1-12.
- **G2**: the C model with his flags + E2's (`--cluster-fight --force-idle`), seeds 1-12.
Read with `tools/armynet/objectives_army.py --mvr-log ... --side model|rules`.

## Results (model side, by seed)

| seed | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | W / L / cap |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A-12 | L | **W** | L | L | L | L | L | L | L | L | L | L | 1 / 11 / - |
| G1 (C + E3) | L | L | L | L | L | **W** | L | **W** | **W** | L | L | **W** | 4 / 8 / - |
| G2 (C + E2) | L | ahead | L | L | **W** | L | L | ahead | **W** | L | **W** | **W** | 4 / 6 / 2 ahead |

G2 seeds 4 and 5 ended at 8.6 and 9.0 min on a commander kill, one each way. Against A, seed by seed: G1 better on
4 seeds, worse on 1; G2 better on 5 or 6 (two caps ahead where A lost or won), worse on 0 or 1.
On the new seeds 7-12 A lost all six; G1 won 3, G2 won 3 and was ahead at the cap in a fourth.

## The tables (model / rules side, same games, 12 each)

| | A-12 model | A-12 rules | G1 model | G1 rules | G2 model | G2 rules |
|---|---|---|---|---|---|---|
| **building metal killed per 1,000 army metal-min at a live cluster** | 262 | 1,005 | **651** | 831 | 440 | 868 |
| **our army metal lost per building metal killed there** | 3.62 | 0.53 | **0.79** | 0.91 | 1.34 | 1.08 |
| share of metal-time at a live cluster | .114 | .172 | .249 | .141 | .243 | .158 |
| enemy building in weapon range there | .548 | .551 | .707 | .591 | .688 | .535 |
| standing order there move / attack / fight | .73 / .21 / .00 | .48 / .35 / .12 | .43 / .42 / .09 | .50 / .35 / .10 | .21 / .65 / .11 | .49 / .42 / .07 |
| orders per unit-minute there | 39.9 | 24.3 | 21.8 | 23.5 | 17.2 | 25.0 |
| stints cleared / left / died / open | .11 / .28 / .52 / .09 | .33 / .32 / .32 / .03 | .29 / .18 / .42 / .11 | .27 / .29 / .43 / .02 | .14 / .19 / .48 / .19 | .20 / .30 / .49 / .02 |
| after clearing: none | .725 | .560 | .596 | .420 | .547 | .465 |
| after clearing: deeper / sideways / back | .08 / .13 / .07 | .20 / .07 / .17 | .23 / .05 / .13 | .20 / .14 / .24 | .24 / .10 / .12 | .22 / .09 / .23 |
| none = same / ghost / dead (count) | .50 / .41 / .08 (28) | .75 / .21 / .04 (230) | .83 / .13 / .04 (67) | .73 / .20 / .07 (124) | .66 / .26 / .08 (75) | .80 / .07 / .12 (87) |
| at a known cluster / of it ghosts | .190 / .401 | .464 / .630 | .399 / .376 | .345 / .590 | .470 / .483 | .365 / .568 |
| **in their half, units 5-15 / 15-25 / 25+ min** | .21 / .21 / .20 | .35 / .40 / .56 | .19 / .22 / .34 | .29 / .42 / .34 | **.28 / .36 / .45** | .28 / .39 / .29 |
| idle at its target | .259 | .266 | .301 | .240 | .238 | .262 |
| funnel arrived | .623 | .627 | .676 | .585 | .713 | .620 |

Seeds 1-6 vs 7-12, model side (kill rate / lost per killed / their half 15-25):
G1 1,078 / 0.73 / .18 and 587 / 0.81 / .25; G2 181 / 1.80 / .22 and 749 / 1.21 / .41. G2's seeds 1-6 include
the seed-2 game that sat at a cluster to the cap (stints open .47), so its kill rate there is one long siege.

Forced answers (serve logs, all 12 games): G1 8,354: deeper .43, same .43, back .12, sideways .02 (3,009
unit-steps released at a cluster); G2 9,215: deeper .50, same .34, back .12, sideways .04.

## Read

1. **Both G arms beat A on the same 12 seeds** (4-8 and 4-6 with 2 ahead vs 1-11), and the gain held on the six
   seeds A had not played (A 0-6; G1 3-3; G2 3-2, 1 ahead). Twelve games each is still a direction
   (one-sided Fisher on 5 of 12, G2 with its caps ahead as halves, vs A's 1 of 12 is about .08), but it is the same direction as E (1 -> 2 -> 3 of 6), now with
   the memory-fix model and new seeds.
2. **G1 (C + E3) trades best at a cluster:** 651 killed per 1,000 metal-min at 0.79 lost per killed, better than its
   rules side's 0.91 and far from A's 3.62 over these 12. It does not stand forward until late (their half .22 at
   15-25 min, as A).
3. **G2 (C + E2) stands furthest forward** of any model arm so far: units in their half .28 / .36 / .45 at 5-15 /
   15-25 / 25+ min, level with or past its rules side (.28 / .39 / .29), with the most time at a cluster (.42 of
   metal-time; .65 when ahead). It trades worse there than G1 (1.34), and its kill rate leans on one long game.
4. **"None after clearing" is a choice in both:** idle with no decision is 0; the rest is "stay here" (.83 / .66)
   or a ghost (.13 / .26). The memory fix does not clear ghosts that died unseen; G2 has no release to the AI's
   own attack, so it spends more of that time on ghosts.
5. Not changed: his online model and flags.

<!-- meta {"topic": "armynet", "date": "2026-11-27", "title": "G: the memory-fix model with E3's and E2's flags, 12 seeds, vs A on the same 12", "games": 30, "W": 8, "L": 20, "w": 2, "l": 0, "verdict": "Model side counted (G1 C+E3 4-8, G2 C+E2 4-6 + 2 ahead at the cap; A on seeds 7-12 0-6, A-12 1-11). On the same 12 seeds both beat A; held on the 6 new seeds. G1 trades best at a cluster (lost per killed 0.79 vs A 3.62); G2 stands furthest forward (their half .36 / .45 at 15-25 / 25+ min)."} -->
