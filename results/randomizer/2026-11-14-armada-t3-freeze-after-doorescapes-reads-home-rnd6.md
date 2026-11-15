<!-- meta {"date": "2026-11-14", "topic": "randomizer", "title": "Armada T3 freeze after DoorEscapes reads home (rnd6)", "games": 2, "W": 0, "L": 0, "w": 2, "l": 0, "inc20": 100.84, "verdict": "Fixed: 297k and 327k built vs v0.5.11's 5.8k and 5.1k. But army 1-2% of spend: 8-9 T3 bot labs a seat that made only constructors -- the roll gave armhalab a flying con, PlantClass called it an air plant, and its army half read the strike net (0). Next: a lab with ground combat stays ground (rnd7)."} -->
# Armada T3 freeze after DoorEscapes reads home (rnd6)

- **Date:** 2026-11-14
- **Topic:** randomizer
- **Purpose:** DoorEscapes does not refuse a door when the largest unit cannot leave home either.
- **Result:** 2 games: won 0, lost 0, timeouts ahead 2, behind 0; income at 20 min x100.84 ours/theirs
- **Verdict:** Fixed: 297k and 327k built vs v0.5.11's 5.8k and 5.1k. But army 1-2% of spend: 8-9 T3 bot labs a seat that made only constructors -- the roll gave armhalab a flying con, PlantClass called it an air plant, and its army half read the strike net (0). Next: a lab with ground combat stays ground (rnd7).
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.11-standard
- **Code:** Apex-v0.5.11-standard = `v0.5.11` (2 games); Apexestall-lane-estall-standard = `c494a6f08c+5f0c48e99fb5` (2 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8
- **Sides:** Armada; **bonus:** 50; **time cap:** 25 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.11:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 25 --speed 20 --handicap 50 --sides Armada,Armada --seed 9444 --randomizer --out matches/rnd6-v0-cc-A9444`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9444 | 0 | w | 25.0 | x98.48 | c494a6f08c+5f0c48e99fb5, v0.5.11 | `matches/rnd6-v0-cc-A9444` |
| 1 | Carrot Mountains v2.0 | Armada | 9446 | 0 | w | 25.0 | x103.25 | c494a6f08c+5f0c48e99fb5, v0.5.11 | `matches/rnd6-v0-cm-A9446` |
