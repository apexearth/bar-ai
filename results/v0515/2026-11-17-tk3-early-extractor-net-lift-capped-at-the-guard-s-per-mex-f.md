<!-- meta {"date": "2026-11-17", "topic": "v0515", "title": "tk3: early extractor net lift capped at the guard's + per-mex floor unmeasured + bare rate for uncovered guards (apex_mex_tilt_cap 1 vs 0) vs WRDistilled 0.4, both +50, Armada, Comet Catcher 1v1, 16 seeds", "games": 32, "W": 0, "L": 17, "w": 12, "l": 3, "inc20": 1.17, "verdict": "Proven, made the code: extractors lost to Ticks by 10 min 37 (on) vs 70, fewer in 13 of 16 pairs (t=-4.66); first turret order 2.7 vs 3.1 min, turret orders before 4 min 6.6 vs 5.1; won or ahead 6 vs 4; kill minus lost better in 10 (+13.8k); lost per killed 0.95 vs 1.36; income at 20 ~217 vs ~156; their extractors killed /10 min 18.0 vs 16.6. 19 of 37 Tick-killed extractors still had a turret ordered within 600 before (step two)."} -->
# tk3: early extractor net lift capped at the guard's + per-mex floor unmeasured + bare rate for uncovered guards (apex_mex_tilt_cap 1 vs 0) vs WRDistilled 0.4, both +50, Armada, Comet Catcher 1v1, 16 seeds

