# 24 — How units fight

apexearth's directives for combat, in his words made straight. Nothing in
this file is an idea of Claude's: every rule was stated by apexearth, and a
session may add to it only from something he said. The one exception is the
flanking-damage mechanic in the last section, which he asked to have
researched; it is labelled with where it was verified. Where he gave a
number, the number is his and is marked as such.

`docs/23-the-plan.md` says what the economy is for. This file says how the
army is to fight. Where code, a skill or a comment disagrees with this file,
this file wins and the other is stale.

## The test: fight without turrets

- **Build no turret defences.** A player can respond to radar sightings and
  position units to defend buildings; the AI must do the same. Fighting is
  gauged with static defence switched off, so nothing hides a bad army.
- **Make units earlier.** Defending with units alone means military must
  exist early. Presently the AI makes about three constructors before any
  military, and that is an issue.
- **Measure the first five minutes.** Performance in fighting over the first
  five minutes of the game is the test of this logic. The metrics that
  matter:
  - damage efficiency;
  - units killed against units lost;
  - the count of builder interruptions;
  - building damage received against building damage dealt.

## Shape: curves and lines, never a ball

- **Units in a squad must not all move to a single location.** Grouped into
  one spot they take splash damage from the enemy.
- **Organize into curves and lines, "crossing the T" on the enemy.** Units
  are organized into curved lines against the general area of enemy
  influence, never into balls. A line across the enemy's approach also has
  the units already in position to apply flanking damage (see the last
  section).
- **Form a wall against the enemy**, so that when the enemy comes in to
  attack there is a wall of fire from every well-positioned unit. The wall
  also blocks enemy leaks between units.
- **Some enemies deal large area-of-effect damage. A ball makes those hitters
  even more effective**, which is one more reason never to form one.
- **Units that can be D-gunned together must spread out**, so no single shot
  takes several of them.
- **Cohesion is measured as the averaged positional radius of the squad.**
  Take all the unit locations and average their distance from the centre; a
  squad that is spread out is not a strong fighting force.
- **Kite the enemy, often.** But not every unit can shoot behind itself, so
  kiting is only for units whose firing arc allows it (the Starlight example
  below is the case that cannot).

## Enter the fight together

- **Organize the units so that all of them enter the fight at about the same
  time.** That means spreading out and crossing the T before contact, not
  arriving as a column with only the leaders able to fire.
- **Move at the speed of the slowest unit in the group**, so the fast units
  do not run in and engage first, die, and leave the slow units behind them
  to fight and die or run.
- **A joining unit joins the squad, not the target.** Units must not trickle
  to the place where the squad was attacking and get picked off one by one,
  standing within enemy fire and indecisive.
- **The squad must not stand within enemy fire being indecisive.** A squad
  that changes its mind repeatedly, running in circles on the spot, has
  thrown its effectiveness away. Commit to a target.

## Range and standoff

- **Fight at about 90% of maximum attack range. Do not move any closer.**
  (His number.)
- **Almost always stay moving.** Standing still leads to death much quicker.
  Units may circle around the enemies they are shooting, staying on the
  move and changing direction to boost evasion.
- **Back up before the enemy can fire back.** When enemies are close to
  getting in range to fire, back up immediately instead of waiting to be
  hit. A unit that dies on the first hit must move away when the enemy is
  within 90% of its own range; being 10% out of the enemy's range is the
  moment to move.
- **Siege units are afraid of enemy units getting too close to them.**
- **Indirect fire is the exception to standing off.** Rocket-launcher style
  enemies can be stood within range of, as long as the unit keeps moving and
  avoids where the missile is going. Arbiters have very long range and are
  very vulnerable up close.
- **A more powerful unit does not run from a longer-ranged weaker one.**
  Thugs and Maces are more powerful than rocket bots and must not be afraid
  of them because of range.
- **Do not walk short-range brawlers up into the enemy.** Thugs and Maces
  walking up close get creamed.
