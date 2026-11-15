<!-- meta {"date": "2026-11-14", "topic": "air", "title": "Escort fly-home on HOLD POSITION OFF vs v0.5.11 (esc4)", "games": 24, "W": 1, "L": 3, "w": 11, "l": 9, "inc20": 1.02, "verdict": ""} -->
# Escort fly-home on HOLD POSITION OFF vs v0.5.11 (esc4)

- **Date:** 2026-11-14
- **Topic:** air
- **Purpose:** Fly-home alone saved no fighters (esc3): they broke off to chase planes on the way home. This build sends them home on hold position (new C++ binding CmdHoldPos) and gives their move state back with their next task. Both arms: hunters only as surplus; no bomber wing at a negative priced net. This arm: apex_air_hold_home=0. Same seeds as esc3.
- **Result:** 24 games: won 1, lost 3, timeouts ahead 11, behind 9; income at 20 min x1.02 ours/theirs
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.11-standard
- **Code:** Apex-v0.5.11-standard = `v0.5.11` (24 games); Apexestall-lane-estall-standard = `c494a6f08c+3aab41690558` (24 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 35 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.11:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 35 --speed 20 --handicap 50 --sides Armada,Armada --seed 9401 --ai-option apex_air_hold_home=0 --out matches/esc4-h0-cc-A9401`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9401 | 0 | w | 35.0 | x1.43 | c494a6f08c+3aab41690558, v0.5.11 | `matches/esc4-h0-cc-A9401` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9402 | 0 | L | 30.93 | x0.50 | c494a6f08c+3aab41690558, v0.5.11 | `matches/esc4-h0-cc-A9402` |
| 2 | Comet Catcher Remake 1.8 | Armada | 9403 | 0 | w | 35.0 | x1.54 | c494a6f08c+3aab41690558, v0.5.11 | `matches/esc4-h0-cc-A9403` |
| 3 | Comet Catcher Remake 1.8 | Armada | 9404 | 0 | l | 35.0 | x1.34 | c494a6f08c+3aab41690558, v0.5.11 | `matches/esc4-h0-cc-A9404` |
| 4 | Comet Catcher Remake 1.8 | Cortex | 9401 | 0 | l | 35.0 | x0.80 | c494a6f08c+3aab41690558, v0.5.11 | `matches/esc4-h0-cc-C9401` |
| 5 | Comet Catcher Remake 1.8 | Cortex | 9402 | 0 | l | 35.0 | x0.53 | c494a6f08c+3aab41690558, v0.5.11 | `matches/esc4-h0-cc-C9402` |
| 6 | Comet Catcher Remake 1.8 | Cortex | 9403 | 0 | W | 28.61 | x2.01 | c494a6f08c+3aab41690558, v0.5.11 | `matches/esc4-h0-cc-C9403` |
| 7 | Comet Catcher Remake 1.8 | Cortex | 9404 | 0 | l | 35.0 | x0.89 | c494a6f08c+3aab41690558, v0.5.11 | `matches/esc4-h0-cc-C9404` |
| 8 | Carrot Mountains v2.0 | Armada | 9401 | 0 | w | 35.0 | x1.46 | c494a6f08c+3aab41690558, v0.5.11 | `matches/esc4-h0-cm-A9401` |
| 9 | Carrot Mountains v2.0 | Armada | 9402 | 0 | L | 26.76 | x0.70 | c494a6f08c+3aab41690558, v0.5.11 | `matches/esc4-h0-cm-A9402` |
| 10 | Carrot Mountains v2.0 | Armada | 9403 | 0 | l | 35.0 | x0.79 | c494a6f08c+3aab41690558, v0.5.11 | `matches/esc4-h0-cm-A9403` |
| 11 | Carrot Mountains v2.0 | Armada | 9404 | 0 | L | 29.14 | x0.53 | c494a6f08c+3aab41690558, v0.5.11 | `matches/esc4-h0-cm-A9404` |
| 12 | Carrot Mountains v2.0 | Cortex | 9401 | 0 | l | 35.0 | x0.94 | c494a6f08c+3aab41690558, v0.5.11 | `matches/esc4-h0-cm-C9401` |
| 13 | Carrot Mountains v2.0 | Cortex | 9402 | 0 | w | 35.0 | x1.46 | c494a6f08c+3aab41690558, v0.5.11 | `matches/esc4-h0-cm-C9402` |
| 14 | Carrot Mountains v2.0 | Cortex | 9403 | 0 | w | 35.0 | x1.30 | c494a6f08c+3aab41690558, v0.5.11 | `matches/esc4-h0-cm-C9403` |
| 15 | Carrot Mountains v2.0 | Cortex | 9404 | 0 | w | 35.0 | x0.98 | c494a6f08c+3aab41690558, v0.5.11 | `matches/esc4-h0-cm-C9404` |
| 16 | Red Comet Remake 1.8 | Armada | 9401 | 0 | w | 35.0 | x1.08 | c494a6f08c+3aab41690558, v0.5.11 | `matches/esc4-h0-rc-A9401` |
| 17 | Red Comet Remake 1.8 | Armada | 9402 | 0 | w | 35.0 | x1.11 | c494a6f08c+3aab41690558, v0.5.11 | `matches/esc4-h0-rc-A9402` |
| 18 | Red Comet Remake 1.8 | Armada | 9403 | 0 | l | 35.0 | x0.60 | c494a6f08c+3aab41690558, v0.5.11 | `matches/esc4-h0-rc-A9403` |
| 19 | Red Comet Remake 1.8 | Armada | 9404 | 0 | w | 35.0 | x1.99 | c494a6f08c+3aab41690558, v0.5.11 | `matches/esc4-h0-rc-A9404` |
| 20 | Red Comet Remake 1.8 | Cortex | 9401 | 0 | w | 35.0 | x1.42 | c494a6f08c+3aab41690558, v0.5.11 | `matches/esc4-h0-rc-C9401` |
| 21 | Red Comet Remake 1.8 | Cortex | 9402 | 0 | w | 35.0 | x1.26 | c494a6f08c+3aab41690558, v0.5.11 | `matches/esc4-h0-rc-C9402` |
| 22 | Red Comet Remake 1.8 | Cortex | 9403 | 0 | l | 35.0 | x1.07 | c494a6f08c+3aab41690558, v0.5.11 | `matches/esc4-h0-rc-C9403` |
| 23 | Red Comet Remake 1.8 | Cortex | 9404 | 0 | l | 35.0 | x0.69 | c494a6f08c+3aab41690558, v0.5.11 | `matches/esc4-h0-rc-C9404` |
