<!-- meta {"date": "2026-11-17", "topic": "v0515", "title": "rv4: A/A control, v0.5.14 vs v0.5.14 on rv2's seeds, Comet Catcher 1v1, both +50, both factions, 20 games", "games": 20, "W": 4, "L": 6, "w": 8, "l": 2, "inc20": 1.0, "verdict": "Commander on their half: 0.43 and 0.55 minutes a seat (1 of 40 seats 2+ minutes), against v0.5.15's 0.84 (7 of 40) and v0.5.14's 0.26 (2 of 40) in rv2+rv3: v0.5.15's commander walks past the middle more often than identical code drifts (~p 0.02 for this one check, ~25 checks run). No mechanism found: scripts differ by comments and one off switch; C++ by the off raid-answer exemption and the chat line. The forward stints are the item-117 pattern (extractor claims at 0.55-0.75 of the way, 8-12 min, rv2 A9304); he died there once in 40. Kept on validation 117; the next release check must clear it."} -->
# rv4: A/A control, v0.5.14 vs v0.5.14 on rv2's seeds, Comet Catcher 1v1, both +50, both factions, 20 games

- **Date:** 2026-11-17
- **Topic:** v0515
- **Purpose:** How far identical code drifts on the two checks rv2/rv3 flagged for v0.5.15 (commander minutes on their half, lost per killed).
- **Result:** 20 games: won 4, lost 6, timeouts ahead 8, behind 2; income at 20 min x1.00 ours/theirs
- **Verdict:** Commander on their half: 0.43 and 0.55 minutes a seat (1 of 40 seats 2+ minutes), against v0.5.15's 0.84 (7 of 40) and v0.5.14's 0.26 (2 of 40) in rv2+rv3: v0.5.15's commander walks past the middle more often than identical code drifts (~p 0.02 for this one check, ~25 checks run). No mechanism found: scripts differ by comments and one off switch; C++ by the off raid-answer exemption and the chat line. The forward stints are the item-117 pattern (extractor claims at 0.55-0.75 of the way, 8-12 min, rv2 A9304); he died there once in 40. Kept on validation 117; the next release check must clear it.
- **Ours:** Apex-v0.5.14-standard
- **Opponents:** Apex-v0.5.14-standard
- **Code:** Apex-v0.5.14-standard = `363c70a0a5+1bb8e5b07c76` (20 games)
- **Maps:** Comet Catcher Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apex:v0.5.14:standard --b Apex:v0.5.14:standard --per-side 1 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9301 --out matches/rv4-v0-cc1-A9301`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9301 | 0 | L | 21.49 | x0.12 | 363c70a0a5+1bb8e5b07c76 | `matches/rv4-v0-cc1-A9301` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9302 | 0 | l | 30.0 | x0.86 | 363c70a0a5+1bb8e5b07c76 | `matches/rv4-v0-cc1-A9302` |
| 2 | Comet Catcher Remake 1.8 | Armada | 9303 | 0 | L | 28.36 | x0.24 | 363c70a0a5+1bb8e5b07c76 | `matches/rv4-v0-cc1-A9303` |
| 3 | Comet Catcher Remake 1.8 | Armada | 9304 | 0 | L | 27.61 | x0.55 | 363c70a0a5+1bb8e5b07c76 | `matches/rv4-v0-cc1-A9304` |
| 4 | Comet Catcher Remake 1.8 | Armada | 9305 | 0 | W | 23.96 | x2.49 | 363c70a0a5+1bb8e5b07c76 | `matches/rv4-v0-cc1-A9305` |
| 5 | Comet Catcher Remake 1.8 | Armada | 9306 | 0 | L | 29.64 | x0.62 | 363c70a0a5+1bb8e5b07c76 | `matches/rv4-v0-cc1-A9306` |
| 6 | Comet Catcher Remake 1.8 | Armada | 9307 | 0 | W | 22.89 | x8.63 | 363c70a0a5+1bb8e5b07c76 | `matches/rv4-v0-cc1-A9307` |
| 7 | Comet Catcher Remake 1.8 | Armada | 9308 | 0 | W | 27.13 | x2.82 | 363c70a0a5+1bb8e5b07c76 | `matches/rv4-v0-cc1-A9308` |
| 8 | Comet Catcher Remake 1.8 | Armada | 9309 | 0 | W | 17.4 | - | 363c70a0a5+1bb8e5b07c76 | `matches/rv4-v0-cc1-A9309` |
| 9 | Comet Catcher Remake 1.8 | Armada | 9310 | 0 | l | 30.0 | x0.61 | 363c70a0a5+1bb8e5b07c76 | `matches/rv4-v0-cc1-A9310` |
| 10 | Comet Catcher Remake 1.8 | Cortex | 9301 | 0 | w | 30.0 | x2.12 | 363c70a0a5+1bb8e5b07c76 | `matches/rv4-v0-cc1-C9301` |
| 11 | Comet Catcher Remake 1.8 | Cortex | 9302 | 0 | L | 29.95 | x0.41 | 363c70a0a5+1bb8e5b07c76 | `matches/rv4-v0-cc1-C9302` |
| 12 | Comet Catcher Remake 1.8 | Cortex | 9303 | 0 | w | 30.0 | x1.79 | 363c70a0a5+1bb8e5b07c76 | `matches/rv4-v0-cc1-C9303` |
| 13 | Comet Catcher Remake 1.8 | Cortex | 9304 | 0 | w | 30.0 | x1.90 | 363c70a0a5+1bb8e5b07c76 | `matches/rv4-v0-cc1-C9304` |
| 14 | Comet Catcher Remake 1.8 | Cortex | 9305 | 0 | w | 30.0 | x1.20 | 363c70a0a5+1bb8e5b07c76 | `matches/rv4-v0-cc1-C9305` |
| 15 | Comet Catcher Remake 1.8 | Cortex | 9306 | 0 | L | 26.41 | x0.16 | 363c70a0a5+1bb8e5b07c76 | `matches/rv4-v0-cc1-C9306` |
| 16 | Comet Catcher Remake 1.8 | Cortex | 9307 | 0 | w | 30.0 | x1.43 | 363c70a0a5+1bb8e5b07c76 | `matches/rv4-v0-cc1-C9307` |
| 17 | Comet Catcher Remake 1.8 | Cortex | 9308 | 0 | w | 30.0 | x1.27 | 363c70a0a5+1bb8e5b07c76 | `matches/rv4-v0-cc1-C9308` |
| 18 | Comet Catcher Remake 1.8 | Cortex | 9309 | 0 | w | 30.0 | x2.66 | 363c70a0a5+1bb8e5b07c76 | `matches/rv4-v0-cc1-C9309` |
| 19 | Comet Catcher Remake 1.8 | Cortex | 9310 | 0 | w | 30.0 | x1.22 | 363c70a0a5+1bb8e5b07c76 | `matches/rv4-v0-cc1-C9310` |

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.15 (run `python tools/anomaly.py build`)
```
