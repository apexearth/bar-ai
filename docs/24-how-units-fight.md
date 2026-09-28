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

- **The commander does not chase light scouts he can never catch.** He builds
  a turret where he stands instead, so that ground is closed to them; with
  turret coverage on whatever he is building, the scout does not matter
  (2026-09-19).

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
- **A bombing raid past the point of no return commits** (2026-09-23). Deep in
  enemy territory, meeting AA is not a reason to turn: circling and dodging
  there dies for nothing, while pressing on to the economy does damage. Once
  the way home costs as much as the way in, go for the target.
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
- 2026-09-16, watching Cortex lose ground on Supreme Isthmus 8v8: when the
  enemy is encroaching and winning, the thing to build is the Behemoth
  (`corjugg`) -- it is extremely defensive. He asked whether we hold any
  store of what units are good FOR, so that "Behemoth" answers "defence".

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

**On attacking with more than one group** -- asked whether the army should merge
into one squad before it may attack, judge each target locally, or always keep a
share out, he rejected the framing:

> "We shouldn't need to be one big squad in order to attack, we should be able
> to coordinate and coordinate attacks with multiple groups."

So the promote test is wrong in its UNIT, not its spirit. Today a DEFEND pool
may leave only when it alone matches `PreMaxGroupThreat` -- the enemy's
second-largest group -- and the army is scattered across many pools (measured
2026-09-06, 8v8: 42% of pools held one or two units, pools sat at 0.32 of their
bar, 3% ever reached it, and 218 of 240 census samples had NO attack task in
existence at all). Groups stay separate; the ODDS are judged on what commits
together, not on each pool alone.

The same measurement shows the bar moves the wrong way: it is set by enemy
strength, so the more we are losing the higher it climbs and the more passive we
become -- which is the "we never do anything back" he keeps reporting.

**On conflicting orders** -- watching a sniper walk to its death again:

> "I think we have some very core bugs in our unit control that you are
> completely unaware of. I often see units have move orders over great
> distances... I wonder a lot if we have units receiving move/fight/attack/
> settarget tasks from a wide variety of logic centers causing our units to be
> given conflicting orders constantly."

He is right, and the existing `apex: order-src` census proves it: 16 call sites
issue movement, ~4,400 orders a minute over ~276 units, and in one minute the
standoff ring alone re-sent 367 of its 662 orders inside 3 seconds with 260 of
them moving the goal more than 128 elmos. Escort re-sent 73 of 74. Every one of
regroup's 24 repeats was a long jump.

The consequence is that fixing the CONTENT of a decision can be inert: the
standoff clamp in `FighterTask.cpp` was corrected 2026-09-05 and snipers still
close, because a unit re-ordered every three seconds never reaches any standoff
position. **Check order survival before crediting a movement fix.**
`apex_order_trace=1` + `tools/orders.py` is the instrument.

> "The sniper died because he received a long range move order telling him to go
> to around the map midpoint. There were NO friendlies there - only enemies."

Map-midpoint destinations have two known sources worth ruling out first:
`IFighterTask::RoamPos` falls back to a uniform random point over the whole map
(mean = map centre) whenever `HasFrontPos()` is false, and `GetEnemyPos()` is
the MEAN of the enemy cluster centroids -- with enemies on two flanks that
average is a spot where neither of them is.

**The order-priority table** (`CCircuitUnit::OrdSrcPrio`) implements his ruling
"retreat > dodge > standoff > guard", asked for when sixteen call sites were
found issuing movement to the same units. The unlisted sources follow the same
principle -- a survival reflex outranks holding a firing position, which
outranks committing to a fight, which outranks formation-keeping, which
outranks being stationed somewhere -- and STANDOFF/RING outrank ATTACK/ENGAGE
because of his max-range rule above: if attack outranked standoff, the attack
logic could still pull a sniper in.

TRAVEL and FWALK are unranked on purpose. They are the unit-action layer
carrying out whatever was decided, so blocking them would freeze the very
retreat they are executing. SETTGT moves nothing.

**What the arbiter does NOT fix, measured 2026-09-06.** It refused 5,273 orders
in a 20-minute 1v1 (attack 2509, post 945, script 877, ring 802), so the
cross-centre conflict is real. But the thing he actually watched --

> "our army being given orders to defend one chokepoint, then another
> completely different chokepoint... they stand in neither of the desired
> places because they are constantly asked to go to completely different
> areas. Therefore we're never properly grouped up."

-- is NOT cross-centre. Instrumenting the GOAL (`ITravelAction::SetPath`, the
one place a destination is replaced) rather than the waypoints:

| owning task | long moves (>=1000 elmos) | of those, RETURNS to a place already used |
|---|---|---|
| RAID | 311 | 228 (73%) |
| ATTACK | 147 | 103 (70%) |
| DEFEND | 123 | 47 (38%) |
| AA | 49 | 19 (39%) |

Same source at both ends: **one task changing its own mind**, which no priority
ranking can arbitrate. Whole squads swing together (three armpw with an
identical 94 moves / 73 returns / 21 places).

