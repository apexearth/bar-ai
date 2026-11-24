<!-- meta {"date": "2026-11-23", "topic": "home-radar", "title": "Why the con floor yields, radar on vs off, 14-min games (two runs, 72 games)", "games": 68, "W": 0, "L": 1, "w": 29, "l": 38, "inc20": 1.0, "verdict": "No single rule: the foe-outguns yield is larger with radar on (by 12 min 2.1 vs 1.4, 3.6 vs 2.0), but its out-earn gate flips between runs (46/40%, 41/50%); budget hold blocks most asks in both arms; constructors level to 10 in the second run, gap from 12."} -->
# Why the con floor yields, radar on vs off, 14-min games (two runs, 72 games)

- **Date:** 2026-11-23
- **Topic:** home-radar
- **Purpose:** Logging-only counters in spothands: which armyBehind term yields the con floor (yFoe/yFtr/yShare), outEarn, their extractors counted, and which gate stops a floor with need (cap/upkeep/budget hold).
- **Result:** 68 games: won 0, lost 1, timeouts ahead 29, behind 38; income at 20 min x1.00 ours/theirs
- **Verdict:** No single rule: the foe-outguns yield is larger with radar on (by 12 min 2.1 vs 1.4, 3.6 vs 2.0), but its out-earn gate flips between runs (46/40%, 41/50%); budget hold blocks most asks in both arms; constructors level to 10 in the second run, gap from 12.
- **Ours:** Apexarmynet-lane-armynet-standard
- **Opponents:** Apex-v0.5.17-standard
- **Code:** Apex-v0.5.17-standard = `d32b7b84d8+5a6138c466fd` (68 games); Apexarmynet-lane-armynet-standard = `927ff16c17+0bda731b6623` (32 games); Apexarmynet-lane-armynet-standard = `927ff16c17+3d559b2bbdf4` (36 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 14 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexarmynet:lane-armynet:standard --b Apex:v0.5.17:standard --per-side 2 --minutes 14 --speed 20 --handicap 50 --sides Armada,Armada --seed 1813 --map Comet Catcher Remake 1.8 --out matches/cfy-Cfy1-cc-A1813 --modoption apex_home_radar=1 --modoption apex_com_escort=0`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 1813 | 0 | w | 14.0 | x1.12 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy1-cc-A1813` |
| 1 | Comet Catcher Remake 1.8 | Cortex | 1813 | 0 | w | 14.0 | x1.81 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy1-cc-C1813` |
| 2 | Comet Catcher Remake 1.8 | Armada | 1814 | 0 | l | 14.0 | x0.86 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy1-cc-A1814` |
| 3 | Comet Catcher Remake 1.8 | Cortex | 1814 | 0 | l | 14.0 | x0.93 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy1-cc-C1814` |
| 4 | Comet Catcher Remake 1.8 | Armada | 1815 | 0 | w | 14.0 | x1.25 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy1-cc-A1815` |
| 5 | Comet Catcher Remake 1.8 | Cortex | 1815 | 0 | l | 14.0 | x0.91 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy1-cc-C1815` |
| 6 | Carrot Mountains v2.0 | Armada | 1813 | 0 | l | 14.0 | x0.57 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy1-cm-A1813` |
| 7 | Carrot Mountains v2.0 | Cortex | 1813 | 0 | l | 14.0 | x0.82 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy1-cm-C1813` |
| 8 | Carrot Mountains v2.0 | Armada | 1814 | 0 | w | 14.0 | x1.09 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy1-cm-A1814` |
| 9 | Carrot Mountains v2.0 | Cortex | 1814 | 0 | l | 14.0 | x0.94 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy1-cm-C1814` |
| 10 | Carrot Mountains v2.0 | Armada | 1815 | 0 | l | 14.0 | x0.67 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy1-cm-A1815` |
| 11 | Carrot Mountains v2.0 | Cortex | 1815 | 0 | l | 14.0 | x0.52 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy1-cm-C1815` |
| 12 | Red Comet Remake 1.8 | Armada | 1813 | 0 | w | 14.0 | x8.25 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy1-rc-A1813` |
| 13 | Red Comet Remake 1.8 | Cortex | 1813 | 0 | l | 14.0 | x0.60 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy1-rc-C1813` |
| 14 | Red Comet Remake 1.8 | Armada | 1814 | 0 | w | 14.0 | x1.20 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy1-rc-A1814` |
| 15 | Red Comet Remake 1.8 | Cortex | 1814 | 0 | l | 14.0 | x0.30 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy1-rc-C1814` |
| 16 | Red Comet Remake 1.8 | Armada | 1815 | 0 | w | 14.0 | x1.13 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy1-rc-A1815` |
| 17 | Red Comet Remake 1.8 | Cortex | 1815 | 0 | w | 14.0 | x2.76 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy1-rc-C1815` |
| 18 | Comet Catcher Remake 1.8 | Armada | 1813 | 0 | w | 14.0 | x1.25 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz1-cc-A1813` |
| 19 | Comet Catcher Remake 1.8 | Cortex | 1813 | 0 | l | 14.0 | x0.59 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz1-cc-C1813` |
| 20 | Comet Catcher Remake 1.8 | Armada | 1814 | 0 | w | 14.0 | x1.27 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz1-cc-A1814` |
| 21 | Comet Catcher Remake 1.8 | Cortex | 1814 | 0 | w | 14.0 | x1.05 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz1-cc-C1814` |
| 22 | Comet Catcher Remake 1.8 | Armada | 1815 | 0 | l | 14.0 | x0.90 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz1-cc-A1815` |
| 23 | Comet Catcher Remake 1.8 | Cortex | 1815 | 0 | l | 14.0 | x0.79 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz1-cc-C1815` |
| 24 | Carrot Mountains v2.0 | Armada | 1813 | 0 | l | 14.0 | x0.95 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz1-cm-A1813` |
| 25 | Carrot Mountains v2.0 | Cortex | 1813 | 0 | l | 14.0 | x0.54 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz1-cm-C1813` |
| 26 | Carrot Mountains v2.0 | Armada | 1814 | 0 | l | 14.0 | x0.80 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz1-cm-A1814` |
| 27 | Carrot Mountains v2.0 | Cortex | 1814 | 0 | w | 14.0 | x1.07 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz1-cm-C1814` |
| 28 | Carrot Mountains v2.0 | Armada | 1815 | 0 | l | 14.0 | x0.66 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz1-cm-A1815` |
| 29 | Carrot Mountains v2.0 | Cortex | 1815 | 0 | l | 14.0 | x0.94 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz1-cm-C1815` |
| 30 | Red Comet Remake 1.8 | Armada | 1813 | 0 | L | 11.89 | - | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz1-rc-A1813` |
| 31 | Red Comet Remake 1.8 | Cortex | 1813 | 0 | w | 14.0 | x1.41 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz1-rc-C1813` |
| 32 | Red Comet Remake 1.8 | Armada | 1814 | 0 | l | 14.0 | x0.90 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz1-rc-A1814` |
| 33 | Red Comet Remake 1.8 | Cortex | 1814 | 0 | w | 14.0 | x1.34 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz1-rc-C1814` |
| 34 | Comet Catcher Remake 1.8 | Armada | 1813 | 0 | w | 14.0 | x1.68 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy0-cc-A1813` |
| 35 | Comet Catcher Remake 1.8 | Cortex | 1813 | 0 | l | 14.0 | x0.68 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy0-cc-C1813` |
| 36 | Comet Catcher Remake 1.8 | Armada | 1814 | 0 | l | 14.0 | x0.68 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy0-cc-A1814` |
| 37 | Comet Catcher Remake 1.8 | Cortex | 1814 | 0 | l | 14.0 | x0.78 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy0-cc-C1814` |
| 38 | Comet Catcher Remake 1.8 | Armada | 1815 | 0 | l | 14.0 | x0.40 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy0-cc-A1815` |
| 39 | Comet Catcher Remake 1.8 | Cortex | 1815 | 0 | w | 14.0 | x1.21 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy0-cc-C1815` |
| 40 | Carrot Mountains v2.0 | Armada | 1813 | 0 | l | 14.0 | x0.92 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy0-cm-A1813` |
| 41 | Carrot Mountains v2.0 | Cortex | 1813 | 0 | l | 14.0 | x0.76 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy0-cm-C1813` |
| 42 | Carrot Mountains v2.0 | Armada | 1814 | 0 | l | 14.0 | x0.64 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy0-cm-A1814` |
| 43 | Carrot Mountains v2.0 | Cortex | 1814 | 0 | l | 14.0 | x1.00 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy0-cm-C1814` |
| 44 | Carrot Mountains v2.0 | Armada | 1815 | 0 | w | 14.0 | x1.09 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy0-cm-A1815` |
| 45 | Carrot Mountains v2.0 | Cortex | 1815 | 0 | w | 14.0 | x1.92 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy0-cm-C1815` |
| 46 | Red Comet Remake 1.8 | Armada | 1813 | 0 | l | 14.0 | x0.45 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy0-rc-A1813` |
| 47 | Red Comet Remake 1.8 | Cortex | 1813 | 0 | w | 14.0 | x1.29 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy0-rc-C1813` |
| 48 | Red Comet Remake 1.8 | Armada | 1814 | 0 | w | 14.0 | x1.20 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy0-rc-A1814` |
| 49 | Red Comet Remake 1.8 | Cortex | 1814 | 0 | l | 14.0 | x0.94 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy0-rc-C1814` |
| 50 | Red Comet Remake 1.8 | Armada | 1815 | 0 | l | 14.0 | x0.88 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy0-rc-A1815` |
| 51 | Red Comet Remake 1.8 | Cortex | 1815 | 0 | l | 14.0 | x0.82 | 927ff16c17+3d559b2bbdf4, d32b7b84d8+5a6138c466fd | `matches/cfy-Cfy0-rc-C1815` |
| 52 | Comet Catcher Remake 1.8 | Armada | 1813 | 0 | l | 14.0 | x0.96 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz0-cc-A1813` |
| 53 | Comet Catcher Remake 1.8 | Cortex | 1813 | 0 | w | 14.0 | x2.28 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz0-cc-C1813` |
| 54 | Comet Catcher Remake 1.8 | Armada | 1814 | 0 | w | 14.0 | x3.18 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz0-cc-A1814` |
| 55 | Comet Catcher Remake 1.8 | Cortex | 1814 | 0 | w | 14.0 | x1.52 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz0-cc-C1814` |
| 56 | Comet Catcher Remake 1.8 | Armada | 1815 | 0 | w | 14.0 | x1.84 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz0-cc-A1815` |
| 57 | Comet Catcher Remake 1.8 | Cortex | 1815 | 0 | l | 14.0 | x0.99 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz0-cc-C1815` |
| 58 | Carrot Mountains v2.0 | Armada | 1813 | 0 | w | 14.0 | x1.26 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz0-cm-A1813` |
| 59 | Carrot Mountains v2.0 | Cortex | 1813 | 0 | l | 14.0 | x0.62 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz0-cm-C1813` |
| 60 | Carrot Mountains v2.0 | Armada | 1814 | 0 | l | 14.0 | x0.76 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz0-cm-A1814` |
| 61 | Carrot Mountains v2.0 | Cortex | 1814 | 0 | l | 14.0 | x0.80 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz0-cm-C1814` |
| 62 | Carrot Mountains v2.0 | Armada | 1815 | 0 | w | 14.0 | x1.15 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz0-cm-A1815` |
| 63 | Carrot Mountains v2.0 | Cortex | 1815 | 0 | w | 14.0 | x1.13 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz0-cm-C1815` |
| 64 | Red Comet Remake 1.8 | Armada | 1813 | 0 | l | 14.0 | x1.00 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz0-rc-A1813` |
| 65 | Red Comet Remake 1.8 | Cortex | 1813 | 0 | w | 14.0 | x1.11 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz0-rc-C1813` |
| 66 | Red Comet Remake 1.8 | Armada | 1814 | 0 | l | 14.0 | x0.62 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz0-rc-A1814` |
| 67 | Red Comet Remake 1.8 | Cortex | 1814 | 0 | w | 14.0 | x1.75 | 927ff16c17+0bda731b6623, d32b7b84d8+5a6138c466fd | `matches/cfz-Cfz0-rc-C1814` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 1.65 | 1.86 | - | ok |
| t2->4th moho (min) | 1.66 | 1.12 | 3.00 | ok |
| lab-job leaves/job | 0.25 | 0.25 | 0.00 | ok, short of aim |
| adv plant frame x | 1.90 | 1.96 | 1.50 | ok, short of aim |
| near-done /10k built | 0.50 | 0.76 | 0.00 | ok, short of aim |
| t2 cons given early | 0.00 | 0.00 | 0.00 | ok |
| supers before 4 moho | 0.25 | 0.33 | 0.00 | ok, short of aim |
| lone t2 con minutes | 0.12 | 0.10 | 0.00 | ok, short of aim |
| base lost /covered min | 25.00 | 25.00 | 0.00 | ok, short of aim |
| oldest plant order min | 1.39 | 1.47 | - | ok |
| no t2 by minute 20 | - | - | - | n/a |
| frozen minutes | 0.01 | 0.03 | 0.00 | ok, short of aim |
| com minutes on their half | 1.19 | 1.37 | - | ok |
| com lost on their half | 0.04 | 0.04 | 0.00 | ok, short of aim |
| mex lost to ticks by 10 min | 0.21 | 0.10 | 0.00 | ok, short of aim |
| raider repeat kills /10min | 4.28 | 4.07 | 0.00 | ok, short of aim |
| their mex killed /10min (neg) | -8.70 | -10.08 | - | ok |
| their army / ours, 8-12 min | 1.07 | 0.82 | - | ok |
| lost per killed | 1.56 | 1.50 | - | ok |
| reclaimed / killed (neg) | -0.12 | -0.07 | - | ok |
| bare-hands minutes | 0.04 | 0.07 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.38 | 0.34 | 0.00 | ok, short of aim |
| runs turned back | 0.00 | 0.00 | 0.00 | ok |
| gunships sent to lose | 0.00 | 0.00 | 0.00 | ok |
| stacked radar/jammers | 0.01 | 0.00 | 0.00 | ok, short of aim |
| army stuck /10min/1k army | 10.77 | 14.14 | 0.00 | ok, short of aim |
| ground given up share | 0.09 | 0.09 | 0.00 | ok, short of aim |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.03 | -1.01 | - | ok |
| army share (neg) | 0.41 | 0.42 | - | ok |
| -log income at 20 | - | - | - | n/a |
| games won or ahead | 0.69 | 0.50 | - | ok |

Contract: **PASS** over 68 games (136 of our seats, 136 release seats); 15 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.17 (run `python tools/anomaly.py build`)
```
