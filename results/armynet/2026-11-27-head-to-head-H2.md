# H, first arm: G2 (the memory-fix model + E2's flags) head-to-head against enemy1 as he plays it

Plan: `todo/armynet-objectives.md`, the Fable session's H (11-27): a model change counts only head-to-head against
what he plays. `tools/armynet/model_vs_model.sh` (new): Red Comet 1v1, both +50, 40 min, speed 4, same faction both
sides (Armada seeds 1, 4, 5, 8, 9, 12; Cortex 2, 3, 6, 7, 10, 11), the candidate's team by seed parity, both teams
served by their own `serve.py`, every replay built (`runtime/armynet/own-games/mvm-h2`). The rules AI plays the
economy and the commander on both sides.
- **Candidate**: enemy1-absent (md5 2c0819b4), `BARAI_ABSENT=1`, his flags + `--cluster-fight --force-idle`.
- **Played**: enemy1 model-010000, `BARAI_ABSENT=0`, his online flags (`--forces --learned --rally --arc --fbias -0.19`).

Both servers answered from about frame 1,750 in every game; the flags are as meant in each log. Seed 1: the
candidate's pawns killed the played side's lab at 3.1 min, the rules economy never rebuilt it, and the played side
had one or two army units from minute 5 (its server logs nothing while it has none to order). It counts.

## Results (candidate side)

| seed | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | W / L / cap |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| G2 vs enemy1 | **W** 12.7 | **W** 18.9 | behind | ahead | **W** 38.1 | **W** 22.3 | L 27.6 | L 28.2 | behind | L 31.9 | **W** 33.3 | ahead | **5 / 3 / 2 ahead, 2 behind** |

Seven of 12 won or ahead at the cap, five lost or behind: a direction, not a measurement (seed 1 alone is the
lab rush).

## The tables (candidate / played, same games)

| | G2 candidate | enemy1 played |
|---|---|---|
| **building metal killed per 1,000 army metal-min at a live cluster** | **792** | 437 |
| lost per killed there | 1.91 | 1.87 |
| standing order there move / attack / fight | .33 / .53 / .10 | .55 / .38 / .02 |
| orders per unit-minute there | 15.1 | 29.4 |
| stints cleared / left / died / open | .15 / .15 / .63 / .07 | .12 / .30 / .53 / .05 |
| **after clearing: none** | **.367** | .569 |
| after clearing: deeper / sideways / back | .46 / .11 / .06 | .21 / .05 / .18 |
| at a known cluster / of it ghosts | .413 / .722 | .411 / .584 |
| in their half, units 5-15 / 15-25 / 25+ min | .26 / .23 / .28 | .27 / .28 / .21 |
| idle at its target | .269 | .281 |
| funnel arrived | .638 | .698 |
| middle extractors held, ours / theirs at 6 / 9 / 12 min | 0.8 / 0.8, 1.8 / 2.3, **3.7 / 3.1** | 0.8 / 0.8, 2.3 / 1.8, 3.1 / 3.7 |
| army metal-time at 4-12 near our held / empty middle spots | .084 / .299 | .107 / .311 |
| raids into the middle matched / within 60 s / open at 12 | .64 / .40 / .12 (25) | .60 / .47 / .10 (30) |
| middle extractors / builders lost before 12 min, alone | 26 .12 / 23 .22 | 37 .16 / 20 .05 |

## Trade over time (mean per game still running; `tools/armynet/trade_by_minute.py`, new)

| minutes | games | candidate mobile lost / killed / buildings killed | played mobile lost / killed / buildings killed |
|---|---|---|---|
| 0-4 | 12 | 15 / 59 / 182 | 59 / 15 / 70 |
| 4-8 | 12 | 333 / 275 / 355 | 275 / 333 / 297 |
| 8-12 | 12 | 2,243 / 2,353 / 802 | 2,353 / 2,243 / 648 |
| 12-16 | 12 | 5,033 / 4,984 / 1,610 | 4,984 / 5,033 / 1,713 |
| 16-20 | 11 | 7,964 / 8,011 / 4,039 | 8,011 / 7,964 / 2,650 |
| 20-24 | 10 | 8,243 / 10,431 / 6,735 | 10,431 / 8,243 / 4,014 |
| 24-28 | 9 | 15,578 / 15,661 / 7,195 | 15,661 / 15,578 / 6,248 |
| 28-32 | 8 | 21,138 / 19,399 / 6,384 | 19,399 / 21,138 / 20,211 |
| 32-36 | 6 | 24,544 / 21,354 / 25,246 | 21,354 / 24,544 / 6,610 |
| 36-40 | 5 | 21,622 / 19,262 / 17,146 | 19,262 / 21,622 / 8,921 |
| running sum to 40 | | 106,714 / 101,788 / **69,694** | 101,788 / 106,714 / 51,381 |

## Read

1. **G2 beat what he plays, 5-3 with the caps split 2-2.** It is the first model change to come out ahead
   head-to-head; twelve games do not prove it.
2. **The army trade is even; buildings are not.** Mobile metal lost and killed run level through every bucket
   (8-12 min 2,243 vs 2,353). G2 kills more buildings from minute 16 (by 20: 6,989 vs 5,378 in sum; by 40: 69,694 vs
   51,381), with the kill rate at a live cluster 792 vs 437 and "none after clearing" .37 vs .57: what G showed
   against the rules army holds against the played model.
3. **The middle is level between them:** 1.8 vs 2.3 at 9 min, 3.7 vs 3.1 at 12, raids matched .64 vs .60. Neither
   model holds the middle the way the rules army does (.74 against A). The next lever (`--force-threat`) is for
   both.
4. G2 sits at known clusters with more ghosts (.72 vs .58): it goes deeper after clearing (.46) and finds more of
   what it remembered already gone.

<!-- meta {"topic": "armynet", "date": "2026-11-27", "title": "H, first arm: G2 (memory-fix model + E2 flags) head-to-head vs enemy1 as played", "games": 12, "W": 5, "L": 3, "w": 2, "l": 2, "verdict": "Candidate side counted: 5-3, caps 2 ahead / 2 behind. Army trade even every bucket; buildings killed 69,694 vs 51,381 by 40 min (ahead from 16), live-cluster kill 792 vs 437, none after clearing .37 vs .57. Middle level (3.7 vs 3.1 at 12, raids matched .64 vs .60)."} -->
