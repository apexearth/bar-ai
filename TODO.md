# Plays and behaviours he has asked for, not yet built

The sketchbook: named plays and unbuilt behaviours in his own words, kept because nothing else
records them. `ISSUES.md` is what is wrong now; `USER-FEEDBACK.md` his open asks;
`docs/doctrine.md` the principles. An entry is deleted when built and measured. Where a play is
phrased as a bar ("at 150 metal/s, build a gantry") it is a symptom at the income he was watching,
not a number to code. The fight layer is stock BARb since 2026-09-07, so squad behaviour below is
C++ work on top of stock. Older text: `git log -p TODO.md`.

# Army control redo (his 10-16: "the bane of this AI")

Too many separate systems order the same units. Replace them with one simple layer he can reason
about: an Army says what it wants (attackArea, defend, hold), Squads own their members and do their
own thinking each update (moveTo, attack, setTarget, assessThreat, join), AirSquads search and
strike. Nothing else commands a squad's units. Step 1: TUNE_STOCK_ARMY (our economy, stock BARb army
control) as the floor; then the squad layer, piece by piece, each beating the floor in a few games.

# Know them, then hit with conviction (his 10-22)

His 10-22, after a player said our AI is "too afraid of static defenses": *"our AI needs more scouting. It
often doesn't understand what the enemy has and isn't sure what to do. Obvious answer is to make air scouts and
use them to help the army understand what they're up against."* *"our air attacks stay small when they need to
get bigger."* *"massive attacks work better than lots of small attacks. you have to fight with conviction,
hesitation will be the downfall."* *"To fight against enemy AA we can throw cheap scouts in first."*

- [ ] **Scouting the army can use.** Air scouts priced by what an unknown costs the army: a fight decision made
  against a blind guess (FoeKnown false, stale ghosts) is worth what a look would change in it. The look feeds
  the army's own assessment of what it faces, not only the bomber wing's target choice (LookGainFor today).
- [ ] **Too afraid of towers** (a player, 10-22): replay his v0.3.5 game of 10-22 (the one before the hosted game
  that night) and measure where the army stopped short of a tower line it could have taken. Likely the stock
  threat map's read of static guns.
- [ ] **Bigger air strikes.** A wing goes when it is big enough to finish its target, not on a cadence; small
  repeated strikes into AA are the failure. Cheap scouts or decoys first to draw the AA.
- [ ] **Mass, then commit.** One big attack over many small ones; once committed, no trickle-back. The army
  waits to gather by price (what the extra mass wins), then goes and does not hesitate.
- [ ] **A style per seat** -- *"strongly prefers air"*, not "always goes air". A modest price tilt the policy net
  can see as an input (so training is not confused), per seat, never said in chat. Each style screened against a
  neutral seat and its tilt cut until it costs no more than a few percent. Never forced: a liked option wins close
  calls, never clear losers (*"we don't want to get things so out of whack that the whole AI breaks down"*).
- [ ] **Adapt when something stops working** -- *"Right now we do a lot of air, humans realize it eventually and
  just make tons of AA... so what we need to do is something OTHER than air at that point"*; *"Need some way to
  better adapt to whats going on in games. if one thing isn't working, we have to learn/try something else."* As a
  price, not a rule: each investment's worth learns from its realized return this game (an air strike's metal
  killed per metal sent and lost, a ground push's, a nuke's), so a line that keeps failing prices itself down and
  the money goes to what is working. Their AA seen is already an input; this closes the loop on outcomes.
  Measured 10-23 (his game): bombers already learn from scored runs, too slowly -- a run's damage per bomber moved
  the model's prior by half whatever its size, so 89 Shadows lost in four runs for nothing still priced at 177-1,296
  metal each, above their cost. A run now weighs by bombers sent over the wing planned (apex_air_obs_evidence, on).
  Ground types have the record (worth.as RecordMul); gunship runs are not scored yet.
