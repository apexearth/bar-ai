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
