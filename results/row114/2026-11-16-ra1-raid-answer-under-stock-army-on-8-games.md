<!-- meta {"date": "2026-11-16", "topic": "row114", "title": "ra1: raid answer under stock army, on (8 games)", "games": 8, "W": 0, "L": 1, "w": 5, "l": 2, "inc20": 1.31, "verdict": "Not decided by 8 pairs. Lost 1, at time ahead 5 behind 2 (off: 3 of 8 won or ahead, on: 5 of 8; per pair better 3, worse 2, same 3). The answer fired 2-9 times a game. Early home losses worse with it on: 2.43k vs 1.97k by minute 10, on better in 2 of 8 pairs; kill minus lost better by 2.7k a game, in 5 of 8. Army stuck 6.7 vs 5.3 per 10 min per 1k army against the release in the same games (off arm 6.6 vs 6.1)."} -->
# ra1: raid answer under stock army, on (8 games)

- **Date:** 2026-11-16
- **Topic:** row114
- **Purpose:** Row 114 A/B, arm ON: apex_raid_answer_stock 1, otherwise identical to the OFF arm (same seeds, maps, factions).
- **Result:** 8 games: won 0, lost 1, timeouts ahead 5, behind 2; income at 20 min x1.31 ours/theirs
- **Verdict:** Not decided by 8 pairs. Lost 1, at time ahead 5 behind 2 (off: 3 of 8 won or ahead, on: 5 of 8; per pair better 3, worse 2, same 3). The answer fired 2-9 times a game. Early home losses worse with it on: 2.43k vs 1.97k by minute 10, on better in 2 of 8 pairs; kill minus lost better by 2.7k a game, in 5 of 8. Army stuck 6.7 vs 5.3 per 10 min per 1k army against the release in the same games (off arm 6.6 vs 6.1).
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.14-standard
- **Code:** Apex-v0.5.14-standard = `363c70a0a5+1bb8e5b07c76` (8 games); Apexestall-lane-estall-standard = `6fc9a74aef+246f4b91b37d` (8 games)
- **Maps:** Carrot Mountains v2.0, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 20 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.14:standard --per-side 2 --map Carrot Mountains v2.0 --minutes 20 --speed 20 --handicap 50 --sides Armada,Armada --seed 9801 --ai-option apex_raid_answer_stock=1 --out matches/ra1-v1-cm2-A9801`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Carrot Mountains v2.0 | Armada | 9801 | 0 | l | 20.0 | x0.74 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra1-v1-cm2-A9801` |
| 1 | Carrot Mountains v2.0 | Armada | 9802 | 0 | L | 19.63 | - | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra1-v1-cm2-A9802` |
| 2 | Carrot Mountains v2.0 | Cortex | 9801 | 0 | w | 20.0 | x1.45 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra1-v1-cm2-C9801` |
| 3 | Carrot Mountains v2.0 | Cortex | 9802 | 0 | w | 20.0 | x1.30 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra1-v1-cm2-C9802` |
| 4 | Red Comet Remake 1.8 | Armada | 9801 | 0 | w | 20.0 | x1.18 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra1-v1-rc2-A9801` |
| 5 | Red Comet Remake 1.8 | Armada | 9802 | 0 | w | 20.0 | x3.93 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra1-v1-rc2-A9802` |
| 6 | Red Comet Remake 1.8 | Cortex | 9801 | 0 | w | 20.0 | x1.39 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra1-v1-rc2-C9801` |
| 7 | Red Comet Remake 1.8 | Cortex | 9802 | 0 | l | 20.0 | x0.76 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+246f4b91b37d | `matches/ra1-v1-rc2-C9802` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.32 | 2.88 | - | ok |
| t2->4th moho (min) | 5.00 | 6.14 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.37 | 0.41 | 0.00 | ok, short of aim |
| adv plant frame x | 1.96 | 2.28 | 1.50 | ok, short of aim |
| near-done /10k built | 0.61 | 0.38 | 0.00 | FAIL (worse than release) |
| t2 cons given early | 0.00 | 0.00 | 0.00 | ok |
| supers before 4 moho | 1.27 | 1.27 | 0.00 | ok, short of aim |
| lone t2 con minutes | 0.40 | 1.07 | 0.00 | ok, short of aim |
| base lost while 'covered' k | 1.08 | 1.49 | 0.00 | ok, short of aim |
| oldest plant order min | 2.03 | 2.32 | - | ok |
| no t2 by minute 20 | 0.14 | - | - | n/a |
| frozen minutes | 0.00 | 0.00 | 0.00 | ok |
| bare-hands minutes | 0.00 | 0.12 | 0.00 | ok |
| wiped bomber runs | 0.26 | 0.42 | 0.00 | ok, short of aim |
| runs turned back | 0.00 | 0.00 | 0.00 | ok |
| gunships sent to lose | 0.00 | 0.00 | 0.00 | ok |
| stacked radar/jammers | 0.00 | 0.00 | 0.00 | ok |
| army stuck /10min/1k army | 6.69 | 5.32 | 0.00 | FAIL (worse than release) |
| ground given up share | 0.17 | 0.15 | 0.00 | ok, short of aim |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.28 | -1.04 | - | ok |
| army share (neg) | 0.38 | 0.41 | - | ok |
| -log income at 20 | -4.71 | - | - | n/a |
| games won or ahead | 0.75 | 0.50 | - | ok |

Contract: **FAIL (2)** over 8 games (16 of our seats, 16 release seats); 10 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.14 (run `python tools/anomaly.py build`)
```