- **Long guns must not run deep into enemy territory to fight from close
  up.** Hounds and rocket bots walking into turrets is the mistake.
- **Lower-HP units have to be much more careful than high-HP units.**
- **To commit to killing sniper-like units, dive in** and ignore the
  stay-at-range rule; otherwise they simply keep shooting and the squad
  never arrives.
- **Choose safer angles** when there are two equivalent positions to stand
  at.
- **Standoff moves must not walk a unit into a new threat.** Keeping distance
  from the enemy being fought must not step into a second enemy's range.
- **A tower that cannot fight back is attacked, not orbited.** The move logic
  is for enemies that shoot back.

## The squad: screen in front, guns behind, sensors at the back

- **The mainstay of a good T2 army is tanky units in front, long-range units
  in back, radar and jammers in support, and rezbots keeping them healed.**
- **The screen shields the guns.** Tanks stand around in front of the
  Sheldons. They take hits if they have to, but they do not walk up to
  enemies to shoot at them; if they walk closer they take a lot more damage.
  They are there as a shield. This is how every unit behaves when in a squad
  with ranged units. The squad seeks to remain at max range. It is a siege
  mentality.
- **The anchored range ladder:** one Mammoth, one radar, one jammer, ten
  Sheldons, five Arbiters, everyone guarding the Mammoth, and the Mammoth
  given a fight order toward the enemy base. The Mammoth's range keeps it
  far enough away that usually only the Mammoth is seen; the rest stay
  hidden behind it and still shoot; the jammer keeps them off radar; the
  radar gives sight; the Arbiters give anti-building damage. If the AI does
  not actually form a squad like this it is much less valuable. When the
  Mammoth dies the squad breaks down fast; the answer is more Mammoths, in
  proportion to the squad.
- **The screen does not need to deal damage.** apexearth 2026-09-05: "Ensure
  that our tankier units in squads don't dive too deep into enemy lines. Their
  job is to protect the longer range units in their squad. We don't really need
  them to be dishing out the damage, they'll do damage when enemies get too
  close. Rely on rocketbots to shoot from long range." Standing at its own
  weapon range is a dive: the screen holds a rank in front of the guns even
  when that is outside its own reach.
- **Radar and jammer units always angle themselves behind their squad
  relative to the direction of the enemy**, towards the back of the squad.
  Sheldons with a radar and a jammer are very good; Sheldons moved as a
  tight ball are not.
- **A squad carries at most two jammers and two radars.** (His number, per
  squad.)
- **Units want to stand within their squad's jammer** when the squad has
  one, fragile units such as snipers especially.
- **Units that easily die must be way more careful than the rest.** A
  fragile unit stands further out on the same line, screened by healthier
  squadmates.
- **Hurt units move towards the back of the pack, at under 60% health.** (His
  number.) They keep fighting from the rear rather than leaving.
- **The whole squad falls back together when its total health is too low**,
  not unit by unit. When the squad is only a few units and they are all low,
  the whole squad falls back; the goal is to keep people in the fight while
  stopping them being targeted.
- **A retreating unit has zero power. It is no longer fighting.** Units that
  stay and fight must not count the runners as part of their strength.
- **Some units fighting while others run splits the force and gets it
  clobbered.** Once in contact, the squad fights or leaves as one.

## Orders

- **Use move orders plus set-target, not "attack this unit" orders.** Moving
  around within range of the target while set-targeting it keeps the unit
  moving while shooting.
- **A unit that wants spacing or wants to run must not use a fight order.**
  Using a fight order for that was incorrect.
- **Snipers take only move orders and a set-target**, never fight or attack
  orders.
- **No flat move order may override common sense.** A fragile unit must never
  blind-walk into enemy fire: a Sharpshooter walked deep into the enemy army
  on a plain move order, unable to stop and shoot things well inside its own
  range. Halting to fire, standing off and routing around are all
  acceptable; walking blind is not.
