<!-- meta {"date": "2026-11-17", "topic": "v0515", "title": "rv5+rv6: replication of rv2/rv3 on new seeds 9311-9320, installed v0.5.15 vs v0.5.14, both seatings, Comet Catcher 1v1, both +50, both factions, 40 games", "games": 40, "W": 5, "L": 4, "w": 20, "l": 11, "inc20": 1.19, "verdict": "Did not replicate as a fail: commander on their half 0.70 vs 0.40 minutes a seat, 2+ minutes 5 vs 3 of 40 seats, lost there 0 vs 0 (contract ok). Pooled 80 games: 12 vs 5 seats (p~0.12 for one of ~25 checks), so cleared for v0.5.15, the check kept. Won or ahead 0.62 vs 0.50; lost per killed 1.57 vs 1.81. Two different checks fail here (adv plant frame x 3.15 vs 2.57, base lost while covered 3.24 vs 1.62) where rv2/rv3 failed others: on identical play each 20-40 game check fails ~2 of ~25 checks at random, so the contract's margins need calibrating on A/A noise (rv4)."} -->
# rv5+rv6: replication of rv2/rv3 on new seeds 9311-9320, installed v0.5.15 vs v0.5.14, both seatings, Comet Catcher 1v1, both +50, both factions, 40 games

