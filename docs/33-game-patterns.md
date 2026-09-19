# 33 — Game patterns, read from 90 finished games (2026-09-19)

What happens over time in our games against BARb hard, read with `tools/story.py
<match> --bucket 120` and `tools/mapframe.py`. Behaviour only; no causes unless an
`apex:` line names one. Every number below is recomputable from the same gadget
lines (`[BARAI_STATS|ARMY|DEATH|POS|BUILD]`) via `story.load()`.

## Corpus

| set | dirs (all `tournaments/20260919-*`) | games | ours W-L-D |
|---|---|---|---|
| 1v1 Comet Catcher Remake (CC) | t2urgency-{treated,control,cover,screen,super}, story-1v1 | 21 | 6-14-1 |
| 1v1 Glacier Pass (GP) | same | 22 | 12-9-1 |
| 2v2 CC | story-2v2, holdground, noscreen(103828), rezcore, labassist, confloor | 22 | 0-9-13 |
| 2v2 GP | same | 21 | 0-14-7 |
| 8v8 Supreme Isthmus (SI) | `matches/20260919-163553`, `-185914`, `-190815` | 3 | 0-0-3 |
| 1v1 SI | `matches/20260919-055126` | 1 | 0-1-0 |

Dropped: t2urgency-screen/t002 (4.2 min), noscreen-103633 (no stats), and
**rezcore-2v2/t004** — its infolog is a truncated copy of t001's (same
`[t=00:00:15.783999][f=3600]` stamp, no `Mapname` line); its "win" is not a game.
All +100% handicap both sides, all Cortex. "We" below covers every Apex variant in
the sets (they differ in one tunable each; the shapes below do not differ between
arms). Side names: story.py prints A = first spec (ally 0); in `tNNN-BARb_...` dirs
A is BARb.

Definitions used: **front** = metal-weighted 0..1 position of the standing army
(0 own start, 1 enemy start). **Region** home/mid/enemy = thirds of that axis.
**cohesion** = share of one team's army metal within 600 elmo of its metal-weighted
centroid (per team, metal-weighted mean over allies). **lone** = share of army
metal with no same-team army unit within 350 elmo. Bucket rows are stamped by
their END minute.

## 1. The opening (0-6 min)

- Both sides finish the first plant at 1.0 min (median over 129 teams each) and
  the second at 8.7 vs 8.8. By 4 min a team has built (mean): mex 3.6 vs BARb
  4.8, energy 7.1 vs 6.2, nano 1.4 vs 1.6, def 2.4 vs 2.3, converters **1.7 vs
  0.0** (3.8 vs 0.9 by 6 min).
- Army metal at 4 min, median ratio ours/theirs: CC 1v1 **0.42** (502 vs 1289),
  GP 1v1 0.54 (783 vs 1335), CC 2v2 0.89, GP 2v2 0.61, SI 8v8 0.57 (4257 vs 7547).
  Distribution over 87 1v1+2v2 games: p10 0.30, p25 0.44, p50 0.63, p75 0.89, p90
  1.10; we are behind in 84% of games at 4 min, 76% at 6 and 8, 63% at 10, 51% at 12.
- We have MORE units and less metal: 26.8 army units per team at 6 min vs 20.7,
  because at 8 min our standing army is 92% AK/Thud/Storm (corak 37%, corthud
  30%, corstorm 25%, over 86 games) while BARb's is Gator 16%, Raider 16%, Thud
  15%, Leveler 14%, AK 14%, Storm 9%, Wolverine 8% — a vehicle line from the start.
- Where the army stands at 4 min (front, median): CC 1v1 ours 0.25 vs BARb
  **0.43** (max 0.56); GP 1v1 0.29 vs 0.32; CC 2v2 0.21 vs 0.34; GP 2v2 0.28 vs
  0.33; SI 8v8 0.15 vs 0.19. On CC BARb's army is at the midpoint before the 4-minute
  mark in every game; ours is on its own doorstep.
- First to put army (>300 metal) at front >= 0.45: CC 1v1 BARb 19/21, CC 2v2
  BARb 19/22, GP 2v2 BARb 17/22, GP 1v1 **ours 11 vs 8**. GP 1v1 is the only
  class where we get to the middle first, and the only class we win.
