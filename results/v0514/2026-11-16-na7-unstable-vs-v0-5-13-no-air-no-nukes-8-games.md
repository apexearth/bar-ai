<!-- meta {"date": "2026-11-16", "topic": "v0514", "title": "na7: Unstable vs v0.5.13, no air, no nukes (8 games)", "games": 8, "W": 1, "L": 0, "w": 2, "l": 5, "inc20": 1.95, "verdict": "Even: won 1, lost 0, at time ahead 2 behind 5; won or ahead 0.50 vs 0.50; income at 20 x1.95. Contract FAIL (2): adv plant frame x 3.5 vs 2.3, army stuck 45 vs 35 per 10 min. Stacked radar/jammers 0.13 vs 0.79 (row 112 fix shows here). 8 games: direction only."} -->
# na7: Unstable vs v0.5.13, no air, no nukes (8 games)

- **Date:** 2026-11-16
- **Topic:** v0514
- **Purpose:** No-air, no-nuke games (his 11-15 13,000-metal / constructor blob game was no-air): constructors per income, stacked senses, army stuck. +50, both factions.
- **Result:** 8 games: won 1, lost 0, timeouts ahead 2, behind 5; income at 20 min x1.95 ours/theirs
- **Verdict:** Even: won 1, lost 0, at time ahead 2 behind 5; won or ahead 0.50 vs 0.50; income at 20 x1.95. Contract FAIL (2): adv plant frame x 3.5 vs 2.3, army stuck 45 vs 35 per 10 min. Stacked radar/jammers 0.13 vs 0.79 (row 112 fix shows here). 8 games: direction only.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.13-standard
- **Code:** Apex-v0.5.13-standard = `b836bd8247+2f2ca832cead` (8 games); Apexestall-lane-estall-standard = `363c70a0a5+5a24d1c035be` (8 games)
- **Maps:** Carrot Mountains v2.0, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 40 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.13:standard --per-side 2 --map Carrot Mountains v2.0 --minutes 40 --speed 20 --handicap 50 --sides Armada,Armada --seed 9602 --modoption unit_restrictions_noair=1 --modoption unit_restrictions_nonukes=1 --out matches/na7-v0-cm2-A9602`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Carrot Mountains v2.0 | Armada | 9602 | 0 | l | 40.0 | x1.10 | 363c70a0a5+5a24d1c035be, b836bd8247+2f2ca832cead | `matches/na7-v0-cm2-A9602` |
| 1 | Carrot Mountains v2.0 | Armada | 9604 | 0 | w | 40.0 | x2.56 | 363c70a0a5+5a24d1c035be, b836bd8247+2f2ca832cead | `matches/na7-v0-cm2-A9604` |
| 2 | Carrot Mountains v2.0 | Cortex | 9602 | 0 | l | 40.0 | x0.78 | 363c70a0a5+5a24d1c035be, b836bd8247+2f2ca832cead | `matches/na7-v0-cm2-C9602` |
| 3 | Carrot Mountains v2.0 | Cortex | 9604 | 0 | l | 40.0 | x0.79 | 363c70a0a5+5a24d1c035be, b836bd8247+2f2ca832cead | `matches/na7-v0-cm2-C9604` |
| 4 | Red Comet Remake 1.8 | Armada | 9601 | 0 | l | 40.0 | x0.78 | 363c70a0a5+5a24d1c035be, b836bd8247+2f2ca832cead | `matches/na7-v0-rc2-A9601` |
| 5 | Red Comet Remake 1.8 | Armada | 9603 | 0 | W | 20.23 | x164.05 | 363c70a0a5+5a24d1c035be, b836bd8247+2f2ca832cead | `matches/na7-v0-rc2-A9603` |
| 6 | Red Comet Remake 1.8 | Cortex | 9601 | 0 | l | 40.0 | x0.99 | 363c70a0a5+5a24d1c035be, b836bd8247+2f2ca832cead | `matches/na7-v0-rc2-C9601` |
| 7 | Red Comet Remake 1.8 | Cortex | 9603 | 0 | w | 40.0 | x0.97 | 363c70a0a5+5a24d1c035be, b836bd8247+2f2ca832cead | `matches/na7-v0-rc2-C9603` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.32 | 3.29 | - | ok |
| t2->4th moho (min) | 5.64 | 6.01 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.71 | 0.67 | 0.00 | ok, short of aim |
| adv plant frame x | 3.48 | 2.25 | 1.50 | FAIL (worse than release) |
| near-done strips | 10.88 | 9.19 | 0.00 | ok, short of aim |
| t2 cons given early | 0.00 | 0.00 | 0.00 | ok |
| supers before 4 moho | 0.88 | 0.57 | 0.00 | ok, short of aim |
| lone t2 con minutes | 0.50 | 0.43 | 0.00 | ok, short of aim |
| base lost while 'covered' k | 3.03 | 5.22 | 0.00 | ok, short of aim |
| oldest plant order min | 3.61 | 3.51 | - | ok |
| no t2 by minute 20 | 0.00 | 0.12 | - | ok |
| frozen minutes | 0.38 | 0.62 | 0.00 | ok, short of aim |
| bare-hands minutes | 0.62 | 0.38 | 0.00 | ok, short of aim |
| wiped bomber runs | - | - | 0.00 | n/a |
| runs turned back | - | - | 0.00 | n/a |
| gunships sent to lose | - | - | 0.00 | n/a |
| stacked radar/jammers | 0.13 | 0.79 | 0.00 | ok, short of aim |
| army stuck per 10 min | 45.42 | 34.84 | 0.00 | FAIL (worse than release) |
| ground given up share | 0.22 | - | 0.00 | n/a |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.64 | -1.70 | - | ok |
| army share (neg) | 0.48 | 0.46 | - | ok |
| -log income at 20 | -5.32 | -5.11 | - | ok |
| games won or ahead | 0.50 | 0.50 | - | ok |

Contract: **FAIL (2)** over 8 games (16 of our seats, 16 release seats); 11 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.13 (run `python tools/anomaly.py build`)
```
