<!-- meta {"date": "2026-11-23", "topic": "home-radar", "title": "Commander lab-assist (comescort) off vs on, radar off, 36 pairs", "games": 72, "W": 12, "L": 12, "w": 28, "l": 20, "inc20": 1.02, "verdict": "No difference: income at 20 139 off vs 138 on (off higher 21 of 34), at 24 225 vs 216 (13 of 29); won/ahead 0.61 vs 0.67. Keep it as shipped in v0.5.17 (on)."} -->
# Commander lab-assist (comescort) off vs on, radar off, 36 pairs

- **Date:** 2026-11-23
- **Topic:** home-radar
- **Purpose:** Settle apex_com_escort for v0.5.18. Off arm: matches/esc-Esc0* (1813-1818); on arm: big-Brad0 (same seeds). The modoption reaches v0.5.17 too, so the opponent differs between arms; read income, not win rate.
- **Result:** 72 games: won 12, lost 12, timeouts ahead 28, behind 20; income at 20 min x1.02 ours/theirs
- **Verdict:** No difference: income at 20 139 off vs 138 on (off higher 21 of 34), at 24 225 vs 216 (13 of 29); won/ahead 0.61 vs 0.67. Keep it as shipped in v0.5.17 (on).
- **Ours:** Apexarmynet-lane-armynet-standard
- **Opponents:** Apex-v0.5.17-standard
- **Code:** Apex-v0.5.17-standard = `d32b7b84d8+5a6138c466fd` (72 games); Apexarmynet-lane-armynet-standard = `927ff16c17+13b06632edeb` (18 games); Apexarmynet-lane-armynet-standard = `927ff16c17+45274bc3e196` (36 games); Apexarmynet-lane-armynet-standard = `927ff16c17+f9503eb1ac00` (18 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexarmynet:lane-armynet:standard --b Apex:v0.5.17:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 1813 --modoption apex_home_radar=0 --modoption apex_com_escort=0 --out matches/esc-Esc0b-cc-A1813`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 1813 | 0 | W | 29.76 | x1.46 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0b-cc-A1813` |
| 1 | Comet Catcher Remake 1.8 | Cortex | 1813 | 0 | W | 25.28 | x3.09 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0b-cc-C1813` |
| 2 | Carrot Mountains v2.0 | Armada | 1813 | 0 | l | 30.0 | x0.74 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cm-A1813` |
| 3 | Carrot Mountains v2.0 | Cortex | 1813 | 0 | w | 30.0 | x1.36 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cm-C1813` |
| 4 | Red Comet Remake 1.8 | Armada | 1813 | 0 | L | 14.82 | - | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-rc-A1813` |
| 5 | Red Comet Remake 1.8 | Cortex | 1813 | 0 | W | 29.5 | x1.00 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-rc-C1813` |
| 6 | Comet Catcher Remake 1.8 | Armada | 1814 | 0 | w | 30.0 | x1.20 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cc-A1814` |
| 7 | Comet Catcher Remake 1.8 | Cortex | 1814 | 0 | l | 30.0 | x1.10 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cc-C1814` |
| 8 | Carrot Mountains v2.0 | Armada | 1814 | 0 | w | 30.0 | x1.36 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cm-A1814` |
| 9 | Carrot Mountains v2.0 | Cortex | 1814 | 0 | l | 30.0 | x0.83 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cm-C1814` |
| 10 | Red Comet Remake 1.8 | Armada | 1814 | 0 | W | 21.0 | x16.33 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-rc-A1814` |
| 11 | Red Comet Remake 1.8 | Cortex | 1814 | 0 | l | 30.0 | x0.67 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-rc-C1814` |
| 12 | Comet Catcher Remake 1.8 | Armada | 1815 | 0 | l | 30.0 | x0.66 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cc-A1815` |
| 13 | Comet Catcher Remake 1.8 | Cortex | 1815 | 0 | l | 30.0 | x0.60 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cc-C1815` |
| 14 | Carrot Mountains v2.0 | Armada | 1815 | 0 | w | 30.0 | x1.34 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cm-A1815` |
| 15 | Carrot Mountains v2.0 | Cortex | 1815 | 0 | l | 30.0 | x1.51 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cm-C1815` |
| 16 | Red Comet Remake 1.8 | Armada | 1815 | 0 | w | 30.0 | x1.56 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-rc-A1815` |
| 17 | Red Comet Remake 1.8 | Cortex | 1815 | 0 | w | 30.0 | x1.86 | 927ff16c17+f9503eb1ac00, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-rc-C1815` |
| 18 | Comet Catcher Remake 1.8 | Armada | 1816 | 0 | l | 30.0 | x0.78 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cc-A1816` |
| 19 | Comet Catcher Remake 1.8 | Cortex | 1816 | 0 | w | 30.0 | x0.94 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cc-C1816` |
| 20 | Carrot Mountains v2.0 | Armada | 1816 | 0 | L | 28.11 | x0.46 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cm-A1816` |
| 21 | Carrot Mountains v2.0 | Cortex | 1816 | 0 | l | 30.0 | x0.81 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cm-C1816` |
| 22 | Red Comet Remake 1.8 | Armada | 1816 | 0 | L | 11.13 | - | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-rc-A1816` |
| 23 | Red Comet Remake 1.8 | Cortex | 1816 | 0 | L | 27.73 | x0.43 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-rc-C1816` |
| 24 | Comet Catcher Remake 1.8 | Armada | 1817 | 0 | w | 30.0 | x1.58 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cc-A1817` |
| 25 | Comet Catcher Remake 1.8 | Cortex | 1817 | 0 | L | 29.04 | x0.95 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cc-C1817` |
| 26 | Carrot Mountains v2.0 | Armada | 1817 | 0 | w | 30.0 | x1.44 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cm-A1817` |
| 27 | Carrot Mountains v2.0 | Cortex | 1817 | 0 | w | 30.0 | x0.56 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cm-C1817` |
| 28 | Red Comet Remake 1.8 | Armada | 1817 | 0 | W | 27.63 | x1.30 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-rc-A1817` |
| 29 | Red Comet Remake 1.8 | Cortex | 1817 | 0 | w | 30.0 | x1.37 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-rc-C1817` |
| 30 | Comet Catcher Remake 1.8 | Armada | 1818 | 0 | L | 28.83 | x0.39 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cc-A1818` |
| 31 | Comet Catcher Remake 1.8 | Cortex | 1818 | 0 | w | 30.0 | x0.82 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cc-C1818` |
| 32 | Carrot Mountains v2.0 | Armada | 1818 | 0 | w | 30.0 | x1.97 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cm-A1818` |
| 33 | Carrot Mountains v2.0 | Cortex | 1818 | 0 | l | 30.0 | x0.97 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-cm-C1818` |
| 34 | Red Comet Remake 1.8 | Armada | 1818 | 0 | L | 25.64 | x0.08 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-rc-A1818` |
| 35 | Red Comet Remake 1.8 | Cortex | 1818 | 0 | l | 30.0 | x1.12 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/esc-Esc0-rc-C1818` |
| 36 | Comet Catcher Remake 1.8 | Armada | 1813 | 0 | W | 28.4 | x1.09 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cc-A1813` |
| 37 | Comet Catcher Remake 1.8 | Cortex | 1813 | 0 | w | 30.0 | x0.98 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cc-C1813` |
| 38 | Carrot Mountains v2.0 | Armada | 1813 | 0 | w | 30.0 | x1.06 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cm-A1813` |
| 39 | Carrot Mountains v2.0 | Cortex | 1813 | 0 | w | 30.0 | x1.09 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cm-C1813` |
| 40 | Red Comet Remake 1.8 | Armada | 1813 | 0 | L | 26.65 | x0.78 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-rc-A1813` |
| 41 | Red Comet Remake 1.8 | Cortex | 1813 | 0 | w | 30.0 | x1.93 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-rc-C1813` |
| 42 | Comet Catcher Remake 1.8 | Armada | 1814 | 0 | w | 30.0 | x1.75 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cc-A1814` |
| 43 | Comet Catcher Remake 1.8 | Cortex | 1814 | 0 | L | 29.96 | x0.50 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cc-C1814` |
| 44 | Carrot Mountains v2.0 | Armada | 1814 | 0 | L | 24.57 | x0.48 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cm-A1814` |
| 45 | Carrot Mountains v2.0 | Cortex | 1814 | 0 | w | 30.0 | x0.94 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cm-C1814` |
| 46 | Red Comet Remake 1.8 | Armada | 1814 | 0 | w | 30.0 | x1.24 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-rc-A1814` |
| 47 | Red Comet Remake 1.8 | Cortex | 1814 | 0 | w | 30.0 | x1.23 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-rc-C1814` |
| 48 | Comet Catcher Remake 1.8 | Armada | 1815 | 0 | w | 30.0 | x0.92 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cc-A1815` |
| 49 | Comet Catcher Remake 1.8 | Cortex | 1815 | 0 | W | 29.46 | x1.36 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cc-C1815` |
| 50 | Carrot Mountains v2.0 | Armada | 1815 | 0 | l | 30.0 | x0.63 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cm-A1815` |
| 51 | Carrot Mountains v2.0 | Cortex | 1815 | 0 | w | 30.0 | x0.77 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cm-C1815` |
| 52 | Red Comet Remake 1.8 | Armada | 1815 | 0 | W | 25.14 | x1.51 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-rc-A1815` |
| 53 | Red Comet Remake 1.8 | Cortex | 1815 | 0 | W | 18.24 | - | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-rc-C1815` |
| 54 | Comet Catcher Remake 1.8 | Armada | 1816 | 0 | l | 30.0 | x0.63 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cc-A1816` |
| 55 | Comet Catcher Remake 1.8 | Cortex | 1816 | 0 | l | 30.0 | x0.41 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cc-C1816` |
| 56 | Carrot Mountains v2.0 | Armada | 1816 | 0 | l | 30.0 | x1.51 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cm-A1816` |
| 57 | Carrot Mountains v2.0 | Cortex | 1816 | 0 | l | 30.0 | x1.09 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cm-C1816` |
| 58 | Red Comet Remake 1.8 | Armada | 1816 | 0 | W | 23.29 | x12.13 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-rc-A1816` |
| 59 | Red Comet Remake 1.8 | Cortex | 1816 | 0 | L | 19.72 | - | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-rc-C1816` |
| 60 | Comet Catcher Remake 1.8 | Armada | 1817 | 0 | w | 30.0 | x0.87 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cc-A1817` |
| 61 | Comet Catcher Remake 1.8 | Cortex | 1817 | 0 | l | 30.0 | x0.78 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cc-C1817` |
| 62 | Carrot Mountains v2.0 | Armada | 1817 | 0 | W | 26.02 | x2.04 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cm-A1817` |
| 63 | Carrot Mountains v2.0 | Cortex | 1817 | 0 | w | 30.0 | x1.00 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cm-C1817` |
| 64 | Red Comet Remake 1.8 | Armada | 1817 | 0 | W | 21.0 | x29.36 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-rc-A1817` |
| 65 | Red Comet Remake 1.8 | Cortex | 1817 | 0 | w | 30.0 | x1.97 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-rc-C1817` |
| 66 | Comet Catcher Remake 1.8 | Armada | 1818 | 0 | l | 30.0 | x0.41 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cc-A1818` |
| 67 | Comet Catcher Remake 1.8 | Cortex | 1818 | 0 | l | 30.0 | x0.58 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cc-C1818` |
| 68 | Carrot Mountains v2.0 | Armada | 1818 | 0 | w | 30.0 | x1.37 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cm-A1818` |
| 69 | Carrot Mountains v2.0 | Cortex | 1818 | 0 | w | 30.0 | x1.09 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-cm-C1818` |
| 70 | Red Comet Remake 1.8 | Armada | 1818 | 0 | L | 20.14 | x0.01 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-rc-A1818` |
| 71 | Red Comet Remake 1.8 | Cortex | 1818 | 0 | l | 30.0 | x0.93 | 927ff16c17+45274bc3e196, d32b7b84d8+5a6138c466fd | `matches/big-Brad0-rc-C1818` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.50 | 2.75 | - | ok |
| t2->4th moho (min) | 6.33 | 6.62 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.36 | 0.40 | 0.00 | ok, short of aim |
| adv plant frame x | 1.95 | 2.21 | 1.50 | ok, short of aim |
| near-done /10k built | 0.48 | 0.50 | 0.00 | ok, short of aim |
| t2 cons given early | 0.01 | 0.01 | 0.00 | ok, short of aim |
| supers before 4 moho | 1.33 | 1.51 | 0.00 | ok, short of aim |
| lone t2 con minutes | 0.61 | 0.82 | 0.00 | ok, short of aim |
| base lost /covered min | 47.00 | 109.13 | 0.00 | ok, short of aim |
| oldest plant order min | 2.77 | 2.88 | - | ok |
| no t2 by minute 20 | 0.04 | 0.04 | - | ok |
| frozen minutes | 0.43 | 0.53 | 0.00 | ok, short of aim |
| com minutes on their half | 1.54 | 1.60 | - | ok |
| com lost on their half | 0.09 | 0.04 | 0.00 | ok, short of aim |
| mex lost to ticks by 10 min | 0.21 | 0.17 | 0.00 | ok, short of aim |
| raider repeat kills /10min | 11.31 | 11.73 | 0.00 | ok, short of aim |
| their mex killed /10min (neg) | -15.40 | -15.82 | - | ok |
| their army / ours, 8-12 min | 1.28 | 0.94 | - | worse, within noise (63% of resamples) |
| lost per killed | 1.51 | 1.58 | - | ok |
| reclaimed / killed (neg) | -0.16 | -0.16 | - | ok |
| bare-hands minutes | 0.62 | 0.75 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.49 | 0.46 | 0.00 | ok, short of aim |
| runs turned back | 0.01 | 0.02 | 0.00 | ok, short of aim |
| gunships sent to lose | 0.00 | 0.00 | 0.00 | ok |
| stacked radar/jammers | 0.03 | 0.04 | 0.00 | ok, short of aim |
| army stuck /10min/1k army | 2.97 | 3.51 | 0.00 | ok, short of aim |
| ground given up share | 0.21 | 0.21 | 0.00 | ok, short of aim |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.39 | -1.36 | - | ok |
| army share (neg) | 0.36 | 0.36 | - | ok |
| -log income at 20 | -4.83 | -4.89 | - | ok |
| games won or ahead | 0.64 | 0.50 | - | ok |

Contract: **PASS** over 72 games (144 of our seats, 144 release seats); 18 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.17 (run `python tools/anomaly.py build`)
```
