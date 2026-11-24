<!-- meta {"date": "2026-11-23", "topic": "home-radar", "title": "Home radar on vs off with the air answer off (comescort off), 36 games", "games": 36, "W": 5, "L": 6, "w": 8, "l": 17, "inc20": 0.88, "verdict": "Refuted: radar on still loses (won/ahead 0.28 vs 0.39; income at 20 102 vs 129, on higher 4 of 18) with less air army than off. The fighter answer is not the coupling."} -->
# Home radar on vs off with the air answer off (comescort off), 36 games

- **Date:** 2026-11-23
- **Topic:** home-radar
- **Purpose:** Test whether the radar's cost runs through the fighter answer: radar shows more enemy air, fighters owed, no T2 cons. apex_air_answer=0 reaches v0.5.17 too, so win rates are not comparable with other batches.
- **Result:** 36 games: won 5, lost 6, timeouts ahead 8, behind 17; income at 20 min x0.88 ours/theirs
- **Verdict:** Refuted: radar on still loses (won/ahead 0.28 vs 0.39; income at 20 102 vs 129, on higher 4 of 18) with less air army than off. The fighter answer is not the coupling.
- **Ours:** Apexarmynet-lane-armynet-standard
- **Opponents:** Apex-v0.5.17-standard
- **Code:** Apex-v0.5.17-standard = `d32b7b84d8+5a6138c466fd` (36 games); Apexarmynet-lane-armynet-standard = `927ff16c17+f9503eb1ac00` (36 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexarmynet:lane-armynet:standard --b Apex:v0.5.17:standard --per-side 2 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 1813 --map Comet Catcher Remake 1.8 --out matches/aans-Aan1-cc-A1813 --modoption apex_home_radar=1 --modoption apex_com_escort=0 --modoption apex_air_answer=0`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 1813 | 0 | W | 26.28 | x2.74 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan1-cc-A1813` |
| 1 | Comet Catcher Remake 1.8 | Cortex | 1813 | 0 | l | 30.0 | x0.96 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan1-cc-C1813` |
| 2 | Comet Catcher Remake 1.8 | Armada | 1814 | 0 | L | 28.19 | x0.31 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan1-cc-A1814` |
| 3 | Comet Catcher Remake 1.8 | Cortex | 1814 | 0 | L | 22.41 | x0.10 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan1-cc-C1814` |
| 4 | Comet Catcher Remake 1.8 | Armada | 1815 | 0 | l | 30.0 | x1.30 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan1-cc-A1815` |
| 5 | Comet Catcher Remake 1.8 | Cortex | 1815 | 0 | l | 30.0 | x0.68 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan1-cc-C1815` |
| 6 | Carrot Mountains v2.0 | Armada | 1813 | 0 | w | 30.0 | x0.72 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan1-cm-A1813` |
| 7 | Carrot Mountains v2.0 | Cortex | 1813 | 0 | L | 29.5 | x0.26 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan1-cm-C1813` |
| 8 | Carrot Mountains v2.0 | Armada | 1814 | 0 | l | 30.0 | x0.55 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan1-cm-A1814` |
| 9 | Carrot Mountains v2.0 | Cortex | 1814 | 0 | l | 30.0 | x0.64 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan1-cm-C1814` |
| 10 | Carrot Mountains v2.0 | Armada | 1815 | 0 | L | 28.42 | x0.27 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan1-cm-A1815` |
| 11 | Carrot Mountains v2.0 | Cortex | 1815 | 0 | w | 30.0 | x1.58 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan1-cm-C1815` |
| 12 | Red Comet Remake 1.8 | Armada | 1813 | 0 | l | 30.0 | x0.85 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan1-rc-A1813` |
| 13 | Red Comet Remake 1.8 | Cortex | 1813 | 0 | l | 30.0 | x0.73 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan1-rc-C1813` |
| 14 | Red Comet Remake 1.8 | Armada | 1814 | 0 | l | 30.0 | x0.26 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan1-rc-A1814` |
| 15 | Red Comet Remake 1.8 | Cortex | 1814 | 0 | w | 30.0 | x1.17 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan1-rc-C1814` |
| 16 | Red Comet Remake 1.8 | Armada | 1815 | 0 | w | 30.0 | x1.51 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan1-rc-A1815` |
| 17 | Red Comet Remake 1.8 | Cortex | 1815 | 0 | l | 30.0 | x0.80 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan1-rc-C1815` |
| 18 | Comet Catcher Remake 1.8 | Armada | 1813 | 0 | l | 30.0 | x0.82 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan0-cc-A1813` |
| 19 | Comet Catcher Remake 1.8 | Cortex | 1813 | 0 | l | 30.0 | x0.73 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan0-cc-C1813` |
| 20 | Comet Catcher Remake 1.8 | Armada | 1814 | 0 | W | 22.27 | x12.85 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan0-cc-A1814` |
| 21 | Comet Catcher Remake 1.8 | Cortex | 1814 | 0 | l | 30.0 | x0.52 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan0-cc-C1814` |
| 22 | Comet Catcher Remake 1.8 | Armada | 1815 | 0 | l | 30.0 | x0.49 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan0-cc-A1815` |
| 23 | Comet Catcher Remake 1.8 | Cortex | 1815 | 0 | l | 30.0 | x0.89 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan0-cc-C1815` |
| 24 | Carrot Mountains v2.0 | Armada | 1813 | 0 | w | 30.0 | x1.11 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan0-cm-A1813` |
| 25 | Carrot Mountains v2.0 | Cortex | 1813 | 0 | l | 30.0 | x0.56 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan0-cm-C1813` |
| 26 | Carrot Mountains v2.0 | Armada | 1814 | 0 | L | 27.65 | x0.55 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan0-cm-A1814` |
| 27 | Carrot Mountains v2.0 | Cortex | 1814 | 0 | w | 30.0 | x2.20 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan0-cm-C1814` |
| 28 | Carrot Mountains v2.0 | Armada | 1815 | 0 | l | 30.0 | x0.64 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan0-cm-A1815` |
| 29 | Carrot Mountains v2.0 | Cortex | 1815 | 0 | w | 30.0 | x1.56 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan0-cm-C1815` |
| 30 | Red Comet Remake 1.8 | Armada | 1813 | 0 | W | 27.12 | x1.54 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan0-rc-A1813` |
| 31 | Red Comet Remake 1.8 | Cortex | 1813 | 0 | W | 24.91 | x5.93 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan0-rc-C1813` |
| 32 | Red Comet Remake 1.8 | Armada | 1814 | 0 | L | 26.09 | x0.52 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan0-rc-A1814` |
| 33 | Red Comet Remake 1.8 | Cortex | 1814 | 0 | w | 30.0 | x0.74 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan0-rc-C1814` |
| 34 | Red Comet Remake 1.8 | Armada | 1815 | 0 | W | 23.47 | x3.16 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan0-rc-A1815` |
| 35 | Red Comet Remake 1.8 | Cortex | 1815 | 0 | l | 30.0 | x1.41 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/aans-Aan0-rc-C1815` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.71 | 2.64 | - | ok |
| t2->4th moho (min) | 6.45 | 6.05 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.43 | 0.36 | 0.00 | ok, short of aim |
| adv plant frame x | 2.09 | 2.11 | 1.50 | ok, short of aim |
| near-done /10k built | 0.44 | 0.60 | 0.00 | ok, short of aim |
| t2 cons given early | 0.01 | 0.03 | 0.00 | ok, short of aim |
| supers before 4 moho | 1.19 | 1.35 | 0.00 | ok, short of aim |
| lone t2 con minutes | 0.74 | 0.58 | 0.00 | ok, short of aim |
| base lost /covered min | 192.94 | 50.00 | 0.00 | ok, short of aim |
| oldest plant order min | 2.80 | 2.99 | - | ok |
| no t2 by minute 20 | 0.07 | 0.04 | - | ok |
| frozen minutes | 0.92 | 0.42 | 0.00 | ok, short of aim |
| com minutes on their half | 1.88 | 1.87 | - | ok |
| com lost on their half | 0.08 | 0.10 | 0.00 | ok, short of aim |
| mex lost to ticks by 10 min | 0.32 | 0.15 | 0.00 | ok, short of aim |
| raider repeat kills /10min | 11.90 | 11.15 | 0.00 | worse, within noise (54% of resamples) |
| their mex killed /10min (neg) | -16.01 | -17.53 | - | ok |
| their army / ours, 8-12 min | 0.98 | 0.94 | - | ok |
| lost per killed | 1.63 | 1.52 | - | ok |
| reclaimed / killed (neg) | -0.16 | -0.15 | - | ok |
| bare-hands minutes | 0.92 | 0.53 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.51 | 0.43 | 0.00 | ok, short of aim |
| runs turned back | 0.01 | 0.01 | 0.00 | ok, short of aim |
| gunships sent to lose | 0.00 | 0.00 | 0.00 | ok |
| stacked radar/jammers | 0.01 | 0.10 | 0.00 | ok, short of aim |
| army stuck /10min/1k army | 3.05 | 2.95 | 0.00 | ok, short of aim |
| ground given up share | 0.23 | 0.19 | 0.00 | ok, short of aim |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.31 | -1.38 | - | ok |
| army share (neg) | 0.36 | 0.35 | - | ok |
| -log income at 20 | -4.73 | -4.94 | - | worse, within noise (64% of resamples) |
| games won or ahead | 0.33 | 0.50 | - | FAIL (does not beat the release) |

Contract: **FAIL (1)** over 36 games (72 of our seats, 72 release seats); 18 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.17 (run `python tools/anomaly.py build`)
```
