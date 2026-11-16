<!-- meta {"date": "2026-11-16", "topic": "stuck-push", "title": "ln8: travel lean 1 vs 2 in games vs v0.5.13 (8 games), wreck_push 8 more", "games": 8, "W": 1, "L": 1, "w": 4, "l": 2, "inc20": 0.76, "verdict": "Scenario, all 7 pairs: lean=2 stuck 0 every run vs 17 nudges at lean=1; all killed 31-33 s vs 33-78 s (mean 44), lean=2 faster in 7 of 7. Games: army stuck per 10 min per 1k army 2.98 (lean 2) vs 3.44 (lean 1), v0.5.13 seats 2.36; won or ahead 0.50 vs 0.75, noise at 4 games. Made the Unstable default (TUNE_TRAVEL_LEAN 2) for the next gate."} -->
# ln8: travel lean 1 vs 2 in games vs v0.5.13 (8 games), wreck_push 8 more

- **Date:** 2026-11-16
- **Topic:** stuck-push
- **Purpose:** Row 113, army.md step 2 after the scenario: Unstable lane stockf vs v0.5.13 at +50, 4 seeds (rc A9501, cm C9502, cc A9503, fm C9511), each seed played at apex_travel_lean=1 and =2. Before it, wreck_push 8 more runs alternating.
- **Result:** 8 games: won 1, lost 1, timeouts ahead 4, behind 2; income at 20 min x0.76 ours/theirs
- **Verdict:** Scenario, all 7 pairs: lean=2 stuck 0 every run vs 17 nudges at lean=1; all killed 31-33 s vs 33-78 s (mean 44), lean=2 faster in 7 of 7. Games: army stuck per 10 min per 1k army 2.98 (lean 2) vs 3.44 (lean 1), v0.5.13 seats 2.36; won or ahead 0.50 vs 0.75, noise at 4 games. Made the Unstable default (TUNE_TRAVEL_LEAN 2) for the next gate.
- **Ours:** Apexstockf-lane-stockf-standard
- **Opponents:** Apex-v0.5.13-standard
- **Code:** Apex-v0.5.13-standard = `b836bd8247+2f2ca832cead` (8 games); Apexstockf-lane-stockf-standard = `363c70a0a5+6fd539d7c2aa` (8 games)
- **Maps:** Carrot Mountains v2.0, Comet Catcher Remake 1.8, Full Metal Plate 1.7, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexstockf:lane-stockf:standard --b Apex:v0.5.13:standard --per-side 2 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 9503 --ai-option apex_travel_lean=1 --out matches/ln8-v1-cc2-A9503`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9503 | 0 | w | 30.0 | x1.54 | 363c70a0a5+6fd539d7c2aa, b836bd8247+2f2ca832cead | `matches/ln8-v1-cc2-A9503` |
| 1 | Carrot Mountains v2.0 | Cortex | 9502 | 0 | w | 30.0 | x1.27 | 363c70a0a5+6fd539d7c2aa, b836bd8247+2f2ca832cead | `matches/ln8-v1-cm2-C9502` |
| 2 | Full Metal Plate 1.7 | Cortex | 9511 | 0 | l | 30.0 | x0.72 | 363c70a0a5+6fd539d7c2aa, b836bd8247+2f2ca832cead | `matches/ln8-v1-fm2-C9511` |
| 3 | Red Comet Remake 1.8 | Armada | 9501 | 0 | w | 30.0 | x0.80 | 363c70a0a5+6fd539d7c2aa, b836bd8247+2f2ca832cead | `matches/ln8-v1-rc2-A9501` |
| 4 | Comet Catcher Remake 1.8 | Armada | 9503 | 0 | w | 30.0 | x1.19 | 363c70a0a5+6fd539d7c2aa, b836bd8247+2f2ca832cead | `matches/ln8-v2-cc2-A9503` |
| 5 | Carrot Mountains v2.0 | Cortex | 9502 | 0 | l | 30.0 | x0.76 | 363c70a0a5+6fd539d7c2aa, b836bd8247+2f2ca832cead | `matches/ln8-v2-cm2-C9502` |
| 6 | Full Metal Plate 1.7 | Cortex | 9511 | 0 | W | 27.53 | x5.72 | 363c70a0a5+6fd539d7c2aa, b836bd8247+2f2ca832cead | `matches/ln8-v2-fm2-C9511` |
| 7 | Red Comet Remake 1.8 | Armada | 9501 | 0 | L | 21.31 | x0.02 | 363c70a0a5+6fd539d7c2aa, b836bd8247+2f2ca832cead | `matches/ln8-v2-rc2-A9501` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 3.28 | 3.06 | - | ok |
| t2->4th moho (min) | 7.16 | 5.52 | 3.00 | FAIL (worse than release) |
| lab-job leaves/job | 0.44 | 0.40 | 0.00 | ok, short of aim |
| adv plant frame x | 1.92 | 2.09 | 1.50 | ok, short of aim |
| near-done strips | 12.94 | 6.69 | 0.00 | FAIL (worse than release) |
| t2 cons given early | 0.12 | 0.06 | 0.00 | ok, short of aim |
| supers before 4 moho | 6.40 | 5.60 | 0.00 | FAIL (worse than release) |
| lone t2 con minutes | 0.40 | 0.00 | 0.00 | ok, short of aim |
| base lost while 'covered' k | 10.95 | 2.98 | 0.00 | FAIL (worse than release) |
| oldest plant order min | 3.47 | 3.28 | - | ok |
| no t2 by minute 20 | 0.06 | 0.06 | - | ok |
| frozen minutes | 0.88 | 1.12 | 0.00 | ok, short of aim |
| bare-hands minutes | 1.12 | 1.12 | 0.00 | ok, short of aim |
| wiped bomber runs | 0.41 | 0.36 | 0.00 | ok, short of aim |
| runs turned back | 0.07 | 0.00 | 0.00 | ok, short of aim |
| gunships sent to lose | 0.00 | 0.00 | 0.00 | ok |
| stacked radar/jammers | 0.20 | 0.25 | 0.00 | ok, short of aim |
| army stuck /10min/1k army | 3.01 | 2.35 | 0.00 | ok, short of aim |
| ground given up share | 0.28 | - | 0.00 | n/a |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.63 | -1.54 | - | ok |
| army share (neg) | 0.38 | 0.37 | - | ok |
| -log income at 20 | -5.04 | -5.18 | - | ok |
| games won or ahead | 0.62 | 0.50 | - | ok |

Contract: **FAIL (4)** over 8 games (16 of our seats, 16 release seats); 14 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.13 (run `python tools/anomaly.py build`)
```
