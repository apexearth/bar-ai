# Strategies and behaviours he has asked for, not yet built

This file is the third list, and the narrowest. `ISSUES.md` is what is wrong
now; `USER-FEEDBACK.md` is the standing brief of what he wants; this is the
sketchbook -- named plays and unbuilt behaviours in his own words, kept because
nothing else records them.

Same lifecycle as the other two: **an entry is DELETED when it is built and
measured, never marked done.** Pruned 2026-09-15: constructor roles by share
(built, `roles.as`), dedicated energy builders (a role category), the eco base
layout (rows, no rear lanes, flush packing -- 09-14) and the C++ refactor list
(the six fight classes went back to stock BARb on 09-07, `docs/30`) are gone.

Read `docs/23-the-plan.md` before coding anything here. Where one of these is
phrased as a bar ("at 150 metal/s, build a gantry"), that is him reporting a
symptom at the income he happened to be watching -- it is not a number to code.
The AI reaches a play when the arithmetic says the play is the fastest path.

The fight layer is stock since 2026-09-07; every play below that needs squad
behaviour is C++ work on top of stock, not a re-tune of deleted code.

# Strategies

## Abuse the BARb AI the way humans do -- the standing doctrine

apexearth 2026-09-01, offered as frame of mind rather than a spec:

  "I want to see this AI abuse the Barb AI the same we humans do :-P
   - make them attack us when they're more powerful
   - eat their wrecks
   - keep making more military
   - don't waste it
   - grow
   - overwhelm the enemy
   - use cheeky strategies/squads like i mentioned
   - stand at enemy border and siege them long range
   - let them come at our army while we stand still and defend, using rezbots,
     twitchers, etc to heal our tanks."

These are one doctrine, not eight wishes. Every item is a way of NOT walking
into their guns.

  hold, do not charge   they attack us; we fight on our ground at our range
  heal in place         rezbots and twitchers repair the screen mid-fight, so
                        the same metal fights several times
  eat the wrecks        their dead army funds ours; the battlefield is the
                        richest reclaim on the map and it is where we already
                        are
  never idle production the line keeps running while the ball holds
  siege the border      the anchored range ladder, parked at their edge

WHAT IS MISSING: the POSTURE that ties them together -- a deliberate "hold and
let them come" mode distinct from attack, with the healers inside the ball
rather than following it, and battlefield reclaim treated as a first-class
income stream after a won fight. "Make them attack us when they're more
powerful" is a bait, and this AI has no way to express "I am deliberately not
attacking because their coming to me is worth more than my going to them."

## Two squad doctrines: the siege screen, and the deep raid

apexearth 2026-09-01, on what a short-range unit should do in a squad that has
artillery behind it:

  "the tanks should just stand around in front of the sheldons. They'll take
  hits if they have to, but they won't walk up to enemies to shoot at them.
  They're just protecting the ranged units. If they walk closer they'll take a
  lot more damage. They are there as a shield. This is how all our units should
  behave when in a squad with ranged units. The squad should seek to remain at
  max range, tanks should try not to get hit but still protect their ranged
  units. It's a bit of a siege mentality really."

  "But that's not the only option we have. We can also just YOLO attack deep
  into the enemy. The goal can be to just blast through the front line and make
  it into unguarded economy in the backlines and then run around dealing free
  damage."

### A. SIEGE SCREEN

    escort (no weapon):  hold at  highestRange + standoff
    carry  (longest):    hold at  ownRange
    screen (shorter):    hold at  carryRange - screenGap

The squad sits at the carry row's range ("remain at max range") and the screen
stands between the enemy and the guns rather than out ahead of them. A
short-range unit in a mixed squad is bought as a SHIELD, so it is worth
absorbing HP and body size there, not its own dps (the range-ladder valuation
below). `TUNE_SCREEN_GAP` (200) is still declared in `tunables.as` and read by
nothing since the 09-07 revert.

### B. DEEP RAID