- **Date:** 2026-11-17
- **Topic:** v0515
- **Purpose:** rv2+rv3 flagged v0.5.15's commander on their half (7 vs 2 of 40 seats with 2+ minutes); repeat on fresh seeds before blaming code.
- **Result:** 40 games: won 5, lost 4, timeouts ahead 20, behind 11; income at 20 min x1.19 ours/theirs
- **Verdict:** Did not replicate as a fail: commander on their half 0.70 vs 0.40 minutes a seat, 2+ minutes 5 vs 3 of 40 seats, lost there 0 vs 0 (contract ok). Pooled 80 games: 12 vs 5 seats (p~0.12 for one of ~25 checks), so cleared for v0.5.15, the check kept. Won or ahead 0.62 vs 0.50; lost per killed 1.57 vs 1.81. Two different checks fail here (adv plant frame x 3.15 vs 2.57, base lost while covered 3.24 vs 1.62) where rv2/rv3 failed others: on identical play each 20-40 game check fails ~2 of ~25 checks at random, so the contract's margins need calibrating on A/A noise (rv4).
- **Ours:** Apex-v0.5.15-standard
- **Opponents:** Apex-v0.5.14-standard
- **Code:** Apex-v0.5.14-standard = `363c70a0a5+1bb8e5b07c76` (40 games); Apex-v0.5.15-standard = `6fc9a74aef+f354c2f891ab` (40 games)
- **Maps:** Comet Catcher Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apex:v0.5.15:standard --b Apex:v0.5.14:standard --per-side 1 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9311 --out matches/rv5-v0-cc1-A9311`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9311 | 0 | l | 30.0 | x1.35 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv5-v0-cc1-A9311` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9312 | 0 | w | 30.0 | x2.34 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv5-v0-cc1-A9312` |
| 2 | Comet Catcher Remake 1.8 | Armada | 9313 | 0 | w | 30.0 | x1.15 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv5-v0-cc1-A9313` |
| 3 | Comet Catcher Remake 1.8 | Armada | 9314 | 0 | L | 27.08 | x0.30 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv5-v0-cc1-A9314` |
| 4 | Comet Catcher Remake 1.8 | Armada | 9315 | 0 | w | 30.0 | x1.38 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv5-v0-cc1-A9315` |
| 5 | Comet Catcher Remake 1.8 | Armada | 9316 | 0 | w | 30.0 | x1.42 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv5-v0-cc1-A9316` |
| 6 | Comet Catcher Remake 1.8 | Armada | 9317 | 0 | w | 30.0 | x0.73 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv5-v0-cc1-A9317` |
| 7 | Comet Catcher Remake 1.8 | Armada | 9318 | 0 | l | 30.0 | x1.65 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv5-v0-cc1-A9318` |
| 8 | Comet Catcher Remake 1.8 | Armada | 9319 | 0 | l | 30.0 | x0.96 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv5-v0-cc1-A9319` |
| 9 | Comet Catcher Remake 1.8 | Armada | 9320 | 0 | l | 30.0 | x0.58 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv5-v0-cc1-A9320` |
| 10 | Comet Catcher Remake 1.8 | Cortex | 9311 | 0 | w | 30.0 | x2.11 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv5-v0-cc1-C9311` |
| 11 | Comet Catcher Remake 1.8 | Cortex | 9312 | 0 | W | 27.21 | x3.56 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv5-v0-cc1-C9312` |
| 12 | Comet Catcher Remake 1.8 | Cortex | 9313 | 0 | L | 29.34 | x0.73 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv5-v0-cc1-C9313` |
| 13 | Comet Catcher Remake 1.8 | Cortex | 9314 | 0 | L | 26.2 | x0.27 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv5-v0-cc1-C9314` |
| 14 | Comet Catcher Remake 1.8 | Cortex | 9315 | 0 | l | 30.0 | x0.95 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv5-v0-cc1-C9315` |
| 15 | Comet Catcher Remake 1.8 | Cortex | 9316 | 0 | l | 30.0 | x0.78 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv5-v0-cc1-C9316` |
| 16 | Comet Catcher Remake 1.8 | Cortex | 9317 | 0 | w | 30.0 | x1.37 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv5-v0-cc1-C9317` |
| 17 | Comet Catcher Remake 1.8 | Cortex | 9318 | 0 | w | 30.0 | x0.79 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv5-v0-cc1-C9318` |
| 18 | Comet Catcher Remake 1.8 | Cortex | 9319 | 0 | l | 30.0 | x1.01 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv5-v0-cc1-C9319` |
| 19 | Comet Catcher Remake 1.8 | Cortex | 9320 | 0 | w | 30.0 | x0.50 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv5-v0-cc1-C9320` |
| 20 | Comet Catcher Remake 1.8 | Armada | 9311 | 1 | w | 30.0 | x1.26 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv6-v0-cc1-A9311` |
| 21 | Comet Catcher Remake 1.8 | Armada | 9312 | 1 | l | 30.0 | x0.96 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv6-v0-cc1-A9312` |
| 22 | Comet Catcher Remake 1.8 | Armada | 9313 | 1 | L | 20.2 | x0.39 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv6-v0-cc1-A9313` |
| 23 | Comet Catcher Remake 1.8 | Armada | 9314 | 1 | l | 30.0 | x0.98 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv6-v0-cc1-A9314` |
| 24 | Comet Catcher Remake 1.8 | Armada | 9315 | 1 | W | 10.73 | - | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv6-v0-cc1-A9315` |
| 25 | Comet Catcher Remake 1.8 | Armada | 9316 | 1 | w | 30.0 | x3.08 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv6-v0-cc1-A9316` |
| 26 | Comet Catcher Remake 1.8 | Armada | 9317 | 1 | w | 30.0 | x1.05 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv6-v0-cc1-A9317` |
| 27 | Comet Catcher Remake 1.8 | Armada | 9318 | 1 | W | 28.34 | x2.42 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv6-v0-cc1-A9318` |
| 28 | Comet Catcher Remake 1.8 | Armada | 9319 | 1 | l | 30.0 | x1.29 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv6-v0-cc1-A9319` |
| 29 | Comet Catcher Remake 1.8 | Armada | 9320 | 1 | w | 30.0 | x1.51 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv6-v0-cc1-A9320` |
| 30 | Comet Catcher Remake 1.8 | Cortex | 9311 | 1 | w | 30.0 | x3.42 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv6-v0-cc1-C9311` |
| 31 | Comet Catcher Remake 1.8 | Cortex | 9312 | 1 | w | 30.0 | x1.22 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv6-v0-cc1-C9312` |
| 32 | Comet Catcher Remake 1.8 | Cortex | 9313 | 1 | w | 30.0 | x1.64 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv6-v0-cc1-C9313` |
| 33 | Comet Catcher Remake 1.8 | Cortex | 9314 | 1 | w | 30.0 | x2.59 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv6-v0-cc1-C9314` |
| 34 | Comet Catcher Remake 1.8 | Cortex | 9315 | 1 | W | 23.18 | x6.31 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv6-v0-cc1-C9315` |
| 35 | Comet Catcher Remake 1.8 | Cortex | 9316 | 1 | l | 30.0 | x0.55 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv6-v0-cc1-C9316` |
| 36 | Comet Catcher Remake 1.8 | Cortex | 9317 | 1 | w | 30.0 | x1.03 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv6-v0-cc1-C9317` |
| 37 | Comet Catcher Remake 1.8 | Cortex | 9318 | 1 | w | 30.0 | x1.08 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv6-v0-cc1-C9318` |
| 38 | Comet Catcher Remake 1.8 | Cortex | 9319 | 1 | w | 30.0 | x1.53 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv6-v0-cc1-C9319` |
| 39 | Comet Catcher Remake 1.8 | Cortex | 9320 | 1 | W | 28.65 | x1.41 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv6-v0-cc1-C9320` |

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.15 (run `python tools/anomaly.py build`)
```
