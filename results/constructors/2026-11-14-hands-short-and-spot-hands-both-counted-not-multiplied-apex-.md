<!-- meta {"date": "2026-11-14", "topic": "constructors", "title": "Hands short and spot hands both counted, not multiplied (apex_con_spot_count 1 vs 0, second form)", "games": 16, "W": 2, "L": 3, "w": 7, "l": 4, "inc20": 1.17, "verdict": "Con-floor orders fell 30% (935 vs 1,335 over the 8 pairs, lower in 6). Army share 48% vs 42% (Legion), 40% vs 33% (normal); built ratio 0.90 vs 1.16 (Legion; one rc game lost early), 1.13 vs 1.10 (normal). Standing cons did not fall (they follow the economy). Found: the floor runs twice -- ground labs count only walkers, the air plant only flyers -- so each side fills the whole need, and the walker floor never subtracted spare hands. Spare hands now by kind; the double floor is his call."} -->
# Hands short and spot hands both counted, not multiplied (apex_con_spot_count 1 vs 0, second form)

- **Date:** 2026-11-14
- **Topic:** constructors
- **Purpose:** The con floor's multiplier (con net 5.4-7.1) scaled HandsShort as well as SpotHandsOwed. 4 pairs Legion 2x + 4 pairs normal +50, 25 min.
- **Result:** 16 games: won 2, lost 3, timeouts ahead 7, behind 4; income at 20 min x1.17 ours/theirs
- **Verdict:** Con-floor orders fell 30% (935 vs 1,335 over the 8 pairs, lower in 6). Army share 48% vs 42% (Legion), 40% vs 33% (normal); built ratio 0.90 vs 1.16 (Legion; one rc game lost early), 1.13 vs 1.10 (normal). Standing cons did not fall (they follow the economy). Found: the floor runs twice -- ground labs count only walkers, the air plant only flyers -- so each side fills the whole need, and the walker floor never subtracted spare hands. Spare hands now by kind; the double floor is his call.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.11-standard
- **Code:** Apex-v0.5.11-standard = `v0.5.11` (16 games); Apexestall-lane-estall-standard = `c494a6f08c+5f0c48e99fb5` (16 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Red Comet Remake 1.8
- **Sides:** Armada, Cortex, Legion; **bonus:** 50; **time cap:** 25 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.11:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 25 --speed 20 --handicap 50 --sides Legion,Legion --seed 9481 --ai-option apex_con_spot_count=0 --modoption multiplier_resourceincome=2 --out matches/hcL-v0-cc-L9481`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Legion | 9481 | 0 | L | 22.46 | x0.18 | c494a6f08c+5f0c48e99fb5, v0.5.11 | `matches/hcL-v0-cc-L9481` |
| 1 | Comet Catcher Remake 1.8 | Legion | 9484 | 0 | l | 25.0 | x1.45 | c494a6f08c+5f0c48e99fb5, v0.5.11 | `matches/hcL-v0-cc-L9484` |
| 2 | Carrot Mountains v2.0 | Legion | 9483 | 0 | w | 25.0 | x1.68 | c494a6f08c+5f0c48e99fb5, v0.5.11 | `matches/hcL-v0-cm-L9483` |
| 3 | Red Comet Remake 1.8 | Legion | 9482 | 0 | W | 23.53 | x7.02 | c494a6f08c+5f0c48e99fb5, v0.5.11 | `matches/hcL-v0-rc-L9482` |
| 4 | Comet Catcher Remake 1.8 | Legion | 9481 | 0 | w | 25.0 | x0.96 | c494a6f08c+5f0c48e99fb5, v0.5.11 | `matches/hcL-v1-cc-L9481` |
| 5 | Comet Catcher Remake 1.8 | Legion | 9484 | 0 | l | 25.0 | x1.47 | c494a6f08c+5f0c48e99fb5, v0.5.11 | `matches/hcL-v1-cc-L9484` |
| 6 | Carrot Mountains v2.0 | Legion | 9483 | 0 | w | 25.0 | x1.28 | c494a6f08c+5f0c48e99fb5, v0.5.11 | `matches/hcL-v1-cm-L9483` |
| 7 | Red Comet Remake 1.8 | Legion | 9482 | 0 | L | 16.91 | - | c494a6f08c+5f0c48e99fb5, v0.5.11 | `matches/hcL-v1-rc-L9482` |
| 8 | Carrot Mountains v2.0 | Armada | 9492 | 0 | l | 25.0 | x0.89 | c494a6f08c+5f0c48e99fb5, v0.5.11 | `matches/hcN-v0-cm-A9492` |
| 9 | Carrot Mountains v2.0 | Cortex | 9494 | 0 | w | 25.0 | x1.42 | c494a6f08c+5f0c48e99fb5, v0.5.11 | `matches/hcN-v0-cm-C9494` |
| 10 | Red Comet Remake 1.8 | Armada | 9493 | 0 | W | 17.65 | - | c494a6f08c+5f0c48e99fb5, v0.5.11 | `matches/hcN-v0-rc-A9493` |
| 11 | Red Comet Remake 1.8 | Cortex | 9491 | 0 | l | 25.0 | x0.46 | c494a6f08c+5f0c48e99fb5, v0.5.11 | `matches/hcN-v0-rc-C9491` |
| 12 | Carrot Mountains v2.0 | Armada | 9492 | 0 | w | 25.0 | x1.59 | c494a6f08c+5f0c48e99fb5, v0.5.11 | `matches/hcN-v1-cm-A9492` |
| 13 | Carrot Mountains v2.0 | Cortex | 9494 | 0 | w | 25.0 | x1.41 | c494a6f08c+5f0c48e99fb5, v0.5.11 | `matches/hcN-v1-cm-C9494` |
| 14 | Red Comet Remake 1.8 | Armada | 9493 | 0 | L | 17.82 | - | c494a6f08c+5f0c48e99fb5, v0.5.11 | `matches/hcN-v1-rc-A9493` |
| 15 | Red Comet Remake 1.8 | Cortex | 9491 | 0 | w | 25.0 | x1.06 | c494a6f08c+5f0c48e99fb5, v0.5.11 | `matches/hcN-v1-rc-C9491` |
