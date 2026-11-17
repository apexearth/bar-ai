<!-- meta {"date": "2026-11-17", "topic": "v0515", "title": "rz2: resurrection fleet cap off (apex_medic_frac 0) vs 12% of army (0.12, release) vs WRDistilled 0.4, both +50, Armada, Comet Catcher 1v1, 12 new seeds", "games": 24, "W": 5, "L": 11, "w": 5, "l": 3, "inc20": 0.73, "verdict": "Same direction, still not proven. rz2 alone: won or ahead 5 (cap off) vs 4; lost per killed 1.11 vs 1.45; kill 50.7k vs 31.1k, lost 47.3k vs 40.0k; mean fleet 5.7 vs 3.9. Pooled rz1+rz2, 24 pairs: won or ahead 9 vs 7; kill minus lost better with the cap off in 16 of 24, mean +10.0k (sd 30.2k, paired t=1.63, p~0.12); lost per killed 1.09 vs 1.58; reclaimed/killed 0.16 vs 0.17 (unchanged: more is reclaimed only because more is killed). Not changed in the AI: switching off a cap is his call, and the evidence is under the bar."} -->
# rz2: resurrection fleet cap off (apex_medic_frac 0) vs 12% of army (0.12, release) vs WRDistilled 0.4, both +50, Armada, Comet Catcher 1v1, 12 new seeds

