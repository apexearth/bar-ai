<!-- meta {"date": "2026-11-23", "topic": "home-radar", "title": "Home radar cost without sight (apex_home_radar=2, mast self-destructed when built), 18 games", "games": 18, "W": 2, "L": 5, "w": 1, "l": 10, "inc20": 0.62, "verdict": "Cost-only is the worst arm (won/ahead 0.17 vs on 0.44 vs off 0.67), but the blast killed our own early eco in 24 of 36 seats (3,368 m) on Carrot and Red Comet. Blast-free Comet Catcher only (6 pairs): income at 24 113 cost-only vs 198 on vs 230 off. Sight is not the harm; building it is (or something the arm adds)."} -->
# Home radar cost without sight (apex_home_radar=2, mast self-destructed when built), 18 games

- **Date:** 2026-11-23
- **Topic:** home-radar
- **Purpose:** Split the radar's cost from its sight: the mast is priced, sited and built as under 1, then self-destructed. Controls: Esc0 (off) and Esc1 (on), same seeds and settings, results page 2026-11-23 commander-lab-assist.
- **Result:** 18 games: won 2, lost 5, timeouts ahead 1, behind 10; income at 20 min x0.62 ours/theirs
- **Verdict:** Cost-only is the worst arm (won/ahead 0.17 vs on 0.44 vs off 0.67), but the blast killed our own early eco in 24 of 36 seats (3,368 m) on Carrot and Red Comet. Blast-free Comet Catcher only (6 pairs): income at 24 113 cost-only vs 198 on vs 230 off. Sight is not the harm; building it is (or something the arm adds).
- **Ours:** Apexarmynet-lane-armynet-standard
- **Opponents:** Apex-v0.5.17-standard
- **Code:** Apex-v0.5.17-standard = `d32b7b84d8+5a6138c466fd` (18 games); Apexarmynet-lane-armynet-standard = `927ff16c17+13b06632edeb` (18 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexarmynet:lane-armynet:standard --b Apex:v0.5.17:standard --per-side 2 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 1813 --map Comet Catcher Remake 1.8 --out matches/hrp-Hrp2-cc-A1813 --modoption apex_home_radar=2 --modoption apex_com_escort=0`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 1813 | 0 | l | 30.0 | x0.90 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/hrp-Hrp2-cc-A1813` |
| 1 | Comet Catcher Remake 1.8 | Cortex | 1813 | 0 | l | 30.0 | x0.53 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/hrp-Hrp2-cc-C1813` |
| 2 | Comet Catcher Remake 1.8 | Armada | 1814 | 0 | L | 25.21 | x0.14 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/hrp-Hrp2-cc-A1814` |
| 3 | Comet Catcher Remake 1.8 | Cortex | 1814 | 0 | l | 30.0 | x0.39 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/hrp-Hrp2-cc-C1814` |
| 4 | Comet Catcher Remake 1.8 | Armada | 1815 | 0 | L | 28.5 | x0.47 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/hrp-Hrp2-cc-A1815` |
| 5 | Comet Catcher Remake 1.8 | Cortex | 1815 | 0 | l | 30.0 | x0.52 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/hrp-Hrp2-cc-C1815` |
| 6 | Carrot Mountains v2.0 | Armada | 1813 | 0 | w | 30.0 | x1.45 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/hrp-Hrp2-cm-A1813` |
| 7 | Carrot Mountains v2.0 | Cortex | 1813 | 0 | l | 30.0 | x0.66 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/hrp-Hrp2-cm-C1813` |
| 8 | Carrot Mountains v2.0 | Armada | 1814 | 0 | L | 16.53 | - | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/hrp-Hrp2-cm-A1814` |
| 9 | Carrot Mountains v2.0 | Cortex | 1814 | 0 | l | 30.0 | x0.99 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/hrp-Hrp2-cm-C1814` |
| 10 | Carrot Mountains v2.0 | Armada | 1815 | 0 | l | 30.0 | x1.01 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/hrp-Hrp2-cm-A1815` |
| 11 | Carrot Mountains v2.0 | Cortex | 1815 | 0 | L | 26.83 | x0.30 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/hrp-Hrp2-cm-C1815` |
| 12 | Red Comet Remake 1.8 | Armada | 1813 | 0 | L | 27.11 | x0.28 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/hrp-Hrp2-rc-A1813` |
| 13 | Red Comet Remake 1.8 | Cortex | 1813 | 0 | l | 30.0 | x0.36 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/hrp-Hrp2-rc-C1813` |
| 14 | Red Comet Remake 1.8 | Armada | 1814 | 0 | W | 26.93 | x2.42 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/hrp-Hrp2-rc-A1814` |
| 15 | Red Comet Remake 1.8 | Cortex | 1814 | 0 | l | 30.0 | x0.71 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/hrp-Hrp2-rc-C1814` |
| 16 | Red Comet Remake 1.8 | Armada | 1815 | 0 | W | 29.01 | x1.47 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/hrp-Hrp2-rc-A1815` |
| 17 | Red Comet Remake 1.8 | Cortex | 1815 | 0 | l | 30.0 | x0.58 | 927ff16c17+13b06632edeb, d32b7b84d8+5a6138c466fd | `matches/hrp-Hrp2-rc-C1815` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.91 | 2.72 | - | ok |
| t2->4th moho (min) | 6.77 | 5.56 | 3.00 | worse, within noise (66% of resamples) |
| lab-job leaves/job | 0.50 | 0.36 | 0.00 | worse, within noise (72% of resamples) |
| adv plant frame x | 2.10 | 2.34 | 1.50 | ok, short of aim |
| near-done /10k built | 0.37 | 0.56 | 0.00 | ok, short of aim |
| t2 cons given early | 0.11 | 0.03 | 0.00 | ok, short of aim |
| supers before 4 moho | 1.88 | 1.51 | 0.00 | ok, short of aim |
| lone t2 con minutes | 1.45 | 0.51 | 0.00 | ok, short of aim |
| base lost /covered min | 222.73 | 36.58 | 0.00 | ok, short of aim |
| oldest plant order min | 2.90 | 2.67 | - | ok |
| no t2 by minute 20 | 0.06 | 0.03 | - | ok |
| frozen minutes | 0.56 | 0.06 | 0.00 | ok, short of aim |
| com minutes on their half | 1.82 | 2.07 | - | ok |
| com lost on their half | 0.08 | 0.03 | 0.00 | worse, within noise (62% of resamples) |
| mex lost to ticks by 10 min | 0.19 | 0.33 | 0.00 | ok, short of aim |
| raider repeat kills /10min | 13.29 | 8.82 | 0.00 | FAIL (worse than release, 95% of resamples) |
| their mex killed /10min (neg) | -13.95 | -16.32 | - | worse, within noise (58% of resamples) |
| their army / ours, 8-12 min | 1.25 | 0.61 | - | FAIL (worse than release, 97% of resamples) |
| lost per killed | 2.23 | 1.22 | - | FAIL (worse than release, 94% of resamples) |
| reclaimed / killed (neg) | -0.16 | -0.14 | - | ok |
| bare-hands minutes | 1.22 | 0.22 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.51 | 0.47 | 0.00 | ok, short of aim |
| runs turned back | 0.00 | 0.00 | 0.00 | ok |
| gunships sent to lose | 0.00 | 0.00 | 0.00 | ok |
| stacked radar/jammers | 0.06 | 0.08 | 0.00 | ok, short of aim |
| army stuck /10min/1k army | 2.97 | 2.95 | 0.00 | ok, short of aim |
| ground given up share | 0.23 | 0.17 | 0.00 | worse, within noise (60% of resamples) |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.28 | -1.34 | - | ok |
| army share (neg) | 0.37 | 0.34 | - | ok |
| -log income at 20 | -4.54 | -5.05 | - | FAIL (worse than release, 98% of resamples) |
| games won or ahead | 0.17 | 0.50 | - | FAIL (does not beat the release) |

Contract: **FAIL (5)** over 18 games (36 of our seats, 36 release seats); 17 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.17 (run `python tools/anomaly.py build`)
```