- **Date:** 2026-11-17
- **Topic:** v0515
- **Purpose:** His 11-17: try capping the early extractor tilt (then why ordered guards are late). tk1/tk2 alone moved nothing; with the cap alone extractors still won on base gain (23-35 vs 8-9) because the guard read the quiet rate.
- **Result:** 32 games: won 0, lost 17, timeouts ahead 12, behind 3; income at 20 min x1.17 ours/theirs
- **Verdict:** Proven, made the code: extractors lost to Ticks by 10 min 37 (on) vs 70, fewer in 13 of 16 pairs (t=-4.66); first turret order 2.7 vs 3.1 min, turret orders before 4 min 6.6 vs 5.1; won or ahead 6 vs 4; kill minus lost better in 10 (+13.8k); lost per killed 0.95 vs 1.36; income at 20 ~217 vs ~156; their extractors killed /10 min 18.0 vs 16.6. 19 of 37 Tick-killed extractors still had a turret ordered within 600 before (step two).
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** WRDistilled-0.4
- **Code:** Apexestall-lane-estall-standard = `fe11f3ad04+dc811072ebe9` (32 games); WRDistilled-0.4 = `?` (32 games)
- **Maps:** Comet Catcher Remake 1.8
- **Sides:** Armada; **bonus:** 50; **time cap:** 25 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b WRDistilled:0.4 --per-side 1 --map Comet Catcher Remake 1.8 --minutes 25 --speed 20 --handicap 50 --sides Armada,Armada --seed 9701 --ai-option apex_mex_tilt_cap=1 --out matches/tk3-v1-cc1-A9701`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9701 | 0 | w | 25.0 | x1.32 | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v1-cc1-A9701` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9702 | 0 | L | 16.27 | - | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v1-cc1-A9702` |
| 2 | Comet Catcher Remake 1.8 | Armada | 9703 | 0 | w | 25.0 | x2.58 | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v1-cc1-A9703` |
| 3 | Comet Catcher Remake 1.8 | Armada | 9704 | 0 | L | 20.85 | x1.31 | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v1-cc1-A9704` |
| 4 | Comet Catcher Remake 1.8 | Armada | 9705 | 0 | w | 25.0 | x3.13 | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v1-cc1-A9705` |
| 5 | Comet Catcher Remake 1.8 | Armada | 9706 | 0 | w | 25.0 | x1.68 | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v1-cc1-A9706` |
| 6 | Comet Catcher Remake 1.8 | Armada | 9707 | 0 | l | 25.0 | x1.04 | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v1-cc1-A9707` |
| 7 | Comet Catcher Remake 1.8 | Armada | 9708 | 0 | L | 22.53 | x1.81 | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v1-cc1-A9708` |
| 8 | Comet Catcher Remake 1.8 | Armada | 9709 | 0 | L | 18.37 | - | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v1-cc1-A9709` |
| 9 | Comet Catcher Remake 1.8 | Armada | 9710 | 0 | L | 18.06 | - | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v1-cc1-A9710` |
| 10 | Comet Catcher Remake 1.8 | Armada | 9711 | 0 | L | 17.7 | - | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v1-cc1-A9711` |
| 11 | Comet Catcher Remake 1.8 | Armada | 9712 | 0 | w | 25.0 | x1.33 | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v1-cc1-A9712` |
| 12 | Comet Catcher Remake 1.8 | Armada | 9713 | 0 | l | 25.0 | x0.25 | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v1-cc1-A9713` |
| 13 | Comet Catcher Remake 1.8 | Armada | 9714 | 0 | l | 25.0 | x0.59 | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v1-cc1-A9714` |
| 14 | Comet Catcher Remake 1.8 | Armada | 9715 | 0 | w | 25.0 | x2.47 | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v1-cc1-A9715` |
| 15 | Comet Catcher Remake 1.8 | Armada | 9716 | 0 | w | 25.0 | x1.89 | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v1-cc1-A9716` |
| 16 | Comet Catcher Remake 1.8 | Armada | 9701 | 0 | L | 24.83 | x1.52 | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v0-cc1-A9701` |
| 17 | Comet Catcher Remake 1.8 | Armada | 9702 | 0 | L | 24.18 | x0.98 | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v0-cc1-A9702` |
| 18 | Comet Catcher Remake 1.8 | Armada | 9703 | 0 | w | 25.0 | x1.86 | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v0-cc1-A9703` |
| 19 | Comet Catcher Remake 1.8 | Armada | 9704 | 0 | w | 25.0 | x0.87 | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v0-cc1-A9704` |
| 20 | Comet Catcher Remake 1.8 | Armada | 9705 | 0 | L | 23.52 | x0.94 | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v0-cc1-A9705` |
| 21 | Comet Catcher Remake 1.8 | Armada | 9706 | 0 | L | 17.97 | - | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v0-cc1-A9706` |
| 22 | Comet Catcher Remake 1.8 | Armada | 9707 | 0 | L | 22.01 | x0.86 | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v0-cc1-A9707` |
| 23 | Comet Catcher Remake 1.8 | Armada | 9708 | 0 | w | 25.0 | x0.52 | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v0-cc1-A9708` |
| 24 | Comet Catcher Remake 1.8 | Armada | 9709 | 0 | L | 19.11 | - | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v0-cc1-A9709` |
| 25 | Comet Catcher Remake 1.8 | Armada | 9710 | 0 | w | 25.0 | x3.44 | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v0-cc1-A9710` |
| 26 | Comet Catcher Remake 1.8 | Armada | 9711 | 0 | w | 25.0 | x2.13 | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v0-cc1-A9711` |
| 27 | Comet Catcher Remake 1.8 | Armada | 9712 | 0 | L | 24.54 | x0.32 | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v0-cc1-A9712` |
| 28 | Comet Catcher Remake 1.8 | Armada | 9713 | 0 | L | 24.19 | x1.12 | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v0-cc1-A9713` |
| 29 | Comet Catcher Remake 1.8 | Armada | 9714 | 0 | L | 22.71 | x0.39 | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v0-cc1-A9714` |
| 30 | Comet Catcher Remake 1.8 | Armada | 9715 | 0 | L | 18.84 | - | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v0-cc1-A9715` |
| 31 | Comet Catcher Remake 1.8 | Armada | 9716 | 0 | L | 14.52 | - | ?, fe11f3ad04+dc811072ebe9 | `matches/tk3-v0-cc1-A9716` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.02 | - | - | n/a |
| t2->4th moho (min) | 4.46 | - | 3.00 | n/a |
| lab-job leaves/job | 0.46 | - | 0.00 | n/a |
| adv plant frame x | 2.60 | - | 1.50 | n/a |
| near-done /10k built | 0.61 | 0.00 | 0.00 | FAIL (worse than release, 100% of resamples) |
| t2 cons given early | 0.00 | 0.00 | 0.00 | ok |
| supers before 4 moho | 1.25 | - | 0.00 | n/a |
| lone t2 con minutes | 0.56 | - | 0.00 | n/a |
| base lost while 'covered' k | 2.78 | - | 0.00 | n/a |
| oldest plant order min | 1.69 | - | - | n/a |
| no t2 by minute 20 | 0.00 | 1.00 | - | ok |
| frozen minutes | 0.06 | 0.00 | 0.00 | ok, short of aim |
| com minutes on their half | 0.45 | 0.00 | - | ok |
| com lost on their half | 0.06 | 0.00 | 0.00 | worse, within noise (62% of resamples) |
| mex lost to ticks by 10 min | 3.34 | 0.31 | 0.00 | FAIL (worse than release, 100% of resamples) |
| their mex killed /10min (neg) | -17.29 | -23.87 | - | FAIL (worse than release, 100% of resamples) |
| their army / ours, 8-12 min | 1.06 | - | - | n/a |
| lost per killed | 1.15 | 1.27 | - | ok |
| reclaimed / killed (neg) | -0.20 | -0.04 | - | ok |
| bare-hands minutes | 0.12 | 0.06 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.29 | - | 0.00 | n/a |
| runs turned back | 0.00 | - | 0.00 | n/a |
| gunships sent to lose | 0.00 | - | 0.00 | n/a |
| stacked radar/jammers | 0.00 | - | 0.00 | n/a |
| army stuck /10min/1k army | 3.65 | 0.00 | 0.00 | FAIL (worse than release, 100% of resamples) |
| ground given up share | 0.33 | - | 0.00 | n/a |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.47 | -2.61 | - | FAIL (worse than release, 100% of resamples) |
| army share (neg) | 0.39 | 0.90 | - | FAIL (worse than release, 100% of resamples) |
| -log income at 20 | -5.27 | -5.07 | - | ok |
| games won or ahead | 0.31 | 0.50 | - | FAIL (does not beat the release, 98% of resamples) |

Contract: **FAIL (7)** over 32 games (32 of our seats, 32 release seats); 6 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.15 (run `python tools/anomaly.py build`)
```
