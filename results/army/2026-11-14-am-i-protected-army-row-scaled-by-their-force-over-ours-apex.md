<!-- meta {"date": "2026-11-14", "topic": "army", "title": "Am I protected: army row scaled by their force over ours (apex_protect 1 vs 0)", "games": 8, "W": 2, "L": 0, "w": 5, "l": 1, "inc20": 1.86, "verdict": "Inconclusive: an A/A. The multiplier rose above 1 on 2 of 480 log lines; in these games we always out-held what we saw (ratio 0.03-0.9). Needs games where we are outgunned, or a reading of their force we are not seeing."} -->
# Am I protected: army row scaled by their force over ours (apex_protect 1 vs 0)

- **Date:** 2026-11-14
- **Topic:** army
- **Purpose:** His 11-14: the AI must know whether its army protects it. ProtectMult = enemy ground force known / team army+guns, clamped 1..3, on the ARMY budget row. 4 paired seeds, 30 min.
- **Result:** 8 games: won 2, lost 0, timeouts ahead 5, behind 1; income at 20 min x1.86 ours/theirs
- **Verdict:** Inconclusive: an A/A. The multiplier rose above 1 on 2 of 480 log lines; in these games we always out-held what we saw (ratio 0.03-0.9). Needs games where we are outgunned, or a reading of their force we are not seeing.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.11-standard
- **Code:** Apex-v0.5.11-standard = `v0.5.11` (8 games); Apexestall-lane-estall-standard = `c494a6f08c+a6ce72ed13da` (8 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.11:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Cortex,Cortex --seed 9421 --ai-option apex_protect=1 --out matches/prot1-v1-cc-C9421`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Cortex | 9421 | 0 | w | 30.0 | x1.01 | c494a6f08c+a6ce72ed13da, v0.5.11 | `matches/prot1-v1-cc-C9421` |
| 1 | Carrot Mountains v2.0 | Armada | 9422 | 0 | w | 30.0 | x0.76 | c494a6f08c+a6ce72ed13da, v0.5.11 | `matches/prot1-v1-cm-A9422` |
| 2 | Carrot Mountains v2.0 | Cortex | 9422 | 0 | w | 30.0 | x1.62 | c494a6f08c+a6ce72ed13da, v0.5.11 | `matches/prot1-v1-cm-C9422` |
| 3 | Red Comet Remake 1.8 | Armada | 9421 | 0 | W | 20.99 | x6.71 | c494a6f08c+a6ce72ed13da, v0.5.11 | `matches/prot1-v1-rc-A9421` |
| 4 | Comet Catcher Remake 1.8 | Cortex | 9421 | 0 | w | 30.0 | x1.68 | c494a6f08c+a6ce72ed13da, v0.5.11 | `matches/prot1-v0-cc-C9421` |
| 5 | Carrot Mountains v2.0 | Armada | 9422 | 0 | l | 30.0 | x1.64 | c494a6f08c+a6ce72ed13da, v0.5.11 | `matches/prot1-v0-cm-A9422` |
| 6 | Carrot Mountains v2.0 | Cortex | 9422 | 0 | w | 30.0 | x1.45 | c494a6f08c+a6ce72ed13da, v0.5.11 | `matches/prot1-v0-cm-C9422` |
| 7 | Red Comet Remake 1.8 | Armada | 9421 | 0 | W | 23.13 | x4.23 | c494a6f08c+a6ce72ed13da, v0.5.11 | `matches/prot1-v0-rc-A9421` |
