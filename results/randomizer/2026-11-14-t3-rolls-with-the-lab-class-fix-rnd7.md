<!-- meta {"date": "2026-11-14", "topic": "randomizer", "title": "T3 rolls with the lab-class fix (rnd7)", "games": 5, "W": 0, "L": 0, "w": 5, "l": 0, "inc20": 21.16, "verdict": "No freeze in 5 (built 92k-321k vs v0.5.11 6k-11k), but army 2-6% of spend in the four T3 rolls. One roll gave corvacct a cost of 1 metal: 1,537-1,664 of them a seat. Randomizer-only; not chased further today."} -->
# T3 rolls with the lab-class fix (rnd7)

- **Date:** 2026-11-14
- **Topic:** randomizer
- **Purpose:** A lab offering an air con stays ground while it fields ground combat (apex_plant_class_army).
- **Result:** 5 games: won 0, lost 0, timeouts ahead 5, behind 0; income at 20 min x21.16 ours/theirs
- **Verdict:** No freeze in 5 (built 92k-321k vs v0.5.11 6k-11k), but army 2-6% of spend in the four T3 rolls. One roll gave corvacct a cost of 1 metal: 1,537-1,664 of them a seat. Randomizer-only; not chased further today.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.11-standard
- **Code:** Apex-v0.5.11-standard = `v0.5.11` (5 games); Apexestall-lane-estall-standard = `c494a6f08c+5d00bd523600` (5 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8
- **Sides:** Armada, Cortex, Legion; **bonus:** 50; **time cap:** 25 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.11:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 25 --speed 20 --handicap 50 --sides Armada,Armada --seed 9444 --randomizer --out matches/rnd7-v0-cc-A9444`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9444 | 0 | w | 25.0 | x73.13 | c494a6f08c+5d00bd523600, v0.5.11 | `matches/rnd7-v0-cc-A9444` |
| 1 | Comet Catcher Remake 1.8 | Cortex | 9437 | 0 | w | 25.0 | x88.93 | c494a6f08c+5d00bd523600, v0.5.11 | `matches/rnd7-v0-cc-C9437` |
| 2 | Carrot Mountains v2.0 | Armada | 9446 | 0 | w | 25.0 | x68.15 | c494a6f08c+5d00bd523600, v0.5.11 | `matches/rnd7-v0-cm-A9446` |
| 3 | Carrot Mountains v2.0 | Cortex | 9433 | 0 | w | 25.0 | x8.81 | c494a6f08c+5d00bd523600, v0.5.11 | `matches/rnd7-v0-cm-C9433` |
| 4 | Carrot Mountains v2.0 | Legion | 9453 | 0 | w | 25.0 | x1.09 | c494a6f08c+5d00bd523600, v0.5.11 | `matches/rnd7-v0-cm-L9453` |
