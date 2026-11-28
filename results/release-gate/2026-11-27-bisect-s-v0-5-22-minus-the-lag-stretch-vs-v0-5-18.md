<!-- meta {"date": "2026-11-27", "topic": "release-gate", "title": "Bisect S: v0.5.22 minus the lag stretch vs v0.5.18", "games": 12, "W": 4, "L": 3, "w": 5, "l": 0, "inc20": 1.04, "verdict": "PASS, won or ahead 8/12, lost per killed 0.97 vs 2.67; the full v0.5.22 rerun also passed (6/12), so no regression is shown"} -->
# Bisect S: v0.5.22 minus the lag stretch vs v0.5.18

- **Date:** 2026-11-27
- **Topic:** release-gate
- **Purpose:** Does the lag stretch cause v0.5.22's 2/12? v0.5.21's main/perf/decide in v0.5.22
- **Result:** 12 games: won 4, lost 3, timeouts ahead 5, behind 0; income at 20 min x1.04 ours/theirs
- **Verdict:** PASS, won or ahead 8/12, lost per killed 0.97 vs 2.67; the full v0.5.22 rerun also passed (6/12), so no regression is shown
- **Ours:** Apexarmynet-lane-armynet
- **Opponents:** Apex-v0.5.18
- **Code:** Apex-v0.5.18 = `927ff16c17+512c8555dbd3` (12 games); Apexarmynet-lane-armynet = `7860befdad+941eeb7b5576` (12 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** [50, 50]; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexarmynet:lane-armynet --b Apex:v0.5.18 --map Carrot Mountains v2.0 --minutes 30 --seed 1 --speed 20 --handicap 50,50 --sides Armada,Armada --ai-option armynet=0 --ai-option-b armynet=0 --out matches/bisS-CarrotMo-s1`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Carrot Mountains v2.0 | Armada | 1 | 0 | W | 28.62 | x1.85 | 7860befdad+941eeb7b5576, 927ff16c17+512c8555dbd3 | `matches/bisS-CarrotMo-s1` |
| 1 | Carrot Mountains v2.0 | Armada | 2 | 1 | w | 30.0 | x1.09 | 7860befdad+941eeb7b5576, 927ff16c17+512c8555dbd3 | `matches/bisS-CarrotMo-s2` |
| 2 | Carrot Mountains v2.0 | Cortex | 3 | 0 | w | 30.0 | x2.03 | 7860befdad+941eeb7b5576, 927ff16c17+512c8555dbd3 | `matches/bisS-CarrotMo-s3` |
| 3 | Carrot Mountains v2.0 | Cortex | 4 | 1 | W | 23.52 | x3.72 | 7860befdad+941eeb7b5576, 927ff16c17+512c8555dbd3 | `matches/bisS-CarrotMo-s4` |
| 4 | Comet Catcher Remake 1.8 | Armada | 1 | 0 | L | 25.21 | x0.29 | 7860befdad+941eeb7b5576, 927ff16c17+512c8555dbd3 | `matches/bisS-CometCat-s1` |
| 5 | Comet Catcher Remake 1.8 | Armada | 2 | 1 | L | 21.93 | x0.07 | 7860befdad+941eeb7b5576, 927ff16c17+512c8555dbd3 | `matches/bisS-CometCat-s2` |
| 6 | Comet Catcher Remake 1.8 | Cortex | 3 | 0 | w | 30.0 | x0.68 | 7860befdad+941eeb7b5576, 927ff16c17+512c8555dbd3 | `matches/bisS-CometCat-s3` |
| 7 | Comet Catcher Remake 1.8 | Cortex | 4 | 1 | w | 30.0 | x1.89 | 7860befdad+941eeb7b5576, 927ff16c17+512c8555dbd3 | `matches/bisS-CometCat-s4` |
| 8 | Red Comet Remake 1.8 | Armada | 1 | 0 | w | 30.0 | x1.23 | 7860befdad+941eeb7b5576, 927ff16c17+512c8555dbd3 | `matches/bisS-RedComet-s1` |
| 9 | Red Comet Remake 1.8 | Armada | 2 | 1 | L | 23.15 | x0.17 | 7860befdad+941eeb7b5576, 927ff16c17+512c8555dbd3 | `matches/bisS-RedComet-s2` |
| 10 | Red Comet Remake 1.8 | Cortex | 3 | 0 | W | 23.05 | x10.11 | 7860befdad+941eeb7b5576, 927ff16c17+512c8555dbd3 | `matches/bisS-RedComet-s3` |
| 11 | Red Comet Remake 1.8 | Cortex | 4 | 1 | W | 24.45 | x1.91 | 7860befdad+941eeb7b5576, 927ff16c17+512c8555dbd3 | `matches/bisS-RedComet-s4` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.90 | 3.17 | - | ok |
| t2->4th moho (min) | 5.71 | 6.72 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.32 | 0.28 | 0.00 | ok, short of aim |
| adv plant frame x | 2.50 | 1.62 | 1.50 | worse, within noise (83% of resamples) |
| near-done /10k built | 0.36 | 0.52 | 0.00 | ok, short of aim |
| t2 cons given early | 0.00 | 0.00 | 0.00 | ok |
| supers before 4 moho | 0.75 | 1.82 | 0.00 | ok, short of aim |
| lone t2 con minutes | 0.17 | 0.18 | 0.00 | ok, short of aim |
| base lost /covered min | 15.75 | 990.31 | 0.00 | ok, short of aim |
| oldest plant order min | 2.45 | 2.49 | - | ok |
| no t2 by minute 20 | 0.00 | 0.08 | - | ok |
| frozen minutes | 0.00 | 0.00 | 0.00 | ok |
| com minutes on their half | 0.79 | 0.83 | - | ok |
| com lost on their half | 0.00 | 0.00 | 0.00 | ok |
| mex lost to ticks by 10 min | 0.58 | 0.75 | 0.00 | ok, short of aim |
| raider repeat kills /10min | 12.90 | 15.50 | 0.00 | ok, short of aim |
| their mex killed /10min (neg) | -19.47 | -14.52 | - | ok |
| their army / ours, 8-12 min | 0.62 | 0.75 | - | ok |
| lost per killed | 0.97 | 2.67 | - | ok |
| reclaimed / killed (neg) | -0.11 | -0.19 | - | worse, within noise (76% of resamples) |
| bare-hands minutes | 0.00 | 0.17 | 0.00 | ok |
| mex done by 3 min (neg) | -5.00 | -5.00 | - | ok |
| AA panics on unarmed air | 0.00 | 0.00 | 0.00 | ok |
| minutes without a land lab | 0.02 | 0.00 | 0.00 | ok, short of aim |
| minutes without a converter | 0.00 | 0.00 | 0.00 | ok |
| wiped bomber runs | 0.25 | 0.36 | 0.00 | ok, short of aim |
| runs turned back | 0.00 | 0.00 | 0.00 | ok |
| gunships sent to lose | 0.00 | 0.00 | 0.00 | ok |
| stacked radar/jammers | 0.00 | 0.00 | 0.00 | ok |
| army stuck /10min/1k army | 4.12 | 3.46 | 0.00 | ok, short of aim |
| ground given up share | 0.25 | 0.26 | 0.00 | ok, short of aim |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.78 | -1.35 | - | ok |
| army share (neg) | 0.45 | 0.37 | - | ok |
| -log income at 20 | -5.29 | -5.39 | - | ok |
| games won or ahead | 0.67 | 0.50 | - | ok |

Contract: **PASS** over 12 games (12 of our seats, 12 release seats); 13 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.18 (run `python tools/anomaly.py build`)
```
