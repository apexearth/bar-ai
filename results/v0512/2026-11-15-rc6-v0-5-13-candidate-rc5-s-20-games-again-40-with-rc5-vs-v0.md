<!-- meta {"date": "2026-11-15", "topic": "v0512", "title": "rc6: v0.5.13 candidate, rc5's 20 games again (40 with rc5) vs v0.5.11", "games": 20, "W": 1, "L": 1, "w": 12, "l": 6, "inc20": 1.05, "verdict": "rc5+rc6 (40 games): contract PASS after two instrument corrections made on this data -- lone t2 con minutes counts only minutes with an advanced plant standing (rc3 1.06 -> rc5 0.44, release 0.28), peak constructors became log peak cons per income (his 11-15 'release it': 121 vs 106 cons on 17% more income, same army share; per income -1.65 vs -1.58). Won or ahead 0.72, gunships sent to lose 0.00 vs 0.29, base lost while covered 3.47k vs 7.25k, 4th moho 6.37 vs 6.79 min. NOT RECORDED: the bar must be v0.5.12 and these games played v0.5.11; he chose to skip the v0.5.12 head-to-head this once (v0.5.12 vs v0.5.11 was 0.60 on rc3's games) and v0.5.13 was deployed with --allow-red."} -->
# rc6: v0.5.13 candidate, rc5's 20 games again (40 with rc5) vs v0.5.11

