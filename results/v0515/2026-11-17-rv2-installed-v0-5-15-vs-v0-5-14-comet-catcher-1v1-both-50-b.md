<!-- meta {"date": "2026-11-17", "topic": "v0515", "title": "rv2: installed v0.5.15 vs v0.5.14, Comet Catcher 1v1, both +50, both factions, 20 games (the release check stopped on 11-16)", "games": 20, "W": 7, "L": 3, "w": 4, "l": 6, "inc20": 1.53, "verdict": "No regression: won 7, lost 3, ahead 4, behind 6 (won or ahead 11 of 20; Armada 7/10, Cortex 4/10); no crashes on engine 2026.09.03. Contract FAIL on 2 checks, com minutes on their half 1.18 vs 0.38 and their extractors killed per 10 min 18.9 vs 21.5; with the play unchanged these read as seat noise at 20 games, and both are watched in the next release check."} -->
# rv2: installed v0.5.15 vs v0.5.14, Comet Catcher 1v1, both +50, both factions, 20 games (the release check stopped on 11-16)

- **Date:** 2026-11-17
- **Topic:** v0515
- **Purpose:** The 20-game release check v0.5.15 shipped without (--allow-red on his OK when he chose to play it online). v0.5.15's default play is meant to equal v0.5.14's.
- **Result:** 20 games: won 7, lost 3, timeouts ahead 4, behind 6; income at 20 min x1.53 ours/theirs
- **Verdict:** No regression: won 7, lost 3, ahead 4, behind 6 (won or ahead 11 of 20; Armada 7/10, Cortex 4/10); no crashes on engine 2026.09.03. Contract FAIL on 2 checks, com minutes on their half 1.18 vs 0.38 and their extractors killed per 10 min 18.9 vs 21.5; with the play unchanged these read as seat noise at 20 games, and both are watched in the next release check.
- **Ours:** Apex-v0.5.15-standard
- **Opponents:** Apex-v0.5.14-standard
- **Code:** Apex-v0.5.14-standard = `363c70a0a5+1bb8e5b07c76` (20 games); Apex-v0.5.15-standard = `6fc9a74aef+f354c2f891ab` (20 games)
- **Maps:** Comet Catcher Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apex:v0.5.15:standard --b Apex:v0.5.14:standard --per-side 1 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9301 --out matches/rv2-v0-cc1-A9301`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9301 | 0 | W | 16.9 | - | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv2-v0-cc1-A9301` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9302 | 0 | W | 24.88 | x2.52 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv2-v0-cc1-A9302` |
| 2 | Comet Catcher Remake 1.8 | Armada | 9303 | 0 | l | 30.0 | x0.32 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv2-v0-cc1-A9303` |
| 3 | Comet Catcher Remake 1.8 | Armada | 9304 | 0 | l | 30.0 | x0.87 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv2-v0-cc1-A9304` |
| 4 | Comet Catcher Remake 1.8 | Armada | 9305 | 0 | w | 30.0 | x1.83 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv2-v0-cc1-A9305` |
| 5 | Comet Catcher Remake 1.8 | Armada | 9306 | 0 | W | 21.04 | x111.07 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv2-v0-cc1-A9306` |
| 6 | Comet Catcher Remake 1.8 | Armada | 9307 | 0 | W | 23.62 | x6.89 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv2-v0-cc1-A9307` |
| 7 | Comet Catcher Remake 1.8 | Armada | 9308 | 0 | w | 30.0 | x1.37 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv2-v0-cc1-A9308` |
| 8 | Comet Catcher Remake 1.8 | Armada | 9309 | 0 | W | 20.84 | x27.76 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv2-v0-cc1-A9309` |
| 9 | Comet Catcher Remake 1.8 | Armada | 9310 | 0 | l | 30.0 | x0.44 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv2-v0-cc1-A9310` |
| 10 | Comet Catcher Remake 1.8 | Cortex | 9301 | 0 | l | 30.0 | x0.67 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv2-v0-cc1-C9301` |
| 11 | Comet Catcher Remake 1.8 | Cortex | 9302 | 0 | L | 22.45 | x0.03 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv2-v0-cc1-C9302` |
| 12 | Comet Catcher Remake 1.8 | Cortex | 9303 | 0 | w | 30.0 | x1.08 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv2-v0-cc1-C9303` |
| 13 | Comet Catcher Remake 1.8 | Cortex | 9304 | 0 | l | 30.0 | x0.56 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv2-v0-cc1-C9304` |
| 14 | Comet Catcher Remake 1.8 | Cortex | 9305 | 0 | L | 23.61 | x0.20 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv2-v0-cc1-C9305` |
| 15 | Comet Catcher Remake 1.8 | Cortex | 9306 | 0 | l | 30.0 | x0.53 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv2-v0-cc1-C9306` |
| 16 | Comet Catcher Remake 1.8 | Cortex | 9307 | 0 | L | 29.42 | x0.51 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv2-v0-cc1-C9307` |
| 17 | Comet Catcher Remake 1.8 | Cortex | 9308 | 0 | w | 30.0 | x3.12 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv2-v0-cc1-C9308` |
| 18 | Comet Catcher Remake 1.8 | Cortex | 9309 | 0 | W | 26.8 | x3.69 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv2-v0-cc1-C9309` |
| 19 | Comet Catcher Remake 1.8 | Cortex | 9310 | 0 | W | 23.5 | x26.09 | 363c70a0a5+1bb8e5b07c76, 6fc9a74aef+f354c2f891ab | `matches/rv2-v0-cc1-C9310` |

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.15 (run `python tools/anomaly.py build`)
```
