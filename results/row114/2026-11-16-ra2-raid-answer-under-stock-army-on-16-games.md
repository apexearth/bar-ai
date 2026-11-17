<!-- meta {"date": "2026-11-16", "topic": "row114", "title": "ra2: raid answer under stock army, on (16 games)", "games": 16, "W": 1, "L": 0, "w": 9, "l": 6, "inc20": 1.11, "verdict": "On is better. This batch: won 1 lost 0, ahead 9 behind 6 (off 0-1, 7-8); kill minus lost better in 13 of 16 pairs. Pooled ra1+ra2, 24 pairs: won or ahead 15 of 24 vs 10 of 24; kill minus lost +7.9k a game, better in 18 of 24 (sign test p~0.02); income at 20 277 vs 236; home structures lost by minute 20 17.6k vs 19.8k, but by minute 10 2.34k vs 1.91k (on better in 9 of 24). Contract PASS both arms. His 11-16 rule held: 112 answers, median 5% of the seat's army, max 31%."} -->
# ra2: raid answer under stock army, on (16 games)

- **Date:** 2026-11-16
- **Topic:** row114
- **Purpose:** Row 114 A/B follow-up, arm ON (apex_raid_answer_stock 1), otherwise identical to the OFF arm.
- **Result:** 16 games: won 1, lost 0, timeouts ahead 9, behind 6; income at 20 min x1.11 ours/theirs
- **Verdict:** On is better. This batch: won 1 lost 0, ahead 9 behind 6 (off 0-1, 7-8); kill minus lost better in 13 of 16 pairs. Pooled ra1+ra2, 24 pairs: won or ahead 15 of 24 vs 10 of 24; kill minus lost +7.9k a game, better in 18 of 24 (sign test p~0.02); income at 20 277 vs 236; home structures lost by minute 20 17.6k vs 19.8k, but by minute 10 2.34k vs 1.91k (on better in 9 of 24). Contract PASS both arms. His 11-16 rule held: 112 answers, median 5% of the seat's army, max 31%.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.14-standard
- **Code:** Apex-v0.5.14-standard = `363c70a0a5+1bb8e5b07c76` (16 games); Apexestall-lane-estall-standard = `6fc9a74aef+246f4b91b37d` (16 games)
- **Maps:** Carrot Mountains v2.0, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 20 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.14:standard --per-side 2 --map Carrot Mountains v2.0 --minutes 20 --speed 20 --handicap 50 --sides Armada,Armada --seed 9803 --ai-option apex_raid_answer_stock=1 --out matches/ra2-v1-cm2-A9803`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Carrot Mountains v2.0 | Armada | 9803 | 0 | w | 20.0 | x2.42 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v1-cm2-A9803` |
| 1 | Carrot Mountains v2.0 | Armada | 9804 | 0 | w | 20.0 | x1.00 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v1-cm2-A9804` |
| 2 | Carrot Mountains v2.0 | Armada | 9805 | 0 | l | 20.0 | x0.47 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v1-cm2-A9805` |
| 3 | Carrot Mountains v2.0 | Armada | 9806 | 0 | l | 20.0 | x0.23 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v1-cm2-A9806` |
| 4 | Carrot Mountains v2.0 | Cortex | 9803 | 0 | l | 20.0 | x0.90 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v1-cm2-C9803` |
| 5 | Carrot Mountains v2.0 | Cortex | 9804 | 0 | l | 20.0 | x0.74 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v1-cm2-C9804` |
| 6 | Carrot Mountains v2.0 | Cortex | 9805 | 0 | w | 20.0 | x1.68 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v1-cm2-C9805` |
| 7 | Carrot Mountains v2.0 | Cortex | 9806 | 0 | w | 20.0 | x4.41 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v1-cm2-C9806` |
| 8 | Red Comet Remake 1.8 | Armada | 9803 | 0 | w | 20.0 | x1.25 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v1-rc2-A9803` |
| 9 | Red Comet Remake 1.8 | Armada | 9804 | 0 | W | 18.22 | - | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v1-rc2-A9804` |
| 10 | Red Comet Remake 1.8 | Armada | 9805 | 0 | l | 20.0 | x0.72 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v1-rc2-A9805` |
| 11 | Red Comet Remake 1.8 | Armada | 9806 | 0 | w | 20.0 | x1.70 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v1-rc2-A9806` |
| 12 | Red Comet Remake 1.8 | Cortex | 9803 | 0 | w | 20.0 | x1.14 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v1-rc2-C9803` |
| 13 | Red Comet Remake 1.8 | Cortex | 9804 | 0 | l | 20.0 | x0.94 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v1-rc2-C9804` |
| 14 | Red Comet Remake 1.8 | Cortex | 9805 | 0 | w | 20.0 | x1.38 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v1-rc2-C9805` |
| 15 | Red Comet Remake 1.8 | Cortex | 9806 | 0 | w | 20.0 | x1.58 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra2-v1-rc2-C9806` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 3.34 | 2.61 | - | FAIL (worse than release) |
| t2->4th moho (min) | 6.23 | 5.66 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.33 | 0.41 | 0.00 | ok, short of aim |
| adv plant frame x | 2.23 | 2.08 | 1.50 | ok, short of aim |
| near-done /10k built | 0.41 | 0.51 | 0.00 | ok, short of aim |
| t2 cons given early | 0.00 | 0.00 | 0.00 | ok |
| supers before 4 moho | 1.22 | 1.61 | 0.00 | ok, short of aim |
| lone t2 con minutes | 0.44 | 0.93 | 0.00 | ok, short of aim |
| base lost while 'covered' k | 1.21 | 2.81 | 0.00 | ok, short of aim |
| oldest plant order min | 2.37 | 2.39 | - | ok |
| no t2 by minute 20 | 0.00 | - | - | n/a |
| frozen minutes | 0.31 | 0.38 | 0.00 | ok, short of aim |
| raid answer army share | 0.12 | - | - | n/a |
| bare-hands minutes | 0.19 | 0.12 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.39 | 0.39 | 0.00 | ok, short of aim |
| runs turned back | 0.03 | 0.00 | 0.00 | ok, short of aim |
| gunships sent to lose | 0.00 | 0.00 | 0.00 | ok |
| stacked radar/jammers | 0.00 | 0.03 | 0.00 | ok |
| army stuck /10min/1k army | 5.28 | 5.21 | 0.00 | ok, short of aim |
| ground given up share | 0.16 | 0.13 | 0.00 | ok, short of aim |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.15 | -1.17 | - | ok |
| army share (neg) | 0.39 | 0.39 | - | ok |
| -log income at 20 | -4.91 | - | - | n/a |
| games won or ahead | 0.81 | 0.50 | - | ok |

Contract: **FAIL (1)** over 16 games (32 of our seats, 32 release seats); 13 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.14 (run `python tools/anomaly.py build`)
```
