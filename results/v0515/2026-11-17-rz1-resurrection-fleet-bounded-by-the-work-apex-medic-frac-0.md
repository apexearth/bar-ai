<!-- meta {"date": "2026-11-17", "topic": "v0515", "title": "rz1: resurrection fleet bounded by the work (apex_medic_frac 0) vs 12% of army (0.12, release) vs WRDistilled 0.4, both +50, Armada, Comet Catcher 1v1, 12 seeds", "games": 24, "W": 1, "L": 15, "w": 6, "l": 2, "inc20": 0.67, "verdict": "Direction favours lifting the cap, not proven: won or ahead 4 (cap off) vs 3 (cap on) of 12 pairs; kill minus lost better with the cap off in 9 of 12 pairs (mean +7.8k metal, sign test p~0.15); lost per killed median 1.09 vs 1.64; mean kill 46.5k vs 36.3k, lost 50.1k vs 47.7k. Reclaim barely moved: reclaimed/killed 0.15 vs 0.13; mean fleet 4.5 vs 3.3 bots (peaks to 39 in both arms). The fleet is not what changed the trade much; WRDistilled's tanks still out-trade us at 1v1. Next: 12 more seeds (rz2) before the cap goes."} -->
# rz1: resurrection fleet bounded by the work (apex_medic_frac 0) vs 12% of army (0.12, release) vs WRDistilled 0.4, both +50, Armada, Comet Catcher 1v1, 12 seeds

