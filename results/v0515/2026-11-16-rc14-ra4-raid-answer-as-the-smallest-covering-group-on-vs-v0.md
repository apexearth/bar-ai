<!-- meta {"date": "2026-11-16", "topic": "v0515", "title": "rc14+ra4: raid answer as the smallest covering group, ON vs v0.5.14, rc11 and ra1/ra2 seeds, 44 games", "games": 44, "W": 2, "L": 4, "w": 16, "l": 21, "inc20": 0.84, "verdict": "rc11 seeds: won or ahead 16 vs OFF 9 of 20 (contract PASS, 0.80). ra seeds: 12 vs 14 of 24. Together 28 vs 23 of 44 (only-ON 14, only-OFF 9; sign test p~0.4); kill-lost better ON in 21 of 44. Answer share median 0.12 (was 0.19), 18 of 213 over half. Leans ON, unproven."} -->
# rc14+ra4: raid answer as the smallest covering group, ON vs v0.5.14, rc11 and ra1/ra2 seeds, 44 games

- **Date:** 2026-11-16
- **Topic:** v0515
- **Purpose:** rc13/ra3 showed nearest-first sizing overshooting (24k of a 26k army at a 4.5k raid). The answer now takes, nearest first, every unit that fits in 1.2x the raid, then the one unit that closes the rest with the least spare. Paired with the OFF arms rc12, ra1-v0, ra2-v0.
- **Result:** 44 games: won 2, lost 4, timeouts ahead 16, behind 21; income at 20 min x0.84 ours/theirs
- **Verdict:** rc11 seeds: won or ahead 16 vs OFF 9 of 20 (contract PASS, 0.80). ra seeds: 12 vs 14 of 24. Together 28 vs 23 of 44 (only-ON 14, only-OFF 9; sign test p~0.4); kill-lost better ON in 21 of 44. Answer share median 0.12 (was 0.19), 18 of 213 over half. Leans ON, unproven.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.14-standard
- **Code:** Apex-v0.5.14-standard = `363c70a0a5+1bb8e5b07c76` (44 games); Apexestall-lane-estall-standard = `6fc9a74aef+ed7a47fe57fc` (44 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Full Metal Plate 1.7, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 20, 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.14:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9903 --ai-option apex_raid_answer_stock=1 --out matches/rc14-v1-cc2-A9903`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9903 | 0 | w | 30.0 | x1.01 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/rc14-v1-cc2-A9903` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9906 | 0 | L | 23.25 | x0.08 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/rc14-v1-cc2-A9906` |
| 2 | Comet Catcher Remake 1.8 | Cortex | 9903 | 0 | L | 29.91 | x0.56 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/rc14-v1-cc2-C9903` |
| 3 | Comet Catcher Remake 1.8 | Cortex | 9906 | 0 | w | 30.0 | x1.41 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/rc14-v1-cc2-C9906` |
| 4 | Carrot Mountains v2.0 | Armada | 9902 | 0 | w | 30.0 | x1.40 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/rc14-v1-cm2-A9902` |
| 5 | Carrot Mountains v2.0 | Armada | 9905 | 0 | l | 30.0 | x0.84 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/rc14-v1-cm2-A9905` |
| 6 | Carrot Mountains v2.0 | Cortex | 9902 | 0 | l | 30.0 | x1.12 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/rc14-v1-cm2-C9902` |
| 7 | Carrot Mountains v2.0 | Cortex | 9905 | 0 | w | 30.0 | x0.77 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/rc14-v1-cm2-C9905` |
| 8 | Full Metal Plate 1.7 | Armada | 9911 | 0 | W | 23.12 | x1.34 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/rc14-v1-fm1-A9911` |
| 9 | Full Metal Plate 1.7 | Armada | 9912 | 0 | w | 30.0 | x1.12 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/rc14-v1-fm1-A9912` |
| 10 | Full Metal Plate 1.7 | Cortex | 9911 | 0 | l | 30.0 | x0.73 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/rc14-v1-fm1-C9911` |
| 11 | Full Metal Plate 1.7 | Cortex | 9912 | 0 | l | 30.0 | x0.97 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/rc14-v1-fm1-C9912` |
| 12 | Full Metal Plate 1.7 | Armada | 9911 | 0 | l | 30.0 | x0.59 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/rc14-v1-fm2-A9911` |
| 13 | Full Metal Plate 1.7 | Armada | 9912 | 0 | w | 30.0 | x1.81 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/rc14-v1-fm2-A9912` |
| 14 | Full Metal Plate 1.7 | Cortex | 9911 | 0 | l | 30.0 | x1.36 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/rc14-v1-fm2-C9911` |
| 15 | Full Metal Plate 1.7 | Cortex | 9912 | 0 | w | 30.0 | x1.20 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/rc14-v1-fm2-C9912` |
| 16 | Red Comet Remake 1.8 | Armada | 9901 | 0 | w | 30.0 | x1.72 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/rc14-v1-rc2-A9901` |
| 17 | Red Comet Remake 1.8 | Armada | 9904 | 0 | - | 30.0 | x2.06 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/rc14-v1-rc2-A9904` |
| 18 | Red Comet Remake 1.8 | Cortex | 9901 | 0 | w | 30.0 | x2.70 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/rc14-v1-rc2-C9901` |
| 19 | Red Comet Remake 1.8 | Cortex | 9904 | 0 | w | 30.0 | x1.82 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/rc14-v1-rc2-C9904` |
| 20 | Carrot Mountains v2.0 | Armada | 9801 | 0 | l | 20.0 | x0.33 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/ra4-v1-cm2-A9801` |
| 21 | Carrot Mountains v2.0 | Armada | 9802 | 0 | l | 20.0 | x0.46 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/ra4-v1-cm2-A9802` |
| 22 | Carrot Mountains v2.0 | Armada | 9803 | 0 | l | 20.0 | x0.62 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/ra4-v1-cm2-A9803` |
| 23 | Carrot Mountains v2.0 | Armada | 9804 | 0 | l | 20.0 | x0.59 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/ra4-v1-cm2-A9804` |
| 24 | Carrot Mountains v2.0 | Armada | 9805 | 0 | w | 20.0 | x2.13 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/ra4-v1-cm2-A9805` |
| 25 | Carrot Mountains v2.0 | Armada | 9806 | 0 | w | 20.0 | x1.15 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/ra4-v1-cm2-A9806` |
| 26 | Carrot Mountains v2.0 | Cortex | 9801 | 0 | w | 20.0 | x1.09 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/ra4-v1-cm2-C9801` |
| 27 | Carrot Mountains v2.0 | Cortex | 9802 | 0 | l | 20.0 | x0.81 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/ra4-v1-cm2-C9802` |
| 28 | Carrot Mountains v2.0 | Cortex | 9803 | 0 | l | 20.0 | x0.84 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/ra4-v1-cm2-C9803` |
| 29 | Carrot Mountains v2.0 | Cortex | 9804 | 0 | l | 20.0 | x0.74 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/ra4-v1-cm2-C9804` |
| 30 | Carrot Mountains v2.0 | Cortex | 9805 | 0 | l | 20.0 | x0.77 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/ra4-v1-cm2-C9805` |
| 31 | Carrot Mountains v2.0 | Cortex | 9806 | 0 | l | 20.0 | x0.63 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/ra4-v1-cm2-C9806` |
| 32 | Red Comet Remake 1.8 | Armada | 9801 | 0 | W | 19.61 | - | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/ra4-v1-rc2-A9801` |
| 33 | Red Comet Remake 1.8 | Armada | 9802 | 0 | L | 19.65 | - | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/ra4-v1-rc2-A9802` |
| 34 | Red Comet Remake 1.8 | Armada | 9803 | 0 | w | 20.0 | x1.52 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/ra4-v1-rc2-A9803` |
| 35 | Red Comet Remake 1.8 | Armada | 9804 | 0 | l | 20.0 | x0.60 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/ra4-v1-rc2-A9804` |
| 36 | Red Comet Remake 1.8 | Armada | 9805 | 0 | l | 20.0 | x0.24 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/ra4-v1-rc2-A9805` |
| 37 | Red Comet Remake 1.8 | Armada | 9806 | 0 | l | 20.0 | x0.23 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/ra4-v1-rc2-A9806` |
| 38 | Red Comet Remake 1.8 | Cortex | 9801 | 0 | l | 20.0 | x0.63 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/ra4-v1-rc2-C9801` |
| 39 | Red Comet Remake 1.8 | Cortex | 9802 | 0 | w | 20.0 | x1.39 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/ra4-v1-rc2-C9802` |
| 40 | Red Comet Remake 1.8 | Cortex | 9803 | 0 | L | 18.13 | - | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/ra4-v1-rc2-C9803` |
| 41 | Red Comet Remake 1.8 | Cortex | 9804 | 0 | l | 20.0 | x0.61 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/ra4-v1-rc2-C9804` |
| 42 | Red Comet Remake 1.8 | Cortex | 9805 | 0 | w | 20.0 | x1.22 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/ra4-v1-rc2-C9805` |
| 43 | Red Comet Remake 1.8 | Cortex | 9806 | 0 | l | 20.0 | x0.37 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+ed7a47fe57fc | `matches/ra4-v1-rc2-C9806` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.65 | 2.69 | - | ok |
| t2->4th moho (min) | 5.83 | 5.71 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.35 | 0.33 | 0.00 | ok, short of aim |
| adv plant frame x | 2.11 | 1.96 | 1.50 | ok, short of aim |
| near-done /10k built | 0.53 | 0.55 | 0.00 | ok, short of aim |
| t2 cons given early | 0.04 | 0.08 | 0.00 | ok, short of aim |
| supers before 4 moho | 2.01 | 2.29 | 0.00 | ok, short of aim |
| lone t2 con minutes | 0.46 | 0.76 | 0.00 | ok, short of aim |
| base lost while 'covered' k | 3.33 | 4.84 | 0.00 | ok, short of aim |
| oldest plant order min | 2.84 | 2.86 | - | ok |
| no t2 by minute 20 | 0.00 | 0.03 | - | ok |
| frozen minutes | 0.43 | 0.19 | 0.00 | ok, short of aim |
| raid answer army share | 0.47 | - | - | n/a |
| bare-hands minutes | 0.50 | 0.29 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.36 | 0.40 | 0.00 | ok, short of aim |
| runs turned back | 0.04 | 0.03 | 0.00 | ok, short of aim |
| gunships sent to lose | 0.00 | 0.00 | 0.00 | ok |
| stacked radar/jammers | 0.05 | 0.08 | 0.00 | ok, short of aim |
| army stuck /10min/1k army | 3.23 | 4.27 | 0.00 | ok, short of aim |
| ground given up share | 0.20 | 0.21 | 0.00 | ok, short of aim |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.37 | -1.34 | - | ok |
| army share (neg) | 0.40 | 0.39 | - | ok |
| -log income at 20 | -5.06 | -5.30 | - | FAIL (worse than release) |
| games won or ahead | 0.64 | 0.50 | - | ok |

Contract: **FAIL (1)** over 44 games (84 of our seats, 84 release seats); 15 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.14 (run `python tools/anomaly.py build`)
```
