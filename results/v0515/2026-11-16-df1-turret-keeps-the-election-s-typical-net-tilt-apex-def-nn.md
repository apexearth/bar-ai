<!-- meta {"date": "2026-11-16", "topic": "v0515", "title": "df1: turret keeps the election's typical net tilt (apex_def_nn_floor) ON vs OFF vs WRDistilled 0.4, both +50, Armada, Comet Catcher 1v1, 16 seeds", "games": 32, "W": 1, "L": 15, "w": 11, "l": 5, "inc20": 1.05, "verdict": "No effect, removed: won or ahead 6 vs 7 of 16; extractors lost to Ticks by 10 min 4.25 vs 4.25; lost per killed 1.12 vs 1.21; income at 20 level. The floor lifted turrets in ~25% of elections, but the guards that matter come too late: first Tick kill 2.7-3.9 min, extractor-guard turrets (mexSite=1) ordered 3.3-4.9 min, often Beamers walked 2,300 across the map. Next: price the guard by how soon their cheapest raider can reach the field, nearest builder, cheapest gun that stops a Tick. (The cm2 half of this batch was stopped on his 'Comet Catcher 1v1 only'.)"} -->
# df1: turret keeps the election's typical net tilt (apex_def_nn_floor) ON vs OFF vs WRDistilled 0.4, both +50, Armada, Comet Catcher 1v1, 16 seeds

