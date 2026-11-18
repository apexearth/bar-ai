<!-- meta {"date": "2026-11-18", "topic": "v0515", "title": "rc17 release check: stock escorts vs v0.5.16 head-to-head", "games": 20, "W": 6, "L": 0, "w": 9, "l": 5, "inc20": 1.58, "verdict": "Won or ahead 17 of 20 (6 wins, 0 losses). Contract PASS (11 short of aim)."} -->
# rc17 release check: stock escorts vs v0.5.16 head-to-head

- **Date:** 2026-11-18
- **Topic:** v0515
- **Purpose:** Release gate for v0.5.17 (escorts [2,1,600]): new vs v0.5.16, Comet Catcher 1v1, +50 both, seeds 10101-10110, both factions, 30 min
- **Result:** 20 games: won 6, lost 0, timeouts ahead 9, behind 5; income at 20 min x1.58 ours/theirs
- **Verdict:** Won or ahead 17 of 20 (6 wins, 0 losses). Contract PASS (11 short of aim).
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.16-standard
- **Code:** Apex-v0.5.16-standard = `c52cd47708` (20 games); Apexestall-lane-estall-standard = `eb84c59728+8dcd91d7ffdb` (20 games)
- **Maps:** Comet Catcher Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.16:standard --per-side 1 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 10101 --out matches/rc17-v0-cc1-A10101`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 10101 | 0 | W | 27.99 | x4.29 | c52cd47708, eb84c59728+8dcd91d7ffdb | `matches/rc17-v0-cc1-A10101` |
| 1 | Comet Catcher Remake 1.8 | Armada | 10102 | 0 | w | 30.0 | x1.71 | c52cd47708, eb84c59728+8dcd91d7ffdb | `matches/rc17-v0-cc1-A10102` |
| 2 | Comet Catcher Remake 1.8 | Armada | 10103 | 0 | W | 22.83 | x9.75 | c52cd47708, eb84c59728+8dcd91d7ffdb | `matches/rc17-v0-cc1-A10103` |
| 3 | Comet Catcher Remake 1.8 | Armada | 10104 | 0 | l | 30.0 | x0.59 | c52cd47708, eb84c59728+8dcd91d7ffdb | `matches/rc17-v0-cc1-A10104` |
| 4 | Comet Catcher Remake 1.8 | Armada | 10105 | 0 | w | 30.0 | x1.27 | c52cd47708, eb84c59728+8dcd91d7ffdb | `matches/rc17-v0-cc1-A10105` |
| 5 | Comet Catcher Remake 1.8 | Armada | 10106 | 0 | w | 30.0 | x1.12 | c52cd47708, eb84c59728+8dcd91d7ffdb | `matches/rc17-v0-cc1-A10106` |
| 6 | Comet Catcher Remake 1.8 | Armada | 10107 | 0 | l | 30.0 | x3.47 | c52cd47708, eb84c59728+8dcd91d7ffdb | `matches/rc17-v0-cc1-A10107` |
| 7 | Comet Catcher Remake 1.8 | Armada | 10108 | 0 | w | 30.0 | x1.27 | c52cd47708, eb84c59728+8dcd91d7ffdb | `matches/rc17-v0-cc1-A10108` |
| 8 | Comet Catcher Remake 1.8 | Armada | 10109 | 0 | W | 24.11 | x2.10 | c52cd47708, eb84c59728+8dcd91d7ffdb | `matches/rc17-v0-cc1-A10109` |
| 9 | Comet Catcher Remake 1.8 | Armada | 10110 | 0 | l | 30.0 | x0.83 | c52cd47708, eb84c59728+8dcd91d7ffdb | `matches/rc17-v0-cc1-A10110` |
| 10 | Comet Catcher Remake 1.8 | Cortex | 10101 | 0 | w | 30.0 | x1.11 | c52cd47708, eb84c59728+8dcd91d7ffdb | `matches/rc17-v0-cc1-C10101` |
| 11 | Comet Catcher Remake 1.8 | Cortex | 10102 | 0 | W | 26.93 | x2.58 | c52cd47708, eb84c59728+8dcd91d7ffdb | `matches/rc17-v0-cc1-C10102` |
| 12 | Comet Catcher Remake 1.8 | Cortex | 10103 | 0 | w | 30.0 | x1.00 | c52cd47708, eb84c59728+8dcd91d7ffdb | `matches/rc17-v0-cc1-C10103` |
| 13 | Comet Catcher Remake 1.8 | Cortex | 10104 | 0 | l | 30.0 | x0.72 | c52cd47708, eb84c59728+8dcd91d7ffdb | `matches/rc17-v0-cc1-C10104` |
| 14 | Comet Catcher Remake 1.8 | Cortex | 10105 | 0 | l | 30.0 | x0.68 | c52cd47708, eb84c59728+8dcd91d7ffdb | `matches/rc17-v0-cc1-C10105` |
| 15 | Comet Catcher Remake 1.8 | Cortex | 10106 | 0 | w | 30.0 | x1.79 | c52cd47708, eb84c59728+8dcd91d7ffdb | `matches/rc17-v0-cc1-C10106` |
| 16 | Comet Catcher Remake 1.8 | Cortex | 10107 | 0 | w | 30.0 | x1.62 | c52cd47708, eb84c59728+8dcd91d7ffdb | `matches/rc17-v0-cc1-C10107` |
| 17 | Comet Catcher Remake 1.8 | Cortex | 10108 | 0 | W | 29.52 | x2.19 | c52cd47708, eb84c59728+8dcd91d7ffdb | `matches/rc17-v0-cc1-C10108` |
| 18 | Comet Catcher Remake 1.8 | Cortex | 10109 | 0 | w | 30.0 | x1.38 | c52cd47708, eb84c59728+8dcd91d7ffdb | `matches/rc17-v0-cc1-C10109` |
| 19 | Comet Catcher Remake 1.8 | Cortex | 10110 | 0 | W | 18.21 | - | c52cd47708, eb84c59728+8dcd91d7ffdb | `matches/rc17-v0-cc1-C10110` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.35 | 2.64 | - | ok |
| t2->4th moho (min) | 5.42 | 5.40 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.22 | 0.35 | 0.00 | ok, short of aim |
| adv plant frame x | 2.82 | 3.02 | 1.50 | ok, short of aim |
| near-done /10k built | 0.55 | 0.47 | 0.00 | ok, short of aim |
| t2 cons given early | 0.00 | 0.00 | 0.00 | ok |
| supers before 4 moho | 1.10 | 1.10 | 0.00 | ok, short of aim |
| lone t2 con minutes | 0.30 | 0.60 | 0.00 | ok, short of aim |
| base lost while 'covered' k | 1.87 | 1.74 | 0.00 | ok, short of aim |
| oldest plant order min | 2.37 | 2.17 | - | ok |
| no t2 by minute 20 | 0.00 | 0.00 | - | ok |
| frozen minutes | 0.00 | 0.10 | 0.00 | ok |
| com minutes on their half | 0.38 | 0.23 | - | ok |
| com lost on their half | 0.00 | 0.00 | 0.00 | ok |
| mex lost to ticks by 10 min | 1.10 | 0.75 | 0.00 | ok, short of aim |
| their mex killed /10min (neg) | -24.89 | -21.05 | - | ok |
| their army / ours, 8-12 min | 0.51 | 0.64 | - | ok |
| lost per killed | 1.18 | 2.08 | - | ok |
| reclaimed / killed (neg) | -0.15 | -0.20 | - | worse, within noise (66% of resamples) |
| bare-hands minutes | 0.00 | 0.10 | 0.00 | ok |
| wiped bomber runs | 0.44 | 0.35 | 0.00 | ok, short of aim |
| runs turned back | 0.00 | 0.00 | 0.00 | ok |
| gunships sent to lose | 0.00 | 0.00 | 0.00 | ok |
| stacked radar/jammers | 0.00 | 0.00 | 0.00 | ok |
| army stuck /10min/1k army | 2.67 | 3.88 | 0.00 | ok, short of aim |
| ground given up share | 0.27 | 0.33 | 0.00 | ok, short of aim |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.75 | -1.46 | - | ok |
| army share (neg) | 0.36 | 0.38 | - | ok |
| -log income at 20 | -5.33 | -5.04 | - | ok |
| games won or ahead | 0.85 | 0.50 | - | ok |

Contract: **PASS** over 20 games (20 of our seats, 20 release seats); 11 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.16 (run `python tools/anomaly.py build`)
```
