<!-- meta {"date": "2026-11-14", "topic": "constructors", "title": "Open-spot hands counted, not multiplied (apex_con_spot_count 1 vs 0)", "games": 16, "W": 2, "L": 1, "w": 6, "l": 7, "inc20": 1.21, "verdict": "Small, same direction in both: our cons 237 vs 265 (Legion), 88 vs 101 (normal); army share 45% vs 40%, 40% vs 33%; built ratio 1.40 vs 1.21, 0.98 vs 0.83. The floor's need fell to 5-32 later in the game, but HandsShort was still multiplied and the floor still ordered most cons (legck 102, legca 65 a seat); spare hands read up to 119. Next: HandsShort unscaled too (hcL/hcN)."} -->
# Open-spot hands counted, not multiplied (apex_con_spot_count 1 vs 0)

- **Date:** 2026-11-14
- **Topic:** constructors
- **Purpose:** The con floor took SpotHandsOwed and multiplied it by the con net's floor size (5.4-6.7, trust 1; rule 2.5): 5-6 constructors per open spot. 4 pairs Legion 2x income + 4 pairs normal +50, estall vs v0.5.11, 25 min.
- **Result:** 16 games: won 2, lost 1, timeouts ahead 6, behind 7; income at 20 min x1.21 ours/theirs
- **Verdict:** Small, same direction in both: our cons 237 vs 265 (Legion), 88 vs 101 (normal); army share 45% vs 40%, 40% vs 33%; built ratio 1.40 vs 1.21, 0.98 vs 0.83. The floor's need fell to 5-32 later in the game, but HandsShort was still multiplied and the floor still ordered most cons (legck 102, legca 65 a seat); spare hands read up to 119. Next: HandsShort unscaled too (hcL/hcN).
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.11-standard
- **Code:** Apex-v0.5.11-standard = `v0.5.11` (16 games); Apexestall-lane-estall-standard = `c494a6f08c+bc1085c0ab85` (16 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Red Comet Remake 1.8
- **Sides:** Armada, Cortex, Legion; **bonus:** 50; **time cap:** 25 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.11:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 25 --speed 20 --handicap 50 --sides Legion,Legion --seed 9461 --ai-option apex_con_spot_count=0 --modoption multiplier_resourceincome=2 --out matches/scL-v0-cc-L9461`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Legion | 9461 | 0 | w | 25.0 | x1.74 | c494a6f08c+bc1085c0ab85, v0.5.11 | `matches/scL-v0-cc-L9461` |
| 1 | Comet Catcher Remake 1.8 | Legion | 9464 | 0 | W | 23.61 | x3.43 | c494a6f08c+bc1085c0ab85, v0.5.11 | `matches/scL-v0-cc-L9464` |
| 2 | Carrot Mountains v2.0 | Legion | 9463 | 0 | l | 25.0 | x0.80 | c494a6f08c+bc1085c0ab85, v0.5.11 | `matches/scL-v0-cm-L9463` |
| 3 | Red Comet Remake 1.8 | Legion | 9462 | 0 | l | 25.0 | x1.04 | c494a6f08c+bc1085c0ab85, v0.5.11 | `matches/scL-v0-rc-L9462` |
| 4 | Comet Catcher Remake 1.8 | Legion | 9461 | 0 | w | 25.0 | x2.35 | c494a6f08c+bc1085c0ab85, v0.5.11 | `matches/scL-v1-cc-L9461` |
| 5 | Comet Catcher Remake 1.8 | Legion | 9464 | 0 | L | 23.67 | x0.39 | c494a6f08c+bc1085c0ab85, v0.5.11 | `matches/scL-v1-cc-L9464` |
| 6 | Carrot Mountains v2.0 | Legion | 9463 | 0 | l | 25.0 | x1.14 | c494a6f08c+bc1085c0ab85, v0.5.11 | `matches/scL-v1-cm-L9463` |
| 7 | Red Comet Remake 1.8 | Legion | 9462 | 0 | W | 21.28 | x2.44 | c494a6f08c+bc1085c0ab85, v0.5.11 | `matches/scL-v1-rc-L9462` |
| 8 | Carrot Mountains v2.0 | Armada | 9472 | 0 | l | 25.0 | x0.66 | c494a6f08c+bc1085c0ab85, v0.5.11 | `matches/scN-v0-cm-A9472` |
| 9 | Carrot Mountains v2.0 | Cortex | 9474 | 0 | l | 25.0 | x0.64 | c494a6f08c+bc1085c0ab85, v0.5.11 | `matches/scN-v0-cm-C9474` |
| 10 | Red Comet Remake 1.8 | Armada | 9473 | 0 | w | 25.0 | x1.05 | c494a6f08c+bc1085c0ab85, v0.5.11 | `matches/scN-v0-rc-A9473` |
| 11 | Red Comet Remake 1.8 | Cortex | 9471 | 0 | w | 25.0 | x1.78 | c494a6f08c+bc1085c0ab85, v0.5.11 | `matches/scN-v0-rc-C9471` |
| 12 | Carrot Mountains v2.0 | Armada | 9472 | 0 | w | 25.0 | x1.48 | c494a6f08c+bc1085c0ab85, v0.5.11 | `matches/scN-v1-cm-A9472` |
| 13 | Carrot Mountains v2.0 | Cortex | 9474 | 0 | l | 25.0 | x0.59 | c494a6f08c+bc1085c0ab85, v0.5.11 | `matches/scN-v1-cm-C9474` |
| 14 | Red Comet Remake 1.8 | Armada | 9473 | 0 | w | 25.0 | x1.96 | c494a6f08c+bc1085c0ab85, v0.5.11 | `matches/scN-v1-rc-A9473` |
| 15 | Red Comet Remake 1.8 | Cortex | 9471 | 0 | l | 25.0 | x1.20 | c494a6f08c+bc1085c0ab85, v0.5.11 | `matches/scN-v1-rc-C9471` |
