# Ground defence never reaches its target: the funnel (2026-10-09)

The 121-game 2v2 vs BARb batch (20261008-054849). The exemption of step 14 while DefenceShortfall() > 0 is
UNMEASURED (`apex: def-funnel`). Still open, read off the funnel:
- **Executor refuses 68% of ground-gun attempts** (43k): grave 9.5k, takeNull 9.7k, interior 7.3k, ferry 2.8k,
  ok 13.8k. coverall 89.6% refused (26k the same site again), basefront 58%. Fixes to interior/sole cover/
  relocation/folding are built and UNMEASURED (`apex: def-refuse`).
- **Value at min 10-20**: when a defence want IS in a draw list the best rival is 6.6x it (median); draw sharpness
  2.9 makes that ~1% odds. After min 20 the ratio is 0.66 and defence wins when present.
- **The gap is counted twice on pull-priced slots**: the pull is gap/180 s, and the want is then multiplied by
  TargetFill = gap/target again (protect_want.as `gDwFill`), so value goes as gap^2/target there.

## T2 guns come late and are the slow ones (same batch)

T2 ground guns per side: us 6.9 / 16.6k metal a game, BARb 14.3 / 30.0k. Our first T2 gun stands at median min 22.4
(none in 35 of 121 games), BARb's at 18.1; their first armed T2 ground unit reaches 1500 of a core at 15.8. When
2000+ metal of their T2 is that close we have ZERO T2 guns standing in 66 of 92 games (BARb: 19 of 54). Mix: we
build Annihilator / Doomsday / Legion popup (2.3/2.1/2.1 a game) and almost never the quick T2 guns (Pit Bull 0.16,
Viper 0.12, Toaster 0.13, Ambusher 0.07); BARb builds Viper 2.8, Pit Bull 1.8, Toaster 1.9, Ambusher 1.7. Wins 12.0
T2 guns, losses 1.0. Head `deftype` (protect_nntype.as) records the class choice against it.
