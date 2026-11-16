<!-- meta {"date": "2026-11-16", "topic": "v0514", "title": "na9: Unstable vs v0.5.13, no air, no nukes (8 games)", "games": 8, "W": 1, "L": 2, "w": 2, "l": 3, "inc20": 1.16, "verdict": "Worse than na8. Decided 1-2 (na8 3-1), at time ahead 2 behind 3; won or ahead 0.62 vs 0.50. Contract FAIL (3): base lost while covered 7.26k vs 4.46k (medians 4.2 vs 1.8), t2 to first moho median 2.89 vs 2.18 min, oldest plant order 3.88 vs 2.71 min (na8 on near-identical code passed both: 2.94 vs 2.60, 2.74 vs 3.19). Pooled rc9+na9 (52 seats a side): only base lost while covered fails, 7.54 vs 4.80."} -->
# na9: Unstable vs v0.5.13, no air, no nukes (8 games)

- **Date:** 2026-11-16
- **Topic:** v0514
- **Purpose:** Same code as rc9, the 8 no-air/no-nuke 40-min games.
- **Result:** 8 games: won 1, lost 2, timeouts ahead 2, behind 3; income at 20 min x1.16 ours/theirs
- **Verdict:** Worse than na8. Decided 1-2 (na8 3-1), at time ahead 2 behind 3; won or ahead 0.62 vs 0.50. Contract FAIL (3): base lost while covered 7.26k vs 4.46k (medians 4.2 vs 1.8), t2 to first moho median 2.89 vs 2.18 min, oldest plant order 3.88 vs 2.71 min (na8 on near-identical code passed both: 2.94 vs 2.60, 2.74 vs 3.19). Pooled rc9+na9 (52 seats a side): only base lost while covered fails, 7.54 vs 4.80.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.13-standard
- **Code:** Apex-v0.5.13-standard = `b836bd8247+2f2ca832cead` (8 games); Apexestall-lane-estall-standard = `363c70a0a5+c487dbeb848d` (8 games)
- **Maps:** Carrot Mountains v2.0, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 40 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.13:standard --per-side 2 --map Carrot Mountains v2.0 --minutes 40 --speed 20 --handicap 50 --sides Armada,Armada --seed 9602 --modoption unit_restrictions_noair=1 --modoption unit_restrictions_nonukes=1 --out matches/na9-v0-cm2-A9602`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Carrot Mountains v2.0 | Armada | 9602 | 0 | l | 40.0 | x1.07 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/na9-v0-cm2-A9602` |
| 1 | Carrot Mountains v2.0 | Armada | 9604 | 0 | w | 40.0 | x1.19 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/na9-v0-cm2-A9604` |
| 2 | Carrot Mountains v2.0 | Cortex | 9602 | 0 | w | 40.0 | x1.35 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/na9-v0-cm2-C9602` |
| 3 | Carrot Mountains v2.0 | Cortex | 9604 | 0 | l | 40.0 | x1.23 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/na9-v0-cm2-C9604` |
| 4 | Red Comet Remake 1.8 | Armada | 9601 | 0 | L | 25.53 | x0.40 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/na9-v0-rc2-A9601` |
| 5 | Red Comet Remake 1.8 | Armada | 9603 | 0 | W | 22.05 | x8.26 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/na9-v0-rc2-A9603` |
| 6 | Red Comet Remake 1.8 | Cortex | 9601 | 0 | l | 40.0 | x0.92 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/na9-v0-rc2-C9601` |
| 7 | Red Comet Remake 1.8 | Cortex | 9603 | 0 | L | 32.26 | x0.50 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/na9-v0-rc2-C9603` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.89 | 2.18 | - | FAIL (worse than release) |
| t2->4th moho (min) | 5.30 | 5.47 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.71 | 0.71 | 0.00 | ok, short of aim |
| adv plant frame x | 1.73 | 2.07 | 1.50 | ok, short of aim |
| near-done strips | 6.38 | 4.94 | 0.00 | ok, short of aim |
| t2 cons given early | 0.06 | 0.06 | 0.00 | ok, short of aim |
| supers before 4 moho | 0.75 | 1.25 | 0.00 | ok, short of aim |
| lone t2 con minutes | 0.62 | 0.50 | 0.00 | ok, short of aim |
| base lost while 'covered' k | 7.26 | 4.46 | 0.00 | FAIL (worse than release) |
| oldest plant order min | 3.88 | 2.71 | - | FAIL (worse than release) |
| no t2 by minute 20 | 0.00 | 0.12 | - | ok |
| frozen minutes | 0.00 | 0.38 | 0.00 | ok |
| bare-hands minutes | 0.12 | 0.25 | 0.00 | ok, short of aim |
| wiped bomber runs | - | - | 0.00 | n/a |
| runs turned back | - | - | 0.00 | n/a |
| gunships sent to lose | - | - | 0.00 | n/a |
| stacked radar/jammers | 0.12 | 0.60 | 0.00 | ok, short of aim |
| army stuck /10min/1k army | 1.63 | 1.37 | 0.00 | ok, short of aim |
| ground given up share | 0.18 | - | 0.00 | n/a |
| anomalous seats | 0.12 | 0.12 | 0.00 | ok, short of aim |
| log peak cons per income | -1.54 | -1.44 | - | ok |
| army share (neg) | 0.52 | 0.42 | - | ok |
| -log income at 20 | -5.38 | -4.98 | - | ok |
| games won or ahead | 0.62 | 0.50 | - | ok |

Contract: **FAIL (3)** over 8 games (16 of our seats, 16 release seats); 12 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomalies: 2 seat(s) of 16 outside 5 robust deviations of v0.5.13's normal
  na9-v0-rc2-A9603 t1 lane-estall: 10m T2 share 40% (normal 0%, z +8); 15m T2 share 58% (normal 18%, z +7)
  na9-v0-cm2-A9602 t0 lane-estall: 10m T2 share 27% (normal 0%, z +5)
```
