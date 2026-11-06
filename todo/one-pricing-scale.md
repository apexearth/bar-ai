# Replace the overrides with one pricing scale -- THE CURRENT JOB (his 10-19, restated)

His 10-19: "I'm trying to get us to not have to rely on so many overrides and for our evaluation system to really be
correct. Everything needs to have a proper value, even the roles that were assigned to constructors. Ideally, we
don't even need those... if we didn't need them, I wouldn't want them." And the principle: "a constructor, a solar,
metal, all of these things are what let us create those other highly valued units, and thus all these things could
inherit/embody some of the value of what they allow the creation of."

**The principle.** Only what wins the game has value of its own. A resource or enabler is worth the share of the
value it makes possible: an extractor is worth the metal it adds times what metal buys now; a solar, its energy times
energy's price; a constructor, its build power times build power's price plus what its unlock allows; a lab, what its
line produces. Then the army's scale flows into everything that funds it, and only ratios decide.

**Every single spend (his 11-05: "every single spend we make needs to be considered in this way"), in the shared price and the election, never per kind.** **What each choice takes away from (his 11-05, watching v0.5.06: "when we make decisions about what to do we never
think about what we're taking away from in our choices").** A price is the option's gain against the best other use of
the same metal, builders and time, never its gain alone. The tests it must pass, from his All That Glitters 8v8:
- a builder leaving an unfinished frame pays for that frame's sunk metal and its delayed output (75 T2 extractor
  frames left under 10% built across our 8 seats);
- a plant is priced against the army the same metal and build power would field now (every seat bought a T2 air
  lab while far behind on army);
- a new site is priced against slowing every site already open (50 m/s split six ways instead of finishing the
  extractor upgrades first). His words: "it's always 'more of this, more of that', never 'oh, I'll just make
  building that mex take LONGER'." The cost of a new job is TIME on the jobs it shares income and hands with: each
  one finishes later, and its output is lost for the delay.

**Measured 11-05 (benches mexhold, focus1, focus2 vs v0.5.06, 24 1v1 pairs each vs BARb hard).**
- Extractors paying the in-flight delay like every other build (price.as `isMex`): unfinished extractor frames
  12.8 -> 7.9 a game, all unfinished frames 38.6 -> 30.5, income at 12 min +7 (t 0.9). Kept.
- Doing nothing (price.as): a start whose delay charge exceeds its gain over the payback horizon is worth 0 --
  fired ~420 seat-minutes in 24 games; with the above, wins 1 -> 4 (t 1.4), income at 12 min +5.3 (t 1.7). Kept.
- Charging every start the help it forgoes (assist gain x horizon, in the election): WORSE -- metal lost +36%
  (t 2.2), jobs failed +34% (t 2.5), army -35%. Removed. Why: gains are not metal. A T1 mex bid gain=55.96 with
  nn=21.8 (it yields ~2 m/s): growth premiums and the network's multiplier ride on gains, so a charge in real metal
  is crushing for some wants and nothing for others. The help price sits at a median 0.001 of the start that wins
  for the same reason. Opportunity cost needs every gain in one currency first -- this job.
- Live build requests per seat did not move (~15 mean, ~27 peak in 1v1; 39 / 90 in his 8v8): starts still
  outnumber what the hands can finish. `tools/focus.py` reads it; `apex: help-stat` reads help beside every start.

**What is wrong today (measured 10-19).**
- Two currencies. Army gain is gap metal x a strength factor; a con's is income in m/s. In a T2 bot lab
  (matches/labbest) the T2 con read 20-490 against Zeus 8k-347k, Fatboy 37k-1.3M, sniper 31k-2.2M.
- The strength factor runs away: UnitPPC (with its range/worth/hold modifiers) over the line's best UnitCore
  (without them) -- the sniper read p=54 (pc=15.9 before sight/screen/afford).
- Labs choose by a value-weighted lottery (b16e31e8, 08-23), so even a correctly top-priced con loses two times in
  three (his game: Incinerator 784 drawn over the T2 con 2,494). TUNE_LAB_BEST (b3ad8ed9, off) is the best-priced
  pick; on only after the prices are fixed.
