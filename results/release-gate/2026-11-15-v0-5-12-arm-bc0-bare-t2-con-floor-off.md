<!-- meta {"date": "2026-11-15", "topic": "release-gate", "title": "v0.5.12 arm bc0: bare T2-con floor off", "games": 12, "W": 0, "L": 0, "w": 3, "l": 9, "inc20": 0.95, "verdict": "worse than rc3 on the same seeds: contract FAIL on income at 20 (median seat 105 vs 143), ahead 0.50 vs rc3 0.67; the floor stays on"} -->
# v0.5.12 arm bc0: bare T2-con floor off

- **Date:** 2026-11-15
- **Topic:** release-gate
- **Purpose:** Does apex_con_bare_ceiling cause the pkg3->pkg4 income drop? rc3 code with apex_con_bare_ceiling=0, rc3's 12 2v2 seeds (rc/cm/cc 9501-9506).
- **Result:** 12 games: won 0, lost 0, timeouts ahead 3, behind 9; income at 20 min x0.95 ours/theirs
- **Verdict:** worse than rc3 on the same seeds: contract FAIL on income at 20 (median seat 105 vs 143), ahead 0.50 vs rc3 0.67; the floor stays on
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.11-standard
- **Code:** Apex-v0.5.11-standard = `v0.5.11` (12 games); Apexestall-lane-estall-standard = `c494a6f08c+98de158b5ddc` (12 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.11:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9503 --ai-option apex_con_bare_ceiling=0 --out matches/bc0-v0-cc2-A9503`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9503 | 0 | l | 30.0 | x0.68 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/bc0-v0-cc2-A9503` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9506 | 0 | w | 30.0 | x4.34 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/bc0-v0-cc2-A9506` |
| 2 | Comet Catcher Remake 1.8 | Cortex | 9503 | 0 | l | 30.0 | x0.67 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/bc0-v0-cc2-C9503` |
| 3 | Comet Catcher Remake 1.8 | Cortex | 9506 | 0 | l | 30.0 | x0.97 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/bc0-v0-cc2-C9506` |
| 4 | Carrot Mountains v2.0 | Armada | 9502 | 0 | w | 30.0 | x0.96 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/bc0-v0-cm2-A9502` |
| 5 | Carrot Mountains v2.0 | Armada | 9505 | 0 | l | 30.0 | x0.99 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/bc0-v0-cm2-A9505` |
| 6 | Carrot Mountains v2.0 | Cortex | 9502 | 0 | l | 30.0 | x0.80 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/bc0-v0-cm2-C9502` |
| 7 | Carrot Mountains v2.0 | Cortex | 9505 | 0 | w | 30.0 | x1.31 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/bc0-v0-cm2-C9505` |
| 8 | Red Comet Remake 1.8 | Armada | 9501 | 0 | l | 30.0 | x1.02 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/bc0-v0-rc2-A9501` |
| 9 | Red Comet Remake 1.8 | Armada | 9504 | 0 | l | 30.0 | x0.34 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/bc0-v0-rc2-A9504` |
| 10 | Red Comet Remake 1.8 | Cortex | 9501 | 0 | l | 30.0 | x0.78 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/bc0-v0-rc2-C9501` |
| 11 | Red Comet Remake 1.8 | Cortex | 9504 | 0 | l | 30.0 | x0.99 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/bc0-v0-rc2-C9504` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.46 | 2.71 | - | ok |
| t2->4th moho (min) | 6.50 | 7.97 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.38 | 0.50 | 0.00 | ok, short of aim |
| adv plant frame x | 2.03 | 2.10 | 1.50 | ok, short of aim |
| near-done strips | 8.25 | 84.75 | 0.00 | ok, short of aim |
| t2 cons given early | 0.04 | 0.46 | 0.00 | ok, short of aim |
| supers before 4 moho | 1.22 | 1.54 | 0.00 | ok, short of aim |
| lone t2 con minutes | 0.52 | 0.83 | 0.00 | ok, short of aim |
| oldest plant order min | - | - | - | n/a |
| no t2 by minute 20 | 0.04 | 0.00 | - | ok |
| frozen minutes | 0.50 | 0.25 | 0.00 | ok, short of aim |
| bare-hands minutes | 0.75 | 0.33 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.51 | 0.53 | 0.00 | ok, short of aim |
| runs turned back | 0.00 | - | 0.00 | n/a |
| anomalous seats | 0.08 | 0.08 | 0.00 | ok, short of aim |
| peak constructors | 79.00 | 93.42 | - | ok |
| army share (neg) | 0.39 | 0.31 | - | ok |
| -log income at 20 | -4.65 | -4.96 | - | FAIL (worse than release) |
| games won or ahead | 0.50 | 0.50 | - | ok |

Contract: **FAIL (1)** over 12 games (24 of our seats, 24 release seats); 11 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomalies: 2 seat(s) of 24 outside 5 robust deviations of v0.5.11's normal
  bc0-v0-rc2-A9504 t0 lane-estall: 15m constructors 0 (normal 27, z -7); 20m constructors 1 (normal 39, z -6)
  bc0-v0-cc2-A9503 t0 lane-estall: 30m constructors 4 (normal 80, z -5)
```
