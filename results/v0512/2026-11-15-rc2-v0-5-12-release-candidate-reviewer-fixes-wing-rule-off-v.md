<!-- meta {"date": "2026-11-15", "topic": "v0512", "title": "rc2: v0.5.12 release candidate (reviewer fixes, wing rule off) vs v0.5.11", "games": 20, "W": 2, "L": 1, "w": 4, "l": 13, "inc20": 0.76, "verdict": "Contract FAIL on t2->4th moho: ours 7.57 min vs the release's 6.47 (margin 1.0); Carrot Mountains 7.78 vs 5.27. Cause: decide.as super push sent home-crew T2 cons to anti-nukes / long-range guns over upgrades priced 20x higher (rc2-v0-cm2-C9502 t0: corfmd v=2.4 over mexup v=52.8); its yield to upgrades lived under apex_t2_eco (off) and field hands only. Fixed 11-15 (validation row 106), re-run as rc3. Won or ahead 0.55."} -->
# rc2: v0.5.12 release candidate (reviewer fixes, wing rule off) vs v0.5.11

- **Date:** 2026-11-15
- **Topic:** v0512
- **Purpose:** Release gate for v0.5.12: 12 2v2 on Red Comet / Carrot Mountains / Comet Catcher plus 8 Full Metal Plate 1v1 and 2v2, both factions, +50.
- **Result:** 20 games: won 2, lost 1, timeouts ahead 4, behind 13; income at 20 min x0.76 ours/theirs
- **Verdict:** Contract FAIL on t2->4th moho: ours 7.57 min vs the release's 6.47 (margin 1.0); Carrot Mountains 7.78 vs 5.27. Cause: decide.as super push sent home-crew T2 cons to anti-nukes / long-range guns over upgrades priced 20x higher (rc2-v0-cm2-C9502 t0: corfmd v=2.4 over mexup v=52.8); its yield to upgrades lived under apex_t2_eco (off) and field hands only. Fixed 11-15 (validation row 106), re-run as rc3. Won or ahead 0.55.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.11-standard
- **Code:** Apex-v0.5.11-standard = `v0.5.11` (20 games); Apexestall-lane-estall-standard = `c494a6f08c+3c079aadf5ae` (20 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Full Metal Plate 1.7, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.11:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9503 --out matches/rc2-v0-cc2-A9503`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9503 | 0 | W | 27.48 | x2.92 | c494a6f08c+3c079aadf5ae, v0.5.11 | `matches/rc2-v0-cc2-A9503` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9506 | 0 | L | 10.62 | - | c494a6f08c+3c079aadf5ae, v0.5.11 | `matches/rc2-v0-cc2-A9506` |
| 2 | Comet Catcher Remake 1.8 | Cortex | 9503 | 0 | l | 30.0 | x0.86 | c494a6f08c+3c079aadf5ae, v0.5.11 | `matches/rc2-v0-cc2-C9503` |
| 3 | Comet Catcher Remake 1.8 | Cortex | 9506 | 0 | l | 30.0 | x0.42 | c494a6f08c+3c079aadf5ae, v0.5.11 | `matches/rc2-v0-cc2-C9506` |
| 4 | Carrot Mountains v2.0 | Armada | 9502 | 0 | w | 30.0 | x0.82 | c494a6f08c+3c079aadf5ae, v0.5.11 | `matches/rc2-v0-cm2-A9502` |
| 5 | Carrot Mountains v2.0 | Armada | 9505 | 0 | l | 30.0 | x0.55 | c494a6f08c+3c079aadf5ae, v0.5.11 | `matches/rc2-v0-cm2-A9505` |
| 6 | Carrot Mountains v2.0 | Cortex | 9502 | 0 | l | 30.0 | x0.85 | c494a6f08c+3c079aadf5ae, v0.5.11 | `matches/rc2-v0-cm2-C9502` |
| 7 | Carrot Mountains v2.0 | Cortex | 9505 | 0 | l | 30.0 | x0.99 | c494a6f08c+3c079aadf5ae, v0.5.11 | `matches/rc2-v0-cm2-C9505` |
| 8 | Full Metal Plate 1.7 | Armada | 9511 | 0 | l | 30.0 | x0.47 | c494a6f08c+3c079aadf5ae, v0.5.11 | `matches/rc2-v0-fm1-A9511` |
| 9 | Full Metal Plate 1.7 | Armada | 9512 | 0 | w | 30.0 | x1.18 | c494a6f08c+3c079aadf5ae, v0.5.11 | `matches/rc2-v0-fm1-A9512` |
| 10 | Full Metal Plate 1.7 | Cortex | 9511 | 0 | l | 30.0 | x0.74 | c494a6f08c+3c079aadf5ae, v0.5.11 | `matches/rc2-v0-fm1-C9511` |
| 11 | Full Metal Plate 1.7 | Cortex | 9512 | 0 | w | 30.0 | x0.95 | c494a6f08c+3c079aadf5ae, v0.5.11 | `matches/rc2-v0-fm1-C9512` |
| 12 | Full Metal Plate 1.7 | Armada | 9511 | 0 | w | 30.0 | x1.20 | c494a6f08c+3c079aadf5ae, v0.5.11 | `matches/rc2-v0-fm2-A9511` |
| 13 | Full Metal Plate 1.7 | Armada | 9512 | 0 | l | 30.0 | x0.64 | c494a6f08c+3c079aadf5ae, v0.5.11 | `matches/rc2-v0-fm2-A9512` |
| 14 | Full Metal Plate 1.7 | Cortex | 9511 | 0 | l | 30.0 | x0.61 | c494a6f08c+3c079aadf5ae, v0.5.11 | `matches/rc2-v0-fm2-C9511` |
| 15 | Full Metal Plate 1.7 | Cortex | 9512 | 0 | l | 30.0 | x0.19 | c494a6f08c+3c079aadf5ae, v0.5.11 | `matches/rc2-v0-fm2-C9512` |
| 16 | Red Comet Remake 1.8 | Armada | 9501 | 0 | l | 30.0 | x0.64 | c494a6f08c+3c079aadf5ae, v0.5.11 | `matches/rc2-v0-rc2-A9501` |
| 17 | Red Comet Remake 1.8 | Armada | 9504 | 0 | W | 21.06 | x1.09 | c494a6f08c+3c079aadf5ae, v0.5.11 | `matches/rc2-v0-rc2-A9504` |
| 18 | Red Comet Remake 1.8 | Cortex | 9501 | 0 | l | 30.0 | x0.72 | c494a6f08c+3c079aadf5ae, v0.5.11 | `matches/rc2-v0-rc2-C9501` |
| 19 | Red Comet Remake 1.8 | Cortex | 9504 | 0 | l | 30.0 | x0.81 | c494a6f08c+3c079aadf5ae, v0.5.11 | `matches/rc2-v0-rc2-C9504` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 3.05 | 3.35 | - | ok |
| t2->4th moho (min) | 7.57 | 6.47 | 3.00 | FAIL (worse than release) |
| lab-job leaves/job | 0.51 | 0.53 | 0.00 | ok, short of aim |
| adv plant frame x | 2.21 | 2.02 | 1.50 | ok, short of aim |
| near-done strips | 8.06 | 173.75 | 0.00 | ok, short of aim |
| t2 cons given early | 0.14 | 0.28 | 0.00 | ok, short of aim |
| supers before 4 moho | 4.97 | 5.71 | 0.00 | ok, short of aim |
| lone t2 con minutes | 1.65 | 0.94 | 0.00 | ok, short of aim |
| no t2 by minute 20 | 0.00 | 0.00 | - | ok |
| frozen minutes | 0.28 | 0.17 | 0.00 | ok, short of aim |
| bare-hands minutes | 0.33 | 0.22 | 0.00 | ok, short of aim |
| wiped bomber runs | 1.22 | 1.42 | 0.00 | ok, short of aim |
| runs turned back | 0.00 | - | 0.00 | n/a |
| anomalous seats | 0.14 | 0.11 | 0.00 | ok, short of aim |
| peak constructors | 79.50 | 112.50 | - | ok |
| army share (neg) | 0.39 | 0.38 | - | ok |
| games won or ahead | 0.55 | 0.50 | - | ok |

Contract: **FAIL (1)** over 20 games (36 of our seats, 36 release seats); 11 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomalies: 0 seat(s) of 0 outside 5 robust deviations of v0.5.11's normal
```
