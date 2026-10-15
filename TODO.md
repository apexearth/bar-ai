# Plays and behaviours he has asked for, not yet built

The sketchbook: named plays and unbuilt behaviours in his own words, kept because nothing else
records them. `ISSUES.md` is what is wrong now; `USER-FEEDBACK.md` his open asks;
`docs/doctrine.md` the principles. An entry is deleted when built and measured. Where a play is
phrased as a bar ("at 150 metal/s, build a gantry") it is a symptom at the income he was watching,
not a number to code. The fight layer is stock BARb since 2026-09-07, so squad behaviour below is
C++ work on top of stock. Older text: `git log -p TODO.md`.

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