- **Date:** 2026-11-15
- **Topic:** v0512
- **Purpose:** rc5 failed one check (supers before 4 moho) on two Full Metal Plate outliers; rerun the same 20 games to judge the candidate on 40.
- **Result:** 20 games: won 1, lost 1, timeouts ahead 12, behind 6; income at 20 min x1.05 ours/theirs
- **Verdict:** rc5+rc6 (40 games): contract PASS after two instrument corrections made on this data -- lone t2 con minutes counts only minutes with an advanced plant standing (rc3 1.06 -> rc5 0.44, release 0.28), peak constructors became log peak cons per income (his 11-15 'release it': 121 vs 106 cons on 17% more income, same army share; per income -1.65 vs -1.58). Won or ahead 0.72, gunships sent to lose 0.00 vs 0.29, base lost while covered 3.47k vs 7.25k, 4th moho 6.37 vs 6.79 min. NOT RECORDED: the bar must be v0.5.12 and these games played v0.5.11; he chose to skip the v0.5.12 head-to-head this once (v0.5.12 vs v0.5.11 was 0.60 on rc3's games) and v0.5.13 was deployed with --allow-red.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.11-standard
- **Code:** Apex-v0.5.11-standard = `v0.5.11` (20 games); Apexestall-lane-estall-standard = `b836bd8247+9942a5256dfa` (20 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Full Metal Plate 1.7, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.11:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9503 --out matches/rc6-v0-cc2-A9503`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9503 | 0 | l | 30.0 | x1.31 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc6-v0-cc2-A9503` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9506 | 0 | w | 30.0 | x1.84 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc6-v0-cc2-A9506` |
| 2 | Comet Catcher Remake 1.8 | Cortex | 9503 | 0 | w | 30.0 | x2.16 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc6-v0-cc2-C9503` |
| 3 | Comet Catcher Remake 1.8 | Cortex | 9506 | 0 | l | 30.0 | x0.54 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc6-v0-cc2-C9506` |
| 4 | Carrot Mountains v2.0 | Armada | 9502 | 0 | w | 30.0 | x1.47 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc6-v0-cm2-A9502` |
| 5 | Carrot Mountains v2.0 | Armada | 9505 | 0 | w | 30.0 | x2.49 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc6-v0-cm2-A9505` |
| 6 | Carrot Mountains v2.0 | Cortex | 9502 | 0 | w | 30.0 | x1.01 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc6-v0-cm2-C9502` |
| 7 | Carrot Mountains v2.0 | Cortex | 9505 | 0 | l | 30.0 | x0.77 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc6-v0-cm2-C9505` |
| 8 | Full Metal Plate 1.7 | Armada | 9511 | 0 | w | 30.0 | x1.09 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc6-v0-fm1-A9511` |
| 9 | Full Metal Plate 1.7 | Armada | 9512 | 0 | l | 30.0 | x0.89 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc6-v0-fm1-A9512` |
| 10 | Full Metal Plate 1.7 | Cortex | 9511 | 0 | w | 30.0 | x3.72 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc6-v0-fm1-C9511` |
| 11 | Full Metal Plate 1.7 | Cortex | 9512 | 0 | L | 20.93 | x0.02 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc6-v0-fm1-C9512` |
| 12 | Full Metal Plate 1.7 | Armada | 9511 | 0 | w | 30.0 | x0.89 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc6-v0-fm2-A9511` |
| 13 | Full Metal Plate 1.7 | Armada | 9512 | 0 | w | 30.0 | x1.91 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc6-v0-fm2-A9512` |
| 14 | Full Metal Plate 1.7 | Cortex | 9511 | 0 | w | 30.0 | x0.96 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc6-v0-fm2-C9511` |
| 15 | Full Metal Plate 1.7 | Cortex | 9512 | 0 | l | 30.0 | x0.44 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc6-v0-fm2-C9512` |
| 16 | Red Comet Remake 1.8 | Armada | 9501 | 0 | w | 30.0 | x1.57 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc6-v0-rc2-A9501` |
| 17 | Red Comet Remake 1.8 | Armada | 9504 | 0 | W | 21.89 | x3.64 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc6-v0-rc2-A9504` |
| 18 | Red Comet Remake 1.8 | Cortex | 9501 | 0 | l | 30.0 | x0.76 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc6-v0-rc2-C9501` |
| 19 | Red Comet Remake 1.8 | Cortex | 9504 | 0 | w | 30.0 | x1.41 | b836bd8247+9942a5256dfa, v0.5.11 | `matches/rc6-v0-rc2-C9504` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.37 | 2.48 | - | ok |
| t2->4th moho (min) | 6.32 | 7.13 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.38 | 0.59 | 0.00 | ok, short of aim |
| adv plant frame x | 2.04 | 2.49 | 1.50 | ok, short of aim |
| near-done strips | 11.83 | 146.11 | 0.00 | ok, short of aim |
| t2 cons given early | 0.11 | 0.36 | 0.00 | ok, short of aim |
| supers before 4 moho | 2.64 | 2.94 | 0.00 | ok, short of aim |
| lone t2 con minutes | 0.33 | 0.39 | 0.00 | ok, short of aim |
| base lost while 'covered' k | 2.62 | 7.16 | 0.00 | ok, short of aim |
| oldest plant order min | 3.54 | - | - | n/a |
| no t2 by minute 20 | 0.00 | 0.00 | - | ok |
| frozen minutes | 0.33 | 0.67 | 0.00 | ok, short of aim |
| bare-hands minutes | 0.39 | 0.89 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.44 | 0.41 | 0.00 | ok, short of aim |
| runs turned back | 0.03 | - | 0.00 | n/a |
| gunships sent to lose | 0.00 | 0.33 | 0.00 | ok |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.64 | -1.53 | - | ok |
| army share (neg) | 0.37 | 0.37 | - | ok |
| -log income at 20 | -5.29 | -5.16 | - | ok |
| games won or ahead | 0.80 | 0.50 | - | ok |

Contract: **PASS** over 20 games (36 of our seats, 36 release seats); 11 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomalies: 0 seat(s) of 24 outside 5 robust deviations of v0.5.11's normal; 12 seat(s) skipped, no normal yet for hc50-x1-A-1v1@Full Metal Plate, hc50-x1-A-2v2@Full Metal Plate, hc50-x1-C-1v1@Full Metal Plate, hc50-x1-C-2v2@Full Metal Plate
```
