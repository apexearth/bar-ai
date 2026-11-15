<!-- meta {"date": "2026-11-14", "topic": "randomizer", "title": "BaRandom Legion, double income (his 11-14 game's settings)", "games": 8, "W": 4, "L": 2, "w": 0, "l": 2, "inc20": 1.37, "verdict": "No air opener in 8. Both water-gantry T3 rolls froze v0.5.11 (4.9k, 5.4k built) and not ours (103k, 46k). One T3 roll (leghalab) put 1% of spend into army: 479 Infestors, which are assault bots that are also builders (build only themselves), ordered as constructors at gain 34k-66k; v0.5.11 the same with 1,157. His own game's glut was air cons (legca 122-134 per seat) from the con floor at need ~98 = rule need ~30 x TUNE_CON_RULE 2.5."} -->
# BaRandom Legion, double income (his 11-14 game's settings)

- **Date:** 2026-11-14
- **Topic:** randomizer
- **Purpose:** Reproduce his all-Legion 2x-resource randomizer game: air openers and the constructor glut. 8 games, estall vs v0.5.11 Legion mirror, multiplier_resourceincome=2, +50, 25 min.
- **Result:** 8 games: won 4, lost 2, timeouts ahead 0, behind 2; income at 20 min x1.37 ours/theirs
- **Verdict:** No air opener in 8. Both water-gantry T3 rolls froze v0.5.11 (4.9k, 5.4k built) and not ours (103k, 46k). One T3 roll (leghalab) put 1% of spend into army: 479 Infestors, which are assault bots that are also builders (build only themselves), ordered as constructors at gain 34k-66k; v0.5.11 the same with 1,157. His own game's glut was air cons (legca 122-134 per seat) from the con floor at need ~98 = rule need ~30 x TUNE_CON_RULE 2.5.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.11-standard
- **Code:** Apex-v0.5.11-standard = `v0.5.11` (8 games); Apexestall-lane-estall-standard = `c494a6f08c+dd5a64aca042` (8 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Red Comet Remake 1.8
- **Sides:** Legion; **bonus:** 50; **time cap:** 25 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.11:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 25 --speed 20 --handicap 50 --sides Legion,Legion --seed 9451 --randomizer --modoption multiplier_resourceincome=2 --out matches/rndL1-v0-cc-L9451`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Legion | 9451 | 0 | W | 8.85 | - | c494a6f08c+dd5a64aca042, v0.5.11 | `matches/rndL1-v0-cc-L9451` |
| 1 | Comet Catcher Remake 1.8 | Legion | 9454 | 0 | L | 12.61 | - | c494a6f08c+dd5a64aca042, v0.5.11 | `matches/rndL1-v0-cc-L9454` |
| 2 | Comet Catcher Remake 1.8 | Legion | 9457 | 0 | W | 20.67 | x5.29 | c494a6f08c+dd5a64aca042, v0.5.11 | `matches/rndL1-v0-cc-L9457` |
| 3 | Carrot Mountains v2.0 | Legion | 9453 | 0 | l | 25.0 | x0.79 | c494a6f08c+dd5a64aca042, v0.5.11 | `matches/rndL1-v0-cm-L9453` |
| 4 | Carrot Mountains v2.0 | Legion | 9456 | 0 | l | 25.0 | x0.61 | c494a6f08c+dd5a64aca042, v0.5.11 | `matches/rndL1-v0-cm-L9456` |
| 5 | Red Comet Remake 1.8 | Legion | 9452 | 0 | W | 13.06 | - | c494a6f08c+dd5a64aca042, v0.5.11 | `matches/rndL1-v0-rc-L9452` |
| 6 | Red Comet Remake 1.8 | Legion | 9455 | 0 | L | 17.78 | - | c494a6f08c+dd5a64aca042, v0.5.11 | `matches/rndL1-v0-rc-L9455` |
| 7 | Red Comet Remake 1.8 | Legion | 9458 | 0 | W | 9.73 | - | c494a6f08c+dd5a64aca042, v0.5.11 | `matches/rndL1-v0-rc-L9458` |
