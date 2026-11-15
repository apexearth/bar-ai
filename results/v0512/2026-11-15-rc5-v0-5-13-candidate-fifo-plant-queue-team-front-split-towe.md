<!-- meta {"date": "2026-11-15", "topic": "v0512", "title": "rc5: v0.5.13 candidate (FIFO plant queue, team-front split, tower arrivals, gunship price guard) vs v0.5.11", "games": 20, "W": 2, "L": 0, "w": 9, "l": 9, "inc20": 1.37, "verdict": "Contract FAIL on one check: supers before 4 moho 4.08 vs 2.97 (margin 0.5), driven by two Full Metal Plate seat-0 outliers (35, 26; release 21, 12 on the same seeds) -- rc5-fm2-A9511 t0 lost its T2 labs at minute 13-14 and its moho tasks dropped with no workers, so it never reached a 4th moho and every later strategic build counted. The release's own mean moved 3.69 -> 2.97 between rc3 and rc5 on identical seeds. Everything else ok: gunships sent to lose 0.00 vs 0.26, base lost while covered 4.32k vs 7.34k, won or ahead 0.65. Lone t2 con minutes 1.44 vs 1.39 (the FIFO fix did not move it); oldest plant order 3.42 min mean. Rerun as rc6 (same 20 games) to judge on 40."} -->
# rc5: v0.5.13 candidate (FIFO plant queue, team-front split, tower arrivals, gunship price guard) vs v0.5.11