- **The commander uses its D-gun.** A commander must not fight a Titan laser
  against laser with the D-gun ready.

## Targeting

- **Concentrate fire on the lowest-HP enemies to finish them sooner.** Focus
  fire is a set-target thing only, and overkill volleys must be thought
  about: deal the squad across the wounded in lethal doses, not everyone on
  one target.
- **Finish what is nearly dead.** Do not lose half the army to a turret that
  was almost killed and then run away, so the turret never dies.
- **Prioritize killing enemy long-range units and artillery.** Do not let the
  artillery blob pile up; assassinate it.
- **Do not send entire armies chasing a few light units** off the front line.
- **Big T3 units ignore small units and attack bases and economy.** While
  marching they shoot the most valuable target within range and keep moving
  into the enemy base. Juggernauts walk straight into an enemy base, because
  they explode when they die. T3 units must not hang around not fighting.
- **Near the enemy base, dive straight in and target their economy.** Do not
  get distracted by military or towers if an advanced converter or an
  advanced fusion is in range.
- **Killing economy is the win path, and killing energy economy is better
  than killing metal.** Strikes prioritize their energy (fusions, advanced
  solars, converters), then metal, then build power (nano turrets). There
  is no commander-hunting doctrine.
- **Attack their mexes and their economy, and defend against their army.**
  Do not send the army at the enemy wall to fight; when there is a free
  enemy mex to kill, kill it rather than walking off to fight army in the
  middle.
- **After a raid on enemy mexes, go further and take out more**, rather than
  turning around and walking home to do nothing.
- **Cheeky moves win games:** running the edge of the map and popping enemy
  energy converters in one or two hits, because they are explosive and
  fragile.
- **Do not bomb a building still under construction** when it is the
  finished one beside it that explodes.

## Taking out a defended building: scout, gauge, call, regroup, strike

- One Incisor (`corgator`) cannot take out an LLT. Two can, easily.
- A scout that finds an enemy building gauges its threat level and calls for
  reinforcements to take it out. The caller can be a Grunt (`corak`) or a
  Tick (`armflea`) asking for a few units to join it, just enough to kill
  that tower.
- The caller pulls back out of line of sight and waits for the
  reinforcements.
- When they are all together and grouped up, they attack the tower.
- **A static cannot chase.** A raider squad hovering just outside a tower's
  range, unable to shoot, is wrong: either the squad can overwhelm the tower
  and commits, or it should not be pressing it at all.

## When to fight

- **Any fight you take and lose was the wrong thing to do.** Do not realize
  the danger too late, head in, panic, turn around and die.
- **Compare our power in the area of the attack to theirs, and go in only if
  our power is strong enough in that area.** A 2v4 is not a winning fight and
  must not be taken.
- **Do not believe we are overwhelming something that is superior.**
- **Judge fights on the squad's real health**, not as if it were fresh. A
  mauled squad must not take on fights it is outgunned in.
- **When the recent kill/death ratio is low, be more careful and require
  greater odds to attack.** When the army keeps getting killed, make more
  army and use it in defence.
- **Do not be cowardly against enemy bases we could win.** When the squad
  could take out an enemy base, it takes it rather than circling nearby for
  minutes until the enemy comes, surrounds it and kills it.
- **Armies ignore enemies less than half their strength unless defending the
  home base.** (His number.) Do not move the entire army to the back to
  chase petty raiders while the enemy walks into the base.
- **If our base is being pushed, defence is the priority: meet that army and
  destroy it.** Do not keep distance from an army that is destroying our base
  when we have more than they do. Do not make the army abandon the base to
  join a squad elsewhere.
- **Defending at home takes a fight near parity**, about 1.2x (his number),
  because we need time to build the army to match what is up there rather
  than continuously letting units die.
- **Unknown does not mean small.** There are long stretches when no enemy army
  can be seen; that is fog, not weakness. Do not throw the army at a superior
  force. Size the enemy from the most seen at one time over a window, not
  from everything that ever cycled through the fog.
