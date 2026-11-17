<!-- meta {"date": "2026-11-16", "topic": "v0515", "title": "wr1: raid answer ON vs OFF against WRDistilled 0.4 raids, us +50, WRDistilled +75, 2v2, 16 seeds", "games": 32, "W": 13, "L": 0, "w": 6, "l": 13, "inc20": 0.79, "verdict": "No effect: won or ahead ON 8 vs OFF 8 of 16, every pair the same; kill-lost better ON in 9 of 16. Red Comet 8 of 8 both arms (most won by 14-18 min); Carrot Mountains 0 of 8 both arms (WRDistilled built 1.0-2.1x our metal by 20 min). Answers median 18% of the standing army, 10 of 79 over half. Commander 2.8-2.9 min a seat on their half, lost there once in 32 seats (baseline for apex_com_unseen)."} -->
# wr1: raid answer ON vs OFF against WRDistilled 0.4 raids, us +50, WRDistilled +75, 2v2, 16 seeds

- **Date:** 2026-11-16
- **Topic:** v0515
- **Purpose:** His 11-16: test the raid answer against WRDistilled, whose own raids move differently from BARb's and ours ('they chased down our commander ... they had the speed advantage'), with it given 20-30 more bonus.
- **Result:** 32 games: won 13, lost 0, timeouts ahead 6, behind 13; income at 20 min x0.79 ours/theirs
- **Verdict:** No effect: won or ahead ON 8 vs OFF 8 of 16, every pair the same; kill-lost better ON in 9 of 16. Red Comet 8 of 8 both arms (most won by 14-18 min); Carrot Mountains 0 of 8 both arms (WRDistilled built 1.0-2.1x our metal by 20 min). Answers median 18% of the standing army, 10 of 79 over half. Commander 2.8-2.9 min a seat on their half, lost there once in 32 seats (baseline for apex_com_unseen).
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** WRDistilled-0.4
- **Code:** Apexestall-lane-estall-standard = `6fc9a74aef+ed7a47fe57fc` (32 games); WRDistilled-0.4 = `?` (32 games)
- **Maps:** Carrot Mountains v2.0, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** [50, 75]; **time cap:** 20 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b WRDistilled:0.4 --per-side 2 --map Carrot Mountains v2.0 --minutes 20 --speed 20 --handicap 50,75 --sides Armada,Armada --seed 9702 --ai-option apex_raid_answer_stock=0 --out matches/wr1-v0-cm2-A9702`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Carrot Mountains v2.0 | Armada | 9702 | 0 | l | 20.0 | x0.40 | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v0-cm2-A9702` |
| 1 | Carrot Mountains v2.0 | Armada | 9704 | 0 | l | 20.0 | x0.98 | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v0-cm2-A9704` |
| 2 | Carrot Mountains v2.0 | Armada | 9706 | 0 | l | 20.0 | x0.79 | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v0-cm2-A9706` |
| 3 | Carrot Mountains v2.0 | Armada | 9708 | 0 | l | 20.0 | x0.80 | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v0-cm2-A9708` |
| 4 | Carrot Mountains v2.0 | Cortex | 9702 | 0 | l | 20.0 | x0.52 | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v0-cm2-C9702` |
| 5 | Carrot Mountains v2.0 | Cortex | 9704 | 0 | l | 20.0 | x0.68 | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v0-cm2-C9704` |
| 6 | Carrot Mountains v2.0 | Cortex | 9706 | 0 | l | 20.0 | x0.85 | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v0-cm2-C9706` |
| 7 | Carrot Mountains v2.0 | Cortex | 9708 | 0 | l | 20.0 | x0.49 | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v0-cm2-C9708` |
| 8 | Red Comet Remake 1.8 | Armada | 9701 | 0 | W | 19.65 | - | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v0-rc2-A9701` |
| 9 | Red Comet Remake 1.8 | Armada | 9703 | 0 | W | 17.29 | - | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v0-rc2-A9703` |
| 10 | Red Comet Remake 1.8 | Armada | 9705 | 0 | W | 19.12 | - | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v0-rc2-A9705` |
| 11 | Red Comet Remake 1.8 | Armada | 9707 | 0 | W | 14.56 | - | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v0-rc2-A9707` |
| 12 | Red Comet Remake 1.8 | Cortex | 9701 | 0 | W | 19.94 | - | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v0-rc2-C9701` |
| 13 | Red Comet Remake 1.8 | Cortex | 9703 | 0 | w | 20.0 | x1.85 | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v0-rc2-C9703` |
| 14 | Red Comet Remake 1.8 | Cortex | 9705 | 0 | W | 18.79 | - | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v0-rc2-C9705` |
| 15 | Red Comet Remake 1.8 | Cortex | 9707 | 0 | W | 16.68 | - | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v0-rc2-C9707` |
| 16 | Carrot Mountains v2.0 | Armada | 9702 | 0 | l | 20.0 | x0.24 | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v1-cm2-A9702` |
| 17 | Carrot Mountains v2.0 | Armada | 9704 | 0 | w | 20.0 | x1.31 | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v1-cm2-A9704` |
| 18 | Carrot Mountains v2.0 | Armada | 9706 | 0 | l | 20.0 | x0.22 | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v1-cm2-A9706` |
| 19 | Carrot Mountains v2.0 | Armada | 9708 | 0 | w | 20.0 | x1.11 | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v1-cm2-A9708` |
| 20 | Carrot Mountains v2.0 | Cortex | 9702 | 0 | l | 20.0 | x0.64 | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v1-cm2-C9702` |
| 21 | Carrot Mountains v2.0 | Cortex | 9704 | 0 | l | 20.0 | x0.28 | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v1-cm2-C9704` |
| 22 | Carrot Mountains v2.0 | Cortex | 9706 | 0 | w | 20.0 | x1.15 | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v1-cm2-C9706` |
| 23 | Carrot Mountains v2.0 | Cortex | 9708 | 0 | l | 20.0 | x0.51 | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v1-cm2-C9708` |
| 24 | Red Comet Remake 1.8 | Armada | 9701 | 0 | W | 17.21 | - | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v1-rc2-A9701` |
| 25 | Red Comet Remake 1.8 | Armada | 9703 | 0 | W | 18.83 | - | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v1-rc2-A9703` |
| 26 | Red Comet Remake 1.8 | Armada | 9705 | 0 | w | 20.0 | x2.21 | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v1-rc2-A9705` |
| 27 | Red Comet Remake 1.8 | Armada | 9707 | 0 | W | 14.79 | - | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v1-rc2-A9707` |
| 28 | Red Comet Remake 1.8 | Cortex | 9701 | 0 | W | 15.08 | - | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v1-rc2-C9701` |
| 29 | Red Comet Remake 1.8 | Cortex | 9703 | 0 | W | 15.52 | - | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v1-rc2-C9703` |
| 30 | Red Comet Remake 1.8 | Cortex | 9705 | 0 | W | 18.54 | - | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v1-rc2-C9705` |
| 31 | Red Comet Remake 1.8 | Cortex | 9707 | 0 | w | 20.0 | x8.61 | 6fc9a74aef+ed7a47fe57fc, ? | `matches/wr1-v1-rc2-C9707` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.19 | 6.70 | - | ok |
| t2->4th moho (min) | 4.84 | 6.70 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.38 | - | 0.00 | n/a |
| adv plant frame x | 1.93 | - | 1.50 | n/a |
| near-done /10k built | 0.76 | 0.00 | 0.00 | FAIL (worse than release) |
| t2 cons given early | 0.00 | 0.00 | 0.00 | ok |
| supers before 4 moho | 1.25 | 0.00 | 0.00 | FAIL (worse than release) |
| lone t2 con minutes | 0.57 | 0.00 | 0.00 | ok, short of aim |
| base lost while 'covered' k | 1.59 | - | 0.00 | n/a |
| oldest plant order min | 1.93 | - | - | n/a |
| no t2 by minute 20 | 0.00 | - | - | n/a |
| frozen minutes | 0.09 | 0.31 | 0.00 | ok, short of aim |
| raid answer army share | 0.37 | - | - | n/a |
| com minutes on their half | 2.84 | 0.00 | - | FAIL (worse than release) |
| com lost on their half | 0.03 | 0.00 | 0.00 | ok, short of aim |
| bare-hands minutes | 0.03 | 1.00 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.31 | - | 0.00 | n/a |
| runs turned back | 0.00 | - | 0.00 | n/a |
| gunships sent to lose | 0.00 | - | 0.00 | n/a |
| stacked radar/jammers | 0.05 | - | 0.00 | n/a |
| army stuck /10min/1k army | 5.58 | 0.00 | 0.00 | FAIL (worse than release) |
| ground given up share | 0.19 | - | 0.00 | n/a |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.26 | -2.43 | - | FAIL (worse than release) |
| army share (neg) | 0.43 | 0.61 | - | FAIL (worse than release) |
| -log income at 20 | -5.05 | - | - | n/a |
| games won or ahead | 0.50 | 0.50 | - | ok |

Contract: **FAIL (6)** over 32 games (64 of our seats, 64 release seats); 8 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.14 (run `python tools/anomaly.py build`)
```
