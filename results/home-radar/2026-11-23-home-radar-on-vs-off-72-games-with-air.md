<!-- meta {"date": "2026-11-23", "topic": "home-radar", "title": "Home radar on vs off, 72 games with air", "games": 72, "W": 9, "L": 13, "w": 23, "l": 27, "inc20": 0.82, "verdict": "Radar ON loses: won or ahead 0.31 vs 0.67, contract FAIL vs PASS; income at 20 109 vs 136 (on higher in 9 of 36 paired). Cause found in the opening: the comescort hoist fires when the home radar outranks the mex, taking the commander to the lab 60 s at a time (34 vs 13 times before minute 4). Follow-up: comescort off, matches/esc."} -->
# Home radar on vs off, 72 games with air

- **Date:** 2026-11-23
- **Topic:** home-radar
- **Purpose:** Settle the v0.5.18 home-radar question at normal settings (air and nukes on), same seeds 1813-1818 x 3 maps x 2 factions, vs v0.5.17 at +50.
- **Result:** 72 games: won 9, lost 13, timeouts ahead 23, behind 27; income at 20 min x0.82 ours/theirs
- **Verdict:** Radar ON loses: won or ahead 0.31 vs 0.67, contract FAIL vs PASS; income at 20 109 vs 136 (on higher in 9 of 36 paired). Cause found in the opening: the comescort hoist fires when the home radar outranks the mex, taking the commander to the lab 60 s at a time (34 vs 13 times before minute 4). Follow-up: comescort off, matches/esc.
- **Ours:** Apexarmynet-lane-armynet-standard
- **Opponents:** Apex-v0.5.17-standard
- **Code:** Apex-v0.5.17-standard = `d32b7b84d8+5a6138c466fd` (72 games); Apexarmynet-lane-armynet-standard = `927ff16c17+45274bc3e196` (72 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexarmynet:lane-armynet:standard --b Apex:v0.5.17:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 1813 --modoption apex_home_radar=0 --out matches/big-Brad0-cc-A1813`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 1813 | 0 | W | 28.4 | x1.09 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cc-A1813` |
| 1 | Comet Catcher Remake 1.8 | Armada | 1814 | 0 | w | 30.0 | x1.75 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cc-A1814` |
| 2 | Comet Catcher Remake 1.8 | Armada | 1815 | 0 | w | 30.0 | x0.92 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cc-A1815` |
| 3 | Comet Catcher Remake 1.8 | Armada | 1816 | 0 | l | 30.0 | x0.63 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cc-A1816` |
| 4 | Comet Catcher Remake 1.8 | Armada | 1817 | 0 | w | 30.0 | x0.87 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cc-A1817` |
| 5 | Comet Catcher Remake 1.8 | Armada | 1818 | 0 | l | 30.0 | x0.41 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cc-A1818` |
| 6 | Comet Catcher Remake 1.8 | Cortex | 1813 | 0 | w | 30.0 | x0.98 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cc-C1813` |
| 7 | Comet Catcher Remake 1.8 | Cortex | 1814 | 0 | L | 29.96 | x0.50 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cc-C1814` |
| 8 | Comet Catcher Remake 1.8 | Cortex | 1815 | 0 | W | 29.46 | x1.36 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cc-C1815` |
| 9 | Comet Catcher Remake 1.8 | Cortex | 1816 | 0 | l | 30.0 | x0.41 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cc-C1816` |
| 10 | Comet Catcher Remake 1.8 | Cortex | 1817 | 0 | l | 30.0 | x0.78 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cc-C1817` |
| 11 | Comet Catcher Remake 1.8 | Cortex | 1818 | 0 | l | 30.0 | x0.58 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cc-C1818` |
| 12 | Carrot Mountains v2.0 | Armada | 1813 | 0 | w | 30.0 | x1.06 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cm-A1813` |
| 13 | Carrot Mountains v2.0 | Armada | 1814 | 0 | L | 24.57 | x0.48 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cm-A1814` |
| 14 | Carrot Mountains v2.0 | Armada | 1815 | 0 | l | 30.0 | x0.63 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cm-A1815` |
| 15 | Carrot Mountains v2.0 | Armada | 1816 | 0 | l | 30.0 | x1.51 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cm-A1816` |
| 16 | Carrot Mountains v2.0 | Armada | 1817 | 0 | W | 26.02 | x2.04 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cm-A1817` |
| 17 | Carrot Mountains v2.0 | Armada | 1818 | 0 | w | 30.0 | x1.37 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cm-A1818` |
| 18 | Carrot Mountains v2.0 | Cortex | 1813 | 0 | w | 30.0 | x1.09 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cm-C1813` |
| 19 | Carrot Mountains v2.0 | Cortex | 1814 | 0 | w | 30.0 | x0.94 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cm-C1814` |
| 20 | Carrot Mountains v2.0 | Cortex | 1815 | 0 | w | 30.0 | x0.77 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cm-C1815` |
| 21 | Carrot Mountains v2.0 | Cortex | 1816 | 0 | l | 30.0 | x1.09 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cm-C1816` |
| 22 | Carrot Mountains v2.0 | Cortex | 1817 | 0 | w | 30.0 | x1.00 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cm-C1817` |
| 23 | Carrot Mountains v2.0 | Cortex | 1818 | 0 | w | 30.0 | x1.09 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cm-C1818` |
| 24 | Red Comet Remake 1.8 | Armada | 1813 | 0 | L | 26.65 | x0.78 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-rc-A1813` |
| 25 | Red Comet Remake 1.8 | Armada | 1814 | 0 | w | 30.0 | x1.24 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-rc-A1814` |
| 26 | Red Comet Remake 1.8 | Armada | 1815 | 0 | W | 25.14 | x1.51 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-rc-A1815` |
| 27 | Red Comet Remake 1.8 | Armada | 1816 | 0 | W | 23.29 | x12.13 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-rc-A1816` |
| 28 | Red Comet Remake 1.8 | Armada | 1817 | 0 | W | 21.0 | x29.36 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-rc-A1817` |
| 29 | Red Comet Remake 1.8 | Armada | 1818 | 0 | L | 20.14 | x0.01 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-rc-A1818` |
| 30 | Red Comet Remake 1.8 | Cortex | 1813 | 0 | w | 30.0 | x1.93 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-rc-C1813` |
| 31 | Red Comet Remake 1.8 | Cortex | 1814 | 0 | w | 30.0 | x1.23 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-rc-C1814` |
| 32 | Red Comet Remake 1.8 | Cortex | 1815 | 0 | W | 18.24 | - | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-rc-C1815` |
| 33 | Red Comet Remake 1.8 | Cortex | 1816 | 0 | L | 19.72 | - | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-rc-C1816` |
| 34 | Red Comet Remake 1.8 | Cortex | 1817 | 0 | w | 30.0 | x1.97 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-rc-C1817` |
| 35 | Red Comet Remake 1.8 | Cortex | 1818 | 0 | l | 30.0 | x0.93 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-rc-C1818` |
| 36 | Comet Catcher Remake 1.8 | Armada | 1813 | 0 | l | 30.0 | x0.86 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-cc-A1813` |
| 37 | Comet Catcher Remake 1.8 | Armada | 1814 | 0 | l | 30.0 | x0.82 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-cc-A1814` |
| 38 | Comet Catcher Remake 1.8 | Armada | 1815 | 0 | l | 30.0 | x0.75 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-cc-A1815` |
| 39 | Comet Catcher Remake 1.8 | Armada | 1816 | 0 | l | 30.0 | x0.74 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-cc-A1816` |
| 40 | Comet Catcher Remake 1.8 | Armada | 1817 | 0 | L | 22.38 | x0.03 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-cc-A1817` |
| 41 | Comet Catcher Remake 1.8 | Armada | 1818 | 0 | w | 30.0 | x1.37 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-cc-A1818` |
| 42 | Comet Catcher Remake 1.8 | Cortex | 1813 | 0 | w | 30.0 | x2.28 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-cc-C1813` |
| 43 | Comet Catcher Remake 1.8 | Cortex | 1814 | 0 | l | 30.0 | x0.87 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-cc-C1814` |
| 44 | Comet Catcher Remake 1.8 | Cortex | 1815 | 0 | l | 30.0 | x0.44 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-cc-C1815` |
| 45 | Comet Catcher Remake 1.8 | Cortex | 1816 | 0 | W | 28.42 | x3.82 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-cc-C1816` |
| 46 | Comet Catcher Remake 1.8 | Cortex | 1817 | 0 | l | 30.0 | x0.62 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-cc-C1817` |
| 47 | Comet Catcher Remake 1.8 | Cortex | 1818 | 0 | l | 30.0 | x0.54 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-cc-C1818` |
| 48 | Carrot Mountains v2.0 | Armada | 1813 | 0 | L | 25.9 | x0.19 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-cm-A1813` |
| 49 | Carrot Mountains v2.0 | Armada | 1814 | 0 | l | 30.0 | x0.59 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-cm-A1814` |
| 50 | Carrot Mountains v2.0 | Armada | 1815 | 0 | L | 28.03 | x0.45 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-cm-A1815` |
| 51 | Carrot Mountains v2.0 | Armada | 1816 | 0 | L | 28.58 | x0.68 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-cm-A1816` |
| 52 | Carrot Mountains v2.0 | Armada | 1817 | 0 | l | 30.0 | x0.32 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-cm-A1817` |
| 53 | Carrot Mountains v2.0 | Armada | 1818 | 0 | w | 30.0 | x1.22 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-cm-A1818` |
| 54 | Carrot Mountains v2.0 | Cortex | 1813 | 0 | l | 30.0 | x0.79 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-cm-C1813` |
| 55 | Carrot Mountains v2.0 | Cortex | 1814 | 0 | l | 30.0 | x0.76 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-cm-C1814` |
| 56 | Carrot Mountains v2.0 | Cortex | 1815 | 0 | l | 30.0 | x0.61 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-cm-C1815` |
| 57 | Carrot Mountains v2.0 | Cortex | 1816 | 0 | w | 30.0 | x1.33 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-cm-C1816` |
| 58 | Carrot Mountains v2.0 | Cortex | 1817 | 0 | w | 30.0 | x1.53 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-cm-C1817` |
| 59 | Carrot Mountains v2.0 | Cortex | 1818 | 0 | l | 30.0 | x0.64 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-cm-C1818` |
| 60 | Red Comet Remake 1.8 | Armada | 1813 | 0 | l | 30.0 | x0.29 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-rc-A1813` |
| 61 | Red Comet Remake 1.8 | Armada | 1814 | 0 | w | 30.0 | x0.59 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-rc-A1814` |
| 62 | Red Comet Remake 1.8 | Armada | 1815 | 0 | w | 30.0 | x1.76 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-rc-A1815` |
| 63 | Red Comet Remake 1.8 | Armada | 1816 | 0 | L | 19.2 | - | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-rc-A1816` |
| 64 | Red Comet Remake 1.8 | Armada | 1817 | 0 | W | 22.4 | x1.98 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-rc-A1817` |
| 65 | Red Comet Remake 1.8 | Armada | 1818 | 0 | L | 16.4 | - | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-rc-A1818` |
| 66 | Red Comet Remake 1.8 | Cortex | 1813 | 0 | l | 30.0 | x0.41 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-rc-C1813` |
| 67 | Red Comet Remake 1.8 | Cortex | 1814 | 0 | w | 30.0 | x1.30 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-rc-C1814` |
| 68 | Red Comet Remake 1.8 | Cortex | 1815 | 0 | l | 30.0 | x0.26 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-rc-C1815` |
| 69 | Red Comet Remake 1.8 | Cortex | 1816 | 0 | l | 30.0 | x0.56 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-rc-C1816` |
| 70 | Red Comet Remake 1.8 | Cortex | 1817 | 0 | L | 29.94 | x0.27 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-rc-C1817` |
| 71 | Red Comet Remake 1.8 | Cortex | 1818 | 0 | L | 18.45 | - | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad1-rc-C1818` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.83 | 2.59 | - | ok |
| t2->4th moho (min) | 6.37 | 6.22 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.41 | 0.33 | 0.00 | ok, short of aim |
| adv plant frame x | 2.05 | 2.06 | 1.50 | ok, short of aim |
| near-done /10k built | 0.48 | 0.53 | 0.00 | ok, short of aim |
| t2 cons given early | 0.06 | 0.01 | 0.00 | ok, short of aim |
| supers before 4 moho | 1.45 | 1.59 | 0.00 | ok, short of aim |
| lone t2 con minutes | 0.60 | 0.81 | 0.00 | ok, short of aim |
| base lost /covered min | 82.82 | 77.50 | 0.00 | ok, short of aim |
| oldest plant order min | 2.63 | 2.74 | - | ok |
| no t2 by minute 20 | 0.04 | 0.01 | - | ok |
| frozen minutes | 0.44 | 0.22 | 0.00 | ok, short of aim |
| com minutes on their half | 1.33 | 1.64 | - | ok |
| com lost on their half | 0.10 | 0.03 | 0.00 | worse, within noise (73% of resamples) |
| mex lost to ticks by 10 min | 0.31 | 0.22 | 0.00 | ok, short of aim |
| raider repeat kills /10min | 12.44 | 10.97 | 0.00 | worse, within noise (87% of resamples) |
| their mex killed /10min (neg) | -15.16 | -16.11 | - | ok |
| their army / ours, 8-12 min | 1.14 | 0.81 | - | worse, within noise (72% of resamples) |
| lost per killed | 1.84 | 1.49 | - | worse, within noise (72% of resamples) |
| reclaimed / killed (neg) | -0.16 | -0.17 | - | ok |
| bare-hands minutes | 0.60 | 0.38 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.50 | 0.44 | 0.00 | ok, short of aim |
| runs turned back | 0.01 | 0.04 | 0.00 | ok, short of aim |
| gunships sent to lose | 0.00 | 0.00 | 0.00 | ok |
| stacked radar/jammers | 0.03 | 0.07 | 0.00 | ok, short of aim |
| army stuck /10min/1k army | 3.05 | 3.51 | 0.00 | ok, short of aim |
| ground given up share | 0.21 | 0.20 | 0.00 | ok, short of aim |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.37 | -1.37 | - | ok |
| army share (neg) | 0.36 | 0.36 | - | ok |
| -log income at 20 | -4.82 | -5.04 | - | worse, within noise (88% of resamples) |
| games won or ahead | 0.49 | 0.50 | - | FAIL (does not beat the release) |

Contract: **FAIL (1)** over 72 games (144 of our seats, 144 release seats); 18 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.17 (run `python tools/anomaly.py build`)
```