- **Date:** 2026-11-15
- **Topic:** v0512
- **Purpose:** Gate the fixes made after v0.5.12 on rc3's 20 games: plant orders append FIFO (row 107), team-front bonus split (108), measured-defence arrivals count new enemy metal (109), gunships refuse a GO their own price loses (110).
- **Result:** 20 games: won 2, lost 0, timeouts ahead 9, behind 9; income at 20 min x1.37 ours/theirs
- **Verdict:** Contract FAIL on one check: supers before 4 moho 4.08 vs 2.97 (margin 0.5), driven by two Full Metal Plate seat-0 outliers (35, 26; release 21, 12 on the same seeds) -- rc5-fm2-A9511 t0 lost its T2 labs at minute 13-14 and its moho tasks dropped with no workers, so it never reached a 4th moho and every later strategic build counted. The release's own mean moved 3.69 -> 2.97 between rc3 and rc5 on identical seeds. Everything else ok: gunships sent to lose 0.00 vs 0.26, base lost while covered 4.32k vs 7.34k, won or ahead 0.65. Lone t2 con minutes 1.44 vs 1.39 (the FIFO fix did not move it); oldest plant order 3.42 min mean. Rerun as rc6 (same 20 games) to judge on 40.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.11-standard
- **Code:** Apex-v0.5.11-standard = `v0.5.11` (20 games); Apexestall-lane-estall-standard = `b836bd8247+9942a5256dfa` (20 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Full Metal Plate 1.7, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.11:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9503 --out matches/rc5-v0-cc2-A9503`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9503 | 0 | w | 30.0 | x2.55 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc5-v0-cc2-A9503` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9506 | 0 | w | 30.0 | x2.55 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc5-v0-cc2-A9506` |
| 2 | Comet Catcher Remake 1.8 | Cortex | 9503 | 0 | w | 30.0 | x1.07 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc5-v0-cc2-C9503` |
| 3 | Comet Catcher Remake 1.8 | Cortex | 9506 | 0 | l | 30.0 | x1.04 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc5-v0-cc2-C9506` |
| 4 | Carrot Mountains v2.0 | Armada | 9502 | 0 | l | 30.0 | x0.76 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc5-v0-cm2-A9502` |
| 5 | Carrot Mountains v2.0 | Armada | 9505 | 0 | l | 30.0 | x0.94 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc5-v0-cm2-A9505` |
| 6 | Carrot Mountains v2.0 | Cortex | 9502 | 0 | w | 30.0 | x1.35 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc5-v0-cm2-C9502` |
| 7 | Carrot Mountains v2.0 | Cortex | 9505 | 0 | w | 30.0 | x1.09 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc5-v0-cm2-C9505` |
| 8 | Full Metal Plate 1.7 | Armada | 9511 | 0 | w | 30.0 | x1.15 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc5-v0-fm1-A9511` |
| 9 | Full Metal Plate 1.7 | Armada | 9512 | 0 | w | 30.0 | x1.65 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc5-v0-fm1-A9512` |
| 10 | Full Metal Plate 1.7 | Cortex | 9511 | 0 | l | 30.0 | x1.17 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc5-v0-fm1-C9511` |
| 11 | Full Metal Plate 1.7 | Cortex | 9512 | 0 | W | 27.83 | x15.19 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc5-v0-fm1-C9512` |
| 12 | Full Metal Plate 1.7 | Armada | 9511 | 0 | l | 30.0 | x0.65 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc5-v0-fm2-A9511` |
| 13 | Full Metal Plate 1.7 | Armada | 9512 | 0 | l | 30.0 | x0.57 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc5-v0-fm2-A9512` |
| 14 | Full Metal Plate 1.7 | Cortex | 9511 | 0 | w | 30.0 | x1.84 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc5-v0-fm2-C9511` |
| 15 | Full Metal Plate 1.7 | Cortex | 9512 | 0 | w | 30.0 | x0.92 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc5-v0-fm2-C9512` |
| 16 | Red Comet Remake 1.8 | Armada | 9501 | 0 | W | 24.44 | x3.09 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc5-v0-rc2-A9501` |
| 17 | Red Comet Remake 1.8 | Armada | 9504 | 0 | l | 30.0 | x1.09 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc5-v0-rc2-A9504` |
| 18 | Red Comet Remake 1.8 | Cortex | 9501 | 0 | l | 30.0 | x0.60 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc5-v0-rc2-C9501` |
| 19 | Red Comet Remake 1.8 | Cortex | 9504 | 0 | l | 30.0 | x1.59 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc5-v0-rc2-C9504` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.68 | 2.90 | - | ok |
| t2->4th moho (min) | 6.47 | 6.54 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.45 | 0.51 | 0.00 | ok, short of aim |
| adv plant frame x | 2.19 | 2.16 | 1.50 | ok, short of aim |
| near-done strips | 12.17 | 155.36 | 0.00 | ok, short of aim |
| t2 cons given early | 0.17 | 0.33 | 0.00 | ok, short of aim |
| supers before 4 moho | 4.08 | 2.97 | 0.00 | FAIL (worse than release) |
| lone t2 con minutes | 1.44 | 1.39 | 0.00 | ok, short of aim |
| base lost while 'covered' k | 4.32 | 7.34 | 0.00 | ok, short of aim |
| oldest plant order min | 3.42 | - | - | n/a |
| no t2 by minute 20 | 0.00 | 0.00 | - | ok |
| frozen minutes | 0.61 | 0.44 | 0.00 | ok, short of aim |
| bare-hands minutes | 0.56 | 0.61 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.43 | 0.44 | 0.00 | ok, short of aim |
| runs turned back | 0.03 | - | 0.00 | n/a |
| gunships sent to lose | 0.00 | 0.26 | 0.00 | ok |
| anomalous seats | - | - | 0.00 | n/a |
| peak constructors | 115.61 | 105.67 | - | ok |
| army share (neg) | 0.37 | 0.37 | - | ok |
| -log income at 20 | -5.25 | -4.96 | - | ok |
| games won or ahead | 0.65 | 0.50 | - | ok |

Contract: **FAIL (1)** over 20 games (36 of our seats, 36 release seats); 11 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomalies: 0 seat(s) of 24 outside 5 robust deviations of v0.5.11's normal; 12 seat(s) skipped, no normal yet for hc50-x1-A-1v1@Full Metal Plate, hc50-x1-A-2v2@Full Metal Plate, hc50-x1-C-1v1@Full Metal Plate, hc50-x1-C-2v2@Full Metal Plate
```
