<!-- meta {"date": "2026-11-17", "topic": "v0515", "title": "rz3: resurrection fleet cap off (apex_medic_frac 0) vs 12% of army (0.12) vs WRDistilled 0.4, both +50, Armada, Comet Catcher 1v1, 24 new seeds", "games": 48, "W": 6, "L": 14, "w": 20, "l": 8, "inc20": 1.06, "verdict": "Held in direction: won or ahead 12 (cap off) vs 9; kill minus lost better in 12 of 24 (mean +4.3k, t=0.73); lost per killed 0.97 vs 1.15; reclaimed/killed 0.21 vs 0.16; their army / ours 0.49 vs 0.88. Pooled rz1-rz3, 48 pairs: won or ahead 21 vs 16, kill minus lost better in 28 (mean +7.2k, t=1.69), lost per killed 1.06 vs 1.25, reclaimed/killed 0.19 vs 0.17. Cap deleted (TUNE_MEDIC_FRAC); RezFleetCap still bounds the fleet."} -->
# rz3: resurrection fleet cap off (apex_medic_frac 0) vs 12% of army (0.12) vs WRDistilled 0.4, both +50, Armada, Comet Catcher 1v1, 24 new seeds

- **Date:** 2026-11-17
- **Topic:** v0515
- **Purpose:** His 11-17: run 24 more pairs, lift the cap if the result holds.
- **Result:** 48 games: won 6, lost 14, timeouts ahead 20, behind 8; income at 20 min x1.06 ours/theirs
- **Verdict:** Held in direction: won or ahead 12 (cap off) vs 9; kill minus lost better in 12 of 24 (mean +4.3k, t=0.73); lost per killed 0.97 vs 1.15; reclaimed/killed 0.21 vs 0.16; their army / ours 0.49 vs 0.88. Pooled rz1-rz3, 48 pairs: won or ahead 21 vs 16, kill minus lost better in 28 (mean +7.2k, t=1.69), lost per killed 1.06 vs 1.25, reclaimed/killed 0.19 vs 0.17. Cap deleted (TUNE_MEDIC_FRAC); RezFleetCap still bounds the fleet.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** WRDistilled-0.4
- **Code:** Apexestall-lane-estall-standard = `d65ee24aca+feb79889ce75` (48 games); WRDistilled-0.4 = `?` (48 games)
- **Maps:** Comet Catcher Remake 1.8
- **Sides:** Armada; **bonus:** 50; **time cap:** 25 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b WRDistilled:0.4 --per-side 1 --map Comet Catcher Remake 1.8 --minutes 25 --speed 20 --handicap 50 --sides Armada,Armada --seed 9225 --ai-option apex_medic_frac=0.12 --out matches/rz3-v0.12-cc1-A9225`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9225 | 0 | L | 21.17 | x0.64 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0.12-cc1-A9225` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9226 | 0 | l | 25.0 | x0.48 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0.12-cc1-A9226` |
| 2 | Comet Catcher Remake 1.8 | Armada | 9227 | 0 | L | 22.16 | x0.44 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0.12-cc1-A9227` |
| 3 | Comet Catcher Remake 1.8 | Armada | 9228 | 0 | L | 20.92 | x0.23 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0.12-cc1-A9228` |
| 4 | Comet Catcher Remake 1.8 | Armada | 9229 | 0 | L | 18.66 | - | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0.12-cc1-A9229` |
| 5 | Comet Catcher Remake 1.8 | Armada | 9230 | 0 | w | 25.0 | x2.72 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0.12-cc1-A9230` |
| 6 | Comet Catcher Remake 1.8 | Armada | 9231 | 0 | L | 11.51 | - | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0.12-cc1-A9231` |
| 7 | Comet Catcher Remake 1.8 | Armada | 9232 | 0 | L | 19.9 | - | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0.12-cc1-A9232` |
| 8 | Comet Catcher Remake 1.8 | Armada | 9233 | 0 | W | 23.77 | x3.90 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0.12-cc1-A9233` |
| 9 | Comet Catcher Remake 1.8 | Armada | 9234 | 0 | l | 25.0 | x0.60 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0.12-cc1-A9234` |
| 10 | Comet Catcher Remake 1.8 | Armada | 9235 | 0 | l | 25.0 | x0.52 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0.12-cc1-A9235` |
| 11 | Comet Catcher Remake 1.8 | Armada | 9236 | 0 | w | 25.0 | x2.07 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0.12-cc1-A9236` |
| 12 | Comet Catcher Remake 1.8 | Armada | 9237 | 0 | l | 25.0 | x0.73 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0.12-cc1-A9237` |
| 13 | Comet Catcher Remake 1.8 | Armada | 9238 | 0 | l | 25.0 | x0.37 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0.12-cc1-A9238` |
| 14 | Comet Catcher Remake 1.8 | Armada | 9239 | 0 | w | 25.0 | x1.59 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0.12-cc1-A9239` |
| 15 | Comet Catcher Remake 1.8 | Armada | 9240 | 0 | w | 25.0 | x2.74 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0.12-cc1-A9240` |
| 16 | Comet Catcher Remake 1.8 | Armada | 9241 | 0 | L | 19.23 | - | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0.12-cc1-A9241` |
| 17 | Comet Catcher Remake 1.8 | Armada | 9242 | 0 | L | 20.11 | x0.15 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0.12-cc1-A9242` |
| 18 | Comet Catcher Remake 1.8 | Armada | 9243 | 0 | W | 24.84 | x2.84 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0.12-cc1-A9243` |
| 19 | Comet Catcher Remake 1.8 | Armada | 9244 | 0 | L | 19.95 | - | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0.12-cc1-A9244` |
| 20 | Comet Catcher Remake 1.8 | Armada | 9245 | 0 | L | 21.75 | x0.35 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0.12-cc1-A9245` |
| 21 | Comet Catcher Remake 1.8 | Armada | 9246 | 0 | w | 25.0 | x3.12 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0.12-cc1-A9246` |
| 22 | Comet Catcher Remake 1.8 | Armada | 9247 | 0 | l | 25.0 | x2.01 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0.12-cc1-A9247` |
| 23 | Comet Catcher Remake 1.8 | Armada | 9248 | 0 | w | 25.0 | x2.62 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0.12-cc1-A9248` |
| 24 | Comet Catcher Remake 1.8 | Armada | 9225 | 0 | w | 25.0 | x1.14 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0-cc1-A9225` |
| 25 | Comet Catcher Remake 1.8 | Armada | 9226 | 0 | l | 25.0 | x1.10 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0-cc1-A9226` |
| 26 | Comet Catcher Remake 1.8 | Armada | 9227 | 0 | L | 22.03 | x0.59 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0-cc1-A9227` |
| 27 | Comet Catcher Remake 1.8 | Armada | 9228 | 0 | L | 16.5 | - | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0-cc1-A9228` |
| 28 | Comet Catcher Remake 1.8 | Armada | 9229 | 0 | L | 22.34 | x2.77 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0-cc1-A9229` |
| 29 | Comet Catcher Remake 1.8 | Armada | 9230 | 0 | L | 21.97 | x0.52 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0-cc1-A9230` |
| 30 | Comet Catcher Remake 1.8 | Armada | 9231 | 0 | w | 25.0 | x0.23 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0-cc1-A9231` |
| 31 | Comet Catcher Remake 1.8 | Armada | 9232 | 0 | W | 24.13 | x3.68 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0-cc1-A9232` |
| 32 | Comet Catcher Remake 1.8 | Armada | 9233 | 0 | w | 25.0 | x0.54 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0-cc1-A9233` |
| 33 | Comet Catcher Remake 1.8 | Armada | 9234 | 0 | w | 25.0 | x1.18 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0-cc1-A9234` |
| 34 | Comet Catcher Remake 1.8 | Armada | 9235 | 0 | w | 25.0 | x0.76 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0-cc1-A9235` |
| 35 | Comet Catcher Remake 1.8 | Armada | 9236 | 0 | w | 25.0 | x2.00 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0-cc1-A9236` |
| 36 | Comet Catcher Remake 1.8 | Armada | 9237 | 0 | w | 25.0 | x0.94 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0-cc1-A9237` |
| 37 | Comet Catcher Remake 1.8 | Armada | 9238 | 0 | w | 25.0 | x1.61 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0-cc1-A9238` |
| 38 | Comet Catcher Remake 1.8 | Armada | 9239 | 0 | w | 25.0 | x1.95 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0-cc1-A9239` |
| 39 | Comet Catcher Remake 1.8 | Armada | 9240 | 0 | W | 24.45 | x2.18 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0-cc1-A9240` |
| 40 | Comet Catcher Remake 1.8 | Armada | 9241 | 0 | w | 25.0 | x1.67 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0-cc1-A9241` |
| 41 | Comet Catcher Remake 1.8 | Armada | 9242 | 0 | W | 18.61 | - | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0-cc1-A9242` |
| 42 | Comet Catcher Remake 1.8 | Armada | 9243 | 0 | w | 25.0 | x1.25 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0-cc1-A9243` |
| 43 | Comet Catcher Remake 1.8 | Armada | 9244 | 0 | w | 25.0 | x3.08 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0-cc1-A9244` |
| 44 | Comet Catcher Remake 1.8 | Armada | 9245 | 0 | w | 25.0 | x0.59 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0-cc1-A9245` |
| 45 | Comet Catcher Remake 1.8 | Armada | 9246 | 0 | w | 25.0 | x0.86 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0-cc1-A9246` |
| 46 | Comet Catcher Remake 1.8 | Armada | 9247 | 0 | l | 25.0 | x0.38 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0-cc1-A9247` |
| 47 | Comet Catcher Remake 1.8 | Armada | 9248 | 0 | W | 22.28 | x2.39 | ?, d65ee24aca+feb79889ce75 | `matches/rz3-v0-cc1-A9248` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.71 | - | - | n/a |
| t2->4th moho (min) | 5.18 | - | 3.00 | n/a |
| lab-job leaves/job | 0.43 | - | 0.00 | n/a |
| adv plant frame x | 2.40 | - | 1.50 | n/a |
| near-done /10k built | 0.53 | 0.00 | 0.00 | FAIL (worse than release, 100% of resamples) |
| t2 cons given early | 0.00 | 0.00 | 0.00 | ok |
| supers before 4 moho | 1.79 | - | 0.00 | n/a |
| lone t2 con minutes | 0.47 | - | 0.00 | n/a |
| base lost while 'covered' k | 1.91 | - | 0.00 | n/a |
| oldest plant order min | 1.98 | - | - | n/a |
| no t2 by minute 20 | 0.00 | 1.00 | - | ok |
| frozen minutes | 0.00 | 0.00 | 0.00 | ok |
| com minutes on their half | 0.09 | 0.00 | - | ok |
| com lost on their half | 0.00 | 0.00 | 0.00 | ok |
| mex lost to ticks by 10 min | 3.31 | 0.21 | 0.00 | FAIL (worse than release, 100% of resamples) |
| their mex killed /10min (neg) | -19.49 | -23.87 | - | FAIL (worse than release, 97% of resamples) |
| their army / ours, 8-12 min | 0.72 | - | - | n/a |
| lost per killed | 1.04 | 1.53 | - | ok |
| reclaimed / killed (neg) | -0.19 | -0.05 | - | ok |
| bare-hands minutes | 0.04 | 0.04 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.29 | - | 0.00 | n/a |
| runs turned back | 0.02 | - | 0.00 | n/a |
| gunships sent to lose | 0.00 | - | 0.00 | n/a |
| stacked radar/jammers | 0.02 | - | 0.00 | n/a |
| army stuck /10min/1k army | 3.53 | 0.00 | 0.00 | FAIL (worse than release, 100% of resamples) |
| ground given up share | 0.36 | - | 0.00 | n/a |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.43 | -2.50 | - | FAIL (worse than release, 100% of resamples) |
| army share (neg) | 0.40 | 0.89 | - | FAIL (worse than release, 100% of resamples) |
| -log income at 20 | -5.09 | -4.97 | - | ok |
| games won or ahead | 0.44 | 0.50 | - | under half, within noise (78% of resamples) |

Contract: **FAIL (6)** over 48 games (48 of our seats, 48 release seats); 4 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.15 (run `python tools/anomaly.py build`)
```