- [ ] **Some seats more aggressive** (10-22, with the style per seat): a lean toward taking fights and pushing,
  as part of a seat's style, not a separate rule.
- [ ] **Allies agree a timing**: *"the AI could suggest to each other that at a certain time they'll all go air
  and do a massive air attack, things like that would be crazy and fun."* A team plan names a time and a kind
  (all air, all T3 ground); each seat's tilt leans toward it until the strike, then back to its own style.
- [ ] **Rich: more T2 air plants, more air** (his 10-23: "when you're rich, make more T2 air labs, make more air").
  His 10-23 watch game, seat 0 at 1,238-1,310 m/s: one advanced air plant (a second at minute 35); the plant's
  line read `armblade: wing0(full 120(pool120)/59)` -- ScaledBombers (state.as) is a COUNT, AIR_BOMBERS plus one
  per AIR_SCALE_INCOME of income plus an AA soak, and past it StrikeGainWing prices the next bomber at 0, so
  neither more bombers nor another plant is ever worth anything however rich we are. As a price: the next bomber
  is worth what it adds to the strike (MarginalGain, measured per bomber once runs are scored), no count; spilled
  metal is cheap (MCostScale), so a rich seat buys air while it pays and plants follow the demand.
- [ ] **Punch through their AA: strike the air defence itself** (his 10-23: "you're trying to punch through the
  enemy's air defense... this might mean you attack the air defenses directly"). The strike planner's targets
  are economy only (NaSnapEnemy gNaEcoP); AA enters only as a cost, so a base ringed with AA offers nothing worth
  a small wing (his game, Cortex seat: the cheapest paying wing was 58 Phoenixes for 106 net). As a price: an
  AA site is a target worth its own metal plus what it stops protecting -- the next runs' losses it no longer
  causes over the cells behind it.
- [ ] **Gunships commit or stay home** (his 10-23 watch: a 40-gunship wing lingered over their base without
  attacking while bombers and fighters struck; against humans it would all die to AA). NaDecide sends the wing
  at a cell priced against their AA (`nnair-go gunships n=40 ... killF=0.24 lossN=40`); the C++ raid task then
  commits with no target (`raid-commit ... target=- aaSet=24`) and refuses each one under AA, so it circles. One
  judgement: the raid takes the target the decision priced; the decision counts the wing it expects to lose.
- [ ] **Air scouts for the army** (his 10-23: no scout planes to see how strong their base is; 0 `air look`
  flights in 37 minutes). LookGainFor prices a look only by what it adds to the first bomber's prize; add what
  the army gains from knowing whether their base can be pushed.
- [ ] **Ultra-late air to end the game** -- *"Eventually we just make mostly T3 and we kinda stop to make air it seems.
  Air is still a good way to end a game. We should invest more into air in ultra late game and do huge air raids,
  something to try to end the game. Instead it feels like we do less."* His 10-22 hosted game (8 seats, v0.3.5):
  air orders per 5 min 70-80 to minute 45, then 23 and 22 while T3 took 61-70; 12 air plants ordered in minutes
  50-55. Lag from minute 35 (sim 0.94-0.96). NOT the lag ladder: its lower-tier stop (production.as) exempts air
  lines; the cause is still open (his 10-23 game, 4 seats: air peaked at minutes 15-20 and fell as ground rose).
  As a price: a mass strike that can end the game (their economy or commander) carries its
  decisive worth, not a unit's trade value, and pairs with the team timing below.
- [ ] **Stop re-nuking blind** -- *"we keep nuking spots we've already landed several nukes on. If we landed 2+ nukes
  there but we haven't rescouted there and don't know what's up, then we should stop nuking there."* As a price,
  not a count: each landed nuke cuts what the target is believed to still hold (by the blast against what stood
  there); nothing restores it without a fresh look, so a spot hit twice since its last scouting prices near zero
  and a rescout of it becomes the valuable move. A look that shows it rebuilt brings the price back.
- [ ] **Reclaim idle turrets while the host lags** -- *"one additional thing we can do when the host is lagging, is
  to reclaim nano turrets which are idle."* In the reclaim market: an idle turret's keep value (the chance work
  enters its reach soon x its rebuild cost) against its running cost, which rises with the measured lag (Perf's sim
  speed against wall time); the farthest-from-work idle turrets go first and return their metal. Our own only;
  a turret a coming build will need keeps its value, so nothing is reclaimed and rebuilt a minute later.