- Mexes at 6 min (median): CC 1v1 5 vs 5 (BARb 0.8 of them on mid ground, ours
  0.0); GP 1v1 4 vs 4 (1 mid each); CC 2v2 8 vs **12**; GP 2v2 5.5 vs 8; SI 8v8
  14 vs 16. In CC 2v2 our best game (11) is barely above BARb's worst (10).
- Fast BARb pressure on CC: t2urgency-control/t000 (CC 1v1, lost 12.4) — BARb
  army at our base edge at 6 min (mapframe frame 6), mexes 11 vs 7 at 6, 13 vs 7
  at 8, 26 vs 11 at 12; our army 1k at 8 min died at home.
- Losses in the opening are small either way: metal lost by 6 min median ours
  308 vs 170 (CC 1v1), 374 vs 218 (GP 1v1), 852 vs 623 (GP 2v2).
- Income at 6 min (pooled): CC 1v1 26 vs 27; GP 1v1 22 vs 22; CC 2v2 46 vs **63**;
  GP 2v2 36 vs 45; SI 8v8 125 vs 103 (we are ahead at 6-10 min in 8v8).

## 2. The middle (6-16 min)

**When the leads change hands** (last flip, then who holds it at the end; 90 games):
- Army lead final holder: BARb 67 (45 L, 21 D, 1 W), ours 23 (17 W, 2 L, 4 D).
  Income lead: BARb 71 (47 L, 24 D), ours 19 (18 W, 1 D). Whoever holds the income
  lead at the end has won or is winning; income never ends in our hands in a loss.
- Median last-flip minute: army 16, income 16, mexes 15. Army lead never flipped
  in 21 games (BARb led from minute 4 to the end).
- In the two buckets before we lose the army lead we were spending 57% army, 18%
  eco, 7% def, 18% buildpower (88 buckets); BARb, in the 34 buckets before it lost
  the lead, 50/19/8/22. We do not lose the army lead by starving the army.

**Spend share by phase** (sum over 1v1+2v2, `mArmy/mEco/mDefence/mBP` deltas):

| minutes | ours arm/eco/def/bp | BARb arm/eco/def/bp |
|---|---|---|
| 2-6 | 36/32/5/27 | 37/19/8/36 |
| 8-12 | 49/18/10/23 | 36/23/15/26 |
| 14-18 | 55/20/6/19 | 32/27/**19**/22 |
| 20-30 | 57/14/12/17 | 49/17/**20**/14 |

- Metal into finished buildings: by 16 min BARb has put 28% into static defence
  (37% by 22) vs our 15% (21%). Towers standing at 10 min: ours 1130 vs BARb 1864;
  on mid ground **63 vs 357**; at 16 min mid ground 128 vs 580. BARb fortifies the
  mexes it takes in the middle; we do not (memory: mex-guard ruling).

**Where we die and to what, 8-16 min** (built units, metal):

| class | ours lost, region | killed by (top) | BARb lost, region |
|---|---|---|---|
| CC 1v1 | 235k: home 52% mid 37% enemy 11% | corgol 36k, corban 27k, corpyro 15k, correap 13k, corlevlr 12k, corgator 11k | 146k: home 22% mid 46% enemy 32% |
| GP 1v1 | 154k: home 25% mid 25% **enemy 50%** | corak 19k, corlevlr 17k, corthud 13k, corgator 11k | 151k: **home 66%** |
| CC 2v2 | 442k: home 40% mid 40% | corak 64k, corgol 58k, corban 49k, corlevlr 20k | 297k: mid 41%, home 30%, enemy 30% |
| GP 2v2 | 392k: **home 59%** | corak 83k, corthud 38k, corlevlr 25k, corgator 19k | 313k: enemy 46% |
| SI 8v8 | 167k: home 50% mid 47% | armjanus, armwar, armfboy, armbull | 122k: enemy 54% mid 40% |

- What of ours dies in 8-16: corthud, corak, corstorm in every class (CC 1v1
  49k/29k/26k). What of BARb's dies: cornecro (rezbots), corgator, corlevlr,
  corraid, and on GP 1v1 **coralab 11.6k** (two T2 labs killed by our raids).
- On CC (both sizes) T2 vehicles kill us from ~12 min: corgol (Tiger) and corban
  are the top two killers of our metal; on GP it is still T1 (AK, Leveler, Gator)
  because the game is decided by mex counts, not fights.
