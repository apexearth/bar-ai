<!-- meta {"date": "2026-11-18", "topic": "v0515", "title": "sh3 v0.5.17 candidate vs BARb stable hard (final tree, no lobby options)", "games": 20, "W": 4, "L": 0, "w": 13, "l": 3, "inc20": 1.66, "verdict": "Won/ahead 18/20 (v0.5.16 18/20, bb1-vnew 19/20). Income at 20 median 263 (v0.5.16 228, bb1-vnew 251). Raider extractor kills after 12 min 37 (v0.5.16 13). Contract vs v0.5.16's BARb games: FAIL on one check only, mex lost to Ticks by 10 min 2.40 vs 1.00 (92% of resamples). His 11-18 call: ship the escorts and take the Tick losses up with our own fight layer (issues/ticks-flank-extractors.md); the leak-screen fix tried for it was dead code and was removed."} -->
# sh3 v0.5.17 candidate vs BARb stable hard (final tree, no lobby options)

- **Date:** 2026-11-18
- **Topic:** v0515
- **Purpose:** BARb leg of the v0.5.17 release gate: the final tree vs BARb:stable:hard, seeds 10201-10210 both factions, 30 min, Comet Catcher 1v1 +50. Old leg: bb1-vrel (v0.5.16, same seeds); same-code control: bb1-vnew (escorts, old DLL and lobby file).
- **Result:** 20 games: won 4, lost 0, timeouts ahead 13, behind 3; income at 20 min x1.66 ours/theirs
- **Verdict:** Won/ahead 18/20 (v0.5.16 18/20, bb1-vnew 19/20). Income at 20 median 263 (v0.5.16 228, bb1-vnew 251). Raider extractor kills after 12 min 37 (v0.5.16 13). Contract vs v0.5.16's BARb games: FAIL on one check only, mex lost to Ticks by 10 min 2.40 vs 1.00 (92% of resamples). His 11-18 call: ship the escorts and take the Tick losses up with our own fight layer (issues/ticks-flank-extractors.md); the leak-screen fix tried for it was dead code and was removed.
- **Ours:** Apexestall-lane-estall
- **Opponents:** BARb-stable-hard
- **Code:** Apexestall-lane-estall = `d32b7b84d8+5fc1ba8c650e` (20 games); BARb-stable-hard = `?` (20 games)
- **Maps:** Comet Catcher Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall --b BARb:stable:hard --per-side 1 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 10201 --out matches/sh3-vhome-cc1-A10201`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 10201 | 0 | w | 30.0 | x1.65 | ?, d32b7b84d8+5fc1ba8c650e | `matches/sh3-vhome-cc1-A10201` |
| 1 | Comet Catcher Remake 1.8 | Armada | 10202 | 0 | w | 30.0 | x2.61 | ?, d32b7b84d8+5fc1ba8c650e | `matches/sh3-vhome-cc1-A10202` |
| 2 | Comet Catcher Remake 1.8 | Armada | 10203 | 0 | w | 30.0 | x1.93 | ?, d32b7b84d8+5fc1ba8c650e | `matches/sh3-vhome-cc1-A10203` |
| 3 | Comet Catcher Remake 1.8 | Armada | 10204 | 0 | w | 30.0 | x1.66 | ?, d32b7b84d8+5fc1ba8c650e | `matches/sh3-vhome-cc1-A10204` |
| 4 | Comet Catcher Remake 1.8 | Armada | 10205 | 0 | W | 27.23 | x3.25 | ?, d32b7b84d8+5fc1ba8c650e | `matches/sh3-vhome-cc1-A10205` |
| 5 | Comet Catcher Remake 1.8 | Armada | 10206 | 0 | l | 30.0 | x0.98 | ?, d32b7b84d8+5fc1ba8c650e | `matches/sh3-vhome-cc1-A10206` |
| 6 | Comet Catcher Remake 1.8 | Armada | 10207 | 0 | w | 30.0 | x1.51 | ?, d32b7b84d8+5fc1ba8c650e | `matches/sh3-vhome-cc1-A10207` |
| 7 | Comet Catcher Remake 1.8 | Armada | 10208 | 0 | l | 30.0 | x0.95 | ?, d32b7b84d8+5fc1ba8c650e | `matches/sh3-vhome-cc1-A10208` |
| 8 | Comet Catcher Remake 1.8 | Armada | 10209 | 0 | w | 30.0 | x1.18 | ?, d32b7b84d8+5fc1ba8c650e | `matches/sh3-vhome-cc1-A10209` |
| 9 | Comet Catcher Remake 1.8 | Armada | 10210 | 0 | w | 30.0 | x2.04 | ?, d32b7b84d8+5fc1ba8c650e | `matches/sh3-vhome-cc1-A10210` |
| 10 | Comet Catcher Remake 1.8 | Cortex | 10201 | 0 | w | 30.0 | x1.70 | ?, d32b7b84d8+5fc1ba8c650e | `matches/sh3-vhome-cc1-C10201` |
| 11 | Comet Catcher Remake 1.8 | Cortex | 10202 | 0 | W | 18.84 | - | ?, d32b7b84d8+5fc1ba8c650e | `matches/sh3-vhome-cc1-C10202` |
| 12 | Comet Catcher Remake 1.8 | Cortex | 10203 | 0 | w | 30.0 | x1.86 | ?, d32b7b84d8+5fc1ba8c650e | `matches/sh3-vhome-cc1-C10203` |
| 13 | Comet Catcher Remake 1.8 | Cortex | 10204 | 0 | W | 26.15 | x2.78 | ?, d32b7b84d8+5fc1ba8c650e | `matches/sh3-vhome-cc1-C10204` |
| 14 | Comet Catcher Remake 1.8 | Cortex | 10205 | 0 | w | 30.0 | x2.29 | ?, d32b7b84d8+5fc1ba8c650e | `matches/sh3-vhome-cc1-C10205` |
| 15 | Comet Catcher Remake 1.8 | Cortex | 10206 | 0 | W | 9.55 | - | ?, d32b7b84d8+5fc1ba8c650e | `matches/sh3-vhome-cc1-C10206` |
| 16 | Comet Catcher Remake 1.8 | Cortex | 10207 | 0 | w | 30.0 | x1.69 | ?, d32b7b84d8+5fc1ba8c650e | `matches/sh3-vhome-cc1-C10207` |
| 17 | Comet Catcher Remake 1.8 | Cortex | 10208 | 0 | w | 30.0 | x2.07 | ?, d32b7b84d8+5fc1ba8c650e | `matches/sh3-vhome-cc1-C10208` |
| 18 | Comet Catcher Remake 1.8 | Cortex | 10209 | 0 | l | 30.0 | x0.69 | ?, d32b7b84d8+5fc1ba8c650e | `matches/sh3-vhome-cc1-C10209` |
| 19 | Comet Catcher Remake 1.8 | Cortex | 10210 | 0 | w | 30.0 | x1.20 | ?, d32b7b84d8+5fc1ba8c650e | `matches/sh3-vhome-cc1-C10210` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.56 | 16.67 | - | ok |
| t2->4th moho (min) | 4.93 | 16.67 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.30 | - | 0.00 | n/a |
| adv plant frame x | 2.73 | - | 1.50 | n/a |
| near-done /10k built | 0.61 | 0.00 | 0.00 | FAIL (worse than release, 100% of resamples) |
| t2 cons given early | 0.00 | 0.00 | 0.00 | ok |
| supers before 4 moho | 1.05 | 0.00 | 0.00 | FAIL (worse than release, 100% of resamples) |
| lone t2 con minutes | 0.42 | 0.00 | 0.00 | ok, short of aim |
| base lost while 'covered' k | 0.70 | - | 0.00 | n/a |
| oldest plant order min | 2.30 | - | - | n/a |
| no t2 by minute 20 | 0.00 | 0.06 | - | ok |
| frozen minutes | 0.00 | 0.00 | 0.00 | ok |
| com minutes on their half | 0.33 | 0.00 | - | ok |
| com lost on their half | 0.00 | 0.00 | 0.00 | ok |
| mex lost to ticks by 10 min | 2.40 | 0.10 | 0.00 | FAIL (worse than release, 100% of resamples) |
| their mex killed /10min (neg) | -12.35 | -30.13 | - | FAIL (worse than release, 100% of resamples) |
| their army / ours, 8-12 min | 1.04 | - | - | n/a |
| lost per killed | 1.45 | 1.43 | - | ok |
| reclaimed / killed (neg) | -0.15 | -0.05 | - | ok |
| bare-hands minutes | 0.00 | 0.00 | 0.00 | ok |
| wiped bomber runs | 0.23 | - | 0.00 | n/a |
| runs turned back | 0.00 | - | 0.00 | n/a |
| gunships sent to lose | 0.00 | - | 0.00 | n/a |
| stacked radar/jammers | 0.00 | - | 0.00 | n/a |
| army stuck /10min/1k army | 3.54 | 0.00 | 0.00 | FAIL (worse than release, 100% of resamples) |
| ground given up share | 0.26 | - | 0.00 | n/a |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.73 | -1.99 | - | worse, within noise (83% of resamples) |
| army share (neg) | 0.37 | 0.35 | - | ok |
| -log income at 20 | -5.57 | -5.08 | - | ok |
| games won or ahead | 0.90 | 0.50 | - | ok |

Contract: **FAIL (5)** over 20 games (20 of our seats, 20 release seats); 6 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.16 (run `python tools/anomaly.py build`)
```