The defence anchor is INNOCENT and the obvious fix was already there:
`guardsum` measured 337 re-picks with **0** changes of spot, and both offenders
already carry a commitment term -- `RAID_TARGET_STICKY` and `TARGET_STICKY`,
both 1.4, both added after his earlier "it can't make up its mind and just runs
in circles". So the answer is not "add commitment"; commitment exists in
exactly the two tasks that flap, and at 1.4 it is measurably not enough. Why it
fails is the open question -- the discount applies only while `enemy ==
GetTarget()`, so a target lost from LOS clears the incumbent's advantage and
the comparison restarts cold.

## Escorts have to WIN the fight, not just reach it (2026-09-07)

> "We are using rascals as escorts and they really suck at it. Need incisors if
> you want a good enough vehicle escort."

Rascal is `corfav`: 26 metal, and BAR's own description is **Light Scout
Vehicle**. Incisor is `corgator`: 120 metal, **Light Tank**.

`Market::EscortWorthy` admits a def on one of two axes -- FAST (above the
ground field's mean speed) or TOUGH (the `RIOT` role tag) -- with a cost cap
(`TUNE_ESCORT_MAX_COST` 120) and a SKIRM/ARTY exclusion. A scout car clears the
speed bar trivially, so it qualifies, catches the raider coming for the
constructor, and then loses to it. **Nothing in the filter asks whether the
escort can kill what it caught.**

This is the same shape as the Rocketeer error the SKIRM/ARTY exclusion was
added for, one axis over. The missing axis is combat power, and the bar should
come from the field's own mean the way the speed bar already does -- not from a
unit name. `apex: escort-field` / `escort-cand` print the whole candidate field
with cost, speed, power and the pass flag, so the bar is read off real data
before it is enforced.

## Raiding is not optional, and defending only is losing slowly (2026-09-07)

> "I didn't see us raid a single time. Everyone is too busy escorting or
> guarding structures."

> "We want the enemy chasing us all over the map on THEIR side of the map. If
> we're only defending then we're accepting all the damage."

Two statements of one doctrine. A unit standing on our ground trades at best
evenly; a unit on their ground makes them spend to answer it, and everything
they spend answering is not spent on us. **Pressure on their half is a form of
defence**, and the cheapest one -- so an army that is entirely committed to
escort and guard duty has not chosen safety, it has chosen to absorb every
attack at full price.

Escort and guard demand is our-anchored and never satisfied (a worker is
exposed whenever it is outside the safe radius), so left alone it can consume
the whole army. Whatever else changes, some share of the army must be on their
side of the map, and that share is not the leftovers after every guard slot is
filled.

## When they are closing on the base, defence is not a purchase (2026-09-07)

> "When enemies are getting closer and closer to our base and we're at T2 we
> really really need to try and making T2 or T3 defense to stop the enemies.
> It becomes a life/death situation."

Two things in one sentence. **Closing** is the trigger, not arrival: the tower
has to be standing when they get here, so the decision is made off a force that
is still walking. And at T2 the answer is a T2 or T3 gun, not more of the cheap
one -- a wall of light towers against a heavy push is metal spent on nothing.

The field could not hear the first half. `HazardWith`'s loss term reads what
has **already** been destroyed here, and its presence term is scaled by the
gradient toward their **base**, which is zero at ours by construction -- so our
own ground reported the floor hazard while it was being taken apart (Frozen
Ford, `20260907-175233`, minutes 21-26: four mexes down to one, 1,148 / 2,251 /
2,337 metal of losses per sample, `home[hazard=1.25/ks]` on every line, which
is exactly `apex_risk_floor`). Defence finished that game at 1.7% of spend
against BARb's 15.9%.

## They arrive as one blob; we arrive in pieces (2026-09-07)

> "The enemy tends to come at us with one big blob of army all together at the
> same time. Our army tends to be very spread out so we die to them piece by
> piece. That is at least part of why we lost that game."

This is not the same rule as "curves and lines, never a ball" above. That one
is about the SHAPE a formation holds when it arrives. This one is about how
much of the army arrives at all. A wall is still a wall when it is the whole
army; what loses is committing a third of it at a time.

Measured in the game he watched (Altair Crossing, `20260907-183449`), from the
`apex: squadsize` line, late game:

| | | | | | | |
|---|---|---|---|---|---|---|
| their largest group | 19 | 22 | 25 | 27 | 30 | 32 |
| our largest squad | 10 | 12 | 14 | 13 | 7 | 6 |
| our squad count | 5 | 4 | 4 | 2 | 2 | 1 |

Their mean group ran ~9-10 units against our ~4-6, and their peak group was
32 against our peak of 15. Half of every pool pass that game (95 of 178) was a
squad of one or two units.

### What beats a blob (2026-09-07)

> "How to beat a big 32 unit blob = beamers and HLT + jammer and make the enemy
> bleed into us. Support those turrets with con turrets. Easy for me to say,
> hard for us to make our AI good enough to do that lol"

So the answer to a massed push is not only a massed answer. It is ground that
costs them to cross: beam towers and HLTs to do the damage, a jammer so the
blob cannot see what it is walking into, and **construction turrets behind the
line** so the guns are repaired and rebuilt while they are being shot at. A
turret without a nano behind it is a one-use item.

This does not contradict "fight without turrets" at the top of this file --
that is the condition he gauges FIGHTING under, so nothing hides a bad army. It
is the same instruction as the life/death T2 defence entry below it, with the
composition named.

## Splash is worth what it hits (2026-09-08)

> "If we have tons of enemy T1 coming at us we need big AOE damage to clear
> them out. Perhaps we lack that logic?"

We do. `TUNE_WORTH_AOE = 0` (`tunables.as:912`), and `UnitCore` guards the term
with `if (wAoe != 0.f)`, so the splash factor never executes. It is
unmeasured-and-off, not measured-and-rejected: `docs/27` has no entry for it.
`RANGE` is the other one at zero; `DPS`, `HP`, `ALPHA` and `COST` are all live.

But a fixed weight is not the rule he stated. **The value of splash is the
number of targets standing inside it**, so it is a function of what the enemy
is bringing, not a constant. Against six spread raiders a Fatboy's splash is
worth one hit; against thirty massed T1 it is worth several per shot. We
already measure their clustering — `CEnemyManager::GetEnemyGroups()` carries
members and positions, and the `apex: squadsize` census records the enemy's
mean and max group size every pass (it read `enemy n=9 avg=9.9 max=32` in the
game he watched). So this is derivable from what we already collect, with no
invented constant.

Note the coupling: the big-AOE answer to massed T1 **is** the expensive T2
assault unit, and the production auction cannot buy one — see the cost-squared
error below. Turning AOE on without fixing that would change nothing.

## The back rank leaves the front rank to die (2026-09-08)

> "we often will have like 4 or 5 units up close to the enemy getting pummelled
> while our units in the back move away OUT OF RANGE TO FIRE AT ENEMIES. So our
> front guys take all the punishment and we aren't even dishing out any damage
> at the enemies with the rest of our army. Imagine you are with your allies,
> and you are attacking and getting hit... you think your allies are still there
> behind you but they all turned around and left."

The named mechanism is `IFighterTask::KeepRange` (`FighterTask.cpp:469`), called
from `OnUnitDamaged` (`:303`) **before any health check** -- stock issues no
movement at all for a healthy damaged unit. It fires on every damage event,
throttled to once a second by `apex_dodge_cd`, and issues a raw `CmdMoveTo` to
95% of the unit's own max range measured from **whichever single enemy last hit
it**, plus a sideways offset proportional to speed (the orbit that reads as
going in circles).

Two things are wrong with that shape. It positions against ONE attacker with no
reference to where our own front rank is standing, so a long-range unit walks
back to its own maximum while the short-range units it was supposed to be
shooting over are left in contact. And it is a movement order, not a fight
order, so the unit spends the second walking rather than shooting -- which is
his "we aren't even dishing out any damage".

The rule he is stating: **a unit with range advantage holds at range and FIRES.
It does not leave the line.** Standoff is a firing position, not a withdrawal.

## Jammers are wanted every sample and never built (2026-09-08)

> "Btw still no jammers, and we used to make jammer T2 units but wow im not
> seeing those anymore either."

Not a missing want. The instrument says the demand is live and constant --
`apex: support-diag def=armaser cls=jam need=1.00 squads=1 have=0.00 own=0
pend=0 adv=9852`, on every sample of `20260907-210124` -- and we finish the game
owning zero. `armpeep` (radar) is identical: need 1.00, built 0.

`armaser` never appears in the production rank line at all, so it is not losing
the army draw; the support branch (`production.as:570`) builds its own Want and
`continue`s, and that Want loses wherever it competes. Note also that `need` is
capped by `EscortSquadCount()`, which read **1** against an advanced army of
9,852 metal -- so even fully served we would buy one.

## Gunships read the enemy's AA (2026-09-08)

> "Gunships can fight units but if enemy has lots of AA then our gunships
> should try acting more like bombers - targetting enemy economy"

Asked whether Hornet (`armblade`, Rapid Assault Gunship) and Archaic Dragon
(`corcrw`, Flying Fortress) should bomb or fight, he gave neither answer: the
role is **a function of the enemy's anti-air**, not a tag.

Both static answers currently in the tree are therefore wrong. Ours routes them
to `BOMB` unconditionally (`hooks.as:134`, `Air::IsBomberDef`) on the argument
that "a released bomber bombs whatever its config role says" -- so they bomb
even against an empty sky where they could be killing army. Stock has no BOMB
entry for role `heavy` and drops them into the GROUND massing pool, so they
trade with tanks even when the sky is full of flak.

The rule is a gradient, not a branch: as enemy AA rises, a gunship's expected
value against units falls (it dies on approach) while its value against
undefended economy holds. The AA census already exists -- `airthreat.as` reads
enemy air and AA, and `apexaa:` logs `airRaw/seen/heavy` -- so this is
derivable from what we measure, with no threshold to invent.

Note for the revert: neither the apex line nor the stock default implements
this, so this is a REBUILD, not a KEEP. It is the only air item that is.

## 2026-09-11 — bombers mass, then strike the economy; they do not wait forever

On the wing that sat "not armed" for 25 minutes while its released planes died
one at a time (91 built, 91 dead, no strike flown): *"fix that, we need to
build up bombers, and then eventually attack enemy eco in a large mass. You
can't sit around forever doing nothing."*

So: the wing is held and grown until it can strike; the strike is the enemy
ECONOMY, in one mass; and "until" has an end -- a wing that cannot strike is
not kept indefinitely. The agent's 2026-09-11 change that stops buying bombers
for a wing that will not be kept stands; this is the other half.

### 2026-09-12 — scouts, so the wing knows what to hit; a bomb counts after its plane dies

Told that in 15 of 16 games the strike never flew because the wing is priced
on enemy structures we have SEEN and the census read zero for 10-17 minutes
after the air plant landed: *"Yes we absolutely need scouts so we know what to
hit."* So intel is bought for the wing -- the look at the enemy economy is
part of the strike's price, not something that happens to arrive.

And on the strike ledger that credited only bombs whose plane outlived them
(a run that killed ~11k read 1/7 of it and stopped the buying): *"Should still
value bombs that hit after the plane dies."* Built the same day: static deaths
inside the run's cell count for the run whatever the attacker credit says
(0e0a8b13, S30).

## 2026-09-11 — "all build power onto one fusion" was an eco-role statement

On fusions drawing a mean crew of 14 and a peak of 49 at 1,300 metal/s: *"You're
putting all our build power into that? In an eco role sure, but that's not
what we're doing here. You're taking that statement too far and out of proper
context."* The whole-pool crew on big energy (`Requests::SiteWorkerCap`,
"BIG ENERGY TAKES THE WHOLE HAND POOL") is the eco role's rule, not the
standard game's.

