# Gate 3: round 3 (outcome-weighted, from sp2) vs the played model (enemy1)

**Candidate:** sp3 = fine-tune from sp2 model-008000, 8,000 steps, 5 workers, 1,331 player games + 97 own games
(selfplay-r1, r2, r3, r4, pc3) at --own-share 0.5, with BARAI_OWN_RATE_K=1.0: on own games a click's weight is
exp(raw rating) both ways (0.14-7.4) and clicks rated under -0.5 are pushed down (9% of clicks vs 2.7%).
runtime/armynet/sp3/model-008000.pt (md5 69a89c4f...).

**Held-out vs enemy1:** act logloss .3155 vs .3168 (better), place 416 vs 415, click rate .041 vs .042 (players .044),
goal 927 vs 941, judge_auc .651. The first candidate that lost nothing on imitation.

**Gate:** all 20 on the Mac (4 lanes), seeds 301-320, Red Comet 1v1, both +50, speed 4, 40-min cap, no exploration,
even seed sp3 at t0. Ladder: the Mac's runtime/armynet/h2h-gate3.log.

**Result: enemy1 14 (11 decided + 3 at cap), sp3 6 (4 decided + 2 at cap). Not promoted: worse.**

| per side, paired | enemy1 | sp3 | enemy1 ahead |
|---|---|---|---|
| trade 8 / 12 / 20 / 30 | 3.39 / 1.03 / 0.83 / 0.88 | 2.22 / 1.23 / 1.08 / 1.01 | 10, 11, 11, 11 of 20 |
| army at 20 / 30 | 17,321 / 41,497 | 17,443 / 40,856 | 11/20, 11/20 |
| buildings killed 20 / 30 | 3,842 / 14,323 | 4,429 / 12,430 | 7/20, 9/20 |
| army in their half 5-15 / 15-25 | 0.20 / 0.23 | 0.20 / 0.27 | -, 6/12 |

sp3 wins: 5 of 6 at t0. Its averages match or beat enemy1's while it loses the games.

**A confound found on the way:** every head-to-head so far was Armada at t0 vs Cortex at t1, and t0 won 42 of 65 PC
games. The seed-parity swap keeps the comparisons fair but doubles the noise. selfplay.sh now plays the same faction on
both sides, alternating every two seeds.

**Verdict:** the stronger outcome weighting made the model play worse in games while its held-out numbers improved:
the per-decision rating (trade against the side's other orders in the window) is not aligned with winning, and
amplifying it amplifies its error. BARAI_OWN_RATE_K stays off by default.

## The rating against the result (64 decided own games, both sides rated; scratchpad rating_vs_win.py)
- The side with the higher mean raw rating won 12 of 64 (19%): the rating runs AGAINST winning.
- The side with fewer orders rated under -0.5 won 40 of 64 (62%): only the bad tail leans the right way.
- Mean raw rating: winners 0.026, losers 0.077.
A likely reason: the rating is the local trade near the order's target (damage dealt minus taken), against the side's
other orders in the same window. A side being pushed back fights near its own guns and trades well locally while
losing the map. Weighting the rating up (round 3) taught the model the loser's habits.
