# L: why the G games were lost to the rules army (14 losses, 8 wins and 2 caps for contrast)

Plan: `todo/armynet-objectives.md`, the Fable session's L (11-27). No new games: the [G](2026-11-27-model-vs-rules-G.md)
games, read with `tools/story.py <match> --bucket 120` (per-side income, extractors home/mid/enemy, army metal and
front, metal lost, extractors lost, lead flips) and the death lines. Model side throughout; "front" is the army's
mean position on the start-to-start axis (0 = own start, 1 = theirs). "First lost trade" = the first bucket from
6 min where the model side lost at least twice what it killed and at least 800 metal.

## What ended them

| cause | losses | games |
|---|---|---|
| **lost the middle by 12 min, then out-expanded and raided at home** | **10** | G1 s1 s2 s3 s4 s7 s11; G2 s1 s3 s6 s10 |
| even to 12-14 min, out-expanded after (then lost the army at 20-22) | 1 | G1 s5 |
| army lost in one fight while level (22-24 min: 5,797 -> 919, 27,000 lost in two buckets) | 1 | G2 s7 |
| commander walked into an enemy turret while level or ahead (8.6 / 11.4 min) | 2 | G2 s4 (a light laser tower), G1 s10 (a cannon turret) |
| out-produced with no raid | 0 | |

## The table

| game | result | end | first lost trade | lost / killed | army us / them before | front us / them | extractors us / them at 12 (mid) | at 16 | ours lost / theirs lost by 16 |
|---|---|---|---|---|---|---|---|---|---|
| G1 s1 | L | 25.3 | 8 | 1,193 / 54 | 1,003 / 1,460 | .29 / .23 | 8 / 14 (1 / 4) | 14 / 18 | 14 / 17 |
| G1 s2 | L | 26.0 | 10 | 2,318 / 368 | 1,045 / 1,617 | .26 / .34 | 9 / 14 (0 / 4) | 7 / 17 | 15 / 14 |
| G1 s3 | L | 22.0 | 8 | 1,072 / 464 | 882 / 772 | .30 / .32 | 10 / 17 (0 / 6) | 9 / 20 | 16 / 14 |
| G1 s4 | L | 22.5 | 14 | 5,476 / 2,687 | 3,318 / 4,585 | .29 / .43 | 9 / 20 (1 / 8) | 8 / 21 | 14 / 7 |
| G1 s5 | L | 28.6 | 10 | 1,752 / 829 | 1,765 / 1,495 | .23 / .35 | 13 / 10 (3 / 1) | 11 / 16 | 12 / 12 |
| G1 s7 | L | 30.6 | 10 | 2,048 / 440 | 1,398 / 1,036 | .40 / .34 | 11 / 18 (0 / 7) | 12 / 20 | 9 / 12 |
| G1 s10 | L | 11.4 | - | (commander) | 1,881 / 1,963 | .31 / .27 | 16 / 14 (5 / 6) | | |
| G1 s11 | L | 24.2 | 10 | 1,410 / 702 | 1,297 / 985 | .25 / .34 | 11 / 16 (3 / 5) | 11 / 17 | 17 / 15 |
| G2 s1 | L | 25.4 | 26 | 13,634 / 1,989 | 471 / 14,063 | | 11 / 12 (1 / 3) | 9 / 18 | 12 / 13 |
| G2 s3 | L | 29.3 | 10 | 3,244 / 1,501 | 1,367 / 1,441 | .25 / .44 | 12 / 14 (0 / 3) | 7 / 19 | 19 / 10 |
| G2 s4 | L | 8.6 | - | (commander) | 1,192 / 1,005 | .24 / .23 | 15 / 11 at 10 (3 / 1) | | |
| G2 s6 | L | 16.5 | 10 | 1,160 / 372 | 1,140 / 1,367 | .22 / .39 | 10 / 14 (2 / 3) | 10 / 16 | 18 / 7 |
| G2 s7 | L | 28.0 | 22 | 9,830 / 3,644 | 3,807 / 5,053 | .25 / .34 | 11 / 12 (2 / 0) | 11 / 13 | 6 / 20 |
| G2 s10 | L | 25.4 | 12 | 3,228 / 1,162 | 2,600 / 2,727 | .36 / .42 | 9 / 15 (0 / 3) | 11 / 19 | 19 / 9 |
| *wins and caps* | | | | | | | | | |
| G1 s6 | W | 26.9 | 10 | 1,329 / 585 | 1,536 / 1,575 | .36 / .19 | 16 / 8 (4 / 0) | 16 / 18 | 21 / 17 |
| G1 s8 | W | 34.2 | 12 | 3,347 / 1,599 | 2,152 / 1,835 | .27 / .31 | 13 / 13 (1 / 3) | 21 / 11 | 8 / 17 |
| G1 s9 | W | 34.2 | 8 | 806 / 266 | 1,584 / 652 | .31 / .18 | 18 / 11 (6 / 0) | 18 / 12 | 18 / 4 |
| G1 s12 | W | 33.3 | - | | | | 17 / 15 (6 / 3) | 19 / 14 | 17 / 10 |
| G2 s2 | cap, ahead | 40 | 18 | 9,672 / 1,772 | 5,602 / 2,195 | .39 / .24 | 16 / 8 (4 / 0) | 25 / 8 | 10 / 11 |
| G2 s5 | W | 9.0 | - | (their commander) | | | 11 / 15 at 10 (0 / 3) | | |
| G2 s8 | cap, ahead | 40 | 36 | | | | 19 / 9 (9 / 1) | 19 / 13 | 5 / 14 |
| G2 s9 | W | 34.8 | 16 | 7,170 / 3,036 | 4,360 / 1,776 | .42 / .24 | 18 / 9 (6 / 0) | 26 / 10 | 11 / 14 |
| G2 s11 | W | 24.5 | 12 | 2,252 / 966 | 2,359 / 656 | .37 / .27 | 17 / 10 (5 / 0) | 23 / 11 | 12 / 12 |
| G2 s12 | W | 29.9 | 8 | 863 / 347 | 1,081 / 808 | .20 / .13 | 17 / 12 (5 / 1) | 20 / 15 | 10 / 12 |