- GP 1v1 is our one winning shape: story-1v1/t002 (won 22.8) — at 4 min our army is
  a single column walking the map edge (frame 4), at 6 min two columns on the far
  corners (frame 6), mex 7 vs 4 at 8 min, BARb income 18 at 10 min after losing its
  outer mexes, BARb boxed at 3-4 mexes from 12 min on. Same in t2urgency-treated
  t004-t007 (all won; peak army ratio 2.9x-9.2x).

**Standing army as a body or as spray** (cohesion, median per class; lone share in brackets):

| minute | CC 1v1 ours / BARb | GP 1v1 | CC 2v2 | GP 2v2 | SI 8v8 |
|---|---|---|---|---|---|
| 6 | 0.59 / 0.63 | 0.40 / 0.53 | **0.11 / 0.44** | 0.31 / 0.40 | 0.13 / 0.31 |
| 8 | 0.54 / 0.46 | 0.32 / 0.59 | 0.12 / 0.30 | 0.35 / 0.38 | 0.16 / 0.28 |
| 10 | 0.49 / 0.65 | **0.26 / 0.49** | 0.13 / 0.21 | 0.39 / 0.28 | 0.17 / 0.11 |
| 12 | 0.36 / 0.56 | 0.38 / 0.42 | 0.17 / 0.19 | 0.30 / 0.30 | 0.10 / 0.07 |
| 16 | 0.33 / 0.33 | **0.15 / 0.57** | 0.18 / 0.22 | 0.41 / 0.26 | 0.08 / 0.07 |
| lone 6-12 | 0.08-0.12 / 0.09-0.14 | 0.07-0.11 / 0.04-0.07 | 0.08-0.15 / 0.10-0.14 | 0.07-0.13 / 0.07-0.11 | 0.09-0.23 / 0.18-0.28 |

- BARb keeps half or more of its metal in one body through minute 10 in 1v1 (0.49-0.65)
  and at 6-8 min in 2v2 CC (0.44/0.30); ours is 0.11-0.13 in CC 2v2 for the whole
  middle game. The lone share does not differ: we are not more single stragglers,
  we are **several groups instead of one** (holdground/t001 frames 8-12: red dots in
  every grid cell of the east half, blue in 3-4 clumps; same in story-1v1/t001 frame
  10-12).
- Our front is flat for the whole game: median 0.31-0.35 from minute 6 to 24
  (n=48-88). BARb's rises from 0.34 at 4 to 0.40-0.43 from minute 12 on. The army
  we mass stays in our third of the map.
- `apex: withdraw` fires 10-13 times per 2-minute bucket per side in 2v2 from 8 to
  14 min (CC 13.0 at 10-14, GP 11.5-13.0), 7-10 in 1v1 CC. Reasons over the day's
  tournaments: recall-home 1600, infl 917, trade 760, pack 469, leash 30; units:
  corak 786, corstorm 498, corthud 470.

**Mexes and income through the middle** (median ours / BARb, mexmid = mean count on mid ground):

