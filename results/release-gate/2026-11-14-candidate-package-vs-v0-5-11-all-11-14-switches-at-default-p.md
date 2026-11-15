<!-- meta {"date": "2026-11-14", "topic": "release-gate", "title": "Candidate package vs v0.5.11, all 11-14 switches at default (pkg1)", "games": 12, "W": 0, "L": 1, "w": 3, "l": 8, "inc20": 0.78, "verdict": "Behind: income at 20 min x0.78, lost 1, ahead 3, behind 8 at time; kills about even (+1.6k a game); end-of-game built ratio median 0.96. pkg0 reruns the same seeds with every 11-14 switch off to tell today's changes from older ones."} -->
# Candidate package vs v0.5.11, all 11-14 switches at default (pkg1)

- **Date:** 2026-11-14
- **Topic:** release-gate
- **Purpose:** Progress check toward v0.5.12: everything in the estall tree as it would ship, 12 games 2v2 +50, Armada and Cortex, Red Comet / Carrot / Comet Catcher, 30 min.
- **Result:** 12 games: won 0, lost 1, timeouts ahead 3, behind 8; income at 20 min x0.78 ours/theirs
- **Verdict:** Behind: income at 20 min x0.78, lost 1, ahead 3, behind 8 at time; kills about even (+1.6k a game); end-of-game built ratio median 0.96. pkg0 reruns the same seeds with every 11-14 switch off to tell today's changes from older ones.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.11-standard
- **Code:** Apex-v0.5.11-standard = `v0.5.11` (12 games); Apexestall-lane-estall-standard = `c494a6f08c+5d00bd523600` (12 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.11:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9503 --out matches/pkg1-v0-cc-A9503`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9503 | 0 | l | 30.0 | x0.99 | c494a6f08c+5d00bd523600, v0.5.11 | `matches/pkg1-v0-cc-A9503` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9506 | 0 | l | 30.0 | x1.30 | c494a6f08c+5d00bd523600, v0.5.11 | `matches/pkg1-v0-cc-A9506` |
| 2 | Comet Catcher Remake 1.8 | Cortex | 9503 | 0 | w | 30.0 | x1.78 | c494a6f08c+5d00bd523600, v0.5.11 | `matches/pkg1-v0-cc-C9503` |
| 3 | Comet Catcher Remake 1.8 | Cortex | 9506 | 0 | l | 30.0 | x0.94 | c494a6f08c+5d00bd523600, v0.5.11 | `matches/pkg1-v0-cc-C9506` |
| 4 | Carrot Mountains v2.0 | Armada | 9502 | 0 | w | 30.0 | x0.90 | c494a6f08c+5d00bd523600, v0.5.11 | `matches/pkg1-v0-cm-A9502` |
| 5 | Carrot Mountains v2.0 | Armada | 9505 | 0 | l | 30.0 | x0.73 | c494a6f08c+5d00bd523600, v0.5.11 | `matches/pkg1-v0-cm-A9505` |
| 6 | Carrot Mountains v2.0 | Cortex | 9502 | 0 | l | 30.0 | x0.69 | c494a6f08c+5d00bd523600, v0.5.11 | `matches/pkg1-v0-cm-C9502` |
| 7 | Carrot Mountains v2.0 | Cortex | 9505 | 0 | l | 30.0 | x0.73 | c494a6f08c+5d00bd523600, v0.5.11 | `matches/pkg1-v0-cm-C9505` |
| 8 | Red Comet Remake 1.8 | Armada | 9501 | 0 | w | 30.0 | x1.49 | c494a6f08c+5d00bd523600, v0.5.11 | `matches/pkg1-v0-rc-A9501` |
| 9 | Red Comet Remake 1.8 | Armada | 9504 | 0 | L | 20.44 | x0.13 | c494a6f08c+5d00bd523600, v0.5.11 | `matches/pkg1-v0-rc-A9504` |
| 10 | Red Comet Remake 1.8 | Cortex | 9501 | 0 | l | 30.0 | x0.56 | c494a6f08c+5d00bd523600, v0.5.11 | `matches/pkg1-v0-rc-C9501` |
| 11 | Red Comet Remake 1.8 | Cortex | 9504 | 0 | l | 30.0 | x0.69 | c494a6f08c+5d00bd523600, v0.5.11 | `matches/pkg1-v0-rc-C9504` |
