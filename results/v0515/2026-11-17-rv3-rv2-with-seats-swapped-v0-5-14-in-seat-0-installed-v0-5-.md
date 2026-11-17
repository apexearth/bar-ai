<!-- meta {"date": "2026-11-17", "topic": "v0515", "title": "rv3: rv2 with seats swapped (v0.5.14 in seat 0), installed v0.5.15 vs v0.5.14, Comet Catcher 1v1, both +50, both factions, 20 games", "games": 20, "W": 1, "L": 7, "w": 8, "l": 4, "inc20": 0.92, "verdict": "Won or ahead 8 of 20 (rv2+rv3: 19 of 40 vs 21 of 40, level). Commander on their half 0.50 vs 0.15 here; pooled 40 games 0.84 vs 0.26 (games with 2+ minutes there 7 vs 2), commanders lost there 1 vs 0. Lost per killed 2.03 vs 1.41 here, pooled 1.84 vs 1.67; extractors killed level. The two releases' scripts differ only in comments and one off switch, and the DLL change touches only script-made raids crewed by freed units, so a real difference is unexpected; the A/A control rv4 (v0.5.14 vs itself, same seeds) measures how far identical code drifts on these checks."} -->
# rv3: rv2 with seats swapped (v0.5.14 in seat 0), installed v0.5.15 vs v0.5.14, Comet Catcher 1v1, both +50, both factions, 20 games

- **Date:** 2026-11-17
- **Topic:** v0515
- **Purpose:** rv2's contract flagged com minutes on their half 1.18 vs 0.38 with v0.5.15 always in seat 0: tell the version from the start position.
- **Result:** 20 games: won 1, lost 7, timeouts ahead 8, behind 4; income at 20 min x0.92 ours/theirs
- **Verdict:** Won or ahead 8 of 20 (rv2+rv3: 19 of 40 vs 21 of 40, level). Commander on their half 0.50 vs 0.15 here; pooled 40 games 0.84 vs 0.26 (games with 2+ minutes there 7 vs 2), commanders lost there 1 vs 0. Lost per killed 2.03 vs 1.41 here, pooled 1.84 vs 1.67; extractors killed level. The two releases' scripts differ only in comments and one off switch, and the DLL change touches only script-made raids crewed by freed units, so a real difference is unexpected; the A/A control rv4 (v0.5.14 vs itself, same seeds) measures how far identical code drifts on these checks.
- **Ours:** Apex-v0.5.15-standard
- **Opponents:** Apex-v0.5.14-standard
- **Code:** Apex-v0.5.14-standard = `363c70a0a5+1bb8e5b07c76` (20 games); Apex-v0.5.15-standard = `6fc9a74aef+f354c2f891ab` (20 games)
- **Maps:** Comet Catcher Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apex:v0.5.14:standard --b Apex:v0.5.15:standard --per-side 1 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9301 --out matches/rv3-v0-cc1-A9301`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9301 | 1 | l | 30.0 | x1.05 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv3-v0-cc1-A9301` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9302 | 1 | l | 30.0 | x0.51 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv3-v0-cc1-A9302` |
| 2 | Comet Catcher Remake 1.8 | Armada | 9303 | 1 | L | 12.88 | - | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv3-v0-cc1-A9303` |
| 3 | Comet Catcher Remake 1.8 | Armada | 9304 | 1 | L | 29.94 | x0.61 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv3-v0-cc1-A9304` |
| 4 | Comet Catcher Remake 1.8 | Armada | 9305 | 1 | w | 30.0 | x1.38 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv3-v0-cc1-A9305` |
| 5 | Comet Catcher Remake 1.8 | Armada | 9306 | 1 | l | 30.0 | x0.63 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv3-v0-cc1-A9306` |
| 6 | Comet Catcher Remake 1.8 | Armada | 9307 | 1 | w | 30.0 | x0.95 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv3-v0-cc1-A9307` |
| 7 | Comet Catcher Remake 1.8 | Armada | 9308 | 1 | l | 30.0 | x0.98 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv3-v0-cc1-A9308` |
| 8 | Comet Catcher Remake 1.8 | Armada | 9309 | 1 | W | 29.02 | x1.24 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv3-v0-cc1-A9309` |
| 9 | Comet Catcher Remake 1.8 | Armada | 9310 | 1 | L | 26.23 | x0.62 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv3-v0-cc1-A9310` |
| 10 | Comet Catcher Remake 1.8 | Cortex | 9301 | 1 | L | 17.4 | - | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv3-v0-cc1-C9301` |
| 11 | Comet Catcher Remake 1.8 | Cortex | 9302 | 1 | w | 30.0 | x1.86 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv3-v0-cc1-C9302` |
| 12 | Comet Catcher Remake 1.8 | Cortex | 9303 | 1 | w | 30.0 | x0.95 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv3-v0-cc1-C9303` |
| 13 | Comet Catcher Remake 1.8 | Cortex | 9304 | 1 | L | 19.92 | - | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv3-v0-cc1-C9304` |
| 14 | Comet Catcher Remake 1.8 | Cortex | 9305 | 1 | w | 30.0 | x1.25 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv3-v0-cc1-C9305` |
| 15 | Comet Catcher Remake 1.8 | Cortex | 9306 | 1 | w | 30.0 | x1.53 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv3-v0-cc1-C9306` |
| 16 | Comet Catcher Remake 1.8 | Cortex | 9307 | 1 | w | 30.0 | x2.02 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv3-v0-cc1-C9307` |
| 17 | Comet Catcher Remake 1.8 | Cortex | 9308 | 1 | L | 22.32 | x0.09 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv3-v0-cc1-C9308` |
| 18 | Comet Catcher Remake 1.8 | Cortex | 9309 | 1 | L | 18.1 | - | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv3-v0-cc1-C9309` |
| 19 | Comet Catcher Remake 1.8 | Cortex | 9310 | 1 | w | 30.0 | x2.03 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv3-v0-cc1-C9310` |

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.15 (run `python tools/anomaly.py build`)
```
