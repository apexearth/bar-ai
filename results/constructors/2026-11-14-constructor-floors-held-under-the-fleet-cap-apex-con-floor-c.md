<!-- meta {"date": "2026-11-14", "topic": "constructors", "title": "Constructor floors held under the fleet cap (apex_con_floor_cap 1 vs 0)", "games": 8, "W": 0, "L": 0, "w": 1, "l": 7, "inc20": 0.89, "verdict": "Not kept as is. Cap on: built ratio median 0.84 vs 1.06 off, kill margin -15.8k vs +7.2k, our cons median 87 vs 136 -- still 2x over the cap of 40, so the floors are not the only path, and on Red Comet both cap-on games fell well behind. 4 pairs is noise-level, but nothing here says the cap helps."} -->
# Constructor floors held under the fleet cap (apex_con_floor_cap 1 vs 0)

- **Date:** 2026-11-14
- **Topic:** constructors
- **Purpose:** His 11-14 randomizer game: 143-232 constructors a seat. The con floors bypassed ConPoolFull; FloorUnderCap holds them under it. 4 paired seeds, estall vs v0.5.11 2v2 +50, 25 min.
- **Result:** 8 games: won 0, lost 0, timeouts ahead 1, behind 7; income at 20 min x0.89 ours/theirs
- **Verdict:** Not kept as is. Cap on: built ratio median 0.84 vs 1.06 off, kill margin -15.8k vs +7.2k, our cons median 87 vs 136 -- still 2x over the cap of 40, so the floors are not the only path, and on Red Comet both cap-on games fell well behind. 4 pairs is noise-level, but nothing here says the cap helps.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.11-standard
- **Code:** Apex-v0.5.11-standard = `v0.5.11` (8 games); Apexestall-lane-estall-standard = `c494a6f08c+a6ce72ed13da` (8 games)
- **Maps:** Comet Catcher Remake 1.8, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 25 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.11:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 25 --speed 20 --handicap 50 --sides Armada,Armada --seed 9412 --ai-option apex_con_floor_cap=1 --out matches/cap1-v1-cc-A9412`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9412 | 0 | l | 25.0 | x1.04 | c494a6f08c+a6ce72ed13da, v0.5.11 | `matches/cap1-v1-cc-A9412` |
| 1 | Comet Catcher Remake 1.8 | Cortex | 9411 | 0 | l | 25.0 | x0.87 | c494a6f08c+a6ce72ed13da, v0.5.11 | `matches/cap1-v1-cc-C9411` |
| 2 | Red Comet Remake 1.8 | Armada | 9411 | 0 | l | 25.0 | x0.48 | c494a6f08c+a6ce72ed13da, v0.5.11 | `matches/cap1-v1-rc-A9411` |
| 3 | Red Comet Remake 1.8 | Cortex | 9412 | 0 | l | 25.0 | x0.74 | c494a6f08c+a6ce72ed13da, v0.5.11 | `matches/cap1-v1-rc-C9412` |
| 4 | Comet Catcher Remake 1.8 | Armada | 9412 | 0 | l | 25.0 | x0.82 | c494a6f08c+a6ce72ed13da, v0.5.11 | `matches/cap1-v0-cc-A9412` |
| 5 | Comet Catcher Remake 1.8 | Cortex | 9411 | 0 | l | 25.0 | x1.02 | c494a6f08c+a6ce72ed13da, v0.5.11 | `matches/cap1-v0-cc-C9411` |
| 6 | Red Comet Remake 1.8 | Armada | 9411 | 0 | w | 25.0 | x1.39 | c494a6f08c+a6ce72ed13da, v0.5.11 | `matches/cap1-v0-rc-A9411` |
| 7 | Red Comet Remake 1.8 | Cortex | 9412 | 0 | l | 25.0 | x1.04 | c494a6f08c+a6ce72ed13da, v0.5.11 | `matches/cap1-v0-rc-C9412` |