Break the front line, get into unguarded economy, stay mobile dealing free
damage. Stock `CRaidTask` picks the target; what is missing is the DECISION to
spend a squad this way rather than on the front, and the target choice once
through. He knows: "These changes would require some updates to our C++ code.
We should keep working on this though as fixing our military composition is
very important."

## The anchored range ladder -- one Mammoth, everyone guards it

apexearth 2026-09-01: "I can take 1 mammoth, 1 radar, jammer, 10 sheldons, 5
arbiters... and have everyone guard the mammoth, and then give the mammoth a
fight order towards the enemy base. This army can literally take out the entire
enemy base."

"It just happens that the mammoth range keeps it far enough away from enemies
that usually only the mammoth is seen. The rest of the army behind it stays
hidden but can still shoot at enemies up front. The jammer keeps them off
radar. The radar gives LOS/radar. Arbiters give the extra anti-building damage.
If the AI doesn't actually form a squad like this then its much less valuable.
And when the mammoth dies well the whole squad breaks down fast."

    corsumo  Mammoth  2,200m  15,600hp  spd 22.5  range   650
    cormort  Sheldon    410m     940hp  spd 50.4  range   850
    corhrk   Arbiter    600m     610hp  spd 54    range 1,210

THE MECHANISM IS A RANGE LADDER: each rank stands behind the one in front and
still reaches, because its range is LONGER than the anchor's. Only the anchor
is inside the enemy's range. A reach unit is protected when an anchor with a
SHORTER range and enough HP stands in front of it -- not when the army holds a
given metal fraction of "meat". `ShieldShare()` = (tankM + midM)/totalM scores
his ball 0.24 and a homogeneous Thug ball ~1.0; metal share is the wrong
currency.

Squads already pace to lowestSpeed, so the engine does not refuse the mix.
Missing: (1) the range-ladder valuation; (2) the FORMATION -- everyone guards
the anchor, the anchor gets the fight order; (3) radar and jammer as squad
MEMBERS; (4) anchor fragility -- his answer "just add more mammoths :-P": the
anchor requirement is absorbing HP against what is incoming, so a bigger ball
wants MORE anchors, and the redundancy falls out of the arithmetic. No
single-point-of-failure rule.

## Surprise Air Eco attack! (special temporary strategy to swap to in the middle of a game)