## 2026-09-11 — factory support: at least BARb's floor

On constructors spending 0.8% of their time on a factory against BARb's
13-22%: *"OK"* to adopting BARb's guarantee as a floor -- nanos in reach per
factory by tier (T1 2, T2 4, T3 9, stock `FactoryManager.cpp:895-916`), and an
idle builder within 600 elmos guards a recruiting factory while the bank is
above 20% of storage (`EconomyManager.cpp:1697-1723`) -- priced above the floor
as now.

## 2026-09-12 — the line is chosen for the map: vehicles where vehicles are stronger

*"Since we're back on the basic fight logic, I kinda feel like if we lose, it
is because we are not making the most optimal army composition. I still notice
and feel very often that we just make bots almost all the time. So in maps
where vehicles are obviously more powerful, we don't do quite as well."*

Measured the same day across 40 logged games: our first plant is a bot lab in
most of them and our T2 step is the T2 bot lab almost always (one 8-player
game: 8 bot labs, 8 T2 bot labs); BARb splits bots and vehicles at both tiers.
Until then the production half of a plant's price carried no fact about the
units it makes -- only terrain coverage and tier -- so on Comet Catcher Remake
the bot and vehicle labs priced within 5% and bots won on coverage 95 vs 88.

## 2026-09-12 — the held army leaves: cover pools promote, and cover is sized by their raiders

