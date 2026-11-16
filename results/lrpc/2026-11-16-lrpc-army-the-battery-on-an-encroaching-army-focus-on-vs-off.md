<!-- meta {"date": "2026-11-16", "topic": "lrpc", "title": "lrpc_army: the battery on an encroaching army (focus on vs off)", "games": 4, "W": 0, "L": 0, "w": 0, "l": 0, "inc20": null, "verdict": "After the fix: focus on killed 5 and 12 of 16 Hammers, focus off 0 and 0 (fusions 8/8 both). The cannons still die: 16 Hammers vs 4 unescorted guns. 2+2 runs: direction, needs a long game."} -->
# lrpc_army: the battery on an encroaching army (focus on vs off)

- **Date:** 2026-11-16
- **Topic:** lrpc
- **Purpose:** Row 115, his 11-15 'if the enemy is encroaching, sick the lrpc on them'. 4 Berthas at our start, 8 fusions + 16 mexes of theirs in reach, 16 Hammers on a fight order from the centre to our start. First runs with focus on: 0 Hammers killed -- C++ CSuperTask::AimAtStructure re-pointed every gun at a building between the director's 10 s looks, and an army was priced at its own metal only. Fixed: SuperTask leaves non-stock supers to the director while apex_lrpc_focus is on; an army cell also counts our stake within its reach plus 10 s walk.
- **Result:** 4 games: won 0, lost 0, timeouts ahead 0, behind 0
- **Verdict:** After the fix: focus on killed 5 and 12 of 16 Hammers, focus off 0 and 0 (fusions 8/8 both). The cannons still die: 16 Hammers vs 4 unescorted guns. 2+2 runs: direction, needs a long game.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** BARb-stable-hard
- **Code:** Apexestall-lane-estall-standard = `363c70a0a5+3894ed90630e` (4 games); BARb-stable-hard = `?` (4 games); NullAI-0.1 = `?` (4 games)
- **Maps:** Geyser Plains BAR v1.2.1
- **Sides:** Armada; **bonus:** 0; **time cap:** 4 min
- **Runs:** matches/scenario-dev/20261116-045022-lrpc_army, matches/scenario-dev/20261116-045053-lrpc_army, matches/scenario-dev/20261116-045124-lrpc_army, matches/scenario-dev/20261116-045155-lrpc_army
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b BARb:stable:hard --map Geyser Plains --minutes 4 --speed 20 --sides Armada,Armada --out C:\Users\apexe\WebstormProjects\bar-ai\matches\scenario-dev\20261116-045022-lrpc_army --write-dir C:\Users\apexe\WebstormProjects\bar-ai\matches\scenario-dev\_engine-0 --timeout 420 --modoption dev_scenario=lrpc_army --modoption dev_scenario_units=0:armbrtha:4:s0:0:0:120:ai|1:armfus:8:s1:0:0:110:ai|1:armmex:16:s1:-400:0:120:ai|1:armham:16:c:300:0:48:fight:s0:0:0 --modoption dev_scenario_spawn=90 --modoption dev_scenario_len=150 --modoption dev_scenario_coms=remove --modoption dev_scenario_los=global --modoption dev_maxgameminutes=2.5833 --modoption debugcommands=4740:quitforce --modoption deathmode=neverend --extra-ai NullAI:0.1@1 --ai-option apex_lrpc_focus=1`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Geyser Plains BAR v1.2.1 | Armada | None | 0 | - | 2.58 | - | 363c70a0a5+3894ed90630e, ? | `matches/scenario-dev/20261116-045022-lrpc_army` |
| 1 | Geyser Plains BAR v1.2.1 | Armada | None | 0 | - | 2.58 | - | 363c70a0a5+3894ed90630e, ? | `matches/scenario-dev/20261116-045053-lrpc_army` |
| 2 | Geyser Plains BAR v1.2.1 | Armada | None | 0 | - | 2.58 | - | 363c70a0a5+3894ed90630e, ? | `matches/scenario-dev/20261116-045124-lrpc_army` |
| 3 | Geyser Plains BAR v1.2.1 | Armada | None | 0 | - | 2.58 | - | 363c70a0a5+3894ed90630e, ? | `matches/scenario-dev/20261116-045155-lrpc_army` |

## Behaviour contract

Ours against the release seats in these same games (`tools/contract.py`). FAIL = worse than the release past the noise margin.

| check | ours | release | his aim | verdict |
|---|---|---|---|---|
| t2->1st moho (min) | - | - | - | n/a |
| t2->4th moho (min) | - | - | 3.00 | n/a |
| lab-job leaves/job | - | - | 0.00 | n/a |
| adv plant frame x | - | - | 1.50 | n/a |
| near-done strips | 0.00 | 0.00 | 0.00 | ok |
| t2 cons given early | 0.00 | 0.00 | 0.00 | ok |
| supers before 4 moho | - | - | 0.00 | n/a |
| lone t2 con minutes | - | - | 0.00 | n/a |
| base lost while 'covered' k | 0.00 | - | 0.00 | n/a |
| oldest plant order min | - | - | - | n/a |
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
| log peak cons per income | - | - | - | n/a |
| army share (neg) | 0.13 | 0.55 | - | FAIL (worse than release) |
| -log income at 20 | - | - | - | n/a |
| games won or ahead | 0.00 | 0.50 | - | FAIL (does not beat the release) |

Contract: **FAIL (2)** over 4 games (4 of our seats, 8 release seats); 0 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.13 (run `python tools/anomaly.py build`)
```
