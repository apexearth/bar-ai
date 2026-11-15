<!-- meta {"date": "2026-11-14", "topic": "release-gate", "title": "Side-A start control: v0.5.11 vs v0.5.11 on the package seeds (aa1)", "games": 12, "W": 0, "L": 0, "w": 6, "l": 6, "inc20": 0.89, "verdict": "Side A reads income at 20 x0.89, ahead 6 / behind 6, built at 20 0.97. So of the candidate's x0.78 (ahead 3, behind 7-8, built 0.92) about x0.88 is real: a ~10% early-economy regression from changes older than 11-14. Bisect next: v0.5.12 as deployed 11-14 morning (v512), candidate with apex_air_hold_home 0 (hh1)."} -->
# Side-A start control: v0.5.11 vs v0.5.11 on the package seeds (aa1)

- **Date:** 2026-11-14
- **Topic:** release-gate
- **Purpose:** Our AI always plays side A. Same 12 seeds as pkg0/pkg1, v0.5.11 on both sides.
- **Result:** 12 games: won 0, lost 0, timeouts ahead 6, behind 6; income at 20 min x0.89 ours/theirs
- **Verdict:** Side A reads income at 20 x0.89, ahead 6 / behind 6, built at 20 0.97. So of the candidate's x0.78 (ahead 3, behind 7-8, built 0.92) about x0.88 is real: a ~10% early-economy regression from changes older than 11-14. Bisect next: v0.5.12 as deployed 11-14 morning (v512), candidate with apex_air_hold_home 0 (hh1).
- **Ours:** Apex-v0.5.11-standard
- **Opponents:** Apex-v0.5.11-standard
- **Code:** Apex-v0.5.11-standard = `v0.5.11` (12 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apex:v0.5.11:standard --b Apex:v0.5.11:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9503 --out matches/aa1-cc-A9503`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9503 | 0 | w | 30.0 | x1.71 | v0.5.11 | `matches/aa1-cc-A9503` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9506 | 0 | w | 30.0 | x1.09 | v0.5.11 | `matches/aa1-cc-A9506` |
| 2 | Comet Catcher Remake 1.8 | Cortex | 9503 | 0 | l | 30.0 | x0.60 | v0.5.11 | `matches/aa1-cc-C9503` |
| 3 | Comet Catcher Remake 1.8 | Cortex | 9506 | 0 | w | 30.0 | x1.88 | v0.5.11 | `matches/aa1-cc-C9506` |
| 4 | Carrot Mountains v2.0 | Armada | 9502 | 0 | l | 30.0 | x0.87 | v0.5.11 | `matches/aa1-cm-A9502` |
| 5 | Carrot Mountains v2.0 | Armada | 9505 | 0 | w | 30.0 | x1.03 | v0.5.11 | `matches/aa1-cm-A9505` |
| 6 | Carrot Mountains v2.0 | Cortex | 9502 | 0 | w | 30.0 | x0.75 | v0.5.11 | `matches/aa1-cm-C9502` |
| 7 | Carrot Mountains v2.0 | Cortex | 9505 | 0 | l | 30.0 | x1.11 | v0.5.11 | `matches/aa1-cm-C9505` |
| 8 | Red Comet Remake 1.8 | Armada | 9501 | 0 | w | 30.0 | x0.84 | v0.5.11 | `matches/aa1-rc-A9501` |
| 9 | Red Comet Remake 1.8 | Armada | 9504 | 0 | l | 30.0 | x0.40 | v0.5.11 | `matches/aa1-rc-A9504` |
| 10 | Red Comet Remake 1.8 | Cortex | 9501 | 0 | l | 30.0 | x0.71 | v0.5.11 | `matches/aa1-rc-C9501` |
| 11 | Red Comet Remake 1.8 | Cortex | 9504 | 0 | l | 30.0 | x0.70 | v0.5.11 | `matches/aa1-rc-C9504` |
