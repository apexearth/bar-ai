# Gate 1: self-play round 1 candidate (sp1) vs the played model (enemy1)

**Purpose:** todo/armynet-self-play.md. The first self-improvement round: 12 self-play games (enemy1 on both sides,
`--explore 1.0`: a fifth of force-steps take a place sampled among the head's top 8) + 6 A/A games, built into
own-games (runtime/armynet/own-games/selfplay-r1, 17 files; one playback died). sp1 = fine-tune from enemy1
model-010000 with `--own selfplay-r1 --own-share 0.5`, 8,000 steps planned; the final save failed when C: filled, so
the candidate is the step-6,000 save (runtime/armynet/sp1/model-006000.pt).

**Held-out (141 player games), same data version:** act logloss .3191 vs .3168, place error 428 vs 415 elmos, force
click rate .036 vs .042 (players .044): slightly worse at imitating players.

**Gate settings:** Red Comet Remake 1.8 1v1, both sides Apex lane AI with the bridge (armynet=1), both +50, speed 4,
40-min cap, seeds 31-40 (lane armynet) and 41-50 (lane rel521), sides swapped by seed, no exploration, the same serve
flags both sides (--forces --learned --rally --arc --fbias -0.19). A capped game counts for the side with more standing
metal (built minus lost) at the cap. Ladder: runtime/armynet/h2h-gate1.log.

**Result: 10 - 10. sp1 9 decided + 1 at the cap; enemy1 7 decided + 3 at the cap. Bar: 12 of 20. Not promoted.**

| per side, 20 games (paired) | enemy1 | sp1 | enemy1 ahead |
|---|---|---|---|
| trade 8 / 12 / 20 / 30 | 1.99 / 1.35 / 0.88 / 0.81 | 2.98 / 1.09 / 0.84 / 0.93 | 10/19, 11/20, 11/20, 8/20 |
| army 8 / 20 / 30 | 4,362 / 20,830 / 52,020 | 4,701 / 22,886 / 52,911 | 4/20, 10/20, 8/20 |
| buildings killed 12 / 20 / 30 | 860 / 4,967 / 12,168 | 830 / 4,912 / 15,711 | 10/20, 12/20, 9/20 |
| army in their half, 5-15 / 15-25 min | 0.15 / 0.20 | 0.25 / 0.29 | 8/20, 7/18 |

**Verdict: no improvement.** The two play as equals. sp1 holds a larger army at 8 min (16 of 20) and stands in their
half more, but neither moves the result. Next round: more self-play data (these 20 gate games join own-games),
the full planned steps, 3 data workers.
