<!-- meta {"date": "2026-11-18", "topic": "v0515", "title": "sh1: leak screen counts only the army at home, vs BARb hard", "games": 20, "W": 5, "L": 0, "w": 14, "l": 1, "inc20": 1.91, "verdict": "Won/ahead 19 of 20 (5 wins, 0 losses). Extractors lost to Ticks/scout cars by 10 min 1.85 (no fix 3.10, v0.5.16 1.00); per seed vs no fix: 9 better, 1 worse. Income@20 med 275 (251, 228). Contract vs v0.5.16: PASS (Ticks worse within noise, 72%). The screen engaged in only 5 of 57 samples at minutes 7-10 (home army mostly over 800), so part of the gain may be noise."} -->
# sh1: leak screen counts only the army at home, vs BARb hard

- **Date:** 2026-11-18
- **Topic:** v0515
- **Purpose:** Fix for the bb1 Ticks FAIL: apex_screen_home 1 (guard floor for bare extractors returns when the army near home drops under the screen). Lane estall vs BARb:stable:hard, seeds 10201-10210 both factions, Comet Catcher 1v1, +50, 30 min; controls bb1-vnew (no fix) and bb1-vrel (v0.5.16)
- **Result:** 20 games: won 5, lost 0, timeouts ahead 14, behind 1; income at 20 min x1.91 ours/theirs
- **Verdict:** Won/ahead 19 of 20 (5 wins, 0 losses). Extractors lost to Ticks/scout cars by 10 min 1.85 (no fix 3.10, v0.5.16 1.00); per seed vs no fix: 9 better, 1 worse. Income@20 med 275 (251, 228). Contract vs v0.5.16: PASS (Ticks worse within noise, 72%). The screen engaged in only 5 of 57 samples at minutes 7-10 (home army mostly over 800), so part of the gain may be noise.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** BARb-stable-hard
- **Code:** Apexestall-lane-estall-standard = `d32b7b84d8+b6416ef8fe43` (20 games); BARb-stable-hard = `?` (20 games)
- **Maps:** Comet Catcher Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b BARb:stable:hard --per-side 1 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 10201 --out matches/sh1-vhome-cc1-A10201`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 10201 | 0 | w | 30.0 | x1.06 | ?, d32b7b84d8+b6416ef8fe43 | `matches/sh1-vhome-cc1-A10201` |
| 1 | Comet Catcher Remake 1.8 | Armada | 10202 | 0 | w | 30.0 | x2.27 | ?, d32b7b84d8+b6416ef8fe43 | `matches/sh1-vhome-cc1-A10202` |
| 2 | Comet Catcher Remake 1.8 | Armada | 10203 | 0 | l | 30.0 | x1.17 | ?, d32b7b84d8+b6416ef8fe43 | `matches/sh1-vhome-cc1-A10203` |
| 3 | Comet Catcher Remake 1.8 | Armada | 10204 | 0 | W | 25.23 | x3.33 | ?, d32b7b84d8+b6416ef8fe43 | `matches/sh1-vhome-cc1-A10204` |
| 4 | Comet Catcher Remake 1.8 | Armada | 10205 | 0 | w | 30.0 | x0.88 | ?, d32b7b84d8+b6416ef8fe43 | `matches/sh1-vhome-cc1-A10205` |
| 5 | Comet Catcher Remake 1.8 | Armada | 10206 | 0 | W | 29.34 | x2.19 | ?, d32b7b84d8+b6416ef8fe43 | `matches/sh1-vhome-cc1-A10206` |
| 6 | Comet Catcher Remake 1.8 | Armada | 10207 | 0 | w | 30.0 | x1.71 | ?, d32b7b84d8+b6416ef8fe43 | `matches/sh1-vhome-cc1-A10207` |
| 7 | Comet Catcher Remake 1.8 | Armada | 10208 | 0 | W | 25.05 | x3.20 | ?, d32b7b84d8+b6416ef8fe43 | `matches/sh1-vhome-cc1-A10208` |
| 8 | Comet Catcher Remake 1.8 | Armada | 10209 | 0 | w | 30.0 | x1.50 | ?, d32b7b84d8+b6416ef8fe43 | `matches/sh1-vhome-cc1-A10209` |
| 9 | Comet Catcher Remake 1.8 | Armada | 10210 | 0 | w | 30.0 | x2.16 | ?, d32b7b84d8+b6416ef8fe43 | `matches/sh1-vhome-cc1-A10210` |
| 10 | Comet Catcher Remake 1.8 | Cortex | 10201 | 0 | w | 30.0 | x2.55 | ?, d32b7b84d8+b6416ef8fe43 | `matches/sh1-vhome-cc1-C10201` |
| 11 | Comet Catcher Remake 1.8 | Cortex | 10202 | 0 | W | 24.43 | x2.76 | ?, d32b7b84d8+b6416ef8fe43 | `matches/sh1-vhome-cc1-C10202` |
| 12 | Comet Catcher Remake 1.8 | Cortex | 10203 | 0 | w | 30.0 | x1.17 | ?, d32b7b84d8+b6416ef8fe43 | `matches/sh1-vhome-cc1-C10203` |
| 13 | Comet Catcher Remake 1.8 | Cortex | 10204 | 0 | w | 30.0 | x1.21 | ?, d32b7b84d8+b6416ef8fe43 | `matches/sh1-vhome-cc1-C10204` |
| 14 | Comet Catcher Remake 1.8 | Cortex | 10205 | 0 | w | 30.0 | x2.24 | ?, d32b7b84d8+b6416ef8fe43 | `matches/sh1-vhome-cc1-C10205` |
| 15 | Comet Catcher Remake 1.8 | Cortex | 10206 | 0 | w | 30.0 | x2.44 | ?, d32b7b84d8+b6416ef8fe43 | `matches/sh1-vhome-cc1-C10206` |
| 16 | Comet Catcher Remake 1.8 | Cortex | 10207 | 0 | w | 30.0 | x1.01 | ?, d32b7b84d8+b6416ef8fe43 | `matches/sh1-vhome-cc1-C10207` |
| 17 | Comet Catcher Remake 1.8 | Cortex | 10208 | 0 | w | 30.0 | x2.15 | ?, d32b7b84d8+b6416ef8fe43 | `matches/sh1-vhome-cc1-C10208` |
| 18 | Comet Catcher Remake 1.8 | Cortex | 10209 | 0 | W | 25.12 | x6.96 | ?, d32b7b84d8+b6416ef8fe43 | `matches/sh1-vhome-cc1-C10209` |
| 19 | Comet Catcher Remake 1.8 | Cortex | 10210 | 0 | w | 30.0 | x1.66 | ?, d32b7b84d8+b6416ef8fe43 | `matches/sh1-vhome-cc1-C10210` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.58 | 16.27 | - | ok |
| t2->4th moho (min) | 5.00 | 16.27 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.21 | - | 0.00 | n/a |
| adv plant frame x | 3.42 | - | 1.50 | n/a |
| near-done /10k built | 0.64 | 0.00 | 0.00 | FAIL (worse than release, 100% of resamples) |
| t2 cons given early | 0.00 | 0.00 | 0.00 | ok |
| supers before 4 moho | 1.25 | 0.00 | 0.00 | FAIL (worse than release, 100% of resamples) |
| lone t2 con minutes | 0.20 | 0.00 | 0.00 | ok, short of aim |
| base lost while 'covered' k | 1.73 | - | 0.00 | n/a |
| oldest plant order min | 2.30 | - | - | n/a |
| no t2 by minute 20 | 0.00 | 0.05 | - | ok |
| frozen minutes | 0.00 | 0.00 | 0.00 | ok |
| com minutes on their half | 0.45 | 0.00 | - | ok |
| com lost on their half | 0.00 | 0.00 | 0.00 | ok |
| mex lost to ticks by 10 min | 1.85 | 0.15 | 0.00 | FAIL (worse than release, 99% of resamples) |
| their mex killed /10min (neg) | -12.92 | -32.20 | - | FAIL (worse than release, 100% of resamples) |
| their army / ours, 8-12 min | 0.93 | - | - | n/a |
| lost per killed | 1.59 | 1.09 | - | worse, within noise (76% of resamples) |
| reclaimed / killed (neg) | -0.17 | -0.09 | - | ok |
| bare-hands minutes | 0.00 | 0.00 | 0.00 | ok |
| wiped bomber runs | 0.34 | - | 0.00 | n/a |
| runs turned back | 0.00 | - | 0.00 | n/a |
| gunships sent to lose | 0.00 | - | 0.00 | n/a |
| stacked radar/jammers | 0.10 | - | 0.00 | n/a |
| army stuck /10min/1k army | 2.93 | 0.00 | 0.00 | FAIL (worse than release, 100% of resamples) |
| ground given up share | 0.28 | - | 0.00 | n/a |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.69 | -1.98 | - | FAIL (worse than release, 92% of resamples) |
| army share (neg) | 0.36 | 0.32 | - | ok |
| -log income at 20 | -5.62 | -4.94 | - | ok |
| games won or ahead | 0.95 | 0.50 | - | ok |

Contract: **FAIL (6)** over 20 games (20 of our seats, 20 release seats); 6 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.16 (run `python tools/anomaly.py build`)
```

**Correction (11-18, fresh review):** the change tested here was dead code. The leak-screen term (at most 1) never beats the guard floor (MexGunsWanted >= 1), so it changed no price; the Ticks difference above is seed noise. Removed before v0.5.17; see issues/ticks-flank-extractors.md.