Surprise the enemy by building up a force of 20+ fighters and 20+ bombers (T2), or T3 Dragons, invade enemy territory by ***avoiding*** enemy army (go around them, don't retreat!!!!) and attack constructors, economy, and keep going until dead. This is a suicide attack strategy for the units involved and the goal is to inflict maximum damage on their economy and build power.

## Tick Spam! (late game additive strategy)

In late game, like 20-30m+ in time, when theres lots of big bois or annoying long range units attacking you, you can distract them very well by spamming ticks at the enemy. Alternatives are grunts, pawns, rascals, wheelies, the cheap but fast units - we don't care about grouping up these units. They go straight to the front and run as far into the enemy base as they can. Their purpose is to provide vision and to be a distraction. These shouldn't get swept up into groups, or treated like normal army - they are fodder. (`TUNE_SPAM_RAIDERS` is on since 09-13 for the raider class; the deliberate late-game fodder wave is not built.)

## Stop buying what keeps dying for nothing (unit track record)

apexearth 2026-09-16. Keep a record, across games and within one, of how
each unit type performs, and discount the ones that keep proving useless:

- A unit has justified its existence when the damage it dealt equals its own
  health. Five times its health is a 5x. A 1,000-metal unit that dealt 50
  metal of damage is almost useless.
- Keep it simple: a moving average per unit type. It has to read bad
  continuously for some duration before the AI says "you're not worth it".
- **Fodder is never judged.** Its whole purpose is distraction; we know it will
  die. Keep making it. (In code that is the raider class the spam path sends,
  `hooks.as` / `TUNE_SPAM_RAIDERS`.)
- Open, his idea 2026-09-19: judge a squad, not a unit -- "this was our
  squad, and based on our squad's composition, how did we do against this
  unit?" -- so a tank is credited with what its squadmates dealt while it
  absorbed. Fuzzy by his own account; the class bar (a tank judged as a
  tank) is the simple form built instead.
- **Fighters are never discounted.** You always need fighters with aircraft.
  At most, T1 fighters may be discounted in favour of T2 ones.
- The engine tracks unit experience already; the AI can read damage dealt per
  unit through the damage callbacks, so no new bookkeeping in the game.
- Where it lands: the per-def worth multiplier (`worth.as` `UnitWorthMod`,
  hand-set today) becomes the measured ratio. A price term, not a ban.
- Stage 0 is the instrument: log damage-dealt/health per unit type at death
  and at game end, check the ranking is stable across a battery, THEN price.

## Fighter cover for air missions

apexearth 2026-09-16, watching scouts fly out alone and die to the first
enemy fighters. When we send scouts, bombers or radar planes out on a mission,
fighters go with them to guard them. (Stage 0 of the track record and this
are the same session's work.)

## Never an idle factory while metal goes unspent

apexearth 2026-09-16, from an 8v8 on Isthmus he watched. Our eco player got
very strong and stood about ten advanced air labs -- and they sat idle much of
the time while we spent only about half the metal we were making. There was no
excuse: with that bank and that income the labs should have been pumping out
air without pause. An idle factory next to unspent metal is UNACCEPTABLE, not
a tuning question.

This is the third report of the same class (gantries 09-12 and 09-13, air labs
now; ISSUES GANTRIES). The fixes of 09-12/13 did not close it. What is open:

- Nothing yet says WHY a standing lab is idle -- army target reached, a want
  that never elects, a `gap0` on every candidate, a jammed yard. `FacYardWatch`
  reads a blocked plant only. Stage 0 is the instrument: per lab, per minute,
  idle time and the reason the auction gave it nothing.
  Found 09-21 (his Isthmus 8v8, fourth report: "we still have a lot of idle
  time on our airlabs... we need to be making longer queues"): `apex: facqueue
  short <lab> ordered=1 pend=0 sec=0/15 stop=slice us=16000-79000` on every
  seat lab after minute 30 -- one ConOrderFor costs 16-79 ms, the 4 ms batch
  slice ends after slot 0, and a nano'd line that builds a unit in 2 s gets
  one unit per 10 s election. Built 09-21: past the slice the window is
  filled by re-drawing the election's own ranked list (`RedrawFor`).
  Unmeasured in a rich game yet.
- The standing obligation ("army stays at its share of the economy we built")
  must not read satisfied while the bank sits full. Metal we are not spending
  is not economy we have built; the share is of what is USED.

## The jammer ring -- the stall that buys more time than the same metal in army

apexearth 2026-09-21: when we cannot match their army, the right choice can be
to make a jammer, put a bunch of HLT turrets inside its ring, some nano turrets
there too, and make sure we have radar; with T2, T2 defence goes in the ring.
The best choice is the T3 turret -- that is what costs the ~4,000 metal -- with
a bunch of crappy turrets in front of it to take the enemy fire, all under the
jammer. Against a bonused enemy AI coming down with really tough stuff, that
holds; it buys more time than 4,000 metal of army would.

The situation it answers is the 8v8 ally's (ISSUES "the allies' mohos are
metal-bound"): an army that stands at 1-6k against 12-22k, walks in, dies and
is rebuilt from zero every ~5 minutes. The trigger is the same reading -- the
enemy field in reach against our own -- that the class bar and the track record
already take; the answer is a defence ring priced as time bought, not a unit.

## Allies keep each other's walkways -- one lane system for the team

apexearth 2026-09-21, watching an Isthmus 8v8: we purposely leave certain
areas open so our units can walk there, and then an ally builds in that gap and
blocks it. All of us should align to the same system.

What stands: each AI lays its walkways from its OWN anchor and axis
(`baseplan/state.as`, lanes in world offsets at `LANE_PITCH`), so two adjacent
bases stripe the ground on unrelated grids, and neither one's site test knows
the other's gaps. A team frame -- one origin and axis published like the eco
seat is (`TV_*` team values), lanes as world lines in that frame -- makes the
gaps the same lines for every base, and a site that lands in any ally's lane
is refused the way our own is.

## Nuke Spam!

- prefer a docile enemy, likely wait until we have a rush to T2 and based on observed enemy strength *maybe* enable this strategy
- not a good strategy versus aggressive enemies

Before the enemy is ready, have the entire team go straight for nukes. Build up and SAVE multiple nukes and then at around 18m in launch all the nukes we've got on all the different enemy bases. Spread them out. After this reclaim all the nuke launchers and turn off the strategy to play normally or with a different strategy.

## Three detectors from one hosted night (apexearth 2026-08-19)

1. **Exploit enemy complacency.** "If enemy is not attacking us but just being
   defensive, we should form our own defense a bit more and take the time to
   scale our army." A passivity read (near-zero recent losses, base
   uncontested, static front) under which we greed eco AND scale army on our
   own timeline.
2. **Push back when pushed.** "If the front line is moving back into us then we
   need to make more army and push it back." Front-position memory; sustained
   shrink raises the army share until the line recovers.
3. **Defend the flank the front is wrapping around.** "If we know the
   frontline is shifting like that we should work hard to make defense in our
   base." The same memory's BEARING: a swing means a flank forming; the
   team-front gap price (docs/32) reads open bearings but not a moving one.

# Tips

- in late game take advantage of air constructors - they allow you to scale everything much faster, because ground cons move slowly. HOWEVER - air cons are easily shot down near the front line - this requires intelligence so that air cons aren't used when enemy AA is nearby. You have to hook this into their behavior, choice of where to build, AND whether they even get constructed. Complex. (Fighter escort for air cons built 09-13, unverified; the AA-aware siting is not.)
- AI should hover under a jammer and stay cloaked, when enemy T3 comes and attacks it should try to do surprise D-guns to kill all the T3 without dying itself.
- Build artillery on hilltops to attack enemies below (2026-08-27). No elevation binding; `ai.GetPathLength` detour sampling is the available proxy.

# Unbuilt behaviours (2026-08-09)

## Rezbots follow the attack group and eat what it kills

apexearth, 2026-08-09, watching an 8v8: "we should have this group followed by
rezbots which will reclaim everything they kill... this is a nice to have, but
would be great, and prevent enemy from just resurrecting all their stuff."

Two payoffs: the metal from a won fight comes back, and the enemy loses the
option to resurrect its losses. Rez bots now station behind `ArmyFront` (the
forward-most tenth of our combat units) and salvage from there; what is
missing is following a SQUAD and, for this job, RECLAIM not resurrect
("rezzing takes MUCH LONGER than reclaiming... if in a dangerous area you
should generally reclaim"). Needs a leash to the squad and must not pull
bots off base work while the squad idles at home.

## Long-range siege units should hold the base line, not walk into the open

apexearth, 2026-08-09: "Starlights, Ambassadors, these really long range units
are great for defense. But I typically see us move them out into open ground and
get destroyed. They should act like defensive turrets and stay home... waiting
around where I have my nano turrets and my own defensive turrets to help add DPS
and heal my units if they get hit."

- `armmanni` Starlight: range 950, 1,200 metal, role `anti_heavy_ass`, attribute `siege`
- `armmerl` Ambassador: range 1,300, 920 metal, role `artillery`, attribute `siege`

The `siege` attribute only changes the travel action; it does not keep them
home. What is wanted is a LEASH: a long-ranged, fragile, expensive unit stays
within our defended area and shoots outward. Must interact with the killing
blow, which commits everything when far ahead. Not built.

## Scout the mex area first, then size the group to what is actually there

apexearth, 2026-08-09: "you can scout with 1 cheap unit first to see what the
enemy has in these areas... then you can build your attack size based on how
strong the mex area is."

Replaces a global quota with a per-target decision. Stock
`GetScoutPosition` only counts a cluster scoutable when a spot reads
`threat < THREAT_MIN`, so we never look where they are; enemy groups are built
from what we have SEEN, so an unscouted extractor is not a candidate at all.
`CAttackTask::FindTarget` already computes the local influence of a candidate;
what is missing is using it to SET the group size rather than accept or refuse.
Not built.

## A single T3 assault unit should raid on its own, around the rim

apexearth, 2026-08-09: "Once we have units like the 'Titan' they can do these
attack orders all on their own. Through the edge of the map they'll be very
good."

Titan is `armbanth` (13,500 metal), Korgoth `corkorg` (29,000); either is worth
more than the whole massing floor, so waiting to bundle one with Pawns spends
the wrong resource. It may already work -- a Titan's power may fill
`quota.attack` alone; never read. The "through the edge" half is ROUTING: the
stock path crosses whatever the threat map allows, and no lever for a rim
route survives the 09-07 revert. Not built. Unmeasured.

## A basemap: defend territory, not a plethora of buildings

apexearth 2026-09-05, asked whether the defence target should stay 1.82x the
army target:

  "Just like we have a threatmap we need a basemap or something like that.
   Instead of coding towards a whole plethora of buildings we can instead code
   towards what we consider our base or friendly territory which we want to
   defend. Should reduce the complexity I'd say. If we use our army to defend
   structures then we don't need as much defense - and if we make more defense
   on our structures then we don't need as much army there. It should be a
   balance between the two - and a choice - mobility vs concentrated power."

The territory mask (09-12) and the team hull (docs/32) are the map. Not built:
defence and army as two ways of buying the same hold -- substitutes in one
balance, priced against each other, not two independent targets
(`TUNE_DEF_ECO_S` 120 vs `TUNE_ARMY_ECO_S` 66 is the framing he rejected).

## Behemoths when the enemy is encroaching (defence by unit choice)

apexearth 2026-09-16, Cortex losing ground on Supreme Isthmus: build
Behemoths (`corjugg`) -- "super duper defensive" -- when the enemy is winning
on our ground. Asks for a store of what each unit is good FOR (the Behemoth:
defence) that composition can read. Built 09-16 as `UnitHoldMod` /
`apex_hold_<unit>` (tunables.as, worth.as): a worth multiplier live only
while `LosingGround()` or the base is contested, corjugg 2x. Unmeasured --
needs a losing Cortex game with a gantry standing.

## LRPC on high ground

apexearth 2026-09-16: long-range cannons go up on hills so they fire long
distances unobstructed; the ground is allowed, hills are preferred. Supreme
Isthmus has them. Built 09-16: `HighGroundNear` in want_super.as takes the
highest legal ground within 600 elmos of the gate site. Unmeasured -- no LRPC
went up in the 32-minute test games.


## Air-lift turrets: what is still unbuilt

apexearth 2026-09-18 and 09-24: idle turrets flown by transport to where they
are needed "around the base"; also transports that free a stuck unit. Built
2026-09-24 (`market/lift.as`, DLL `CmdLoadUnit`/`CmdUnloadAt`/`CanLift`/
`GetResUse`/`UnitRelocated`): idle turrets to the working line furthest short
(`LineSiteFor`) only. Still unbuilt:
- other destinations -- a big frame being built (the nano-sink sites
  execute.as already scores), the held front line (`WallSupportSlot`);
- the stuck unit: `UnitMoveFailed` reaches the DLL, nothing asks for a lift;
- more than one transport per turret class (`LiftGainFor` prices a second
  plane at zero while one that fits stands);
- BAR's `unit_transportable_nanos.lua` refuses a lift of an ALLY's turret,
  so in team games each seat only moves its own.

## Escort strength scales with the risk of the trip

apexearth 2026-09-24: the "assumed danger" prior backfired because some cons
were allowed no risk and never walked out to build; perhaps boost the escort
considerably based on the risk instead. Today an escort is binary: exposure
>= 0.5 asks for one (army.as ExposeRefresh), and one escort of any size makes
the worker "escorted" (guards.as EscortedWorker). Nothing sizes it to what
could arrive. Unbuilt: escort metal per worker against the threat expected at
its site, and the build's danger priced as min(expected loss, escort cost) so
risk buys protection instead of cancelling the trip.

## Air-lift towers forward, army to raid or flank, a hidden base

apexearth 2026-09-24: build light towers (beamers) in the safety of the base
and fly them up toward the front line; transport army to raid or to flank
("a place the enemy will not expect"); sneak a constructor behind enemy lines
to make a base there (docs/24). Transportable towers (engine default for a building is NOT
transportable; these opt in): LLT (armllt/corllt, mass 5100), Beamer
(armbeamer 7500), corhllt (10200), armrl/corrl, radars. HLT, Dragon's Claw
and Maw cannot be lifted. Every tower is over the Stork's 750 mass, so this
is heavy transports only (Abductor/Skyhook). T1 army fits a Stork (mass is
capped at 750 for units under 751 metal); the heavies take footprint <= 4.

## Do not marry the starting point

apexearth 2026-09-18: "We really shouldn't 'marry' our starting point. If
we lose our base but have other safe ground to rebuild on then we should
do that." Today every anchor, farm, lane and leash is measured from the
start position (Base::gAnchor, Builder::gHomePos, EcoSiteFor's farm); a
base overrun keeps rebuilding on the same ground under the same guns.
Unbuilt: a re-anchoring election -- when the home ground reads lost
(EcoDangerNear sustained, the plants dead) and quieter ground of ours
exists (a held mex cluster, an ally's rear), the anchor, farm and leash
move there and the plant want rebuilds at the new anchor.

## Finish a won game: nukes, flanks, air, scouts, LRPC, Ragnarok

THE LENS (apexearth 2026-09-18): "I'm just trying to think what a human
would do to beat us in this particular game. And the answer would be mass
nukes, naval attacks from the side, or some big air attacks. Those are the
things that they would be able to do to kill us. We finally won because we
finally landed a nuke in their base." Judge every play below by that: is
it what a human would do to us at this economy, from a direction we do not
hold.

apexearth 2026-09-18, watching a game at three times the enemy's economy
that took "forever" to win: "we don't use our nukes very smart. We're not
attacking the enemy from the sides pretty much ever. We don't use air
against the enemy... We don't even use scouts, so we don't really know
where we should be nuking... if we just built nukes and consistently nuked
the enemy, that would probably be the easiest way to win, but I would like
to see us be able to do a variety of strategies. Like if we made a whole
lot of marauders, if you attack the enemy with like 50 marauders, all of a
sudden from the side, you'll really wreck the enemy good. We also lack LRPC
cannons, and I never see us make anything like a Ragnarok."
Six plays, none built as a play today: (1) nuke targeting from scouting
(the silo fires at what radar and scouts have seen -- ai-nukes); (2) a
flank: the army's approach vector off the direct line; (3) air used
offensively (the bomber wing exists -- ISSUES BOMBERS -- and never flies
in his games); (4) scouts kept alive as eyes (the Tick is buyable since
479ab851); (5) a massed single-type strike (50 Marauders from a side);
(6) LRPC (HighGroundNear exists, unmeasured) and the Ragnarok never
priced in -- is it the super-weapon budget or the track record?

## Building as he would think it (2026-09-20)

His model, offered as perspective while the election was being measured at
121-236 runs per player-minute: the thought starts from the WANT, not the
hand. "I want a fusion" -> "do I have a spare T2 con, or what are they
doing?" -> if none is free, drop it and come back a second or two later.
Only when every hand is on a job worth more than the want does the hard
question run: "if I take one off the moho, how much does that cost, and is
the fusion worth it?" Later in the game that collapses to "which hands are
free or just guarding someone -- take one", because a guard's lathe is
what the nanos give anyway and we rarely build many things in parallel.
Today's market is the inverse: every idle hand re-asks all nineteen
proposers. The demand-first shape is a ranked want list computed once per
team on its own cadence, with a hand's election a lookup into it.

## 2v2 Glacier Pass: the one arm left unmeasured (2026-09-22)

The commander's WORK leash is what stalls the expansion at minutes 2-4
(`mexdiag comFar=63` per sample, everything else under 8). Widening it back
to the full `apex_eco_leash` while the chase keeps its own 0.5-leash bound
in safety.as ran 3 of 16 games before the batch was reaped for memory:
mexes at 12 min 6.1 -> 9.3, army at 4 min ahead of BARb for the first time,
0-3 with 9.3k lost in the 8-12 bucket. To finish it:

    # in floor.as ComFar: `> 0.5f * leash` -> `> leash`
    BARAI_LANE=winrate python tools/deploy_ai.py deploy
    BARAI_LANE=winrate python tools/run_tournament.py \
      --a Apexwinrate:lane-winrate:standard --b BARb:stable:hard \
      --maps "Glacier Pass" --games 16 --minutes 60 --speed 5 --per-side 2 \
      --sides Armada,Armada --handicap 100 --box-size 0.2 --boxes lr \
      --workers 4 --name t27b-comleash-s5-16

Read: `tools/spendtable.py` (mexes at 8/12 min, the 8-12 loss bucket),
`mexdiag comFar`, and commander death times. If the mexes hold and the
losses do not, it is the first thing all night to move the minute-4 wall.

## His four early-game directives (2026-09-22), with what is measured so far

1. **Guard our mexes with a turret.** At minute 4 we are at parity (59% vs
   60%) and by minute 6 we are not (62% vs 88%) -- their tower count nearly
   doubles between 4 and 6, ours is flat. `apex_t1_tower_late=0` and
   `apex_mex_cover_floor=2` both read inside the noise, so it is not the
   rule or the floor: it is hands and metal in that window.
2. **Harass their engineers and mexes with pawns/ticks.** The raid director
   was DEAD: `RaidTarget` needs a remembered enemy STRUCTURE near a spot and
   we scout nothing early, so it refused 128 of 130 asks ("no enemy ground
   seen"). Given a geometric target (nearest spot on their half when nothing
   has been seen) it asks 50 times and forms raid tasks -- but the packs are
   1-3 units because the director wants ~5 Pawns and our whole early army is
   defending. Neutral at 8 minutes (32 games each); full-length arm running.
3. **Minimize walk time; fortify what the commander walks to.** Not built.
   The walk is priced twice today (see ISSUES: a 34 s walk costs a mex claim
   609 metal and an assist 37) and making them equal did not help.
4. **Keep enemies off our energy and converters.** Not built, not measured.

The loop for all four: `python tools/openloop.py run --name X --games 32`
(6.5 min), compare against a 32-game control, then `tools/perminute.py` on
one win and one loss. Anything under ~0.5 mex at n=32 is noise.

## Host the AI from a lobby bot, not from his client (parked 2026-09-30)

His ask: the AI hosted like a server, not by a player who joins and adds it.
He parked it the same day ("we should not do this yet").

Proven locally (`tools/netproof.py`): `spring-dedicated` as the server, a
`spring-headless` spectator ("ApexBot") that owns the AI, a second client as
the human. The game started and the AI played (11 decisions, 5 placements in
3 game-minutes, no desync). Traps found:
- `spring-dedicated` has no `--write-dir`; it reads `SPRING_WRITEDIR`, and its
  config flag is `-config`.
- A cold client spends 20+ s hashing the game before it answers; the server
  dropped both clients after ~10 s. A kept write-dir (warm cache) plus
  `InitialNetworkTimeout`/`NetworkTimeout = 300` fixed it.

The plan when he picks it up:
1. `tools/lobbybot.py` speaks the SpringLobby protocol (what Chobby and SPADS
   use today; Tachyon is replacing it): log in, take his PM (`!join`, `!add 2
   enemy`), JOINBATTLE as a spectator, ADDBOT with itself as owner, and on
   the host going in-game launch spring-headless with the room's IP/port and
   its own script password.
2. Keep the room's engine, game and map installed (pr-downloader) and the
   Apex AI deployed into that engine; keep the cache warm.
3. Build and test against BAR-Devtools (Teiserver + SPADS + bar-lobby in
   Docker) before the live server.
His part: BAR bans alt accounts, so the bot account needs the admins'
approval as a bot, and their word on a custom-AI host bot in public rooms.
Where it runs matters: on his PC both clients simulate the whole game.
