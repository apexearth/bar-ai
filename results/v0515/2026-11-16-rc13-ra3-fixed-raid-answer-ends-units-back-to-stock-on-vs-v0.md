<!-- meta {"date": "2026-11-16", "topic": "v0515", "title": "rc13+ra3: fixed raid answer (ends, units back to stock) ON vs v0.5.14, rc11 and ra1/ra2 seeds, 44 games", "games": 44, "W": 1, "L": 4, "w": 17, "l": 22, "inc20": 0.88, "verdict": "No gain: won or ahead ON 25 vs OFF 23 of 44 (11 vs 9 on rc11 seeds, 14 vs 14 on ra seeds); kill-lost better ON in 19 of 44. Answers median 21% of the standing army, 53 of 417 over half; worst sent 24k of a 26k army (5 from attack) at a 4.5k raid and a lone 20k unit at a 2.2k raid: nearest-first sizing overshoots. Next: smallest covering answer (rc14/ra4)."} -->
# rc13+ra3: fixed raid answer (ends, units back to stock) ON vs v0.5.14, rc11 and ra1/ra2 seeds, 44 games

- **Date:** 2026-11-16
- **Topic:** v0515
- **Purpose:** Retest after the 11-16 review found the answer under stock roamed as a stock raid and never released its units (trap S65). Paired with the OFF arms rc12, ra1-v0, ra2-v0 (v0.5.14 code).
- **Result:** 44 games: won 1, lost 4, timeouts ahead 17, behind 22; income at 20 min x0.88 ours/theirs
- **Verdict:** No gain: won or ahead ON 25 vs OFF 23 of 44 (11 vs 9 on rc11 seeds, 14 vs 14 on ra seeds); kill-lost better ON in 19 of 44. Answers median 21% of the standing army, 53 of 417 over half; worst sent 24k of a 26k army (5 from attack) at a 4.5k raid and a lone 20k unit at a 2.2k raid: nearest-first sizing overshoots. Next: smallest covering answer (rc14/ra4).
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.14-standard
- **Code:** Apex-v0.5.14-standard = `363c70a0a5+1bb8e5b07c76` (44 games); Apexestall-lane-estall-standard = `6fc9a74aef+6cb015fd2772` (44 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Full Metal Plate 1.7, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 20, 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.14:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9903 --ai-option apex_raid_answer_stock=1 --out matches/rc13-v1-cc2-A9903`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9903 | 0 | L | 24.16 | x0.18 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/rc13-v1-cc2-A9903` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9906 | 0 | w | 30.0 | x1.36 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/rc13-v1-cc2-A9906` |
| 2 | Comet Catcher Remake 1.8 | Cortex | 9903 | 0 | w | 30.0 | x1.43 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/rc13-v1-cc2-C9903` |
| 3 | Comet Catcher Remake 1.8 | Cortex | 9906 | 0 | l | 30.0 | x0.86 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/rc13-v1-cc2-C9906` |
| 4 | Carrot Mountains v2.0 | Armada | 9902 | 0 | w | 30.0 | x1.72 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/rc13-v1-cm2-A9902` |
| 5 | Carrot Mountains v2.0 | Armada | 9905 | 0 | w | 30.0 | x1.59 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/rc13-v1-cm2-A9905` |
| 6 | Carrot Mountains v2.0 | Cortex | 9902 | 0 | w | 30.0 | x2.00 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/rc13-v1-cm2-C9902` |
| 7 | Carrot Mountains v2.0 | Cortex | 9905 | 0 | w | 30.0 | x0.74 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/rc13-v1-cm2-C9905` |
| 8 | Full Metal Plate 1.7 | Armada | 9911 | 0 | l | 30.0 | x0.69 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/rc13-v1-fm1-A9911` |
| 9 | Full Metal Plate 1.7 | Armada | 9912 | 0 | l | 30.0 | x0.79 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/rc13-v1-fm1-A9912` |
| 10 | Full Metal Plate 1.7 | Cortex | 9911 | 0 | l | 30.0 | x0.47 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/rc13-v1-fm1-C9911` |
| 11 | Full Metal Plate 1.7 | Cortex | 9912 | 0 | l | 30.0 | x1.07 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/rc13-v1-fm1-C9912` |
| 12 | Full Metal Plate 1.7 | Armada | 9911 | 0 | l | 30.0 | x0.66 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/rc13-v1-fm2-A9911` |
| 13 | Full Metal Plate 1.7 | Armada | 9912 | 0 | l | 30.0 | x0.46 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/rc13-v1-fm2-A9912` |
| 14 | Full Metal Plate 1.7 | Cortex | 9911 | 0 | w | 30.0 | x1.55 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/rc13-v1-fm2-C9911` |
| 15 | Full Metal Plate 1.7 | Cortex | 9912 | 0 | l | 30.0 | x0.35 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/rc13-v1-fm2-C9912` |
| 16 | Red Comet Remake 1.8 | Armada | 9901 | 0 | l | 30.0 | x1.19 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/rc13-v1-rc2-A9901` |
| 17 | Red Comet Remake 1.8 | Armada | 9904 | 0 | L | 21.51 | x0.15 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/rc13-v1-rc2-A9904` |
| 18 | Red Comet Remake 1.8 | Cortex | 9901 | 0 | L | 19.23 | - | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/rc13-v1-rc2-C9901` |
| 19 | Red Comet Remake 1.8 | Cortex | 9904 | 0 | w | 30.0 | x1.19 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/rc13-v1-rc2-C9904` |
| 20 | Carrot Mountains v2.0 | Armada | 9801 | 0 | w | 20.0 | x1.63 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/ra3-v1-cm2-A9801` |
| 21 | Carrot Mountains v2.0 | Armada | 9802 | 0 | l | 20.0 | x0.98 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/ra3-v1-cm2-A9802` |
| 22 | Carrot Mountains v2.0 | Armada | 9803 | 0 | w | 20.0 | x1.09 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/ra3-v1-cm2-A9803` |
| 23 | Carrot Mountains v2.0 | Armada | 9804 | 0 | L | 18.02 | - | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/ra3-v1-cm2-A9804` |
| 24 | Carrot Mountains v2.0 | Armada | 9805 | 0 | l | 20.0 | x0.96 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/ra3-v1-cm2-A9805` |
| 25 | Carrot Mountains v2.0 | Armada | 9806 | 0 | w | 20.0 | x2.10 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/ra3-v1-cm2-A9806` |
| 26 | Carrot Mountains v2.0 | Cortex | 9801 | 0 | l | 20.0 | x0.89 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/ra3-v1-cm2-C9801` |
| 27 | Carrot Mountains v2.0 | Cortex | 9802 | 0 | l | 20.0 | x0.92 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/ra3-v1-cm2-C9802` |
| 28 | Carrot Mountains v2.0 | Cortex | 9803 | 0 | l | 20.0 | x0.45 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/ra3-v1-cm2-C9803` |
| 29 | Carrot Mountains v2.0 | Cortex | 9804 | 0 | l | 20.0 | x0.55 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/ra3-v1-cm2-C9804` |
| 30 | Carrot Mountains v2.0 | Cortex | 9805 | 0 | l | 20.0 | x0.76 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/ra3-v1-cm2-C9805` |
| 31 | Carrot Mountains v2.0 | Cortex | 9806 | 0 | l | 20.0 | x0.72 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/ra3-v1-cm2-C9806` |
| 32 | Red Comet Remake 1.8 | Armada | 9801 | 0 | w | 20.0 | x1.75 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/ra3-v1-rc2-A9801` |
| 33 | Red Comet Remake 1.8 | Armada | 9802 | 0 | l | 20.0 | x0.64 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/ra3-v1-rc2-A9802` |
| 34 | Red Comet Remake 1.8 | Armada | 9803 | 0 | l | 20.0 | x0.43 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/ra3-v1-rc2-A9803` |
| 35 | Red Comet Remake 1.8 | Armada | 9804 | 0 | w | 20.0 | x1.31 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/ra3-v1-rc2-A9804` |
| 36 | Red Comet Remake 1.8 | Armada | 9805 | 0 | W | 19.82 | - | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/ra3-v1-rc2-A9805` |
| 37 | Red Comet Remake 1.8 | Armada | 9806 | 0 | w | 20.0 | x4.84 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/ra3-v1-rc2-A9806` |
| 38 | Red Comet Remake 1.8 | Cortex | 9801 | 0 | l | 20.0 | x0.82 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/ra3-v1-rc2-C9801` |
| 39 | Red Comet Remake 1.8 | Cortex | 9802 | 0 | w | 20.0 | x2.11 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/ra3-v1-rc2-C9802` |
| 40 | Red Comet Remake 1.8 | Cortex | 9803 | 0 | w | 20.0 | x1.02 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/ra3-v1-rc2-C9803` |
| 41 | Red Comet Remake 1.8 | Cortex | 9804 | 0 | l | 20.0 | x0.20 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/ra3-v1-rc2-C9804` |
| 42 | Red Comet Remake 1.8 | Cortex | 9805 | 0 | w | 20.0 | x1.32 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/ra3-v1-rc2-C9805` |
| 43 | Red Comet Remake 1.8 | Cortex | 9806 | 0 | l | 20.0 | x0.89 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+6cb015fd2772 | `matches/ra3-v1-rc2-C9806` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.73 | 2.66 | - | ok |
| t2->4th moho (min) | 5.54 | 5.66 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.38 | 0.36 | 0.00 | ok, short of aim |
| adv plant frame x | 2.05 | 2.03 | 1.50 | ok, short of aim |
| near-done /10k built | 0.49 | 0.60 | 0.00 | ok, short of aim |
| t2 cons given early | 0.11 | 0.05 | 0.00 | ok, short of aim |
| supers before 4 moho | 1.87 | 2.20 | 0.00 | ok, short of aim |
| lone t2 con minutes | 0.51 | 0.69 | 0.00 | ok, short of aim |
| base lost while 'covered' k | 4.69 | 3.62 | 0.00 | FAIL (worse than release) |
| oldest plant order min | 2.85 | 2.72 | - | ok |
| no t2 by minute 20 | 0.05 | 0.03 | - | ok |
| frozen minutes | 0.45 | 0.21 | 0.00 | ok, short of aim |
| raid answer army share | 0.43 | - | - | n/a |
| bare-hands minutes | 0.60 | 0.24 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.31 | 0.42 | 0.00 | ok, short of aim |
| runs turned back | 0.03 | 0.03 | 0.00 | ok, short of aim |
| gunships sent to lose | 0.00 | 0.00 | 0.00 | ok |
| stacked radar/jammers | 0.05 | 0.04 | 0.00 | ok, short of aim |
| army stuck /10min/1k army | 3.82 | 4.63 | 0.00 | ok, short of aim |
| ground given up share | 0.23 | 0.22 | 0.00 | ok, short of aim |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.35 | -1.38 | - | ok |
| army share (neg) | 0.39 | 0.39 | - | ok |
| -log income at 20 | -4.92 | -5.39 | - | FAIL (worse than release) |
| games won or ahead | 0.57 | 0.50 | - | ok |

Contract: **FAIL (2)** over 44 games (84 of our seats, 84 release seats); 15 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.14 (run `python tools/anomaly.py build`)
```
