# Opening counts the hands the lobby sends (Mac, 24 games)

**Purpose:** issues/slow-opening.md. The lab-or-mexes-first choice is made at frame ~5, before the assist drones
(frame 150) and the build turret (~2 s after warp-in) exist, so it counted only the commander. The change
(henry-outbox/open-lobby-hands-v0521.patch + the C++ binding CCircuitDef::GetCustomParam): read the lobby's drone
count and build-turret option, count their build power and spend in the lab-first test, and decide again if more
helping build power appears before the plant is ordered.
**Settings:** v0.5.21 + one-con-count + aa-armed-only (+ arm), Mac dylib v0521-gcp (full rebuild), Red Comet 1v1 vs BARb
hard, +50 both, 12 min, speed 20, seeds 1-4, lobbies D (drones + turret) and N (none). Per seed: the Mac's
vendor/v0521/open4-read-base3.txt.

Log check: D open-plan MEX2 otherBp=700 carryE=0.27 in 4/4; N plan=LAB otherBp=0 in 4/4; no open-replan.

| D lobby | control | lobby hands | hands + no stall hoist | (no opening order, earlier) |
|---|---|---|---|---|
| result | T L T T | T L T T (same seed, same minute) | T T T T | |
| mex 1-5, mean s | 25, 73, 114, 157, 175 | 7, 14, 30, 54, 81 | 7, 23, 32, 92, 130 | 7, 16, 32, 58, 65 |
| mexes by 3 min | 5.75 | 7.25 | 7.75 | 10.5 |
| first plant, first army unit s | 13, 25 | 47, 55 | 49, 80 | 134, 141 |
| stalled / capped s | 64 / 39 | 118 / 19 | 135 / 6 | |
| income 3/5/8/10/12 | 17/35/64/62/73 | 25/55/71/80/111 | 26/52/81/88/118 | 32/38/72/80/111 |
| lost by 12: units, buildings | 45, 48 | 56, 44 | 81, 30 | |
| army trade at 12 | 0.74 | 0.48 | 0.76 | |

N lobby: the lobby-hands arm makes the same choices as control, so the two are an A/A, and they read 3.0 vs 4.75
mexes by 3 min, income at 12 65 vs 62, trade 0.54 vs 0.83. That is the noise of a 4-seed cell. Hands + no stall hoist
in N: 4.75 mexes, income 80 at 12, trade 0.52.

**Verdict:** in the drone lobby the change gets the income of dropping the opening order (111 at 12, +52% on control)
with the lab at 47 s instead of 134 and the first army at 55 s instead of 141. Its trade (0.48 vs 0.74) is inside the
N-lobby A/A noise. Kept in source. The stall hoist stays an open question: without it income is best (118) and fewer
buildings are lost, but the most units are lost (81); needs more seeds.

## Confirmation, 8 seeds per lobby (Mac, 48 games, fresh full-rebuild dylib v0521-gcp)
Base v0.5.21 + aa-armed-only + one-con-count; seeds 1-8 x D/N. N lobby: lobby-hands matches control's open-plan line
exactly on all 8 seeds (plan=LAB, otherBp=0). D: lobby-hands plan=MEX2 otherBp=700 in 8/8; no open-replan anywhere.

| D lobby | control | lobby hands | hands + no stall hoist |
|---|---|---|---|
| result | 7T 1L | 8T | 7T 1L |
| mex 1-5, mean s | 21, 96, 144, 177, 200 | 7, 14, 30, 56, 93 | 7, 23, 39, 80, 106 |
| mexes by 3 min | 3.75 | 7.5 | 7.5 |
| first plant, first army unit s | 13, 26 | 48, 54 | 43, 64 |
| stalled / capped s; energy wasted | 71 / 55; 5,419 | 88 / 23; 4,882 | 131 / 11; 528 |
| income 3/5/8/10/12 | 13/27/58/62/67 | 22/49/84/91/137 | 28/53/72/100/136 |
| lost by 12: units, buildings | 35, 29 | 60, 22 | 70, 35 |
| army trade at 12 | 0.78 | 0.71 | 0.57 |

N lobby (same plan in all arms, so noise): mexes by 3 min 4.38 / 4.75 / 4.50, income at 12 63 / 68 / 59, trade
0.60 / 0.73 / 0.70; control lost one (s3 at 11.1 min).

**Verdict, 8 seeds:** lobby-hands doubles mexes by 3 min and income at 12 in the drone lobby (137 vs 67), no loss in
8, trade held (0.71 vs 0.78). Kept. The stall hoist off on top adds no income and trades worse (0.57, one loss): the
hoist stays.

## Stall hoist, 12 seeds per arm (Mac; base v0.5.21 + one-con + aa + lobby-hands; seeds 1-8 the runs above, 9-12 new)
Control vs no stall hoist, paired. D lobby: W/T/L 0/12/0 vs 1/10/1; income at 12 124.7 vs 125.4 (paired +0.6, se
13.4); trade at 12 0.70 vs 0.63 (paired -0.08, se 0.07); stalled 88 vs 135 s. N lobby: 0/12/0 both; income at 12
70.7 vs 57.8 (paired -12.9, se 7.7, higher in 3/12); trade 0.74 vs 0.74 (per-seed 0.20-1.71). Off changes nothing
measurable at 12 min; the one lean (N income) favours keeping it. The stall hoist stays. Per seed: the Mac's
vendor/v0521/estall-12seeds.txt.