Shown that the C++ fight tasks are stock since 09-07 but the election feeding
them is ours -- in a 40-minute Isthmus 1v1, 427 units elected to `cover` and
61 to `mass.hold` (both a Defend pool that never converts), 231 to `escort`,
60 to stock, 20 to `mass.attack`; a 307k army at its 323k target against
13-27k of theirs, holding an uncontested line to the time limit -- and offered
two changes: cover and hold pools get stock's exit to ATTACK once full, and the
cover need is sized by the raider metal they have fielded rather than by our
building count. *"Ok try doing both of those."* Earlier, on whether the army
target should scale higher late: it was met, so not size -- use.

## 2026-09-13 — escorts are not a late-game posture; the cheap units go forward

Watching Carrot Mountains 8v8, on one player's base full of Pawns and Rovers
beside its workers: *"We have so many escorts in the base it is ludicrous. At
this point in the game I'm not so sure we need these escorts anymore. Barb
stable seems to have no more escorts late game... All these escorts should
instead be the fodder/spam guys distracting our enemies."* Stock caps escorts
at three for the whole game (`"escort": [3, 1, 540]`).

On routing cheap raiders to spam: *"if raider-spam works correctly then yes I'm
ok with having it on."* The condition is the doing: the units must be seen
going forward and dying on their side, not standing at home under a new name.

On the idle lines the same base kept buying: *"Why have 3 gantries if we aren't
even using them?... This guy has almost 1000 metal income and all his gantries
are idle and he's full on metal... It is hard to win when you don't make
units."* An idle production line is never a reason to buy another; metal the
economy cannot spend is army, not a shortage of hands.

On the builders: *"I think our whole weights system is brutal at times and we
completely stop caring about building certain things... I thought that our
builder role system was supposed to solve that."* Shown that the roles copied
the draw's own shares (defence 1% of spend, 99% of its target unmet): *"Having
builder roles come from target gaps sounds like a smart idea to me. We
certainly have more than enough builders."*

## 2026-09-13 (later) — where escorts belong, and the outer mexes

*"The times when we're likely to need escort is when we're going out to make
more mexes or are making defences and things outside our base area... Right now
I see our cons losing their escorts really early on and as a result we lose a
lot of constructors. Even air cons should get a little fighter escort :-P"*

*"Also none of our mexes outside our base have any turrets guarding them. it
costs us to push enemy mexes, it costs them nothing."*

On what to read a trade by: *"stop looking at k/d and look at damage
efficiency more"* -- BAR's D%, damage dealt over damage received.


