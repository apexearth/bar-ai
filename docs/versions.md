# Versions and candidates

One row per release or candidate: what it is, and its measured record. Head-to-head is against v0.2.6,
sides swapped every game, starts staggered 15 s; a time-limit game goes to the side clearly ahead on army
x mexes at the end (`scratchpad/h2hend.py`), else a draw. 12 games per map size: a difference under
~25 points is inside the noise.

| Version | Tag | What changed | Small (Red Comet 4v4) | Mid (Comet Catcher 4v4) | Large (Supreme Isthmus 4v4) |
|---|---|---|---|---|---|
| v0.2.6 | `v0.2.6` | release 10-15 (watch slot of that day, tech-now on) | baseline | baseline | baseline |
| cand-1 | `cand-0.2.7-1` | v0.2.6 + rush awareness, team tech, splash vs blob, unstick, unit upkeep, tech-now off | 6W 0D 6L | 8W 1D 3L | 5W 2D 5L |
| cand-2 | `cand-0.2.7-2` | cand-1 + map share (army nudge and aggression while under our fair share of the map) | 7W 0D 4L | 11W 1D 0L | 3W 2D 7L (worse) |
| cand-3 | `cand-0.2.7-3` | cand-1 + small-map hard military (path contact, strength at arrival, starve their mexes, commander at the factory); map share off | 7W 0D 5L | - | 5W 1D 6L |
| cand-4 | `cand-0.2.7-4` | cand-3 + budget hold (builder floors/hoists yield while army is under its share) + fixed T1-plant tag (walk flood, enemy commanders and rush speed prior now real) | 7W 1D 4L | 10W 0D 2L | 7W 1D 4L |
| cand-5 | `cand-0.2.7-5` | cand-4 + large-map walk fix (box ring widens) + map share on | **21W 0D 3L** (24: seeds 500+ 9-0-3, 600+ 12-0-0) | **11W 1D 0L** | **6W 5D 1L** |
| cand-6 | `cand-0.2.7-6` | cand-5 + commander stays home (far jobs pay for lost factory help, base attack seen and answered, D-gun/fire-factor fight fixes, no blind walk-in) | 14W 2D 8L (24: 500+ 6-1-5, 600+ 8-1-3) -- worse than cand-5 | 9W 3D 0L | 4W 6D 2L |
| cand-7 | `cand-0.2.7-7` | cand-5 + early ball (pawn/grunt priced by what a ball razes before their defence answers, field coverage, ball sent whole, air scouts priced by information; pawn no longer counted as a scout) | **10W 0D 2L** | **12W 0D 0L** | **9W 0D 3L** |
| cand-8 | (merged, untested) | team mass air (TUNE_TEAM_AIR): leader prices AIR vs NORMAL, all seats build air, gather, strike together | - | - | - |
| cand-9 | `cand-0.2.7-9` | cand-7 + open race (con vs fighter on one clock, your timing rule), no e-stall idle labs, no chasing uncatchable targets | vs BARb Red Comet: **1W 2D 7L, score -0.4** (cand-5 arm same seeds: 0W 0D 10L, -2.5) | - | - |
| cand-10 | (lane-c9) | cand-9 + spot race (con value = spots we reach first), square-law fighter strength, army contests spots | vs BARb Red Comet: 1W 0D 9L | - | - |
| cand-11 | `cand-0.2.7-11` | cand-10 + fighter kills only while alive, strength without speed, basic fighter not a scout (Ticks -> Pawns) | vs BARb Red Comet: 1W 1D 8L; 30% of early losses to their commanders | - | - |
| cand-12 | `cand-0.2.7-12` | cand-11 + fight estimate (TUNE_COM_FIGHT: group vs army+towers+commander, fall back/merge, keep-out rings, split by matchup) | vs BARb Red Comet: 1W 1D 8L; fires (fall 1948, split 1107, rings 705) but 841 engage/fall flips, estimate predicts 3.5x our real losses; deaths still 89% | - | - |
| (control) | - | cand-11 with apex_target_value, apex_fight_travel, apex_birth_defend OFF | vs BARb Red Comet: 1W 0D 9L, deaths still 88% -- our fight layers are not the cause | - | - |
| cand-13 | `cand-0.2.7-13` | cand-12 + fight estimate calibrated from outcomes, fall-back priced by the stake abandoned, hysteresis, concentrate/defeat in detail, raid packs sized by the estimate | vs BARb Red Comet: **1W 4D 5L** (as Armada/side A 1W 4D 0L, mean +0.70; as Cortex/side B 0W 0D 5L) | - | - |
| cand-14 | `cand-0.2.7-14` | cand-13 + counter mix (production by matchup vs the army seen) + calibration fix (prediction per fight segment) | vs BARb Red Comet, mean score: Armada A -1.03, Armada B -0.12, Cortex A -1.84, Cortex B -1.74 (avg -1.18; cand-13 avg -0.54) -- worse | - | - |
| cal | (lane-c9 arm) | cand-13 + calibration fix only | vs BARb: Armada A +0.32, Armada B +0.52, Cortex A -2.31, Cortex B -2.06 (avg -0.88) | - | - |
| cand-15 | `cand-0.2.7-15` | cal + focus fire (TUNE_FOCUS_FIRE) | vs BARb: -0.69 / -0.89 / -2.56 / -2.46 (avg -1.65) -- WORSE in every cell; off in the watch slot | - | - |
