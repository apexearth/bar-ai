<!-- meta {"date": "2026-11-16", "topic": "stuck-push", "title": "wreck_push: travel lean 1 vs 2 (in-contact lean)", "games": 6, "W": 0, "L": 0, "w": 0, "l": 0, "inc20": null, "verdict": "lean=2 better in all 3 pairs, small sample. lean=1: stuck nudges 0/3/12, all killed 33.0/43.3/77.9 s, travel orders 44/64/129 (+ring 264, attack 132 in the stalled run). lean=2: stuck 0/0/0, all killed 32.4/32.7/33.0 s, travel orders 52/41/30. Next: more scenario repeats, then 3-4 full games per army.md."} -->
# wreck_push: travel lean 1 vs 2 (in-contact lean)

- **Date:** 2026-11-16
- **Topic:** stuck-push
- **Purpose:** Row 113, his 11-15: pushes stall in wreck fields under constant move orders; 'move further up and maybe stop giving quite so many move orders'. Scenario: 12 armwar push through 64 armwar wrecks onto 8 Pawns + an LLT holding. Runs alternate apex_travel_lean=1 (release) and =2 (lean in contact too), lane stockf, Unstable + the FightAction/MoveAction change.
- **Result:** 6 games: won 0, lost 0, timeouts ahead 0, behind 0
- **Verdict:** lean=2 better in all 3 pairs, small sample. lean=1: stuck nudges 0/3/12, all killed 33.0/43.3/77.9 s, travel orders 44/64/129 (+ring 264, attack 132 in the stalled run). lean=2: stuck 0/0/0, all killed 32.4/32.7/33.0 s, travel orders 52/41/30. Next: more scenario repeats, then 3-4 full games per army.md.
- **Ours:** Apexstockf-lane-stockf-standard
- **Opponents:** BARb-stable-hard
- **Code:** Apexstockf-lane-stockf-standard = `363c70a0a5+5a24d1c035be` (6 games); BARb-stable-hard = `?` (6 games); NullAI-0.1 = `?` (6 games)
- **Maps:** Geyser Plains BAR v1.2.1
- **Sides:** Armada; **bonus:** 0; **time cap:** 4 min
- **Runs:** matches/scenario-dev/20261116-001831-wreck_push, matches/scenario-dev/20261116-001925-wreck_push, matches/scenario-dev/20261116-002008-wreck_push, matches/scenario-dev/20261116-002051-wreck_push, matches/scenario-dev/20261116-002132-wreck_push, matches/scenario-dev/20261116-002215-wreck_push
- **Command (first game):** `run_match.py --a Apexstockf:lane-stockf:standard --b BARb:stable:hard --map Geyser Plains --minutes 4 --speed 20 --sides Armada,Armada --out C:\Users\apexe\WebstormProjects\bar-ai\matches\scenario-dev\20261116-001831-wreck_push --write-dir C:\Users\apexe\WebstormProjects\bar-ai\matches\scenario-dev\_engine-0 --timeout 420 --modoption dev_scenario=wreck_push --modoption dev_scenario_units=0:armwar:12:c:-1000:0:48:ai|1:armpw:8:c:250:0:56:hold|1:armllt:1:c:350:0:48:hold --modoption dev_scenario_spawn=90 --modoption dev_scenario_len=150 --modoption dev_scenario_coms=remove --modoption dev_scenario_los=global --modoption dev_maxgameminutes=2.5833 --modoption debugcommands=4740:quitforce --modoption dev_scenario_wrecks=armwar:64:c:-350:0:56 --modoption deathmode=neverend --extra-ai NullAI:0.1@1 --ai-option apex_travel_lean=1`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Geyser Plains BAR v1.2.1 | Armada | None | 0 | - | 2.58 | - | 363c70a0a5+5a24d1c035be, ? | `matches/scenario-dev/20261116-001831-wreck_push` |
| 1 | Geyser Plains BAR v1.2.1 | Armada | None | 0 | - | 2.58 | - | 363c70a0a5+5a24d1c035be, ? | `matches/scenario-dev/20261116-001925-wreck_push` |
| 2 | Geyser Plains BAR v1.2.1 | Armada | None | 0 | - | 2.58 | - | 363c70a0a5+5a24d1c035be, ? | `matches/scenario-dev/20261116-002008-wreck_push` |
| 3 | Geyser Plains BAR v1.2.1 | Armada | None | 0 | - | 2.58 | - | 363c70a0a5+5a24d1c035be, ? | `matches/scenario-dev/20261116-002051-wreck_push` |
| 4 | Geyser Plains BAR v1.2.1 | Armada | None | 0 | - | 2.58 | - | 363c70a0a5+5a24d1c035be, ? | `matches/scenario-dev/20261116-002132-wreck_push` |
| 5 | Geyser Plains BAR v1.2.1 | Armada | None | 0 | - | 2.58 | - | 363c70a0a5+5a24d1c035be, ? | `matches/scenario-dev/20261116-002215-wreck_push` |

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
| army stuck per 10 min | - | - | 0.00 | n/a |
| ground given up share | - | - | 0.00 | n/a |
| anomalous seats | - | - | 0.00 | n/a |
| log peak cons per income | - | - | - | n/a |
| army share (neg) | 1.00 | 1.08 | - | FAIL (worse than release) |
| -log income at 20 | - | - | - | n/a |
| games won or ahead | 1.00 | 0.50 | - | ok |

Contract: **FAIL (1)** over 6 games (6 of our seats, 12 release seats); 0 check(s) short of his aim.

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.13 (run `python tools/anomaly.py build`)
```
