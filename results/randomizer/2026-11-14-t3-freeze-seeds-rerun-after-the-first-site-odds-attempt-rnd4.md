<!-- meta {"date": "2026-11-14", "topic": "randomizer", "title": "T3 freeze seeds rerun after the first site-odds attempt (rnd4)", "games": 4, "W": 0, "L": 0, "w": 1, "l": 3, "inc20": 0.93, "verdict": "Still frozen in 4 of 4: the counter never fired (the dead task keeps its asked position, so the no-position test missed it). Redone on 'died before its frame stood' with a 30 s x (1+n) run; rnd5 reruns."} -->
# T3 freeze seeds rerun after the first site-odds attempt (rnd4)

- **Date:** 2026-11-14
- **Topic:** randomizer
- **Purpose:** Check PlantSiteOdds on the four T3 rolls that froze.
- **Result:** 4 games: won 0, lost 0, timeouts ahead 1, behind 3; income at 20 min x0.93 ours/theirs
- **Verdict:** Still frozen in 4 of 4: the counter never fired (the dead task keeps its asked position, so the no-position test missed it). Redone on 'died before its frame stood' with a 30 s x (1+n) run; rnd5 reruns.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.11-standard
- **Code:** Apex-v0.5.11-standard = `v0.5.11` (4 games); Apexestall-lane-estall-standard = `c494a6f08c+bee41ea7b150` (4 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 25 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.11:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 25 --speed 20 --handicap 50 --sides Armada,Armada --seed 9444 --randomizer --out matches/rnd4-v0-cc-A9444`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9444 | 0 | l | 25.0 | x0.85 | c494a6f08c+bee41ea7b150, v0.5.11 | `matches/rnd4-v0-cc-A9444` |
| 1 | Comet Catcher Remake 1.8 | Cortex | 9437 | 0 | l | 25.0 | x0.86 | c494a6f08c+bee41ea7b150, v0.5.11 | `matches/rnd4-v0-cc-C9437` |
| 2 | Carrot Mountains v2.0 | Armada | 9446 | 0 | l | 25.0 | x1.00 | c494a6f08c+bee41ea7b150, v0.5.11 | `matches/rnd4-v0-cm-A9446` |
| 3 | Carrot Mountains v2.0 | Cortex | 9433 | 0 | w | 25.0 | x1.00 | c494a6f08c+bee41ea7b150, v0.5.11 | `matches/rnd4-v0-cm-C9433` |
