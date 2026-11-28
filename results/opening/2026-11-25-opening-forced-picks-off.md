# Opening: each forced pick switched off (Mac, 32 games)

**Purpose:** issues/slow-opening.md. Three rules put their own pick ahead of a higher-valued mex in the first minutes:
the recorded opening order (lab first), the energy-stall hoist, the cover-push gun hoist. Each switched off alone.
**Settings:** v0.5.21 + aa-armed-only + the arm, Mac v0.5.21 dylib, Red Comet 1v1 vs BARb hard, +50 both, 12 min,
speed 20, seeds 1-4, lobby D (3 flying drones + build turret) and N (none). All 32 games level at 12 min. The no-open
patch first failed to compile (unreachable code is an error); rerun as `if (ai.frame >= 0) return false;`. Per seed:
the Mac's vendor/v0521/open4-read.txt.

| D lobby | control | no stall hoist | no opening order | no cover push |
|---|---|---|---|---|
| mex 1-5, mean s | 26, 108, 132, 173, 180 | 18, 69, 105, 137, 178 | 7, 16, 31, 55, 65 | 18, 85, 126, 145, 156 |
| mexes by 3 min | 5.0 | 5.0 | 10.0 | 6.25 |
| stalled / capped s (first 3 min) | 41 / 58 | 135 / 22 | 60 / 68 | 80 / 18 |
| first plant, first army unit s | 13, 25 | 13, 27 | 139, 170 | 13, 25 |
| income 3/5/8/10/12 | 15/35/70/79/93 | 15/27/50/43/86 | 27/40/76/94/113 | 19/36/62/57/81 |
| lost by 12: units, buildings | 47, 18 | 42, 31 | 49, 29 | 46, 36 |
| army trade at 12 | 0.91 | 1.14 | 0.67 | 0.65 |

| N lobby | control | no stall hoist | no opening order | no cover push |
|---|---|---|---|---|
| mex 1-5, mean s | 29, 80, 98, 159, 186 | 30, 76, 129, 152, 177 | 10, 33, 115, 175, 205 | 29, 99, 125, 169, 209 |
| mexes by 3 min | 4.25 | 4.75 | 4.0 | 4.25 |
| stalled / capped s | 54 / 68 | 96 / 59 | 19 / 95 | 95 / 47 |
| first plant, first army unit s | 20, 56 | 20, 57 | 95, 181 | 20, 56 |
| income 3/5/8/10/12 | 17/30/45/56/58 | 18/30/45/57/62 | 16/24/55/56/76 | 17/29/54/55/56 |
| lost by 12: units, buildings | 36, 17 | 21, 19 | 27, 18 | 32, 24 |
| army trade at 12 | 0.83 | 1.47 | 0.78 | 0.94 |

**Read (4 seeds per cell: direction only):** in the drone lobby the lab-first order is the large cost: without it
mexes by 3 min double and income leads at every mark (113 vs 93 at 12), but the lab waits to 139 s and the army trade
falls. In the normal lobby dropping it gains nothing by 3 min and delays the lab to 95 s. The stall hoist trades
stall time for mexes and buys no income; without it the trade is better in both lobbies (1.14, 1.47), units lost
fewer in N. The cover push: no clear effect in N, more mexes but more buildings lost in D. Next: the lobby-hands
opening (counts the drones and turret the lobby sends), alone and with the stall hoist off, in both lobbies, 8 seeds.
