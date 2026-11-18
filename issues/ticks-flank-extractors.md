# Ticks and scout cars take flank extractors at minutes 7-10 (11-18)

Since escorts went to stock BARb's `[2,1,600]` (6e494d6f), the raiders that used to sit beside constructors raid
instead (enemy extractors killed after minute 12: 44 vs 13 for v0.5.16; income at minute 20 251 vs 228). The cost:
vs BARb:stable:hard on Comet Catcher 1v1 +50, extractors lost to Ticks/scout cars before minute 10 were 3.10 a game
against v0.5.16's 1.00 (bb1, contract FAIL). The net extractor exchange is even again by minute 15.

**Not a screen problem.** From minute 6 our home army is 1,000-2,500 metal (sh2, `apex: leak-screen home=`), above
the 800 leak screen; it stands near home, not near the flank extractors, and does not go to them.

**Tried, dead:** the leak-screen term in `MexFloorFactor` (`1 - army/screen`, at most 1) never beats the gun floor
(`MexGunsWanted` >= 1), so neither ArmyValue nor a home-only count (`HomeArmyM`, sh1/sh2) changes any price. sh1's
1.85 was seed noise. The code was removed before v0.5.17.

**His call (11-18):** ship the escorts; take this up when the BARb fight and movement layer is replaced with our own.
That layer should send part of an idle home army to a raided extractor (`issues/mex-losses-vs-barb.md` has the older
DEFEND-pool half of this).
