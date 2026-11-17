<!-- meta {"date": "2026-11-16", "topic": "v0515", "title": "rc11: v0.5.15 candidate (raid answer under stock army on) vs v0.5.14, 20 games, 30 min", "games": 20, "W": 1, "L": 6, "w": 5, "l": 8, "inc20": 0.91, "verdict": "contract FAIL: won or ahead 8 of 20 (0.40 vs bar 0.50); base lost while covered 4.47k vs 2.54k. Rich Full Metal Plate 6 of 8 ahead; Red Comet, Carrot Mountains, Comet Catcher 2v2 2 of 12 (the ledger count below reads ahead by its own measure). Answers small (median 4% of the army, max 58%). The earlier paired A/B on cm2+rc2 read 15 of 24 for ON; control rc12 (same seeds, answer off) queued to tell the change from the seeds."} -->
# rc11: v0.5.15 candidate (raid answer under stock army on) vs v0.5.14, 20 games, 30 min

- **Date:** 2026-11-16
- **Topic:** v0515
- **Purpose:** Release gate for v0.5.15: the only AI change since v0.5.14 is the raid answer running under the stock army (his 11-16 'test both first'; 'pushes can't hold us back, not our entire army chasing small raiding groups'). +50 both, both factions, seeds 99xx.
- **Result:** 20 games: won 1, lost 6, timeouts ahead 5, behind 8; income at 20 min x0.91 ours/theirs
- **Verdict:** contract FAIL: won or ahead 8 of 20 (0.40 vs bar 0.50); base lost while covered 4.47k vs 2.54k. Rich Full Metal Plate 6 of 8 ahead; Red Comet, Carrot Mountains, Comet Catcher 2v2 2 of 12 (the ledger count below reads ahead by its own measure). Answers small (median 4% of the army, max 58%). The earlier paired A/B on cm2+rc2 read 15 of 24 for ON; control rc12 (same seeds, answer off) queued to tell the change from the seeds.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.14-standard
- **Code:** Apex-v0.5.14-standard = `363c70a0a5+1bb8e5b07c76` (20 games); Apexestall-lane-estall-standard = `6fc9a74aef+f62d5251e625` (20 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Full Metal Plate 1.7, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.14:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9903 --out matches/rc11-v0-cc2-A9903`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9903 | 0 | W | 25.46 | x4.92 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc11-v0-cc2-A9903` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9906 | 0 | L | 29.38 | x0.42 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc11-v0-cc2-A9906` |
| 2 | Comet Catcher Remake 1.8 | Cortex | 9903 | 0 | l | 30.0 | x0.82 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc11-v0-cc2-C9903` |
| 3 | Comet Catcher Remake 1.8 | Cortex | 9906 | 0 | l | 30.0 | x0.53 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc11-v0-cc2-C9906` |
| 4 | Carrot Mountains v2.0 | Armada | 9902 | 0 | w | 30.0 | x1.15 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc11-v0-cm2-A9902` |
| 5 | Carrot Mountains v2.0 | Armada | 9905 | 0 | L | 26.03 | x0.49 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc11-v0-cm2-A9905` |
| 6 | Carrot Mountains v2.0 | Cortex | 9902 | 0 | l | 30.0 | x0.50 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc11-v0-cm2-C9902` |
| 7 | Carrot Mountains v2.0 | Cortex | 9905 | 0 | l | 30.0 | x0.87 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc11-v0-cm2-C9905` |
| 8 | Full Metal Plate 1.7 | Armada | 9911 | 0 | L | 22.33 | x0.85 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc11-v0-fm1-A9911` |
| 9 | Full Metal Plate 1.7 | Armada | 9912 | 0 | w | 30.0 | x1.32 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc11-v0-fm1-A9912` |
| 10 | Full Metal Plate 1.7 | Cortex | 9911 | 0 | l | 30.0 | x2.12 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc11-v0-fm1-C9911` |
| 11 | Full Metal Plate 1.7 | Cortex | 9912 | 0 | l | 30.0 | x1.06 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc11-v0-fm1-C9912` |
| 12 | Full Metal Plate 1.7 | Armada | 9911 | 0 | w | 30.0 | x3.06 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc11-v0-fm2-A9911` |
| 13 | Full Metal Plate 1.7 | Armada | 9912 | 0 | w | 30.0 | x1.12 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc11-v0-fm2-A9912` |
| 14 | Full Metal Plate 1.7 | Cortex | 9911 | 0 | w | 30.0 | x1.03 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc11-v0-fm2-C9911` |
| 15 | Full Metal Plate 1.7 | Cortex | 9912 | 0 | l | 30.0 | x1.03 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc11-v0-fm2-C9912` |
| 16 | Red Comet Remake 1.8 | Armada | 9901 | 0 | L | 29.79 | x0.24 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc11-v0-rc2-A9901` |
| 17 | Red Comet Remake 1.8 | Armada | 9904 | 0 | L | 29.64 | x1.38 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc11-v0-rc2-A9904` |
| 18 | Red Comet Remake 1.8 | Cortex | 9901 | 0 | l | 30.0 | x0.47 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc11-v0-rc2-C9901` |
| 19 | Red Comet Remake 1.8 | Cortex | 9904 | 0 | L | 26.34 | x0.50 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc11-v0-rc2-C9904` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.74 | 3.14 | - | ok |
| t2->4th moho (min) | 6.49 | 5.86 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.56 | 0.53 | 0.00 | ok, short of aim |
| adv plant frame x | 1.54 | 2.19 | 1.50 | ok, short of aim |
| near-done /10k built | 0.40 | 0.60 | 0.00 | ok, short of aim |
| t2 cons given early | 0.11 | 0.11 | 0.00 | ok, short of aim |
| supers before 4 moho | 2.61 | 2.22 | 0.00 | ok, short of aim |
| lone t2 con minutes | 0.67 | 0.28 | 0.00 | ok, short of aim |
| base lost while 'covered' k | 4.47 | 2.54 | 0.00 | FAIL (worse than release) |
| oldest plant order min | 3.67 | 3.22 | - | ok |
| no t2 by minute 20 | 0.00 | 0.00 | - | ok |
| frozen minutes | 0.56 | 0.44 | 0.00 | ok, short of aim |
| raid answer army share | 0.11 | - | - | n/a |
| bare-hands minutes | 0.72 | 0.50 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.40 | 0.41 | 0.00 | ok, short of aim |
| runs turned back | 0.06 | 0.06 | 0.00 | ok, short of aim |
| gunships sent to lose | 0.00 | 0.00 | 0.00 | ok |
| stacked radar/jammers | 0.08 | 0.03 | 0.00 | ok, short of aim |
| army stuck /10min/1k army | 2.78 | 2.48 | 0.00 | ok, short of aim |
| ground given up share | 0.25 | 0.23 | 0.00 | ok, short of aim |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.69 | -1.62 | - | ok |
| army share (neg) | 0.44 | 0.40 | - | ok |
| -log income at 20 | -5.35 | -5.32 | - | ok |
| games won or ahead | 0.40 | 0.50 | - | FAIL (does not beat the release) |

Contract: **FAIL (2)** over 20 games (36 of our seats, 36 release seats); 15 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.14 (run `python tools/anomaly.py build`)
```
