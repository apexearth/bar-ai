<!-- meta {"date": "2026-11-16", "topic": "rebuild", "title": "rebuild_bare: one con on open ground, no lab (v0.5.14)", "games": 1, "W": 0, "L": 0, "w": 0, "l": 0, "inc20": null, "verdict": "Yes on open ground: extractors, a lab ordered at 2.5 min and standing at 4.2 min, its queue running, then nano and energy. The 11-14 shape (a 48-min priced walk, the order released every 30 s) did not occur. Recent frozen seats are bases under an enemy army (row 114)."} -->
# rebuild_bare: one con on open ground, no lab (v0.5.14)

- **Date:** 2026-11-16
- **Topic:** rebuild
- **Purpose:** His 11-14 'when we lose too much of our base we don't rebuild': does a seat left with one constructor on open, uncontested ground find a path back.
- **Result:** 1 games: won 0, lost 0, timeouts ahead 0, behind 0
- **Verdict:** Yes on open ground: extractors, a lab ordered at 2.5 min and standing at 4.2 min, its queue running, then nano and energy. The 11-14 shape (a 48-min priced walk, the order released every 30 s) did not occur. Recent frozen seats are bases under an enemy army (row 114).
- **Ours:** Apex-v0.5.14-standard
- **Opponents:** NullAI-0.1
- **Code:** Apex-v0.5.14-standard = `363c70a0a5+1bb8e5b07c76` (1 games); NullAI-0.1 = `?` (1 games)
- **Maps:** Geyser Plains BAR v1.2.1
- **Sides:** Armada; **bonus:** 0; **time cap:** 8 min
- **Runs:** matches/scenario-dev/20261116-094238-rebuild_bare
- **Command (first game):** `run_match.py --a Apex:v0.5.14:standard --b NullAI:0.1 --map Geyser Plains --minutes 8 --speed 20 --sides Armada,Armada --out C:\Users\apexe\WebstormProjects\bar-ai\matches\scenario-dev\20261116-094238-rebuild_bare --write-dir C:\Users\apexe\WebstormProjects\bar-ai\matches\scenario-dev\_engine-0 --timeout 420 --modoption dev_scenario=rebuild_bare --modoption dev_scenario_units=0:armck:1:s0:0:0:48:ai|0:armmex:2:s0:-250:0:140:ai|0:armsolar:2:s0:0:200:100:ai|1:armlab:1:s1:0:0:48:ai --modoption dev_scenario_spawn=90 --modoption dev_scenario_len=360 --modoption dev_scenario_coms=remove --modoption dev_scenario_los=global --modoption dev_maxgameminutes=6.0833 --modoption debugcommands=11040:quitforce --modoption deathmode=neverend`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Geyser Plains BAR v1.2.1 | Armada | None | 0 | - | 6.08 | - | 363c70a0a5+1bb8e5b07c76, ? | `matches/scenario-dev/20261116-094238-rebuild_bare` |

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.14 (run `python tools/anomaly.py build`)
```