# Next big job (his 10-15: "we'll do it later")

## Replace the overrides with one pricing scale -- THE CURRENT JOB (his 10-19, restated)

His 10-19: "I'm trying to get us to not have to rely on so many overrides and for our evaluation system to
really be correct. Everything needs to have a proper value, even the roles that were assigned to constructors.
Ideally, we don't even need those... if we didn't need them, I wouldn't want them." And the principle: "a
constructor, a solar, metal, all of these things are what let us create those other highly valued units, and
thus all these things could inherit/embody some of the value of what they allow the creation of."

**The principle.** Only what wins the game has value of its own. A resource or enabler is worth the share of
the value it makes possible: an extractor is worth the metal it adds times what metal buys now; a solar, its
energy times energy's price; a constructor, its build power times build power's price plus what its unlock
allows; a lab, what its line produces. Then the army's scale flows into everything that funds it, and only
ratios decide.

**What is wrong today (measured 10-19).**
- Two currencies. Army gain is gap metal x a strength factor; a con's is income in m/s. In a T2 bot lab
  (matches/labbest) the T2 con read 20-490 against Zeus 8k-347k, Fatboy 37k-1.3M, sniper 31k-2.2M.
- The strength factor runs away: UnitPPC (with its range/worth/hold modifiers) over the line's best UnitCore
  (without them) -- the sniper read p=54 (pc=15.9 before sight/screen/afford).
- Labs choose by a value-weighted lottery (b16e31e8, 08-23), so even a correctly top-priced con loses two
  times in three (his game: Incinerator 784 drawn over the T2 con 2,494). TUNE_LAB_BEST (b3ad8ed9, off) is
  the best-priced pick; on only after the prices are fixed.
- Builder decisions that skip the price, two 22-min 2v2s (~2,250 each): draw (category lottery) 40-46%,
  ladder 15%, role 9-10%, field 7-10%, metalfirst 3%, estall 3%, then commetal, nanofloor, comescort, held,
  upfirst, super, defpanic, open. Also the hoists listed before: defjoin (v=1000), advanced-defence role,
  basefront, coverall.
- Pieces that already reach for inheritance, each from one corner: energy priced by the metal it converts to
  (EPriceFloor), TUNE_INCOME_ACCEL (income credited with the in-flight jobs it speeds), the con's upgrade term
  (T2CON_UNLOCK), TeamTechMul. TUNE_ARMY_ONE_CURRENCY (off) was measured alone with the runaway factor in
  place and hurt the army (0.52/0.72 of theirs vs 0.76/1.34 off, his +100 scav 8v8).

**The steps, in order. Each is measured before the next; tick it here with the commit and the number.**
1. [x] Instrument a live price per resource (e1ee2abb: apex: vscale shows each kind's top value per minute) -- what one more m/s of metal, e/s of energy, unit of build power
   would buy now (value per cost of the best wants going unfunded, army included). Read-only; one game of
   numbers shown to him before anything uses them.
2. [ ] Enablers priced from those prices (mex, energy, converters, cons, nanos, labs). Labs started: the advanced
   lab inherits its upgrades' prices and takes its time as a horizon share (016cd027: first T2 lab 9.0/6.3/7.4
   min against 16.6/12.9/10.4, upgrades before minute 15 9/4/4 against 0/0/0, one game). Every income stream
   now takes its time as a horizon share (geo joined 10-20; converters already did).