- **Group sizing is dynamic, based on what we have.** The squad minimum scales
  with economy and army, never a flat number. The enemy masses big and kills
  our smaller masses one by one; mass as hard as they do.
- **Be the aggressor only when we have built for it.** If we chose economy
  and they chose offence, the army we bought is for holding, not trading; if
  we are conservative we do not attack an aggressive enemy. If the enemy is
  not attacking and just being defensive, form our own defence a bit more
  and take the time to scale the army. Too much silence demands proper
  scouting.
- **If the front line is moving back into us, make more army and push it
  back.** If the front is shifting around a side, build defence on that
  flank before the damage.
- **The T1 commit is all or nothing.** Committed to the T1 push, the army
  attacks the enemy base and is not distracted running all over the map.
- **A committed push never regroups somewhere safe.** Its purpose is to kill
  bases, and on a large map it cannot get away anyway. Breakthrough doctrine:
  punch through the front line, then stay in the back lines killing bases.
- **A charger keeps moving forward.** Chargers and colossi are never pulled
  back and are not distracted by every little unit that comes at them.
- **After losing a big fight with very few units left, do not leave the base
  at all** until rebuilt.
- **A squad that has just won presses on**, onto remembered enemy positions
  and the enemy's centre of mass, instead of walking home to stand around and
  hand the enemy a free rebuild.
- **Either commit to the enemy base or come home, never neither.** The army
  must not roam around without getting anything useful done while the base
  takes hits.
- **When ready, push more. No time-based cooldown.**
- **Do not abandon a nearly-won endgame to caution.** An enormous army must
  saturate a doomsday gun, not orbit its range ring.

## Retreat

- **A squad in a fight it obviously cannot win turns around and retreats
  immediately.** If there are nearby towers or defences to go behind, go
  there, hide behind them and fight the enemy under our towers; the towers
  take some of the damage while we keep shooting.
- **Retreat to the chokepoints and front-line areas, not the home base.** The
  walk home is long on some maps and splits the army.
- **Retreat logic must not take a unit into new threats.**
- **Retreating at a very low HP percentage is a symptom**; where the unit
  runs and whether anything covers it is the question. Look at the action
  before the retreat, never at the retreat itself: "retreat" is not a valid
  answer in a death report.
- **Units that are stuck and cannot go anywhere are reclaimed.** Never the
  commander.

## Hunting enemies in our areas

- **Be extremely good at detecting enemy threats in our areas.** It is
  visible long before they get to our base that they are pushing towards it;
  prepare for it.
- **Create an appropriately sized squad for each threat, and hunt it down.**
- **Read the trajectory of enemy units and intercept them.** The goal is to
  meet them before they reach our buildings, not to arrive after a mex has
  died. In the early game, with 3 to 8 mexes, 2 to 15 wind generators and a
  T1 lab, we have twice the army the enemy has raiders: 2 to their 1, 10 to
  their 5, 20 to their 10.
- **Enemies come from many sides at once, each after a mex or a solar.**
  Expect five groups from five angles going for five different buildings.
  Wherever our units start, in the centre of the base or spread out, they
  seek out each group coming at the base and kill it. "Do we defend our
  buildings?" is the question the raid test (`tools/test_raid.py`) asks; its
  scripted raiders are dumb, so it is easier than a real opponent, and the
  question is still the valid one.
- **Light, fast units are the best for this, so make sure they are being
  built.** Thugs (`corthud`) and rocket bots (Rocketeer `armrock`) are good
  army fighters, but fast units are needed, especially in the early game.
- **The first units out of the factory are the light ones.** Conventionally
  the lab opens with rocket bots and Thugs; the AI logic should be making
  the light units first. We need vision and speed to defend ourselves
  properly.
- **Keep the units spread out enough to react quickly.** We fail to react in
  time because the entire army chases the enemy, and without fast units it
  cannot get back. Some of the army is always near every part of the base.
