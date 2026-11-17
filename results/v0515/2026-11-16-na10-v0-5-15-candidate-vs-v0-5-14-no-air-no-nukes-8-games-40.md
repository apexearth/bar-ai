<!-- meta {"date": "2026-11-16", "topic": "v0515", "title": "na10: v0.5.15 candidate vs v0.5.14, no air, no nukes, 8 games, 40 min", "games": 8, "W": 2, "L": 1, "w": 1, "l": 4, "inc20": 1.2, "verdict": "contract PASS: won or ahead 4 of 8 (0.50); bare-hands minutes 0.12 vs 0.62, t2->4th moho 4.6 vs 6.6 min, base lost while covered 5.0k vs 7.1k. Red Comet 3 of 4, Carrot Mountains 1 of 4."} -->
# na10: v0.5.15 candidate vs v0.5.14, no air, no nukes, 8 games, 40 min

- **Date:** 2026-11-16
- **Topic:** v0515
- **Purpose:** Second half of the v0.5.15 gate: ground-only games where the raid answer and pushes decide more.
- **Result:** 8 games: won 2, lost 1, timeouts ahead 1, behind 4; income at 20 min x1.20 ours/theirs
- **Verdict:** contract PASS: won or ahead 4 of 8 (0.50); bare-hands minutes 0.12 vs 0.62, t2->4th moho 4.6 vs 6.6 min, base lost while covered 5.0k vs 7.1k. Red Comet 3 of 4, Carrot Mountains 1 of 4.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.14-standard
- **Code:** Apex-v0.5.14-standard = `363c70a0a5+1bb8e5b07c76` (8 games); Apexestall-lane-estall-standard = `6fc9a74aef+f62d5251e625` (8 games)
- **Maps:** Carrot Mountains v2.0, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 40 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.14:standard --per-side 2 --map Carrot Mountains v2.0 --minutes 40 --speed 20 --handicap 50 --sides Armada,Armada --seed 9902 --modoption unit_restrictions_noair=1 --modoption unit_restrictions_nonukes=1 --out matches/na10-v0-cm2-A9902`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Carrot Mountains v2.0 | Armada | 9902 | 0 | l | 40.0 | x0.83 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/na10-v0-cm2-A9902` |
| 1 | Carrot Mountains v2.0 | Armada | 9904 | 0 | l | 40.0 | x1.32 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/na10-v0-cm2-A9904` |
| 2 | Carrot Mountains v2.0 | Cortex | 9902 | 0 | l | 40.0 | x0.72 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/na10-v0-cm2-C9902` |
| 3 | Carrot Mountains v2.0 | Cortex | 9904 | 0 | l | 40.0 | x0.85 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/na10-v0-cm2-C9904` |
| 4 | Red Comet Remake 1.8 | Armada | 9901 | 0 | W | 26.03 | x3.85 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/na10-v0-rc2-A9901` |
| 5 | Red Comet Remake 1.8 | Armada | 9903 | 0 | W | 30.11 | x1.78 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/na10-v0-rc2-A9903` |
| 6 | Red Comet Remake 1.8 | Cortex | 9901 | 0 | w | 40.0 | x1.56 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/na10-v0-rc2-C9901` |
| 7 | Red Comet Remake 1.8 | Cortex | 9903 | 0 | L | 35.22 | x0.60 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/na10-v0-rc2-C9903` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.45 | 3.54 | - | ok |
| t2->4th moho (min) | 4.64 | 6.57 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.71 | 0.70 | 0.00 | ok, short of aim |
| adv plant frame x | 1.63 | 2.10 | 1.50 | ok, short of aim |
| near-done /10k built | 0.23 | 0.25 | 0.00 | ok, short of aim |
| t2 cons given early | 0.00 | 0.12 | 0.00 | ok |
| supers before 4 moho | 0.81 | 0.69 | 0.00 | ok, short of aim |
| lone t2 con minutes | 0.25 | 0.12 | 0.00 | ok, short of aim |
| base lost while 'covered' k | 5.00 | 7.10 | 0.00 | ok, short of aim |
| oldest plant order min | 3.45 | 4.04 | - | ok |
| no t2 by minute 20 | 0.00 | 0.06 | - | ok |
| frozen minutes | 0.12 | 0.25 | 0.00 | ok, short of aim |
| raid answer army share | 0.20 | - | - | n/a |
| bare-hands minutes | 0.12 | 0.62 | 0.00 | ok, short of aim |
| wiped bomber runs | - | - | 0.00 | n/a |
| runs turned back | - | - | 0.00 | n/a |
| gunships sent to lose | - | - | 0.00 | n/a |
| stacked radar/jammers | 0.00 | 0.06 | 0.00 | ok |
| army stuck /10min/1k army | 1.42 | 1.64 | 0.00 | ok, short of aim |
| ground given up share | 0.27 | 0.26 | 0.00 | ok, short of aim |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.74 | -1.77 | - | ok |
| army share (neg) | 0.48 | 0.49 | - | ok |
| -log income at 20 | -5.21 | -5.05 | - | ok |
| games won or ahead | 0.50 | 0.50 | - | ok |

Contract: **PASS** over 8 games (16 of our seats, 16 release seats); 11 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.14 (run `python tools/anomaly.py build`)
```
