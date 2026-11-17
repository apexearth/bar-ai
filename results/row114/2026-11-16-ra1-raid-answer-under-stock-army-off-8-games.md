<!-- meta {"date": "2026-11-16", "topic": "row114", "title": "ra1: raid answer under stock army, off (8 games)", "games": 8, "W": 1, "L": 1, "w": 2, "l": 4, "inc20": 0.84, "verdict": "Baseline arm. Won 1 lost 1, at time ahead 2 behind 4. Our structures lost on our half by minute 10: 1.97k a game; kill minus lost -10.5k."} -->
# ra1: raid answer under stock army, off (8 games)

- **Date:** 2026-11-16
- **Topic:** row114
- **Purpose:** Row 114 A/B, arm OFF: lane estall = v0.5.14 code, apex_raid_answer_stock 0, vs v0.5.14, 2v2 20 min, Red Comet + Carrot Mountains, both factions, seeds 9801-9802 (paired with the ON arm).
- **Result:** 8 games: won 1, lost 1, timeouts ahead 2, behind 4; income at 20 min x0.84 ours/theirs
- **Verdict:** Baseline arm. Won 1 lost 1, at time ahead 2 behind 4. Our structures lost on our half by minute 10: 1.97k a game; kill minus lost -10.5k.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.14-standard
- **Code:** Apex-v0.5.14-standard = `363c70a0a5+1bb8e5b07c76` (8 games); Apexestall-lane-estall-standard = `6fc9a74aef+246f4b91b37d` (8 games)
- **Maps:** Carrot Mountains v2.0, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 20 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.14:standard --per-side 2 --map Carrot Mountains v2.0 --minutes 20 --speed 20 --handicap 50 --sides Armada,Armada --seed 9801 --ai-option apex_raid_answer_stock=0 --out matches/ra1-v0-cm2-A9801`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Carrot Mountains v2.0 | Armada | 9801 | 0 | l | 20.0 | x0.83 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra1-v0-cm2-A9801` |
| 1 | Carrot Mountains v2.0 | Armada | 9802 | 0 | l | 20.0 | x0.47 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra1-v0-cm2-A9802` |
| 2 | Carrot Mountains v2.0 | Cortex | 9801 | 0 | l | 20.0 | x0.86 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra1-v0-cm2-C9801` |
| 3 | Carrot Mountains v2.0 | Cortex | 9802 | 0 | w | 20.0 | x1.17 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra1-v0-cm2-C9802` |
| 4 | Red Comet Remake 1.8 | Armada | 9801 | 0 | l | 20.0 | x0.76 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra1-v0-rc2-A9801` |
| 5 | Red Comet Remake 1.8 | Armada | 9802 | 0 | W | 10.65 | - | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra1-v0-rc2-A9802` |
| 6 | Red Comet Remake 1.8 | Cortex | 9801 | 0 | w | 20.0 | x1.22 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra1-v0-rc2-C9801` |
| 7 | Red Comet Remake 1.8 | Cortex | 9802 | 0 | L | 11.85 | - | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra1-v0-rc2-C9802` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.60 | 2.22 | - | ok |
| t2->4th moho (min) | 5.51 | 5.04 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.33 | 0.29 | 0.00 | ok, short of aim |
| adv plant frame x | 2.68 | 2.07 | 1.50 | FAIL (worse than release) |
| near-done /10k built | 0.71 | 0.37 | 0.00 | FAIL (worse than release) |
| t2 cons given early | 0.00 | 0.00 | 0.00 | ok |
| supers before 4 moho | 2.33 | 1.58 | 0.00 | FAIL (worse than release) |
| lone t2 con minutes | 0.67 | 0.00 | 0.00 | ok, short of aim |
| base lost while 'covered' k | 0.93 | 0.79 | 0.00 | ok, short of aim |
| oldest plant order min | 1.89 | 1.87 | - | ok |
| no t2 by minute 20 | 0.00 | - | - | n/a |
| frozen minutes | 0.00 | 0.00 | 0.00 | ok |
| bare-hands minutes | 0.00 | 0.00 | 0.00 | ok |
| wiped bomber runs | 0.11 | 0.36 | 0.00 | ok, short of aim |
| runs turned back | 0.00 | 0.00 | 0.00 | ok |
| gunships sent to lose | 0.00 | 0.00 | 0.00 | ok |
| stacked radar/jammers | 0.00 | 0.00 | 0.00 | ok |
| army stuck /10min/1k army | 6.63 | 6.08 | 0.00 | ok, short of aim |
| ground given up share | 0.13 | 0.11 | 0.00 | ok, short of aim |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.19 | -1.00 | - | ok |
| army share (neg) | 0.39 | 0.41 | - | ok |
| -log income at 20 | -4.85 | - | - | n/a |
| games won or ahead | 0.75 | 0.50 | - | ok |

Contract: **FAIL (3)** over 8 games (16 of our seats, 16 release seats); 10 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.14 (run `python tools/anomaly.py build`)
```