## 2026-09-13 (morning) — the silo before the gun; the map edge is where they come

*"I notice we often make like 1 basilica per team early on. Why is that? I
would rather it be a nuke silo."* The Basilica came first because the super
lane's gain was affordability alone, which rewards the cheaper class.

*"The edges of map are often the most vulnerable and undefended areas. Let's
make sure if we are on the edge of the map we make extra defense there."*

## 2026-09-13 (morning) — rezbots down a little; support the gantry, don't multiply it

*"Let's turn the rezbots down a little and I'll watch it in future games."*

Watching an 8v8: *"I'm looking at the enemy team's 1 gantry -- it is supported
by 170 nano turrets. Our base opposing it has 6 gantries and if you added all
of the nanos that can support them combined we do not have as many as 170.
This is a lesson in efficiency. I like redundancy, and know that if they hit
my gantry I won't lose all of the build power at once. However, we're just
very inefficient with how we support these gantries. We've taken up a shit-ton
of room and support the gantry very little. In an 8v8 imagine we're more
likely to lose because we run out of room, make our T3 in parallel, thus get
the T3 later/slower, lose ground on the battlefield, and that compounds down
the road. We have room on the side of our gantries to make ~3 more nanos but
we keep distance on the side -- we don't need to keep distance on the side. A
much better use of our resource in late game is to make more nuke launchers or
LRPC, and have fewer Gantries -- but to better support the gantries we have
with nanos."*

## 2026-09-13 (midday) — adjacent nanos, fewer plants, bombing raids, three anti-nukes

*"We aren't building nanos completely adjacent to air labs. We should be. Same
with the sides of our gantry, seem to be keeping distance still. And I see
gantries with obvious room for dozens more nanos but we still made more
gantries. Same with advanced air labs -- we have 10 advanced air labs but
really we should just have ~4 with heavy nano turret support. I want to see us
making bombers and doing bombing raids on our enemies but I'm really not seeing
this very much. Our bombing logic is boring. We need to be more exciting -- so
more late-game LRPC and nukes, less perpetual making of factories we hardly
support."*

*"Also in late game we may want our anti nuke coverage to go from just 1 AN to
~3 AN."*

Measured in the game he was watching: the air lead had 11 advanced air plants,
159 fighters and **0 bombers against a wing target of 102** -- the wing was
priced on the 36k of enemy structures in sight against a mirrored base of
690k, so every bomber lost the draw to fighters and air cons.

## 2026-09-13 (midday) — defence blobs, and the raided flank with nothing

His screenshot (`~/Downloads/bar-defence-concentrations.PNG`): *"We concentrate
our defenses into blobs like you see here in the center. The side of the map
where green keeps getting attacked is completely undefended, yet we've made 3
pulsars all in the same area. This is a very bad defence flaw which we really
need to address."*

## 2026-09-13 (evening) — the eight-player eco seat

*"Can we try adding in something where 1 player does an eco role where they
only activate their military once they've hit ~1000 metal income? They spend
the entire early game only making economy... and if bonus is +100% then its
2000 metal income. So this would be only on an 8v8 map, 1 AI makes almost no
defense and makes no military, focusing on economy. It should be the player
furthest away from the enemies."* Shown the existing rear specialist at 500
and what became of it in his game: *"Yes let's do it."*

Watching the first game of it: *"I see who is doing eco and the issue I'm seeing
is they spend huge on defenses. Almost 10k on defenses spent by minute 13, we
would eco so much faster if we didn't do that."* The seat's defence target is
zero while it grows.

Same game: *"they made 15k worth of energy buildings but aren't making
converters. Lastly we don't seem to be transitioning early enough to making
AFUS buildings. We keep building fusion for too long. Look at the last fix for
fusion -> afus, it went too strong."* And: *"two players on our team made 59
advanced solars -- both legion -- I'm unsure if legion players have an issue
making fusion/afus."* Measured in that game: no team of eight built an
advanced fusion in 34 minutes (fusions 5-16 each, one at 733 income).

*"We need to make sure we do not make a gantry until we intend to make
military. (nothing non military comes out of there)"* -- the seat's gantry
waits for its activation.

Watching the seat on Supreme Isthmus: *"we have like 100 advanced bot cons, way
too many. we should be using air cons, should do something to not run into a
situation where we have such an excess number of ground cons. I think if we are
too often idle or spending most of our time walking around maybe we start to
prefer air?... Also still mostly just building fusions, not afuses."* Measured:
the seat's hands line read `tBuild=1578 tFeed=242` at 15.9k build power and
1,142 income -- the order start latency counted as lathe time -- and bought 147
advanced bot constructors against 28 air.

*"Do rezbots reclaim old buildings? We need to increase the speed at which we
reclaim old stuff."* They did not: the rez chain had no retirement rule while
the market discounted every constructor's retirement bid the moment a rez bot
existed. *"Our base ends up cluttered with buildings which aren't worth the
space they take up. Old energy, old converters, old defenses. We need to clean
up a lot faster."* And: *"land reclaim seems to feed into resurrection sub want
and it shouldn't. We often make tons of rez boats but no real navy."*