- **A unit protecting a building counts as cover, the same as a turret
  does.** We have the cover metric for defences on buildings; a unit standing
  by a building is cover for it too. Distribute the units well enough to
  ensure proper coverage of our buildings for defence. The light units are
  for escort and for covering the buildings, and we need a lot more of them
  to protect the base.
- **The commander spams the D-gun at enemies so long as he has the energy.**
- **We are still not making nearly enough Pawns.** Centurions are also good
  at defending, since we are Armada; Cortex does not get that, so Cortex
  sticks to Grunts. (His words after watching the guard posts in play.)
- **The raid test sizes the enemy from our army**, not the other way round:
  the AI builds its own units and the raiders are scaled to them. Spawning
  units for us was not fair to the aggressor.
- **Tit for tat.** Our constructors must not be harassed and killed if we are
  not going to harass and kill theirs. Raiders raid for the whole game, as
  stock BARb does.
- **Cut off enemy reinforcements** where possible; understand which pathways
  lead into our territory.
- **Defend the deep interior**, not only the border. Leaks happen behind the
  line.

## Holding ground: the front line

- **Units are positioned on the front line.** Squads must not move around
  like blobs with no responsibility for any area; humans form a line of army
  that holds a region and stays there.
- **A front line is where our territory ends and the enemy's begins.** It
  wraps all our territory, is distinguished from the back line, is unknown
  at game start, and must be near the enemy. Its goal is that no enemy can go
  around it.
- **Hold a front line at a narrower part of the map.** Holding that line is
  best; the army holds the choke first and the guns come up under it.
- **Fight within range of our nano turrets and get healed while fighting.**
- **Hold and let them come.** Make them attack us when they are more
  powerful; we fight on our ground at our range. Hunker down and make them
  bleed, control where that metal falls so we can resurrect or reclaim it.
- **Eat their wrecks.** Their dead army funds ours; the battlefield is the
  richest reclaim on the map.
- **Keep making more military, do not waste it, grow, overwhelm the enemy.**
- **Stand at the enemy border and siege them long range.**
- **When the forward lane is lost, pull back.** Defend streaming into a lost
  lane looks like an attack and is not one.
- **While rebuilding the army, defend the borders** rather than going outside
  the base to trade badly.

## Movement and pathing

- **Do not walk many times the necessary distance around enemy defences.**
  Sending the army around the back edge of the map instead of towards the
  front line is wasteful movement, and it does a poor job of defending.
- **Do not always attack straight up the middle.** Attack from around the
  side; flanks are feasible on small maps too.
- **Wrap the edge of their line, not its middle.** When the enemy backs up and
  forms an encirclement, shift the whole squad to one side, wrap around the
  edge of their line and swallow them.
- **Accept more risk in the path when needed, rather than turning all the
  careful logic off.**
- **Big slow units go straight.** The attack-around-the-edge strategy is
  normally good, but Behemoths are terribly slow so it is less good for
  them.
- **Humans kill the AI by attacking around the edges slowly over time**, while
  the AI prefers to attack through the centre. Work the flank.
- **Penetrate deeper** into places we believe are empty, to kill mexes and
  bases.

## Support during the fight

- **Constructors and rezbots heal units while they fight**; this turns fights
  around. Rezbots and twitchers repair the screen mid-fight so the same metal
  fights several times.
- **Rez bots do not loiter in dangerous areas** after their job; they move to
  safety.

## Air

- **Mass air before attacking with air.** Save up an equal or greater number
  of fighters than the enemy has, then attack; never go in with one.
- **Air attacks the enemy home base**, not the small mex emplacements; hitting
  a low-value target and flying a huge arc home usually dies to AA.
- **Vary air targets.** Air must not repeatedly bomb the same thing.
- **Coordinate air raids with the land engagement** on the same front at the
  same time.
