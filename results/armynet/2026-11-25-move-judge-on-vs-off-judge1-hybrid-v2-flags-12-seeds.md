<!-- meta {"date": "2026-11-25", "topic": "armynet", "title": "Move judge on vs off (judge1, hybrid v2 flags, 12 seeds)", "games": 24, "W": 0, "L": 12, "w": 10, "l": 2, "inc20": 0.81, "verdict": "Judge on: 0W/5L/7T vs 0W/7L/5T. Paired (paired_summary, joff as base): trade at 12 min 0.53 vs 0.31 (11/12 seeds better), army killed by 12 +909 (10/12), army lost by 12 -1,240 (11/12 lower), army ratio at 12 1.18 vs 0.60 (9/12); trade at 20 0.52 vs 0.42 (8/12). It orders less forward (0.38 vs 0.49, 10/12) and keeps units nearer its own (228 vs 307): better fights, not a more forward line. Kept as the play candidate; next a gate vs hBARb2's model and more seeds."} -->
# Move judge on vs off (judge1, hybrid v2 flags, 12 seeds)

- **Date:** 2026-11-25
- **Topic:** armynet
- **Purpose:** Does letting the judge head pick among the place head's top 5 cells (serve --judge 5) play better than the same model without it? Same judge1 model both arms, hBARb2 flags, vs BARb hard, 40 min, seeds 89-100. Arms: jon = --judge 5, joff = judge off.
- **Result:** 24 games: won 0, lost 12, timeouts ahead 10, behind 2; income at 20 min x0.81 ours/theirs
- **Verdict:** Judge on: 0W/5L/7T vs 0W/7L/5T. Paired (paired_summary, joff as base): trade at 12 min 0.53 vs 0.31 (11/12 seeds better), army killed by 12 +909 (10/12), army lost by 12 -1,240 (11/12 lower), army ratio at 12 1.18 vs 0.60 (9/12); trade at 20 0.52 vs 0.42 (8/12). It orders less forward (0.38 vs 0.49, 10/12) and keeps units nearer its own (228 vs 307): better fights, not a more forward line. Kept as the play candidate; next a gate vs hBARb2's model and more seeds.
- **Ours:** Apexarmynet-lane-armynet-standard
- **Opponents:** BARb-stable-hard
- **Code:** Apexarmynet-lane-armynet-standard = `7860befdad+b2733aaf46f9` (24 games); BARb-stable-hard = `?` (24 games)
- **Maps:** Comet Catcher Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** [50, 50]; **time cap:** 40 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexarmynet:lane-armynet:standard --b BARb:stable:hard --map Comet Catcher Remake 1.8 --minutes 40 --seed 89 --replay --speed 4 --handicap 50,50 --sides Cortex,Cortex --ai-option apex_verbose=1 --modoption dev_armynet=1 --modoption dev_armynet_keep=armawac,armfav,armflea,armpeep,armpt,armsh,armspy,corawac,corfav,corfink,corpt,corsh,corspy --write-dir C:\Users\apexe\WebstormProjects\bar-ai\matches\watch-armynet-engine-20261125-100357-37680 --out C:\Users\apexe\WebstormProjects\bar-ai\matches\armynet-watch-20261125-100357-37680`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Cortex | 89 | 0 | L | 27.61 | x0.21 | 7860befdad+b2733aaf46f9, ? | `matches/armynet-watch-20261125-100357-37680` |
| 1 | Comet Catcher Remake 1.8 | Cortex | 89 | 0 | L | 35.38 | x0.42 | 7860befdad+b2733aaf46f9, ? | `matches/armynet-watch-20261125-100417-20244` |
| 2 | Comet Catcher Remake 1.8 | Armada | 90 | 0 | w | 40.0 | x1.30 | 7860befdad+b2733aaf46f9, ? | `matches/armynet-watch-20261125-100437-45724` |
| 3 | Comet Catcher Remake 1.8 | Armada | 90 | 0 | L | 37.07 | x1.08 | 7860befdad+b2733aaf46f9, ? | `matches/armynet-watch-20261125-101157-15824` |
| 4 | Comet Catcher Remake 1.8 | Cortex | 91 | 0 | L | 30.52 | x0.46 | 7860befdad+b2733aaf46f9, ? | `matches/armynet-watch-20261125-101620-29312` |
| 5 | Comet Catcher Remake 1.8 | Cortex | 91 | 0 | w | 40.0 | x2.32 | 7860befdad+b2733aaf46f9, ? | `matches/armynet-watch-20261125-101402-44316` |
| 6 | Comet Catcher Remake 1.8 | Armada | 92 | 0 | L | 32.44 | x0.70 | 7860befdad+b2733aaf46f9, ? | `matches/armynet-watch-20261125-102216-2812` |
| 7 | Comet Catcher Remake 1.8 | Armada | 92 | 0 | L | 28.49 | x1.77 | 7860befdad+b2733aaf46f9, ? | `matches/armynet-watch-20261125-102449-35728` |
| 8 | Comet Catcher Remake 1.8 | Cortex | 93 | 0 | w | 40.0 | x1.32 | 7860befdad+b2733aaf46f9, ? | `matches/armynet-watch-20261125-102517-36160` |
| 9 | Comet Catcher Remake 1.8 | Cortex | 93 | 0 | L | 37.11 | x0.67 | 7860befdad+b2733aaf46f9, ? | `matches/armynet-watch-20261125-103117-42388` |
| 10 | Comet Catcher Remake 1.8 | Armada | 94 | 0 | w | 40.0 | x1.62 | 7860befdad+b2733aaf46f9, ? | `matches/armynet-watch-20261125-103245-24600` |
| 11 | Comet Catcher Remake 1.8 | Armada | 94 | 0 | w | 40.0 | x1.46 | 7860befdad+b2733aaf46f9, ? | `matches/armynet-watch-20261125-103645-18216` |
| 12 | Comet Catcher Remake 1.8 | Cortex | 95 | 0 | w | 40.0 | x0.63 | 7860befdad+b2733aaf46f9, ? | `matches/armynet-watch-20261125-104212-35400` |
| 13 | Comet Catcher Remake 1.8 | Armada | 96 | 0 | L | 31.35 | x0.63 | 7860befdad+b2733aaf46f9, ? | `matches/armynet-watch-20261125-110700-26636` |
| 14 | Comet Catcher Remake 1.8 | Armada | 96 | 0 | w | 40.0 | x1.02 | 7860befdad+b2733aaf46f9, ? | `matches/armynet-watch-20261125-110721-16868` |
| 15 | Comet Catcher Remake 1.8 | Cortex | 95 | 0 | w | 40.0 | x1.34 | 7860befdad+b2733aaf46f9, ? | `matches/armynet-watch-20261125-110640-47872` |
| 16 | Comet Catcher Remake 1.8 | Cortex | 97 | 0 | L | 30.64 | x0.41 | 7860befdad+b2733aaf46f9, ? | `matches/armynet-watch-20261125-111556-15216` |
| 17 | Comet Catcher Remake 1.8 | Cortex | 97 | 0 | L | 34.24 | x0.51 | 7860befdad+b2733aaf46f9, ? | `matches/armynet-watch-20261125-111841-35504` |
| 18 | Comet Catcher Remake 1.8 | Armada | 98 | 0 | w | 40.0 | x0.59 | 7860befdad+b2733aaf46f9, ? | `matches/armynet-watch-20261125-111901-14624` |
| 19 | Comet Catcher Remake 1.8 | Armada | 98 | 0 | L | 32.92 | x0.75 | 7860befdad+b2733aaf46f9, ? | `matches/armynet-watch-20261125-112424-10332` |
| 20 | Comet Catcher Remake 1.8 | Cortex | 99 | 0 | L | 35.58 | x0.51 | 7860befdad+b2733aaf46f9, ? | `matches/armynet-watch-20261125-112805-8168` |
| 21 | Comet Catcher Remake 1.8 | Cortex | 99 | 0 | w | 40.0 | x1.30 | 7860befdad+b2733aaf46f9, ? | `matches/armynet-watch-20261125-113034-15236` |
| 22 | Comet Catcher Remake 1.8 | Armada | 100 | 0 | l | 40.0 | x0.79 | 7860befdad+b2733aaf46f9, ? | `matches/armynet-watch-20261125-113329-28112` |
| 23 | Comet Catcher Remake 1.8 | Armada | 100 | 0 | l | 40.0 | x0.72 | 7860befdad+b2733aaf46f9, ? | `matches/armynet-watch-20261125-113808-41664` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.57 | 26.27 | - | ok |
| t2->4th moho (min) | 5.46 | 26.27 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.42 | - | 0.00 | n/a |
| adv plant frame x | 2.56 | - | 1.50 | n/a |
| near-done /10k built | 0.52 | 0.00 | 0.00 | FAIL (worse than release, 100% of resamples) |
| t2 cons given early | 0.00 | 0.00 | 0.00 | ok |
| supers before 4 moho | 1.54 | 0.00 | 0.00 | FAIL (worse than release, 100% of resamples) |
| lone t2 con minutes | 0.42 | 0.00 | 0.00 | ok, short of aim |
| base lost /covered min | 491.52 | - | 0.00 | n/a |
| oldest plant order min | 3.85 | - | - | n/a |
| no t2 by minute 20 | 0.00 | 0.00 | - | ok |
| frozen minutes | 0.00 | 0.00 | 0.00 | ok |
| com minutes on their half | 0.58 | 0.00 | - | worse, within noise (54% of resamples) |
| com lost on their half | 0.00 | 0.00 | 0.00 | ok |
| mex lost to ticks by 10 min | 2.38 | 0.12 | 0.00 | FAIL (worse than release, 100% of resamples) |
| raider repeat kills /10min | 26.09 | 2.44 | 0.00 | FAIL (worse than release, 100% of resamples) |
| their mex killed /10min (neg) | -7.87 | -30.66 | - | FAIL (worse than release, 100% of resamples) |
| their army / ours, 8-12 min | 0.88 | - | - | n/a |
| lost per killed | 3.48 | 0.49 | - | FAIL (worse than release, 100% of resamples) |
| reclaimed / killed (neg) | -0.20 | -0.02 | - | ok |
| bare-hands minutes | 0.00 | 0.00 | 0.00 | ok |
| minutes without a land lab | 0.15 | - | 0.00 | n/a |
| minutes without a converter | 0.30 | - | 0.00 | n/a |
| wiped bomber runs | 0.21 | - | 0.00 | n/a |
| runs turned back | 0.88 | - | 0.00 | n/a |
| gunships sent to lose | - | - | 0.00 | n/a |
| stacked radar/jammers | 0.04 | - | 0.00 | n/a |
| army stuck /10min/1k army | 3.57 | 0.00 | 0.00 | FAIL (worse than release, 100% of resamples) |
| ground given up share | 0.50 | - | 0.00 | n/a |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.61 | -2.66 | - | FAIL (worse than release, 100% of resamples) |
| army share (neg) | 0.37 | 0.43 | - | FAIL (worse than release, 90% of resamples) |
| -log income at 20 | -5.26 | -5.53 | - | worse, within noise (80% of resamples) |
| games won or ahead | 0.46 | 0.50 | - | FAIL (does not beat the release) |

Contract: **FAIL (10)** over 24 games (24 of our seats, 24 release seats); 7 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.18 (run `python tools/anomaly.py build`)
```