- **Date:** 2026-11-16
- **Topic:** v0515
- **Purpose:** His 11-16: Ticks kill extractors one light turret would save; his strategy against a heavy army (strong defences they bleed into). Scenario ticks_mexes showed the nets tilting a turret 5-30x under an extractor.
- **Result:** 32 games: won 1, lost 15, timeouts ahead 11, behind 5; income at 20 min x1.05 ours/theirs
- **Verdict:** No effect, removed: won or ahead 6 vs 7 of 16; extractors lost to Ticks by 10 min 4.25 vs 4.25; lost per killed 1.12 vs 1.21; income at 20 level. The floor lifted turrets in ~25% of elections, but the guards that matter come too late: first Tick kill 2.7-3.9 min, extractor-guard turrets (mexSite=1) ordered 3.3-4.9 min, often Beamers walked 2,300 across the map. Next: price the guard by how soon their cheapest raider can reach the field, nearest builder, cheapest gun that stops a Tick. (The cm2 half of this batch was stopped on his 'Comet Catcher 1v1 only'.)
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** WRDistilled-0.4
- **Code:** Apexestall-lane-estall-standard = `6fc9a74aef+86d40282a02c` (24 games); Apexestall-lane-estall-standard = `?` (8 games); WRDistilled-0.4 = `?` (32 games)
- **Maps:** Comet Catcher Remake 1.8
- **Sides:** Armada; **bonus:** 50; **time cap:** 20 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b WRDistilled:0.4 --per-side 1 --map Comet Catcher Remake 1.8 --minutes 20 --speed 20 --handicap 50 --sides Armada,Armada --seed 9401 --ai-option apex_def_nn_floor=0 --out matches/df1-v0-cc1-A9401`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9401 | 0 | L | 16.56 | - | 6fc9a74aef+86d40282a02c, ? | `matches/df1-v0-cc1-A9401` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9402 | 0 | w | 20.0 | x1.01 | 6fc9a74aef+86d40282a02c, ? | `matches/df1-v0-cc1-A9402` |
| 2 | Comet Catcher Remake 1.8 | Armada | 9403 | 0 | l | 20.0 | x0.05 | 6fc9a74aef+86d40282a02c, ? | `matches/df1-v0-cc1-A9403` |
| 3 | Comet Catcher Remake 1.8 | Armada | 9404 | 0 | w | 20.0 | x1.27 | 6fc9a74aef+86d40282a02c, ? | `matches/df1-v0-cc1-A9404` |
| 4 | Comet Catcher Remake 1.8 | Armada | 9405 | 0 | L | 11.59 | - | 6fc9a74aef+86d40282a02c, ? | `matches/df1-v0-cc1-A9405` |
| 5 | Comet Catcher Remake 1.8 | Armada | 9406 | 0 | w | 20.0 | x1.29 | 6fc9a74aef+86d40282a02c, ? | `matches/df1-v0-cc1-A9406` |
| 6 | Comet Catcher Remake 1.8 | Armada | 9407 | 0 | l | 20.0 | x0.54 | 6fc9a74aef+86d40282a02c, ? | `matches/df1-v0-cc1-A9407` |
| 7 | Comet Catcher Remake 1.8 | Armada | 9408 | 0 | w | 20.0 | x5.04 | 6fc9a74aef+86d40282a02c, ? | `matches/df1-v0-cc1-A9408` |
| 8 | Comet Catcher Remake 1.8 | Armada | 9409 | 0 | l | 20.0 | x0.57 | 6fc9a74aef+86d40282a02c, ? | `matches/df1-v0-cc1-A9409` |
| 9 | Comet Catcher Remake 1.8 | Armada | 9410 | 0 | w | 20.0 | x1.00 | 6fc9a74aef+86d40282a02c, ? | `matches/df1-v0-cc1-A9410` |
| 10 | Comet Catcher Remake 1.8 | Armada | 9411 | 0 | w | 20.0 | x1.13 | 6fc9a74aef+86d40282a02c, ? | `matches/df1-v0-cc1-A9411` |
| 11 | Comet Catcher Remake 1.8 | Armada | 9412 | 0 | W | 19.27 | - | 6fc9a74aef+86d40282a02c, ? | `matches/df1-v0-cc1-A9412` |
| 12 | Comet Catcher Remake 1.8 | Armada | 9413 | 0 | L | 0.1 | - | ? | `matches/df1-v0-cc1-A9413` |
| 13 | Comet Catcher Remake 1.8 | Armada | 9414 | 0 | L | 0.1 | - | ? | `matches/df1-v0-cc1-A9414` |
| 14 | Comet Catcher Remake 1.8 | Armada | 9415 | 0 | L | 0.12 | - | ? | `matches/df1-v0-cc1-A9415` |
| 15 | Comet Catcher Remake 1.8 | Armada | 9416 | 0 | L | 0.08 | - | ? | `matches/df1-v0-cc1-A9416` |
| 16 | Comet Catcher Remake 1.8 | Armada | 9401 | 0 | w | 20.0 | x6.24 | 6fc9a74aef+86d40282a02c, ? | `matches/df1-v1-cc1-A9401` |
| 17 | Comet Catcher Remake 1.8 | Armada | 9402 | 0 | L | 13.73 | - | 6fc9a74aef+86d40282a02c, ? | `matches/df1-v1-cc1-A9402` |
| 18 | Comet Catcher Remake 1.8 | Armada | 9403 | 0 | L | 18.35 | - | 6fc9a74aef+86d40282a02c, ? | `matches/df1-v1-cc1-A9403` |
| 19 | Comet Catcher Remake 1.8 | Armada | 9404 | 0 | w | 20.0 | x1.28 | 6fc9a74aef+86d40282a02c, ? | `matches/df1-v1-cc1-A9404` |
| 20 | Comet Catcher Remake 1.8 | Armada | 9405 | 0 | L | 17.79 | - | 6fc9a74aef+86d40282a02c, ? | `matches/df1-v1-cc1-A9405` |
| 21 | Comet Catcher Remake 1.8 | Armada | 9406 | 0 | L | 19.64 | - | 6fc9a74aef+86d40282a02c, ? | `matches/df1-v1-cc1-A9406` |
| 22 | Comet Catcher Remake 1.8 | Armada | 9407 | 0 | w | 20.0 | x1.49 | 6fc9a74aef+86d40282a02c, ? | `matches/df1-v1-cc1-A9407` |
| 23 | Comet Catcher Remake 1.8 | Armada | 9408 | 0 | w | 20.0 | x1.25 | 6fc9a74aef+86d40282a02c, ? | `matches/df1-v1-cc1-A9408` |
| 24 | Comet Catcher Remake 1.8 | Armada | 9409 | 0 | L | 17.19 | - | 6fc9a74aef+86d40282a02c, ? | `matches/df1-v1-cc1-A9409` |
| 25 | Comet Catcher Remake 1.8 | Armada | 9410 | 0 | l | 20.0 | x0.55 | 6fc9a74aef+86d40282a02c, ? | `matches/df1-v1-cc1-A9410` |
| 26 | Comet Catcher Remake 1.8 | Armada | 9411 | 0 | w | 20.0 | x2.41 | 6fc9a74aef+86d40282a02c, ? | `matches/df1-v1-cc1-A9411` |
| 27 | Comet Catcher Remake 1.8 | Armada | 9412 | 0 | l | 20.0 | x0.79 | 6fc9a74aef+86d40282a02c, ? | `matches/df1-v1-cc1-A9412` |
| 28 | Comet Catcher Remake 1.8 | Armada | 9413 | 0 | L | 0.1 | - | ? | `matches/df1-v1-cc1-A9413` |
| 29 | Comet Catcher Remake 1.8 | Armada | 9414 | 0 | L | 0.1 | - | ? | `matches/df1-v1-cc1-A9414` |
| 30 | Comet Catcher Remake 1.8 | Armada | 9415 | 0 | L | 0.12 | - | ? | `matches/df1-v1-cc1-A9415` |
| 31 | Comet Catcher Remake 1.8 | Armada | 9416 | 0 | L | 0.08 | - | ? | `matches/df1-v1-cc1-A9416` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.03 | - | - | n/a |
| t2->4th moho (min) | 4.05 | - | 3.00 | n/a |
| lab-job leaves/job | 0.20 | - | 0.00 | n/a |
| adv plant frame x | 2.36 | - | 1.50 | n/a |
| near-done /10k built | 0.51 | 0.00 | 0.00 | FAIL (worse than release) |
| t2 cons given early | 0.00 | 0.00 | 0.00 | ok |
| supers before 4 moho | 1.00 | - | 0.00 | n/a |
| lone t2 con minutes | 0.10 | - | 0.00 | n/a |
| base lost while 'covered' k | 0.88 | - | 0.00 | n/a |
| oldest plant order min | 1.45 | - | - | n/a |
| no t2 by minute 20 | 0.00 | - | - | n/a |
| frozen minutes | 0.08 | 0.00 | 0.00 | ok, short of aim |
| raid answer army share | - | - | - | n/a |
| com minutes on their half | 0.52 | 0.00 | - | FAIL (worse than release) |
| com lost on their half | 0.00 | 0.00 | 0.00 | ok |
| mex lost to ticks by 10 min | 4.25 | 0.12 | 0.00 | FAIL (worse than release) |
| their mex killed /10min (neg) | -13.72 | -20.88 | - | FAIL (worse than release) |
| their army / ours, 8-12 min | 0.76 | - | - | n/a |
| lost per killed | 1.17 | 1.40 | - | ok |
| reclaimed / killed (neg) | -0.17 | -0.06 | - | ok |
| bare-hands minutes | 0.08 | 0.00 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.21 | - | 0.00 | n/a |
| runs turned back | 0.00 | - | 0.00 | n/a |
| gunships sent to lose | 0.00 | - | 0.00 | n/a |
| stacked radar/jammers | 0.00 | - | 0.00 | n/a |
| army stuck /10min/1k army | 3.98 | 0.00 | 0.00 | FAIL (worse than release) |
| ground given up share | 0.24 | - | 0.00 | n/a |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.50 | -2.41 | - | FAIL (worse than release) |
| army share (neg) | 0.40 | 0.82 | - | FAIL (worse than release) |
| -log income at 20 | -5.16 | - | - | n/a |
| games won or ahead | 0.54 | 0.50 | - | ok |

Contract: **FAIL (7)** over 24 games (24 of our seats, 24 release seats); 5 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.14 (run `python tools/anomaly.py build`)
```
