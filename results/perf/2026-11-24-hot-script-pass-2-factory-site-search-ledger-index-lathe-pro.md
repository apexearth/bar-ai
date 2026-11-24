<!-- meta {"date": "2026-11-24", "topic": "perf", "title": "Hot script pass 2: factory site search, ledger index, lathe probe, splash pairs in C++ (identity checks)", "games": 5, "W": 0, "L": 1, "w": 0, "l": 4, "inc20": 0.27, "verdict": "All identical: 31/31 factory sites, 767/767 lathe probes, 0 mismatches over 15,654 + 11,098 checked ledger/cover/splash calls, no script exceptions. Factory search worst 64.2 -> 4.2 ms, 272 -> 33 ms total in 20 min; the lathe turret scores 217 -> 116 ms over 767 probes"} -->
# Hot script pass 2: factory site search, ledger index, lathe probe, splash pairs in C++ (identity checks)

- **Date:** 2026-11-24
- **Topic:** perf
- **Purpose:** Prove each change returns what the old code returned, in the same game: every factory site search run both ways (apex_fac_pretest_check), the lathe-site turret scores recomputed the old way (apex_lathe_check), ComCountOf/ComNearest, the AA cover sums and the splash bins against the full walks (apex_com_check). All-Apex 8v8 Greenest Fields +100, 20-30 min; the checks were removed after
- **Result:** 5 games: won 0, lost 1, timeouts ahead 0, behind 4; income at 20 min x0.27 ours/theirs
- **Verdict:** All identical: 31/31 factory sites, 767/767 lathe probes, 0 mismatches over 15,654 + 11,098 checked ledger/cover/splash calls, no script exceptions. Factory search worst 64.2 -> 4.2 ms, 272 -> 33 ms total in 20 min; the lathe turret scores 217 -> 116 ms over 767 probes
- **Ours:** Apexhotcpp-lane-hotcpp-standard
- **Opponents:** Apexhotcpp-lane-hotcpp-standard
- **Code:** Apexhotcpp-lane-hotcpp-standard = `ed1b4904a7+04bde405a455` (1 games); Apexhotcpp-lane-hotcpp-standard = `ed1b4904a7+2e7a92e52209` (1 games); Apexhotcpp-lane-hotcpp-standard = `ed1b4904a7+b5759a53f40d` (1 games); Apexhotcpp-lane-hotcpp-standard = `ed1b4904a7+bdeb797cc9fa` (1 games); Apexhotcpp-lane-hotcpp-standard = `ed1b4904a7+d58e31c28bc9` (1 games)
- **Maps:** Greenest Fields 1.3.1
- **Sides:** Cortex; **bonus:** 100; **time cap:** 20, 25, 30 min
- **Runs:** .
- **Note:** both sides ran the same slot (lane-hotcpp), so the win/loss and income columns count the code against itself and say nothing. hotcpp-facsite is the before reading for the factory search (a timing probe, since removed); the other four carry the checks.
- **Command (first game):** `run_match.py --a Apexhotcpp:lane-hotcpp:standard --b Apexhotcpp:lane-hotcpp:standard --map Greenest Fields --per-side 8 --sides Cortex,Cortex --boxes lr --box-size 0.1 --handicap 100 --minutes 20 --seed 5 --speed 20 --out matches/hotcpp-facsite`

Results are ours, counted by seat. W/L decided; w/l a time-capped game ahead/behind on income at the end.

| # | map | sides | seed | our seat | result | minutes | income at 20 | code | game |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Greenest Fields 1.3.1 | Cortex | 5 | 0 | l | 20.0 | x0.17 | ed1b4904a7+b5759a53f40d | `matches/hotcpp-facsite` |
| 1 | Greenest Fields 1.3.1 | Cortex | 5 | 0 | l | 20.0 | x0.22 | ed1b4904a7+bdeb797cc9fa | `matches/hotcpp-pretest` |
| 2 | Greenest Fields 1.3.1 | Cortex | 6 | 0 | L | 28.19 | x0.19 | ed1b4904a7+d58e31c28bc9 | `matches/hotcpp-lathecheck` |
| 3 | Greenest Fields 1.3.1 | Cortex | 7 | 0 | l | 25.0 | x0.33 | ed1b4904a7+2e7a92e52209 | `matches/hotcpp-comcheck` |
| 4 | Greenest Fields 1.3.1 | Cortex | 8 | 0 | l | 25.0 | x0.56 | ed1b4904a7+04bde405a455 | `matches/hotcpp-comcheck2` |

## Anomalies

Seats far outside the release's normal play in the same regime (`tools/anomaly.py`, robust z >= 5 against every finished release seat).

```
anomaly: no baseline for v0.5.18 (run `python tools/anomaly.py build`)
```