*"We keep making the same obsolete buildings we've reclaimed. Need to fix
that... if it is obsolete we shouldn't be making it, need some buffer in there
so we aren't flipflopping."* *"I saw converters doing this."* Measured on the
rd3blob8 set: one game rebuilt the basic converter twelve times after
reclaiming it.

## 2026-09-20 — the commander defends the base against T1; the base arms when the army is away

Watching a 4v4 on Comet Catcher Remake, T1 artillery shelling one of our bases
with the commander standing by: *"Sometimes the only thing that'll save a base
is the commander delegating the enemies and protecting his base. Yeah, there's
a good chance he'll die, but if he doesn't [go], he will have lost his entire
base. So he really should defend it, sometimes, at least in the early game. If
it's just T1 attacking, try to protect your base. We've got a bunch of
artillery pounding our base. All the commander had to do was walk up to them
and D-gun them."*

- **T1 attacking the base is the commander's to kill.** The tier of what is
  attacking is his test -- not the enemy's whole field, not a strength sum,
  not his own health. The risk of his death is accepted: losing the base is
  the worse outcome.
- Measured in that game: caution flipped at 3.4 minutes for every one of our
  four commanders (four enemies' mobile mass against one commander's cost),
  which held the fight rule at zero engagements for the whole game.

Same session: *"One thing I'm often seeing is our entire army wants to go to
one side of the map. When this happens, our base should make extra defenses
if most of the army is far from home."*

- **When most of the army is far from home, the base buys extra defence.**
  The army at home is cover; the army away is not, and the defence price must
  read that. His answer when asked which way (2026-09-20): the army at home
  counts as cover, both directions. Built the same day in guardposts.as
  (`ArmyCoverSample`, `apex: army-cover`); measured near inert in a 1v1 --
  each unit covers only its 8-second answer reach (~360 elmo, one building's
  life against one raider), so a 1,500-metal army at the farm read 0-31
  metal of cover at the rim sites priced. The reach a massed army answers
  within is the open question.

## 2026-09-20 — an atomic bomber built early is used, alone: scouts find the AA gap, it flies round it

Watching Frozen Ford, a Liche bought at 18 minutes and held at home with three
Phoenixes: *"If we're pretty early into the game and we make a nuclear bomber,
we should find a way to use that thing. Still early on, the enemy likely
doesn't have very strong anti-air yet. So get some scouts out there, find
where the anti-air is not, and then send that nuclear bomber in and attack the
enemy's base. We're basically holding our bombers back until we get a good
mass... right now, one nuclear bomber could go around the outside of the map
and bomb all their converters that do have one flak in their base. It's worth
trying."*

- **An atomic bomber is a strike by itself.** Its bomb takes what it flies
  over; there is no mass it waits for. It goes when the scouted picture shows
  a cell whose economy pays for the plane's risk, and it stays with the wing
  only while no such cell exists.
- **Scouts first.** Where the AA is not is the question the run is priced on;
  the look is part of the run, not something that happens to arrive.
- **Around, not through.** The approach goes round the AA -- the outside of
  the map -- to the cell the AA does not cover, not across the base that has
  the flak.
- Measured in that game: the Liche read as ten Phoenixes of wing mass, so the
  wing "reached" its deadline bar with four planes and flew twice into a
  base it had not looked at; the Liche died 36 seconds into the second run,
  killed by something the threat map had never seen.

## 2026-09-20 (evening) — air cons lead safe builds; bombers commit over the cell; Titans are never walked home

Watching an 8v8 on Greenest: every constructor on the team trailed one T2 bot
con 80 s to a gantry site inside the base. *"Advanced constructors should
always have priority on building if they're an air constructor. If the
location is safe, air can definitely get there faster. If it's on the front
line, that's where you want to bring all your ground constructors."*

- **A safe site is started by whoever arrives first, and that is the air
  con.** A front-line site is the ground crew's. Built the same day: a hand
  that can place the def takes its own order on the site instead of guarding
  the lead (`execute.as` WK_ASSIST, `apex: assist-own`); a flyer only where
  the site is not hot and not past the front.

The same game, a 29-Phoenix wave over the enemy base: *"They decided they
were scared of something, so they tried to turn around, but they're already
over the enemy base. They should have just committed and attacked the best
thing that they could have."* Measured: no target scored inside the cell for
three minutes, no bomb dropped, 15 of 29 lost circling.

- **Over the cell the wave is committed.** The AA veto shapes the approach;
  inside the cell nothing is refused on threat -- the AA is paid on the way
  out whether the bomb drops or not. Built in `BombTask.cpp` (`apex: bomb
  no-target` counts what was refused and why).
- **While bombers are being held for a strike, the plant makes bombers
  without pause.** *"We're making one and then waiting five, ten or more
  seconds before we try to make another one."* Measured: one order per
  election because a single order costs 8-28 ms against a 4 ms slice; the
  line now re-enters after one second instead of a ten-second window
  (`facqueue.as`, `apex: facqueue short`).

Titans: *"We retreat our titans back to our main base sometimes. And that's
a really, really long walk. ... We've got like 13 there. We could walk those
through the ocean, come up the side of the enemy's base and win the game.
None of the BARb stable AI seems to do this -- they're using all their titans
for offense."*

