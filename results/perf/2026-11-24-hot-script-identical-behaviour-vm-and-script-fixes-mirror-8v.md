<!-- meta {"date": "2026-11-24", "topic": "perf", "title": "Hot script: identical-behaviour VM and script fixes (mirror 8v8s)", "games": 2, "W": 1, "L": 1, "w": 0, "l": 0, "inc20": 0.98, "verdict": "AI time -4.2% (game 1) and -13.0% (game 2) over minutes 2-17, where both sides field comparable armies; script-only (main hook) -10.6% / -3.0%. Later minutes track whichever side is winning. Collector: 3.3 s -> 0.28 s in 19 min of 8 AIs. Verdict still FAIL (worst minute ~0.55 ms est. vs 0.417)"} -->
# Hot script: identical-behaviour VM and script fixes (mirror 8v8s)

- **Date:** 2026-11-24
- **Topic:** perf
- **Purpose:** Measure the per-frame collector, no line cues, the election re-sum, LiftFits and Def caches against HEAD scripts + stock VM, both slots in one game (control side A in game 1, side B in game 2), 8v8 Greenest Fields +100, 35 min cap
- **Result:** 2 games: won 1, lost 1, timeouts ahead 0, behind 0; income at 20 min x0.98 ours/theirs
- **Verdict:** AI time -4.2% (game 1) and -13.0% (game 2) over minutes 2-17, where both sides field comparable armies; script-only (main hook) -10.6% / -3.0%. Later minutes track whichever side is winning. Collector: 3.3 s -> 0.28 s in 19 min of 8 AIs. Verdict still FAIL (worst minute ~0.55 ms est. vs 0.417)
- **Ours:** Apexhotcpp-lane-hotcpp-standard
- **Opponents:** Apexhotcpp-lane-hotcppbase-standard
- **Code:** Apexhotcpp-lane-hotcpp-standard = `ee586fddaf+8805a18bf7fb` (2 games); Apexhotcpp-lane-hotcppbase-standard = `ee586fddaf+8805a18bf7fb` (2 games)
- **Maps:** Greenest Fields 1.3.1
- **Sides:** Cortex; **bonus:** 100; **time cap:** 35 min
- **Runs:** .
- **Code note:** the fingerprint above is the working tree, which neither slot ran as is. Both slots ran one DLL (this commit's ScriptManager). lane-hotcppbase: HEAD's game-side scripts, AI options apex_as_gc=0 apex_as_linecues=1 (the stock collector and line cues; both options removed in this commit). lane-hotcpp: HEAD plus decide.as, lift.as, catalog.as from this commit. Other sessions' uncommitted army.as, nukes.as, tunables.as were pinned to HEAD in both.
- **Command (first game):** `run_match.py --a Apexhotcpp:lane-hotcppbase:standard --b Apexhotcpp:lane-hotcpp:standard --map Greenest Fields --per-side 8 --sides Cortex,Cortex --boxes lr --box-size 0.1 --handicap 100 --minutes 35 --speed 20 --seed 1 --ai-option apex_as_gc=0 --ai-option apex_as_linecues=1 --out matches/hotcpp-mirror1`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Greenest Fields 1.3.1 | Cortex | 1 | 1 | W | 30.51 | x3.29 | ee586fddaf+8805a18bf7fb | `matches/hotcpp-mirror1` |
| 1 | Greenest Fields 1.3.1 | Cortex | 2 | 0 | L | 27.7 | x0.29 | ee586fddaf+8805a18bf7fb | `matches/hotcpp-mirror2` |

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.18 (run `python tools/anomaly.py build`)
```
