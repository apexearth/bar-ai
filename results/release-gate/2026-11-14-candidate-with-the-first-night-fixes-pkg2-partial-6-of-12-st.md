<!-- meta {"date": "2026-11-14", "topic": "release-gate", "title": "Candidate with the first night fixes (pkg2, partial 6 of 12, stopped for a newer build)", "games": 6, "W": 0, "L": 1, "w": 3, "l": 2, "inc20": 1.1, "verdict": "Stopped at 6 games to deploy the second round (crew one number, keep on draw, press-on, nuke guess, bare-hands floor). Read the contract table below as a partial."} -->
# Candidate with the first night fixes (pkg2, partial 6 of 12, stopped for a newer build)

- **Date:** 2026-11-14
- **Topic:** release-gate
- **Purpose:** peel near-done, keep same job, gift own first, plant class/site odds, team front, metal log; vs v0.5.11, the package seeds.
- **Result:** 6 games: won 0, lost 1, timeouts ahead 3, behind 2; income at 20 min x1.10 ours/theirs
- **Verdict:** Stopped at 6 games to deploy the second round (crew one number, keep on draw, press-on, nuke guess, bare-hands floor). Read the contract table below as a partial.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.11-standard
- **Code:** Apex-v0.5.11-standard = `v0.5.11` (6 games); Apexestall-lane-estall-standard = `c494a6f08c+3cb93925ef0e` (6 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.11:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9503 --out matches/pkg2-v0-cc-A9503`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9503 | 0 | l | 30.0 | x0.76 | c494a6f08c+3cb93925ef0e, v0.5.11 | `matches/pkg2-v0-cc-A9503` |
| 1 | Comet Catcher Remake 1.8 | Cortex | 9503 | 0 | l | 30.0 | x0.90 | c494a6f08c+3cb93925ef0e, v0.5.11 | `matches/pkg2-v0-cc-C9503` |
| 2 | Carrot Mountains v2.0 | Armada | 9502 | 0 | w | 30.0 | x1.45 | c494a6f08c+3cb93925ef0e, v0.5.11 | `matches/pkg2-v0-cm-A9502` |
| 3 | Carrot Mountains v2.0 | Cortex | 9502 | 0 | w | 30.0 | x1.01 | c494a6f08c+3cb93925ef0e, v0.5.11 | `matches/pkg2-v0-cm-C9502` |
| 4 | Red Comet Remake 1.8 | Armada | 9501 | 0 | L | 20.07 | - | c494a6f08c+3cb93925ef0e, v0.5.11 | `matches/pkg2-v0-rc-A9501` |
| 5 | Red Comet Remake 1.8 | Cortex | 9501 | 0 | w | 30.0 | x1.63 | c494a6f08c+3cb93925ef0e, v0.5.11 | `matches/pkg2-v0-rc-C9501` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 4.70 | 4.18 | - | FAIL (worse than release) |
| t2->4th moho (min) | 8.15 | 8.56 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.92 | 0.93 | 0.00 | ok, short of aim |
| adv plant frame x | 4.89 | 4.25 | 1.50 | FAIL (worse than release) |
| near-done strips | 7.25 | 80.67 | 0.00 | ok, short of aim |
| t2 cons given early | 0.00 | 0.25 | 0.00 | ok |
| frozen minutes | 1.00 | 0.00 | 0.00 | ok, short of aim |
| bare-hands minutes | 1.00 | 0.00 | 0.00 | ok, short of aim |
| wiped bomber runs | 1.58 | 1.00 | 0.00 | FAIL (worse than release) |
| runs turned back | 0.00 | 0.00 | 0.00 | ok |
| anomalous seats | 0.08 | 0.00 | 0.00 | ok, short of aim |
| peak constructors | 52.50 | 73.50 | - | ok |
| army share (neg) | 0.38 | 0.33 | - | ok |
| games won or ahead | 0.50 | 0.50 | - | ok |

Contract: **FAIL (3)** over 6 games (12 of our seats, 12 release seats); 8 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomalies: 1 seat(s) of 12 outside 5 robust deviations of v0.5.11's normal
  pkg2-v0-rc-A9501 t1 lane-estall: 20m constructors 0 (normal 47, z -8); 15m constructors 0 (normal 34, z -7); 20m army share 62% (normal 36%, z +5); 20m units 26 (normal 339, z -5)
```
