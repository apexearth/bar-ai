<!-- meta {"date": "2026-11-16", "topic": "v0515", "title": "rc12 control: rc11's 20 games with the raid answer under stock army OFF (= v0.5.14 code) vs v0.5.14", "games": 20, "W": 2, "L": 2, "w": 6, "l": 10, "inc20": 0.96, "verdict": "v0.5.14 against itself reads 9 of 20 (contract FAIL at 0.45). Paired with rc11 seed by seed: answer on ahead in 6 discordant games, off in 7. With ra1+ra2: on 23 of 44, off 19 of 44. The rc11 FAIL is inside the noise of identical code; base lost while covered reads 5.71 vs 8.26 here (rc11 4.47 vs 2.54), noise at this size."} -->
# rc12 control: rc11's 20 games with the raid answer under stock army OFF (= v0.5.14 code) vs v0.5.14

- **Date:** 2026-11-16
- **Topic:** v0515
- **Purpose:** Tell the raid-answer change from the seeds: rc11 (answer on) read 8 of 20 won or ahead. Same seeds, sides, maps, 30 min; the lane seat plays v0.5.14's net (deploy installs it), so this arm is v0.5.14 against itself.
- **Result:** 20 games: won 2, lost 2, timeouts ahead 6, behind 10; income at 20 min x0.96 ours/theirs
- **Verdict:** v0.5.14 against itself reads 9 of 20 (contract FAIL at 0.45). Paired with rc11 seed by seed: answer on ahead in 6 discordant games, off in 7. With ra1+ra2: on 23 of 44, off 19 of 44. The rc11 FAIL is inside the noise of identical code; base lost while covered reads 5.71 vs 8.26 here (rc11 4.47 vs 2.54), noise at this size.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.14-standard
- **Code:** Apex-v0.5.14-standard = `363c70a0a5+1bb8e5b07c76` (20 games); Apexestall-lane-estall-standard = `6fc9a74aef+f62d5251e625` (20 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Full Metal Plate 1.7, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.14:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9903 --ai-option apex_raid_answer_stock=0 --out matches/rc12-v0-cc2-A9903`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9903 | 0 | L | 27.74 | x0.47 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc12-v0-cc2-A9903` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9906 | 0 | l | 30.0 | x0.53 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc12-v0-cc2-A9906` |
| 2 | Comet Catcher Remake 1.8 | Cortex | 9903 | 0 | l | 30.0 | x0.80 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc12-v0-cc2-C9903` |
| 3 | Comet Catcher Remake 1.8 | Cortex | 9906 | 0 | l | 30.0 | x0.58 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc12-v0-cc2-C9906` |
| 4 | Carrot Mountains v2.0 | Armada | 9902 | 0 | l | 30.0 | x0.84 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc12-v0-cm2-A9902` |
| 5 | Carrot Mountains v2.0 | Armada | 9905 | 0 | w | 30.0 | x1.84 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc12-v0-cm2-A9905` |
| 6 | Carrot Mountains v2.0 | Cortex | 9902 | 0 | w | 30.0 | x1.65 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc12-v0-cm2-C9902` |
| 7 | Carrot Mountains v2.0 | Cortex | 9905 | 0 | W | 29.54 | x2.47 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc12-v0-cm2-C9905` |
| 8 | Full Metal Plate 1.7 | Armada | 9911 | 0 | W | 26.18 | x3.83 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc12-v0-fm1-A9911` |
| 9 | Full Metal Plate 1.7 | Armada | 9912 | 0 | l | 30.0 | x0.69 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc12-v0-fm1-A9912` |
| 10 | Full Metal Plate 1.7 | Cortex | 9911 | 0 | l | 30.0 | x0.91 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc12-v0-fm1-C9911` |
| 11 | Full Metal Plate 1.7 | Cortex | 9912 | 0 | w | 30.0 | x0.97 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc12-v0-fm1-C9912` |
| 12 | Full Metal Plate 1.7 | Armada | 9911 | 0 | w | 30.0 | x1.94 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc12-v0-fm2-A9911` |
| 13 | Full Metal Plate 1.7 | Armada | 9912 | 0 | l | 30.0 | x0.22 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc12-v0-fm2-A9912` |
| 14 | Full Metal Plate 1.7 | Cortex | 9911 | 0 | l | 30.0 | x0.54 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc12-v0-fm2-C9911` |
| 15 | Full Metal Plate 1.7 | Cortex | 9912 | 0 | l | 30.0 | x0.61 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc12-v0-fm2-C9912` |
| 16 | Red Comet Remake 1.8 | Armada | 9901 | 0 | L | 9.54 | - | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc12-v0-rc2-A9901` |
| 17 | Red Comet Remake 1.8 | Armada | 9904 | 0 | l | 30.0 | x0.40 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc12-v0-rc2-A9904` |
| 18 | Red Comet Remake 1.8 | Cortex | 9901 | 0 | w | 30.0 | x1.78 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc12-v0-rc2-C9901` |
| 19 | Red Comet Remake 1.8 | Cortex | 9904 | 0 | w | 30.0 | x2.73 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f62d5251e625 | `matches/rc12-v0-rc2-C9904` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.69 | 3.46 | - | ok |
| t2->4th moho (min) | 6.13 | 7.18 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.45 | 0.56 | 0.00 | ok, short of aim |
| adv plant frame x | 1.76 | 2.11 | 1.50 | ok, short of aim |
| near-done /10k built | 0.54 | 0.50 | 0.00 | ok, short of aim |
| t2 cons given early | 0.14 | 0.11 | 0.00 | ok, short of aim |
| supers before 4 moho | 3.73 | 3.39 | 0.00 | ok, short of aim |
| lone t2 con minutes | 0.73 | 0.55 | 0.00 | ok, short of aim |
| base lost while 'covered' k | 5.71 | 8.26 | 0.00 | ok, short of aim |
| oldest plant order min | 3.26 | 3.36 | - | ok |
| no t2 by minute 20 | 0.03 | 0.03 | - | ok |
| frozen minutes | 0.56 | 0.50 | 0.00 | ok, short of aim |
| raid answer army share | - | - | - | n/a |
| bare-hands minutes | 0.78 | 0.67 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.47 | 0.43 | 0.00 | ok, short of aim |
| runs turned back | 0.14 | 0.04 | 0.00 | ok, short of aim |
| gunships sent to lose | 0.00 | 0.00 | 0.00 | ok |
| stacked radar/jammers | 0.20 | 0.09 | 0.00 | ok, short of aim |
| army stuck /10min/1k army | 2.10 | 2.78 | 0.00 | ok, short of aim |
| ground given up share | 0.36 | 0.34 | 0.00 | ok, short of aim |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.64 | -1.65 | - | ok |
| army share (neg) | 0.40 | 0.39 | - | ok |
| -log income at 20 | -5.23 | -5.27 | - | ok |
| games won or ahead | 0.45 | 0.50 | - | FAIL (does not beat the release) |

Contract: **FAIL (1)** over 20 games (36 of our seats, 36 release seats); 15 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.14 (run `python tools/anomaly.py build`)
```
