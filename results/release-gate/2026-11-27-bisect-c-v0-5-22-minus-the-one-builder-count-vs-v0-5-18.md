<!-- meta {"date": "2026-11-27", "topic": "release-gate", "title": "Bisect C: v0.5.22 minus the one builder count vs v0.5.18", "games": 12, "W": 3, "L": 2, "w": 3, "l": 4, "inc20": 1.21, "verdict": "PASS, won or ahead 8/12; the full v0.5.22 rerun also passed (6/12), so no regression is shown"} -->
# Bisect C: v0.5.22 minus the one builder count vs v0.5.18

- **Date:** 2026-11-27
- **Topic:** release-gate
- **Purpose:** Does the one builder count cause v0.5.22's 2/12? v0.5.21's production.as in v0.5.22
- **Result:** 12 games: won 3, lost 2, timeouts ahead 3, behind 4; income at 20 min x1.21 ours/theirs
- **Verdict:** PASS, won or ahead 8/12; the full v0.5.22 rerun also passed (6/12), so no regression is shown
- **Ours:** Apexrel521-lane-rel521
- **Opponents:** Apex-v0.5.18
- **Code:** Apex-v0.5.18 = `927ff16c17+512c8555dbd3` (12 games); Apexrel521-lane-rel521 = `7860befdad+c424a347a219` (12 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** [50, 50]; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexrel521:lane-rel521 --b Apex:v0.5.18 --map Carrot Mountains v2.0 --minutes 30 --seed 1 --speed 20 --handicap 50,50 --sides Armada,Armada --ai-option armynet=0 --ai-option-b armynet=0 --out matches/bisC-CarrotMo-s1`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Carrot Mountains v2.0 | Armada | 1 | 0 | w | 30.0 | x1.29 | 7860befdad+c424a347a219, 927ff16c17+512c8555dbd3 | `matches/bisC-CarrotMo-s1` |
| 1 | Carrot Mountains v2.0 | Armada | 2 | 1 | w | 30.0 | x1.87 | 7860befdad+c424a347a219, 927ff16c17+512c8555dbd3 | `matches/bisC-CarrotMo-s2` |
| 2 | Carrot Mountains v2.0 | Cortex | 3 | 0 | l | 30.0 | x1.35 | 7860befdad+c424a347a219, 927ff16c17+512c8555dbd3 | `matches/bisC-CarrotMo-s3` |
| 3 | Carrot Mountains v2.0 | Cortex | 4 | 1 | w | 30.0 | x0.63 | 7860befdad+c424a347a219, 927ff16c17+512c8555dbd3 | `matches/bisC-CarrotMo-s4` |
| 4 | Comet Catcher Remake 1.8 | Armada | 1 | 0 | W | 12.37 | - | 7860befdad+c424a347a219, 927ff16c17+512c8555dbd3 | `matches/bisC-CometCat-s1` |
| 5 | Comet Catcher Remake 1.8 | Armada | 2 | 1 | W | 27.71 | x3.64 | 7860befdad+c424a347a219, 927ff16c17+512c8555dbd3 | `matches/bisC-CometCat-s2` |
| 6 | Comet Catcher Remake 1.8 | Cortex | 3 | 0 | l | 30.0 | x0.67 | 7860befdad+c424a347a219, 927ff16c17+512c8555dbd3 | `matches/bisC-CometCat-s3` |
| 7 | Comet Catcher Remake 1.8 | Cortex | 4 | 1 | l | 30.0 | x1.87 | 7860befdad+c424a347a219, 927ff16c17+512c8555dbd3 | `matches/bisC-CometCat-s4` |
| 8 | Red Comet Remake 1.8 | Armada | 1 | 0 | L | 13.98 | - | 7860befdad+c424a347a219, 927ff16c17+512c8555dbd3 | `matches/bisC-RedComet-s1` |
| 9 | Red Comet Remake 1.8 | Armada | 2 | 1 | L | 8.76 | - | 7860befdad+c424a347a219, 927ff16c17+512c8555dbd3 | `matches/bisC-RedComet-s2` |
| 10 | Red Comet Remake 1.8 | Cortex | 3 | 0 | l | 30.0 | x0.47 | 7860befdad+c424a347a219, 927ff16c17+512c8555dbd3 | `matches/bisC-RedComet-s3` |
| 11 | Red Comet Remake 1.8 | Cortex | 4 | 1 | W | 10.07 | - | 7860befdad+c424a347a219, 927ff16c17+512c8555dbd3 | `matches/bisC-RedComet-s4` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.26 | 2.55 | - | ok |
| t2->4th moho (min) | 4.61 | 3.78 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.33 | 0.25 | 0.00 | ok, short of aim |
| adv plant frame x | 2.70 | 2.54 | 1.50 | ok, short of aim |
| near-done /10k built | 0.34 | 0.41 | 0.00 | ok, short of aim |
| t2 cons given early | 0.00 | 0.00 | 0.00 | ok |
| supers before 4 moho | 1.60 | 1.00 | 0.00 | worse, within noise (59% of resamples) |
| lone t2 con minutes | 0.40 | 0.40 | 0.00 | ok, short of aim |
| base lost /covered min | 111.21 | 367.75 | 0.00 | ok, short of aim |
| oldest plant order min | 2.28 | 2.26 | - | ok |
| no t2 by minute 20 | 0.00 | 0.00 | - | ok |
| frozen minutes | 0.00 | 0.00 | 0.00 | ok |
| com minutes on their half | 1.71 | 0.88 | - | worse, within noise (66% of resamples) |
| com lost on their half | 0.08 | 0.08 | 0.00 | ok, short of aim |
| mex lost to ticks by 10 min | 0.33 | 0.17 | 0.00 | ok, short of aim |
| raider repeat kills /10min | 12.68 | 12.99 | 0.00 | ok, short of aim |
| their mex killed /10min (neg) | -17.15 | -20.21 | - | worse, within noise (66% of resamples) |
| their army / ours, 8-12 min | 0.67 | 0.62 | - | ok |
| lost per killed | 1.72 | 1.34 | - | worse, within noise (62% of resamples) |
| reclaimed / killed (neg) | -0.15 | -0.20 | - | ok |
| bare-hands minutes | 0.17 | 0.00 | 0.00 | ok, short of aim |
| mex done by 3 min (neg) | -5.00 | -4.50 | - | ok |
| AA panics on unarmed air | 0.00 | 0.00 | 0.00 | ok |
| minutes without a land lab | 0.00 | 0.01 | 0.00 | ok |
| minutes without a converter | 0.00 | 0.00 | 0.00 | ok |
| wiped bomber runs | 0.37 | 0.46 | 0.00 | ok, short of aim |
| runs turned back | 0.22 | 0.00 | 0.00 | ok, short of aim |
| gunships sent to lose | 0.00 | 0.00 | 0.00 | ok |
| stacked radar/jammers | 0.00 | 0.00 | 0.00 | ok |
| army stuck /10min/1k army | 3.65 | 4.81 | 0.00 | ok, short of aim |
| ground given up share | 0.21 | 0.20 | 0.00 | ok, short of aim |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.42 | -1.34 | - | ok |
| army share (neg) | 0.42 | 0.43 | - | ok |
| -log income at 20 | -5.44 | -5.51 | - | ok |
| games won or ahead | 0.67 | 0.50 | - | ok |

Contract: **PASS** over 12 games (12 of our seats, 12 release seats); 15 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.18 (run `python tools/anomaly.py build`)
```