- **A Titan is never walked home.** Measured in that game: 17 of 17 Titans
  that turned at 30% died on the walk, none reached repair. Chargers now
  carry retreat 0 (`posture.as ApplyRetreatPosture`).
- **A Titan is not parked at home because shells are landing.** The
  charger's home hold was the raw under-attack test with no cap; it is now
  the pool's own need-capped hold, registered so the release reaches it
  (`hooks.as`, `apex: armbanth holds home heldM= needM=`).
- Open, his to rule: solo beeline (his 2026-08-19 ruling, the code today) or
  the thirteen going together as BARb's do.

*"Is our fight logic identical to our opponents'? ... I feel like we are
more cautious and careful and because of that less likely to capture ground
and attack enemies and more likely to move out of the way of our enemies."*
Audited the same evening (agent report in the commit message): the C++ squad
core is stock; `quota/thr_mod` attack [1.0,1.0] and defence [1.0,1.0] against
stock hard's [0.6,0.8] and [0.3,0.5] is the one knob stock turns to be
aggressive, ours was set to offset a margin function the 09-07 revert deleted;
`withdraw.as` orders a unit off enemy-influenced ground with no gun on it;
the MELEE hold pool never marches while the base reads "under attack".

## 2026-09-20 (late) — rez bots work under artillery; the Dragons' flap

Watching Comet Catcher 1v1 (`matches/_engine-39028`): *"Our rezbot logic
seems to break in the late game. They just keep seeming to get their orders
interrupted by patrol orders."* Read from the log: an enemy Basilisk (range
4,950) put every rez bot on the map inside "enemy reach"; the rez guard
dropped ~2,900 jobs a minute across 120+ bots and the election sent each one
home on a 20-second patrol.

*"If it's LRPC from enemies that's hitting us, we can't just spend the entire
game running away and huddling in our base. We have to go out and do our
job. Yeah, some of us are gonna die, but that's okay."*

- **Long-range artillery is not a reason for a rez bot to stay home.** A
  shell still in the air past the react window is one the bot walks out from
  under: its reach against a mover is what it flies in that window
  (`CircuitAI.cpp ReachIn`, `apex: reach-mover` per def). Basilisk 4,950 →
  1,150; Tremor 1,470 → 420; Goliath 650 → 310; lasers unchanged.
- **Rez bots dying at their job is accepted.** The flee-on-hit rule stays.

Dragons (`corcrwh`): *"They wanted to go out and attack multiple times, but
then they kept going back to the base."* Traced: a Dragon nanoframe counted
as 16 held bombers, and the "home is bigger" recall fired against the wave's
plane COUNT every second for ten minutes (`air/update.as:235`). Open, his to
rule: does a gunship finishing mid-strike join the wave out, and is a strike
ever recalled because home outgrew it?

Rolling bombs (2026-09-22): *"Make sure that rolling bombs don't group up into
squads and make sure they just head straight for enemies. They should try to
avoid being near allies so when they blow up they don't hurt allies."*

- **A rolling bomb never joins a squad.** It is one delivery of one explosion,
  not a line unit: massing it waits for a group it does not need, and a group
  of them dies to one blast.
- **It goes straight at an enemy.** No forming up, no waiting for a ratio.
- **It keeps away from our own units on the way in.** Its own death is the
  weapon, so standing among allies is how the weapon lands on us.
- Armada `armvader` (Tumbleweed) is the one in his 2v2 regime; `corroach`
  (Bedbug) and `corsktl` (Skuttle) are the Cortex pair. All three were roled
  `raider` + `melee`, which is what put them in raid packs.

Scavenger units (2026-09-22): *"When scavenger units are on we make a ton of
drone carriers, and Epic Tumbleweed units. Unfortunately these units are not
that good but our algorithm thinks they're pretty good. So when the enemy
comes at us with titans and thor tanks we really can't stop them."*

- **Drone carriers and Epic Tumbleweeds are not worth their stats.** Against
  Titans and Thors they do not hold, whatever RANGE/DAMAGE/HP says.
- The units: `armvadert4` (Epic Tumbleweed, the T4 rolling bomb),
  `armdronecarry`, `armdronecarryland`, `cordronecarry`, `cordronecarryair`.

A nano concentration should become a fortress (2026-09-22): *"I see in the
game we will make one pulsar, just one. Not even enough, honestly. And then
we'll make a ton of nanoturrets all around it. So my thought immediately is
like, oh great, we have a lot of nanoturrets there. We could make a nice
little fortress right there. We could even put a shield there. Man, it would
be freaking awesome. But all we do is make one pulsar, and that's it. It
sucks."*

- **One gun is not a defence.** Where a gun stands, more guns belong.
- **Where the nano turrets are massed, that ground is worth fortifying** --
  the lathe to build it is already standing there, which is the cheapest
  fortress on the map.
- **A shield belongs on that ground too.**
- Read with his 2026-09-17 mex-guard ruling: this is the same complaint one
  step up -- we buy the first gun and never the second.

## Rolling bombs (2026-09-23)

*"Right now we have amphibious rolling bombs trying to run away when they are
almost dead, but the point of them is to like die and blow up into the enemy,
so we shouldn't have them run away. The one I'm talking about happened to be a
rolling nuclear bomb, so we really don't want that exploding in our base."*

