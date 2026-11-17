<!-- meta {"date": "2026-11-17", "topic": "v0515", "title": "tk2: per-mex defence floor held before any attack is measured (apex_mex_floor_unmeasured 1 vs 0) vs WRDistilled 0.4, both +50, Armada, Comet Catcher 1v1, 16 seeds", "games": 32, "W": 4, "L": 18, "w": 8, "l": 2, "inc20": 0.84, "verdict": "Turrets priced from 46 s instead of ~3 min, but the decision did not move: first turret order median 2.8 min both arms, turret orders before 4 min 5.4 vs 6.5, extractors lost to Ticks by 10 min 55 vs 50 (3.44 vs 3.12 a seat), won or ahead 4 vs 7. Removed. A priced turret still loses to the extractor's net tilt (x7-24); and 23 of ~50 Tick-killed extractors had a turret ordered within 600 beforehand (late, or not covering)."} -->
# tk2: per-mex defence floor held before any attack is measured (apex_mex_floor_unmeasured 1 vs 0) vs WRDistilled 0.4, both +50, Armada, Comet Catcher 1v1, 16 seeds

- **Date:** 2026-11-17
- **Topic:** v0515
- **Purpose:** Found in tkdbg-9601: DefenceTarget x measured attack rate is 0 before the first raid kills something, so every turret priced -1 until a Tick had taken an extractor.
- **Result:** 32 games: won 4, lost 18, timeouts ahead 8, behind 2; income at 20 min x0.84 ours/theirs
- **Verdict:** Turrets priced from 46 s instead of ~3 min, but the decision did not move: first turret order median 2.8 min both arms, turret orders before 4 min 5.4 vs 6.5, extractors lost to Ticks by 10 min 55 vs 50 (3.44 vs 3.12 a seat), won or ahead 4 vs 7. Removed. A priced turret still loses to the extractor's net tilt (x7-24); and 23 of ~50 Tick-killed extractors had a turret ordered within 600 beforehand (late, or not covering).
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** WRDistilled-0.4
- **Code:** Apexestall-lane-estall-standard = `3ea746d562+6d1c857dfceb` (32 games); WRDistilled-0.4 = `?` (32 games)
- **Maps:** Comet Catcher Remake 1.8
- **Sides:** Armada; **bonus:** 50; **time cap:** 25 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b WRDistilled:0.4 --per-side 1 --map Comet Catcher Remake 1.8 --minutes 25 --speed 20 --handicap 50 --sides Armada,Armada --seed 9601 --ai-option apex_mex_floor_unmeasured=1 --out matches/tk2-v1-cc1-A9601`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9601 | 0 | L | 20.15 | x0.06 | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v1-cc1-A9601` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9602 | 0 | L | 18.48 | - | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v1-cc1-A9602` |
| 2 | Comet Catcher Remake 1.8 | Armada | 9603 | 0 | w | 25.0 | x1.08 | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v1-cc1-A9603` |
| 3 | Comet Catcher Remake 1.8 | Armada | 9604 | 0 | L | 21.03 | x0.09 | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v1-cc1-A9604` |
| 4 | Comet Catcher Remake 1.8 | Armada | 9605 | 0 | L | 19.73 | - | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v1-cc1-A9605` |
| 5 | Comet Catcher Remake 1.8 | Armada | 9606 | 0 | W | 21.27 | x5.97 | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v1-cc1-A9606` |
| 6 | Comet Catcher Remake 1.8 | Armada | 9607 | 0 | L | 19.66 | - | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v1-cc1-A9607` |
| 7 | Comet Catcher Remake 1.8 | Armada | 9608 | 0 | W | 16.18 | - | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v1-cc1-A9608` |
| 8 | Comet Catcher Remake 1.8 | Armada | 9609 | 0 | l | 25.0 | x0.97 | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v1-cc1-A9609` |
| 9 | Comet Catcher Remake 1.8 | Armada | 9610 | 0 | L | 22.89 | x0.30 | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v1-cc1-A9610` |
| 10 | Comet Catcher Remake 1.8 | Armada | 9611 | 0 | L | 12.67 | - | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v1-cc1-A9611` |
| 11 | Comet Catcher Remake 1.8 | Armada | 9612 | 0 | L | 12.35 | - | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v1-cc1-A9612` |
| 12 | Comet Catcher Remake 1.8 | Armada | 9613 | 0 | L | 18.6 | - | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v1-cc1-A9613` |
| 13 | Comet Catcher Remake 1.8 | Armada | 9614 | 0 | L | 13.18 | - | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v1-cc1-A9614` |
| 14 | Comet Catcher Remake 1.8 | Armada | 9615 | 0 | L | 23.45 | x0.49 | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v1-cc1-A9615` |
| 15 | Comet Catcher Remake 1.8 | Armada | 9616 | 0 | w | 25.0 | x2.87 | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v1-cc1-A9616` |
| 16 | Comet Catcher Remake 1.8 | Armada | 9601 | 0 | L | 21.01 | x0.18 | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v0-cc1-A9601` |
| 17 | Comet Catcher Remake 1.8 | Armada | 9602 | 0 | W | 23.03 | x3.39 | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v0-cc1-A9602` |
| 18 | Comet Catcher Remake 1.8 | Armada | 9603 | 0 | L | 18.11 | - | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v0-cc1-A9603` |
| 19 | Comet Catcher Remake 1.8 | Armada | 9604 | 0 | w | 25.0 | x3.23 | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v0-cc1-A9604` |
| 20 | Comet Catcher Remake 1.8 | Armada | 9605 | 0 | w | 25.0 | x0.81 | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v0-cc1-A9605` |
| 21 | Comet Catcher Remake 1.8 | Armada | 9606 | 0 | L | 24.36 | x0.37 | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v0-cc1-A9606` |
| 22 | Comet Catcher Remake 1.8 | Armada | 9607 | 0 | W | 19.14 | - | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v0-cc1-A9607` |
| 23 | Comet Catcher Remake 1.8 | Armada | 9608 | 0 | l | 25.0 | x1.02 | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v0-cc1-A9608` |
| 24 | Comet Catcher Remake 1.8 | Armada | 9609 | 0 | w | 25.0 | x1.22 | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v0-cc1-A9609` |
| 25 | Comet Catcher Remake 1.8 | Armada | 9610 | 0 | w | 25.0 | x4.00 | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v0-cc1-A9610` |
| 26 | Comet Catcher Remake 1.8 | Armada | 9611 | 0 | L | 22.55 | x0.09 | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v0-cc1-A9611` |
| 27 | Comet Catcher Remake 1.8 | Armada | 9612 | 0 | L | 20.35 | x0.53 | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v0-cc1-A9612` |
| 28 | Comet Catcher Remake 1.8 | Armada | 9613 | 0 | L | 18.14 | - | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v0-cc1-A9613` |
| 29 | Comet Catcher Remake 1.8 | Armada | 9614 | 0 | w | 25.0 | x2.60 | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v0-cc1-A9614` |
| 30 | Comet Catcher Remake 1.8 | Armada | 9615 | 0 | w | 25.0 | x2.37 | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v0-cc1-A9615` |
| 31 | Comet Catcher Remake 1.8 | Armada | 9616 | 0 | L | 20.59 | x1.83 | 3ea746d562+6d1c857dfceb, ? | `matches/tk2-v0-cc1-A9616` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.60 | - | - | n/a |
| t2->4th moho (min) | 5.48 | - | 3.00 | n/a |
| lab-job leaves/job | 0.34 | - | 0.00 | n/a |
| adv plant frame x | 2.26 | - | 1.50 | n/a |
| near-done /10k built | 0.59 | 0.00 | 0.00 | FAIL (worse than release, 100% of resamples) |
| t2 cons given early | 0.00 | 0.00 | 0.00 | ok |
| supers before 4 moho | 0.90 | - | 0.00 | n/a |
| lone t2 con minutes | 0.33 | - | 0.00 | n/a |
| base lost while 'covered' k | 2.18 | - | 0.00 | n/a |
| oldest plant order min | 1.69 | - | - | n/a |
| no t2 by minute 20 | 0.05 | 1.00 | - | ok |
| frozen minutes | 0.06 | 0.00 | 0.00 | ok, short of aim |
| com minutes on their half | 0.34 | 0.00 | - | ok |
| com lost on their half | 0.12 | 0.00 | 0.00 | FAIL (worse than release, 93% of resamples) |
| mex lost to ticks by 10 min | 3.28 | 0.41 | 0.00 | FAIL (worse than release, 100% of resamples) |
| their mex killed /10min (neg) | -16.90 | -19.39 | - | worse, within noise (58% of resamples) |
| their army / ours, 8-12 min | 0.75 | - | - | n/a |
| lost per killed | 1.17 | 1.16 | - | ok |
| reclaimed / killed (neg) | -0.19 | -0.04 | - | ok |
| bare-hands minutes | 0.06 | 0.06 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.35 | - | 0.00 | n/a |
| runs turned back | 0.04 | - | 0.00 | n/a |
| gunships sent to lose | 0.00 | - | 0.00 | n/a |
| stacked radar/jammers | 0.00 | - | 0.00 | n/a |
| army stuck /10min/1k army | 4.11 | 0.00 | 0.00 | FAIL (worse than release, 100% of resamples) |
| ground given up share | 0.32 | - | 0.00 | n/a |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.40 | -2.50 | - | FAIL (worse than release, 100% of resamples) |
| army share (neg) | 0.40 | 0.86 | - | FAIL (worse than release, 100% of resamples) |
| -log income at 20 | -4.89 | -4.98 | - | ok |
| games won or ahead | 0.34 | 0.50 | - | FAIL (does not beat the release, 95% of resamples) |

Contract: **FAIL (7)** over 32 games (32 of our seats, 32 release seats); 6 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.15 (run `python tools/anomaly.py build`)
```
