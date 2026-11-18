<!-- meta {"date": "2026-11-17", "topic": "v0515", "title": "rc15: release check, Unstable (raid answer deleted, rez fleet uncapped, Ticks tilt cap) vs v0.5.15, Comet Catcher 1v1, both +50, both factions, 20 games", "games": 20, "W": 5, "L": 4, "w": 3, "l": 8, "inc20": 0.91, "verdict": "PASS at the bar: won or ahead 10 of 20 (0.50); no check worse past noise (their extractors killed /10 min 20.2 vs 23.3 and lost per killed 1.71 vs 1.45 worse within noise, 68-70% of resamples). Rerun on the reviewed code (rc16) for the record."} -->
# rc15: release check, Unstable (raid answer deleted, rez fleet uncapped, Ticks tilt cap) vs v0.5.15, Comet Catcher 1v1, both +50, both factions, 20 games

- **Date:** 2026-11-17
- **Topic:** v0515
- **Purpose:** The head-to-head gate before the next release; ran before the review fixes (cap counts ground defence only, cheap test first).
- **Result:** 20 games: won 5, lost 4, timeouts ahead 3, behind 8; income at 20 min x0.91 ours/theirs
- **Verdict:** PASS at the bar: won or ahead 10 of 20 (0.50); no check worse past noise (their extractors killed /10 min 20.2 vs 23.3 and lost per killed 1.71 vs 1.45 worse within noise, 68-70% of resamples). Rerun on the reviewed code (rc16) for the record.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.15-standard
- **Code:** Apex-v0.5.15-standard = `6fc9a74aef+f354c2f891ab` (20 games); Apexestall-lane-estall-standard = `fe11f3ad04+dac8259ca8f8` (20 games)
- **Maps:** Comet Catcher Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.15:standard --per-side 1 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9801 --out matches/rc15-v0-cc1-A9801`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9801 | 0 | l | 30.0 | x0.76 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+dac8259ca8f8 | `matches/rc15-v0-cc1-A9801` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9802 | 0 | L | 26.53 | x0.60 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+dac8259ca8f8 | `matches/rc15-v0-cc1-A9802` |
| 2 | Comet Catcher Remake 1.8 | Armada | 9803 | 0 | l | 30.0 | x0.64 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+dac8259ca8f8 | `matches/rc15-v0-cc1-A9803` |
| 3 | Comet Catcher Remake 1.8 | Armada | 9804 | 0 | l | 30.0 | x0.31 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+dac8259ca8f8 | `matches/rc15-v0-cc1-A9804` |
| 4 | Comet Catcher Remake 1.8 | Armada | 9805 | 0 | w | 30.0 | x0.86 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+dac8259ca8f8 | `matches/rc15-v0-cc1-A9805` |
| 5 | Comet Catcher Remake 1.8 | Armada | 9806 | 0 | l | 30.0 | x0.88 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+dac8259ca8f8 | `matches/rc15-v0-cc1-A9806` |
| 6 | Comet Catcher Remake 1.8 | Armada | 9807 | 0 | W | 28.38 | x3.07 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+dac8259ca8f8 | `matches/rc15-v0-cc1-A9807` |
| 7 | Comet Catcher Remake 1.8 | Armada | 9808 | 0 | W | 27.36 | x0.89 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+dac8259ca8f8 | `matches/rc15-v0-cc1-A9808` |
| 8 | Comet Catcher Remake 1.8 | Armada | 9809 | 0 | l | 30.0 | x1.12 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+dac8259ca8f8 | `matches/rc15-v0-cc1-A9809` |
| 9 | Comet Catcher Remake 1.8 | Armada | 9810 | 0 | l | 30.0 | x0.69 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+dac8259ca8f8 | `matches/rc15-v0-cc1-A9810` |
| 10 | Comet Catcher Remake 1.8 | Cortex | 9801 | 0 | L | 22.19 | x0.14 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+dac8259ca8f8 | `matches/rc15-v0-cc1-C9801` |
| 11 | Comet Catcher Remake 1.8 | Cortex | 9802 | 0 | W | 26.56 | x6.41 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+dac8259ca8f8 | `matches/rc15-v0-cc1-C9802` |
| 12 | Comet Catcher Remake 1.8 | Cortex | 9803 | 0 | w | 30.0 | x2.06 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+dac8259ca8f8 | `matches/rc15-v0-cc1-C9803` |
| 13 | Comet Catcher Remake 1.8 | Cortex | 9804 | 0 | L | 29.66 | x0.66 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+dac8259ca8f8 | `matches/rc15-v0-cc1-C9804` |
| 14 | Comet Catcher Remake 1.8 | Cortex | 9805 | 0 | l | 30.0 | x0.74 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+dac8259ca8f8 | `matches/rc15-v0-cc1-C9805` |
| 15 | Comet Catcher Remake 1.8 | Cortex | 9806 | 0 | w | 30.0 | x1.89 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+dac8259ca8f8 | `matches/rc15-v0-cc1-C9806` |
| 16 | Comet Catcher Remake 1.8 | Cortex | 9807 | 0 | W | 16.35 | - | 6fc9a74aef+f354c2f891ab, fe11f3ad04+dac8259ca8f8 | `matches/rc15-v0-cc1-C9807` |
| 17 | Comet Catcher Remake 1.8 | Cortex | 9808 | 0 | W | 29.83 | x2.77 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+dac8259ca8f8 | `matches/rc15-v0-cc1-C9808` |
| 18 | Comet Catcher Remake 1.8 | Cortex | 9809 | 0 | l | 30.0 | x1.08 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+dac8259ca8f8 | `matches/rc15-v0-cc1-C9809` |
| 19 | Comet Catcher Remake 1.8 | Cortex | 9810 | 0 | L | 29.03 | x0.24 | 6fc9a74aef+f354c2f891ab, fe11f3ad04+dac8259ca8f8 | `matches/rc15-v0-cc1-C9810` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.37 | 2.33 | - | ok |
| t2->4th moho (min) | 5.26 | 4.98 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.35 | 0.32 | 0.00 | ok, short of aim |
| adv plant frame x | 2.95 | 3.22 | 1.50 | ok, short of aim |
| near-done /10k built | 0.51 | 0.56 | 0.00 | ok, short of aim |
| t2 cons given early | 0.00 | 0.00 | 0.00 | ok |
| supers before 4 moho | 1.05 | 1.05 | 0.00 | ok, short of aim |
| lone t2 con minutes | 0.63 | 0.50 | 0.00 | ok, short of aim |
| base lost while 'covered' k | 2.60 | 2.23 | 0.00 | ok, short of aim |
| oldest plant order min | 2.36 | 2.64 | - | ok |
| no t2 by minute 20 | 0.05 | 0.00 | - | ok |
| frozen minutes | 0.00 | 0.00 | 0.00 | ok |
| com minutes on their half | 0.40 | 0.33 | - | ok |
| com lost on their half | 0.00 | 0.00 | 0.00 | ok |
| mex lost to ticks by 10 min | 0.95 | 0.70 | 0.00 | ok, short of aim |
| their mex killed /10min (neg) | -20.18 | -23.25 | - | worse, within noise (68% of resamples) |
| their army / ours, 8-12 min | 0.53 | 0.60 | - | ok |
| lost per killed | 1.71 | 1.45 | - | worse, within noise (70% of resamples) |
| reclaimed / killed (neg) | -0.15 | -0.16 | - | ok |
| bare-hands minutes | 0.10 | 0.10 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.48 | 0.39 | 0.00 | ok, short of aim |
| runs turned back | 0.00 | 0.00 | 0.00 | ok |
| gunships sent to lose | 0.00 | 0.00 | 0.00 | ok |
| stacked radar/jammers | 0.00 | 0.00 | 0.00 | ok |
| army stuck /10min/1k army | 2.76 | 3.06 | 0.00 | ok, short of aim |
| ground given up share | 0.29 | 0.29 | 0.00 | ok, short of aim |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.67 | -1.54 | - | ok |
| army share (neg) | 0.36 | 0.35 | - | ok |
| -log income at 20 | -5.21 | -5.33 | - | ok |
| games won or ahead | 0.50 | 0.50 | - | ok |

Contract: **PASS** over 20 games (20 of our seats, 20 release seats); 12 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.15 (run `python tools/anomaly.py build`)
```