*"We also shouldn't let these rolling bombs merge into a squad together.
They'll just all blow up together in one place. We need to spread them out and
have them attack the enemy from different angles."*

- **A bomb never retreats.** Its weapon IS its death, so pulling it out at low
  hp wastes it -- and a nuclear one retreating detonates in our own base.
- **Bombs do not group.** Several arriving together spend one blast on the
  ground one of them could have covered alone.
- **They arrive separately, from different bearings.** Spread is the delivery,
  not a formation preference.

## 2026-09-24 — how careful the commander is depends on the game mode

- **Respawning commanders** (modoption `comrespawn`): the commander has an
  Effigy; when he dies the Effigy is sacrificed and he returns. While one
  stands he does not have to be careful with his life -- the Effigy is what
  has to stay alive.
- **Evolving commanders** (modoption `evocom`): he grows very strong, and at
  level 10 is "a crazy powerful dude"; he does not have to be quite so
  careful, but still has to be careful -- killing the commander is often the
  game.
- **Default**: in T2 play the commander must be careful. A single T2 tank can
  kill him: it outranges him and moves faster than him.

## 2026-09-24 — air transports: raid, flank, and a hidden base

- **Transports carry army to raid or to flank.** Those are the two uses that
  matter: drop units where the enemy will not expect them.
- **Towers can be flown forward.** Light towers (a beamer) are built in the
  safety of the base and carried up toward the front line.
- **A constructor can be sneaked behind enemy lines to make a base there.**
- **After a drop the transport goes back to the base.** Staying to hover over
  what it dropped at the front line is dangerous: "Don't do that. Go back to
  the base." A transport never keeps holding its cargo either.
- **Build only as many transports as are needed**; a fleet that sits unused is
  waste.

## 2026-09-27 — no T1 army once T2 stands; every player gets a gantry

- **Tiny units are the lag.** Once a player's T2 plant stands, its T1 labs
  make no ground army at all, fodder included (`Outgrown`, `worth.as`). Ground
  AA and air are left to their own rules.
- **A gantry by 38 minutes is not optional.** Watched on Colorado 8v8: two of
  eight had one. Poorer players now bid for it at a reduced gain instead of
  never, and a gantry that finds no room marks the ground so the next try goes
  elsewhere or clears old T1 economy out of the way.

## 2026-09-27 — the eco seat is the middle back, never a corner

- **Enemies attack from the sides.** Humans flank; the corner and the ends of
  the line are the exposed seats, however far they stand from the enemy.
- **The eco player is the middle back player**: allies in front of it and on
  both sides. "Furthest from the enemies" (09-13) meant safest, and straight
  distance picks the corner.
- Built: the seat is the home with the most of the team's own ground between it
  and any enemy-facing or flank edge of the homes' hull (`EcoShelter`,
  `army.as`); `apex: rear-elect` prints every home's shelter.

## 2026-09-27 — water maps: reach the enemy, hold the water, go air

Watched on Coast To Coast 4v4 (60% water, two coasts, no land path).

- **A unit that cannot reach the enemy is worth nothing.** Behemoths and
  Incisors massed on our own coast. Shore defence is towers ("generally more
  powerful than units"), plus whatever amphibious tanks we already have.
  Built: `ReachDead` (want_plant.as).
- **No naval presence is a great way to lose.** Build navy early; whoever
  holds the water first holds it more easily.
- **Amphibious tanks have no underwater weapons.** They are only good on land,
  so they must cross to the enemy's shore to be useful. Walking them into a
  formation of enemy water units throws them away.
- **Air is a viable path for a team on a map like this**: it hits both water
  and land.
- **On a map like this everyone goes water**, and the team takes complete
  control of it; then the enemy very likely loses. Not water-only: they keep a
  land presence, but the water must be theirs. Why: land left, land right,
  only water in the middle. Whoever holds the water holds the middle plus
  their own coast, 2/3 to 3/4 of the map.
- **Take the water hard and fast, early, with enough boats.** Once they have
  complete control, a shipyard cannot be built at all.
- **All four players make a shipyard** and each makes some fighting ships, to
  attack the enemy or at least defend against them. Commanders walk the shore
  and make the mexes there. The economy goes on LAND: it is safer, and on this
  map we have that option. (Answering "one water seat like BARb, or all?")
- **Torpedo launchers and defences IN the water** (09-28): we never build any.
  Having trouble getting a water presence? Shoreline builders put torpedo
  launchers out on the water, then further out, to get out there. His game:
  none of ours made a yard; one enemy opened with a yard and that one player
  held the water for his whole team.
- **Build for where the enemy is.** Against an enemy with a lot of water the
  gantry's hover tank is the pick: it hits land, drops depth charges on subs,
  and subs cannot shoot it. We made Shivas, and a Shiva underwater can do
  nothing.
- **Water lost, no yard possible:** build air power, torpedo bombers,
  shoreline defences, and shields. Most boats fire plasma, which shields stop.
- **The mix: surface boats and submarines, by what each can hit.** A sub hits
  anything that sits in the water but cannot hit a hovercraft. A destroyer
  hits subs; most other boats cannot. The navy has to understand these
  matchups, not just count metal.
- **Land economy is still good to do**, but some maps need the water economy
  too.