## Read

1. **The middle at 12 minutes separates the results.** Middle extractors at 12 min, model / rules: in the 12
   losses that were not commander deaths, 13 / 47 in all (behind in 10); in the 7 wins that went past 10 min,
   33 / 7 (ahead in 6, behind in 1, G1 s8); in both caps, 4 / 0 and 9 / 1. By 16 min the losses stand at 10 extractors to
   the rules side's 18 (mean), the wins at 20 to 13.
2. **Raids are not the difference:** by 16 min both lose about the same number of extractors (losses 14.3 of
   ours, 12.5 of theirs; wins 13.9 and 12.3). What differs is who rebuilds and takes new spots: the side whose army
   holds the middle.
3. **Where the model's army was at the turn (10-12 min):** behind the middle and behind theirs. Front at the first
   lost trade: losses .28 vs the rules side's .36 (mean); wins .32 vs .22. The killers of our home extractors are the
   rules side's main army (Thuds, Storms, AKs on our ground), not raiders.
4. **The first lost fight alone is not the cause:** wins also lost a bucket 2-3 to 1 at 8-12 min (G1 s6, s8, s9;
   G2 s11, s12). The army before it differs: in the losses ours was level or smaller (us / them 0.65-1.35), in the
   wins level or larger (0.98-3.6).
5. **Two of 14 are the commander, not the army model:** both walked into an enemy turret (8.6 and 11.4 min, level
   or ahead). The commander is the rules AI's in every arm here.
6. So the next lever is holding the middle from 8 to 12 minutes (where the army stands while our builders take the
   mid spots), not finishing at clusters (G already moved that) and not raid defence.

<!-- meta {"topic": "armynet", "date": "2026-11-27", "title": "L: why the G games were lost to the rules army (14 losses, wins for contrast)", "games": 24, "W": 8, "L": 14, "w": 2, "l": 0, "verdict": "No new games. 10 of 14 losses lost the middle by 12 min and were out-expanded (middle extractors at 12: 13 vs 47 in losses, 33 vs 7 in wins); 1 out-expanded later, 1 army lost in one fight at 22-24, 2 commander walked into a turret. Raids equal in wins and losses; the army's front at the turn .28 vs theirs .36 (wins .32 vs .22)."} -->
