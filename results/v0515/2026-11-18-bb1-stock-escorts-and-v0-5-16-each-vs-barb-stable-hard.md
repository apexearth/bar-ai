<!-- meta {"date": "2026-11-18", "topic": "v0515", "title": "bb1: stock escorts and v0.5.16 each vs BARb stable hard", "games": 40, "W": 13, "L": 0, "w": 22, "l": 5, "inc20": 1.55, "verdict": "New won/ahead 19 of 20 (8 wins), v0.5.16 18 of 20 (5 wins); income@20 med 251 vs 228; kill-lost better in 11 of 20 pairs (t=0.30). Contract FAIL: extractors lost to Ticks/scout cars by 10 min 3.1 vs 1.0 (96% of resamples), all in the Armada mirror, minutes 7-10 (36 vs 6): raiders leave home to raid. Net extractor exchange equal again by minute 15."} -->
# bb1: stock escorts and v0.5.16 each vs BARb stable hard

- **Date:** 2026-11-18
- **Topic:** v0515
- **Purpose:** Release gate BARb leg: new and v0.5.16 each vs BARb:stable:hard on seeds 10201-10210, both factions, Comet Catcher 1v1, +50 both
- **Result:** 40 games: won 13, lost 0, timeouts ahead 22, behind 5; income at 20 min x1.55 ours/theirs
- **Verdict:** New won/ahead 19 of 20 (8 wins), v0.5.16 18 of 20 (5 wins); income@20 med 251 vs 228; kill-lost better in 11 of 20 pairs (t=0.30). Contract FAIL: extractors lost to Ticks/scout cars by 10 min 3.1 vs 1.0 (96% of resamples), all in the Armada mirror, minutes 7-10 (36 vs 6): raiders leave home to raid. Net extractor exchange equal again by minute 15.
- **Ours:** Apex-v0.5.16-standard, Apexestall-lane-estall-standard
- **Opponents:** BARb-stable-hard
- **Code:** Apex-v0.5.16-standard = `c52cd47708` (20 games); Apexestall-lane-estall-standard = `eb84c59728+8dcd91d7ffdb` (20 games); BARb-stable-hard = `?` (40 games)
- **Maps:** Comet Catcher Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 30 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b BARb:stable:hard --per-side 1 --map Comet Catcher Remake 1.8 --minutes 30 --speed 20 --handicap 50 --sides Armada,Armada --seed 10201 --out matches/bb1-vnew-cc1-A10201`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 10201 | 0 | w | 30.0 | x1.05 | ?, eb84c59728+8dcd91d7ffdb | `matches/bb1-vnew-cc1-A10201` |
| 1 | Comet Catcher Remake 1.8 | Armada | 10202 | 0 | w | 30.0 | x1.21 | ?, eb84c59728+8dcd91d7ffdb | `matches/bb1-vnew-cc1-A10202` |
| 2 | Comet Catcher Remake 1.8 | Armada | 10203 | 0 | W | 15.9 | - | ?, eb84c59728+8dcd91d7ffdb | `matches/bb1-vnew-cc1-A10203` |
| 3 | Comet Catcher Remake 1.8 | Armada | 10204 | 0 | w | 30.0 | x1.05 | ?, eb84c59728+8dcd91d7ffdb | `matches/bb1-vnew-cc1-A10204` |
| 4 | Comet Catcher Remake 1.8 | Armada | 10205 | 0 | l | 30.0 | x0.76 | ?, eb84c59728+8dcd91d7ffdb | `matches/bb1-vnew-cc1-A10205` |
| 5 | Comet Catcher Remake 1.8 | Armada | 10206 | 0 | W | 29.38 | x3.49 | ?, eb84c59728+8dcd91d7ffdb | `matches/bb1-vnew-cc1-A10206` |
| 6 | Comet Catcher Remake 1.8 | Armada | 10207 | 0 | w | 30.0 | x2.15 | ?, eb84c59728+8dcd91d7ffdb | `matches/bb1-vnew-cc1-A10207` |
| 7 | Comet Catcher Remake 1.8 | Armada | 10208 | 0 | W | 27.51 | x2.05 | ?, eb84c59728+8dcd91d7ffdb | `matches/bb1-vnew-cc1-A10208` |
| 8 | Comet Catcher Remake 1.8 | Armada | 10209 | 0 | W | 28.21 | x2.70 | ?, eb84c59728+8dcd91d7ffdb | `matches/bb1-vnew-cc1-A10209` |
| 9 | Comet Catcher Remake 1.8 | Armada | 10210 | 0 | w | 30.0 | x1.30 | ?, eb84c59728+8dcd91d7ffdb | `matches/bb1-vnew-cc1-A10210` |
| 10 | Comet Catcher Remake 1.8 | Cortex | 10201 | 0 | w | 30.0 | x1.13 | ?, eb84c59728+8dcd91d7ffdb | `matches/bb1-vnew-cc1-C10201` |
| 11 | Comet Catcher Remake 1.8 | Cortex | 10202 | 0 | W | 26.0 | x3.59 | ?, eb84c59728+8dcd91d7ffdb | `matches/bb1-vnew-cc1-C10202` |
| 12 | Comet Catcher Remake 1.8 | Cortex | 10203 | 0 | w | 30.0 | x1.21 | ?, eb84c59728+8dcd91d7ffdb | `matches/bb1-vnew-cc1-C10203` |
| 13 | Comet Catcher Remake 1.8 | Cortex | 10204 | 0 | W | 26.46 | x1.60 | ?, eb84c59728+8dcd91d7ffdb | `matches/bb1-vnew-cc1-C10204` |
| 14 | Comet Catcher Remake 1.8 | Cortex | 10205 | 0 | W | 17.6 | - | ?, eb84c59728+8dcd91d7ffdb | `matches/bb1-vnew-cc1-C10205` |
| 15 | Comet Catcher Remake 1.8 | Cortex | 10206 | 0 | w | 30.0 | x0.80 | ?, eb84c59728+8dcd91d7ffdb | `matches/bb1-vnew-cc1-C10206` |
| 16 | Comet Catcher Remake 1.8 | Cortex | 10207 | 0 | w | 30.0 | x1.14 | ?, eb84c59728+8dcd91d7ffdb | `matches/bb1-vnew-cc1-C10207` |
| 17 | Comet Catcher Remake 1.8 | Cortex | 10208 | 0 | w | 30.0 | x3.15 | ?, eb84c59728+8dcd91d7ffdb | `matches/bb1-vnew-cc1-C10208` |
| 18 | Comet Catcher Remake 1.8 | Cortex | 10209 | 0 | l | 30.0 | x0.58 | ?, eb84c59728+8dcd91d7ffdb | `matches/bb1-vnew-cc1-C10209` |
| 19 | Comet Catcher Remake 1.8 | Cortex | 10210 | 0 | W | 27.93 | x2.58 | ?, eb84c59728+8dcd91d7ffdb | `matches/bb1-vnew-cc1-C10210` |
| 20 | Comet Catcher Remake 1.8 | Armada | 10201 | 0 | W | 29.38 | x3.35 | ?, c52cd47708 | `matches/bb1-vrel-cc1-A10201` |
| 21 | Comet Catcher Remake 1.8 | Armada | 10202 | 0 | W | 23.84 | x2.57 | ?, c52cd47708 | `matches/bb1-vrel-cc1-A10202` |
| 22 | Comet Catcher Remake 1.8 | Armada | 10203 | 0 | w | 30.0 | x1.00 | ?, c52cd47708 | `matches/bb1-vrel-cc1-A10203` |
| 23 | Comet Catcher Remake 1.8 | Armada | 10204 | 0 | W | 18.38 | - | ?, c52cd47708 | `matches/bb1-vrel-cc1-A10204` |
| 24 | Comet Catcher Remake 1.8 | Armada | 10205 | 0 | w | 30.0 | x2.25 | ?, c52cd47708 | `matches/bb1-vrel-cc1-A10205` |
| 25 | Comet Catcher Remake 1.8 | Armada | 10206 | 0 | l | 30.0 | x1.15 | ?, c52cd47708 | `matches/bb1-vrel-cc1-A10206` |
| 26 | Comet Catcher Remake 1.8 | Armada | 10207 | 0 | W | 28.63 | x3.13 | ?, c52cd47708 | `matches/bb1-vrel-cc1-A10207` |
| 27 | Comet Catcher Remake 1.8 | Armada | 10208 | 0 | W | 25.48 | x3.95 | ?, c52cd47708 | `matches/bb1-vrel-cc1-A10208` |
| 28 | Comet Catcher Remake 1.8 | Armada | 10209 | 0 | w | 30.0 | x1.08 | ?, c52cd47708 | `matches/bb1-vrel-cc1-A10209` |
| 29 | Comet Catcher Remake 1.8 | Armada | 10210 | 0 | w | 30.0 | x0.90 | ?, c52cd47708 | `matches/bb1-vrel-cc1-A10210` |
| 30 | Comet Catcher Remake 1.8 | Cortex | 10201 | 0 | w | 30.0 | x2.11 | ?, c52cd47708 | `matches/bb1-vrel-cc1-C10201` |
| 31 | Comet Catcher Remake 1.8 | Cortex | 10202 | 0 | w | 30.0 | x3.77 | ?, c52cd47708 | `matches/bb1-vrel-cc1-C10202` |
| 32 | Comet Catcher Remake 1.8 | Cortex | 10203 | 0 | l | 30.0 | x0.73 | ?, c52cd47708 | `matches/bb1-vrel-cc1-C10203` |
| 33 | Comet Catcher Remake 1.8 | Cortex | 10204 | 0 | w | 30.0 | x0.84 | ?, c52cd47708 | `matches/bb1-vrel-cc1-C10204` |
| 34 | Comet Catcher Remake 1.8 | Cortex | 10205 | 0 | w | 30.0 | x2.10 | ?, c52cd47708 | `matches/bb1-vrel-cc1-C10205` |
| 35 | Comet Catcher Remake 1.8 | Cortex | 10206 | 0 | w | 30.0 | x2.64 | ?, c52cd47708 | `matches/bb1-vrel-cc1-C10206` |
| 36 | Comet Catcher Remake 1.8 | Cortex | 10207 | 0 | w | 30.0 | x0.89 | ?, c52cd47708 | `matches/bb1-vrel-cc1-C10207` |
| 37 | Comet Catcher Remake 1.8 | Cortex | 10208 | 0 | l | 30.0 | x0.57 | ?, c52cd47708 | `matches/bb1-vrel-cc1-C10208` |
| 38 | Comet Catcher Remake 1.8 | Cortex | 10209 | 0 | w | 30.0 | x1.53 | ?, c52cd47708 | `matches/bb1-vrel-cc1-C10209` |
| 39 | Comet Catcher Remake 1.8 | Cortex | 10210 | 0 | w | 30.0 | x1.06 | ?, c52cd47708 | `matches/bb1-vrel-cc1-C10210` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.95 | 14.11 | - | ok |
| t2->4th moho (min) | 4.85 | 14.11 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.22 | 0.25 | 0.00 | ok, short of aim |
| adv plant frame x | 3.10 | 2.55 | 1.50 | worse, within noise (56% of resamples) |
| near-done /10k built | 0.68 | 0.20 | 0.00 | FAIL (worse than release, 100% of resamples) |
| t2 cons given early | 0.00 | 0.00 | 0.00 | ok |
| supers before 4 moho | 1.05 | 0.38 | 0.00 | worse, within noise (74% of resamples) |
| lone t2 con minutes | 0.50 | 0.10 | 0.00 | ok, short of aim |
| base lost while 'covered' k | 0.80 | 2.71 | 0.00 | ok, short of aim |
| oldest plant order min | 2.38 | 2.60 | - | ok |
| no t2 by minute 20 | 0.00 | 0.00 | - | ok |
| frozen minutes | 0.00 | 0.00 | 0.00 | ok |
| com minutes on their half | 0.60 | 0.09 | - | worse, within noise (47% of resamples) |
| com lost on their half | 0.00 | 0.00 | 0.00 | ok |
| mex lost to ticks by 10 min | 3.10 | 0.40 | 0.00 | FAIL (worse than release, 100% of resamples) |
| their mex killed /10min (neg) | -11.83 | -24.67 | - | FAIL (worse than release, 100% of resamples) |
| their army / ours, 8-12 min | 0.82 | 0.86 | - | ok |
| lost per killed | 1.46 | 1.44 | - | ok |
| reclaimed / killed (neg) | -0.15 | -0.10 | - | ok |
| bare-hands minutes | 0.00 | 0.07 | 0.00 | ok |
| wiped bomber runs | 0.34 | 0.36 | 0.00 | ok, short of aim |
| runs turned back | 0.00 | 0.05 | 0.00 | ok |
| gunships sent to lose | 0.00 | 0.00 | 0.00 | ok |
| stacked radar/jammers | 0.00 | 0.00 | 0.00 | ok |
| army stuck /10min/1k army | 3.18 | 0.00 | 0.00 | FAIL (worse than release, 100% of resamples) |
| ground given up share | 0.28 | 0.32 | 0.00 | ok, short of aim |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.68 | -1.93 | - | FAIL (worse than release, 91% of resamples) |
| army share (neg) | 0.36 | 0.34 | - | ok |
| -log income at 20 | -5.52 | -5.28 | - | ok |
| games won or ahead | 0.47 | 0.50 | - | FAIL (does not beat the release) |

Contract: **FAIL (6)** over 40 games (20 of our seats, 60 release seats); 11 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.16 (run `python tools/anomaly.py build`)
```
