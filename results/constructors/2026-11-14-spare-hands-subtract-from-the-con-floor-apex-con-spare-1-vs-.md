<!-- meta {"date": "2026-11-14", "topic": "constructors", "title": "Spare hands subtract from the con floor (apex_con_spare 1 vs 0)", "games": 16, "W": 0, "L": 2, "w": 5, "l": 9, "inc20": 0.87, "verdict": "Mechanism did not bite: con-floor orders were not lower with it on (389 vs 256, 279 vs 242) and our cons rose (median 257 vs 101 Legion, 188 vs 104 normal); results favoured on (built ratio 1.12 vs 0.56 Legion, 1.09 vs 0.89 normal) but with the floor unchanged that is game noise. The floor's need is 200-400 a seat on 2x income: SpotHandsOwed (43-82 open spots) x the con net's floor multiplier 5.4-5.6 (trust=1; the rule is 2.5). Next: spots counted, not multiplied (apex_con_spot_count)."} -->
# Spare hands subtract from the con floor (apex_con_spare 1 vs 0)

- **Date:** 2026-11-14
- **Topic:** constructors
- **Purpose:** His 11-14 game: 120+ air cons on make-work while the floor asked for 98. Cons the market had nothing for in 30 s subtract from ConsNeedAt. 4 pairs Legion 2x income + 4 pairs normal +50, estall vs v0.5.11, 25 min.
- **Result:** 16 games: won 0, lost 2, timeouts ahead 5, behind 9; income at 20 min x0.87 ours/theirs
- **Verdict:** Mechanism did not bite: con-floor orders were not lower with it on (389 vs 256, 279 vs 242) and our cons rose (median 257 vs 101 Legion, 188 vs 104 normal); results favoured on (built ratio 1.12 vs 0.56 Legion, 1.09 vs 0.89 normal) but with the floor unchanged that is game noise. The floor's need is 200-400 a seat on 2x income: SpotHandsOwed (43-82 open spots) x the con net's floor multiplier 5.4-5.6 (trust=1; the rule is 2.5). Next: spots counted, not multiplied (apex_con_spot_count).
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.11-standard
- **Code:** Apex-v0.5.11-standard = `v0.5.11` (16 games); Apexestall-lane-estall-standard = `c494a6f08c+bee41ea7b150` (16 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Red Comet Remake 1.8
- **Sides:** Armada, Cortex, Legion; **bonus:** 50; **time cap:** 25 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.11:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 25 --speed 20 --handicap 50 --sides Legion,Legion --seed 9461 --ai-option apex_con_spare=0 --modoption multiplier_resourceincome=2 --out matches/spL-v0-cc-L9461`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Legion | 9461 | 0 | L | 22.67 | x0.32 | c494a6f08c+bee41ea7b150, v0.5.11 | `matches/spL-v0-cc-L9461` |
| 1 | Comet Catcher Remake 1.8 | Legion | 9464 | 0 | l | 25.0 | x0.71 | c494a6f08c+bee41ea7b150, v0.5.11 | `matches/spL-v0-cc-L9464` |
| 2 | Carrot Mountains v2.0 | Legion | 9463 | 0 | l | 25.0 | x0.75 | c494a6f08c+bee41ea7b150, v0.5.11 | `matches/spL-v0-cm-L9463` |
| 3 | Red Comet Remake 1.8 | Legion | 9462 | 0 | L | 23.66 | x0.27 | c494a6f08c+bee41ea7b150, v0.5.11 | `matches/spL-v0-rc-L9462` |
| 4 | Comet Catcher Remake 1.8 | Legion | 9461 | 0 | w | 25.0 | x0.93 | c494a6f08c+bee41ea7b150, v0.5.11 | `matches/spL-v1-cc-L9461` |
| 5 | Comet Catcher Remake 1.8 | Legion | 9464 | 0 | l | 25.0 | x0.34 | c494a6f08c+bee41ea7b150, v0.5.11 | `matches/spL-v1-cc-L9464` |
| 6 | Carrot Mountains v2.0 | Legion | 9463 | 0 | w | 25.0 | x1.10 | c494a6f08c+bee41ea7b150, v0.5.11 | `matches/spL-v1-cm-L9463` |
| 7 | Red Comet Remake 1.8 | Legion | 9462 | 0 | l | 25.0 | x1.14 | c494a6f08c+bee41ea7b150, v0.5.11 | `matches/spL-v1-rc-L9462` |
| 8 | Carrot Mountains v2.0 | Armada | 9472 | 0 | l | 25.0 | x0.51 | c494a6f08c+bee41ea7b150, v0.5.11 | `matches/spN-v0-cm-A9472` |
| 9 | Carrot Mountains v2.0 | Cortex | 9474 | 0 | l | 25.0 | x0.87 | c494a6f08c+bee41ea7b150, v0.5.11 | `matches/spN-v0-cm-C9474` |
| 10 | Red Comet Remake 1.8 | Armada | 9473 | 0 | l | 25.0 | x3.90 | c494a6f08c+bee41ea7b150, v0.5.11 | `matches/spN-v0-rc-A9473` |
| 11 | Red Comet Remake 1.8 | Cortex | 9471 | 0 | l | 25.0 | x1.15 | c494a6f08c+bee41ea7b150, v0.5.11 | `matches/spN-v0-rc-C9471` |
| 12 | Carrot Mountains v2.0 | Armada | 9472 | 0 | w | 25.0 | x1.08 | c494a6f08c+bee41ea7b150, v0.5.11 | `matches/spN-v1-cm-A9472` |
| 13 | Carrot Mountains v2.0 | Cortex | 9474 | 0 | w | 25.0 | x1.07 | c494a6f08c+bee41ea7b150, v0.5.11 | `matches/spN-v1-cm-C9474` |
| 14 | Red Comet Remake 1.8 | Armada | 9473 | 0 | w | 25.0 | x2.04 | c494a6f08c+bee41ea7b150, v0.5.11 | `matches/spN-v1-rc-A9473` |
| 15 | Red Comet Remake 1.8 | Cortex | 9471 | 0 | l | 25.0 | x1.15 | c494a6f08c+bee41ea7b150, v0.5.11 | `matches/spN-v1-rc-C9471` |
