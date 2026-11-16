<!-- meta {"date": "2026-11-16", "topic": "lrpc", "title": "lrpc_melee + lrpc_army after review 2: director holds guns, own-fire guard", "games": 6, "W": 0, "L": 0, "w": 0, "l": 0, "inc20": null, "verdict": "lrpc_army (on): 4 and 12 Hammers killed (was 10/6/12/15). lrpc_melee: Warriors lost 12 and 7 with the battery on, 12 and 12 off; Hammers all dead in 62/45 s on, 82/70 s off. No sign of own fire. 2+2 runs: direction."} -->
# lrpc_melee + lrpc_army after review 2: director holds guns, own-fire guard

- **Date:** 2026-11-16
- **Topic:** lrpc
- **Purpose:** Review 11-16 #2: the director bypassed the C++ aim's own-fire guard and silenced guns it did not hold. Now a held gun is scriptFree (CSuperTask steps aside only for it), targets with our metal within 1.25x splash are skipped, and guns are handed back on switch/release. New scenario lrpc_melee: 12 of our Warriors hold 900 out, 16 Hammers fight through them.
- **Result:** 6 games: won 0, lost 0, timeouts ahead 0, behind 0
- **Verdict:** lrpc_army (on): 4 and 12 Hammers killed (was 10/6/12/15). lrpc_melee: Warriors lost 12 and 7 with the battery on, 12 and 12 off; Hammers all dead in 62/45 s on, 82/70 s off. No sign of own fire. 2+2 runs: direction.
- **Ours:** Apexestall-lane-estall-standard
- **Opponents:** BARb-stable-hard
- **Code:** Apexestall-lane-estall-standard = `363c70a0a5+c487dbeb848d` (6 games); BARb-stable-hard = `?` (6 games); NullAI-0.1 = `?` (6 games)
- **Maps:** Geyser Plains BAR v1.2.1
- **Sides:** Armada; **bonus:** 0; **time cap:** 4 min
- **Runs:** matches/scenario-dev/20261116-065747-lrpc_army, matches/scenario-dev/20261116-065749-lrpc_melee, matches/scenario-dev/20261116-065821-lrpc_army, matches/scenario-dev/20261116-065823-lrpc_melee, matches/scenario-dev/20261116-065855-lrpc_melee, matches/scenario-dev/20261116-065926-lrpc_melee
- **Command (first game):** `run_match.py --a Apexestall:lane-estall:standard --b BARb:stable:hard --map Geyser Plains --minutes 4 --speed 20 --sides Armada,Armada --out C:\Users\apexe\WebstormProjects\bar-ai\matches\scenario-dev\20261116-065747-lrpc_army --write-dir C:\Users\apexe\WebstormProjects\bar-ai\matches\scenario-dev\_engine-0 --timeout 420 --modoption dev_scenario=lrpc_army --modoption dev_scenario_units=0:armbrtha:4:s0:0:0:120:ai|1:armfus:8:s1:0:0:110:ai|1:armmex:16:s1:-400:0:120:ai|1:armham:16:c:300:0:48:fight:s0:0:0 --modoption dev_scenario_spawn=90 --modoption dev_scenario_len=150 --modoption dev_scenario_coms=remove --modoption dev_scenario_los=global --modoption dev_maxgameminutes=2.5833 --modoption debugcommands=4740:quitforce --modoption deathmode=neverend --extra-ai NullAI:0.1@1 --ai-option apex_lrpc_focus=1`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Geyser Plains BAR v1.2.1 | Armada | None | 0 | - | 2.58 | - | 363c70a0a5+c487dbeb848d, ? | `matches/scenario-dev/20261116-065747-lrpc_army` |
| 1 | Geyser Plains BAR v1.2.1 | Armada | None | 0 | - | 2.58 | - | 363c70a0a5+c487dbeb848d, ? | `matches/scenario-dev/20261116-065821-lrpc_army` |
| 2 | Geyser Plains BAR v1.2.1 | Armada | None | 0 | - | 2.58 | - | 363c70a0a5+c487dbeb848d, ? | `matches/scenario-dev/20261116-065749-lrpc_melee` |
| 3 | Geyser Plains BAR v1.2.1 | Armada | None | 0 | - | 2.58 | - | 363c70a0a5+c487dbeb848d, ? | `matches/scenario-dev/20261116-065823-lrpc_melee` |
| 4 | Geyser Plains BAR v1.2.1 | Armada | None | 0 | - | 2.58 | - | 363c70a0a5+c487dbeb848d, ? | `matches/scenario-dev/20261116-065855-lrpc_melee` |
| 5 | Geyser Plains BAR v1.2.1 | Armada | None | 0 | - | 2.58 | - | 363c70a0a5+c487dbeb848d, ? | `matches/scenario-dev/20261116-065926-lrpc_melee` |

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

Contract: **FAIL (2)** over 6 games (10 of our seats, 12 release seats); 0 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomalies: 0 seat(s) of 0 outside 5 robust deviations of v0.5.13's normal; 10 seat(s) skipped, no normal yet for hc0-x1-?-1v1@Geyser Plains BAR, hc0-x1-A-1v1@Geyser Plains BAR
```