3. [ ] The army strength factor normalised against its own measure (line's best UnitPPC = 1), with one
   currency. 10-20: root cause found -- army values are metal/s (the 09-07 x cost), a con's metal/s per
   metal (Fatboy 2,114 vs T2 con 0.28). The consistent form (min(gap, cost x p)/fill, per metal; 4cb87bbf,
   off) starved the early army in 2 of 3 games: army has no per-metal value of its own yet. What it is
   worth is the loss it prevents -- what of ours is reachable by their army, times how much likelier we
   keep it with this unit added (ours vs theirs at the fight, the calibrated estimate), over the horizon --
   plus what it can take from them. Build that as the army's gain, then retry one currency + TUNE_LAB_BEST.
   Calibration 10-20, ~50 2v2 games vs BARb (tools/lossfit.py / defeatfit.py over matches/oc, drawbest,
   roles, crew, labbest, scale), by army ratio r = ours/theirs:
     our structure losses: 11.5-11.8%/min of our assets at r < 0.35, 10.0% at 0.35-0.5, 8.5-8.8% at 0.5-1,
       6.4% above 2.5 (slope ~3.5%/min per unit r below 1);
     eliminated within 10 min: 39% (r < 0.1), 18% (0.1-0.2), 11% (0.2-0.35), 5.6% (0.35-0.5), 1-2% (0.5-1),
       0% above 1 -- fits P = 0.5 exp(-r/0.15);
     their losses (BARb side): ~1.8%/min of their assets while we are under 0.4 of them, 2.8-3.2% at 0.4-1.
   Priced from these, a metal of army returns ~0.005-0.01/s at realistic numbers -- above an extractor only
   near defeat. The open question for him: the builder values carry growth premiums (apex_mex_growth up to
   8x) that a raw extractor return (~0.035/s) does not; either those overstate economy, or observational
   data (weak economies field small armies) cannot separate cause and effect here. Needs his call before
   the army price is built on it.
4. [ ] TUNE_LAB_BEST on; then the builder category draw replaced by the best-priced pick the same way.
5. [ ] Each override above A/B'd off, one at a time, and deleted when the pricing already chooses what it
   forced (ladder, roles, field crew, metalfirst, estall, ...). A role that still wins its A/B marks a missing
   price term: find the term, add it, then delete the role.
Tests: normal games vs v0.3.2 and BARb (not only his heavy setting); counters per step -- T2 cons per T2
lab and each new lab's first unit, mohos by minute 12 per seat, why= shares, army vs theirs, result.

# Team T2 (his 10-19)

## Fly the tech seat's T2 constructors to the allies

One seat goes T2 and hands T2 cons to the rest (TUNE_TEAM_TECH; all seats going T2 at once is the bad case).
His 10-19: "if we do make T2 for allies, we can have or be given by teammates a transport plane so we can
deliver the T2 constructors to our allies quickly." The lift that moves nano turrets (lift.as) is the carrier;
price the flight as the walk it saves the receiver's upgrades. No override: the tech seat's T2 is priced like
anyone's, and a receiver's own lab is worth less by the handouts that cover it (TeamTechMul).



## The economy ramp (his 10-20, watching the +0 eco test)

Run `python tools/ecotest.py` (+0, NullAI, eco only; `--ai-option apex_first_lab=3` opens with air). His notes
from the air-first watch game: "sometimes we choose to make fusion plants where we have no nanos nearby, also we
spread ourselves out on too many mex upgrades at once, restrict to fewer and assisting more would cascade the
progress better, also anticipating future nanoturret needs ahead of time would allow us to scale more properly."
And earlier: "eventually reclaim the T2 bot lab if you need the metal for fusion or the T2 air lab, then go into
air cons"; no hover lab in an eco game (0 economic benefit); the T2 lab beside the turret block.
- [ ] Fusion and other big builds land at the turret block (BigEnergySite / LatheSite).
- [ ] Fewer mex upgrades at once, more hands on each: a new upgrade is charged for the ones it slows.
- [ ] Turrets bought ahead of the work that will need them.
- [ ] The T2 bot lab reclaimed once the T2 air lab stands and its metal is wanted.
- [ ] The commander stays home on the plant and home work; every slow hand pays its share of the walk home. In a war game, field defence counts as field work too.
- [ ] T1 air cons keep coming while metal overflows.
- [ ] Build near idle turret rings; while overflowing, idle ring sites take whatever is needed most; more frames at once while turrets idle.
- [ ] Transports move idle turrets to the work (lift.as flies them; in eco no plane is priced, and the sink is "outside every turret circle", which a big base never has).
- [ ] Anticipate needs: converters before the AFUS finishes; the same look-ahead for turrets, storage and the next generator.
- [ ] No plant whose builder is dominated: a slower builder at the same or lower reach than one we already make adds no hands (his 10-20, the vehicle plant beside the air plants).
- [ ] Tight packing (his 10-20: "snapping to nearby same-size buildings"). Within a def the lattice already tiles; the waste is between defs -- each def has its own lattice at its footprint pitch, so a 3-cell turret block meeting a 5-cell fusion block leaves 1-4 square strips (his watch game: 191 such gaps against 555 flush; 107 off-lattice, 79 of them turrets filling those gaps after 22 lattice cells taken). His layout is blocks of one kind scaling in one direction; that is a placement redesign, mostly in the C++ cell choice -- ask him first.

Tried 10-20 as switches, each one per symptom, and deleted: paired eco games found none of them better
(future job, smoothed fullness, reach once, cons as lathe raisers, idle-ring siting, lift sink, converter
anticipation: -5%, se 11%, at 28 min as a set; turret energy cost -31%; assist energy feed -27%; lab order gain
-12%/-3%; realize-to-capacity -30%). The numbers are in the commits 26b63ab1, ce756327 and the one after; the
lesson is in memory no-switch-bloat: find the shared cause.
## Teammates fund the tech seat (his 10-19)

"So the right choice is to keep boosting our income until we feel more comfortable making the T2 lab. Also if
we boost or have 1 of our guys go T2 early on a team game then that can be fine too. We just need to have
someone be willing and then the teammates can depend on them for the upgrade, they could even send metal to get
their T2 con sooner." Team tech elects the seat and its lab now inherits the allies' upgrades it serves
(TUNE_LAB_INHERIT); not built: allies send metal to the tech seat while its lab or first T2 con is short, priced
as the upgrades the metal brings forward (the gift path already has ai.SendResources).
# Strategies

## Abuse the BARb AI the way humans do

His frame of mind (2026-09-01): *"make them attack us when they're more powerful; eat their
wrecks; keep making more military; don't waste it; grow; overwhelm the enemy; use cheeky
strategies/squads; stand at enemy border and siege them long range; let them come at our army
while we stand still and defend, using rezbots, twitchers, etc to heal our tanks."* One doctrine:
every item is a way of not walking into their guns. Missing: a deliberate "hold and let them come"
posture distinct from attack (the bait), healers inside the ball, and battlefield reclaim after a
won fight treated as an income stream.

## Two squad doctrines: the siege screen and the deep raid

*"The tanks should just stand around in front of the sheldons. They'll take hits if they have
to, but they won't walk up to enemies to shoot at them... It's a bit of a siege mentality
really."* And: *"We can also just YOLO attack deep into the enemy... blast through the front line
and make it into unguarded economy in the backlines and then run around dealing free damage."*
Siege screen: carry at its own range, screen between enemy and guns, a short-range unit bought as a
shield (`TUNE_SCREEN_GAP` is read by nothing since the revert). Deep raid: the decision to spend a
squad this way, and the target once through. C++ work.

## The anchored range ladder: one Mammoth, everyone guards it

*"I can take 1 mammoth, 1 radar, jammer, 10 sheldons, 5 arbiters... and have everyone guard the
mammoth, and then give the mammoth a fight order towards the enemy base. This army can literally
take out the entire enemy base."* Each rank outranges the anchor in front of it, so only the
anchor is seen. Missing: the range-ladder valuation (a reach unit is protected by a shorter-range,
high-HP anchor, not by a metal share of "meat"), the formation (guard the anchor, anchor gets the
fight order), radar and jammer as squad members, and more anchors for a bigger ball (*"just add
more mammoths"*).

## Surprise air eco attack (a strategy to swap to mid-game)

20+ fighters and 20+ T2 bombers, or T3 Dragons, invade by going around their army (*"don't
retreat!!!!"*) and hit constructors, economy and build power until dead. A suicide attack for
maximum economic damage.

## Tick spam (late game)

At 20-30 min+, against big or long-range units, spam Ticks (or Grunts, Pawns, Rascals): ungrouped,
straight to the front and as deep into their base as they get, for vision and distraction. Fodder,
not army. (`TUNE_SPAM_RAIDERS` covers the raider class; the deliberate late wave is not built.)

## Nuke spam

Before the enemy is ready the whole team goes for nukes, saves several, and around minute 18
launches them all on different enemy bases; then reclaims the launchers and plays normally.
Prefer a docile enemy; not against aggressive ones.

## Finish a won game: what a human would do to us

*"What a human would do to beat us in this particular game... mass nukes, naval attacks from the
side, or some big air attacks."* And: *"if you attack the enemy with like 50 marauders, all of a
sudden from the side, you'll really wreck the enemy good. We also lack LRPC cannons, and I never
see us make anything like a Ragnarok."* Plays: (1) nuke targeting from scouting; (2) the flank
(built 10-10, `CAttackTask::ChooseFlank`, unmeasured); (3) air used offensively; (4) scouts kept
alive as eyes; (5) a massed single-type strike from a side; (6) LRPCs and the Ragnarok priced in;
(7) (10-12) *"Whatevers making them afraid, why not call for air support? They totally have the
ability to win the game on their own if they were aggressive enough... We are dominant in many
games, we just don't capitalize on it"*: a push about to break off calls the air wing.

## The jammer ring: a stall that buys more time than the same metal in army

(09-21) When we cannot match their army: a jammer, HLTs inside its ring, nano turrets there, radar;
with T2, T2 defence in the ring; best a T3 turret with cheap turrets in front, all under the
jammer. Priced as time bought, triggered by the enemy field in reach against our own.

## Three detectors from one hosted night (08-19)

1. Exploit complacency: *"If enemy is not attacking us but just being defensive, we should form
   our own defense a bit more and take the time to scale our army."*
2. Push back when pushed: *"If the front line is moving back into us then we need to make more
   army and push it back."*
3. Defend the flank the front wraps around: a front-position memory whose bearing swings.

# Unbuilt behaviours

- **Stop buying what keeps dying for nothing** (09-16): a unit justifies itself when its damage
  dealt equals its health; fodder never judged; fighters never discounted. Built as the exchange
  matrix (`TUNE_RECORD_BITE`). Open, his idea: judge a squad, not a unit (*"based on our squad's
  composition, how did we do against this unit?"*).
- **Join a fight only if we get there in time** (10-08): *"by the time... they're gonna either win
  or be dead by the time our units even get there."* Built as the `reinf` head; unmeasured.
- **Formation spacing and squad membership by unit type, decided by a net** (10-11): *"snipers
  bunched up is often a bad idea"*; *"our air attacks should fly a bit more spread out."* Bombers
  built; ground spacing per unit and whether a unit joins a squad are open.
- **Metal maps** (10-08, Full Metal Plate): *"just make a lot of metal extractors, put them right
  next to each other."* Needs a per-AI extractor farm near its base, a new want kind; the shared
  spot list cannot carry it.
- **Fighter cover for air missions** (09-16): scouts, bombers and radar planes fly with fighters.
  Ground AA on the route is the bigger loss.
- **Never an idle factory while metal goes unspent** (09-16, four reports): *"UNACCEPTABLE, not a
  tuning question."* `RedrawFor` built; open: why a standing lab is idle, per lab per minute, and
  the share obligation read against metal USED, not built.
- **Tips:** late game, use air constructors (not near enemy AA: siting and whether to build them);
  the commander hovers cloaked under a jammer and D-guns enemy T3; artillery on hilltops.
- **Rez bots follow the attack group and RECLAIM what it kills** (08-09): *"prevent enemy from just
  resurrecting all their stuff."* A leash to the squad, not pulling bots off base work.
- **Scout the mex area first, then size the group to what is there** (08-09): the group size from
  the target's local influence, not a global quota.
- **A single T3 assault unit raids on its own around the rim** (08-09): *"Through the edge of the
  map they'll be very good."* Routing lever missing since the revert.
- **A basemap: defend territory, not a plethora of buildings** (09-05): *"If we use our army to
  defend structures then we don't need as much defense... a choice - mobility vs concentrated
  power."* Defence and army priced as substitutes for one hold.
- **Behemoths when the enemy is encroaching** (09-16): built as `apex_hold_corjugg` 2x; unmeasured.
- **LRPC on high ground** (09-16): built (`HighGroundNear`); unmeasured.
- **Air-lift turrets**: other destinations (a big frame, the held front line), freeing a stuck
  unit, more than one transport per class, and (10-07) moving BUSY turrets from a low-value job to a
  high-value one, priced by the move.
- **Escort strength scales with the trip's risk** (09-24): escort metal per worker against the
  threat expected at its site; danger priced as min(expected loss, escort cost) so risk buys
  protection instead of cancelling the trip.
- **Air-lift towers forward, army to raid or flank, a hidden base** (09-24): heavy transports only
  for towers (every tower is over the Stork's 750 mass; HLT, Claw and Maw cannot be lifted).
- **Building as he would think it** (09-20): start from the WANT: *"I want a fusion" -> "do I have
  a spare T2 con?"*; only when every hand is busy ask what taking one off costs. A team want list
  on its own cadence, a hand's election a lookup. (`TUNE_CREW_ELECT` is a step toward it.)
- **His four early-game directives** (09-22): guard our mexes with a turret; harass their
  engineers and mexes with Pawns/Ticks; minimize walk time and fortify what the commander walks to;
  keep enemies off our energy and converters. The last two are not built.
- **Spread the economy by the share we can afford to lose at once** (10-14): *"if the eco blows
  up, what % of my eco am I willing to lose all at once? It is a space-efficiency/risk kinda
  algorithm."* Not built.
- **Flank guards** (10-14): *"Enemies go around our defense towers and attack our economy
  freely."* Built as `TUNE_FLANK_GUARD`, off pending A/B.
- **Seat merge** (built, off): on a crowded map, fewer and stronger seats. Off because the kept
  seat did not play six commanders; it must send them out to claim, size labs and expansion to the
  hands it holds, and drop the eco role.
- **Host the AI from a lobby bot** (parked by him 09-30, *"we should not do this yet"*): proven
  locally with `tools/netproof.py` (dedicated server, a headless spectator owning the AI). Needs a
  SpringLobby bot, the room's engine and game installed, a warm cache, and the BAR admins' approval
  of a bot account.
- **Mass the long-range cannons** (10-18): one cannon may not get through their defence, but ten or
  twenty may, and then they have to spend on shields, which are costly. Today each cannon is priced
  as if it kills alone and the next one is worth less; nothing prices the volley that breaks a
  position or the shields it forces them to buy. Not built.
- **Find the lag on particular maps** (10-19): pathfinding is one of the big issues; units that are stuck
  or cannot reach their destination should back off, or the ground a unit type cannot reach should be
  blacklisted. Measured so far: in the 16-AI benchmark the engine is 75-85% of the late frame (34-51 ms
  a frame at ~3,000 units) and our path queries 98 s of worker CPU (317k); reclaim refused for threat now
  backs off (1dfb106f) and radar sites an ally covers are no longer chosen. Not yet compared across maps.
