<!-- meta {"date": "2026-11-15", "topic": "v0512", "title": "wr1: pkg4 + apex_wing_rule=1 (the net may not flip the bomber rule's WAIT)", "games": 12, "W": 3, "L": 0, "w": 4, "l": 5, "inc20": 1.07, "verdict": "contract PASS; 3 games won vs pkg4's 0 (1 lost), ahead 0.50; bomber kill per bomber lost 143 vs pkg4's 221; inconclusive, stays off"} -->
# wr1: pkg4 + apex_wing_rule=1 (the net may not flip the bomber rule's WAIT)

- **Date:** 2026-11-15
- **Topic:** v0512
- **Purpose:** Bombers flown 1-3 at a time into fighters: the stale pg net flipped ~1/3 of the rule's WAITs to GO (2.8 bombers, 2% home)
- **Result:** 12 games: won 3, lost 0, timeouts ahead 4, behind 5; income at 20 min x1.07 ours/theirs
- **Verdict:** contract PASS; 3 games won vs pkg4's 0 (1 lost), ahead 0.50; bomber kill per bomber lost 143 vs pkg4's 221; inconclusive, stays off
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.11-standard
- **Code:** Apex-v0.5.11-standard = `v0.5.11` (12 games); Apexestall-lane-estall-standard = `c494a6f08c+21df3f03f13f` (12 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.11:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9503 --ai-option apex_wing_rule=1 --out matches/wr1-v1-cc-A9503`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9503 | 0 | W | 23.65 | x8.55 | c494a6f08c+21df3f03f13f, v0.5.11 | `matches/wr1-v1-cc-A9503` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9506 | 0 | W | 11.25 | - | c494a6f08c+21df3f03f13f, v0.5.11 | `matches/wr1-v1-cc-A9506` |
| 2 | Comet Catcher Remake 1.8 | Cortex | 9503 | 0 | l | 30.0 | x0.80 | c494a6f08c+21df3f03f13f, v0.5.11 | `matches/wr1-v1-cc-C9503` |
| 3 | Comet Catcher Remake 1.8 | Cortex | 9506 | 0 | l | 30.0 | x0.85 | c494a6f08c+21df3f03f13f, v0.5.11 | `matches/wr1-v1-cc-C9506` |
| 4 | Carrot Mountains v2.0 | Armada | 9502 | 0 | w | 30.0 | x1.20 | c494a6f08c+21df3f03f13f, v0.5.11 | `matches/wr1-v1-cm-A9502` |
| 5 | Carrot Mountains v2.0 | Armada | 9505 | 0 | l | 30.0 | x0.40 | c494a6f08c+21df3f03f13f, v0.5.11 | `matches/wr1-v1-cm-A9505` |
| 6 | Carrot Mountains v2.0 | Cortex | 9502 | 0 | W | 25.18 | x0.83 | c494a6f08c+21df3f03f13f, v0.5.11 | `matches/wr1-v1-cm-C9502` |
| 7 | Carrot Mountains v2.0 | Cortex | 9505 | 0 | w | 30.0 | x1.11 | c494a6f08c+21df3f03f13f, v0.5.11 | `matches/wr1-v1-cm-C9505` |
| 8 | Red Comet Remake 1.8 | Armada | 9501 | 0 | w | 30.0 | x1.07 | c494a6f08c+21df3f03f13f, v0.5.11 | `matches/wr1-v1-rc-A9501` |
| 9 | Red Comet Remake 1.8 | Armada | 9504 | 0 | w | 30.0 | x1.24 | c494a6f08c+21df3f03f13f, v0.5.11 | `matches/wr1-v1-rc-A9504` |
| 10 | Red Comet Remake 1.8 | Cortex | 9501 | 0 | l | 30.0 | x0.93 | c494a6f08c+21df3f03f13f, v0.5.11 | `matches/wr1-v1-rc-C9501` |
| 11 | Red Comet Remake 1.8 | Cortex | 9504 | 0 | l | 30.0 | x0.64 | c494a6f08c+21df3f03f13f, v0.5.11 | `matches/wr1-v1-rc-C9504` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 4.23 | 3.91 | - | ok |
| t2->4th moho (min) | 7.99 | 7.89 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.30 | 0.38 | 0.00 | ok, short of aim |
| adv plant frame x | 2.26 | 2.16 | 1.50 | ok, short of aim |
| near-done strips | 8.38 | 78.08 | 0.00 | ok, short of aim |
| t2 cons given early | 0.04 | 0.21 | 0.00 | ok, short of aim |
| lone t2 con minutes | 0.64 | 1.09 | 0.00 | ok, short of aim |
| frozen minutes | 0.00 | 0.33 | 0.00 | ok |
| bare-hands minutes | 0.00 | 0.25 | 0.00 | ok |
| wiped bomber runs | 1.21 | 1.50 | 0.00 | ok, short of aim |
| runs turned back | 0.05 | - | 0.00 | n/a |
| anomalous seats | 0.04 | 0.12 | 0.00 | ok, short of aim |
| peak constructors | 47.00 | 67.00 | - | ok |
| army share (neg) | 0.34 | 0.32 | - | ok |
| games won or ahead | 0.50 | 0.50 | - | ok |

Contract: **PASS** over 12 games (24 of our seats, 24 release seats); 8 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomalies: 1 seat(s) of 24 outside 5 robust deviations of v0.5.11's normal
  wr1-v1-cm-A9505 t0 lane-estall: t2 minute 20.2 (normal 11.5, z +6); 10m army share 79% (normal 48%, z +5)
```