- **Air scouts are not spam.** Scouts get made so the army knows where the
  enemy economy is.
- **AA is proportional to the enemy air we have seen**, and in the later
  part of the game flak is spread out around the base whether or not air has
  shown up yet. Later means economy, not clock.
- **AA units do not join ground pushes**; they died there for nothing.

## Fodder

- **Tick spam** in the late game: cheap fast units (Ticks, Grunts, Pawns,
  Rascals, Wheelies) go straight to the front and run as far into the enemy
  base as they can, for vision and distraction. They are not grouped and not
  treated as normal army.

## Unit nuance

Once the five-minute test is in place, the work goes through, in order: how
to fight; how to organize; when to form a squad; how to size a squad for its
purpose; which units are not good for squadding; and unit nuance, unit by
unit.

- The Starlight (`armmanni`) can only shoot in its forward 180-degree arc,
  whereas snipers (Sharpshooter `armsnipe`, Arbiter `corhrk`) have a
  360-degree firing arc. This penalizes the Starlight if it moves up too far
  and needs to turn around.
- Snipers are much better than Recluse spiders; stats alone misprice units
  because projectile speed and accuracy are invisible to them.
- Amphibious tanks must not act cowardly.
- The commander hovers under a jammer, cloaked, and surprise D-guns enemy T3
  when it comes.

## Diagnostics he asked for

- **Squads ping the map with their intent**, so what they are thinking can be
  seen.
- **The death log records the action before the retreat**, such as
  "attack-retreat", never bare "retreat".
- **Good diagnostics and instrumentation are important.** If a rule never
  fired, fix it; there was never a moment it could not have applied.
- **Making this kind of strategic logic easy to express is itself a goal.**

## Flanking damage

- **Do not let the enemy flank us. Flank the enemy whenever possible.**
- apexearth's understanding: two enemies shooting from a 90-degree arc do
  150% damage; two from a 180-degree arc (one in front, one behind) do 200%.

Verified mechanic (engine `rts/Sim/Units/Unit.cpp`, `GetFlankingDamageBonus`
and `DoDamage`; game `BAR.sdd/gamedata/modrules.lua`, `flankingBonus`; no unit
def in the pinned tree overrides it):

- BAR uses flanking mode 1 with min 1.0 and max 2.0. Damage is multiplied by
  `1.5 - 0.5 * dot(dirToAttacker, flankDir)`.
- `flankDir` is in world coordinates and ignores which way the unit faces.
  It starts as world forward, and the unit's first hit snaps it fully onto
  that attacker's direction. So the first attacker does 1.0x, an attacker at
  90 degrees from it does 1.5x, and an attacker directly opposite does 2.0x.
  His understanding is exact.
- After every hit the swing ability resets to zero and regrows by 0.01 each
  slow update (every 15 frames, half a second). A unit under steady fire
  therefore keeps its "front" on whoever hit it first; only a unit left
  unhit for a while re-faces toward a new attacker, and slowly.

## Guards answer the base, and stand as a wall

apexearth, 2026-09-05, watching a no-turret 1v1 against BARb:

- "When we're attacked our dudes still just dry hump our most valuable mex.
  We should be spreading ourselves out as a wall so if enemies attack we
  don't receive a lot of flanking damage and instead get flanking damage on
  them."
- "Our main base will be under attack and the mex guards don't move to help
  the main base. That's not so great. It is really bad that they don't
  respond to nearby parts of our base being attacked."
