<!-- meta {"date": "2026-11-16", "topic": "v0514", "title": "rc9: Unstable vs v0.5.13 (20 games)", "games": 20, "W": 3, "L": 1, "w": 5, "l": 11, "inc20": 1.0, "verdict": "Not a clean PASS. Decided 3-1, at time ahead 5 behind 11; won or ahead 0.55 vs 0.50; income at 20 x1.00. Contract FAIL (1): base lost while covered 7.67k vs 4.95k; one seat fm2-C9511 t0 (80.6k) carries most of it, without it 5.6 vs 4.95 (margin 1.0). The release side itself reads 4.5-8.0 across rc8/rc9/na8/na9 on unchanged code. Early defence at minute 8: target 2270 have 825 vs release 2638/962 (rc8 2577/998): no overbuild from the first-arrival weight jump. Stacked senses 0.06 vs 0.53, supers before 4 moho 3.2 vs 4.6, anomalous seats 0 vs 0.08."} -->
# rc9: Unstable vs v0.5.13 (20 games)

- **Date:** 2026-11-16
- **Topic:** v0514
- **Purpose:** Final 0.5.14 candidate after review 2 fixes: LRPC director holds its guns (scriptFree) and skips targets with our metal under splash; arrival weight over the larger of the recent mean and the standing mark. +50, both factions, h13 seeds.
- **Result:** 20 games: won 3, lost 1, timeouts ahead 5, behind 11; income at 20 min x1.00 ours/theirs
- **Verdict:** Not a clean PASS. Decided 3-1, at time ahead 5 behind 11; won or ahead 0.55 vs 0.50; income at 20 x1.00. Contract FAIL (1): base lost while covered 7.67k vs 4.95k; one seat fm2-C9511 t0 (80.6k) carries most of it, without it 5.6 vs 4.95 (margin 1.0). The release side itself reads 4.5-8.0 across rc8/rc9/na8/na9 on unchanged code. Early defence at minute 8: target 2270 have 825 vs release 2638/962 (rc8 2577/998): no overbuild from the first-arrival weight jump. Stacked senses 0.06 vs 0.53, supers before 4 moho 3.2 vs 4.6, anomalous seats 0 vs 0.08.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.13-standard
- **Code:** Apex-v0.5.13-standard = `b836bd8247+2f2ca832cead` (20 games); Apexestall-lane-estall-standard = `363c70a0a5+c487dbeb848d` (20 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Full Metal Plate 1.7, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.13:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9503 --out matches/rc9-v0-cc2-A9503`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9503 | 0 | l | 30.0 | x0.55 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc9-v0-cc2-A9503` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9506 | 0 | l | 30.0 | x0.56 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc9-v0-cc2-A9506` |
| 2 | Comet Catcher Remake 1.8 | Cortex | 9503 | 0 | l | 30.0 | x0.62 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc9-v0-cc2-C9503` |
| 3 | Comet Catcher Remake 1.8 | Cortex | 9506 | 0 | w | 30.0 | x1.27 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc9-v0-cc2-C9506` |
| 4 | Carrot Mountains v2.0 | Armada | 9502 | 0 | W | 26.77 | x3.02 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc9-v0-cm2-A9502` |
| 5 | Carrot Mountains v2.0 | Armada | 9505 | 0 | W | 28.72 | x5.75 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc9-v0-cm2-A9505` |
| 6 | Carrot Mountains v2.0 | Cortex | 9502 | 0 | w | 30.0 | x1.52 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc9-v0-cm2-C9502` |
| 7 | Carrot Mountains v2.0 | Cortex | 9505 | 0 | l | 30.0 | x0.60 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc9-v0-cm2-C9505` |
| 8 | Full Metal Plate 1.7 | Armada | 9511 | 0 | w | 30.0 | x1.34 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc9-v0-fm1-A9511` |
| 9 | Full Metal Plate 1.7 | Armada | 9512 | 0 | l | 30.0 | x0.97 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc9-v0-fm1-A9512` |
| 10 | Full Metal Plate 1.7 | Cortex | 9511 | 0 | l | 30.0 | x0.92 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc9-v0-fm1-C9511` |
| 11 | Full Metal Plate 1.7 | Cortex | 9512 | 0 | W | 26.44 | x1.46 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc9-v0-fm1-C9512` |
| 12 | Full Metal Plate 1.7 | Armada | 9511 | 0 | l | 30.0 | x0.71 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc9-v0-fm2-A9511` |
| 13 | Full Metal Plate 1.7 | Armada | 9512 | 0 | l | 30.0 | x0.57 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc9-v0-fm2-A9512` |
| 14 | Full Metal Plate 1.7 | Cortex | 9511 | 0 | l | 30.0 | x0.47 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc9-v0-fm2-C9511` |
| 15 | Full Metal Plate 1.7 | Cortex | 9512 | 0 | w | 30.0 | x2.48 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc9-v0-fm2-C9512` |
| 16 | Red Comet Remake 1.8 | Armada | 9501 | 0 | l | 30.0 | x0.62 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc9-v0-rc2-A9501` |
| 17 | Red Comet Remake 1.8 | Armada | 9504 | 0 | w | 30.0 | x1.38 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc9-v0-rc2-A9504` |
| 18 | Red Comet Remake 1.8 | Cortex | 9501 | 0 | L | 7.08 | - | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc9-v0-rc2-C9501` |
| 19 | Red Comet Remake 1.8 | Cortex | 9504 | 0 | l | 30.0 | x0.38 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc9-v0-rc2-C9504` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 3.15 | 3.14 | - | ok |
| t2->4th moho (min) | 6.70 | 6.84 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.47 | 0.52 | 0.00 | ok, short of aim |
| adv plant frame x | 1.93 | 1.89 | 1.50 | ok, short of aim |
| near-done strips | 12.31 | 12.36 | 0.00 | ok, short of aim |
| t2 cons given early | 0.14 | 0.14 | 0.00 | ok, short of aim |
| supers before 4 moho | 3.21 | 4.55 | 0.00 | ok, short of aim |
| lone t2 con minutes | 0.47 | 0.61 | 0.00 | ok, short of aim |
| base lost while 'covered' k | 7.67 | 4.95 | 0.00 | FAIL (worse than release) |
| oldest plant order min | 3.61 | 3.72 | - | ok |
| no t2 by minute 20 | 0.00 | 0.03 | - | ok |
| frozen minutes | 0.11 | 0.56 | 0.00 | ok, short of aim |
| bare-hands minutes | 0.11 | 0.56 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.41 | 0.48 | 0.00 | ok, short of aim |
| runs turned back | 0.00 | 0.00 | 0.00 | ok |
| gunships sent to lose | 0.00 | 0.00 | 0.00 | ok |
| stacked radar/jammers | 0.06 | 0.53 | 0.00 | ok, short of aim |
| army stuck /10min/1k army | 2.30 | 2.86 | 0.00 | ok, short of aim |
| ground given up share | 0.31 | - | 0.00 | n/a |
| anomalous seats | 0.00 | 0.08 | 0.00 | ok |
| log peak cons per income | -1.70 | -1.64 | - | ok |
| army share (neg) | 0.40 | 0.39 | - | ok |
| -log income at 20 | -5.42 | -5.24 | - | ok |
| games won or ahead | 0.55 | 0.50 | - | ok |

Contract: **FAIL (1)** over 20 games (36 of our seats, 36 release seats); 13 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomalies: 0 seat(s) of 24 outside 5 robust deviations of v0.5.13's normal; 12 seat(s) skipped, no normal yet for hc50-x1-A-1v1@Full Metal Plate, hc50-x1-A-2v2@Full Metal Plate, hc50-x1-C-1v1@Full Metal Plate, hc50-x1-C-2v2@Comet Catcher Remake
```
