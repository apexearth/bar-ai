<!-- meta {"date": "2026-11-14", "topic": "randomizer", "title": "BaRandom after the water-plant and flyer-door fixes (rnd2 same seeds, rnd3 new)", "games": 16, "W": 8, "L": 1, "w": 2, "l": 5, "inc20": 1.0, "verdict": "Water fix works: where v0.5.11 still opened the underwater gantry and built ~6k all game, ours opened the land gantry and built 26.8k and 43.8k. Still frozen: corhaap (dead-end refusals continue, its largest unit is not a flyer under the randomizer) and armshltx (no site found within 1600 on Comet Catcher / Carrot). Next: plants priced at their odds of finding a site, 1/(1+no-site deaths). One T1 roll opened air on all four seats (gains 5.9 air vs 5.9-8.0 ground; the ground lab's army half was 1.5 m/s)."} -->
# BaRandom after the water-plant and flyer-door fixes (rnd2 same seeds, rnd3 new)

- **Date:** 2026-11-14
- **Topic:** randomizer
- **Purpose:** Check the T3 freeze fixes: PlantClass reads minWaterDepth; C++ DoorEscapes skips a plant whose largest unit flies. 16 games, estall vs v0.5.11 2v2 +50, 25 min; not a version comparison.
- **Result:** 16 games: won 8, lost 1, timeouts ahead 2, behind 5; income at 20 min x1.00 ours/theirs
- **Verdict:** Water fix works: where v0.5.11 still opened the underwater gantry and built ~6k all game, ours opened the land gantry and built 26.8k and 43.8k. Still frozen: corhaap (dead-end refusals continue, its largest unit is not a flyer under the randomizer) and armshltx (no site found within 1600 on Comet Catcher / Carrot). Next: plants priced at their odds of finding a site, 1/(1+no-site deaths). One T1 roll opened air on all four seats (gains 5.9 air vs 5.9-8.0 ground; the ground lab's army half was 1.5 m/s).
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.11-standard
- **Code:** Apex-v0.5.11-standard = `v0.5.11` (16 games); Apexestall-lane-estall-standard = `c494a6f08c+dd5a64aca042` (16 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 25 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.11:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 25 --speed 20 --handicap 50 --sides Armada,Armada --seed 9434 --randomizer --out matches/rnd2-v0-cc-A9434`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9434 | 0 | W | 17.71 | - | c494a6f08c+dd5a64aca042, v0.5.11 | `matches/rnd2-v0-cc-A9434` |
| 1 | Comet Catcher Remake 1.8 | Cortex | 9431 | 0 | w | 25.0 | x4.32 | c494a6f08c+dd5a64aca042, v0.5.11 | `matches/rnd2-v0-cc-C9431` |
| 2 | Comet Catcher Remake 1.8 | Cortex | 9437 | 0 | l | 25.0 | x1.00 | c494a6f08c+dd5a64aca042, v0.5.11 | `matches/rnd2-v0-cc-C9437` |
| 3 | Carrot Mountains v2.0 | Armada | 9436 | 0 | W | 23.68 | x4.00 | c494a6f08c+dd5a64aca042, v0.5.11 | `matches/rnd2-v0-cm-A9436` |
| 4 | Carrot Mountains v2.0 | Cortex | 9433 | 0 | l | 25.0 | x0.68 | c494a6f08c+dd5a64aca042, v0.5.11 | `matches/rnd2-v0-cm-C9433` |
| 5 | Red Comet Remake 1.8 | Armada | 9432 | 0 | W | 10.29 | - | c494a6f08c+dd5a64aca042, v0.5.11 | `matches/rnd2-v0-rc-A9432` |
| 6 | Red Comet Remake 1.8 | Armada | 9438 | 0 | W | 12.4 | - | c494a6f08c+dd5a64aca042, v0.5.11 | `matches/rnd2-v0-rc-A9438` |
| 7 | Red Comet Remake 1.8 | Cortex | 9435 | 0 | l | 25.0 | x0.32 | c494a6f08c+dd5a64aca042, v0.5.11 | `matches/rnd2-v0-rc-C9435` |
| 8 | Comet Catcher Remake 1.8 | Armada | 9444 | 0 | l | 25.0 | x1.00 | c494a6f08c+dd5a64aca042, v0.5.11 | `matches/rnd3-v0-cc-A9444` |
| 9 | Comet Catcher Remake 1.8 | Cortex | 9441 | 0 | L | 23.79 | x0.12 | c494a6f08c+dd5a64aca042, v0.5.11 | `matches/rnd3-v0-cc-C9441` |
| 10 | Comet Catcher Remake 1.8 | Cortex | 9447 | 0 | w | 25.0 | x2.18 | c494a6f08c+dd5a64aca042, v0.5.11 | `matches/rnd3-v0-cc-C9447` |
| 11 | Carrot Mountains v2.0 | Armada | 9446 | 0 | l | 25.0 | x1.00 | c494a6f08c+dd5a64aca042, v0.5.11 | `matches/rnd3-v0-cm-A9446` |
| 12 | Carrot Mountains v2.0 | Cortex | 9443 | 0 | W | 16.63 | - | c494a6f08c+dd5a64aca042, v0.5.11 | `matches/rnd3-v0-cm-C9443` |
| 13 | Red Comet Remake 1.8 | Armada | 9442 | 0 | W | 10.53 | - | c494a6f08c+dd5a64aca042, v0.5.11 | `matches/rnd3-v0-rc-A9442` |
| 14 | Red Comet Remake 1.8 | Armada | 9448 | 0 | W | 18.42 | - | c494a6f08c+dd5a64aca042, v0.5.11 | `matches/rnd3-v0-rc-A9448` |
| 15 | Red Comet Remake 1.8 | Cortex | 9445 | 0 | W | 19.31 | - | c494a6f08c+dd5a64aca042, v0.5.11 | `matches/rnd3-v0-rc-C9445` |