- Same game, after the wall and the answer-by-need fix ("this one looks
  much better"): "we tend to not attack artillery that is attacking us, we
  should be more willing to meet artillery and kill them."
- Same game: "I just saw our hounds walk right up next to enemy t1 tanks and
  get obliterated. That was very bad logic right there. Units like that
  should always want to keep a safe distance."

## Second no-turret game, 2026-09-05 (seed 17, lost at 16 minutes)

apexearth, watching:

- "Enemy pawns are able to distract our commander for minutes and that's
  really not good."
- "We also tend to chase directly towards the enemy instead of in the
  direction they're heading."
- "Seems like some of our guys might be pulled away for attacking or
  something, our base was being hit but new units ran away from protecting it
  to fight on the frontline for some reason."
- "We're fighting a lot and doing pretty good at it but we don't expand quite
  so well. So we lose the long game. Something to help our fights be more
  resilient would be rezbots. We aren't making nearly enough rezbots in the
  early game (0 in fact where enemy has 6, is resurrecting and healing, and we
  lose those fights because of it)."
- "We made a T2 lab while losing active frontline fighting which we could
  obviously read/see - we never should be doing something like that."
- "Actively engaging in fights with every army we make instead of saving up
  our army."
- Same game: "A commander should value himself based on what we perceive his
  power to be from his hp, range, dps, speed... and we should value enemies
  like this too, not based on metal." And: "We already calculate a power like
  that somewhere, reuse that."
- Third game (seed 18): "Just saw a rocket bot die to a T1 turret which it
  outranges. We shouldn't have been standing that close to something we
  outrange." · "I see 1 rezbot, we need like 4 or 5 at this point (~12m into
  the game)." · "Our commander looks totally braindead sometimes still. Some
  bad logic somewhere."
- Same game, on pricing them: "Rezbots gain value when: there is valuable
  reclaim available; there are units that need repairing; there are units
  available to resurrect."
- Fourth game (seed 19): "Our commander still chases enemies a LOT which
  causes him to be long-term distracted and not useful. Enemies won't even
  have a trajectory towards our buildings and he chases them 'into the
  sunset'."
- After the sets (2026-09-05): "Compare strength, work on that T2 lab while
  losing, if we're bleeding army we should try to mass more. Ensure the
  commander's time isn't wasted. Like I said - if enemy is running away,
  fine - let them."
- Seed 20 watch (2026-09-05): "The issue I see a lot is our rezbots idling
  between actions. It takes them a long time occasionally to decide what
  they want to do. I think you should analyze what they're doing because it
  is very wasteful. Also they should always angle themselves BEHIND our
  units in combat. Never stand in front of them where they're likely to
  become collateral damage."
- Same watch: "If an enemy comes at us with a high dps unit that outranges
  us we need to make a longer range unit to fight back against it at our
  T2 lab."
- 2026-09-06, on rez bots: "They need to be productive and have good
  survival instinct. In combat they should stand behind allied units away
  from enemies. They should back away when enemy units are close to being
  within range of the rezbots. They need to be quick to react. Delays of
  more than a second are unacceptable."

## Self-play watch, 2026-09-05

apexearth, watching two copies of this AI play each other:

- "It is really telling how passive our AI is - they haven't attacked each
  other a single time in 13m. They've also not scouted or tried to harass
  each other at all."
- "I see us defending our buildings all around our base, and that is nice to
  see, but our base has depth and we spread our army out around both the front
  AND back of our base. If the enemy attacks they'll be coming at the front of
  our base, not the back of our base... so we need to draw lines of our units
  towards the frontline."
- "I don't see why higher level knowledge can't choose to do a raid. If we know
  that there are some pretty undefended areas we should be able to ask for a
  raid, and pull units from wherever seems appropriate in order to make a raid
  happen."
- "Even marauders are raiders and most people play them as raiders, skirting
  their way around the front lines to attack enemies behind." (`armmar` is a
  gantry unit -- T3.) So no tier converts a raider into line army, and the
  route is part of the ruling: around the line, not through it.

## Riot holds a post; fast units do the chasing (2026-09-06)

Watching a game lost to raiders loose in the base -- "enemy grunts running all
around our base and we have nobody who can chase them down and stop them... we
get killed by grunts slowly":

- "The trouble with those riot units is that they need to stand guard post at a
  specific place. They're not fast. So we need to have fast units like pawns or
  grunts."
