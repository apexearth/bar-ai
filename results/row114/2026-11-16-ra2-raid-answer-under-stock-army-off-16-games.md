<!-- meta {"date": "2026-11-16", "topic": "row114", "title": "ra2: raid answer under stock army, off (16 games)", "games": 16, "W": 0, "L": 1, "w": 7, "l": 8, "inc20": 0.8, "verdict": "Baseline arm. Won 0 lost 1, at time ahead 7 behind 8, income x0.80."} -->
# ra2: raid answer under stock army, off (16 games)

- **Date:** 2026-11-16
- **Topic:** row114
- **Purpose:** Row 114 A/B follow-up, arm OFF (apex_raid_answer_stock 0 = v0.5.14 code) vs v0.5.14, 2v2 20 min, Red Comet + Carrot Mountains, both factions, seeds 9803-9806, paired with the ON arm.
- **Result:** 16 games: won 0, lost 1, timeouts ahead 7, behind 8; income at 20 min x0.80 ours/theirs
- **Verdict:** Baseline arm. Won 0 lost 1, at time ahead 7 behind 8, income x0.80.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.14-standard
- **Code:** Apex-v0.5.14-standard = `363c70a0a5+1bb8e5b07c76` (16 games); Apexestall-lane-estall-standard = `6fc9a74aef+246f4b91b37d` (16 games)
- **Maps:** Carrot Mountains v2.0, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 20 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.14:standard --per-side 2 --map Carrot Mountains v2.0 --minutes 20 --speed 20 --handicap 50 --sides Armada,Armada --seed 9803 --ai-option apex_raid_answer_stock=0 --out matches/ra2-v0-cm2-A9803`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Carrot Mountains v2.0 | Armada | 9803 | 0 | l | 20.0 | x0.75 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v0-cm2-A9803` |
| 1 | Carrot Mountains v2.0 | Armada | 9804 | 0 | l | 20.0 | x0.78 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v0-cm2-A9804` |
| 2 | Carrot Mountains v2.0 | Armada | 9805 | 0 | w | 20.0 | x2.99 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v0-cm2-A9805` |
| 3 | Carrot Mountains v2.0 | Armada | 9806 | 0 | l | 20.0 | x0.23 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v0-cm2-A9806` |
| 4 | Carrot Mountains v2.0 | Cortex | 9803 | 0 | l | 20.0 | x0.47 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v0-cm2-C9803` |
| 5 | Carrot Mountains v2.0 | Cortex | 9804 | 0 | w | 20.0 | x1.03 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v0-cm2-C9804` |
| 6 | Carrot Mountains v2.0 | Cortex | 9805 | 0 | l | 20.0 | x0.50 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v0-cm2-C9805` |
| 7 | Carrot Mountains v2.0 | Cortex | 9806 | 0 | w | 20.0 | x1.06 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v0-cm2-C9806` |
| 8 | Red Comet Remake 1.8 | Armada | 9803 | 0 | w | 20.0 | x1.81 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v0-rc2-A9803` |
| 9 | Red Comet Remake 1.8 | Armada | 9804 | 0 | w | 20.0 | x1.86 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v0-rc2-A9804` |
| 10 | Red Comet Remake 1.8 | Armada | 9805 | 0 | L | 7.52 | - | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v0-rc2-A9805` |
| 11 | Red Comet Remake 1.8 | Armada | 9806 | 0 | w | 20.0 | x3.16 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v0-rc2-A9806` |
| 12 | Red Comet Remake 1.8 | Cortex | 9803 | 0 | l | 20.0 | x0.67 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v0-rc2-C9803` |
| 13 | Red Comet Remake 1.8 | Cortex | 9804 | 0 | l | 20.0 | x0.11 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v0-rc2-C9804` |
| 14 | Red Comet Remake 1.8 | Cortex | 9805 | 0 | l | 20.0 | x0.31 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v0-rc2-C9805` |
| 15 | Red Comet Remake 1.8 | Cortex | 9806 | 0 | w | 20.0 | x1.29 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v0-rc2-C9806` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.67 | 2.96 | - | ok |
| t2->4th moho (min) | 4.99 | 5.47 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.30 | 0.32 | 0.00 | ok, short of aim |
| adv plant frame x | 1.77 | 2.71 | 1.50 | ok, short of aim |
| near-done /10k built | 0.72 | 0.99 | 0.00 | ok, short of aim |
| t2 cons given early | 0.03 | 0.06 | 0.00 | ok, short of aim |
| supers before 4 moho | 1.10 | 1.93 | 0.00 | ok, short of aim |
| lone t2 con minutes | 0.69 | 0.22 | 0.00 | ok, short of aim |
| base lost while 'covered' k | 1.60 | 1.08 | 0.00 | ok, short of aim |
| oldest plant order min | 2.19 | 1.98 | - | ok |
| no t2 by minute 20 | 0.00 | - | - | n/a |
| frozen minutes | 0.00 | 0.06 | 0.00 | ok |
| raid answer army share | - | - | - | n/a |
| bare-hands minutes | 0.12 | 0.25 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.34 | 0.40 | 0.00 | ok, short of aim |
| runs turned back | 0.00 | 0.00 | 0.00 | ok |
| gunships sent to lose | 0.00 | 0.00 | 0.00 | ok |
| stacked radar/jammers | 0.00 | 0.00 | 0.00 | ok |
| army stuck /10min/1k army | 4.98 | 6.75 | 0.00 | ok, short of aim |
| ground given up share | 0.18 | 0.14 | 0.00 | ok, short of aim |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.15 | -1.11 | - | ok |
| army share (neg) | 0.38 | 0.41 | - | ok |
| -log income at 20 | -4.82 | - | - | n/a |
| games won or ahead | 0.50 | 0.50 | - | ok |

Contract: **PASS** over 16 games (32 of our seats, 32 release seats); 12 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.14 (run `python tools/anomaly.py build`)
```