- Builder decisions that skip the price, two 22-min 2v2s (~2,250 each): draw (category lottery) 40-46%, ladder 15%,
  role 9-10%, field 7-10%, metalfirst 3%, estall 3%, then commetal, nanofloor, comescort, held, upfirst, super,
  defpanic, open. Also the hoists: defjoin (v=1000), advanced-defence role, basefront, coverall. The four still to
  become prices first: `issues/exceptions-to-price.md`.
- Pieces that already reach for inheritance, each from one corner: energy priced by the metal it converts to
  (EPriceFloor), TUNE_INCOME_ACCEL, the con's upgrade term (T2CON_UNLOCK), TeamTechMul. TUNE_ARMY_ONE_CURRENCY (off)
  was measured alone with the runaway factor in place and hurt the army (0.52/0.72 of theirs vs 0.76/1.34 off, his
  +100 scav 8v8).

**The steps, in order. Each is measured before the next; tick it here with the commit and the number.**
1. [x] A live price per resource (e1ee2abb, `apex: vscale`, each kind's top value per minute; read-only).
2. [ ] Enablers priced from those prices (mex, energy, converters, cons, nanos, labs). Labs started: the advanced lab
   inherits its upgrades' prices and takes its time as a horizon share (016cd027: first T2 lab 9.0/6.3/7.4 min against
   16.6/12.9/10.4, upgrades before minute 15 9/4/4 against 0/0/0, one game). Every income stream takes its time as a
   horizon share (geo joined 10-20; converters already did).
3. [ ] The army strength factor normalised against its own measure (line's best UnitPPC = 1), with one currency.
   10-20 root cause: army values are metal/s (the 09-07 x cost), a con's metal/s per metal (Fatboy 2,114 vs T2 con
   0.28). The consistent form (min(gap, cost x p)/fill, per metal; 4cb87bbf, off) starved the early army in 2 of 3
   games: army has no per-metal value of its own yet. What it is worth is the loss it prevents -- what of ours is
   reachable by their army, times how much likelier we keep it with this unit added (ours vs theirs at the fight, the
   calibrated estimate), over the horizon -- plus what it can take from them. Build that as the army's gain, then
   retry one currency + TUNE_LAB_BEST.
   Calibration 10-20, ~50 2v2 games vs BARb (tools/lossfit.py / defeatfit.py), by army ratio r = ours/theirs:
     our structure losses: 11.5-11.8%/min of our assets at r < 0.35, 10.0% at 0.35-0.5, 8.5-8.8% at 0.5-1,
       6.4% above 2.5 (slope ~3.5%/min per unit r below 1);
     eliminated within 10 min: 39% (r < 0.1), 18% (0.1-0.2), 11% (0.2-0.35), 5.6% (0.35-0.5), 1-2% (0.5-1),
       0% above 1 -- fits P = 0.5 exp(-r/0.15);
     their losses (BARb side): ~1.8%/min of their assets while we are under 0.4 of them, 2.8-3.2% at 0.4-1.
   Priced from these, a metal of army returns ~0.005-0.01/s at realistic numbers -- above an extractor only near
   defeat. The open question for him: the builder values carry growth premiums (apex_mex_growth up to 8x) that a raw
   extractor return (~0.035/s) does not; either those overstate economy, or observational data (weak economies field
   small armies) cannot separate cause and effect here. Needs his call before the army price is built on it.
4. [ ] TUNE_LAB_BEST on; then the builder category draw replaced by the best-priced pick the same way (TUNE_DRAW_BEST,
   e3a306b1, exists, off).
5. [ ] Each override above A/B'd off, one at a time, and deleted when the pricing already chooses what it forced
   (ladder, roles, field crew, metalfirst, estall, ...). A role that still wins its A/B marks a missing price term:
   find the term, add it, then delete the role.

Tests: normal games vs v0.3.2 and BARb (not only his heavy setting); counters per step -- T2 cons per T2 lab and each
new lab's first unit, mohos by minute 12 per seat, why= shares, army vs theirs, result.
