<!-- meta {"date": "2026-11-15", "topic": "v0512", "title": "esc1: pkg3 + priced bomber escort (apex_air_escort_priced=1)", "games": 12, "W": 2, "L": 1, "w": 3, "l": 6, "inc20": 1.23, "verdict": "contract FAIL: wiped runs 2.00 vs 1.33, T2->1st moho 4.20 vs 3.65; ahead 0.50; stays off"} -->
# esc1: pkg3 + priced bomber escort (apex_air_escort_priced=1)

- **Date:** 2026-11-15
- **Topic:** v0512
- **Purpose:** Escort sized against the fighters met (his 11-14: ~100 of 400 fighters intercept each run)
- **Result:** 12 games: won 2, lost 1, timeouts ahead 3, behind 6; income at 20 min x1.23 ours/theirs
- **Verdict:** contract FAIL: wiped runs 2.00 vs 1.33, T2->1st moho 4.20 vs 3.65; ahead 0.50; stays off
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.11-standard
- **Code:** Apex-v0.5.11-standard = `v0.5.11` (12 games); Apexestall-lane-estall-standard = `c494a6f08c+970b63b06949` (12 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.11:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9503 --ai-option apex_air_escort_priced=1 --out matches/esc1-v1-cc-A9503`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9503 | 0 | l | 30.0 | x0.40 | c494a6f08c+970b63b06949, v0.5.11 | `matches/esc1-v1-cc-A9503` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9506 | 0 | l | 30.0 | x1.39 | c494a6f08c+970b63b06949, v0.5.11 | `matches/esc1-v1-cc-A9506` |
| 2 | Comet Catcher Remake 1.8 | Cortex | 9503 | 0 | l | 30.0 | x0.62 | c494a6f08c+970b63b06949, v0.5.11 | `matches/esc1-v1-cc-C9503` |
| 3 | Comet Catcher Remake 1.8 | Cortex | 9506 | 0 | l | 30.0 | x0.72 | c494a6f08c+970b63b06949, v0.5.11 | `matches/esc1-v1-cc-C9506` |
| 4 | Carrot Mountains v2.0 | Armada | 9502 | 0 | l | 30.0 | x1.02 | c494a6f08c+970b63b06949, v0.5.11 | `matches/esc1-v1-cm-A9502` |
| 5 | Carrot Mountains v2.0 | Armada | 9505 | 0 | w | 30.0 | x1.32 | c494a6f08c+970b63b06949, v0.5.11 | `matches/esc1-v1-cm-A9505` |
| 6 | Carrot Mountains v2.0 | Cortex | 9502 | 0 | l | 30.0 | x0.72 | c494a6f08c+970b63b06949, v0.5.11 | `matches/esc1-v1-cm-C9502` |
| 7 | Carrot Mountains v2.0 | Cortex | 9505 | 0 | w | 30.0 | x0.79 | c494a6f08c+970b63b06949, v0.5.11 | `matches/esc1-v1-cm-C9505` |
| 8 | Red Comet Remake 1.8 | Armada | 9501 | 0 | W | 21.9 | x13.25 | c494a6f08c+970b63b06949, v0.5.11 | `matches/esc1-v1-rc-A9501` |
| 9 | Red Comet Remake 1.8 | Armada | 9504 | 0 | w | 30.0 | x1.13 | c494a6f08c+970b63b06949, v0.5.11 | `matches/esc1-v1-rc-A9504` |
| 10 | Red Comet Remake 1.8 | Cortex | 9501 | 0 | W | 27.86 | x3.37 | c494a6f08c+970b63b06949, v0.5.11 | `matches/esc1-v1-rc-C9501` |
| 11 | Red Comet Remake 1.8 | Cortex | 9504 | 0 | L | 12.1 | - | c494a6f08c+970b63b06949, v0.5.11 | `matches/esc1-v1-rc-C9504` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 4.20 | 3.65 | - | FAIL (worse than release) |
| t2->4th moho (min) | 8.27 | 7.92 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.32 | 0.47 | 0.00 | ok, short of aim |
| adv plant frame x | 1.81 | 2.12 | 1.50 | ok, short of aim |
| near-done strips | 6.25 | 89.08 | 0.00 | ok, short of aim |
| t2 cons given early | 0.00 | 0.38 | 0.00 | ok |
| lone t2 con minutes | 1.00 | 1.39 | 0.00 | ok, short of aim |
| frozen minutes | 0.08 | 0.17 | 0.00 | ok, short of aim |
| bare-hands minutes | 0.17 | 0.17 | 0.00 | ok, short of aim |
| wiped bomber runs | 2.00 | 1.33 | 0.00 | FAIL (worse than release) |
| runs turned back | 1.00 | - | 0.00 | n/a |
| anomalous seats | 0.08 | 0.12 | 0.00 | ok, short of aim |
| peak constructors | 68.50 | 68.00 | - | ok |
| army share (neg) | 0.34 | 0.34 | - | ok |
| games won or ahead | 0.50 | 0.50 | - | ok |

Contract: **FAIL (2)** over 12 games (24 of our seats, 24 release seats); 9 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomalies: 2 seat(s) of 24 outside 5 robust deviations of v0.5.11's normal
  esc1-v1-cm-C9505 t0 lane-estall: 10m T2 share 35% (normal 0%, z +7); 15m T2 share 56% (normal 16%, z +7)
  esc1-v1-cc-A9503 t0 lane-estall: 30m constructors 0 (normal 62, z -6); 30m T2 share 0% (normal 56%, z -6)
```