- **Date:** 2026-11-17
- **Topic:** v0515
- **Purpose:** Confirms rz1 on seeds 9213-9224 before the 12% cap on the resurrection fleet is lifted (his 11-16 heavy-army strategy: resbots eat the reclaim, win on the trade).
- **Result:** 24 games: won 5, lost 11, timeouts ahead 5, behind 3; income at 20 min x0.73 ours/theirs
- **Verdict:** Same direction, still not proven. rz2 alone: won or ahead 5 (cap off) vs 4; lost per killed 1.11 vs 1.45; kill 50.7k vs 31.1k, lost 47.3k vs 40.0k; mean fleet 5.7 vs 3.9. Pooled rz1+rz2, 24 pairs: won or ahead 9 vs 7; kill minus lost better with the cap off in 16 of 24, mean +10.0k (sd 30.2k, paired t=1.63, p~0.12); lost per killed 1.09 vs 1.58; reclaimed/killed 0.16 vs 0.17 (unchanged: more is reclaimed only because more is killed). Not changed in the AI: switching off a cap is his call, and the evidence is under the bar.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** WRDistilled-0.4
- **Code:** Apexestall-lane-estall-standard = `6fc9a74aef+ed47322b3619` (24 games); WRDistilled-0.4 = `?` (24 games)
- **Maps:** Comet Catcher Remake 1.8
- **Sides:** Armada; **bonus:** 50; **time cap:** 25 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b WRDistilled:0.4 --per-side 1 --map Comet Catcher Remake 1.8 --minutes 25 --speed 20 --handicap 50 --sides Armada,Armada --seed 9213 --ai-option apex_medic_frac=0.12 --out matches/rz2-v0.12-cc1-A9213`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9213 | 0 | L | 22.29 | x0.21 | 6fc9a74aef+ed47322b3619, ? | `matches/rz2-v0.12-cc1-A9213` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9214 | 0 | W | 19.71 | - | 6fc9a74aef+ed47322b3619, ? | `matches/rz2-v0.12-cc1-A9214` |
| 2 | Comet Catcher Remake 1.8 | Armada | 9215 | 0 | W | 21.46 | x26.19 | 6fc9a74aef+ed47322b3619, ? | `matches/rz2-v0.12-cc1-A9215` |
| 3 | Comet Catcher Remake 1.8 | Armada | 9216 | 0 | L | 11.59 | - | 6fc9a74aef+ed47322b3619, ? | `matches/rz2-v0.12-cc1-A9216` |
| 4 | Comet Catcher Remake 1.8 | Armada | 9217 | 0 | L | 17.87 | - | 6fc9a74aef+ed47322b3619, ? | `matches/rz2-v0.12-cc1-A9217` |
| 5 | Comet Catcher Remake 1.8 | Armada | 9218 | 0 | W | 14.97 | - | 6fc9a74aef+ed47322b3619, ? | `matches/rz2-v0.12-cc1-A9218` |
| 6 | Comet Catcher Remake 1.8 | Armada | 9219 | 0 | L | 21.36 | x0.30 | 6fc9a74aef+ed47322b3619, ? | `matches/rz2-v0.12-cc1-A9219` |
| 7 | Comet Catcher Remake 1.8 | Armada | 9220 | 0 | w | 25.0 | x1.28 | 6fc9a74aef+ed47322b3619, ? | `matches/rz2-v0.12-cc1-A9220` |
| 8 | Comet Catcher Remake 1.8 | Armada | 9221 | 0 | L | 24.57 | x0.65 | 6fc9a74aef+ed47322b3619, ? | `matches/rz2-v0.12-cc1-A9221` |
| 9 | Comet Catcher Remake 1.8 | Armada | 9222 | 0 | l | 25.0 | x0.93 | 6fc9a74aef+ed47322b3619, ? | `matches/rz2-v0.12-cc1-A9222` |
| 10 | Comet Catcher Remake 1.8 | Armada | 9223 | 0 | L | 22.58 | x0.13 | 6fc9a74aef+ed47322b3619, ? | `matches/rz2-v0.12-cc1-A9223` |
| 11 | Comet Catcher Remake 1.8 | Armada | 9224 | 0 | L | 16.23 | - | 6fc9a74aef+ed47322b3619, ? | `matches/rz2-v0.12-cc1-A9224` |
| 12 | Comet Catcher Remake 1.8 | Armada | 9213 | 0 | w | 25.0 | x1.84 | 6fc9a74aef+ed47322b3619, ? | `matches/rz2-v0-cc1-A9213` |
| 13 | Comet Catcher Remake 1.8 | Armada | 9214 | 0 | l | 25.0 | x0.77 | 6fc9a74aef+ed47322b3619, ? | `matches/rz2-v0-cc1-A9214` |
| 14 | Comet Catcher Remake 1.8 | Armada | 9215 | 0 | l | 25.0 | x0.45 | 6fc9a74aef+ed47322b3619, ? | `matches/rz2-v0-cc1-A9215` |
| 15 | Comet Catcher Remake 1.8 | Armada | 9216 | 0 | L | 19.08 | - | 6fc9a74aef+ed47322b3619, ? | `matches/rz2-v0-cc1-A9216` |
| 16 | Comet Catcher Remake 1.8 | Armada | 9217 | 0 | L | 11.68 | - | 6fc9a74aef+ed47322b3619, ? | `matches/rz2-v0-cc1-A9217` |
| 17 | Comet Catcher Remake 1.8 | Armada | 9218 | 0 | W | 24.72 | x1.48 | 6fc9a74aef+ed47322b3619, ? | `matches/rz2-v0-cc1-A9218` |
| 18 | Comet Catcher Remake 1.8 | Armada | 9219 | 0 | w | 25.0 | x0.37 | 6fc9a74aef+ed47322b3619, ? | `matches/rz2-v0-cc1-A9219` |
| 19 | Comet Catcher Remake 1.8 | Armada | 9220 | 0 | w | 25.0 | x1.94 | 6fc9a74aef+ed47322b3619, ? | `matches/rz2-v0-cc1-A9220` |
| 20 | Comet Catcher Remake 1.8 | Armada | 9221 | 0 | L | 16.19 | - | 6fc9a74aef+ed47322b3619, ? | `matches/rz2-v0-cc1-A9221` |
| 21 | Comet Catcher Remake 1.8 | Armada | 9222 | 0 | W | 24.14 | x2.13 | 6fc9a74aef+ed47322b3619, ? | `matches/rz2-v0-cc1-A9222` |
| 22 | Comet Catcher Remake 1.8 | Armada | 9223 | 0 | w | 25.0 | x1.89 | 6fc9a74aef+ed47322b3619, ? | `matches/rz2-v0-cc1-A9223` |
| 23 | Comet Catcher Remake 1.8 | Armada | 9224 | 0 | L | 20.45 | x0.01 | 6fc9a74aef+ed47322b3619, ? | `matches/rz2-v0-cc1-A9224` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.14 | - | - | n/a |
| t2->4th moho (min) | 4.44 | - | 3.00 | n/a |
| lab-job leaves/job | 0.29 | - | 0.00 | n/a |
| adv plant frame x | 2.49 | - | 1.50 | n/a |
| near-done /10k built | 0.68 | 0.00 | 0.00 | FAIL (worse than release) |
| t2 cons given early | 0.00 | 0.00 | 0.00 | ok |
| supers before 4 moho | 1.14 | - | 0.00 | n/a |
| lone t2 con minutes | 0.36 | - | 0.00 | n/a |
| base lost while 'covered' k | 2.09 | - | 0.00 | n/a |
| oldest plant order min | 1.85 | - | - | n/a |
| no t2 by minute 20 | 0.00 | 1.00 | - | ok |
| frozen minutes | 0.00 | 0.00 | 0.00 | ok |
| raid answer army share | - | - | - | n/a |
| com minutes on their half | 0.54 | 0.00 | - | FAIL (worse than release) |
| com lost on their half | 0.04 | 0.00 | 0.00 | ok, short of aim |
| mex lost to ticks by 10 min | 2.96 | 0.38 | 0.00 | FAIL (worse than release) |
| their mex killed /10min (neg) | -17.11 | -20.59 | - | FAIL (worse than release) |
| their army / ours, 8-12 min | 0.81 | - | - | n/a |
| lost per killed | 1.21 | 1.32 | - | ok |
| reclaimed / killed (neg) | -0.17 | -0.06 | - | ok |
| bare-hands minutes | 0.00 | 0.08 | 0.00 | ok |
| wiped bomber runs | 0.51 | - | 0.00 | n/a |
| runs turned back | 0.00 | - | 0.00 | n/a |
| gunships sent to lose | 0.00 | - | 0.00 | n/a |
| stacked radar/jammers | 0.00 | - | 0.00 | n/a |
| army stuck /10min/1k army | 4.41 | 0.00 | 0.00 | FAIL (worse than release) |
| ground given up share | 0.34 | - | 0.00 | n/a |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.36 | -2.44 | - | FAIL (worse than release) |
| army share (neg) | 0.41 | 0.85 | - | FAIL (worse than release) |
| -log income at 20 | -4.88 | -5.09 | - | FAIL (worse than release) |
| games won or ahead | 0.38 | 0.50 | - | FAIL (does not beat the release) |

Contract: **FAIL (9)** over 24 games (24 of our seats, 24 release seats); 4 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.15 (run `python tools/anomaly.py build`)
```
