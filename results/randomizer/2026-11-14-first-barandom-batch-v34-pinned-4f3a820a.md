<!-- meta {"date": "2026-11-14", "topic": "randomizer", "title": "First BaRandom batch (v34, pinned 4f3a820a)", "games": 8, "W": 1, "L": 3, "w": 2, "l": 2, "inc20": 0.6, "verdict": "Three of three T3 rolls (all Cortex) froze both AIs for 25 min: the commander re-elected one unplaceable plant 1,700-2,800 times (underwater gantry on land: PlantClass missed minWaterDepth; experimental aircraft plant: C++ DoorEscapes refused a flyer plant as a dead end, 1,088 times). Fixed both; rnd2 reruns the seeds. T1/T2 rolls opened air more often than ground (armap 19 vs armlab 4; armaap 32-46 vs armalab 13-27)."} -->
# First BaRandom batch (v34, pinned 4f3a820a)

- **Date:** 2026-11-14
- **Topic:** randomizer
- **Purpose:** His 11-14: randomized units find the flaws in the decision logic. 8 games, estall vs v0.5.11 2v2 +50, 25 min; not a version comparison.
- **Result:** 8 games: won 1, lost 3, timeouts ahead 2, behind 2; income at 20 min x0.60 ours/theirs
- **Verdict:** Three of three T3 rolls (all Cortex) froze both AIs for 25 min: the commander re-elected one unplaceable plant 1,700-2,800 times (underwater gantry on land: PlantClass missed minWaterDepth; experimental aircraft plant: C++ DoorEscapes refused a flyer plant as a dead end, 1,088 times). Fixed both; rnd2 reruns the seeds. T1/T2 rolls opened air more often than ground (armap 19 vs armlab 4; armaap 32-46 vs armalab 13-27).
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.11-standard
- **Code:** Apex-v0.5.11-standard = `v0.5.11` (8 games); Apexestall-lane-estall-standard = `c494a6f08c+a6ce72ed13da` (8 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 25 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.11:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 25 --speed 20 --handicap 50 --sides Armada,Armada --seed 9434 --randomizer --out matches/rnd1-v0-cc-A9434`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9434 | 0 | L | 17.58 | - | c494a6f08c+a6ce72ed13da, v0.5.11 | `matches/rnd1-v0-cc-A9434` |
| 1 | Comet Catcher Remake 1.8 | Cortex | 9431 | 0 | l | 25.0 | x0.99 | c494a6f08c+a6ce72ed13da, v0.5.11 | `matches/rnd1-v0-cc-C9431` |
| 2 | Comet Catcher Remake 1.8 | Cortex | 9437 | 0 | w | 25.0 | x1.00 | c494a6f08c+a6ce72ed13da, v0.5.11 | `matches/rnd1-v0-cc-C9437` |
| 3 | Carrot Mountains v2.0 | Armada | 9436 | 0 | L | 20.14 | x0.05 | c494a6f08c+a6ce72ed13da, v0.5.11 | `matches/rnd1-v0-cm-A9436` |
| 4 | Carrot Mountains v2.0 | Cortex | 9433 | 0 | l | 25.0 | x0.68 | c494a6f08c+a6ce72ed13da, v0.5.11 | `matches/rnd1-v0-cm-C9433` |
| 5 | Red Comet Remake 1.8 | Armada | 9432 | 0 | w | 25.0 | x2.31 | c494a6f08c+a6ce72ed13da, v0.5.11 | `matches/rnd1-v0-rc-A9432` |
| 6 | Red Comet Remake 1.8 | Armada | 9438 | 0 | L | 17.76 | - | c494a6f08c+a6ce72ed13da, v0.5.11 | `matches/rnd1-v0-rc-A9438` |
| 7 | Red Comet Remake 1.8 | Cortex | 9435 | 0 | W | 12.71 | - | c494a6f08c+a6ce72ed13da, v0.5.11 | `matches/rnd1-v0-rc-C9435` |
