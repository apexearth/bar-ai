# Gate 2: self-play round 2 candidate (sp2) vs the played model (enemy1)

**Candidate:** sp2 = fine-tune from enemy1 model-010000, 8,000 steps, 3 data workers (1.62 steps/s), on the 1,331
player games plus own-games selfplay-r1 at --own-share 0.5: 34 own games (11 round-1 self-play with --explore 1.0,
6 A/A, 17 gate-1). runtime/armynet/sp2/model-008000.pt (md5 84bb5f05...).

**Held-out (141 player games) vs enemy1:** act logloss .3222 vs .3168, place 424 vs 415 elmos, click rate .039 vs .042
(players .044), goal at 60 s 923 vs 941 (better), deep .406 vs .397, judge_auc .648.

**Gate:** Red Comet Remake 1.8 1v1, both +50, speed 4, 40-min cap, no exploration, same serve flags both sides, sides
swapped by seed parity; a capped game goes to the side with more standing metal at the cap. Seeds 81-90 PC (two
lanes), 51-57 Mac (v0.5.21 + aa + one-con + lobby-hands, one lane), 58-60 PC. The PC also replayed 56 and 57
(rebalance message arrived late): extra games, not counted.

**Result: 10 - 10. Not promoted, no improvement.**

| games | sp2 | enemy1 |
|---|---|---|
| PC 81-90 | 7 (5 decided + 2 at cap) | 3 (decided) |
| Mac 51-57 | 3 (52, 55 decided; 56 at cap) | 4 (54, 57 decided; 51, 53 at cap) |
| PC 58-60 | 0 | 3 (59 decided; 58, 60 at cap) |
| PC duplicates 56, 57 (not counted) | 0 | 2 |

Every game played, duplicates included: sp2 10, enemy1 12. The 7-3 first half was noise: seed 56 went to sp2 on the
Mac and to enemy1 on the PC.

**Next (round 3):** change what is learned, not only how much: outcome weighting pushed harder on our own games
(moves that won their fights up, lost ones down), train from sp2, data from both models with exploration
(PC seeds 91-102 started, Mac 61-72).
