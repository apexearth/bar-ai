<!-- meta {"date": "2026-11-17", "topic": "v0515", "title": "rs1: raiders keep raiding after T2 (apex_spam_send_raiders 0) vs sent as spam (1) vs WRDistilled 0.4, both +50, Armada, Comet Catcher 1v1, 16 seeds", "games": 32, "W": 3, "L": 14, "w": 12, "l": 3, "inc20": 0.72, "verdict": "No help, removed: raider extractor kills 18-24 min 23 vs 3, but ground RAID tasks did not rise (12-18 min 0.58 vs 0.94), their extractors killed /10 min 14.7 vs 18.6, won or ahead 4 vs 8, lost per killed 1.38 vs 0.93. Raiders kept from spam still do not form raids under the stock army; mid and late extractor kills come from attack pushes (Fido, Fatboy) and air."} -->
# rs1: raiders keep raiding after T2 (apex_spam_send_raiders 0) vs sent as spam (1) vs WRDistilled 0.4, both +50, Armada, Comet Catcher 1v1, 16 seeds

- **Date:** 2026-11-17
- **Topic:** v0515
- **Purpose:** His 11-17: we raid early but barely mid and late game. Found: after the T2 plant every raider is spam (one move at their base core, then idle).
- **Result:** 32 games: won 3, lost 14, timeouts ahead 12, behind 3; income at 20 min x0.72 ours/theirs
- **Verdict:** No help, removed: raider extractor kills 18-24 min 23 vs 3, but ground RAID tasks did not rise (12-18 min 0.58 vs 0.94), their extractors killed /10 min 14.7 vs 18.6, won or ahead 4 vs 8, lost per killed 1.38 vs 0.93. Raiders kept from spam still do not form raids under the stock army; mid and late extractor kills come from attack pushes (Fido, Fatboy) and air.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** WRDistilled-0.4
- **Code:** Apexestall-lane-estall-standard = `5ed7262470+9ac43145ba5c` (32 games); WRDistilled-0.4 = `?` (32 games)
- **Maps:** Comet Catcher Remake 1.8
- **Sides:** Armada; **bonus:** 50; **time cap:** 25 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b WRDistilled:0.4 --per-side 1 --map Comet Catcher Remake 1.8 --minutes 25 --speed 20 --handicap 50 --sides Armada,Armada --seed 9901 --ai-option apex_spam_send_raiders=0 --out matches/rs1-v0-cc1-A9901`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9901 | 0 | L | 18.78 | - | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v0-cc1-A9901` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9902 | 0 | w | 25.0 | x1.10 | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v0-cc1-A9902` |
| 2 | Comet Catcher Remake 1.8 | Armada | 9903 | 0 | l | 25.0 | x0.86 | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v0-cc1-A9903` |
| 3 | Comet Catcher Remake 1.8 | Armada | 9904 | 0 | l | 25.0 | x0.37 | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v0-cc1-A9904` |
| 4 | Comet Catcher Remake 1.8 | Armada | 9905 | 0 | w | 25.0 | x0.72 | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v0-cc1-A9905` |
| 5 | Comet Catcher Remake 1.8 | Armada | 9906 | 0 | w | 25.0 | x3.96 | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v0-cc1-A9906` |
| 6 | Comet Catcher Remake 1.8 | Armada | 9907 | 0 | L | 14.62 | - | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v0-cc1-A9907` |
| 7 | Comet Catcher Remake 1.8 | Armada | 9908 | 0 | L | 23.21 | x0.01 | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v0-cc1-A9908` |
| 8 | Comet Catcher Remake 1.8 | Armada | 9909 | 0 | L | 23.8 | x0.50 | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v0-cc1-A9909` |
| 9 | Comet Catcher Remake 1.8 | Armada | 9910 | 0 | L | 18.75 | - | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v0-cc1-A9910` |
| 10 | Comet Catcher Remake 1.8 | Armada | 9911 | 0 | L | 17.16 | - | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v0-cc1-A9911` |
| 11 | Comet Catcher Remake 1.8 | Armada | 9912 | 0 | w | 25.0 | x1.85 | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v0-cc1-A9912` |
| 12 | Comet Catcher Remake 1.8 | Armada | 9913 | 0 | L | 23.04 | x0.03 | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v0-cc1-A9913` |
| 13 | Comet Catcher Remake 1.8 | Armada | 9914 | 0 | w | 25.0 | x0.98 | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v0-cc1-A9914` |
| 14 | Comet Catcher Remake 1.8 | Armada | 9915 | 0 | L | 24.37 | x1.83 | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v0-cc1-A9915` |
| 15 | Comet Catcher Remake 1.8 | Armada | 9916 | 0 | L | 15.45 | - | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v0-cc1-A9916` |
| 16 | Comet Catcher Remake 1.8 | Armada | 9901 | 0 | W | 20.92 | x3.63 | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v1-cc1-A9901` |
| 17 | Comet Catcher Remake 1.8 | Armada | 9902 | 0 | l | 25.0 | x0.44 | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v1-cc1-A9902` |
| 18 | Comet Catcher Remake 1.8 | Armada | 9903 | 0 | W | 17.84 | - | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v1-cc1-A9903` |
| 19 | Comet Catcher Remake 1.8 | Armada | 9904 | 0 | w | 25.0 | x2.22 | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v1-cc1-A9904` |
| 20 | Comet Catcher Remake 1.8 | Armada | 9905 | 0 | w | 25.0 | x2.00 | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v1-cc1-A9905` |
| 21 | Comet Catcher Remake 1.8 | Armada | 9906 | 0 | W | 14.72 | - | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v1-cc1-A9906` |
| 22 | Comet Catcher Remake 1.8 | Armada | 9907 | 0 | w | 25.0 | x1.69 | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v1-cc1-A9907` |
| 23 | Comet Catcher Remake 1.8 | Armada | 9908 | 0 | L | 20.15 | x0.03 | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v1-cc1-A9908` |
| 24 | Comet Catcher Remake 1.8 | Armada | 9909 | 0 | L | 17.0 | - | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v1-cc1-A9909` |
| 25 | Comet Catcher Remake 1.8 | Armada | 9910 | 0 | w | 25.0 | x1.13 | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v1-cc1-A9910` |
| 26 | Comet Catcher Remake 1.8 | Armada | 9911 | 0 | L | 23.51 | x1.04 | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v1-cc1-A9911` |
| 27 | Comet Catcher Remake 1.8 | Armada | 9912 | 0 | L | 17.74 | - | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v1-cc1-A9912` |
| 28 | Comet Catcher Remake 1.8 | Armada | 9913 | 0 | w | 25.0 | x1.74 | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v1-cc1-A9913` |
| 29 | Comet Catcher Remake 1.8 | Armada | 9914 | 0 | w | 25.0 | x1.66 | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v1-cc1-A9914` |
| 30 | Comet Catcher Remake 1.8 | Armada | 9915 | 0 | L | 9.17 | - | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v1-cc1-A9915` |
| 31 | Comet Catcher Remake 1.8 | Armada | 9916 | 0 | w | 25.0 | x1.17 | 5ed7262470+9ac43145ba5c, ? | `matches/rs1-v1-cc1-A9916` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.52 | - | - | n/a |
| t2->4th moho (min) | 5.01 | - | 3.00 | n/a |
| lab-job leaves/job | 0.47 | - | 0.00 | n/a |
| adv plant frame x | 2.41 | - | 1.50 | n/a |
| near-done /10k built | 0.45 | 0.00 | 0.00 | FAIL (worse than release, 100% of resamples) |
| t2 cons given early | 0.00 | 0.00 | 0.00 | ok |
| supers before 4 moho | 1.38 | - | 0.00 | n/a |
| lone t2 con minutes | 0.31 | - | 0.00 | n/a |
| base lost while 'covered' k | 3.08 | - | 0.00 | n/a |
| oldest plant order min | 1.55 | - | - | n/a |
| no t2 by minute 20 | 0.09 | 1.00 | - | ok |
| frozen minutes | 0.31 | 0.00 | 0.00 | ok, short of aim |
| com minutes on their half | 0.27 | 0.00 | - | ok |
| com lost on their half | 0.06 | 0.00 | 0.00 | worse, within noise (62% of resamples) |
| mex lost to ticks by 10 min | 3.25 | 0.12 | 0.00 | FAIL (worse than release, 100% of resamples) |
| their mex killed /10min (neg) | -16.64 | -21.26 | - | FAIL (worse than release, 96% of resamples) |
| their army / ours, 8-12 min | 0.87 | - | - | n/a |
| lost per killed | 1.07 | 1.31 | - | ok |
| reclaimed / killed (neg) | -0.19 | -0.05 | - | ok |
| bare-hands minutes | 0.19 | 0.00 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.29 | - | 0.00 | n/a |
| runs turned back | 0.00 | - | 0.00 | n/a |
| gunships sent to lose | 0.00 | - | 0.00 | n/a |
| stacked radar/jammers | 0.00 | - | 0.00 | n/a |
| army stuck /10min/1k army | 4.07 | 0.00 | 0.00 | FAIL (worse than release, 100% of resamples) |
| ground given up share | 0.35 | - | 0.00 | n/a |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.44 | -2.52 | - | FAIL (worse than release, 100% of resamples) |
| army share (neg) | 0.39 | 0.87 | - | FAIL (worse than release, 100% of resamples) |
| -log income at 20 | -5.09 | -5.07 | - | ok |
| games won or ahead | 0.38 | 0.50 | - | FAIL (does not beat the release) |

Contract: **FAIL (7)** over 32 games (32 of our seats, 32 release seats); 6 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.16 (run `python tools/anomaly.py build`)
```
