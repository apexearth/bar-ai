<!-- meta {"date": "2026-11-18", "topic": "v0515", "title": "rc19 v0.5.17 candidate vs v0.5.16 head-to-head (final tree, no lobby options)", "games": 20, "W": 3, "L": 3, "w": 6, "l": 8, "inc20": 0.93, "verdict": "Contract PASS, recorded (d32b7b84d8-5fc1ba8c650e). Won or ahead 11/20 (3 won, 3 lost; at time 8 ahead, 6 behind by metal built, the contract's measure; the table below uses its own). rc17 ran the identical game-side code (escort edits byte-identical) on the same seeds at 17/20; option values read are the same (nn_blend 1, plan_explore 0 as before), and the BARb leg (sh3) shows no drop vs that code, so the gap reads as seed noise: 28/40 over both. Mex lost to Ticks by 10 min 0.55 vs 0.65."} -->
# rc19 v0.5.17 candidate vs v0.5.16 head-to-head (final tree, no lobby options)

- **Date:** 2026-11-18
- **Topic:** v0515
- **Purpose:** Release gate for v0.5.17 on the final tree: stock escorts [2,1,600], lobby trimmed to Personalities + Economy player, C++ fallbacks for the removed options (game-side files on, merge off, profile standard). Side A ran with no lobby options at all, as a player's lobby now sends it. Comet Catcher 1v1, +50 both, seeds 10101-10110, both factions, 30 min.
- **Result:** 20 games: won 3, lost 3, timeouts ahead 6, behind 8; income at 20 min x0.93 ours/theirs
- **Verdict:** Contract PASS, recorded (d32b7b84d8-5fc1ba8c650e). Won or ahead 11/20 (3 won, 3 lost; at time 8 ahead, 6 behind by metal built, the contract's measure; the table below uses its own). rc17 ran the identical game-side code (escort edits byte-identical) on the same seeds at 17/20; option values read are the same (nn_blend 1, plan_explore 0 as before), and the BARb leg (sh3) shows no drop vs that code, so the gap reads as seed noise: 28/40 over both. Mex lost to Ticks by 10 min 0.55 vs 0.65.
- **Ours:** Apexestall-lane-estall
- **Opponents:** Apex-v0.5.16-standard
- **Code:** Apex-v0.5.16-standard = `c52cd47708` (20 games); Apexestall-lane-estall = `d32b7b84d8+5fc1ba8c650e` (20 games)
- **Maps:** Comet Catcher Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall --b Apex:v0.5.16:standard --per-side 1 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 10101 --out matches/rc19-v0-cc1-A10101`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 10101 | 0 | l | 30.0 | x0.99 | c52cd47708, d32b7b84d8+5fc1ba8c650e | `matches/rc19-v0-cc1-A10101` |
| 1 | Comet Catcher Remake 1.8 | Armada | 10102 | 0 | W | 29.04 | x2.42 | c52cd47708, d32b7b84d8+5fc1ba8c650e | `matches/rc19-v0-cc1-A10102` |
| 2 | Comet Catcher Remake 1.8 | Armada | 10103 | 0 | w | 30.0 | x1.99 | c52cd47708, d32b7b84d8+5fc1ba8c650e | `matches/rc19-v0-cc1-A10103` |
| 3 | Comet Catcher Remake 1.8 | Armada | 10104 | 0 | w | 30.0 | x1.04 | c52cd47708, d32b7b84d8+5fc1ba8c650e | `matches/rc19-v0-cc1-A10104` |
| 4 | Comet Catcher Remake 1.8 | Armada | 10105 | 0 | l | 30.0 | x1.41 | c52cd47708, d32b7b84d8+5fc1ba8c650e | `matches/rc19-v0-cc1-A10105` |
| 5 | Comet Catcher Remake 1.8 | Armada | 10106 | 0 | l | 30.0 | x1.04 | c52cd47708, d32b7b84d8+5fc1ba8c650e | `matches/rc19-v0-cc1-A10106` |
| 6 | Comet Catcher Remake 1.8 | Armada | 10107 | 0 | L | 24.8 | x0.47 | c52cd47708, d32b7b84d8+5fc1ba8c650e | `matches/rc19-v0-cc1-A10107` |
| 7 | Comet Catcher Remake 1.8 | Armada | 10108 | 0 | w | 30.0 | x1.56 | c52cd47708, d32b7b84d8+5fc1ba8c650e | `matches/rc19-v0-cc1-A10108` |
| 8 | Comet Catcher Remake 1.8 | Armada | 10109 | 0 | L | 22.37 | x0.09 | c52cd47708, d32b7b84d8+5fc1ba8c650e | `matches/rc19-v0-cc1-A10109` |
| 9 | Comet Catcher Remake 1.8 | Armada | 10110 | 0 | l | 30.0 | x0.76 | c52cd47708, d32b7b84d8+5fc1ba8c650e | `matches/rc19-v0-cc1-A10110` |
| 10 | Comet Catcher Remake 1.8 | Cortex | 10101 | 0 | W | 23.88 | x1.59 | c52cd47708, d32b7b84d8+5fc1ba8c650e | `matches/rc19-v0-cc1-C10101` |
| 11 | Comet Catcher Remake 1.8 | Cortex | 10102 | 0 | l | 30.0 | x0.74 | c52cd47708, d32b7b84d8+5fc1ba8c650e | `matches/rc19-v0-cc1-C10102` |
| 12 | Comet Catcher Remake 1.8 | Cortex | 10103 | 0 | w | 30.0 | x1.18 | c52cd47708, d32b7b84d8+5fc1ba8c650e | `matches/rc19-v0-cc1-C10103` |
| 13 | Comet Catcher Remake 1.8 | Cortex | 10104 | 0 | w | 30.0 | x2.11 | c52cd47708, d32b7b84d8+5fc1ba8c650e | `matches/rc19-v0-cc1-C10104` |
| 14 | Comet Catcher Remake 1.8 | Cortex | 10105 | 0 | w | 30.0 | x1.27 | c52cd47708, d32b7b84d8+5fc1ba8c650e | `matches/rc19-v0-cc1-C10105` |
| 15 | Comet Catcher Remake 1.8 | Cortex | 10106 | 0 | l | 30.0 | x0.44 | c52cd47708, d32b7b84d8+5fc1ba8c650e | `matches/rc19-v0-cc1-C10106` |
| 16 | Comet Catcher Remake 1.8 | Cortex | 10107 | 0 | l | 30.0 | x0.99 | c52cd47708, d32b7b84d8+5fc1ba8c650e | `matches/rc19-v0-cc1-C10107` |
| 17 | Comet Catcher Remake 1.8 | Cortex | 10108 | 0 | l | 30.0 | x0.52 | c52cd47708, d32b7b84d8+5fc1ba8c650e | `matches/rc19-v0-cc1-C10108` |
| 18 | Comet Catcher Remake 1.8 | Cortex | 10109 | 0 | L | 9.91 | - | c52cd47708, d32b7b84d8+5fc1ba8c650e | `matches/rc19-v0-cc1-C10109` |
| 19 | Comet Catcher Remake 1.8 | Cortex | 10110 | 0 | W | 17.75 | - | c52cd47708, d32b7b84d8+5fc1ba8c650e | `matches/rc19-v0-cc1-C10110` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.66 | 2.58 | - | ok |
| t2->4th moho (min) | 5.35 | 5.05 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.29 | 0.29 | 0.00 | ok, short of aim |
| adv plant frame x | 2.80 | 2.66 | 1.50 | ok, short of aim |
| near-done /10k built | 0.47 | 0.38 | 0.00 | ok, short of aim |
| t2 cons given early | 0.00 | 0.00 | 0.00 | ok |
| supers before 4 moho | 1.21 | 1.00 | 0.00 | ok, short of aim |
| lone t2 con minutes | 0.63 | 0.56 | 0.00 | ok, short of aim |
| base lost while 'covered' k | 3.63 | 1.81 | 0.00 | worse, within noise (79% of resamples) |
| oldest plant order min | 2.49 | 2.22 | - | ok |
| no t2 by minute 20 | 0.00 | 0.00 | - | ok |
| frozen minutes | 0.00 | 0.00 | 0.00 | ok |
| com minutes on their half | 0.50 | 0.45 | - | ok |
| com lost on their half | 0.05 | 0.00 | 0.00 | ok, short of aim |
| mex lost to ticks by 10 min | 0.55 | 0.65 | 0.00 | ok, short of aim |
| their mex killed /10min (neg) | -22.36 | -23.71 | - | ok |
| their army / ours, 8-12 min | 0.65 | 0.61 | - | ok |
| lost per killed | 1.77 | 1.52 | - | worse, within noise (64% of resamples) |
| reclaimed / killed (neg) | -0.13 | -0.17 | - | ok |
| bare-hands minutes | 0.00 | 0.00 | 0.00 | ok |
| wiped bomber runs | 0.44 | 0.39 | 0.00 | ok, short of aim |
| runs turned back | 0.00 | 0.00 | 0.00 | ok |
| gunships sent to lose | 0.00 | 0.00 | 0.00 | ok |
| stacked radar/jammers | 0.05 | 0.00 | 0.00 | ok, short of aim |
| army stuck /10min/1k army | 2.94 | 3.05 | 0.00 | ok, short of aim |
| ground given up share | 0.28 | 0.26 | 0.00 | ok, short of aim |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.63 | -1.72 | - | ok |
| army share (neg) | 0.40 | 0.39 | - | ok |
| -log income at 20 | -5.29 | -5.29 | - | ok |
| games won or ahead | 0.55 | 0.50 | - | ok |

Contract: **PASS** over 20 games (20 of our seats, 20 release seats); 13 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.16 (run `python tools/anomaly.py build`)
```
