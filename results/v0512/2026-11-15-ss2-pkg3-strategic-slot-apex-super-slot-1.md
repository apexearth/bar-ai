<!-- meta {"date": "2026-11-15", "topic": "v0512", "title": "ss2: pkg3 + strategic slot (apex_super_slot=1)", "games": 12, "W": 2, "L": 0, "w": 5, "l": 5, "inc20": 1.0, "verdict": "contract PASS, ahead 0.67 (8 of 12), T2->1st moho 4.18 vs 4.89; super_slot becomes the default"} -->
# ss2: pkg3 + strategic slot (apex_super_slot=1)

- **Date:** 2026-11-15
- **Topic:** v0512
- **Purpose:** Bisect of the early-economy regression: the strategic slot restored
- **Result:** 12 games: won 2, lost 0, timeouts ahead 5, behind 5; income at 20 min x1.00 ours/theirs
- **Verdict:** contract PASS, ahead 0.67 (8 of 12), T2->1st moho 4.18 vs 4.89; super_slot becomes the default
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.11-standard
- **Code:** Apex-v0.5.11-standard = `v0.5.11` (12 games); Apexestall-lane-estall-standard = `c494a6f08c+970b63b06949` (12 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.11:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9503 --ai-option apex_super_slot=1 --out matches/ss2-v1-cc-A9503`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9503 | 0 | w | 30.0 | x1.17 | c494a6f08c+970b63b06949, v0.5.11 | `matches/ss2-v1-cc-A9503` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9506 | 0 | l | 30.0 | x0.97 | c494a6f08c+970b63b06949, v0.5.11 | `matches/ss2-v1-cc-A9506` |
| 2 | Comet Catcher Remake 1.8 | Cortex | 9503 | 0 | w | 30.0 | x1.27 | c494a6f08c+970b63b06949, v0.5.11 | `matches/ss2-v1-cc-C9503` |
| 3 | Comet Catcher Remake 1.8 | Cortex | 9506 | 0 | l | 30.0 | x0.60 | c494a6f08c+970b63b06949, v0.5.11 | `matches/ss2-v1-cc-C9506` |
| 4 | Carrot Mountains v2.0 | Armada | 9502 | 0 | w | 30.0 | x0.93 | c494a6f08c+970b63b06949, v0.5.11 | `matches/ss2-v1-cm-A9502` |
| 5 | Carrot Mountains v2.0 | Armada | 9505 | 0 | l | 30.0 | x0.43 | c494a6f08c+970b63b06949, v0.5.11 | `matches/ss2-v1-cm-A9505` |
| 6 | Carrot Mountains v2.0 | Cortex | 9502 | 0 | l | 30.0 | x0.72 | c494a6f08c+970b63b06949, v0.5.11 | `matches/ss2-v1-cm-C9502` |
| 7 | Carrot Mountains v2.0 | Cortex | 9505 | 0 | l | 30.0 | x0.77 | c494a6f08c+970b63b06949, v0.5.11 | `matches/ss2-v1-cm-C9505` |
| 8 | Red Comet Remake 1.8 | Armada | 9501 | 0 | W | 29.41 | x2.84 | c494a6f08c+970b63b06949, v0.5.11 | `matches/ss2-v1-rc-A9501` |
| 9 | Red Comet Remake 1.8 | Armada | 9504 | 0 | W | 27.94 | x2.29 | c494a6f08c+970b63b06949, v0.5.11 | `matches/ss2-v1-rc-A9504` |
| 10 | Red Comet Remake 1.8 | Cortex | 9501 | 0 | w | 30.0 | x0.87 | c494a6f08c+970b63b06949, v0.5.11 | `matches/ss2-v1-rc-C9501` |
| 11 | Red Comet Remake 1.8 | Cortex | 9504 | 0 | w | 30.0 | x0.89 | c494a6f08c+970b63b06949, v0.5.11 | `matches/ss2-v1-rc-C9504` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 4.18 | 4.89 | - | ok |
| t2->4th moho (min) | 9.01 | 8.31 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.35 | 0.47 | 0.00 | ok, short of aim |
| adv plant frame x | 2.43 | 2.21 | 1.50 | ok, short of aim |
| near-done strips | 6.88 | 93.54 | 0.00 | ok, short of aim |
| t2 cons given early | 0.00 | 0.42 | 0.00 | ok |
| lone t2 con minutes | 1.22 | 1.74 | 0.00 | ok, short of aim |
| frozen minutes | 0.50 | 0.92 | 0.00 | ok, short of aim |
| bare-hands minutes | 0.50 | 0.50 | 0.00 | ok, short of aim |
| wiped bomber runs | 1.46 | 1.79 | 0.00 | ok, short of aim |
| runs turned back | 0.41 | - | 0.00 | n/a |
| anomalous seats | 0.12 | 0.12 | 0.00 | ok, short of aim |
| peak constructors | 65.50 | 64.00 | - | ok |
| army share (neg) | 0.35 | 0.35 | - | ok |
| games won or ahead | 0.67 | 0.50 | - | ok |

Contract: **PASS** over 12 games (24 of our seats, 24 release seats); 9 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomalies: 3 seat(s) of 24 outside 5 robust deviations of v0.5.11's normal
  ss2-v1-cm-A9505 t1 lane-estall: 25m constructors 0 (normal 60, z -8)
  ss2-v1-cm-C9502 t0 lane-estall: 30m T2 share 0% (normal 56%, z -7); 20m constructors 1 (normal 48, z -6); 30m constructors 2 (normal 77, z -6); 25m constructors 3 (normal 58, z -5)
  ss2-v1-cc-C9506 t0 lane-estall: 30m constructors 1 (normal 77, z -6)
```
