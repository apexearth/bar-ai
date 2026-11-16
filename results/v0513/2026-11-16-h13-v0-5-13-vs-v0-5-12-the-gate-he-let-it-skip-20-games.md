<!-- meta {"date": "2026-11-16", "topic": "v0513", "title": "h13: v0.5.13 vs v0.5.12, the gate he let it skip (20 games)", "games": 20, "W": 1, "L": 3, "w": 7, "l": 9, "inc20": 0.9, "verdict": "Not better than v0.5.12. Contract FAIL (2): won or ahead 0.45 vs 0.50, army share 0.38 vs 0.42; income at 20 x0.90. Better on near-done strips 9.4 vs 14.9, supers before 4 moho 2.9 vs 4.3, gunships sent to lose 0.00 vs 0.32 (row 110), stacked senses 0.20 vs 0.28, army stuck 45 vs 58 per 10 min. Worse on bare-hands 1.3 vs 0.5 and frozen 0.8 vs 0.4 minutes. Unstable (rc7) is tested against v0.5.13 next."} -->
# h13: v0.5.13 vs v0.5.12, the gate he let it skip (20 games)

- **Date:** 2026-11-16
- **Topic:** v0513
- **Purpose:** His 11-15 'skip the gate this time': v0.5.13 shipped on 40 games vs v0.5.11; this is the head-to-head against v0.5.12 it skipped, at +50, both factions, rc/cm/cc/fm. 15 games ran 11-15, the last 5 (Full Metal Plate) after his game 11-16.
- **Result:** 20 games: won 1, lost 3, timeouts ahead 7, behind 9; income at 20 min x0.90 ours/theirs
- **Verdict:** Not better than v0.5.12. Contract FAIL (2): won or ahead 0.45 vs 0.50, army share 0.38 vs 0.42; income at 20 x0.90. Better on near-done strips 9.4 vs 14.9, supers before 4 moho 2.9 vs 4.3, gunships sent to lose 0.00 vs 0.32 (row 110), stacked senses 0.20 vs 0.28, army stuck 45 vs 58 per 10 min. Worse on bare-hands 1.3 vs 0.5 and frozen 0.8 vs 0.4 minutes. Unstable (rc7) is tested against v0.5.13 next.
- **Ours:** Apex-v0.5.13-standard
- **Opponents:** Apex-v0.5.12-standard
- **Code:** Apex-v0.5.12-standard = `c494a6f08c+9be850ac4a90` (20 games); Apex-v0.5.13-standard = `b836bd8247+2f2ca832cead` (20 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Full Metal Plate 1.7, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apex:v0.5.13:standard --b Apex:v0.5.12:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9503 --out matches/h13-v0-cc2-A9503`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9503 | 0 | W | 27.54 | x4.08 | b836bd8247+2f2ca832cead, c494a6f08c+9be850ac4a90 | `matches/h13-v0-cc2-A9503` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9506 | 0 | l | 30.0 | x0.66 | b836bd8247+2f2ca832cead, c494a6f08c+9be850ac4a90 | `matches/h13-v0-cc2-A9506` |
| 2 | Comet Catcher Remake 1.8 | Cortex | 9503 | 0 | w | 30.0 | x1.07 | b836bd8247+2f2ca832cead, c494a6f08c+9be850ac4a90 | `matches/h13-v0-cc2-C9503` |
| 3 | Comet Catcher Remake 1.8 | Cortex | 9506 | 0 | l | 30.0 | x0.54 | b836bd8247+2f2ca832cead, c494a6f08c+9be850ac4a90 | `matches/h13-v0-cc2-C9506` |
| 4 | Carrot Mountains v2.0 | Armada | 9502 | 0 | w | 30.0 | x1.73 | b836bd8247+2f2ca832cead, c494a6f08c+9be850ac4a90 | `matches/h13-v0-cm2-A9502` |
| 5 | Carrot Mountains v2.0 | Armada | 9505 | 0 | l | 30.0 | x1.07 | b836bd8247+2f2ca832cead, c494a6f08c+9be850ac4a90 | `matches/h13-v0-cm2-A9505` |
| 6 | Carrot Mountains v2.0 | Cortex | 9502 | 0 | l | 30.0 | x0.83 | b836bd8247+2f2ca832cead, c494a6f08c+9be850ac4a90 | `matches/h13-v0-cm2-C9502` |
| 7 | Carrot Mountains v2.0 | Cortex | 9505 | 0 | L | 27.9 | x0.28 | b836bd8247+2f2ca832cead, c494a6f08c+9be850ac4a90 | `matches/h13-v0-cm2-C9505` |
| 8 | Full Metal Plate 1.7 | Armada | 9511 | 0 | L | 29.02 | x0.65 | b836bd8247+2f2ca832cead, c494a6f08c+9be850ac4a90 | `matches/h13-v0-fm1-A9511` |
| 9 | Full Metal Plate 1.7 | Armada | 9512 | 0 | w | 30.0 | x1.53 | b836bd8247+2f2ca832cead, c494a6f08c+9be850ac4a90 | `matches/h13-v0-fm1-A9512` |
| 10 | Full Metal Plate 1.7 | Cortex | 9511 | 0 | L | 26.89 | x0.81 | b836bd8247+2f2ca832cead, c494a6f08c+9be850ac4a90 | `matches/h13-v0-fm1-C9511` |
| 11 | Full Metal Plate 1.7 | Cortex | 9512 | 0 | w | 30.0 | x0.89 | b836bd8247+2f2ca832cead, c494a6f08c+9be850ac4a90 | `matches/h13-v0-fm1-C9512` |
| 12 | Full Metal Plate 1.7 | Armada | 9511 | 0 | w | 30.0 | x2.15 | b836bd8247+2f2ca832cead, c494a6f08c+9be850ac4a90 | `matches/h13-v0-fm2-A9511` |
| 13 | Full Metal Plate 1.7 | Armada | 9512 | 0 | l | 30.0 | x0.70 | b836bd8247+2f2ca832cead, c494a6f08c+9be850ac4a90 | `matches/h13-v0-fm2-A9512` |
| 14 | Full Metal Plate 1.7 | Cortex | 9511 | 0 | l | 30.0 | x0.63 | b836bd8247+2f2ca832cead, c494a6f08c+9be850ac4a90 | `matches/h13-v0-fm2-C9511` |
| 15 | Full Metal Plate 1.7 | Cortex | 9512 | 0 | l | 30.0 | x0.50 | b836bd8247+2f2ca832cead, c494a6f08c+9be850ac4a90 | `matches/h13-v0-fm2-C9512` |
| 16 | Red Comet Remake 1.8 | Armada | 9501 | 0 | l | 30.0 | x0.80 | b836bd8247+2f2ca832cead, c494a6f08c+9be850ac4a90 | `matches/h13-v0-rc2-A9501` |
| 17 | Red Comet Remake 1.8 | Armada | 9504 | 0 | w | 30.0 | x1.21 | b836bd8247+2f2ca832cead, c494a6f08c+9be850ac4a90 | `matches/h13-v0-rc2-A9504` |
| 18 | Red Comet Remake 1.8 | Cortex | 9501 | 0 | l | 30.0 | x0.81 | b836bd8247+2f2ca832cead, c494a6f08c+9be850ac4a90 | `matches/h13-v0-rc2-C9501` |
| 19 | Red Comet Remake 1.8 | Cortex | 9504 | 0 | w | 30.0 | x0.70 | b836bd8247+2f2ca832cead, c494a6f08c+9be850ac4a90 | `matches/h13-v0-rc2-C9504` |

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomalies: 0 seat(s) of 0 outside 5 robust deviations of v0.5.12's normal; 36 seat(s) skipped, no normal yet for hc50-x1-A-1v1@Full Metal Plate, hc50-x1-A-2v2@Carrot Mountains, hc50-x1-A-2v2@Comet Catcher Remake, hc50-x1-A-2v2@Full Metal Plate, hc50-x1-A-2v2@Red Comet Remake, hc50-x1-C-1v1@Full Metal Plate, hc50-x1-C-2v2@Carrot Mountains, hc50-x1-C-2v2@Comet Catcher Remake, hc50-x1-C-2v2@Full Metal Plate, hc50-x1-C-2v2@Red Comet Remake
```
