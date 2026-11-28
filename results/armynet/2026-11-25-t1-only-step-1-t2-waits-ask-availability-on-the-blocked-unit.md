<!-- meta {"date": "2026-11-25", "topic": "armynet", "title": "T1-only step 1: T2 waits ask availability (on the blocked-unit DLL)", "games": 8, "W": 8, "L": 0, "w": 0, "l": 0, "inc20": 0.53, "verdict": "8/8 W (blk alone 5/8, off 6/8); enemy coms 35 (28, 30); ours lost 4 (5, 4); our ground at 30 min mean 21.8k (9.1k, 13.2k), air 18.0k (16.5k, 13.9k); minutes without a land lab 2.69 (5.49, 3.01); air-plant elections 196 vs 258. Candidate; Mac 6v6 next, judged against its A/A noise (+-12 commanders over 8 seeds)."} -->
# T1-only step 1: T2 waits ask availability (on the blocked-unit DLL)

- **Date:** 2026-11-25
- **Topic:** armynet
- **Purpose:** His 11-25: stop the anticipation of a T2 that never comes, and the air drift. Step 1 = 'one T1 line until T2' and production's richBal hold both wait for T2 only when an advanced plant is available (worth.as AdvancedPlantAvailable), on the blocked-unit DLL (CircuitDef modoption_blocked -> maxThisUnit 0). Carrot 4v4 notech2 vs BARb hard, BARb +100 / us +0, 45 min, seeds 1-8, vs the armk blocked-unit-only games and the arme/armh off games (same seeds and setup).
- **Result:** 8 games: won 8, lost 0, timeouts ahead 0, behind 0; income at 20 min x0.53 ours/theirs
- **Verdict:** 8/8 W (blk alone 5/8, off 6/8); enemy coms 35 (28, 30); ours lost 4 (5, 4); our ground at 30 min mean 21.8k (9.1k, 13.2k), air 18.0k (16.5k, 13.9k); minutes without a land lab 2.69 (5.49, 3.01); air-plant elections 196 vs 258. Candidate; Mac 6v6 next, judged against its A/A noise (+-12 commanders over 8 seeds).
- **Ours:** Apexarmynet-lane-armynet
- **Opponents:** BARb-stable-hard
- **Code:** Apexarmynet-lane-armynet = `7860befdad+f53ca75243b5` (8 games); BARb-stable-hard = `?` (8 games)
- **Maps:** Carrot Mountains v2.0
- **Sides:** Armada/Cortex; **bonus:** [0, 100]; **time cap:** 45 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexarmynet:lane-armynet --b BARb:stable:hard --map Carrot Mountains v2.0 --per-side 4 --minutes 45 --seed 1 --speed 20 --handicap 0,100 --modoption unit_restrictions_notech2=1 --out matches/armm-s1p-s1`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Carrot Mountains v2.0 | Armada/Cortex | 1 | 0 | W | 38.89 | x0.85 | 7860befdad+f53ca75243b5, ? | `matches/armm-s1p-s1` |
| 1 | Carrot Mountains v2.0 | Armada/Cortex | 2 | 0 | W | 31.84 | x0.56 | 7860befdad+f53ca75243b5, ? | `matches/armm-s1p-s2` |
| 2 | Carrot Mountains v2.0 | Armada/Cortex | 3 | 0 | W | 37.33 | x0.49 | 7860befdad+f53ca75243b5, ? | `matches/armm-s1p-s3` |
| 3 | Carrot Mountains v2.0 | Armada/Cortex | 4 | 0 | W | 33.66 | x0.49 | 7860befdad+f53ca75243b5, ? | `matches/armm-s1p-s4` |
| 4 | Carrot Mountains v2.0 | Armada/Cortex | 5 | 0 | W | 32.77 | x0.59 | 7860befdad+f53ca75243b5, ? | `matches/armm-s1p-s5` |
| 5 | Carrot Mountains v2.0 | Armada/Cortex | 6 | 0 | W | 32.92 | x0.38 | 7860befdad+f53ca75243b5, ? | `matches/armm-s1p-s6` |
| 6 | Carrot Mountains v2.0 | Armada/Cortex | 7 | 0 | W | 39.82 | x0.47 | 7860befdad+f53ca75243b5, ? | `matches/armm-s1p-s7` |
| 7 | Carrot Mountains v2.0 | Armada/Cortex | 8 | 0 | W | 36.37 | x0.54 | 7860befdad+f53ca75243b5, ? | `matches/armm-s1p-s8` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | - | - | - | n/a |
| t2->4th moho (min) | - | - | 3.00 | n/a |
| lab-job leaves/job | 0.37 | - | 0.00 | n/a |
| adv plant frame x | - | - | 1.50 | n/a |
| near-done /10k built | 0.66 | 0.00 | 0.00 | FAIL (worse than release, 100% of resamples) |
| t2 cons given early | 0.03 | 0.00 | 0.00 | ok, short of aim |
| supers before 4 moho | - | - | 0.00 | n/a |
| lone t2 con minutes | - | - | 0.00 | n/a |
| base lost /covered min | 11.11 | - | 0.00 | n/a |
| oldest plant order min | 2.07 | - | - | n/a |
| no t2 by minute 20 | 1.00 | 1.00 | - | ok |
| frozen minutes | 0.62 | 1.38 | 0.00 | ok, short of aim |
| com minutes on their half | 5.42 | 0.00 | - | FAIL (worse than release, 100% of resamples) |
| com lost on their half | 0.06 | 0.00 | 0.00 | worse, within noise (66% of resamples) |
| mex lost to ticks by 10 min | 0.03 | 0.09 | 0.00 | ok, short of aim |
| raider repeat kills /10min | 8.15 | 12.29 | 0.00 | ok, short of aim |
| their mex killed /10min (neg) | -8.69 | -16.00 | - | FAIL (worse than release, 100% of resamples) |
| their army / ours, 8-12 min | 1.45 | - | - | n/a |
| lost per killed | 1.01 | 2.35 | - | ok |
| reclaimed / killed (neg) | -0.24 | -0.04 | - | ok |
| bare-hands minutes | 0.69 | 1.56 | 0.00 | ok, short of aim |
| minutes without a land lab | 2.69 | - | 0.00 | n/a |
| minutes without a converter | 0.84 | - | 0.00 | n/a |
| wiped bomber runs | 0.39 | - | 0.00 | n/a |
| runs turned back | 0.03 | - | 0.00 | n/a |
| gunships sent to lose | 0.00 | - | 0.00 | n/a |
| stacked radar/jammers | 0.03 | - | 0.00 | n/a |
| army stuck /10min/1k army | 5.92 | 0.00 | 0.00 | FAIL (worse than release, 100% of resamples) |
| ground given up share | 0.15 | - | 0.00 | n/a |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -0.51 | -1.49 | - | FAIL (worse than release, 100% of resamples) |
| army share (neg) | 0.59 | 0.21 | - | ok |
| -log income at 20 | -3.97 | -4.62 | - | FAIL (worse than release, 100% of resamples) |
| games won or ahead | 1.00 | 0.50 | - | ok |

Contract: **FAIL (6)** over 8 games (32 of our seats, 32 release seats); 8 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.18 (run `python tools/anomaly.py build`)
```
