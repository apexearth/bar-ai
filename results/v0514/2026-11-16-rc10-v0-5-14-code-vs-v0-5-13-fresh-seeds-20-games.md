<!-- meta {"date": "2026-11-16", "topic": "v0514", "title": "rc10: v0.5.14 code vs v0.5.13, fresh seeds (20 games)", "games": 20, "W": 1, "L": 2, "w": 12, "l": 5, "inc20": 1.32, "verdict": "The covered gap did not hold: 4.41k vs 4.40k (rc9 7.67 vs 4.95). Won or ahead 0.75 vs 0.50. Contract FAIL (1): near-done strips 17.1 vs 10.7, a raw count that grows with building: we built 290k vs 223k metal a seat; per 10k built 0.59 vs 0.48 here, 0.47 vs 0.52 in rc9, 0.42 vs 0.50 in rc8 (no trend over 60 games). Pooled rc9+rc10 (72 seats): near-done 14.7 vs 11.5, covered 6.0 vs 4.7. Frozen minutes 0.33 vs 1.11, bare-hands 0.22 vs 1.33, army stuck 1.96 vs 2.57."} -->
# rc10: v0.5.14 code vs v0.5.13, fresh seeds (20 games)

- **Date:** 2026-11-16
- **Topic:** v0514
- **Purpose:** Same code as the shipped v0.5.14 (lane estall), 20 more games on fresh seeds 97xx, to see whether rc9's base-lost-while-covered gap is real.
- **Result:** 20 games: won 1, lost 2, timeouts ahead 12, behind 5; income at 20 min x1.32 ours/theirs
- **Verdict:** The covered gap did not hold: 4.41k vs 4.40k (rc9 7.67 vs 4.95). Won or ahead 0.75 vs 0.50. Contract FAIL (1): near-done strips 17.1 vs 10.7, a raw count that grows with building: we built 290k vs 223k metal a seat; per 10k built 0.59 vs 0.48 here, 0.47 vs 0.52 in rc9, 0.42 vs 0.50 in rc8 (no trend over 60 games). Pooled rc9+rc10 (72 seats): near-done 14.7 vs 11.5, covered 6.0 vs 4.7. Frozen minutes 0.33 vs 1.11, bare-hands 0.22 vs 1.33, army stuck 1.96 vs 2.57.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.13-standard
- **Code:** Apex-v0.5.13-standard = `b836bd8247+2f2ca832cead` (20 games); Apexestall-lane-estall-standard = `363c70a0a5+c487dbeb848d` (20 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Full Metal Plate 1.7, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.13:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9703 --out matches/rc10-v0-cc2-A9703`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9703 | 0 | w | 30.0 | x1.46 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc10-v0-cc2-A9703` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9706 | 0 | w | 30.0 | x1.49 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc10-v0-cc2-A9706` |
| 2 | Comet Catcher Remake 1.8 | Cortex | 9703 | 0 | w | 30.0 | x0.87 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc10-v0-cc2-C9703` |
| 3 | Comet Catcher Remake 1.8 | Cortex | 9706 | 0 | w | 30.0 | x1.37 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc10-v0-cc2-C9706` |
| 4 | Carrot Mountains v2.0 | Armada | 9702 | 0 | w | 30.0 | x1.10 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc10-v0-cm2-A9702` |
| 5 | Carrot Mountains v2.0 | Armada | 9705 | 0 | w | 30.0 | x1.55 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc10-v0-cm2-A9705` |
| 6 | Carrot Mountains v2.0 | Cortex | 9702 | 0 | w | 30.0 | x2.58 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc10-v0-cm2-C9702` |
| 7 | Carrot Mountains v2.0 | Cortex | 9705 | 0 | l | 30.0 | x0.74 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc10-v0-cm2-C9705` |
| 8 | Full Metal Plate 1.7 | Armada | 9711 | 0 | w | 30.0 | x1.78 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc10-v0-fm1-A9711` |
| 9 | Full Metal Plate 1.7 | Armada | 9712 | 0 | l | 30.0 | x0.69 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc10-v0-fm1-A9712` |
| 10 | Full Metal Plate 1.7 | Cortex | 9711 | 0 | l | 30.0 | x0.95 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc10-v0-fm1-C9711` |
| 11 | Full Metal Plate 1.7 | Cortex | 9712 | 0 | l | 30.0 | x1.11 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc10-v0-fm1-C9712` |
| 12 | Full Metal Plate 1.7 | Armada | 9711 | 0 | w | 30.0 | x0.72 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc10-v0-fm2-A9711` |
| 13 | Full Metal Plate 1.7 | Armada | 9712 | 0 | l | 30.0 | x0.94 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc10-v0-fm2-A9712` |
| 14 | Full Metal Plate 1.7 | Cortex | 9711 | 0 | w | 30.0 | x1.96 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc10-v0-fm2-C9711` |
| 15 | Full Metal Plate 1.7 | Cortex | 9712 | 0 | w | 30.0 | x2.04 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc10-v0-fm2-C9712` |
| 16 | Red Comet Remake 1.8 | Armada | 9701 | 0 | W | 21.67 | x19.32 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc10-v0-rc2-A9701` |
| 17 | Red Comet Remake 1.8 | Armada | 9704 | 0 | w | 30.0 | x1.78 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc10-v0-rc2-A9704` |
| 18 | Red Comet Remake 1.8 | Cortex | 9701 | 0 | L | 28.84 | x0.49 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc10-v0-rc2-C9701` |
| 19 | Red Comet Remake 1.8 | Cortex | 9704 | 0 | L | 29.76 | x0.55 | 363c70a0a5+c487dbeb848d, b836bd8247+2f2ca832cead | `matches/rc10-v0-rc2-C9704` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.87 | 2.55 | - | ok |
| t2->4th moho (min) | 5.73 | 6.13 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.43 | 0.47 | 0.00 | ok, short of aim |
| adv plant frame x | 2.05 | 1.66 | 1.50 | ok, short of aim |
| near-done strips | 17.14 | 10.72 | 0.00 | FAIL (worse than release) |
| t2 cons given early | 0.14 | 0.11 | 0.00 | ok, short of aim |
| supers before 4 moho | 3.17 | 4.29 | 0.00 | ok, short of aim |
| lone t2 con minutes | 0.50 | 0.53 | 0.00 | ok, short of aim |
| base lost while 'covered' k | 4.41 | 4.40 | 0.00 | ok, short of aim |
| oldest plant order min | 3.82 | 3.54 | - | ok |
| no t2 by minute 20 | 0.00 | 0.06 | - | ok |
| frozen minutes | 0.33 | 1.11 | 0.00 | ok, short of aim |
| bare-hands minutes | 0.22 | 1.33 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.38 | 0.49 | 0.00 | ok, short of aim |
| runs turned back | 0.12 | 0.07 | 0.00 | ok, short of aim |
| gunships sent to lose | 0.00 | 0.00 | 0.00 | ok |
| stacked radar/jammers | 0.22 | 0.29 | 0.00 | ok, short of aim |
| army stuck /10min/1k army | 1.96 | 2.57 | 0.00 | ok, short of aim |
| ground given up share | 0.32 | - | 0.00 | n/a |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.70 | -1.73 | - | ok |
| army share (neg) | 0.40 | 0.40 | - | ok |
| -log income at 20 | -5.38 | -5.00 | - | ok |
| games won or ahead | 0.75 | 0.50 | - | ok |

Contract: **FAIL (1)** over 20 games (36 of our seats, 36 release seats); 14 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomalies: 1 seat(s) of 24 outside 5 robust deviations of v0.5.13's normal; 12 seat(s) skipped, no normal yet for hc50-x1-A-1v1@Full Metal Plate, hc50-x1-A-2v2@Full Metal Plate, hc50-x1-C-1v1@Full Metal Plate, hc50-x1-C-2v2@Comet Catcher Remake
  rc10-v0-rc2-C9701 t1 lane-estall: 25m constructors 1 (normal 34, z -6)
```
