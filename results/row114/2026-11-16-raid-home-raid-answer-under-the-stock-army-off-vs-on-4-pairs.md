<!-- meta {"date": "2026-11-16", "topic": "row114", "title": "raid_home: raid answer under the stock army, off vs on (4 pairs)", "games": 8, "W": 0, "L": 0, "w": 0, "l": 0, "inc20": null, "verdict": "First build: the answer fired but C++ dropped the pull (leak=3 remove=3), so the Warriors never left stock's attack task. Fixed: a pulled unit is scriptFree before RemoveUnit. After: the answer goes out and ends clear every run, no leaks; losses 655/655/155/655 on vs 655/655/155/965 off (mean 530 vs 607): stock already kills all 10 Pawns here, so the scenario does not separate them. Games decide (ra1)."} -->
# raid_home: raid answer under the stock army, off vs on (4 pairs)

- **Date:** 2026-11-16
- **Topic:** row114
- **Purpose:** His 11-16 row 114 'test both first': 10 Pawns raid our lab, mexes and solars; 8 Warriors 600 out on stock control; apex_raid_answer_stock 0 vs 1.
- **Result:** 8 games: won 0, lost 0, timeouts ahead 0, behind 0
- **Verdict:** First build: the answer fired but C++ dropped the pull (leak=3 remove=3), so the Warriors never left stock's attack task. Fixed: a pulled unit is scriptFree before RemoveUnit. After: the answer goes out and ends clear every run, no leaks; losses 655/655/155/655 on vs 655/655/155/965 off (mean 530 vs 607): stock already kills all 10 Pawns here, so the scenario does not separate them. Games decide (ra1).
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** NullAI-0.1
- **Code:** Apexestall-lane-estall-standard = `6fc9a74aef+246f4b91b37d` (8 games); NullAI-0.1 = `?` (8 games)
- **Maps:** Geyser Plains BAR v1.2.1
- **Sides:** Armada; **bonus:** 0; **time cap:** 4 min
- **Runs:** matches/scenario-dev/20261116-105753-raid_home, matches/scenario-dev/20261116-105825-raid_home, matches/scenario-dev/20261116-105856-raid_home, matches/scenario-dev/20261116-105927-raid_home, matches/scenario-dev/20261116-105958-raid_home, matches/scenario-dev/20261116-110030-raid_home, matches/scenario-dev/20261116-110101-raid_home, matches/scenario-dev/20261116-110132-raid_home
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b NullAI:0.1 --map Geyser Plains --minutes 4 --speed 20 --sides Armada,Armada --out C:\Users\apexe\WebstormProjects\bar-ai\matches\scenario-dev\20261116-110132-raid_home --write-dir C:\Users\apexe\WebstormProjects\bar-ai\matches\scenario-dev\_engine-0 --timeout 420 --modoption dev_scenario=raid_home --modoption dev_scenario_units=0:armlab:1:s0:0:0:48:ai|0:armmex:4:s0:-200:150:120:ai|0:armsolar:6:s0:0:-250:90:ai|0:armwar:8:s0:-600:0:50:ai|1:armlab:1:s1:0:0:48:ai|1:armpw:10:s0:900:0:40:fight:s0:0:0 --modoption dev_scenario_spawn=90 --modoption dev_scenario_len=150 --modoption dev_scenario_coms=remove --modoption dev_scenario_los=global --modoption dev_maxgameminutes=2.5833 --modoption debugcommands=4740:quitforce --modoption deathmode=neverend --extra-ai NullAI:0.1@1 --seed 4 --ai-option apex_raid_answer_stock=1`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Geyser Plains BAR v1.2.1 | Armada | 4 | 0 | - | 2.58 | - | 6fc9a74aef+246f4b91b37d, ? | `matches/scenario-dev/20261116-110132-raid_home` |
| 1 | Geyser Plains BAR v1.2.1 | Armada | 4 | 0 | - | 2.58 | - | 6fc9a74aef+246f4b91b37d, ? | `matches/scenario-dev/20261116-110101-raid_home` |
| 2 | Geyser Plains BAR v1.2.1 | Armada | 3 | 0 | - | 2.58 | - | 6fc9a74aef+246f4b91b37d, ? | `matches/scenario-dev/20261116-110030-raid_home` |
| 3 | Geyser Plains BAR v1.2.1 | Armada | 3 | 0 | - | 2.58 | - | 6fc9a74aef+246f4b91b37d, ? | `matches/scenario-dev/20261116-105958-raid_home` |
| 4 | Geyser Plains BAR v1.2.1 | Armada | 2 | 0 | - | 2.58 | - | 6fc9a74aef+246f4b91b37d, ? | `matches/scenario-dev/20261116-105927-raid_home` |
| 5 | Geyser Plains BAR v1.2.1 | Armada | 2 | 0 | - | 2.58 | - | 6fc9a74aef+246f4b91b37d, ? | `matches/scenario-dev/20261116-105856-raid_home` |
| 6 | Geyser Plains BAR v1.2.1 | Armada | 1 | 0 | - | 2.58 | - | 6fc9a74aef+246f4b91b37d, ? | `matches/scenario-dev/20261116-105825-raid_home` |
| 7 | Geyser Plains BAR v1.2.1 | Armada | 1 | 0 | - | 2.58 | - | 6fc9a74aef+246f4b91b37d, ? | `matches/scenario-dev/20261116-105753-raid_home` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | - | - | - | n/a |
| t2->4th moho (min) | - | - | 3.00 | n/a |
| lab-job leaves/job | - | - | 0.00 | n/a |
| adv plant frame x | - | - | 1.50 | n/a |
| near-done /10k built | - | - | 0.00 | n/a |
| t2 cons given early | 0.00 | 0.00 | 0.00 | ok |
| supers before 4 moho | - | - | 0.00 | n/a |
| lone t2 con minutes | - | - | 0.00 | n/a |
| base lost while 'covered' k | 0.00 | - | 0.00 | n/a |
| oldest plant order min | 0.22 | - | - | n/a |
| no t2 by minute 20 | - | - | - | n/a |
| frozen minutes | 0.00 | 0.00 | 0.00 | ok |
| bare-hands minutes | 0.00 | 0.00 | 0.00 | ok |
| wiped bomber runs | - | - | 0.00 | n/a |
| runs turned back | - | - | 0.00 | n/a |
| gunships sent to lose | - | - | 0.00 | n/a |
| stacked radar/jammers | - | - | 0.00 | n/a |
| army stuck /10min/1k army | - | - | 0.00 | n/a |
| ground given up share | - | - | 0.00 | n/a |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | 0.99 | - | - | n/a |
| army share (neg) | 0.77 | 1.02 | - | FAIL (worse than release) |
| -log income at 20 | - | - | - | n/a |
| games won or ahead | 1.00 | 0.50 | - | ok |

Contract: **FAIL (1)** over 8 games (8 of our seats, 16 release seats); 0 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.14 (run `python tools/anomaly.py build`)
```