| class | 8 min | 10 | 12 | 14 | 16 |
|---|---|---|---|---|---|
| CC 1v1 inc | 36/45 | 47/59 | 67/82 | 95/119 | 137/161 |
| CC 1v1 mex (mid) | 7/10 (0.0/2.3) | 9/11 (0.0/2.6) | 13/14 | 18/16 | 24/19 (1.2/3.3) |
| GP 1v1 inc | 30/27 | 35/36 | 41/45 | 66/55 | 83/66 |
| GP 1v1 mex | 4/5 | 5/5 | 6/6 | 7/7 | 8/6 |
| CC 2v2 inc | 72/82 | 96/119 | 137/160 | 183/209 | 208/**344** |
| CC 2v2 mex (mid) | 12/16 (0.1/0.7) | 17/22 | 23/26 | 28/30 | 27/35 (1.4/3.8) |
| GP 2v2 inc | 48/54 | 54/71 | 58/95 | 65/114 | 76/138 |
| GP 2v2 mex (mid) | 6/9 (0.3/1.3) | 6/10 | 7/10 | 7/11 | 7/12 (0.6/2.8) |
| SI 8v8 inc | 149/135 | 254/211 | 329/348 | 415/432 | 438/493 |
| SI 8v8 mex (mid) | 17/23 (0.0/0.3) | 29/33 (0.0/1.0) | 35/44 (0.7/5.0) | 40/46 | 39/50 (1.3/7.3) |

- On CC 1v1 we out-mex BARb from 14 min (18 vs 16, 24 vs 19) and still trail in
  income (95 vs 119, 137 vs 161). On GP 2v2 we sit at 6-7 mexes from minute 8 to
  20 while BARb goes 9 → 12.
- Income per mex (pooled 1v1+2v2 median): 6.1 vs 6.2 at 10 min, 9.1 vs 10.0 at 16,
  10.1 vs **14.3** at 20, 12.0 vs 17.8 at 22, 15.3 vs 22.5 at 28. From minute 18
  BARb's income is not its mexes.

## 3. The late game (16+)

- Every decided game (47 L, 19 W) ends within 1 minute of the loser's last
  commander death; no base wipe or resignation ends a game earlier.
- **Commander deaths that did not end the game**: ours **38** (all in 2v2 and 8v8),
  BARb 10. Ours: minutes 7.5, 7.9, 8.4, 9.7, 10.6, 10.8, 11.2, 11.8, 11.8, 12.4,
  12.5, 12.8, 13.0, 13.4, 14.4 ... ; killers corak 11, corgol 7, corpyro 5,
  corban 3; median 1394 elmo from its own start, 35 of 39 in the home third.
  Example holdground/t005 team 3: `apex: com-pos` home=401 at 7.5 min, home=1921
  at 8.5, home=1989 at 9.0 (fwd 0.52), killed by corlevlr at 9.7 at 2317,2757
  (start 3963,3676) while its last act list was `mov>mov>dgn>dgn`.
- Commander position samples (`apex: com-pos`, 1v1+2v2 story sets): >1200 elmo
  from its start in 0% of samples at 0-4 min, 8% at 4-8, **35% at 8-12**, 29-34%
  from 12 to 28 min; fwd>0.4 in 5% or fewer after minute 8. It is out of the base
  a third of the time from minute 8, on the flanks, not toward the enemy.
- **Tech timing** (`tools/techtime.py`, T2 = lab started; my agg = lab finished):
  we START T2 at 4.2-5.7 min at income 20-29 in every arm; BARb at 6.0-7.5 at
  26-38. Both FINISH at median 8.5 (ours) vs 8.6 (BARb): our T2 lab takes ~3.5
  minutes to complete, BARb's ~1.5. Fusion finished: ours in 60/88 games at median
  16.0, BARb 76/88 at 13.9. Gantry: ours **13/88 at 23.8**, BARb **55/88 at 17.0**.
  BARb had the first fusion in 64 games, we in 16.
- inc20 / inc30 (techtime, per arm): 2v2 ours 96-138 / 53-150 vs BARb 176-248 /
  353-610; 1v1 ours 91-177 / 132-231 vs BARb 118-218 / 122-231.
- Income ratio ours/BARb (median, 1v1+2v2): 0.81 at 10-12 min, 0.78 at 16, 0.68 at
  18, **0.55 at 20**, 0.50 at 22, 0.40 at 28. Mex ratio over the same minutes stays
  0.79-0.88 until 20 then 0.62-0.77.
- Standing army at 24 min (40 games): ours corsumo 31%, corhrk 10%, corcan 10%,
  cortermite 9%, coraak 6%; BARb corsumo 14%, **corkorg 13%, corjugg 11%, corcat
  9%, corkarg 4%** (37% T3), corgol 12%. Our army has no T3 in its top nine.
- What decides the draws: of 25 draws, **21 end with BARb holding the army lead**,
  usually by 3-10x at the last full bucket — noscreen/t002 (CC 2v2) 21.8k vs 298k,
  rezcore/t002 29.6k vs 225k, confloor/t003 28k vs 183k, story-2v2/t000 36k vs
  165k, SI 8v8 163553 189k vs 572k at 28 min (income 1308 vs 2604, mex 16 vs 62).
  A 30-minute draw is a loss the clock interrupted.
- Our own big leads do not close: we held >=1.5x army at some bucket >= 10 min in
  39 games → W 15, D 13, L 11. story-1v1/t000 (CC, draw): 11.2k vs 4.6k at 14 min,
  21.6k vs 7.9k at 18, front 0.34-0.43; BARb spent def 10,000 in the 16 bucket and
  plant 8,400 (gantry) in the 18; our losses in 20-28: corvipe 3.3k, cordoom
  5.9k+5.4k, corjugg 16.5k; BARb army 4.6k at 14 → 53k at 28, ours 26k at 20 →
  13k at 28. confloor/t002 (CC 2v2, draw): 98k vs 44k at 24, 151k vs 72k at 28,
  income 792 vs 374, and the two BARb bases (60 rings each, frames 24-28) stand.
  matches/055126 (SI 1v1, lost 40.1): 18.6k vs 7.2k at 14 min with front 0.29,
  BARb income passes ours at 14 (133 vs 86) with fewer mexes (15 vs 17), 415 vs
  227 at 22 with 22 vs 41 mexes; armbanth kills 8k of ours at 22; BARb 264k army
  at 36.
- The one win shape that closes: BARb at <=4 mexes by 12 min (GP 1v1). Even then
  it takes 10 minutes of 5-30x army to walk through the tower ring (story-1v1/t002:
  BARb army 1-3k from 12 min, game ends 22.8).

## 4. Per map

**Comet Catcher Remake** (starts 1460,2976 vs 6571,3008; ~5100 elmo apart on one
axis; mexes ring each base and fill the corners).
- BARb's army is at the midpoint by 4 min (front 0.43) and at our base edge by
  6-8 in 19/21 1v1 games; the CC fight is in our home third (52% of our 8-16 losses)
  and the strip between the bases.
- BARb takes the mid strip and the far corners by 8 min (10 vs 7 mexes, 2.3 on
  mid ground vs 0.0) and puts towers on them (mid towers 357 vs 63 at 10 min, all
  classes pooled). We take our ring, then the whole map after 14 min when BARb has
  turtled (24 vs 19 at 16, 49 vs 21 at 28 in story-1v1/t000) — and still lose income.
- What wins CC for BARb: Tiger/Banisher from 12 min, a ~40-60 tower ring per base
  by 20 (frames 20-28 of story-1v1/t000 and confloor/t002), gantry at 17.
- What wins CC for us (6/21): an early army lead that reaches their base before
  the ring exists — t2urgency-treated/t002 (won 20.4): 4858 vs 4793 at 10 min,
  army flip at 10, 6.4x at 18. Five of our six CC 1v1 wins had the army lead by
  minute 12 (flips at 6, 6, 8, 10, 12); cover/t000 won on income (flip at 10).

**Glacier Pass** (1v1 starts 876,2464 vs 4083,2496; 2v2 starts stacked on the west
and east edges; 4-5 mexes per base, the rest on the central diagonal and corners).
- 1v1: whoever holds the diagonal and corners wins. Our columns along the map
  edges reach the far corners by 6 min (story-1v1/t002 frames 4-6), and 50% of our
  8-16 losses are on enemy ground — raids that trade. BARb loses 66% at home.
  12-9-1.
- 2v2: BARb has 8-9 mexes at 4 min vs our 4-5, a plant at map centre by 4-6 min
  (labassist/t006 frames 4, 6, 8: red plant square at centre) and LLTs along the
  diagonal by 8 (story-2v2/t002 frame 8). We hold 6-7 mexes from minute 8 to 20.
  Our units go up the diagonal as a thin north-south line at x~600-1000 (frame 10)
  and die there (frame 12 of both). 0-14-7. 59% of our metal dies at home.

**Supreme Isthmus** (8v8; our 8 starts in the NE quadrant, BARb's in the SW; one
diagonal isthmus with the mid mexes on it).
- BARb has a column on the isthmus at 4 min and is at the isthmus mouth on our
  side at 6 (163553 frames 4-6; 185914 frame 6). Its mid-ground mex count: 0.3 at
  6, 1.0 at 10, 5.0 at 12, 7.3 at 16, 9.5-10 at 20-24; ours 0.0 / 0.0 / 0.7 / 1.3 /
  0.0.
- We lead in income from 6 to 10 min (125 vs 103, 254 vs 211) and in army from 8
  to 16 (27.6k vs 19.6k, 77.9k vs 46.3k at 16 in 163553), with our units posted as a
  ring round the NE quadrant (185914 frames 8-10, blue perimeter). The fight sits at
  the mouth on our side of it from minute 10 on (x marks, 163553 frames 10-20).
- BARb passes us in income at 12-14 (348 vs 329, 1043 vs 532 at 14 in 163553) with
  62 vs 32 mexes, then 2604 vs 1308 at 28 and 572k vs 189k army. 055126 (1v1) shows
  the mechanism in isolation: BARb `conv:11` finished by 8 min, income/mex 18.9 vs
  our 5.5 at 22 min.

## 5. The five most consistent differences (by how often they appear)

1. **Army at home** (every class, every game). Front median 0.31-0.35 for us from
   minute 6 to 24; BARb 0.40-0.43 from 12 on. At 4 min on CC ours 0.25 vs 0.43.
   Line: story.py `front` column, any game; `apex: withdraw ... recall-home` 1600x.
2. **Mexes: theirs first, mid, and guarded** (team games from 4 min, CC 1v1 from
   8). Medians 12 vs 8 (CC 2v2 at 6), 8 vs 5.5 (GP 2v2 at 6), 10 vs 7 (CC 1v1 at 8);
   mid-ground mexes 0.0-0.4 vs 0.7-2.6 through minute 12; mid towers 63 vs 357 at
   10 min. Line: story.py `mex (home/mid/en)` column and `built def:` field.
3. **Income per mex** (from minute 14 in every class). 9.1 vs 10.0 at 16, 10.1 vs
   14.3 at 20, 15.3 vs 22.5 at 28; BARb had the first fusion in 64 games to our
   16, a gantry in 55 games to our 13. Line: techtime `fus/gantry/inc20/inc30`; story.py `inc` vs `mex`.
4. **Several groups instead of one body** (2v2 CC 6-16 min, GP 1v1 8-16, 8v8 6-8).
   Cohesion 0.11-0.18 vs 0.44-0.19 (CC 2v2), 0.26-0.15 vs 0.49-0.57 (GP 1v1
   10-16); lone share equal. Line: `[BARAI_ARMY]` snapshots; pictures holdground/
   t001 frames 8-12, story-1v1/t001 frames 10-19.
5. **Static defence and the T3 finish** (every game past 16 min). Def share of
   spend 19-20% vs our 6-12% from 14 min; 37% of BARb's building metal by 22 min;
   T3 is 37% of BARb's standing army at 24 vs none of ours; our T1-bot line (AK/
   Thud/Storm 92% at 8, Sumo/Can/Thud/Termite at 16) dies to Tiger/Banisher/
   Toaster/Doomsday/Juggernaut. Line: story.py `spent arm/eco/def/bp`, `lost ... to`.

Runner-up, 2v2 only: **a commander dies before minute 15 in 14 of the 43 2v2
games** (38 non-final deaths in all), 1.4k elmo from its start, to AKs and Pyros.

## 6. What the instruments could not tell me

- Why an army at 3x sits at front 0.34 instead of walking: no `apex:` line names
  the stance decision per bucket; `withdraw` reasons are per unit and `recall-home`
  is the bulk of them, but there is no line for "the body was ordered to hold".
- What BARb is doing with its metal between mexes and income: converters show as
  `conv:` in built (cheap, so 0-2% of metal) — the energy → metal conversion is not
  in any gadget line, and neither is either side's energy income or bank.
- Whether our mid-map units at 8-12 are raids, escorts, posts or leftovers: ARMY
  snapshots have position and health, not the task; `apex: posts/frontline` lines
  exist but are not in the story instrument.
- Why the T2 lab takes 3.5 minutes for us and 1.5 for BARb (start vs finish): no
  line reports assist count or stall on a specific build.
- What the commander was elected to when it walked 1900 elmo out (holdground/t005
  9.0 min `com-pos fwd=0.52`): `decide/exec` lines in that window are all
  `request held/new` for other builders; `curTask=t4b-1f` at death in all 62 cases
  is not human-readable.
- The +100% handicap: `mInc` is post-handicap for both, so per-mex income
  compares fairly, but the base (unhandicapped) numbers are not logged.
- 8v8: only three games, all draws by clock (20, 24, 31.7 min). No 8v8 decided game
  is in the corpus.
- The pictures cannot show who is shooting whom; x marks are deaths in the last
  two minutes without the killer, and clustered dots may be a body or a queue.
