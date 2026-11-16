<!-- meta {"date": "2026-11-16", "topic": "v0514", "title": "na8: Unstable vs v0.5.13, no air, no nukes (8 games)", "games": 8, "W": 3, "L": 1, "w": 2, "l": 2, "inc20": 1.07, "verdict": "Decided 3-1, at time ahead 2 behind 2; won or ahead 0.62 vs 0.50; income at 20 x1.07. Contract FAIL (1): near-done strips 14.9 vs 7.8; the trim rule is unchanged since v0.5.12 and near-done is the same share of all trims (0.21 vs 0.20): ours ran 1113 trims to 631 on 26% more metal built. Adv plant frame x first read 2.69 vs 1.86, all from three first plants whose decision logged no price (both AIs ~1 in 5, the 10 s floor read them 16-24x); contract.py now skips an unpriced plant: 2.04 vs 1.86. Stacked radar/jammers 0.12 vs 0.81. 8 games: direction only."} -->
# na8: Unstable vs v0.5.13, no air, no nukes (8 games)

- **Date:** 2026-11-16
- **Topic:** v0514
- **Purpose:** Unstable after the 11-16 review fixes: pure-sensor spacing (row 112), LRPC army value capped at its own metal and a 3 s look while an army is the focus (115), lean 2 only for ground units on an attack (113), arrival high-water mark (109), with the constructor blob fix (111/116). +50, both factions, the h13 seeds. No air, no nukes, 40 min.
- **Result:** 8 games: won 3, lost 1, timeouts ahead 2, behind 2; income at 20 min x1.07 ours/theirs
- **Verdict:** Decided 3-1, at time ahead 2 behind 2; won or ahead 0.62 vs 0.50; income at 20 x1.07. Contract FAIL (1): near-done strips 14.9 vs 7.8; the trim rule is unchanged since v0.5.12 and near-done is the same share of all trims (0.21 vs 0.20): ours ran 1113 trims to 631 on 26% more metal built. Adv plant frame x first read 2.69 vs 1.86, all from three first plants whose decision logged no price (both AIs ~1 in 5, the 10 s floor read them 16-24x); contract.py now skips an unpriced plant: 2.04 vs 1.86. Stacked radar/jammers 0.12 vs 0.81. 8 games: direction only.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** Apex-v0.5.13-standard
- **Code:** Apex-v0.5.13-standard = `b836bd8247+2f2ca832cead` (8 games); Apexestall-lane-estall-standard = `363c70a0a5+cf493e59b8f4` (8 games)
- **Maps:** Carrot Mountains v2.0, Red Comet Remake 1.8
- **Sides:** Armada, Cortex; **bonus:** 50; **time cap:** 40 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b Apex:v0.5.13:standard --per-side 2 --map Carrot Mountains v2.0 --minutes 40 --speed 20 --handicap 50 --sides Armada,Armada --seed 9602 --modoption unit_restrictions_noair=1 --modoption unit_restrictions_nonukes=1 --out matches/na8-v0-cm2-A9602`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Carrot Mountains v2.0 | Armada | 9602 | 0 | l | 40.0 | x0.63 | 363c70a0a5+cf493e59b8f4, b836bd8247+2f2ca832cead | `matches/na8-v0-cm2-A9602` |
| 1 | Carrot Mountains v2.0 | Armada | 9604 | 0 | W | 37.42 | x2.77 | 363c70a0a5+cf493e59b8f4, b836bd8247+2f2ca832cead | `matches/na8-v0-cm2-A9604` |
| 2 | Carrot Mountains v2.0 | Cortex | 9602 | 0 | w | 40.0 | x0.74 | 363c70a0a5+cf493e59b8f4, b836bd8247+2f2ca832cead | `matches/na8-v0-cm2-C9602` |
| 3 | Carrot Mountains v2.0 | Cortex | 9604 | 0 | w | 40.0 | x2.01 | 363c70a0a5+cf493e59b8f4, b836bd8247+2f2ca832cead | `matches/na8-v0-cm2-C9604` |
| 4 | Red Comet Remake 1.8 | Armada | 9601 | 0 | W | 26.2 | x1.87 | 363c70a0a5+cf493e59b8f4, b836bd8247+2f2ca832cead | `matches/na8-v0-rc2-A9601` |
| 5 | Red Comet Remake 1.8 | Armada | 9603 | 0 | L | 32.59 | x0.48 | 363c70a0a5+cf493e59b8f4, b836bd8247+2f2ca832cead | `matches/na8-v0-rc2-A9603` |
| 6 | Red Comet Remake 1.8 | Cortex | 9601 | 0 | l | 40.0 | x0.66 | 363c70a0a5+cf493e59b8f4, b836bd8247+2f2ca832cead | `matches/na8-v0-rc2-C9601` |
| 7 | Red Comet Remake 1.8 | Cortex | 9603 | 0 | W | 33.75 | x1.15 | 363c70a0a5+cf493e59b8f4, b836bd8247+2f2ca832cead | `matches/na8-v0-rc2-C9603` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.94 | 2.60 | - | ok |
| t2->4th moho (min) | 6.35 | 6.74 | 3.00 | ok, short of aim |
| lab-job leaves/job | 0.70 | 0.72 | 0.00 | ok, short of aim |
| adv plant frame x | 2.04 | 1.86 | 1.50 | ok, short of aim |
| near-done strips | 14.88 | 7.81 | 0.00 | FAIL (worse than release) |
| t2 cons given early | 0.12 | 0.12 | 0.00 | ok, short of aim |
| supers before 4 moho | 0.67 | 0.62 | 0.00 | ok, short of aim |
| lone t2 con minutes | 0.53 | 0.38 | 0.00 | ok, short of aim |
| base lost while 'covered' k | 8.20 | 7.99 | 0.00 | ok, short of aim |
| oldest plant order min | 2.74 | 3.19 | - | ok |
| no t2 by minute 20 | 0.06 | 0.00 | - | ok |
| frozen minutes | 0.38 | 0.88 | 0.00 | ok, short of aim |
| bare-hands minutes | 0.62 | 1.00 | 0.00 | ok, short of aim |
| wiped bomber runs | - | - | 0.00 | n/a |
| runs turned back | - | - | 0.00 | n/a |
| gunships sent to lose | - | - | 0.00 | n/a |
| stacked radar/jammers | 0.12 | 0.81 | 0.00 | ok, short of aim |
| army stuck /10min/1k army | 1.55 | 1.63 | 0.00 | ok, short of aim |
| ground given up share | 0.26 | - | 0.00 | n/a |
| anomalous seats | 0.06 | 0.12 | 0.00 | ok, short of aim |
| log peak cons per income | -1.53 | -1.62 | - | ok |
| army share (neg) | 0.42 | 0.44 | - | ok |
| -log income at 20 | -4.83 | -4.96 | - | ok |
| games won or ahead | 0.62 | 0.50 | - | ok |

Contract: **FAIL (1)** over 8 games (16 of our seats, 16 release seats); 13 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomalies: 1 seat(s) of 16 outside 5 robust deviations of v0.5.13's normal
  na8-v0-rc2-A9601 t1 lane-estall: 10m T2 share 30% (normal 0%, z +6)
```
