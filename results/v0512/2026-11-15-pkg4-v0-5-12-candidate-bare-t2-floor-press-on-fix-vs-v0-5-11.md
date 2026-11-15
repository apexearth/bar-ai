<!-- meta {"date": "2026-11-15", "topic": "v0512", "title": "pkg4: v0.5.12 candidate (bare T2 floor, press-on fix) vs v0.5.11", "games": 12, "W": 0, "L": 1, "w": 6, "l": 5, "inc20": 0.89, "verdict": "contract PASS (recorded c494a6f08c-afccf8f64262); lone T2 con minutes 0.26 vs 0.58; turned back 0; near-done strips 8.7 vs 88.6; ahead 0.50; built x1.05 at 30"} -->
# pkg4: v0.5.12 candidate (bare T2 floor, press-on fix) vs v0.5.11

- **Date:** 2026-11-15
- **Topic:** v0512
- **Purpose:** Release candidate: pkg3 plus apex_con_bare_ceiling and press-on that a home force cannot recall; 2v2 +50, rc/cm/cc, both factions
- **Result:** 12 games: won 0, lost 1, timeouts ahead 6, behind 5; income at 20 min x0.89 ours/theirs
- **Verdict:** contract PASS (recorded c494a6f08c-afccf8f64262); lone T2 con minutes 0.26 vs 0.58; turned back 0; near-done strips 8.7 vs 88.6; ahead 0.50; built x1.05 at 30
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.11-standard
- **Code:** Apex-v0.5.11-standard = `v0.5.11` (12 games); Apexestall-lane-estall-standard = `c494a6f08c+21df3f03f13f` (12 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.11:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9503 --out matches/pkg4-v0-cc-A9503`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9503 | 0 | w | 30.0 | x0.95 | c494a6f08c+21df3f03f13f, v0.5.11 | `matches/pkg4-v0-cc-A9503` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9506 | 0 | w | 30.0 | x0.78 | c494a6f08c+21df3f03f13f, v0.5.11 | `matches/pkg4-v0-cc-A9506` |
| 2 | Comet Catcher Remake 1.8 | Cortex | 9503 | 0 | l | 30.0 | x0.97 | c494a6f08c+21df3f03f13f, v0.5.11 | `matches/pkg4-v0-cc-C9503` |
| 3 | Comet Catcher Remake 1.8 | Cortex | 9506 | 0 | l | 30.0 | x1.03 | c494a6f08c+21df3f03f13f, v0.5.11 | `matches/pkg4-v0-cc-C9506` |
| 4 | Carrot Mountains v2.0 | Armada | 9502 | 0 | w | 30.0 | x0.95 | c494a6f08c+21df3f03f13f, v0.5.11 | `matches/pkg4-v0-cm-A9502` |
| 5 | Carrot Mountains v2.0 | Armada | 9505 | 0 | w | 30.0 | x0.96 | c494a6f08c+21df3f03f13f, v0.5.11 | `matches/pkg4-v0-cm-A9505` |
| 6 | Carrot Mountains v2.0 | Cortex | 9502 | 0 | w | 30.0 | x1.28 | c494a6f08c+21df3f03f13f, v0.5.11 | `matches/pkg4-v0-cm-C9502` |
| 7 | Carrot Mountains v2.0 | Cortex | 9505 | 0 | l | 30.0 | x0.43 | c494a6f08c+21df3f03f13f, v0.5.11 | `matches/pkg4-v0-cm-C9505` |
| 8 | Red Comet Remake 1.8 | Armada | 9501 | 0 | l | 30.0 | x1.13 | c494a6f08c+21df3f03f13f, v0.5.11 | `matches/pkg4-v0-rc-A9501` |
| 9 | Red Comet Remake 1.8 | Armada | 9504 | 0 | L | 23.2 | x0.59 | c494a6f08c+21df3f03f13f, v0.5.11 | `matches/pkg4-v0-rc-A9504` |
| 10 | Red Comet Remake 1.8 | Cortex | 9501 | 0 | w | 30.0 | x1.15 | c494a6f08c+21df3f03f13f, v0.5.11 | `matches/pkg4-v0-rc-C9501` |
| 11 | Red Comet Remake 1.8 | Cortex | 9504 | 0 | l | 30.0 | x0.82 | c494a6f08c+21df3f03f13f, v0.5.11 | `matches/pkg4-v0-rc-C9504` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 4.03 | 3.64 | - | ok |
| t2->4th moho (min) | 8.54 | 7.64 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.25 | 0.44 | 0.00 | ok, short of aim |
| adv plant frame x | 2.72 | 2.27 | 1.50 | ok, short of aim |
| near-done strips | 8.71 | 88.58 | 0.00 | ok, short of aim |
| t2 cons given early | 0.04 | 0.29 | 0.00 | ok, short of aim |
| lone t2 con minutes | 0.26 | 0.58 | 0.00 | ok, short of aim |
| frozen minutes | 0.25 | 0.00 | 0.00 | ok, short of aim |
| bare-hands minutes | 0.33 | 0.00 | 0.00 | ok, short of aim |
| wiped bomber runs | 1.79 | 2.00 | 0.00 | ok, short of aim |
| runs turned back | 0.00 | - | 0.00 | n/a |
| anomalous seats | 0.04 | 0.00 | 0.00 | ok, short of aim |
| peak constructors | 74.00 | 64.50 | - | ok |
| army share (neg) | 0.38 | 0.32 | - | ok |
| games won or ahead | 0.50 | 0.50 | - | ok |

Contract: **PASS** over 12 games (24 of our seats, 24 release seats); 10 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomalies: 1 seat(s) of 24 outside 5 robust deviations of v0.5.11's normal
  pkg4-v0-rc-A9504 t0 lane-estall: 20m constructors 0 (normal 47, z -8)
```
