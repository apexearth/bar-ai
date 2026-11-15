<!-- meta {"date": "2026-11-15", "topic": "v0512", "title": "rc1: candidate with apex_wing_rule on by default", "games": 12, "W": 1, "L": 0, "w": 4, "l": 7, "inc20": 0.97, "verdict": "contract FAIL: ahead 0.33, t2->4th moho 7.65 vs 6.58; with wr1, 24 games ahead 0.42: wing rule left off"} -->
# rc1: candidate with apex_wing_rule on by default

- **Date:** 2026-11-15
- **Topic:** v0512
- **Purpose:** Release candidate with the bomber rule's WAIT protected from the net (TUNE_WING_RULE=1)
- **Result:** 12 games: won 1, lost 0, timeouts ahead 4, behind 7; income at 20 min x0.97 ours/theirs
- **Verdict:** contract FAIL: ahead 0.33, t2->4th moho 7.65 vs 6.58; with wr1, 24 games ahead 0.42: wing rule left off
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.11-standard
- **Code:** Apex-v0.5.11-standard = `v0.5.11` (12 games); Apexestall-lane-estall-standard = `c494a6f08c+4d89a3427ef7` (12 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.11:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9503 --out matches/rc1-v0-cc-A9503`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9503 | 0 | w | 30.0 | x0.85 | c494a6f08c+4d89a3427ef7, v0.5.11 | `matches/rc1-v0-cc-A9503` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9506 | 0 | l | 30.0 | x0.63 | c494a6f08c+4d89a3427ef7, v0.5.11 | `matches/rc1-v0-cc-A9506` |
| 2 | Comet Catcher Remake 1.8 | Cortex | 9503 | 0 | w | 30.0 | x1.16 | c494a6f08c+4d89a3427ef7, v0.5.11 | `matches/rc1-v0-cc-C9503` |
| 3 | Comet Catcher Remake 1.8 | Cortex | 9506 | 0 | l | 30.0 | x0.94 | c494a6f08c+4d89a3427ef7, v0.5.11 | `matches/rc1-v0-cc-C9506` |
| 4 | Carrot Mountains v2.0 | Armada | 9502 | 0 | l | 30.0 | x0.99 | c494a6f08c+4d89a3427ef7, v0.5.11 | `matches/rc1-v0-cm-A9502` |
| 5 | Carrot Mountains v2.0 | Armada | 9505 | 0 | l | 30.0 | x0.50 | c494a6f08c+4d89a3427ef7, v0.5.11 | `matches/rc1-v0-cm-A9505` |
| 6 | Carrot Mountains v2.0 | Cortex | 9502 | 0 | w | 30.0 | x0.71 | c494a6f08c+4d89a3427ef7, v0.5.11 | `matches/rc1-v0-cm-C9502` |
| 7 | Carrot Mountains v2.0 | Cortex | 9505 | 0 | l | 30.0 | x0.77 | c494a6f08c+4d89a3427ef7, v0.5.11 | `matches/rc1-v0-cm-C9505` |
| 8 | Red Comet Remake 1.8 | Armada | 9501 | 0 | w | 30.0 | x1.47 | c494a6f08c+4d89a3427ef7, v0.5.11 | `matches/rc1-v0-rc-A9501` |
| 9 | Red Comet Remake 1.8 | Armada | 9504 | 0 | l | 30.0 | x0.83 | c494a6f08c+4d89a3427ef7, v0.5.11 | `matches/rc1-v0-rc-A9504` |
| 10 | Red Comet Remake 1.8 | Cortex | 9501 | 0 | l | 30.0 | x0.65 | c494a6f08c+4d89a3427ef7, v0.5.11 | `matches/rc1-v0-rc-C9501` |
| 11 | Red Comet Remake 1.8 | Cortex | 9504 | 0 | W | 24.35 | x5.21 | c494a6f08c+4d89a3427ef7, v0.5.11 | `matches/rc1-v0-rc-C9504` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.82 | 2.60 | - | ok |
| t2->4th moho (min) | 7.65 | 6.58 | 3.00 | FAIL (worse than release) |
| lab-job leaves/job | 0.39 | 0.37 | 0.00 | ok, short of aim |
| adv plant frame x | 2.27 | 2.76 | 1.50 | ok, short of aim |
| near-done strips | 7.96 | 102.83 | 0.00 | ok, short of aim |
| t2 cons given early | 0.00 | 0.38 | 0.00 | ok |
| lone t2 con minutes | 1.25 | 0.75 | 0.00 | ok, short of aim |
| no t2 by minute 20 | 0.00 | 0.00 | - | ok |
| frozen minutes | 0.08 | 0.08 | 0.00 | ok, short of aim |
| bare-hands minutes | 0.08 | 0.00 | 0.00 | ok, short of aim |
| wiped bomber runs | 1.21 | 1.67 | 0.00 | ok, short of aim |
| runs turned back | 0.00 | - | 0.00 | n/a |
| anomalous seats | 0.00 | 0.12 | 0.00 | ok |
| peak constructors | 63.50 | 85.00 | - | ok |
| army share (neg) | 0.34 | 0.28 | - | ok |
| games won or ahead | 0.33 | 0.50 | - | FAIL (does not beat the release) |

Contract: **FAIL (2)** over 12 games (24 of our seats, 24 release seats); 8 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomalies: 0 seat(s) of 24 outside 5 robust deviations of v0.5.11's normal
```
