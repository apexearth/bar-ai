<!-- meta {"date": "2026-11-13", "topic": "release-gate", "title": "v0.5.12 candidate (breach removed) vs v0.5.11 (512h)", "games": 16, "W": 2, "L": 2, "w": 5, "l": 7, "inc20": 0.87, "verdict": ""} -->
# v0.5.12 candidate (breach removed) vs v0.5.11 (512h)

- **Date:** 2026-11-13
- **Topic:** release-gate
- **Purpose:** Release-settings head-to-head of the build he took for 11-13 night (local v0.5.12): breach removed; slot removal, ally help on important buildings, anti-nuke on a known threat, missile launchers valued per shot, randomizer range clip, EMP range. Same seeds as 512b-g. Stopped by his game.
- **Result:** 16 games: won 2, lost 2, timeouts ahead 5, behind 7; income at 20 min x0.87 ours/theirs
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.11-standard
- **Code:** Apex-v0.5.11-standard = `v0.5.11` (16 games); Apexestall-lane-estall-standard = `c494a6f08c+16aae229cdad` (16 games)
- **Maps:** Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 35 min
- **Runs:** tournaments\20261113-220843-bench-cor512h, tournaments\20261113-220903-bench-arm512h
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.11:standard --map Red Comet Remake 1.8 --minutes 35 --seed 804968469 --out C:\Users\apexe\WebstormProjects\bar-ai\tournaments\20261113-220843-bench-cor512h\matches\t000-Apexestall_lane-estall_standard_vs_Apex_v0.5.11_standard-Red_Comet_Remake_1.8 --write-dir C:\Users\apexe\WebstormProjects\bar-ai\runtime\engine-w0-33436 --per-side 2 --replay --boxes lr --handicap 50 --sides Cortex,Cortex --speed 20`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Red Comet Remake 1.8 | Cortex | 804968469 | 0 | l | 35.0 | x1.24 | c494a6f08c+16aae229cdad, v0.5.11 | `tournaments/20261113-220843-bench-cor512h/matches/t000-Apexestall_lane-estall_standard_vs_Apex_v0.5.11_standard-Red_Comet_Remake_1.8` |
| 1 | Red Comet Remake 1.8 | Cortex | 804968469 | 1 | l | 35.0 | x0.66 | c494a6f08c+16aae229cdad, v0.5.11 | `tournaments/20261113-220843-bench-cor512h/matches/t001-Apex_v0.5.11_standard_vs_Apexestall_lane-estall_standard-Red_Comet_Remake_1.8` |
| 2 | Red Comet Remake 1.8 | Cortex | 804968470 | 0 | w | 35.0 | x1.21 | c494a6f08c+16aae229cdad, v0.5.11 | `tournaments/20261113-220843-bench-cor512h/matches/t002-Apexestall_lane-estall_standard_vs_Apex_v0.5.11_standard-Red_Comet_Remake_1.8` |
| 3 | Red Comet Remake 1.8 | Cortex | 804968470 | 1 | w | 35.0 | x1.01 | c494a6f08c+16aae229cdad, v0.5.11 | `tournaments/20261113-220843-bench-cor512h/matches/t003-Apex_v0.5.11_standard_vs_Apexestall_lane-estall_standard-Red_Comet_Remake_1.8` |
| 4 | Red Comet Remake 1.8 | Cortex | 804968471 | 0 | l | 35.0 | x1.24 | c494a6f08c+16aae229cdad, v0.5.11 | `tournaments/20261113-220843-bench-cor512h/matches/t004-Apexestall_lane-estall_standard_vs_Apex_v0.5.11_standard-Red_Comet_Remake_1.8` |
| 5 | Red Comet Remake 1.8 | Cortex | 804968471 | 1 | w | 35.0 | x0.52 | c494a6f08c+16aae229cdad, v0.5.11 | `tournaments/20261113-220843-bench-cor512h/matches/t005-Apex_v0.5.11_standard_vs_Apexestall_lane-estall_standard-Red_Comet_Remake_1.8` |
| 6 | Red Comet Remake 1.8 | Cortex | 804968472 | 0 | l | 35.0 | x0.73 | c494a6f08c+16aae229cdad, v0.5.11 | `tournaments/20261113-220843-bench-cor512h/matches/t006-Apexestall_lane-estall_standard_vs_Apex_v0.5.11_standard-Red_Comet_Remake_1.8` |
| 7 | Red Comet Remake 1.8 | Cortex | 804968472 | 1 | w | 35.0 | x1.20 | c494a6f08c+16aae229cdad, v0.5.11 | `tournaments/20261113-220843-bench-cor512h/matches/t007-Apex_v0.5.11_standard_vs_Apexestall_lane-estall_standard-Red_Comet_Remake_1.8` |
| 8 | Red Comet Remake 1.8 | Armada | 804968469 | 0 | l | 35.0 | x0.67 | c494a6f08c+16aae229cdad, v0.5.11 | `tournaments/20261113-220903-bench-arm512h/matches/t000-Apexestall_lane-estall_standard_vs_Apex_v0.5.11_standard-Red_Comet_Remake_1.8` |
| 9 | Red Comet Remake 1.8 | Armada | 804968469 | 1 | l | 35.0 | x0.67 | c494a6f08c+16aae229cdad, v0.5.11 | `tournaments/20261113-220903-bench-arm512h/matches/t001-Apex_v0.5.11_standard_vs_Apexestall_lane-estall_standard-Red_Comet_Remake_1.8` |
| 10 | Red Comet Remake 1.8 | Armada | 804968470 | 0 | L | 32.13 | x0.73 | c494a6f08c+16aae229cdad, v0.5.11 | `tournaments/20261113-220903-bench-arm512h/matches/t002-Apexestall_lane-estall_standard_vs_Apex_v0.5.11_standard-Red_Comet_Remake_1.8` |
| 11 | Red Comet Remake 1.8 | Armada | 804968470 | 1 | L | 27.3 | x0.33 | c494a6f08c+16aae229cdad, v0.5.11 | `tournaments/20261113-220903-bench-arm512h/matches/t003-Apex_v0.5.11_standard_vs_Apexestall_lane-estall_standard-Red_Comet_Remake_1.8` |
| 12 | Red Comet Remake 1.8 | Armada | 804968471 | 0 | w | 35.0 | x1.15 | c494a6f08c+16aae229cdad, v0.5.11 | `tournaments/20261113-220903-bench-arm512h/matches/t004-Apexestall_lane-estall_standard_vs_Apex_v0.5.11_standard-Red_Comet_Remake_1.8` |
| 13 | Red Comet Remake 1.8 | Armada | 804968471 | 1 | W | 28.9 | x2.09 | c494a6f08c+16aae229cdad, v0.5.11 | `tournaments/20261113-220903-bench-arm512h/matches/t005-Apex_v0.5.11_standard_vs_Apexestall_lane-estall_standard-Red_Comet_Remake_1.8` |
| 14 | Red Comet Remake 1.8 | Armada | 804968472 | 0 | l | 35.0 | x0.87 | c494a6f08c+16aae229cdad, v0.5.11 | `tournaments/20261113-220903-bench-arm512h/matches/t006-Apexestall_lane-estall_standard_vs_Apex_v0.5.11_standard-Red_Comet_Remake_1.8` |
| 15 | Red Comet Remake 1.8 | Armada | 804968472 | 1 | W | 19.77 | - | c494a6f08c+16aae229cdad, v0.5.11 | `tournaments/20261113-220903-bench-arm512h/matches/t007-Apex_v0.5.11_standard_vs_Apexestall_lane-estall_standard-Red_Comet_Remake_1.8` |
