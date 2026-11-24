<!-- meta {"date": "2026-11-23", "topic": "home-radar", "title": "Commander lab-assist (comescort) off, radar on vs off, 36 games", "games": 36, "W": 5, "L": 4, "w": 13, "l": 14, "inc20": 1.03, "verdict": "Comescort explains the opening delay only: with it off the 40 s lag from build 8 is gone. Radar still costs income later: at 20 129 vs 154 (on higher in 6 of 16), at 24 182 vs 246 (3 of 15); won or ahead 0.44 vs 0.67. Comescort off vs on, same seeds: radar off won/ahead 0.67 vs 0.78, income at 24 245 vs 218 (higher 7 of 15) -- no clear effect. tech-diag etaSave 0.08 vs 0.29 (min 6-16) is the next lead."} -->
# Commander lab-assist (comescort) off, radar on vs off, 36 games

- **Date:** 2026-11-23
- **Topic:** home-radar
- **Purpose:** Does the home radar cost us only by unlocking the comescort hoist? Same 18 seeds as the radar batch, apex_com_escort=0.
- **Result:** 36 games: won 5, lost 4, timeouts ahead 13, behind 14; income at 20 min x1.03 ours/theirs
- **Verdict:** Comescort explains the opening delay only: with it off the 40 s lag from build 8 is gone. Radar still costs income later: at 20 129 vs 154 (on higher in 6 of 16), at 24 182 vs 246 (3 of 15); won or ahead 0.44 vs 0.67. Comescort off vs on, same seeds: radar off won/ahead 0.67 vs 0.78, income at 24 245 vs 218 (higher 7 of 15) -- no clear effect. tech-diag etaSave 0.08 vs 0.29 (min 6-16) is the next lead.
- **Ours:** Apexarmynet-lane-armynet-standard
- **Opponents:** Apex-v0.5.17-standard
- **Code:** Apex-v0.5.17-standard = `d32b7b84d8+5a6138c466fd` (36 games); Apexarmynet-lane-armynet-standard = `927ff16c17+f9503eb1ac00` (36 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexarmynet:lane-armynet:standard --b Apex:v0.5.17:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 1813 --modoption apex_home_radar=1 --modoption apex_com_escort=0 --out matches/esc-Esc1b-cc-A1813`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 1813 | 0 | l | 30.0 | x0.77 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc1b-cc-A1813` |
| 1 | Comet Catcher Remake 1.8 | Cortex | 1813 | 0 | w | 30.0 | x1.65 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc1b-cc-C1813` |
| 2 | Comet Catcher Remake 1.8 | Armada | 1814 | 0 | w | 30.0 | x1.23 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc1-cc-A1814` |
| 3 | Comet Catcher Remake 1.8 | Cortex | 1814 | 0 | l | 30.0 | x0.99 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc1-cc-C1814` |
| 4 | Comet Catcher Remake 1.8 | Armada | 1815 | 0 | w | 30.0 | x1.56 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc1-cc-A1815` |
| 5 | Comet Catcher Remake 1.8 | Cortex | 1815 | 0 | l | 30.0 | x0.84 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc1-cc-C1815` |
| 6 | Carrot Mountains v2.0 | Armada | 1813 | 0 | l | 30.0 | x0.76 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc1-cm-A1813` |
| 7 | Carrot Mountains v2.0 | Cortex | 1813 | 0 | l | 30.0 | x1.09 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc1-cm-C1813` |
| 8 | Carrot Mountains v2.0 | Armada | 1814 | 0 | l | 30.0 | x0.49 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc1-cm-A1814` |
| 9 | Carrot Mountains v2.0 | Cortex | 1814 | 0 | w | 30.0 | x1.88 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc1-cm-C1814` |
| 10 | Carrot Mountains v2.0 | Armada | 1815 | 0 | L | 25.85 | x0.09 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc1-cm-A1815` |
| 11 | Carrot Mountains v2.0 | Cortex | 1815 | 0 | w | 30.0 | x0.90 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc1-cm-C1815` |
| 12 | Red Comet Remake 1.8 | Armada | 1813 | 0 | l | 30.0 | x0.81 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc1-rc-A1813` |
| 13 | Red Comet Remake 1.8 | Cortex | 1813 | 0 | L | 22.54 | x0.28 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc1-rc-C1813` |
| 14 | Red Comet Remake 1.8 | Armada | 1814 | 0 | w | 30.0 | x1.78 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc1-rc-A1814` |
| 15 | Red Comet Remake 1.8 | Cortex | 1814 | 0 | L | 28.76 | x0.44 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc1-rc-C1814` |
| 16 | Red Comet Remake 1.8 | Armada | 1815 | 0 | W | 17.72 | - | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc1-rc-A1815` |
| 17 | Red Comet Remake 1.8 | Cortex | 1815 | 0 | w | 30.0 | x0.80 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc1-rc-C1815` |
| 18 | Comet Catcher Remake 1.8 | Armada | 1813 | 0 | W | 29.76 | x1.46 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0b-cc-A1813` |
| 19 | Comet Catcher Remake 1.8 | Cortex | 1813 | 0 | W | 25.28 | x3.09 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0b-cc-C1813` |
| 20 | Comet Catcher Remake 1.8 | Armada | 1814 | 0 | w | 30.0 | x1.20 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cc-A1814` |
| 21 | Comet Catcher Remake 1.8 | Cortex | 1814 | 0 | l | 30.0 | x1.10 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cc-C1814` |
| 22 | Comet Catcher Remake 1.8 | Armada | 1815 | 0 | l | 30.0 | x0.66 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cc-A1815` |
| 23 | Comet Catcher Remake 1.8 | Cortex | 1815 | 0 | l | 30.0 | x0.60 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cc-C1815` |
| 24 | Carrot Mountains v2.0 | Armada | 1813 | 0 | l | 30.0 | x0.74 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cm-A1813` |
| 25 | Carrot Mountains v2.0 | Cortex | 1813 | 0 | w | 30.0 | x1.36 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cm-C1813` |
| 26 | Carrot Mountains v2.0 | Armada | 1814 | 0 | w | 30.0 | x1.36 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cm-A1814` |
| 27 | Carrot Mountains v2.0 | Cortex | 1814 | 0 | l | 30.0 | x0.83 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cm-C1814` |
| 28 | Carrot Mountains v2.0 | Armada | 1815 | 0 | w | 30.0 | x1.34 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cm-A1815` |
| 29 | Carrot Mountains v2.0 | Cortex | 1815 | 0 | l | 30.0 | x1.51 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cm-C1815` |
| 30 | Red Comet Remake 1.8 | Armada | 1813 | 0 | L | 14.82 | - | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-rc-A1813` |
| 31 | Red Comet Remake 1.8 | Cortex | 1813 | 0 | W | 29.5 | x1.00 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-rc-C1813` |
| 32 | Red Comet Remake 1.8 | Armada | 1814 | 0 | W | 21.0 | x16.33 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-rc-A1814` |
| 33 | Red Comet Remake 1.8 | Cortex | 1814 | 0 | l | 30.0 | x0.67 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-rc-C1814` |
| 34 | Red Comet Remake 1.8 | Armada | 1815 | 0 | w | 30.0 | x1.56 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-rc-A1815` |
| 35 | Red Comet Remake 1.8 | Cortex | 1815 | 0 | w | 30.0 | x1.86 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-rc-C1815` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.60 | 2.67 | - | ok |
| t2->4th moho (min) | 6.20 | 6.02 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.34 | 0.41 | 0.00 | ok, short of aim |
| adv plant frame x | 1.99 | 1.93 | 1.50 | ok, short of aim |
| near-done /10k built | 0.50 | 0.49 | 0.00 | ok, short of aim |
| t2 cons given early | 0.00 | 0.00 | 0.00 | ok |
| supers before 4 moho | 1.68 | 1.47 | 0.00 | ok, short of aim |
| lone t2 con minutes | 0.46 | 0.82 | 0.00 | ok, short of aim |
| base lost /covered min | 131.53 | 160.67 | 0.00 | ok, short of aim |
| oldest plant order min | 2.90 | 2.96 | - | ok |
| no t2 by minute 20 | 0.01 | 0.03 | - | ok |
| frozen minutes | 0.36 | 0.50 | 0.00 | ok, short of aim |
| com minutes on their half | 1.28 | 1.71 | - | ok |
| com lost on their half | 0.06 | 0.06 | 0.00 | ok, short of aim |
| mex lost to ticks by 10 min | 0.14 | 0.17 | 0.00 | ok, short of aim |
| raider repeat kills /10min | 11.64 | 11.51 | 0.00 | ok, short of aim |
| their mex killed /10min (neg) | -15.85 | -17.18 | - | ok |
| their army / ours, 8-12 min | 1.25 | 0.93 | - | worse, within noise (52% of resamples) |
| lost per killed | 1.55 | 1.55 | - | ok |
| reclaimed / killed (neg) | -0.14 | -0.16 | - | ok |
| bare-hands minutes | 0.64 | 0.72 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.50 | 0.46 | 0.00 | ok, short of aim |
| runs turned back | 0.01 | 0.00 | 0.00 | ok, short of aim |
| gunships sent to lose | 0.00 | 0.00 | 0.00 | ok |
| stacked radar/jammers | 0.07 | 0.01 | 0.00 | ok, short of aim |
| army stuck /10min/1k army | 2.65 | 2.90 | 0.00 | ok, short of aim |
| ground given up share | 0.22 | 0.19 | 0.00 | ok, short of aim |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.38 | -1.27 | - | ok |
| army share (neg) | 0.34 | 0.36 | - | ok |
| -log income at 20 | -4.96 | -4.80 | - | ok |
| games won or ahead | 0.56 | 0.50 | - | ok |

Contract: **PASS** over 36 games (72 of our seats, 72 release seats); 17 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.17 (run `python tools/anomaly.py build`)
```
