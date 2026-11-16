<!-- meta {"date": "2026-11-16", "topic": "v0514", "title": "rc8: Unstable vs v0.5.13 (20 games)", "games": 20, "W": 3, "L": 1, "w": 6, "l": 10, "inc20": 1.3, "verdict": "Better than rc7, not a clean PASS. Decided 3-1 (rc7 1-4; both rc7 wipes gone), at time ahead 6 behind 10; won or ahead 0.50 vs 0.50; income at 20 x1.30 (rc7 x0.80). Contract FAIL (1): supers before 4 moho 3.74 vs 3.18, all from one seat (fm2-A9511 t0, 35 orders, a game we won; Full Metal Plate seats run high for both AIs, a release seat there 27); without it 2.8 vs 3.2 (rc7 2.8 vs 3.8). Army stuck per 1k army 2.0 vs 2.3; stacked radar/jammers 0.18 vs 0.17; anomalous seats 0.04 vs 0.08 (baseline built 11-16). Loss rc2-A9501 at 14.6 min: lab raided by Pawns and Fleas by minute 4 (row 114). Red Comet 0-4 for us."} -->
# rc8: Unstable vs v0.5.13 (20 games)

- **Date:** 2026-11-16
- **Topic:** v0514
- **Purpose:** Unstable after the 11-16 review fixes: pure-sensor spacing (row 112), LRPC army value capped at its own metal and a 3 s look while an army is the focus (115), lean 2 only for ground units on an attack (113), arrival high-water mark (109), with the constructor blob fix (111/116). +50, both factions, the h13 seeds.
- **Result:** 20 games: won 3, lost 1, timeouts ahead 6, behind 10; income at 20 min x1.30 ours/theirs
- **Verdict:** Better than rc7, not a clean PASS. Decided 3-1 (rc7 1-4; both rc7 wipes gone), at time ahead 6 behind 10; won or ahead 0.50 vs 0.50; income at 20 x1.30 (rc7 x0.80). Contract FAIL (1): supers before 4 moho 3.74 vs 3.18, all from one seat (fm2-A9511 t0, 35 orders, a game we won; Full Metal Plate seats run high for both AIs, a release seat there 27); without it 2.8 vs 3.2 (rc7 2.8 vs 3.8). Army stuck per 1k army 2.0 vs 2.3; stacked radar/jammers 0.18 vs 0.17; anomalous seats 0.04 vs 0.08 (baseline built 11-16). Loss rc2-A9501 at 14.6 min: lab raided by Pawns and Fleas by minute 4 (row 114). Red Comet 0-4 for us.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.13-standard
- **Code:** Apex-v0.5.13-standard = `b836bd8247+2f2ca832cead` (20 games); Apexestall-lane-estall-standard = `363c70a0a5+cf493e59b8f4` (20 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Full Metal Plate 1.7, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.13:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9503 --out matches/rc8-v0-cc2-A9503`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9503 | 0 | l | 30.0 | x1.30 | 363c70a0a5+cf493e59b8f4, b836bd8247+2f2ca832cead | `matches/rc8-v0-cc2-A9503` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9506 | 0 | l | 30.0 | x0.64 | 363c70a0a5+cf493e59b8f4, b836bd8247+2f2ca832cead | `matches/rc8-v0-cc2-A9506` |
| 2 | Comet Catcher Remake 1.8 | Cortex | 9503 | 0 | l | 30.0 | x1.06 | 363c70a0a5+cf493e59b8f4, b836bd8247+2f2ca832cead | `matches/rc8-v0-cc2-C9503` |
| 3 | Comet Catcher Remake 1.8 | Cortex | 9506 | 0 | W | 26.97 | x3.20 | 363c70a0a5+cf493e59b8f4, b836bd8247+2f2ca832cead | `matches/rc8-v0-cc2-C9506` |
| 4 | Carrot Mountains v2.0 | Armada | 9502 | 0 | W | 28.76 | x3.23 | 363c70a0a5+cf493e59b8f4, b836bd8247+2f2ca832cead | `matches/rc8-v0-cm2-A9502` |
| 5 | Carrot Mountains v2.0 | Armada | 9505 | 0 | l | 30.0 | x0.72 | 363c70a0a5+cf493e59b8f4, b836bd8247+2f2ca832cead | `matches/rc8-v0-cm2-A9505` |
| 6 | Carrot Mountains v2.0 | Cortex | 9502 | 0 | l | 30.0 | x1.04 | 363c70a0a5+cf493e59b8f4, b836bd8247+2f2ca832cead | `matches/rc8-v0-cm2-C9502` |
| 7 | Carrot Mountains v2.0 | Cortex | 9505 | 0 | w | 30.0 | x2.12 | 363c70a0a5+cf493e59b8f4, b836bd8247+2f2ca832cead | `matches/rc8-v0-cm2-C9505` |
| 8 | Full Metal Plate 1.7 | Armada | 9511 | 0 | w | 30.0 | x1.64 | 363c70a0a5+cf493e59b8f4, b836bd8247+2f2ca832cead | `matches/rc8-v0-fm1-A9511` |
| 9 | Full Metal Plate 1.7 | Armada | 9512 | 0 | w | 30.0 | x1.28 | 363c70a0a5+cf493e59b8f4, b836bd8247+2f2ca832cead | `matches/rc8-v0-fm1-A9512` |
| 10 | Full Metal Plate 1.7 | Cortex | 9511 | 0 | w | 30.0 | x1.50 | 363c70a0a5+cf493e59b8f4, b836bd8247+2f2ca832cead | `matches/rc8-v0-fm1-C9511` |
| 11 | Full Metal Plate 1.7 | Cortex | 9512 | 0 | l | 30.0 | x1.49 | 363c70a0a5+cf493e59b8f4, b836bd8247+2f2ca832cead | `matches/rc8-v0-fm1-C9512` |
| 12 | Full Metal Plate 1.7 | Armada | 9511 | 0 | W | 27.91 | x1.27 | 363c70a0a5+cf493e59b8f4, b836bd8247+2f2ca832cead | `matches/rc8-v0-fm2-A9511` |
| 13 | Full Metal Plate 1.7 | Armada | 9512 | 0 | l | 30.0 | x0.34 | 363c70a0a5+cf493e59b8f4, b836bd8247+2f2ca832cead | `matches/rc8-v0-fm2-A9512` |
| 14 | Full Metal Plate 1.7 | Cortex | 9511 | 0 | w | 30.0 | x3.77 | 363c70a0a5+cf493e59b8f4, b836bd8247+2f2ca832cead | `matches/rc8-v0-fm2-C9511` |
| 15 | Full Metal Plate 1.7 | Cortex | 9512 | 0 | w | 30.0 | x1.52 | 363c70a0a5+cf493e59b8f4, b836bd8247+2f2ca832cead | `matches/rc8-v0-fm2-C9512` |
| 16 | Red Comet Remake 1.8 | Armada | 9501 | 0 | L | 14.58 | - | 363c70a0a5+cf493e59b8f4, b836bd8247+2f2ca832cead | `matches/rc8-v0-rc2-A9501` |
| 17 | Red Comet Remake 1.8 | Armada | 9504 | 0 | l | 30.0 | x0.97 | 363c70a0a5+cf493e59b8f4, b836bd8247+2f2ca832cead | `matches/rc8-v0-rc2-A9504` |
| 18 | Red Comet Remake 1.8 | Cortex | 9501 | 0 | l | 30.0 | x1.31 | 363c70a0a5+cf493e59b8f4, b836bd8247+2f2ca832cead | `matches/rc8-v0-rc2-C9501` |
| 19 | Red Comet Remake 1.8 | Cortex | 9504 | 0 | l | 30.0 | x0.71 | 363c70a0a5+cf493e59b8f4, b836bd8247+2f2ca832cead | `matches/rc8-v0-rc2-C9504` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 1.99 | 2.52 | - | ok |
| t2->4th moho (min) | 5.94 | 6.13 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.49 | 0.42 | 0.00 | ok, short of aim |
| adv plant frame x | 2.15 | 2.02 | 1.50 | ok, short of aim |
| near-done strips | 12.31 | 11.47 | 0.00 | ok, short of aim |
| t2 cons given early | 0.14 | 0.11 | 0.00 | ok, short of aim |
| supers before 4 moho | 3.74 | 3.18 | 0.00 | FAIL (worse than release) |
| lone t2 con minutes | 0.24 | 0.41 | 0.00 | ok, short of aim |
| base lost while 'covered' k | 6.19 | 7.01 | 0.00 | ok, short of aim |
| oldest plant order min | 3.43 | 3.05 | - | ok |
| no t2 by minute 20 | 0.00 | 0.06 | - | ok |
| frozen minutes | 0.28 | 0.78 | 0.00 | ok, short of aim |
| bare-hands minutes | 0.28 | 0.89 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.46 | 0.35 | 0.00 | ok, short of aim |
| runs turned back | 0.06 | 0.00 | 0.00 | ok, short of aim |
| gunships sent to lose | 0.00 | 0.00 | 0.00 | ok |
| stacked radar/jammers | 0.18 | 0.17 | 0.00 | ok, short of aim |
| army stuck /10min/1k army | 2.01 | 2.29 | 0.00 | ok, short of aim |
| ground given up share | 0.32 | - | 0.00 | n/a |
| anomalous seats | 0.04 | 0.08 | 0.00 | ok, short of aim |
| log peak cons per income | -1.83 | -1.65 | - | ok |
| army share (neg) | 0.40 | 0.38 | - | ok |
| -log income at 20 | -5.28 | -5.38 | - | ok |
| games won or ahead | 0.50 | 0.50 | - | ok |

Contract: **FAIL (1)** over 20 games (36 of our seats, 36 release seats); 15 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomalies: 1 seat(s) of 24 outside 5 robust deviations of v0.5.13's normal; 12 seat(s) skipped, no normal yet for hc50-x1-A-1v1@Full Metal Plate, hc50-x1-A-2v2@Full Metal Plate, hc50-x1-C-1v1@Full Metal Plate, hc50-x1-C-2v2@Comet Catcher Remake
  rc8-v0-rc2-A9504 t0 lane-estall: 10m T2 share 29% (normal 0%, z +6)
```
