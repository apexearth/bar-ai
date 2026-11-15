<!-- meta {"date": "2026-11-14", "topic": "release-gate", "title": "Candidate with every 11-14 switch off vs v0.5.11 (pkg0)", "games": 12, "W": 1, "L": 1, "w": 3, "l": 7, "inc20": 0.78, "verdict": "Same lag: income at 20 x0.78, behind 7, ahead 3. Today's switches are not the cause; by game end they helped (built ratio higher in most pairs, e.g. 1.65 vs 0.31, 1.92 vs 0.62). Behind from minute 10 (built 0.92, eco 0.92; cons 0.75 and T2 mex 0.74 at 20). Not the net (lane runs v0.5.11's), not ally-key (0 asks). aa1 runs v0.5.11 vs itself on these seeds to test the side-A start."} -->
# Candidate with every 11-14 switch off vs v0.5.11 (pkg0)

- **Date:** 2026-11-14
- **Topic:** release-gate
- **Purpose:** Same 12 seeds as pkg1 with apex_con_floor_cap, protect, con_spot_count, con_spare, team_front, plant_site_odds, plant_class_army, air_gun_race, air_cadence_net all 0: are today's changes the lag, or older ones?
- **Result:** 12 games: won 1, lost 1, timeouts ahead 3, behind 7; income at 20 min x0.78 ours/theirs
- **Verdict:** Same lag: income at 20 x0.78, behind 7, ahead 3. Today's switches are not the cause; by game end they helped (built ratio higher in most pairs, e.g. 1.65 vs 0.31, 1.92 vs 0.62). Behind from minute 10 (built 0.92, eco 0.92; cons 0.75 and T2 mex 0.74 at 20). Not the net (lane runs v0.5.11's), not ally-key (0 asks). aa1 runs v0.5.11 vs itself on these seeds to test the side-A start.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.11-standard
- **Code:** Apex-v0.5.11-standard = `v0.5.11` (12 games); Apexestall-lane-estall-standard = `c494a6f08c+5d00bd523600` (12 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.11:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9503 --ai-option apex_con_floor_cap=0 --ai-option apex_protect=0 --ai-option apex_con_spot_count=0 --ai-option apex_con_spare=0 --ai-option apex_team_front=0 --ai-option apex_plant_site_odds=0 --ai-option apex_plant_class_army=0 --ai-option apex_air_gun_race=0 --ai-option apex_air_cadence_net=0 --out matches/pkg0-cc-A9503`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9503 | 0 | l | 30.0 | x0.83 | c494a6f08c+5d00bd523600, v0.5.11 | `matches/pkg0-cc-A9503` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9506 | 0 | w | 30.0 | x2.14 | c494a6f08c+5d00bd523600, v0.5.11 | `matches/pkg0-cc-A9506` |
| 2 | Comet Catcher Remake 1.8 | Cortex | 9503 | 0 | w | 30.0 | x0.56 | c494a6f08c+5d00bd523600, v0.5.11 | `matches/pkg0-cc-C9503` |
| 3 | Comet Catcher Remake 1.8 | Cortex | 9506 | 0 | W | 25.3 | x10.73 | c494a6f08c+5d00bd523600, v0.5.11 | `matches/pkg0-cc-C9506` |
| 4 | Carrot Mountains v2.0 | Armada | 9502 | 0 | l | 30.0 | x0.38 | c494a6f08c+5d00bd523600, v0.5.11 | `matches/pkg0-cm-A9502` |
| 5 | Carrot Mountains v2.0 | Armada | 9505 | 0 | l | 30.0 | x0.73 | c494a6f08c+5d00bd523600, v0.5.11 | `matches/pkg0-cm-A9505` |
| 6 | Carrot Mountains v2.0 | Cortex | 9502 | 0 | l | 30.0 | x0.72 | c494a6f08c+5d00bd523600, v0.5.11 | `matches/pkg0-cm-C9502` |
| 7 | Carrot Mountains v2.0 | Cortex | 9505 | 0 | l | 30.0 | x0.53 | c494a6f08c+5d00bd523600, v0.5.11 | `matches/pkg0-cm-C9505` |
| 8 | Red Comet Remake 1.8 | Armada | 9501 | 0 | l | 30.0 | x0.64 | c494a6f08c+5d00bd523600, v0.5.11 | `matches/pkg0-rc-A9501` |
| 9 | Red Comet Remake 1.8 | Armada | 9504 | 0 | w | 30.0 | x1.59 | c494a6f08c+5d00bd523600, v0.5.11 | `matches/pkg0-rc-A9504` |
| 10 | Red Comet Remake 1.8 | Cortex | 9501 | 0 | L | 24.56 | x0.08 | c494a6f08c+5d00bd523600, v0.5.11 | `matches/pkg0-rc-C9501` |
| 11 | Red Comet Remake 1.8 | Cortex | 9504 | 0 | l | 30.0 | x0.53 | c494a6f08c+5d00bd523600, v0.5.11 | `matches/pkg0-rc-C9504` |
