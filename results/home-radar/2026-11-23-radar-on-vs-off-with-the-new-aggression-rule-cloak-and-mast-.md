<!-- meta {"date": "2026-11-23", "topic": "home-radar", "title": "Radar on vs off with the new aggression rule + cloak and mast fixes, 36 games (seeds 1813-1815)", "games": 36, "W": 3, "L": 5, "w": 20, "l": 8, "inc20": 0.87, "verdict": "Radar on now ahead: won/ahead 0.72 vs 0.56; income at 20 137 vs 128 (on higher 11 of 18), at 24 207 vs 188; first moho 16.0 vs 17.4 min; lost per killed 1.24 vs 1.62. Before these changes (same seeds) radar on trailed 0.33 vs 0.61. Replication on 1816-1818 next."} -->
# Radar on vs off with the new aggression rule + cloak and mast fixes, 36 games (seeds 1813-1815)

- **Date:** 2026-11-23
- **Topic:** home-radar
- **Purpose:** His goal: radar on early as good as off. Three changes in both arms: C++ comship cloak prices the moving cost while the commander walks; comescort does not pull him off a top-ranked home mast; apex_stance_unheld=1 (AGGRESSIVE only when the seen army outclasses our side's, or a group at home outweighs the guns plus our side's army, or raid pressure).
- **Result:** 36 games: won 3, lost 5, timeouts ahead 20, behind 8; income at 20 min x0.87 ours/theirs
- **Verdict:** Radar on now ahead: won/ahead 0.72 vs 0.56; income at 20 137 vs 128 (on higher 11 of 18), at 24 207 vs 188; first moho 16.0 vs 17.4 min; lost per killed 1.24 vs 1.62. Before these changes (same seeds) radar on trailed 0.33 vs 0.61. Replication on 1816-1818 next.
- **Ours:** Apexarmynet-lane-armynet-standard
- **Opponents:** Apex-v0.5.17-standard
- **Code:** Apex-v0.5.17-standard = `d32b7b84d8+5a6138c466fd` (36 games); Apexarmynet-lane-armynet-standard = `927ff16c17+4503bcf55d8f` (36 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexarmynet:lane-armynet:standard --b Apex:v0.5.17:standard --per-side 2 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 1813 --map Comet Catcher Remake 1.8 --out matches/stu-Stu1-cc-A1813 --modoption apex_home_radar=1 --modoption apex_stance_unheld=1`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 1813 | 0 | w | 30.0 | x0.72 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu1-cc-A1813` |
| 1 | Comet Catcher Remake 1.8 | Cortex | 1813 | 0 | w | 30.0 | x1.60 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu1-cc-C1813` |
| 2 | Comet Catcher Remake 1.8 | Armada | 1814 | 0 | l | 30.0 | x0.52 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu1-cc-A1814` |
| 3 | Comet Catcher Remake 1.8 | Cortex | 1814 | 0 | w | 30.0 | x2.14 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu1-cc-C1814` |
| 4 | Comet Catcher Remake 1.8 | Armada | 1815 | 0 | w | 30.0 | x1.41 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu1-cc-A1815` |
| 5 | Comet Catcher Remake 1.8 | Cortex | 1815 | 0 | w | 30.0 | x1.68 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu1-cc-C1815` |
| 6 | Carrot Mountains v2.0 | Armada | 1813 | 0 | w | 30.0 | x1.26 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu1-cm-A1813` |
| 7 | Carrot Mountains v2.0 | Cortex | 1813 | 0 | l | 30.0 | x0.58 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu1-cm-C1813` |
| 8 | Carrot Mountains v2.0 | Armada | 1814 | 0 | w | 30.0 | x1.30 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu1-cm-A1814` |
| 9 | Carrot Mountains v2.0 | Cortex | 1814 | 0 | w | 30.0 | x2.07 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu1-cm-C1814` |
| 10 | Carrot Mountains v2.0 | Armada | 1815 | 0 | w | 30.0 | x0.89 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu1-cm-A1815` |
| 11 | Carrot Mountains v2.0 | Cortex | 1815 | 0 | w | 30.0 | x1.56 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu1-cm-C1815` |
| 12 | Red Comet Remake 1.8 | Armada | 1813 | 0 | l | 30.0 | x0.53 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu1-rc-A1813` |
| 13 | Red Comet Remake 1.8 | Cortex | 1813 | 0 | w | 30.0 | x1.15 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu1-rc-C1813` |
| 14 | Red Comet Remake 1.8 | Armada | 1814 | 0 | l | 30.0 | x0.75 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu1-rc-A1814` |
| 15 | Red Comet Remake 1.8 | Cortex | 1814 | 0 | w | 30.0 | x0.69 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu1-rc-C1814` |
| 16 | Red Comet Remake 1.8 | Armada | 1815 | 0 | w | 30.0 | x0.90 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu1-rc-A1815` |
| 17 | Red Comet Remake 1.8 | Cortex | 1815 | 0 | l | 30.0 | x1.01 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu1-rc-C1815` |
| 18 | Comet Catcher Remake 1.8 | Armada | 1813 | 0 | l | 30.0 | x1.11 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu0-cc-A1813` |
| 19 | Comet Catcher Remake 1.8 | Cortex | 1813 | 0 | w | 30.0 | x1.02 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu0-cc-C1813` |
| 20 | Comet Catcher Remake 1.8 | Armada | 1814 | 0 | l | 30.0 | x0.62 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu0-cc-A1814` |
| 21 | Comet Catcher Remake 1.8 | Cortex | 1814 | 0 | l | 30.0 | x1.18 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu0-cc-C1814` |
| 22 | Comet Catcher Remake 1.8 | Armada | 1815 | 0 | W | 27.36 | x2.07 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu0-cc-A1815` |
| 23 | Comet Catcher Remake 1.8 | Cortex | 1815 | 0 | L | 29.76 | x0.75 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu0-cc-C1815` |
| 24 | Carrot Mountains v2.0 | Armada | 1813 | 0 | L | 28.49 | x0.25 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu0-cm-A1813` |
| 25 | Carrot Mountains v2.0 | Cortex | 1813 | 0 | w | 30.0 | x1.15 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu0-cm-C1813` |
| 26 | Carrot Mountains v2.0 | Armada | 1814 | 0 | w | 30.0 | x1.07 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu0-cm-A1814` |
| 27 | Carrot Mountains v2.0 | Cortex | 1814 | 0 | W | 28.75 | x2.52 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu0-cm-C1814` |
| 28 | Carrot Mountains v2.0 | Armada | 1815 | 0 | w | 30.0 | x1.25 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu0-cm-A1815` |
| 29 | Carrot Mountains v2.0 | Cortex | 1815 | 0 | L | 21.84 | x0.16 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu0-cm-C1815` |
| 30 | Red Comet Remake 1.8 | Armada | 1813 | 0 | L | 24.5 | x0.23 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu0-rc-A1813` |
| 31 | Red Comet Remake 1.8 | Cortex | 1813 | 0 | w | 30.0 | x0.79 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu0-rc-C1813` |
| 32 | Red Comet Remake 1.8 | Armada | 1814 | 0 | w | 30.0 | x0.44 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu0-rc-A1814` |
| 33 | Red Comet Remake 1.8 | Cortex | 1814 | 0 | w | 30.0 | x1.12 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu0-rc-C1814` |
| 34 | Red Comet Remake 1.8 | Armada | 1815 | 0 | W | 19.34 | - | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu0-rc-A1815` |
| 35 | Red Comet Remake 1.8 | Cortex | 1815 | 0 | L | 23.79 | x0.15 | 927ff16c17+4503bcf55d8f, d32b7b84d8+5a6138c466fd | `matches/stu-Stu0-rc-C1815` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.93 | 2.68 | - | ok |
| t2->4th moho (min) | 6.20 | 6.22 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.40 | 0.39 | 0.00 | ok, short of aim |
| adv plant frame x | 2.29 | 2.12 | 1.50 | ok, short of aim |
| near-done /10k built | 0.47 | 0.47 | 0.00 | ok, short of aim |
| t2 cons given early | 0.01 | 0.00 | 0.00 | ok, short of aim |
| supers before 4 moho | 1.32 | 1.61 | 0.00 | ok, short of aim |
| lone t2 con minutes | 0.56 | 0.87 | 0.00 | ok, short of aim |
| base lost /covered min | 75.00 | 89.43 | 0.00 | ok, short of aim |
| oldest plant order min | 2.77 | 2.99 | - | ok |
| no t2 by minute 20 | 0.01 | 0.03 | - | ok |
| frozen minutes | 0.33 | 0.44 | 0.00 | ok, short of aim |
| com minutes on their half | 1.73 | 1.72 | - | ok |
| com lost on their half | 0.04 | 0.03 | 0.00 | ok, short of aim |
| mex lost to ticks by 10 min | 0.24 | 0.25 | 0.00 | ok, short of aim |
| raider repeat kills /10min | 11.16 | 13.03 | 0.00 | ok, short of aim |
| their mex killed /10min (neg) | -15.94 | -16.57 | - | ok |
| their army / ours, 8-12 min | 1.11 | 0.86 | - | worse, within noise (47% of resamples) |
| lost per killed | 1.36 | 1.69 | - | ok |
| reclaimed / killed (neg) | -0.16 | -0.16 | - | ok |
| bare-hands minutes | 0.36 | 0.58 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.52 | 0.49 | 0.00 | ok, short of aim |
| runs turned back | 0.03 | 0.00 | 0.00 | ok, short of aim |
| gunships sent to lose | 0.00 | 0.00 | 0.00 | ok |
| stacked radar/jammers | 0.09 | 0.06 | 0.00 | ok, short of aim |
| army stuck /10min/1k army | 2.92 | 3.45 | 0.00 | ok, short of aim |
| ground given up share | 0.19 | 0.19 | 0.00 | ok, short of aim |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.38 | -1.30 | - | ok |
| army share (neg) | 0.36 | 0.35 | - | ok |
| -log income at 20 | -4.85 | -4.88 | - | ok |
| games won or ahead | 0.64 | 0.50 | - | ok |

Contract: **PASS** over 36 games (72 of our seats, 72 release seats); 18 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.17 (run `python tools/anomaly.py build`)
```
