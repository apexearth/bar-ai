<!-- meta {"date": "2026-11-17", "topic": "v0515", "title": "tk1: uncovered extractor guard at the bare-extractor rate (apex_mex_own_risk 1 vs 0) vs WRDistilled 0.4, both +50, Armada, Comet Catcher 1v1, 16 seeds", "games": 32, "W": 3, "L": 18, "w": 8, "l": 3, "inc20": 0.91, "verdict": "No help, removed: extractors lost to Ticks by 10 min 4.31 (on) vs 3.06 (off); won or ahead 3 vs 6; lost per killed 1.21 vs 1.21. Scenario ticks_mexes fails both ways (3-4 of 4 lost): no guard is priced at all before the first death (one site fill a frame, four elections in the first minute), so the rate on it was not the block. Next: keep the defence fills warm across frames."} -->
# tk1: uncovered extractor guard at the bare-extractor rate (apex_mex_own_risk 1 vs 0) vs WRDistilled 0.4, both +50, Armada, Comet Catcher 1v1, 16 seeds

- **Date:** 2026-11-17
- **Topic:** v0515
- **Purpose:** His 11-17 choice for Ticks: each extractor carries its own risk, so a turret beside an unguarded one is worth buying early.
- **Result:** 32 games: won 3, lost 18, timeouts ahead 8, behind 3; income at 20 min x0.91 ours/theirs
- **Verdict:** No help, removed: extractors lost to Ticks by 10 min 4.31 (on) vs 3.06 (off); won or ahead 3 vs 6; lost per killed 1.21 vs 1.21. Scenario ticks_mexes fails both ways (3-4 of 4 lost): no guard is priced at all before the first death (one site fill a frame, four elections in the first minute), so the rate on it was not the block. Next: keep the defence fills warm across frames.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** WRDistilled-0.4
- **Code:** Apexestall-lane-estall-standard = `3ea746d562+38ece9595056` (32 games); WRDistilled-0.4 = `?` (32 games)
- **Maps:** Comet Catcher Remake 1.8
- **Sides:** Armada; **bonus:** 50; **time cap:** 25 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b WRDistilled:0.4 --per-side 1 --map Comet Catcher Remake 1.8 --minutes 25 --speed 20 --handicap 50 --sides Armada,Armada --seed 9501 --ai-option apex_mex_own_risk=1 --out matches/tk1-v1-cc1-A9501`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9501 | 0 | L | 20.93 | x1.55 | 3ea746d562+38ece9595056, ? | `matches/tk1-v1-cc1-A9501` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9502 | 0 | L | 24.88 | x1.15 | 3ea746d562+38ece9595056, ? | `matches/tk1-v1-cc1-A9502` |
| 2 | Comet Catcher Remake 1.8 | Armada | 9503 | 0 | L | 18.72 | - | 3ea746d562+38ece9595056, ? | `matches/tk1-v1-cc1-A9503` |
| 3 | Comet Catcher Remake 1.8 | Armada | 9504 | 0 | l | 25.0 | x0.46 | 3ea746d562+38ece9595056, ? | `matches/tk1-v1-cc1-A9504` |
| 4 | Comet Catcher Remake 1.8 | Armada | 9505 | 0 | L | 18.36 | - | 3ea746d562+38ece9595056, ? | `matches/tk1-v1-cc1-A9505` |
| 5 | Comet Catcher Remake 1.8 | Armada | 9506 | 0 | w | 25.0 | x0.55 | 3ea746d562+38ece9595056, ? | `matches/tk1-v1-cc1-A9506` |
| 6 | Comet Catcher Remake 1.8 | Armada | 9507 | 0 | L | 11.62 | - | 3ea746d562+38ece9595056, ? | `matches/tk1-v1-cc1-A9507` |
| 7 | Comet Catcher Remake 1.8 | Armada | 9508 | 0 | L | 19.55 | - | 3ea746d562+38ece9595056, ? | `matches/tk1-v1-cc1-A9508` |
| 8 | Comet Catcher Remake 1.8 | Armada | 9509 | 0 | L | 22.01 | x0.17 | 3ea746d562+38ece9595056, ? | `matches/tk1-v1-cc1-A9509` |
| 9 | Comet Catcher Remake 1.8 | Armada | 9510 | 0 | L | 14.01 | - | 3ea746d562+38ece9595056, ? | `matches/tk1-v1-cc1-A9510` |
| 10 | Comet Catcher Remake 1.8 | Armada | 9511 | 0 | l | 25.0 | x1.09 | 3ea746d562+38ece9595056, ? | `matches/tk1-v1-cc1-A9511` |
| 11 | Comet Catcher Remake 1.8 | Armada | 9512 | 0 | w | 25.0 | x1.73 | 3ea746d562+38ece9595056, ? | `matches/tk1-v1-cc1-A9512` |
| 12 | Comet Catcher Remake 1.8 | Armada | 9513 | 0 | L | 15.72 | - | 3ea746d562+38ece9595056, ? | `matches/tk1-v1-cc1-A9513` |
| 13 | Comet Catcher Remake 1.8 | Armada | 9514 | 0 | w | 25.0 | x1.05 | 3ea746d562+38ece9595056, ? | `matches/tk1-v1-cc1-A9514` |
| 14 | Comet Catcher Remake 1.8 | Armada | 9515 | 0 | w | 25.0 | x1.59 | 3ea746d562+38ece9595056, ? | `matches/tk1-v1-cc1-A9515` |
| 15 | Comet Catcher Remake 1.8 | Armada | 9516 | 0 | l | 25.0 | x2.13 | 3ea746d562+38ece9595056, ? | `matches/tk1-v1-cc1-A9516` |
| 16 | Comet Catcher Remake 1.8 | Armada | 9501 | 0 | L | 20.37 | x0.09 | 3ea746d562+38ece9595056, ? | `matches/tk1-v0-cc1-A9501` |
| 17 | Comet Catcher Remake 1.8 | Armada | 9502 | 0 | L | 13.29 | - | 3ea746d562+38ece9595056, ? | `matches/tk1-v0-cc1-A9502` |
| 18 | Comet Catcher Remake 1.8 | Armada | 9503 | 0 | w | 25.0 | x1.61 | 3ea746d562+38ece9595056, ? | `matches/tk1-v0-cc1-A9503` |
| 19 | Comet Catcher Remake 1.8 | Armada | 9504 | 0 | w | 25.0 | x1.00 | 3ea746d562+38ece9595056, ? | `matches/tk1-v0-cc1-A9504` |
| 20 | Comet Catcher Remake 1.8 | Armada | 9505 | 0 | L | 16.2 | - | 3ea746d562+38ece9595056, ? | `matches/tk1-v0-cc1-A9505` |
| 21 | Comet Catcher Remake 1.8 | Armada | 9506 | 0 | L | 21.99 | x0.07 | 3ea746d562+38ece9595056, ? | `matches/tk1-v0-cc1-A9506` |
| 22 | Comet Catcher Remake 1.8 | Armada | 9507 | 0 | W | 22.83 | x4.29 | 3ea746d562+38ece9595056, ? | `matches/tk1-v0-cc1-A9507` |
| 23 | Comet Catcher Remake 1.8 | Armada | 9508 | 0 | L | 16.72 | - | 3ea746d562+38ece9595056, ? | `matches/tk1-v0-cc1-A9508` |
| 24 | Comet Catcher Remake 1.8 | Armada | 9509 | 0 | W | 24.46 | x2.91 | 3ea746d562+38ece9595056, ? | `matches/tk1-v0-cc1-A9509` |
| 25 | Comet Catcher Remake 1.8 | Armada | 9510 | 0 | w | 25.0 | x3.76 | 3ea746d562+38ece9595056, ? | `matches/tk1-v0-cc1-A9510` |
| 26 | Comet Catcher Remake 1.8 | Armada | 9511 | 0 | L | 23.63 | x0.43 | 3ea746d562+38ece9595056, ? | `matches/tk1-v0-cc1-A9511` |
| 27 | Comet Catcher Remake 1.8 | Armada | 9512 | 0 | L | 18.55 | - | 3ea746d562+38ece9595056, ? | `matches/tk1-v0-cc1-A9512` |
| 28 | Comet Catcher Remake 1.8 | Armada | 9513 | 0 | L | 24.16 | x0.93 | 3ea746d562+38ece9595056, ? | `matches/tk1-v0-cc1-A9513` |
| 29 | Comet Catcher Remake 1.8 | Armada | 9514 | 0 | w | 25.0 | x0.40 | 3ea746d562+38ece9595056, ? | `matches/tk1-v0-cc1-A9514` |
| 30 | Comet Catcher Remake 1.8 | Armada | 9515 | 0 | W | 24.9 | x3.74 | 3ea746d562+38ece9595056, ? | `matches/tk1-v0-cc1-A9515` |
| 31 | Comet Catcher Remake 1.8 | Armada | 9516 | 0 | L | 16.26 | - | 3ea746d562+38ece9595056, ? | `matches/tk1-v0-cc1-A9516` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.96 | - | - | n/a |
| t2->4th moho (min) | 5.18 | - | 3.00 | n/a |
| lab-job leaves/job | 0.35 | - | 0.00 | n/a |
| adv plant frame x | 2.30 | - | 1.50 | n/a |
| near-done /10k built | 0.46 | 0.00 | 0.00 | FAIL (worse than release, 100% of resamples) |
| t2 cons given early | 0.00 | 0.00 | 0.00 | ok |
| supers before 4 moho | 1.11 | - | 0.00 | n/a |
| lone t2 con minutes | 0.36 | - | 0.00 | n/a |
| base lost while 'covered' k | 2.55 | - | 0.00 | n/a |
| oldest plant order min | 1.64 | - | - | n/a |
| no t2 by minute 20 | 0.00 | 1.00 | - | ok |
| frozen minutes | 0.12 | 0.00 | 0.00 | ok, short of aim |
| com minutes on their half | 0.14 | 0.00 | - | ok |
| com lost on their half | 0.09 | 0.00 | 0.00 | worse, within noise (82% of resamples) |
| mex lost to ticks by 10 min | 3.69 | 0.31 | 0.00 | FAIL (worse than release, 100% of resamples) |
| their mex killed /10min (neg) | -16.17 | -21.89 | - | FAIL (worse than release, 98% of resamples) |
| their army / ours, 8-12 min | 0.92 | - | - | n/a |
| lost per killed | 1.21 | 1.21 | - | ok |
| reclaimed / killed (neg) | -0.18 | -0.05 | - | ok |
| bare-hands minutes | 0.19 | 0.00 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.14 | - | 0.00 | n/a |
| runs turned back | 0.00 | - | 0.00 | n/a |
| gunships sent to lose | 0.00 | - | 0.00 | n/a |
| stacked radar/jammers | 0.03 | - | 0.00 | n/a |
| army stuck /10min/1k army | 4.60 | 0.00 | 0.00 | FAIL (worse than release, 100% of resamples) |
| ground given up share | 0.32 | - | 0.00 | n/a |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.43 | -2.59 | - | FAIL (worse than release, 100% of resamples) |
| army share (neg) | 0.41 | 0.88 | - | FAIL (worse than release, 100% of resamples) |
| -log income at 20 | -5.19 | -5.10 | - | ok |
| games won or ahead | 0.28 | 0.50 | - | FAIL (does not beat the release, 100% of resamples) |

Contract: **FAIL (7)** over 32 games (32 of our seats, 32 release seats); 6 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.15 (run `python tools/anomaly.py build`)
```
