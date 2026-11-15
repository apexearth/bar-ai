<!-- meta {"date": "2026-11-14", "topic": "randomizer", "title": "T3 freeze seeds after the started-or-not site odds (rnd5)", "games": 4, "W": 1, "L": 0, "w": 2, "l": 1, "inc20": 2.71, "verdict": "Cortex fixed: 114.7k and 99.0k built vs v0.5.11's 5.4k and 11.8k. Armada still frozen in 2 of 2: every Armada T3 plant (armshltx, armhaap, armhalab, armhavp) refused as a dead end in all four facings; site odds fell to 0.02 but there is nothing placeable to switch to. Next: DoorEscapes does not refuse when the unit cannot leave home either (rnd6)."} -->
# T3 freeze seeds after the started-or-not site odds (rnd5)

- **Date:** 2026-11-14
- **Topic:** randomizer
- **Purpose:** PlantSiteOdds counted on orders that die before a frame stands.
- **Result:** 4 games: won 1, lost 0, timeouts ahead 2, behind 1; income at 20 min x2.71 ours/theirs
- **Verdict:** Cortex fixed: 114.7k and 99.0k built vs v0.5.11's 5.4k and 11.8k. Armada still frozen in 2 of 2: every Armada T3 plant (armshltx, armhaap, armhalab, armhavp) refused as a dead end in all four facings; site odds fell to 0.02 but there is nothing placeable to switch to. Next: DoorEscapes does not refuse when the unit cannot leave home either (rnd6).
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.11-standard
- **Code:** Apex-v0.5.11-standard = `v0.5.11` (4 games); Apexestall-lane-estall-standard = `c494a6f08c+bc1085c0ab85` (4 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 25 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.11:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 25 --speed 20 --handicap 50 --sides Armada,Armada --seed 9444 --randomizer --out matches/rnd5-v0-cc-A9444`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9444 | 0 | w | 25.0 | x2.05 | c494a6f08c+bc1085c0ab85, v0.5.11 | `matches/rnd5-v0-cc-A9444` |
| 1 | Comet Catcher Remake 1.8 | Cortex | 9437 | 0 | W | 10.07 | - | c494a6f08c+bc1085c0ab85, v0.5.11 | `matches/rnd5-v0-cc-C9437` |
| 2 | Carrot Mountains v2.0 | Armada | 9446 | 0 | l | 25.0 | x1.00 | c494a6f08c+bc1085c0ab85, v0.5.11 | `matches/rnd5-v0-cm-A9446` |
| 3 | Carrot Mountains v2.0 | Cortex | 9433 | 0 | w | 25.0 | x9.67 | c494a6f08c+bc1085c0ab85, v0.5.11 | `matches/rnd5-v0-cm-C9433` |