- **Date:** 2026-11-17
- **Topic:** v0515
- **Purpose:** His 11-16 heavy-army strategy: a medium army behind strong defences they bleed into, resbots eat the reclaim, win on the trade. The fleet was capped at 12% of army value; this lifts the cap so the fleet is sized by the wreck and repair stream alone (still RezFleetCap 40).
- **Result:** 24 games: won 1, lost 15, timeouts ahead 6, behind 2; income at 20 min x0.67 ours/theirs
- **Verdict:** Direction favours lifting the cap, not proven: won or ahead 4 (cap off) vs 3 (cap on) of 12 pairs; kill minus lost better with the cap off in 9 of 12 pairs (mean +7.8k metal, sign test p~0.15); lost per killed median 1.09 vs 1.64; mean kill 46.5k vs 36.3k, lost 50.1k vs 47.7k. Reclaim barely moved: reclaimed/killed 0.15 vs 0.13; mean fleet 4.5 vs 3.3 bots (peaks to 39 in both arms). The fleet is not what changed the trade much; WRDistilled's tanks still out-trade us at 1v1. Next: 12 more seeds (rz2) before the cap goes.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** WRDistilled-0.4
- **Code:** Apexestall-lane-estall-standard = `6fc9a74aef+ed47322b3619` (24 games); WRDistilled-0.4 = `?` (24 games)
- **Maps:** Comet Catcher Remake 1.8
- **Sides:** Armada; **bonus:** 50; **time cap:** 25 min
- **Runs:** .
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b WRDistilled:0.4 --per-side 1 --map Comet Catcher Remake 1.8 --minutes 25 --speed 20 --handicap 50 --sides Armada,Armada --seed 9201 --ai-option apex_medic_frac=0.12 --out matches/rz1-v0.12-cc1-A9201`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Comet Catcher Remake 1.8 | Armada | 9201 | 0 | w | 25.0 | x1.55 | 6fc9a74aef+ed47322b3619, ? | `matches/rz1-v0.12-cc1-A9201` |
| 1 | Comet Catcher Remake 1.8 | Armada | 9202 | 0 | w | 25.0 | x1.22 | 6fc9a74aef+ed47322b3619, ? | `matches/rz1-v0.12-cc1-A9202` |
| 2 | Comet Catcher Remake 1.8 | Armada | 9203 | 0 | L | 20.53 | x0.14 | 6fc9a74aef+ed47322b3619, ? | `matches/rz1-v0.12-cc1-A9203` |
| 3 | Comet Catcher Remake 1.8 | Armada | 9204 | 0 | w | 25.0 | x1.00 | 6fc9a74aef+ed47322b3619, ? | `matches/rz1-v0.12-cc1-A9204` |
| 4 | Comet Catcher Remake 1.8 | Armada | 9205 | 0 | L | 19.39 | - | 6fc9a74aef+ed47322b3619, ? | `matches/rz1-v0.12-cc1-A9205` |
| 5 | Comet Catcher Remake 1.8 | Armada | 9206 | 0 | L | 20.83 | x0.01 | 6fc9a74aef+ed47322b3619, ? | `matches/rz1-v0.12-cc1-A9206` |
| 6 | Comet Catcher Remake 1.8 | Armada | 9207 | 0 | L | 22.49 | x1.09 | 6fc9a74aef+ed47322b3619, ? | `matches/rz1-v0.12-cc1-A9207` |
| 7 | Comet Catcher Remake 1.8 | Armada | 9208 | 0 | L | 22.82 | x0.31 | 6fc9a74aef+ed47322b3619, ? | `matches/rz1-v0.12-cc1-A9208` |
| 8 | Comet Catcher Remake 1.8 | Armada | 9209 | 0 | L | 16.71 | - | 6fc9a74aef+ed47322b3619, ? | `matches/rz1-v0.12-cc1-A9209` |
| 9 | Comet Catcher Remake 1.8 | Armada | 9210 | 0 | L | 19.38 | - | 6fc9a74aef+ed47322b3619, ? | `matches/rz1-v0.12-cc1-A9210` |
| 10 | Comet Catcher Remake 1.8 | Armada | 9211 | 0 | L | 18.38 | - | 6fc9a74aef+ed47322b3619, ? | `matches/rz1-v0.12-cc1-A9211` |
| 11 | Comet Catcher Remake 1.8 | Armada | 9212 | 0 | L | 17.28 | - | 6fc9a74aef+ed47322b3619, ? | `matches/rz1-v0.12-cc1-A9212` |
| 12 | Comet Catcher Remake 1.8 | Armada | 9201 | 0 | L | 22.43 | x1.39 | 6fc9a74aef+ed47322b3619, ? | `matches/rz1-v0-cc1-A9201` |
| 13 | Comet Catcher Remake 1.8 | Armada | 9202 | 0 | W | 24.33 | x1.96 | 6fc9a74aef+ed47322b3619, ? | `matches/rz1-v0-cc1-A9202` |
| 14 | Comet Catcher Remake 1.8 | Armada | 9203 | 0 | L | 23.04 | x0.07 | 6fc9a74aef+ed47322b3619, ? | `matches/rz1-v0-cc1-A9203` |
| 15 | Comet Catcher Remake 1.8 | Armada | 9204 | 0 | l | 25.0 | x0.72 | 6fc9a74aef+ed47322b3619, ? | `matches/rz1-v0-cc1-A9204` |
| 16 | Comet Catcher Remake 1.8 | Armada | 9205 | 0 | L | 15.75 | - | 6fc9a74aef+ed47322b3619, ? | `matches/rz1-v0-cc1-A9205` |
| 17 | Comet Catcher Remake 1.8 | Armada | 9206 | 0 | w | 25.0 | x1.58 | 6fc9a74aef+ed47322b3619, ? | `matches/rz1-v0-cc1-A9206` |
| 18 | Comet Catcher Remake 1.8 | Armada | 9207 | 0 | L | 17.49 | - | 6fc9a74aef+ed47322b3619, ? | `matches/rz1-v0-cc1-A9207` |
| 19 | Comet Catcher Remake 1.8 | Armada | 9208 | 0 | l | 25.0 | x1.60 | 6fc9a74aef+ed47322b3619, ? | `matches/rz1-v0-cc1-A9208` |
| 20 | Comet Catcher Remake 1.8 | Armada | 9209 | 0 | w | 25.0 | x1.06 | 6fc9a74aef+ed47322b3619, ? | `matches/rz1-v0-cc1-A9209` |
| 21 | Comet Catcher Remake 1.8 | Armada | 9210 | 0 | L | 21.41 | x2.16 | 6fc9a74aef+ed47322b3619, ? | `matches/rz1-v0-cc1-A9210` |
| 22 | Comet Catcher Remake 1.8 | Armada | 9211 | 0 | L | 17.11 | - | 6fc9a74aef+ed47322b3619, ? | `matches/rz1-v0-cc1-A9211` |
| 23 | Comet Catcher Remake 1.8 | Armada | 9212 | 0 | w | 25.0 | x2.05 | 6fc9a74aef+ed47322b3619, ? | `matches/rz1-v0-cc1-A9212` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | 2.79 | - | - | n/a |
| t2->4th moho (min) | 4.79 | - | 3.00 | n/a |
| lab-job leaves/job | 0.38 | - | 0.00 | n/a |
| adv plant frame x | 1.98 | - | 1.50 | n/a |
| near-done /10k built | 0.44 | 0.00 | 0.00 | FAIL (worse than release) |
| t2 cons given early | 0.00 | 0.00 | 0.00 | ok |
| supers before 4 moho | 0.57 | - | 0.00 | n/a |
| lone t2 con minutes | 0.26 | - | 0.00 | n/a |
| base lost while 'covered' k | 4.42 | - | 0.00 | n/a |
| oldest plant order min | 1.65 | - | - | n/a |
| no t2 by minute 20 | 0.00 | 1.00 | - | ok |
| frozen minutes | 0.00 | 0.00 | 0.00 | ok |
| raid answer army share | - | - | - | n/a |
| com minutes on their half | 0.25 | 0.00 | - | ok |
| com lost on their half | 0.08 | 0.00 | 0.00 | FAIL (worse than release) |
| mex lost to ticks by 10 min | 2.96 | 0.33 | 0.00 | FAIL (worse than release) |
| their mex killed /10min (neg) | -16.23 | -23.52 | - | FAIL (worse than release) |
| their army / ours, 8-12 min | 0.95 | - | - | n/a |
| lost per killed | 1.31 | 1.14 | - | FAIL (worse than release) |
| reclaimed / killed (neg) | -0.14 | -0.06 | - | ok |
| bare-hands minutes | 0.00 | 0.00 | 0.00 | ok |
| wiped bomber runs | 0.22 | - | 0.00 | n/a |
| runs turned back | 0.00 | - | 0.00 | n/a |
| gunships sent to lose | 0.00 | - | 0.00 | n/a |
| stacked radar/jammers | 0.00 | - | 0.00 | n/a |
| army stuck /10min/1k army | 3.97 | 0.00 | 0.00 | FAIL (worse than release) |
| ground given up share | 0.33 | - | 0.00 | n/a |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | -1.40 | -2.55 | - | FAIL (worse than release) |
| army share (neg) | 0.40 | 0.88 | - | FAIL (worse than release) |
| -log income at 20 | -5.25 | -5.03 | - | ok |
| games won or ahead | 0.29 | 0.50 | - | FAIL (does not beat the release) |

Contract: **FAIL (9)** over 24 games (24 of our seats, 24 release seats); 4 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.15 (run `python tools/anomaly.py build`)
```
