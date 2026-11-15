<!-- meta {"date": "2026-11-15", "topic": "release-gate", "title": "v0.5.12 arm po0: bombers press-on off", "games": 12, "W": 0, "L": 3, "w": 5, "l": 4, "inc20": 0.68, "verdict": "worse than rc3 on the same seeds: contract FAIL, won or ahead 0.33 vs rc3 0.67; press-on stays on"} -->
# v0.5.12 arm po0: bombers press-on off

- **Date:** 2026-11-15
- **Topic:** release-gate
- **Purpose:** Does apex_air_press_on cause the pkg3->pkg4 income drop? rc3 code with apex_air_press_on=0, rc3's 12 2v2 seeds.
- **Result:** 12 games: won 0, lost 3, timeouts ahead 5, behind 4; income at 20 min x0.68 ours/theirs
- **Verdict:** worse than rc3 on the same seeds: contract FAIL, won or ahead 0.33 vs rc3 0.67; press-on stays on
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.11-standard
- **Code:** Apex-v0.5.11-standard = `v0.5.11` (12 games); Apexestall-lane-estall-standard = `c494a6f08c+98de158b5ddc` (12 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.11:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9503 --ai-option apex_air_press_on=0 --out matches/po0-v0-cc2-A9503`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9503 | 0 | l | 30.0 | x0.37 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/po0-v0-cc2-A9503` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9506 | 0 | l | 30.0 | x0.85 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/po0-v0-cc2-A9506` |
| 2 | Comet Catcher Remake 1.8 | Cortex | 9503 | 0 | w | 30.0 | x2.20 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/po0-v0-cc2-C9503` |
| 3 | Comet Catcher Remake 1.8 | Cortex | 9506 | 0 | w | 30.0 | x0.85 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/po0-v0-cc2-C9506` |
| 4 | Carrot Mountains v2.0 | Armada | 9502 | 0 | l | 30.0 | x0.59 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/po0-v0-cm2-A9502` |
| 5 | Carrot Mountains v2.0 | Armada | 9505 | 0 | w | 30.0 | x1.78 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/po0-v0-cm2-A9505` |
| 6 | Carrot Mountains v2.0 | Cortex | 9502 | 0 | l | 30.0 | x0.63 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/po0-v0-cm2-C9502` |
| 7 | Carrot Mountains v2.0 | Cortex | 9505 | 0 | w | 30.0 | x0.96 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/po0-v0-cm2-C9505` |
| 8 | Red Comet Remake 1.8 | Armada | 9501 | 0 | L | 16.18 | - | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/po0-v0-rc2-A9501` |
| 9 | Red Comet Remake 1.8 | Armada | 9504 | 0 | L | 23.95 | x0.10 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/po0-v0-rc2-A9504` |
| 10 | Red Comet Remake 1.8 | Cortex | 9501 | 0 | w | 30.0 | x1.26 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/po0-v0-rc2-C9501` |
| 11 | Red Comet Remake 1.8 | Cortex | 9504 | 0 | L | 27.93 | x0.28 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/po0-v0-rc2-C9504` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 3.57 | 3.22 | - | ok |
| t2->4th moho (min) | 6.35 | 6.73 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.36 | 0.49 | 0.00 | ok, short of aim |
| adv plant frame x | 2.35 | 2.14 | 1.50 | ok, short of aim |
| near-done strips | 6.42 | 91.58 | 0.00 | ok, short of aim |
| t2 cons given early | 0.00 | 0.46 | 0.00 | ok |
| supers before 4 moho | 1.18 | 2.50 | 0.00 | ok, short of aim |
| lone t2 con minutes | 1.55 | 1.00 | 0.00 | ok, short of aim |
| oldest plant order min | - | - | - | n/a |
| no t2 by minute 20 | 0.09 | 0.00 | - | ok |
| frozen minutes | 0.50 | 0.08 | 0.00 | ok, short of aim |
| bare-hands minutes | 0.92 | 0.00 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.40 | 0.43 | 0.00 | ok, short of aim |
| runs turned back | 0.45 | - | 0.00 | n/a |
| anomalous seats | 0.12 | 0.08 | 0.00 | ok, short of aim |
| peak constructors | 85.92 | 87.75 | - | ok |
| army share (neg) | 0.38 | 0.34 | - | ok |
| -log income at 20 | -4.78 | -4.84 | - | ok |
| games won or ahead | 0.33 | 0.50 | - | FAIL (does not beat the release) |

Contract: **FAIL (1)** over 12 games (24 of our seats, 24 release seats); 10 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomalies: 3 seat(s) of 24 outside 5 robust deviations of v0.5.11's normal
  po0-v0-rc2-C9504 t0 lane-estall: 25m constructors 0 (normal 47, z -8)
  po0-v0-rc2-A9501 t1 lane-estall: 15m constructors 0 (normal 27, z -7); 10m constructors 0 (normal 19, z -6); 15m army share 64% (normal 38%, z +5)
  po0-v0-rc2-C9504 t1 lane-estall: t2 minute 21.5 (normal 11.4, z +6)
```
