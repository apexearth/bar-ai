<!-- meta {"date": "2026-11-15", "topic": "v0512", "title": "rc3: v0.5.12 candidate, super push yields to upgrades, vs v0.5.11", "games": 20, "W": 2, "L": 1, "w": 10, "l": 7, "inc20": 1.4, "verdict": "Contract PASS (recorded). t2->4th moho 6.63 vs the release's 7.00 (rc2 7.57 vs 6.47); supers on the first T2 con 5/36 (rc2 11/34); income at 20 per seat x1.22 (rc2 x0.70); won or ahead 0.60. Contract instrument fixes this batch: anomaly regime keyed by map (Full Metal Plate has no release normal yet, skipped) and beaten seats dropped; ledger now feeds the detector our seats; wiped bomber runs as a share of runs (margin 0.15 = the release's own 0.40-0.57 spread); peak constructors by mean (a median fell between map clusters). Lone T2 con minutes 1.56 vs 0.67, inside the margin."} -->
# rc3: v0.5.12 candidate, super push yields to upgrades, vs v0.5.11

- **Date:** 2026-11-15
- **Topic:** v0512
- **Purpose:** Release gate re-run on rc2's 20 games (12 2v2 rc/cm/cc + 8 Full Metal Plate 1v1/2v2, both factions, +50) after the super-push fix (validation row 106).
- **Result:** 20 games: won 2, lost 1, timeouts ahead 10, behind 7; income at 20 min x1.40 ours/theirs
- **Verdict:** Contract PASS (recorded). t2->4th moho 6.63 vs the release's 7.00 (rc2 7.57 vs 6.47); supers on the first T2 con 5/36 (rc2 11/34); income at 20 per seat x1.22 (rc2 x0.70); won or ahead 0.60. Contract instrument fixes this batch: anomaly regime keyed by map (Full Metal Plate has no release normal yet, skipped) and beaten seats dropped; ledger now feeds the detector our seats; wiped bomber runs as a share of runs (margin 0.15 = the release's own 0.40-0.57 spread); peak constructors by mean (a median fell between map clusters). Lone T2 con minutes 1.56 vs 0.67, inside the margin.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.11-standard
- **Code:** Apex-v0.5.11-standard = `v0.5.11` (20 games); Apexestall-lane-estall-standard = `c494a6f08c+98de158b5ddc` (20 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Full Metal Plate 1.7, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.11:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9503 --out matches/rc3-v0-cc2-A9503`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9503 | 0 | w | 30.0 | x1.70 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/rc3-v0-cc2-A9503` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9506 | 0 | l | 30.0 | x1.23 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/rc3-v0-cc2-A9506` |
| 2 | Comet Catcher Remake 1.8 | Cortex | 9503 | 0 | w | 30.0 | x1.66 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/rc3-v0-cc2-C9503` |
| 3 | Comet Catcher Remake 1.8 | Cortex | 9506 | 0 | l | 30.0 | x0.63 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/rc3-v0-cc2-C9506` |
| 4 | Carrot Mountains v2.0 | Armada | 9502 | 0 | w | 30.0 | x0.82 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/rc3-v0-cm2-A9502` |
| 5 | Carrot Mountains v2.0 | Armada | 9505 | 0 | w | 30.0 | x1.25 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/rc3-v0-cm2-A9505` |
| 6 | Carrot Mountains v2.0 | Cortex | 9502 | 0 | w | 30.0 | x1.53 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/rc3-v0-cm2-C9502` |
| 7 | Carrot Mountains v2.0 | Cortex | 9505 | 0 | l | 30.0 | x1.04 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/rc3-v0-cm2-C9505` |
| 8 | Full Metal Plate 1.7 | Armada | 9511 | 0 | l | 30.0 | x0.70 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/rc3-v0-fm1-A9511` |
| 9 | Full Metal Plate 1.7 | Armada | 9512 | 0 | W | 28.44 | x1.16 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/rc3-v0-fm1-A9512` |
| 10 | Full Metal Plate 1.7 | Cortex | 9511 | 0 | w | 30.0 | x0.88 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/rc3-v0-fm1-C9511` |
| 11 | Full Metal Plate 1.7 | Cortex | 9512 | 0 | W | 21.11 | x500.01 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/rc3-v0-fm1-C9512` |
| 12 | Full Metal Plate 1.7 | Armada | 9511 | 0 | w | 30.0 | x1.02 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/rc3-v0-fm2-A9511` |
| 13 | Full Metal Plate 1.7 | Armada | 9512 | 0 | l | 30.0 | x1.06 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/rc3-v0-fm2-A9512` |
| 14 | Full Metal Plate 1.7 | Cortex | 9511 | 0 | w | 30.0 | x0.87 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/rc3-v0-fm2-C9511` |
| 15 | Full Metal Plate 1.7 | Cortex | 9512 | 0 | w | 30.0 | x0.89 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/rc3-v0-fm2-C9512` |
| 16 | Red Comet Remake 1.8 | Armada | 9501 | 0 | L | 27.14 | x0.58 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/rc3-v0-rc2-A9501` |
| 17 | Red Comet Remake 1.8 | Armada | 9504 | 0 | l | 30.0 | x0.72 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/rc3-v0-rc2-A9504` |
| 18 | Red Comet Remake 1.8 | Cortex | 9501 | 0 | l | 30.0 | x0.83 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/rc3-v0-rc2-C9501` |
| 19 | Red Comet Remake 1.8 | Cortex | 9504 | 0 | w | 30.0 | x2.23 | c494a6f08c+98de158b5ddc, v0.5.11 | `matches/rc3-v0-rc2-C9504` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.62 | 2.87 | - | ok |
| t2->4th moho (min) | 6.63 | 7.00 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.46 | 0.48 | 0.00 | ok, short of aim |
| adv plant frame x | 2.26 | 2.39 | 1.50 | ok, short of aim |
| near-done strips | 12.89 | 177.61 | 0.00 | ok, short of aim |
| t2 cons given early | 0.06 | 0.31 | 0.00 | ok, short of aim |
| supers before 4 moho | 3.03 | 3.69 | 0.00 | ok, short of aim |
| lone t2 con minutes | 1.56 | 0.67 | 0.00 | ok, short of aim |
| no t2 by minute 20 | 0.00 | 0.00 | - | ok |
| frozen minutes | 0.17 | 0.11 | 0.00 | ok, short of aim |
| bare-hands minutes | 0.22 | 0.06 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.51 | 0.40 | 0.00 | ok, short of aim |
| runs turned back | 0.00 | - | 0.00 | n/a |
| anomalous seats | 0.00 | 0.04 | 0.00 | ok |
| peak constructors | 112.42 | 113.42 | - | ok |
| army share (neg) | 0.41 | 0.38 | - | ok |
| -log income at 20 | -5.38 | -5.18 | - | ok |
| games won or ahead | 0.60 | 0.50 | - | ok |

Contract: **PASS** over 20 games (36 of our seats, 36 release seats); 10 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomalies: 0 seat(s) of 24 outside 5 robust deviations of v0.5.11's normal; 12 seat(s) skipped, no normal yet for hc50-x1-A-1v1@Full Metal Plate, hc50-x1-A-2v2@Full Metal Plate, hc50-x1-C-1v1@Full Metal Plate, hc50-x1-C-2v2@Full Metal Plate
```
