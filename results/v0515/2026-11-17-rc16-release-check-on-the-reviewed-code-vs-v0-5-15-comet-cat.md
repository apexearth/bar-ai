<!-- meta {"date": "2026-11-17", "topic": "v0515", "title": "rc16: release check on the reviewed code vs v0.5.15, Comet Catcher 1v1, both +50, both factions, 20 new seeds", "games": 20, "W": 6, "L": 2, "w": 5, "l": 7, "inc20": 1.49, "verdict": "PASS, recorded: won or ahead 14 of 20 (0.70); rc15+rc16 24 of 40. No check worse past noise (supers before 4 moho 1.47 vs 0.72 at 78% of resamples, commanders lost on their half 0.10 vs 0 at 58%). Extractors lost to Ticks by 10 min 0.80 vs 0.75 a seat in this mirror (v0.5.15 makes few Ticks)."} -->
# rc16: release check on the reviewed code vs v0.5.15, Comet Catcher 1v1, both +50, both factions, 20 new seeds

- **Date:** 2026-11-17
- **Topic:** v0515
- **Purpose:** The head-to-head gate on the code to be released (rc15 plus the review fixes: the tilt cap counts ground defence only, the bare-rate test cheap-first; head-to-head gate back to a point test).
- **Result:** 20 games: won 6, lost 2, timeouts ahead 5, behind 7; income at 20 min x1.49 ours/theirs
- **Verdict:** PASS, recorded: won or ahead 14 of 20 (0.70); rc15+rc16 24 of 40. No check worse past noise (supers before 4 moho 1.47 vs 0.72 at 78% of resamples, commanders lost on their half 0.10 vs 0 at 58%). Extractors lost to Ticks by 10 min 0.80 vs 0.75 a seat in this mirror (v0.5.15 makes few Ticks).
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.15-standard
- **Code:** Apex-v0.5.15-standard = `6fc9a74aef+f354c2f891ab` (20 games); Apexestall-lane-estall-standard = `fe11f3ad04+9f1ee02515e9` (20 games)
- **Maps:** Comet Catcher Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.15:standard --per-side 1 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9811 --out matches/rc16-v0-cc1-A9811`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9811 | 0 | W | 29.38 | x2.49 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+9f1ee02515e9 | `matches/rc16-v0-cc1-A9811` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9812 | 0 | W | 26.21 | x1.86 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+9f1ee02515e9 | `matches/rc16-v0-cc1-A9812` |
| 2 | Comet Catcher Remake 1.8 | Armada | 9813 | 0 | W | 27.14 | x1.43 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+9f1ee02515e9 | `matches/rc16-v0-cc1-A9813` |
| 3 | Comet Catcher Remake 1.8 | Armada | 9814 | 0 | w | 30.0 | x0.78 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+9f1ee02515e9 | `matches/rc16-v0-cc1-A9814` |
| 4 | Comet Catcher Remake 1.8 | Armada | 9815 | 0 | L | 11.06 | - | 6fc9a74aef+f354c2f891ab, fe11f3ad04+9f1ee02515e9 | `matches/rc16-v0-cc1-A9815` |
| 5 | Comet Catcher Remake 1.8 | Armada | 9816 | 0 | l | 30.0 | x0.75 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+9f1ee02515e9 | `matches/rc16-v0-cc1-A9816` |
| 6 | Comet Catcher Remake 1.8 | Armada | 9817 | 0 | l | 30.0 | x1.02 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+9f1ee02515e9 | `matches/rc16-v0-cc1-A9817` |
| 7 | Comet Catcher Remake 1.8 | Armada | 9818 | 0 | l | 30.0 | x1.35 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+9f1ee02515e9 | `matches/rc16-v0-cc1-A9818` |
| 8 | Comet Catcher Remake 1.8 | Armada | 9819 | 0 | w | 30.0 | x2.25 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+9f1ee02515e9 | `matches/rc16-v0-cc1-A9819` |
| 9 | Comet Catcher Remake 1.8 | Armada | 9820 | 0 | w | 30.0 | x1.20 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+9f1ee02515e9 | `matches/rc16-v0-cc1-A9820` |
| 10 | Comet Catcher Remake 1.8 | Cortex | 9811 | 0 | W | 29.51 | x3.25 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+9f1ee02515e9 | `matches/rc16-v0-cc1-C9811` |
| 11 | Comet Catcher Remake 1.8 | Cortex | 9812 | 0 | l | 30.0 | x0.54 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+9f1ee02515e9 | `matches/rc16-v0-cc1-C9812` |
| 12 | Comet Catcher Remake 1.8 | Cortex | 9813 | 0 | w | 30.0 | x1.23 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+9f1ee02515e9 | `matches/rc16-v0-cc1-C9813` |
| 13 | Comet Catcher Remake 1.8 | Cortex | 9814 | 0 | l | 30.0 | x0.80 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+9f1ee02515e9 | `matches/rc16-v0-cc1-C9814` |
| 14 | Comet Catcher Remake 1.8 | Cortex | 9815 | 0 | L | 28.39 | x0.09 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+9f1ee02515e9 | `matches/rc16-v0-cc1-C9815` |
| 15 | Comet Catcher Remake 1.8 | Cortex | 9816 | 0 | w | 30.0 | x1.35 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+9f1ee02515e9 | `matches/rc16-v0-cc1-C9816` |
| 16 | Comet Catcher Remake 1.8 | Cortex | 9817 | 0 | W | 20.04 | x234.31 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+9f1ee02515e9 | `matches/rc16-v0-cc1-C9817` |
| 17 | Comet Catcher Remake 1.8 | Cortex | 9818 | 0 | W | 26.45 | x5.63 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+9f1ee02515e9 | `matches/rc16-v0-cc1-C9818` |
| 18 | Comet Catcher Remake 1.8 | Cortex | 9819 | 0 | l | 30.0 | x1.34 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+9f1ee02515e9 | `matches/rc16-v0-cc1-C9819` |
| 19 | Comet Catcher Remake 1.8 | Cortex | 9820 | 0 | l | 30.0 | x0.35 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+9f1ee02515e9 | `matches/rc16-v0-cc1-C9820` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 3.23 | 3.45 | - | ok |
| t2->4th moho (min) | 5.61 | 5.47 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.28 | 0.18 | 0.00 | ok, short of aim |
| adv plant frame x | 3.14 | 2.53 | 1.50 | worse, within noise (48% of resamples) |
| near-done /10k built | 0.45 | 0.48 | 0.00 | ok, short of aim |
| t2 cons given early | 0.00 | 0.00 | 0.00 | ok |
| supers before 4 moho | 1.47 | 0.72 | 0.00 | worse, within noise (78% of resamples) |
| lone t2 con minutes | 0.42 | 0.44 | 0.00 | ok, short of aim |
| base lost while 'covered' k | 3.15 | 5.21 | 0.00 | ok, short of aim |
| oldest plant order min | 2.25 | 2.53 | - | ok |
| no t2 by minute 20 | 0.00 | 0.05 | - | ok |
| frozen minutes | 0.20 | 0.00 | 0.00 | ok, short of aim |
| com minutes on their half | 0.45 | 0.42 | - | ok |
| com lost on their half | 0.10 | 0.00 | 0.00 | worse, within noise (58% of resamples) |
| mex lost to ticks by 10 min | 0.80 | 0.75 | 0.00 | ok, short of aim |
| their mex killed /10min (neg) | -21.01 | -21.11 | - | ok |
| their army / ours, 8-12 min | 0.41 | 0.67 | - | ok |
| lost per killed | 1.28 | 1.77 | - | ok |
| reclaimed / killed (neg) | -0.15 | -0.12 | - | ok |
| bare-hands minutes | 0.20 | 0.20 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.41 | 0.32 | 0.00 | ok, short of aim |
| runs turned back | 0.05 | 0.05 | 0.00 | ok, short of aim |
| gunships sent to lose | 0.00 | 0.00 | 0.00 | ok |
| stacked radar/jammers | 0.00 | 0.06 | 0.00 | ok |
| army stuck /10min/1k army | 2.02 | 2.52 | 0.00 | ok, short of aim |
| ground given up share | 0.24 | 0.30 | 0.00 | ok, short of aim |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.69 | -1.72 | - | ok |
| army share (neg) | 0.36 | 0.37 | - | ok |
| -log income at 20 | -5.37 | -5.14 | - | ok |
| games won or ahead | 0.70 | 0.50 | - | ok |

Contract: **PASS** over 20 games (20 of our seats, 20 release seats); 15 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.15 (run `python tools/anomaly.py build`)
```