- On the army being one blob: "Certainly sounds like an issue if we just have
  one large squad." (Measured that game: `apex: squadsize own n=1 avg=8.0 |
  enemy n=9 avg=2.9`.)

So the counter chain's RIOT-answers-RAIDER (`market/army.as`) is the POST half
only. A riot unit is bought to hold a place; nothing in it chases, and pricing
it as the whole answer to raiders leaves the base with no interceptor. The
mobile half is a fast cheap unit -- Pawn or Grunt -- and it is a separate
demand, not the same one.

## Range discipline, blobbing and target sanity (2026-09-06)

Watching the 38-minute Comet Catcher loss, in his own words:

- "our artillery walked into an enemy tower and died (3 of them). I've seen a
  lot of our units 1 by 1 walk into some tower ranges dying."
- "I saw a sniper walk up close to a mammoth (where did our distance keeping go
  on our ranged units? did we regress or has it never worked well?)"
- "We need to respond to incoming LRPC fire with shields."
- "We should be doing more raids, not sure I see this happen..."
- "I see squads of our armies being given fight orders to single spots on the
  map (causing a blob of bunched up units) and then being given set target
  commands against enemy units which are far out of range."
- "Our targetting logic also sets some units to attack enemy aircraft which they
  are ill-equipped to hit."

Four rulings are implied and they are his, not ours:

- **A long-ranged unit's standoff is its OWN weapon range, not the squad's.**
  A sniper that closes to a Mammoth has been given someone else's ring.
- **Arriving one at a time inside a tower's range is the failure**, not the
  losing trade -- he is describing a trickle, so the fault is the destination
  and the arrival, not the fight.
- **A fight order to a single point is wrong on its face.** A squad is a
  frontage, not a coordinate; the blob is the order's shape showing through.
- **Never hand a unit a target it cannot hit** -- out of range, or in the air
  when the weapon cannot reach air. He read both off the screen, so both are
  visible to a watcher and neither needs a measurement to justify.

"We survived until the late game and that was good."

## Range, routes and turret zones (2026-09-06, answering four questions)

Asked directly, after the 38-minute Comet Catcher loss:

**On walking through enemy turret coverage:**

> "If we're going to go through a turret zone we should do so with the intent on
> killing it. Otherwise should walk around it - and if we're unexpectedly
> getting shot at we should route further away."

Three obligations, and note the third is a REACTION, not a plan: entering a
turret's reach is a decision to kill that turret; any other route goes around;
and taking unexpected fire is itself the signal to widen the route. Nothing in
the code reacts to being shot at today -- only the destination is ever checked,
never the path, and `travelAct->StateWait()` parks the threat-aware traveller
for the whole engagement.

**On long-range units:**

> "Snipers, artillery, those types of units... they should always try to stay at
> maximum range. Theres no need to get any closer as that would only put them in
> greater danger. If they don't have vision/protection they shouldn't move
> forward."

MAXIMUM RANGE IS THE STANDOFF, always -- not a floor to be clamped down from.
The second sentence is the ruling that was being violated: a blind long-range
unit must NOT advance to acquire. `FighterTask.cpp` did the exact opposite,
pulling an unsighted gun IN to its own sight radius (armart 710 -> 328, inside
a 435-range LLT).

**On guards answering contacts alone** -- he declined the question and named a
better one:

> "I wonder if sometimes we're treating the frontline like this, as part of our
> base... Maybe we're sending guards out on the frontline which would be quite
> silly. I'm unsure what to answer here because something seems off."

So the question "should a guard answer alone" is the WRONG question until we
know whether guards are being sent to the front at all. A guard belongs at a
post; if the post set includes front positions, every answer about grouping is
an answer about the wrong units. Investigate before proposing doctrine.

**On shields:** remember an enemy LRPC after the sighting, but let it fade if
nothing has shelled us -- not a permanent latch (which is what enemy AIR gets),
because a plasma cannon can be killed.
