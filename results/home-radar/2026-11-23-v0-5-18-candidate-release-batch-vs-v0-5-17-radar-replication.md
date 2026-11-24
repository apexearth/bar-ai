<!-- meta {"date": "2026-11-23", "topic": "home-radar", "title": "v0.5.18 candidate release batch vs v0.5.17 + radar replication, 36 games (seeds 1816-1818)", "games": 36, "W": 2, "L": 8, "w": 16, "l": 10, "inc20": 0.82, "verdict": "Contract PASS, won or ahead 0.50 vs 0.50. Radar on vs off on these seeds even (won/ahead 0.50 vs 0.50, income at 20 131 vs 127, 10 of 18). Both radar batches combined (36 pairs): won/ahead 0.61 vs 0.53, lost per killed 1.32 vs 1.47, income at 20 134 vs 127 (21 of 36), at 24 191 vs 197 -- radar on early is as good or better (before the fixes 0.31 vs 0.67)."} -->
# v0.5.18 candidate release batch vs v0.5.17 + radar replication, 36 games (seeds 1816-1818)

- **Date:** 2026-11-23
- **Topic:** home-radar
- **Purpose:** Release gate for v0.5.18 (arm R: lane defaults = the candidate, no modoptions; contract recorded for AI code 927ff16c17-db260d789aa3) and the radar replication on new seeds (arm R0: apex_home_radar=0). Candidate: home radar, TUNE_STANCE_UNHELD 1 with the reviewer's fixes, walking-cloak and mast fixes, grid layout (flush 2, streets 2).
- **Result:** 36 games: won 2, lost 8, timeouts ahead 16, behind 10; income at 20 min x0.82 ours/theirs
- **Verdict:** Contract PASS, won or ahead 0.50 vs 0.50. Radar on vs off on these seeds even (won/ahead 0.50 vs 0.50, income at 20 131 vs 127, 10 of 18). Both radar batches combined (36 pairs): won/ahead 0.61 vs 0.53, lost per killed 1.32 vs 1.47, income at 20 134 vs 127 (21 of 36), at 24 191 vs 197 -- radar on early is as good or better (before the fixes 0.31 vs 0.67).
- **Ours:** Apexarmynet-lane-armynet-standard
- **Opponents:** Apex-v0.5.17-standard
- **Code:** Apex-v0.5.17-standard = `d32b7b84d8+5a6138c466fd` (36 games); Apexarmynet-lane-armynet-standard = `927ff16c17+512c8555dbd3` (36 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexarmynet:lane-armynet:standard --b Apex:v0.5.17:standard --per-side 2 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 1816 --map Comet Catcher Remake 1.8 --out matches/rel518d-R-cc-A1816`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 1816 | 0 | w | 30.0 | x0.97 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R-cc-A1816` |
| 1 | Comet Catcher Remake 1.8 | Cortex | 1816 | 0 | w | 30.0 | x1.77 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R-cc-C1816` |
| 2 | Carrot Mountains v2.0 | Armada | 1816 | 0 | l | 30.0 | x0.78 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R-cm-A1816` |
| 3 | Carrot Mountains v2.0 | Cortex | 1816 | 0 | w | 30.0 | x1.78 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R-cm-C1816` |
| 4 | Red Comet Remake 1.8 | Armada | 1816 | 0 | W | 21.56 | x4.49 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R-rc-A1816` |
| 5 | Red Comet Remake 1.8 | Cortex | 1816 | 0 | L | 23.05 | x0.49 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R-rc-C1816` |
| 6 | Comet Catcher Remake 1.8 | Armada | 1817 | 0 | w | 30.0 | x1.12 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R-cc-A1817` |
| 7 | Comet Catcher Remake 1.8 | Cortex | 1817 | 0 | w | 30.0 | x0.85 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R-cc-C1817` |
| 8 | Carrot Mountains v2.0 | Armada | 1817 | 0 | L | 29.37 | x0.30 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R-cm-A1817` |
| 9 | Carrot Mountains v2.0 | Cortex | 1817 | 0 | l | 30.0 | x0.78 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R-cm-C1817` |
| 10 | Red Comet Remake 1.8 | Armada | 1817 | 0 | w | 30.0 | x1.40 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R-rc-A1817` |
| 11 | Red Comet Remake 1.8 | Cortex | 1817 | 0 | l | 30.0 | x0.70 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R-rc-C1817` |
| 12 | Comet Catcher Remake 1.8 | Armada | 1818 | 0 | L | 29.44 | x0.42 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R-cc-A1818` |
| 13 | Comet Catcher Remake 1.8 | Cortex | 1818 | 0 | l | 30.0 | x0.54 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R-cc-C1818` |
| 14 | Carrot Mountains v2.0 | Armada | 1818 | 0 | l | 30.0 | x1.08 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R-cm-A1818` |
| 15 | Carrot Mountains v2.0 | Cortex | 1818 | 0 | w | 30.0 | x1.91 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R-cm-C1818` |
| 16 | Red Comet Remake 1.8 | Armada | 1818 | 0 | L | 24.07 | x0.41 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R-rc-A1818` |
| 17 | Red Comet Remake 1.8 | Cortex | 1818 | 0 | l | 30.0 | x1.15 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R-rc-C1818` |
| 18 | Comet Catcher Remake 1.8 | Armada | 1816 | 0 | w | 30.0 | x0.74 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R0-cc-A1816` |
| 19 | Comet Catcher Remake 1.8 | Cortex | 1816 | 0 | w | 30.0 | x1.30 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R0-cc-C1816` |
| 20 | Carrot Mountains v2.0 | Armada | 1816 | 0 | w | 30.0 | x1.54 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R0-cm-A1816` |
| 21 | Carrot Mountains v2.0 | Cortex | 1816 | 0 | l | 30.0 | x0.85 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R0-cm-C1816` |
| 22 | Red Comet Remake 1.8 | Armada | 1816 | 0 | L | 23.59 | x0.34 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R0-rc-A1816` |
| 23 | Red Comet Remake 1.8 | Cortex | 1816 | 0 | l | 30.0 | x0.59 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R0-rc-C1816` |
| 24 | Comet Catcher Remake 1.8 | Armada | 1817 | 0 | w | 30.0 | x1.19 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R0-cc-A1817` |
| 25 | Comet Catcher Remake 1.8 | Cortex | 1817 | 0 | L | 25.19 | x0.20 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R0-cc-C1817` |
| 26 | Carrot Mountains v2.0 | Armada | 1817 | 0 | W | 24.74 | x1.35 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R0-cm-A1817` |
| 27 | Carrot Mountains v2.0 | Cortex | 1817 | 0 | w | 30.0 | x1.57 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R0-cm-C1817` |
| 28 | Red Comet Remake 1.8 | Armada | 1817 | 0 | L | 23.27 | x0.10 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R0-rc-A1817` |
| 29 | Red Comet Remake 1.8 | Cortex | 1817 | 0 | w | 30.0 | x0.99 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R0-rc-C1817` |
| 30 | Comet Catcher Remake 1.8 | Armada | 1818 | 0 | l | 30.0 | x0.39 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R0-cc-A1818` |
| 31 | Comet Catcher Remake 1.8 | Cortex | 1818 | 0 | w | 30.0 | x1.26 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R0-cc-C1818` |
| 32 | Carrot Mountains v2.0 | Armada | 1818 | 0 | w | 30.0 | x1.06 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R0-cm-A1818` |
| 33 | Carrot Mountains v2.0 | Cortex | 1818 | 0 | w | 30.0 | x1.26 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R0-cm-C1818` |
| 34 | Red Comet Remake 1.8 | Armada | 1818 | 0 | L | 23.06 | x0.38 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R0-rc-A1818` |
| 35 | Red Comet Remake 1.8 | Cortex | 1818 | 0 | l | 30.0 | x0.98 | 927ff16c17+512c8555dbd3, d32b7b84d8+5a6138c466fd | `matches/rel518d-R0-rc-C1818` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.86 | 2.43 | - | ok |
| t2->4th moho (min) | 6.19 | 6.27 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.39 | 0.38 | 0.00 | ok, short of aim |
| adv plant frame x | 1.86 | 1.92 | 1.50 | ok, short of aim |
| near-done /10k built | 0.43 | 0.56 | 0.00 | ok, short of aim |
| t2 cons given early | 0.15 | 0.03 | 0.00 | ok, short of aim |
| supers before 4 moho | 1.33 | 1.47 | 0.00 | ok, short of aim |
| lone t2 con minutes | 0.81 | 0.60 | 0.00 | ok, short of aim |
| base lost /covered min | 78.33 | 33.46 | 0.00 | ok, short of aim |
| oldest plant order min | 2.88 | 2.88 | - | ok |
| no t2 by minute 20 | 0.06 | 0.03 | - | ok |
| frozen minutes | 0.72 | 0.36 | 0.00 | ok, short of aim |
| com minutes on their half | 1.71 | 2.03 | - | ok |
| com lost on their half | 0.10 | 0.07 | 0.00 | ok, short of aim |
| mex lost to ticks by 10 min | 0.28 | 0.22 | 0.00 | ok, short of aim |
| raider repeat kills /10min | 12.92 | 11.88 | 0.00 | worse, within noise (63% of resamples) |
| their mex killed /10min (neg) | -15.91 | -16.38 | - | ok |
| their army / ours, 8-12 min | 0.93 | 0.83 | - | ok |
| lost per killed | 1.42 | 1.56 | - | ok |
| reclaimed / killed (neg) | -0.15 | -0.18 | - | ok |
| bare-hands minutes | 0.86 | 0.42 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.53 | 0.53 | 0.00 | ok, short of aim |
| runs turned back | 0.00 | 0.00 | 0.00 | ok |
| gunships sent to lose | 0.00 | 0.00 | 0.00 | ok |
| stacked radar/jammers | 0.06 | 0.04 | 0.00 | ok, short of aim |
| army stuck /10min/1k army | 3.02 | 3.02 | 0.00 | ok, short of aim |
| ground given up share | 0.23 | 0.20 | 0.00 | ok, short of aim |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.33 | -1.44 | - | worse, within noise (56% of resamples) |
| army share (neg) | 0.37 | 0.35 | - | ok |
| -log income at 20 | -4.87 | -4.99 | - | ok |
| games won or ahead | 0.50 | 0.50 | - | ok |

Contract: **PASS** over 36 games (72 of our seats, 72 release seats); 17 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.17 (run `python tools/anomaly.py build`)
```
