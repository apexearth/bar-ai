<!-- meta {"date": "2026-11-16", "topic": "v0514", "title": "rc7: Unstable vs v0.5.13 (20 games)", "games": 20, "W": 1, "L": 4, "w": 9, "l": 6, "inc20": 0.8, "verdict": "Not yet a release. Decided 1-4 (two wipes: cc A9503 x0.10, fm2 A9511 x0.04), at time ahead 9 behind 6; won or ahead 0.65 vs 0.50; income at 20 x0.80. Contract FAIL (2): lab-job leaves 0.57 vs 0.44, income at 20. Better: bare-hands 0.06 vs 1.06 and frozen 0.06 vs 0.89 minutes (blob fix), supers before 4 moho 2.8 vs 3.8, army share 0.42 vs 0.39. Stacked radar/jammers 0.28 vs 0.42, not gone: still to read."} -->
# rc7: Unstable vs v0.5.13 (20 games)

- **Date:** 2026-11-16
- **Topic:** v0514
- **Purpose:** Unstable since v0.5.13: arrival weighting (row 109), constructor blob (111/116), shelled-jammer siting (112), travel lean tunable (default 1, unchanged play), acts= logging. +50, both factions, rc/cm/cc/fm, the h13 seeds.
- **Result:** 20 games: won 1, lost 4, timeouts ahead 9, behind 6; income at 20 min x0.80 ours/theirs
- **Verdict:** Not yet a release. Decided 1-4 (two wipes: cc A9503 x0.10, fm2 A9511 x0.04), at time ahead 9 behind 6; won or ahead 0.65 vs 0.50; income at 20 x0.80. Contract FAIL (2): lab-job leaves 0.57 vs 0.44, income at 20. Better: bare-hands 0.06 vs 1.06 and frozen 0.06 vs 0.89 minutes (blob fix), supers before 4 moho 2.8 vs 3.8, army share 0.42 vs 0.39. Stacked radar/jammers 0.28 vs 0.42, not gone: still to read.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.13-standard
- **Code:** Apex-v0.5.13-standard = `b836bd8247+2f2ca832cead` (20 games); Apexestall-lane-estall-standard = `363c70a0a5+5a24d1c035be` (20 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Full Metal Plate 1.7, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.13:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9503 --out matches/rc7-v0-cc2-A9503`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9503 | 0 | L | 21.5 | x0.10 | 363c70a0a5+5a24d1c035be, b836bd8247+2f2ca832cead | `matches/rc7-v0-cc2-A9503` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9506 | 0 | l | 30.0 | x0.64 | 363c70a0a5+5a24d1c035be, b836bd8247+2f2ca832cead | `matches/rc7-v0-cc2-A9506` |
| 2 | Comet Catcher Remake 1.8 | Cortex | 9503 | 0 | L | 29.5 | x0.53 | 363c70a0a5+5a24d1c035be, b836bd8247+2f2ca832cead | `matches/rc7-v0-cc2-C9503` |
| 3 | Comet Catcher Remake 1.8 | Cortex | 9506 | 0 | w | 30.0 | x1.54 | 363c70a0a5+5a24d1c035be, b836bd8247+2f2ca832cead | `matches/rc7-v0-cc2-C9506` |
| 4 | Carrot Mountains v2.0 | Armada | 9502 | 0 | w | 30.0 | x1.08 | 363c70a0a5+5a24d1c035be, b836bd8247+2f2ca832cead | `matches/rc7-v0-cm2-A9502` |
| 5 | Carrot Mountains v2.0 | Armada | 9505 | 0 | w | 30.0 | x1.14 | 363c70a0a5+5a24d1c035be, b836bd8247+2f2ca832cead | `matches/rc7-v0-cm2-A9505` |
| 6 | Carrot Mountains v2.0 | Cortex | 9502 | 0 | w | 30.0 | x2.45 | 363c70a0a5+5a24d1c035be, b836bd8247+2f2ca832cead | `matches/rc7-v0-cm2-C9502` |
| 7 | Carrot Mountains v2.0 | Cortex | 9505 | 0 | l | 30.0 | x0.76 | 363c70a0a5+5a24d1c035be, b836bd8247+2f2ca832cead | `matches/rc7-v0-cm2-C9505` |
| 8 | Full Metal Plate 1.7 | Armada | 9511 | 0 | w | 30.0 | x1.59 | 363c70a0a5+5a24d1c035be, b836bd8247+2f2ca832cead | `matches/rc7-v0-fm1-A9511` |
| 9 | Full Metal Plate 1.7 | Armada | 9512 | 0 | w | 30.0 | x0.64 | 363c70a0a5+5a24d1c035be, b836bd8247+2f2ca832cead | `matches/rc7-v0-fm1-A9512` |
| 10 | Full Metal Plate 1.7 | Cortex | 9511 | 0 | l | 30.0 | x2.48 | 363c70a0a5+5a24d1c035be, b836bd8247+2f2ca832cead | `matches/rc7-v0-fm1-C9511` |
| 11 | Full Metal Plate 1.7 | Cortex | 9512 | 0 | l | 30.0 | x0.62 | 363c70a0a5+5a24d1c035be, b836bd8247+2f2ca832cead | `matches/rc7-v0-fm1-C9512` |
| 12 | Full Metal Plate 1.7 | Armada | 9511 | 0 | L | 20.31 | x0.04 | 363c70a0a5+5a24d1c035be, b836bd8247+2f2ca832cead | `matches/rc7-v0-fm2-A9511` |
| 13 | Full Metal Plate 1.7 | Armada | 9512 | 0 | l | 30.0 | x0.63 | 363c70a0a5+5a24d1c035be, b836bd8247+2f2ca832cead | `matches/rc7-v0-fm2-A9512` |
| 14 | Full Metal Plate 1.7 | Cortex | 9511 | 0 | W | 29.31 | x2.34 | 363c70a0a5+5a24d1c035be, b836bd8247+2f2ca832cead | `matches/rc7-v0-fm2-C9511` |
| 15 | Full Metal Plate 1.7 | Cortex | 9512 | 0 | w | 30.0 | x0.89 | 363c70a0a5+5a24d1c035be, b836bd8247+2f2ca832cead | `matches/rc7-v0-fm2-C9512` |
| 16 | Red Comet Remake 1.8 | Armada | 9501 | 0 | w | 30.0 | x1.45 | 363c70a0a5+5a24d1c035be, b836bd8247+2f2ca832cead | `matches/rc7-v0-rc2-A9501` |
| 17 | Red Comet Remake 1.8 | Armada | 9504 | 0 | w | 30.0 | x1.29 | 363c70a0a5+5a24d1c035be, b836bd8247+2f2ca832cead | `matches/rc7-v0-rc2-A9504` |
| 18 | Red Comet Remake 1.8 | Cortex | 9501 | 0 | l | 30.0 | x0.98 | 363c70a0a5+5a24d1c035be, b836bd8247+2f2ca832cead | `matches/rc7-v0-rc2-C9501` |
| 19 | Red Comet Remake 1.8 | Cortex | 9504 | 0 | L | 24.95 | x0.56 | 363c70a0a5+5a24d1c035be, b836bd8247+2f2ca832cead | `matches/rc7-v0-rc2-C9504` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.94 | 2.74 | - | ok |
| t2->4th moho (min) | 7.29 | 7.26 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.57 | 0.44 | 0.00 | FAIL (worse than release) |
| adv plant frame x | 2.30 | 2.49 | 1.50 | ok, short of aim |
| near-done strips | 11.03 | 11.28 | 0.00 | ok, short of aim |
| t2 cons given early | 0.11 | 0.06 | 0.00 | ok, short of aim |
| supers before 4 moho | 2.78 | 3.83 | 0.00 | ok, short of aim |
| lone t2 con minutes | 0.44 | 0.46 | 0.00 | ok, short of aim |
| base lost while 'covered' k | 5.80 | 5.33 | 0.00 | ok, short of aim |
| oldest plant order min | 3.08 | 3.12 | - | ok |
| no t2 by minute 20 | 0.00 | 0.03 | - | ok |
| frozen minutes | 0.06 | 0.89 | 0.00 | ok, short of aim |
| bare-hands minutes | 0.06 | 1.06 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.45 | 0.40 | 0.00 | ok, short of aim |
| runs turned back | 0.03 | 0.10 | 0.00 | ok, short of aim |
| gunships sent to lose | 0.00 | 0.00 | 0.00 | ok |
| stacked radar/jammers | 0.28 | 0.42 | 0.00 | ok, short of aim |
| army stuck per 10 min | 46.44 | 43.27 | 0.00 | ok, short of aim |
| ground given up share | 0.23 | - | 0.00 | n/a |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.62 | -1.69 | - | ok |
| army share (neg) | 0.42 | 0.39 | - | ok |
| -log income at 20 | -4.87 | -5.29 | - | FAIL (worse than release) |
| games won or ahead | 0.65 | 0.50 | - | ok |

Contract: **FAIL (2)** over 20 games (36 of our seats, 36 release seats); 14 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.13 (run `python tools/anomaly.py build`)
```

## Read after the batch

- Spend split, median of 20 games (story.py at 240 s buckets, ours vs v0.5.13). Minute 12: income 150 vs 152, army 6.1k vs 5.4k, eco 6.2k vs 6.2k, def 2.3k vs 2.7k, buildpower 6.2k vs 6.0k. Minute 16: income 238 vs 227, buildpower 10.1k vs 10.1k. The x0.80 income at 20 comes from a few collapses, not a general eco loss.
- cc2-A9503 (lost at 21.5): behind from minute 8, with defence spend 2.9k vs 1.7k and army 2.3k vs 4.0k.
- fm2-A9511 (lost at 20.3): even to 12; at 16, income 632 vs 1,557 and buildpower 14k vs 44k.
- Stacked senses, ours: 8 radars 300-800 apart, 2 jammers re-sited by the C++ builder beside a standing one (validation row 112).
